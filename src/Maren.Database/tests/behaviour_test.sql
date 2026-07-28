SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Behaviour Intelligence verification.

    Behaviour is the platform's single source of truth about how she lives, and
    six engines are going to read it without checking it. So the assertions here
    are about the properties those engines will assume:

      - a day she did it is defined exactly once, and a routine is not "done"
        on a day she completed half of it
      - streaks are consecutive days and a broken streak is not called current
      - confidence comes from the span she has actually shown, never asserted
      - a measure below its minimum span is absent, not zero
      - probabilities are never 0 or 100, because watching someone cannot
        justify certainty
      - nothing clinical, nothing causal
      - and no other schema computes any of this

    That last one is the architectural assertion, and it is the reason this file
    exists rather than trusting a convention. The whole design fails the moment
    a second procedure counts her days its own way.

    The fixture is built from arithmetic rather than a fixed calendar so the
    suite is re-runnable on any date: 40 days of water with three known gaps,
    sleep every other day, and a half-completed evening routine.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/behaviour_test.sql -I
    Expect: TOTAL: 20  FAILED: 0

    Re-runnable: owns its user and removes it at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @user  UNIQUEIDENTIFIER = '000000BE-0000-0000-0000-000000000001';
DECLARE @fresh UNIQUEIDENTIFIER = '000000BE-0000-0000-0000-000000000002';
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @n INT, @d DECIMAL(9,4), @t NVARCHAR(80), @c INT;

DELETE FROM [Behaviour].[Observation] WHERE UserId IN (@user, @fresh);
DELETE FROM [Timeline].[Event]        WHERE UserId IN (@user, @fresh);
DELETE FROM [Identity].[User]         WHERE UserId IN (@user, @fresh);

INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail, PasswordHash,
                               PasswordSalt, PasswordIterations, SecurityStamp)
VALUES (@user,  'behaviour-test@example.com', 'BEHAVIOUR-TEST@EXAMPLE.COM',
        0x00, 0x00, 210000, NEWID()),
       (@fresh, 'behaviour-new@example.com',  'BEHAVIOUR-NEW@EXAMPLE.COM',
        0x00, 0x00, 210000, NEWID());

-- ---------------------------------------------------------------------------
-- Fixture
-- ---------------------------------------------------------------------------
/*  Water on 37 of the last 40 days, missing 5, 12 and 23 days ago. So the
    current streak is 5 (days 0-4), and the best run inside the window is the
    11 days between the gaps at 12 and 23. Both numbers are arithmetic, not
    guesses, which is what makes them worth asserting. */
DECLARE @i INT = 0, @day DATE;
WHILE @i < 40
BEGIN
    SET @day = DATEADD(DAY, -@i, @today);

    IF @i NOT IN (5, 12, 23)
        INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode, OccurredUtc,
              OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
        VALUES (NEWID(), @user, 'water',
                DATEADD(HOUR, 14, CAST(@day AS DATETIME2(3))),
                @day, SYSUTCDATETIME(), 'manual', 250);

    /*  A second water event on the same day, to prove a day is counted once
        however many times she logs it. */
    IF @i NOT IN (5, 12, 23)
        INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode, OccurredUtc,
              OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
        VALUES (NEWID(), @user, 'water',
                DATEADD(HOUR, 20, CAST(@day AS DATETIME2(3))),
                @day, SYSUTCDATETIME(), 'manual', 250);

    IF @i % 2 = 0
        INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode, OccurredUtc,
              OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
        VALUES (NEWID(), @user, 'sleep',
                DATEADD(HOUR, 7, CAST(@day AS DATETIME2(3))),
                @day, SYSUTCDATETIME(), 'manual', 7);

    /*  Only one of the evening routine's two required parts. It must never
        count as a completed routine. */
    INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode, OccurredUtc,
          OccurredLocalDate, RecordedUtc, [Source])
    VALUES (NEWID(), @user, 'brush_teeth',
            DATEADD(HOUR, 22, CAST(@day AS DATETIME2(3))),
            @day, SYSUTCDATETIME(), 'manual');

    SET @i = @i + 1;
END

/*  A woman who joined two days ago. Everything about her must be absent rather
    than small. */
INSERT [Timeline].[Event] (EventId, UserId, EventTypeCode, OccurredUtc,
      OccurredLocalDate, RecordedUtc, [Source], ValueNumeric)
VALUES (NEWID(), @fresh, 'water', DATEADD(HOUR, 14, CAST(@today AS DATETIME2(3))),
        @today, SYSUTCDATETIME(), 'manual', 250);

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Behaviour].[MeasureType] WHERE IsActive = 1;
INSERT @results VALUES ('the measure vocabulary is seeded',
    CONCAT(@n, ' measures'),
    CASE WHEN @n >= 14 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  A subject that no event type feeds would observe behaviour from nothing. */
SELECT @n = COUNT(*) FROM [Behaviour].[Subject] s
WHERE s.IsActive = 1
  AND NOT EXISTS (SELECT 1 FROM [Behaviour].[SubjectEvent] se
                  WHERE se.SubjectKey = s.SubjectKey);
INSERT @results VALUES ('every subject is fed by the timeline',
    CONCAT(@n, ' fed by nothing'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  Logging water twice in a day is one day of hydration. Without this a thirsty
    afternoon reads as a week of consistency. */
SELECT @n = COUNT(*) FROM [Behaviour].[fn_SubjectDays](@user, @today, 56)
WHERE SubjectKey = 'hydration';
INSERT @results VALUES ('a day is counted once however often she logs',
    CONCAT(@n, ' days from 74 events'),
    CASE WHEN @n = 37 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  The routine has two required parts and she logged one. Half a routine is
    not a routine. */
SELECT @n = COUNT(*) FROM [Behaviour].[fn_SubjectDays](@user, @today, 56)
WHERE SubjectKey = 'evening_routine';
INSERT @results VALUES ('half a routine does not count as done',
    CONCAT(@n, ' days credited'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  Gaps at 5, 12 and 23 days ago leave days 0-4 unbroken. */
SELECT @d = ValueNumeric FROM [Behaviour].[fn_Observe](@user, @today, 56)
WHERE SubjectKey = 'hydration' AND MeasureCode = 'streak_current';
INSERT @results VALUES ('the current streak stops at the first gap',
    CONCAT('streak=', CAST(@d AS INT)),
    CASE WHEN @d = 5 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  Gaps at 5, 12 and 23 leave four runs: days 0-4 (5), 6-11 (6), 13-22 (10)
    and 24-39 (16). The oldest is the longest. */
SELECT @d = ValueNumeric FROM [Behaviour].[fn_Observe](@user, @today, 56)
WHERE SubjectKey = 'hydration' AND MeasureCode = 'streak_best';
INSERT @results VALUES ('the best streak is the longest unbroken run',
    CONCAT('best=', CAST(@d AS INT)),
    CASE WHEN @d = 16 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  37 active days across a 40-day span. */
SELECT @d = ValueNumeric FROM [Behaviour].[fn_Observe](@user, @today, 56)
WHERE SubjectKey = 'hydration' AND MeasureCode = 'consistency';
INSERT @results VALUES ('consistency is active days over the observed span',
    CONCAT('consistency=', CAST(@d AS DECIMAL(5,1))),
    CASE WHEN @d BETWEEN 92 AND 93 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  Span is her history, not the window. She has 40 days, not 56. */
SELECT @n = MIN(SpanDays) FROM [Behaviour].[fn_Observe](@user, @today, 56)
WHERE SubjectKey = 'hydration';
INSERT @results VALUES ('span is what she showed us, not the window',
    CONCAT('span=', @n),
    CASE WHEN @n = 40 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  40 of a 56-day full span is 71%, not 100. Confidence describes coverage. */
SELECT @c = Confidence FROM [Behaviour].[fn_Observe](@user, @today, 56)
WHERE SubjectKey = 'hydration' AND MeasureCode = 'momentum';
INSERT @results VALUES ('confidence scales with the span observed',
    CONCAT('confidence=', @c),
    CASE WHEN @c BETWEEN 65 AND 75 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  days_active reaches full confidence at 28 days and she has 40. */
SELECT @c = Confidence FROM [Behaviour].[fn_Observe](@user, @today, 56)
WHERE SubjectKey = 'hydration' AND MeasureCode = 'days_active';
INSERT @results VALUES ('a fully covered measure reaches 100',
    CONCAT('confidence=', @c),
    CASE WHEN @c = 100 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  The honesty rule. Two days of history produces no weekly rhythm at all -
    not a rhythm with low confidence, and not zero. */
SELECT @n = COUNT(*) FROM [Behaviour].[fn_Observe](@fresh, @today, 56)
WHERE MeasureCode IN ('rhythm_weekday_best', 'momentum', 'streak_best');
INSERT @results VALUES ('a measure below its minimum span is absent',
    CONCAT(@n, ' invented'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  But she is not invisible. Short-span measures still report. */
SELECT @n = COUNT(*) FROM [Behaviour].[fn_Observe](@fresh, @today, 56);
INSERT @results VALUES ('a new user still gets what one day supports',
    CONCAT(@n, ' measures'),
    CASE WHEN @n BETWEEN 1 AND 6 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  Watching someone cannot justify certainty. Never 0, never 1. */
SELECT @n = COUNT(*) FROM [Behaviour].[fn_Observe](@user, @today, 56)
WHERE Family = 'probability'
  AND (ValueNumeric <= 0 OR ValueNumeric >= 1);
INSERT @results VALUES ('no probability is ever 0 or 100 per cent',
    CONCAT(@n, ' certain'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  Drop-off is the complement of engagement, computed once. Two engines each
    deriving it would eventually disagree by a rounding rule. */
SELECT @d = ABS(1.0
    - (SELECT ValueNumeric FROM [Behaviour].[fn_Observe](@user, @today, 56)
       WHERE SubjectKey = 'hydration' AND MeasureCode = 'engagement_probability')
    - (SELECT ValueNumeric FROM [Behaviour].[fn_Observe](@user, @today, 56)
       WHERE SubjectKey = 'hydration' AND MeasureCode = 'dropoff_probability'));
INSERT @results VALUES ('drop-off is exactly the complement of engagement',
    CONCAT('drift=', CAST(@d AS DECIMAL(5,3))),
    CASE WHEN @d < 0.002 THEN 'PASS' ELSE 'FAIL' END);

-- 15 ------------------------------------------------------------------------
/*  Every observation must justify itself. A row without a reason, evidence or
    a version is a number an engine cannot explain to the woman it is about. */
SELECT @n = COUNT(*) FROM [Behaviour].[fn_Observe](@user, @today, 56)
WHERE Reason IS NULL OR LEN(Reason) < 10
   OR EvidenceCsv IS NULL OR LEN(EvidenceCsv) = 0
   OR SpanDays IS NULL OR SupportingEventCount IS NULL;
INSERT @results VALUES ('every observation carries its own justification',
    CONCAT(@n, ' unjustified'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 16 ------------------------------------------------------------------------
/*  Weekday reads as a name. A screen showing "3" is an internal code that has
    leaked out of the database. */
SELECT @t = ValueText FROM [Behaviour].[fn_Observe](@user, @today, 56)
WHERE SubjectKey = 'hydration' AND MeasureCode = 'rhythm_weekday_best';
INSERT @results VALUES ('a weekday is named, not numbered',
    ISNULL(@t, '(null)'),
    CASE WHEN @t IN (N'Sunday', N'Monday', N'Tuesday', N'Wednesday',
                     N'Thursday', N'Friday', N'Saturday')
         THEN 'PASS' ELSE 'FAIL' END);

-- 17 ------------------------------------------------------------------------
/*  Resolving twice for the same day must overwrite it, not accumulate. This
    runs from the pipeline on every request. */
EXEC [Behaviour].[usp_Behaviour_Resolve] @UserId = @user, @AsOfDate = @today;
EXEC [Behaviour].[usp_Behaviour_Resolve] @UserId = @user, @AsOfDate = @today;
SELECT @n = COUNT(*) FROM [Behaviour].[Observation]
WHERE UserId = @user AND ForLocalDate = @today
  AND SubjectKey = 'hydration' AND MeasureCode = 'consistency';
INSERT @results VALUES ('resolving twice overwrites the day',
    CONCAT(@n, ' rows'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 18 ------------------------------------------------------------------------
/*  The snapshot must equal what the function produced. If reading and
    computing disagree, every engine downstream is reading a different woman. */
SELECT @n = COUNT(*)
FROM [Behaviour].[fn_Observe](@user, @today, 56) f
JOIN [Behaviour].[Observation] o
      ON o.UserId = @user AND o.ForLocalDate = @today
     AND o.SubjectKey = f.SubjectKey AND o.MeasureCode = f.MeasureCode
WHERE ISNULL(o.ValueNumeric, -999) <> ISNULL(f.ValueNumeric, -999)
   OR o.Confidence <> f.Confidence;
INSERT @results VALUES ('the snapshot matches what was observed',
    CONCAT(@n, ' disagree'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 19 ------------------------------------------------------------------------
/*  The architectural assertion, and the reason this file exists.

    Behaviour is the single source of truth. Any other schema that computes a
    streak or counts her active days is a second source, and the second source
    is always the one that is wrong. Detected structurally rather than by
    convention, because a convention survives exactly as long as the person who
    remembers it. */
SELECT @n = COUNT(*)
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name <> 'Behaviour'
  AND (m.definition LIKE '%Behaviour.Observation%'
    OR m.definition LIKE '%fn_SubjectDays%')
  AND o.name NOT LIKE 'usp_Inspector%';
INSERT @results VALUES ('nothing outside Behaviour computes behaviour',
    CONCAT(@n, ' duplicating'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 20 ------------------------------------------------------------------------
/*  Nothing clinical, nothing causal. The same ban the knowledge graph carries,
    asserted here because behaviour is where a well-meaning "because" would
    most naturally be written. */
SELECT @n = COUNT(*)
FROM [Behaviour].[MeasureType]
WHERE [Description] LIKE '%causes%' OR [Description] LIKE '%leads to%'
   OR [Description] LIKE '%diagnos%' OR [Description] LIKE '%risk of%'
   OR [Description] LIKE '%treat%' OR [Description] LIKE '%symptom%'
   OR UnknownText LIKE '%diagnos%' OR DisplayName LIKE '%risk%';
INSERT @results VALUES ('no measure is clinical or causal',
    CONCAT(@n, ' offending'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 56), 56) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 30), 30) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DELETE FROM [Behaviour].[Observation] WHERE UserId IN (@user, @fresh);
DELETE FROM [Timeline].[Event]        WHERE UserId IN (@user, @fresh);
DELETE FROM [Identity].[User]         WHERE UserId IN (@user, @fresh);

IF @failed > 0
    THROW 51000, 'Behaviour assertions failed.', 1;
GO
