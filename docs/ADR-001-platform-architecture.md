# ADR-001 — Maren Platform architecture

**Status:** Accepted
**Date:** 2026-07-22
**Scope:** Phase 1 (Enterprise CMS). Records decisions that later phases inherit.

---

## Context

Maren was an offline-only Flutter application. It is becoming a platform where
the Flutter app is one client among several (admin portal, later: partner,
clinician, subscription). Content that previously shipped inside the APK must
become editable without a Play Store release.

That single requirement — change content without shipping an app — is what
drives most of what follows.

---

## Decisions

### 1. Two solutions, not one

`Maren.Platform` (.NET) and `Maren.Mobile` (Flutter) are separate.

They have different toolchains, release cadences and reviewers. A single
repository would tie a server hotfix to a mobile CI run that takes twenty
minutes and cannot fail for any reason a server change would cause.

**Cost:** contract drift between the two. Mitigated by the client contract being
small and versioned, not by tooling.

---

### 2. Stored procedures are the only data access

No ORM-generated SQL, no query builders. Dapper calls named procedures.

The business rules that matter here are rules about *state transitions* —
publish requires approval, restore writes forward, a version is immutable once
written. Expressing those in application code means every future client
(reporting job, admin script, partner import) can bypass them by writing to the
table directly. In the database, they hold regardless of who connects.

It also means a rule can be fixed without redeploying the API, which for a
content-safety rule is the difference between minutes and hours.

**Cost:** procedures are harder to unit test and diff than C#. Accepted, and
answered by decision 8.

---

### 3. Content versions are JSON snapshots, not diffs or foreign keys

`ContentVersion.SnapshotJson` holds the complete item as it was.

A version chain built from diffs cannot be read without replaying every prior
version, and a version built from foreign keys into the live tables stops being
a record of the past the moment the schema changes. A snapshot survives both.

This also makes approval meaningful: an approval names a version id, and that
version id names exact bytes.

**Cost:** storage. Content items are small text records; this is not a real
constraint at this scale.

---

### 4. The client reads the published snapshot, never the live tables

`usp_Content_GetForClient` sources title, body and summary from the published
version's snapshot.

This was originally wrong — the procedure gated on `PublishedVersionId` but read
its text from `ContentTranslation`, the live working copy. An editor typing into
a published article pushed unreviewed text to every device on the next sync,
with no approval and no publish event. The approval workflow was decorative for
anything already live.

For a pregnancy app, unreviewed health text reaching users is a clinical-safety
problem before it is a workflow one.

**Deliberate exception:** targeting (country filter, week range, season, minimum
app version, publish window) is still read live from the item row. Those are
operational controls. Narrowing distribution during an incident must take effect
immediately and must not require a publish cycle. Approval governs *what it
says*; an operator governs *who sees it*.

---

### 5. Authorization is permission-based and enforced in the pipeline

Requests declare `IRequirePermission`. A MediatR behaviour checks it. Controllers
carry `[Authorize]` only, which asserts that a caller is authenticated and
nothing more.

Roles are never checked in code. A role is a bundle of permissions an
administrator can change; code that checks for `"ContentEditor"` breaks the
moment somebody creates a second role that should also edit.

Putting the check on the *request* rather than in the *handler* means a handler
invoked from another handler cannot skip it. A handler that checks its own
permission is one refactor away from being called by something that forgot.

The portal filters its navigation by the same permission codes. That is a
courtesy so people are not shown buttons that will fail — it is not access
control, and the API does not trust it.

---

### 6. Separation of duties between authoring and approval

`ContentEditor` holds `content.write` but not `content.review`.
`ContentApprover` holds `content.review` but not `content.write`.

An approver who can edit can approve their own change by editing after approval.
The gate would still pass, because the pointer would still name an approved
snapshot — the snapshot would simply no longer be the one anybody read.

`SuperAdmin` holds both. That is a deliberate escape hatch, and it is audited.

---

### 7. Feature flags default to enabled when undefined

`CachedFeatureFlagEvaluator` returns true for a flag with no row.

Defaulting to disabled means adding a new `IRequireFeature` gate silently
switches that endpoint off in every environment until somebody remembers to
insert a row — a deployment that appears to succeed and quietly removes
functionality. Defaulting to enabled makes a flag an off-switch for something
that already works, which is how the rest of the platform treats them.

Evaluation is cached for 30 seconds. That bounds how long a kill-switch takes to
bite, which is short enough for the "turn it off at 3am" case the flag exists
for.

**Cost:** a typo in a flag key silently disables the gate rather than the
feature. Answered by the seed test that asserts every referenced key exists.

---

### 8. Integration tests run against a real database

`Maren.Tests` opens real connections and calls real procedures. There are no
repository mocks.

Every rule worth testing lives in a procedure (decision 2). A suite that mocks
`IContentRepository` verifies the mocks. It cannot tell you whether an editor
can publish something nobody approved, which is the only question that matters.

This is what caught the decision-4 bug, and it is what `ProcedureShapeTests`
exists for: three endpoints had shipped returning 500 on every call because a
procedure ended in `SELECT *` while its DTO was a positional record. No amount
of mocked testing would have found any of them.

**Cost:** the suite needs SQL Server present and is slower than pure unit tests.
At three seconds for 86 tests this is not yet a problem.

---

### 9. One response envelope, everywhere

Every endpoint returns `ApiResponse<T>` — success and failure, including from
the exception handler. Status codes are still accurate for proxies and logs.

A client that has one shape to parse has one error path to get right.

---

## Consequences for later phases

- **Notifications, analytics, subscriptions** inherit the permission model and
  the pipeline. New capability means a new permission code in
  `PlatformPermissions` *and* in `21_Seed_*.sql`; the drift test enforces both.
- **Any new client-facing read** must decide, explicitly, whether it serves
  approved bytes or live ones. Decision 4 is not automatic — it was hand-written
  into one procedure and could be got wrong again in the next.
- **Any procedure returning a result set** must name its columns. There is a
  test that scans for this.

---

## Open items

- **PD-1 (unresolved, carried from `PLATFORM_DECISIONS.md`).** The shipped app's
  About screen states there is no network code in Maren. Cloud sync makes that
  false and changes the Play Store Data Safety declaration and the GDPR posture.
  The schema is built so sync is opt-in, so this is not yet a released
  contradiction — but it becomes one the day the Flutter client talks to this
  API. This needs a decision before Phase 2 ships to a device.
- **Portal session lifetime.** The access token is held in memory, so a browser
  refresh signs the operator out. This is deliberate — a token in `localStorage`
  is readable by any script that runs on the page, and this portal can publish to
  every user. The proper fix is the refresh token in a `SameSite`, `HttpOnly`
  cookie, which needs an API change.
- **Cache is in-process.** Behind more than one API instance, an editor's change
  can take up to the TTL to appear on an instance that did not serve the write.
  Acceptable now; wants Redis before horizontal scaling. It sits behind
  `IQueryCache` for that reason.
