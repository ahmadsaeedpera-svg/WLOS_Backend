# PRODUCTION CHECKLIST

**Rule:** a box is ticked only when it has been **executed and observed**, not when it has been written.
**Legend:** ✅ verified here · ❌ blocked or absent · ⬜ not started

---

## Engineering

| | Item | Evidence |
|---|---|---|
| ✅ | Backend builds under CI conditions | `-warnaserror`, Release: 0 warnings, exit 0 |
| ✅ | Backend tests pass | 127 passed, **exit 0**, fresh database |
| ✅ | Database deploys from scratch | 20 scripts, brand-new database |
| ✅ | Schema is idempotent | Full re-apply converges |
| ✅ | SQL rule assertions pass | 52 assertions across 5 suites |
| ✅ | Portal builds with strict types | `tsc -b && vite build` |
| ✅ | Portal has tests | 24, mutation-tested |
| ❌ | **Mobile app builds** | **BLOCKED** — no Flutter SDK |
| ❌ | **Mobile tests pass** | **BLOCKED** — 462 blocks never executed |
| ❌ | E2E across the API boundary | None exist |
| ⬜ | Contract tests on `Maren.Contracts` | Two clients unprotected |

## API and security

| | Item | Evidence |
|---|---|---|
| ✅ | Liveness probe | `200 {"status":"alive"}` |
| ✅ | Readiness probe reaches the database | `200 {"status":"ready","database":"ok"}` |
| ✅ | Unauthenticated requests refused | `401` |
| ✅ | Forged tokens refused | `401` |
| ✅ | Rate limiting active | 6 × `429` after 300/min |
| ✅ | No dynamic SQL | Zero `EXEC(`/`sp_executesql` in procedures |
| ✅ | Passwords: PBKDF2-SHA256, 210k iterations | Code-verified |
| ✅ | Refresh rotation + reuse detection | Enforced in `usp_RefreshToken_Redeem` |
| ❌ | **Secrets in a vault** | No store; env vars with dev fallbacks |
| ❌ | **Secret rotation procedure** | None; JWT key rotation invalidates all tokens |
| ❌ | **Database least-privilege GRANTs** | Zero `GRANT`/`DENY` in any script |
| ❌ | Penetration test | Never performed |
| ⬜ | Authorization matrix (endpoint × role) | Ad-hoc coverage only |

## Operations — **the blocking section**

| | Item | Evidence |
|---|---|---|
| ❌ | **Anything deployed anywhere** | No environment exists |
| ❌ | **Container healthcheck works** | **Broken.** Would restart-loop; masked in dev by a compose override |
| ❌ | **Backups exist** | `SIMPLE` recovery; `backupset` has 0 rows |
| ❌ | **Point-in-time recovery** | Impossible by definition under `SIMPLE` |
| ❌ | **A restore has been performed** | Never attempted |
| ❌ | **Monitoring / alerting** | None |
| ❌ | **Log aggregation** | Console only; logs die with the container |
| ❌ | **Correlation IDs** | Column exists, never populated |
| ❌ | **Rollback rehearsed** | Nothing to roll back |
| ❌ | **On-call defined** | None |
| ❌ | CI has run on a real runner | Verified only by equivalent commands |
| ❌ | Cloudflare / CDN / WAF | No config in any repo |
| ❌ | Infrastructure as code | None |

## Mobile release

| | Item |
|---|---|
| ❌ | **Release signing** — currently debug keys; cannot ship to Play |
| ❌ | **Billing** — `StubSubscriptionGateway`, no store SDK, no paywall |
| ❌ | Play Console account |
| ❌ | Launcher icons / splash — placeholders |
| ❌ | Data Safety declaration matches the binary (**PD-1 unresolved**) |
| ❌ | Device testing completed |

## Compliance and legal — **launch gate**

| | Item |
|---|---|
| ❌ | **RC-1** Insights content compliance rewrite (~25 articles) |
| ❌ | **RC-2** FDA General Wellness wording audit of every string |
| ❌ | **RC-3** Clinician review of health content |
| ❌ | **RC-4** Legal review — privacy policy has `[TO FILL]`, **no Terms of Use exists** |
| ❌ | **RC-5** Clinical behavioural audit |
| ❌ | Trademark clearance vs "Marani Health" |
| ❌ | GDPR erasure — `usp_User_Erase` does not exist |
| ❌ | GDPR export — promised in shipped FAQ copy, not implemented |
| ❌ | Consent records — no tables exist |

## Accessibility

| | Item |
|---|---|
| ❌ | Automated a11y tests — none |
| ❌ | RolesMatrix screen-reader usable — unlabelled checkboxes, no row headers |
| ❌ | FeatureFlags controls labelled — switch and slider have no accessible name |
| ❌ | Portal usable on mobile — drawer is permanent 232px with no responsive variant |
| ❌ | Keyboard-only operation — DataGrid rows are mouse-only |

---

## Minimum set to launch a **free** app

1. Release signing keystore
2. Resolve PD-1 and correct the Data Safety declaration
3. RC-1 … RC-5 signed off by clinician and counsel
4. Terms of Use drafted
5. Backups on, **with a restore performed**
6. Container healthcheck fixed and validated against a real `docker run`
7. Monitoring and alerting with a named on-call
8. Flutter suite executed and green in CI

**Items 1–4 are not engineering work.** They are external review and legal drafting, and they set the launch date.

## Additionally required to take money

9. Store billing SDK + paywall
10. Subscriptions backend slice with receipt validation

## Additionally required for enterprise

11. Multi-tenancy — **no tenant dimension exists on any of the 45 tables**; retrofitting touches every table, index, procedure and permission check
12. SLA, DR with tested RTO/RPO, audit export, SSO, SOC 2 posture
