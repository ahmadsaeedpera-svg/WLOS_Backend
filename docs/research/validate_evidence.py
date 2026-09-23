#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
WLOS Phase A evidence checker.

Companion to:
    docs/research/EVIDENCE_SCHEMA.md
    docs/WLOS_INTERVIEW_PROTOCOL.md   (LOCKED - rubric in section 6 is definitive)
    docs/WLOS_RECRUITMENT_SCREENER.md (LOCKED)

WHAT THIS DOES
    Checks the STRUCTURE and COMPLETENESS of a 14-row Phase A evidence file.

WHAT THIS DOES NOT DO
    It does not interpret participant evidence. It does not judge whether a
    score is the right score. It does not produce a finding, a verdict or a
    recommendation.

THE ONE BEHAVIOUR THAT MATTERS MOST
    Protocol section 6.0: "Do not compute or look at aggregate scores until all
    14 rows are locked."

    This script will not compute a total, a count, a distribution or a
    threshold result while any row is unlocked or structurally invalid. Asked
    to aggregate early, it refuses, says why, and exits 3.

    During validation it never prints a score value back - seeing the scores is
    aggregation. Only INVALID values are echoed, so they can be corrected.

USAGE
    python validate_evidence.py <evidence.csv>
    python validate_evidence.py <evidence.csv> --strict
    python validate_evidence.py <evidence.csv> --aggregate

EXIT CODES
    0  structure valid (and, with --aggregate, the gate was open)
    1  usage or file error
    2  structural validation failed
    3  aggregation refused - rows not all locked

Python standard library only.
"""

from __future__ import annotations

import argparse
import csv
import datetime as _dt
import os
import re
import sys

# --------------------------------------------------------------------------
# Schema - must match EVIDENCE_SCHEMA.md section 2 and the template header
# --------------------------------------------------------------------------

COLUMNS = [
    "participant_id",
    "age_band",
    "occupation",
    "country",
    "segment",
    "c4_status",
    "first_sentence_verbatim",
    "difficult_week_narrative",
    "interaction_evidence",
    "interaction_score",
    "verbatim_causal_chains",
    "recurrence_score",
    "existing_tools",
    "existing_tools_score",
    "existing_tool_gap",
    "gap_score",
    "gap_evidence",
    "memory_value_score",
    "personalization_need_score",
    "trust_score",
    "frequency_score",
    "action_taken",
    "employer_trust_score",
    "counter_evidence",
    "researcher_notes",
    "evidence_lock_timestamp",
]

EXPECTED_IDS = ["P%02d" % n for n in range(1, 15)]  # P01 .. P14
EXPECTED_ROW_COUNT = 14

LOCK_COLUMN = "evidence_lock_timestamp"

# Every rubric score. Protocol section 6.1: 0 / 1 / 2, nothing else.
SCORE_COLUMNS = [
    "interaction_score",
    "recurrence_score",
    "gap_score",
    "memory_value_score",
    "trust_score",
    "frequency_score",
    "existing_tools_score",
    "personalization_need_score",
    "employer_trust_score",
]
VALID_SCORES = {"0", "1", "2"}

# Phenomenon vs viability - protocol section 6.1. Reported separately, always.
PHENOMENON_SIGNAL = "interaction_score"
VIABILITY_SIGNALS = [
    "recurrence_score",
    "gap_score",
    "memory_value_score",
    "trust_score",
    "frequency_score",
]
DESCRIPTIVE_SIGNALS = [
    "existing_tools_score",
    "personalization_need_score",
    "employer_trust_score",
]

# Fields that are transcription, not summary. A one-word stub is not a verbatim.
VERBATIM_COLUMNS = {
    "first_sentence_verbatim": 20,
    "difficult_week_narrative": 40,
    "interaction_evidence": 20,
    "verbatim_causal_chains": 20,
    "gap_evidence": 15,
    "action_taken": 20,
    "counter_evidence": 15,
}

# Single-character cells are legitimate elsewhere (a score is "2", a segment is
# "A"), so the floor outside the verbatim fields is 1. Junk in those fields is
# caught by the placeholder and enum checks instead.
MIN_LENGTH_DEFAULT = 1

VALID_SEGMENTS = {"A", "B", "C1", "C2", "C3", "C4"}
SEGMENT_QUOTA = {"A": 5, "B": 5, "C1": 1, "C2": 1, "C3": 1, "C4": 1}

VALID_C4_STATUS = {
    "not_applicable",
    "recruited_interviewed",
    "recruited_withdrew",
    "not_recruited",
}
C4_STATUS_ALLOWING_ANALYSIS = "recruited_interviewed"

# Sentinels. Each records a deliberate absence, so absence survives into the
# output instead of looking like a coding gap. See EVIDENCE_SCHEMA.md 2.4/2.7.
SENTINEL_NO_CHAIN = "NONE_STATED:"
SENTINEL_NO_TOOLS = "NONE_USED"
SENTINEL_TOOL_GAP_NA = "NOT_APPLICABLE"
SENTINEL_NO_COUNTER = "NONE_RECORDED"

# A sentinel is a deliberate statement of absence, so it is exempt from the
# minimum length that applies to transcription in the same column.
SENTINEL_EXEMPT = {
    "existing_tools": {SENTINEL_NO_TOOLS},
    "existing_tool_gap": {SENTINEL_TOOL_GAP_NA},
    "counter_evidence": {SENTINEL_NO_COUNTER},
}

# Placeholder shapes. Checked against the whole cell, case-insensitively.
PLACEHOLDER_EXACT = {
    "", "-", "--", "---", "_", "__", ".", "..", "...", "?", "??", "???",
    "x", "xx", "xxx", "n/a", "na", "n.a.", "nil", "none", "null", "nan",
    "tbd", "t.b.d.", "tba", "todo", "to do", "to-do", "pending", "placeholder",
    "fill", "fill me", "fill in", "fill this in", "text here", "quote here",
    "verbatim here", "insert", "insert here", "same as above", "as above",
    "ditto", "see above", "see notes", "unknown", "?  ?", "lorem ipsum",
    "example", "sample", "test", "coming", "later", "n a",
}
PLACEHOLDER_PATTERNS = [
    re.compile(r"^<.*>$", re.S),          # <her first sentence>
    re.compile(r"^\[.*\]$", re.S),        # [transcribe here]
    re.compile(r"^\{.*\}$", re.S),        # {chain}
    re.compile(r"^lorem ipsum\b", re.I),
    re.compile(r"^x{2,}$", re.I),
    re.compile(r"^\W+$"),                 # punctuation only
]

# action_taken should read as an ordered sequence (schema 2.6). Warning only.
SEQUENCE_HINTS = ("->", "→", ";", " then ", " -> ", "1.", "1)")

BAR = "=" * 74
RULE = "-" * 74


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def _norm(value):
    """Collapse whitespace so a cell of spaces is treated as empty."""
    if value is None:
        return ""
    return " ".join(str(value).split())


def _is_placeholder(value):
    v = _norm(value)
    if v.lower() in PLACEHOLDER_EXACT:
        return True
    for pattern in PLACEHOLDER_PATTERNS:
        if pattern.match(v):
            return True
    return False


def _parse_lock_timestamp(value):
    """
    Return (datetime, None) or (None, reason).

    Requires ISO 8601 with an explicit timezone. A naive timestamp is rejected:
    a lock is a claim about when coding closed, and that claim needs an offset.
    """
    raw = _norm(value)
    if not raw:
        return None, "empty"
    candidate = raw
    if candidate.endswith(("Z", "z")):
        candidate = candidate[:-1] + "+00:00"
    try:
        parsed = _dt.datetime.fromisoformat(candidate)
    except ValueError:
        return None, "not ISO 8601 (expected e.g. 2026-10-04T16:20:00Z)"
    if parsed.tzinfo is None:
        return None, "no timezone offset (expected trailing Z or +HH:MM)"
    now = _dt.datetime.now(_dt.timezone.utc)
    if parsed > now + _dt.timedelta(minutes=5):
        return None, "timestamp is in the future"
    return parsed, None


# --------------------------------------------------------------------------
# Row-level structural validation - no evidence is interpreted here
# --------------------------------------------------------------------------

class RowResult(object):
    def __init__(self, participant_id):
        self.participant_id = participant_id
        self.errors = []
        self.warnings = []
        self.locked = False       # has a valid lock timestamp
        self.complete = False     # no structural errors

    @property
    def usable(self):
        """A row may enter aggregation only if it is both complete and locked."""
        return self.complete and self.locked


def validate_row(row, index):
    pid = _norm(row.get("participant_id"))
    result = RowResult(pid or "row %d" % index)

    expected_pid = EXPECTED_IDS[index] if index < len(EXPECTED_IDS) else None
    if expected_pid and pid != expected_pid:
        result.errors.append(
            "participant_id is %r, expected %r (row order is fixed by the template)"
            % (pid, expected_pid))

    # --- presence and placeholder checks on every column -------------------
    for column in COLUMNS:
        value = _norm(row.get(column))
        if value == "":
            result.errors.append("%s: missing (required in a locked row)" % column)
            continue
        if _is_placeholder(value):
            result.errors.append(
                "%s: placeholder text, not evidence (%r)" % (column, value[:48]))
            continue
        if value.upper() in SENTINEL_EXEMPT.get(column, ()):
            continue
        if column == "verbatim_causal_chains" and value.upper().startswith(SENTINEL_NO_CHAIN):
            continue  # length of the sentinel form is checked below
        minimum = VERBATIM_COLUMNS.get(column, MIN_LENGTH_DEFAULT)
        if len(value) < minimum:
            result.errors.append(
                "%s: too short to be a capture (%d chars, minimum %d)"
                % (column, len(value), minimum))

    # --- enums -------------------------------------------------------------
    segment = _norm(row.get("segment"))
    if segment and segment not in VALID_SEGMENTS:
        result.errors.append(
            "segment: %r is not one of %s"
            % (segment, "/".join(sorted(VALID_SEGMENTS))))

    c4_status = _norm(row.get("c4_status"))
    if c4_status and c4_status not in VALID_C4_STATUS:
        result.errors.append(
            "c4_status: %r is not one of %s"
            % (c4_status, "/".join(sorted(VALID_C4_STATUS))))
    elif c4_status:
        if segment == "C4" and c4_status == "not_applicable":
            result.errors.append(
                "c4_status: this row is segment C4 and cannot be 'not_applicable'")
        if segment and segment != "C4" and c4_status != "not_applicable":
            result.errors.append(
                "c4_status: must be 'not_applicable' on a non-C4 row")

    # --- scores: 0 / 1 / 2 only -------------------------------------------
    # Invalid values are echoed so they can be fixed. Valid values are never
    # printed: reading the scores is aggregation, and aggregation is gated.
    for column in SCORE_COLUMNS:
        value = _norm(row.get(column))
        if value == "":
            continue  # already reported as missing
        if value not in VALID_SCORES:
            note = ""
            if column == PHENOMENON_SIGNAL:
                note = "  <- interaction_score must be 0, 1 or 2 and nothing else"
            result.errors.append(
                "%s: %r is not a valid rubric score (allowed: 0, 1, 2)%s"
                % (column, value, note))

    # --- verbatim causal chains actually captured --------------------------
    chains = _norm(row.get("verbatim_causal_chains"))
    if chains:
        if chains.upper().startswith(SENTINEL_NO_CHAIN):
            tail = chains[len(SENTINEL_NO_CHAIN):].strip()
            if len(tail) < 10 or _is_placeholder(tail):
                result.errors.append(
                    "verbatim_causal_chains: '%s' must be followed by her "
                    "verbatim words (a rejected connection is data, and is "
                    "recorded, not left blank)" % SENTINEL_NO_CHAIN)
        elif chains.upper() == SENTINEL_NO_CHAIN.rstrip(":"):
            result.errors.append(
                "verbatim_causal_chains: bare sentinel with no verbatim text")

    # --- existing tools / existing-tool gap / Gap: three fields, never merged
    tools = _norm(row.get("existing_tools"))
    tool_gap = _norm(row.get("existing_tool_gap"))
    if tool_gap.upper() == SENTINEL_TOOL_GAP_NA and tools.upper() != SENTINEL_NO_TOOLS:
        result.warnings.append(
            "existing_tool_gap is '%s' but existing_tools is not '%s' - "
            "confirm this is intended" % (SENTINEL_TOOL_GAP_NA, SENTINEL_NO_TOOLS))
    if tools and tools.upper() not in (SENTINEL_NO_TOOLS,) and len(tools) < 3:
        result.warnings.append(
            "existing_tools: very short - name the tools, or use '%s'"
            % SENTINEL_NO_TOOLS)

    # --- action taken ------------------------------------------------------
    action = _norm(row.get("action_taken"))
    if action and not any(h in action for h in SEQUENCE_HINTS):
        result.warnings.append(
            "action_taken: no sequence separator found - protocol 6.2 asks for "
            "the sequence of what she did, in order (use '->' between steps)")

    # --- counter-evidence --------------------------------------------------
    counter = _norm(row.get("counter_evidence"))
    if counter.upper() == SENTINEL_NO_COUNTER:
        result.warnings.append(
            "counter_evidence is '%s' - protocol 8 point 6 makes counter-"
            "evidence non-optional; confirm the transcript really holds none"
            % SENTINEL_NO_COUNTER)

    # --- the lock ----------------------------------------------------------
    stamp, reason = _parse_lock_timestamp(row.get(LOCK_COLUMN))
    if stamp is None:
        result.locked = False
        if reason != "empty":
            result.errors.append("%s: %s" % (LOCK_COLUMN, reason))
    else:
        result.locked = True

    result.complete = not result.errors
    return result


# --------------------------------------------------------------------------
# File-level checks
# --------------------------------------------------------------------------

def load_rows(path):
    """Return (rows, file_errors). Never raises on malformed content."""
    file_errors = []
    if not os.path.isfile(path):
        return None, ["file not found: %s" % path]
    try:
        with open(path, "r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            header = reader.fieldnames
            if header is None:
                return None, ["file is empty: %s" % path]
            header = [_norm(h) for h in header]
            if header != COLUMNS:
                missing = [c for c in COLUMNS if c not in header]
                unexpected = [c for c in header if c not in COLUMNS]
                file_errors.append(
                    "header does not match the schema (expected %d columns in "
                    "the order defined by EVIDENCE_SCHEMA.md section 2)"
                    % len(COLUMNS))
                if missing:
                    file_errors.append("  missing columns: %s" % ", ".join(missing))
                if unexpected:
                    file_errors.append("  unexpected columns: %s" % ", ".join(unexpected))
                if not missing and not unexpected:
                    file_errors.append("  columns are present but out of order")
                return None, file_errors
            rows = [dict(r) for r in reader]
    except (OSError, UnicodeDecodeError, csv.Error) as exc:
        return None, ["could not read %s: %s" % (path, exc)]
    return rows, file_errors


def check_participant_set(rows):
    errors = []
    ids = [_norm(r.get("participant_id")) for r in rows]
    if len(rows) != EXPECTED_ROW_COUNT:
        errors.append(
            "expected %d participant rows (P01-P14), found %d"
            % (EXPECTED_ROW_COUNT, len(rows)))
    seen = {}
    for pid in ids:
        seen[pid] = seen.get(pid, 0) + 1
    duplicates = sorted(p for p, n in seen.items() if n > 1 and p)
    if duplicates:
        errors.append("duplicate participant_id: %s" % ", ".join(duplicates))
    absent = [p for p in EXPECTED_IDS if p not in seen]
    if absent:
        errors.append("missing participant rows: %s" % ", ".join(absent))
    unexpected = sorted(p for p in seen if p and p not in EXPECTED_IDS)
    if unexpected:
        errors.append("unexpected participant_id: %s" % ", ".join(unexpected))
    return errors


def check_sampling_composition(rows):
    """
    Screener section 2 quota and section 6/9 C4 rule. Structural only - this
    says nothing about what any participant reported.
    """
    errors = []
    counts = {}
    for row in rows:
        segment = _norm(row.get("segment"))
        if segment in VALID_SEGMENTS:
            counts[segment] = counts.get(segment, 0) + 1
    for segment, required in sorted(SEGMENT_QUOTA.items()):
        found = counts.get(segment, 0)
        if found != required:
            errors.append(
                "segment %s: quota is %d row(s), file has %d (screener section 2)"
                % (segment, required, found))

    c4_rows = [r for r in rows if _norm(r.get("segment")) == "C4"]
    if len(c4_rows) == 1:
        status = _norm(c4_rows[0].get("c4_status"))
        if status != C4_STATUS_ALLOWING_ANALYSIS:
            errors.append(
                "C4 c4_status is %r - screener section 9: 'C4 not found -> do "
                "not proceed to analysis without her.' She is not substitutable"
                % status)
    return errors


# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------

def print_header(path):
    print(BAR)
    print("WLOS Phase A - evidence structure check")
    print("file: %s" % path)
    print(BAR)
    print("Structure and completeness only. This checker does not interpret")
    print("participant evidence, and prints no score values.")
    print("")


def print_row_report(results):
    print("Per-row status")
    print(RULE)
    for result in results:
        if result.complete and result.locked:
            state = "COMPLETE + LOCKED"
        elif result.complete and not result.locked:
            state = "complete, NOT LOCKED"
        elif result.locked:
            state = "LOCKED BUT INVALID"
        else:
            state = "incomplete"
        print("%-6s %s" % (result.participant_id, state))
        for error in result.errors:
            print("       ERROR   %s" % error)
        for warning in result.warnings:
            print("       warning %s" % warning)
    print("")


def print_refusal(reasons, asked_for_aggregate):
    print("")
    print(BAR)
    print("REFUSED - AGGREGATION IS GATED")
    print(BAR)
    if asked_for_aggregate:
        print("You asked for an aggregate. This checker will not produce one.")
    else:
        print("No aggregate, total, count or conclusion has been produced.")
    print("")
    print("WLOS_INTERVIEW_PROTOCOL.md section 6.0:")
    print('  "Do not compute or look at aggregate scores until all 14 rows')
    print('   are locked."')
    print('  "No running totals. No \'we are at 6 of 8 so far.\' Knowing the')
    print("   count changes how interview 11 is heard, and retroactively")
    print("   changes how interview 3 is remembered.\"")
    print("")
    print("Blocking:")
    for reason in reasons:
        print("  - %s" % reason)
    print("")
    print("Nothing about the evidence in this file has been summarised,")
    print("counted, scored or compared. Finish and lock the rows above, then")
    print("run again with --aggregate.")
    print(BAR)


def compute_and_print_aggregate(rows, results):
    """
    Reached ONLY when all 14 rows are complete and locked. Emits arithmetic:
    threshold counts and kill-condition counts, phenomenon and viability
    reported separately (protocol section 8 point 5). It emits no verdict.
    """
    # Defensive re-assertion of the gate. If this ever fails, the caller is
    # wrong and the run must abort rather than compute anything.
    if not results or len(results) != EXPECTED_ROW_COUNT or not all(r.usable for r in results):
        raise AssertionError(
            "aggregate refused: gate re-check failed - not all 14 rows are "
            "complete and locked")

    def count_at_least(column, minimum):
        total = 0
        for row in rows:
            value = _norm(row.get(column))
            if value in VALID_SCORES and int(value) >= minimum:
                total += 1
        return total

    def count_equal(column, target):
        total = 0
        for row in rows:
            if _norm(row.get(column)) == str(target):
                total += 1
        return total

    n = EXPECTED_ROW_COUNT
    threshold = 9

    print("")
    print(BAR)
    print("ALL 14 ROWS COMPLETE AND LOCKED - GATE OPEN")
    print(BAR)
    print("Arithmetic only. These are counts, not findings. The decision")
    print("(Phase B / narrow / change the product) is a human judgement made")
    print("from the findings report, and is not an output of this script.")
    print("")

    print("PHENOMENON SIGNAL - does the thing exist?")
    print(RULE)
    ge1 = count_at_least(PHENOMENON_SIGNAL, 1)
    eq2 = count_equal(PHENOMENON_SIGNAL, 2)
    print("  interaction >= 1 : %2d of %d   (threshold %d: %s)"
          % (ge1, n, threshold, "met" if ge1 >= threshold else "not met"))
    print("  interaction  = 2 : %2d of %d   (counted, not gated)" % (eq2, n))
    print("")
    print("  Protocol: interaction score is evidence strength, not a market")
    print("  verdict. Interaction is NOT a sixth viability gate.")
    print("")

    print("VIABILITY SIGNALS - all five must clear (reported separately)")
    print(RULE)
    for column in VIABILITY_SIGNALS:
        value = count_at_least(column, 1)
        print("  %-26s >= 1 : %2d of %d   (threshold %d: %s)"
              % (column, value, n, threshold,
                 "met" if value >= threshold else "not met"))
    print("")

    print("DESCRIPTIVE (context, not gates)")
    print(RULE)
    for column in DESCRIPTIVE_SIGNALS:
        value = count_at_least(column, 1)
        print("  %-26s >= 1 : %2d of %d" % (column, value, n))
    print("")
    print("  existing_tools is context for interpreting Gap. Only Gap is a")
    print("  viability signal. The two are separate and must not be merged.")
    print("")

    print("INDEPENDENT KILL CONDITIONS")
    print(RULE)
    kills = [
        ("interaction = 0 in >= 10", count_equal("interaction_score", 0), 10),
        ("trust <= 1 in >= 7", sum(
            1 for r in rows
            if _norm(r.get("trust_score")) in VALID_SCORES
            and int(_norm(r.get("trust_score"))) <= 1), 7),
        ("gap = 0 in >= 9", count_equal("gap_score", 0), 9),
        ("employer trust = 0 in >= 7", count_equal("employer_trust_score", 0), 7),
    ]
    for label, value, trigger in kills:
        print("  %-28s : %2d of %d   (trigger at %d: %s)"
              % (label, value, n, trigger,
                 "TRIGGERED" if value >= trigger else "not triggered"))
    print("")

    print(RULE)
    print("Carry into the findings report, whatever the counts say:")
    print("  - Nine of fourteen justifies a prototype. It does NOT establish")
    print("    a market.")
    print("  - Do not write 'common'. The supported phrasing is 'sufficiently")
    print("    represented in this purposive sample'.")
    print("  - Protocol 8.1 sentence must appear verbatim in the report.")
    print("  - Strongest counter-evidence must be stated as forcefully as the")
    print("    supporting case (protocol 8 point 6).")
    print(BAR)


# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description=(
            "Structural checker for the WLOS Phase A evidence file. Checks "
            "structure and completeness only; never interprets evidence, and "
            "never aggregates while any row is unlocked."),
        epilog="Exit codes: 0 ok, 1 file/usage error, 2 invalid, 3 aggregation refused.")
    default_csv = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                               "evidence_template.csv")
    parser.add_argument(
        "csv_path", nargs="?", default=default_csv,
        help="evidence CSV (default: the template next to this script)")
    parser.add_argument(
        "--aggregate", action="store_true",
        help="request threshold counts. Refused unless all 14 rows are locked.")
    parser.add_argument(
        "--strict", action="store_true",
        help="treat warnings as failures (use before the findings report)")
    parser.add_argument(
        "--quiet", action="store_true",
        help="suppress the per-row report; print only blocking problems")
    args = parser.parse_args(argv)

    path = args.csv_path
    print_header(path)

    rows, file_errors = load_rows(path)
    if rows is None:
        for error in file_errors:
            print("FILE ERROR  %s" % error)
        print("")
        print_refusal(["the file could not be read against the schema"],
                      args.aggregate)
        return 1

    blocking = []

    set_errors = check_participant_set(rows)
    for error in set_errors:
        print("FILE ERROR  %s" % error)
    if set_errors:
        print("")
    blocking.extend(set_errors)

    results = [validate_row(row, index) for index, row in enumerate(rows)]
    if not args.quiet:
        print_row_report(results)

    for result in results:
        if not result.complete:
            blocking.append("%s: %d structural error(s)"
                            % (result.participant_id, len(result.errors)))
        elif not result.locked:
            blocking.append("%s: no evidence lock timestamp - row is not locked"
                            % result.participant_id)
        if args.strict and result.warnings:
            blocking.append("%s: %d warning(s), and --strict is on"
                            % (result.participant_id, len(result.warnings)))

    # Composition is only meaningful once the rows carry segments.
    if not set_errors:
        composition_errors = check_sampling_composition(rows)
        for error in composition_errors:
            print("SAMPLING    %s" % error)
        if composition_errors:
            print("")
        blocking.extend(composition_errors)

    gate_open = (
        not blocking
        and len(results) == EXPECTED_ROW_COUNT
        and all(r.usable for r in results)
    )

    if not gate_open:
        print_refusal(blocking or ["the gate check did not pass"], args.aggregate)
        if args.aggregate:
            return 3
        return 2

    print("Structure valid: 14 rows, all fields present, all rows locked.")

    if args.aggregate:
        compute_and_print_aggregate(rows, results)
    else:
        print("")
        print("No aggregate produced. The gate is open; run with --aggregate")
        print("when the study is ready for it. Nothing has been counted here.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
