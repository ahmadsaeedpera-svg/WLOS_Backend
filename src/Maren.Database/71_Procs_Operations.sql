/*  71_Procs_Operations.sql

    Recording and reporting deployment and recovery state.

    These are the only writers to Ops.DeploymentJournal and Ops.RestoreDrill.
    Both journals are append-only: nothing here updates or deletes, and
    ops_test.sql asserts that against every procedure in the database, the same
    way the audit log is protected.

    The status procedures are written for the person reading them at the point
    they need them, which is usually during an incident. They answer in
    sentences, not in row counts.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- usp_Deployment_Record
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Ops.usp_Deployment_Record') IS NOT NULL
    DROP PROCEDURE [Ops].[usp_Deployment_Record];
GO
/*  One row per script applied.

    Called by the deploy runner after each script returns, with the outcome it
    actually observed. It is deliberately not called *before* the script runs:
    a row written in advance would claim an application that may never have
    happened, and a crashed session would leave that claim behind as the most
    recent word on the subject. */
CREATE PROCEDURE [Ops].[usp_Deployment_Record]
    @RunId          UNIQUEIDENTIFIER,
    @ScriptName     VARCHAR(100),
    @OrdinalInRun   INT,
    @ScriptChecksum CHAR(64),
    @Outcome        VARCHAR(12),
    @DurationMs     INT,
    @Message        NVARCHAR(1000) = NULL,
    @HostName       SYSNAME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT [Ops].[DeploymentJournal]
        (RunId, ScriptName, OrdinalInRun, ScriptChecksum, Outcome,
         DurationMs, [Message], AppliedByHost)
    VALUES
        (@RunId, @ScriptName, @OrdinalInRun, LOWER(@ScriptChecksum), @Outcome,
         @DurationMs, @Message, ISNULL(@HostName, HOST_NAME()));
END
GO

-- ---------------------------------------------------------------------------
-- usp_Deployment_Status
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Ops.usp_Deployment_Status') IS NOT NULL
    DROP PROCEDURE [Ops].[usp_Deployment_Status];
GO
/*  Where this database stands.

    Three result sets, in the order the questions get asked during an incident:
    the summary, the most recent run script by script, and the scripts that have
    ever failed and not since succeeded.

    The third is the one that matters. A script that failed in one run and
    succeeded in the next is history; a script whose most recent word is
    'failed' is a database that is two-thirds applied, and that is very hard to
    see any other way. */
CREATE PROCEDURE [Ops].[usp_Deployment_Status]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @latestRun UNIQUEIDENTIFIER =
        (SELECT TOP 1 RunId FROM [Ops].[DeploymentJournal]
         ORDER BY DeploymentJournalId DESC);

    SELECT
        (SELECT COUNT(DISTINCT RunId) FROM [Ops].[DeploymentJournal]) AS TotalRuns,
        (SELECT COUNT(*) FROM [Ops].[DeploymentJournal]
         WHERE RunId = @latestRun) AS ScriptsInLatestRun,
        (SELECT COUNT(*) FROM [Ops].[DeploymentJournal]
         WHERE RunId = @latestRun AND Outcome = 'failed') AS FailuresInLatestRun,
        (SELECT MAX(AppliedUtc) FROM [Ops].[DeploymentJournal]) AS LastAppliedUtc,
        @latestRun AS LatestRunId,
        /*  Said in a sentence, because the person reading this is usually
            reading it under pressure. */
        CASE
            WHEN @latestRun IS NULL
                THEN N'This database has never been deployed by the recorded runner. '
                   + N'Its schema may still be correct — it simply cannot say so.'
            WHEN EXISTS (SELECT 1 FROM [Ops].[DeploymentJournal]
                         WHERE RunId = @latestRun AND Outcome = 'failed')
                THEN N'The most recent deployment FAILED partway. This database is '
                   + N'partially applied; see the failing script below.'
            ELSE N'The most recent deployment completed with every script succeeding.'
        END AS Assessment;

    SELECT
        ScriptName, OrdinalInRun, Outcome, DurationMs, ScriptChecksum,
        [Message], AppliedByLogin, AppliedUtc
    FROM [Ops].[DeploymentJournal]
    WHERE RunId = @latestRun
    ORDER BY OrdinalInRun;

    /*  Scripts whose latest word is a failure. */
    SELECT
        j.ScriptName, j.Outcome, j.[Message], j.AppliedUtc
    FROM [Ops].[DeploymentJournal] j
    WHERE j.DeploymentJournalId = (
        SELECT MAX(j2.DeploymentJournalId)
        FROM [Ops].[DeploymentJournal] j2
        WHERE j2.ScriptName = j.ScriptName)
      AND j.Outcome = 'failed'
    ORDER BY j.ScriptName;
END
GO

-- ---------------------------------------------------------------------------
-- usp_RestoreDrill_Record
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Ops.usp_RestoreDrill_Record') IS NOT NULL
    DROP PROCEDURE [Ops].[usp_RestoreDrill_Record];
GO
/*  One row per rehearsal.

    Recorded against the SOURCE database, not the scratch copy — the scratch
    copy is dropped when the drill finishes, and a record that disappears with
    it would prove nothing to anybody afterwards. */
CREATE PROCEDURE [Ops].[usp_RestoreDrill_Record]
    @SourceDatabase SYSNAME,
    @RestoredAs     SYSNAME,
    @FullBackupPath NVARCHAR(400),
    @LogBackupPath  NVARCHAR(400) = NULL,
    @StopAtUtc      DATETIME2(3) = NULL,
    @RestoreMs      INT,
    @ChecksRun      NVARCHAR(400),
    @ChecksPassed   INT,
    @ChecksFailed   INT,
    @Outcome        VARCHAR(12),
    @Message        NVARCHAR(1000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT [Ops].[RestoreDrill]
        (SourceDatabase, RestoredAs, FullBackupPath, LogBackupPath, StopAtUtc,
         RestoreMs, ChecksRun, ChecksPassed, ChecksFailed, Outcome, [Message])
    VALUES
        (@SourceDatabase, @RestoredAs, @FullBackupPath, @LogBackupPath, @StopAtUtc,
         @RestoreMs, @ChecksRun, @ChecksPassed, @ChecksFailed, @Outcome, @Message);
END
GO

-- ---------------------------------------------------------------------------
-- usp_RestoreDrill_Status
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Ops.usp_RestoreDrill_Status') IS NOT NULL
    DROP PROCEDURE [Ops].[usp_RestoreDrill_Status];
GO
/*  Whether this platform can actually be recovered, and when that was last
    demonstrated.

    @MaxAgeDays is the age past which a passing drill stops counting. A restore
    rehearsed once a year against a schema that has changed forty times since
    is not evidence about today's database. */
CREATE PROCEDURE [Ops].[usp_RestoreDrill_Status]
    @MaxAgeDays INT = 30
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @lastPassUtc DATETIME2(3) =
        (SELECT MAX(PerformedUtc) FROM [Ops].[RestoreDrill] WHERE Outcome = 'passed');

    SELECT
        (SELECT COUNT(*) FROM [Ops].[RestoreDrill]) AS TotalDrills,
        (SELECT COUNT(*) FROM [Ops].[RestoreDrill] WHERE Outcome = 'passed') AS Passed,
        (SELECT COUNT(*) FROM [Ops].[RestoreDrill] WHERE Outcome = 'failed') AS Failed,
        @lastPassUtc AS LastPassingDrillUtc,
        DATEDIFF(DAY, @lastPassUtc, SYSUTCDATETIME()) AS DaysSinceLastPass,
        /*  The measured RTO. An aspiration until a drill produces it. */
        (SELECT MAX(RestoreMs) FROM [Ops].[RestoreDrill]
         WHERE Outcome = 'passed') AS SlowestPassingRestoreMs,
        CAST(CASE
            WHEN @lastPassUtc IS NULL THEN 0
            WHEN DATEDIFF(DAY, @lastPassUtc, SYSUTCDATETIME()) > @MaxAgeDays THEN 0
            ELSE 1
        END AS BIT) AS IsCurrent,
        CASE
            WHEN @lastPassUtc IS NULL
                THEN N'No restore has ever been rehearsed successfully. The backups '
                   + N'are a hypothesis until one is.'
            WHEN DATEDIFF(DAY, @lastPassUtc, SYSUTCDATETIME()) > @MaxAgeDays
                THEN N'The last successful rehearsal is older than the window. The '
                   + N'schema has probably moved since; rehearse again.'
            ELSE N'A restore has been rehearsed successfully within the window, with '
               + N'checks run against the restored copy.'
        END AS Assessment;

    SELECT TOP 20
        RestoreDrillId, SourceDatabase, RestoredAs, StopAtUtc, RestoreMs,
        ChecksRun, ChecksPassed, ChecksFailed, Outcome, [Message], PerformedUtc
    FROM [Ops].[RestoreDrill]
    ORDER BY RestoreDrillId DESC;
END
GO

PRINT 'Operations — procedures ready.';
GO
