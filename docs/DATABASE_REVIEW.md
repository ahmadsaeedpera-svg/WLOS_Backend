# DATABASE REVIEW — Maren Platform
## Principal Database Architect assessment

**Date:** 2026-07-27
**Reviewer stance:** Code and the **live catalog** are the only sources of truth. Every finding below was verified against a real SQL Server 2025 instance with all 18 scripts applied, not read from DDL alone.
**Method:** schema applied to `MarenAudit` on `(localdb)\MSSQLLocalDB`; catalog views, DMVs and `SHOWPLAN_TEXT` execution plans queried directly.

---

## 0. Verified baseline

| Check | Result |
|---|---|
| All 18 scripts applied in order | ✅ Clean, no errors |
| `cms_workflow_test.sql` | ✅ TOTAL 17, FAILED 0 |
| `access_test.sql` | ✅ TOTAL 19, FAILED 0 |
| `dotnet test` (real DB) | ✅ **127 passed, 0 failed** |
| Test collection cleanup | ❌ `InvalidOperationException` (masked; suite still green) |
| CI build (`-warnaserror`, clean Release) | ❌ **FAILS — 5 errors** (CA1310) |

### Live catalog inventory

| Object | Count |
|---|---|
| Tables | **44** (Identity 11, Content 11, Health 9, Administration 7, Notifications 4, Audit 1, dbo 1) |
| Stored procedures | **47** |
| Indexes | **121** (44 clustered + 77 nonclustered) |
| Filtered indexes | **46** |
| Foreign keys | **37** |
| CHECK constraints | **15** |
| DEFAULT constraints | **199** |
| Tables without a PK | **0** ✅ |
| Heap tables | **0** ✅ |
| Untrusted constraints | **0** ✅ |
| Temporal tables / partition schemes / columnstore / full-text | **0 / 0 / 0 / 0** |

---

## 1. What is EXCELLENT (keep, do not touch)

These are unusually disciplined and should be preserved verbatim through any redesign.

- **Structural hygiene is flawless.** Every one of 44 tables has a primary key and a clustered index. Zero heaps. Zero untrusted constraints — meaning the optimizer can *rely* on every FK and CHECK for plan simplification. This is rare and valuable.
- **Naming is consistent.** `PK_` 44, `IX_` 58, `UQ_` 14, `UX_` 5 — **zero** off-convention index names. Procedures uniformly `usp_<Area>_<Action>`.
- **No SQL injection surface.** Zero dynamic SQL in procedures (`EXEC(`/`sp_executesql` = 0 matches). Sorting uses `CASE` expressions, not string-built `ORDER BY`. JSON inputs guarded by `ISJSON` before `OPENJSON`.
- **Transaction discipline is correct.** 47/47 procedures set `NOCOUNT ON`. 20 use explicit transactions; **21 set `XACT_ABORT ON`**; and critically — **zero procedures open a transaction without `XACT_ABORT ON`.** That combination guarantees automatic rollback on runtime error.
- **Sophisticated, intentional indexing.** 46 filtered indexes, covering indexes with `INCLUDE`, `DESC` keys on time columns for recent-first paging. `UX_DailyLog_User_Date` is a textbook correct filtered unique index.
- **Append-only audit enforced by absence.** No `UPDATE`/`DELETE` procedure exists for `Audit.AuditLog`, and it is the sole justified row in `dbo.AuditContractExemption`.
- **The audit-column contract** (`08_AuditContract.sql`) — a cursor over `sys.tables` that cannot forget a table, with exemptions requiring a written reason. Genuinely good engineering.
- **The rowversion delta-sync pattern** (`15_Procs_ContentDelta.sql`) — token, upserts, tombstones. The most transferable asset in the repository.
- **Security rules live in the database**, not the app: privilege-escalation guard (`fn_UserHoldsAllPermissionsOfRole`), last-admin protection, refresh-token reuse detection burning the whole chain.

---

## 2. CRITICAL findings

### C-1 · 18 foreign keys have no supporting index — **proven to cause table scans**

Verified by execution plan, not inference:

```
SELECT p.PregnancyId FROM Health.Pregnancy p WHERE p.UserId = '...'
  --> Clustered Index Scan(OBJECT:([Health].[Pregnancy].[PK_Pregnancy]),
      WHERE:([UserId]=CONVERT_IMPLICIT(...)))
```

**"Get my pregnancy" — the single most common health query in the product — is a full table scan today.**

Unindexed FK columns (leading-column check against `sys.index_columns`):

| Schema.Table.Column | Impact |
|---|---|
| `Health.Pregnancy.UserId` | 🔴 Every per-user health read scans |
| `Health.HospitalBagItem.UserId` | 🔴 Same |
| `Health.ShareGrant.UserId` | 🔴 Same |
| `Identity.RefreshToken.UserId` | 🔴 Token lookup + revoke-all-sessions scans; **highest-write table** |
| `Identity.RolePermission.PermissionId` | 🟠 **CASCADE delete** → scan on permission delete |
| `Identity.User.CountryId` | 🟡 Lookup join |
| `Content.ContentItem.CategoryId` | 🟠 Category browse scans |
| `Content.ContentApproval.ContentItemId` / `.ContentVersionId` | 🟠 **CASCADE** |
| `Content.ContentReview.ContentItemId` / `.ContentVersionId` | 🟠 **CASCADE** |
| `Content.ContentPublishSchedule.ContentItemId` | 🟠 **CASCADE** |
| `Content.ContentItemTag.TagId` | 🟠 **CASCADE** |
| `Content.ContentAuthor.UserId` / `.AvatarMediaId` | 🟡 |
| `Administration.FeatureFlagAssignment.UserId` | 🟠 Per-user flag evaluation |
| `Administration.SupportTicket.UserId` | 🟡 |
| `Notifications.Campaign.TemplateId` | 🟡 |

**Aggravating factor:** 12 FKs use `ON DELETE CASCADE`. A cascade delete against an unindexed child column scans the child table.

### C-2 · The 42 `IX_*_NotDeleted` indexes are non-selective and cost writes on every insert

`08_AuditContract.sql` generates, for ~42 tables:

```sql
CREATE INDEX IX_<Table>_NotDeleted ON <table>(IsDeleted) WHERE IsDeleted = 0;
```

Verified in the live catalog: **42 such indexes, every one keyed on `IsDeleted` and filtered on that same column.** The key column is therefore **constant within the filter** — the index has no selectivity, covers nothing, and can satisfy almost no seek. It does add write amplification to **every insert on every table**, including the highest-write tables (`RefreshToken`, `Delivery`, all nine Health tables).

The *intent* is sound; the *implementation* does not deliver it. A filtered index is valuable when the **filter** is `IsDeleted = 0` and the **key** is the real predicate — exactly as `UX_DailyLog_User_Date` correctly does.

### C-3 · The entire Health schema is unreachable

Nine tables — `Pregnancy`, `Cycle`, `DailyLog`, `Symptom`, `BodyMeasurement`, `Appointment`, `HospitalBagItem`, `BirthPreference`, `ShareGrant` — are deployed, indexed and audit-contract compliant, and have **zero stored procedures**. Under the repo's own rule (`CLAUDE.md §4.1`: procedures only; §3: repositories call one named procedure), **no procedure means no reachable API.**

The foundation of the entire health domain is currently dead weight in the database.

### C-4 · `usp_User_Erase` is referenced but does not exist — GDPR gap

`02_Identity.sql:25` states erasure is handled by `usp_User_Erase`. **That procedure is not defined anywhere.** No procedure sets `User.IsDeleted`. The permission `users.delete` is seeded with nothing behind it. There is no export capability and **no consent tables at all** — a hard blocker for a product intending to serve adolescents.

Additionally, seeded FAQ content (`22_Seed_FAQ.sql`) publishes user-facing copy promising "an archive of everything you have tracked" — **a capability the database cannot perform.**

### C-5 · No backups, ever — and SIMPLE recovery

Live check: `recovery_model_desc = SIMPLE`, and `msdb.dbo.backupset` returns **zero rows for this database**. Combined with the audit finding that no backup/DR configuration exists in any repo, the current position is: **no point-in-time recovery, no backup history, no tested restore.** Acceptable for LocalDB development; **catastrophic if this pattern reaches production.**

---

## 3. HIGH findings

### H-1 · Unbounded growth on six tables, no archival anywhere

| Table | Growth driver | Retention |
|---|---|---|
| `Identity.RefreshToken` | **One row per token refresh, forever** (rotation on every use) | none |
| `Notifications.Delivery` | One row per user per push | none |
| `Audit.AuditLog` | Every admin action; two `NVARCHAR(MAX)` columns (`BeforeJson`, `AfterJson`) + `UserAgent NVARCHAR(1000)` | none |
| `Administration.CrashReport` | Full `StackTrace NVARCHAR(MAX)` per crash | none |
| `Content.ContentVersion` | Full JSON snapshot per edit, never pruned | none |
| `Health.*` | Per-user daily; soft-deleted rows never leave | none |

**Zero partitioning** exists (0 partition functions/schemes). `Audit.AuditLog` and `Notifications.Delivery` are the textbook date-partition candidates.

### H-2 · Content search will not scale — proven

```
SELECT ... FROM Content.ContentItem ci JOIN Content.ContentTranslation ct ...
WHERE ct.Title LIKE '%sleep%' OR ct.Body LIKE '%sleep%'
  --> Clustered Index Scan(OBJECT:([Content].[ContentTranslation].[PK_ContentTranslation]))
```

`LIKE '%term%'` over `NVARCHAR(MAX)` bodies is unindexable and degrades linearly. **Zero full-text indexes exist.** Tolerable for a small editorial library; not for a 19-module content estate.

### H-3 · `Notifications.Delivery` has no index on `UserId`

Its only nonclustered index is `IX_Delivery_Campaign(CampaignId, Status)`. "What have we sent this user?", per-user suppression checks, and send-dedup **all scan the highest-write table in the database.** There is also no idempotency key, so a retried send double-inserts.

### H-4 · Clustered PKs on client-supplied random GUIDs

All nine Health tables use `PRIMARY KEY CLUSTERED` on a **client-generated V4 GUID**. Under offline-sync insert bursts this fragments the clustered index badly and causes page splits. (Server-assigned GUIDs correctly use `NEWSEQUENTIALID()` — the discipline exists, it just cannot apply to client-generated keys.)

### H-5 · `READ_COMMITTED_SNAPSHOT` is OFF

Live check: `is_read_committed_snapshot_on = 0`, `snapshot_isolation_state_desc = OFF`. For a read-heavy API this means **readers block writers and writers block readers**. Enabling RCSI is one of the highest-value, lowest-risk changes available for concurrency.

### H-6 · No multi-tenancy dimension of any kind

No `Organization`/`Tenant`/`Program` table; no tenant column on any of the 44 tables; roles are global (`UserRole` is `PK(UserId, RoleId)` with no scope). The seeded `Doctor` role has **no permissions granted at all** — B2B2C was anticipated in the role list and never built. **This is the most expensive possible retrofit** and must be decided *before* the health procedure layer is written.

---

### H-7 · `usp_Content_RunDueSchedules` bypasses the approval gate — latent data-integrity bug

`usp_Content_Publish` enforces "publish requires approval" (`12_Procs_Content.sql:192-200`, returns `NOT_APPROVED`). The scheduled-publish runner does **not**: it publishes via `COALESCE(i.PublishedVersionId, i.CurrentVersionId)` with **no `ContentApproval` check** (`12_Procs_Content.sql:769-776`).

This is latent **only because nothing calls the runner** (no `BackgroundService` exists). The moment scheduling is wired up — which the roadmap requires — **unapproved content publishes itself to every device.** In a health product this is the clinical-safety rule the whole CMS was built to enforce. Must be fixed *before* the runner is scheduled.

### H-8 · Missing index on `ContentItem.ModifiedOn` — the default sort key

Admin content search sorts by `ModifiedOn` by default (`12_Procs_Content.sql:530-535`), and `ModifiedOn`, `CreatedOn` and `AuthorId` are **not indexed** on `ContentItem`. Every admin list therefore does scan → LOB read → **full sort of the matched set** → `OFFSET/FETCH`. Combined with H-2 this is the admin-side scale wall.

### H-9 · Unbounded result sets (no paging at all)

| Procedure | Returns |
|---|---|
| `usp_Content_Revisions` (`:584-590`) | **Every version including `SnapshotJson`** — grows forever per item |
| `usp_Content_GetForClient` (`:613`) | The **entire published library** per call — hottest anonymous endpoint |
| `usp_Content_GetDelta` (null token) | Full library on first sync |
| `usp_Access_GetRevocations` (`13_...:814`) | Whole revocation table, reloaded every 30s per instance, **never pruned** |

### H-10 · Cursor N+1 inside a transaction — `usp_Role_SetPermissions`

`13_Procs_Access.sql:729-746` opens a `CURSOR LOCAL FAST_FORWARD` over affected users and calls `usp_Access_RotateSecurityStamp` **once per user**, each doing `UPDATE` + `MERGE` + `DELETE` — **inside the transaction, holding locks**. Editing a role with 50k members ≈ 150k statements. All three inner statements are already set-based, so this is fixable to a single set-based pass.

---

## 4. MEDIUM findings

- **M-0 · Page size is clamped in only one procedure.** C# validators clamp 1–200 on all four paged endpoints, but SQL clamps only `usp_Content_Search` (`12_...:485-486`). `usp_User_Search`, `usp_Audit_Search` and `usp_Setting_Search` have no clamp and no `@Page < 1` guard — a defence-in-depth gap (not currently reachable through the API).
- **M-9 · `Audit.AuditLog.CorrelationId` is never populated.** The column exists, is selected out, and is surfaced on `AuditEntryDto` — but **no code ever writes a value**. It is `NULL` on all 191 seeded rows. A user-reported error cannot be tied to a log line.

- **M-1 · Two redundant index pairs.** `Content.ContentVersion`: `IX_ContentVersion_Item` duplicates the leading keys of `UQ_ContentVersion` (`ContentItemId, VersionNumber`) — pure write overhead. `Identity.User`: `IX_User_Search` and `IX_User_NotDeleted` overlap.
- **M-2 · `audit_contract_test.sql` is referenced but does not exist.** `08_AuditContract.sql:27` claims the build fails if a table falls out of the contract. The `tests/` folder contains only `access_test.sql` and `cms_workflow_test.sql`. **The contract is unpoliced.**
- **M-3 · No `TRY/CATCH` and no `THROW` in any of 47 procedures.** Consistent with the documented "expected failures return `Result` rows, unexpected errors bubble" model, and safe because `XACT_ABORT ON` guarantees rollback — but it means **no procedure can add context to an error** or translate a deadlock into a domain failure code.
- **M-4 · `Notifications` schema is 4 tables with zero procedures**, no per-user preferences, no quiet-hours storage (only three *global* settings rows), no recurring-reminder table, no dedup key.
- **M-5 · `Identity.Profile` is written once (empty) by `usp_User_Register` and never read or updated** by any procedure. `DateOfBirth`, `TimeZoneId` and the display fields are unreachable.
- **M-6 · Two prefixes for the same concept** — `UQ_` (14) and `UX_` (5) both denote uniqueness. Defensible (constraint vs index) but undocumented.
- **M-7 · `Reporting` schema exists and is empty.** Three `reporting.*` permissions are seeded against nothing.
- **M-8 · Audit-column overhead on the highest-volume tables.** Six audit columns (~40 bytes + two GUIDs) are added to *every* table including `Notifications.Delivery` and `Administration.CrashReport`, where the overhead may exceed the payload.

---

## 5. Non-findings (checked, and NOT problems)

Recorded so they are not "fixed" by a future reviewer:

- **Collation is consistent.** DB and server are both `SQL_Latin1_General_CP1_CI_AS`. (A collation conflict appears when joining `sys` catalog columns — that is normal metadata collation, not a schema defect.)
- **`SELECT *, COUNT(*) OVER()` in `usp_Content_Search`** draws from a CTE whose column list is fully explicit, so the result shape is controlled. Not a violation of the no-`SELECT *` rule.
- **`page_verify = CHECKSUM`** — correct.
- **`auto_shrink = OFF`** — correct.
- **Idempotent migrations genuinely work.** Re-applying all 18 scripts converges (CI proves this by applying them twice).

---

## 6. Verdict

| Dimension | Score | Basis |
|---|---:|---|
| Structural integrity | **10/10** | 0 heaps, 0 missing PKs, 0 untrusted constraints |
| Naming & consistency | **9/10** | Perfectly consistent; minor `UQ_`/`UX_` duality |
| Security | **9/10** | No dynamic SQL, rules in DB, append-only audit; GRANTs absent from repo |
| Transactions | **9/10** | `XACT_ABORT` universal where needed; no error enrichment |
| Relationships & constraints | **7/10** | 37 FKs all trusted — but 18 unindexed, 12 cascading |
| Indexing | **6/10** | Sophisticated where hand-written; 42 useless generated indexes |
| Performance | **5/10** | Proven scans on the hottest query paths; unindexable search |
| Scalability | **3/10** | No partitioning, no archival, unbounded growth on 6 tables |
| Backups / DR | **1/10** | SIMPLE recovery, zero backups ever taken |
| Fit for the 10-stage vision | **3/10** | Health domain unreachable; no tenancy, billing, consent, analytics |
| **Overall** | **6.5/10** | **Excellently crafted core; operationally and directionally incomplete** |

**Redesign necessary? Mostly NO.** The core is well built and should be preserved. What is required is **additive correction** (indexes, archival, partitioning, RCSI), **completion** (Health procedures, notifications wiring, erasure), and **two genuine redesigns** (generic life-episode in place of pregnancy-only; targeting-as-rules in place of targeting-as-columns).

**Compatibility:** every improvement in the accompanying plan is designed to be **additive and backward-compatible**. No existing procedure signature, table, or column is removed or renamed in the first three phases.

→ See `DATABASE_IMPROVEMENT_PLAN.md`.
