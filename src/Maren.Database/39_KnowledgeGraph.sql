/*  39_KnowledgeGraph.sql

    The knowledge graph: observable signals and how they tend to relate.

    Read the safety section before changing anything here
    ----------------------------------------------------
    This is the most dangerous structure in the platform so far, because it
    looks exactly like clinical reasoning and must never become it.

    A graph that says "poor sleep causes headaches" has diagnosed something. A
    graph that says "poor sleep and headaches are commonly reported together"
    has organised an observation and left the conclusion to her and her doctor.
    The distance between those two sentences is the distance between a wellness
    product and a regulated medical device, and it is one careless verb wide.

    So the vocabulary is constrained in the schema, not in a comment:

        commonly_precedes  - tends to be recorded before
        commonly_co_occurs - tends to be recorded on the same day
        may_relate_to      - a weaker, undirected association

    There is no 'causes'. There is no 'leads_to'. There is no 'results_in'. The
    CHECK constraint refuses them and knowledge_graph_test.sql asserts the
    vocabulary has not grown a causal verb, because that is exactly the kind of
    change that arrives in a hurry and looks harmless in review.

    Every edge must also carry a SourceNote. An edge nobody can justify is an
    opinion the platform is presenting as knowledge, and requiring the field
    makes that visible at authoring time rather than in a complaint.

    Health-sensitive signals
    ------------------------
    Some signals are self-reported health observations - a headache, a symptom.
    Those are flagged, and the flag exists so later engines cannot forget: a
    health-sensitive signal may be shown back to her as something she recorded,
    and may never be used to generate advice or a score. The recommendation
    engine will assert that rule; this is where it gets the data to do it.

    Thresholds
    ----------
    Signal rules are deterministic and read the timeline. They deliberately
    cover wellness quantities only - sleep duration, water, activity, screen
    time - and never a clinical measure. "She recorded less water than the
    amount she set as her target" is descriptive. "Her blood pressure is high"
    would not be, and no rule here is permitted to say it.

    Idempotent. Purely additive.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = 'Knowledge')
    EXEC('CREATE SCHEMA [Knowledge]');
GO

-- ---------------------------------------------------------------------------
-- Signals: the observable states the platform can recognise
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Knowledge.Signal') IS NULL
CREATE TABLE [Knowledge].[Signal] (
    SignalCode      VARCHAR(40)  NOT NULL,
    DisplayName     NVARCHAR(80) NOT NULL,

    /*  Which part of her life this belongs to. Ties the graph to the same
        vocabulary the timeline and the dashboard use. */
    DomainCode      VARCHAR(30)  NOT NULL,

    /*  Phrased as she would see it. "You've been sleeping less than usual",
        never "you have insomnia". The copy is data because it has to be
        localised and, more importantly, because it has to be reviewable by
        somebody who is not reading SQL. */
    ObservationText NVARCHAR(300) NOT NULL,

    /*  A self-reported health observation. May be reflected back to her; may
        never drive advice or a score. */
    IsHealthSensitive BIT NOT NULL
        CONSTRAINT DF_Signal_IsHealthSensitive DEFAULT 0,

    IsActive        BIT NOT NULL CONSTRAINT DF_Signal_IsActive DEFAULT 1,
    SortOrder       INT NOT NULL,

    CONSTRAINT PK_Signal PRIMARY KEY CLUSTERED (SignalCode),
    CONSTRAINT FK_Signal_Domain FOREIGN KEY (DomainCode)
        REFERENCES [Content].[LifeDomain](DomainCode)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Signal_Domain'
                 AND object_id = OBJECT_ID('[Knowledge].[Signal]'))
    CREATE INDEX [IX_Signal_Domain] ON [Knowledge].[Signal] (DomainCode);
GO

-- ---------------------------------------------------------------------------
-- Rules: how a signal is detected from the timeline
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Knowledge.SignalRule') IS NULL
CREATE TABLE [Knowledge].[SignalRule] (
    SignalRuleId  UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT DF_SignalRule_Id DEFAULT NEWSEQUENTIALID(),
    SignalCode    VARCHAR(40) NOT NULL,

    /*  What to measure, using the timeline's own aggregation so a signal and a
        score can never disagree about what a day's water was. */
    EventTypeCode VARCHAR(40) NOT NULL,

    /*  'lt' | 'lte' | 'gt' | 'gte'. Deliberately no equality: these are
        thresholds on continuous quantities, and equality on a decimal is a
        rule that fires almost never and confuses everyone when it does. */
    Comparator    VARCHAR(4) NOT NULL,
    Threshold     DECIMAL(18,4) NOT NULL,

    /*  How many days the aggregate covers. 1 is "today". */
    WindowDays    INT NOT NULL CONSTRAINT DF_SignalRule_WindowDays DEFAULT 1,

    /*  How many days within the window must breach the threshold before the
        signal is raised. Stops a single unusual day from being treated as a
        pattern, which is the difference between an observation and a nag. */
    MinBreachDays INT NOT NULL CONSTRAINT DF_SignalRule_MinBreachDays DEFAULT 1,

    IsActive      BIT NOT NULL CONSTRAINT DF_SignalRule_IsActive DEFAULT 1,

    CONSTRAINT PK_SignalRule PRIMARY KEY CLUSTERED (SignalRuleId),
    CONSTRAINT FK_SignalRule_Signal FOREIGN KEY (SignalCode)
        REFERENCES [Knowledge].[Signal](SignalCode),
    CONSTRAINT FK_SignalRule_EventType FOREIGN KEY (EventTypeCode)
        REFERENCES [Timeline].[EventType](EventTypeCode),
    CONSTRAINT CK_SignalRule_Comparator
        CHECK (Comparator IN ('lt', 'lte', 'gt', 'gte')),
    CONSTRAINT CK_SignalRule_Window
        CHECK (WindowDays BETWEEN 1 AND 90 AND MinBreachDays BETWEEN 1 AND WindowDays)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_SignalRule_Signal'
                 AND object_id = OBJECT_ID('[Knowledge].[SignalRule]'))
    CREATE INDEX [IX_SignalRule_Signal] ON [Knowledge].[SignalRule] (SignalCode);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_SignalRule_EventType'
                 AND object_id = OBJECT_ID('[Knowledge].[SignalRule]'))
    CREATE INDEX [IX_SignalRule_EventType] ON [Knowledge].[SignalRule] (EventTypeCode);
GO

-- ---------------------------------------------------------------------------
-- Relations: the edges
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Knowledge.SignalRelation') IS NULL
CREATE TABLE [Knowledge].[SignalRelation] (
    SignalRelationId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT DF_SignalRelation_Id DEFAULT NEWSEQUENTIALID(),
    FromSignalCode   VARCHAR(40) NOT NULL,
    ToSignalCode     VARCHAR(40) NOT NULL,

    /*  Observational only. See the header - there is no causal verb here and
        adding one is a product and regulatory decision, not a schema tweak. */
    RelationKind     VARCHAR(20) NOT NULL,

    /*  0 to 1. How consistently this is reported, not how certain we are that
        one produces the other. Used to order what she is shown, never to
        assert confidence in a mechanism. */
    Strength         DECIMAL(3,2) NOT NULL,

    /*  Required. An edge nobody can justify is an opinion being presented as
        knowledge. NOT NULL makes that a decision somebody has to make at
        authoring time. */
    SourceNote       NVARCHAR(300) NOT NULL,

    IsActive         BIT NOT NULL CONSTRAINT DF_SignalRelation_IsActive DEFAULT 1,

    CONSTRAINT PK_SignalRelation PRIMARY KEY CLUSTERED (SignalRelationId),
    CONSTRAINT FK_SignalRelation_From FOREIGN KEY (FromSignalCode)
        REFERENCES [Knowledge].[Signal](SignalCode),
    CONSTRAINT FK_SignalRelation_To FOREIGN KEY (ToSignalCode)
        REFERENCES [Knowledge].[Signal](SignalCode),
    CONSTRAINT CK_SignalRelation_Kind
        CHECK (RelationKind IN ('commonly_precedes', 'commonly_co_occurs', 'may_relate_to')),
    CONSTRAINT CK_SignalRelation_Strength
        CHECK (Strength > 0 AND Strength <= 1),
    /*  A signal relating to itself is noise in every traversal. */
    CONSTRAINT CK_SignalRelation_NotSelf
        CHECK (FromSignalCode <> ToSignalCode),
    CONSTRAINT UQ_SignalRelation
        UNIQUE (FromSignalCode, ToSignalCode, RelationKind)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_SignalRelation_From'
                 AND object_id = OBJECT_ID('[Knowledge].[SignalRelation]'))
    CREATE INDEX [IX_SignalRelation_From]
        ON [Knowledge].[SignalRelation] (FromSignalCode) INCLUDE (ToSignalCode, Strength);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_SignalRelation_To'
                 AND object_id = OBJECT_ID('[Knowledge].[SignalRelation]'))
    CREATE INDEX [IX_SignalRelation_To]
        ON [Knowledge].[SignalRelation] (ToSignalCode);
GO

-- ---------------------------------------------------------------------------
-- Seed: signals
-- ---------------------------------------------------------------------------

MERGE [Knowledge].[Signal] AS target
USING (VALUES
    ('short_sleep',      N'Sleeping less',     'sleep',        N'You have been sleeping less than you usually do.',        0, 10),
    ('late_wake',        N'Waking later',      'sleep',        N'You have been waking up later than usual.',               0, 20),
    ('high_stress',      N'Feeling stretched', 'mental',       N'You have been recording higher stress than usual.',       0, 30),
    ('low_mood',         N'Lower mood',        'mental',       N'You have recorded a lower mood over the last few days.',  0, 40),
    ('low_hydration',    N'Drinking less',     'hydration',    N'You have been drinking less water than your target.',     0, 50),
    ('missed_breakfast', N'Skipping breakfast','nutrition',    N'Breakfast has not been recorded on several days.',        0, 60),
    ('low_activity',     N'Moving less',       'fitness',      N'You have been moving less than usual.',                   0, 70),
    ('high_screen_time', N'More screen time',  'lifestyle',    N'Your screen time has been higher than usual.',            0, 80),
    ('long_work',        N'Long working days', 'work',         N'You have been recording long working days.',              0, 90),
    ('low_selfcare',     N'Less time for you', 'selfcare',     N'You have recorded fewer self-care moments than usual.',   0, 100),
    /*  Health-sensitive: reflected back, never used to generate advice. */
    ('headache',         N'Headaches',         'health',       N'You have recorded headaches on several days.',            1, 110),
    ('symptom_reported', N'Symptoms recorded', 'health',       N'You have recorded symptoms recently.',                    1, 120)
) AS source (SignalCode, DisplayName, DomainCode, ObservationText, IsHealthSensitive, SortOrder)
    ON target.SignalCode = source.SignalCode
WHEN NOT MATCHED THEN
    INSERT (SignalCode, DisplayName, DomainCode, ObservationText, IsHealthSensitive, SortOrder)
    VALUES (source.SignalCode, source.DisplayName, source.DomainCode,
            source.ObservationText, source.IsHealthSensitive, source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: detection rules
-- ---------------------------------------------------------------------------

/*  Wellness quantities only. Not every signal has a rule - some are recorded
    directly by her - and a signal without a rule is still a valid node in the
    graph, it simply is not detected automatically. */
MERGE [Knowledge].[SignalRule] AS target
USING (VALUES
    ('short_sleep',      'sleep',       'lt',  360.0, 3, 2),   -- under 6h on 2 of 3 days
    ('low_hydration',    'water',       'lt', 1500.0, 3, 2),   -- under 1.5L on 2 of 3 days
    ('high_stress',      'stress',      'gte',   4.0, 3, 2),   -- 4+ on the 1-5 scale
    ('low_mood',         'mood',        'lte',   2.0, 3, 2),
    ('low_activity',     'steps',       'lt', 3000.0, 3, 2),
    ('high_screen_time', 'screen_time', 'gt',  300.0, 3, 2),   -- over 5h
    ('long_work',        'work',        'gt',  600.0, 3, 2)    -- over 10h
) AS source (SignalCode, EventTypeCode, Comparator, Threshold, WindowDays, MinBreachDays)
    ON target.SignalCode = source.SignalCode
   AND target.EventTypeCode = source.EventTypeCode
WHEN NOT MATCHED THEN
    INSERT (SignalCode, EventTypeCode, Comparator, Threshold, WindowDays, MinBreachDays)
    VALUES (source.SignalCode, source.EventTypeCode, source.Comparator,
            source.Threshold, source.WindowDays, source.MinBreachDays);
GO

-- ---------------------------------------------------------------------------
-- Seed: relations
-- ---------------------------------------------------------------------------

/*  The chain the product describes, expressed observationally. Read it as
    "these tend to be reported together or in this order", never as a
    mechanism. Every SourceNote says where the claim comes from, and "widely
    reported" is an honest note - it is not a citation and does not pretend to
    be one. Clinical review before any of this is shown to a woman is tracked
    as a release blocker, not assumed done. */
MERGE [Knowledge].[SignalRelation] AS target
USING (VALUES
    ('short_sleep',      'late_wake',        'commonly_precedes',  0.60, N'Widely reported pattern; not clinically reviewed.'),
    ('short_sleep',      'high_stress',      'commonly_co_occurs', 0.55, N'Widely reported pattern; not clinically reviewed.'),
    ('short_sleep',      'low_activity',     'commonly_precedes',  0.45, N'Widely reported pattern; not clinically reviewed.'),
    ('late_wake',        'missed_breakfast', 'commonly_precedes',  0.65, N'Widely reported pattern; not clinically reviewed.'),
    ('missed_breakfast', 'low_hydration',    'commonly_co_occurs', 0.40, N'Widely reported pattern; not clinically reviewed.'),
    ('high_stress',      'low_mood',         'commonly_co_occurs', 0.60, N'Widely reported pattern; not clinically reviewed.'),
    ('high_stress',      'short_sleep',      'commonly_precedes',  0.55, N'Reported in both directions; see the reverse edge.'),
    ('long_work',        'high_stress',      'commonly_precedes',  0.50, N'Widely reported pattern; not clinically reviewed.'),
    ('long_work',        'low_selfcare',     'commonly_co_occurs', 0.55, N'Widely reported pattern; not clinically reviewed.'),
    ('high_screen_time', 'short_sleep',      'commonly_precedes',  0.45, N'Widely reported pattern; not clinically reviewed.'),
    ('low_hydration',    'headache',         'may_relate_to',      0.35, N'Self-reported association only. Never presented as a cause.'),
    ('short_sleep',      'headache',         'may_relate_to',      0.35, N'Self-reported association only. Never presented as a cause.'),
    ('low_activity',     'low_mood',         'may_relate_to',      0.40, N'Widely reported pattern; not clinically reviewed.')
) AS source (FromSignalCode, ToSignalCode, RelationKind, Strength, SourceNote)
    ON target.FromSignalCode = source.FromSignalCode
   AND target.ToSignalCode = source.ToSignalCode
   AND target.RelationKind = source.RelationKind
WHEN NOT MATCHED THEN
    INSERT (FromSignalCode, ToSignalCode, RelationKind, Strength, SourceNote)
    VALUES (source.FromSignalCode, source.ToSignalCode, source.RelationKind,
            source.Strength, source.SourceNote);
GO
