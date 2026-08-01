# Marén Platform — Administration Guide

**Audience:** operators, support, DevOps, security review.
**Source:** extracted from a deployed database on 2026-08-01, not from memory.
Regenerate the matrix below with the query in §7 after any seed change.

> **This document contains no credentials and must never contain any.**
> If you find a password, key or token in this file, treat it as an incident:
> rotate the secret, then delete it here. §5 explains where secrets actually live.

---

## 1. Access model

Authorization is **permission-based, never role-based in code**. Requests declare
`IRequirePermission`; the pipeline checks it before the handler runs. Nothing in
C# tests for a role name, because a role is a bundle an administrator can change
and code checking for `"ContentEditor"` breaks the moment a second role should
also edit.

Two rules are enforced in the database, not only in the application, so they hold
regardless of who connects:

- **You cannot grant a permission you do not hold.** Enforced in
  `usp_User_AssignRole` via `fn_UserHoldsAllPermissionsOfRole`. Without it,
  holding `roles.write` *is* holding every permission.
- **Audit is append-only.** No procedure updates or deletes `Audit.AuditLog`.

A refused escalation is itself recorded as `Security.EscalationRefused`. Probing
leaves a trail; auditing only successes means the first evidence of an attempt is
the attempt that worked.

---

## 2. Roles as deployed

8 roles, 31 permissions.

| Role | Permissions | Purpose |
|---|---:|---|
| `SuperAdmin` | **31** (all) | Platform administration. Granted by joining the full permission set, not by an enumerated list, so a new permission is covered automatically. |
| `ContentEditor` | 10 | Authors and manages content and media. |
| `ContentApprover` | 5 | Reviews and publishes. Cannot author. |
| `Marketing` | 5 | Notifications and analytics. |
| `SupportAgent` | 3 | Reads user records, handles tickets. |
| `Translator` | 2 | Translates existing content only. |
| `Member` | 0 | Every registered end user. Holds no administrative permission by design. |
| `Doctor` | **0** | **Seeded and unusable — see §6.** |

### Matrix

```
ContentApprover  audit.read, content.publish, content.read, content.review, media.read
ContentEditor    category.manage, content.delete, content.publish, content.read,
                 content.restore, content.translate, content.write,
                 media.manage, media.read, media.write
Marketing        analytics.read, notifications.read, notifications.send,
                 notifications.write, reports.read
SupportAgent     support.read, support.write, users.read
Translator       content.read, content.translate
Member           (none)
Doctor           (none)
SuperAdmin       all 31
```

### Separation of duties

`ContentEditor` holds `content.publish` but not `content.review`. That is
deliberate and safe: `usp_Content_Publish` refuses a version nobody approved, so
an editor can publish only something an approver already reviewed. The gate is
the procedure, not the permission.

Clients read **approved snapshots**, never live tables. `usp_Content_GetForClient`
sources text from the published version's JSON snapshot. It once gated on the
published id but read text from the working copy, so an editor typing into a
published article pushed unreviewed text to every device on the next sync. In a
health app that is a clinical-safety problem before it is a workflow one.

---

## 3. Provisioning an operator

There are **no seeded accounts and no default passwords**. A fresh deployment has
roles and no users.

1. The person creates their own account through `POST /api/v1/auth/register`.
   They choose their own password; nobody else ever knows it.
2. An existing operator holding `users.write` **and every permission of the target
   role** assigns it: `POST /api/v1/admin/users/{id}/roles`.
3. The assignment rotates the target's security stamp, so the new permissions
   take effect on re-authentication rather than whenever their token happens to
   expire.
4. Both the grant and any refusal are written to `Audit.AuditLog`.

**Never share an account.** Audit rows name a user id; a shared login makes every
row unattributable and destroys the value of the trail.

### Deprovisioning

`DELETE /api/v1/admin/users/{id}/roles/{roleId}` removes a role.
`POST /api/v1/admin/users/{id}/revoke-sessions` invalidates live tokens
immediately — do this first when offboarding, or the holder keeps working
access until their refresh token expires.

---

## 4. Authentication

- JWT access tokens, **15 minutes**.
- Refresh tokens are opaque, stored **SHA-256 hashed**, rotated on use.
  **Reuse is detected and treated as compromise.**
- Passwords: PBKDF2-HMAC-SHA256, **210,000 iterations**, per-row iteration count,
  fixed-time comparison.
- Only `usp_User_GetForLogin` and `usp_User_Register` may reference password
  material. A test asserts this across every procedure in the database.

---

## 5. Secrets

Secrets are **configuration, never repository content**.

| Secret | Where it belongs |
|---|---|
| `Jwt:SigningKey` | Environment variable or a managed vault. Minimum 32 characters. The API **refuses to boot in Production without one** — this guard is verified working. |
| Connection string | Environment variable. |
| `MAREN_API_BASE` (mobile) | Build-time `--dart-define`, never compiled in. |

`appsettings.Development.json` holds a LocalDB string and a key explicitly named
`dev-only-…`. It is committed deliberately and is excluded from container images
by `.dockerignore` — a secret that ships is a secret that leaked, whether or not
the process loads it.

---

## 6. Known gaps — read before operating a real deployment

These are verified defects, not theoretical:

1. **No first-administrator path.** `usp_User_Register` grants `Member` only, and
   §1's escalation rule means no account can ever reach `SuperAdmin` through the
   API. **A freshly deployed database is administrable only by hand-written SQL.**
   Tracked as the next backend slice.
2. **`Doctor` role has zero permissions.** It is seeded, assignable, and grants
   nothing. Either give it a permission set or remove it; an assignable role that
   does nothing is a support ticket waiting to happen.
3. **`users.impersonate` is seeded and deliberately unimplemented.** It would mean
   an operator reading symptom logs inside a health app. It needs a consent model,
   a time limit, a user-visible banner and legal review before anyone builds it.
4. **No MFA on administrative roles.**
5. **`UseForwardedHeaders` is never called.** Behind a reverse proxy or tunnel,
   every anonymous caller shares one rate-limit partition.
6. **`usp_User_Erase` is referenced in a comment and does not exist.** GDPR
   erasure is currently not possible.

Items 1, 4, 5 and 6 are prerequisites for any internet-facing deployment.

---

## 7. Regenerating this matrix

```sql
SELECT r.Name + ' :: ' + STRING_AGG(p.Code, ', ') WITHIN GROUP (ORDER BY p.Code)
FROM [Identity].[Role] r
JOIN [Identity].[RolePermission] rp ON rp.RoleId = r.RoleId
JOIN [Identity].[Permission]     p  ON p.PermissionId = rp.PermissionId
GROUP BY r.Name ORDER BY r.Name;
```

Run with `sqlcmd -I` (`QUOTED_IDENTIFIER ON`); without it the filtered indexes
reject the connection.

A drift test asserts the permission catalogue in `PlatformPermissions` and the
seeded rows agree. If they disagree, the seed is authoritative for what is
enforced and the code is authoritative for what is intended — reconcile, do not
guess.
