SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Life domain and knowledge graph verification.

    Assertions 1 to 4 are the ones that matter most, and none of them tests a
    feature. They test that the graph has not quietly become a diagnostic
    engine: that the relation vocabulary contains no causal verb, that every
    edge carries a justification, and that health observations are marked so
    later engines cannot use them to generate advice.

    Those are the assertions that will be inconvenient one day. That is
    precisely why they exist - the change that adds "causes" will arrive in a
    hurry and look harmless in review.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/knowledge_graph_test.sql -I
    Expect: TOTAL: 14  FAILED: 0

    Re-runnable: owns its user and removes it at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @user UNIQUEIDENTIFIER = '00000000-0000-0000-0000-00000000CAFE';
DECLARE @n INT, @tmp UNIQUEIDENTIFIER, @d DATE = '2026-07-20';

DELETE FROM [Timeline].[Event] WHERE UserId = @user;
DELETE FROM [Identity].[User]  WHERE UserId = @user;
INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail, PasswordHash,
                               PasswordSalt, PasswordIterations, SecurityStamp)
VALUES (@user, 'kg-test@example.com', 'KG-TEST@EXAMPLE.COM', 0x00, 0x00, 210000, NEWID());

-- 1 -------------------------------------------------------------------------
/*  The vocabulary must not contain a causal verb. A graph that says one thing
    causes another has diagnosed something. */
SELECT @n = COUNT(*)
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID('Knowledge.SignalRelation')
  AND name = 'CK_SignalRelation_Kind'
  AND (definition LIKE '%cause%' OR definition LIKE '%leads_to%'
    OR definition LIKE '%results_in%' OR definition LIKE '%due_to%');
INSERT @results VALUES ('the relation vocabulary contains no causal verb',
    CASE WHEN @n = 0 THEN 'observational only' ELSE 'CAUSAL VERB PRESENT' END,
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Knowledge].[SignalRelation]
WHERE RelationKind NOT IN ('commonly_precedes', 'commonly_co_occurs', 'may_relate_to');
INSERT @results VALUES ('every stored edge uses an observational kind',
    CONCAT(@n, ' violation(s)'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  An edge nobody can justify is an opinion presented as knowledge. */
SELECT @n = COUNT(*) FROM [Knowledge].[SignalRelation]
WHERE SourceNote IS NULL OR LEN(LTRIM(RTRIM(SourceNote))) = 0;
INSERT @results VALUES ('every edge carries a justification', CONCAT(@n, ' unjustified'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  Health observations must be flagged, or a later engine will score them. */
SELECT @n = COUNT(*) FROM [Knowledge].[Signal]
WHERE SignalCode IN ('headache', 'symptom_reported') AND IsHealthSensitive = 0;
INSERT @results VALUES ('health observations are flagged as sensitive',
    CONCAT(@n, ' unflagged'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  No rule may derive a health-sensitive signal from a threshold. Detecting a
    headache from a number is the line between wellness and diagnosis. */
SELECT @n = COUNT(*)
FROM [Knowledge].[SignalRule] r
JOIN [Knowledge].[Signal] s ON s.SignalCode = r.SignalCode
WHERE s.IsHealthSensitive = 1;
INSERT @results VALUES ('no threshold rule derives a health-sensitive signal',
    CONCAT(@n, ' rule(s)'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Content].[LifeDomain] WHERE IsActive = 1;
INSERT @results VALUES ('life domains are seeded', CONCAT(@n, ' domains'),
    CASE WHEN @n >= 25 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  The registry must actually be authoritative for event categories. */
SELECT @n = COUNT(*) FROM sys.foreign_keys WHERE name = 'FK_EventType_Domain';
INSERT @results VALUES ('event categories reference the domain registry',
    CASE WHEN @n = 1 THEN 'FK present' ELSE 'FK missing' END,
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Timeline].[EventType] et
WHERE NOT EXISTS (SELECT 1 FROM [Content].[LifeDomain] d WHERE d.DomainCode = et.Category);
INSERT @results VALUES ('no event type has an unregistered category',
    CONCAT(@n, ' orphan(s)'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  The hierarchy must be a tree. A cycle makes every traversal non-terminating
    and CHECK constraints cannot express it. */
;WITH walk AS (
    SELECT DomainCode, ParentDomainCode, 1 AS Depth,
           CAST('|' + DomainCode + '|' AS NVARCHAR(1000)) AS Path
    FROM [Content].[LifeDomain] WHERE ParentDomainCode IS NOT NULL
    UNION ALL
    SELECT w.DomainCode, d.ParentDomainCode, w.Depth + 1,
           CAST(w.Path + d.DomainCode + '|' AS NVARCHAR(1000))
    FROM walk w
    JOIN [Content].[LifeDomain] d ON d.DomainCode = w.ParentDomainCode
    WHERE w.Depth < 10 AND w.Path NOT LIKE '%|' + d.DomainCode + '|%'
)
SELECT @n = COUNT(*) FROM walk WHERE Depth >= 10;
INSERT @results VALUES ('the domain hierarchy has no cycle', CONCAT(@n, ' deep path(s)'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  Detection. Two days under 6 hours of sleep within the 3-day window. */
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'sleep', @OccurredUtc = '2026-07-19T23:00:00',
    @OccurredLocalDate = '2026-07-19', @ValueNumeric = 300;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'sleep', @OccurredUtc = '2026-07-20T23:00:00',
    @OccurredLocalDate = '2026-07-20', @ValueNumeric = 320;

CREATE TABLE #sig (SignalCode VARCHAR(40), DisplayName NVARCHAR(80),
    DomainCode VARCHAR(30), ObservationText NVARCHAR(300),
    IsHealthSensitive BIT, BreachDays INT);
INSERT #sig EXEC [Knowledge].[usp_Knowledge_EvaluateSignals]
    @UserId = @user, @AsOfDate = @d;
SELECT @n = COUNT(*) FROM #sig WHERE SignalCode = 'short_sleep';
INSERT @results VALUES ('short sleep is detected from the timeline',
    CONCAT(@n, ' signal(s)'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  One bad night is not a pattern. MinBreachDays is 2, so a single breach
    must not raise the signal - the difference between a companion and a nag. */
DELETE FROM [Timeline].[Event] WHERE UserId = @user;
SET @tmp = NEWID();
EXEC [Timeline].[usp_Timeline_Record] @EventId = @tmp, @UserId = @user,
    @EventTypeCode = 'sleep', @OccurredUtc = '2026-07-20T23:00:00',
    @OccurredLocalDate = '2026-07-20', @ValueNumeric = 300;
DELETE #sig;
INSERT #sig EXEC [Knowledge].[usp_Knowledge_EvaluateSignals]
    @UserId = @user, @AsOfDate = @d;
SELECT @n = COUNT(*) FROM #sig WHERE SignalCode = 'short_sleep';
INSERT @results VALUES ('a single off day does not raise a signal',
    CONCAT(@n, ' signal(s)'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  Silence is not a breach. Logging nothing must never be read as doing
    badly, or the platform scolds her for stopping recording. */
DELETE FROM [Timeline].[Event] WHERE UserId = @user;
DELETE #sig;
INSERT #sig EXEC [Knowledge].[usp_Knowledge_EvaluateSignals]
    @UserId = @user, @AsOfDate = @d;
SELECT @n = COUNT(*) FROM #sig;
INSERT @results VALUES ('no data raises no signals', CONCAT(@n, ' signal(s)'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
CREATE TABLE #rel (SignalCode VARCHAR(40), DisplayName NVARCHAR(80),
    DomainCode VARCHAR(30), ObservationText NVARCHAR(300),
    IsHealthSensitive BIT, Depth INT, Strength DECIMAL(10,6));
INSERT #rel EXEC [Knowledge].[usp_Knowledge_Related]
    @SignalCode = 'short_sleep', @MaxDepth = 2;
SELECT @n = COUNT(*) FROM #rel WHERE SignalCode = 'late_wake' AND Depth = 1;
INSERT @results VALUES ('the graph walks outward from a signal',
    CONCAT(@n, ' first-hop match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  The seed contains a legitimate two-way pair (stress and short sleep), so a
    traversal that did not track its path would not terminate. */
SELECT @n = COUNT(*) FROM #rel WHERE SignalCode = 'short_sleep';
INSERT @results VALUES ('a cycle does not revisit the origin',
    CONCAT(@n, ' self-reference(s)'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 58), 58) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 22), 22) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DROP TABLE #sig; DROP TABLE #rel;
DELETE FROM [Timeline].[Event] WHERE UserId = @user;
DELETE FROM [Identity].[User]  WHERE UserId = @user;

IF @failed > 0
    THROW 51000, 'Knowledge graph assertions failed.', 1;
GO
