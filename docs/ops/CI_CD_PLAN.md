# CI_CD_PLAN

**Companion to:** `DEPLOYMENT_PLAN.md`

---

## 1. Current state

**One workflow exists:** `Maren-Backend/.github/workflows/ci.yml`. **It is red.**

What it does well — and it is genuinely good for a project this young:
- Spins a real SQL Server 2022 service container; integration tests run against real procedures, not mocks
- Applies all schema scripts, then **applies them a second time to prove idempotency**
- Runs five SQL assertion suites
- `dotnet build -warnaserror`
- A security job: `dotnet list package --vulnerable` (fails the build), `--deprecated` (advisory), plus a committed-secret grep
- Concurrency group cancels superseded runs

What is missing:
- **It is failing.** 5 × `CA1310` in `ContentDeltaTests.cs` under `-warnaserror`
- **No CD.** Nothing builds an image, tags it, pushes it, or deploys it
- **No frontend workflow at all** — `Maren-Frontend/.github/` has templates but no `workflows/`
- No dependency update automation (Dependabot/Renovate)
- No code coverage reporting
- No branch protection requiring the workflow

---

## 2. Why red CI is the first thing to fix

A pipeline that always fails teaches the team to ignore it, and then it protects nothing. Every commit on this branch — the foreign-key indexes, the approval-gate fix, the AI safety ledger — is currently unvalidated by CI, despite each being verified locally. Fixing five one-line lint errors restores the gate for all of them.

The errors are real, not noise: `string.StartsWith(string)` uses the current culture, so the same test can pass in one locale and fail in another. On a CI runner in a different region that is a genuine flake source. The fix is `StringComparison.Ordinal`.

---

## 3. Target pipeline

```
┌── on PR ───────────────────────────────────────────────┐
│ backend:  build -warnaserror → schema ×2 → 5 SQL suites│
│           → 127 integration tests → vuln + secret scan │
│ portal:   tsc -b → oxlint → vite build → bundle budget │
│ mobile:   flutter analyze → flutter test               │
└────────────────────────────────────────────────────────┘
                          │ all green
                          ▼
┌── on merge to main ────────────────────────────────────┐
│ build image → tag :sha and :main → push GHCR           │
│ deploy staging → smoke test /health/ready              │
└────────────────────────────────────────────────────────┘
                          │ manual approval
                          ▼
┌── production ──────────────────────────────────────────┐
│ deploy → smoke → watch error rate → rollback on breach │
└────────────────────────────────────────────────────────┘
```

---

## 4. Workflows to add

### 4.1 `frontend-ci.yml` (Maren-Frontend) — **highest missing value**

Two independent jobs, path-filtered so a Flutter change does not run a Node build:

```yaml
portal:   npm ci → tsc -b → oxlint → vite build → assert initial bundle < 200 kB gzip
mobile:   flutter pub get → flutter analyze (clean) → flutter test
```

The bundle budget is worth encoding. The portal's initial payload was 332 kB gzip until route splitting brought it to 161 kB; without a check, it silently grows back.

### 4.2 `release.yml` (Maren-Backend)

On merge to `main`, after CI passes: build the image, tag with the commit SHA **and** `main`, push to GHCR, deploy to staging, smoke `/health/ready`.

**Tag with the SHA, never only `latest`.** `latest` cannot be rolled back to and cannot be traced from a running container to a commit.

### 4.3 `dependabot.yml`

Weekly, grouped by ecosystem (NuGet, npm, pub, Actions). Grouping matters — ungrouped updates produce a PR storm that gets ignored wholesale.

Relevant now: react-router carries a **high-severity advisory** (GHSA-qwww-vcr4-c8h2, RSC-mode CSRF). The portal is a client-side SPA that does not use RSC mode, so it is **not exploitable here**, and npm's proposed "fix" is a *downgrade* to 7.11.0. The correct remedy is a deliberate upgrade to ≥ 8.3.0, tracked as its own task — not `npm audit fix --force`.

---

## 5. Branch protection

Once CI is green, require on `main`:
- CI must pass
- One approving review
- Branch up to date before merge
- No force push, no deletion

Requiring a red workflow is impossible, which is another reason fixing it comes first.

---

## 6. Deployment safety

| Control | Approach |
|---|---|
| **Rollback** | Redeploy the previous SHA tag. Must be one command, and must be rehearsed |
| **Schema vs code** | Scripts are additive and idempotent, so schema-first is safe and the old code keeps running. **Never ship a destructive schema change in the same release as the code that needs it** |
| **Smoke test** | `/health/ready` (real `SELECT 1`) after every deploy; fail the deploy on non-200 |
| **Approval** | Production requires a human. Staging does not |
| **Secrets** | GitHub OIDC federation rather than stored cloud credentials |

The schema/code ordering rule deserves emphasis: because every script is idempotent and additive, the database can always be migrated ahead of the application. That property is what makes rollback simple, and it is worth protecting.

---

## 7. Metrics worth gating on

| Metric | Gate |
|---|---|
| Backend build + tests | Must pass |
| SQL assertion suites | `FAILED: 0` on all five |
| Schema idempotency | Second apply must succeed |
| Vulnerable packages | Fail on high/critical |
| Portal type check + lint | Must pass |
| Portal initial bundle | < 200 kB gzip |
| Flutter analyze | Clean |
| CI wall time | < 15 min, or people start bypassing it |
