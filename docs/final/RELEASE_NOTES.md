# RELEASE NOTES

**Branches:** `feature/backend-v2` · `feature/portal-v2`
**Status:** Not merged. Not released. Feature branches for review.

---

## Fixed

### Unapproved content could publish itself
`usp_Content_RunDueSchedules` never consulted `ContentApproval`, so a scheduled publish bypassed the approval gate that `usp_Content_Publish` enforces. An editor could schedule an unreviewed draft and have it reach every device unattended. In a pregnancy product that is a clinical-safety problem before it is a workflow one.

Latent only because no background service calls the runner yet — it had to be fixed *before* one is wired up, not after.

### Scheduled publishes silently republished stale content
The same procedure set `PublishedVersionId = COALESCE(PublishedVersionId, CurrentVersionId)`. For an item published before, that resolves to the version *already live*, so scheduling a newly approved edit republished the old text and reported success. Found by writing the test first.

### CI had been failing on every commit
Two independent causes. Five `CA1310` errors under `-warnaserror` (culture-sensitive `StartsWith` — a real cross-region flake source, not pedantry), and `dotnet test` exiting 1 while printing `Passed! 127, Failed: 0`, because the test fixture disposed a container holding an `IAsyncDisposable`-only service synchronously. Fixing only the first would have left CI red.

### Eighteen foreign keys had no supporting index
"Get my pregnancy" — the most common read in the health domain — was a full table scan, confirmed by execution plan. Twelve of the schema's foreign keys cascade on delete, so the cost was paid twice.

Writing the assertion first found a nineteenth case the catalog sweep missed: `Health.DailyLog.UserId` *looked* covered, but only by an index filtered to `IsDeleted = 0`, which cannot serve a reference check or a GDPR export that must include deleted rows.

---

## Added

### AI companion — design and first guardrail
Specifications for a companion across fourteen everyday domains (sleep, food, hydration, movement, habits, routine, focus, mood, relationships, learning, work, planning, medication reminders) that **never diagnoses and never prescribes**, with those rules enforced in four independent places rather than stated once in a prompt.

Ships the first guardrail: `AI.SafetyEvent`, an append-only ledger recording refusals, categories and classifier scores. It **cannot hold message content** — no such column exists, and the test suite fails the build if one is added. Conversation stays on the device.

### Portal: first automated tests
24 tests on the API client and auth context — the two units every screen depends on. Coverage 93% and 97%. Mutation-tested: two injected regressions were each caught by exactly the right test.

### Portal: route splitting, strict TypeScript, error boundaries
Initial payload **332 kB → 161 kB gzip**. An unauthenticated visitor no longer downloads the entire admin app, including a 408 kB DataGrid, to see a login form. `strict` was claimed in documentation but never enabled; turning it on produced zero errors. A render error no longer white-pages the portal.

### Continuous integration for the frontend
The portal had no automated checks at all. Now lints, tests, builds with strict types, and fails if the initial bundle exceeds 200 kB gzip.

### Documentation
Database review and improvement plan · deployment, CI/CD, backup and recovery plans · AI system, prompts and pipeline · master test plan · product vision, personas, life-stage design, feature matrix and roadmap.

---

## Changed

- Schema script lists in CI, README, CLAUDE.md and the runbook were stale — they omitted five scripts CI had been applying. Now match reality.
- Five SQL assertion suites (52 assertions) run in CI, up from two.

---

## Known issues — shipped unfixed

| Issue | Impact |
|---|---|
| **Container healthcheck is broken** | Would restart-loop any real container deploy. Masked in development by a compose override |
| 42 `IX_*_NotDeleted` indexes are non-selective | Write cost on every insert, no read benefit |
| ContentEditor destroys unsaved typing on background refetch | An operator loses work with no error |
| ContentEditor can send `If-Match: null` | Silent last-write-wins on a CMS |
| Settings blanks a secret when editing its description | Config reaching every device is erased |
| RolesMatrix unusable by screen reader | Unlabelled checkboxes, no row headers |
| RolesMatrix: saving one role discards staged edits to others | Silent data loss |
| FeatureFlags: slider frozen while dragging; 100% flags cannot be reduced | Control is unusable at the top of its range |
| `usp_User_Erase` does not exist | GDPR erasure is referenced in a comment only |

---

## Not verified in this environment

**The Flutter app was never executed.** No SDK is installed; its 462 test blocks were counted statically. **Docker is not installed**, so no image was built and the healthcheck fix could not be validated. **The GitHub Actions workflows have never run on a runner** — only their equivalent commands were executed by hand. The **portal's authenticated screens** were never driven against a live API.

See `FINAL_REPORT.md` §1 for the full blocked list with evidence.
