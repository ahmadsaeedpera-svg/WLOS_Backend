# DATABASE IMPROVEMENT PLAN — Maren Platform

**Companion to:** `DATABASE_REVIEW.md`
**Branch:** `feature/backend-v2`
**Governing constraints:**
1. **Never break compatibility.** No table, column, or procedure signature is removed or renamed in Phases 1–3. Every change is additive or internal.
2. **Redesign only if necessary.** The core is well built; most work is correction and completion, not replacement.
3. **One improvement at a time.** Each is independently verifiable, independently revertible, and committed on its own.

---

## Execution rules (applied to every improvement)

| Step | Requirement |
|---|---|
| **Architecture** | State what changes and why; confirm additive/backward-compatible |
| **Implementation** | Idempotent SQL in a numbered script; never edit a shipped script's meaning |
| **Tests** | SQL assertions and/or integration tests that fail before and pass after |
| **Security** | Confirm no new surface (no dynamic SQL, no privilege change) |
| **Performance** | Measure before/after where the change is performance-motivated |
| **Verification** | Re-apply all scripts (idempotency), run both SQL suites, run `dotnet test` |
| **Commit** | One improvement per commit, conventional message explaining *why* |

**Idempotency rule:** new scripts are numbered `30_*` and above so the existing 01–22 ordering is untouched, and every statement is guarded (`IF NOT EXISTS`). Re-running must converge, exactly as CI's double-apply proves.

---

## PHASE 0 — Unblock the build (prerequisite)

Nothing else can be verified while CI is red.

| # | Improvement | Type | Risk |
|---|---|---|---|
| **0.1** | Fix the 5 `CA1310` errors in `ContentDeltaTests.cs` (add `StringComparison.Ordinal`) | Test-only | None |
| **0.2** | Fix `DatabaseFixture` async disposal (`IAsyncLifetime`/`CreateAsyncScope`) — removes the masked `InvalidOperationException` | Test-only | None |

> Not database changes, but they gate honest verification of everything below.

---

## PHASE 1 — Additive performance corrections (zero compatibility risk)

All pure `CREATE INDEX` / `DROP INDEX` work. No schema, no procedure, no contract change.

### 1.1 · Add the 18 missing foreign-key indexes 🔴 **START HERE**
- **Why:** proven Clustered Index Scan on `Health.Pregnancy` by `UserId`; 12 FKs cascade against unindexed children.
- **What:** filtered indexes (`WHERE IsDeleted = 0` where the column exists) on every FK column lacking a leading-column index.
- **Verify:** re-run `SHOWPLAN_TEXT`; scan must become a seek. Assertion script proves zero unindexed FKs remain.
- **Compatibility:** additive only.

### 1.2 · Replace the 42 non-selective `IX_*_NotDeleted` indexes
- **Why:** keyed on `IsDeleted` *and* filtered on it — no selectivity, pure write amplification on every insert.
- **What:** drop them; fold `WHERE IsDeleted = 0` into the real per-table indexes from 1.1. **Amend the generator** in `08_AuditContract.sql` so they do not come back.
- **Verify:** index count drops by ~42; all suites still green; write path measured.
- **Compatibility:** indexes are not part of any contract.

### 1.3 · Add sort/filter indexes for admin list paths
- `ContentItem(ModifiedOn DESC)`, `ContentItem(CreatedOn DESC)`, `ContentItem(AuthorId)`; `Notifications.Delivery(UserId, QueuedUtc DESC)`.
- **Why:** default sort key is unindexed (H-8); `Delivery.UserId` scans the highest-write table (H-3).

### 1.4 · Remove the 2 redundant indexes
- `IX_ContentVersion_Item` (duplicated by `UQ_ContentVersion`); review `IX_User_NotDeleted` against `IX_User_Search`.

### 1.5 · Enable `READ_COMMITTED_SNAPSHOT`
- **Why:** readers block writers today. Highest concurrency win available.
- **Caution:** requires exclusive DB access to switch; adds `tempdb` version-store load. Deploy-time change, documented in the runbook.

---

## PHASE 2 — Correctness & safety (bug fixes, still compatible)

### 2.1 · Fix the approval-gate bypass in `usp_Content_RunDueSchedules` ✅ **DONE**
- Added the `ContentApproval` check `usp_Content_Publish` enforces. Refusals now mark the schedule `failed` with a `FailureReason` (both already existed in the schema and were unused) and write an audit row.
- **A second defect surfaced while testing:** the runner published `COALESCE(PublishedVersionId, CurrentVersionId)`, which for an already-published item resolves to the version *already live* — so scheduling a newly approved edit silently republished the old text. Now publishes `CurrentVersionId`, agreeing with `usp_Content_Publish`.
- **Test:** `tests/scheduled_publish_test.sql` — 5 of 6 assertions failed before the fix, 6/6 after. Wired into CI.
- **Compatibility:** result set deliberately left at one column (`Executed`); the caller uses `QuerySingleAsync<int>`.

### 2.2 · Clamp page size in `usp_User_Search`, `usp_Audit_Search`, `usp_Setting_Search`
- Match `usp_Content_Search`'s 1–200 clamp and add a `@Page < 1` guard. Defence in depth.

### 2.3 · De-cursor `usp_Role_SetPermissions`
- Replace the per-user cursor with a single set-based stamp rotation. Same semantics, one pass instead of ~150k statements at 50k members.

### 2.4 · Populate `Audit.AuditLog.CorrelationId`
- Thread a correlation id from the API through to the audit procedures (currently `NULL` on every row). Additive parameter with a default, so no signature break.

### 2.5 · Create the missing `audit_contract_test.sql`
- `08_AuditContract.sql:27` claims the build fails if a table leaves the contract. That test does not exist — **the contract is unpoliced.** Write it.

---

## PHASE 3 — Growth control (additive, operational)

### 3.1 · Retention & archival procedures
- `usp_RefreshToken_Purge` (expired/revoked), `usp_Delivery_Archive`, `usp_CrashReport_Purge`, `usp_ContentVersion_Prune` (keep N + all published), `usp_Access_PruneRevocations`.
- **Why:** six tables grow unbounded with zero retention; the revocation table is reloaded whole every 30s per instance and never pruned.
- **Note:** these need a scheduler — see the backend plan's background-jobs module. Ship the procedures first; they are safe to run manually.

### 3.2 · Partition `Audit.AuditLog` and `Notifications.Delivery` by month
- Both are append-only, date-ordered, and the two largest projected tables. Partitioning enables cheap archival by switch-out.
- **Compatibility:** partitioning is transparent to queries.

### 3.3 · Full-text index for content search
- Replace `LIKE '%…%'` (proven scan + LOB read) with a full-text catalog on `ContentTranslation(Title, Summary, Body)`.
- **Caveat noted in code:** a catalog must exist before deploy — so this becomes a documented deployment prerequisite, and `usp_Content_Search` keeps a `LIKE` fallback path for environments without it. **Backward compatible by design.**

### 3.4 · Backups & recovery model
- Not a schema change: define recovery model (FULL for production), backup schedule, retention, and a **tested restore** runbook. Today: SIMPLE recovery, zero backups ever taken.

---

## PHASE 4 — Completion (new capability; additive)

### 4.1 · Health domain procedures — **the biggest functional gap**
Nine tables, zero procedures, therefore no reachable API. Build CRUD + delta-sync per table, reusing the excellent `15_Procs_ContentDelta.sql` rowversion pattern verbatim.
> **Decide first:** hand-write ~50–70 procedures, or generate CRUD from a table manifest the way `08_AuditContract.sql` generates columns. This is the rate limiter on backend v2.

### 4.2 · GDPR: `usp_User_Erase`, export, consent
- `usp_User_Erase` is referenced in a comment but **does not exist**; `users.delete` has nothing behind it; there are **no consent tables**. Seeded FAQ copy already promises users "an archive of everything you have tracked" — a capability the database cannot perform. **Legal exposure; and mandatory before serving adolescents.**

### 4.3 · Notifications wiring
- Per-user preferences, quiet hours (currently three *global* settings rows; `Profile.TimeZoneId` exists but is never read), recurring reminders, delivery dedup key, and the procedures — currently zero.

### 4.4 · `Identity.Profile` read/write procedures
- Written once (empty) by `usp_User_Register`, never read or updated. `DateOfBirth` and `TimeZoneId` are unreachable — both are prerequisites for life-stage and quiet-hours features.

---

## PHASE 5 — Directional redesign (breaking; requires explicit decision)

**Do not start without a product decision.** These are the only genuine redesigns.

| # | Change | Trigger |
|---|---|---|
| **5.1** | `Health.Pregnancy` → generic `Health.LifeEpisode(EpisodeType, …)` | Only if the multi-life-stage vision is confirmed |
| **5.2** | Targeting-as-columns → `Content.ContentTargetingRule` table | Adding a 7th dimension currently means editing **6 places** incl. DTOs |
| **5.3** | Generalize `HospitalBagItem` → checklist, `BirthPreference` → preference store | Correct shapes trapped behind pregnancy-specific names |
| **5.4** | Move pregnancy fields off `Identity.Profile` | `ExpectingMultiples`/`BabyTerm` on the identity record |
| **5.5** | Health PKs: `NONCLUSTERED` on client GUID, cluster on `(UserId, Date)` | Client-generated V4 GUIDs fragment the clustered index under sync load |
| **5.6** | **Multi-tenancy dimension** | **Most expensive retrofit on the list — decide BEFORE 4.1 is written** |

> ⚠️ **5.6 is the critical sequencing decision.** Adding a tenant dimension after the Health procedure layer exists means rewriting every one of them. If B2B2C is genuinely on the roadmap, decide it now.

---

## Sequencing summary

```
Phase 0  Unblock build            ── prerequisite for honest verification
Phase 1  Additive indexes + RCSI  ── zero risk, immediate measurable win  ◄── START
Phase 2  Correctness bugs         ── includes the approval-gate bypass (severe)
Phase 3  Growth control           ── retention, partitioning, full-text, backups
Phase 4  Completion               ── Health procs, GDPR, notifications
Phase 5  Redesign                 ── gated on product decisions (esp. tenancy)
```

**Order rationale:** Phase 1 is pure upside with no compatibility surface, so it validates the whole workflow (change → verify → commit) at zero risk. Phase 2 contains the only *severe* correctness bug. Phases 3–4 are large but additive. Phase 5 is deliberately last and decision-gated.

---

## Verification harness (used for every improvement)

```bash
# 1. idempotency — re-apply all scripts, must converge
for f in src/Maren.Database/*.sql; do sqlcmd -S "$SERVER" -I -d "$DB" -i "$f" -b || exit 1; done

# 2. SQL assertion suites
sqlcmd -S "$SERVER" -I -d "$DB" -i src/Maren.Database/tests/cms_workflow_test.sql   # expect TOTAL 17 FAILED 0
sqlcmd -S "$SERVER" -I -d "$DB" -i src/Maren.Database/tests/access_test.sql         # expect TOTAL 19 FAILED 0

# 3. integration tests against the real database
dotnet test tests/Maren.Tests                                                       # expect 127 passed

# 4. CI-equivalent build
dotnet build --no-restore -c Release -warnaserror
```

**Baseline recorded 2026-07-27:** 18 scripts apply clean · SQL suites 17/0 and 19/0 · **127 tests pass** · CI build **fails** (5 × CA1310) · 44 tables, 47 procedures, 121 indexes, 37 FKs.
