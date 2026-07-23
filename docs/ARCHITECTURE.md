# Maren Platform — Architecture

Complete system design, layering rules, and data flow across the three-repo split.

---

## System Overview

```
┌──────────────────────────────────────────────────────────────┐
│                    CLIENTS (Frontend Repo)                   │
├──────────────────────────┬──────────────────────────────────┤
│   Flutter Mobile App     │    React Admin Portal             │
│   (Maren-Frontend/mobile)│    (Maren-Frontend/web-admin)     │
│   - Offline-first        │    - API-backed                   │
│   - Drift SQLite         │    - TypeScript strict            │
│   - 425 tests            │    - MUI + DataGrid               │
└──────────────────────────┴──────────────────────────────────┘
           │                           │
           └───────────────────────────┘
                       │
                 REST API + JWT
                (TCP 5199 dev)
           (Maren-Backend/Maren.Api)
                       │
    ┌──────────────────┴──────────────────┐
    │     CQRS Pipeline (MediatR)         │
    │  ┌─────────────────────────────┐   │
    │  │ 1. Logging Behavior         │   │
    │  ├─────────────────────────────┤   │
    │  │ 2. Authorization (IRequire  │   │
    │  │    Permission check)        │   │
    │  ├─────────────────────────────┤   │
    │  │ 3. Feature Flag Behavior    │   │
    │  │ (IRequireFeature)           │   │
    │  ├─────────────────────────────┤   │
    │  │ 4. Validation (FluentVal)   │   │
    │  ├─────────────────────────────┤   │
    │  │ 5. Caching (IQueryCache)    │   │
    │  ├─────────────────────────────┤   │
    │  │ 6. Transaction              │   │
    │  ├─────────────────────────────┤   │
    │  │ Handlers (CQRS)             │   │
    │  └─────────────────────────────┘   │
    │                                     │
    │  Domain Layer (invariants only)    │
    └─────────────────────────────────────┘
                       │
    ┌──────────────────┴──────────────────┐
    │  Repositories (Dapper only)         │
    │  - No ORM, no query generation      │
    │  - Call stored procedures by name   │
    │  - Result materialization only      │
    └──────────────────┬──────────────────┘
                       │
        ┌──────────────┴──────────────┐
        │   SQL Server 2025           │
        │   (LocalDB for dev)          │
        │                             │
        │  Schemas:                   │
        │  ├─ Identity                │
        │  ├─ Administration          │
        │  ├─ Health                  │
        │  ├─ Content                 │
        │  ├─ Notifications           │
        │  ├─ Audit                   │
        │  ├─ CMS                     │
        │  ├─ Access                  │
        │  └─ Configuration           │
        │                             │
        │  All rules enforced in      │
        │  stored procedures          │
        └─────────────────────────────┘
```

---

## Layering Decisions

### 1. Two Repositories, Not One

**Decision:** Maren-Backend and Maren-Frontend are separate.

**Why:**
- Different toolchains (.NET vs. Dart/TypeScript)
- Different release cadences (API can hotfix independent of mobile app review)
- Different reviewers (backend code review ≠ mobile UI review)

**Contract:** Client contracts live in `src/Maren.Contracts`. Changing a DTO is a breaking change for the frontend.

**Mitigation:** Contract is small and versioned. No automatic code generation; explicit visibility prevents drift.

---

### 2. Stored Procedures Only — No ORM

**Decision:** `Maren.Persistence` contains Dapper repositories calling named procedures. Zero ad-hoc SQL.

**Why:**
- **Rules belong in the database.** State-transition rules (publish requires approval, restore writes forward, you cannot grant a permission you do not hold) live in procedures, not C#.
- **Rules hold regardless of who connects.** An import job, a support script, a CLI tool—anything calling the database follows the same rules because they are enforced in the database.
- **Rules survive refactoring.** A procedural rule can be fixed without redeploying the API, saving hours on a clinical-safety issue.
- **API has no table permissions.** The SQL login used by the API can `EXECUTE` specific schemas and has **zero table permissions**. A leaked connection string cannot `SELECT * FROM`.

**Cost:** Procedures are harder to unit test than C#. **Mitigated by ADR-008:** integration tests run against a real database, so every rule worth testing is tested for real.

---

### 3. Content Versions Are Snapshots, Not Diffs

**Decision:** `ContentVersion.SnapshotJson` holds the complete item as it was.

**Why:**
- **Versions are immutable records of the past.** A version built from foreign keys into live tables becomes incorrect the moment the schema changes. A snapshot survives schema evolution.
- **Approval names specific bytes.** An approval references a version id, and that version id names exact JSON—reproducible.
- **No replay cost.** You do not need to replay every prior version to read a single one.

**Cost:** Storage. Content items are small text; this is not a constraint at this scale.

---

### 4. Clients Read Published Snapshots, Never Live Tables

**Decision:** `usp_Content_GetForClient` sources text from the published version's snapshot, not from `ContentTranslation` (the live working copy).

**History:** This was originally wrong—a procedure gated on `PublishedVersionId` but read text from the live tables. An editor typing into a published article pushed unreviewed health text to every device on sync, defeating the approval workflow entirely. For a pregnancy app, unreviewed health content is a clinical-safety problem.

**Exception:** Targeting (country filter, week range, season, app version, publish window) is read live. Those are operational controls for narrowing distribution during an incident without a publish cycle. Approval governs *what it says*; operators govern *who sees it*.

---

### 5. Authorization Is Permission-Based, Not Role-Based

**Decision:** Requests declare `IRequirePermission`. Authorization is checked in the MediatR pipeline before the handler runs.

**Why:**
- **Roles are mutable bundles.** Code checking for `role.Name == "ContentEditor"` breaks the moment an administrator creates a second role with the same permission.
- **Pipeline check prevents handler bypass.** A handler invoked by another handler cannot skip authorization because the check is on the request, not in the handler.
- **One check, consistently enforced.** A role is a UI construct; permissions are the actual boundaries.

**In the portal:** Permission codes are used to hide buttons (a courtesy). The API re-checks every permission in the pipeline. A hidden button is defeated by opening the network tab—so the UI is not access control, only UX.

---

### 6. Separation of Duties: Authoring ≠ Approval

**Decision:** `ContentEditor` holds `content.write` but not `content.review`. `ContentApprover` holds `content.review` but not `content.write`.

**Why:** An approver who can also edit can approve their own changes by editing after approval. The approval workflow would still pass because the pointer would name an approved snapshot—but the snapshot would no longer be what anybody reviewed.

**Exception:** `SuperAdmin` holds both. This is deliberate and audited.

---

### 7. Feature Flags Default to Enabled

**Decision:** `CachedFeatureFlagEvaluator` returns `true` for a flag with no database row.

**Why:** Defaulting to disabled means adding a new `IRequireFeature` gate silently disables that endpoint in every environment until someone remembers to insert a row. A deployment that appears to succeed and quietly removes functionality. Defaulting to enabled makes a flag an off-switch for something that already works.

**Cost:** A typo in a flag name silently disables the gate. **Mitigated by ADR-007:** seed tests assert every referenced flag name exists.

---

### 8. Integration Tests Run Against Real SQL

**Decision:** `Maren.Tests` opens real connections and calls real procedures. There are no repository mocks.

**Why:** Every rule worth testing lives in a procedure (decision 2). Mocking `IContentRepository` verifies the mock, not the rule. The only meaningful test is whether an editor can publish something nobody approved, and that rule lives in `usp_Content_Publish`, not in C#.

**Discovery:** `ProcedureShapeTests` caught three endpoints returning 500 on every call because procedures ended in `SELECT *` while their DTOs expected specific columns. No mocked test would have found any of them.

**Cost:** Slower than unit tests, needs SQL Server. At three seconds for 86 tests, not yet a constraint.

---

### 9. One Response Envelope, Everywhere

**Decision:** Every endpoint returns `ApiResponse<T>`, both for success and failure.

```csharp
{
  "succeeded": bool,
  "data": T | null,
  "failureCode": string | null,
  "message": string | null,
  "validationErrors": { string: string[] } | null
}
```

**Why:** A client that parses one shape has one error path to get right. Status codes are still correct for proxies and logs, but the envelope is consistent.

---

## Backend Architecture

### Layer 1: API (Maren.Api)

- **Controllers:** HTTP only. No business logic. Translate `Result<T>` → HTTP status + body.
- **Middleware:** JWT validation, security stamp, rate limiting (not yet implemented).
- **DI Configuration:** Register all handlers, validators, repositories, caching.
- **OpenAPI:** Native framework via `AddOpenApi()` + Scalar (not Swashbuckle).

**Rule:** Controllers contain only `[Authorize]` (is authenticated?). Permissions are checked by the pipeline.

### Layer 2: Application (Maren.Application)

- **CQRS:** MediatR handlers for commands and queries.
- **Pipeline Behaviors:** Logging → Authorization → FeatureFlag → Validation → Caching → Transaction (order matters).
- **Validators:** FluentValidation on every command and query.
- **Abstractions:** `IRequirePermission`, `IRequireFeature`, `ITransactional`.

**Rule:** Handlers orchestrate only. They call one repository method or invoke a domain rule. No inline SQL. No business logic in multiple handlers.

### Layer 3: Domain (Maren.Domain)

- **Invariants:** Rules about state transitions (e.g., `PublishApprovalRules`, `PermissionEscalationRules`).
- **Value objects:** `Permission`, `Email`, `Password`.
- **Entities:** Domain entities (not Persistence entities).

**Rule:** Domain imports nothing from the framework. It is pure Dart (conceptually)—testable, portable, independent.

### Layer 4: Persistence (Maren.Persistence)

- **Dapper repositories:** One method per stored procedure call.
- **Result materialization:** Maps SQL result sets to DTOs/records.
- **No query builders:** No inline SQL, no LINQ-to-SQL.
- **Connection pooling:** Managed by the framework.

**Rule:** A repository method opens the connection once, calls one procedure, maps the result, closes the connection. No composition.

### Layer 5: Infrastructure (Maren.Infrastructure)

- **JWT:** Token generation, refresh-token rotation, reuse detection.
- **Password hashing:** PBKDF2-HMAC-SHA256, 210,000 iterations, per-row count.
- **Caching:** In-process cache behind `IQueryCache` (Redis-ready).
- **Security stamps:** Session revocation within ~30 seconds.

---

## Frontend Architecture

### Mobile (Flutter)

**Layering:** Presentation → Application → Domain ← Data

```
lib/features/<feature>/
├─ presentation/          Screens, widgets (no logic)
├─ application/           Controllers, state (Riverpod)
├─ domain/                Entities, rules (pure Dart)
└─ data/                  Repository implementations, Drift DAOs
```

**Rule:** A screen never touches a DAO. Domain imports nothing from Flutter.

**Offline-first:** All state lives in Drift over SQLite. The app is currently offline-only. See **PD-1** before adding networking.

### Admin Portal (React)

**Layering:** Components → API client → Server

```
src/
├─ api/                   client.ts (the only fetch() call)
├─ auth/                  AuthContext, session, permissions
├─ components/            Shell, shared components
├─ modules/               One folder per admin feature
│  ├─ users/
│  ├─ roles/
│  ├─ cms/
│  ├─ audit/
│  └─ ...
```

**Rule:** Modules call the API client, not `fetch()` directly. Token handling, response envelopes, error shaping live in the client once.

**Permission checks:** Courtesy only (hide buttons). The API re-checks every permission. A hidden button is defeated by the network tab.

---

## Data Model Overview

### Identity Schema

- `User` — accounts, email, password hash (PBKDF2), login timestamp
- `Role` — named role, system flag
- `UserRole` — assignment
- `Permission` — permission code, role, privilege escalation rules
- `RefreshToken` — rotation tracking, reuse detection

**Rule:** Only `usp_User_GetForLogin` and `usp_User_Register` may touch password material.

### CMS Schema

- `Content` — title, slug, content type (snippet, article, checklist item)
- `ContentTranslation` — translatable copy (en-GB, other langs)
- `ContentVersion` — complete snapshot as JSON, immutable
- `Approval` — approver, timestamp, version id
- `ContentPublished` — pointer to the approved version clients read
- `ContentSchedule` — targeting (country, week, season, app version)

**Rule:** `usp_Content_GetForClient` reads text from `ContentVersion` snapshots, not from live `ContentTranslation` rows.

### Access Schema

- `Permission` — permission code, role relationship
- `AuditLog` — every state change (append-only)
- `SecurityEvent` — login attempt, permission grant, lock, unlock

**Rule:** Audit is append-only. No update, no delete. Security events are written on refusal (outside the transaction so a rollback does not erase the refusal).

### Health Schema

- `BirthPreference` — user's birth plan
- `HospitalBagItem` — checklist item
- `HospitalBagPhase` — trimester/phase for item visibility
- `ContractionEntry` — contraction logged by the app
- `KickEntry` — fetal movement logged
- `BodyLogEntry` — symptom or observation

### Notifications Schema

- `NotificationTemplate` — email/SMS/push template
- `NotificationCampaign` — scheduled send
- `NotificationSchedule` — when to send
- `NotificationLog` — audit trail of sends

### Configuration Schema

- `FeatureFlag` — on/off switch for a capability, with bucket assignment for gradual rollout
- `Setting` — configurable values (notification quiet hours, content retention, etc.)

---

## Request Lifecycle

```
Client (Flutter/React)
  ↓
  │ HTTP (REST + Bearer token)
  │
  ↓
API Middleware
  ├─ JWT validation
  ├─ Security stamp check (revocation within ~30s)
  ├─ Rate limiting (not yet implemented)
  └─ → 401 SESSION_REVOKED if account was locked
  
  ↓
Controller
  └─ Extract HTTP → CQRS request
  
  ↓
MediatR Pipeline Behaviors (in order):
  ├─ 1. Logging: log request name + actor
  ├─ 2. Authorization: check IRequirePermission
  │       → 403 before validation (leak no field info to unauthorized caller)
  ├─ 3. Feature Flag: check IRequireFeature
  │       → Feature off? 503 or 403 depending on flag intent
  ├─ 4. Validation: FluentValidation
  │       → Validation errors? 400 + details
  ├─ 5. Caching: serve from cache if IRequireFeature marked as cacheable
  │       → Cache hit? return immediately
  └─ 6. Transaction: open SQL transaction (held for minimum time)
  
  ↓
Handler
  └─ Call one repository method
  
  ↓
Repository
  └─ Open connection → EXEC usp_... → materialize result → close
  
  ↓
SQL Server (Stored Procedure)
  └─ State transition rules enforced here
     ├─ Publish requires approval
     ├─ Restore writes forward only
     ├─ Privilege escalation prevented
     ├─ Audit entry written
     └─ Return result set
  
  ↓
Handler
  └─ Return Result<T> (success or failure code + message)
  
  ↓
Transaction Commits
  (if no error)
  
  ↓
Controller
  └─ Convert Result<T> → ApiResponse<T> + HTTP status
  
  ↓
Client
  └─ Parse envelope, switch on failureCode if present
```

---

## Permissions Model

### Permission Structure

Permissions are **not** roles. A permission is a scoped capability: `content.write`, `users.delete`, `audit.read`, etc.

Roles bundle permissions. The portal UI lets administrators:
- Create custom roles
- Assign permissions to roles (subject to privilege escalation rules)
- Assign roles to users

### Privilege Escalation Prevention

**Rule:** You cannot grant a permission you do not hold.

Enforced in:
- `usp_User_AssignRole` — check the assigner holds every permission in the target role
- `usp_Role_SetPermissions` — same check
- C# validation (defense in depth)

Without this rule, granting `users.write` or `roles.write` **is** granting SuperAdmin.

### Authorization in the Pipeline

Every request declares `IRequirePermission`:

```csharp
public sealed class PublishContentCommand : IRequirePermission
{
    public string RequiredPermission => "content.publish";
    // ...
}
```

The `AuthorizationBehavior` checks it before the handler runs:

```csharp
public async Task<TResponse> Handle(
    TRequest request,
    HandleDelegate<TResponse> next,
    CancellationToken ct)
{
    if (request is IRequirePermission { RequiredPermission: var perm })
    {
        var authorized = await _accessRepository.UserHasPermissionAsync(
            _user.Id, perm, ct);
        if (!authorized)
            return Fail(FailureCodes.Forbidden);
    }
    return await next();
}
```

---

## Caching Strategy

### In-Process Cache (IQueryCache)

Queries that read stable data (content, feature flags, permissions) are cached in-process for 30 seconds.

**Behind an abstraction:** `IQueryCache` so Redis can be dropped in later without touching handlers.

```csharp
var content = await _cache.GetOrSetAsync(
    $"content:{id}",
    () => _contentRepository.GetByIdAsync(id),
    TimeSpan.FromSeconds(30));
```

### Why 30 Seconds?

- **Fast enough for most reads.** Avoids the database on repeated access.
- **Short enough for writes.** An editor's change can take up to the TTL to appear on other instances. Acceptable at one instance; wants Redis before horizontal scaling.
- **Operational incident window.** Narrowing distribution during an incident must take effect within ~30s.

### Cache Invalidation

Commands (publishes, approvals, role changes) invalidate the cache:

```csharp
// In a handler after a state change
await _cache.InvalidateAsync($"content:{contentId}");
await _cache.InvalidateAsync("feature-flags"); // clear all flags
```

---

## Audit Trail

**Every** command writes an audit entry. The audit trail records:
- **Who** performed the action (user id)
- **What** they did (command name)
- **When** (UTC timestamp)
- **Before/after state** (for content edits, role changes)
- **Result** (success or failure code)

Audit entries are **append-only.** No update, no delete. Tested by `AuditAppendOnlyTest`.

Used by:
- Compliance (regulatory)
- Incident investigation
- User-facing audit viewer (admin portal)

---

## Error Handling

### Expected vs. Unexpected Failures

**Expected failures** (wrong password, email in use, insufficient permission) return `Result<T>` with a failure code.

```csharp
if (!await _user.VerifyPasswordAsync(password))
    return Result<T>.Fail(FailureCodes.InvalidCredentials, "Password is incorrect.");
```

**Unexpected failures** (database connection dropped, null reference) throw.

```csharp
public async Task<User> GetUserAsync(Guid id)
{
    var user = await _repository.GetAsync(id)
        ?? throw new InvalidOperationException("User not found");
    return user;
}
```

**Why:** Stack traces are meaningful only for real errors. A log file full of "wrong password" entries is noise.

### Failure Codes (Stable Strings)

Failure codes are **not enums**—they are stable strings.

```csharp
public static class FailureCodes
{
    public const string InvalidCredentials = "invalid_credentials";
    public const string Forbidden = "forbidden";
    public const string NotFound = "not_found";
}
```

Clients switch on these. Renumbering an enum breaks a shipped app.

---

## For More Detail

| Topic | Document |
|---|---|
| Decisions 1–9 | `Maren-Backend/docs/ADR-001-platform-architecture.md` |
| Security model | `Maren-Backend/docs/SLICE-01-users-access.md` |
| Database schema | `docs/DATABASE.md` |
| API endpoints | `docs/API_CONTRACTS.md` |
| Testing strategy | `docs/TESTING.md` |
