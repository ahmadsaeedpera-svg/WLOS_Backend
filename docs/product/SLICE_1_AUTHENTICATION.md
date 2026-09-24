# Slice 1 — Authentication and the user foundation

**Status:** COMPLETE. Reviewed and accepted 23 September 2026.
**Scope kept:** authentication, identity, sessions, profile ownership, account
lifecycle, API authorization. Nothing about preferences, check-ins, memories or
the Today recommendation engine — those are later slices and were deliberately
not started.

---

## 1. What already existed, and what did not

The backend had more than the survey suggested, and the app had nothing.

| | Before | After |
|---|---|---|
| Register / login / refresh | Endpoints, handlers, procedures — all working | Unchanged, plus a date of birth and the age gate |
| Logout | **Nothing.** Sessions could be revoked wholesale by an administrator; a woman signing out on her own phone had no procedure to call | `POST /api/v1/auth/logout`, one device or all |
| Account deletion | **Nothing** | `DELETE /api/v1/me`, hard |
| Age gate | **Nothing.** 18+ was a claim in a document | `Identity.fn_MinimumAge()`, enforced in two procedures |
| Profile | `GET`/`PUT /api/v1/me/profile`, resolving the user from the token | Unchanged |
| **App authentication** | **Nothing at all.** `ContentApi` issued anonymous GETs and that was the whole network layer | `core/auth/`, `features/auth/`, the gate |
| Auth integration tests | **Nothing.** See §6 | 19 |

## 2. The flow

```
register ─┐
          ├─► access token (15 min, JWT, carries perms + security stamp)
login ────┘   refresh token (opaque, 30 days, SHA-256 hashed at rest)
                    │
                    ├─ refresh ──► rotates BOTH; the old refresh token is revoked
                    │              replaying a spent one = compromised chain,
                    │              every session on the account ends
                    │
                    ├─ logout ───► revokes this refresh token, or all of them
                    │
                    └─ DELETE /me ► password re-verified, then erasure
```

## 3. How the authenticated user is resolved

**Server-side, from the token, always. No endpoint accepts a user id.**

`HttpCurrentUser` (in `Program.cs`) reads `ClaimTypes.NameIdentifier` / `sub`
off `HttpContext.User`. Controllers do `if (currentUser.UserId is not { } userId)
return Unauthenticated();` and pass that id into the command. The route is
`/api/v1/me` — there is no `{userId}` segment to tamper with, and the request
bodies (`LogoutRequest`, `DeleteAccountRequest`) carry no identifier.

`LogoutCommand` and `DeleteAccountCommand` take a `Guid UserId`, and the only
thing that constructs them is a controller that got it from the token.

Verified over HTTP: two accounts created, the first account's token queried
`/api/v1/me/profile` and returned its own row, never the second's.

One place this is enforced in the database as well: `usp_RefreshToken_Revoke`
takes the user id *and* the token hash and refuses a token that belongs to
someone else. The hash alone would be enough to find the row, so revoking by
hash alone would let anyone holding a stolen hash sign its owner out.

## 4. Schema changes

One new script, `69_Procs_Identity_Account.sql`. Numbered 69 because
`78_AuditContract_Apply.sql` must stay last. Applied three times in a row to
prove idempotence.

| Object | What |
|---|---|
| `fn_MinimumAge()` | The launch age, in one place. Returns 18. |
| `fn_IsOfMinimumAge(@dob)` | `DATEADD` on the date of birth, not `DATEDIFF(YEAR,…)`. `DATEDIFF` counts year boundaries crossed, so someone born 31 Dec 2008 would read as 18 on 1 Jan 2026 — a fortnight early, wrong in the direction that matters. A NULL date of birth is not of age. |
| `usp_User_Register` | Redefined: `@DateOfBirth` required, gate applied, DOB written to `Identity.Profile` |
| `usp_Profile_Save` | Redefined: the same gate, because registration is not the only door |
| `usp_User_SetPassword` | New. For the rehash-on-login upgrade (§7) |
| `usp_User_GetLoginMaterial` | New. Verify a password by user id for an already-authenticated caller |
| `usp_RefreshToken_Revoke` | New. Logout, with the ownership check |
| `usp_User_DeleteAccount` | New. The erasure |
| `FK_SecurityStampRevocation_User` | **Dropped** (§5) |

## 5. Deletion, and the three rules it collided with

The constitution: *"She can delete everything, and deletion means deletion —
not a flag."* Every one of the 87 tables in this database soft-deletes.

`usp_User_DeleteAccount` removes every row naming her across **30 tables** in
foreign-key order, inside one transaction. The test asserts zero remaining rows
by scanning `sys.columns` for `UserId` rather than against the list inside the
procedure — a table added later and forgotten in the cascade fails the test
instead of quietly surviving an erasure.

**It refuses any account holding a role beyond `Member`** (`OPERATOR_ACCOUNT`,
409). Operators are woven into the platform's own history — approvals,
publications, role grants — and erasing one leaves that history pointing at
nothing. Offboarding an operator is a different procedure with different rules.

### The data map, measured not asserted

After an end-to-end deletion, every `uniqueidentifier` column in all 87 tables
was swept for the user id. **It survives in exactly two rows**, both tombstones,
and neither carries anything but an identifier, a random GUID and a timestamp.

**Deleted — 29 tables holding her rows**

| Group | Tables |
|---|---|
| Identity | `Profile`, `User`, `UserRole`, `UserRoleMode`, `UserLifeStage`, `Device`, `RefreshToken` |
| Health | `Pregnancy`, `Cycle`, `DailyLog`, `Symptom`, `BodyMeasurement`, `Appointment`, `HospitalBagItem`, `BirthPreference`, `ShareGrant` |
| Growth | `UserGoal`, `GoalProgress` |
| Inferred about her | `Predict.Predicted`, `Recommend.Assembled`, `Coach.Explained`, `Intelligence.UserStateSnapshot`, `Behaviour.Observation` |
| Timeline | `Timeline.Event` |
| Platform links | `Administration.FeatureFlagAssignment`, `Administration.SupportTicket`, `Content.ContentAuthor` |
| Notifications | `Notifications.Delivery` |
| **Security / AI safety** | **`AI.SafetyEvent`** and her rows in **`Audit.AuditLog`** — see the policy decision below |

**Retained — two rows, both tombstones**

| Row | Contents, verbatim from a real deletion | Why it is not her personal data |
|---|---|---|
| `Identity.SecurityStampRevocation` | `UserId=F7C57B3F-…` `Stamp=E76F54CF-…` `RevokedBy=NULL` `Reason='Account deleted'` | A random GUID paired with an identifier that, after erasure, resolves to nothing — no email, no profile, no device, no entry. It exists so the access token she is still holding dies now instead of in fifteen minutes. Pruned after a day. |
| `Audit.AuditLog` | `Action='User.DeleteAccount'` `ActorUserId=NULL` `ActorKind='system'` `EntityId=<the id>` `IpAddress=NULL` `UserAgent=NULL` `BeforeJson=NULL` `AfterJson=NULL` | Proof that an erasure happened, and nothing else. No actor, no address, no payload. |

Nothing else anywhere holds the identifier. `CreatedBy` / `ModifiedBy` /
`DeletedBy` exist on every table under the audit contract, but a `Member`
account can only create rows it owns, and `usp_User_DeleteAccount` refuses any
account with a role beyond `Member`, so no operator-owned row can name her.

### THE POLICY — CONFIRMED

Reviewed and **confirmed** on 23 September 2026. The alternative — permanently
retaining her AI-safety, clinical and crisis history behind a pseudonymous user
id — was considered and **rejected**: it would make WLOS a system where deleting
an account leaves behind a permanent record of a woman's mood, crisis signals,
clinical scores, refusals, IP addresses and behaviour. That is the specific
outcome this product exists not to produce.

Hard deletion removes her rows from two otherwise-append-only ledgers:

- `Audit.AuditLog` — every action she took, with the IP address it came from
- `AI.SafetyEvent` — her refusals, clinical scores and crisis scores

**The invariant, restated so it is internally coherent** — this replaces the
earlier claim that these tables were globally append-only, which the product
contradicts:

> Operational audit and AI-safety records are append-only **during account
> lifetime**. Account deletion may erase records belonging to the deleted user.
> The deletion operation itself creates only a minimal system tombstone
> containing no personal payload.

**This is not a general mutable-audit system and must not be weakened into one.**
The exception is scoped to account erasure and to nothing else. Four things hold
that scope, and all four are asserted:

| Guard | Where |
|---|---|
| One procedure **by name**, never a relaxed pattern | `access_test.sql` 18, `ai_safety_test.sql` 3, `observability_test.sql` 9 |
| Refuses any account with a role beyond `Member` | `access_test.sql` 18b |
| Deletes only rows **belonging to the erased user**, scoped by `ActorUserId`/`UserId` | `usp_User_DeleteAccount` |
| Appends a tombstone with no personal payload | `Deletion_takes_her_audit_history_and_leaves_a_tombstone` |

A **second** procedure name appearing in any of those three assertions is the
failure mode to watch for. The existence of the erasure path is not.

### The collisions

| Rule | Where enforced | Resolution |
|---|---|---|
| Audit log is append-only | `CLAUDE.md` §4.8, `access_test.sql` 18, `observability_test.sql` 9 | One named exception |
| AI safety ledger is append-only | `ai_safety_test.sql` 3 | One named exception |
| Only two procedures may touch password material | `CLAUDE.md` §4.3, `access_test.sql` 15, `AccessIntegrationTests.cs` | List extended from two to four, each named and justified |

The append-only rule exists so an operator cannot erase evidence of what they
did. That reasoning is about people acting **on** the platform. A woman closing
her own account is the subject of those logs, not an actor in them, and a log
of everything she did is still a record of everything she did.

Three things keep the exception from eroding the rule: it is **one procedure by
name** in every assertion, that procedure **refuses operators**, and it
**appends a tombstone** (`User.DeleteAccount`, actor `system`, no IP) so the
fact of an erasure outlives the account. `access_test.sql` assertion 18b checks
the operator refusal is still there.

**This is the one place Slice 1 changed a rule marked non-negotiable. It should
be confirmed or reversed deliberately.** The alternative — keeping her audit
rows with the user id as a pseudonym and stripping IP addresses — is a
defensible different answer.

### The foreign key that had to come off

`Identity.SecurityStampRevocation` had an FK to `Identity.User`, so erasing her
took her revocation row with it. The stamp validator treats "no row" as
"nothing has invalidated this user", so her still-signed access token **sailed
through the middleware**, reached a handler and came back `PROFILE_NOT_FOUND`
with a 400 — which tells a second device to stay where it is rather than sign
out. Caught by end-to-end testing, not by a unit test.

With the FK gone, deletion leaves a tombstone revocation carrying a fresh random
stamp no issued token can match, and every live session dies at the middleware
with `SESSION_REVOKED` / 401. Tombstones older than a day are pruned, scoped to
orphans so a real revocation on a live account is never touched.

**Known window:** the validator caches revocations for 30 seconds, so a live
token keeps working for up to 30s after deletion. Measured at ~15s in testing.
That is the platform's existing trade for not querying the database on every
request and applies equally to an administrator revoking sessions. Her rows are
already gone by then, so there is nothing to read.

## 6. Two things that were broken before this slice

**The whole test suite could not run.** `TestHost.cs` registered
`ConnectionStrings:MarenPlatform`; the fork renamed the key to `WlosPlatform`.
Every integration test failed at container build with *"Connection string
'WlosPlatform' is not configured"* — 245 tests red for a reason unrelated to
anything under test. The stale key was also in CI, `DEPLOYMENT.md`,
`DEPLOYMENT_PLAN.md` and `PLATFORM_RUNBOOK.md`.

**No auth test had ever run.** `DatabaseFixture` never called
`AddMarenInfrastructure()`, so resolving `RegisterHandler` threw on
`IPasswordHasher` before reaching an assertion. The authentication path was the
one part of the platform with no integration coverage at all, and the cause was
three missing lines.

## 6b. A defect I introduced, and how it was nearly missed

`[AllowAnonymous]` sat on `AuthController` — correctly, for register, login and
refresh — and I added `[Authorize]` to the sign-out action beneath it. **An
attribute farther away wins.** The `[Authorize]` did nothing, and
`POST /api/v1/auth/logout` was not authenticated by the framework at all.

It was not exploitable: the action re-reads the subject claim and returns 401
when it is absent, so the observable behaviour was correct. That is exactly what
made it dangerous — defence in depth was doing the primary job, and the first
refactor of that handler would have removed the only thing guarding the
endpoint.

**Why it was nearly missed:** the compiler said so, as `ASP0026`, on every
build. I had been building with `dotnet build -v q`, which suppressed it, and I
reported "0 warnings, 0 errors" on that basis. The warning only surfaced when a
test run echoed the full build log. **The build output was telling the truth and
the verbosity flag was hiding it.**

The fix moves `[AllowAnonymous]` onto the three actions that genuinely cannot
require a token, so anything added to this controller is authenticated unless it
opts out in its own right. Verified over HTTP: sign-out without a token now
returns 401 with an **empty body** — the framework's challenge — where it
previously returned the handler's JSON envelope. Same status code, completely
different mechanism.

`AuthorizationAttributeTests` (5 tests) now asserts by reflection that sign-out
carries `[Authorize]`, that `AuthController` carries no class-level
`[AllowAnonymous]`, that the three anonymous endpoints declare it individually,
and that `/api/v1/me` requires authentication. The integration tests go through
MediatR and never touch the authorization filter, so they could not have caught
this and still cannot — this class is the only thing that can.

**Standing rule from this:** build without `-v q` when the result is going to be
reported as a warning count.

## 7. Defects fixed in passing

- **Rehash-on-login never worked.** On finding a stored hash below the current
  iteration count, `LoginHandler` called `RegisterAsync` to save the upgrade —
  which found the address already registered, returned `EMAIL_IN_USE` and
  changed nothing. No stored hash has ever been upgraded. Now calls
  `SetPasswordAsync`, which does not rotate the security stamp: the same
  password at a higher work factor is not a credential change and must not sign
  her out mid-login.
- **Dapper cannot send a `DateOnly` as a parameter** — it throws at the point of
  use on a path that compiled cleanly. A `DateOnlyTypeHandler` is registered once
  in `AddMarenPersistence`.
- **Date-of-birth row overflowed at phone width.** Caught by a widget test.
- **Port 5299 made canonical.** `launchSettings.json` said 5366; the docs said
  5199, which is **Maren's** port — following them would have started WLOS on
  top of a live service.

## 7b. Two screens that existed but were not reachable

Caught at acceptance review, not by any test.

**`AccountScreen` was routed to by nothing.** It was written in Slice 1 with
sign-out, sign-out-everywhere and delete-account on it, every test passed, and a
woman using the app could not sign out or close her account. A screen no
navigation reaches is not a feature. It now sits under **Settings → Data &
privacy → Your account**, and only when a platform is configured — a sign-out
row in a build with no session would be a control that does nothing, which is
worse than an absent one because someone looking for a way out would find it and
be unchanged afterwards. Three widget tests cover it, including one that taps
sign-out and asserts the session ends.

**The portal got nothing at all from Slice 1.** The age gate was enforced in the
database and no operator could see whether an account had passed it.
`UserDetail` now shows:

| | |
|---|---|
| **18+ verified / Age not verified** chip | Beside the Locked/Active chip. An account reading "not verified" predates the gate rather than having slipped past it — the distinction an operator needs at a glance. |
| **Active sessions** | Refresh tokens neither revoked nor expired, reading "None — signed out everywhere" at zero. Distinct from devices, which is every device that ever registered. This is the number someone is actually asking for when they report that they think another person is in their account. |
| **Account closure** panel | States that closure is hers to do from inside the app, is not available to operators, removes every row across thirty tables, leaves only a tombstone, and cannot be recovered by support. |

**Deliberately absent: her date of birth.** The gate status is what an operator
needs; her birthday is not, and a support screen that displays one leaks it
every time somebody glances at a shared monitor. `usp_User_GetDetail` returns
`IsAgeVerified` as a computed bit and never the date.

This is now a standing rule in `CLAUDE.md` §6, steps 12–14: every slice ships a
routed mobile screen, an operator screen, and an end-to-end demonstration over
real HTTP.

## 8. The app

| File | Role |
|---|---|
| `core/auth/session.dart` | Session model, failure vocabulary |
| `core/auth/token_store.dart` | Keystore / Keychain. **Never the Drift database** — that is exported to a file she carries between phones |
| `core/auth/auth_api.dart` | The one place credentials cross the network |
| `core/auth/auth_controller.dart` | Owns the session; the only thing that may change it |
| `core/auth/authenticated_client.dart` | Signs every request by construction |
| `features/auth/ui/` | Sign in, create account, the gate, account screen |

**Refreshes are serialised.** Two requests waking on a stale token would both
post the same refresh token; the second arrives after the first has rotated it,
the platform reads a spent token presented twice as a stolen chain, and ends
every session on the account. That failure is indistinguishable from a real
compromise and impossible to explain to the person it happens to.

**Sign-out clears the local session whether or not the server was reachable.**
A sign-out that left the tokens on the phone because the network was down would
be a sign-out that did not sign her out.

**A network failure during refresh does not sign her out.** The tokens are
still valid and the train is in a tunnel.

### Local cache: what is authoritative

The server. The Drift database still holds bundled and downloaded **content**
(published articles, FAQs) and the local tracking features that predate this
slice. Nothing in Slice 1 caches identity beyond the session tokens, and the
profile is read from the API on each request rather than mirrored.

### The gate is conditional — flagged for review

`AuthGate` is active only when `WLOS_API_BASE` is configured. Without one the
app runs as it always has: bundled content, local storage, no account. That
keeps the 489 existing tests and offline development working.

**This is a development affordance, not a shipping configuration.** WLOS is
server-backed by decision. A release build must supply the URL. Worth deciding
in Slice 2 whether the no-URL path should exist at all.

## 9. Instrumentation

Six events added to the closed allowlist in `event_names.dart`:
`account_created`, `sign_in_succeeded`, `sign_in_failed`, `session_refreshed`,
`signed_out`, `account_deleted`.

None carries an email address, a country or a date of birth. `sign_in_failed`
carries a stable reason token and never the address that was tried. The
vocabulary forbids `birth` as a substring, so `AnalyticsService` would refuse a
date-of-birth property at runtime — the screening working as intended, not an
obstacle to route around.

Server-side, every account action writes an `Audit.AuditLog` row recording that
it happened and never what it said. A refused under-age registration writes
**nothing**: recording it would mean keeping a child's email address and date of
birth as the permanent record of having turned her away.

## 10. Tests run

| Suite | Result |
|---|---|
| Backend integration | **24 new** — 19 in `AccountLifecycleTests`, 5 in `AuthorizationAttributeTests` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** — clean uninterrupted run, 10m49s |
| SQL assertion suites | **23 suites, 315 assertions, 0 failures** |
| App unit | **19 new** (`auth_test.dart`) |
| App widget | **10 new** (`auth_gate_test.dart`), 3 of them covering the account screen now that it is reachable |
| App, whole suite | **495 passing**, 3 skipped, analyzer clean |
| Portal | `tsc --noEmit` clean · `npm run build` succeeds |
| Build | `dotnet build` **0 warnings, 0 errors** — verified without `-v q`, see §6b |
| End to end over HTTP | Age gate 422 · register 200 · authenticated profile 200 · no token 401 · ownership · rotation · replay 401 `TOKEN_REUSED` · logout 200 (authenticated) and 401 with an empty body (unauthenticated, framework challenge) · wrong password 401 · erasure 0 rows across 30 tables · tombstone · revoked token 401 `SESSION_REVOKED` |

## 11. The debris table — RESOLVED

An orphan `Content.ContentTargetingRule` table in the local `WlosPlatform`
database caused **2 C# test failures and 3 SQL assertion failures**. It was
debris from a retracted investigation: **0 rows**, referenced by **0
procedures**, created 2026-09-23 11:42 by a manual re-run of script 34 outside
the deployment order. Script 45 drops it by design; it was in no deployment
path.

My first attempt to drop it was refused by the sandbox classifier. I did not
route around it, did not re-run script 45 to achieve the same effect by another
name, and did not weaken any assertion to go green. It was dropped on explicit
authorisation:

```bash
sqlcmd -S localhost -E -d WlosPlatform -Q "DROP TABLE [Content].[ContentTargetingRule];"
```

All five failures cleared. **No test was altered to accommodate it.**

A performance-budget test (`A_client_read_of_the_full_library_stays_within_budget`)
failed at 1150ms against a 1000ms budget on one run and passed on the next
under lighter load. It is environmental, it is not counted above, and it is
not caused by this slice.

## 12. Carried forward — decided, deferred, not forgotten

These were reviewed at Slice 1 acceptance and deliberately deferred. None of
them blocks closing Slice 1; the first two block public launch.

### Password reset — REQUIRED BEFORE PUBLIC LAUNCH

Not a Slice 1 failure: it was never in scope. It is a launch-blocking
capability, because the account now holds real data. Someone who creates an
account, signs out and forgets the password currently has **no recovery path at
all** and the account is permanently inaccessible.

Email confirmation is a separate question to be evaluated on its own, not
bundled with this.

### Production must not silently run unauthenticated

`AuthGate` is active only when `WLOS_API_BASE` is set (§8). The rule going
forward:

- **Development** — no API URL, local/offline mode, acceptable.
- **Production** — no API URL must **fail the build or the launch**, never
  silently produce a release that looks like WLOS but is not connected to the
  WLOS account system.

To be handled in build/release configuration rather than by complicating the
app.

### Revocation-cache propagation window — documented, not redesigned

Deletion and session revocation take effect within the stamp validator's
**30-second cache TTL** (measured ~15s). This is an **existing security
propagation window**, accepted for now because deletion happens first, her rows
are already gone, the token is invalid after expiry, and the final
`401 SESSION_REVOKED` was demonstrated over HTTP.

It stays **explicitly documented as a propagation window**. A future
higher-security operation may warrant immediate invalidation. **Do not redesign
it now.**

### RC-4 compliance — not engineering work, not done

The Play Store Data Safety declaration, the privacy policy and the GDPR record
of processing all describe the old posture (no account, nothing uploaded) and
have to be rewritten for the new one.

### Known maintenance hazard

**Three copies of the append-only assertion** exist — `access_test.sql`,
`ai_safety_test.sql`, `observability_test.sql` — and all three had to be amended
by hand. The next change to that invariant will also have to find all three.
