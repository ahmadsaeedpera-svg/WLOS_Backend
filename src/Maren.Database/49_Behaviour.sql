/*  49_Behaviour.sql

    Behaviour Intelligence: how she lives.

    Everything before this script answers "what is true about her now" - her
    stage, her state, her energy, the cards that follow. One row per dimension
    per day. Nothing answers "what does she keep doing", and that is a different
    question with a different shape: it is measured over a span, not on a date.

    Why one model rather than six engines
    -------------------------------------
    Habits, routines, streaks, consistency, momentum, rhythm, preferences and
    probabilities are not six systems. They are one behavioural model observed
    through different lenses. Built as separate engines they would each need
    "did she do this on that day", each would implement it slightly differently,
    and within a year the habit screen and the coach would disagree about the
    same streak in front of the same woman.

    So there is exactly one definition of a behaviour subject, exactly one
    function that observes it - Behaviour.fn_Observe - and every engine reads
    what it produces. An engine that computed a streak itself would be a second
    source of truth, and the second source is always the one that is wrong.

    Nothing is invented
    -------------------
    Every observation is derived from Timeline.Event and nothing else. There is
    no behavioural input a woman has not logged, no default habit, no assumed
    routine. Where there is not enough history the measure is not reported at
    all - see MinSpanDays - rather than reported with a number that looks
    certain.

    What this is not
    ----------------
    Not clinical. A measure describes what was logged and how often; no measure
    describes a condition, a risk of one, or a cause. The probability measures
    are about completing a routine or staying engaged, never about health
    outcomes. The knowledge graph's ban on causal verbs applies here too and is
    asserted the same way.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('Behaviour') IS NULL
    EXEC('CREATE SCHEMA [Behaviour]');
GO

-- ---------------------------------------------------------------------------
-- MeasureType — the vocabulary of what can be observed
-- ---------------------------------------------------------------------------
/*  A registry rather than a set of columns, for the reason the dashboard card
    registry exists: adding "how often does she do this in the evening" must be
    a row, not a schema change and a deployment.

    MinSpanDays and FullSpanDays are the honesty controls. Below MinSpanDays the
    measure is not produced - a streak calculated from two days is not a streak,
    it is two days. Between the two, confidence scales with the span actually
    observed. This is the same rule the intelligence core follows: confidence is
    computed from coverage and never asserted. */
IF OBJECT_ID('Behaviour.MeasureType') IS NULL
BEGIN
    CREATE TABLE [Behaviour].[MeasureType] (
        MeasureCode   VARCHAR(30)  NOT NULL,
        DisplayName   NVARCHAR(80) NOT NULL,

        /*  Which lens this measure is seen through. Engines select by family
            rather than by naming individual measures, so a new rhythm measure
            reaches the routine engine without touching it. */
        Family        VARCHAR(20)  NOT NULL,

        ValueKind     VARCHAR(12)  NOT NULL,
        Unit          VARCHAR(20)  NULL,

        /*  Below this many days of history the measure is withheld entirely.
            Not reported as zero, not reported as unknown - absent. A woman who
            has used the app for three days has no weekly rhythm, and inventing
            one would be the platform telling her something about herself that
            it does not know. */
        MinSpanDays   INT NOT NULL,

        /*  The span at which confidence reaches 100. */
        FullSpanDays  INT NOT NULL,

        /*  Said in her own words when there is not enough to say anything. */
        UnknownText   NVARCHAR(200) NOT NULL,

        [Description] NVARCHAR(300) NULL,
        SortOrder     INT NOT NULL,
        IsActive      BIT NOT NULL CONSTRAINT DF_MeasureType_IsActive DEFAULT 1,

        CONSTRAINT PK_MeasureType PRIMARY KEY CLUSTERED (MeasureCode),

        CONSTRAINT CK_MeasureType_Family CHECK (Family IN
            ('habit', 'rhythm', 'trend', 'preference', 'probability')),

        CONSTRAINT CK_MeasureType_ValueKind CHECK (ValueKind IN
            ('count', 'percent', 'probability', 'hour', 'weekday', 'days')),

        /*  A measure that reached full confidence before it was allowed to
            report would be confident about a span it never observed. */
        CONSTRAINT CK_MeasureType_Span CHECK (MinSpanDays >= 1
                                          AND FullSpanDays >= MinSpanDays)
    );
END
GO

-- ---------------------------------------------------------------------------
-- Subject — what a measure is about
-- ---------------------------------------------------------------------------
/*  A subject is the thing she does: drinking water, sleeping, an evening
    wind-down. One definition, shared by every engine.

    SubjectKind separates a single logged thing from a routine composed of
    several. The distinction matters for what "done today" means - a routine is
    done when its parts are - and it is recorded once here rather than being
    re-decided by whichever engine is asking. */
IF OBJECT_ID('Behaviour.Subject') IS NULL
BEGIN
    CREATE TABLE [Behaviour].[Subject] (
        SubjectKey    VARCHAR(40)  NOT NULL,
        DisplayName   NVARCHAR(80) NOT NULL,

        SubjectKind   VARCHAR(12)  NOT NULL,

        /*  The life domain this belongs to, so behaviour can be presented
            beside everything else the platform knows in that domain. */
        DomainCode    VARCHAR(30)  NOT NULL,

        /*  Health-sensitive subjects are carried through every layer so a
            client can choose not to surface them in a shared context. */
        IsHealthSensitive BIT NOT NULL
            CONSTRAINT DF_Subject_IsHealthSensitive DEFAULT 0,

        /*  How many qualifying events make a day count as done. One for most
            things; a routine overrides it with the number of its parts. */
        TargetPerDay  INT NOT NULL CONSTRAINT DF_Subject_TargetPerDay DEFAULT 1,

        /*  Neutral, observational wording. "You logged water on 12 of 14 days"
            is an observation; "you are well hydrated" is a conclusion about her
            body, which this platform does not draw. */
        ObservationText NVARCHAR(200) NOT NULL,

        SortOrder     INT NOT NULL,
        IsActive      BIT NOT NULL CONSTRAINT DF_Subject_IsActive DEFAULT 1,

        CONSTRAINT PK_Subject PRIMARY KEY CLUSTERED (SubjectKey),

        CONSTRAINT CK_Subject_Kind CHECK (SubjectKind IN ('event', 'routine')),
        CONSTRAINT CK_Subject_Target CHECK (TargetPerDay >= 1),

        CONSTRAINT FK_Subject_Domain FOREIGN KEY (DomainCode)
            REFERENCES [Content].[LifeDomain] (DomainCode)
    );

    CREATE INDEX IX_Subject_Domain ON [Behaviour].[Subject] (DomainCode)
        INCLUDE (DisplayName, SortOrder);
END
GO

-- ---------------------------------------------------------------------------
-- SubjectEvent — which logged events compose a subject
-- ---------------------------------------------------------------------------
/*  The join from behaviour to the timeline, and the only place it exists. A
    routine's parts live here as rows, so adding a step to the evening routine
    is an edit rather than a release.

    ON DELETE CASCADE is deliberate and safe here, unlike on the rule engine:
    this table has no meaning without its subject, and a subject with orphan
    parts would silently change what "done" means. */
IF OBJECT_ID('Behaviour.SubjectEvent') IS NULL
BEGIN
    CREATE TABLE [Behaviour].[SubjectEvent] (
        SubjectKey    VARCHAR(40) NOT NULL,
        EventTypeCode VARCHAR(40) NOT NULL,

        /*  A part she can skip without the routine counting as missed. The
            distinction is hers to configure, not the engine's to guess. */
        IsRequired    BIT NOT NULL
            CONSTRAINT DF_SubjectEvent_IsRequired DEFAULT 1,

        SortOrder     INT NOT NULL CONSTRAINT DF_SubjectEvent_SortOrder DEFAULT 0,

        CONSTRAINT PK_SubjectEvent PRIMARY KEY CLUSTERED
            (SubjectKey, EventTypeCode),

        CONSTRAINT FK_SubjectEvent_Subject FOREIGN KEY (SubjectKey)
            REFERENCES [Behaviour].[Subject] (SubjectKey) ON DELETE CASCADE,

        CONSTRAINT FK_SubjectEvent_EventType FOREIGN KEY (EventTypeCode)
            REFERENCES [Timeline].[EventType] (EventTypeCode)
    );

    CREATE INDEX IX_SubjectEvent_EventType
        ON [Behaviour].[SubjectEvent] (EventTypeCode) INCLUDE (SubjectKey);
END
GO

-- ---------------------------------------------------------------------------
-- SubjectMeasure — which measures apply to which subject
-- ---------------------------------------------------------------------------
/*  Not every measure suits every subject. "Best hour of day" is meaningful for
    a wind-down and meaningless for a monthly reflection.

    Without this the engine would compute every measure for every subject and
    the meaningless ones would be filtered somewhere downstream - which is
    exactly how two clients end up filtering differently. */
IF OBJECT_ID('Behaviour.SubjectMeasure') IS NULL
BEGIN
    CREATE TABLE [Behaviour].[SubjectMeasure] (
        SubjectKey  VARCHAR(40) NOT NULL,
        MeasureCode VARCHAR(30) NOT NULL,

        CONSTRAINT PK_SubjectMeasure PRIMARY KEY CLUSTERED
            (SubjectKey, MeasureCode),

        CONSTRAINT FK_SubjectMeasure_Subject FOREIGN KEY (SubjectKey)
            REFERENCES [Behaviour].[Subject] (SubjectKey) ON DELETE CASCADE,

        CONSTRAINT FK_SubjectMeasure_Measure FOREIGN KEY (MeasureCode)
            REFERENCES [Behaviour].[MeasureType] (MeasureCode)
    );

    CREATE INDEX IX_SubjectMeasure_Measure
        ON [Behaviour].[SubjectMeasure] (MeasureCode) INCLUDE (SubjectKey);
END
GO

-- ---------------------------------------------------------------------------
-- Observation — what the platform observed, and on what basis
-- ---------------------------------------------------------------------------
/*  The persisted snapshot, and the interface every engine reads.

    Every row carries its own justification: the confidence, the span it was
    measured over, how many events supported it, the dates it spans, the
    reasoning in words, the evidence, and the version of the engine that
    produced it. That is not decoration. A recommendation built on an
    observation has to be able to show why, and a woman asking "why does it
    think that about me" has to get an answer that is true - which means the
    answer travels with the observation rather than being reconstructed later
    by code that has since changed.

    Snapshotted rather than computed on demand, for the reason the state
    snapshot is: recomputing history would mean every definition change
    silently rewrote what the platform used to believe. */
IF OBJECT_ID('Behaviour.Observation') IS NULL
BEGIN
    CREATE TABLE [Behaviour].[Observation] (
        UserId        UNIQUEIDENTIFIER NOT NULL,
        SubjectKey    VARCHAR(40) NOT NULL,
        MeasureCode   VARCHAR(30) NOT NULL,
        ForLocalDate  DATE NOT NULL,

        /*  NULL when confidence is zero. Enforced below, because a zero here
            reads as "she never does it" and the truth is "we do not know". */
        ValueNumeric  DECIMAL(9, 4) NULL,
        ValueText     NVARCHAR(80) NOT NULL,

        Confidence    INT NOT NULL,

        /*  The time span the observation covers, and what was inside it. */
        SpanDays      INT NOT NULL,
        SupportingEventCount INT NOT NULL,
        FirstObservedDate DATE NULL,
        LastObservedDate  DATE NULL,

        Reason        NVARCHAR(600) NOT NULL,
        EvidenceCsv   NVARCHAR(400) NOT NULL,

        /*  Which version of the observation logic produced this. Without it, a
            change to fn_Observe makes every historical row unattributable and
            an operator cannot tell a real behaviour change from a definition
            change. */
        EngineVersion VARCHAR(20) NOT NULL,

        ComputedUtc   DATETIME2(3) NOT NULL
            CONSTRAINT DF_Observation_ComputedUtc DEFAULT SYSUTCDATETIME(),

        /*  Clustered in read order: everything the platform observed about one
            woman on one day, which is what every engine asks for. */
        CONSTRAINT PK_Observation PRIMARY KEY CLUSTERED
            (UserId, ForLocalDate, SubjectKey, MeasureCode),

        CONSTRAINT CK_Observation_Confidence
            CHECK (Confidence BETWEEN 0 AND 100),

        CONSTRAINT CK_Observation_Span CHECK (SpanDays >= 0),
        CONSTRAINT CK_Observation_Support CHECK (SupportingEventCount >= 0),

        /*  The property most likely to be quietly relaxed to make a screen look
            fuller. Stated here as well as in the function, because a constraint
            survives a rewrite of the function and a comment does not. */
        CONSTRAINT CK_Observation_UnknownWhenNoConfidence
            CHECK (Confidence > 0 OR ValueNumeric IS NULL),

        CONSTRAINT FK_Observation_Subject FOREIGN KEY (SubjectKey)
            REFERENCES [Behaviour].[Subject] (SubjectKey),

        CONSTRAINT FK_Observation_Measure FOREIGN KEY (MeasureCode)
            REFERENCES [Behaviour].[MeasureType] (MeasureCode)
    );

    /*  For "how has this one measure moved over time", which is what a trend
        chart and the coach's "you have been improving" both need. */
    CREATE INDEX IX_Observation_Series
        ON [Behaviour].[Observation] (UserId, SubjectKey, MeasureCode, ForLocalDate DESC)
        INCLUDE (ValueNumeric, Confidence);
END
GO

/*  Foreign-key support, and outside the creation block so a database built
    before these existed also gets them.

    Both foreign keys point at reference tables, and neither the clustered key
    nor the series index leads with the referencing column — both lead with
    UserId. Without these, deactivating a subject makes SQL Server scan every
    observation the platform has ever recorded to check the reference. That is
    invisible in every functional test and gets slower every day the platform
    runs, which is exactly the defect index_coverage_test.sql exists to catch;
    it caught these.

    Not filtered. A reference check has to find every referencing row, soft
    deleted ones included. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Observation_Subject'
                 AND object_id = OBJECT_ID('Behaviour.Observation'))
    CREATE INDEX IX_Observation_Subject
        ON [Behaviour].[Observation] (SubjectKey) INCLUDE (UserId, ForLocalDate);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Observation_Measure'
                 AND object_id = OBJECT_ID('Behaviour.Observation'))
    CREATE INDEX IX_Observation_Measure
        ON [Behaviour].[Observation] (MeasureCode) INCLUDE (UserId, ForLocalDate);
GO

-- ---------------------------------------------------------------------------
-- Seed: measures
-- ---------------------------------------------------------------------------
/*  Idempotent MERGE, matching every other seed in this database. */
MERGE [Behaviour].[MeasureType] AS target
USING (VALUES
    -- habit family ---------------------------------------------------------
    /*  Minimum of one day, unlike everything below it.

        MinSpanDays exists to stop the platform inferring a pattern from thin
        history. Counting is not inferring: "you logged water on one day" is a
        fact, complete after that one day, and withholding it would leave a
        woman who joined this morning with an empty screen and every engine
        downstream treating her as though she had done nothing. */
    ('days_active', N'Days logged', 'habit', 'count', 'days', 1, 28,
     N'Nothing logged yet.',
     N'How many days in the window carried at least the target number of events.', 10),

    ('consistency', N'Consistency', 'habit', 'percent', '%', 7, 28,
     N'Not enough logged yet to see a pattern.',
     N'Share of days in the window on which the subject was done.', 20),

    /*  Three days, not one. A single day is factually a run of one, but calling
        it a streak is the encouragement inflation this platform does not do -
        it would be the product congratulating her for opening the app. */
    ('streak_current', N'Current streak', 'habit', 'count', 'days', 3, 21,
     N'No streak yet.',
     N'Consecutive days up to and including today.', 30),

    ('streak_best', N'Best streak', 'habit', 'count', 'days', 7, 28,
     N'Not enough history for a best streak.',
     N'The longest run of consecutive days inside the window.', 40),

    /*  Also a count rather than an inference: the date of the last one is known
        the moment there is a last one. */
    ('days_since_last', N'Days since last', 'habit', 'days', 'days', 1, 14,
     N'Nothing logged yet.',
     N'Days since the subject was last done. A lapse, stated as a number.', 50),

    -- trend family ---------------------------------------------------------
    ('momentum', N'Momentum', 'trend', 'percent', 'pp', 14, 56,
     N'Not enough history to compare two periods.',
     N'Consistency in the recent half of the window minus the earlier half, '
     + N'in percentage points. Positive is improving, negative declining.', 60),

    -- rhythm family --------------------------------------------------------
    ('rhythm_weekday_best', N'Strongest day', 'rhythm', 'weekday', NULL, 14, 56,
     N'Not enough weeks to see a weekly rhythm.',
     N'The weekday with the highest completion rate.', 70),

    ('rhythm_weekday_worst', N'Hardest day', 'rhythm', 'weekday', NULL, 14, 56,
     N'Not enough weeks to see a weekly rhythm.',
     N'The weekday with the lowest completion rate.', 80),

    ('rhythm_month_best', N'Strongest part of the month', 'rhythm', 'count', NULL, 56, 112,
     N'Not enough months to see a monthly rhythm.',
     N'Which third of the month carries the highest completion rate: 1, 2 or 3.', 90),

    ('rhythm_season_best', N'Strongest season', 'rhythm', 'count', NULL, 180, 365,
     N'Not enough of a year to see a seasonal rhythm.',
     N'The calendar quarter with the highest completion rate.', 100),

    -- preference family ----------------------------------------------------
    ('preferred_hour', N'Usual time', 'preference', 'hour', 'hour', 7, 28,
     N'Not enough logged to see a usual time.',
     N'The hour of day she most often does this, in her local time.', 110),

    ('hardest_hour', N'Least likely time', 'preference', 'hour', 'hour', 14, 56,
     N'Not enough logged to see which times are hardest.',
     N'The waking hour she least often does this.', 120),

    -- probability family ---------------------------------------------------
    ('completion_probability', N'Chance of doing it tomorrow', 'probability', 'probability', NULL, 14, 56,
     N'Not enough history to estimate.',
     N'Observed completion rate, adjusted by recent momentum. Behavioural only '
     + N'- it says nothing about health.', 130),

    ('engagement_probability', N'Chance of logging next week', 'probability', 'probability', NULL, 14, 56,
     N'Not enough history to estimate.',
     N'Likelihood she keeps logging at all, from recency and consistency.', 140),

    ('dropoff_probability', N'Chance of stopping', 'probability', 'probability', NULL, 14, 56,
     N'Not enough history to estimate.',
     N'The complement of engagement. Surfaced separately because it is what a '
     + N'reminder is decided on.', 150)
) AS source (MeasureCode, DisplayName, Family, ValueKind, Unit,
             MinSpanDays, FullSpanDays, UnknownText, [Description], SortOrder)
    ON target.MeasureCode = source.MeasureCode
WHEN NOT MATCHED THEN
    INSERT (MeasureCode, DisplayName, Family, ValueKind, Unit,
            MinSpanDays, FullSpanDays, UnknownText, [Description], SortOrder)
    VALUES (source.MeasureCode, source.DisplayName, source.Family,
            source.ValueKind, source.Unit, source.MinSpanDays,
            source.FullSpanDays, source.UnknownText, source.[Description],
            source.SortOrder);
GO

/*  Seeds insert but never update, so an operator's edit survives redeployment.
    That leaves one case this script must handle itself: a database seeded
    before the counting measures were separated from the inferring ones would
    keep the old three-day gate, and a woman who joined this morning would get
    an empty screen on a platform that had already been corrected.

    Narrow on purpose - only these two codes, and only where the value is still
    the one this script originally shipped. An operator who deliberately raised
    the gate keeps their number. */
UPDATE [Behaviour].[MeasureType]
SET MinSpanDays = 1
WHERE MeasureCode IN ('days_active', 'days_since_last')
  AND MinSpanDays = 3;
GO

-- ---------------------------------------------------------------------------
-- Seed: subjects
-- ---------------------------------------------------------------------------
/*  Seeded only where a matching event type already exists, so this script
    cannot create a subject the timeline cannot feed. A subject with no events
    would produce observations from nothing, which is the one thing this whole
    design refuses to do. */
MERGE [Behaviour].[Subject] AS target
USING (VALUES
    ('hydration', N'Drinking water', 'event', 'hydration', 0, 1,
     N'How often you log water.', 10),
    ('sleep', N'Sleep', 'event', 'body', 0, 1,
     N'How often you log a night''s sleep.', 20),
    ('movement', N'Moving', 'event', 'fitness', 0, 1,
     N'How often you log movement of any kind.', 30),
    ('reflection', N'Checking in', 'event', 'mental', 0, 1,
     N'How often you check in with yourself.', 40),
    ('skincare', N'Skin care', 'event', 'beauty', 0, 1,
     N'How often you log looking after your skin.', 50),
    ('evening_routine', N'Evening wind-down', 'routine', 'lifestyle', 0, 2,
     N'How often you complete your evening wind-down.', 60)
) AS source (SubjectKey, DisplayName, SubjectKind, DomainCode,
             IsHealthSensitive, TargetPerDay, ObservationText, SortOrder)
    ON target.SubjectKey = source.SubjectKey
WHEN NOT MATCHED AND EXISTS (
        SELECT 1 FROM [Content].[LifeDomain] d
        WHERE d.DomainCode = source.DomainCode) THEN
    INSERT (SubjectKey, DisplayName, SubjectKind, DomainCode,
            IsHealthSensitive, TargetPerDay, ObservationText, SortOrder)
    VALUES (source.SubjectKey, source.DisplayName, source.SubjectKind,
            source.DomainCode, source.IsHealthSensitive, source.TargetPerDay,
            source.ObservationText, source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: subject composition
-- ---------------------------------------------------------------------------
/*  Only rows whose event type exists are inserted. A deployment where an event
    type has been renamed gets a subject with fewer parts and an honest lower
    confidence, rather than a foreign key error at deployment time or a routine
    that silently counts as done because its missing step was never checked. */
MERGE [Behaviour].[SubjectEvent] AS target
USING (VALUES
    ('hydration',       'water',       1, 10),
    ('sleep',           'sleep',       1, 10),
    /*  Three ways of moving, any of which counts. The subject is "did she
        move", not "did she use the app's step counter". */
    ('movement',        'walk',        1, 10),
    ('movement',        'steps',       1, 20),
    ('movement',        'exercise',    1, 30),
    ('reflection',      'mood',        1, 10),
    ('reflection',      'journal',     1, 20),
    ('skincare',        'skin_care',   1, 10),
    ('skincare',        'face_care',   1, 20),
    ('evening_routine', 'brush_teeth', 1, 10),
    ('evening_routine', 'skin_care',   1, 20),
    ('evening_routine', 'meditation',  0, 30)
) AS source (SubjectKey, EventTypeCode, IsRequired, SortOrder)
    ON target.SubjectKey = source.SubjectKey
   AND target.EventTypeCode = source.EventTypeCode
WHEN NOT MATCHED AND EXISTS (
        SELECT 1 FROM [Behaviour].[Subject] s
        WHERE s.SubjectKey = source.SubjectKey)
     AND EXISTS (
        SELECT 1 FROM [Timeline].[EventType] t
        WHERE t.EventTypeCode = source.EventTypeCode) THEN
    INSERT (SubjectKey, EventTypeCode, IsRequired, SortOrder)
    VALUES (source.SubjectKey, source.EventTypeCode, source.IsRequired,
            source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: which measures apply to which subject
-- ---------------------------------------------------------------------------
/*  Every active subject gets every active measure except the two hour-of-day
    preferences, which are withheld from subjects whose events are recorded
    once a day at a time the woman did not choose. Sleep is logged in the
    morning about the night before; "her usual time for sleep" would describe
    when she opens the app, not when she sleeps. */
INSERT [Behaviour].[SubjectMeasure] (SubjectKey, MeasureCode)
SELECT s.SubjectKey, m.MeasureCode
FROM [Behaviour].[Subject] s
CROSS JOIN [Behaviour].[MeasureType] m
WHERE s.IsActive = 1
  AND m.IsActive = 1
  AND NOT (m.Family = 'preference' AND s.SubjectKey IN ('sleep'))
  AND NOT EXISTS (
        SELECT 1 FROM [Behaviour].[SubjectMeasure] sm
        WHERE sm.SubjectKey = s.SubjectKey AND sm.MeasureCode = m.MeasureCode);
GO

PRINT 'Behaviour Intelligence schema ready.';
GO
