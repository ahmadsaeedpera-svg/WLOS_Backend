/*  41_Dashboard.sql

    The Adaptive Dashboard Engine: what a woman should see, when, and why.

    A dashboard is generated, never hardcoded
    -----------------------------------------
    Every card, its position, and the reason it is there are decided from data
    at request time. Nothing in this file names a screen, and no client is
    permitted to decide the order — a client that sorted cards itself would be
    a second copy of the priority rules, and the two would disagree within a
    release.

    The three tables
    ----------------
    CardType        what kinds of card exist, and how they behave
    CardRule        when a card is eligible at all
    PriorityAdjust  how a raised signal changes its urgency

    Eligibility is separate from priority on purpose. "May a pregnant woman see
    a kick counter" and "how urgent is it right now" are different questions
    with different answers, and collapsing them produces rules nobody can read
    six months later.

    Reusing the targeting vocabulary
    --------------------------------
    CardRule references Content.TargetingDimension - the same life_stage,
    role_mode, age, country, season and module dimensions the content engine
    uses. One vocabulary, not two. If a stage means something in content
    targeting it must mean the same thing on the dashboard, and two registries
    would drift apart the first time somebody added a dimension to one.

    The evaluation SQL is close to fn_TargetedItems but not shared, because the
    existing function is on the content serving path and refactoring it under a
    second caller is a change with its own risk. Folding both onto one generic
    evaluator is tracked as debt rather than smuggled in here.

    No magic numbers
    ----------------
    Base priorities, adjustments, lifetimes and refresh intervals are all
    columns. There is one convention rather than a constant: a card whose final
    priority falls to zero or below is not shown. That gives suppression -
    "a meeting in an hour hides long recommendations" - without a second
    mechanism to reason about.

    Idempotent. Purely additive.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = 'Dashboard')
    EXEC('CREATE SCHEMA [Dashboard]');
GO

-- ---------------------------------------------------------------------------
-- Card registry
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Dashboard.CardType') IS NULL
CREATE TABLE [Dashboard].[CardType] (
    CardTypeCode    VARCHAR(40)  NOT NULL,
    DisplayName     NVARCHAR(80) NOT NULL,

    /*  Which part of her life this belongs to. Lets an operator switch off a
        whole area, and gives the client a grouping it did not invent. */
    DomainCode      VARCHAR(30)  NOT NULL,

    /*  Where it sits before anything adapts it. Data, not a constant in code,
        because reordering the default dashboard is an editorial decision. */
    BasePriority    INT NOT NULL,

    /*  How long the client may keep showing it without asking again, and how
        long before it is stale. A medication card that is an hour old is
        misleading; a baby-development card is fine for a day. */
    RefreshSeconds  INT NOT NULL CONSTRAINT DF_CardType_Refresh DEFAULT 900,
    LifetimeSeconds INT NULL,

    /*  Whether she can dismiss it. A prompt, yes. An overdue medication
        reminder, no - dismissing it is a decision she should make in the
        medication screen, not by swiping. */
    IsDismissible   BIT NOT NULL CONSTRAINT DF_CardType_Dismissible DEFAULT 1,

    /*  Optional gate on the existing feature-flag system, so a card can be
        rolled out gradually or killed without a deploy. */
    FeatureFlagKey  VARCHAR(100) NULL,

    /*  Health-sensitive cards are never generated from an inference. They may
        reflect what she recorded and must never assert a finding. Carried as
        data so a later engine cannot forget by omission. */
    IsHealthSensitive BIT NOT NULL CONSTRAINT DF_CardType_HealthSensitive DEFAULT 0,

    IsActive        BIT NOT NULL CONSTRAINT DF_CardType_IsActive DEFAULT 1,

    CONSTRAINT PK_CardType PRIMARY KEY CLUSTERED (CardTypeCode),
    CONSTRAINT FK_CardType_Domain FOREIGN KEY (DomainCode)
        REFERENCES [Content].[LifeDomain](DomainCode),
    CONSTRAINT CK_CardType_BasePriority
        CHECK (BasePriority BETWEEN 0 AND 100),
    CONSTRAINT CK_CardType_Refresh
        CHECK (RefreshSeconds BETWEEN 30 AND 86400),
    CONSTRAINT CK_CardType_Lifetime
        CHECK (LifetimeSeconds IS NULL OR LifetimeSeconds BETWEEN 60 AND 604800)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_CardType_Domain'
                 AND object_id = OBJECT_ID('[Dashboard].[CardType]'))
    CREATE INDEX [IX_CardType_Domain] ON [Dashboard].[CardType] (DomainCode);
GO

-- ---------------------------------------------------------------------------
-- Eligibility
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Dashboard.CardRule') IS NULL
CREATE TABLE [Dashboard].[CardRule] (
    CardRuleId    UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT DF_CardRule_Id DEFAULT NEWSEQUENTIALID(),
    CardTypeCode  VARCHAR(40) NOT NULL,
    DimensionCode VARCHAR(30) NOT NULL,
    [Operator]    VARCHAR(10) NOT NULL,
    ValuesJson    NVARCHAR(2000) NOT NULL,

    /*  Why this rule exists, in words an operator can read in the portal. The
        engine echoes it back as part of the card's reason, so an unexplained
        card is impossible to configure by construction. */
    RuleNote      NVARCHAR(200) NOT NULL,

    CreatedOn     DATETIME2(3) NOT NULL
        CONSTRAINT DF_CardRule_CreatedOn DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_CardRule PRIMARY KEY CLUSTERED (CardRuleId),
    CONSTRAINT FK_CardRule_CardType FOREIGN KEY (CardTypeCode)
        REFERENCES [Dashboard].[CardType](CardTypeCode) ON DELETE CASCADE,
    CONSTRAINT FK_CardRule_Dimension FOREIGN KEY (DimensionCode)
        REFERENCES [Content].[TargetingDimension](DimensionCode),
    CONSTRAINT CK_CardRule_Operator
        CHECK ([Operator] IN ('in', 'not_in', 'between')),
    CONSTRAINT CK_CardRule_ValuesJson CHECK (ISJSON(ValuesJson) = 1)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_CardRule_CardType'
                 AND object_id = OBJECT_ID('[Dashboard].[CardRule]'))
    CREATE INDEX [IX_CardRule_CardType]
        ON [Dashboard].[CardRule] (CardTypeCode)
        INCLUDE (DimensionCode, [Operator], ValuesJson);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_CardRule_Dimension'
                 AND object_id = OBJECT_ID('[Dashboard].[CardRule]'))
    CREATE INDEX [IX_CardRule_Dimension] ON [Dashboard].[CardRule] (DimensionCode);
GO

-- ---------------------------------------------------------------------------
-- Priority adjustment
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Dashboard.PriorityAdjustment') IS NULL
CREATE TABLE [Dashboard].[PriorityAdjustment] (
    PriorityAdjustmentId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT DF_PriorityAdjustment_Id DEFAULT NEWSEQUENTIALID(),
    CardTypeCode   VARCHAR(40) NOT NULL,

    /*  The observation that moves this card. Signals come from the knowledge
        graph and are deterministic - short sleep, low hydration, long working
        days - so an adjustment is explainable rather than inferred. */
    SignalCode     VARCHAR(40) NOT NULL,

    /*  'add' shifts the base priority. 'set' overrides it outright, for the
        cases where nothing else should outrank the card - an overdue
        medication is not "a bit more important than hydration". */
    AdjustmentKind VARCHAR(5) NOT NULL,

    /*  Negative values are how suppression works. A card driven below zero is
        not shown, which is what "a meeting in an hour hides long
        recommendations" means in practice. */
    Amount         INT NOT NULL,

    /*  Shown to her, and to the operator configuring it. Written from her side
        of the screen: "You have been sleeping less than usual" rather than
        "signal short_sleep raised". */
    ReasonText     NVARCHAR(200) NOT NULL,

    /*  How much weight to put on this. Rule-driven adjustments are
        deterministic so the default is full confidence; the column exists
        because a later engine will have adjustments that are not. */
    Confidence     DECIMAL(3,2) NOT NULL
        CONSTRAINT DF_PriorityAdjustment_Confidence DEFAULT 1.00,

    IsActive       BIT NOT NULL CONSTRAINT DF_PriorityAdjustment_IsActive DEFAULT 1,

    CONSTRAINT PK_PriorityAdjustment PRIMARY KEY CLUSTERED (PriorityAdjustmentId),
    CONSTRAINT FK_PriorityAdjustment_CardType FOREIGN KEY (CardTypeCode)
        REFERENCES [Dashboard].[CardType](CardTypeCode) ON DELETE CASCADE,
    CONSTRAINT FK_PriorityAdjustment_Signal FOREIGN KEY (SignalCode)
        REFERENCES [Knowledge].[Signal](SignalCode),
    CONSTRAINT CK_PriorityAdjustment_Kind
        CHECK (AdjustmentKind IN ('add', 'set')),
    CONSTRAINT CK_PriorityAdjustment_Amount
        CHECK (Amount BETWEEN -100 AND 100),
    CONSTRAINT CK_PriorityAdjustment_Confidence
        CHECK (Confidence > 0 AND Confidence <= 1),
    CONSTRAINT UQ_PriorityAdjustment
        UNIQUE (CardTypeCode, SignalCode)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_PriorityAdjustment_Signal'
                 AND object_id = OBJECT_ID('[Dashboard].[PriorityAdjustment]'))
    CREATE INDEX [IX_PriorityAdjustment_Signal]
        ON [Dashboard].[PriorityAdjustment] (SignalCode);
GO

-- ---------------------------------------------------------------------------
-- Seed: the cards
-- ---------------------------------------------------------------------------

/*  Base priorities are spaced so an adjustment can move a card past its
    neighbour without needing every value renumbered. */
MERGE [Dashboard].[CardType] AS target
USING (VALUES
    -- always-relevant
    ('today_focus',       N'Today',                'lifestyle',    70,  900,  0, 0),
    ('hydration_prompt',  N'Water',                'hydration',    40,  900,  1, 0),
    ('sleep_summary',     N'Last night',           'sleep',        45, 3600,  1, 0),
    ('move_prompt',       N'Move a little',        'fitness',      35, 3600,  1, 0),
    ('relaxation',        N'Take a moment',        'mental',       30, 3600,  1, 0),
    -- health, never inferred
    ('medication_due',    N'Medication',           'medication',   80,  300,  0, 1),
    ('appointment_next',  N'Next appointment',     'health',       75, 1800,  1, 1),
    ('symptom_log',       N'How are you feeling',  'health',       25, 3600,  1, 1),
    ('cycle_log',         N'Your cycle',           'cycle',        40, 3600,  1, 1),
    -- pregnancy
    ('baby_development',  N'Your baby this week',  'pregnancy',    60, 86400, 1, 1),
    ('kick_counter',      N'Movements',            'pregnancy',    55, 1800,  1, 1),
    -- life
    ('checklist_today',   N'Your list',            'household',    50, 1800,  1, 0),
    ('study_focus',       N'Study',                'learning',     55, 1800,  1, 0),
    ('exam_countdown',    N'Exam',                 'learning',     65, 86400, 1, 0),
    ('work_break',        N'Take a break',         'work',         30, 1800,  1, 0),
    ('family_call',       N'Keep in touch',        'family',       25, 86400, 1, 0),
    ('learning_nudge',    N'Something to read',    'learning',     20, 86400, 1, 0)
) AS source (CardTypeCode, DisplayName, DomainCode, BasePriority,
             RefreshSeconds, IsDismissible, IsHealthSensitive)
    ON target.CardTypeCode = source.CardTypeCode
WHEN NOT MATCHED THEN
    INSERT (CardTypeCode, DisplayName, DomainCode, BasePriority,
            RefreshSeconds, IsDismissible, IsHealthSensitive)
    VALUES (source.CardTypeCode, source.DisplayName, source.DomainCode,
            source.BasePriority, source.RefreshSeconds, source.IsDismissible,
            source.IsHealthSensitive);
GO

-- ---------------------------------------------------------------------------
-- Seed: eligibility
-- ---------------------------------------------------------------------------

/*  A card with no rules is eligible for everyone. That is the default on
    purpose: most cards are universal, and requiring a rule for each would mean
    a new card reaches nobody until somebody remembers to write one. */
MERGE [Dashboard].[CardRule] AS target
USING (VALUES
    ('baby_development', 'life_stage', 'in', N'["pregnancy"]',
     N'Only while she is pregnant.'),
    ('kick_counter',     'life_stage', 'in', N'["pregnancy"]',
     N'Only while she is pregnant.'),
    ('cycle_log',        'life_stage', 'not_in', N'["pregnancy","menopause","senior"]',
     N'Not during pregnancy, and not after menopause.'),
    ('study_focus',      'role_mode',  'in', N'["student"]',
     N'For women who are studying.'),
    ('exam_countdown',   'role_mode',  'in', N'["student"]',
     N'For women who are studying.'),
    ('work_break',       'role_mode',  'in', N'["professional","remote_worker","freelancer","entrepreneur"]',
     N'For women who are working.'),
    ('checklist_today',  'role_mode',  'in', N'["homemaker","caregiver"]',
     N'For women running a home or caring for someone.'),
    ('family_call',      'life_stage', 'in', N'["senior","menopause","midlife"]',
     N'Offered later in life, when staying connected matters more.')
) AS source (CardTypeCode, DimensionCode, [Operator], ValuesJson, RuleNote)
    ON target.CardTypeCode = source.CardTypeCode
   AND target.DimensionCode = source.DimensionCode
WHEN NOT MATCHED THEN
    INSERT (CardTypeCode, DimensionCode, [Operator], ValuesJson, RuleNote)
    VALUES (source.CardTypeCode, source.DimensionCode, source.[Operator],
            source.ValuesJson, source.RuleNote);
GO

-- ---------------------------------------------------------------------------
-- Seed: how signals move cards
-- ---------------------------------------------------------------------------

/*  The adaptive behaviour the product describes, expressed as data. Poor sleep
    raising hydration is a row here, not a branch in code. */
MERGE [Dashboard].[PriorityAdjustment] AS target
USING (VALUES
    ('hydration_prompt', 'low_hydration',    'add',  35,
     N'You have been drinking less water than usual.'),
    ('hydration_prompt', 'short_sleep',      'add',  15,
     N'Short nights often go with drinking less during the day.'),
    ('sleep_summary',    'short_sleep',      'add',  30,
     N'You have been sleeping less than you usually do.'),
    ('relaxation',       'high_stress',      'add',  40,
     N'You have been recording higher stress than usual.'),
    ('relaxation',       'low_mood',         'add',  30,
     N'Your mood has been lower over the last few days.'),
    ('move_prompt',      'low_activity',     'add',  30,
     N'You have been moving less than usual.'),
    ('work_break',       'long_work',        'add',  35,
     N'You have been recording long working days.'),
    /*  Suppression. On a long working day a reading nudge is noise, so it is
        pushed below zero and simply not returned. */
    ('learning_nudge',   'long_work',        'add', -40,
     N'Set aside on the days you are working long hours.'),
    ('sleep_summary',    'high_screen_time', 'add',  20,
     N'Your screen time has been higher than usual.')
) AS source (CardTypeCode, SignalCode, AdjustmentKind, Amount, ReasonText)
    ON target.CardTypeCode = source.CardTypeCode
   AND target.SignalCode = source.SignalCode
WHEN NOT MATCHED THEN
    INSERT (CardTypeCode, SignalCode, AdjustmentKind, Amount, ReasonText)
    VALUES (source.CardTypeCode, source.SignalCode, source.AdjustmentKind,
            source.Amount, source.ReasonText);
GO
