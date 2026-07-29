#!/usr/bin/env bash
#
# Take a backup of a Maren database, and verify it.
#
#   ./ops/db/backup.sh <database> [server]
#   ./ops/db/backup.sh <database> [server] --enable-pitr
#
# Environment:
#   MAREN_BACKUP_DIR  where backups go. This is a path on the SQL SERVER, not on
#                     the machine running this script. They are the same host
#                     for LocalDB and for the compose stack; they are not the
#                     same host in production, and writing a backup to a path
#                     the client can see but the server cannot is the usual way
#                     a backup job appears to work and produces nothing.
#   SQLCMD, SQLAUTH   as for deploy.sh
#
# Two things this script refuses to do quietly.
#
# It will not switch a database to FULL recovery as a side effect. Point-in-time
# recovery needs FULL, but FULL without a log backup job grows the transaction
# log until the volume fills, which is a worse outage than the one it was meant
# to protect against. Pass --enable-pitr to make that change deliberately.
#
# It will not report success on a backup it has not verified. RESTORE VERIFYONLY
# reads the backup back and checks the checksums; a BACKUP statement returning
# zero only means the write was accepted.

set -u
set -o pipefail

DB="${1:?usage: backup.sh <database> [server] [--enable-pitr]}"
SERVER="${2:-(localdb)\\MSSQLLocalDB}"
ENABLE_PITR=0
for arg in "$@"; do
  [ "$arg" = "--enable-pitr" ] && ENABLE_PITR=1
done

SQLCMD="${SQLCMD:-sqlcmd}"
SQLAUTH="${SQLAUTH:-}"

sql() {
  # shellcheck disable=SC2086
  "$SQLCMD" -S "$SERVER" $SQLAUTH -I -b -d "$1" -Q "$2" < /dev/null 2>&1
}
scalar() {
  # shellcheck disable=SC2086
  "$SQLCMD" -S "$SERVER" $SQLAUTH -I -b -h -1 -W -d "$1" -Q "SET NOCOUNT ON; $2" \
    < /dev/null 2>/dev/null | head -1 | tr -d '\r'
}
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

# ---------------------------------------------------------------------------

if [ "$(scalar master "SELECT CASE WHEN DB_ID('$(esc "$DB")') IS NULL THEN 0 ELSE 1 END;")" != "1" ]; then
  echo "FATAL: database [$DB] does not exist on $SERVER." >&2
  exit 2
fi

BACKUP_DIR="${MAREN_BACKUP_DIR:-}"
if [ -z "$BACKUP_DIR" ]; then
  BACKUP_DIR="$(scalar master "SELECT CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400));")"
fi
if [ -z "$BACKUP_DIR" ] || [ "$BACKUP_DIR" = "NULL" ]; then
  echo "FATAL: no backup directory. Set MAREN_BACKUP_DIR to a path the SQL Server" >&2
  echo "       service account can write to. LocalDB reports no default backup" >&2
  echo "       path, so there is nothing sensible to guess." >&2
  exit 3
fi
BACKUP_DIR="${BACKUP_DIR%/}"
BACKUP_DIR="${BACKUP_DIR%\\}"

# Join with the separator the path already uses. SQL Server accepts a mixed
# "D:\dir/file.bak" but an operator copying that path back into a RESTORE by
# hand on Windows will not, and the paths are recorded in the drill journal for
# exactly that purpose.
case "$BACKUP_DIR" in
  *\\*) SEP='\' ;;
  *)    SEP='/' ;;
esac

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RECOVERY="$(scalar master "SELECT recovery_model_desc FROM sys.databases WHERE name = '$(esc "$DB")';")"

echo "Database:       $DB"
echo "Server:         $SERVER"
echo "Backup path:    $BACKUP_DIR   (as seen by the SERVER)"
echo "Recovery model: $RECOVERY"
echo

# ---------------------------------------------------------------------------
# Point-in-time recovery, only when asked for
# ---------------------------------------------------------------------------

if [ "$ENABLE_PITR" = "1" ] && [ "$RECOVERY" != "FULL" ]; then
  echo "Switching [$DB] to FULL recovery."
  echo "  From this point the transaction log is retained until it is backed up."
  echo "  Schedule ./ops/db/backup.sh --log, or the log will grow without bound."
  if ! out=$(sql master "ALTER DATABASE [$DB] SET RECOVERY FULL;"); then
    echo "$out" >&2
    echo "FATAL: could not switch recovery model." >&2
    exit 4
  fi
  RECOVERY="FULL"
  echo
fi

# ---------------------------------------------------------------------------
# Full backup
# ---------------------------------------------------------------------------

FULL_PATH="${BACKUP_DIR}${SEP}${DB}_${STAMP}.bak"

echo "Full backup -> $FULL_PATH"
# CHECKSUM makes the server validate page checksums as it writes and record a
# checksum over the backup itself, which is what makes VERIFYONLY below able to
# detect a corrupted file rather than merely a truncated one.
if ! out=$(sql master "BACKUP DATABASE [$DB] TO DISK = N'$(esc "$FULL_PATH")'
                        WITH INIT, CHECKSUM, FORMAT, NAME = N'$(esc "$DB") full';"); then
  echo "$out" >&2
  echo "FATAL: full backup failed." >&2
  exit 5
fi
echo "$out" | grep -E "successfully processed" || true

echo "Verifying..."
if ! out=$(sql master "RESTORE VERIFYONLY FROM DISK = N'$(esc "$FULL_PATH")' WITH CHECKSUM;"); then
  echo "$out" >&2
  echo "FATAL: the backup was written but did not verify. Treat it as absent." >&2
  exit 6
fi
echo "  verified."

# ---------------------------------------------------------------------------
# Log backup — only meaningful under FULL recovery
# ---------------------------------------------------------------------------

LOG_PATH=""
if [ "$RECOVERY" = "FULL" ]; then
  LOG_PATH="${BACKUP_DIR}${SEP}${DB}_${STAMP}.trn"
  echo
  echo "Log backup -> $LOG_PATH"
  if ! out=$(sql master "BACKUP LOG [$DB] TO DISK = N'$(esc "$LOG_PATH")'
                          WITH INIT, CHECKSUM, NAME = N'$(esc "$DB") log';"); then
    echo "$out" >&2
    echo "FATAL: log backup failed. The log is NOT truncated; it will keep growing." >&2
    exit 7
  fi
  echo "$out" | grep -E "successfully processed" || true

  if ! out=$(sql master "RESTORE VERIFYONLY FROM DISK = N'$(esc "$LOG_PATH")' WITH CHECKSUM;"); then
    echo "$out" >&2
    echo "FATAL: the log backup did not verify." >&2
    exit 8
  fi
  echo "  verified."
else
  echo
  echo "NOTE: [$DB] is in $RECOVERY recovery, so no log backup was taken and"
  echo "      point-in-time recovery is impossible for it — not unconfigured,"
  echo "      impossible. Re-run with --enable-pitr if this database needs it."
fi

# ---------------------------------------------------------------------------

echo
echo "Recovery exposure now:"
# msdb is the one record of what has been backed up. This script deliberately
# keeps no second copy of that in the application database: two answers to "when
# was the last backup" disagree the first time somebody restores from a file
# this database never heard about.
sql msdb "SET NOCOUNT ON;
  SELECT TOP 5
      CASE bs.[type] WHEN 'D' THEN 'full' WHEN 'L' THEN 'log' WHEN 'I' THEN 'diff'
                     ELSE bs.[type] END AS Kind,
      bs.backup_finish_date AS FinishedUtc,
      DATEDIFF(MINUTE, bs.backup_finish_date, GETDATE()) AS MinutesAgo,
      CAST(bs.backup_size / 1048576.0 AS DECIMAL(10,1)) AS SizeMB,
      bs.has_backup_checksums AS Checksummed
  FROM msdb.dbo.backupset bs
  WHERE bs.database_name = N'$(esc "$DB")'
  ORDER BY bs.backup_finish_date DESC;"

echo
echo "FULL_BACKUP_PATH=$FULL_PATH"
[ -n "$LOG_PATH" ] && echo "LOG_BACKUP_PATH=$LOG_PATH"
echo "Backup complete and verified."
