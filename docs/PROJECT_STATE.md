# Project State — Maren and WLOS

**As at:** 23 September 2026
**Status:** **LOCKED** — this is the agreed project state of record.
Superseded only by the Phase A findings report.
**Purpose:** single record of where both products stand, what is decided, what
is hypothesis, and what is unproven.

> **Engineering rule in force:** no WLOS implementation. The platform work is
> not discarded — it waits for product evidence. WLOS repo states are
> preserved; exact HEADs are in section 1.
>
> **Research rule in force:** participants are never told the candidate jobs and
> asked which they want. Evidence must emerge from experience → what happened →
> what she did → what was missing → what she wished existed → whether
> remembering would have helped.

---

## 1. Two products, fully separated

| | Maren | WLOS |
|---|---|---|
| What it is | Pregnancy-focused product, stable | Lifelong companion, in discovery |
| Status | **Working, deployed, live** | **Repos seeded, no product work** |
| Repos | `Maren-Backend`, `Maren-Frontend` | `WLOS_Backend`, `WLOS_App`, `WLOS_FrontEnd` |
| Hosting | `maren-api` / `maren-app` `.hamzadecor.com` | None yet |
| Database | `MarenPlatform` | `WlosPlatform` |
| Ports | API 5199, portal 4173 | API 5299, portal 4273 |
| App id | `com.ostrevo.maren` | `com.ostrevo.wlos` |

### Commit state

Maren is pinned below. WLOS HEADs move as research documents land; read them
from git rather than from here, so this table cannot go stale.

| Repo | HEAD | Commits |
|---|---|---|
| `Maren-Backend` | `813fd15` | 65 |
| `Maren-Frontend` | `2bc6030` | 61 |
| `WLOS_Backend` | see git | — |
| `WLOS_App` | see git | — |
| `WLOS_FrontEnd` | `301688d` | 16 |

**Maren services verified live 23 Sep:** API `database: ok`, portal `200`.

---

## 2. What was done to Maren

Maren was broken in several ways and is now working. Two real defects were found
and fixed:

1. **`Country.Iso2` did not exist** — the column is `IsoCode`. This failed
   `contextResolution`, the first stage of the Life OS pipeline, on every call
   to `/me/today`, starving every stage after it. Fixed in `813fd15`.
2. **No ProGuard rules at all** — the release APK crashed on launch, every
   time. R8 stripped WorkManager's Room implementation, which `androidx.startup`
   then failed to initialise before any Flutter code ran. Release-only, which is
   why a debug build never showed it. Fixed in `2bc6030`.

Also delivered: database deployed (57 scripts), admin account created, staging
tunnel live, release APK built and verified running on an emulator.

**Important correction on the record.** An earlier report claimed 177 files
existed only on one machine, plus a list of missing interfaces, unregistered
repositories and a stale runbook. That was measured against a checkout **49
commits behind** `origin/main`. After fetching, upstream already had all of it
and built with 0 errors. Only the two defects above were real.

---

## 3. What WLOS is

**North star:**

> A lifelong personal companion that helps her care for herself, manage her
> life, grow, remember what matters, and navigate difficult moments — with an
> understanding of the context she chooses to share.

**Principle:** every part of her life can matter, but no single part defines
her.

WLOS is not "an app that detects life interactions." Contextual intelligence is
the **brain**, not the product. The product spans: know me · care for me · help
me live · help me grow · understand me · support me · remember for me · help me
connect · guide me · grow with me.

---

## 4. What the platform already has

Measured against the deployed `WlosPlatform`, not inferred from docs.

| Capability | State |
|---|---|
| Life domains | **22, hierarchical** — `pregnancy` is a child of `health` |
| Life stages | **12**, with history and `Source` (declared vs derived) |
| Role modes | **8**, multi-select |
| Targeting dimensions | **10** — `week` (pregnancy) is tenth by sort order |
| Targeting evaluator | `fn_TargetedItems` — 3 operators, OR within / AND across |
| Knowledge signals | **12**, with `SignalRelation` carrying `RelationKind`, `Strength`, `SourceNote` |
| State dimensions | **9**, each with `UnknownText` |
| Pipeline | **24 stages**, explainability contract on every decision |
| Endpoints | 68 |
| AI safety | `AI.SafetyEvent` — clinical and crisis scores, refusal category, model and prompt version |
| RTL languages | `Identity.Language.IsRightToLeft` |
| Machine-translation flag | `ContentTranslation.IsMachineTranslated` |
| Sharing consent | `Health.ShareGrant` — scoped, expiring, revocable, view-counted |
| **Content items** | **6** |

### The two facts that matter most

**The FACT → OBSERVATION → PATTERN → INTERPRETATION hierarchy is already
implemented.** `SignalRelation` uses `commonly_precedes` and
`commonly_co_occurs` — deliberately non-causal language — with `Strength` as
confidence and `SourceNote` as provenance. Its seeded rows are the thesis
itself: `long_work → high_stress → low_mood`.

**The constraint is editorial, not technical.** 22 domains, 10 dimensions, 12
stages, 24 pipeline stages, 68 endpoints — and **6 content items**.

---

## 5. What is genuinely missing

Six primitives, in cost order:

| Concept | Cost | Note |
|---|---|---|
| **Need** | small | Reference table + user table with expiry + one seed row |
| **Intent / response mode** | small | `Coach.ToneProfile` exists (4 tones); intent does not |
| **Preference + boundary + controls** | **medium — do first** | **Nothing exists.** One assembly point to apply it |
| Responsibility load | medium | Self-declared only. No dependents model anywhere |
| Country safety configuration | medium | `Identity.Country` has 4 columns; no emergency, healthcare or regulatory profile |
| Support network | **large** | Account-to-account. Safety rules first |

**Preference and boundary first** because the platform can personalise and **has
no model of her saying no**. The only per-user preference tables are
`Identity.Profile` and `Health.BirthPreference`. `Administration.Setting` has no
`UserId`. Retrofitted after features exist, a boundary becomes fifty enforcement
points.

---

## 6. Unresolved future work — do not resolve now

**Neither of the two findings below is a defect to fix. Both are decisions that
need evidence or policy first, and both are out of scope during Phase A.**

### 6.1 No user-data write path exists

`Health` has **9 tables and 0 stored procedures**, with no `Health.*` reference
in any C# file. `Timeline.Event` — the sole input to signals, state, behaviour,
goals, recommendations, coaching and prediction — has **no endpoint that can
write to it**. The read and evaluation foundation is substantial; the loop
*user does something → system records it → system understands it → later
interaction uses that history* has no first step.

**Do not build it yet.** Phase A has not told us what needs remembering. The
validated first experience may require timeline events, health records, mood,
sleep, goals, a need, or something much smaller. Build the minimum write path
**after** the evidence names it.

### 6.2 Deletion semantics are contractually unresolved

83 of 87 tables carry `IsDeleted`; constitution §1.3 requires deletion to mean
deletion. No procedure exports or deletes a user.

**This must not be settled by an engineer choosing one.** It is a data-policy
decision with legal and audit consequences on both sides — soft delete preserves
the audit trail the platform depends on; hard delete is what §1.3 promises her.
Deliberate decision required, later.

### 6.3 Carried, lower priority

| Item | Note |
|---|---|
| Orphan table in `WlosPlatform` | Created by the mistaken manual re-run of script 34 (§6.4), after script 74 applied the audit contract. The only non-exempt table outside that contract. **Do not modify database state during the freeze** — drop it when the freeze lifts |
| Targeting evaluator documentation is stale | `WLOS_FOUNDATION.md` §§2.1–2.7 describe the superseded evaluator. Whether `Rules.fn_Match` preserves the three operators, OR-within/AND-across, the universal fallback and UNKNOWN handling is **not verified** and stays marked so until checked |

### 6.4 Retracted — history retained

**`ContentTargetingRule` "deployment defect" — withdrawn. Removed from the
active defect list.**

The actual sequence is designed migration behaviour:

```
34_ContentTargeting.sql   creates the legacy table
45_RuleEngine.sql         migrates its rows, then DROPs it
46_Procs_RuleEngine.sql   rewrites the functions onto Rules.Rule
Rules.Rule                becomes the real rule source
fn_TargetedItems          verified reading Rules.Rule
```

`Dashboard.CardRule` is dropped identically at `45_RuleEngine.sql:251`. A clean
deploy producing no `ContentTargetingRule` is **correct**, and the deploy
reporting success was accurate.

It was reported as the highest-priority backend defect and reproduced in a
clean-room database. The reproduction was of intended behaviour. The
investigation history is kept here so the error stays legible; it is no longer
an open item.
| Maren's deployed database is stale | Medium | Built from the pre-fetch checkout. 43 of 86 tables lack the audit contract; `WlosPlatform` has 3 (documented exemptions) |
| `WLOS_FrontEnd` has no docs index | Low | Carries the product audit only |
| `WLOS_Backend` references Maren repo URLs | Low | 20 files, 19 Markdown + 1 YAML, **zero `.cs`** |

---

## 7. Research completed

Nine documents in `WLOS_Backend/docs/` and `WLOS_App/docs/`:

`WLOS_PRODUCT_AUDIT` · `WLOS_LIFE_MODEL` · `WLOS_CONSTITUTION` ·
`WLOS_HUMAN_MODEL_REVIEW` · `WLOS_FOUNDATION` · `WLOS_MARKET_RESEARCH` ·
`WLOS_MARKET_RESEARCH_II` · `WLOS_INTERVIEW_PROTOCOL` ·
`WLOS_RECRUITMENT_SCREENER`

### Key external findings

| Finding | Source date |
|---|---|
| **EU KIDS Act** bans, for minors: profiling-based recommender feeds, streaks that penalise non-return, AI companions (off by default; banned under 13), and requires conversation memory deletion. Penalties to **6% of global turnover** | **17 Sep 2026** |
| Italy's Garante fined Replika's developer **€5M**, partly for age verification despite an 18+ policy | 2025 |
| Category day-30 retention median | **5%** |
| Streak paradox: critical to retention, **44%** motivation drop-off after breaking one | 2026 |
| Trust in AI health advice **with** professional oversight 49–55%, **without** 3–6% | 2026 |
| Gen Z burnout **74%**; **96%** of women report high/extreme pressure vs 86% of men | 2026 |
| 69% of large US employers view holistic women's health as critical to recruitment; Maven covers 6.7M lives | 2026 |
| Smartphone ownership gender gap in LMICs **13%**; 810M women not using mobile internet | GSMA 2026 |
| Market $6.3B (2026) → $23.4B (2033); NA 38.2% share, APAC 15.8% CAGR | 2026 |
| Regulatory classification is determined by **intended use and marketing copy**, not technology | FDA rev. 6 Jan 2026 / EU MDR Rule 11 |

---

## 8. Decided · Hypothesis · Unproven

### Decided

- Maren and WLOS are separate products, separately hosted and versioned
- Maren stays pregnancy-focused and is not converted
- WLOS is seeded from Maren with full history preserved
- The constitution governs what may never be inferred
- Research instruments are **locked** for Phase A

### Hypothesis — not decided

| Hypothesis | Standing |
|---|---|
| **Launch age — unresolved** | **16+ and 18+ both remain candidates. No launch-age decision has been made.** Needs legal review per jurisdiction. The stronger question is architectural: is a non-personalised, streak-free WLOS still WLOS? |
| 18–35 is the segment | Best-evidenced of six; **three segments unresearched** |
| B2B2C distribution | Strongest commercial evidence — but an employer-funded product raises a trust question that may matter more than acquisition cost |
| "What do you need today?" is the entry loop | Only loop that works on day one with no data |

### Unproven

- **Whether the join is perceptible in use.** The largest unknown. Only a
  working Today screen answers it
- Whether longitudinal context beats a sharp single job at day 31. **No
  competitor has proven it** — the opportunity and the risk
- Retention. Country. Pricing. Final feature set

---

## 9. Immediate next step

### 9.0 Do not touch — the full list

Everything below waits for the Phase A Findings Report. Each was recommended at
some point in the research; **none is authorised**:

~~`ContentTargetingRule` fix~~ *(retracted - not a defect)* · Need implementation · preference and boundary
tables · personalization controls · response modes · content expansion · Today
screen · AI implementation · camera implementation · relationship model ·
country safety configuration · market ranking · country selection · pricing ·
B2B2C implementation · streak redesign

**A recommendation in a research document is not authorisation to build.** Where
an earlier document lists an engineering sequence — including Part 8 of the
constitution — that sequence is suspended.

**RETRACTED: there was no `ContentTargetingRule` defect** - script 45 drops the
table deliberately. See section 6. Nothing here changes the freeze.

### 9.1 The one next action

**Recruit C4.**

Not another architecture review. Not another market report. Not another backend
migration. Not another feature.

> Find the woman who started a health, fitness or habit app within the last
> year, stopped using it, and is willing to explain what was happening around
> the time she stopped.

She is non-substitutable. She is the only person who can explain day 31, and
analysis does not proceed without her.

### 9.2 Then

**Phase A: 14 interviews.** No backend work.

| Group | N |
|---|---|
| 18–27 early career | 5 |
| 28–35 working | 5 |
| Sceptics, recruited for objection | 4 |

**Recruit C4 first** — the woman who started a health app and stopped. She is
marked non-substitutable; she is the only person who can explain day 31.

Discipline: code within 24 hours, lock the row, **no running totals**, no
interpretation during fieldwork, no AI analysis mid-study.

Gate: interaction ≥1 in ≥9 of 14 (phenomenon), **and all five** of recurrence,
gap, memory value, trust, frequency clearing ≥9 (viability). Nine of fourteen
justifies a prototype; **it does not establish a market**.

### The Phase A findings report — required contents

Nothing is designed until this exists:

1. Strongest **supporting** evidence
2. Strongest **counter**-evidence, stated as forcefully
3. Interaction evidence — scores and verbatim chains
4. Recurrence
5. Existing-tool gap *(recorded separately from Gap)*
6. Memory value
7. Personalization need
8. Trust
9. Frequency
10. **Action taken** — the sequence of what she actually did
11. Employer trust
12. Thresholds and kill conditions, phenomenon and viability **reported
    separately**
13. Decision: **Phase B · narrow · or change the product**

Only after item 13 is the first real WLOS experience designed.

---

## 10. Status board

```
Maren product          GREEN   working, deployed, live
Maren defects          GREEN   both real ones fixed
WLOS repos             GREEN   seeded, independent, verified
WLOS architecture      GREEN   stop expanding
Human model            GREEN   10 of 15 dimensions exist
Trust / constitution   GREEN   written, and already partly implemented
Market research        GREEN   sufficient for discovery
Research instruments   GREEN   LOCKED
Recruitment            AMBER   not started
Segment                AMBER   unknown
Country                AMBER   unknown
Business model         AMBER   B2B2C hypothesis only
Launch age             AMBER   unresolved - 16+ and 18+ both candidates
Core problem           AMBER   interview validation pending
Targeting deploy bug   RED     blocks reproducible environments
Core experience        RED     not proven
Retention              RED     not proven
Product-market fit     RED     completely unproven
```

This is a healthy position. The project has not failed to build a product — it
has reached the point where building one would be rational.
