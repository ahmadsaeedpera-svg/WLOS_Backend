/*  53_Procs_Growth_Goals.sql

    Goal resolution: how far she has come, and on what evidence.

    Every number here is derived from Behaviour.fn_Read. Nothing counts a day,
    derives a streak or estimates a probability - those exist once, in
    Behaviour, and behaviour_test.sql fails if this schema tries to reach past
    the published interface into the observation store.

    So this file contains exactly one piece of arithmetic that Behaviour does
    not already do: the distance between an observed value and a target. That
    is what a goal is.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_ResolveGoals
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.fn_ResolveGoals') IS NOT NULL
    DROP FUNCTION [Growth].[fn_ResolveGoals];
GO
/*  Progress on every goal she is currently holding.

    Progress per measure is how far the observed value has travelled towards its
    target, clamped to 0-100. For a 'gte' measure that is value over target; for
    'lte' - "logged within the last two days" - it inverts, because a smaller
    number is better and a woman four days out is not 200% done.

    The goal's progress is the weighted mean of its measures, so a goal resting
    mostly on consistency does not read as half finished because its secondary
    streak is young.

    Confidence is inherited, never asserted. A measure Behaviour did not produce
    - too little history - contributes no progress and drags confidence down,
    which is the honest answer: the platform cannot yet say how she is doing.

    A table-valued function so it composes. INSERT ... EXEC cannot nest, and a
    consuming engine inside its own INSERT ... EXEC would silently receive
    nothing - a defect this platform has already paid for once. */
CREATE FUNCTION [Growth].[fn_ResolveGoals]
    (@UserId UNIQUEIDENTIFIER, @AsOfDate DATE)
RETURNS TABLE
AS
RETURN
    WITH observed AS (
        SELECT SubjectKey, MeasureCode, ValueNumeric, Confidence, EvidenceCsv
        FROM [Behaviour].[fn_Read](@UserId, @AsOfDate)
    ),
    /*  One row per goal measure, with what Behaviour had to say about it. A
        LEFT JOIN, because a missing observation is information: it means she
        has not shown the platform enough for that part of the goal yet. */
    perMeasure AS (
        SELECT
            g.UserGoalId,
            gm.SubjectKey,
            gm.MeasureCode,
            gm.Weight,
            gm.TargetText,
            gm.Comparison,
            gm.TargetValue,
            o.ValueNumeric,
            ISNULL(o.Confidence, 0) AS Confidence,

            /*  Met is a straight comparison against the target. Unobserved is
                never met - a goal must not complete because nothing was seen. */
            CAST(CASE
                WHEN o.ValueNumeric IS NULL THEN 0
                WHEN gm.Comparison = 'gte' AND o.ValueNumeric >= gm.TargetValue THEN 1
                WHEN gm.Comparison = 'lte' AND o.ValueNumeric <= gm.TargetValue THEN 1
                ELSE 0
            END AS BIT) AS IsMet,

            CASE
                WHEN o.ValueNumeric IS NULL THEN CAST(0 AS DECIMAL(9, 4))

                WHEN gm.Comparison = 'gte' THEN
                    CASE WHEN 100.0 * o.ValueNumeric / NULLIF(gm.TargetValue, 0) > 100
                         THEN CAST(100 AS DECIMAL(9, 4))
                         WHEN o.ValueNumeric < 0 THEN CAST(0 AS DECIMAL(9, 4))
                         ELSE CAST(100.0 * o.ValueNumeric
                                   / NULLIF(gm.TargetValue, 0) AS DECIMAL(9, 4))
                    END

                /*  Inverted: the target is a ceiling. At or under it is done;
                    twice the ceiling is nothing. Divided by target + 1 so a
                    ceiling of zero - "logged today" - does not divide by zero
                    and does not make one day late look like total failure. */
                ELSE
                    CASE WHEN o.ValueNumeric <= gm.TargetValue
                         THEN CAST(100 AS DECIMAL(9, 4))
                         WHEN o.ValueNumeric >= 2 * gm.TargetValue + 1
                         THEN CAST(0 AS DECIMAL(9, 4))
                         ELSE CAST(100.0 * (2 * gm.TargetValue + 1 - o.ValueNumeric)
                                   / NULLIF(gm.TargetValue + 1, 0) AS DECIMAL(9, 4))
                    END
            END AS MeasureProgress
        FROM [Growth].[UserGoal] g
        JOIN [Growth].[GoalMeasure] gm
              ON gm.GoalTemplateKey = g.GoalTemplateKey
        LEFT JOIN observed o
              ON o.SubjectKey = gm.SubjectKey AND o.MeasureCode = gm.MeasureCode
        WHERE g.UserId = @UserId
          AND g.[Status] IN ('active', 'paused')
    ),
    rolled AS (
        SELECT
            UserGoalId,
            SUM(Weight) AS TotalWeight,
            COUNT(*) AS MeasureCount,
            SUM(CAST(IsMet AS INT)) AS MeasuresMet,
            SUM(MeasureProgress * Weight) / NULLIF(SUM(Weight), 0) AS ProgressPercent,
            SUM(Confidence * Weight) / NULLIF(SUM(Weight), 0) AS Confidence
        FROM perMeasure
        GROUP BY UserGoalId
    )

    SELECT
        g.UserGoalId,
        g.GoalTemplateKey,
        t.DisplayName,
        t.DomainCode,
        t.PurposeText,
        t.ExplanationText,
        t.IsHealthSensitive,
        g.[Status],
        g.MotivationText,
        g.Priority,
        g.StartedOn,
        g.TargetDate,
        t.ExpectedDurationDays,

        r.MeasureCount,
        r.MeasuresMet,
        CAST(ROUND(r.Confidence, 0) AS INT) AS Confidence,

        /*  Null rather than zero when nothing was observed. A zero progress ring
            says "you have made no progress"; the truth is that the platform has
            not seen enough to say. */
        CASE WHEN CAST(ROUND(r.Confidence, 0) AS INT) = 0 THEN NULL
             ELSE CAST(ROUND(r.ProgressPercent, 1) AS DECIMAL(5, 1)) END
            AS ProgressPercent,

        /*  Complete when every measure is met and something was actually
            observed. Both conditions, because a goal awarded for silence is
            worse than no goal. */
        CAST(CASE WHEN r.MeasuresMet = r.MeasureCount AND r.MeasureCount > 0
                   AND CAST(ROUND(r.Confidence, 0) AS INT) > 0
                  THEN 1 ELSE 0 END AS BIT) AS IsComplete,

        /*  Named in words, so "why am I not there yet" resolves to the specific
            thing that is short rather than to a percentage. */
        CASE
            WHEN CAST(ROUND(r.Confidence, 0) AS INT) = 0 THEN
                N'Not enough logged yet to say how this is going.'
            WHEN r.MeasuresMet = r.MeasureCount THEN
                CONCAT(N'All ', r.MeasureCount, N' of this goal''s measures are met.')
            ELSE
                CONCAT(r.MeasuresMet, N' of ', r.MeasureCount,
                       N' measures met. Still short: ',
                       ISNULL(STUFF((
                           SELECT N'; ' + pm.TargetText
                           FROM perMeasure pm
                           WHERE pm.UserGoalId = g.UserGoalId AND pm.IsMet = 0
                           ORDER BY pm.Weight DESC, pm.MeasureCode
                           FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''),
                           N'nothing'),
                       N'.')
        END AS Reason,

        /*  The behaviour measures this goal rests on, so evidence resolves to
            observations she can open rather than to a description of the
            arithmetic. */
        ISNULL(STUFF((
            SELECT N',' + pm.SubjectKey + N'.' + pm.MeasureCode
            FROM perMeasure pm
            WHERE pm.UserGoalId = g.UserGoalId
            ORDER BY pm.SubjectKey, pm.MeasureCode
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS EvidenceCsv

    FROM [Growth].[UserGoal] g
    JOIN [Growth].[GoalTemplate] t ON t.GoalTemplateKey = g.GoalTemplateKey
    JOIN rolled r ON r.UserGoalId = g.UserGoalId
    WHERE g.UserId = @UserId
      AND g.[Status] IN ('active', 'paused');
GO

-- ---------------------------------------------------------------------------
-- usp_Goal_Resolve
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.usp_Goal_Resolve') IS NOT NULL
    DROP PROCEDURE [Growth].[usp_Goal_Resolve];
GO
/*  Resolve and persist the day's progress.

    Persisted for the reason behaviour and state are: a change to a goal's
    targets must not rewrite what she had already achieved. A woman who reached
    a goal in March must still have reached it after somebody raises the target
    in June.

    Achieving a goal is recorded here rather than left to a client, and only
    forward: a goal already marked achieved is never un-achieved by a later
    resolution. Consistency drifts; taking a completed goal away from somebody
    because last week was hard would be the platform punishing her for a bad
    week. */
CREATE PROCEDURE [Growth].[usp_Goal_Resolve]
    @UserId   UNIQUEIDENTIFIER,
    @AsOfDate DATE = NULL,
    @Persist  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    DECLARE @version VARCHAR(20) = '1.0.0';

    DECLARE @resolved TABLE (
        UserGoalId UNIQUEIDENTIFIER, GoalTemplateKey VARCHAR(40),
        DisplayName NVARCHAR(80), DomainCode VARCHAR(30),
        PurposeText NVARCHAR(300), ExplanationText NVARCHAR(600),
        IsHealthSensitive BIT, [Status] VARCHAR(12),
        MotivationText NVARCHAR(300), Priority INT,
        StartedOn DATE, TargetDate DATE, ExpectedDurationDays INT,
        MeasureCount INT, MeasuresMet INT, Confidence INT,
        ProgressPercent DECIMAL(5, 1), IsComplete BIT,
        Reason NVARCHAR(600), EvidenceCsv NVARCHAR(400));

    INSERT @resolved
    SELECT UserGoalId, GoalTemplateKey, DisplayName, DomainCode, PurposeText,
           ExplanationText, IsHealthSensitive, [Status], MotivationText,
           Priority, StartedOn, TargetDate, ExpectedDurationDays,
           MeasureCount, MeasuresMet, Confidence, ProgressPercent, IsComplete,
           Reason, EvidenceCsv
    FROM [Growth].[fn_ResolveGoals](@UserId, @AsOfDate);

    IF @Persist = 1
    BEGIN
        MERGE [Growth].[GoalProgress] AS target
        USING (SELECT * FROM @resolved) AS source
            ON  target.UserId = @UserId
            AND target.ForLocalDate = @AsOfDate
            AND target.UserGoalId = source.UserGoalId
        WHEN MATCHED THEN UPDATE SET
            ProgressPercent = source.ProgressPercent,
            Confidence = source.Confidence,
            IsComplete = source.IsComplete,
            MeasuresMet = source.MeasuresMet,
            MeasureCount = source.MeasureCount,
            Reason = source.Reason,
            EvidenceCsv = source.EvidenceCsv,
            EngineVersion = @version,
            ComputedUtc = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT
            (UserId, UserGoalId, ForLocalDate, ProgressPercent, Confidence,
             IsComplete, MeasuresMet, MeasureCount, Reason, EvidenceCsv,
             EngineVersion)
        VALUES
            (@UserId, source.UserGoalId, @AsOfDate, source.ProgressPercent,
             source.Confidence, source.IsComplete, source.MeasuresMet,
             source.MeasureCount, source.Reason, source.EvidenceCsv, @version);

        /*  Forward only. Never un-achieves. */
        UPDATE g
        SET [Status] = 'achieved', AchievedOn = @AsOfDate
        FROM [Growth].[UserGoal] g
        JOIN @resolved r ON r.UserGoalId = g.UserGoalId
        WHERE r.IsComplete = 1 AND g.[Status] = 'active';
    END

    SELECT
        r.UserGoalId, r.GoalTemplateKey, r.DisplayName, r.DomainCode,
        r.PurposeText, r.ExplanationText, r.IsHealthSensitive,
        /*  Re-read, so a goal achieved by this very call reports as achieved
            rather than as the active goal it was a moment ago. */
        g.[Status], r.MotivationText, r.Priority, r.StartedOn, r.TargetDate,
        g.AchievedOn, r.ExpectedDurationDays, r.MeasureCount, r.MeasuresMet,
        r.Confidence, r.ProgressPercent, r.IsComplete, r.Reason, r.EvidenceCsv,
        @version AS EngineVersion
    FROM @resolved r
    JOIN [Growth].[UserGoal] g ON g.UserGoalId = r.UserGoalId
    ORDER BY r.Priority DESC, r.DisplayName;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Goal_Offer
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.usp_Goal_Offer') IS NOT NULL
    DROP PROCEDURE [Growth].[usp_Goal_Offer];
GO
/*  The goals worth offering this woman, and why each one fits.

    Applicability comes from Rules.fn_Match under the 'goalTemplate' scope - the
    platform's one matcher, the same one that decides which content and which
    dashboard cards reach her. A goal with no rules is universal, matching the
    behaviour of every other scope: silence means "everybody", not "nobody".

    Goals she already holds are excluded, because offering somebody a goal they
    are three weeks into is the platform admitting it does not know her. */
CREATE PROCEDURE [Growth].[usp_Goal_Offer]
    @UserId      UNIQUEIDENTIFIER,
    @ContextJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.GoalTemplateKey,
        t.DisplayName,
        t.DomainCode,
        t.PurposeText,
        t.ExplanationText,
        t.MotivationPrompt,
        t.BasePriority,
        t.ExpectedDurationDays,
        t.IsHealthSensitive,
        (SELECT COUNT(*) FROM [Growth].[GoalMeasure] gm
         WHERE gm.GoalTemplateKey = t.GoalTemplateKey) AS MeasureCount,
        ISNULL(STUFF((
            SELECT N'; ' + gm.TargetText
            FROM [Growth].[GoalMeasure] gm
            WHERE gm.GoalTemplateKey = t.GoalTemplateKey
            ORDER BY gm.Weight DESC, gm.MeasureCode
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''),
            N'') AS TargetsText
    FROM [Growth].[GoalTemplate] t
    WHERE t.IsActive = 1
      AND NOT EXISTS (
            SELECT 1 FROM [Growth].[UserGoal] g
            WHERE g.UserId = @UserId
              AND g.GoalTemplateKey = t.GoalTemplateKey
              AND g.[Status] IN ('active', 'paused'))
      AND (
            NOT EXISTS (SELECT 1 FROM [Rules].[Rule] r
                        WHERE r.ScopeCode = 'goalTemplate'
                          AND r.TargetKey = t.GoalTemplateKey)
         OR EXISTS (SELECT 1 FROM [Rules].[fn_Match]('goalTemplate', @ContextJson) m
                    WHERE m.TargetKey = t.GoalTemplateKey))
    ORDER BY t.BasePriority DESC, t.SortOrder;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Goal_Adopt
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.usp_Goal_Adopt') IS NOT NULL
    DROP PROCEDURE [Growth].[usp_Goal_Adopt];
GO
/*  She takes a goal on, in her own words.

    Idempotent: adopting a goal she already holds updates her motivation and
    priority rather than failing. An offline client retries, and a woman who
    taps twice should not see an error about a goal she just set.

    Re-adopting one she abandoned starts a new row, so the old attempt survives.
    "You did this before" is the most encouraging thing the platform can say to
    somebody starting again, and a deleted row cannot say it. */
CREATE PROCEDURE [Growth].[usp_Goal_Adopt]
    @UserId          UNIQUEIDENTIFIER,
    @GoalTemplateKey VARCHAR(40),
    @MotivationText  NVARCHAR(300) = NULL,
    @Priority        INT = NULL,
    @TargetDate      DATE = NULL,
    @AsOfDate        DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    IF NOT EXISTS (SELECT 1 FROM [Growth].[GoalTemplate]
                   WHERE GoalTemplateKey = @GoalTemplateKey AND IsActive = 1)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserGoalId;
        RETURN;
    END

    IF @Priority IS NULL
        SELECT @Priority = BasePriority FROM [Growth].[GoalTemplate]
        WHERE GoalTemplateKey = @GoalTemplateKey;

    DECLARE @existing UNIQUEIDENTIFIER = (
        SELECT UserGoalId FROM [Growth].[UserGoal]
        WHERE UserId = @UserId AND GoalTemplateKey = @GoalTemplateKey
          AND [Status] IN ('active', 'paused'));

    IF @existing IS NOT NULL
    BEGIN
        UPDATE [Growth].[UserGoal]
        SET MotivationText = ISNULL(@MotivationText, MotivationText),
            Priority = @Priority,
            TargetDate = ISNULL(@TargetDate, TargetDate),
            [Status] = 'active'
        WHERE UserGoalId = @existing;

        SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(20)) AS FailureCode,
               @existing AS UserGoalId;
        RETURN;
    END

    DECLARE @new UNIQUEIDENTIFIER = NEWID();

    INSERT [Growth].[UserGoal]
        (UserGoalId, UserId, GoalTemplateKey, [Status], MotivationText,
         Priority, StartedOn, TargetDate)
    VALUES
        (@new, @UserId, @GoalTemplateKey, 'active', @MotivationText,
         @Priority, @AsOfDate, @TargetDate);

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(20)) AS FailureCode,
           @new AS UserGoalId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Goal_SetStatus
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.usp_Goal_SetStatus') IS NOT NULL
    DROP PROCEDURE [Growth].[usp_Goal_SetStatus];
GO
/*  Pause or abandon a goal she has taken on.

    'achieved' is deliberately not settable here. Achievement is decided by the
    engine from what she logged; letting a client declare it would make the one
    number in the platform that has to be earned into one that can be asked for. */
CREATE PROCEDURE [Growth].[usp_Goal_SetStatus]
    @UserId     UNIQUEIDENTIFIER,
    @UserGoalId UNIQUEIDENTIFIER,
    @Status     VARCHAR(12)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Status NOT IN ('active', 'paused', 'abandoned')
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_STATUS' AS FailureCode;
        RETURN;
    END

    /*  Scoped to her own goals. Without the UserId predicate this is a
        one-parameter way to abandon a stranger's goal. */
    IF NOT EXISTS (SELECT 1 FROM [Growth].[UserGoal]
                   WHERE UserGoalId = @UserGoalId AND UserId = @UserId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode;
        RETURN;
    END

    UPDATE [Growth].[UserGoal]
    SET [Status] = @Status
    WHERE UserGoalId = @UserGoalId AND UserId = @UserId
      AND [Status] <> 'achieved';

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(20)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Goal_ListTemplates
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.usp_Goal_ListTemplates') IS NOT NULL
    DROP PROCEDURE [Growth].[usp_Goal_ListTemplates];
GO
/*  The goal library, for operators. Configuration, not anybody's data. */
CREATE PROCEDURE [Growth].[usp_Goal_ListTemplates]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.GoalTemplateKey,
        t.DisplayName,
        t.DomainCode,
        t.PurposeText,
        t.ExplanationText,
        t.MotivationPrompt,
        t.BasePriority,
        t.ExpectedDurationDays,
        t.IsHealthSensitive,
        t.IsActive,
        (SELECT COUNT(*) FROM [Growth].[GoalMeasure] gm
         WHERE gm.GoalTemplateKey = t.GoalTemplateKey) AS MeasureCount,
        /*  How many rules narrow it. Zero means universal, which an operator
            must be able to see rather than infer from an empty list. */
        (SELECT COUNT(*) FROM [Rules].[Rule] r
         WHERE r.ScopeCode = 'goalTemplate'
           AND r.TargetKey = t.GoalTemplateKey) AS RuleCount,
        ISNULL(STUFF((
            SELECT N'; ' + gm.TargetText
            FROM [Growth].[GoalMeasure] gm
            WHERE gm.GoalTemplateKey = t.GoalTemplateKey
            ORDER BY gm.Weight DESC, gm.MeasureCode
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, N''),
            N'') AS TargetsText,
        ISNULL(STUFF((
            SELECT N',' + gm.SubjectKey + N'.' + gm.MeasureCode
            FROM [Growth].[GoalMeasure] gm
            WHERE gm.GoalTemplateKey = t.GoalTemplateKey
            ORDER BY gm.SubjectKey, gm.MeasureCode
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS MeasuresCsv
    FROM [Growth].[GoalTemplate] t
    ORDER BY t.SortOrder, t.GoalTemplateKey;
END
GO

PRINT 'Personal Growth Platform — goal procedures ready.';
GO
