# EXECUTION LEDGER

**The single source of truth for resuming work.** Every session reads this
first and updates it last. Never depend on conversation history.

Machine-readable companion: [`execution-state.json`](execution-state.json).

**Last updated:** 2026-07-29 · backend `84f747b` · portal `adbd99f`

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

**Observability: correlation.** `Audit.AuditLog.CorrelationId` had existed
since `05_Content_Notifications_Audit.sql`, was selected back by
`usp_Audit_Search`, and was **written by nothing** — 157 audit rows, 0
correlated. One request writes audit rows, a security event on its own
connection and potentially a safety event, and nothing said those rows were one
action.

**Fixed without editing a single existing procedure.** The value is established
once per connection in `SESSION_CONTEXT` and the columns default from it, so an
`INSERT` that omits the column — which is exactly what all 33 existing write
sites do — picks it up. The obvious alternative, a `@CorrelationId` parameter
threaded through every command procedure, costs more with every engine added;
this costs nothing, and a new engine gets correlation by writing an audit row
the ordinary way.

Honesty holds: no correlation means `NULL`, never a manufactured id. An
uncorrelated row is honest; an invented one would be indistinguishable from a
real trail and would therefore be believed.

### Previous slice — Operations: deployment and recovery

The first slice in this repository that is not an engine, taken deliberately
ahead of the Planner because the engine layer was far ahead of everything
holding it up.

Two questions the platform could not answer about itself, and now can.

**"Is this database current, and did anything fail halfway?"**
`Ops.DeploymentJournal` records every script applied, with its SHA-256, its
duration and its outcome. `ops/db/deploy.sh` reads the order from the runbook
rather than a fifth hand-maintained copy, asserts the documented count against
disk, and stops at the first failure with the journal showing exactly where.

**"Has a restore ever actually been performed?"** Until this slice, no.
`ops/db/backup.sh` takes full and log backups with `CHECKSUM` and verifies them
by reading them back; `ops/db/restore-drill.sh` restores the chain to a scratch
database, runs `DBCC CHECKDB` and every assertion suite **against the restored
copy**, records the result in `Ops.RestoreDrill` and drops the scratch. A drill
that ran no checks cannot be recorded as passed — a `CHECK` constraint refuses
it, because "RESTORE returned 0" is not evidence of anything.

Point-in-time recovery is real and demonstrated: a write made after a captured
timestamp is gone after `STOPAT`, and the write before it survives.

## Current Epic / Slice / Track

| | |
|---|---|
| Epic | 2 — Operations |
| Slice | Observability: correlation — **closed** |
| Track | A (backend) complete · B (portal) not applicable · C blocked · D ongoing |

---

## Completed Features

Verified from code, in commit order. Commits up to `aee4d60` were made on
`feature/backend-v2`; work continues on `feature/backend-v3`, branched from that
commit rather than rebased, so every hash below is reachable from both:

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
| Routines as a thin layer over Behaviour | `0ec3f20` |
| fn_Observe split — simulation shares one implementation | `26854dc` |
| Recommendation Platform | `2061132` |
| **Coach Platform** | `84a2a3f` |
| **Prediction Platform** | `5a0e8e6` |
| **Operations — deployment journal, backups, rehearsed restore** | `2fe17e7` |
| **Observability — correlation, with no procedure edited** | `84f747b` |

On Maren-Frontend — `feature/portal-v2` up to `857b55c`, continuing on
`feature/portal-v3` from the same commit:

| Feature | Commit |
|---|---|
| Route splitting, strict TS, error boundaries | `aa1e731` |
| First portal tests (client + auth) | `87be8e0` |
| Onboarding configuration + adaptive preview | `89f7199` |
| Life profile Flutter architecture (unverified) | `e83471d` |
| Decision Inspector screen | `2480e78` |
| Behaviour configuration screen | `35567a6` |
| Goal library screen | `bfef851` |
| Routine library screen | `f905e5b` |
| Recommendation library + simulator | `0f77a14` |
| **Coach library + simulator** | `857b55c` |
| **Prediction library + simulator** | `adbd99f` |

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
renumbered 48 → 51 → 54 → 65 → **69** as Behaviour, Growth, Recommendation,
Coach and Prediction added tables, which is the rule working.
`tests/audit_contract_test.sql` (6 assertions) fails if it is forgotten, and
runs in CI as its own step. It was confirmed to still fail-then-pass across the
Prediction renumber: 3 non-compliant tables before, 24 columns and 3 indexes
added after.

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

### Two Prediction foreign keys shipped without a supporting index

**Severity: medium. Found and fixed this session, before commit.**

`Predict.Predicted (SubjectKey)` and `Predict.PredictionType (HorizonCode)` were
created with foreign keys and no index leading on the key column.
`Predicted` grows once per woman per prediction per day, so the parent-side
delete and every join to `Behaviour.Subject` would have been a scan on the one
table here with real cardinality.

**Found by** `index_coverage_test.sql` on the clean-room run — not by review,
and not by any of the twenty prediction assertions written specifically for this
feature. Worth recording: a feature's own suite tests what its author was
thinking about, and the platform-wide suites are what catch what they were not.

**Fixed** as guarded `IF NOT EXISTS ... CREATE INDEX` statements outside the
`CREATE TABLE` block rather than inside it. Inside, the index would never reach
a database that already had the table, so re-applying would not converge — the
same shape as the audit contract defect above, which is why the convention set
by `30_Indexes_ForeignKeys.sql` is the one to follow. Verified both ways: it
converges on the database that already had the tables, and a database built from
scratch passes all 87 foreign-key checks.

### A justification that did not survive its own mutation test

**Severity: low, and recorded because the reasoning was wrong rather than the
code.**

`SqlConnectionFactory` clears the session correlation to `NULL` when there is
nothing to set, rather than skipping the call. That was written and documented
as the barrier preventing a pooled connection from carrying one request's
correlation id into another request's audit rows.

Mutation-testing it disproved the justification: deleting the clear entirely
leaves the test passing. `sp_reset_connection`, which the pool issues when
handing a connection on, already discards session context. The leak the comment
described cannot occur.

The behaviour stays — `Pooling=false`, a driver change, or a connection opened
outside the factory would each remove that reset, and the failure mode is silent
misattribution in the record that gets believed. But it is insurance against an
assumption held elsewhere, not the barrier, and both the code comment and the
test now say so. **The mutation proof that was expected here does not exist, and
claiming one would have been the exact failure this ledger exists to prevent.**

### The restore-verification gate would have passed a catastrophic restore

**Severity: high. Found and fixed 2026-07-29.**

`RECOVERY_PLAN.md` §6 told an on-call engineer to verify a restored database by
checking `sys.tables = 45` and `sys.procedures = 47`, then running five named
assertion suites.

By then the schema was **84 tables and 102 procedures**, and twenty suites
existed. The thresholds had gone stale silently, because nothing executes a
number written in a document.

The consequence is worse than "no check". A backup taken before ten feature
schemas existed matches 45/47 **exactly** — so the gate would have reported a
clean verification of a database missing Behaviour, Growth, Recommend, Coach,
Predict, Timeline, Knowledge, Dashboard, Intelligence and Rules, to somebody
deciding under pressure whether to return it to service.

Demonstrated rather than argued: a database on the verification instance still
sits at exactly 45/47. Backed up and put through the new drill, it fails **15 of
21** checks. The old gate passes it.

The commands were also missing `-S`, so they could not connect to the instance
the rest of the documentation uses. They had never been run as written.

**Fix:** §6 is now `./ops/db/restore-drill.sh`, which enumerates suites from
disk instead of from a list and checks behaviour instead of shape. Assertion
suites cannot rot quietly the way a number can, because they gate CI.

### The documented deployment loop could not detect a failed script

**Severity: high. Found and fixed 2026-07-29.**

The apply loop published in `README.md`, `CLAUDE.md`, `PLATFORM_RUNBOOK.md` and
both CI jobs ended `|| break` — and omitted `sqlcmd -b`. Without `-b`, `sqlcmd`
exits 0 on a T-SQL error, so `|| break` was dead code in every copy. A failure
at script 34 did not stop anything: the loop ran the remaining scripts against a
broken database and finished looking exactly like success.

This is the same class of defect as the audit-contract ordering bug and the
twice-repeated silently-green CI step — a guard that cannot fire, which is
indistinguishable from a guard that never needed to.

**Fix:** `-b` added in all four documented copies, `ops/db/deploy.sh` written to
supersede them, and `ci_workflow_test.sh` now fails if any schema-application
line in CI omits `-b`.

### The ledger's own status sections had gone stale

**Severity: low. Found and fixed this session.**

`Current Maturity` read 43 while `execution-state.json` read 60, and
`Next Feature` still described splitting `fn_Observe` — work completed two
features earlier. The header of `69_AuditContract_Apply.sql` likewise still said
`48_` after two renumbers, and `CLAUDE.md` said the audit contract script was
`54` when it was `65`.

None of these broke anything, which is the point: the continuation protocol
recovers state from the repository rather than from conversation, so a stale
"next feature" sends the next session to work that is already done. The prose
sections drift precisely because nothing executes them. The machine-readable
state file, which is updated in the same commit as the work, stayed correct
throughout.

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
| ~~Container `HEALTHCHECK` calls an unhandled `--healthcheck` arg~~ | **Fixed 2026-07-29.** The wording here was also wrong: plain Docker Engine never restarts a container for being unhealthy — it only marks it so. The restart loop needs an orchestrator (Swarm, Kubernetes) or a `restart` policy reacting to the probe. Under plain `docker run` the consequence was quieter and arguably worse: a container reporting unhealthy forever while serving correctly, and a load balancer refusing to route to it |
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
| Database | 56 numbered scripts (`01`–`74`), 22 assertion suites |
| API | v1 · `/api/v1/me`, `/api/v1/admin/*` |
| Portal | React 19 / MUI 9 / Vite 8, 105 tests |
| Operations | `ops/db/{deploy,backup,restore-drill}.sh`; journals in `Ops` |
| Flutter | Architecture only, **never compiled** |
| AI | Specs + safety ledger. **No model integration** |
| Infrastructure | None deployed |

---

## Verification Summary

Executed on this machine, not claimed:

| Check | Result |
|---|---|
| Database created empty and applied **once, in order**, 56 scripts, via `ops/db/deploy.sh` (order read from the runbook, count asserted against disk) | PASS |
| Idempotency (second apply adds 0 columns, 0 indexes — 2823 and 487 both passes) | PASS |
| **Backup taken and verified** (`CHECKSUM` + `RESTORE VERIFYONLY`, full and log) | PASS |
| **Restore rehearsed** — DBCC CHECKDB + 21 suites against the restored copy, 22/22, **1034 ms** | PASS |
| **Point-in-time restore** discards a post-`STOPAT` write and keeps the earlier one | PASS |
| **Container health probe** — exit 0 alive, exit 1 dead, exit 0 on a cold first request | PASS |
| SQL assertion suites | **22 suites, 303 assertions, 0 failures** |
| Clean Release build `-warnaserror` (never incremental) | 0 errors, 0 warnings |
| Integration tests | **245 passed, exit 0** |
| Portal `tsc -b --force` | exit 0 |
| Portal tests | **105 passed, exit 0** |
| Portal production build | succeeds |
| Mutation check — restore drill | drilling a genuinely incomplete database (the one the old 45/47 gate passes) failed 15 of 21 checks |
| Mutation check — deployment journal | a deliberately broken script 67 stopped the run at 51/55 and `usp_Deployment_Status` named it |
| Mutation check — ops append-only guard | a procedure updating `Ops.RestoreDrill` failed assertion 10 |
| Mutation check — CI guard | it caught `ops_test.sql` missing from CI and itself missing from CI, before those were added |
| Mutation check — prediction never recomputes | `+5` on the percent and dropping the confidence floor failed 3 SQL assertions and 3 integration tests |
| Mutation check — prediction never-recomputes guard | a `Predict` module doing recency-decay arithmetic failed assertion 10 |
| Mutation check — prediction structural guards | a non-probability source, a framing without `{support}`, a framing without `{window}`, a stored row with no support and one with no evidence were each refused; a well-formed row was still accepted |
| Mutation check — portal traceability | hiding the source measure failed 1 test |
| Mutation check — CI guard | removing the prediction step failed it with `1 missing prediction_test.sql` |

The first row is deliberately worded. It used to read "fresh database", which
was true of a database that had been re-applied, and that wording is exactly
what hid `3f6520a` for weeks. It now means what it says: `CREATE DATABASE`,
then one ordered pass.

**Not verified:** Flutter (no SDK), container image (no Docker), CI on a runner,
portal screens against a live API.

---

## Current Maturity: **67 / 100**

Up five from 62, and this is the first rise in a while that is not about
application quality.

The platform can now be **deployed with a record of what was deployed**, can be
**backed up**, and — the one that had never been true — can be **restored, with
that restore rehearsed, verified against its own assertions, and timed**. The
measured RTO for a database of this size is about a second; the number matters
less than the fact that it is now a measurement rather than a hope.

What is still zero, and what caps this number: **nothing is deployed anywhere**.
There is no environment, no IaC, no image built by CI, no monitoring, no
alerting, no log aggregation and no on-call. The mobile client — the actual
product — has still never been executed. Backups of a database nobody is using
protect nothing yet; they mean the capability exists before it is needed, which
is the only useful time to build it.

Honest framing: this slice moved the platform from "would lose everything" to
"has a tested way not to". That is a real step and a small one.

---

## Git

| | |
|---|---|
| Backend branch | `feature/backend-v3` (pushed, tracking) |
| Frontend branch | `feature/portal-v3` (pushed, tracking) |
| `main` | Untouched on both repositories |
| Previous branches | `feature/backend-v2` @ `aee4d60`, `feature/portal-v2` @ `857b55c` — left on the remote, not deleted |

---

## Next Feature

**Continue operations: get something deployed, then observability.**

The previous entry named the Planner and attached a caveat saying deployment
mattered more. Acting on that caveat is what produced this slice, and the same
reasoning still applies — the engine layer remains far ahead of what holds it
up.

In order:

1. **Infrastructure as code and a deployed environment.** Everything the ops
   scripts do assumes a database that exists somewhere. There is still no
   environment, no IaC, and CI never builds the image, so the container fixes in
   this slice are verified only by exit code on a developer machine. This is the
   single largest gap; it is also the one that cannot be closed here, because
   there is no Docker and no runner on this workstation.
2. **Observability.** `Audit.AuditLog.CorrelationId` is declared, read back, and
   **written by nothing** — all 33 write sites omit it and no procedure accepts
   one. There is no request correlation middleware, no structured logging sink,
   no metrics. Logs are unstructured console text that dies with the process.
   Deliberately not attempted in this slice: threading a correlation id means
   changing every command procedure's signature, which is its own slice and
   should not ride along inside a backup change.
3. **Then the Planner**, which is still the right next engine.

### Also found and not fixed here

Recorded so they are not rediscovered: the CI `security` job fails on every run
(`GHSA-v5pm-xwqc-g5wc`; the `NuGetAuditSuppress` is restore-time and does not
suppress it); the committed-secret scan regex cannot match a key in any
`appsettings*.json`; `UseForwardedHeaders` is never called, so behind a proxy
every anonymous caller shares one rate-limit partition; `/health/ready` binds
the exception but never logs it, so a 503 carries no diagnostic anywhere; and no
test covers either health endpoint.

### The Planner, when it comes

Everything it needs now exists. Behaviour says how she lives, Growth what she is
working towards, Recommendation what to suggest, Coach how to say it, Prediction
what is likely. A planner is the arrangement of those into a day and a week: it
selects, orders and schedules, and it originates nothing.

**Scope:** a plan schema with slots as data rather than a hard-coded day shape;
`fn_PlanFrom` consuming what the engines published — the fifth engine on the
simulate-from-a-set split; a `planResolution` stage; contracts, CQRS,
repository, controller; assertions including a never-originates one and a
never-clinical one; inspector simulation; portal library.

**The constraint that governs it,** as for every engine before it: orchestration
over `IntelligenceKeys.Behaviour`, `.Goals`, `.Routines`, `.Recommendations`,
`.CoachMessages` and `.Predictions`. It computes no habit, streak, consistency
figure or probability, and writes no sentence a coach did not already write.

### Read this before starting it

**The engine layer is now well ahead of everything around it, and the gap is
the risk.** Fifteen engines are built, explainable and tested; nothing is
deployed anywhere, there are no backups, there is no monitoring, and the mobile
client has never been executed. Another engine adds to the side of the ledger
that is already strong.

Two things are worth more than the planner, and neither is engine work:

1. **Get something deployed with backups and a rehearsed restore.** The database
   is in `SIMPLE` recovery with zero rows in `backupset`. Point-in-time recovery
   is impossible by definition, not by omission.
2. **Answer PD-1 and the tenancy question.** The Health domain still has nine
   tables and zero procedures, so the tenancy decision is still a design choice
   rather than a rewrite. It stops being cheap the moment that layer is written.

The planner is the right *next engine*. Whether the next engine is the right
next thing is a question for a person.
