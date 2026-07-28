# EXECUTION LEDGER

**The single source of truth for resuming work.** Every session reads this
first and updates it last. Never depend on conversation history.

Machine-readable companion: [`execution-state.json`](execution-state.json).

**Last updated:** 2026-07-27 · commit `9de8ebc`+ (see below)

---

## Current Feature

**Decision Inspector — API + Application + Repository + Controller** (Track A of
the portal slice). Complete and verified. The React screen is not built.

## Current Epic / Slice / Track

| | |
|---|---|
| Epic | 1 — Intelligence Platform |
| Slice | Decision Inspector |
| Track | A (backend) complete · **B (portal) next** · C blocked · D ongoing |

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
| **Decision inspector — API/CQRS/repository** | this commit |

On `feature/portal-v2` (Maren-Frontend):

| Feature | Commit |
|---|---|
| Route splitting, strict TS, error boundaries | `aa1e731` |
| First portal tests (client + auth) | `87be8e0` |
| Onboarding configuration + adaptive preview | `89f7199` |
| Life profile Flutter architecture (unverified) | `e83471d` |

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
8. **The inspector simulates, never impersonates.** No inspector procedure may
   reference a user id, the timeline or a state snapshot; asserted in SQL.
9. **Nineteen user categories are two dimensions**, life stage × role mode,
   not nineteen experiences.
10. **Timeline clusters on `(UserId, OccurredUtc)`**, not on a random GUID.

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
| Database | 36 numbered scripts (`01`–`47`), 13 assertion suites |
| API | v1 · `/api/v1/me`, `/api/v1/admin/*` |
| Portal | React 19 / MUI 9 / Vite 8, 35 tests |
| Flutter | Architecture only, **never compiled** |
| AI | Specs + safety ledger. **No model integration** |
| Infrastructure | None deployed |

---

## Verification Summary

Executed on this machine, not claimed:

| Check | Result |
|---|---|
| Fresh database, 36 scripts | PASS |
| Idempotency (second apply) | PASS |
| SQL assertion suites | **13 suites, 157 assertions, 0 failures** |
| Clean Release build `-warnaserror` | 0 errors |
| Integration tests | **161 passed, exit 0** |
| Inspector endpoints unauthenticated | `401` |
| OpenAPI documents both inspector routes | yes |
| Portal build + tests | strict build, 35 tests |

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

**Decision Inspector — Track B (portal screen).**

**Why selected:** the backend now exposes simulation and per-card explanation,
and nothing renders either. The pipeline publishes confidence factors, observed
inputs and outputs, evidence, warnings, diagnostics and version across 23
stages; an explainable platform nobody can inspect is explainable only in
theory. This is the smallest remaining step that turns explainability from a
property of the code into a tool an operator can use.

**Scope:** `src/api/inspector.ts`; a screen with stage and role pickers, signal
toggles, resulting cards ordered by priority with reason and evidence, and a
distinct **suppressed** section answering "why is my card missing"; per-card
explanation showing failing rules alongside passing ones. Accessibility to the
standard set in `OnboardingConfig` — labelled controls, an `h1`, a live region,
meaning carried in text rather than colour. Vitest coverage on client and screen.
