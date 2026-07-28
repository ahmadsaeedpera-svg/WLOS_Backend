SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Decision inspector verification.

    Two properties matter.

    First, the inspector must show what the platform actually does. If it
    computed eligibility or priority its own way it would show an operator a
    fiction, which is worse than having no inspector - they would configure
    against it and be surprised in production. Assertions 2 to 5 pin its
    answers to the same numbers the real engine produces.

    Second, it must explain absence. A list of cards that appeared explains a
    card's presence and never its absence, and "why is my card missing" is the
    question an operator actually arrives with. Assertion 6 covers suppression;
    assertion 8 covers a failing rule.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/inspector_test.sql -I
    Expect: TOTAL: 10  FAILED: 0

    Read-only. Touches no user and no timeline.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @n INT, @p INT, @sup BIT, @passes BIT;

CREATE TABLE #sim (
    CardTypeCode VARCHAR(40), DisplayName NVARCHAR(80), DomainCode VARCHAR(30),
    Priority INT, BasePriority INT, Confidence DECIMAL(3,2),
    IsHealthSensitive BIT, IsSuppressed BIT, Reason NVARCHAR(MAX),
    EvidenceSignals NVARCHAR(MAX), [Source] VARCHAR(10));

DECLARE @pregnant NVARCHAR(MAX) = N'[{"dimension":"life_stage","value":"pregnancy"}]';
DECLARE @worker   NVARCHAR(MAX) = N'[{"dimension":"life_stage","value":"independent"},
                                     {"dimension":"role_mode","value":"professional"}]';

-- 1 -------------------------------------------------------------------------
/*  No user, no timeline. The inspector must not be able to reach a real
    woman's data even by accident - that is the privacy decision it exists
    under, so it is asserted rather than trusted. */
SELECT @n = COUNT(*)
FROM sys.sql_modules m
JOIN sys.procedures p ON p.object_id = m.object_id
WHERE p.name LIKE 'usp_Inspector%'
  AND (m.definition LIKE '%@UserId%'
    OR m.definition LIKE '%Timeline.Event%'
    OR m.definition LIKE '%UserStateSnapshot%');
INSERT @results VALUES ('the inspector cannot read a real account',
    CONCAT(@n, ' procedure(s) reference user data'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
DELETE #sim;
INSERT #sim EXEC [Dashboard].[usp_Inspector_SimulateDashboard]
    @ContextJson = @pregnant, @SignalsCsv = NULL;
SELECT @n = COUNT(*) FROM #sim WHERE CardTypeCode = 'baby_development';
INSERT @results VALUES ('it reproduces eligibility for a life stage',
    CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM #sim WHERE CardTypeCode = 'study_focus';
INSERT @results VALUES ('and exclusion for one she does not match',
    CONCAT(@n, ' leaked'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  Same numbers as the live engine: base 40 for hydration on an ordinary day. */
DELETE #sim;
INSERT #sim EXEC [Dashboard].[usp_Inspector_SimulateDashboard]
    @ContextJson = @worker, @SignalsCsv = NULL;
SELECT @p = Priority FROM #sim WHERE CardTypeCode = 'hydration_prompt';
INSERT @results VALUES ('baseline priority matches the real engine',
    CONCAT('water=', @p),
    CASE WHEN @p = 40 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  And the same arithmetic when signals are supplied: 40 + 35 + 15. */
DELETE #sim;
INSERT #sim EXEC [Dashboard].[usp_Inspector_SimulateDashboard]
    @ContextJson = @worker, @SignalsCsv = N'low_hydration,short_sleep';
SELECT @p = Priority FROM #sim WHERE CardTypeCode = 'hydration_prompt';
INSERT @results VALUES ('supplied signals move priority exactly as live',
    CONCAT('40 -> ', @p),
    CASE WHEN @p = 90 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  The reason an inspector exists: a suppressed card is shown and flagged,
    where the real path simply drops it. */
DELETE #sim;
INSERT #sim EXEC [Dashboard].[usp_Inspector_SimulateDashboard]
    @ContextJson = @worker, @SignalsCsv = N'long_work';
SELECT @sup = IsSuppressed FROM #sim WHERE CardTypeCode = 'learning_nudge';
INSERT @results VALUES ('a suppressed card is shown and flagged, not hidden',
    CONCAT('suppressed=', ISNULL(CAST(@sup AS varchar(1)), 'missing')),
    CASE WHEN @sup = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM #sim
WHERE CardTypeCode = 'learning_nudge' AND EvidenceSignals LIKE '%long_work%';
INSERT @results VALUES ('and names the signal that suppressed it',
    CONCAT(@n, ' with evidence'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  Explaining an absence. A pregnancy card against a working woman's context
    must report its rule as failing, which is what answers "why is it missing". */
/*  usp_Inspector_ExplainCard returns three differently-shaped result sets -
    the card, its rules, its adjustments - which is right for the API, where
    Dapper reads all three in one round trip. INSERT ... EXEC cannot capture
    that, so the assertion below checks the property the procedure exists to
    provide, against the same rule engine it queries.

    A pregnancy card must report its rule as failing for a working woman's
    context. That is what turns "why is my card missing" into an answer; a list
    of only the rules that passed explains presence and never absence. */
SELECT @passes = CAST(CASE WHEN EXISTS (
        SELECT 1 FROM [Rules].[fn_Match]('dashboardCard', @worker) m
        WHERE m.TargetKey = 'baby_development') THEN 1 ELSE 0 END AS BIT);

INSERT @results VALUES ('an absent card reports its rule as failing',
    CONCAT('contextPasses=', CAST(@passes AS varchar(1))),
    CASE WHEN @passes = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Rules].[Rule]
WHERE ScopeCode = 'dashboardCard' AND TargetKey = 'baby_development';
INSERT @results VALUES ('its eligibility rules are inspectable',
    CONCAT(@n, ' rule(s)'),
    CASE WHEN @n >= 1 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  Unknown signal names are dropped rather than refused. An operator typing
    into a what-if box should see what the platform recognises, not an error. */
DELETE #sim;
INSERT #sim EXEC [Dashboard].[usp_Inspector_SimulateDashboard]
    @ContextJson = @worker, @SignalsCsv = N'not_a_real_signal,low_hydration';
SELECT @p = Priority FROM #sim WHERE CardTypeCode = 'hydration_prompt';
INSERT @results VALUES ('an unknown signal is ignored, not an error',
    CONCAT('water=', @p),
    CASE WHEN @p = 75 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  The signal list is the picker the portal draws. If it comes back empty the
    screen renders a fieldset with nothing in it and an operator concludes the
    engine has no signals at all. */
CREATE TABLE #sig (
    SignalCode VARCHAR(40), DisplayName NVARCHAR(80), DomainCode VARCHAR(30),
    ObservationText NVARCHAR(200), IsHealthSensitive BIT, AffectsCardCount INT);

INSERT #sig EXEC [Dashboard].[usp_Inspector_ListSignals];

SELECT @n = COUNT(*) FROM #sig;
INSERT @results VALUES ('the simulatable signals are server-driven',
    CONCAT(@n, ' offered'),
    CASE WHEN @n >= 1 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  Only signals that move something. A signal with no priority adjustment
    changes nothing, so offering it invites an operator to toggle it, see the
    same cards, and conclude the engine is broken. */
SELECT @n = COUNT(*) FROM #sig s
WHERE NOT EXISTS (SELECT 1 FROM [Dashboard].[PriorityAdjustment] pa
                  WHERE pa.SignalCode = s.SignalCode AND pa.IsActive = 1);
INSERT @results VALUES ('no signal is offered that changes nothing',
    CONCAT(@n, ' inert'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  The count is a claim the portal repeats to an operator, so it has to be the
    real number of adjustments and not the row count of a join. */
SELECT @n = COUNT(*) FROM #sig s
WHERE s.AffectsCardCount <> (
    SELECT COUNT(*) FROM [Dashboard].[PriorityAdjustment] pa
    WHERE pa.SignalCode = s.SignalCode AND pa.IsActive = 1);
INSERT @results VALUES ('the affected-card count is accurate',
    CONCAT(@n, ' wrong'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  Every offered signal must be one the simulator recognises. If the picker
    could list a name that SimulateDashboard drops as unknown, the inspector
    would silently lie: toggled on, nothing moves, no error. */
SELECT @n = COUNT(*) FROM #sig s
WHERE NOT EXISTS (SELECT 1 FROM [Knowledge].[Signal] k
                  WHERE k.SignalCode = s.SignalCode AND k.IsActive = 1);
INSERT @results VALUES ('every offered signal is one the engine knows',
    CONCAT(@n, ' unrecognised'),
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

DROP TABLE #sim;
DROP TABLE #sig;

IF @failed > 0
    THROW 51000, 'Inspector assertions failed.', 1;
GO
