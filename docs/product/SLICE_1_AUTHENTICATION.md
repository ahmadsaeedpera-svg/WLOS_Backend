| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |# Slice 1 — Authentication and the user foundation
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Status:** complete, awaiting review.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Scope kept:** authentication, identity, sessions, profile ownership, account
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |lifecycle, API authorization. Nothing about preferences, check-ins, memories or
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |the Today recommendation engine — those are later slices and were deliberately
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |not started.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |---
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 1. What already existed, and what did not
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |The backend had more than the survey suggested, and the app had nothing.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || | Before | After |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) ||---|---|---|
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Register / login / refresh | Endpoints, handlers, procedures — all working | Unchanged, plus a date of birth and the age gate |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Logout | **Nothing.** Sessions could be revoked wholesale by an administrator; a woman signing out on her own phone had no procedure to call | `POST /api/v1/auth/logout`, one device or all |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Account deletion | **Nothing** | `DELETE /api/v1/me`, hard |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Age gate | **Nothing.** 18+ was a claim in a document | `Identity.fn_MinimumAge()`, enforced in two procedures |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Profile | `GET`/`PUT /api/v1/me/profile`, resolving the user from the token | Unchanged |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || **App authentication** | **Nothing at all.** `ContentApi` issued anonymous GETs and that was the whole network layer | `core/auth/`, `features/auth/`, the gate |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Auth integration tests | **Nothing.** See §6 | 19 |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 2. The flow
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |```
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |register ─┐
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |          ├─► access token (15 min, JWT, carries perms + security stamp)
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |login ────┘   refresh token (opaque, 30 days, SHA-256 hashed at rest)
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |                    │
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |                    ├─ refresh ──► rotates BOTH; the old refresh token is revoked
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |                    │              replaying a spent one = compromised chain,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |                    │              every session on the account ends
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |                    │
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |                    ├─ logout ───► revokes this refresh token, or all of them
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |                    │
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |                    └─ DELETE /me ► password re-verified, then erasure
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |```
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 3. How the authenticated user is resolved
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Server-side, from the token, always. No endpoint accepts a user id.**
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`HttpCurrentUser` (in `Program.cs`) reads `ClaimTypes.NameIdentifier` / `sub`
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |off `HttpContext.User`. Controllers do `if (currentUser.UserId is not { } userId)
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |return Unauthenticated();` and pass that id into the command. The route is
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`/api/v1/me` — there is no `{userId}` segment to tamper with, and the request
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |bodies (`LogoutRequest`, `DeleteAccountRequest`) carry no identifier.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`LogoutCommand` and `DeleteAccountCommand` take a `Guid UserId`, and the only
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |thing that constructs them is a controller that got it from the token.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Verified over HTTP: two accounts created, the first account's token queried
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`/api/v1/me/profile` and returned its own row, never the second's.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |One place this is enforced in the database as well: `usp_RefreshToken_Revoke`
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |takes the user id *and* the token hash and refuses a token that belongs to
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |someone else. The hash alone would be enough to find the row, so revoking by
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |hash alone would let anyone holding a stolen hash sign its owner out.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 4. Schema changes
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |One new script, `69_Procs_Identity_Account.sql`. Numbered 69 because
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`74_AuditContract_Apply.sql` must stay last. Applied three times in a row to
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |prove idempotence.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Object | What |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) ||---|---|
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `fn_MinimumAge()` | The launch age, in one place. Returns 18. |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `fn_IsOfMinimumAge(@dob)` | `DATEADD` on the date of birth, not `DATEDIFF(YEAR,…)`. `DATEDIFF` counts year boundaries crossed, so someone born 31 Dec 2008 would read as 18 on 1 Jan 2026 — a fortnight early, wrong in the direction that matters. A NULL date of birth is not of age. |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `usp_User_Register` | Redefined: `@DateOfBirth` required, gate applied, DOB written to `Identity.Profile` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `usp_Profile_Save` | Redefined: the same gate, because registration is not the only door |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `usp_User_SetPassword` | New. For the rehash-on-login upgrade (§7) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `usp_User_GetLoginMaterial` | New. Verify a password by user id for an already-authenticated caller |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `usp_RefreshToken_Revoke` | New. Logout, with the ownership check |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `usp_User_DeleteAccount` | New. The erasure |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `FK_SecurityStampRevocation_User` | **Dropped** (§5) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 5. Deletion, and the three rules it collided with
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |The constitution: *"She can delete everything, and deletion means deletion —
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |not a flag."* Every one of the 87 tables in this database soft-deletes.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`usp_User_DeleteAccount` removes every row naming her across **30 tables** in
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |foreign-key order, inside one transaction. The test asserts zero remaining rows
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |by scanning `sys.columns` for `UserId` rather than against the list inside the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |procedure — a table added later and forgotten in the cascade fails the test
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |instead of quietly surviving an erasure.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**It refuses any account holding a role beyond `Member`** (`OPERATOR_ACCOUNT`,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |409). Operators are woven into the platform's own history — approvals,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |publications, role grants — and erasing one leaves that history pointing at
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |nothing. Offboarding an operator is a different procedure with different rules.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### The data map, measured not asserted
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |After an end-to-end deletion, every `uniqueidentifier` column in all 87 tables
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |was swept for the user id. **It survives in exactly two rows**, both tombstones,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |and neither carries anything but an identifier, a random GUID and a timestamp.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Deleted — 29 tables holding her rows**
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Group | Tables |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) ||---|---|
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Identity | `Profile`, `User`, `UserRole`, `UserRoleMode`, `UserLifeStage`, `Device`, `RefreshToken` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Health | `Pregnancy`, `Cycle`, `DailyLog`, `Symptom`, `BodyMeasurement`, `Appointment`, `HospitalBagItem`, `BirthPreference`, `ShareGrant` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Growth | `UserGoal`, `GoalProgress` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Inferred about her | `Predict.Predicted`, `Recommend.Assembled`, `Coach.Explained`, `Intelligence.UserStateSnapshot`, `Behaviour.Observation` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Timeline | `Timeline.Event` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Platform links | `Administration.FeatureFlagAssignment`, `Administration.SupportTicket`, `Content.ContentAuthor` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Notifications | `Notifications.Delivery` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || **Security / AI safety** | **`AI.SafetyEvent`** and her rows in **`Audit.AuditLog`** — see the policy decision below |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Retained — two rows, both tombstones**
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Row | Contents, verbatim from a real deletion | Why it is not her personal data |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) ||---|---|---|
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `Identity.SecurityStampRevocation` | `UserId=F7C57B3F-…` `Stamp=E76F54CF-…` `RevokedBy=NULL` `Reason='Account deleted'` | A random GUID paired with an identifier that, after erasure, resolves to nothing — no email, no profile, no device, no entry. It exists so the access token she is still holding dies now instead of in fifteen minutes. Pruned after a day. |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `Audit.AuditLog` | `Action='User.DeleteAccount'` `ActorUserId=NULL` `ActorKind='system'` `EntityId=<the id>` `IpAddress=NULL` `UserAgent=NULL` `BeforeJson=NULL` `AfterJson=NULL` | Proof that an erasure happened, and nothing else. No actor, no address, no payload. |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Nothing else anywhere holds the identifier. `CreatedBy` / `ModifiedBy` /
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`DeletedBy` exist on every table under the audit contract, but a `Member`
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |account can only create rows it owns, and `usp_User_DeleteAccount` refuses any
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |account with a role beyond `Member`, so no operator-owned row can name her.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### THE POLICY — CONFIRMED
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Reviewed and **confirmed** on 23 September 2026. The alternative — permanently
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |retaining her AI-safety, clinical and crisis history behind a pseudonymous user
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |id — was considered and **rejected**: it would make WLOS a system where deleting
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |an account leaves behind a permanent record of a woman's mood, crisis signals,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |clinical scores, refusals, IP addresses and behaviour. That is the specific
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |outcome this product exists not to produce.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Hard deletion removes her rows from two otherwise-append-only ledgers:
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |- `Audit.AuditLog` — every action she took, with the IP address it came from
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |- `AI.SafetyEvent` — her refusals, clinical scores and crisis scores
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**The invariant, restated so it is internally coherent** — this replaces the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |earlier claim that these tables were globally append-only, which the product
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |contradicts:
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |> Operational audit and AI-safety records are append-only **during account
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |> lifetime**. Account deletion may erase records belonging to the deleted user.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |> The deletion operation itself creates only a minimal system tombstone
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |> containing no personal payload.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**This is not a general mutable-audit system and must not be weakened into one.**
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |The exception is scoped to account erasure and to nothing else. Four things hold
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |that scope, and all four are asserted:
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Guard | Where |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) ||---|---|
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || One procedure **by name**, never a relaxed pattern | `access_test.sql` 18, `ai_safety_test.sql` 3, `observability_test.sql` 9 |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Refuses any account with a role beyond `Member` | `access_test.sql` 18b |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Deletes only rows **belonging to the erased user**, scoped by `ActorUserId`/`UserId` | `usp_User_DeleteAccount` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Appends a tombstone with no personal payload | `Deletion_takes_her_audit_history_and_leaves_a_tombstone` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |A **second** procedure name appearing in any of those three assertions is the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |failure mode to watch for. The existence of the erasure path is not.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### The collisions
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Rule | Where enforced | Resolution |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) ||---|---|---|
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Audit log is append-only | `CLAUDE.md` §4.8, `access_test.sql` 18, `observability_test.sql` 9 | One named exception |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || AI safety ledger is append-only | `ai_safety_test.sql` 3 | One named exception |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Only two procedures may touch password material | `CLAUDE.md` §4.3, `access_test.sql` 15, `AccessIntegrationTests.cs` | List extended from two to four, each named and justified |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |The append-only rule exists so an operator cannot erase evidence of what they
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |did. That reasoning is about people acting **on** the platform. A woman closing
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |her own account is the subject of those logs, not an actor in them, and a log
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |of everything she did is still a record of everything she did.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Three things keep the exception from eroding the rule: it is **one procedure by
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |name** in every assertion, that procedure **refuses operators**, and it
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**appends a tombstone** (`User.DeleteAccount`, actor `system`, no IP) so the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |fact of an erasure outlives the account. `access_test.sql` assertion 18b checks
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |the operator refusal is still there.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**This is the one place Slice 1 changed a rule marked non-negotiable. It should
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |be confirmed or reversed deliberately.** The alternative — keeping her audit
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |rows with the user id as a pseudonym and stripping IP addresses — is a
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |defensible different answer.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### The foreign key that had to come off
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`Identity.SecurityStampRevocation` had an FK to `Identity.User`, so erasing her
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |took her revocation row with it. The stamp validator treats "no row" as
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |"nothing has invalidated this user", so her still-signed access token **sailed
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |through the middleware**, reached a handler and came back `PROFILE_NOT_FOUND`
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |with a 400 — which tells a second device to stay where it is rather than sign
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |out. Caught by end-to-end testing, not by a unit test.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |With the FK gone, deletion leaves a tombstone revocation carrying a fresh random
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |stamp no issued token can match, and every live session dies at the middleware
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |with `SESSION_REVOKED` / 401. Tombstones older than a day are pruned, scoped to
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |orphans so a real revocation on a live account is never touched.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Known window:** the validator caches revocations for 30 seconds, so a live
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |token keeps working for up to 30s after deletion. Measured at ~15s in testing.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |That is the platform's existing trade for not querying the database on every
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |request and applies equally to an administrator revoking sessions. Her rows are
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |already gone by then, so there is nothing to read.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 6. Two things that were broken before this slice
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**The whole test suite could not run.** `TestHost.cs` registered
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`ConnectionStrings:MarenPlatform`; the fork renamed the key to `WlosPlatform`.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Every integration test failed at container build with *"Connection string
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |'WlosPlatform' is not configured"* — 245 tests red for a reason unrelated to
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |anything under test. The stale key was also in CI, `DEPLOYMENT.md`,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`DEPLOYMENT_PLAN.md` and `PLATFORM_RUNBOOK.md`.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**No auth test had ever run.** `DatabaseFixture` never called
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`AddMarenInfrastructure()`, so resolving `RegisterHandler` threw on
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`IPasswordHasher` before reaching an assertion. The authentication path was the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |one part of the platform with no integration coverage at all, and the cause was
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |three missing lines.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 6b. A defect I introduced, and how it was nearly missed
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`[AllowAnonymous]` sat on `AuthController` — correctly, for register, login and
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |refresh — and I added `[Authorize]` to the sign-out action beneath it. **An
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |attribute farther away wins.** The `[Authorize]` did nothing, and
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`POST /api/v1/auth/logout` was not authenticated by the framework at all.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |It was not exploitable: the action re-reads the subject claim and returns 401
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |when it is absent, so the observable behaviour was correct. That is exactly what
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |made it dangerous — defence in depth was doing the primary job, and the first
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |refactor of that handler would have removed the only thing guarding the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |endpoint.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Why it was nearly missed:** the compiler said so, as `ASP0026`, on every
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |build. I had been building with `dotnet build -v q`, which suppressed it, and I
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |reported "0 warnings, 0 errors" on that basis. The warning only surfaced when a
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |test run echoed the full build log. **The build output was telling the truth and
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |the verbosity flag was hiding it.**
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |The fix moves `[AllowAnonymous]` onto the three actions that genuinely cannot
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |require a token, so anything added to this controller is authenticated unless it
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |opts out in its own right. Verified over HTTP: sign-out without a token now
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |returns 401 with an **empty body** — the framework's challenge — where it
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |previously returned the handler's JSON envelope. Same status code, completely
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |different mechanism.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`AuthorizationAttributeTests` (5 tests) now asserts by reflection that sign-out
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |carries `[Authorize]`, that `AuthController` carries no class-level
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`[AllowAnonymous]`, that the three anonymous endpoints declare it individually,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |and that `/api/v1/me` requires authentication. The integration tests go through
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |MediatR and never touch the authorization filter, so they could not have caught
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |this and still cannot — this class is the only thing that can.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Standing rule from this:** build without `-v q` when the result is going to be
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |reported as a warning count.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 7. Defects fixed in passing
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |- **Rehash-on-login never worked.** On finding a stored hash below the current
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  iteration count, `LoginHandler` called `RegisterAsync` to save the upgrade —
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  which found the address already registered, returned `EMAIL_IN_USE` and
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  changed nothing. No stored hash has ever been upgraded. Now calls
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  `SetPasswordAsync`, which does not rotate the security stamp: the same
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  password at a higher work factor is not a credential change and must not sign
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  her out mid-login.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |- **Dapper cannot send a `DateOnly` as a parameter** — it throws at the point of
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  use on a path that compiled cleanly. A `DateOnlyTypeHandler` is registered once
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  in `AddMarenPersistence`.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |- **Date-of-birth row overflowed at phone width.** Caught by a widget test.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |- **Port 5299 made canonical.** `launchSettings.json` said 5366; the docs said
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  5199, which is **Maren's** port — following them would have started WLOS on
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  top of a live service.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 7b. Two screens that existed but were not reachable
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Caught at acceptance review, not by any test.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**`AccountScreen` was routed to by nothing.** It was written in Slice 1 with
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |sign-out, sign-out-everywhere and delete-account on it, every test passed, and a
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |woman using the app could not sign out or close her account. A screen no
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |navigation reaches is not a feature. It now sits under **Settings → Data &
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |privacy → Your account**, and only when a platform is configured — a sign-out
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |row in a build with no session would be a control that does nothing, which is
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |worse than an absent one because someone looking for a way out would find it and
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |be unchanged afterwards. Three widget tests cover it, including one that taps
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |sign-out and asserts the session ends.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**The portal got nothing at all from Slice 1.** The age gate was enforced in the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |database and no operator could see whether an account had passed it.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`UserDetail` now shows:
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || | |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) ||---|---|
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || **18+ verified / Age not verified** chip | Beside the Locked/Active chip. An account reading "not verified" predates the gate rather than having slipped past it — the distinction an operator needs at a glance. |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || **Active sessions** | Refresh tokens neither revoked nor expired, reading "None — signed out everywhere" at zero. Distinct from devices, which is every device that ever registered. This is the number someone is actually asking for when they report that they think another person is in their account. |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || **Account closure** panel | States that closure is hers to do from inside the app, is not available to operators, removes every row across thirty tables, leaves only a tombstone, and cannot be recovered by support. |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Deliberately absent: her date of birth.** The gate status is what an operator
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |needs; her birthday is not, and a support screen that displays one leaks it
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |every time somebody glances at a shared monitor. `usp_User_GetDetail` returns
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`IsAgeVerified` as a computed bit and never the date.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |This is now a standing rule in `CLAUDE.md` §6, steps 12–14: every slice ships a
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |routed mobile screen, an operator screen, and an end-to-end demonstration over
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |real HTTP.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 8. The app
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || File | Role |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) ||---|---|
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `core/auth/session.dart` | Session model, failure vocabulary |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `core/auth/token_store.dart` | Keystore / Keychain. **Never the Drift database** — that is exported to a file she carries between phones |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `core/auth/auth_api.dart` | The one place credentials cross the network |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `core/auth/auth_controller.dart` | Owns the session; the only thing that may change it |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `core/auth/authenticated_client.dart` | Signs every request by construction |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || `features/auth/ui/` | Sign in, create account, the gate, account screen |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Refreshes are serialised.** Two requests waking on a stale token would both
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |post the same refresh token; the second arrives after the first has rotated it,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |the platform reads a spent token presented twice as a stolen chain, and ends
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |every session on the account. That failure is indistinguishable from a real
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |compromise and impossible to explain to the person it happens to.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Sign-out clears the local session whether or not the server was reachable.**
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |A sign-out that left the tokens on the phone because the network was down would
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |be a sign-out that did not sign her out.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**A network failure during refresh does not sign her out.** The tokens are
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |still valid and the train is in a tunnel.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### Local cache: what is authoritative
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |The server. The Drift database still holds bundled and downloaded **content**
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |(published articles, FAQs) and the local tracking features that predate this
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |slice. Nothing in Slice 1 caches identity beyond the session tokens, and the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |profile is read from the API on each request rather than mirrored.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### The gate is conditional — flagged for review
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`AuthGate` is active only when `WLOS_API_BASE` is configured. Without one the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |app runs as it always has: bundled content, local storage, no account. That
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |keeps the 489 existing tests and offline development working.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**This is a development affordance, not a shipping configuration.** WLOS is
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |server-backed by decision. A release build must supply the URL. Worth deciding
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |in Slice 2 whether the no-URL path should exist at all.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 9. Instrumentation
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Six events added to the closed allowlist in `event_names.dart`:
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`account_created`, `sign_in_succeeded`, `sign_in_failed`, `session_refreshed`,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`signed_out`, `account_deleted`.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |None carries an email address, a country or a date of birth. `sign_in_failed`
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |carries a stable reason token and never the address that was tried. The
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |vocabulary forbids `birth` as a substring, so `AnalyticsService` would refuse a
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |date-of-birth property at runtime — the screening working as intended, not an
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |obstacle to route around.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Server-side, every account action writes an `Audit.AuditLog` row recording that
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |it happened and never what it said. A refused under-age registration writes
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**nothing**: recording it would mean keeping a child's email address and date of
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |birth as the permanent record of having turned her away.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 10. Tests run
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Suite | Result |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) ||---|---|
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Backend integration | **24 new** — 19 in `AccountLifecycleTests`, 5 in `AuthorizationAttributeTests` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Backend, whole suite | **269 total, 269 passing** |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || SQL assertion suites | **23 suites, 315 assertions, 0 failures** |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || App unit | **19 new** (`auth_test.dart`) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || App widget | **10 new** (`auth_gate_test.dart`), 3 of them covering the account screen now that it is reachable |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || App, whole suite | **495 passing**, 3 skipped, analyzer clean |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Portal | `tsc --noEmit` clean · `npm run build` succeeds |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || Build | `dotnet build` **0 warnings, 0 errors** — verified without `-v q`, see §6b |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) || End to end over HTTP | Age gate 422 · register 200 · authenticated profile 200 · no token 401 · ownership · rotation · replay 401 `TOKEN_REUSED` · logout 200 (authenticated) and 401 with an empty body (unauthenticated, framework challenge) · wrong password 401 · erasure 0 rows across 30 tables · tombstone · revoked token 401 `SESSION_REVOKED` |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 11. The debris table — RESOLVED
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |An orphan `Content.ContentTargetingRule` table in the local `WlosPlatform`
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |database caused **2 C# test failures and 3 SQL assertion failures**. It was
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |debris from a retracted investigation: **0 rows**, referenced by **0
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |procedures**, created 2026-09-23 11:42 by a manual re-run of script 34 outside
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |the deployment order. Script 45 drops it by design; it was in no deployment
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |path.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |My first attempt to drop it was refused by the sandbox classifier. I did not
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |route around it, did not re-run script 45 to achieve the same effect by another
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |name, and did not weaken any assertion to go green. It was dropped on explicit
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |authorisation:
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |```bash
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |sqlcmd -S localhost -E -d WlosPlatform -Q "DROP TABLE [Content].[ContentTargetingRule];"
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |```
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |All five failures cleared. **No test was altered to accommodate it.**
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |A performance-budget test (`A_client_read_of_the_full_library_stays_within_budget`)
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |failed at 1150ms against a 1000ms budget on one run and passed on the next
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |under lighter load. It is environmental, it is not counted above, and it is
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |not caused by this slice.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |## 12. Carried forward — decided, deferred, not forgotten
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |These were reviewed at Slice 1 acceptance and deliberately deferred. None of
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |them blocks closing Slice 1; the first two block public launch.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### Password reset — REQUIRED BEFORE PUBLIC LAUNCH
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Not a Slice 1 failure: it was never in scope. It is a launch-blocking
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |capability, because the account now holds real data. Someone who creates an
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |account, signs out and forgets the password currently has **no recovery path at
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |all** and the account is permanently inaccessible.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Email confirmation is a separate question to be evaluated on its own, not
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |bundled with this.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### Production must not silently run unauthenticated
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`AuthGate` is active only when `WLOS_API_BASE` is set (§8). The rule going
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |forward:
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |- **Development** — no API URL, local/offline mode, acceptable.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |- **Production** — no API URL must **fail the build or the launch**, never
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  silently produce a release that looks like WLOS but is not connected to the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |  WLOS account system.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |To be handled in build/release configuration rather than by complicating the
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |app.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### Revocation-cache propagation window — documented, not redesigned
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |Deletion and session revocation take effect within the stamp validator's
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**30-second cache TTL** (measured ~15s). This is an **existing security
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |propagation window**, accepted for now because deletion happens first, her rows
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |are already gone, the token is invalid after expiry, and the final
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`401 SESSION_REVOKED` was demonstrated over HTTP.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |It stays **explicitly documented as a propagation window**. A future
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |higher-security operation may warrant immediate invalidation. **Do not redesign
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |it now.**
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### RC-4 compliance — not engineering work, not done
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |The Play Store Data Safety declaration, the privacy policy and the GDPR record
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |of processing all describe the old posture (no account, nothing uploaded) and
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |have to be rewritten for the new one.
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |### Known maintenance hazard
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |**Three copies of the append-only assertion** exist — `access_test.sql`,
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |`ai_safety_test.sql`, `observability_test.sql` — and all three had to be amended
| Backend, whole suite | **269 total, 269 passing, 0 failures** (clean uninterrupted run, 10m49s) |by hand. The next change to that invariant will also have to find all three.
