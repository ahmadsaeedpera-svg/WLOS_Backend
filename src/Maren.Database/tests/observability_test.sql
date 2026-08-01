SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Observability — correlation.

    `Audit.AuditLog.CorrelationId` existed, was read back, and was written by
    nothing: 157 audit rows and 0 correlated. The fix establishes the value once
    per connection in SESSION_CONTEXT and defaults the column from it, so an
    INSERT that omits the column picks it up.

    That property is what these assertions protect, and it is the whole reason
    the change was affordable: 33 existing write sites gained correlation
    without one of them being edited, and a new engine gets it by writing an
    audit row the ordinary way.

    The honesty assertion is 6. With no correlation established the column is
    NULL, not a manufactured value. An uncorrelated row is honest; one stamped
    with an invented id would be indistinguishable from a real trail and would
    therefore be believed.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/observability_test.sql -I
    Expect: TOTAL: 10  FAILED: 0

    Re-runnable: writes only rows it removes again.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @n INT;
DECLARE @probe UNIQUEIDENTIFIER = NEWID();
DECLARE @marker NVARCHAR(64) = CAST(@probe AS NVARCHAR(64));
DECLARE @read UNIQUEIDENTIFIER;

DELETE FROM [Audit].[AuditLog] WHERE EntityType = 'ObservabilityProbe';

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM sys.default_constraints
WHERE name = 'DF_AuditLog_CorrelationId';
INSERT @results VALUES ('the audit log correlation default exists',
    CONCAT(@n, ' constraint'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM sys.default_constraints
WHERE name = 'DF_SafetyEvent_CorrelationId';
INSERT @results VALUES ('the safety ledger correlation default exists',
    CONCAT(@n, ' constraint'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  Both defaults must read SESSION_CONTEXT and nothing else. A default that
    reached for a user id, a login name or a host would put a person into a
    column whose entire safety argument is that it identifies a request. */
SELECT @n = COUNT(*) FROM sys.default_constraints
WHERE name IN ('DF_AuditLog_CorrelationId', 'DF_SafetyEvent_CorrelationId')
  AND (definition NOT LIKE '%SESSION_CONTEXT%'
    OR definition LIKE '%SUSER%' OR definition LIKE '%USER_NAME%'
    OR definition LIKE '%HOST_NAME%' OR definition LIKE '%ORIGINAL_LOGIN%');
INSERT @results VALUES ('the defaults read the session and never a person',
    CONCAT(@n, ' offending'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM sys.objects
WHERE name = 'fn_CurrentCorrelation' AND type = 'FN';
INSERT @results VALUES ('one spelling of the current correlation exists',
    CONCAT(@n, ' function'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  The round trip that the whole design rests on: a write that does not mention
    correlation still becomes correlated. */
EXEC sp_set_session_context @key = N'CorrelationId', @value = @probe;

INSERT INTO [Audit].[AuditLog]
    (OccurredUtc, ActorUserId, ActorKind, [Action], EntityType, EntityId)
VALUES
    (SYSUTCDATETIME(), NULL, 'system', 'observability.probe',
     'ObservabilityProbe', @marker);

SELECT @read = CorrelationId FROM [Audit].[AuditLog]
WHERE EntityType = 'ObservabilityProbe' AND EntityId = @marker;

INSERT @results VALUES ('a write that omits the column is still correlated',
    CASE WHEN @read IS NULL THEN 'null' ELSE 'correlated' END,
    CASE WHEN @read = @probe THEN 'PASS' ELSE 'FAIL' END);

DELETE FROM [Audit].[AuditLog] WHERE EntityType = 'ObservabilityProbe';

-- 6 -------------------------------------------------------------------------
/*  The honesty assertion. No correlation means NULL, never a stand-in. */
EXEC sp_set_session_context @key = N'CorrelationId', @value = NULL;

INSERT INTO [Audit].[AuditLog]
    (OccurredUtc, ActorUserId, ActorKind, [Action], EntityType, EntityId)
VALUES
    (SYSUTCDATETIME(), NULL, 'system', 'observability.probe',
     'ObservabilityProbe', @marker);

SELECT @read = CorrelationId FROM [Audit].[AuditLog]
WHERE EntityType = 'ObservabilityProbe' AND EntityId = @marker;

INSERT @results VALUES ('with no correlation the column is null, not invented',
    CASE WHEN @read IS NULL THEN 'null' ELSE CAST(@read AS NVARCHAR(40)) END,
    CASE WHEN @read IS NULL THEN 'PASS' ELSE 'FAIL' END);

DELETE FROM [Audit].[AuditLog] WHERE EntityType = 'ObservabilityProbe';

-- 7 -------------------------------------------------------------------------
/*  One truth. The correlation id is established in exactly one place — the
    connection factory — and nothing in the database may set its own. A
    procedure that did would be a second source, and the two would disagree the
    first time one of them changed. */
SELECT @n = COUNT(*)
FROM sys.sql_modules sm
JOIN sys.objects o ON o.object_id = sm.object_id
WHERE o.type IN ('P', 'FN', 'TF', 'IF', 'TR')
  AND sm.definition LIKE '%sp_set_session_context%';
INSERT @results VALUES ('nothing in the database sets its own correlation',
    CONCAT(@n, ' setting it'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  The column must stay nullable. Making it NOT NULL would force every write
    path to invent a value, which is precisely the outcome assertion 6 refuses. */
SELECT @n = COUNT(*)
FROM sys.columns
WHERE object_id = OBJECT_ID('Audit.AuditLog')
  AND name = 'CorrelationId' AND is_nullable = 1;
INSERT @results VALUES ('unknown correlation remains representable',
    CONCAT(@n, ' nullable'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  Correlation must not have weakened the append-only guarantee it was added
    to serve.

    The verb must be matched against the table it targets, not merely found in
    the same procedure. Roughly thirty procedures write an audit row while
    legitimately updating their own domain tables — publishing content, rotating
    a token — and a guard that flagged those would report twenty-two offenders
    that do not exist. It did, on the first run of this suite.

    So: normalise the module text (brackets are a character class in a LIKE
    pattern, and newlines hide adjacency), then look for a mutation verb
    immediately against Audit.AuditLog. */
;WITH flattened AS (
    SELECT o.object_id,
           REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               sm.definition, CHAR(13), ' '), CHAR(10), ' '), CHAR(9), ' '),
               '[', ''), ']', '') AS body
    FROM sys.sql_modules sm
    JOIN sys.objects o ON o.object_id = sm.object_id
    WHERE o.type = 'P'
),
collapsed AS (
    SELECT object_id,
           REPLACE(REPLACE(REPLACE(REPLACE(body, '  ', ' '), '  ', ' '),
                   '  ', ' '), '  ', ' ') AS body
    FROM flattened
)
SELECT @n = COUNT(*)
FROM collapsed
WHERE body LIKE '%UPDATE Audit.AuditLog%'
   OR body LIKE '%DELETE FROM Audit.AuditLog%'
   OR body LIKE '%TRUNCATE TABLE Audit.AuditLog%';
INSERT @results VALUES ('the audit log is still append-only',
    CONCAT(@n, ' rewriting'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  Every table that carries a correlation id must default it. A table added
    later with the column and no default would silently write NULLs forever, and
    look exactly like a table nobody had correlated yet. */
SELECT @n = COUNT(*)
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
WHERE c.name = 'CorrelationId'
  AND c.default_object_id = 0;
INSERT @results VALUES ('every correlation column defaults from the session',
    CONCAT(@n, ' without a default'),
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

IF @failed > 0
    THROW 51000, 'Observability assertions failed.', 1;
GO
