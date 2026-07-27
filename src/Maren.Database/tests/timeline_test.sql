SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Timeline verification.

    The timeline is intended to be the single source of truth every later
    engine reads from, so the properties that matter are the ones those engines
    will assume without checking:

      - recording is idempotent, because an offline client retries
      - a deletion leaves a tombstone, because other devices must learn of it
      - aggregation sums what accumulates and averages what does not
      - the clustered index is on (UserId, OccurredUtc), not on a random GUID

    That last one is asserted rather than trusted. It is the difference between
    a table that stays healthy at ten million rows and one that fragments on
    every sync, and it is invisible in every functional test.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/timeline_test.sql -I
    Expect: TOTAL: 14  FAILED: 0

    Re-runnable: owns its user and removes it at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @res TABLE (Succeeded BIT, FailureCode VARCHAR(50));
DECLARE @user UNIQUEIDENTIFIER = '00000000-0000-0000-0000-00000000FEED';
DECLARE @e1 UNIQUEIDENTIFIER = '11111111-0000-0000-0000-00000000FEED';
DECLARE @e2 UNIQUEIDENTIFIER = '22222222-0000-0000-0000-00000000FEED';
DECLARE @n INT, @ok BIT, @code VARCHAR(50);
DECLARE @dec DECIMAL(18,4);
/*  T-SQL will not accept a function call as an EXEC argument, so ids that only
    need to be unique are generated into a variable first. */
DECLARE @tmp UNIQUEIDENTIFIER;

DELETE FROM [Timeline].[Event] WHERE UserId = @user;
DELETE FROM [Identity].[User]  WHERE UserId = @user;

INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail, PasswordHash,
                               PasswordSalt, PasswordIterations, SecurityStamp)
VALUES (@user, 'timeline-test@example.com', 'TIMELINE-TEST@EXAMPLE.COM',
        0x00, 0x00, 210000, NEWID());

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Timeline].[EventType] WHERE IsActive = 1;
INSERT @results VALUES ('event types are seeded and open-ended', CONCAT(@n, ' types'),
    CASE WHEN @n >= 30 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  The structural assertion. Clustering on a random client GUID is what
    fragments the Health tables today; this one must cluster on the access
    path instead. */
SELECT @n = COUNT(*)
FROM sys.indexes i
JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE i.object_id = OBJECT_ID('Timeline.Event')
  AND i.type_desc = 'CLUSTERED'
  AND ic.key_ordinal = 1
  AND c.name = 'UserId';
INSERT @results VALUES ('clustered on UserId, not on a random identifier',
    CASE WHEN @n = 1 THEN 'UserId leads' ELSE 'wrong key' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM sys.indexes
WHERE object_id = OBJECT_ID('Timeline.Event')
  AND is_primary_key = 1 AND type_desc = 'NONCLUSTERED';
INSERT @results VALUES ('the identifier is a nonclustered key',
    CASE WHEN @n = 1 THEN 'nonclustered' ELSE 'clustered' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Timeline].[usp_Timeline_Record]
    @EventId = @e1, @UserId = @user, @EventTypeCode = 'water',
    @OccurredUtc = '2026-07-20T09:00:00', @OccurredLocalDate = '2026-07-20',
    @ValueNumeric = 250;
SELECT @ok = Succeeded FROM @res;
INSERT @results VALUES ('an event can be recorded', 'water 250ml',
    CASE WHEN @ok = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  Idempotence. A sync that timed out after the server committed will be
    retried, and a retry must not become a second glass of water. */
DELETE @res;
INSERT @res EXEC [Timeline].[usp_Timeline_Record]
    @EventId = @e1, @UserId = @user, @EventTypeCode = 'water',
    @OccurredUtc = '2026-07-20T09:00:00', @OccurredLocalDate = '2026-07-20',
    @ValueNumeric = 250;
SELECT @n = COUNT(*) FROM [Timeline].[Event] WHERE UserId = @user;
INSERT @results VALUES ('re-sending the same event does not duplicate it',
    CONCAT(@n, ' row(s)'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  ...but a genuine correction updates in place. */
DELETE @res;
INSERT @res EXEC [Timeline].[usp_Timeline_Record]
    @EventId = @e1, @UserId = @user, @EventTypeCode = 'water',
    @OccurredUtc = '2026-07-20T09:00:00', @OccurredLocalDate = '2026-07-20',
    @ValueNumeric = 400;
SELECT @dec = ValueNumeric FROM [Timeline].[Event] WHERE EventId = @e1;
INSERT @results VALUES ('re-sending with a new value corrects it',
    CONCAT('value=', CAST(@dec AS varchar(20))),
    CASE WHEN @dec = 400 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
DELETE @res;
SET @tmp = NEWID();
INSERT @res EXEC [Timeline].[usp_Timeline_Record]
    @EventId = @tmp, @UserId = @user, @EventTypeCode = 'levitation',
    @OccurredUtc = '2026-07-20T09:00:00';
SELECT @ok = Succeeded, @code = FailureCode FROM @res;
INSERT @results VALUES ('an unknown event type is refused', ISNULL(@code, '(none)'),
    CASE WHEN @ok = 0 AND @code = 'UNKNOWN_EVENT_TYPE' THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  Refused, not clamped. A client sending 9 has a bug, and quietly storing 5
    hides it while distorting every average taken from that row afterwards. */
DELETE @res;
SET @tmp = NEWID();
INSERT @res EXEC [Timeline].[usp_Timeline_Record]
    @EventId = @tmp, @UserId = @user, @EventTypeCode = 'mood',
    @OccurredUtc = '2026-07-20T10:00:00', @ValueNumeric = 9;
SELECT @ok = Succeeded, @code = FailureCode FROM @res;
INSERT @results VALUES ('a scale value outside 1-5 is refused', ISNULL(@code, '(none)'),
    CASE WHEN @ok = 0 AND @code = 'VALUE_OUT_OF_RANGE' THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
DELETE @res;
SET @tmp = NEWID();
INSERT @res EXEC [Timeline].[usp_Timeline_Record]
    @EventId = @tmp, @UserId = @user, @EventTypeCode = 'water',
    @OccurredUtc = '2026-07-20T11:00:00', @ValueNumeric = -50;
SELECT @ok = Succeeded, @code = FailureCode FROM @res;
INSERT @results VALUES ('a negative quantity is refused', ISNULL(@code, '(none)'),
    CASE WHEN @ok = 0 AND @code = 'VALUE_OUT_OF_RANGE' THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  Cumulative: a day's water is the sum of the glasses. */
EXEC [Timeline].[usp_Timeline_Record]
    @EventId = @e2, @UserId = @user, @EventTypeCode = 'water',
    @OccurredUtc = '2026-07-20T14:00:00', @OccurredLocalDate = '2026-07-20',
    @ValueNumeric = 300;

CREATE TABLE #agg (LocalDate DATE, Total DECIMAL(18,4), EventCount INT);
INSERT #agg EXEC [Timeline].[usp_Timeline_Aggregate]
    @UserId = @user, @EventTypeCode = 'water',
    @FromDate = '2026-07-20', @ToDate = '2026-07-20';
SELECT @dec = Total FROM #agg;
INSERT @results VALUES ('a cumulative type is summed for the day',
    CONCAT('400+300=', CAST(@dec AS varchar(20))),
    CASE WHEN @dec = 700 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  Non-cumulative: two weights on one day average rather than add. Summing
    them would report her at twice her weight. */
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'weight', @OccurredUtc = '2026-07-21T08:00:00',
    @OccurredLocalDate = '2026-07-21', @ValueNumeric = 60;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'weight', @OccurredUtc = '2026-07-21T20:00:00',
    @OccurredLocalDate = '2026-07-21', @ValueNumeric = 62;

DELETE #agg;
INSERT #agg EXEC [Timeline].[usp_Timeline_Aggregate]
    @UserId = @user, @EventTypeCode = 'weight',
    @FromDate = '2026-07-21', @ToDate = '2026-07-21';
SELECT @dec = Total FROM #agg;
INSERT @results VALUES ('a non-cumulative type is averaged, not summed',
    CONCAT('avg(60,62)=', CAST(@dec AS varchar(20))),
    CASE WHEN @dec = 61 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  Deletion must leave a tombstone. A hard delete removes the row and every
    other device carries on showing it. */
DELETE @res;
INSERT @res EXEC [Timeline].[usp_Timeline_Delete] @EventId = @e2, @UserId = @user;
SELECT @n = COUNT(*) FROM [Timeline].[Event]
WHERE EventId = @e2 AND IsDeleted = 1;
INSERT @results VALUES ('a deletion leaves a tombstone for other devices',
    CASE WHEN @n = 1 THEN 'tombstoned' ELSE 'gone' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  And a deleted event stops counting towards the day. */
DELETE #agg;
INSERT #agg EXEC [Timeline].[usp_Timeline_Aggregate]
    @UserId = @user, @EventTypeCode = 'water',
    @FromDate = '2026-07-20', @ToDate = '2026-07-20';
SELECT @dec = Total FROM #agg;
INSERT @results VALUES ('a deleted event no longer counts',
    CONCAT('total=', CAST(@dec AS varchar(20))),
    CASE WHEN @dec = 400 THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  Delta sync returns tombstones as well as upserts, or a deletion never
    reaches her other devices. */
CREATE TABLE #delta (EventId UNIQUEIDENTIFIER, EventTypeCode VARCHAR(40),
    OccurredUtc DATETIME2(3), OccurredLocalDate DATE, [Source] VARCHAR(20),
    ValueNumeric DECIMAL(18,4), ValueText NVARCHAR(200), Unit VARCHAR(20),
    MetadataJson NVARCHAR(2000), IsDeleted BIT, ModifiedOn DATETIME2(3),
    SyncToken BINARY(8));
INSERT #delta EXEC [Timeline].[usp_Timeline_GetDelta] @UserId = @user, @SinceToken = NULL;
SELECT @n = COUNT(*) FROM #delta WHERE IsDeleted = 1;
INSERT @results VALUES ('delta sync carries tombstones', CONCAT(@n, ' tombstone(s)'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 58), 58) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 24), 24) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DROP TABLE #agg;
DROP TABLE #delta;
DELETE FROM [Timeline].[Event] WHERE UserId = @user;
DELETE FROM [Identity].[User]  WHERE UserId = @user;

IF @failed > 0
    THROW 51000, 'Timeline assertions failed.', 1;
GO
