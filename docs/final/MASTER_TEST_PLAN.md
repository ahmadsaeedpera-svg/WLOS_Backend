# MASTER TEST PLAN — Maren Platform

**Date:** 2026-07-27 · **Role:** QA Director
**Scope:** Maren-Backend · Maren-Frontend (Flutter `mobile/`, React `web-admin/`)

---

## 1. Verified baseline

Executed, not quoted from documentation.

| Layer | Tests | Status | Verified how |
|---|---:|---|---|
| **Backend integration** | **127** | ✅ Pass, exit 0 | `dotnet test -c Release --no-build` against real SQL Server 2025 |
| **SQL assertion suites** | **52** | ✅ All pass | 5 suites: cms_workflow 17, access 19, index_coverage 2, scheduled_publish 6, ai_safety 8 |
| **Portal (web-admin)** | **0** | 🔴 **No runner, no tests, no script** | `package.json` has no test script; no test files exist |
| **Flutter (mobile)** | 462 blocks / 47 files | ⚠️ **NOT VERIFIED** | Flutter SDK is not installed on this machine. Counted statically; **never executed here** |
| **E2E (any layer)** | **0** | 🔴 None exist | No Playwright/Cypress/Selenium anywhere |
| **Accessibility** | **0** | 🔴 None | No axe, no a11y assertions |
| **Performance / load** | **0** | 🔴 None | No k6, NBomber, JMeter |
| **Security** | partial | 🟡 | CI runs `dotnet list package --vulnerable` + a secret grep. No authz test suite, no fuzzing |

**Honest summary:** the backend and database are genuinely well tested — real database, no mocks, rules verified where they are enforced. **Everything else is untested or unverified.** The portal, which can publish content to every user of the app, has zero automated tests.

---

## 2. Risk-ranked gaps

Ranked by *consequence of the bug reaching production*, not by ease of testing.

| # | Gap | Consequence | Priority |
|---|---|---|---|
| **1** | **Portal has no tests** | The portal publishes health content and grants permissions. The page review found defects that destroy an operator's unsaved work and can silently blank a secret. Nothing would catch a regression | 🔴 P0 |
| **2** | **Flutter suite never executed in CI** | 462 assertions that may or may not pass. An unrun test is not a test | 🔴 P0 |
| **3** | **No E2E across the API boundary** | Backend and clients are tested in isolation; nothing proves they agree. A DTO change breaks the app silently | 🟠 P1 |
| **4** | **No authorization test matrix** | Permission checks are the security boundary. Tested for some paths, not systematically per endpoint × role | 🟠 P1 |
| **5** | **No accessibility tests** | Portal has unlabelled checkboxes and switches; the roles matrix is unusable by screen reader | 🟠 P1 |
| **6** | **No performance baseline** | Known scans on hot paths. No way to detect a regression | 🟡 P2 |
| **7** | **No contract tests** | `Maren.Contracts` changes are breaking changes for two clients with nothing enforcing it | 🟡 P2 |

---

## 3. Test strategy per layer

### 3.1 Backend — *strong, extend rather than rebuild*

Current approach is correct and should be preserved: **integration tests against a real database, no repository mocks**, deliberately. Every rule worth testing lives in a stored procedure; a suite mocking `IContentRepository` verifies the mocks and cannot tell you whether an editor can publish something nobody approved.

**Add:**
- **Authorization matrix** — every endpoint × every role, asserting 200/403. Currently ad-hoc.
- **Contract snapshot tests** — serialize every DTO in `Maren.Contracts`, compare against a committed snapshot. A change forces a deliberate update and a note to the frontend repo.
- **Failure-path coverage** — deadlock, timeout, conflict mapping through `SqlErrorMapper`.
- **Rate-limit test** — 300/min is a security control and is untested.

### 3.2 Database — *strong, keep growing*

The SQL assertion suites test rules where they are enforced, which is the right place. Five suites, 52 assertions, all in CI.

**Add:** the missing `audit_contract_test.sql` (referenced in `08_AuditContract.sql` but does not exist — the contract is currently unpoliced), and a data-retention/growth assertion once retention procedures exist.

### 3.3 Portal — *build from zero*

**Runner:** Vitest + React Testing Library + jsdom. Vitest because the project is already Vite; a second toolchain is a tax nobody pays willingly.

Priority order — highest-risk logic first, not easiest:

1. **`api/client.ts`** — the single chokepoint for every request. Envelope parsing, 401 token clearing, `ApiError` shaping, `If-Match`, non-JSON responses. Pure logic, high leverage.
2. **`auth/AuthContext.tsx`** — unverified JWT claim decoding, `can()`, sign-in/out. A bug here mis-draws every permission gate.
3. **`ErrorBoundary`** — catches and resets. Untested error handling is a contradiction.
4. **ContentEditor** — the dirty-draft guard, `If-Match` presence, conflict dialog. Where an operator loses real work.
5. **RolesMatrix** — the "saving one role wipes another's edits" defect.
6. **Accessibility** — axe on every page; assert zero violations of the rules that matter (labels, roles, headings).

### 3.4 Flutter — *make it real*

The suite exists and is substantial. It is **not verified**, which currently makes it worth less than it should be.

1. **Run it in CI** (`flutter analyze` + `flutter test`). Until this happens, the 462 number is a claim.
2. Then measure coverage and fill gaps — priority on the compliance guard tests (`test/guards/`), which enforce the "describe, never prescribe" rule that the product's regulatory position depends on.

### 3.5 E2E — *thin and few*

E2E tests are expensive and flaky; the value is in proving the layers agree, not in re-testing logic.

**Playwright, ~6 journeys only:**
sign in → search content → edit and save → conflict on stale save → approve then publish → grant a role → view audit entry.

Run against a real API and a real database, in CI, on a schedule rather than every PR if wall time demands it.

### 3.6 Security

- Authorization matrix (§3.1) — the main one.
- Negative auth: expired token, revoked session (~30s stamp), tampered JWT, missing token.
- Input: oversized payloads, injection strings through search fields (procedures use no dynamic SQL, so this asserts a property already held).
- Dependency scanning already in CI; add Dependabot.

### 3.7 Performance

Not load testing for its own sake — **baselines that detect regression**:
- Content search p95 under a realistic library size
- Bootstrap endpoint (highest-volume authenticated path)
- Client content delta on first sync (unbounded today)

---

## 4. Coverage targets

Deliberately not "80% everywhere" — a coverage number is a proxy, and chasing it on generated code wastes effort.

| Area | Target | Rationale |
|---|---:|---|
| Backend handlers | 90% | Business orchestration |
| Backend domain rules | 95% | Small, pure, high consequence |
| Stored procedure rules | 100% of *rules* | Assertion suites, not line coverage |
| Portal API layer | 90% | Single chokepoint, pure logic |
| Portal components | 60% | Diminishing returns beyond critical paths |
| Flutter domain/data | 85% | Offline correctness |
| E2E journeys | 6 | Cross-boundary proof only |

---

## 5. Definition of done for a suite

A suite is complete only when all of these hold:

1. It **fails before** the fix and **passes after** — a test that never failed proves nothing.
2. It runs in **CI**, not only locally.
3. It is **deterministic** — no sleeps, no ordering dependence, re-runnable.
4. Its **exit code** is checked, not its printed summary. *(A green summary line is not a green step — `dotnet test` printed "Passed! 127" while exiting 1.)*
5. Failure output says **what broke and where**.

---

## 6. Execution order

| # | Suite | Why this order |
|---|---|---|
| **1** | **Portal: API client + auth + ErrorBoundary** | Zero → something, on the highest-consequence untested code. Verifiable here |
| **2** | Portal: critical components (ContentEditor, RolesMatrix) | Where the known work-destroying defects live |
| **3** | Portal: accessibility (axe) | Known violations, cheap to assert |
| **4** | Flutter in CI | Converts 462 claimed into 462 verified |
| **5** | Backend authorization matrix | Systematic security boundary coverage |
| **6** | Contract snapshot tests | Protects two clients |
| **7** | E2E journeys | Needs a running stack |
| **8** | Performance baselines | Needs a deployed environment |

Suites 1–3 need nothing but this repository. Suite 4 needs the Flutter SDK. Suites 7–8 need a deployed environment, so they are last by necessity rather than by preference.
