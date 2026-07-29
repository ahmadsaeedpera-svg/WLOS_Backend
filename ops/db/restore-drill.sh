#!/usr/bin/env bash
#
# Rehearse a restore, verify the restored copy, and record that it happened.
#
#   ./ops/db/restore-drill.sh <source-database> <full-backup-path> [log-backup-path] [--stopat 'YYYY-MM-DDTHH:MM:SS.mmm']
#
# Environment: SQLCMD, SQLAUTH, SERVER as for the other ops scripts.
#
# Why this exists in this form
# ----------------------------
# A backup that has never been restored is a hypothesis. The recovery plan
# described a rehearsal in prose; nothing executed it, so the first real test
# would have been during an incident.
#
# It restores to a SCRATCH database and never over the source. A rehearsal that
# can cause the outage it rehearses for is not a rehearsal.
#
# The verification is the point, and it is deliberately not a row count. The
# recovery plan used to say "expect 45 tables, 47 procedures". The schema has
# since roughly doubled — it is 84 and 102 — so those thresholds had drifted
# into a gate that would pass a database missing ten entire feature schemas
# while reporting success. Counts of things are a bad check because they go
# stale silently and nothing fails when they do.
#
# So the drill runs the actual SQL assertion suites against the restored copy —
# every suite on disk, not a hand-picked five — plus DBCC CHECKDB. Those
# assertions are maintained because they gate CI, so they cannot rot quietly in
# the way a hard-coded number can. If the restored database cannot satisfy the
# platform's own rules, it has not been restored, whatever RESTORE returned.

set -u
set -o pipefail

SOURCE_DB="${1:?usage: restore-drill.sh <source-database> <full-backup-path> [log-backup-path] [--stopat <utc>]}"
FULL_BACKUP="${2:?a full backup path is required}"
LOG_BACKUP=""
STOPAT=""

shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --stopat) STOPAT="${2:-}"; shift 2 ;;
    --server) SERVER_ARG="${2:-}"; shift 2 ;;
    *)        LOG_BACKUP="$1"; shift ;;
  esac
done

SERVER="${SERVER_ARG:-${SERVER:-(localdb)\\MSSQLLocalDB}}"
SQLCMD="${SQLCMD:-sqlcmd}"
SQLAUTH="${SQLAUTH:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_DIR="$REPO_ROOT/src/Maren.Database/tests"

DRILL_DB="${SOURCE_DB}_drill"

sql() {
  # shellcheck disable=SC2086
  "$SQLCMD" -S "$SERVER" $SQLAUTH -I -b -d "$1" -Q "$2" < /dev/null 2>&1
}
sql_file_in() {
  # Relative filename with the working directory set — the Windows sqlcmd
  # cannot open a POSIX absolute path. See deploy.sh for the same note.
  # shellcheck disable=SC2086
  ( cd "$3" && "$SQLCMD" -S "$SERVER" $SQLAUTH -I -d "$1" -i "$2" < /dev/null 2>&1 )
}
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

cleanup() {
  sql master "IF DB_ID('$(esc "$DRILL_DB")') IS NOT NULL
              BEGIN
                ALTER DATABASE [$DRILL_DB] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE [$DRILL_DB];
              END" > /dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Restore drill"
echo "  source:  $SOURCE_DB"
echo "  restore: $DRILL_DB  (scratch — dropped when this finishes)"
echo "  full:    $FULL_BACKUP"
[ -n "$LOG_BACKUP" ] && echo "  log:     $LOG_BACKUP"
[ -n "$STOPAT" ]     && echo "  stopat:  $STOPAT"
echo

cleanup

# ---------------------------------------------------------------------------
# Relocate the data files, or the restore collides with the source database's
# own files and fails in a way that reads like a permissions problem.
# ---------------------------------------------------------------------------

MOVE_CLAUSE="$(
  # shellcheck disable=SC2086
  "$SQLCMD" -S "$SERVER" $SQLAUTH -I -h -1 -W -d master \
    -Q "SET NOCOUNT ON;
        DECLARE @files TABLE (LogicalName NVARCHAR(128), PhysicalName NVARCHAR(400),
                              Type CHAR(1), FileGroupName NVARCHAR(128), Size NUMERIC(20,0),
                              MaxSize NUMERIC(20,0), FileId BIGINT, CreateLSN NUMERIC(25,0),
                              DropLSN NUMERIC(25,0), UniqueId UNIQUEIDENTIFIER,
                              ReadOnlyLSN NUMERIC(25,0), ReadWriteLSN NUMERIC(25,0),
                              BackupSizeInBytes BIGINT, SourceBlockSize INT, FileGroupId INT,
                              LogGroupGUID UNIQUEIDENTIFIER, DifferentialBaseLSN NUMERIC(25,0),
                              DifferentialBaseGUID UNIQUEIDENTIFIER, IsReadOnly BIT,
                              IsPresent BIT, TDEThumbprint VARBINARY(32),
                              SnapshotUrl NVARCHAR(360));
        INSERT @files EXEC('RESTORE FILELISTONLY FROM DISK = N''$(esc "$FULL_BACKUP")''');
        SELECT STUFF((SELECT ', MOVE N''' + LogicalName + ''' TO N'''
                           + REPLACE(PhysicalName,
                               REVERSE(LEFT(REVERSE(PhysicalName),
                                 CHARINDEX('\\', REVERSE(PhysicalName)) - 1)),
                               '$(esc "$DRILL_DB")_' + LogicalName
                               + CASE WHEN Type = 'L' THEN '.ldf' ELSE '.mdf' END)
                           + ''''
                      FROM @files FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 0, '');" \
    < /dev/null 2>/dev/null | head -1 | tr -d '\r'
)"

if [ -z "$MOVE_CLAUSE" ] || [ "$MOVE_CLAUSE" = "NULL" ]; then
  echo "FATAL: could not read the file list from $FULL_BACKUP." >&2
  echo "       Is the path correct AS SEEN BY THE SERVER?" >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Restore, and time it. This number is the RTO, measured rather than hoped for.
# ---------------------------------------------------------------------------

RECOVERY_CLAUSE="WITH RECOVERY"
[ -n "$LOG_BACKUP" ] && RECOVERY_CLAUSE="WITH NORECOVERY"

start_ns="$(date +%s%N)"

if ! out=$(sql master "RESTORE DATABASE [$DRILL_DB] FROM DISK = N'$(esc "$FULL_BACKUP")'
                       $RECOVERY_CLAUSE, REPLACE $MOVE_CLAUSE;"); then
  echo "$out" >&2
  echo "FATAL: the full restore failed." >&2
  exit 3
fi
echo "$out" | grep -E "successfully processed" || true

if [ -n "$LOG_BACKUP" ]; then
  STOP_CLAUSE=""
  [ -n "$STOPAT" ] && STOP_CLAUSE=", STOPAT = N'$(esc "$STOPAT")'"
  if ! out=$(sql master "RESTORE LOG [$DRILL_DB] FROM DISK = N'$(esc "$LOG_BACKUP")'
                         WITH RECOVERY$STOP_CLAUSE;"); then
    echo "$out" >&2
    echo "FATAL: the log restore failed." >&2
    exit 4
  fi
  echo "$out" | grep -E "successfully processed" || true
fi

end_ns="$(date +%s%N)"
RESTORE_MS=$(( (end_ns - start_ns) / 1000000 ))
echo "Restored in ${RESTORE_MS}ms."
echo

# ---------------------------------------------------------------------------
# Verify the RESTORED COPY. This is the part that makes it a drill.
# ---------------------------------------------------------------------------

passed=0
failed=0
checks=""

echo "DBCC CHECKDB..."
if out=$(sql "$DRILL_DB" "DBCC CHECKDB ([$DRILL_DB]) WITH NO_INFOMSGS, ALL_ERRORMSGS;") \
   && [ -z "$(printf '%s' "$out" | tr -d '[:space:]')" ]; then
  echo "  clean."
  passed=$((passed + 1))
else
  echo "  FAILED:"; echo "$out" | head -10
  failed=$((failed + 1))
fi
checks="DBCC CHECKDB"

# Every suite on disk. Not a curated five — the curated list is what went stale.
mapfile -t SUITES < <(cd "$TEST_DIR" && ls ./*_test.sql 2>/dev/null | sed 's|^\./||' | sort)
echo "Assertion suites (${#SUITES[@]} on disk):"

for s in "${SUITES[@]}"; do
  out=$(sql_file_in "$DRILL_DB" "$s" "$TEST_DIR")
  line=$(printf '%s' "$out" | grep -oE "TOTAL: *[0-9]+ +FAILED: *[0-9]+" | tail -1)
  if [ -z "$line" ]; then
    printf '  %-34s NO RESULT\n' "$s"
    failed=$((failed + 1))
    continue
  fi
  n=$(printf '%s' "$line" | sed -E 's/.*FAILED: *([0-9]+).*/\1/')
  if [ "$n" = "0" ]; then
    printf '  %-34s %s\n' "$s" "$line"
    passed=$((passed + 1))
  else
    printf '  %-34s %s  <-- FAILED\n' "$s" "$line"
    failed=$((failed + 1))
  fi
done

checks="$checks + ${#SUITES[@]} assertion suites"

echo
echo "Checks passed: $passed   failed: $failed"

OUTCOME="passed"
MESSAGE=""
if [ "$failed" -ne 0 ] || [ "$passed" -eq 0 ]; then
  OUTCOME="failed"
  MESSAGE="$failed check(s) failed against the restored copy; the backup does not reconstitute a usable database."
fi

# ---------------------------------------------------------------------------
# Record it against the SOURCE database — the scratch copy is about to vanish.
# ---------------------------------------------------------------------------

STOPAT_SQL="NULL"
[ -n "$STOPAT" ] && STOPAT_SQL="N'$(esc "$STOPAT")'"
LOG_SQL="NULL"
[ -n "$LOG_BACKUP" ] && LOG_SQL="N'$(esc "$LOG_BACKUP")'"
MSG_SQL="NULL"
[ -n "$MESSAGE" ] && MSG_SQL="N'$(esc "$MESSAGE")'"

if out=$(sql "$SOURCE_DB" "
    IF OBJECT_ID('Ops.usp_RestoreDrill_Record', 'P') IS NULL
        RAISERROR('Ops.usp_RestoreDrill_Record is absent; apply 71_Procs_Operations.sql.', 16, 1);
    ELSE
    EXEC [Ops].[usp_RestoreDrill_Record]
        @SourceDatabase = N'$(esc "$SOURCE_DB")',
        @RestoredAs     = N'$(esc "$DRILL_DB")',
        @FullBackupPath = N'$(esc "$FULL_BACKUP")',
        @LogBackupPath  = $LOG_SQL,
        @StopAtUtc      = $STOPAT_SQL,
        @RestoreMs      = $RESTORE_MS,
        @ChecksRun      = N'$(esc "$checks")',
        @ChecksPassed   = $passed,
        @ChecksFailed   = $failed,
        @Outcome        = '$OUTCOME',
        @Message        = $MSG_SQL;"); then
  echo "Drill recorded against [$SOURCE_DB]."
else
  echo "$out" >&2
  echo "WARNING: the drill ran but could not be recorded." >&2
fi

echo
if [ "$OUTCOME" = "passed" ]; then
  echo "DRILL PASSED — this backup reconstitutes a database that satisfies the"
  echo "platform's own assertions. Measured restore time: ${RESTORE_MS}ms."
  exit 0
fi

echo "DRILL FAILED — $MESSAGE"
exit 1
