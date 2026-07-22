# Platform — Architectural Decisions

Decisions taken while building `Maren.Platform`, with the reasoning, so they
can be revisited deliberately rather than rediscovered.

---

## PD-1 — The mobile app's privacy claims change with sync

**Status:** Recorded, awaiting confirmation · **Owner:** Product / Legal

The shipped mobile app states, on its About screen and in its store listing:

> "there is no network code in Maren at all. Nothing you type can leave the
> device, because there is nothing here that could send it."

Plus: no account, no analytics, no third parties, `allowBackup=false` justified
by the health database never leaving the device, and a Data Safety form
answering "No collection" across every category.

Syncing health data to this platform makes each of those untrue. That is not a
copy change, it is a change of regulatory posture:

| Area | Change |
|---|---|
| Play Data Safety | Must declare collection of Health and fitness, Personal info, Device IDs |
| Privacy policy | Rewrite; currently states nothing leaves the device |
| GDPR | Maren becomes a data controller — lawful basis, DPA with hosting, breach notification, erasure across systems and backups |
| HIPAA | Becomes a live question if US healthcare providers ever access shared summaries via the `Doctor` role |
| ASO | Offline-first is currently the stated differentiator against Flo |

**The schema is built so this is a choice, not a consequence.** Sync is
opt-in by design: `Identity.User` supports an account, but no `Health` row
requires one to exist locally. A user who never registers keeps a fully local
app, and the mobile client's existing local-first storage remains the source of
truth until they opt in.

**Needed:** confirmation of whether cloud sync is opt-in (recommended) or
mandatory. Everything else can proceed either way.

---

## PD-2 — Stored procedures only, no inline SQL in repositories

`Maren.Persistence` contains one inline query (the admin flag list) and
otherwise calls procedures exclusively.

The payoff is a permission boundary that actually holds: the API's SQL login
can be granted `EXECUTE` on specific schemas and **no table permissions at
all**. A leaked connection string then cannot `SELECT * FROM
Identity.[User]`, because the login has no rights to the table — only to the
procedures that expose a curated projection of it.

The remaining inline query is admin-only and reads a table with no personal
data. It should still move to a procedure before the admin portal ships.

---

## PD-3 — Feature flag rollout is a stable hash, not random

`RAND()` re-rolls per call: a user sees a feature, closes the app, and it is
gone. The bucket is `ABS(CHECKSUM(HASHBYTES('SHA2_256', key + '|' + userId))) % 100`.

Verified against 2000 users: 50.25% inclusion at a 50% rollout, identical
across repeated calls, and raising 50 → 80 adds users without removing any.

`HASHBYTES` rather than bare `CHECKSUM` because `CHECKSUM` clusters badly on
sequential GUIDs and would put most of a cohort in the same bucket.

---

## PD-4 — Version comparison is numeric

`fn_VersionToCode` exists because string comparison sorts `"1.10.0"` before
`"1.9.0"`. A minimum-version gate built on string comparison would let through
precisely the builds it was meant to block. Mirrored in C# as
`VersionCode.Parse` so the API can send an integer the database can index on.

---

## PD-5 — Access tokens are short and carry permissions

Permissions travel as `perm` claims so authorisation needs no database round
trip per request. The cost is staleness: a revoked permission applies at the
next refresh, not immediately.

That trade is only acceptable because the access token lives 15 minutes.
`ClockSkew` is set to zero — the default five-minute grace is a meaningful
extension of a fifteen-minute token.

---

## PD-6 — Refresh token reuse burns the chain

A refresh token presented twice is either a race or a theft, and the two are
indistinguishable server-side. `usp_RefreshToken_Redeem` revokes **every** live
token for that user and writes a `RefreshToken.ReuseDetected` audit row.

A legitimate client recovers by logging in again. A thief loses the session
immediately. Silently issuing a new token would leave an attacker with
indefinite access.

Only the SHA-256 hash is stored, so a leaked table yields nothing replayable.

Verified: rotation works, replaying the old token returns `TOKEN_REUSED`, and
the newly issued token is dead too.

---

## PD-7 — Login is indistinguishable for unknown accounts

`usp_User_GetForLogin` returns the same shape whether or not the account
exists, and `LoginHandler` computes a hash even when there is no user, so
"no such account" is not measurably faster than "wrong password".

Both return `INVALID_CREDENTIALS` / HTTP 401. An endpoint that reveals whether
an address is registered lets anyone enumerate users of a pregnancy app.

Verified: both paths return identical status and failure code.

---

## PD-8 — `usp_User_GetForLogin` returns six columns

It originally returned twelve, including email, security stamp and country —
none of which the verifier used. Every extra column is account data crossing a
process boundary on an **unauthenticated** path, where the caller has proved
nothing.

Found because Dapper could not materialise the six-field record from twelve
columns. The fix narrowed the procedure rather than widening the record.

---

## PD-9 — PBKDF2, with a per-row iteration count

Not Argon2 or bcrypt, both stronger per unit of work. PBKDF2 is in the
framework with no native dependency, which matters for a service that must run
identically on a developer laptop, a Linux container and App Service.

The iteration count (currently 210,000) is stored per row, so raising it does
not invalidate existing accounts — `Verify` reports `NeedsRehash` and the login
path upgrades the stored hash on the next successful sign-in, the one moment
the plaintext is legitimately in hand.

Comparison is `CryptographicOperations.FixedTimeEquals`.

---

## PD-10 — Swashbuckle replaced by the framework's OpenAPI

.NET 10 ships OpenAPI document generation. Swashbuckle 6.x pulls
`Microsoft.OpenApi` 1.x, which conflicts with the 2.x that
`Microsoft.AspNetCore.OpenApi` already brings in — the build fails on
`Microsoft.OpenApi.Models` not existing.

Using `AddOpenApi()` with Scalar for the UI avoids carrying two incompatible
versions of the same library.

---

## PD-11 — Scripts set their own SET options

`SET QUOTED_IDENTIFIER ON` is at the top of every deployment script rather than
being left to the client. The filtered indexes require it, `sqlcmd` defaults it
off, and a schema that deploys from SSMS but not from a CI runner is a schema
that breaks on the day it matters.

Note for any new client: writes to `Identity.[User]`, `Health.DailyLog` and
`Health.Symptom` require `QUOTED_IDENTIFIER ON` because of their filtered and
computed-column indexes. .NET `SqlClient` sets it on by default.

---

## Verified end to end

Against SQL Server 2025 LocalDB with the API running:

- register → 200, user created, `Member` role assigned, audit row written
- duplicate email → 409 `EMAIL_IN_USE`
- wrong password → 401 `INVALID_CREDENTIALS`
- unknown account → 401 `INVALID_CREDENTIALS` (identical)
- short password → 400 with a field-level validation message
- login with device → 200, device row upserted
- refresh → 200, new token differs from the old
- replay old token → 401 `TOKEN_REUSED`, whole chain revoked
- bootstrap at v1.5.0 → `cloud_sync` off (version gate)
- bootstrap at v2.1.0 → `cloud_sync` on
- admin flags without a token → 401
- admin flag write as a Member → 403 `FORBIDDEN`
- audit log contains register, login success, login failure, 2 reuse
  detections, 3 flag upserts
