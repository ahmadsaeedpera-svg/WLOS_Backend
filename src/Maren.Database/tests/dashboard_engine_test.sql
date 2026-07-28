SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Adaptive Dashboard Engine verification.

    A dashboard is generated, so the only way to know it is right is to
    generate one and inspect it. These assertions cover the properties every
    later layer will depend on without checking:

      - the same woman gets different cards at different life stages
      - the timeline changes the order, not just the content
      - a card driven below zero disappears rather than sitting at the bottom
      - every card can say why it is there
      - no card is invented for a woman we know nothing about

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/dashboard_engine_test.sql -I
    Expect: TOTAL: 14  FAILED: 0

    Re-runnable: owns its user and removes it at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @user UNIQUEIDENTIFIER = '00000000-0000-0000-0000-0000000D45BD';
DECLARE @n INT, @tmp UNIQUEIDENTIFIER, @d DATE = '2026-07-20';
DECLARE @pHydration INT, @pReading INT, @pSleep INT;

DELETE FROM [Timeline].[Event] WHERE UserId = @user;
DELETE FROM [Identity].[User]  WHERE UserId = @user;
INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail, PasswordHash,
                               PasswordSalt, PasswordIterations, SecurityStamp)
VALUES (@user, 'dash-test@example.com', 'DASH-TEST@EXAMPLE.COM', 0x00, 0x00, 210000, NEWID());

CREATE TABLE #cards (
    CardTypeCode VARCHAR(40), DisplayName NVARCHAR(80), DomainCode VARCHAR(30),
    Priority INT, BasePriority INT, Confidence DECIMAL(3,2),
    RefreshSeconds INT, LifetimeSeconds INT, IsDismissible BIT,
    IsHealthSensitive BIT, Reason NVARCHAR(MAX), EvidenceSignals NVARCHAR(MAX),
    [Source] VARCHAR(10));

DECLARE @pregnant NVARCHAR(MAX) = N'[{"dimension":"life_stage","value":"pregnancy"}]';
DECLARE @student  NVARCHAR(MAX) = N'[{"dimension":"life_stage","value":"young_adult"},
                                     {"dimension":"role_mode","value":"student"}]';
DECLARE @senior   NVARCHAR(MAX) = N'[{"dimension":"life_stage","value":"senior"}]';
DECLARE @worker   NVARCHAR(MAX) = N'[{"dimension":"life_stage","value":"independent"},
                                     {"dimension":"role_mode","value":"professional"}]';
DECLARE @unknown  NVARCHAR(MAX) = N'[]';

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Dashboard].[CardType] WHERE IsActive = 1;
INSERT @results VALUES ('a card registry exists', CONCAT(@n, ' card types'),
    CASE WHEN @n >= 15 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  No magic numbers: priorities live in columns, so an operator can reorder
    the default dashboard without a deploy. */
SELECT @n = COUNT(*) FROM [Dashboard].[CardType]
WHERE BasePriority IS NULL OR BasePriority NOT BETWEEN 0 AND 100;
INSERT @results VALUES ('every card carries a configurable base priority',
    CONCAT(@n, ' invalid'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  Every eligibility rule and adjustment must say why it exists, or the
    dashboard becomes unconfigurable by anyone who did not write it. */
/*  Eligibility rules moved to Rules.Rule when the two matchers were
    consolidated; the requirement that every one explains itself did not. */
SELECT @n = (SELECT COUNT(*) FROM [Rules].[Rule]
             WHERE ScopeCode = 'dashboardCard' AND LEN(LTRIM(RuleNote)) = 0)
         + (SELECT COUNT(*) FROM [Dashboard].[PriorityAdjustment] WHERE LEN(LTRIM(ReasonText)) = 0);
INSERT @results VALUES ('every rule and adjustment explains itself',
    CONCAT(@n, ' unexplained'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
DELETE #cards;
INSERT #cards EXEC [Dashboard].[usp_Dashboard_Resolve]
    @UserId = @user, @ContextJson = @pregnant, @AsOfDate = @d;
SELECT @n = COUNT(*) FROM #cards WHERE CardTypeCode = 'baby_development';
INSERT @results VALUES ('a pregnant woman sees pregnancy cards',
    CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM #cards WHERE CardTypeCode IN ('study_focus', 'exam_countdown');
INSERT @results VALUES ('and not cards meant for a student', CONCAT(@n, ' leaked'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  Same platform, same engine, different woman. This is the whole point of
    the pivot: not nineteen apps, one that adapts. */
DELETE #cards;
INSERT #cards EXEC [Dashboard].[usp_Dashboard_Resolve]
    @UserId = @user, @ContextJson = @student, @AsOfDate = @d;
SELECT @n = CASE WHEN EXISTS (SELECT 1 FROM #cards WHERE CardTypeCode = 'study_focus')
                  AND NOT EXISTS (SELECT 1 FROM #cards WHERE CardTypeCode = 'baby_development')
            THEN 1 ELSE 0 END;
INSERT @results VALUES ('a student sees study cards and no pregnancy cards',
    CASE WHEN @n = 1 THEN 'adapted' ELSE 'wrong set' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  Cycle tracking is offered by default but withdrawn where it would be
    wrong, which a not_in rule expresses without listing every stage. */
DELETE #cards;
INSERT #cards EXEC [Dashboard].[usp_Dashboard_Resolve]
    @UserId = @user, @ContextJson = @senior, @AsOfDate = @d;
SELECT @n = COUNT(*) FROM #cards WHERE CardTypeCode = 'cycle_log';
INSERT @results VALUES ('a senior woman is not offered cycle tracking',
    CONCAT(@n, ' shown'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM #cards WHERE CardTypeCode = 'family_call';
INSERT @results VALUES ('and is offered cards meant for later life',
    CONCAT(@n, ' shown'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  A woman we know nothing about must still get a usable dashboard - the
    universal cards - without being guessed at. */
DELETE #cards;
INSERT #cards EXEC [Dashboard].[usp_Dashboard_Resolve]
    @UserId = @user, @ContextJson = @unknown, @AsOfDate = @d;
SELECT @n = CASE WHEN EXISTS (SELECT 1 FROM #cards WHERE CardTypeCode = 'hydration_prompt')
                  AND NOT EXISTS (SELECT 1 FROM #cards WHERE CardTypeCode = 'baby_development')
            THEN 1 ELSE 0 END;
INSERT @results VALUES ('an unknown woman gets universal cards only',
    CASE WHEN @n = 1 THEN 'universal only' ELSE 'guessed' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  Baseline order, before the timeline says anything. */
DELETE #cards;
INSERT #cards EXEC [Dashboard].[usp_Dashboard_Resolve]
    @UserId = @user, @ContextJson = @worker, @AsOfDate = @d;
SELECT @pHydration = Priority FROM #cards WHERE CardTypeCode = 'hydration_prompt';
SELECT @pSleep = Priority FROM #cards WHERE CardTypeCode = 'sleep_summary';
INSERT @results VALUES ('baseline priorities come from the registry',
    CONCAT('water=', @pHydration, ' sleep=', @pSleep),
    CASE WHEN @pHydration = 40 AND @pSleep = 45 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  Now the timeline speaks. Two short nights and two dry days inside the
    three-day window raise both signals. */
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'sleep', @OccurredUtc = '2026-07-19T23:00:00',
    @OccurredLocalDate = '2026-07-19', @ValueNumeric = 300;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'sleep', @OccurredUtc = '2026-07-20T23:00:00',
    @OccurredLocalDate = '2026-07-20', @ValueNumeric = 320;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'water', @OccurredUtc = '2026-07-19T12:00:00',
    @OccurredLocalDate = '2026-07-19', @ValueNumeric = 500;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'water', @OccurredUtc = '2026-07-20T12:00:00',
    @OccurredLocalDate = '2026-07-20', @ValueNumeric = 600;

DELETE #cards;
INSERT #cards EXEC [Dashboard].[usp_Dashboard_Resolve]
    @UserId = @user, @ContextJson = @worker, @AsOfDate = @d;
SELECT @n = Priority FROM #cards WHERE CardTypeCode = 'hydration_prompt';
INSERT @results VALUES ('poor sleep and low water raise hydration',
    CONCAT('40 -> ', @n),
    CASE WHEN @n = 40 + 35 + 15 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  Ordering, not just scoring: hydration must actually overtake sleep. */
SELECT @pHydration = Priority FROM #cards WHERE CardTypeCode = 'hydration_prompt';
SELECT @pSleep = Priority FROM #cards WHERE CardTypeCode = 'sleep_summary';
INSERT @results VALUES ('the timeline reorders the dashboard',
    CONCAT('water=', @pHydration, ' > sleep=', @pSleep),
    CASE WHEN @pHydration > @pSleep THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  Every card explains itself, and a card with no adjustment says so honestly
    rather than inventing a justification. */
SELECT @n = COUNT(*) FROM #cards
WHERE Reason IS NULL OR LEN(LTRIM(Reason)) = 0;
INSERT @results VALUES ('every card returned carries a reason',
    CONCAT(@n, ' unexplained'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  Suppression. Long working days push the reading nudge below zero, and a
    suppressed card must vanish rather than sit at the bottom. */
SELECT @pReading = COUNT(*) FROM #cards WHERE CardTypeCode = 'learning_nudge';

SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'work', @OccurredUtc = '2026-07-19T18:00:00',
    @OccurredLocalDate = '2026-07-19', @ValueNumeric = 700;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'work', @OccurredUtc = '2026-07-20T18:00:00',
    @OccurredLocalDate = '2026-07-20', @ValueNumeric = 720;

DELETE #cards;
INSERT #cards EXEC [Dashboard].[usp_Dashboard_Resolve]
    @UserId = @user, @ContextJson = @worker, @AsOfDate = @d;
SELECT @n = COUNT(*) FROM #cards WHERE CardTypeCode = 'learning_nudge';
INSERT @results VALUES ('a suppressed card disappears rather than ranks last',
    CONCAT('before=', @pReading, ' after=', @n),
    CASE WHEN @pReading = 1 AND @n = 0 THEN 'PASS' ELSE 'FAIL' END);

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

DROP TABLE #cards;
DELETE FROM [Timeline].[Event] WHERE UserId = @user;
DELETE FROM [Identity].[User]  WHERE UserId = @user;

IF @failed > 0
    THROW 51000, 'Dashboard engine assertions failed.', 1;
GO
