# Team Responsibilities & Repository Ownership

Clear ownership boundaries after the repository split.

---

## Repository Split (22 July 2026)

| Repository | Team | Responsibility |
|---|---|---|
| **[Maren-Backend](https://github.com/ahmadsaeedpera-svg/Maren-Backend)** | Backend | ASP.NET Core API, SQL Server, stored procedures, permissions, audit, CMS, platform foundation |
| **[Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend)** | Mobile + Portal | Flutter app, React admin portal |
| **This archive** | — | Read-only history (no commits) |

---

## Backend Team

**Repository:** [Maren-Backend](https://github.com/ahmadsaeedpera-svg/Maren-Backend)

### Ownership

**You own:**
- SQL Server schema and stored procedures
- ASP.NET Core API (Maren.Api)
- CQRS layer (Maren.Application)
- Domain invariants (Maren.Domain)
- Repositories and data access (Maren.Persistence)
- Infrastructure (JWT, hashing, caching, security stamps)
- Feature flags and configuration
- Permissions model and audit trail
- All database-enforced rules

**Specific modules:**
- ✅ Authentication (register, login, refresh tokens)
- ✅ Authorization & permissions (IRequirePermission enforcement)
- ✅ Users & roles management (CRUD, assignments, role matrix)
- ✅ Audit trail (append-only logging)
- ✅ CMS (content versioning, approval workflow, publishing)
- ✅ Content localization (language fallback chains)
- ✅ Content targeting (country, week, season, app version filters)
- ✅ Settings & configuration (global settings, feature flags)
- ✅ Hospital bag content (items, phases, defaults)
- ✅ Birth preference content (options, categories)
- ✅ Weekly content delivery (via CMS)
- 🟡 Notifications (schema designed, handlers pending—Slice 2)
- 🟡 Analytics (schema pending—Slice 3)

### What You Must NEVER Do

❌ **Do not:**
- Build mobile UI or screens
- Edit Flutter code
- Build React admin portal UI
- Write TypeScript
- Deploy to Google Play
- Deploy to a web host (frontend teams handle that)
- Modify `.env` files or client-side configuration
- Add business logic that depends on client-side enforcement
- Make assumptions about the frontend architecture

### Code Review Checklist

Before approving a PR, verify:
- [ ] `dotnet build` passes with no warnings
- [ ] `dotnet test tests/Maren.Tests` passes (111/111)
- [ ] `cms_workflow_test.sql` passes (17/17)
- [ ] `access_test.sql` passes (19/19)
- [ ] No new stored procedures end in `SELECT *` (ProcedureShapeTests)
- [ ] No password material outside login path (test: `PasswordTestBase`)
- [ ] No business logic in C# that belongs in a procedure
- [ ] Permission codes in code match database seed (drift test)
- [ ] Audit logging on every command
- [ ] Feature flag name matches database (seed test)
- [ ] Failure codes are stable strings (not enums)
- [ ] Authorization is permission-based (not role-based)
- [ ] Breaking changes to `Maren.Contracts` are documented in PR body

### Dependencies

**Frontend team depends on you for:**
- API contracts (DTOs in `Maren.Contracts`)
- Endpoint stability (no URL changes without notice)
- Permission codes (must match what the portal UI expects)
- Feature flags (portal needs to know all flag names)

**You depend on frontend for:**
- Bug reports (via issues)
- Feature requests (via roadmap discussions)
- Contract feedback (if DTOs don't fit mobile/portal needs)

### Deployment

- You deploy the API independently
- Frontend teams deploy independently
- No coordinated deploys needed (versioned contracts)

---

## Mobile Team

**Repository:** [Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend) — `mobile/` directory

### Ownership

**You own:**
- Flutter app (Dart code)
- Mobile UI and UX
- Local storage (Drift SQLite)
- Offline-first architecture
- Notifications integration (device-side)
- App signing and keystore
- Play Store listing and assets

**Specific modules:**
- ✅ Due date calculator (offline, no backend)
- ✅ Onboarding (offline, no backend)
- ✅ Hospital bag checklist (offline, no backend)
- ✅ Global search (offline index)
- 🟡 Birth preferences (UI pending legal review)
- 🟡 Kick counter (UI pending)
- 🟡 Contraction timer (UI pending)
- 🟡 Body log (UI pending)
- 🟡 Daily check-in (UI in progress)
- 🟡 Wellness insights (articles need compliance rewrite)
- 🟡 Export/import (UI pending, **launch blocker**)
- 🟡 Home widget (partial)

### What You Must NEVER Do

❌ **Do not:**
- Write backend logic (if a rule matters, it belongs in a stored procedure)
- Build backend API endpoints
- Write SQL
- Commit `.env.local`, `key.properties`, `*.keystore`, or `google-services.json`
- Add code that bypasses offline storage (no mock servers)
- Duplicate validation that lives in the backend
- Share code with web-admin (two different products for two audiences)
- Deploy backend changes
- Modify SQL schema
- Make decisions about permissions or authentication rules

### Code Review Checklist

Before approving a PR, verify:
- [ ] `flutter analyze` is clean
- [ ] `flutter test` passes (425/425)
- [ ] Guard tests pass (5/5):
  - `no_interpretation_test.dart` (no medical advice)
  - `analytics_event_test.dart` (no health data disclosed)
  - `contraception_claim_test.dart` (no contraception phrasing)
  - `crash_scrubbing_test.dart` (no dates, user data in crashes)
  - `inclusive_copy_test.dart` (no gendered terms hardcoded)
- [ ] `flutter format .` has been run
- [ ] All strings go through `l10n.yaml` (no hardcoded English)
- [ ] No `print()` (use logger instead)
- [ ] No `TODO` in committed code (open an issue)
- [ ] `const` constructors where possible
- [ ] Semantic labels on all interactive elements
- [ ] Tested on a real device (not just emulator)

### Dependencies

**You depend on backend for:**
- Database schema (health data tables)
- No new API endpoints yet (app is offline-only—see PD-1)
- Once PD-1 is resolved: API contracts for sync

**Backend team depends on you for:**
- Mobile app roadmap (what features you need)
- Content requirements (what health data schema should store)
- Device testing feedback (regressions, performance issues)

### Deployment

- You deploy to Google Play independently
- App review is your responsibility (2-week cycle)
- No coordination with backend or portal needed

### Compliance Responsibility

**You are responsible for:**
- RC-1: Rewrite 25 wellness articles to compliance standard
- RC-2: FDA wording audit (all user-facing strings)
- RC-5: Clinical behavioral audit (contraction timer, kick counter show raw data only)
- Guard tests remain passing
- Module READMEs cite compliance documents

---

## Admin Portal Team

**Repository:** [Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend) — `web-admin/` directory

### Ownership

**You own:**
- React admin portal (TypeScript)
- User interface for:
  - Content management (CMS)
  - User & role administration
  - Permissions management
  - Feature flags
  - Settings
  - Audit viewer
  - Reports (future)
  - Analytics (future)
- Portal deployment (static hosting)

**Specific modules:**
- ✅ Users & roles (CRUD, role matrix)
- ✅ Permissions (grant/revoke, separation of duties)
- ✅ CMS (editor, approval workflow, publish, history)
- ✅ Feature flags (on/off, rollout)
- ✅ Settings (global configuration)
- ✅ Audit viewer (search, filter, export)

### What You Must NEVER Do

❌ **Do not:**
- Write backend API endpoints
- Write SQL
- Implement business logic in the portal (all rules go in backend)
- Share code with mobile app
- Call `fetch()` directly (use `client.ts` only)
- Store access tokens in `localStorage` (memory only—refresh revokes on page refresh)
- Skip the `If-Match` header on saves (ETag for optimistic concurrency)
- Retry 401, 403, or 400 responses (they will not change on retry)
- Make assumptions about mobile app UX

### Code Review Checklist

Before approving a PR, verify:
- [ ] `npm run build` passes (TypeScript strict, no errors)
- [ ] `tsc -b` is clean
- [ ] All API calls go through `client.ts` (no direct `fetch`)
- [ ] No access token in `localStorage`
- [ ] Permission checks are UI only (API re-checks)
- [ ] Every form has client-side + server-side validation
- [ ] Failure messages from API are shown verbatim (never "Something went wrong")
- [ ] ETag (`If-Match`) used on every write
- [ ] Version conflict (409) shown to user with option to reload
- [ ] No automatic retry on 401/403/400
- [ ] Portal responds to API permission changes in real time
- [ ] No `TODO` in committed code (open an issue)

### Dependencies

**You depend on backend for:**
- API endpoints (must be documented at `/scalar/v1`)
- Permission codes (must match frontend expected permissions)
- Feature flags (must be seeded in backend)
- DTOs in `Maren.Contracts` (breaking changes block you)

**Backend team depends on you for:**
- Feedback on API usability (hard to use = bad design)
- Bug reports via issues
- Operator workflow feedback (is the UI natural?)

### Deployment

- You deploy independently to a static host
- Portal can be updated without backend deploy
- Backend can be updated without portal deploy

### Compliance Responsibility

**You are responsible for:**
- Portal compliance (no medical advice in UI text)
- Error messages must be clear and actionable
- No health data exposed in page titles or breadcrumbs

---

## Shared Responsibilities

| Responsibility | Backend | Mobile | Portal |
|---|:---:|:---:|:---:|
| **Commit messages** | ✅ | ✅ | ✅ |
| **Pull request descriptions** | ✅ | ✅ | ✅ |
| **Architecture review** | ✅ | ✅ | ✅ |
| **Code review** (own repo) | ✅ | ✅ | ✅ |
| **Tests writing** | ✅ | ✅ | ✅ |
| **Documentation** | ✅ | ✅ | ✅ |
| **Security** | ✅ | ✅ | ✅ |
| **Accessibility** | ⚠️ | ✅ | ✅ |

---

## Communication Protocol

### Backend Changes Affecting Frontend

**Scenario:** You change a DTO in `Maren.Contracts`

**Action:**
1. Mark the PR with ⚠️ breaking change
2. State in PR body: "Breaking change to `RegisterResponse`: added `VerificationEmailSent` field"
3. Frontend teams can plan their updates before the merge
4. Coordinate the deploy timing (optional if new fields are optional)

### Frontend Bug in Backend Scope

**Scenario:** Mobile app crashes when calling `/api/v1/content/{id}`

**Action:**
1. Mobile team opens an issue in Maren-Backend repo
2. State the exact request and error response
3. Backend team investigates and responds

### Breaking Changes

**No uncoordinated breaking changes.** If you must break a contract:
1. Open an issue for discussion
2. Propose a deprecation timeline
3. Both teams agree before implementing

---

## Escalation Path

| Issue Type | Escalation |
|---|---|
| **Major architecture change** | Product team lead decision |
| **Security concern** | Pause work, brief all teams immediately |
| **Data loss risk** | Pause work, engage QA and product |
| **Compliance question** | Legal/compliance team decision |
| **Performance regression** | Investigate root cause before merge |

---

## Appendix: Contract Stability

### Frontend Contract (Maren.Contracts)

**Where it lives:** `Maren-Backend/src/Maren.Contracts`

**Who uses it:**
- Mobile app (when PD-1 is resolved)
- Admin portal (today)

**Change policy:**
- New optional fields: safe, no coordination needed
- New required fields: breaking, requires coordination
- Rename/delete fields: breaking, requires coordination
- Change field type: breaking, requires coordination

**Versioning:** API URLs include version (`/api/v1/...`). Changing major version is a breaking change.

---

## For More Information

- **Backend CLAUDE.md:** Maren-Backend/CLAUDE.md
- **Frontend CLAUDE.md:** Maren-Frontend/CLAUDE.md
- **Architecture:** `docs/ARCHITECTURE.md`
- **Security:** `docs/SECURITY.md`
- **Testing:** `docs/TESTING.md`
