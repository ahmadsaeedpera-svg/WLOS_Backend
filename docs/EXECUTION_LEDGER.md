# EXECUTION LEDGER

**The single source of truth for resuming work.** Every session reads this
first and updates it last. Never depend on conversation history.

Machine-readable companion: [`execution-state.json`](execution-state.json).

**Last updated:** 2026-07-28 · backend `0ec3f20` · portal `f905e5b`

---

## Behaviour Intelligence — the load-bearing architectural decision

**Read this before building any consuming engine. Habits and goals already
comply; routines, recommendation, coach and prediction must too.**

Habits, routines, streaks, consistency, momentum, rhythm, preferences and
probabilities are **one behavioural model seen through different lenses**, not
six engines. There is exactly one definition of a subject
(`Behaviour.Subject` + `SubjectEvent`), exactly one function that observes it
(`Behaviour.fn_Observe`), and every engine reads what it produces.

`habitResolution` and `goalResolution` are already orchestration over it and
compute nothing. Routine, recommendation, coach and prediction must be the same.
`behaviour_test.sql` assertion 19 fails if any schema outside `Behaviour`
references the observation store or the day-counting function, so this is
structural rather than a convention somebody remembers.

### The permanent invariant

**`Growth.Routine` must never own a step list.** It references
`Behaviour.Subject`, and composition, required parts and the done-today rule all
live there. Two step lists are two answers to "what is in my evening routine",
and the day they disagree is the day her checklist shows four steps while her
streak counts three.

Held in four places, because one is not enough for something this load-bearing:

| Where | What it stops |
|---|---|
| `growth_routines_test.sql` #2 | Any `Step`, `EventType` or `Percent` column appearing on `Growth.Routine` |
| `tr_Routine_SubjectMustBeRoutine` | A routine pointing at an event subject — aimed at `hydration` it would complete on one glass of water |
| `growth_routines_test.sql` #16 | Any Growth procedure reaching the observation store, the day-counting function or the timeline |
| `RoutineIntegrationTests` | `RoutineToday` growing a mutable setter or a `Percent` property |

**Completion is derived, never stored.** No percentage column, no mark-complete
command, no completion endpoint. To finish a routine she logs its steps.

---

**Consumption goes through `Behaviour.fn_Read`**, the published interface, and
`Behaviour.fn_ReadSteps` for where she is up to today. The
assertion forbids recomputation and direct storage access, not reading — and
when Growth needed behaviour it forced that interface into existence rather than
merely blocking the work. `growth_goals_test.sql` assertion 18 holds the same
line from the other side: no Growth procedure may reference the observation
store, the day-counting function or the timeline.

Everything derives from `Timeline.Event`. No profile field, no assumed routine,
no default. Days are counted on `OccurredLocalDate`, so a woman in Karachi
logging water at 2am does not break her own streak by doing the thing she is
trying to keep doing.

**The honesty controls, which are the engine's whole credibility:**

| Rule | Why |
|---|---|
| A measure below `MinSpanDays` is **absent**, not zero | A zero streak and an unknown streak look identical on a screen and mean opposite things |
| Confidence is coverage of the span she has actually shown | 30 days of a 56-day measure is 54, not 100 |
| No probability is ever 0 or 100 | A woman who has done something daily for a month is not certain to do it tomorrow |
| Every observation carries confidence, span, supporting events, dates, reasoning, evidence and engine version | A recommendation built on one must show why; a change in the line must be tellable from a change in the definition |
| Nothing clinical, nothing causal | Asserted, like the knowledge graph's ban on causal verbs |

**Counting is not inferring.** `days_active` and `days_since_last` report from
day one; `streak_current` needs three, because calling one day a streak is
encouragement inflation. This distinction was found by a failing test, not
designed in.

---

## Current Feature

**Personal Growth Platform — goals and routines.** Both complete vertical
slices: schema, resolution functions, procedures, contracts, CQRS, repositories,
controllers, pipeline stages, integration tests, SQL assertions and portal
library screens.

## Current Epic / Slice / Track

| | |
|---|---|
| Epic | 1 — Intelligence Platform |
| Slice | Growth: goals + routines — **closed** |
| Track | A (backend) complete · B (portal) complete · C blocked · D ongoing |

---

## Completed Features

Verified from code, in commit order on `feature/backend-v2`:

| Feature | Commit |
|---|---|
| Database review + improvement plan | `be209e6` |
| 18 missing foreign-key indexes | `bf1731e` |
| Scheduled publish obeys the approval gate | `e2499db` |
| AI companion specs (system, prompts, pipeline) | `b7cb9bb` |
| AI safety ledger (`AI.SafetyEvent`) | `9ad55a6` |
| Deployment / CI-CD / backup / recovery plans | `365a1a2` |
| CI build gate restored | `91eeb96` |
| Final audit reports | `e05ea2c` |
| Life stages + role modes + profile procedures | `0fcba64` |
| Content targeting as data | `27342af` |
| Timeline event store | `41c8ea9` |
| Life domains + observational knowledge graph | `8b8189f` |
| Onboarding backend (`/api/v1/me`) | `2cf7f4b` |
| Adaptive dashboard engine | `a7fec6e` |
| Women's Life OS orchestration | `555b071` |
| Intelligence core (9 derived dimensions) | `e6ddf1f` |
| Pipeline refactor — 23 stages, zero-modification | `1d11215` |
| One rule engine (consolidated two matchers) | `b6613a2` |
| Decision inspector — SQL | `9de8ebc` |
| Decision inspector — API/CQRS/repository | `e83a2c1` |
| Inspector signal endpoint | `978c1b6` |
| Audit contract applied after every table exists | `3f6520a` |
| **Behaviour Intelligence — one model, six lenses** | `b769372` |
| Behaviour measure vocabulary for operators | `9a3c192` |
| Goals as desired outcomes, measured by behaviour | `66d63f9` |
| **Routines as a thin layer over Behaviour** | `0ec3f20` |

On `feature/portal-v2` (Maren-Frontend):

| Feature | Commit |
|---|---|
| Route splitting, strict TS, error boundaries | `aa1e731` |
| First portal tests (client + auth) | `87be8e0` |
| Onboarding configuration + adaptive preview | `89f7199` |
| Life profile Flutter architecture (unverified) | `e83471d` |
| Decision Inspector screen | `2480e78` |
| Behaviour configuration screen | `35567a6` |
| Goal library screen | `bfef851` |
| **Routine library screen** | `f905e5b` |

---

## Defects Found by Verification

### The audit contract was applied before most tables existed

**Severity: high. Found this session, fixed in `3f6520a`.**

A database built by following the documented deployment procedure once, in
order, on an empty server failed the platform's own audit contract: **19 tables
short by 147 columns and 19 filtered indexes.**

`08_AuditContract.sql` applies the contract with a cursor over `sys.tables`. It
runs ninth of thirty-seven, so it never sees anything created by scripts 30–47 —
the entire Women's Life OS. The exposed tables included `Timeline.Event` and
`Intelligence.UserStateSnapshot`, which hold what a woman logs and what the
platform infers from it. Those are the last two tables in the platform that
should be missing attribution and soft delete.

**Why it stayed hidden.** `AuditContractTests` had been green for weeks — but
every database it ran against had been re-applied more than once, and a second
pass over an already-built database picks the later tables up by accident. The
test was correct; the environment was quietly compensating. A first production
deployment would not have had that accident.

**The lesson, which generalises past this defect:** a green test on a database
that has been incrementally re-applied proves the schema *converges*, not that
the documented procedure *produces* it. Verification has to run against what one
ordered pass actually builds. This is the same class of error as the stale-binary
trap — the artefact under test was not the artefact the procedure produces.

**Fix:** the cursor moved into `dbo.usp_ApplyAuditContract`, called by `08` as
before and again by a final numbered script after every table exists. The
ordering requirement is carried by the number, not a comment — it has since been
renumbered 48 → 51 → **54** as Behaviour and Growth added tables, which is the
rule working. `tests/audit_contract_test.sql` (6 assertions) fails if it is
forgotten, and runs in CI as its own step.

### The verification harness silently dropped the last script

**Severity: medium. Found and fixed in `66d63f9`.**

The harness extracts the script list from `PLATFORM_RUNBOOK.md` so the docs
cannot drift from what is verified. It filtered tokens on `.sql$` — which does
not match the final entry, because that one carries the loop's trailing `;`.

So 41 scripts were verified as 40, silently, and the dropped one was
`54_AuditContract_Apply.sql`. The harness reported a clean full-order build
while never running the script that applies the audit contract to late tables:
the same class of silent truncation as the defect above, this time in the tool
built to catch it.

**Found by** a second pass showing script 08 adding 227 columns the first pass
should already have applied. **Fixed** by stripping the loop syntax before
tokenising, and by asserting the documented list count equals the scripts on
disk — a check that would have failed loudly rather than passing quietly.

---

## Architecture Decisions

Decisions that constrain future work. Reversing any of these needs a reason.

1. **Rules live in stored procedures**, not C#. Anything connecting to the
   database is subject to them.
2. **The platform decides; clients render.** Sorting, priority and eligibility
   happen once, server-side. A client that re-sorted would be disagreeing with
   the platform rather than presenting it.
3. **Adding a pipeline stage is registration only.** The intelligence context
   is an open keyed store; no existing stage or shared class changes.
4. **Inputs and outputs are observed, not declared.** The context records what
   a stage actually read and wrote, so a stage cannot misreport itself.
5. **Confidence is computed from coverage, never asserted.** No data means no
   confidence means `unknown` — never a baseline dressed as an answer.
6. **The knowledge graph is observational.** No causal verb exists in the
   relation vocabulary and a test fails if one appears.
7. **One rule engine.** `Rules.fn_Match` is the only matcher. Cost accepted:
   no foreign key to targets, replaced by an asserted invariant and cleanup
   triggers.
8. **Goals are desired outcomes, measured only by Behaviour.** Progress is the distance between what was observed and what the goal asks for. Never self-reported, never awarded on silence, and achievement is forward-only.
9. **Behaviour Intelligence is the only source of behavioural truth.** No engine computes a habit, streak, consistency figure or probability. Asserted in SQL against every schema.
10. **The inspector simulates, never impersonates.** No inspector procedure may
   reference a user id, the timeline or a state snapshot; asserted in SQL.
11. **Nineteen user categories are two dimensions**, life stage × role mode,
   not nineteen experiences.
12. **Timeline clusters on `(UserId, OccurredUtc)`**, not on a random GUID.

---

## Known Blockers

| Blocker | Type | Evidence |
|---|---|---|
| Flutter SDK absent | Environment | `flutter --version` → command not found |
| Docker absent | Environment | `docker --version` → command not found |
| CI never executed on a runner | Environment | No runner available; verified by equivalent commands only |
| PD-1: networking in `mobile/` | Legal | About screen claims no network code; part of Play Data Safety declaration |
| Multi-tenancy undecided | Product | No tenant dimension on any table. **Open 7 sessions.** Blocks the Health procedure layer |
| No deployment / backups / monitoring | Infrastructure | `recovery_model = SIMPLE`, zero `backupset` rows, no config in any repo |

---

## Technical Debt

| Item | Impact |
|---|---|
| Container `HEALTHCHECK` calls an unhandled `--healthcheck` arg | Would restart-loop a real container deploy. Masked in dev by a compose override |
| 42 `IX_*_NotDeleted` indexes are non-selective | Write cost on every insert, no read benefit |
| ContentEditor destroys unsaved typing on background refetch | Operator loses work with no error |
| ContentEditor can send `If-Match: null` | Silent last-write-wins on a CMS |
| Settings blanks a secret when editing its description | Config reaching every device is erased |
| RolesMatrix unusable by screen reader | Unlabelled checkboxes, no row headers |
| RolesMatrix: saving one role discards staged edits to others | Silent data loss |
| FeatureFlags slider frozen while dragging; 100% cannot be reduced | Control unusable at top of range |
| `usp_User_Erase` referenced in a comment, does not exist | GDPR erasure impossible |
| README/CLAUDE.md still open with "pregnancy and maternal wellness" | Stale framing vs the platform's actual scope |

---

## Open Product Decisions

1. **Multi-tenancy** — tenant-per-row now, consumer-only declared in writing, or
   tenancy-neutral behind a seam. Recommendation: decide before the Health
   procedure layer, because retrofitting rewrites every procedure.
2. **Consumer or public-health product** — code says US/UK consumer Play Store
   app; the account context implies Punjab government. Unanswered.
3. **PD-1 sync posture** — opt-in, mandatory, or none.

---

## Versions

| Layer | Version / state |
|---|---|
| Database | 43 numbered scripts (`01`–`57`), 17 assertion suites |
| API | v1 · `/api/v1/me`, `/api/v1/admin/*` |
| Portal | React 19 / MUI 9 / Vite 8, 75 tests |
| Flutter | Architecture only, **never compiled** |
| AI | Specs + safety ledger. **No model integration** |
| Infrastructure | None deployed |

---

## Verification Summary

Executed on this machine, not claimed:

| Check | Result |
|---|---|
| Database created empty and applied **once, in order**, 43 scripts (list read from the runbook, count asserted against disk) | PASS |
| Idempotency (second apply adds 0 columns, 0 indexes) | PASS |
| SQL assertion suites | **17 suites, 221 assertions, 0 failures** |
| Clean Release build `-warnaserror` (never incremental) | 0 errors, 0 warnings |
| Integration tests | **203 passed, exit 0** |
| Portal `tsc -b --force` | exit 0 |
| Portal tests | **75 passed, exit 0** |
| Portal production build | succeeds; inspector is a 2.69 kB gzip chunk |
| Mutation check — inspector inert-signal assertion | fails as intended (5 inert) |
| Mutation check — portal suppression split | fails 2 tests as intended |

The first row is deliberately worded. It used to read "fresh database", which
was true of a database that had been re-applied, and that wording is exactly
what hid `3f6520a` for weeks. It now means what it says: `CREATE DATABASE`,
then one ordered pass.

**Not verified:** Flutter (no SDK), container image (no Docker), CI on a runner,
portal screens against a live API.

---

## Current Maturity: **43 / 100**

Backend intelligence is strong and genuinely explainable. Deployment, backups
and monitoring remain at zero, and the mobile client — the actual product — has
never been executed. Application quality does not compensate for those.

---

## Git

| | |
|---|---|
| Backend branch | `feature/backend-v2` (pushed) |
| Frontend branch | `feature/portal-v2` (pushed) |
| `main` | Untouched on both repositories |

---

## Next Feature

**Split `fn_Observe` first. Then Recommendation Assembly, Coach, Prediction.**

**The prerequisite is now blocking three engines, not one.** The Decision
Inspector cannot render behaviour, goals or routines. It is account-free by
construction — no inspector procedure may reference a user id or the timeline,
asserted in SQL — and all three need a woman's timeline. Simulating any of them
as things stand would mean a second implementation of `fn_Observe`, which is the
one thing this architecture forbids.

The fix: split `fn_Observe` so the measure arithmetic consumes a day set rather
than calling `fn_SubjectDays` itself. The real path and a simulated one then
feed the same arithmetic and there is still one definition. Do this **before**
the engines below, not after — each one added makes the inspector gap wider.

**Then recommendation assembly.** Every input now exists: behaviour, knowledge,
signals, rules, life stage, role modes, goals, routines, timeline and state. A
recommendation is **assembled** from them and decides nothing itself. Each one
returns confidence, reasoning, evidence, contributing engines, supporting
observations, priority, expected benefit, expected effort, expiry and version.

**Then coach**, which explains why a recommendation exists and generates no
advice of its own. **Then prediction**, behavioural only: routine completion,
goal completion, habit continuation, engagement, drop-off, streak survival,
reminder timing. Never clinical, never deterministic.

**Then the planner and reviews** — daily focus, weekly and monthly review — all
assembled from what the engines already produce.

**The constraint that governs all of them:** each is orchestration over
`IntelligenceKeys.Behaviour`, `.Goals` and `.Routines`. None computes a habit,
streak, consistency figure or probability. Routines proved this works — the
entire layer is configuration plus a planning view, with no new behavioural
computation anywhere in it.
