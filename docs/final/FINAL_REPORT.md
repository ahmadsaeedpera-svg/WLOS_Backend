# FINAL REPORT — Maren Platform

**Date:** 2026-07-27 · **Branch:** `feature/backend-v2` (backend) · `feature/portal-v2` (frontend)
**Rule applied:** nothing is marked verified unless it was executed here. Everything else is **BLOCKED**, with evidence.

---

## 1. Verification matrix

### ✅ VERIFIED — executed on this machine

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Backend build, exactly as CI runs it | **PASS** | `dotnet build --no-restore -c Release -warnaserror` → 0 warnings, 0 errors, **exit 0** |
| 2 | Backend integration tests | **PASS** | `dotnet test --no-build -c Release` → **127 passed, 0 failed, exit 0** |
| 3 | Database fresh deploy | **PASS** | 20 scripts applied to a brand-new database (`MarenVerify`) |
| 4 | Database idempotency | **PASS** | Full set re-applied; converges |
| 5 | SQL assertion suites (5) | **PASS** | cms_workflow 17/0 · access 19/0 · index_coverage 2/0 · scheduled_publish 6/0 · ai_safety 8/0 = **52 assertions** |
| 6 | API liveness | **PASS** | `GET /health/live` → `200 {"status":"alive"}` |
| 7 | API readiness incl. real DB | **PASS** | `GET /health/ready` → `200 {"status":"ready","database":"ok"}` |
| 8 | API anonymous endpoint | **PASS** | `GET /api/v1/config/bootstrap` → `200` |
| 9 | API rejects missing token | **PASS** | `GET /api/v1/admin/users` → `401` |
| 10 | API rejects forged token | **PASS** | Same endpoint with `Bearer forged.token.here` → `401` |
| 11 | **Rate limiting** | **PASS** | 301 rapid requests → **6 × HTTP 429** |
| 12 | Portal build (strict TS) | **PASS** | `tsc -b && vite build` → built, no type errors |
| 13 | Portal tests | **PASS** | **24 passed** (client.ts 93% cov, AuthContext.tsx 97%) |
| 14 | Portal lint | **PASS** | 2 warnings, both pre-existing fast-refresh notices |
| 15 | Portal bundle budget | **PASS** | Initial payload **161 kB gzip** (was 332 kB), budget 200 kB |
| 16 | Execution-plan improvement | **PASS** | `Health.Pregnancy` by `UserId`: Clustered Index Scan → **Index Seek** |

**Note on #11:** the handover report stated "Rate limiting not implemented." It **is** implemented and now proven to fire. Code wins.

---

### ❌ BLOCKED — cannot be verified here, with evidence

| # | Check | Status | Evidence |
|---|---|---|---|
| B1 | **Flutter mobile suite** | **BLOCKED** | `flutter --version` → *command not found*. The 462 test blocks across 47 files were **counted statically and never executed**. Any claim they pass is unsupported |
| B2 | **Flutter build / APK** | **BLOCKED** | Same: no SDK |
| B3 | **Docker image build** | **BLOCKED** | `docker --version` → *command not found* |
| B4 | **Container healthcheck fix** | **BLOCKED — and still broken** | Defect confirmed by reading (`HEALTHCHECK` calls `--healthcheck`; `Program.cs` has no arg handling). **Not fixed.** Cannot be validated without Docker |
| B5 | **GitHub Actions workflows** | **BLOCKED** | No runner available locally. Verified only by executing the *equivalent commands* by hand; the YAML itself has never run |
| B6 | **Cloudflare** | **BLOCKED / NOTHING EXISTS** | Searched all three repos for `wrangler.toml`, tunnel config, DNS-as-code: **zero files**. There is nothing to verify |
| B7 | **Render / Railway / Azure / k8s** | **BLOCKED / NOTHING EXISTS** | Same search: no `render.yaml`, `railway.*`, `*.bicep`, `*.tf`, `Chart.yaml`, manifests |
| B8 | **Deployment** | **BLOCKED** | No environment exists. Nothing has ever been deployed |
| B9 | **Backups / DR** | **BLOCKED** | `recovery_model_desc = SIMPLE`; `msdb.dbo.backupset` has **0 rows**. Nothing to restore, no restore ever attempted |
| B10 | **Monitoring / alerting** | **BLOCKED / NOTHING EXISTS** | No APM, metrics, uptime probe or error tracking in any repo |
| B11 | **Accessibility** | **BLOCKED** | No axe/a11y tests written. Known violations (unlabelled checkboxes in RolesMatrix, unlabelled switch and slider in FeatureFlags) are **documented but unverified and unfixed** |
| B12 | **E2E across the API boundary** | **BLOCKED** | No Playwright/Cypress. Backend and clients have never been tested together |
| B13 | **Performance under load** | **BLOCKED** | No load tool, no baseline. Execution plans verified; throughput never measured |
| B14 | **Secrets management** | **BLOCKED / NOTHING EXISTS** | No vault, no rotation. Env vars with committed dev fallbacks only |
| B15 | **Portal against a live API** | **BLOCKED** | Authenticated screens never exercised in a browser — no API instance was running when the portal was driven |

---

## 2. What changed in this engagement

**23 commits across two branches.** Every one verified before commit.

| Commit | Change | Verified by |
|---|---|---|
| `be209e6` | Database review + improvement plan | Live catalog, DMVs, execution plans |
| `bf1731e` | **18 missing FK indexes** (+1 found by the test) | Scan → Seek, proven by plan |
| `e2499db` | **Scheduled publish obeyed the approval gate** | 5/6 assertions failed before, 6/6 after |
| `b7cb9bb` | AI companion system/prompts/pipeline specs | — |
| `9ad55a6` | **AI safety ledger** (append-only, no message content) | 8/8 assertions; exemption verified on re-apply |
| `365a1a2` | Deployment / CI-CD / backup / recovery plans | Repo-wide config search |
| `91eeb96` | **CI gate restored** (two causes, not one) | Build exit 0; tests exit 0 |
| `aa1e731` | Portal: route splitting, strict TS, error boundaries | 332 → 161 kB gzip; browser smoke |
| `87be8e0` | **Portal's first 24 tests** | Mutation-tested; both injected bugs caught |

### Defects found and fixed

1. **Scheduled publish bypassed the approval gate** — unapproved health content could self-publish. Latent only because no scheduler calls it.
2. **Scheduled publish republished the stale version** — a newly approved edit silently never went live.
3. **18 foreign keys had no index** — "get my pregnancy" was a full table scan, proven by execution plan.
4. **CI was red** — and needed *two* fixes; the second (`dotnet test` exiting 1 while printing "Passed! 127") would have kept it red.

### Defects found and **NOT** fixed

1. **Container healthcheck (B4)** — still broken; would restart-loop any real container deploy.
2. **42 non-selective `IX_*_NotDeleted` indexes** — write amplification on every insert.
3. **ContentEditor destroys unsaved typing** on background refetch; can send `If-Match: null`.
4. **Settings blanks a secret** when editing only its description.
5. **RolesMatrix** is unusable by screen reader; saving one role wipes another's staged edits.
6. **FeatureFlags** slider frozen while dragging; a flag at 100% can never be reduced.
7. **No `usp_User_Erase`** — GDPR erasure is referenced in a comment and does not exist.

---

## 3. Production readiness

### Score: **32 / 100**

Up from ~18 at the start of the engagement. The rise is real but narrow: the *foundation* improved, and none of the *operational* prerequisites did.

| Dimension | Score | Basis |
|---|---:|---|
| Backend correctness | 8/10 | 127 tests, real DB, verified here |
| Database | 8/10 | 52 assertions, fresh deploy, idempotent; retention/partitioning absent |
| API | 8/10 | Health, authz and rate limiting proven live |
| Security (application) | 8/10 | Forged tokens rejected; no dynamic SQL; strong crypto |
| Portal | 6/10 | Strict, split, tested — but known work-destroying defects remain |
| Mobile | **?/10** | **BLOCKED** — never executed. Cannot be scored honestly |
| CI | 7/10 | Green and comprehensive; never actually run on a runner |
| **Deployment** | **1/10** | Nothing deployed; healthcheck broken |
| **Backups / DR** | **0/10** | None exist |
| **Monitoring** | **0/10** | None exists |
| Accessibility | 2/10 | Known violations, untested, unfixed |
| Documentation | 8/10 | Extensive and now reconciled to code |

**The three zeros are the story.** No backups, no monitoring, no deployment. Application quality cannot compensate for any of them.

---

## 4. Estimated readiness

| Milestone | Estimate | Dominated by |
|---|---|---|
| **Free app on Play Store** | **3–5 months** | Not engineering: 5 compliance blockers needing external clinician and legal sign-off, plus release signing and the PD-1 privacy decision |
| **Paid launch (revenue)** | **6–9 months** | Billing is a stub — no store SDK, no paywall, no subscriptions backend |
| **Production-grade operations** | **2–3 months** | Backups, monitoring, deployment, secrets — parallelisable with the above |
| **Enterprise / B2B2C readiness** | **18–30 months** | No multi-tenancy anywhere (the most expensive retrofit on the list), no SLA, no DR, no SOC 2 or HIPAA posture, no clinician surfaces |

These assume the current two-person team. Compliance latency, not engineering throughput, sets the launch date.

---

## 5. Honest summary

The engineering foundation is genuinely strong and is now measurably stronger: a restored CI gate, a clinical-safety bug fixed before it could ship, proven index improvements, the first tests the portal has ever had, and an AI design whose guardrails are enforced by architecture rather than by prompt.

**It is not close to production.** There is no deployment, no backup, and no monitoring; the mobile app — the actual product — has not been executed once in this environment; and the container healthcheck would restart-loop the first real deploy.

**Nothing in this report claims a success that was not executed.** Where it could not be run, it says BLOCKED and says why.
