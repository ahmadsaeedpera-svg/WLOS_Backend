#!/usr/bin/env bash
#
# Apply the Maren schema, in the documented order, and record what was applied.
#
# This replaces the copy-pasted shell loop that lived in four documents. The
# loop was correct but silent: it applied scripts with `|| break`, so a failure
# at script 34 left a two-thirds-applied database that was structurally
# indistinguishable from one nobody had touched since 33. Every script here is
# recorded in Ops.DeploymentJournal with its checksum, its duration and its
# outcome, so that state is legible afterwards.
#
#   ./ops/db/deploy.sh <database> [server]
#
# Environment:
#   SQLCMD   path to sqlcmd            (default: sqlcmd)
#   SQLAUTH  extra auth args for sqlcmd, e.g. "-U sa -P secret -C"
#            (default: empty, meaning integrated auth — used by LocalDB)
#
# The order is read from docs/PLATFORM_RUNBOOK.md rather than hard-coded here.
# There is one deployment order and it is the documented one; a second copy in
# this file would be a second source of truth, and the one that drifts is
# always the one nobody reads.

set -u
set -o pipefail

DB="${1:?usage: deploy.sh <database> [server]}"
SERVER="${2:-(localdb)\\MSSQLLocalDB}"
SQLCMD="${SQLCMD:-sqlcmd}"
SQLAUTH="${SQLAUTH:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB_DIR="$REPO_ROOT/src/Maren.Database"
RUNBOOK="$REPO_ROOT/docs/PLATFORM_RUNBOOK.md"

# The audit contract application must be the last script in the order. It
# applies the contract with a cursor over sys.tables, so anything created after
# it is invisible to that pass. The rule is carried by the number; this is
# where the number is checked.
AUDIT_LAST="81_AuditContract_Apply.sql"

# ---------------------------------------------------------------------------

sql() {
  # shellcheck disable=SC2086
  "$SQLCMD" -S "$SERVER" $SQLAUTH -I -b -d "$1" -Q "$2" < /dev/null 2>&1
}

# sqlcmd is invoked from inside the script directory with a bare filename, never
# with an absolute path. The Windows build cannot open a POSIX-style absolute
# path — `-i /d/repo/01_Schemas.sql` fails with "Access is denied" on the drive
# letter, which reads like a permissions problem and is not one. Relative paths
# behave identically on both platforms, so this is the portable form rather than
# a Windows workaround.
sql_file() {
  # shellcheck disable=SC2086
  ( cd "$3" && "$SQLCMD" -S "$SERVER" $SQLAUTH -I -b -d "$1" -i "$2" < /dev/null 2>&1 )
}

# T-SQL string literal: double every single quote.
esc() { printf '%s' "$1" | sed "s/'/''/g"; }

# ---------------------------------------------------------------------------
# The order, read from the runbook and checked against disk
# ---------------------------------------------------------------------------

if [ ! -f "$RUNBOOK" ]; then
  echo "FATAL: runbook not found at $RUNBOOK" >&2
  exit 2
fi

mapfile -t SCRIPTS < <(
  sed -n '/for f in/,/; do/p' "$RUNBOOK" | grep -oE '[0-9]{2}_[A-Za-z0-9_]+\.sql'
)
mapfile -t DISK < <(cd "$DB_DIR" && ls ./*.sql 2>/dev/null | sed 's|^\./||' | sort)

if [ "${#SCRIPTS[@]}" -eq 0 ]; then
  echo "FATAL: no deployment order found in $RUNBOOK" >&2
  exit 2
fi

if [ "${#SCRIPTS[@]}" -ne "${#DISK[@]}" ]; then
  echo "FATAL: the runbook documents ${#SCRIPTS[@]} scripts, disk has ${#DISK[@]}." >&2
  echo "       A script added without documenting it would deploy differently" >&2
  echo "       everywhere the docs are followed. Reconcile before deploying." >&2
  exit 3
fi

if [ "${SCRIPTS[${#SCRIPTS[@]}-1]}" != "$AUDIT_LAST" ]; then
  echo "FATAL: $AUDIT_LAST must be last in the order; found ${SCRIPTS[${#SCRIPTS[@]}-1]}." >&2
  echo "       It applies the audit contract with a cursor over sys.tables, so" >&2
  echo "       anything created after it never receives the contract." >&2
  exit 4
fi

for f in "${SCRIPTS[@]}"; do
  if [ ! -f "$DB_DIR/$f" ]; then
    echo "FATAL: $f is documented but not on disk." >&2
    exit 5
  fi
done

# ---------------------------------------------------------------------------

RUN_ID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null \
  || powershell -NoProfile -Command '[guid]::NewGuid().ToString()' 2>/dev/null \
  || date +%s%N)"
RUN_ID="$(printf '%s' "$RUN_ID" | tr -d '\r\n')"
HOSTNAME_SHORT="$(hostname 2>/dev/null || echo unknown)"

echo "Deploying ${#SCRIPTS[@]} scripts to [$DB] on $SERVER"
echo "Run id: $RUN_ID"
echo

# The database, if it is this script's to create.
#
# This was a single statement — IF DB_ID(...) IS NULL CREATE DATABASE [x] —
# which is valid on a SQL Server you run and rejected by Azure SQL Database,
# where CREATE DATABASE must be the only statement in its batch. The guard that
# made the script idempotent was therefore the exact thing that made it fail
# against a managed database, on the step before a single schema script ran.
# Probing and creating as separate batches is correct on both.
existing=$(sql master "SET NOCOUNT ON; SELECT CASE WHEN DB_ID('$(esc "$DB")') IS NULL THEN 0 ELSE 1 END;" | tr -dc '0-9')
probe_rc=$?

if [ $probe_rc -ne 0 ] || [ -z "$existing" ]; then
  echo "FATAL: could not reach $SERVER." >&2
  exit 6
fi

if [ "$existing" = "0" ]; then
  if ! sql master "CREATE DATABASE [$DB];" > /dev/null; then
    echo "FATAL: [$DB] does not exist and could not be created on $SERVER." >&2
    echo "       On a managed database — Azure SQL and its equivalents —" >&2
    echo "       creating one is the platform's job and not this script's." >&2
    echo "       Create [$DB] there, then re-run. This applies schema; it does" >&2
    echo "       not provision." >&2
    exit 6
  fi
fi

# Rows are buffered rather than written as we go, because Ops.DeploymentJournal
# does not exist until script 70 applies. Buffering means the journal ends up
# with a complete record of the run including the scripts that ran before the
# journal itself existed — which is most of them, and all of the interesting
# early failures.
# Kept beside the scripts rather than in the system temp directory, for the same
# path reason as above: sqlcmd must be able to open it by relative name.
BUFFER_NAME=".deploy-journal-$$.sql"
BUFFER_FILE="$DB_DIR/$BUFFER_NAME"
: > "$BUFFER_FILE"
trap 'rm -f "$BUFFER_FILE"' EXIT

record() {
  # name ordinal checksum outcome duration message
  {
    printf "EXEC [Ops].[usp_Deployment_Record] @RunId='%s', @ScriptName='%s', " \
      "$RUN_ID" "$(esc "$1")"
    printf "@OrdinalInRun=%s, @ScriptChecksum='%s', @Outcome='%s', @DurationMs=%s, " \
      "$2" "$3" "$4" "$5"
    if [ -n "${6:-}" ]; then
      printf "@Message=N'%s', " "$(esc "$(printf '%s' "$6" | tr '\n\r' '  ' | cut -c1-900)")"
    fi
    printf "@HostName='%s';\n" "$(esc "$HOSTNAME_SHORT")"
  } >> "$BUFFER_FILE"
}

flush_journal() {
  # Only possible once the recording PROCEDURE exists, which is script 71 — not
  # script 70, which creates the table. Gating on the table looked right and was
  # wrong: the buffered statements are EXEC calls, so between 70 and 71 the
  # target exists and the verb to write to it does not, and every deployment
  # printed a warning about a journal that was in fact written correctly moments
  # later. A warning that cries wolf on every successful run is worse than no
  # warning at all.
  #
  # Silent when the procedure is absent — a deployment that fails at script 03
  # has no journal to write to, and saying so every time would train operators
  # to ignore the message.
  local exists
  exists=$(sql "$DB" "SET NOCOUNT ON; SELECT CASE WHEN OBJECT_ID('Ops.usp_Deployment_Record', 'P') IS NULL THEN 0 ELSE 1 END;" \
    | tr -dc '0-9')
  if [ "${exists:-0}" = "1" ] && [ -s "$BUFFER_FILE" ]; then
    if sql_file "$DB" "$BUFFER_NAME" "$DB_DIR" > /dev/null; then
      : > "$BUFFER_FILE"
      return 0
    fi
    echo "WARNING: the deployment journal could not be written." >&2
    echo "         The schema change may still have applied; the record of it did not." >&2
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------

ordinal=0
failed=0

for f in "${SCRIPTS[@]}"; do
  ordinal=$((ordinal + 1))
  checksum="$(sha256sum "$DB_DIR/$f" | cut -c1-64)"

  start_ns="$(date +%s%N)"
  out="$(sql_file "$DB" "$f" "$DB_DIR")"
  rc=$?
  end_ns="$(date +%s%N)"
  duration=$(( (end_ns - start_ns) / 1000000 ))

  if [ $rc -ne 0 ]; then
    printf '%3d/%d  FAILED   %-42s %6dms\n' "$ordinal" "${#SCRIPTS[@]}" "$f" "$duration"
    echo "$out" | tail -15
    record "$f" "$ordinal" "$checksum" "failed" "$duration" "$out"
    failed=1
    break
  fi

  printf '%3d/%d  ok       %-42s %6dms\n' "$ordinal" "${#SCRIPTS[@]}" "$f" "$duration"
  record "$f" "$ordinal" "$checksum" "succeeded" "$duration" ""

  # Flush as soon as the journal can take rows, so a failure after this point
  # is recorded in the database rather than only in this shell's memory.
  if [ "$f" = "71_Procs_Operations.sql" ]; then
    flush_journal || true
  fi
done

flush_journal || true

echo
if [ $failed -ne 0 ]; then
  echo "DEPLOYMENT FAILED. [$DB] is partially applied."
  echo "Run: EXEC [Ops].[usp_Deployment_Status];  — the third result set names"
  echo "the script whose most recent word is a failure."
  exit 1
fi

echo "Deployment complete: ${#SCRIPTS[@]} scripts, run $RUN_ID."
exit 0
