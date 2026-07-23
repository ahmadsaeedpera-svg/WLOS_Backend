# Security & Compliance

Authentication, authorization, data protection, regulatory compliance.

---

## Authentication

### JWT Tokens

**Access Token**
- Issued on login, expires in 15 minutes
- Signed with HMAC-SHA256
- Payload: UserId, email, roles
- Sent in `Authorization: Bearer` header
- Stateless (API verifies signature, no DB lookup)

**Refresh Token**
- Opaque random string (not a JWT)
- Stored SHA-256 hashed in database
- Expires in 30 days
- Single-use (rotated on every use)
- Reuse detected (if same token used twice, treat as compromise)

**Rotating refresh tokens:**
```
Client: POST /auth/login → get (access_token, refresh_token)
After 15 min:
Client: POST /auth/refresh { refresh_token } → get new (access_token, refresh_token)
Database: Old token marked as "replaced by", new token stored
After 30 days:
Token expires, user must login again
```

**Reuse detection:**
```
Client A: POST /auth/refresh { token_X }
Database: Mark token_X as "used", return token_Y
Client B (attacker): POST /auth/refresh { token_X }  ← same token
Database: Detect reuse, invalidate session, return 401
User is signed out and notified (within ~30s via security stamp)
```

### Password Hashing

**Algorithm:** PBKDF2-HMAC-SHA256
**Iterations:** 210,000 (per-row count, not global—allows gradual upgrade)
**Salt:** Random per user
**Comparison:** Fixed-time comparison (prevents timing attacks)

**Never stored unencrypted.** Only procedures `usp_User_Register` and `usp_User_GetForLogin` ever touch `PasswordHash`.

### Account Lockout

**Trigger:** Multiple failed login attempts (tuning pending)

**Duration:** Locked until admin unlocks or timer expires (implementation pending)

**Session revocation:** Locking an account immediately ends all live sessions via security stamp

---

## Authorization

### Permission Model

**Permission-based, not role-based.**

```
Permission = "content.write"
Role = {
  name: "ContentEditor",
  permissions: ["content.write", "content.read"]
}
User → Role → Permissions
```

**Why:** A role is a mutable bundle. Code checking `role == "Editor"` breaks the moment an admin creates "Editor2". Checking permissions survives role restructuring.

### Privilege Escalation Prevention

**Rule:** You cannot grant a permission you do not hold.

**Enforced in:**
- `usp_User_AssignRole` — Check: does assigner have every permission in target role?
- `usp_Role_SetPermissions` — Same check
- C# validation (defense in depth)

**Without this:**
- Granting `users.write` = granting SuperAdmin
- Granting `roles.write` = granting SuperAdmin

### Authorization in Pipeline

Every request declares `IRequirePermission`:

```csharp
public class PublishContentCommand : IRequirePermission
{
    public string RequiredPermission => "content.publish";
}
```

Checked in `AuthorizationBehavior` (runs before validation and handler):

```csharp
var authorized = await _accessRepository.UserHasPermissionAsync(user.Id, perm);
if (!authorized) return Fail("forbidden");
```

**Why pipeline, not handler:**
- Unauthorized caller learns nothing about the request (401 before validation)
- Handler invoked by another handler cannot skip the check
- Consistent enforcement across all handlers

### Separation of Duties

**ContentEditor** → `content.write` (write articles)
**ContentApprover** → `content.review` (approve articles for publish)

An editor who can also approve can approve their own changes by editing after approval. The gate still passes because the pointer names an approved snapshot—the snapshot would simply no longer match the reviewed version.

**SuperAdmin** holds both. Audited.

---

## Session Management

### Security Stamp

Used for fast session revocation when an account is locked.

**Mechanism:**
- Every user has a `SecurityStampId` (GUID)
- Middleware checks the stamp on every request
- Stamp version incremented on lockout/forced logout
- Old stamp becomes invalid (session ends within ~30s)

**Benefit:** No database query on every request (just version check via JWT).

**Trade-off:** Up to ~30s before old session ends (stamp cache TTL).

### Access Token in Memory (Portal)

**Why:** Prevents XSS from stealing the token via `localStorage`.

**Trade-off:** Browser refresh signs you out.

**Long-term fix:** Move refresh token to `SameSite=Strict`, `HttpOnly` cookie (pending API change).

---

## Data Protection

### Data in Transit

- **HTTPS required** (production)
- **TLS 1.3 minimum** (no older)
- **CORS configured explicitly** (never `AllowAnyOrigin`)
- **No token in URL** (only `Authorization` header)

### Data at Rest

**SQL Server encryption:**
- Backup exclusion on mobile (health data never leaves device)
- Encryption at rest (database files encrypted on disk)

**Audit trail:** Immutable, append-only, never encrypted (for regulatory access)

### Health Data Privacy

**Mobile (offline-first):**
- All user data stays on device
- No sync until PD-1 is resolved and backend capability added
- Backup disabled via `allowBackup=false`
- Data accessible only to the user

**Backend (if sync enabled):**
- GDPR applies (user data controller)
- Lawful basis: user consent
- Data subject rights: access, deletion, export
- Data processing agreement (if healthcare partnership)

### Passwords

**Never logged.** Query logs, error messages, crash reports never mention passwords.

Only login handlers touch password material.

---

## Audit Trail

**Every state change is recorded.** Immutable, append-only.

```json
{
  "logId": 12345,
  "actorUserId": "uuid-of-operator",
  "commandName": "PublishContentCommand",
  "entityType": "Content",
  "entityId": "content-uuid",
  "beforeState": { "title": "Old", "status": "draft" },
  "afterState": { "title": "New", "status": "published" },
  "occurredUtc": "2026-07-23T14:30:45Z",
  "succeeded": true
}
```

**Used for:**
- Regulatory compliance (audit trail required for FDA)
- Incident investigation (who made what change)
- User-facing audit viewer (operators see what was changed)

**Protected:**
- Append-only (test verifies no update/delete)
- Actor identification (user ID, not IP—prevents spoofing)
- Timestamp (UTC, atomic)
- Before/after state (full history, not diffs)

---

## Security Events

Separate from audit trail. Recorded on refusal (login failure, permission denied, lockout).

**Why separate:** Written outside the transaction, so a rollback doesn't erase evidence of an attack.

**Examples:**
- Login failure (wrong password)
- Permission denied (insufficient authorization)
- Account lockout (too many failed attempts)
- Privilege escalation attempt (denied)

---

## Compliance

### FDA General Wellness Exclusion

**Scope:** The mobile app is regulated as a general wellness product, not a medical device.

**Requires:**
- No threshold-driven alerts (contraction timer has no "time to hospital")
- No clinical interpretation (body log shows data, not insights)
- No outcome claims (articles describe, never prescribe)
- Plain language (not clinical terminology)

**Guards verify:**
- `no_interpretation_test.dart` — No advice in the five constrained modules
- `analytics_event_test.dart` — No health data disclosed in events
- Wellness articles follow same standard

**Release blocker:** RC-2 (FDA wording audit of all strings)

### GDPR

**Status:** Currently compliant (no data collection).

**If sync enabled (PD-1):** Will require:
- Lawful basis statement (user consent)
- Privacy policy rewrite
- Data processing agreement (if hosting on European servers)
- Data subject rights (access, deletion, export)
- Breach notification procedure

### HIPAA

**Status:** Not applicable (no healthcare provider data).

**If clinician role enabled:** Will require legal review.

### Play Store Data Safety

**Current:** All "No collection" declarations (offline app)

**If sync enabled:** Must update:
- Health & fitness data (yes, collected)
- Personal info (yes, email if registered)
- Device IDs (yes, for analytics if added)

**Blocked on:** PD-1 decision

---

## SQL Injection Prevention

**No inline SQL.** All queries are named stored procedures. Parameters are passed as `SqlParameter`:

```csharp
using (var cmd = new SqlCommand("usp_Content_Search", connection))
{
    cmd.CommandType = CommandType.StoredProcedure;
    cmd.Parameters.AddWithValue("@query", query);  // SQL Server escapes
    // ...
}
```

---

## XSS Prevention (Portal)

**React escapes by default.** Dangerous operations:

- `dangerouslySetInnerHTML` — Never used (content is versioned, safe HTML generated server-side)
- `innerHTML` — Never used
- URL construction — Using `<Link>` (React Router), not `href=""` with variables

**Content Security Policy:** Could be added to static host headers (future hardening)

---

## CSRF Prevention (Portal)

**SameSite cookies:** Refresh token in SameSite cookie (not yet implemented).

**Alternative:** Access token in memory + refresh from `HttpOnly` cookie prevents CSRF on login.

---

## Secrets Management

**Development (committed):**
- `appsettings.Development.json` contains LocalDB connection string and a dev-only signing key
- This file is committed (safe, dev-only values)

**Production (not committed):**
- Connection strings via environment variable or secret store
- JWT signing key via Azure Key Vault or equivalent
- No `.env.local` or `.env.production` in repo

**Mobile app:**
- No secrets in source (no API keys, no signing keystores)
- Keystore signed at build time (separate process)

---

## Rate Limiting

**Status:** Schema designed, not yet implemented.

**For future:**
- Limit login attempts (prevent brute force)
- Limit API calls per user per minute (prevent scraping)
- Limit large result sets (prevent memory exhaustion)

---

## Third-Party Security

**No external service calls (yet):**
- No analytics vendors (Segment, Mixpanel)
- No CDN (assets served from API)
- No Firebase Analytics (standalone app only)
- No Sentry (app-level error handling only)

**If adding:**
- Vendor review (data handling, security posture, SOC 2)
- Data processing agreement required

---

## Security Incident Response

**If a breach is discovered:**

1. **Immediate:** Disable affected accounts, rotate secrets
2. **Preserve:** Audit trail (investigate what was accessed)
3. **Notify:** Users within 72 hours (GDPR requirement)
4. **Report:** Relevant regulators (GDPR, state AGs if US)
5. **Remediate:** Fix the vulnerability, deploy fix
6. **Postmortem:** Document what happened and how to prevent it

---

## For More Information

- **Architecture:** `docs/ARCHITECTURE.md` (permission model details)
- **Authentication:** `Maren-Backend/CLAUDE.md` (§5 Coding standards → Security)
- **Audit trail:** `docs/DATABASE.md` (Audit schema)
- **Compliance:** `Maren-Frontend/RELEASE_BLOCKERS.md` (RC tasks)
