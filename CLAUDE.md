# CLAUDE.md — Maren Platform Backend

Context and rules for AI assistants working in this repository. Read this before
changing anything.

---

## 1. What this repository is

The **Maren Platform** backend: an enterprise health platform for pregnancy and
maternal wellness. ASP.NET Core 10 API, SQL Server, Clean Architecture, CQRS.

**The platform is the product. The mobile app is one client, not the system.**

That framing matters for every decision here. A feature does not exist because a
screen shows it; it exists because the schema, procedures, API, permissions,
audit trail, feature flag and admin surface all exist. Building a mobile screen
against a capability the platform does not have is the specific mistake this
project is organised to prevent.

**Partner repository:** https://github.com/ahmadsaeedpera-svg/Maren-Frontend
(Flutter mobile app + React admin portal). Any change to a DTO in
`src/Maren.Contracts` is a breaking change for that repo — say so in the PR.

---

## 2. Core commands

Run from the repository root.

```bash
# Build
dotnet build

# Test — 240 tests, needs SQL Server reachable (see below)
dotnet test tests/Maren.Tests

# Run the API
dotnet run --project src/Maren.Api --urls http://localhost:5199

# API reference (development only)
#   http://localhost:5199/scalar/v1
```

### Database

There is no EF migration runner. Schema is **numbered SQL scripts, run in
order**, and every one is idempotent.

```bash
cd src/Maren.Database

for f in 01_Schemas.sql 02_Identity.sql 03_Administration.sql 04_Health.sql \
         05_Content_Notifications_Audit.sql 06_CMS.sql 07_Access.sql \
         08_AuditContract.sql 14_Procs_Config.sql \
         10_Procs_Administration.sql 11_Procs_Identity.sql 12_Procs_Content.sql \
         13_Procs_Access.sql 15_Procs_ContentDelta.sql 16_ContentTaxonomy.sql \
         20_Seed.sql 21_Seed_CMS.sql 22_Seed_FAQ.sql \
         30_Indexes_ForeignKeys.sql 31_AI_Safety.sql \
         32_LifeStage.sql 33_Procs_Profile.sql \
         34_ContentTargeting.sql 35_Procs_ContentTargeting.sql \
         36_Timeline.sql 37_Procs_Timeline.sql \
         38_LifeDomain.sql 39_KnowledgeGraph.sql 40_Procs_Knowledge.sql \
         41_Dashboard.sql 42_Procs_Dashboard.sql \
         43_Intelligence.sql 44_Procs_Intelligence.sql \
         45_RuleEngine.sql 46_Procs_RuleEngine.sql 47_Procs_Inspector.sql \
         49_Behaviour.sql 50_Procs_Behaviour.sql 51_Procs_Inspector_Behaviour.sql \
         52_Growth_Goals.sql 53_Procs_Growth_Goals.sql \
         55_Growth_Routines.sql 56_Procs_Growth_Routines.sql 58_Recommendation.sql \
         59_Procs_Recommendation.sql 60_Procs_Inspector_Recommendation.sql 62_Coach.sql 63_Procs_Coach.sql 64_Procs_Inspector_Coach.sql 66_Prediction.sql 67_Procs_Prediction.sql 68_Procs_Inspector_Prediction.sql 70_Operations.sql 71_Procs_Operations.sql 72_AuditContract_Apply.sql; do
  sqlcmd -S "(localdb)\MSSQLLocalDB" -I -b -d MarenPlatform -i "$f" || break
done
```

**Prefer `./ops/db/deploy.sh MarenPlatform`.** It applies this same order, read
from the runbook rather than retyped, and records every script in
`Ops.DeploymentJournal` with its checksum, duration and outcome — so a database
can afterwards say what was applied to it and whether anything failed halfway.
The loop above is kept because it is readable and needs nothing but `sqlcmd`.

**`-b` is mandatory, and was missing here until 2026-07-29.** Without it
`sqlcmd` exits 0 on a T-SQL error, so `|| break` never fires: the loop ran every
remaining script against a broken database and finished looking successful. That
is the failure this whole ordering discipline exists to prevent, and it was
sitting in the documented procedure in four places.

**`-I` is mandatory.** It sets `QUOTED_IDENTIFIER ON`; without it the filtered
indexes fail to create.

**Never add a `USE` statement** to a script. The database name comes from `-d`.

**`69_AuditContract_Apply.sql` must stay last.** It has been 48, 51, 54, 65 and
is now 69 — renumbered each time a script added tables, which is exactly the
case this rule exists for. This paragraph itself said "54" while the file was
already 65, so treat the number here as documentation and
`tests/audit_contract_test.sql` as the check. `08_AuditContract.sql` applies
the audit contract with a cursor over `sys.tables`, and it runs ninth — it
cannot see anything created by the scripts after it. One ordered pass on an
empty server left 19 tables short by 147 columns and 19 filtered indexes,
including `Timeline.Event` and `Intelligence.UserStateSnapshot`. It went
unnoticed for weeks because every verification database had been re-applied
more than once, which picks the later tables up by accident. When you add a
script that creates a table, renumber this one so it stays at the end;
`tests/audit_contract_test.sql` fails if you forget.

### SQL assertion suites

These are not optional. They test rules that live in the database and that no
C# test can reach. There are **20 suites, 277 assertions**; every one runs in CI
and `tests/ci_workflow_test.sh` fails if a suite on disk is missing a CI step.

```bash
sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform -i src/Maren.Database/tests/cms_workflow_test.sql
# expect TOTAL: 17  FAILED: 0

sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform -i src/Maren.Database/tests/access_test.sql
# expect TOTAL: 19  FAILED: 0
```

**Run `index_coverage_test.sql` after adding any table.** A feature's own suite
tests what its author was thinking about; the platform-wide suites catch what
they were not. Both Prediction foreign keys shipped without a supporting index
and none of that feature's twenty assertions noticed.

### Operations

```bash
./ops/db/deploy.sh MarenPlatform                    # apply + record in Ops.DeploymentJournal
./ops/db/backup.sh MarenPlatform                    # full (+ log under FULL recovery), verified
./ops/db/backup.sh MarenPlatform "" --enable-pitr   # switch to FULL recovery, deliberately
./ops/db/restore-drill.sh MarenPlatform <full.bak> [log.trn] [--stopat '<utc>']
```

`MAREN_BACKUP_DIR` is a path **on the SQL Server**, not on the machine running
the script. They are the same host for LocalDB; they are not in production, and
writing a backup somewhere only the client can see is the usual way a backup job
appears to work and produces nothing.

Two rules worth knowing before changing any of this:

- **Verify a restore by behaviour, never by counts.** This section used to say
  "expect 45 tables, 47 procedures". The schema doubled, the numbers went stale
  silently, and a database missing ten whole feature schemas matched them
  exactly. The drill runs `DBCC CHECKDB` and every assertion suite on disk
  against the restored copy instead.
- **A drill that ran no checks cannot be recorded as passing.** A `CHECK`
  constraint on `Ops.RestoreDrill` refuses it. `RESTORE` returning 0 proves the
  file opened, nothing more.

---

## 3. Architecture

```
Maren.Api            Controllers, middleware, DI. HTTP only.
Maren.Application    CQRS handlers, validators, pipeline behaviours, interfaces.
Maren.Domain         Invariants and rules. No dependencies on anything below.
Maren.Contracts      DTOs shared with clients. Changing these breaks the frontend.
Maren.Persistence    Dapper repositories. Calls stored procedures, nothing else.
Maren.Infrastructure Caching, JWT, password hashing, security-stamp validation.
Maren.Shared         Result<T>, failure codes, permission catalogue.
Maren.Database       Numbered SQL scripts and assertion suites.
```

Request flow:

```
Controller → MediatR → [pipeline behaviours] → Handler → Repository → Stored procedure
```

Pipeline order is deliberate and set in `Program.cs`:

```
Logging → Authorization → FeatureFlag → Validation → Caching → Transaction
```

Authorization runs before validation so an unauthorised caller learns nothing
about which fields were wrong. The transaction opens last so it is held for the
shortest possible time.

### Layering rules

- **Controllers contain no business logic.** They translate HTTP to a MediatR
  request and a `Result<T>` back to a status code.
- **Handlers never compose SQL.** They call a repository method.
- **Repositories never contain business rules.** They call one named stored
  procedure and materialise the result.
- **Domain depends on nothing.** If `Maren.Domain` needs a database type, the
  design is wrong.
- **Application must not reference Persistence.** If a type is needed by both,
  it belongs in `Maren.Shared` or `Maren.Contracts`.

---

## 4. Non-negotiable rules

These exist because each was violated once and caused a real defect.

### 4.1 Stored procedures only. No ad-hoc SQL, no ORM query generation

The rules that matter are rules about state transitions — publish requires
approval, restore writes forward, a version is immutable. In application code,
every future caller (reporting job, import script, another service) can bypass
them by writing to the table. In the database they hold regardless of who
connects.

### 4.2 Every procedure that returns a result set names its columns

Never `SELECT *`. Dapper materialises positional records by matching the result
set to the constructor; a table with more columns than the DTO throws at
runtime. **Three endpoints shipped returning 500 on every call** because of
this. `ProcedureShapeTests` executes each procedure for real and a
`sys.sql_modules` scan guards against the pattern returning.

### 4.3 No procedure outside the login path may touch password material

`Identity.User` holds `PasswordHash`, `PasswordSalt`, `PasswordIterations`. Only
`usp_User_GetForLogin` and `usp_User_Register` may reference them. A test
asserts this across every procedure in the database.

### 4.4 Clients read approved snapshots, never live tables

`usp_Content_GetForClient` sources text from the **published version's JSON
snapshot**. It once gated on `PublishedVersionId` but read text from
`ContentTranslation` — the live working copy — so an editor typing into a
published article pushed unreviewed text to every device on the next sync. In a
pregnancy app that is a clinical-safety problem before it is a workflow one.

Targeting (country, week, season, app version) is deliberately read live, so
narrowing distribution during an incident takes effect without a publish.

### 4.5 Authorization is permission-based and enforced in the pipeline

Requests declare `IRequirePermission`. **Never check a role in code.** A role is
a bundle of permissions an administrator can change; code checking for
`"ContentEditor"` breaks the moment a second role should also edit.

Checking on the *request* rather than inside the handler means a handler invoked
by another handler cannot skip it.

### 4.6 You cannot grant a permission you do not hold

Enforced in `usp_User_AssignRole` and `usp_Role_SetPermissions`, not only in C#.
Without it, `roles.write` **is** `SuperAdmin`.

### 4.7 Security events escape the transaction deliberately

`AccessRepository.RecordSecurityEventAsync` opens its own connection. These are
written on the refusal path; the commands are `ITransactional`, so enlisting
would mean the record of an escalation attempt is erased by the very rollback
that attempt caused. This is the **only** deliberate escape from the unit of
work — do not copy the pattern elsewhere.

### 4.8 Audit is append-only

No procedure updates or deletes `Audit.AuditLog`. A test asserts it.

---

## 5. Coding standards

- **C# 13 / .NET 10.** Primary constructors, records, collection expressions,
  file-scoped namespaces.
- **Naming:** `usp_<Area>_<Action>` for procedures, `<Verb><Noun>Command` /
  `<Noun>Query` for CQRS, `I<Name>Repository` for data access.
- **Expected failures return `Result<T>`; unexpected ones throw.** A wrong
  password is a `Result`. A dropped connection is an exception. This keeps stack
  traces meaningful and stops logs filling with users mistyping things.
- **Failure codes are stable strings, never enums.** Clients switch on them and
  a renumbered enum breaks a shipped app that cannot be updated quickly.
- **Never log request bodies.** Content commands carry health-adjacent editorial
  copy. `LoggingBehavior` logs the request name and actor only.
- **Never return a raw SQL exception message.** It names tables and columns.
  `SqlErrorMapper` maps to generic text.
- **Every validator message is written for the person reading it.** "You cannot
  grant users.delete" beats "forbidden" — one is actionable, the other becomes a
  support ticket.

### Security

- JWT: 15-minute access tokens, opaque refresh tokens stored SHA-256 hashed,
  rotated on use, reuse detected and treated as compromise.
- Passwords: PBKDF2-HMAC-SHA256, 210,000 iterations, per-row iteration count,
  `FixedTimeEquals` for comparison.
- Every input is validated by FluentValidation before the handler runs.
- Page sizes are always bounded. An unbounded page size is a denial-of-service
  vector.
- CORS names origins explicitly. **Never `AllowAnyOrigin`** — the portal sends a
  bearer token, and wildcard-with-credentials lets any site an editor visits
  drive the API as them.

---

## 6. Adding a capability

Follow this order. Do not start the next step until the current one is done.

1. **SQL** — tables in a numbered script, procedures in a `1x_Procs_*.sql`,
   assertions in `src/Maren.Database/tests/`.
2. **Domain** — invariants in a `*Rules` class.
3. **Contracts** — DTOs. Remember these are a public contract with the frontend.
4. **Application** — CQRS request, handler, validator; mark
   `IRequirePermission` / `ITransactional` / `IRequireFeature` as appropriate.
5. **Persistence** — repository method on the ambient connection.
6. **API** — controller endpoint. No logic.
7. **Authorization** — add the permission code to `PlatformPermissions` **and**
   seed it. A drift test asserts the two agree.
8. **Audit** — before/after state on every command.
9. **Feature flag** — seed a row if the capability should be switchable.
10. **Tests** — integration tests against the real database.
11. **Docs** — update `docs/PLATFORM_RUNBOOK.md`.

Then the frontend repo can consume it.

---

## 7. Testing

**Integration tests run against a real SQL Server. There are no repository
mocks, deliberately.** Every rule worth testing lives in a procedure; a suite
that mocks `IContentRepository` verifies the mocks and cannot tell you whether
an editor can publish something nobody approved.

- Each test class uses its own key prefix and cleans up on the way in, so the
  suite is re-runnable and order-independent.
- `DatabaseFixture` builds a real DI container over the real connection.
- `SqlUnitOfWork` is `IAsyncDisposable` only — use `CreateAsyncScope()`, not
  `CreateScope()`.

---

## 8. Things not to do

- Do not add Entity Framework or write business logic in C# that belongs in a
  procedure.
- Do not add Swashbuckle. It conflicts with .NET 10's `Microsoft.OpenApi` 2.x.
  The project uses the framework's native `AddOpenApi()` with Scalar.
- Do not build mobile UI or admin screens here — that is the frontend repo.
- Do not implement impersonation. `users.impersonate` is seeded but deliberately
  unimplemented: it means an operator reading symptom logs inside a pregnancy
  app, and needs a consent model, a time limit, a user-visible banner and legal
  review. Shipping it as "log in as user" would be the largest privacy hole in
  the platform.
- Do not commit real secrets. `appsettings.Development.json` holds LocalDB and a
  signing key explicitly named as dev-only.

---

## 9. Open decisions

See `docs/PLATFORM_DECISIONS.md` and `docs/ADR-001-platform-architecture.md`.

**PD-1 is unresolved and blocks mobile integration.** The shipped app's About
screen states there is no network code in Maren. That becomes false the day the
Flutter client talks to this API, and it changes the Play Store Data Safety
declaration and the GDPR posture. The schema is built so sync is opt-in. This
needs a decision before any mobile-integration work ships to a device.
