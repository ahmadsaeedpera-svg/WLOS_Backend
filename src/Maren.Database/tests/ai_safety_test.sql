SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    AI safety ledger verification.

    The companion's two rules - never diagnose, never prescribe - are enforced
    in four independent places (docs/ai/AI_SYSTEM.md section 2). This table is
    how anyone knows whether they are still holding.

    Assertion 2 is the one that matters most. The ledger must not be able to
    hold message content, because the product's privacy position is that
    conversation stays on the device. That position survives exactly as long as
    nobody adds a Message column "just for debugging", so it is asserted here
    rather than written in a comment somebody can overrule.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/ai_safety_test.sql -I

    Expect: TOTAL: 8  FAILED: 0

    Read-only apart from rows it inserts and removes inside a rolled-back
    transaction.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @n INT;

-- 1 -------------------------------------------------------------------------
INSERT @results
SELECT 'safety ledger exists', 'AI.SafetyEvent',
       CASE WHEN OBJECT_ID('AI.SafetyEvent') IS NOT NULL THEN 'PASS' ELSE 'FAIL' END;

-- 2 -------------------------------------------------------------------------
/*  No column may hold message content.

    Two checks in one: nothing named like a message, and no LOB text column at
    all. The second catches the case where somebody adds NVARCHAR(MAX) under an
    innocent name such as "Detail" or "Payload". */
SELECT @n = COUNT(*)
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('AI.SafetyEvent')
  AND (
        c.[name] LIKE '%Message%' OR c.[name] LIKE '%Content%'
     OR c.[name] LIKE '%Text%'    OR c.[name] LIKE '%Body%'
     OR c.[name] LIKE '%Prompt%Text%' OR c.[name] LIKE '%Response%'
     OR c.[name] LIKE '%Transcript%'  OR c.[name] LIKE '%Utterance%'
     OR (t.[name] IN ('nvarchar','varchar','nchar','char') AND c.max_length = -1)
  );

INSERT @results
SELECT 'ledger cannot hold message content',
       CONCAT('content-shaped columns: ', @n),
       CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END;

-- 3 -------------------------------------------------------------------------
/*  Append-only: nothing may update or delete it. Mirrors the rule enforced on
    Audit.AuditLog. Checked against every procedure body in the database. */
SELECT @n = COUNT(*)
FROM sys.sql_modules m
WHERE (m.definition LIKE '%UPDATE%SafetyEvent%'
    OR m.definition LIKE '%DELETE%SafetyEvent%'
    OR m.definition LIKE '%TRUNCATE%SafetyEvent%');

INSERT @results
SELECT 'no procedure updates or deletes the ledger',
       CONCAT('offending modules: ', @n),
       CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END;

-- 4 -------------------------------------------------------------------------
/*  Exempt from the audit-column contract, with a reason recorded. Without this
    the second application of 08_AuditContract.sql gives an append-only ledger
    a DeletedOn column. */
SELECT @n = COUNT(*)
FROM dbo.AuditContractExemption
WHERE SchemaName = 'AI' AND TableName = 'SafetyEvent' AND LEN(Reason) > 0;

INSERT @results
SELECT 'registered as exempt from the audit contract',
       CASE WHEN @n = 1 THEN 'with a reason' ELSE 'missing' END,
       CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END;

-- 5 -------------------------------------------------------------------------
/*  Soft-delete columns must not have appeared despite the exemption. */
SELECT @n = COUNT(*)
FROM sys.columns
WHERE object_id = OBJECT_ID('AI.SafetyEvent')
  AND [name] IN ('IsDeleted', 'DeletedOn', 'DeletedBy');

INSERT @results
SELECT 'ledger has no soft-delete columns',
       CONCAT('found: ', @n),
       CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END;

-- 6, 7, 8 -------------------------------------------------------------------
/*  The constraints do their job. Written inside a transaction that is always
    rolled back, so the suite is re-runnable and leaves nothing behind. */
BEGIN TRAN;

    DECLARE @rejectedDomain BIT = 0, @rejectedDecision BIT = 0, @rejectedCategory BIT = 0;

    BEGIN TRY
        INSERT [AI].[SafetyEvent] ([Domain], Decision, PromptVersion)
        VALUES ('astrology', 'answered', 'test');
    END TRY
    BEGIN CATCH
        SET @rejectedDomain = 1;
    END CATCH

    BEGIN TRY
        INSERT [AI].[SafetyEvent] ([Domain], Decision, PromptVersion)
        VALUES ('sleep', 'diagnosed', 'test');
    END TRY
    BEGIN CATCH
        SET @rejectedDecision = 1;
    END CATCH

    /*  A refusal with no category is unalertable, so the schema refuses it. */
    BEGIN TRY
        INSERT [AI].[SafetyEvent] ([Domain], Decision, PromptVersion)
        VALUES ('sleep', 'refused', 'test');
    END TRY
    BEGIN CATCH
        SET @rejectedCategory = 1;
    END CATCH

ROLLBACK;

INSERT @results VALUES ('an unknown domain is rejected',
    CASE WHEN @rejectedDomain = 1 THEN 'rejected' ELSE 'accepted' END,
    CASE WHEN @rejectedDomain = 1 THEN 'PASS' ELSE 'FAIL' END);

INSERT @results VALUES ('an unknown decision is rejected',
    CASE WHEN @rejectedDecision = 1 THEN 'rejected' ELSE 'accepted' END,
    CASE WHEN @rejectedDecision = 1 THEN 'PASS' ELSE 'FAIL' END);

INSERT @results VALUES ('a refusal without a category is rejected',
    CASE WHEN @rejectedCategory = 1 THEN 'rejected' ELSE 'accepted' END,
    CASE WHEN @rejectedCategory = 1 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 60), 60) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 30), 30) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

IF @failed > 0
    THROW 51000, 'AI safety ledger assertions failed.', 1;
GO
