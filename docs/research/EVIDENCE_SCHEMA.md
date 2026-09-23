# WLOS Phase A — Evidence Capture Schema

**Date:** 23 September 2026
**Companion to:** `docs/WLOS_INTERVIEW_PROTOCOL.md` (**LOCKED**) and
`docs/WLOS_RECRUITMENT_SCREENER.md` (**LOCKED**)
**Applies to:** the 14 Phase A interviews, `P01`–`P14`
**Status:** infrastructure only. This document defines *where evidence is
written*. It does not amend either locked instrument, and it makes no claim
about what the evidence will show.

---

## 0. What this is, and what it deliberately is not

This schema is the row format behind item 1 of protocol §8 ("the rubric table —
14 rows, one per interview"). It exists so that fourteen conversations can be
written down in a comparable shape, one row at a time, and **locked** before
anyone looks at them together.

It is **not** an analysis format. Nothing here scores a participant, ranks one,
compares one to another, or produces a finding. The companion checker
(`validate_evidence.py`) checks structure and completeness only; it never reads
the *meaning* of a cell.

### The single rule everything else serves

> Protocol §6.0: **Do not compute or look at aggregate scores until all 14 rows
> are locked.**

```
interview -> transcript -> pseudonymise -> code -> LOCK ROW
                                                     |
                          (repeat 14 times, no aggregation)
                                                     |
                                    aggregate -> interpret
```

The checker enforces the gate mechanically. It refuses to emit any total,
count, distribution or threshold result while a single row is unlocked, and it
refuses to emit a decision at any time.

---

## 1. Files

| File | Role |
|---|---|
| `docs/research/EVIDENCE_SCHEMA.md` | This document — field definitions |
| `docs/research/evidence_template.csv` | Header row + 14 empty rows, `P01`–`P14` |
| `docs/research/validate_evidence.py` | Deterministic structural checker |

**Working copy.** Do not code into the template. Copy it once:

```
cp docs/research/evidence_template.csv <secure-location>/phase_a_evidence.csv
```

The working copy holds pseudonymised research data and is governed by protocol
§3 ("store in one named place; delete recordings after coding"). It must not be
committed to this repository, and per §3 and screener §7 its contents must not
be pasted into any third-party AI tool.

---

## 2. Field definitions

26 columns. **All are required and must be non-empty in a locked row.** Column
order in the CSV is the order below.

### 2.1 Identity and sampling context

| # | Column | Type | Definition |
|---|---|---|---|
| 1 | `participant_id` | `P01`–`P14` | Pseudonym. Fixed by the template; never reassigned, never reused if someone withdraws |
| 2 | `age_band` | text | `18-27`, `28-35`, or `36-45` (Group C only). Band, never date of birth — screener §7 pseudonymisation |
| 3 | `occupation` | text | Broad occupation as she described it. Feeds screener §2 spread requirements, not analysis |
| 4 | `country` | text | Country of residence |
| 5 | `segment` | enum | `A`, `B`, `C1`, `C2`, `C3`, `C4` — screener §2 and §6 |
| 6 | `c4_status` | enum | See §2.2 |

**Quota, from screener §2 and §6.** Five `A`, five `B`, and exactly one each of
`C1`, `C2`, `C3`, `C4`. The checker verifies this composition before it will
aggregate.

`segment` records recruitment route only. Per screener §2, with n=5 per group
**nothing may be compared between groups**, and the checker never groups by it.

### 2.2 `c4_status` — the non-substitutable interview

Screener §6 and §9: C4 is the woman who started a health, fitness or habit app
within the last year and stopped. She is the only person who can explain day 31.
Screener stop condition: **"C4 not found → do not proceed to analysis without
her."**

| Value | Meaning |
|---|---|
| `not_applicable` | This row is not the C4 participant. Required for all 13 other rows |
| `recruited_interviewed` | The C4 participant, recruited and interviewed |
| `recruited_withdrew` | Recruited, did not complete. **Analysis does not proceed** |
| `not_recruited` | Not found. **Analysis does not proceed** |

The checker refuses to aggregate unless exactly one row is `segment = C4` with
`c4_status = recruited_interviewed`.

Her protocol §7 answers — *"What was happening the week you stopped?"* and
*"Did it ever make you feel like you'd failed at something?"* — are recorded
verbatim in `counter_evidence` and `researcher_notes`. They are not scored.

### 2.3 Verbatim capture (protocol §6.2)

| # | Column | Type | Definition |
|---|---|---|---|
| 7 | `first_sentence_verbatim` | verbatim | **Her first sentence in §1, before any follow-up.** Word for word, including hesitations. Not paraphrased, not tidied |
| 8 | `difficult_week_narrative` | text | The bad week as she told it — what happened, on which days, in her order. Her nouns |
| 9 | `interaction_evidence` | text | What she actually did in §2: volunteered a chain, connected only when asked, or rejected the connection. Record the prompt used, if any |
| 11 | `verbatim_causal_chains` | verbatim | **Any causal chain in her own words.** See §2.4 |
| 22 | `action_taken` | sequence | **The sequence of what she actually did, in order.** See §2.6 |

Verbatim fields are transcription, not summary. If a cell is a summary in the
coder's voice, it is the wrong cell.

### 2.4 `verbatim_causal_chains`

Her words, in order, as she linked them. Protocol §8.2's example of strong
evidence:

> *"I thought I had a sleep problem, but when my manager changed my schedule I
> started sleeping badly, then I stopped exercising, then I was snapping at my
> partner."*

**When she named one factor and no chain, the field is still filled.** Protocol
§2: *"A no here is the most valuable data in the study."* It is recorded, not
left blank, using the explicit sentinel prefix:

```
NONE_STATED: "<her verbatim single-factor statement, or her rejection of the connection>"
```

The sentinel is structural. It records that a chain was absent, so that absence
survives into the output instead of looking like a coding gap. The checker
accepts the prefix and does not read what follows it.

### 2.5 The rubric scores (protocol §6.1)

Every score below is an integer, `0`, `1` or `2`, written as a bare digit. No
decimals, no ranges, no `1.5`, no `1-2`, no `?`. A dimension that cannot be
scored from the transcript is a coding problem, not a half-score.

#### Phenomenon

| # | Column | Values | Definition |
|---|---|---|---|
| 10 | `interaction_score` | **`0` / `1` / `2` only** | `0` = one factor · `1` = connects when asked · `2` = volunteers a chain unprompted |

Protocol thresholds section: **"Interaction score is evidence strength, not a
market verdict."** A score of `1` is a finding, not a failure. Interaction is
**not** a viability gate.

#### Viability — the five signals

| # | Column | Values | Definition |
|---|---|---|---|
| 12 | `recurrence_score` | 0–2 | `0` = one-off · `2` = names it as a recurring pattern |
| 16 | `gap_score` | 0–2 | `0` = nothing meaningful unsolved · `2` = names a specific absence |
| 18 | `memory_value_score` | 0–2 | `0` = would not help · `2` = spontaneously wants continuity |
| 20 | `trust_score` | 0–2 | `0` = refuses · `2` = would allow, **and says under what conditions** |
| 21 | `frequency_score` | 0–2 | `0` = rare · `2` = monthly or more |

#### Descriptive

| # | Column | Values | Definition |
|---|---|---|---|
| 14 | `existing_tools_score` | 0–2 | `0` = well served · `2` = has tools and none helped that week |
| 19 | `personalization_need_score` | 0–2 | `0` = generic advice fine · `2` = generic advice would be useless or wrong |
| 23 | `employer_trust_score` | 0–2 | `0` = would not believe privacy · `2` = would |

`employer_trust_score` is coded from protocol §6 — *"Would you believe it was
private?"* — and from the silence after it. The pause is the measurement; note
its length in `researcher_notes`.

### 2.6 `action_taken` (protocol §6.2)

The ordered sequence of what she *did*, not what she felt. Use `->` between
steps:

```
bad sleep -> cancelled plans -> more coffee -> worked late -> called my sister -> recovered over the weekend
```

This is its own field for a stated reason: **"WLOS does not exist to describe
her problem; it exists to help her act differently."** The sequence is what
shows where an intervention could have landed, and whether she already has a
working recovery path.

If she did nothing, that is the sequence, and it is recorded in her words rather
than left empty.

### 2.7 Existing tools, existing-tool gap, and Gap — three fields, never merged

This is the distinction the schema exists to protect. Protocol §6.1:

> **Existing tools and Gap are separate and must not be conflated.** A woman
> with **no** tool may still have **no** product opportunity — she may simply
> not need one. A woman using **five** tools may still have a **large** gap.
> **Only Gap is a viability signal; Existing tools is context for interpreting
> it.**

| # | Column | Class | What it records |
|---|---|---|---|
| 13 | `existing_tools` | **descriptive** | **What she currently uses.** Apps, notes, calendars, people, routines — named. Inventory only |
| 14 | `existing_tools_score` | **descriptive** | Rubric 0–2, per §2.5 |
| 15 | `existing_tool_gap` | **descriptive** | Where her *existing tools* fell short that week — which tool, and how. Reported separately, per PROJECT_STATE §9 item 5 |
| 16 | `gap_score` | **viability** | Rubric 0–2. Whether **something meaningful remains unsolved**, from §4 of the script |
| 17 | `gap_evidence` | **viability** | The specific absence, in her words — the answer to *"If you could have had one thing that week, what would it have been?"* |

**The four cases the split exists to keep distinguishable:**

| Existing tools | Gap | Reads as |
|---|---|---|
| None | `0` | No tool, no need. **Not an opportunity.** The case most often mis-read as one |
| None | `2` | Unserved need |
| Five | `0` | Well served. **Not an opportunity** |
| Five | `2` | Served badly — an opportunity her current stack does not close |

**Never infer one from the other.** An empty tool list is not a gap. A crowded
tool list is not a gap either. `gap_score` is coded from protocol §4 alone —
what she said was missing — and from nothing else.

`existing_tool_gap` may be `NOT_APPLICABLE` when `existing_tools` is
`NONE_USED`. That is the only case in which it may be a sentinel, and it still
says nothing about `gap_score`.

`existing_tools` may be the sentinel `NONE_USED` when she used nothing. Bare
`none`, `n/a` and `-` are rejected by the checker, because a blank-looking cell
cannot be distinguished from an unfinished one.

### 2.8 Counter-evidence and notes

| # | Column | Type | Definition |
|---|---|---|---|
| 24 | `counter_evidence` | text | **Anything in this interview that argues against the thesis**, stated as strongly as the supporting case. Her scepticism, her rejection of the connection, her refusal on privacy, her account of why a previous app stopped working |
| 25 | `researcher_notes` | text | Coding rationale, interview conditions, second-coder disagreement, the length of the §6 pause, anything that qualifies the row |

Protocol §8 point 6 is explicit: **counter-evidence is not optional.** *"The
failure mode of founder-run research is that the counter-evidence is present in
the transcripts and absent from the summary."* It is captured per row, while the
transcript is open, because it will not be recoverable later.

The permitted sentinel `NONE_RECORDED` exists so that "there was none" is a
deliberate statement rather than an empty cell. The checker warns on it every
time, by design.

**Not in this file.** Safeguarding disclosures go in the safeguarding log, never
in the research notes (protocol §3). Names, employers, and any other
identifier go nowhere — pseudonymise at transcription.

### 2.9 `evidence_lock_timestamp` — the gate

| # | Column | Type |
|---|---|---|
| 26 | `evidence_lock_timestamp` | ISO 8601, timezone-aware |

```
2026-10-04T16:20:00Z          accepted
2026-10-04T16:20:00+05:00     accepted
2026-10-04 16:20:00           rejected — no timezone
04/10/2026                    rejected — not ISO 8601
```

**Writing this timestamp is the act of locking the row.** It asserts three
things, per protocol §6.0:

1. The interview was coded **within 24 hours** of happening.
2. Every other field in this row is final.
3. **The row will not be revised in light of a later interview.**

A locked row is closed. If a genuine transcription error is found afterwards,
correct it, re-lock with a new timestamp, and record both the change and the
reason in `researcher_notes`. Do not silently edit a locked row.

A timestamp in the future is rejected. An unlocked row is not an error during
fieldwork — it is the normal state of an interview that has not happened yet.
It is only fatal to aggregation.

---

## 3. What the checker does

`validate_evidence.py` is deterministic, standard-library only, and reads one
CSV. It checks **structure and completeness**. It does not interpret evidence.

### 3.1 Structural checks

- Exactly the 26 expected columns, in order
- Exactly 14 data rows, with `participant_id` exactly `P01`…`P14`, no
  duplicates, no extras, no gaps
- Every required field present and non-empty
- No placeholder text in any field (`TBD`, `TODO`, `n/a`, `?`, `xxx`,
  `<...>`, `[...]`, `same as above`, the column name repeated, and similar)
- Verbatim fields meet a minimum length, so a one-word stub cannot pass as
  transcription
- `verbatim_causal_chains` is genuinely captured — either verbatim text, or the
  explicit `NONE_STATED:` sentinel followed by her words
- `action_taken` is present, and warns if it shows no sequence separator
- **`interaction_score` is `0`, `1` or `2` and nothing else**
- Every other rubric score is `0`, `1` or `2`
- Every row carries a valid, timezone-aware, non-future lock timestamp
- Segment composition matches the screener quota
- Exactly one C4 row, with `c4_status = recruited_interviewed`

### 3.2 What it will not do

- It does not read the content of any evidence field beyond length, sentinel
  prefix and placeholder shape
- It does not judge whether a score is the *right* score — that is the coder's
  job, and a second coder's, per protocol §6.0
- **It never prints a score value back during validation.** Only invalid values
  are echoed, so that they can be fixed. Seeing the scores is aggregation, and
  aggregation is gated
- It never emits a decision. `proceed to Phase B · narrow · change the product`
  is a human judgement made from the findings report, not an output of a script

### 3.3 The refusal

```
python validate_evidence.py <file>              structural report only
python validate_evidence.py <file> --aggregate  gated
```

`--aggregate` refuses, prints why, and exits `3` unless **all fourteen rows are
locked and structurally valid**. The refusal names each blocking row.

When the gate opens, `--aggregate` emits arithmetic only: the threshold counts
of protocol §6.1 and the kill-condition counts, with phenomenon and viability
reported **separately**, as protocol §8 point 5 requires. It stops there. It
prints no verdict, no ranking, no "looks like", and no recommendation.

**Exit codes**

| Code | Meaning |
|---|---|
| `0` | Structure valid (and, with `--aggregate`, the gate was open) |
| `1` | Usage or file error |
| `2` | Structural validation failed |
| `3` | **Aggregation refused — rows not all locked** |

`--strict` promotes warnings to failures. Run `--strict` before the findings
report; plain during fieldwork.

---

## 4. Coding order, per interview

1. Interview, then transcribe and pseudonymise (protocol §3)
2. Within 24 hours, fill every field for that one row
3. Fill `counter_evidence` **before** filling the scores
4. Run `python validate_evidence.py <file>` — fix anything it names
5. Write `evidence_lock_timestamp`. **The row is now closed**
6. Close the file. Do not read other rows. Do not count anything
7. Next interview

**Between interviews, do not:** compute a running total, ask an assistant what
patterns are emerging, revise a locked row, or form a view. Protocol §6.0:
*"The failure this prevents is invisible from the inside: the study converges on
whatever the interviewer began to believe around interview 6."*

---

## 5. Carried into the findings report

These are properties of the study design, not of the data, and they hold
whatever the fourteen rows say:

- **Selection on recent difficulty** (screener §10.1). Prevalence cannot be
  estimated from this sample — only structure. Do not write "common"; the
  supported phrasing is *"sufficiently represented in this purposive sample"*
- **Nine of fourteen justifies a prototype. It does not establish a market**
- **Interaction is not a sixth gate.** It establishes the phenomenon; the five
  viability signals establish whether it is worth building for
- **The sentence required by protocol §8.1 must appear verbatim in the report:**

  > This study tests the interaction thesis primarily among working women aged
  > 18–35. **It does not establish that this is the optimal WLOS population.**

- Contrast interviews from the screener §4.1 reserve list are recorded
  separately and **excluded from the rubric counts** — they do not belong in
  this file
