SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Women's Life Intelligence Core verification.

    Assertions 3 to 6 are the ones that decide whether this core is honest.

    A platform that reports "balanced, 94% confident" for a woman who logged
    nothing has not understood her life - it has reported its own defaults, and
    it will be wrong in exactly the direction that makes it feel untrustworthy.
    So: no data means no confidence, no confidence means unknown, and the value
    must never be a baseline wearing an answer's clothes.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/intelligence_test.sql -I
    Expect: TOTAL: 15  FAILED: 0

    Re-runnable: owns its user and removes it at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @user UNIQUEIDENTIFIER = '00000000-0000-0000-0000-0000C0DE1234';
DECLARE @n INT, @tmp UNIQUEIDENTIFIER;
DECLARE @d DATE = '2026-07-20', @prev DATE = '2026-07-19';
DECLARE @score INT, @conf INT, @code VARCHAR(30), @trend VARCHAR(20);

DELETE FROM [Intelligence].[UserStateSnapshot] WHERE UserId = @user;
DELETE FROM [Timeline].[Event] WHERE UserId = @user;
DELETE FROM [Identity].[User]  WHERE UserId = @user;
INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail, PasswordHash,
                               PasswordSalt, PasswordIterations, SecurityStamp)
VALUES (@user, 'intel-test@example.com', 'INTEL-TEST@EXAMPLE.COM', 0x00, 0x00, 210000, NEWID());

CREATE TABLE #state (
    DimensionCode VARCHAR(30), DisplayName NVARCHAR(80), ValueKind VARCHAR(12),
    ValueCode VARCHAR(30), ValueText NVARCHAR(80), Score INT, Confidence INT,
    Reason NVARCHAR(MAX), EvidenceCsv NVARCHAR(MAX),
    PreviousScore INT, PreviousDate DATE, Trend VARCHAR(20), SortOrder INT);

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Intelligence].[StateDimension] WHERE IsActive = 1;
INSERT @results VALUES ('the dimensions are a registry, not code',
    CONCAT(@n, ' dimensions'),
    CASE WHEN @n >= 9 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  Every score dimension must know where an ordinary day starts, or it has
    nothing to adjust from. */
SELECT @n = COUNT(*) FROM [Intelligence].[StateDimension]
WHERE ValueKind = 'score' AND BaselineScore IS NULL;
INSERT @results VALUES ('every score dimension has a configurable baseline',
    CONCAT(@n, ' missing'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  Nothing logged. This is the assertion the whole core rests on. */
DELETE #state;
INSERT #state EXEC [Intelligence].[usp_Intelligence_Resolve]
    @UserId = @user, @AsOfDate = @d, @Persist = 0;
SELECT @n = COUNT(*) FROM #state WHERE Confidence <> 0;
INSERT @results VALUES ('no data gives no confidence', CONCAT(@n, ' claimed some'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM #state WHERE ValueCode <> 'unknown';
INSERT @results VALUES ('no confidence gives unknown, not a default',
    CONCAT(@n, ' answered anyway'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM #state WHERE Score IS NOT NULL;
INSERT @results VALUES ('no score is invented when nothing was logged',
    CONCAT(@n, ' scored'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  And she is told so in words, rather than shown a blank. */
SELECT @n = COUNT(*) FROM #state
WHERE Reason IS NULL OR LEN(LTRIM(Reason)) = 0;
INSERT @results VALUES ('an unknown state still explains itself',
    CONCAT(@n, ' silent'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  Partial data gives partial confidence. Energy reads sleep (3), water (1)
    and steps (2); sleep alone is 3 of 6. */
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'sleep', @OccurredUtc = '2026-07-20T23:00:00',
    @OccurredLocalDate = '2026-07-20', @ValueNumeric = 420;

DELETE #state;
INSERT #state EXEC [Intelligence].[usp_Intelligence_Resolve]
    @UserId = @user, @AsOfDate = @d, @Persist = 0;
SELECT @conf = Confidence FROM #state WHERE DimensionCode = 'energy';
INSERT @results VALUES ('partial data gives partial confidence',
    CONCAT('energy confidence=', @conf, '%'),
    CASE WHEN @conf = 50 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  One good night with nothing raised: the baseline stands rather than being
    marked down for silence elsewhere. */
SELECT @score = Score, @code = ValueCode FROM #state WHERE DimensionCode = 'energy';
INSERT @results VALUES ('an ordinary day sits at the baseline',
    CONCAT('score=', @score),
    CASE WHEN @score = 70 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  Now a genuinely poor stretch. Two short nights and two dry days. */
DELETE FROM [Timeline].[Event] WHERE UserId = @user;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'sleep', @OccurredUtc = '2026-07-19T23:00:00',
    @OccurredLocalDate = '2026-07-19', @ValueNumeric = 300;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'sleep', @OccurredUtc = '2026-07-20T23:00:00',
    @OccurredLocalDate = '2026-07-20', @ValueNumeric = 310;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'water', @OccurredUtc = '2026-07-19T12:00:00',
    @OccurredLocalDate = '2026-07-19', @ValueNumeric = 500;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'water', @OccurredUtc = '2026-07-20T12:00:00',
    @OccurredLocalDate = '2026-07-20', @ValueNumeric = 600;

DELETE #state;
INSERT #state EXEC [Intelligence].[usp_Intelligence_Resolve]
    @UserId = @user, @AsOfDate = @d, @Persist = 0;
SELECT @score = Score FROM #state WHERE DimensionCode = 'energy';
INSERT @results VALUES ('a hard stretch lowers energy from the baseline',
    CONCAT('70 -> ', @score),
    CASE WHEN @score = 70 - 25 - 10 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM #state
WHERE DimensionCode = 'energy' AND EvidenceCsv LIKE '%short_sleep%';
INSERT @results VALUES ('the state names the evidence behind it',
    CONCAT(@n, ' with evidence'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  Categorical dimensions pick the value with the strongest support. */
SELECT @code = ValueCode FROM #state WHERE DimensionCode = 'risk';
INSERT @results VALUES ('a categorical dimension picks its strongest value',
    CONCAT('risk=', @code),
    CASE WHEN @code = 'hydration' THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  A score can never leave 0-100 however many rules pile on. */
SELECT @n = COUNT(*) FROM #state
WHERE Score IS NOT NULL AND (Score < 0 OR Score > 100);
INSERT @results VALUES ('a score stays within its range', CONCAT(@n, ' out of range'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  Trend must not claim a direction on the first day. */
DELETE FROM [Intelligence].[UserStateSnapshot] WHERE UserId = @user;
DELETE #state;
INSERT #state EXEC [Intelligence].[usp_Intelligence_Resolve]
    @UserId = @user, @AsOfDate = @d, @Persist = 1;
SELECT @trend = Trend FROM #state WHERE DimensionCode = 'energy';
INSERT @results VALUES ('the first day reports no trend, not improvement',
    CONCAT('trend=', @trend),
    CASE WHEN @trend = 'new' THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  With a worse day behind her, today reads as improving. */
INSERT INTO [Intelligence].[UserStateSnapshot]
    (UserId, DimensionCode, ForLocalDate, ValueCode, ValueText, Score,
     Confidence, Reason)
VALUES (@user, 'energy', @prev, 'scored', N'Energy', 20, 80, N'Seeded for trend.');

DELETE #state;
INSERT #state EXEC [Intelligence].[usp_Intelligence_Resolve]
    @UserId = @user, @AsOfDate = @d, @Persist = 1;
SELECT @trend = Trend FROM #state WHERE DimensionCode = 'energy';
INSERT @results VALUES ('trend compares against the previous snapshot',
    CONCAT('20 -> 35 = ', @trend),
    CASE WHEN @trend = 'improving' THEN 'PASS' ELSE 'FAIL' END);

-- 15 ------------------------------------------------------------------------
/*  Nothing in this core may derive from a health-sensitive signal. Behavioural
    understanding only - no condition, no prediction, no body. */
SELECT @n = COUNT(*)
FROM [Intelligence].[StateRule] r
JOIN [Knowledge].[Signal] s ON s.SignalCode = r.SignalCode
WHERE s.IsHealthSensitive = 1;
INSERT @results VALUES ('no dimension derives from a health-sensitive signal',
    CONCAT(@n, ' rule(s)'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 58), 58) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 26), 26) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DROP TABLE #state;
DELETE FROM [Intelligence].[UserStateSnapshot] WHERE UserId = @user;
DELETE FROM [Timeline].[Event] WHERE UserId = @user;
DELETE FROM [Identity].[User]  WHERE UserId = @user;

IF @failed > 0
    THROW 51000, 'Intelligence core assertions failed.', 1;
GO
