/*  62_Coach.sql

    The Coach Platform.

    The coach explains. It decides nothing, predicts nothing, diagnoses
    nothing, and — the hard one — invents nothing.

    How "invents nothing" is made structural
    ----------------------------------------
    A coach that composed prose freely would eventually say something the
    platform never observed, and nobody would notice until a woman was told
    something untrue about herself. So a coach message is not written; it is
    filled in.

    A tone supplies a pattern with two placeholders: {body}, the recommendation
    the platform already made, and {reason}, the sentences of the observations
    that produced it. Everything else in the pattern is connective phrasing —
    "because", "if it helps" — carrying no claim. A pattern without {reason} is
    refused by a constraint, so no tone can be configured that drops the
    evidence and keeps the encouragement.

    That means the only facts in any coach message are facts the recommendation
    already carried, and those came from her timeline.

    Tone is configuration
    ---------------------
    Which voice to use is chosen from what the other engines observed — low
    energy, thin momentum, a goal nearly done — as ToneRule rows evaluated
    against the same evidence set Recommend uses. There is no second evidence
    vocabulary and no tone logic in code.

    What the coach must never become
    --------------------------------
    Not a second opinion. It never reassembles a recommendation and never
    reaches RecommendationInput; if it did, the platform would have two answers
    to what she should be told. coach_test.sql asserts that against the
    dependency graph.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('Coach') IS NULL
    EXEC('CREATE SCHEMA [Coach]');
GO

-- ---------------------------------------------------------------------------
-- What the coach is given to explain
-- ---------------------------------------------------------------------------
/*  Recommendations that have already been assembled.

    A type rather than a read, for the same reason Behaviour and Recommend have
    one: the live path passes what Recommend produced, the Decision Inspector
    passes a hypothetical, and there is one explanation implementation. The
    coach cannot reassemble even if somebody tried - it has no inputs to
    reassemble from. */
IF TYPE_ID('Coach.ExplainSet') IS NULL
    CREATE TYPE [Coach].[ExplainSet] AS TABLE (
        RecommendationKey VARCHAR(40)  NOT NULL,
        DisplayName       NVARCHAR(80) NOT NULL,
        BodyText          NVARCHAR(400) NOT NULL,
        /*  The recommendation's own reasoning. The coach quotes this; it never
            writes its own. */
        Reason            NVARCHAR(1000) NOT NULL,
        EvidenceCsv       NVARCHAR(600) NOT NULL,
        Priority          INT NOT NULL,
        Confidence        INT NOT NULL,
        ExpectedEffort    TINYINT NOT NULL,
        PRIMARY KEY CLUSTERED (RecommendationKey)
    );
GO

-- ---------------------------------------------------------------------------
-- Tone
-- ---------------------------------------------------------------------------
/*  How the platform sounds, not what it says.

    Separated from content deliberately. A woman with no energy and a woman on
    a fourteen-day run should hear the same fact differently, and neither
    should hear a different fact. */
IF OBJECT_ID('Coach.ToneProfile') IS NULL
BEGIN
    CREATE TABLE [Coach].[ToneProfile] (
        ToneCode      VARCHAR(30)  NOT NULL,
        DisplayName   NVARCHAR(60) NOT NULL,
        [Description] NVARCHAR(300) NOT NULL,

        /*  The message pattern. {body} is the recommendation the platform
            already made; {reason} is the observations that produced it.

            Everything else here is connective phrasing and carries no claim.
            That is the whole "invents nothing" guarantee, and it is enforced by
            the constraint below rather than by review. */
        Pattern       NVARCHAR(600) NOT NULL,

        /*  When two tones both apply. Higher wins; ties break on the code so
            the answer is stable rather than arbitrary. */
        Weight        INT NOT NULL CONSTRAINT DF_ToneProfile_Weight DEFAULT 10,

        /*  Exactly one tone must be usable when nothing else matches, or a
            woman gets a recommendation with no voice at all. */
        IsDefault     BIT NOT NULL CONSTRAINT DF_ToneProfile_IsDefault DEFAULT 0,

        SortOrder     INT NOT NULL,
        IsActive      BIT NOT NULL CONSTRAINT DF_ToneProfile_IsActive DEFAULT 1,

        CONSTRAINT PK_ToneProfile PRIMARY KEY CLUSTERED (ToneCode),

        /*  A pattern that dropped {reason} would keep the encouragement and
            lose the evidence - a coach telling her what to do without saying
            what it saw. That is precisely the failure this platform refuses,
            so it is a constraint and not a guideline. */
        CONSTRAINT CK_ToneProfile_KeepsReason
            CHECK (Pattern LIKE '%{reason}%'),

        /*  And it must carry the recommendation itself, or the message is
            reasoning with nothing attached to it. */
        CONSTRAINT CK_ToneProfile_KeepsBody
            CHECK (Pattern LIKE '%{body}%'),

        CONSTRAINT CK_ToneProfile_Weight CHECK (Weight BETWEEN 1 AND 100)
    );

    /*  At most one default. Two would make the fallback arbitrary. */
    CREATE UNIQUE INDEX UX_ToneProfile_OneDefault
        ON [Coach].[ToneProfile] (IsDefault) WHERE IsDefault = 1;
END
GO

-- ---------------------------------------------------------------------------
-- When each tone applies
-- ---------------------------------------------------------------------------
/*  Tone selection as data, evaluated against the same evidence set
    Recommendation uses. No second vocabulary, and no tone logic in code.

    A tone with no rules is never selected by observation - it can only be the
    default. That is deliberate: a tone that applied unconditionally would win
    every time its weight was highest and the others would be dead rows. */
IF OBJECT_ID('Coach.ToneRule') IS NULL
BEGIN
    CREATE TABLE [Coach].[ToneRule] (
        ToneCode       VARCHAR(30) NOT NULL,
        InputKind      VARCHAR(12) NOT NULL,
        InputKey       VARCHAR(80) NOT NULL,
        Comparison     VARCHAR(3)  NOT NULL
            CONSTRAINT DF_ToneRule_Comparison DEFAULT 'is',
        ThresholdValue DECIMAL(9, 4) NULL,

        /*  Why this tone suits that observation. Shown to operators; never to
            her, because it is about the platform rather than about her. */
        RationaleText  NVARCHAR(200) NOT NULL,

        CONSTRAINT PK_ToneRule PRIMARY KEY CLUSTERED
            (ToneCode, InputKind, InputKey),

        CONSTRAINT CK_ToneRule_Kind CHECK (InputKind IN
            ('signal', 'behaviour', 'goal', 'routine', 'state')),
        CONSTRAINT CK_ToneRule_Comparison
            CHECK (Comparison IN ('gte', 'lte', 'is')),
        CONSTRAINT CK_ToneRule_ThresholdWhenNumeric
            CHECK (Comparison = 'is' OR ThresholdValue IS NOT NULL),

        CONSTRAINT FK_ToneRule_Tone FOREIGN KEY (ToneCode)
            REFERENCES [Coach].[ToneProfile] (ToneCode) ON DELETE CASCADE
    );

    CREATE INDEX IX_ToneRule_Input
        ON [Coach].[ToneRule] (InputKind, InputKey) INCLUDE (ToneCode);
END
GO

-- ---------------------------------------------------------------------------
-- What was explained, and on what basis
-- ---------------------------------------------------------------------------
/*  Snapshotted like every other engine's output: a change to a tone must not
    rewrite what the platform said to her last Tuesday. */
IF OBJECT_ID('Coach.Explained') IS NULL
BEGIN
    CREATE TABLE [Coach].[Explained] (
        UserId            UNIQUEIDENTIFIER NOT NULL,
        RecommendationKey VARCHAR(40) NOT NULL,
        ForLocalDate      DATE NOT NULL,

        ToneCode          VARCHAR(30) NOT NULL,

        /*  The finished message. Composed by substitution, so every fact in it
            came from the recommendation. */
        MessageText       NVARCHAR(1200) NOT NULL,

        /*  Why this tone. About the platform's choice of voice, not about her. */
        ToneRationale     NVARCHAR(200) NOT NULL,

        /*  Carried through from the recommendation unchanged. The coach adds no
            evidence of its own because it observes nothing. */
        EvidenceCsv       NVARCHAR(600) NOT NULL,
        Confidence        INT NOT NULL,

        ExpiresUtc        DATETIME2(3) NOT NULL,
        EngineVersion     VARCHAR(20) NOT NULL,
        ComputedUtc       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Explained_ComputedUtc DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_Explained PRIMARY KEY CLUSTERED
            (UserId, ForLocalDate, RecommendationKey),

        CONSTRAINT CK_Explained_Confidence CHECK (Confidence BETWEEN 0 AND 100),

        /*  Explaining nothing is not explaining. A message with no evidence
            behind it would be the coach speaking on its own account. */
        CONSTRAINT CK_Explained_HasEvidence CHECK (LEN(EvidenceCsv) > 0),
        CONSTRAINT CK_Explained_HasConfidence CHECK (Confidence > 0),

        CONSTRAINT FK_Explained_Tone FOREIGN KEY (ToneCode)
            REFERENCES [Coach].[ToneProfile] (ToneCode)
    );

    CREATE INDEX IX_Explained_Tone
        ON [Coach].[Explained] (ToneCode) INCLUDE (UserId);
END
GO

-- ---------------------------------------------------------------------------
-- Seed: tones
-- ---------------------------------------------------------------------------
/*  Four voices for the same facts. Every pattern carries {body} and {reason},
    so none of them can say more than the recommendation did. */
MERGE [Coach].[ToneProfile] AS target
USING (VALUES
    ('steady', N'Steady', N'The default. Plain, unhurried, no cheerleading.',
     N'{body} {reason}', 10, 1, 10),

    ('gentle', N'Gentle',
     N'For a day when energy or momentum is low. Removes urgency and makes the '
     + N'suggestion optional out loud.',
     N'No pressure today. {body} {reason} Only if it fits.', 30, 0, 20),

    ('encouraging', N'Encouraging',
     N'For a run she is already on, or a goal nearly done. Names what is going '
     + N'well without inflating it.',
     N'You have something going here. {body} {reason}', 25, 0, 30),

    ('brief', N'Brief',
     N'For a day already carrying a lot. Says the thing and stops.',
     N'{body} {reason}', 20, 0, 40)
) AS source (ToneCode, DisplayName, [Description], Pattern, Weight, IsDefault, SortOrder)
    ON target.ToneCode = source.ToneCode
WHEN NOT MATCHED THEN
    INSERT (ToneCode, DisplayName, [Description], Pattern, Weight, IsDefault, SortOrder)
    VALUES (source.ToneCode, source.DisplayName, source.[Description],
            source.Pattern, source.Weight, source.IsDefault, source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: when each tone applies
-- ---------------------------------------------------------------------------
/*  Only where the observation can actually exist. A tone rule naming a measure
    the platform does not produce would never fire, and the tone would look
    identical to one nobody qualifies for. */
MERGE [Coach].[ToneRule] AS target
USING (VALUES
    ('gentle', 'state', 'energy.low', 'is', NULL,
     N'she has low energy today, so the suggestion is offered rather than urged'),
    ('gentle', 'behaviour', 'hydration.momentum', 'lte', -10.0,
     N'her recent consistency has slipped, and a brisk tone would read as blame'),

    ('encouraging', 'goal', 'nearly_there', 'is', NULL,
     N'a goal of hers is close to done'),
    ('encouraging', 'behaviour', 'hydration.streak_current', 'gte', 5.0,
     N'she is on a run worth naming'),

    ('brief', 'state', 'load.high', 'is', NULL,
     N'her day is already carrying a lot')
) AS source (ToneCode, InputKind, InputKey, Comparison, ThresholdValue, RationaleText)
    ON target.ToneCode = source.ToneCode
   AND target.InputKind = source.InputKind
   AND target.InputKey = source.InputKey
WHEN NOT MATCHED AND EXISTS (
        SELECT 1 FROM [Coach].[ToneProfile] t WHERE t.ToneCode = source.ToneCode) THEN
    INSERT (ToneCode, InputKind, InputKey, Comparison, ThresholdValue, RationaleText)
    VALUES (source.ToneCode, source.InputKind, source.InputKey,
            source.Comparison, source.ThresholdValue, source.RationaleText);
GO

PRINT 'Coach Platform — schema ready.';
GO
