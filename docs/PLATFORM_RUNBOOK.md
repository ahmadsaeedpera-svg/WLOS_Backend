# Maren Platform — setup, API, and deployment

Everything needed to bring the platform up from an empty machine, plus what the
API exposes and what to check before a release.

---

## 1. Prerequisites

| Component | Version used |
|---|---|
| .NET SDK | 10.0.302 |
| SQL Server | 2025 (LocalDB for development) |
| Node.js | 25.x (portal) |
| sqlcmd | ODBC Driver 17+ |

---

## 2. Database

Scripts are numbered and **must run in order**. Every one is idempotent, so
re-running the set converges rather than failing.

```bash
cd Maren.Platform/src/Maren.Database

for f in 01_Schemas.sql 02_Identity.sql 03_Administration.sql 04_Health.sql \
         05_Content_Notifications_Audit.sql 06_CMS.sql 07_Access.sql \
         10_Procs_Administration.sql 11_Procs_Identity.sql 12_Procs_Content.sql \
         13_Procs_Access.sql \n         14_Procs_Config.sql 15_Procs_ContentDelta.sql 16_ContentTaxonomy.sql \
         20_Seed.sql 21_Seed_CMS.sql 22_Seed_FAQ.sql; do
  sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform -i "$f" || break
done
```

**`-I` is required.** It sets `QUOTED_IDENTIFIER ON`, without which the filtered
indexes fail to create. The scripts set it themselves, but sqlcmd's session
default overrides them otherwise.

**No `USE` statement.** The database name is passed with `-d` so a different
environment can name it differently.

### Verifying a deployment

```bash
sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform -i tests/cms_workflow_test.sql
sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform -i tests/access_test.sql
```

Expect `TOTAL: 17  FAILED: 0` and `TOTAL: 19  FAILED: 0`. This is safe against a populated database — it
deletes only its own test keys first, and is re-runnable.

---

## 3. API

```bash
cd Maren.Platform
dotnet run --project src/Maren.Api --urls http://localhost:5199
```

Configuration lives in `appsettings.Development.json`. In any other environment
supply these through the environment or a secret store, never the file:

| Key | Notes |
|---|---|
| `ConnectionStrings:MarenPlatform` | |
| `Jwt:Key` | 32 bytes minimum. Rotating it invalidates every access token. |
| `Jwt:Issuer`, `Jwt:Audience` | |
| `Cors:AdminPortalOrigins` | Array. Named origins only — see below. |

CORS is deliberately **not** `AllowAnyOrigin`. The portal sends a bearer token,
and wildcard-with-credentials is exactly the configuration that lets any site a
signed-in editor visits drive the API as them.

### Health probes

| Endpoint | Touches SQL | Meaning |
|---|---|---|
| `GET /health/live` | No | The process is up. Wire this to the restart probe. |
| `GET /health/ready` | Yes | Returns 503 when SQL is unreachable. Wire this to the load balancer. |

Liveness must not touch the database: a database blip that restarts every API
instance takes the platform down harder than the blip did.

### API reference

Development only, at `/scalar/v1` (OpenAPI document at `/openapi/v1.json`).
Uses the framework's native OpenAPI — **not Swashbuckle**, which conflicts with
.NET 10's `Microsoft.OpenApi` 2.x.

---

## 4. Endpoints

All responses use one envelope:

```json
{ "succeeded": true, "data": {}, "failureCode": null,
  "message": null, "validationErrors": null }
```

### Auth — `/api/v1/auth` (anonymous)

`POST register` · `POST login` · `POST refresh`

Access tokens last 15 minutes. Refresh tokens are opaque, stored SHA-256 hashed,
rotated on use, and reuse is detected and treated as compromise.

### Content administration — `/api/v1/content` (authenticated)

| Method | Path | Permission |
|---|---|---|
| GET | `/` | `content.read` |
| GET | `/{id}` | `content.read` |
| PUT | `/` | `content.write` |
| POST | `/{id}/approve` | `content.review` |
| POST | `/{id}/publish` | `content.publish` |
| POST | `/{id}/unpublish` | `content.publish` |
| DELETE | `/{id}` | `content.delete` |
| GET | `/{id}/versions` | `content.read` |
| POST | `/{id}/restore` | `content.restore` |
| POST | `/{id}/schedule` | `content.publish` |
| POST | `/bulk` | varies by operation |
| GET | `/categories` | `content.read` |
| PUT | `/authors` | `content.write` |
| PUT | `/media` | `media.manage` |

Search supports `query`, `contentType`, `categoryKey`, `status`, `languageCode`,
`authorId`, `tag`, `includeDeleted`, `page`, `pageSize`, `sortBy`,
`sortDescending`. Totals come back in `X-Total-Count` and `X-Total-Pages` as well
as the body.

**Optimistic concurrency.** `GET /{id}` returns an `ETag` derived from the
version number. Send it back as `If-Match` on `PUT` (or set
`expectedVersionNumber`). A stale save returns **409 `VERSION_CONFLICT`** rather
than silently winning.

### Client content — `/api/v1/client/content` (anonymous)

Serves published, approved snapshots with en-GB fallback and country/week/season/
app-version gating. `modifiedSince` gives delta sync; a weak `ETag` gives 304.

Anonymous by design — the published library is what a signed-out user opens the
app to see.

### User administration — `/api/v1/admin/users` (authenticated)

| Method | Path | Permission |
|---|---|---|
| GET | `/` | `users.read` |
| GET | `/{id}` | `users.read` |
| POST | `/{id}/lock` | `users.write` |
| POST | `/{id}/roles` | `roles.write` |
| DELETE | `/{id}/roles/{roleId}` | `roles.write` |
| POST | `/{id}/revoke-sessions` | `users.write` |

### Roles — `/api/v1/admin/roles`

`GET /` · `GET /permissions` (`roles.read`); `PUT /`, `DELETE /{id}`,
`PUT /{id}/permissions` (`roles.write`). Setting permissions is replace-all.

### Audit — `/api/v1/admin/audit`

`GET /` (`audit.read`). Filters: `actorUserId`, `entityType`, `entityId`,
`action` (prefix), `fromUtc`, `toUtc`, paging.

### Feature flags — `/api/v1/admin/flags`

`GET` (`flags.read`) · `PUT` (`flags.write`, full upsert — a partial body blanks
what it omits).

### Status codes

| Code | Meaning |
|---|---|
| 400 | Validation failure; see `validationErrors` |
| 401 | No token, expired, or `SESSION_REVOKED` (the account was locked or signed out) |
| 403 | Authenticated but lacking the permission |
| 404 | Not found, **or** the feature is switched off |
| 409 | `VERSION_CONFLICT`, `DUPLICATE_KEY`, `NOT_APPROVED`, `PRIVILEGE_ESCALATION`, `SELF_DEMOTION`, `SYSTEM_ROLE`, `ROLE_IN_USE`, `LAST_ADMINISTRATOR` |
| 429 | Rate limited (300/min per user or IP) |
| 503 | Transient database fault, or not ready |

403 rather than 401 for a permission denial is deliberate: a 401 sends a client
into a token-refresh loop it can never win.

---

## 5. Admin portal

```bash
cd Maren.Platform/src/maren-admin-portal
npm install
npm run dev          # http://localhost:5173
npm run build        # -> dist/, static hosting
```

`VITE_API_BASE` points at the API. The origin must appear in
`Cors:AdminPortalOrigins`.

A browser refresh signs the operator out. The access token is held in memory
deliberately — `localStorage` is readable by any script that runs on the page,
and this portal can publish to every user of the app. See ADR-001, open items.

---

## 6. Granting access

**Through the Admin Portal**, at *Users*. Find the account, open it, pick a role
under *Roles*, and press **Grant**. Removing a role is the bin icon beside it.
Roles and their permissions are managed at *Roles*.

There is no supported SQL path. Earlier versions of this document gave an
`INSERT` to run against production; that is now wrong, because the escalation
and self-demotion rules live in the stored procedures and the portal is what
routes through them.

### Rules that will refuse you

| Refusal | Why |
|---|---|
| `PRIVILEGE_ESCALATION` | You tried to grant a role including permissions you do not hold. The message names them. Without this rule, `roles.write` would be equivalent to `SuperAdmin`. |
| `SELF_DEMOTION` | You tried to change your own access or lock yourself out. Ask another administrator — this exists so the last admin cannot strand the team. |
| `LAST_ADMINISTRATOR` | The last `SuperAdmin` cannot be removed. Grant somebody else the role first. |
| `SYSTEM_ROLE` | Built-in roles cannot be renamed or deleted. |
| `ROLE_IN_USE` | A role with members cannot be deleted. Remove them first so whose access changes is visible. |

`ContentEditor` cannot approve and `ContentApprover` cannot write. That is
separation of duties (ADR-001 §6), not an oversight — one person holding both
can approve their own work.

### When changes take effect

A role change, a lock, or *Sign out everywhere* rotates the account's security
stamp and deletes its refresh tokens. The API compares each request's token
stamp against a snapshot refreshed every 30 seconds, so access ends within
about half a minute rather than at the end of the 15-minute token life.

Measured end to end on a running instance: a locked account's still-unexpired
token was refused **within 5 seconds**.

Granting a role also signs the user out, so they re-authenticate and pick up
the new permissions rather than waiting out a stale token.

### Locking an account

*Users* → open the account → **Lock account**. A reason is required; it is
recorded and is the first thing anyone asks afterwards. Locking ends every
live session. Unlocking clears the failed sign-in counter, so the account does
not immediately re-lock on one mistyped password.

### Reading the audit trail

*Audit log*. Filter by action prefix (`Content.`, `Security.`, `User.`) or
entity type. Click a row to see the before/after payload.

Refused escalation attempts appear as `Security.EscalationRefused`, highlighted
in red. Those are recorded deliberately: somebody probing for a way to escalate
matters more than somebody who succeeded, because success is too late to detect.

The trail is append-only. Nothing in the platform can edit or delete it, and a
test asserts that across every stored procedure.

## 7. Release checklist

```bash
cd Maren.Platform
dotnet build                                    # no warnings introduced
dotnet test tests/Maren.Tests                   # expect 111/111
sqlcmd -S "$SERVER" -I -d "$DB" -i src/Maren.Database/tests/cms_workflow_test.sql
                                                # expect TOTAL: 17  FAILED: 0
sqlcmd -S "$SERVER" -I -d "$DB" -i src/Maren.Database/tests/access_test.sql
                                                # expect TOTAL: 19  FAILED: 0
cd src/maren-admin-portal && npm run build      # expect clean
```

Then confirm by hand against the deployed instance:

- `/health/ready` returns 200 with `"database":"ok"`
- an anonymous `GET /api/v1/client/content` returns 200
- an authenticated caller without `content.read` gets **403**, not 500
- publishing an unapproved item returns **409**
- editing a published item does **not** change what the client endpoint serves
- an operator without a permission cannot grant it — expect **409
  `PRIVILEGE_ESCALATION`** naming what is missing
- locking an account refuses its existing token within ~30s — expect **401
  `SESSION_REVOKED`**

The published-content check is the property the whole approval workflow exists
to provide, and it has been broken before. The escalation check is what keeps
`roles.write` from being equivalent to full administrative access. Check both
every time.

See also `docs/RELEASE_BLOCKERS.md` — RC-1 through RC-5 are open and gate the
mobile release, not the platform.
