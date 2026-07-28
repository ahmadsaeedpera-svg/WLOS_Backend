/*  43_Intelligence.sql

    The Women's Life Intelligence Core: how she lives, derived rather than asked.

    Not AI. Deterministic throughout - the same timeline produces the same
    state, every time, and the reasoning can be shown to a clinician or an
    operator and reproduced exactly. The AI companion arrives several
    capabilities later and its job will be to phrase what this found, never to
    decide it.

    One registry, not ten engines
    -----------------------------
    The brief names ten: context, state, routine, momentum, balance, energy,
    focus, consistency, wellness, risk. Built as ten engines they would be ten
    code paths, ten schemas and a release for the eleventh.

    They are not ten different things. Each is a named dimension whose value is
    derived from the same timeline by configurable rules. So: a registry of
    dimensions, a table of what each one reads, a table of how signals move it,
    and one snapshot table that gives history, trend and last-update for all of
    them at once. An eleventh dimension is a row.

    Confidence is computed, never asserted
    --------------------------------------
    This is the part that decides whether the whole core is honest.

    An example output of "Energy 68%, Confidence 94%" is meaningless unless the
    94 comes from somewhere. Here it comes from coverage: each dimension
    declares the event types it needs, and confidence is the share of those it
    actually has data for. A woman who logged nothing has zero confidence and
    her state is reported as unknown - not as a neutral-looking score that
    implies the platform understood her day.

    That distinction matters more than any other property in this file. A
    system that reports "balanced" for a woman who recorded nothing has not
    understood her life; it has understood its own defaults, and it will be
    wrong in exactly the direction that makes it feel untrustworthy.

    The health boundary
    -------------------
    Risk here is behavioural - low hydration, an overloaded day, a routine that
    has slipped. Nothing in this schema may express a clinical risk, predict a
    condition or describe a body. The dimension registry carries the same
    IsHealthSensitive discipline the rest of the platform uses, and the tests
    assert no dimension derives from a health-sensitive signal.

    Idempotent. Purely additive.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = 'Intelligence')
    EXEC('CREATE SCHEMA [Intelligence]');
GO

-- ---------------------------------------------------------------------------
-- The dimensions
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Intelligence.StateDimension') IS NULL
CREATE TABLE [Intelligence].[StateDimension] (
    DimensionCode VARCHAR(30)  NOT NULL,
    DisplayName   NVARCHAR(80) NOT NULL,

    /*  'categorical' - one of a set of named values (routine, balance)
        'score'       - 0 to 100 (energy, focus, consistency, wellness)

        The evaluator branches on this and on nothing else, so an eleventh
        dimension needs no new code as long as it measures like one of these. */
    ValueKind     VARCHAR(12)  NOT NULL,

    /*  Where a score starts before anything adjusts it. Data, because "what
        does an ordinary day look like" is a product decision that will change
        and must not require a deploy. Null for categorical dimensions. */
    BaselineScore INT NULL,

    /*  What she is told when there is not enough data. Never a neutral value
        dressed up as an answer. */
    UnknownText   NVARCHAR(200) NOT NULL,

    [Description] NVARCHAR(300) NULL,
    SortOrder     INT NOT NULL,
    IsActive      BIT NOT NULL CONSTRAINT DF_StateDimension_IsActive DEFAULT 1,

    CONSTRAINT PK_StateDimension PRIMARY KEY CLUSTERED (DimensionCode),
    CONSTRAINT CK_StateDimension_ValueKind
        CHECK (ValueKind IN ('categorical', 'score')),
    CONSTRAINT CK_StateDimension_Baseline
        CHECK (BaselineScore IS NULL OR BaselineScore BETWEEN 0 AND 100),
    /*  A score dimension without a baseline has nowhere to start. */
    CONSTRAINT CK_StateDimension_ScoreNeedsBaseline
        CHECK (ValueKind <> 'score' OR BaselineScore IS NOT NULL)
);
GO

-- ---------------------------------------------------------------------------
-- What each dimension needs to know anything
-- ---------------------------------------------------------------------------

/*  Confidence comes from here. A dimension that reads sleep, water and
    activity has full confidence only when all three have data in the window;
    with one of three it reports a third, and the client can decide whether a
    third is worth showing. */
IF OBJECT_ID('Intelligence.StateInput') IS NULL
CREATE TABLE [Intelligence].[StateInput] (
    DimensionCode VARCHAR(30) NOT NULL,
    EventTypeCode VARCHAR(40) NOT NULL,

    /*  How much this input matters to confidence. Two inputs of weight 1 and 3
        mean the second carries three quarters of the certainty. */
    Weight        INT NOT NULL CONSTRAINT DF_StateInput_Weight DEFAULT 1,

    CONSTRAINT PK_StateInput PRIMARY KEY CLUSTERED (DimensionCode, EventTypeCode),
    CONSTRAINT FK_StateInput_Dimension FOREIGN KEY (DimensionCode)
        REFERENCES [Intelligence].[StateDimension](DimensionCode) ON DELETE CASCADE,
    CONSTRAINT FK_StateInput_EventType FOREIGN KEY (EventTypeCode)
        REFERENCES [Timeline].[EventType](EventTypeCode),
    CONSTRAINT CK_StateInput_Weight CHECK (Weight BETWEEN 1 AND 10)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_StateInput_EventType'
                 AND object_id = OBJECT_ID('[Intelligence].[StateInput]'))
    CREATE INDEX [IX_StateInput_EventType]
        ON [Intelligence].[StateInput] (EventTypeCode);
GO

-- ---------------------------------------------------------------------------
-- How signals move a dimension
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Intelligence.StateRule') IS NULL
CREATE TABLE [Intelligence].[StateRule] (
    StateRuleId   UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT DF_StateRule_Id DEFAULT NEWSEQUENTIALID(),
    DimensionCode VARCHAR(30) NOT NULL,

    /*  The observation that moves it. Signals are deterministic and come from
        the knowledge graph, so a state is explainable rather than inferred. */
    SignalCode    VARCHAR(40) NOT NULL,

    /*  For a score dimension: how far this shifts it. For a categorical one:
        used only to rank which value wins when several rules fire. */
    ScoreDelta    INT NOT NULL,

    /*  For a categorical dimension: the value this rule argues for. Null on a
        score dimension. */
    ValueCode     VARCHAR(30) NULL,
    ValueText     NVARCHAR(80) NULL,

    /*  Shown to her. Written from her side of the screen. */
    ReasonText    NVARCHAR(200) NOT NULL,

    IsActive      BIT NOT NULL CONSTRAINT DF_StateRule_IsActive DEFAULT 1,

    CONSTRAINT PK_StateRule PRIMARY KEY CLUSTERED (StateRuleId),
    CONSTRAINT FK_StateRule_Dimension FOREIGN KEY (DimensionCode)
        REFERENCES [Intelligence].[StateDimension](DimensionCode) ON DELETE CASCADE,
    CONSTRAINT FK_StateRule_Signal FOREIGN KEY (SignalCode)
        REFERENCES [Knowledge].[Signal](SignalCode),
    CONSTRAINT CK_StateRule_Delta CHECK (ScoreDelta BETWEEN -100 AND 100),
    CONSTRAINT UQ_StateRule UNIQUE (DimensionCode, SignalCode)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_StateRule_Signal'
                 AND object_id = OBJECT_ID('[Intelligence].[StateRule]'))
    CREATE INDEX [IX_StateRule_Signal] ON [Intelligence].[StateRule] (SignalCode);
GO

-- ---------------------------------------------------------------------------
-- Her state over time
-- ---------------------------------------------------------------------------

/*  One row per woman per dimension per day. Gives history, trend and
    last-update for every dimension without a table each.

    Kept rather than recomputed on demand because trend needs yesterday, and
    because "what did the platform think last Tuesday" must survive a change to
    the rules - otherwise every rule edit silently rewrites the past. */
IF OBJECT_ID('Intelligence.UserStateSnapshot') IS NULL
CREATE TABLE [Intelligence].[UserStateSnapshot] (
    UserId        UNIQUEIDENTIFIER NOT NULL,
    DimensionCode VARCHAR(30) NOT NULL,
    ForLocalDate  DATE NOT NULL,

    /*  'unknown' when confidence is zero. Never a neutral value standing in
        for an answer the platform does not have. */
    ValueCode     VARCHAR(30) NOT NULL,
    ValueText     NVARCHAR(80) NOT NULL,
    Score         INT NULL,

    /*  0 to 100, derived from input coverage. See the header. */
    Confidence    INT NOT NULL,

    Reason        NVARCHAR(600) NOT NULL,
    EvidenceCsv   NVARCHAR(400) NOT NULL
        CONSTRAINT DF_UserStateSnapshot_Evidence DEFAULT '',

    ComputedUtc   DATETIME2(3) NOT NULL
        CONSTRAINT DF_UserStateSnapshot_ComputedUtc DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_UserStateSnapshot
        PRIMARY KEY CLUSTERED (UserId, ForLocalDate DESC, DimensionCode),
    CONSTRAINT FK_UserStateSnapshot_Dimension FOREIGN KEY (DimensionCode)
        REFERENCES [Intelligence].[StateDimension](DimensionCode),
    CONSTRAINT CK_UserStateSnapshot_Confidence
        CHECK (Confidence BETWEEN 0 AND 100),
    CONSTRAINT CK_UserStateSnapshot_Score
        CHECK (Score IS NULL OR Score BETWEEN 0 AND 100),
    /*  Zero confidence means unknown, always. Enforced here so no future
        writer can record a value it had no basis for. */
    CONSTRAINT CK_UserStateSnapshot_UnknownWhenNoConfidence
        CHECK (Confidence > 0 OR ValueCode = 'unknown')
);
GO

/*  UserId leads the clustered key, so a woman's history is contiguous and the
    foreign key is covered. Dimension lookups across users are rare enough not
    to earn their own index yet. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_UserStateSnapshot_Dimension'
                 AND object_id = OBJECT_ID('[Intelligence].[UserStateSnapshot]'))
    CREATE INDEX [IX_UserStateSnapshot_Dimension]
        ON [Intelligence].[UserStateSnapshot] (DimensionCode);
GO

-- ---------------------------------------------------------------------------
-- Seed: the dimensions
-- ---------------------------------------------------------------------------

MERGE [Intelligence].[StateDimension] AS target
USING (VALUES
    ('energy',      N'Energy',      'score',       70, N'Not enough logged to tell yet.',        10),
    ('focus',       N'Focus',       'score',       70, N'Not enough logged to tell yet.',        20),
    ('consistency', N'Consistency', 'score',       60, N'Not enough logged to tell yet.',        30),
    ('wellness',    N'Wellbeing',   'score',       70, N'Not enough logged to tell yet.',        40),
    ('balance',     N'Balance',     'categorical', NULL, N'Not enough logged to tell yet.',      50),
    ('routine',     N'Routine',     'categorical', NULL, N'Not enough logged to tell yet.',      60),
    ('momentum',    N'Momentum',    'categorical', NULL, N'Needs a few days before this means anything.', 70),
    ('load',        N'Day',         'categorical', NULL, N'Not enough logged to tell yet.',      80),
    ('risk',        N'Watch out for', 'categorical', NULL, N'Nothing to flag.',                  90)
) AS source (DimensionCode, DisplayName, ValueKind, BaselineScore, UnknownText, SortOrder)
    ON target.DimensionCode = source.DimensionCode
WHEN NOT MATCHED THEN
    INSERT (DimensionCode, DisplayName, ValueKind, BaselineScore, UnknownText, SortOrder)
    VALUES (source.DimensionCode, source.DisplayName, source.ValueKind,
            source.BaselineScore, source.UnknownText, source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: what each dimension reads
-- ---------------------------------------------------------------------------

MERGE [Intelligence].[StateInput] AS target
USING (VALUES
    ('energy',      'sleep',       3),
    ('energy',      'water',       1),
    ('energy',      'steps',       2),
    ('focus',       'sleep',       2),
    ('focus',       'screen_time', 2),
    ('focus',       'work',        1),
    ('consistency', 'sleep',       1),
    ('consistency', 'water',       1),
    ('consistency', 'steps',       1),
    ('wellness',    'sleep',       2),
    ('wellness',    'mood',        3),
    ('wellness',    'stress',      2),
    ('balance',     'work',        3),
    ('balance',     'family_time', 2),
    ('balance',     'steps',       1),
    ('routine',     'sleep',       2),
    ('routine',     'water',       1),
    ('momentum',    'sleep',       1),
    ('momentum',    'steps',       1),
    ('load',        'work',        2),
    ('load',        'screen_time', 1),
    ('load',        'sleep',       1),
    ('risk',        'water',       2),
    ('risk',        'sleep',       1)
) AS source (DimensionCode, EventTypeCode, Weight)
    ON target.DimensionCode = source.DimensionCode
   AND target.EventTypeCode = source.EventTypeCode
WHEN NOT MATCHED THEN
    INSERT (DimensionCode, EventTypeCode, Weight)
    VALUES (source.DimensionCode, source.EventTypeCode, source.Weight);
GO

-- ---------------------------------------------------------------------------
-- Seed: how signals move each dimension
-- ---------------------------------------------------------------------------

MERGE [Intelligence].[StateRule] AS target
USING (VALUES
    -- scores
    ('energy',      'short_sleep',      -25, NULL, NULL, N'You have been sleeping less than usual.'),
    ('energy',      'low_hydration',    -10, NULL, NULL, N'You have been drinking less water than usual.'),
    ('energy',      'low_activity',     -10, NULL, NULL, N'You have been moving less than usual.'),
    ('focus',       'short_sleep',      -20, NULL, NULL, N'Short nights make focus harder.'),
    ('focus',       'high_screen_time', -15, NULL, NULL, N'Your screen time has been higher than usual.'),
    ('focus',       'high_stress',      -15, NULL, NULL, N'You have been recording higher stress.'),
    ('wellness',    'low_mood',         -25, NULL, NULL, N'Your mood has been lower over the last few days.'),
    ('wellness',    'high_stress',      -20, NULL, NULL, N'You have been recording higher stress.'),
    ('wellness',    'short_sleep',      -10, NULL, NULL, N'You have been sleeping less than usual.'),
    ('consistency', 'low_hydration',    -15, NULL, NULL, N'Water has been recorded less often.'),
    ('consistency', 'short_sleep',      -15, NULL, NULL, N'Sleep has been shorter than your usual.'),
    -- categorical
    ('balance',     'long_work',         30, 'work_heavy',  N'Work heavy',
     N'You have been recording long working days.'),
    ('balance',     'low_selfcare',      20, 'work_heavy',  N'Work heavy',
     N'Fewer moments for yourself than usual.'),
    ('load',        'long_work',         30, 'overloaded',  N'A full day',
     N'Long working days alongside everything else.'),
    ('load',        'high_screen_time',  15, 'overloaded',  N'A full day',
     N'Higher screen time than usual.'),
    ('routine',     'short_sleep',       25, 'disrupted',   N'A bit disrupted',
     N'Your sleep pattern has shifted.'),
    ('routine',     'low_hydration',     15, 'disrupted',   N'A bit disrupted',
     N'Water has been less regular.'),
    ('risk',        'low_hydration',     30, 'hydration',   N'Hydration',
     N'You have been drinking less water than your usual.'),
    ('risk',        'short_sleep',       25, 'sleep',       N'Sleep',
     N'You have been sleeping less than your usual.')
) AS source (DimensionCode, SignalCode, ScoreDelta, ValueCode, ValueText, ReasonText)
    ON target.DimensionCode = source.DimensionCode
   AND target.SignalCode = source.SignalCode
WHEN NOT MATCHED THEN
    INSERT (DimensionCode, SignalCode, ScoreDelta, ValueCode, ValueText, ReasonText)
    VALUES (source.DimensionCode, source.SignalCode, source.ScoreDelta,
            source.ValueCode, source.ValueText, source.ReasonText);
GO
