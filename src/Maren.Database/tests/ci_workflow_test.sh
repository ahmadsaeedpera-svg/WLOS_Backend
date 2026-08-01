#!/usr/bin/env bash
#
# Every SQL assertion step in CI must actually run something.
#
# Twice now a step has been authored with a command substitution that the
# authoring shell evaluated before the YAML was written, leaving `out=` empty.
# The step then greps an empty string for "FAILED: 0", finds nothing, and
# reports green forever — a CI step that verifies nothing and says it verified
# everything. It is the worst possible failure for a guard, because it is
# indistinguishable from success.
#
# This checks the committed workflow rather than trusting the author. Run from
# the repository root:
#
#     bash src/Maren.Database/tests/ci_workflow_test.sh
#
# Expect: TOTAL: <n>  FAILED: 0

set -u

WORKFLOW="${1:-.github/workflows/ci.yml}"
total=0
failed=0

check() {
    local name="$1" detail="$2" ok="$3"
    total=$((total + 1))
    if [ "$ok" = "1" ]; then
        printf '  %-58s %-28s PASS\n' "$name" "$detail"
    else
        printf '  %-58s %-28s FAIL\n' "$name" "$detail"
        failed=$((failed + 1))
    fi
}

echo ""
echo "=== CI workflow ============================================================="

[ -f "$WORKFLOW" ] || { echo "Workflow not found: $WORKFLOW"; exit 1; }

# 1. No assertion step may capture an empty command.
empty=$(grep -cE '^\s+out=\s*$' "$WORKFLOW" || true)
check "no assertion step captures an empty command" \
      "$empty empty" \
      "$([ "$empty" = "0" ] && echo 1 || echo 0)"

# 2. Every `out=` capture must invoke sqlcmd.
captures=$(grep -cE '^\s+out=' "$WORKFLOW" || true)
sqlcmd_captures=$(grep -cE '^\s+out=\$\(\$SQLCMD ' "$WORKFLOW" || true)
check "every capture invokes sqlcmd" \
      "$sqlcmd_captures of $captures" \
      "$([ "$captures" = "$sqlcmd_captures" ] && echo 1 || echo 0)"

# 3. Every capture must be checked for FAILED: 0. A step that runs the suite
#    and ignores the result is the same failure wearing a different hat.
checks=$(grep -cE 'grep -q "FAILED: 0"' "$WORKFLOW" || true)
check "every capture is checked for FAILED: 0" \
      "$checks checks, $captures captures" \
      "$([ "$checks" = "$captures" ] && echo 1 || echo 0)"

# 4. Every assertion suite on disk must appear in the workflow. A suite nobody
#    runs in CI is a suite that only passes on the machine that wrote it.
missing=0
missing_names=""
for f in src/Maren.Database/tests/*.sql; do
    base=$(basename "$f")
    if ! grep -q "$base" "$WORKFLOW"; then
        missing=$((missing + 1))
        missing_names="$missing_names $base"
    fi
done
check "every assertion suite runs in CI" \
      "$missing missing$missing_names" \
      "$([ "$missing" = "0" ] && echo 1 || echo 0)"

# 5. Every schema script on disk must appear in the workflow's apply loop.
#    Nothing guarded this before: a numbered script could be committed, pass
#    review, and simply never be applied anywhere. It would not fail — the
#    tables it creates would silently not exist, and the first symptom would be
#    a procedure referencing a missing object at runtime.
unapplied=0
unapplied_names=""
for f in src/Maren.Database/*.sql; do
    base=$(basename "$f")
    if ! grep -q "$base" "$WORKFLOW"; then
        unapplied=$((unapplied + 1))
        unapplied_names="$unapplied_names $base"
    fi
done
check "every schema script is applied in CI" \
      "$unapplied missing$unapplied_names" \
      "$([ "$unapplied" = "0" ] && echo 1 || echo 0)"

# 6. sqlcmd must be invoked with -b wherever the workflow applies schema, or a
#    T-SQL error exits 0 and the loop carries on over a broken database. The
#    documented operator loop was missing this in four places until 2026-07-29:
#    `|| break` was dead code, and every deployment reported success.
apply_lines=$(grep -cE '\$SQLCMD .* -i "\$f"' "$WORKFLOW" || true)
apply_with_b=$(grep -cE '\$SQLCMD .* -i "\$f" -b|\$SQLCMD .* -b .* -i "\$f"' "$WORKFLOW" || true)
check "schema application stops on a T-SQL error" \
      "$apply_with_b of $apply_lines use -b" \
      "$([ "$apply_lines" = "$apply_with_b" ] && echo 1 || echo 0)"

# 7. This guard must itself run in CI. It spent its whole existence unexecuted
#    there: a guard against a silently-green step, itself silently absent.
self=$(grep -c 'ci_workflow_test.sh' "$WORKFLOW" || true)
check "this guard runs in CI" \
      "$self reference(s)" \
      "$([ "$self" != "0" ] && echo 1 || echo 0)"

# 8. The gate must fire on the branches work actually happens on. It listened
#    to `main` alone until 2026-08-01, so forty-four backend commits and eleven
#    portal commits were merged without one CI run: the gate could only report
#    on the far side of the decision it exists to inform. Nothing structural
#    prevented that — the filter was simply narrower than the workflow.
feature_gated=$(grep -cE "^\s+branches: \[main, 'feature/\*\*'\]" "$WORKFLOW" || true)
check "feature branches are gated, not only main" \
      "$feature_gated push filter(s)" \
      "$([ "$feature_gated" != "0" ] && echo 1 || echo 0)"

# 9. The vulnerability step must read the accepted-risk set from the project
#    files rather than carrying its own copy.
#
#    `NuGetAuditSuppress` is restore-time only: it silences the build and
#    `dotnet list package --vulnerable` ignores it completely. So the csproj
#    said "accepted, reviewed, unreachable" while CI independently said "fail",
#    and the security job was red on every run it would ever have had. Two
#    sources of truth for one decision, disagreeing.
#
#    This asserts the step still derives the set from the csproj files. It
#    guards both directions: a hand-maintained list here would drift, and
#    deleting the reconciliation to make the job green would silence every
#    future advisory too.
reads_suppressions=$(grep -c 'NuGetAuditSuppress Include=' "$WORKFLOW" || true)
compares_accepted=$(grep -c 'comm -23 found.txt accepted.txt' "$WORKFLOW" || true)
check "accepted vulnerabilities come from the csproj, not a copy" \
      "$reads_suppressions read, $compares_accepted compare" \
      "$([ "$reads_suppressions" != "0" ] && [ "$compares_accepted" != "0" ] && echo 1 || echo 0)"

echo ""
echo "---------------------------------------------"
echo "TOTAL: $total  FAILED: $failed"
echo "---------------------------------------------"

[ "$failed" = "0" ] || exit 1
