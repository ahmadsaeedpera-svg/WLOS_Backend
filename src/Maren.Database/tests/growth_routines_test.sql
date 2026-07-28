SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Personal Growth Platform — routines.

    A routine is several behaviours done together, and Behaviour already models
    exactly that. So the properties worth asserting are the ones that keep this
    layer thin rather than letting it become a second definition:

      - a routine owns no step list; composition lives on the Behaviour subject
      - completion comes from logged events, never from a stored percentage
      - the checklist and the streak are derived from the same numbers, so they
        cannot disagree in front of her
      - a routine cannot point at an event subject, which would complete on one
        logged event
      - a routine whose target exceeds its required parts can never be
        completed, and must be detectable

    The last one is the misconfiguration a routine library actually hides: a
    routine that can never be finished looks identical to one nobody has done.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/growth_routines_test.sql -I
    Expect: TOTAL: 16  FAILED: 0

    Re-runnable: owns its user and fixtures and removes them at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @user  UNIQUEIDENTIFIER = '000000E2-0000-0000-0000-000000000001';
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @n INT, @d DECIMAL(9,4), @t NVARCHAR(200), @ok BIT, @bit BIT;

DECLARE @routines TABLE (
    RoutineKey VARCHAR(40), DisplayName NVARCHAR(80), SubjectKey VARCHAR(40),
    PurposeText NVARCHAR(300), DomainCode VARCHAR(30), StartHour TINYINT,
    EndHour TINYINT, WindowText NVARCHAR(40), BasePriority INT,
    IsHealthSensitive BIT, TargetPerDay INT, StepCount INT, RequiredCount INT,
    StepsDoneToday INT, RequiredDoneToday INT, IsDoneToday BIT, IsStarted BIT,
    Consistency DECIMAL(9,4), CurrentStreak DECIMAL(9,4),
    CompletionProbability DECIMAL(9,4), Confidence INT, StatusText NVARCHAR(200));

DELETE FROM [Behaviour].[Observation] WHERE UserId = @user;
DELETE FROM [Timeline].[Event]        WHERE UserId = @user;
DELETE FROM [Identity].[User]         WHERE UserId = @user;

INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail, PasswordHash,
                               PasswordSalt, PasswordIterations, SecurityStamp)
VALUES (@user, 'routine-test@example.com', 'ROUTINE-TEST@EXAMPLE.COM',
        0x00, 0x00, 210000, NEWID());

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Growth].[Routine] WHERE IsActive = 1;
INSERT @results VALUES ('the routine library is seeded',
    CONCAT(@n, ' routines'),
    CASE WHEN @n >= 1 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  The single-source decision, asserted structurally. A routine that owned a
    step list would be a second answer to "what is in my evening routine". */
SELECT @n = COUNT(*)
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'Growth' AND t.name = 'Routine'
  AND (c.name LIKE '%Step%' OR c.name LIKE '%EventType%' OR c.name LIKE '%Percent%');
INSERT @results VALUES ('a routine owns no steps and no percentage',
    CONCAT(@n, ' offending columns'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  Every routine must observe a subject that is itself a routine. */
SELECT @n = COUNT(*)
FROM [Growth].[Routine] r
JOIN [Behaviour].[Subject] s ON s.SubjectKey = r.SubjectKey
WHERE s.SubjectKind <> 'routine';
INSERT @results VALUES ('every routine observes a routine subject',
    CONCAT(@n, ' mismatched'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  And the schema refuses one that does not. Pointing a routine at 'hydration'
    would produce a routine complete on a single glass of water. */
BEGIN TRY
    INSERT [Growth].[Routine] (RoutineKey, DisplayName, SubjectKey, PurposeText,
        DomainCode, StartHour, EndHour, WindowText, BasePriority, SortOrder)
    VALUES ('zz_bad_routine', N'Bad', 'hydration', N'x', 'hydration',
            6, 10, N'x', 50, 999);
    SET @ok = 1;
END TRY
BEGIN CATCH
    SET @ok = 0;
END CATCH
DELETE FROM [Growth].[Routine] WHERE RoutineKey = 'zz_bad_routine';
INSERT @results VALUES ('an event subject is refused as a routine',
    CONCAT('inserted=', CAST(@ok AS varchar(1))),
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  A routine whose target exceeds its required parts can never be completed,
    and looks exactly like one nobody has done. */
SELECT @n = COUNT(*)
FROM [Growth].[Routine] r
JOIN [Behaviour].[Subject] s ON s.SubjectKey = r.SubjectKey
WHERE s.TargetPerDay > (SELECT COUNT(*) FROM [Behaviour].[SubjectEvent] se
                        WHERE se.SubjectKey = r.SubjectKey AND se.IsRequired = 1);
INSERT @results VALUES ('no routine is impossible to complete',
    CONCAT(@n, ' unreachable'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  A zero-length window would be a routine that is never due. */
SELECT @n = COUNT(*) FROM [Growth].[Routine] WHERE StartHour = EndHour;
INSERT @results VALUES ('no routine has an empty time window',
    CONCAT(@n, ' empty'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  Nothing logged. She must still see the routine - hiding it until the
    platform has something to say means she never sees a routine she has not
    started, which is when she most needs it. */
DELETE @routines;
INSERT @routines SELECT * FROM [Growth].[fn_ResolveRoutines](@user, @today);
SELECT @n = COUNT(*) FROM @routines;
INSERT @results VALUES ('a routine she has never done still appears',
    CONCAT(@n, ' shown'),
    CASE WHEN @n >= 1 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
SELECT @bit = IsDoneToday, @t = StatusText FROM @routines
WHERE RoutineKey = 'evening_winddown';
INSERT @results VALUES ('with nothing logged it is not done',
    CONCAT('done=', CAST(@bit AS varchar(1))),
    CASE WHEN @bit = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  One of two required parts. Started, not finished - a distinction worth
    making, because "you are one step in" is different to "you have not begun". */
INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode, OccurredUtc,
      OccurredLocalDate, RecordedUtc, [Source])
VALUES (NEWID(), @user, 'brush_teeth',
        DATEADD(HOUR, 22, CAST(@today AS DATETIME2(3))), @today,
        SYSUTCDATETIME(), 'manual');

DELETE @routines;
INSERT @routines SELECT * FROM [Growth].[fn_ResolveRoutines](@user, @today);
SELECT @bit = IsStarted, @n = RequiredDoneToday FROM @routines
WHERE RoutineKey = 'evening_winddown';
INSERT @results VALUES ('one step in reads as started, not done',
    CONCAT('started=', CAST(@bit AS varchar(1)), ' done=', @n),
    CASE WHEN @bit = 1 AND @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
SELECT @bit = IsDoneToday FROM @routines WHERE RoutineKey = 'evening_winddown';
INSERT @results VALUES ('half a routine is still not complete',
    CONCAT('done=', CAST(@bit AS varchar(1))),
    CASE WHEN @bit = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  Both required parts. Now it is complete, and completion came from two logged
    events rather than from anything stored. */
INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode, OccurredUtc,
      OccurredLocalDate, RecordedUtc, [Source])
VALUES (NEWID(), @user, 'skin_care',
        DATEADD(HOUR, 22, CAST(@today AS DATETIME2(3))), @today,
        SYSUTCDATETIME(), 'manual');

DELETE @routines;
INSERT @routines SELECT * FROM [Growth].[fn_ResolveRoutines](@user, @today);
SELECT @bit = IsDoneToday, @t = StatusText FROM @routines
WHERE RoutineKey = 'evening_winddown';
INSERT @results VALUES ('completion comes only from logged events',
    CONCAT('done=', CAST(@bit AS varchar(1))),
    CASE WHEN @bit = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  The checklist and the streak must be derived from the same numbers. If they
    disagree she sees a completed routine beside a broken streak. */
EXEC [Behaviour].[usp_Behaviour_Resolve] @UserId = @user, @AsOfDate = @today;
SELECT @d = ValueNumeric FROM [Behaviour].[fn_Read](@user, @today)
WHERE SubjectKey = 'evening_routine' AND MeasureCode = 'days_since_last';
INSERT @results VALUES ('the checklist agrees with behaviour',
    CONCAT('daysSinceLast=', ISNULL(CAST(CAST(@d AS INT) AS varchar(10)), 'null')),
    CASE WHEN @bit = 1 AND @d = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  A soft-deleted event must not count. This is the specific way two
    definitions of "done" drift apart. */
UPDATE [Timeline].[Event] SET IsDeleted = 1
WHERE UserId = @user AND EventTypeCode = 'skin_care';

DELETE @routines;
INSERT @routines SELECT * FROM [Growth].[fn_ResolveRoutines](@user, @today);
SELECT @bit = IsDoneToday FROM @routines WHERE RoutineKey = 'evening_winddown';
INSERT @results VALUES ('a deleted event stops counting',
    CONCAT('done=', CAST(@bit AS varchar(1))),
    CASE WHEN @bit = 0 THEN 'PASS' ELSE 'FAIL' END);

UPDATE [Timeline].[Event] SET IsDeleted = 0
WHERE UserId = @user AND EventTypeCode = 'skin_care';

-- 14 ------------------------------------------------------------------------
/*  Optional steps are returned and flagged. Hiding the step she may skip would
    quietly turn optional into non-existent. */
SELECT @n = COUNT(*) FROM [Behaviour].[fn_ReadSteps](@user, @today)
WHERE SubjectKey = 'evening_routine' AND IsRequired = 0;
INSERT @results VALUES ('optional steps are shown, not hidden',
    CONCAT(@n, ' optional'),
    CASE WHEN @n >= 1 THEN 'PASS' ELSE 'FAIL' END);

-- 15 ------------------------------------------------------------------------
/*  Silence means everybody, matching every other rule scope. */
SELECT @n = COUNT(*) FROM [Rules].[TargetScope] WHERE ScopeCode = 'routine';
INSERT @results VALUES ('routines use the platform''s one matcher',
    CONCAT(@n, ' scope registered'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 16 ------------------------------------------------------------------------
/*  The architectural assertion. Growth reads behaviour through its published
    interfaces and must never reach the observation store or the timeline. */
SELECT @n = COUNT(*)
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = 'Growth'
  AND (m.definition LIKE '%Behaviour.Observation%'
    OR m.definition LIKE '%fn_SubjectDays%'
    OR m.definition LIKE '%Timeline.Event%');
INSERT @results VALUES ('growth never reads the timeline itself',
    CONCAT(@n, ' reaching past the interface'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 56), 56) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 32), 32) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DELETE FROM [Behaviour].[Observation] WHERE UserId = @user;
DELETE FROM [Timeline].[Event]        WHERE UserId = @user;
DELETE FROM [Identity].[User]         WHERE UserId = @user;

IF @failed > 0
    THROW 51000, 'Routine assertions failed.', 1;
GO
