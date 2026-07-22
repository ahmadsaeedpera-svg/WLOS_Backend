# Security risk register

Known risks that are accepted, deferred or in progress. Every entry names the
exposure, the reason it is tolerable, and the trigger that reopens it.

An accepted risk with no revisit trigger is not accepted — it is forgotten.

**Review cadence:** every milestone completion, and on any change to the
affected component.

---

## Accepted

### SR-001 — `Microsoft.OpenApi` GHSA-v5pm-xwqc-g5wc

| | |
|---|---|
| **Severity** | High (advisory) · **Negligible (as deployed)** |
| **Status** | Accepted, suppressed in CI |
| **Accepted** | 2026-07-22 |
| **Owner** | Platform |

**The advisory.** All published 2.x versions of `Microsoft.OpenApi` carry a
high-severity advisory. No patched version exists. The package arrives
transitively through `Microsoft.AspNetCore.OpenApi`, which is the framework's
own OpenAPI support.

**Why it is tolerable here.** Reachability was assessed, not assumed. The only
code that exercises the package is `MapOpenApi()` and `MapScalarApiReference()`,
and both sit inside `if (app.Environment.IsDevelopment())` in `Program.cs`. No
production request reaches the vulnerable path.

**What was done.** Pinned to the newest 2.x so any unrelated fix is picked up,
then suppressed by advisory id in `Maren.Api.csproj` and `Maren.Tests.csproj`.
Suppressed *by id* rather than by turning `NuGetAudit` off, so every other
advisory still fails the build.

**Revisit when any of these is true:**

- A patched version ships → remove the suppression.
- OpenAPI is exposed outside `Development` → **this becomes live and must be
  fixed before that ships.**
- The advisory is amended to cover a path we do use.

---

## Open — must close before the stated milestone

### SR-002 — Health data is stored unencrypted

| | |
|---|---|
| **Severity** | **Critical** |
| **Status** | Open |
| **Must close by** | M7 — Privacy & Compliance, before M8 |

Pregnancy status, symptoms, appointments and body measurements are stored in
plaintext. No TDE, no Always Encrypted, no column-level encryption. Anyone with
a database backup file has the lot.

Currently mitigated only by the fact that **no production data exists** — the
mobile app has never sent anything to the platform. That mitigation disappears
the moment M8 ships.

### SR-003 — No GDPR erasure or export path

| | |
|---|---|
| **Severity** | **Critical** |
| **Status** | Open |
| **Must close by** | M7, before M8 |

`Identity.User.IsDeleted` is a soft-delete flag, not erasure. There is no way to
satisfy a deletion request, no data export, and no consent ledger. Same
mitigation and same expiry as SR-002.

### SR-004 — Static JWT signing key, no rotation

| | |
|---|---|
| **Severity** | High |
| **Status** | Open |
| **Must close by** | M2 — Operability |

`Jwt:SigningKey` is a single static value. Rotating it invalidates every token
in circulation at once, with no staged rollover, so in practice it will never be
rotated. A leaked key therefore stays valid indefinitely.

Needs multiple valid signing keys with a primary for issuance, plus Key Vault.

### SR-005 — Secrets in configuration files and environment variables

| | |
|---|---|
| **Severity** | High |
| **Status** | Open |
| **Must close by** | M2 |

No Key Vault, no managed identity. Connection strings and signing keys travel as
environment variables, which are readable by any process on the host and appear
in crash dumps.

### SR-006 — Rate limiting is per-instance

| | |
|---|---|
| **Severity** | Medium |
| **Status** | Open |
| **Must close by** | M2 |

The limiter holds state in process. Behind *n* instances the effective limit is
*n* times what is configured, and a restart clears it. Brute-force protection is
therefore weaker than the configuration claims.

### SR-007 — No MFA for administrative roles

| | |
|---|---|
| **Severity** | Medium |
| **Status** | Open |
| **Must close by** | M7 |

An account holding `content.publish` can change what every user of a pregnancy
app reads, and `roles.write` can grant access. Both authenticate with a password
alone.

### SR-008 — One person can author, approve and publish

| | |
|---|---|
| **Severity** | Medium |
| **Status** | Open |
| **Must close by** | M4 |

The approval gate is enforced — publishing refuses without an approval — but a
`SuperAdmin` can supply both halves. Separation of duties holds for
`ContentEditor` and `ContentApprover` and not above them. The stated two-person
approval requirement is not met.

### SR-009 — No field-level permissions

| | |
|---|---|
| **Severity** | Medium |
| **Status** | Open |
| **Must close by** | M7 |

Permissions gate endpoints, not fields. A support agent with `users.read` sees
every column the DTO exposes.

---

## Closed

### SR-000 — Client reads served unreviewed drafts

| | |
|---|---|
| **Severity** | **Critical** (clinical safety) |
| **Closed** | 2026-07-22 |

`usp_Content_GetForClient` gated on `PublishedVersionId` but sourced its text
from `ContentTranslation`, the live working copy. An editor typing into a
published article pushed unreviewed health text to every device on the next
sync, with no approval and no publish event.

Fixed by sourcing text from the published version's JSON snapshot. Assertion
added on what the client actually receives — the prior assertion checked the
pointer, which is why it passed throughout.
