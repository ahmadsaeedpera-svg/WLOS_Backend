/*  66_Prediction.sql

    The Prediction Platform.

    A prediction is framed. It computes nothing.

    Behaviour already observes three probabilities from her logged history —
    the chance of doing a thing again, the chance of still logging next week,
    and the chance of stopping. Prediction turns one of those into a forward
    statement with a window and its support attached. It does not produce a
    new number, adjust an existing one, or combine several into a fourth.

    Why framing rather than forecasting
    -----------------------------------
    A forecasting engine would have to justify its arithmetic, and it could
    not: the justification would describe a model rather than describe her.
    Worse, there would then be two numbers for the same question — the one
    Behaviour observed and the one Prediction produced — and they would
    disagree the day either changed. Because this only frames, every
    prediction resolves to a measure she can be shown, computed once, in the
    one place that computes behaviour.

    How "never recomputes" is made structural
    -----------------------------------------
    A PredictionType names the Behaviour measure it frames, and carries a
    SourceFamily column pinned to 'probability' by a constraint. The pair is a
    foreign key into Behaviour.MeasureType (MeasureCode, Family). So a
    prediction can only ever point at a measure Behaviour publishes as a
    probability — not at a count, not at a rhythm, and not at nothing. There
    is no configuration that makes this engine state a likelihood the
    behaviour engine never observed, and it is refused by the database rather
    than by review.

    How "always says what it rests on" is made structural
    ----------------------------------------------------
    The statement is filled in, not written — the same guarantee the coach
    carries. A framing supplies a pattern with three placeholders: {chance},
    the observed probability; {window}, how far ahead it speaks; and
    {support}, the days of history behind it. A CHECK refuses a pattern
    missing any of them, so no framing can state a likelihood without also
    stating its window and its support. A bare "70% chance" is the thing this
    platform must never say, because it reads as knowledge and is a summary of
    three weeks.

    What prediction must never become
    ---------------------------------
    Never clinical. It predicts behaviour — whether she does a thing — never a
    condition, an outcome of one, or a cause. prediction_test.sql asserts that
    against the same word ban the knowledge graph and the recommender carry.

    Never deterministic. Every statement carries a probability, a window and
    its support; none says a thing will happen.

    Reminder timing is deliberately absent
    --------------------------------------
    The roadmap listed "best reminder time" here. It is not a prediction and
    is not built as one: Behaviour already observes preferred_hour from her
    logged history, and restating an observation in the future tense would be
    a rename. Renaming what the platform observed as what it predicts is
    precisely how a product starts overstating what it knows about a woman, so
    the FK below cannot express it — a preference measure is not a
    probability, and the database refuses the row.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('Predict') IS NULL
    EXEC('CREATE SCHEMA [Predict]');
GO

-- ---------------------------------------------------------------------------
-- The FK target that makes "frames a probability, or nothing" possible
-- ---------------------------------------------------------------------------
/*  Behaviour.MeasureType is keyed on MeasureCode alone, which is correct for
    Behaviour. Prediction needs to reference the code *and* assert its family
    in the same breath, and a foreign key can only point at a unique key.

    Declared here rather than in 49_Behaviour.sql because it exists solely to
    serve this engine's guarantee; keeping it beside the thing it protects
    means a reader of the constraint finds the reason for it. It adds no
    column and no semantics to Behaviour — MeasureCode is already unique, so
    the pair trivially is. */
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints
               WHERE name = 'UQ_MeasureType_CodeFamily')
    ALTER TABLE [Behaviour].[MeasureType]
        ADD CONSTRAINT UQ_MeasureType_CodeFamily UNIQUE (MeasureCode, Family);
GO

-- ---------------------------------------------------------------------------
-- What prediction consumes
-- ---------------------------------------------------------------------------
/*  Observations that have already been made.

    A type rather than a read, for the fourth time and the same reason
    Behaviour, Recommend and Coach have one: the live path passes what
    Behaviour observed, the Decision Inspector passes a hypothetical, and
    there is one framing implementation between them. Simulating this against
    a second copy would let an operator configure the platform against a
    fiction.

    SpanDays is carried because it *is* the support. A prediction that stated
    a chance without the days behind it would be the platform sounding certain
    about three weeks of history, and the placeholder constraint above exists
    to stop exactly that — but only if the number reaches the framing at all. */
IF TYPE_ID('Predict.ObservationSet') IS NULL
    CREATE TYPE [Predict].[ObservationSet] AS TABLE (
        SubjectKey   VARCHAR(40)   NOT NULL,
        MeasureCode  VARCHAR(30)   NOT NULL,
        /*  The probability itself, as Behaviour published it. Nothing in this
            schema or its procedures alters this number. */
        ValueNumeric DECIMAL(9, 4) NULL,
        /*  Inherited, never asserted — a prediction resting on a measure with
            nine days behind it cannot report thick confidence. */
        Confidence   INT           NOT NULL,
        SpanDays     INT           NOT NULL,
        PRIMARY KEY CLUSTERED (SubjectKey, MeasureCode)
    );
GO

-- ---------------------------------------------------------------------------
-- Horizons — how far ahead, as data
-- ---------------------------------------------------------------------------
/*  A window is configuration, not a literal in a procedure. "Tomorrow" and
    "over the next week" are the same statement about different spans, and an
    operator adding a fortnight should not need a release.

    PhraseText is how the window is said to her. It is separate from
    DisplayName because the library lists "Next week" and the sentence reads
    "over the next week", and writing one from the other in code would put
    copy in a procedure. */
IF OBJECT_ID('Predict.Horizon') IS NULL
BEGIN
    CREATE TABLE [Predict].[Horizon] (
        HorizonCode VARCHAR(20)  NOT NULL,
        DisplayName NVARCHAR(60) NOT NULL,
        PhraseText  NVARCHAR(60) NOT NULL,

        /*  How far ahead the statement reaches. Bounded at a quarter: beyond
            that, behaviour observed over a few weeks says nothing worth
            saying, and a window long enough to be unfalsifiable is not a
            prediction. */
        WindowDays  INT NOT NULL,

        SortOrder   INT NOT NULL,

        CONSTRAINT PK_Horizon PRIMARY KEY CLUSTERED (HorizonCode),
        CONSTRAINT CK_Horizon_Window CHECK (WindowDays BETWEEN 1 AND 90)
    );
END
GO

-- ---------------------------------------------------------------------------
-- The catalogue — what may be predicted, and from what
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Predict.PredictionType') IS NULL
BEGIN
    CREATE TABLE [Predict].[PredictionType] (
        PredictionKey     VARCHAR(40)  NOT NULL,
        DisplayName       NVARCHAR(80) NOT NULL,
        [Description]     NVARCHAR(300) NOT NULL,

        HorizonCode       VARCHAR(20)  NOT NULL,

        /*  The Behaviour measure this frames. The whole engine is this
            column: prediction restates this number and adds a window to it. */
        SourceMeasureCode VARCHAR(30)  NOT NULL,

        /*  Pinned, not chosen. Together with the foreign key below this is
            what makes "frames a probability, or nothing" a property of the
            schema rather than a claim in a document. */
        SourceFamily      VARCHAR(20)  NOT NULL
            CONSTRAINT DF_PredictionType_SourceFamily DEFAULT 'probability',

        /*  The statement, as a pattern. {chance} is the observed probability,
            {window} how far ahead it speaks, {support} the days behind it.
            Everything else is connective phrasing carrying no claim. */
        FramingPattern    NVARCHAR(400) NOT NULL,

        /*  Below either of these the prediction is withheld entirely — not
            shown as zero, not shown as unknown, absent. The same rule
            Behaviour follows for a measure it has not seen enough of, applied
            again here because a prediction is a louder statement than the
            measure under it and deserves at least as high a bar. */
        MinConfidence     INT NOT NULL
            CONSTRAINT DF_PredictionType_MinConfidence DEFAULT 40,
        MinSupportDays    INT NOT NULL
            CONSTRAINT DF_PredictionType_MinSupportDays DEFAULT 14,

        /*  How long the statement stays true once made. A statement about
            tomorrow is wrong the day after, and a platform still showing it
            would be talking about a day that has gone. */
        LifetimeHours     INT NOT NULL
            CONSTRAINT DF_PredictionType_Lifetime DEFAULT 24,

        SortOrder         INT NOT NULL,
        IsActive          BIT NOT NULL
            CONSTRAINT DF_PredictionType_IsActive DEFAULT 1,

        CONSTRAINT PK_PredictionType PRIMARY KEY CLUSTERED (PredictionKey),

        /*  A framing that dropped {support} would state a likelihood with
            nothing behind it, and one that dropped {window} would state a
            likelihood about no particular time. Both read as knowledge. Both
            are refused here rather than caught in review. */
        CONSTRAINT CK_PredictionType_KeepsChance
            CHECK (FramingPattern LIKE '%{chance}%'),
        CONSTRAINT CK_PredictionType_KeepsWindow
            CHECK (FramingPattern LIKE '%{window}%'),
        CONSTRAINT CK_PredictionType_KeepsSupport
            CHECK (FramingPattern LIKE '%{support}%'),

        CONSTRAINT CK_PredictionType_SourceFamily
            CHECK (SourceFamily = 'probability'),

        CONSTRAINT CK_PredictionType_MinConfidence
            CHECK (MinConfidence BETWEEN 1 AND 100),
        CONSTRAINT CK_PredictionType_MinSupport
            CHECK (MinSupportDays >= 1),
        CONSTRAINT CK_PredictionType_Lifetime
            CHECK (LifetimeHours BETWEEN 1 AND 720),

        CONSTRAINT FK_PredictionType_Horizon FOREIGN KEY (HorizonCode)
            REFERENCES [Predict].[Horizon] (HorizonCode),

        /*  The structural half of "never recomputes". A prediction may name a
            measure only if Behaviour publishes it as a probability. */
        CONSTRAINT FK_PredictionType_SourceMeasure
            FOREIGN KEY (SourceMeasureCode, SourceFamily)
            REFERENCES [Behaviour].[MeasureType] (MeasureCode, Family)
    );

    CREATE INDEX IX_PredictionType_Source
        ON [Predict].[PredictionType] (SourceMeasureCode)
        INCLUDE (PredictionKey, HorizonCode);
END
GO

-- ---------------------------------------------------------------------------
-- What was predicted, and on what basis
-- ---------------------------------------------------------------------------
/*  Snapshotted like every other engine's output: changing a framing must not
    rewrite what the platform said to her last Tuesday.

    Every column that makes a prediction honest is NOT NULL and constrained.
    A row here cannot exist without its window, its support, its confidence
    and its evidence, so there is no path — procedure, import or otherwise —
    that stores a bare probability. */
IF OBJECT_ID('Predict.Predicted') IS NULL
BEGIN
    CREATE TABLE [Predict].[Predicted] (
        UserId             UNIQUEIDENTIFIER NOT NULL,
        PredictionKey      VARCHAR(40) NOT NULL,
        SubjectKey         VARCHAR(40) NOT NULL,
        ForLocalDate       DATE NOT NULL,

        /*  Carried through from Behaviour unchanged, as a whole percent. The
            measure is a 0–1 probability; the only transformation this engine
            performs is that presentation, and prediction_test.sql asserts the
            round trip. */
        ProbabilityPercent INT NOT NULL,

        /*  The window, denormalised from the horizon on purpose: an operator
            shortening "next week" must not silently restate what she was
            already told. */
        WindowDays         INT NOT NULL,

        /*  The days of history the probability rests on. */
        SupportDays        INT NOT NULL,

        Confidence         INT NOT NULL,

        /*  The finished statement, composed by substitution. Every fact in it
            came from the observation. */
        StatementText      NVARCHAR(600) NOT NULL,

        /*  The observation itself, as kind:key, so evidence resolves to a row
            in Behaviour rather than to prose. */
        EvidenceCsv        NVARCHAR(600) NOT NULL,

        ExpiresUtc         DATETIME2(3) NOT NULL,
        EngineVersion      VARCHAR(20) NOT NULL,
        ComputedUtc        DATETIME2(3) NOT NULL
            CONSTRAINT DF_Predicted_ComputedUtc DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_Predicted PRIMARY KEY CLUSTERED
            (UserId, ForLocalDate, PredictionKey, SubjectKey),

        CONSTRAINT CK_Predicted_Probability
            CHECK (ProbabilityPercent BETWEEN 0 AND 100),

        /*  The four honesty constraints. Each one is a statement the platform
            refuses to make: a chance about no particular window, a chance
            resting on no history, a chance held with no confidence, and a
            chance with nothing to resolve it back to. */
        CONSTRAINT CK_Predicted_HasWindow   CHECK (WindowDays >= 1),
        CONSTRAINT CK_Predicted_HasSupport  CHECK (SupportDays >= 1),
        CONSTRAINT CK_Predicted_HasConfidence
            CHECK (Confidence BETWEEN 1 AND 100),
        CONSTRAINT CK_Predicted_HasEvidence CHECK (LEN(EvidenceCsv) > 0),

        CONSTRAINT FK_Predicted_Type FOREIGN KEY (PredictionKey)
            REFERENCES [Predict].[PredictionType] (PredictionKey),

        CONSTRAINT FK_Predicted_Subject FOREIGN KEY (SubjectKey)
            REFERENCES [Behaviour].[Subject] (SubjectKey)
    );

    CREATE INDEX IX_Predicted_Type
        ON [Predict].[Predicted] (PredictionKey) INCLUDE (UserId, SubjectKey);
END
GO

-- ---------------------------------------------------------------------------
-- Foreign key indexes
-- ---------------------------------------------------------------------------
/*  Every foreign key needs a supporting index, and index_coverage_test.sql
    fails without one. An unindexed foreign key turns the parent-side delete
    and the join into a scan, and on a table that grows once per woman per day
    that is the difference between a seek and a table.

    Declared as guarded statements outside the CREATE TABLE blocks rather than
    inside them, which is the convention 30_Indexes_ForeignKeys.sql set. The
    reason matters: an index created inside `IF OBJECT_ID(...) IS NULL` never
    reaches a database that already has the table, so re-applying would not
    converge — and a schema that only converges on a brand-new server is
    exactly the shape of defect the audit contract ordering bug was. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_PredictionType_Horizon'
                 AND object_id = OBJECT_ID('Predict.PredictionType'))
    CREATE INDEX [IX_PredictionType_Horizon]
        ON [Predict].[PredictionType] (HorizonCode) INCLUDE (PredictionKey);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Predicted_Subject'
                 AND object_id = OBJECT_ID('Predict.Predicted'))
    CREATE INDEX [IX_Predicted_Subject]
        ON [Predict].[Predicted] (SubjectKey) INCLUDE (UserId, PredictionKey);
GO

-- ---------------------------------------------------------------------------
-- Seed: horizons
-- ---------------------------------------------------------------------------
MERGE [Predict].[Horizon] AS target
USING (VALUES
    ('tomorrow',   N'Tomorrow',   N'tomorrow',         1, 10),
    ('next_week',  N'Next week',  N'the next week',    7, 20),
    ('next_month', N'Next month', N'the next month',  30, 30)
) AS source (HorizonCode, DisplayName, PhraseText, WindowDays, SortOrder)
    ON target.HorizonCode = source.HorizonCode
WHEN NOT MATCHED THEN
    INSERT (HorizonCode, DisplayName, PhraseText, WindowDays, SortOrder)
    VALUES (source.HorizonCode, source.DisplayName, source.PhraseText,
            source.WindowDays, source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: what may be predicted
-- ---------------------------------------------------------------------------
/*  Three, because Behaviour observes three probabilities and the foreign key
    permits nothing else. That is the intended relationship between the two
    engines: this catalogue can only grow when the behaviour engine observes
    something new, which is the one place where observing is done.

    Every pattern carries {chance}, {window} and {support}, so none of them
    can say more than the observation did. The wording is deliberately hedged
    and deliberately backward-looking: "you have done this on about 70% of
    days" is a statement about her logged history, where "there is a 70%
    chance you will do this tomorrow" reads as knowledge about a day that has
    not happened. Both rest on the identical number. Only one of them is
    honest about where it came from. */
MERGE [Predict].[PredictionType] AS target
USING (VALUES
    ('habit_continuation', N'Doing it again',
     N'How often she has done this, framed forward one day. Behavioural only: '
     + N'it says nothing about health and nothing about why.',
     'tomorrow', 'completion_probability',
     N'You have done this on about {chance} of days recently, which is the '
     + N'best guide there is to {window}. Based on {support}.',
     40, 14, 24, 10),

    ('engagement', N'Still logging',
     N'Whether she is likely to keep logging at all. Used to decide whether '
     + N'the platform should ask for less, not to grade her.',
     'next_week', 'engagement_probability',
     N'You have kept this going on about {chance} of days recently, which is '
     + N'the best guide there is to {window}. Based on {support}.',
     50, 14, 72, 20),

    ('dropoff', N'Letting it go',
     N'The complement of engagement, surfaced separately because it is what a '
     + N'gentler week is decided on. Never shown to her as a warning.',
     'next_week', 'dropoff_probability',
     N'This has slipped on about {chance} of days recently, which is what '
     + N'{window} is judged on. Based on {support}.',
     50, 14, 72, 30)
) AS source (PredictionKey, DisplayName, [Description], HorizonCode,
             SourceMeasureCode, FramingPattern, MinConfidence, MinSupportDays,
             LifetimeHours, SortOrder)
    ON target.PredictionKey = source.PredictionKey
WHEN NOT MATCHED AND EXISTS (
        SELECT 1 FROM [Behaviour].[MeasureType] m
        WHERE m.MeasureCode = source.SourceMeasureCode
          AND m.Family = 'probability') THEN
    INSERT (PredictionKey, DisplayName, [Description], HorizonCode,
            SourceMeasureCode, FramingPattern, MinConfidence, MinSupportDays,
            LifetimeHours, SortOrder)
    VALUES (source.PredictionKey, source.DisplayName, source.[Description],
            source.HorizonCode, source.SourceMeasureCode,
            source.FramingPattern, source.MinConfidence, source.MinSupportDays,
            source.LifetimeHours, source.SortOrder);
GO

PRINT 'Prediction Platform — schema ready.';
GO
