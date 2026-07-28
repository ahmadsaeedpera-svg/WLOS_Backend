/*  52_Growth_Goals.sql

    The Personal Growth Platform: goals.

    A goal is a desired outcome. It is not a reminder, not a habit and not a
    routine - those are things she does; a goal is what she is trying to reach
    by doing them. The distinction matters structurally: a habit is observed, a
    goal is chosen, and progress towards a goal is the relationship between the
    two.

    Where progress comes from
    -------------------------
    Behaviour Intelligence, and nowhere else. A goal declares which behavioural
    measures it depends on and what value counts as reaching it; progress is the
    weighted distance between what Behaviour observed and those targets. There
    is no manual percentage, no self-reported completion and no second
    calculation of consistency or streaks.

    That is enforced rather than intended: behaviour_test.sql fails if any
    schema outside Behaviour touches the observation store, so this schema reads
    through Behaviour.fn_Read - the published consumption interface - and could
    not recompute a streak even if somebody tried.

    Where applicability comes from
    ------------------------------
    Rules.fn_Match, the platform's one matcher, under a new 'goalTemplate'
    scope. A goal that only makes sense in pregnancy, or only for a woman who
    works, is a rule row like every other targeting decision in the platform. A
    second applicability mechanism here would be the third place life stage is
    interpreted, and the three would drift.

    What a goal is not
    ------------------
    Not clinical. A goal describes something she wants to do more or less of,
    measured by what she logs. No goal describes a health outcome, and none
    claims that reaching it will cause one.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('Growth') IS NULL
    EXEC('CREATE SCHEMA [Growth]');
GO

-- ---------------------------------------------------------------------------
-- The goal library
-- ---------------------------------------------------------------------------
/*  Templates rather than free-text goals, for the reason the dashboard card
    registry exists: a goal has to be measurable by something the platform
    already observes, and a woman typing "be healthier" gives the engine nothing
    to measure. She chooses from what can actually be tracked, and adds her own
    reason for choosing it.

    Operators manage this library as configuration. Adding "read before bed" is
    a row, not a release. */
IF OBJECT_ID('Growth.GoalTemplate') IS NULL
BEGIN
    CREATE TABLE [Growth].[GoalTemplate] (
        GoalTemplateKey VARCHAR(40)  NOT NULL,
        DisplayName     NVARCHAR(80) NOT NULL,

        /*  Why the goal exists, in the platform's words. Distinct from her
            motivation, which is hers and lives on the adopted goal. */
        PurposeText     NVARCHAR(300) NOT NULL,

        DomainCode      VARCHAR(30)  NOT NULL,

        /*  Where it sits when several goals compete for one screen. A starting
            point: her own priority on the adopted goal overrides it. */
        BasePriority    INT NOT NULL CONSTRAINT DF_GoalTemplate_BasePriority DEFAULT 50,

        /*  How long this usually takes, for setting expectations rather than
            for enforcing anything. Nullable: some goals are ongoing. */
        ExpectedDurationDays INT NULL,

        IsHealthSensitive BIT NOT NULL
            CONSTRAINT DF_GoalTemplate_IsHealthSensitive DEFAULT 0,

        /*  What she is asked when adopting it. Her answer is the single most
            useful thing the coach will ever have, because it is the only part
            of a goal the platform cannot observe. */
        MotivationPrompt NVARCHAR(200) NOT NULL,

        /*  The observational basis for explaining the goal. Describes what is
            measured and over what period - never what it will do for her body,
            which would be a claim this platform does not make. */
        ExplanationText NVARCHAR(600) NOT NULL,

        SortOrder       INT NOT NULL,
        IsActive        BIT NOT NULL CONSTRAINT DF_GoalTemplate_IsActive DEFAULT 1,

        CONSTRAINT PK_GoalTemplate PRIMARY KEY CLUSTERED (GoalTemplateKey),

        CONSTRAINT CK_GoalTemplate_Priority CHECK (BasePriority BETWEEN 0 AND 100),
        CONSTRAINT CK_GoalTemplate_Duration
            CHECK (ExpectedDurationDays IS NULL OR ExpectedDurationDays > 0),

        CONSTRAINT FK_GoalTemplate_Domain FOREIGN KEY (DomainCode)
            REFERENCES [Content].[LifeDomain] (DomainCode)
    );

    CREATE INDEX IX_GoalTemplate_Domain
        ON [Growth].[GoalTemplate] (DomainCode) INCLUDE (DisplayName, SortOrder);
END
GO

-- ---------------------------------------------------------------------------
-- Behaviour dependencies — the progress and completion rule, as data
-- ---------------------------------------------------------------------------
/*  Both the progress calculation and the completion rule, expressed once.

    A goal is reached when every one of its measures meets its target. Progress
    is how far the observed values have travelled towards them, weighted. Two
    separate definitions - one for "how far along" and one for "is it done" -
    would eventually disagree, and the woman would see 100% next to "not yet
    achieved".

    SubjectKey and MeasureCode are foreign keys into Behaviour, so a goal cannot
    depend on something the platform does not observe. That is the join that
    makes "goals consume Behaviour Intelligence" structural rather than a
    convention. */
IF OBJECT_ID('Growth.GoalMeasure') IS NULL
BEGIN
    CREATE TABLE [Growth].[GoalMeasure] (
        GoalTemplateKey VARCHAR(40) NOT NULL,
        SubjectKey      VARCHAR(40) NOT NULL,
        MeasureCode     VARCHAR(30) NOT NULL,

        /*  gte: reach at least the target - consistency, streaks.
            lte: stay at or below it - days since last, drop-off risk. */
        Comparison      VARCHAR(3)  NOT NULL,
        TargetValue     DECIMAL(9, 4) NOT NULL,

        /*  Relative importance within the goal. A goal whose main measure is
            consistency and whose secondary one is streak length should not
            report half-done because the streak is young. */
        Weight          INT NOT NULL CONSTRAINT DF_GoalMeasure_Weight DEFAULT 1,

        /*  Shown when this measure is what is holding the goal back. */
        TargetText      NVARCHAR(200) NOT NULL,

        CONSTRAINT PK_GoalMeasure PRIMARY KEY CLUSTERED
            (GoalTemplateKey, SubjectKey, MeasureCode),

        CONSTRAINT CK_GoalMeasure_Comparison CHECK (Comparison IN ('gte', 'lte')),
        CONSTRAINT CK_GoalMeasure_Weight CHECK (Weight BETWEEN 1 AND 100),

        CONSTRAINT FK_GoalMeasure_Template FOREIGN KEY (GoalTemplateKey)
            REFERENCES [Growth].[GoalTemplate] (GoalTemplateKey) ON DELETE CASCADE,

        CONSTRAINT FK_GoalMeasure_Subject FOREIGN KEY (SubjectKey)
            REFERENCES [Behaviour].[Subject] (SubjectKey),

        CONSTRAINT FK_GoalMeasure_Measure FOREIGN KEY (MeasureCode)
            REFERENCES [Behaviour].[MeasureType] (MeasureCode)
    );

    CREATE INDEX IX_GoalMeasure_Subject
        ON [Growth].[GoalMeasure] (SubjectKey) INCLUDE (GoalTemplateKey);
    CREATE INDEX IX_GoalMeasure_Measure
        ON [Growth].[GoalMeasure] (MeasureCode) INCLUDE (GoalTemplateKey);
END
GO

-- ---------------------------------------------------------------------------
-- Knowledge references
-- ---------------------------------------------------------------------------
/*  Which observations from the knowledge graph relate to this goal.

    References, not causes. The knowledge graph carries no causal verb and a
    test fails if one appears; the same holds here. "Women working towards this
    goal often also log short sleep" is an observation. "Poor sleep prevents
    this goal" is a claim about her body, and the platform does not make it. */
IF OBJECT_ID('Growth.GoalKnowledge') IS NULL
BEGIN
    CREATE TABLE [Growth].[GoalKnowledge] (
        GoalTemplateKey VARCHAR(40) NOT NULL,
        SignalCode      VARCHAR(40) NOT NULL,

        /*  Observational wording, shown beside the goal. */
        RelationText    NVARCHAR(200) NOT NULL,
        SortOrder       INT NOT NULL CONSTRAINT DF_GoalKnowledge_SortOrder DEFAULT 0,

        CONSTRAINT PK_GoalKnowledge PRIMARY KEY CLUSTERED
            (GoalTemplateKey, SignalCode),

        CONSTRAINT FK_GoalKnowledge_Template FOREIGN KEY (GoalTemplateKey)
            REFERENCES [Growth].[GoalTemplate] (GoalTemplateKey) ON DELETE CASCADE,

        CONSTRAINT FK_GoalKnowledge_Signal FOREIGN KEY (SignalCode)
            REFERENCES [Knowledge].[Signal] (SignalCode)
    );

    CREATE INDEX IX_GoalKnowledge_Signal
        ON [Growth].[GoalKnowledge] (SignalCode) INCLUDE (GoalTemplateKey);
END
GO

-- ---------------------------------------------------------------------------
-- A goal she has actually taken on
-- ---------------------------------------------------------------------------
/*  The template is what the platform offers. This is what she chose, and why.

    MotivationText is hers, in her words, and is the only part of a goal the
    platform cannot observe. It is also the part that matters most when the
    coach explains why a recommendation exists - "you said you wanted to sleep
    better before the baby comes" is her reason, not the platform's. */
IF OBJECT_ID('Growth.UserGoal') IS NULL
BEGIN
    CREATE TABLE [Growth].[UserGoal] (
        UserGoalId      UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_UserGoal_Id DEFAULT NEWID(),
        UserId          UNIQUEIDENTIFIER NOT NULL,
        GoalTemplateKey VARCHAR(40) NOT NULL,

        /*  active, achieved, paused, abandoned. Kept rather than deleted:
            "you did this before" is the most encouraging thing the platform can
            say to somebody starting again, and a deleted row cannot say it. */
        [Status]        VARCHAR(12) NOT NULL
            CONSTRAINT DF_UserGoal_Status DEFAULT 'active',

        MotivationText  NVARCHAR(300) NULL,

        /*  Hers, overriding the template's. */
        Priority        INT NOT NULL CONSTRAINT DF_UserGoal_Priority DEFAULT 50,

        StartedOn       DATE NOT NULL,
        TargetDate      DATE NULL,
        AchievedOn      DATE NULL,

        CONSTRAINT PK_UserGoal PRIMARY KEY CLUSTERED (UserGoalId),

        CONSTRAINT CK_UserGoal_Status
            CHECK ([Status] IN ('active', 'achieved', 'paused', 'abandoned')),
        CONSTRAINT CK_UserGoal_Priority CHECK (Priority BETWEEN 0 AND 100),

        /*  Achieved without a date, or a date without the status, would make
            "when did I do this" unanswerable. */
        CONSTRAINT CK_UserGoal_Achieved
            CHECK (([Status] = 'achieved' AND AchievedOn IS NOT NULL)
                OR ([Status] <> 'achieved' AND AchievedOn IS NULL)),

        CONSTRAINT CK_UserGoal_TargetAfterStart
            CHECK (TargetDate IS NULL OR TargetDate >= StartedOn),

        CONSTRAINT FK_UserGoal_User FOREIGN KEY (UserId)
            REFERENCES [Identity].[User] (UserId),

        CONSTRAINT FK_UserGoal_Template FOREIGN KEY (GoalTemplateKey)
            REFERENCES [Growth].[GoalTemplate] (GoalTemplateKey)
    );

    /*  She may hold one goal of a kind at a time. Filtered on the live states,
        so abandoning a goal and starting it again in March is allowed and the
        old row survives to say she has done it before. */
    CREATE UNIQUE INDEX UX_UserGoal_OneLivePerTemplate
        ON [Growth].[UserGoal] (UserId, GoalTemplateKey)
        WHERE [Status] IN ('active', 'paused');

    CREATE INDEX IX_UserGoal_User
        ON [Growth].[UserGoal] (UserId, [Status]) INCLUDE (GoalTemplateKey, Priority);

    /*  Non-filtered, for the foreign key. A reference check has to find every
        referencing row, including ones a filtered index excludes. */
    CREATE INDEX IX_UserGoal_Template
        ON [Growth].[UserGoal] (GoalTemplateKey) INCLUDE (UserId);
END
GO

-- ---------------------------------------------------------------------------
-- Progress, snapshotted
-- ---------------------------------------------------------------------------
/*  What the platform believed about her progress on a given day.

    Snapshotted for the same reason behaviour and state are: recomputing history
    on demand would let a change to a goal's targets silently rewrite what she
    had achieved. A woman who reached a goal in March must still have reached it
    after somebody raises the target in June. */
IF OBJECT_ID('Growth.GoalProgress') IS NULL
BEGIN
    CREATE TABLE [Growth].[GoalProgress] (
        UserId       UNIQUEIDENTIFIER NOT NULL,
        UserGoalId   UNIQUEIDENTIFIER NOT NULL,
        ForLocalDate DATE NOT NULL,

        /*  Null when confidence is zero. A zero here reads as "she has made no
            progress"; the truth is that nothing has been observed yet. */
        ProgressPercent DECIMAL(5, 1) NULL,

        /*  Inherited from the observations behind it, never asserted. A goal
            resting on a measure with nine days of history is not confidently
            40% done. */
        Confidence   INT NOT NULL,

        IsComplete   BIT NOT NULL CONSTRAINT DF_GoalProgress_IsComplete DEFAULT 0,

        /*  How many of its measures are currently met, so "nearly there" and
            "one thing left" are distinguishable. */
        MeasuresMet  INT NOT NULL,
        MeasureCount INT NOT NULL,

        Reason       NVARCHAR(600) NOT NULL,
        EvidenceCsv  NVARCHAR(400) NOT NULL,
        EngineVersion VARCHAR(20) NOT NULL,

        ComputedUtc  DATETIME2(3) NOT NULL
            CONSTRAINT DF_GoalProgress_ComputedUtc DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_GoalProgress PRIMARY KEY CLUSTERED
            (UserId, ForLocalDate, UserGoalId),

        CONSTRAINT CK_GoalProgress_Percent
            CHECK (ProgressPercent IS NULL OR ProgressPercent BETWEEN 0 AND 100),
        CONSTRAINT CK_GoalProgress_Confidence
            CHECK (Confidence BETWEEN 0 AND 100),
        CONSTRAINT CK_GoalProgress_Counts
            CHECK (MeasureCount >= 0 AND MeasuresMet BETWEEN 0 AND MeasureCount),

        /*  The same rule behaviour carries. Stated as a constraint because it
            is the property most likely to be relaxed to make a progress ring
            look fuller. */
        CONSTRAINT CK_GoalProgress_UnknownWhenNoConfidence
            CHECK (Confidence > 0 OR ProgressPercent IS NULL),

        /*  Complete with nothing observed would be a goal awarded for silence. */
        CONSTRAINT CK_GoalProgress_CompleteNeedsConfidence
            CHECK (IsComplete = 0 OR Confidence > 0),

        CONSTRAINT FK_GoalProgress_Goal FOREIGN KEY (UserGoalId)
            REFERENCES [Growth].[UserGoal] (UserGoalId) ON DELETE CASCADE
    );

    /*  For a trend line on one goal. */
    CREATE INDEX IX_GoalProgress_Series
        ON [Growth].[GoalProgress] (UserGoalId, ForLocalDate DESC)
        INCLUDE (ProgressPercent, Confidence);
END
GO

-- ---------------------------------------------------------------------------
-- Applicability: one matcher, not a second mechanism
-- ---------------------------------------------------------------------------
/*  Registering the scope is all that is needed. Life stage and role
    applicability become rule rows evaluated by Rules.fn_Match, exactly like
    content and dashboard cards. */
MERGE [Rules].[TargetScope] AS target
USING (VALUES
    ('goalTemplate', N'Goal template',
     'Growth.GoalTemplate', 'GoalTemplateKey',
     N'Which goals the platform offers a woman, by life stage, role, country '
     + N'and language. A goal that only makes sense in pregnancy is a rule row '
     + N'like every other targeting decision.', 40)
) AS source (ScopeCode, DisplayName, TargetTable, TargetColumn, [Description], SortOrder)
    ON target.ScopeCode = source.ScopeCode
WHEN NOT MATCHED THEN
    INSERT (ScopeCode, DisplayName, TargetTable, TargetColumn, [Description], SortOrder)
    VALUES (source.ScopeCode, source.DisplayName, source.TargetTable,
            source.TargetColumn, source.[Description], source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: the goal library
-- ---------------------------------------------------------------------------
/*  Seeded only where the domain exists, so this cannot create a goal in a
    domain the platform does not have. */
MERGE [Growth].[GoalTemplate] AS target
USING (VALUES
    ('drink_more_water', N'Drink water more days than not', 'hydration',
     N'Log water on most days, so the platform can tell a dry week from an '
     + N'ordinary one.',
     60, 28, 0,
     N'Why does this matter to you right now?',
     N'Measured by how many of your recent days carry a logged drink. Nothing '
     + N'here measures how hydrated you are - only how often you told us.', 10),

    ('steady_sleep', N'Log sleep regularly', 'body',
     N'Build a record of your nights, so patterns become visible rather than '
     + N'remembered.',
     70, 28, 0,
     N'What would a better night look like for you?',
     N'Measured by how many of your recent nights are logged, and how long the '
     + N'current run is. It describes your logging, not your sleep quality.', 20),

    ('move_most_days', N'Move on most days', 'fitness',
     N'Any movement counts - a walk, steps, a class. The goal is the habit of '
     + N'moving, not a target distance.',
     55, 42, 0,
     N'What kind of movement do you actually enjoy?',
     N'Measured across walking, steps and exercise together, so a week of walks '
     + N'counts the same as a week at the gym.', 30),

    ('check_in_weekly', N'Check in with yourself', 'mental',
     N'A regular moment to note how you are, so the platform has something to '
     + N'reflect back to you.',
     65, 28, 0,
     N'What do you want to notice about yourself?',
     N'Measured by how often you log a mood or a journal entry. It records that '
     + N'you checked in, never what the entries say.', 40),

    ('keep_evening_routine', N'Keep an evening wind-down', 'lifestyle',
     N'Finish the day the same way often enough that it stops taking effort.',
     50, 56, 0,
     N'What makes your evenings hard to protect?',
     N'Measured by how often you complete the whole wind-down, not parts of it. '
     + N'A half-finished evening does not count towards this.', 50)
) AS source (GoalTemplateKey, DisplayName, DomainCode, PurposeText,
             BasePriority, ExpectedDurationDays, IsHealthSensitive,
             MotivationPrompt, ExplanationText, SortOrder)
    ON target.GoalTemplateKey = source.GoalTemplateKey
WHEN NOT MATCHED AND EXISTS (
        SELECT 1 FROM [Content].[LifeDomain] d
        WHERE d.DomainCode = source.DomainCode) THEN
    INSERT (GoalTemplateKey, DisplayName, DomainCode, PurposeText, BasePriority,
            ExpectedDurationDays, IsHealthSensitive, MotivationPrompt,
            ExplanationText, SortOrder)
    VALUES (source.GoalTemplateKey, source.DisplayName, source.DomainCode,
            source.PurposeText, source.BasePriority, source.ExpectedDurationDays,
            source.IsHealthSensitive, source.MotivationPrompt,
            source.ExplanationText, source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed: what each goal is measured by
-- ---------------------------------------------------------------------------
/*  Only inserted where the behaviour subject and measure both exist. A goal
    that referenced a measure the platform does not produce would sit at zero
    progress forever with no explanation. */
MERGE [Growth].[GoalMeasure] AS target
USING (VALUES
    ('drink_more_water',     'hydration',       'consistency',    'gte', 70.0, 3,
     N'Water logged on at least 70% of your recent days'),
    ('drink_more_water',     'hydration',       'streak_current', 'gte',  3.0, 1,
     N'A run of at least 3 days'),

    ('steady_sleep',         'sleep',           'consistency',    'gte', 70.0, 3,
     N'Sleep logged on at least 70% of your recent nights'),
    ('steady_sleep',         'sleep',           'days_since_last','lte',  2.0, 1,
     N'Logged within the last 2 days'),

    ('move_most_days',       'movement',        'consistency',    'gte', 60.0, 3,
     N'Movement logged on at least 60% of your recent days'),
    ('move_most_days',       'movement',        'streak_current', 'gte',  3.0, 1,
     N'A run of at least 3 days'),

    ('check_in_weekly',      'reflection',      'consistency',    'gte', 30.0, 2,
     N'A check-in on at least 30% of your recent days'),
    ('check_in_weekly',      'reflection',      'days_since_last','lte',  7.0, 2,
     N'Checked in within the last week'),

    ('keep_evening_routine', 'evening_routine', 'consistency',    'gte', 50.0, 3,
     N'The whole wind-down completed on at least half your recent evenings'),
    ('keep_evening_routine', 'evening_routine', 'streak_best',    'gte',  5.0, 1,
     N'A best run of at least 5 evenings')
) AS source (GoalTemplateKey, SubjectKey, MeasureCode, Comparison, TargetValue,
             Weight, TargetText)
    ON target.GoalTemplateKey = source.GoalTemplateKey
   AND target.SubjectKey = source.SubjectKey
   AND target.MeasureCode = source.MeasureCode
WHEN NOT MATCHED
     AND EXISTS (SELECT 1 FROM [Growth].[GoalTemplate] t
                 WHERE t.GoalTemplateKey = source.GoalTemplateKey)
     AND EXISTS (SELECT 1 FROM [Behaviour].[SubjectMeasure] sm
                 WHERE sm.SubjectKey = source.SubjectKey
                   AND sm.MeasureCode = source.MeasureCode) THEN
    INSERT (GoalTemplateKey, SubjectKey, MeasureCode, Comparison, TargetValue,
            Weight, TargetText)
    VALUES (source.GoalTemplateKey, source.SubjectKey, source.MeasureCode,
            source.Comparison, source.TargetValue, source.Weight,
            source.TargetText);
GO

PRINT 'Personal Growth Platform — goals schema ready.';
GO
