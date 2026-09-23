# Handoff: What Future Claude Sessions Need to Know

This guide is for the NEXT Claude Code session. If you're reading this immediately, you are that next session.

---

## Repository Status

**This archive repository is READ-ONLY as of 22 July 2026.** All development has moved to:

- **[Maren-Backend](https://github.com/ahmadsaeedpera-svg/Maren-Backend)** — ASP.NET Core API, SQL Server
- **[Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend)** — Flutter app, React admin portal

**Do not commit to this archive.** History is preserved via `git subtree split`; blame and commit messages survive.

---

## What You're Working On

Maren is a pregnancy wellness platform. It has:

- A **Flutter app** for pregnant people and partners (offline-first, ships to Google Play)
- A **React admin portal** for content editors and administrators
- An **ASP.NET Core API** managing permissions, content, users, and audit trails
- A **SQL Server database** with all business rules in stored procedures (never in C#)

The app has reached architectural maturity. Product development is in progress: three production-ready screens, several in-progress screens, and compliance review as a blocker.

---

## Quick Orientation

### If You're Working on the Backend

1. Clone [Maren-Backend](https://github.com/ahmadsaeedpera-svg/Maren-Backend)
2. Read `Maren-Backend/CLAUDE.md` (it is mandatory)
3. Read this archive's `docs/ARCHITECTURE.md` for the full picture
4. Current status: Foundation complete (auth, permissions, audit, CMS). Notifications next (Slice 2).

**Key files:**
- `src/Maren.Database/` — SQL scripts (numbered, idempotent, apply in order)
- `tests/Maren.Tests/` — 111 integration tests against real SQL
- `src/Maren.Database/tests/` — SQL assertion suites (cms_workflow_test.sql, access_test.sql)

### If You're Working on Mobile

1. Clone [Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend) → `mobile/`
2. Read `Maren-Frontend/CLAUDE.md` (it is mandatory)
3. Read this archive's `docs/ARCHITECTURE.md` for the backend context
4. Current status: Three complete screens (due date, onboarding, hospital bag). Six in-progress. Compliance blockers (RC-1, RC-2, RC-3, RC-4, RC-5).

**Key files:**
- `mobile/lib/features/` — 24 feature modules
- `mobile/test/guards/` — 5 guard tests (verified failing when violated)
- `mobile/lib/core/db/` — Drift schema v6

### If You're Working on the Admin Portal

1. Clone [Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend) → `web-admin/`
2. Read `Maren-Frontend/CLAUDE.md` (it is mandatory)
3. Read this archive's `docs/ARCHITECTURE.md` for the platform model
4. Current status: CMS, users, roles, permissions, audit viewer complete. Notifications, analytics pending.

**Key files:**
- `web-admin/src/api/client.ts` — **The only place `fetch()` is called**
- `web-admin/src/modules/` — One folder per admin feature
- `web-admin/src/auth/` — Session and permission context

---

## The Architecture (Ultra-Short Version)

```
Client → API (MediatR pipeline) → Stored Procedures → SQL Server
         ├─ Logging
         ├─ Authorization (IRequirePermission)
         ├─ Feature Flag (IRequireFeature)
         ├─ Validation
         ├─ Caching (30s, in-process)
         └─ Transaction (held for min time)
```

**Non-negotiable rules:**
1. **Stored procedures only.** No ORM, no ad-hoc SQL. Rules belong in the database.
2. **Authorization is permission-based.** Never check roles in code.
3. **Clients read published snapshots.** Not live tables.
4. **Audit is append-only during account lifetime.** No update, no delete —
   except `usp_User_DeleteAccount`, which erases the rows of an account being
   deleted and nothing else.
5. **Integration tests are real.** No repository mocks.

---

## Right Now (July 2026)

### Completed (Production Ready)

- ✅ **Backend foundation** (auth, permissions, audit, CMS)
- ✅ **Mobile:** Due date calculator, onboarding, hospital bag checklist
- ✅ **Portal:** CMS editor, user management, audit viewer
- ✅ **Database:** 111 tests passing, SQL assertions passing
- ✅ **Architecture:** 9 decisions documented, all implemented

### In Progress

- 🟡 **Mobile:** Birth preferences, kick counter, contraction timer, body log (data models done, UI pending)
- 🟡 **Backend:** Notifications schema done, handlers not yet built (Slice 2)
- 🟡 **Portal:** Reports and analytics pending (Slice 3)

### Blocked

- ❌ **RC-1:** Insights articles need FDA compliance rewrite (25 articles)
- ❌ **RC-2:** All strings need FDA wording audit
- ❌ **RC-3:** Medical content needs clinician review
- ❌ **RC-4:** Legal review (privacy policy, GDPR, terms of use)
- ❌ **RC-5:** Clinical behavioral review (no medical advice in UI)
- ❌ **PD-1:** Mobile sync decision (opt-in or mandatory?)
- ❌ **Device testing:** Only API 36 tested; need Android 10, 12

### Big Risk

**Export is missing while backup is disabled.** Users lose everything on a new phone. This is a **launch blocker for Sprint B**. Schema is ready; UI needs completion.

---

## Before You Start Any Task

1. **Read the team responsibility document.** `docs/TEAM_RESPONSIBILITIES.md` says exactly what your team owns and what you must NEVER do.

2. **Check the roadmap.** `docs/ROADMAP.md` sequences remaining work in dependency order. Don't build something the backend doesn't have yet.

3. **Verify no assumptions.** This archive and the split repos are the source of truth. Trust the code and commit history, not conversation. If the docs contradict the code, the code is right; update the docs.

4. **Check CLAUDE.md in your repo.** Every repository has rules. Violating them once caused a real defect and will cause it again.

5. **Ask about PD-1 before adding networking.** The mobile app states there is no network code. Adding sync changes the Data Safety form, privacy policy, and GDPR posture. This decision has not been made.

---

## The Split Repos Have Their Own Documentation

| File | Contents |
|---|---|
| `Maren-Backend/CLAUDE.md` | Backend rules, architecture, non-negotiables |
| `Maren-Backend/docs/ADR-001-...` | 9 architectural decisions |
| `Maren-Backend/docs/PLATFORM_RUNBOOK.md` | Setup, API reference, deployment |
| `Maren-Frontend/CLAUDE.md` | Frontend rules, architecture, mobile + portal |
| `Maren-Frontend/docs/adr/` | Mobile ADRs |
| `Maren-Frontend/RELEASE_BLOCKERS.md` | RC tasks (compliance) |

This archive (`docs/`) provides the cross-repo view. Use them together.

---

## What You Can Actually Do Right Now

### Backend

- Implement Notifications (Slice 2)
  - Schema exists
  - Create handlers: `CreateNotificationCampaignCommand`, `SendNotificationCommand`
  - Create `usp_Notification_Send`, `usp_NotificationLog_Record`
  - Wire FCM integration
  - Add tests
  
- Implement Analytics (Slice 3)
  - Design schema: `Analytics.Event`, `Analytics.EventProperty`
  - Create ingestion endpoint: `POST /api/v1/events`
  - Create query builder for funnels/retention
  - Add portal dashboard

- Scale improvements
  - Add Redis behind `IQueryCache` (cache currently in-process)
  - Partition audit table by date (append-only, high volume)
  - Add rate limiting (schema + middleware ready)

### Mobile

- **Compliance first** (before any feature)
  - RC-1: Rewrite 25 insights articles to FDA standard
  - RC-2: Audit all strings against General Wellness exclusion
  - RC-5: Clinical review of contraction timer, kick counter, body log (no thresholds, no alerts)

- **Device testing** (Sprint A)
  - Test on Android 10, 12 (only API 36 tested)
  - Test orientation change, background/foreground lifecycle
  - Profile frame timing (first frame is 1576ms—needs analysis)

- **Export/import** (Sprint B — launch blocker)
  - Full-account export/re-import (schema ready, UI partial)
  - Plain-text checklist share (schema ready, UI partial)

- **Screen UI completion** (Sprint D, after compliance)
  - Kick counter UI (model done)
  - Contraction timer UI (model done)
  - Body log UI (model done)

### Portal

- Finish Reports module (pending data source from analytics backend)
- Add analytics dashboard (Slice 3)
- Polish admin UX (forms, error handling, accessibility)

---

## Known Issues & Technical Debt

| Issue | Impact | Status |
|---|---|---|
| **Export missing** | Users lose data on new phone | **Launch blocker** |
| **One instance only** | In-process cache; no horizontal scale | Acceptable now; fix before scale |
| **Token in memory** | Portal logout on refresh | Acceptable dev/staging; fix for prod |
| **Android only** | iOS scaffolded but not released | OK; secondary platform |
| **One device tested** | Could have Android 10/12 regressions | Sprint A must fix |
| **RC compliance** | Store submission blocked | 5 tasks, 2-3 weeks |
| **PD-1 unresolved** | Data Safety posture unclear | Decide before sync ships |
| **No impersonation** | Support workflows limited | Deliberately unimplemented pending legal |

---

## Test Commands

Before committing anything:

**Backend:**
```bash
cd Maren-Backend
dotnet build                                    # no warnings
dotnet test tests/Maren.Tests                   # 111/111 passing
sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform -i src/Maren.Database/tests/cms_workflow_test.sql
sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform -i src/Maren.Database/tests/access_test.sql
```

**Mobile:**
```bash
cd Maren-Frontend/mobile
flutter analyze                                 # must be clean
flutter test                                    # 425/425 passing
flutter test integration_test                   # needs device
```

**Portal:**
```bash
cd Maren-Frontend/web-admin
npm install
npm run build                                   # tsc -b + vite, no TypeScript errors
npm run preview                                 # test locally against running API
```

---

## Git Quick Reference

**Cloning the right repo:**
```bash
# Backend work
git clone https://github.com/ahmadsaeedpera-svg/Maren-Backend.git

# Mobile or portal work
git clone https://github.com/ahmadsaeedpera-svg/Maren-Frontend.git
```

**Feature branch workflow:**
```bash
git checkout -b feature/my-feature
git add .
git commit -m "feat(module): description

Longer explanation of why, not what.

Fixes #123"
git push -u origin feature/my-feature
# Open PR on GitHub
# Merge with merge commit (not squash)
```

**Syncing with main:**
```bash
git fetch origin
git rebase origin/main
git push -u origin feature/my-feature
```

---

## Communication

- **Sync decision (PD-1):** Ask the product team or open an issue in Maren-Backend
- **Compliance questions:** Flag in the issue, brief legal counsel
- **Breaking changes:** Coordinate across teams (see `docs/TEAM_RESPONSIBILITIES.md`)
- **Architecture changes:** Discussion in issues, not assumed

---

## You Are Here

**This archive contains read-only history.** Everything you need to work is in the split repos. Use this archive as a reference for the full picture and cross-repo architecture, but the live code is elsewhere.

**Each split repo is complete:**
- Maren-Backend has everything you need to understand and change the backend
- Maren-Frontend has everything you need to understand and change the mobile app and portal

**For the next session after this one:** All this documentation is committed to both split repos. You will not need to search the archive or previous conversations.

---

## Summary

**You have:**
- A mature architecture with 9 documented decisions
- A split repository strategy with clear team boundaries
- 111 backend tests + 425 mobile tests + 5 guard tests (all passing)
- Complete documentation of schema, API, permissions, audit

**You are blocked on:**
- Compliance review (RC-1 through RC-5)
- A product decision about sync (PD-1)

**You can do right now:**
- Implement Notifications (backend)
- Complete mobile screens (mobile)
- Finish admin portal (portal)
- Device testing (mobile)
- Compliance work (mobile)

**Do not:**
- Add network code to mobile without resolving PD-1
- Build UI for capabilities the backend doesn't have
- Duplicate validation (validation belongs in backend stored procedures)
- Share code between mobile and portal
- Commit secrets

Good luck! The architecture is solid and the split is clean. Go build.
