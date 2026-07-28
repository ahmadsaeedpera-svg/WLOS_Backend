/*  audit_contract_test.sql

    The audit contract, asserted in the database.

    AuditContractTests in C# already checks compliance. This suite exists
    because the defect it is guarding against was not non-compliance — it was
    *ordering*. 08_AuditContract.sql applies the contract with a cursor over
    sys.tables at position 9 of 37, and every table created after it was
    invisible to that pass. A single ordered run on an empty server left 19
    tables short by 147 columns and 19 filtered indexes, and the C# suite had
    never caught it because the databases it ran against had been built with an
    extra pass.

    So these assertions run where a deployment runs, against whatever the
    scripts just produced, rather than against a database somebody has been
    re-applying scripts to for a week.
*/

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

PRINT '';
PRINT '=== audit contract ==========================================================';

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @n INT;

-- 1 -------------------------------------------------------------------------
/*  The mechanism itself. If the procedure is gone the later script throws, but
    a missing procedure with a stale database still looks green. */
SELECT @n = CASE WHEN OBJECT_ID('dbo.usp_ApplyAuditContract') IS NOT NULL
                 THEN 1 ELSE 0 END;
INSERT @results VALUES ('the contract is applied by one reusable procedure',
    CONCAT('exists=', @n),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  The eight columns, on every table that is not exempt. This is the assertion
    that was failing on a genuinely fresh database. */
SELECT @n = COUNT(*)
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE NOT EXISTS (SELECT 1 FROM dbo.AuditContractExemption e
                  WHERE e.SchemaName = s.name AND e.TableName = t.name)
  AND t.name <> 'AuditContractExemption'
  AND EXISTS (
        SELECT 1 FROM (VALUES ('CreatedBy'), ('CreatedOn'), ('ModifiedBy'),
                              ('ModifiedOn'), ('DeletedBy'), ('DeletedOn'),
                              ('IsDeleted')) AS required(col)
        WHERE NOT EXISTS (SELECT 1 FROM sys.columns c
                          WHERE c.object_id = t.object_id AND c.name = required.col));
INSERT @results VALUES ('every table carries the audit columns',
    CONCAT(@n, ' non-compliant'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  Checked by type, not name: SQL Server allows one ROWVERSION per table, so a
    column called something else still satisfies concurrency. Without it a table
    allows silent last-write-wins. */
SELECT @n = COUNT(*)
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE NOT EXISTS (SELECT 1 FROM dbo.AuditContractExemption e
                  WHERE e.SchemaName = s.name AND e.TableName = t.name)
  AND t.name <> 'AuditContractExemption'
  AND NOT EXISTS (SELECT 1 FROM sys.columns c
                  WHERE c.object_id = t.object_id AND c.system_type_id = 189);
INSERT @results VALUES ('every table has a rowversion',
    CONCAT(@n, ' without'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  Every query that respects soft delete filters on IsDeleted = 0, and deleted
    rows accumulate forever because soft delete never removes anything. Without
    the filtered index that filter is applied after a scan that grows without
    bound. */
SELECT @n = COUNT(*)
FROM sys.tables t
WHERE EXISTS (SELECT 1 FROM sys.columns c
              WHERE c.object_id = t.object_id AND c.name = 'IsDeleted')
  AND NOT EXISTS (SELECT 1 FROM sys.indexes i
                  WHERE i.object_id = t.object_id
                    AND i.name = 'IX_' + t.name + '_NotDeleted');
INSERT @results VALUES ('soft-delete filtered indexes exist',
    CONCAT(@n, ' unindexed'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  The tables the ordering defect actually left exposed. Named explicitly
    because a count can be satisfied by an exemption, and these two must never
    be exempt: they hold what a woman logs and what the platform infers from
    it. */
SELECT @n = COUNT(*)
FROM (VALUES ('Timeline', 'Event'),
             ('Intelligence', 'UserStateSnapshot'),
             ('Knowledge', 'Signal'),
             ('Rules', 'Rule')) AS must(SchemaName, TableName)
JOIN sys.tables t ON t.name = must.TableName
JOIN sys.schemas s ON s.schema_id = t.schema_id AND s.name = must.SchemaName
WHERE NOT EXISTS (SELECT 1 FROM sys.columns c
                  WHERE c.object_id = t.object_id AND c.name = 'IsDeleted')
   OR EXISTS (SELECT 1 FROM dbo.AuditContractExemption e
              WHERE e.SchemaName = must.SchemaName AND e.TableName = must.TableName);
INSERT @results VALUES ('the intelligence tables are covered, not exempted',
    CONCAT(@n, ' exposed'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  An exemption without a reason is a hiding place. Two exist today and both
    are argued in the row itself. */
SELECT @n = COUNT(*) FROM dbo.AuditContractExemption
WHERE Reason IS NULL OR LEN(LTRIM(Reason)) < 40;
INSERT @results VALUES ('every exemption is justified in the row',
    CONCAT(@n, ' unjustified'),
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

IF @failed > 0
    THROW 51000, 'Audit contract assertions failed.', 1;
GO
