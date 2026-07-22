# Slice 1 — Users & Access Management

**Status:** Design accepted, implementation in progress
**Date:** 2026-07-22
**Depends on:** Phase 1 CMS (permission model, pipeline, audit)

---

## 1. Why this slice first

`Identity.User`, `Role`, `Permission`, `RolePermission` and `UserRole` all exist.
There is no administration layer over any of them. The consequences today:

- `PLATFORM_RUNBOOK.md` §6 instructs operators to grant a role by writing an
  `INSERT` by hand against production.
- There is no way to lock a compromised account without SQL.
- There is no way to see who changed what, despite `Audit.AuditLog` being
  populated by every CMS write.
- Roles and their permissions cannot be changed at all without a deployment of
  `21_Seed_CMS.sql`.

The standing requirement is that every configurable behaviour is managed through
the Admin Portal without a Play Store update. Access control is the most
security-sensitive configurable behaviour in the platform, and it is currently
the least managed. Everything in later slices — notification senders, analytics
readers, subscription administrators — needs permissions that only this slice can
grant.

---

## 2. Architecture

Standard vertical slice, same layering as CMS:

```
07_Access.sql            tables added by this slice
13_Procs_Access.sql      stored procedures (all data access)
Maren.Domain             AccessRules — invariants expressed once
Maren.Application/Access CQRS commands, queries, validators
Maren.Persistence        AccessRepository (Dapper, ambient connection)
Maren.Api                UsersController, RolesController, AuditController
Maren.Admin portal       Users, Roles, Audit modules
```

No new architectural patterns. This slice deliberately reuses the CMS pipeline
so that authorization, transactions, caching and audit behave identically.

**Mobile integration for this slice: none.** This is an operator-facing
capability. The mobile-facing parts of identity (account deletion, GDPR export)
are deferred to the Privacy slice, because they are blocked on PD-1 — the
shipped app states it has no network code, and account deletion over the network
contradicts that until PD-1 is resolved.

---

## 3. Database design

### 3.1 New tables

**`Identity.SecurityStampRevocation`**

| Column | Type | Notes |
|---|---|---|
| UserId | uniqueidentifier | PK |
| SecurityStamp | uniqueidentifier | the stamp now considered current |
| RevokedUtc | datetime2(3) | |
| RevokedBy | uniqueidentifier NULL | |
| Reason | nvarchar(300) NULL | recorded for the audit trail |

Exists to close the token window described in §5.3. Small by construction — one
row per user, upserted, and only for users who have actually been revoked.

**`Identity.RoleChangeRequest`** — *not built.* Considered and rejected: a
four-eyes approval flow for role grants is real enterprise practice, but with no
notification slice yet there is nothing to tell the second approver a request is
waiting, so it would be a queue nobody watches. Revisit after Slice 2.

### 3.2 Changes to existing tables

None. `Identity.User` already carries `IsLockedOut`, `LockoutEndUtc`,
`IsDeleted`, `SecurityStamp` and `RowVersion`. The slice uses what is there.

### 3.3 Procedures

| Procedure | Purpose |
|---|---|
| `usp_User_Search` | Paged, filtered. Never returns hash, salt or iterations. |
| `usp_User_GetDetail` | Profile, roles, devices, recent activity. Same exclusion. |
| `usp_User_SetLockout` | Lock or unlock, with reason. Revokes on lock. |
| `usp_User_AssignRole` | Grant. Refuses escalation (§5.2). |
| `usp_User_RemoveRole` | Revoke. Refuses self-demotion (§5.2). |
| `usp_User_RevokeSessions` | Force sign-out everywhere. |
| `usp_Role_List` | Roles with permission counts and member counts. |
| `usp_Role_Save` | Create or rename. Refuses to alter a system role's name. |
| `usp_Role_Delete` | Refuses system roles and roles with members. |
| `usp_Role_SetPermissions` | Replace-all. Refuses escalation (§5.2). |
| `usp_Permission_List` | The catalogue, grouped by category. |
| `usp_Audit_Search` | Paged, filtered by actor, entity, action, date. |

**Every procedure names its result columns.** `ProcedureShapeTests` enforces
this; three endpoints shipped returning 500 because of `SELECT *`.

`usp_User_Search` and `usp_User_GetDetail` are the security-critical ones: the
`User` table holds `PasswordHash`, `PasswordSalt` and `PasswordIterations`, and
a `SELECT *` there would put password material on the wire to the browser.

---

## 4. API contracts

All under the standard `ApiResponse<T>` envelope.

### `/api/v1/admin/users`

| Method | Path | Permission | Notes |
|---|---|---|---|
| GET | `/` | `users.read` | `query`, `roleId`, `status`, `page`, `pageSize`, `sortBy`, `sortDescending`. Returns `X-Total-Count`. |
| GET | `/{id}` | `users.read` | Detail with roles, devices, recent audit. |
| POST | `/{id}/lock` | `users.write` | Body: `{ isLocked, reason, lockoutEndUtc? }` |
| POST | `/{id}/roles` | `roles.write` | Body: `{ roleId }` |
| DELETE | `/{id}/roles/{roleId}` | `roles.write` | |
| POST | `/{id}/revoke-sessions` | `users.write` | Body: `{ reason }` |

### `/api/v1/admin/roles`

| Method | Path | Permission |
|---|---|---|
| GET | `/` | `roles.read` |
| PUT | `/` | `roles.write` |
| DELETE | `/{id}` | `roles.write` |
| PUT | `/{id}/permissions` | `roles.write` |
| GET | `/permissions` | `roles.read` |

### `/api/v1/admin/audit`

| Method | Path | Permission |
|---|---|---|
| GET | `/` | `audit.read` |

`actorUserId`, `entityType`, `entityId`, `action`, `fromUtc`, `toUtc`, paging.

### Status codes specific to this slice

| Code | Failure code | Meaning |
|---|---|---|
| 409 | `PRIVILEGE_ESCALATION` | Caller tried to grant what they do not hold |
| 409 | `SELF_DEMOTION` | Caller tried to remove their own access |
| 409 | `SYSTEM_ROLE` | Caller tried to delete or rename a system role |
| 409 | `ROLE_IN_USE` | Role still has members |

---

## 5. Security model

This is the part of the slice that matters. An access-management module with a
hole in it is worse than none, because it looks like a control.

### 5.1 Password material never leaves the database

No read procedure in this slice selects `PasswordHash`, `PasswordSalt` or
`PasswordIterations`. Enforced by named columns and asserted by a test that
executes each procedure and inspects the returned column set.

### 5.2 No privilege escalation, no self-demotion

Two invariants, enforced **in the procedure**, not only in the handler — a
future admin script or import job connects to the database, not to the API.

**You cannot grant a permission you do not hold.** Without this, `roles.write`
is equivalent to `SuperAdmin`: the holder edits any role to include every
permission, or assigns themselves a role that already has them. This is the
single most important rule in the slice.

Concretely: assigning a role is refused unless the caller's own permission set is
a superset of that role's. Setting a role's permissions is refused unless the
caller holds every permission being added.

**You cannot remove your own last administrative role, and you cannot lock
yourself out.** Not a security control — an availability one. It prevents the
failure where the only administrator locks themselves out at 2am and the
recovery path is raw SQL against production.

**System roles cannot be renamed or deleted.** `SuperAdmin` in particular: code
does not check for it, but the seed grants it everything by join, and deleting it
leaves a database nobody can administer.

### 5.3 Revocation takes effect in 30 seconds, not 15 minutes

Permissions are claims in a 15-minute access token. Locking an account or
removing a role would otherwise leave the user fully privileged for up to fifteen
minutes — which for a compromised account or a dismissed employee is the whole
point of the action.

The access token carries the user's `SecurityStamp`. A pipeline behaviour
compares it against a cached user→stamp map with a 30-second TTL, mirroring the
feature-flag evaluator. A mismatch is 401. Lock, role change and force-sign-out
all rotate the stamp and write `SecurityStampRevocation`.

Refresh tokens are revoked immediately and unconditionally on all three actions,
so the session cannot be extended past the current access token regardless.

**Cost:** one cached lookup per authenticated request, and a 30-second window
rather than an instantaneous one. Instantaneous would mean a database read on
every request, which puts a query in front of the entire API to defend against a
30-second exposure. Documented rather than hidden.

### 5.4 Audit is append-only and covers this slice completely

Every command here writes `Audit.AuditLog` with before and after state. There is
no update or delete path to the audit table in any procedure.

Role and lockout changes are audited for the same reason content publishes are:
they change what someone can do to other people's data.

### 5.5 Impersonation is deliberately not built

`users.impersonate` exists as a permission code and stays unimplemented in this
slice.

Impersonation means an operator acting as a user inside a pregnancy health app —
reading symptom logs, notes and dates. Building it needs a consent model, a hard
time limit, a banner the impersonated user can see afterwards, and an audit
record distinguishing operator actions from the user's own. That is its own
slice with its own legal review, not a checkbox on this one. Shipping it as
"log in as user" would be the single largest privacy hole in the platform.

The permission code stays seeded so the eventual slice has somewhere to attach.

---

## 6. Definition of Done

- [ ] `07_Access.sql` and `13_Procs_Access.sql`, idempotent and re-runnable
- [ ] Every procedure names its result columns; no password material selected
- [ ] Domain invariants expressed in `AccessRules`, used by handler and procedure
- [ ] CQRS commands and queries with validators for every input
- [ ] Dapper repository on the ambient connection, sharing CMS transactions
- [ ] All endpoints above, permission-gated through `IRequirePermission`
- [ ] `SecurityStampBehavior` registered; revocation verified to bite within 30s
- [ ] Every command audited with before/after
- [ ] SQL assertion suite for the procedures, re-runnable, all passing
- [ ] xUnit integration tests covering: escalation refused, self-demotion
      refused, system role protected, role in use protected, password material
      absent from every read, revocation effective, audit written
- [ ] Portal modules: Users list, User detail, Roles with permission matrix,
      Audit viewer — permission-filtered
- [ ] Runbook §6 rewritten: grant a role through the portal, not SQL
- [ ] Verified end to end in a browser against a running API
- [ ] Full suite green: xUnit, SQL assertions, portal build

---

## 7. Out of scope, recorded

| Item | Why | Where it goes |
|---|---|---|
| Impersonation | Needs consent model and legal review (§5.5) | Own slice |
| Account deletion / GDPR export | Blocked on PD-1 | Privacy slice |
| Four-eyes role approval | Nothing to notify the approver yet | After Slice 2 |
| SSO / SCIM | No customer requires it yet | Deferred |
| Password reset by operator | Operator-set passwords are an anti-pattern; needs the email sender from Slice 2 | Slice 2 |
