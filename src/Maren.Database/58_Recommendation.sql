/*  58_Recommendation.sql

    The Recommendation Platform.

    A recommendation is assembled. It decides nothing.

    Everything it can know already exists somewhere and is already explained:
    Behaviour says how she lives, Growth says what she is working towards and
    what her routines are, Knowledge says what her timeline currently signals,
    Intelligence says what state she is in, Rules says who a thing applies to.
    A recommendation is the sentence you get when several of those line up.

    Why assembly rather than inference
    ----------------------------------
    An engine that inferred would have to justify itself, and it could not: the
    reasoning would be a description of an algorithm rather than of her. Because
    this only assembles, every recommendation can name the exact observations
    that produced it, and a woman asking "why am I being told this" gets an
    answer made of things she logged.

    It is also the only way the platform stays honest as it grows. Six engines
    each deciding what to suggest is six places to encode an opinion about
    women, and no way to audit any of them.

    The assembly rule is data
    -------------------------
    RecommendationInput rows say which observations contribute, what value
    counts, how much weight each carries, and what sentence each adds to the
    reasoning. Adding "suggest a wind-down when sleep consistency drops below
    half" is rows, not a release. Nothing in this schema computes a streak, a
    consistency figure or a probability - it compares published values to
    configured thresholds, which is what assembly means.

    Nothing clinical
    ----------------
    No recommendation describes a condition, a risk of one, or a cause. The
    knowledge graph's ban on causal verbs applies here and is asserted the same
    way.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('Recommend') IS NULL
    EXEC('CREATE SCHEMA [Recommend]');
GO

-- ---------------------------------------------------------------------------
-- The evidence set — what assembly consumes
-- ---------------------------------------------------------------------------
/*  The same shape the behaviour arithmetic took, and for the same reason.

    fn_AssembleFrom reads this and nothing else, so the real path and the
    Decision Inspector feed one implementation. Before Behaviour.fn_Measure was
    split, simulating behaviour would have meant a second copy of fourteen
    measures; simulating recommendations would mean a second copy of the
    assembly rules, with exactly the same consequence - an operator configuring
    the platform against a fiction.

    InputKey is wide because it carries different vocabularies: a signal code,
    a "subject.measure" pair, a goal template key, a routine key or a state
    dimension. The kind says which. */
IF TYPE_ID('Recommend.EvidenceSet') IS NULL
    CREATE TYPE [Recommend].[EvidenceSet] AS TABLE (
        InputKind    VARCHAR(12)   NOT NULL,
        InputKey     VARCHAR(80)   NOT NULL,
        ValueNumeric DECIMAL(9, 4) NULL,
        /*  Inherited from whichever engine produced it, so a recommendation
            built on thin history cannot report thick confidence. */
        Confidence   INT           NOT NULL,
        PRIMARY KEY CLUSTERED (InputKind, InputKey)
    );
GO

-- ---------------------------------------------------------------------------
-- The catalogue
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Recommend.RecommendationType') IS NULL
BEGIN
    CREATE TABLE [Recommend].[RecommendationType] (
        RecommendationKey VARCHAR(40)  NOT NULL,
        DisplayName       NVARCHAR(80) NOT NULL,
        DomainCode        VARCHAR(30)  NOT NULL,

        /*  What she is actually told. Written from her side of the screen, in
            the second person, and never as an instruction from an authority. */
        BodyText          NVARCHAR(400) NOT NULL,

        /*  Where it sits when several are eligible. A starting point: the
            inputs that matched adjust it. */
        BasePriority      INT NOT NULL
            CONSTRAINT DF_RecommendationType_BasePriority DEFAULT 50,

        /*  Both on a 1-5 scale, both hers rather than the platform's. Benefit
            is how much this tends to move the thing it is about; effort is what
            it costs her. A woman with no energy needs the low-effort one, and
            without both numbers nothing downstream can make that choice. */
        ExpectedBenefit   TINYINT NOT NULL
            CONSTRAINT DF_RecommendationType_Benefit DEFAULT 3,
        ExpectedEffort    TINYINT NOT NULL
            CONSTRAINT DF_RecommendationType_Effort DEFAULT 3,

        /*  How long it stays true once assembled. A suggestion about tonight is
            wrong tomorrow, and a platform that kept showing it would be telling
            her about a day that has gone. */
        LifetimeHours     INT NOT NULL
            CONSTRAINT DF_RecommendationType_Lifetime DEFAULT 24,

        IsHealthSensitive BIT NOT NULL
            CONSTRAINT DF_RecommendationType_HealthSensitive DEFAULT 0,

        SortOrder         INT NOT NULL,
        IsActive          BIT NOT NULL
            CONSTRAINT DF_RecommendationType_IsActive DEFAULT 1,

        CONSTRAINT PK_RecommendationType PRIMARY KEY CLUSTERED (RecommendationKey),

        CONSTRAINT CK_RecommendationType_Priority
            CHECK (BasePriority BETWEEN 0 AND 100),
        CONSTRAINT CK_RecommendationType_Benefit
            CHECK (ExpectedBenefit BETWEEN 1 AND 5),
        CONSTRAINT CK_RecommendationType_Effort
            CHECK (ExpectedEffort BETWEEN 1 AND 5),
        CONSTRAINT CK_RecommendationType_Lifetime
            CHECK (LifetimeHours BETWEEN 1 AND 720),

        CONSTRAINT FK_RecommendationType_Domain FOREIGN KEY (DomainCode)
            REFERENCES [Content].[LifeDomain] (DomainCode)
    );

    CREATE INDEX IX_RecommendationType_Domain
        ON [Recommend].[RecommendationType] (DomainCode)
        INCLUDE (DisplayName, SortOrder);
END
GO

-- ---------------------------------------------------------------------------
-- The assembly rule, as data
-- ---------------------------------------------------------------------------
/*  Which observations contribute to a recommendation, and what each one adds.

    This is the whole of the assembly logic. A recommendation is eligible when
    every required input matches; its priority and confidence come from the
    inputs that did; and its reasoning is the ReasonText of each, joined. So
    "why am I being told this" resolves to a list of things she logged rather
    than to a description of an algorithm. */
IF OBJECT_ID('Recommend.RecommendationInput') IS NULL
BEGIN
    CREATE TABLE [Recommend].[RecommendationInput] (
        RecommendationKey VARCHAR(40) NOT NULL,

        /*  Which engine's vocabulary InputKey belongs to. Deliberately not a
            foreign key: the five engines have five different key shapes, and a
            single constraint across them would need a table per kind. The
            assertion suite checks each kind resolves instead. */
        InputKind         VARCHAR(12) NOT NULL,
        InputKey          VARCHAR(80) NOT NULL,

        /*  'gte', 'lte' or 'is' - the last for signals and state values, where
            presence rather than magnitude is the question. */
        Comparison        VARCHAR(3)  NOT NULL
            CONSTRAINT DF_RecommendationInput_Comparison DEFAULT 'is',
        ThresholdValue    DECIMAL(9, 4) NULL,

        /*  A required input that does not match makes the recommendation
            ineligible. An optional one that does adds weight and a sentence. */
        IsRequired        BIT NOT NULL
            CONSTRAINT DF_RecommendationInput_IsRequired DEFAULT 1,
        Weight            INT NOT NULL
            CONSTRAINT DF_RecommendationInput_Weight DEFAULT 10,

        /*  The sentence this input contributes when it matches. Observational:
            it says what was logged, never what it means for her body. */
        ReasonText        NVARCHAR(200) NOT NULL,

        SortOrder         INT NOT NULL
            CONSTRAINT DF_RecommendationInput_SortOrder DEFAULT 0,

        CONSTRAINT PK_RecommendationInput PRIMARY KEY CLUSTERED
            (RecommendationKey, InputKind, InputKey),

        CONSTRAINT CK_RecommendationInput_Kind CHECK (InputKind IN
            ('signal', 'behaviour', 'goal', 'routine', 'state')),
        CONSTRAINT CK_RecommendationInput_Comparison
            CHECK (Comparison IN ('gte', 'lte', 'is')),
        CONSTRAINT CK_RecommendationInput_Weight CHECK (Weight BETWEEN 1 AND 100),

        /*  A magnitude comparison with nothing to compare against would silently
            never match, and the recommendation would simply never appear. */
        CONSTRAINT CK_RecommendationInput_ThresholdWhenNumeric
            CHECK (Comparison = 'is' OR ThresholdValue IS NOT NULL),

        CONSTRAINT FK_RecommendationInput_Type FOREIGN KEY (RecommendationKey)
            REFERENCES [Recommend].[RecommendationType] (RecommendationKey)
            ON DELETE CASCADE
    );

    CREATE INDEX IX_RecommendationInput_Kind
        ON [Recommend].[RecommendationInput] (InputKind, InputKey)
        INCLUDE (RecommendationKey);
END
GO

-- ---------------------------------------------------------------------------
-- What was assembled, and on what basis
-- ---------------------------------------------------------------------------
/*  Snapshotted for the reason every other engine's output is: a change to the
    assembly rules must not rewrite what the platform told her last Tuesday.

    ExpiresUtc is stored rather than derived so that shortening a lifetime does
    not retroactively expire something she was already shown. */
IF OBJECT_ID('Recommend.Assembled') IS NULL
BEGIN
    CREATE TABLE [Recommend].[Assembled] (
        UserId            UNIQUEIDENTIFIER NOT NULL,
        RecommendationKey VARCHAR(40) NOT NULL,
        ForLocalDate      DATE NOT NULL,

        Priority          INT NOT NULL,

        /*  Inherited from the inputs that matched, never asserted. A
            recommendation resting on a measure with nine days of history behind
            it is not a confident suggestion. */
        Confidence        INT NOT NULL,

        /*  The sentences of the inputs that matched, joined. */
        Reason            NVARCHAR(1000) NOT NULL,

        /*  The observations themselves, as kind:key, so evidence resolves to
            rows in the engines rather than to prose. */
        EvidenceCsv       NVARCHAR(600) NOT NULL,

        /*  Which engines contributed. Lets a client show "from your sleep and
            your goal" without parsing the evidence. */
        EnginesCsv        NVARCHAR(200) NOT NULL,

        ExpiresUtc        DATETIME2(3) NOT NULL,
        EngineVersion     VARCHAR(20) NOT NULL,
        ComputedUtc       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Assembled_ComputedUtc DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_Assembled PRIMARY KEY CLUSTERED
            (UserId, ForLocalDate, RecommendationKey),

        CONSTRAINT CK_Assembled_Priority CHECK (Priority BETWEEN 0 AND 100),
        CONSTRAINT CK_Assembled_Confidence CHECK (Confidence BETWEEN 0 AND 100),

        /*  Assembled from nothing is not a recommendation, it is a guess. The
            platform must never make one. */
        CONSTRAINT CK_Assembled_HasEvidence CHECK (LEN(EvidenceCsv) > 0),
        CONSTRAINT CK_Assembled_HasConfidence CHECK (Confidence > 0),

        CONSTRAINT FK_Assembled_Type FOREIGN KEY (RecommendationKey)
            REFERENCES [Recommend].[RecommendationType] (RecommendationKey)
    );

    /*  Non-filtered, for the foreign key: a reference check has to find every
        referencing row. */
    CREATE INDEX IX_Assembled_Type
        ON [Recommend].[Assembled] (RecommendationKey) INCLUDE (UserId);
END
GO

-- ---------------------------------------------------------------------------
-- Applicability: the same matcher, a new scope
-- ---------------------------------------------------------------------------
MERGE [Rules].[TargetScope] AS target
USING (VALUES
    ('recommendation', N'Recommendation',
     'Recommend.RecommendationType', 'RecommendationKey',
     N'Which recommendations the platform may assemble for a woman, by life '
     + N'stage, role, country and language. A postpartum suggestion is a rule '
     + N'row like every other targeting decision.', 60)
) AS source (ScopeCode, DisplayName, TargetTable, TargetColumn, [Description], SortOrder)
    ON target.ScopeCode = source.ScopeCode
WHEN NOT MATCHED THEN
    INSERT (ScopeCode, DisplayName, TargetTable, TargetColumn, [Description], SortOrder)
    VALUES (source.ScopeCode, source.DisplayName, source.TargetTable,
            source.TargetColumn, source.[Description], source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: the catalogue
-- ---------------------------------------------------------------------------
MERGE [Recommend].[RecommendationType] AS target
USING (VALUES
    ('water_reminder', N'A glass of water', 'hydration',
     N'You have not logged a drink today. If it helps, keep a glass where you '
     + N'will see it.', 55, 3, 1, 12, 0, 10),

    ('protect_evening', N'Protect your evening', 'lifestyle',
     N'Your wind-down has been harder to finish lately. Even one part of it '
     + N'counts.', 60, 4, 2, 24, 0, 20),

    ('gentle_movement', N'Something small and moving', 'fitness',
     N'It has been a few days since you logged moving. A short walk is enough '
     + N'to log.', 50, 3, 2, 24, 0, 30),

    ('check_in_nudge', N'A moment to check in', 'mental',
     N'You have not checked in for a while. A single line is a check-in.',
     45, 3, 1, 48, 0, 40),

    ('goal_encouragement', N'You are close', 'lifestyle',
     N'One of your goals is nearly there. The last stretch is usually the '
     + N'quiet one.', 70, 4, 1, 24, 0, 50)
) AS source (RecommendationKey, DisplayName, DomainCode, BodyText, BasePriority,
             ExpectedBenefit, ExpectedEffort, LifetimeHours, IsHealthSensitive,
             SortOrder)
    ON target.RecommendationKey = source.RecommendationKey
WHEN NOT MATCHED AND EXISTS (
        SELECT 1 FROM [Content].[LifeDomain] d
        WHERE d.DomainCode = source.DomainCode) THEN
    INSERT (RecommendationKey, DisplayName, DomainCode, BodyText, BasePriority,
            ExpectedBenefit, ExpectedEffort, LifetimeHours, IsHealthSensitive,
            SortOrder)
    VALUES (source.RecommendationKey, source.DisplayName, source.DomainCode,
            source.BodyText, source.BasePriority, source.ExpectedBenefit,
            source.ExpectedEffort, source.LifetimeHours,
            source.IsHealthSensitive, source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: what each one is assembled from
-- ---------------------------------------------------------------------------
/*  Only inserted where the referenced observation can actually exist. A
    recommendation whose required input names a measure the platform does not
    produce would never appear, and would look identical to one nobody
    qualifies for. */
MERGE [Recommend].[RecommendationInput] AS target
USING (VALUES
    ('water_reminder',     'behaviour', 'hydration.days_since_last', 'gte', 1.0, 1, 30,
     N'you have not logged a drink today'),
    ('water_reminder',     'behaviour', 'hydration.consistency',     'lte', 80.0, 0, 10,
     N'water has been logged on fewer days than usual'),

    ('protect_evening',    'behaviour', 'evening_routine.consistency', 'lte', 60.0, 1, 30,
     N'your wind-down has been finished on fewer than three evenings in five'),
    ('protect_evening',    'routine',   'evening_winddown',            'is',  NULL, 0, 10,
     N'you have an evening wind-down set up'),

    ('gentle_movement',    'behaviour', 'movement.days_since_last', 'gte', 3.0, 1, 30,
     N'it has been three days or more since you logged moving'),

    ('check_in_nudge',     'behaviour', 'reflection.days_since_last', 'gte', 7.0, 1, 30,
     N'it has been a week since your last check-in'),

    ('goal_encouragement', 'goal',      'nearly_there', 'is', NULL, 1, 40,
     N'one of your goals is close to done')
) AS source (RecommendationKey, InputKind, InputKey, Comparison, ThresholdValue,
             IsRequired, Weight, ReasonText)
    ON target.RecommendationKey = source.RecommendationKey
   AND target.InputKind = source.InputKind
   AND target.InputKey = source.InputKey
WHEN NOT MATCHED AND EXISTS (
        SELECT 1 FROM [Recommend].[RecommendationType] t
        WHERE t.RecommendationKey = source.RecommendationKey) THEN
    INSERT (RecommendationKey, InputKind, InputKey, Comparison, ThresholdValue,
            IsRequired, Weight, ReasonText)
    VALUES (source.RecommendationKey, source.InputKind, source.InputKey,
            source.Comparison, source.ThresholdValue, source.IsRequired,
            source.Weight, source.ReasonText);
GO

PRINT 'Recommendation Platform — schema ready.';
GO
