SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Personal Growth Platform — goals.

    A goal is a desired outcome, and progress towards it is the distance between
    what Behaviour observed and what the goal asks for. So the properties that
    matter here are the ones a coach, a recommendation and a progress ring will
    all assume without checking:

      - progress comes from Behaviour and nowhere else
      - a goal is never complete on silence
      - unknown progress is null, not zero
      - achievement is earned from the timeline, never declared by a client
      - achievement is forward-only: a bad week does not take it back
      - applicability goes through the one rule matcher, not a second mechanism

    The architectural assertion is the last one, and it is why this file exists
    rather than a code review: the moment a second schema counts her days, the
    platform has two answers to the same question about the same woman.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/growth_goals_test.sql -I
    Expect: TOTAL: 18  FAILED: 0

    Re-runnable: owns its user and removes it at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @user  UNIQUEIDENTIFIER = '000000E0-0000-0000-0000-000000000001';
DECLARE @quiet UNIQUEIDENTIFIER = '000000E0-0000-0000-0000-000000000002';
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @n INT, @d DECIMAL(9,4), @t NVARCHAR(600), @c INT, @ok BIT;
DECLARE @goal UNIQUEIDENTIFIER, @goal2 UNIQUEIDENTIFIER;

DECLARE @adopt TABLE (Succeeded BIT, FailureCode VARCHAR(20), UserGoalId UNIQUEIDENTIFIER);
DECLARE @status TABLE (Succeeded BIT, FailureCode VARCHAR(20));

DELETE FROM [Growth].[GoalProgress]   WHERE UserId IN (@user, @quiet);
DELETE FROM [Growth].[UserGoal]       WHERE UserId IN (@user, @quiet);
DELETE FROM [Behaviour].[Observation] WHERE UserId IN (@user, @quiet);
DELETE FROM [Timeline].[Event]        WHERE UserId IN (@user, @quiet);
DELETE FROM [Identity].[User]         WHERE UserId IN (@user, @quiet);

INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail, PasswordHash,
                               PasswordSalt, PasswordIterations, SecurityStamp)
VALUES (@user,  'goal-test@example.com', 'GOAL-TEST@EXAMPLE.COM',
        0x00, 0x00, 210000, NEWID()),
       (@quiet, 'goal-quiet@example.com', 'GOAL-QUIET@EXAMPLE.COM',
        0x00, 0x00, 210000, NEWID());

-- ---------------------------------------------------------------------------
-- Fixture: water every day for 30 days, so the hydration goal is reachable.
-- ---------------------------------------------------------------------------
DECLARE @i INT = 0, @day DATE;
WHILE @i < 30
BEGIN
    SET @day = DATEADD(DAY, -@i, @today);
    INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode, OccurredUtc,
          OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
    VALUES (NEWID(), @user, 'water',
            DATEADD(HOUR, 14, CAST(@day AS DATETIME2(3))),
            @day, SYSUTCDATETIME(), 'manual', 250);
    SET @i = @i + 1;
END

/*  The quiet woman logs nothing at all. Her goal must never complete, and must
    never read as zero progress - those are different facts. */

EXEC [Behaviour].[usp_Behaviour_Resolve] @UserId = @user,  @AsOfDate = @today;
EXEC [Behaviour].[usp_Behaviour_Resolve] @UserId = @quiet, @AsOfDate = @today;

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Growth].[GoalTemplate] WHERE IsActive = 1;
INSERT @results VALUES ('the goal library is seeded',
    CONCAT(@n, ' templates'),
    CASE WHEN @n >= 5 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  A goal with no measures can never progress and never complete. It would sit
    on her screen forever with no explanation. */
SELECT @n = COUNT(*) FROM [Growth].[GoalTemplate] t
WHERE t.IsActive = 1
  AND NOT EXISTS (SELECT 1 FROM [Growth].[GoalMeasure] gm
                  WHERE gm.GoalTemplateKey = t.GoalTemplateKey);
INSERT @results VALUES ('every goal is measured by something',
    CONCAT(@n, ' unmeasurable'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  Every measure a goal depends on must be one Behaviour actually produces for
    that subject, or the goal is permanently stuck at zero. */
SELECT @n = COUNT(*) FROM [Growth].[GoalMeasure] gm
WHERE NOT EXISTS (SELECT 1 FROM [Behaviour].[SubjectMeasure] sm
                  WHERE sm.SubjectKey = gm.SubjectKey
                    AND sm.MeasureCode = gm.MeasureCode);
INSERT @results VALUES ('every goal measure is one behaviour produces',
    CONCAT(@n, ' unproducible'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
DELETE @adopt;
INSERT @adopt EXEC [Growth].[usp_Goal_Adopt]
    @UserId = @user, @GoalTemplateKey = 'drink_more_water',
    @MotivationText = N'I keep forgetting on work days.', @AsOfDate = @today;
SELECT @goal = UserGoalId, @ok = Succeeded FROM @adopt;
INSERT @results VALUES ('she can take a goal on in her own words',
    CONCAT('adopted=', CAST(@ok AS varchar(1))),
    CASE WHEN @ok = 1 AND @goal IS NOT NULL THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  An offline client retries, and a woman who taps twice must not see an error
    about a goal she just set. */
DELETE @adopt;
INSERT @adopt EXEC [Growth].[usp_Goal_Adopt]
    @UserId = @user, @GoalTemplateKey = 'drink_more_water', @AsOfDate = @today;
SELECT @ok = Succeeded, @goal2 = UserGoalId FROM @adopt;
SELECT @n = COUNT(*) FROM [Growth].[UserGoal]
WHERE UserId = @user AND GoalTemplateKey = 'drink_more_water'
  AND [Status] IN ('active', 'paused');
INSERT @results VALUES ('adopting twice updates rather than duplicates',
    CONCAT(@n, ' live rows'),
    CASE WHEN @ok = 1 AND @n = 1 AND @goal2 = @goal THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  Her words survive a retry that did not carry them. */
SELECT @t = MotivationText FROM [Growth].[UserGoal] WHERE UserGoalId = @goal;
INSERT @results VALUES ('a retry does not erase her motivation',
    LEFT(ISNULL(@t, '(null)'), 40),
    CASE WHEN @t = N'I keep forgetting on work days.' THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  30 days of water at 100% consistency and a 30-day streak clears both
    targets, so this goal completes on the evidence. */
EXEC [Growth].[usp_Goal_Resolve] @UserId = @user, @AsOfDate = @today;
SELECT @d = ProgressPercent, @c = Confidence
FROM [Growth].[GoalProgress]
WHERE UserId = @user AND UserGoalId = @goal AND ForLocalDate = @today;
INSERT @results VALUES ('progress is derived from behaviour',
    CONCAT('progress=', CAST(ISNULL(@d, -1) AS DECIMAL(5,1)), ' conf=', @c),
    CASE WHEN @d = 100.0 AND @c > 0 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  Achievement is earned from what she logged, and recorded by the engine. */
SELECT @t = [Status] FROM [Growth].[UserGoal] WHERE UserGoalId = @goal;
INSERT @results VALUES ('a met goal is marked achieved by the engine',
    ISNULL(@t, '(null)'),
    CASE WHEN @t = 'achieved' THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  Forward only. Taking a completed goal away because last week was hard would
    be the platform punishing her for a bad week. */
DELETE FROM [Timeline].[Event]
WHERE UserId = @user AND OccurredLocalDate > DATEADD(DAY, -25, @today);
EXEC [Behaviour].[usp_Behaviour_Resolve] @UserId = @user, @AsOfDate = @today;
EXEC [Growth].[usp_Goal_Resolve] @UserId = @user, @AsOfDate = @today;
SELECT @t = [Status] FROM [Growth].[UserGoal] WHERE UserGoalId = @goal;
INSERT @results VALUES ('achievement is never taken back',
    ISNULL(@t, '(null)'),
    CASE WHEN @t = 'achieved' THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  A client must not be able to declare achievement. It is the one number in
    the platform that has to be earned. */
DELETE @status;
INSERT @status EXEC [Growth].[usp_Goal_SetStatus]
    @UserId = @user, @UserGoalId = @goal, @Status = 'achieved';
SELECT @ok = Succeeded FROM @status;
INSERT @results VALUES ('a client cannot declare a goal achieved',
    CONCAT('accepted=', CAST(@ok AS varchar(1))),
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  Scoping. Without the UserId predicate this is a one-parameter way to abandon
    a stranger's goal. */
DELETE @status;
INSERT @status EXEC [Growth].[usp_Goal_SetStatus]
    @UserId = @quiet, @UserGoalId = @goal, @Status = 'abandoned';
SELECT @ok = Succeeded FROM @status;
SELECT @t = [Status] FROM [Growth].[UserGoal] WHERE UserGoalId = @goal;
INSERT @results VALUES ('nobody can change another woman''s goal',
    CONCAT('accepted=', CAST(@ok AS varchar(1)), ' status=', @t),
    CASE WHEN @ok = 0 AND @t = 'achieved' THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  The woman who logged nothing. Her goal must not complete on silence. */
DELETE @adopt;
INSERT @adopt EXEC [Growth].[usp_Goal_Adopt]
    @UserId = @quiet, @GoalTemplateKey = 'steady_sleep', @AsOfDate = @today;
SELECT @goal2 = UserGoalId FROM @adopt;
EXEC [Growth].[usp_Goal_Resolve] @UserId = @quiet, @AsOfDate = @today;
SELECT @n = COUNT(*) FROM [Growth].[GoalProgress]
WHERE UserGoalId = @goal2 AND IsComplete = 1;
INSERT @results VALUES ('a goal never completes on silence',
    CONCAT(@n, ' awarded'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  And her progress is unknown, not zero. A zero ring says "you have made no
    progress"; the truth is the platform has not seen enough to say. */
SELECT @d = ProgressPercent, @c = Confidence FROM [Growth].[GoalProgress]
WHERE UserGoalId = @goal2 AND ForLocalDate = @today;
INSERT @results VALUES ('unknown progress is null, never zero',
    CONCAT('progress=', ISNULL(CAST(@d AS varchar(10)), 'null'), ' conf=', @c),
    CASE WHEN @c = 0 AND @d IS NULL THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  Enforced by the schema too, not only by the function. A constraint survives
    a rewrite of the function; a comment does not. */
BEGIN TRY
    INSERT [Growth].[GoalProgress] (UserId, UserGoalId, ForLocalDate,
        ProgressPercent, Confidence, IsComplete, MeasuresMet, MeasureCount,
        Reason, EvidenceCsv, EngineVersion)
    VALUES (@quiet, @goal2, DATEADD(DAY, -1, @today), 100.0, 0, 0, 0, 1,
            N'x', N'x', '0');
    SET @ok = 1;
END TRY
BEGIN CATCH
    SET @ok = 0;
END CATCH
INSERT @results VALUES ('the schema refuses progress without confidence',
    CONCAT('inserted=', CAST(@ok AS varchar(1))),
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 15 ------------------------------------------------------------------------
/*  Every resolved goal explains itself, naming what is still short rather than
    reporting a bare percentage. */
SELECT @n = COUNT(*) FROM [Growth].[fn_ResolveGoals](@quiet, @today)
WHERE Reason IS NULL OR LEN(Reason) < 10 OR EvidenceCsv IS NULL;
INSERT @results VALUES ('every goal explains where it stands',
    CONCAT(@n, ' unexplained'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 16 ------------------------------------------------------------------------
/*  Offering a woman a goal she is three weeks into is the platform admitting it
    does not know her. */
DECLARE @offered TABLE (GoalTemplateKey VARCHAR(40), DisplayName NVARCHAR(80),
    DomainCode VARCHAR(30), PurposeText NVARCHAR(300),
    ExplanationText NVARCHAR(600), MotivationPrompt NVARCHAR(200),
    BasePriority INT, ExpectedDurationDays INT, IsHealthSensitive BIT,
    MeasureCount INT, TargetsText NVARCHAR(MAX));
INSERT @offered EXEC [Growth].[usp_Goal_Offer] @UserId = @quiet, @ContextJson = NULL;
SELECT @n = COUNT(*) FROM @offered WHERE GoalTemplateKey = 'steady_sleep';
INSERT @results VALUES ('a goal she already holds is not offered again',
    CONCAT(@n, ' re-offered'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 17 ------------------------------------------------------------------------
/*  Silence means everybody, matching every other rule scope in the platform. */
SELECT @n = COUNT(*) FROM @offered;
INSERT @results VALUES ('an unruled goal is offered to everyone',
    CONCAT(@n, ' offered'),
    CASE WHEN @n >= 4 THEN 'PASS' ELSE 'FAIL' END);

-- 18 ------------------------------------------------------------------------
/*  The architectural assertion.

    Behaviour Intelligence is the only behavioural source. Growth reads it
    through Behaviour.fn_Read - the published interface - and must never reach
    into the observation store or recompute a day count. A second source of
    behavioural truth is always the one that is wrong. */
SELECT @n = COUNT(*)
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = 'Growth'
  AND (m.definition LIKE '%Behaviour.Observation%'
    OR m.definition LIKE '%fn_SubjectDays%'
    OR m.definition LIKE '%Timeline.Event%');
INSERT @results VALUES ('growth never computes behaviour itself',
    CONCAT(@n, ' reaching past the interface'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 56), 56) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 34), 34) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DELETE FROM [Growth].[GoalProgress]   WHERE UserId IN (@user, @quiet);
DELETE FROM [Growth].[UserGoal]       WHERE UserId IN (@user, @quiet);
DELETE FROM [Behaviour].[Observation] WHERE UserId IN (@user, @quiet);
DELETE FROM [Timeline].[Event]        WHERE UserId IN (@user, @quiet);
DELETE FROM [Identity].[User]         WHERE UserId IN (@user, @quiet);

IF @failed > 0
    THROW 51000, 'Goal assertions failed.', 1;
GO
