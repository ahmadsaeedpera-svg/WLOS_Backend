/*  56_Procs_Growth_Routines.sql

    Routine resolution and the daily plan.

    Everything about whether a routine was done comes from Behaviour: fn_Read
    for how it has been going, fn_ReadSteps for where she is up to today.
    Nothing here counts a day, derives a streak or reads the timeline, and
    growth_routines_test.sql fails if it tries.

    What this file actually decides is one thing Behaviour has no opinion on:
    which routine is worth putting in front of her right now.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_ResolveRoutines
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.fn_ResolveRoutines') IS NOT NULL
    DROP FUNCTION [Growth].[fn_ResolveRoutines];
GO
/*  Every routine she could be following, with how it is going and where she is
    up to today.

    Done-today is derived rather than stored: Behaviour's days_since_last is
    zero on a day she completed the whole routine. That is the same number the
    streak is built from, so the checklist and the streak cannot disagree - the
    failure this whole design exists to prevent.

    A routine with no behavioural history yet still appears, with nulls and zero
    confidence. Hiding it until the platform had something to say would mean a
    woman never sees a routine she has not started, which is precisely when she
    most needs to. */
CREATE FUNCTION [Growth].[fn_ResolveRoutines]
    (@UserId UNIQUEIDENTIFIER, @AsOfDate DATE)
RETURNS TABLE
AS
RETURN
    WITH observed AS (
        SELECT SubjectKey, MeasureCode, ValueNumeric, Confidence
        FROM [Behaviour].[fn_Read](@UserId, @AsOfDate)
    ),
    steps AS (
        SELECT SubjectKey, IsRequired, IsDoneToday
        FROM [Behaviour].[fn_ReadSteps](@UserId, @AsOfDate)
    ),
    stepRoll AS (
        SELECT
            SubjectKey,
            COUNT(*) AS StepCount,
            SUM(CASE WHEN IsRequired = 1 THEN 1 ELSE 0 END) AS RequiredCount,
            SUM(CASE WHEN IsDoneToday = 1 THEN 1 ELSE 0 END) AS StepsDone,
            SUM(CASE WHEN IsRequired = 1 AND IsDoneToday = 1 THEN 1 ELSE 0 END)
                AS RequiredDone
        FROM steps
        GROUP BY SubjectKey
    )
    SELECT
        r.RoutineKey,
        r.DisplayName,
        r.SubjectKey,
        r.PurposeText,
        r.DomainCode,
        r.StartHour,
        r.EndHour,
        r.WindowText,
        r.BasePriority,
        r.IsHealthSensitive,
        s.TargetPerDay,

        ISNULL(sr.StepCount, 0)    AS StepCount,
        ISNULL(sr.RequiredCount, 0) AS RequiredCount,
        ISNULL(sr.StepsDone, 0)    AS StepsDoneToday,
        ISNULL(sr.RequiredDone, 0) AS RequiredDoneToday,

        /*  Complete when enough required parts are logged - the subject's own
            rule, read from the subject rather than restated here. */
        CAST(CASE WHEN ISNULL(sr.RequiredDone, 0) >= s.TargetPerDay
                  THEN 1 ELSE 0 END AS BIT) AS IsDoneToday,

        /*  Started but not finished. Worth distinguishing: "you are two steps
            in" is a different thing to say than "you have not begun". */
        CAST(CASE WHEN ISNULL(sr.StepsDone, 0) > 0
                   AND ISNULL(sr.RequiredDone, 0) < s.TargetPerDay
                  THEN 1 ELSE 0 END AS BIT) AS IsStarted,

        (SELECT o.ValueNumeric FROM observed o
         WHERE o.SubjectKey = r.SubjectKey AND o.MeasureCode = 'consistency')
            AS Consistency,
        (SELECT o.ValueNumeric FROM observed o
         WHERE o.SubjectKey = r.SubjectKey AND o.MeasureCode = 'streak_current')
            AS CurrentStreak,
        (SELECT o.ValueNumeric FROM observed o
         WHERE o.SubjectKey = r.SubjectKey AND o.MeasureCode = 'completion_probability')
            AS CompletionProbability,

        /*  Inherited from the consistency observation, never invented here. A
            routine resting on nine days of history is not a confident 60%. */
        ISNULL((SELECT o.Confidence FROM observed o
                WHERE o.SubjectKey = r.SubjectKey AND o.MeasureCode = 'consistency'), 0)
            AS Confidence,

        /*  Said in words, because a checklist that only shows ticks cannot
            explain why it is asking now. */
        CASE
            WHEN ISNULL(sr.RequiredDone, 0) >= s.TargetPerDay THEN
                CONCAT(N'Done ', r.WindowText, N'.')
            WHEN ISNULL(sr.StepsDone, 0) > 0 THEN
                CONCAT(ISNULL(sr.StepsDone, 0), N' of ',
                       ISNULL(sr.RequiredCount, 0), N' steps so far ', r.WindowText, N'.')
            WHEN NOT EXISTS (SELECT 1 FROM observed o WHERE o.SubjectKey = r.SubjectKey) THEN
                N'Nothing logged for this yet.'
            ELSE
                CONCAT(N'Not started ', r.WindowText, N'.')
        END AS StatusText

    FROM [Growth].[Routine] r
    JOIN [Behaviour].[Subject] s ON s.SubjectKey = r.SubjectKey
    LEFT JOIN stepRoll sr ON sr.SubjectKey = r.SubjectKey
    WHERE r.IsActive = 1 AND s.IsActive = 1;
GO

-- ---------------------------------------------------------------------------
-- usp_Routine_Today
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.usp_Routine_Today') IS NOT NULL
    DROP PROCEDURE [Growth].[usp_Routine_Today];
GO
/*  Her routines for today, in the order they belong to the day.

    Two result sets in one round trip: the routines, then every step of each.
    A client rendering a checklist needs both, and two calls would be two
    chances for them to describe different days.

    Ordering is the day itself, not priority. A morning routine listed under an
    evening one because it scores lower would be the platform arguing with the
    clock. Within a window, priority decides.

    Applicability comes from Rules.fn_Match under the 'routine' scope. A routine
    with no rules is universal - silence means everybody, matching every other
    scope in the platform. */
CREATE PROCEDURE [Growth].[usp_Routine_Today]
    @UserId      UNIQUEIDENTIFIER,
    @AsOfDate    DATE = NULL,
    @ContextJson NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    DECLARE @applicable TABLE (RoutineKey VARCHAR(40) PRIMARY KEY);

    INSERT @applicable (RoutineKey)
    SELECT r.RoutineKey
    FROM [Growth].[Routine] r
    WHERE r.IsActive = 1
      AND (
            NOT EXISTS (SELECT 1 FROM [Rules].[Rule] x
                        WHERE x.ScopeCode = 'routine' AND x.TargetKey = r.RoutineKey)
         OR EXISTS (SELECT 1 FROM [Rules].[fn_Match]('routine', @ContextJson) m
                    WHERE m.TargetKey = r.RoutineKey));

    SELECT
        f.RoutineKey, f.DisplayName, f.SubjectKey, f.PurposeText, f.DomainCode,
        f.StartHour, f.EndHour, f.WindowText, f.BasePriority,
        f.IsHealthSensitive, f.TargetPerDay, f.StepCount, f.RequiredCount,
        f.StepsDoneToday, f.RequiredDoneToday, f.IsDoneToday, f.IsStarted,
        f.Consistency, f.CurrentStreak, f.CompletionProbability, f.Confidence,
        f.StatusText
    FROM [Growth].[fn_ResolveRoutines](@UserId, @AsOfDate) f
    JOIN @applicable a ON a.RoutineKey = f.RoutineKey
    ORDER BY f.StartHour, f.BasePriority DESC, f.DisplayName;

    /*  The steps, from Behaviour. Optional parts included and flagged: hiding
        the step she may skip would quietly turn optional into non-existent. */
    SELECT
        r.RoutineKey,
        st.EventTypeCode,
        st.StepName,
        st.IsRequired,
        st.SortOrder,
        st.IsDoneToday,
        st.LastDoneDate
    FROM [Growth].[Routine] r
    JOIN @applicable a ON a.RoutineKey = r.RoutineKey
    JOIN [Behaviour].[fn_ReadSteps](@UserId, @AsOfDate) st
          ON st.SubjectKey = r.SubjectKey
    ORDER BY r.SortOrder, st.SortOrder, st.EventTypeCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Routine_ListTemplates
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.usp_Routine_ListTemplates') IS NOT NULL
    DROP PROCEDURE [Growth].[usp_Routine_ListTemplates];
GO
/*  The routine library, for operators. Configuration, not anybody's data.

    Carries the subject it observes and that subject's part count, because the
    commonest routine misconfiguration is a target higher than the number of
    required parts - a routine that can never be completed, which looks
    identical to one nobody has done. */
CREATE PROCEDURE [Growth].[usp_Routine_ListTemplates]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.RoutineKey,
        r.DisplayName,
        r.SubjectKey,
        r.PurposeText,
        r.DomainCode,
        r.StartHour,
        r.EndHour,
        r.WindowText,
        r.BasePriority,
        r.IsHealthSensitive,
        r.IsActive,
        s.TargetPerDay,
        (SELECT COUNT(*) FROM [Behaviour].[SubjectEvent] se
         WHERE se.SubjectKey = r.SubjectKey) AS StepCount,
        (SELECT COUNT(*) FROM [Behaviour].[SubjectEvent] se
         WHERE se.SubjectKey = r.SubjectKey AND se.IsRequired = 1) AS RequiredCount,
        (SELECT COUNT(*) FROM [Rules].[Rule] x
         WHERE x.ScopeCode = 'routine' AND x.TargetKey = r.RoutineKey) AS RuleCount,
        ISNULL(STUFF((
            SELECT N',' + se.EventTypeCode
            FROM [Behaviour].[SubjectEvent] se
            WHERE se.SubjectKey = r.SubjectKey
            ORDER BY se.SortOrder, se.EventTypeCode
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS StepsCsv
    FROM [Growth].[Routine] r
    JOIN [Behaviour].[Subject] s ON s.SubjectKey = r.SubjectKey
    ORDER BY r.StartHour, r.SortOrder, r.RoutineKey;
END
GO

PRINT 'Personal Growth Platform — routine procedures ready.';
GO
