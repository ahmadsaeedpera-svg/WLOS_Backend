# Enterprise Platform Audit

**Date:** 2026-07-22
**Auditor:** Platform architecture review
**Method:** Direct inspection of the live database, source tree and repositories.
Every number below was measured, not estimated.

---

## Executive summary

The platform has a **strong core and no industrial substrate.**

What exists is genuinely good: stored-procedure-only data access, a CQRS
pipeline with authorization enforced outside handlers, permission-based RBAC
with privilege-escalation prevention enforced in the database, content
versioning with an approval gate, and 111 integration tests running against real
SQL. That is a better foundation than most projects at this stage.

What does not exist is everything that makes it operable by an organisation:
**no CI/CD, no containerisation, no observability, no backup or DR strategy, no
HA story, and a schema where zero tables meet the platform's own stated
contract.**

The single most urgent finding is the audit-column gap, because its cost grows
with every table added. Fixing it at 43 tables is a contained migration. Fixing
it at 150 is a project.

---

## 1. Compliance with the stated database contract

The platform standard requires every table to carry `CreatedBy`, `CreatedOn`,
`ModifiedBy`, `ModifiedOn`, `DeletedBy`, `DeletedOn`, `IsDeleted`, `RowVersion`.

**Measured across all 43 tables:**

| Column | Tables with it | Compliance |
|---|---|---|
| `CreatedOn` / `CreatedUtc` | 24 | 56% |
| `ModifiedOn` / `ModifiedUtc` | 15 | 35% |
| `RowVersion` | 16 | 37% |
| `IsDeleted` | 11 | 26% |
| `CreatedBy` | 4 | 9% |
| `DeletedOn` | 1 | 2% |
| `ModifiedBy` | 3 | 7% |
| `DeletedBy` | **0** | **0%** |

**Tables meeting the full contract: 0 of 43.**

The closest is `Content.ContentItem`, which has six of the eight.

### Why this is the top priority

1. **It is a breaking schema change.** Every month it waits, more procedures
   must be rewritten to populate the new columns.
2. **`DeletedBy` exists nowhere.** The platform can say a row was deleted but
   never who deleted it. For health data under GDPR that is not an acceptable
   answer to a regulator.
3. **Soft delete is inconsistent.** Eleven tables support it; thirty-two hard
   delete. `usp_Access_RotateSecurityStamp` issues a real `DELETE` against
   `Identity.RefreshToken`. Once a row is gone the audit trail references an id
   that resolves to nothing.
4. **Optimistic concurrency is partial.** Sixteen tables have `RowVersion`; the
   rest allow silent last-write-wins. The CMS solved this with version numbers
   and ETags; nothing else did.
5. **Naming is inconsistent** — `CreatedUtc` versus the mandated `CreatedOn`.
   Two conventions in one schema means every new developer picks the wrong one
   half the time.

---

## 2. Inert schema — tables with no way to reach them

| Schema | Tables | Procedures | Status |
|---|---|---|---|
| Identity | 10 | 22 | Healthy |
| Content | 11 | 16 | Healthy |
| Administration | 7 | 4 | Thin — `CrashReport`, `SupportTicket`, `AppVersion`, `FeatureFlagVariant`, `FeatureFlagAssignment` unreachable |
| Audit | 1 | 1 | Adequate |
| **Health** | **9** | **0** | **Completely inert** |
| **Notifications** | **4** | **0** | **Completely inert** |

**13 tables — 30% of the schema — have no stored procedure, no repository, no
API and no portal surface.** They were created and never wired up.

`Health.*` is the entire mobile data model: `Pregnancy`, `DailyLog`, `Symptom`,
`Appointment`, `BirthPreference`, `HospitalBagItem`, `BodyMeasurement`, `Cycle`,
`ShareGrant`. The mobile app stores all of this locally in Drift and the
platform cannot see any of it.

`Notifications.*` has `Campaign`, `Template`, `TemplateTranslation`, `Delivery`
— the skeleton of the notification module with nothing built on it.

This is misleading in a specific way: someone reading the schema would
reasonably conclude these capabilities exist.

---

## 3. Missing modules

Measured against the stated goal — an operator changes the app without an APK
release — here is what the platform can and cannot drive today.

| Capability | Schema | Procs | API | Portal | Status |
|---|---|---|---|---|---|
| Feature flags | ✅ | ✅ | ✅ | ✅ | **Complete** |
| CMS / articles / tips | ✅ | ✅ | ✅ | ✅ | **Complete** |
| Content versioning | ✅ | ✅ | ✅ | ✅ | **Complete** |
| Users / roles / permissions | ✅ | ✅ | ✅ | ✅ | **Complete** |
| Audit | ✅ | ✅ | ✅ | ✅ | **Complete** |
| Translations | ⚠️ per-content only | ⚠️ | ⚠️ | ⚠️ | **Partial** — no UI string catalogue |
| Notifications / push campaigns | ⚠️ tables only | ❌ | ❌ | ❌ | **Not built** |
| Remote config | ⚠️ `Setting` table | ⚠️ | ⚠️ | ❌ | **Partial** |
| Maintenance mode | ❌ | ❌ | ❌ | ❌ | **Not built** |
| Version gates / force upgrade | ⚠️ `AppVersion` | ❌ | ❌ | ❌ | **Not built** |
| Splash screens | ❌ | ❌ | ❌ | ❌ | **Not built** |
| Announcement banners | ❌ | ❌ | ❌ | ❌ | **Not built** |
| Home cards / feed layout | ❌ | ❌ | ❌ | ❌ | **Not built** |
| Journey timeline | ❌ | ❌ | ❌ | ❌ | **Not built** |
| Questionnaires | ❌ | ❌ | ❌ | ❌ | **Not built** |
| Achievements / badges / challenges | ❌ | ❌ | ❌ | ❌ | **Not built** |
| Checklists / hospital lists | ⚠️ user data only | ❌ | ❌ | ❌ | **Not built** — no operator-managed templates |
| Birth plan templates | ⚠️ user data only | ❌ | ❌ | ❌ | **Not built** |
| Emergency numbers / doctor lists | ❌ | ❌ | ❌ | ❌ | **Not built** |
| FAQ | ⚠️ CMS type | ⚠️ | ⚠️ | ⚠️ | **Usable via CMS** |
| Legal pages / terms / privacy / disclaimer | ⚠️ CMS type | ⚠️ | ⚠️ | ⚠️ | **Usable via CMS, no consent ledger** |
| Store listing assets | ❌ | ❌ | ❌ | ❌ | **Not built** |
| A/B tests | ⚠️ `FeatureFlagVariant` | ❌ | ❌ | ❌ | **Not built** — table exists, nothing reads it |
| Deep links | ❌ | ❌ | ❌ | ❌ | **Not built** |
| Analytics / telemetry | ❌ | ❌ | ❌ | ❌ | **Not built** |
| Support tooling | ⚠️ `SupportTicket` | ❌ | ❌ | ❌ | **Not built** |
| Subscriptions / entitlements | ❌ | ❌ | ❌ | ❌ | **Not built** |

**Complete: 5 of 28.** The mobile app currently reads none of it — all content
still ships inside the APK.

---

## 4. Security assessment

### Strong

- Permission-based RBAC with **no role checks in code**.
- Privilege escalation prevented **in the stored procedure**, so a support
  script cannot bypass it. Verified: a `roles.write` holder attempting to grant
  `SuperAdmin` receives 409 naming all 26 missing permissions.
- Session revocation measured at **~5 seconds** against a 15-minute token.
- Refresh token rotation with reuse detection.
- PBKDF2-HMAC-SHA256, 210,000 iterations, per-row iteration count,
  `FixedTimeEquals`.
- Append-only audit, asserted across every procedure.
- Refused escalation attempts audited **outside the transaction**, so a rollback
  cannot erase evidence of probing.
- No password material reachable outside the login path, asserted statically.
- CORS named-origin only.

### Gaps

| Gap | Risk | Notes |
|---|---|---|
| **No encryption at rest** | **High** | Health data — pregnancy status, symptoms, appointments — stored in plaintext. No TDE, no Always Encrypted, no column encryption. |
| **No key rotation** | **High** | `Jwt:SigningKey` is static. Rotating it invalidates every token with no staged rollover. |
| **No two-person approval** | Medium | Content has an approval gate but one `SuperAdmin` can author, approve and publish. Stated requirement not met. |
| **No field-level permissions** | Medium | Permissions gate endpoints, not fields. A support agent reading a user sees every column the DTO exposes. |
| **No ABAC** | Medium | No attribute rules — "own records only", "same country only". Everything is role-derived. |
| **No secrets management** | **High** | Configuration from files and environment. No Key Vault, no managed identity. |
| **Rate limiting is in-memory** | Medium | Per-instance. Behind two instances the effective limit doubles; a restart clears it. |
| **No GDPR erasure** | **High** | No account deletion, no data export, no consent ledger. `IsDeleted` on `User` is not erasure. |
| **No account lockout policy** | Low | `FailedLoginCount` is tracked; nothing automatically locks. |
| **No MFA** | Medium | Administrators holding `content.publish` and `roles.write` authenticate with a password alone. |
| **No device trust** | Low | `Device` registers but is not bound to sessions. |

---

## 5. Scaling and availability

| Concern | Current | Ceiling |
|---|---|---|
| **Cache** | In-process `MemoryQueryCache` | **Blocks horizontal scaling.** Two instances hold divergent flag and content caches for up to the TTL. |
| **Rate limiting** | In-process partitioned limiter | Same. |
| **Security-stamp revocation** | In-process 30s cache | Same — revocation latency multiplies by instance count. |
| **Sessions** | Stateless JWT | Scales fine. |
| **Database** | Single instance | **Single point of failure.** No replica, no failover, no read scale-out. |
| **Background work** | None | Scheduled publishes rely on `usp_Content_RunDueSchedules` being called — **nothing calls it.** Scheduling silently does not work. |
| **Media** | Metadata only | No blob storage, no CDN. |
| **Audit growth** | Single unpartitioned table | Unbounded. Already 2000+ rows in development. |
| **Connection management** | Per-request | Fine, but no retry policy for transient faults. |

**The scheduled-publish finding is a live defect, not a gap.** The procedure
exists, is tested, and no scheduler invokes it. An operator scheduling a publish
today sees it accepted and it never fires.

---

## 6. Observability, DevOps, DR

Measured: **all absent.**

| Area | Status |
|---|---|
| CI/CD | **None.** No `.github/workflows`. Nothing runs tests on push. |
| Containerisation | **None.** No Dockerfile, no compose. |
| Infrastructure as code | **None.** No Bicep, Terraform or ARM. |
| Distributed tracing | **None.** No OpenTelemetry, no Application Insights. |
| Metrics | **None.** No counters, no histograms, no dashboards. |
| Correlation IDs | **Column exists, never populated.** `AuditLog.CorrelationId` is always null. |
| Structured logging | Serilog present; console sink only, no aggregator. |
| Alerting | **None.** |
| Backup strategy | **None documented or automated.** |
| Point-in-time restore | **Untested.** |
| Disaster recovery | **No plan. No RTO. No RPO.** |
| High availability | **None.** Single API, single database. |
| Environment separation | **None.** Development configuration only. |
| Load or soak testing | **None.** |
| Dependency scanning | **None.** |
| Static analysis / SAST | **None.** |

Health probes exist and are correct (`/health/live` avoids the database,
`/health/ready` checks it and returns 503). Nothing consumes them.

---

## 7. Technical debt and duplication

| Item | Severity | Detail |
|---|---|---|
| **Two datetime conventions** | High | `CreatedUtc` vs mandated `CreatedOn`. Fix during the audit-column migration or it calcifies. |
| **`Result` duplicated across layers** | Low | Acceptable — `Maren.Shared` is the single definition. |
| **Escalation rules stated twice** | **Intentional** | Procedure is the boundary; C# gives a better message. Documented in ADR-001. Keep, and keep the test that they agree. |
| **`Administration.Setting` half-built** | Medium | Has a read path for clients, no admin write path. Remote config is stuck. |
| **`FeatureFlagVariant` / `Assignment` orphaned** | Medium | A/B testing schema with nothing reading it. Either build it or drop it — inert schema misleads. |
| **`Maren.Contracts` has no versioning** | High | A DTO change silently breaks shipped mobile clients. No `v1`/`v2` namespace, no deprecation policy. |
| **No API versioning in routes** | Medium | Routes say `/api/v1/` but nothing enforces or negotiates it. |
| **Portal has no tests** | Medium | Zero. Verification is manual browser driving. |
| **Portal missing stated stack** | Medium | React Hook Form and Zod are dependencies but **unused** — forms are hand-rolled `useState`. No charts, no virtualised tables, no dark mode. |
| **No `.editorconfig` / analyzer rules** | Low | Style is convention, not enforced. |
| **`SqlErrorMapper` swallows detail** | Low | Correct for clients, but the original is not logged structurally either. |

---

## 8. What I would tell an incoming CTO

The core is sound and the operational shell is missing entirely. Specifically:

1. **You cannot deploy this repeatably.** No container, no pipeline, no
   infrastructure definition. Deployment today is a developer running `dotnet
   run`.
2. **You cannot tell what it is doing.** No traces, no metrics, no alerts. The
   first sign of a problem will be a user complaint.
3. **You cannot recover it.** No backup automation, no tested restore, no RTO or
   RPO. A database loss today is a total loss.
4. **You cannot scale it.** Three in-process caches make a second instance
   incorrect, not just inefficient.
5. **You are storing health data in plaintext** with no erasure path. That is
   the finding most likely to become a legal problem.
6. **One feature silently does nothing.** Scheduled publishing is accepted by
   the API and never executes.

None of this is unusual for a platform at this stage. All of it must be fixed
before a paying customer or a regulator looks at it.
