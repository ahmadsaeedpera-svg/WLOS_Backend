/*  70_Operations.sql

    The Operations schema.

    Two questions this platform could not answer about itself, and now can.

    1. "Is this database up to date, and did anything fail halfway?"
    -----------------------------------------------------------------
    The schema is 50-odd idempotent numbered scripts applied in a documented
    order. That design is good — it is re-runnable and reviewable — but it kept
    no record of itself. A database could not say which scripts had been applied
    to it, when, by whom, or from what content. An operator looking at a server
    had exactly one way to find out: read the schema and infer.

    That matters most in the case it is hardest to detect. The documented
    procedure is a shell loop with `|| break`. If script 34 fails, the loop
    stops, the operator sees an error scroll past, and the database is left
    two-thirds applied — structurally indistinguishable from a database that was
    never touched after 33. Ops.DeploymentJournal makes that state legible: the
    last row says what ran last and whether it succeeded.

    The checksum is what makes it more than a log. A script that is edited after
    being applied is the ordinary way a database and a repository drift, and
    comparing the recorded checksum against the file on disk detects it.

    2. "Has a restore ever actually been performed?"
    ------------------------------------------------
    Until this script, no. The recovery plan described one in detail; nothing
    had executed it. A backup that has never been restored is a hypothesis, and
    the first time anybody tests it will be the worst possible time.

    Ops.RestoreDrill records rehearsals: what was restored, from which backup,
    to what point, which assertions were run against the restored copy, and
    whether they passed. It is append-only for the same reason the audit log is
    — a failed drill that can be deleted is a failed drill nobody will hear
    about.

    What is deliberately NOT here
    -----------------------------
    Backup status. `msdb.dbo.backupset` already records every backup taken, and
    a second copy in this database would be a second source of truth that
    disagrees the first time somebody restores from a backup this database
    never heard about. The ops scripts query msdb directly, as the operator,
    and the API is given no path to it — backup history is an operator concern
    and the application has no business enumerating it.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF SCHEMA_ID('Ops') IS NULL
    EXEC('CREATE SCHEMA [Ops]');
GO

-- ---------------------------------------------------------------------------
-- What has been applied to this database
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Ops.DeploymentJournal') IS NULL
BEGIN
    CREATE TABLE [Ops].[DeploymentJournal] (
        DeploymentJournalId BIGINT IDENTITY(1,1) NOT NULL,

        /*  The run this row belongs to. One deployment applies many scripts,
            and a half-finished run is only recognisable as such when its rows
            can be grouped. */
        RunId          UNIQUEIDENTIFIER NOT NULL,

        ScriptName     VARCHAR(100) NOT NULL,

        /*  Position within the run, so a partial deployment reads in the order
            it was attempted rather than in whatever order the rows come back. */
        OrdinalInRun   INT NOT NULL,

        /*  SHA-256 of the file as applied. A script edited after the fact is
            the ordinary way a database and a repository drift; comparing this
            against the file on disk is how that is detected rather than
            discovered. */
        ScriptChecksum CHAR(64) NOT NULL,

        /*  'succeeded' or 'failed'. There is deliberately no 'running': a row
            is written after the script returns, so a script that killed the
            session leaves no row at all — and a missing row for a script the
            run should have reached is itself the signal. */
        Outcome        VARCHAR(12) NOT NULL,

        DurationMs     INT NOT NULL,

        /*  Truncated to something a journal can hold. The full text goes to the
            operator's console; this is enough to recognise which failure it
            was. */
        [Message]      NVARCHAR(1000) NULL,

        AppliedByLogin SYSNAME NOT NULL
            CONSTRAINT DF_DeploymentJournal_Login DEFAULT SUSER_SNAME(),
        AppliedByHost  SYSNAME NULL,
        AppliedUtc     DATETIME2(3) NOT NULL
            CONSTRAINT DF_DeploymentJournal_AppliedUtc DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_DeploymentJournal
            PRIMARY KEY CLUSTERED (DeploymentJournalId),

        CONSTRAINT CK_DeploymentJournal_Outcome
            CHECK (Outcome IN ('succeeded', 'failed')),

        /*  A duration cannot be negative, and a checksum that is not a SHA-256
            is a caller passing something else. */
        CONSTRAINT CK_DeploymentJournal_Duration CHECK (DurationMs >= 0),
        CONSTRAINT CK_DeploymentJournal_Checksum
            CHECK (LEN(ScriptChecksum) = 64 AND ScriptChecksum NOT LIKE '%[^0-9a-f]%'),

        /*  A failure must say why. A failed row with no message tells an
            operator only that something went wrong, which they already knew. */
        CONSTRAINT CK_DeploymentJournal_FailureHasMessage
            CHECK (Outcome <> 'failed' OR [Message] IS NOT NULL)
    );

    CREATE INDEX IX_DeploymentJournal_Run
        ON [Ops].[DeploymentJournal] (RunId, OrdinalInRun)
        INCLUDE (ScriptName, Outcome);

    /*  "When was this script last applied, and did it work" — the query an
        operator actually runs. */
    CREATE INDEX IX_DeploymentJournal_Script
        ON [Ops].[DeploymentJournal] (ScriptName, AppliedUtc DESC)
        INCLUDE (Outcome, ScriptChecksum);
END
GO

-- ---------------------------------------------------------------------------
-- Restores that have actually been rehearsed
-- ---------------------------------------------------------------------------
/*  Append-only, like the audit log and for the same reason: a failed drill
    that can be quietly deleted is a failed drill nobody hears about. The
    assertion suite checks no procedure updates or deletes this table. */
IF OBJECT_ID('Ops.RestoreDrill') IS NULL
BEGIN
    CREATE TABLE [Ops].[RestoreDrill] (
        RestoreDrillId  BIGINT IDENTITY(1,1) NOT NULL,

        /*  What was restored, and to where. The drill restores to a scratch
            database rather than over the source, so a rehearsal can never be
            the thing that causes the outage. */
        SourceDatabase  SYSNAME NOT NULL,
        RestoredAs      SYSNAME NOT NULL,

        /*  The backup chain used. Recorded as paths because that is what an
            operator repeating the drill needs to type. */
        FullBackupPath  NVARCHAR(400) NOT NULL,
        LogBackupPath   NVARCHAR(400) NULL,

        /*  Present when the drill proved point-in-time recovery specifically,
            rather than only that the full backup opens. Null means the drill
            restored to the end of the chain. */
        StopAtUtc       DATETIME2(3) NULL,

        /*  How long the restore itself took. This is the number that turns an
            RTO from an aspiration into a measurement. */
        RestoreMs       INT NOT NULL,

        /*  Which checks were run against the RESTORED copy — not against the
            source. A restore that produces an unusable database has not
            succeeded, and "the RESTORE statement returned 0" does not prove
            otherwise. */
        ChecksRun       NVARCHAR(400) NOT NULL,
        ChecksPassed    INT NOT NULL,
        ChecksFailed    INT NOT NULL,

        Outcome         VARCHAR(12) NOT NULL,
        [Message]       NVARCHAR(1000) NULL,

        PerformedByLogin SYSNAME NOT NULL
            CONSTRAINT DF_RestoreDrill_Login DEFAULT SUSER_SNAME(),
        PerformedUtc    DATETIME2(3) NOT NULL
            CONSTRAINT DF_RestoreDrill_PerformedUtc DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_RestoreDrill PRIMARY KEY CLUSTERED (RestoreDrillId),

        CONSTRAINT CK_RestoreDrill_Outcome
            CHECK (Outcome IN ('passed', 'failed')),

        CONSTRAINT CK_RestoreDrill_Counts
            CHECK (ChecksPassed >= 0 AND ChecksFailed >= 0),
        CONSTRAINT CK_RestoreDrill_Duration CHECK (RestoreMs >= 0),

        /*  The honesty constraint. A drill that ran no checks has proved that
            RESTORE returned zero and nothing else, and recording that as a pass
            would be exactly the kind of green tick this platform exists to
            refuse. */
        CONSTRAINT CK_RestoreDrill_PassRanChecks
            CHECK (Outcome <> 'passed'
                   OR (ChecksPassed > 0 AND ChecksFailed = 0)),

        CONSTRAINT CK_RestoreDrill_FailureHasMessage
            CHECK (Outcome <> 'failed' OR [Message] IS NOT NULL),

        /*  A drill must never be recorded against the database it restored
            into being. Restoring over the source is not a rehearsal, it is an
            outage. */
        CONSTRAINT CK_RestoreDrill_NotOverSource
            CHECK (RestoredAs <> SourceDatabase)
    );

    CREATE INDEX IX_RestoreDrill_Performed
        ON [Ops].[RestoreDrill] (PerformedUtc DESC)
        INCLUDE (Outcome, SourceDatabase);
END
GO

PRINT 'Operations — schema ready.';
GO
