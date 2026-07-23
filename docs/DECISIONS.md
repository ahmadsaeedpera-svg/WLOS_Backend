# Architectural Decisions & Open Questions

Decisions made (ADRs), decisions deferred, and decisions awaiting an answer.

---

## ADR-001: Platform Architecture (Accepted)

**File:** `Maren-Backend/docs/ADR-001-platform-architecture.md`

Nine architectural decisions. All accepted and implemented.

**Key decisions:**
1. Two solutions (Backend + Frontend), not one
2. Stored procedures only (no ORM, no inline SQL)
3. Content versions as JSON snapshots
4. Clients read published snapshots (not live tables)
5. Authorization is permission-based (not role-based)
6. Separation of duties (authoring ≠ approval)
7. Feature flags default to enabled
8. Integration tests run against real database
9. One response envelope everywhere

**For details:** See `Maren-Backend/docs/ADR-001-platform-architecture.md`

---

## PD-1: Mobile Sync — Opt-in vs. Mandatory (UNRESOLVED)

**Status:** 🔴 **Awaiting decision** · **Owner:** Product / Legal

**Context:**

The shipped mobile app states (About screen, Play Store listing):
> "There is no network code in Maren at all. Nothing you type can leave the device."

This claim is currently true. The app is offline-only. The Play Data Safety form declares zero collection across all categories.

**The question:**

When the Flutter client syncs health data to the platform, it becomes false. Sync changes:
- Play Data Safety declarations (must add Health & fitness, Personal info, Device IDs)
- Privacy policy (currently states nothing leaves the device)
- GDPR posture (Maren becomes a data controller)
- ASO strategy (offline-first is currently the stated differentiator vs Flo)
- HIPAA scope (if US healthcare providers access shared summaries via Doctor role)

**Schema position:**

The database is designed so this is optional, not mandatory:
- `Identity.User` supports an account, but
- No `Health` row requires a user account to exist
- App can be fully local without registration

**Needed:** A deliberate decision:
- **Option A:** Sync is opt-in (recommended). Users who never register stay fully offline.
- **Option B:** Sync is mandatory eventually. Timeline?
- **Option C:** Sync never happens. Content lives in app, we publish updates as APK releases.

**Impact:**

This decision blocks:
- Mobile integration work (Slice 5 — Privacy, see roadmap)
- Cloud backup/restore
- Data Safety declaration accuracy
- Privacy policy language

**Consequence for later phases:**

Once this is decided, the path is clear. Sync itself is ready—just needs this gate opened.

---

## PD-2: Stored Procedures Only (Accepted)

**Status:** ✅ Implemented

**Decision:** `Maren.Persistence` calls stored procedures exclusively. No ORM-generated SQL, no ad-hoc queries.

**Why this matters:** Rules about state transitions (publish requires approval, restore writes forward, privilege escalation prevented) live in the database. Any client that connects must follow them. An import job, a support script, a future service—all follow the same rules because they are enforced in procedures.

**Trade-off:** Procedures are harder to unit test than C#. Mitigated by decision 8 (integration tests against real database).

---

## PD-3: Content Versions Are Snapshots (Accepted)

**Status:** ✅ Implemented

**Decision:** `ContentVersion.SnapshotJson` holds the complete item as it was. Versions are immutable records.

**Why:** Diff-based versions would need to replay every prior edit to read a single version. Foreign-key-based versions become stale when the schema changes. Snapshots survive both.

---

## PD-4: Clients Read Published Snapshots (Accepted)

**Status:** ✅ Implemented

**Decision:** `usp_Content_GetForClient` reads text from published version snapshots, never from live working tables.

**History:** Originally wrong. Procedure gated on `PublishedVersionId` but read text from `ContentTranslation` (live). An editor typing into a published article pushed unreviewed health text to every device on sync.

**Exception:** Targeting (country, week, season, app version) is read live. Those are operational controls. Narrowing distribution during an incident must take effect immediately.

---

## PD-5: Permission-Based Authorization (Accepted)

**Status:** ✅ Implemented

**Decision:** Code checks permissions, not roles. Requests declare `IRequirePermission`. Pipeline enforces before handler runs.

**Why:** Roles are mutable bundles. Code checking `role.Name == "Editor"` breaks the moment an admin creates another role with the same permission. Checking permissions means the rule survives role reorganization.

---

## PD-6: Separation of Duties (Accepted)

**Status:** ✅ Implemented

**Decision:** `ContentEditor` holds `content.write` but not `content.review`. `ContentApprover` holds `content.review` but not `content.write`.

**Why:** An approver who can edit can approve their own changes. The gate would pass because the pointer names an approved snapshot—the snapshot would simply no longer match what was reviewed.

**Exception:** `SuperAdmin` holds both (deliberately, audited).

---

## PD-7: Feature Flags Default Enabled (Accepted)

**Status:** ✅ Implemented

**Decision:** `CachedFeatureFlagEvaluator` returns true for a flag with no row.

**Why:** Defaulting to disabled means a new `IRequireFeature` gate silently disables an endpoint in every environment until someone inserts a row. A deployment that appears successful but silently removes functionality. Defaulting to enabled makes a flag an off-switch for something that already works.

**Trade-off:** A typo in a flag name silently disables the gate. Mitigated by seed tests asserting every referenced flag exists.

---

## PD-8: Integration Tests Against Real Database (Accepted)

**Status:** ✅ Implemented

**Decision:** `Maren.Tests` opens real SQL Server connections. There are no repository mocks.

**Why:** Rules worth testing live in procedures (PD-2). Mocking `IContentRepository` verifies the mock, not the rule. The only meaningful test is whether an editor can publish something unapproved—that rule lives in `usp_Content_Publish`.

**Discovery:** Three endpoints shipped returning 500 on every call. Procedures ended in `SELECT *` while DTOs expected specific columns. No mocked test would have caught any.

**Trade-off:** Slower than unit tests, needs SQL Server. At 3 seconds for 86 tests, not a constraint yet.

---

## PD-9: One Response Envelope (Accepted)

**Status:** ✅ Implemented

**Decision:** Every endpoint returns the same shape:
```json
{
  "succeeded": bool,
  "data": T | null,
  "failureCode": string | null,
  "message": string | null,
  "validationErrors": { string: string[] } | null
}
```

**Why:** A client that parses one shape has one error path to get right. Status codes are still accurate for proxies and logs.

---

## Portal Session Tokens (Unresolved)

**Status:** 🟡 **Recorded, no timeline** · **Owner:** Architecture

**Context:**

The access token is held in memory. A browser refresh signs the operator out. This is deliberate—`localStorage` is readable by any script on the page, and the portal can publish to every user.

**The proper fix:**

Move the refresh token to a `SameSite=Strict`, `HttpOnly` cookie. The API would set the cookie on login; the browser sends it automatically on every request (no JavaScript needed).

**Blocker:** This requires an API change to the login endpoint (setting cookies instead of returning tokens in the body).

**Current status:** Acceptable for single-operator dev/staging. Before production, this should be fixed.

**Consequence:** If this is not fixed before public launch, operators will be logged out on every browser refresh, which is poor UX.

---

## Cache Strategy (Unresolved)

**Status:** 🟡 **Recorded, no timeline** · **Owner:** Infrastructure

**Context:**

Feature flags and content are cached in-process for 30 seconds. Behind more than one API instance, an editor's change can take up to the TTL to appear on other instances.

**The proper fix:**

Redis behind `IQueryCache`. Requires:
- Redis instance (cloud or self-hosted)
- Update `IQueryCache` implementation
- No handler changes (abstraction holds)

**Current status:** Acceptable at one instance. Before horizontal scaling, this should be fixed.

**Timeline:** When load justifies multiple API instances.

---

## Impersonation (Deliberately Unimplemented)

**Status:** ⚠️ **Feature exists, deliberately not built** · **Owner:** Legal

**Context:**

The `users.impersonate` permission is seeded but the handler is not implemented.

**Why not:**

Impersonation means an operator reading a patient's health data inside a pregnancy app. It requires:
- Legal review (is this allowed under GDPR, HIPAA?)
- Consent model (did the user consent to this operator viewing their data?)
- Time limit (how long can the operator stay logged in as the user?)
- User-visible banner (the operator sees a warning they are impersonating)
- Audit trail (separate entry showing impersonation, not the operator's normal activity)

Shipping this as "log in as user" without the above would be the largest privacy hole in the platform.

**If you want to implement impersonation:**
1. Open an issue with the legal questions
2. Get legal sign-off
3. Design the consent model
4. Implement with the safeguards above
5. Audit every use

---

## Release Candidate Tasks (Blocking Store Submission)

| Task | Status | Gates | Owner |
|---|---|---|---|
| **RC-1** — Insights articles rewrite (25 articles) | 🔴 Open | Store submission | Mobile team |
| **RC-2** — FDA wording audit (all strings) | 🔴 Open | Store submission | Mobile team |
| **RC-3** — Medical content review | 🔴 Open | Store submission | External (clinician) |
| **RC-4** — Legal review (privacy, GDPR, terms) | 🔴 Open | Store submission | Legal counsel |
| **RC-5** — Clinical behavioral audit | 🔴 Open | Store submission | External (clinician) |

See `Maren-Frontend/RELEASE_BLOCKERS.md` for details.

---

## Migration Path for Future Sync

**Once PD-1 is resolved, here is how sync will work:**

1. **User registration** (backend, already built)
   - Mobile: `POST /api/v1/auth/register` → get tokens
   - Tokens stored in memory (access) + app-secure storage (refresh)

2. **Initial sync** (backend, needs implementation)
   - Mobile: `POST /api/v1/client/health/sync` → send all local data
   - Backend: `usp_Health_SyncWrite` → insert/update rows, return any conflicts
   - Mobile: merge conflicts (show UI if user intervention needed)

3. **Ongoing sync** (backend, needs implementation)
   - Mobile: periodic `GET /api/v1/client/health/changes` → get server updates
   - Backend: `usp_Health_GetChanges` → return rows changed since last sync
   - Mobile: merge into local Drift DB

4. **Conflict resolution** (backend needs rules)
   - Last-write-wins? User-selects? Merge?
   - Depends on content type (preferences vs. logs)

5. **Network detection** (mobile responsibility)
   - App detects network and attempts sync
   - Offline: continue working locally
   - Online: background sync

**Everything is ready except:** PD-1 decision + backend sync handlers.

---

## For More Information

| Document | Contents |
|---|---|
| **ADR-001** | Nine architectural decisions (in Maren-Backend/docs) |
| **PLATFORM_DECISIONS.md** | Additional decisions (in Maren-Backend/docs) |
| **RELEASE_BLOCKERS.md** | RC phase work (in Maren-Frontend) |
| **SECURITY.md** | Security model, compliance, auth |
| **ARCHITECTURE.md** | System design, layering |
