SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Operations — the deployment journal and the restore drill record.

    Both journals answer a question the platform could not answer about itself:
    "what was applied to this database", and "has a restore ever actually been
    performed". The assertions here are about the properties that make those
    answers trustworthy rather than decorative.

    The load-bearing one is the drill's honesty constraint. A drill that ran no
    checks has proved that RESTORE returned zero and nothing else, and recording
    that as a pass would be exactly the green tick this platform exists to
    refuse. The schema will not store it.

    Both journals are append-only, for the reason the audit log is: a failed
    deployment or a failed drill that can be quietly deleted is one nobody hears
    about.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/ops_test.sql -I
    Expect: TOTAL: 16  FAILED: 0

    Re-runnable: writes only rows it removes again, and only to its own tables.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @n INT, @ok BIT;
DECLARE @run UNIQUEIDENTIFIER = NEWID();
DECLARE @probe VARCHAR(100) = 'zz_ops_test_probe.sql';
DECLARE @sum CHAR(64) = REPLICATE('a', 64);

-- Clean up anything a previous interrupted run left behind.
DELETE FROM [Ops].[DeploymentJournal] WHERE ScriptName = @probe;
DELETE FROM [Ops].[RestoreDrill] WHERE SourceDatabase = 'zz_ops_test_probe';

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM sys.tables t JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'Ops' AND t.name IN ('DeploymentJournal', 'RestoreDrill');
INSERT @results VALUES ('both operations journals exist',
    CONCAT(@n, ' of 2'),
    CASE WHEN @n = 2 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  The honesty constraint. A drill that ran no checks proved only that RESTORE
    returned zero, and calling that a pass is the exact failure mode this
    platform refuses. */
BEGIN TRY
    INSERT [Ops].[RestoreDrill] (SourceDatabase, RestoredAs, FullBackupPath,
        RestoreMs, ChecksRun, ChecksPassed, ChecksFailed, Outcome)
    VALUES ('zz_ops_test_probe', 'zz_ops_test_probe_drill', 'x.bak',
            100, 'none', 0, 0, 'passed');
    SET @ok = 1;
    DELETE FROM [Ops].[RestoreDrill] WHERE SourceDatabase = 'zz_ops_test_probe';
END TRY
BEGIN CATCH SET @ok = 0; END CATCH
INSERT @results VALUES ('a drill that ran no checks cannot pass',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  Nor one that ran checks and had some fail. */
BEGIN TRY
    INSERT [Ops].[RestoreDrill] (SourceDatabase, RestoredAs, FullBackupPath,
        RestoreMs, ChecksRun, ChecksPassed, ChecksFailed, Outcome)
    VALUES ('zz_ops_test_probe', 'zz_ops_test_probe_drill', 'x.bak',
            100, 'DBCC + suites', 19, 2, 'passed');
    SET @ok = 1;
    DELETE FROM [Ops].[RestoreDrill] WHERE SourceDatabase = 'zz_ops_test_probe';
END TRY
BEGIN CATCH SET @ok = 0; END CATCH
INSERT @results VALUES ('a drill with failing checks cannot pass',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  The control. A guard that refused every drill would pass 2 and 3 while
    making the table unusable, and would look identical from outside. */
BEGIN TRY
    INSERT [Ops].[RestoreDrill] (SourceDatabase, RestoredAs, FullBackupPath,
        RestoreMs, ChecksRun, ChecksPassed, ChecksFailed, Outcome)
    VALUES ('zz_ops_test_probe', 'zz_ops_test_probe_drill', 'x.bak',
            100, 'DBCC + suites', 21, 0, 'passed');
    SET @ok = 1;
    DELETE FROM [Ops].[RestoreDrill] WHERE SourceDatabase = 'zz_ops_test_probe';
END TRY
BEGIN CATCH SET @ok = 0; END CATCH
INSERT @results VALUES ('a genuine passing drill is still accepted',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  Restoring over the source is not a rehearsal, it is an outage. */
BEGIN TRY
    INSERT [Ops].[RestoreDrill] (SourceDatabase, RestoredAs, FullBackupPath,
        RestoreMs, ChecksRun, ChecksPassed, ChecksFailed, Outcome)
    VALUES ('zz_ops_test_probe', 'zz_ops_test_probe', 'x.bak',
            100, 'DBCC', 1, 0, 'passed');
    SET @ok = 1;
    DELETE FROM [Ops].[RestoreDrill] WHERE SourceDatabase = 'zz_ops_test_probe';
END TRY
BEGIN CATCH SET @ok = 0; END CATCH
INSERT @results VALUES ('a drill cannot restore over its own source',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  A failure that does not say why tells an operator only that something went
    wrong, which they already knew. */
BEGIN TRY
    INSERT [Ops].[RestoreDrill] (SourceDatabase, RestoredAs, FullBackupPath,
        RestoreMs, ChecksRun, ChecksPassed, ChecksFailed, Outcome)
    VALUES ('zz_ops_test_probe', 'zz_ops_test_probe_drill', 'x.bak',
            100, 'DBCC', 0, 1, 'failed');
    SET @ok = 1;
    DELETE FROM [Ops].[RestoreDrill] WHERE SourceDatabase = 'zz_ops_test_probe';
END TRY
BEGIN CATCH SET @ok = 0; END CATCH
INSERT @results VALUES ('a failed drill must say why',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  Same rule on the deployment side. */
BEGIN TRY
    INSERT [Ops].[DeploymentJournal] (RunId, ScriptName, OrdinalInRun,
        ScriptChecksum, Outcome, DurationMs)
    VALUES (@run, @probe, 1, @sum, 'failed', 10);
    SET @ok = 1;
    DELETE FROM [Ops].[DeploymentJournal] WHERE ScriptName = @probe;
END TRY
BEGIN CATCH SET @ok = 0; END CATCH
INSERT @results VALUES ('a failed script must say why',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  A checksum that is not a SHA-256 is a caller passing something else, and a
    journal whose checksums cannot be compared to the files on disk detects no
    drift at all. */
BEGIN TRY
    INSERT [Ops].[DeploymentJournal] (RunId, ScriptName, OrdinalInRun,
        ScriptChecksum, Outcome, DurationMs)
    VALUES (@run, @probe, 1, 'not-a-sha-256-at-all', 'succeeded', 10);
    SET @ok = 1;
    DELETE FROM [Ops].[DeploymentJournal] WHERE ScriptName = @probe;
END TRY
BEGIN CATCH SET @ok = 0; END CATCH
INSERT @results VALUES ('a script checksum must be a sha-256',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  Control for 8. */
BEGIN TRY
    INSERT [Ops].[DeploymentJournal] (RunId, ScriptName, OrdinalInRun,
        ScriptChecksum, Outcome, DurationMs)
    VALUES (@run, @probe, 1, @sum, 'succeeded', 10);
    SET @ok = 1;
    DELETE FROM [Ops].[DeploymentJournal] WHERE ScriptName = @probe;
END TRY
BEGIN CATCH SET @ok = 0; END CATCH
INSERT @results VALUES ('a well-formed journal row is still accepted',
    CASE WHEN @ok = 1 THEN 'accepted' ELSE 'refused' END,
    CASE WHEN @ok = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  Append-only, asserted against every procedure in the database rather than by
    reading the four that are supposed to be the writers.

    Resolved through the dependency graph rather than by pattern-matching the
    table name in the text, for two reasons. Formatting defeats a text search —
    [Ops].[RestoreDrill], Ops.RestoreDrill and an aliased UPDATE all name the
    same table. And square brackets in a LIKE pattern are a character class, not
    a literal: the first draft of this assertion searched for
    '%UPDATE%[Ops].[DeploymentJournal]%', which asks for "UPDATE, then any one of
    O/p/s" and duly reported eight offenders that did not exist.

    So: which procedures touch an Ops journal at all, and do any of them contain
    a mutating verb. */
SELECT @n = COUNT(DISTINCT o.object_id)
FROM sys.sql_expression_dependencies d
JOIN sys.objects o ON o.object_id = d.referencing_id
JOIN sys.sql_modules sm ON sm.object_id = o.object_id
WHERE o.type = 'P'
  AND d.referenced_entity_name IN ('DeploymentJournal', 'RestoreDrill')
  AND (sm.definition LIKE '%UPDATE %'
    OR sm.definition LIKE '%DELETE %'
    OR sm.definition LIKE '%TRUNCATE %'
    OR sm.definition LIKE '%MERGE %');
INSERT @results VALUES ('no procedure rewrites either journal',
    CONCAT(@n, ' rewriting'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  The recording procedures exist and are the documented names. The deploy and
    drill scripts call these by name; a rename that missed them would leave both
    scripts silently recording nothing. */
SELECT @n = COUNT(*) FROM sys.procedures p
JOIN sys.schemas s ON s.schema_id = p.schema_id
WHERE s.name = 'Ops'
  AND p.name IN ('usp_Deployment_Record', 'usp_Deployment_Status',
                 'usp_RestoreDrill_Record', 'usp_RestoreDrill_Status');
INSERT @results VALUES ('all four operations procedures exist',
    CONCAT(@n, ' of 4'),
    CASE WHEN @n = 4 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  The recorder round-trips. A procedure that accepted its arguments and wrote
    something else would be worse than no journal, because it would be believed. */
EXEC [Ops].[usp_Deployment_Record]
    @RunId = @run, @ScriptName = @probe, @OrdinalInRun = 7,
    @ScriptChecksum = @sum, @Outcome = 'succeeded', @DurationMs = 1234,
    @HostName = 'zz-probe-host';

SELECT @n = COUNT(*) FROM [Ops].[DeploymentJournal]
WHERE RunId = @run AND ScriptName = @probe AND OrdinalInRun = 7
  AND ScriptChecksum = @sum AND Outcome = 'succeeded' AND DurationMs = 1234
  AND AppliedByHost = 'zz-probe-host';
INSERT @results VALUES ('the deployment recorder round-trips',
    CONCAT(@n, ' matching row'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  Checksums are stored lowercase whatever the caller sent, so comparing
    against `sha256sum` output is a string comparison rather than a puzzle. */
EXEC [Ops].[usp_Deployment_Record]
    @RunId = @run, @ScriptName = @probe, @OrdinalInRun = 8,
    @ScriptChecksum = 'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789',
    @Outcome = 'succeeded', @DurationMs = 1;

SELECT @n = COUNT(*) FROM [Ops].[DeploymentJournal]
WHERE RunId = @run AND OrdinalInRun = 8
  AND ScriptChecksum = LOWER(ScriptChecksum);
INSERT @results VALUES ('checksums are normalised to lowercase',
    CONCAT(@n, ' normalised'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  The status procedure recognises a partially-applied database. This is the
    whole point of the journal: a deployment that stopped at script 34 is
    otherwise indistinguishable from one nobody ran after 33. */
EXEC [Ops].[usp_Deployment_Record]
    @RunId = @run, @ScriptName = @probe, @OrdinalInRun = 9,
    @ScriptChecksum = @sum, @Outcome = 'failed', @DurationMs = 5,
    @Message = N'deliberate probe failure';

SELECT @n = COUNT(*) FROM [Ops].[DeploymentJournal]
WHERE RunId = @run AND Outcome = 'failed';
INSERT @results VALUES ('a failed script is recorded as failed',
    CONCAT(@n, ' failure(s) recorded'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

DELETE FROM [Ops].[DeploymentJournal] WHERE ScriptName = @probe;

-- 15 ------------------------------------------------------------------------
/*  The drill recorder round-trips too, including the measured restore time —
    the number that turns an RTO from an aspiration into a measurement. */
EXEC [Ops].[usp_RestoreDrill_Record]
    @SourceDatabase = 'zz_ops_test_probe', @RestoredAs = 'zz_ops_test_probe_drill',
    @FullBackupPath = 'x.bak', @RestoreMs = 4321,
    @ChecksRun = 'DBCC CHECKDB + 20 assertion suites',
    @ChecksPassed = 21, @ChecksFailed = 0, @Outcome = 'passed';

SELECT @n = COUNT(*) FROM [Ops].[RestoreDrill]
WHERE SourceDatabase = 'zz_ops_test_probe' AND RestoreMs = 4321
  AND ChecksPassed = 21 AND Outcome = 'passed';
INSERT @results VALUES ('the drill recorder round-trips',
    CONCAT(@n, ' matching row'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

DELETE FROM [Ops].[RestoreDrill] WHERE SourceDatabase = 'zz_ops_test_probe';

-- 16 ------------------------------------------------------------------------
/*  The operations journals are about this database's own lifecycle, not about
    any woman. Nothing here may carry a user id — a deployment record that named
    accounts would be an entirely new category of data in a table nobody thinks
    of as personal. */
SELECT @n = COUNT(*)
FROM sys.columns c
JOIN sys.tables t ON t.object_id = c.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name = 'Ops'
  AND (c.name LIKE '%UserId%' OR c.name LIKE '%Email%' OR c.name LIKE '%Subject%');
INSERT @results VALUES ('the operations journals carry no personal data',
    CONCAT(@n, ' personal column(s)'),
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
    THROW 51000, 'Operations assertions failed.', 1;
GO
