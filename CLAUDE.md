# CLAUDE.md — Maren Platform Backend

Context and rules for AI assistants working in this repository. Read this before
changing anything.

---

## 1. What this repository is

The **Maren Platform** backend. Maren is the product; the platform it implements
is a **Women's Life Operating System** — one account a woman keeps from
adolescence through healthy aging, adapting as her life changes rather than
asking her to change applications. ASP.NET Core 10 API, SQL Server, Clean
Architecture, CQRS.

**Pregnancy is one life stage, not the product.** `Identity.LifeStage` holds
twelve; pregnancy is one row. Anything that treats it as the default — a schema
column, an endpoint, a naming choice, a screen — is a regression, and the schema
has been neutral since `0fcba64`. Menopause, postpartum, breastfeeding and the
rest are specializations under the same rule: no stage owns the platform.

The test for any new capability: does it still make sense for a woman of 16, 24,
35, 48 and 63 — pregnant, never pregnant, or post-menopause? If not, it belongs
behind a life-stage gate.

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

# Test — 264 tests, needs SQL Server reachable (see below)
dotnet test tests/Maren.Tests

# Run the API
dotnet run --project src/Maren.Api --urls http://localhost:5299

# API reference (development only)
#   http://localhost:5299/scalar/v1
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
         59_Procs_Recommendation.sql 60_Procs_Inspector_Recommendation.sql 62_Coach.sql 63_Procs_Coach.sql 64_Procs_Inspector_Coach.sql 66_Prediction.sql 67_Procs_Prediction.sql 68_Procs_Inspector_Prediction.sql 69_Procs_Identity_Account.sql 70_Operations.sql 71_Procs_Operations.sql 72_Procs_Bootstrap.sql 73_Observability.sql 74_AuditContract_Apply.sql; do
  sqlcmd -S "(localdb)\MSSQLLocalDB" -I -b -d WlosPlatform -i "$f" || break
done
```

**Prefer `./ops/db/deploy.sh WlosPlatform`.** It applies this same order, read
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

**`74_AuditContract_Apply.sql` must stay last.** It has been 48, 51, 54, 65, 69
and is now 74 — renumbered each time a script added tables, which is exactly
the case this rule exists for. This paragraph has now been wrong twice: it said
"54" while the file was 65, was corrected to "69" while the file was already
74, and both times the surrounding prose was the only thing that knew. Treat
the number here as documentation and `tests/audit_contract_test.sql` as the
check — it is the only one of the two that fails. `08_AuditContract.sql` applies
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
C# test can reach. There are **23 suites, 315 assertions**; every one runs in CI
and `tests/ci_workflow_test.sh` fails if a suite on disk is missing a CI step.

```bash
sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d WlosPlatform -i src/Maren.Database/tests/cms_workflow_test.sql
# expect TOTAL: 17  FAILED: 0

sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d WlosPlatform -i src/Maren.Database/tests/access_test.sql
# expect TOTAL: 20  FAILED: 0
```

**Run `index_coverage_test.sql` after adding any table.** A feature's own suite
tests what its author was thinking about; the platform-wide suites catch what
they were not. Both Prediction foreign keys shipped without a supporting index
and none of that feature's twenty assertions noticed.

### Operations

```bash
./ops/db/deploy.sh WlosPlatform                    # apply + record in Ops.DeploymentJournal
./ops/db/backup.sh WlosPlatform                    # full (+ log under FULL recovery), verified
./ops/db/backup.sh WlosPlatform "" --enable-pitr   # switch to FULL recovery, deliberately
./ops/db/restore-drill.sh WlosPlatform <full.bak> [log.trn] [--stopat '<utc>']
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
these four procedures may reference them, and a test asserts it across every
procedure in the database:

| Procedure | Why it is on the list |
|---|---|
| `usp_User_GetForLogin` | Verify a password by email — signing in |
| `usp_User_Register` | Set the first password |
| `usp_User_GetLoginMaterial` | Verify a password by **user id**, for an already-authenticated caller confirming something irreversible. The alternative was an authenticated endpoint asking a client for an email address to name an account the token already names. |
| `usp_User_SetPassword` | Replace stored material — the rehash-on-login upgrade |

The list is the credential path, not a convenience allow-list. A procedure that
needs to be added to it is almost always a procedure that should not be reading
password material.

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

### 4.8 Append-only for the account's lifetime; erasable on account deletion

**The invariant, stated precisely:**

> Operational audit and AI-safety records are append-only **during account
> lifetime**. Account deletion may erase records belonging to the deleted user.
> The deletion operation itself creates only a minimal system tombstone
> containing no personal payload.

This replaces an earlier, less accurate claim that these tables were globally
append-only. They never could be, once deletion means deletion — and having
three assertion suites insist on a rule the product contradicts is worse than
naming the boundary. This is **not** a general mutable-audit system, and it must
not be weakened into one.

**Two tables are in scope: `Audit.AuditLog` and `AI.SafetyEvent`. One procedure
may erase from them: `usp_User_DeleteAccount`. That is the whole exception.**

The append-only property is about accountability — an operator must not be able
to erase evidence of what they did. That reasoning covers people acting **on**
the platform. A woman closing her own account is the *subject* of those records,
not an actor in them, and the WLOS constitution is unambiguous: *"she can delete
everything, and deletion means deletion, not a flag."* Deleting an account must
not leave behind a permanent history of her mood, crisis signals, clinical
scores, refusals, IP addresses and behaviour.

Four things keep the exception scoped to account erasure:

- It is one procedure **by name** in every assertion, never a relaxed pattern.
  `access_test.sql` 18, `ai_safety_test.sql` 3 and `observability_test.sql` 9 all
  name it and nothing else.
- That procedure refuses any account holding a role beyond `Member`, so the
  erasure path cannot be turned on an operator — the case the original rule was
  written to prevent. `access_test.sql` 18b asserts the refusal is still there.
- It only ever deletes rows **belonging to the user being erased**, scoped by
  `ActorUserId` / `UserId`. It has no other write path into either table.
- It appends a tombstone (`User.DeleteAccount`, actor `system`, no IP, no user
  agent, no payload) so the fact of an erasure outlives the account.

**During an account's lifetime nothing may update or delete either table.** A
second procedure appearing in any of those three assertions means the rule has
stopped meaning anything — that is the failure mode to watch for, not the
existence of the erasure path.

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

### Every slice ships visible, usable screens. Not just schema.

**Standing rule, set at Slice 1 acceptance.** A slice is not done when the
procedures exist and the tests pass. It is done when a woman can see and use it
in **WLOS_App**, and an operator can see and act on it in **WLOS_FrontEnd**.

This exists because Slice 1 nearly shipped two failures of exactly that kind:

- `AccountScreen` was written with sign-out, sign-out-everywhere and
  delete-account on it, and **nothing routed to it**. Every test passed. A woman
  could not sign out or close her account from the running app. A screen no
  navigation reaches is not a feature.
- The portal got **nothing at all** from Slice 1 — no age-gate status, no
  session state, no statement of what account closure does. The backend rule
  existed and no operator could see it.

So: when you finish the backend steps below, you are half done. Ask what she
sees, what she can tap, and what an operator can see about it. If the answer to
any of those is "nothing yet", the slice is not finished.

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
12. **Mobile screen** — in `WLOS_App`, *and routed to*. A widget test that
    reaches it through the navigation a woman would actually use, not by
    constructing the screen directly.
13. **Operator screen** — in `WLOS_FrontEnd`. What an operator needs to see or
    do about this capability, and no more of her personal data than that needs.
14. **Show it working** — the capability exercised end to end over real HTTP,
    app → authenticated API → database, not only through the handlers.

Steps 12–14 are not optional and not "the frontend repo's job later". A
capability that exists only in the schema is a capability nobody has.

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

**PD-1 was resolved for WLOS and remains open for Maren.**

The question was whether mobile sync is opt-in or mandatory. Maren's shipped
About screen states there is no network code and no account, which the schema
was built to keep true by making sync opt-in. **That answer still stands for
Maren, and Maren is not to be changed.**

WLOS answered it the other way, by decision: Phase 1 is server-backed, an
account is required, and a local cache exists for offline reading, performance
and drafts rather than as the system of record. The consequences were taken
with it rather than left for later —

- The About screen's "there is no account" and "nothing you enter is ever
  uploaded" claims were rewritten in the same change that made them false.
- The launch age is 18+, enforced in `Identity.usp_User_Register` and again in
  `usp_Profile_Save`, not in a validator.
- Deletion is real. `usp_User_DeleteAccount` removes every row naming her
  across thirty tables and is the one named exception to section 4.8.

What this still needs before a store submission: the Play Store Data Safety
declaration, the privacy policy and the GDPR record of processing all describe
the old posture and have to be rewritten for the new one. That is compliance
work (RC-4), not engineering, and it is not done.
