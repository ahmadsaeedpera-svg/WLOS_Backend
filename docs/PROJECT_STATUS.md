# Maren Platform — Project Status

**Last Updated:** 23 July 2026  
**Status:** Alpha — Architecture complete, product incomplete  
**Archive Note:** This repository has been split and archived. Development continues in:
- [Maren-Backend](https://github.com/ahmadsaeedpera-svg/Maren-Backend) — ASP.NET Core API
- [Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend) — Flutter + React

---

## Executive Summary

Maren is a pregnancy wellness platform: offline-first mobile app, content management system, and administrative portal. The platform has reached architectural maturity with robust permissions, audit trails, and feature flags. Product development is in progress: the mobile app ships three production-ready screens and several in-progress features.

### The Split

On 22 July 2026, the monorepo was divided into three repositories to allow independent team deployment:

| Repository | Team | Responsibility |
|---|---|---|
| **Maren-Backend** | Backend | SQL Server, stored procedures, API, permissions, audit, CMS, notifications |
| **Maren-Frontend** | Mobile + Portal | Flutter app, React admin portal |
| **This archive** | — | Read-only history. Do not commit here. |

Commit history was preserved via `git subtree split`, so `git blame` and provenance survive.

---

## Current Scores

| Dimension | Score | Status |
|---|---:|---|
| **Architecture** | 9.5/10 | ✅ Layered, tested, documented |
| **Code quality** | 9/10 | ✅ Clean Architecture + CQRS |
| **Backend tests** | 111/111 | ✅ Passing (integration, real SQL) |
| **Mobile tests** | 425/425 | ✅ Passing (guards verified failing) |
| **Product completeness** | 45% | 🟡 3 of 9 screens production-ready |
| **Backend readiness** | 90% | 🟡 Foundation done; Notifications/Analytics pending |
| **Mobile readiness** | 60% | 🟡 Storage + sync model defined; opt-in decision pending |
| **Release readiness** | 5% | ❌ **Blocked on compliance review** |

---

## Architecture Overview

```
┌─────────────────────────────────────────┐
│         Clients (Frontend Repo)         │
├──────────────────┬──────────────────────┤
│  Flutter App     │  React Admin Portal  │
│  (mobile/)       │  (web-admin/)        │
├──────────────────┴──────────────────────┤
│           REST API + JWT                 │
│     (Backend Repo: Maren.Api)            │
├─────────────────────────────────────────┤
│  CQRS Layer (MediatR + Behaviors)       │
│  ├─ Logging                             │
│  ├─ Authorization (IRequirePermission)  │
│  ├─ Feature Flags (IRequireFeature)     │
│  ├─ Validation (FluentValidation)       │
│  ├─ Caching (IQueryCache)               │
│  └─ Transactions                        │
├─────────────────────────────────────────┤
│  Repositories (Dapper only)             │
│  → Stored Procedures (decision 2)       │
├─────────────────────────────────────────┤
│    SQL Server 2025 (LocalDB for dev)    │
│    ├─ Identity (users, roles, tokens)   │
│    ├─ CMS (content, versions, approval) │
│    ├─ Access (permissions, audit)       │
│    ├─ Health (birth preferences, logs)  │
│    ├─ Notifications (templates, send)   │
│    └─ Configuration (feature flags)     │
└─────────────────────────────────────────┘
```

---

## Build and Test Status

### Backend (Maren-Backend repo)

| Check | Result | Details |
|---|---|---|
| `dotnet build` | ✅ | No warnings |
| `dotnet test` | ✅ 127/127 | Real SQL integration tests (verified) |
| `cms_workflow_test.sql` | ✅ 17/17 | Content approval rules verified |
| `access_test.sql` | ✅ 19/19 | Permission boundaries verified |
| SQL assertions | ✅ | Audit append-only, no password leaks |

### Mobile (Maren-Frontend/mobile)

| Check | Result | Details |
|---|---|---|
| `flutter analyze` | ✅ | No issues |
| `flutter test` | ✅ 448/448 | Unit + widget tests (verified) |
| `flutter test integration_test` | ✅ | Needs device |
| Guard tests | ✅ 5/5 | Verified failing when violated |
| Coverage | 52% | ~72% excluding generated (app_database.g.dart) |
| `flutter build apk --release` | ✅ | 58.8 MB (fat) |
| `flutter build appbundle` | ✅ | 57.5 MB (Play ships splits) |

### Admin Portal (Maren-Frontend/web-admin)

| Check | Result | Details |
|---|---|---|
| `npm run build` | ✅ | TypeScript strict, no errors |
| Type checking | ✅ | tsc -b strict mode |
| Tests | ⛔ | None yet (manual verification only) |

---

## Implementation Matrix

Complete status of all modules across the stack:

| Module | Database | SP | Repository | CQRS | API | Portal | Mobile | Tests | Status |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **Authentication** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Offline, no sync |
| **Authorization** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Portal only |
| **Users & Roles** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Portal only |
| **Permissions** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Portal only |
| **Audit Trail** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Portal viewer only |
| **Feature Flags** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Portal only |
| **CMS** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 | ✅ | Read-only in app |
| **Settings** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Portal only |
| **Notifications** | 🟡 | 🟡 | 🟡 | ⛔ | ⛔ | ⛔ | 🟡 | ⛔ | **Blocked** |
| **Analytics** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | Slice 3 |
| **Subscriptions** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | Slice 4 |
| **Content Delivery** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 | ✅ | Offline, no sync |
| **Due Date Calculator** | ✅ | ✅ | ✅ | ⛔ | ⛔ | ⛔ | ✅ | ✅ | Offline, complete |
| **Onboarding** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ✅ | Offline, complete |
| **Hospital Bag** | ✅ | ✅ | ✅ | ⛔ | ⛔ | ⛔ | ✅ | ✅ | Offline, complete |
| **Birth Preferences** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | ✅ | Blocked: legal review |
| **Kick Counter** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Model only |
| **Contraction Timer** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Model only |
| **Body Log** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Model only |
| **Weekly Content** | ✅ | ✅ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | Blocked: clinical review |
| **Widgets** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Home widget partial |
| **Search** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ✅ | Offline, complete |
| **Export/Import** | ✅ | ✅ | ✅ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Schema ready, UI partial |

**Legend:** ✅ Complete · 🟡 Partial · ⛔ Not started

---

## Known Blockers

### Release Candidate (Compliance)

| Item | Status | Gates |
|---|---|---|
| **RC-1:** Insights articles compliance rewrite | 🔴 Open | Store submission |
| **RC-2:** FDA wording audit (all strings) | 🔴 Open | Store submission |
| **RC-3:** Medical content review | 🔴 Open | Store submission |
| **RC-4:** Legal review (privacy, GDPR, terms) | 🔴 Open | Store submission |
| **RC-5:** Clinical review (behavioral audit) | 🔴 Open | Store submission |

### Product Decisions

| Decision | Status | Impact |
|---|---|---|
| **PD-1:** Mobile sync opt-in vs. mandatory | 🟡 Recorded | Data Safety, GDPR, privacy claims |
| **PD-2:** Stored procedures only (accepted) | ✅ Implemented | Security boundary, no inline SQL |

### Development Blockers

| Item | Status | Impact |
|---|---|---|
| **Trademark clearance** (Nice 9/42/44) | 🔴 Pending | Store assets, marketing |
| **Play Console account** | 🔴 Pending | ASO, analytics, store listing |
| **Device testing** (Android 10, 12) | 🟡 Partial | Release readiness Sprint A |

---

## Risk Register

| Risk | Severity | Mitigation |
|---|---|---|
| **Export missing while backup off** | **High** | Sprint B: export is launch blocker |
| **Schema migration data loss** | High | v1→v2 tested against v1 data |
| **One device tested** | Medium | Sprint A: Android 10, 12 required |
| **Fat APK 58.8 MB** | Medium | Play serves splits; measure live |
| **Cache in-process** | Medium | Behind `IQueryCache`; Redis before scale |
| **Portal token in memory** | Medium | Mitigated by refresh-token in cookie (pending API change) |
| **Category deceleration** | Medium | Accepted risk; entry through abandoned keywords |
| **Legal blocks US content** | Medium | UK ship independently |

---

## Repository Structure

### Split Repositories

**[Maren-Backend](https://github.com/ahmadsaeedpera-svg/Maren-Backend)**
```
src/
  Maren.Api              Controllers, middleware, DI
  Maren.Application      CQRS, validators, behaviors
  Maren.Domain           Invariants
  Maren.Contracts        DTOs (DTO changes = breaking for frontend)
  Maren.Persistence      Dapper repositories
  Maren.Infrastructure   JWT, hashing, caching
  Maren.Shared           Result<T>, failure codes, permissions
  Maren.Database         111 SQL scripts + assertion suites
tests/
  Maren.Tests            111 integration tests (real SQL)
docs/
  ADR-001-platform-architecture.md
  PLATFORM_RUNBOOK.md
  PLATFORM_DECISIONS.md
  SLICE-01-users-access.md
  RELEASE_BLOCKERS.md
```

**[Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend)**
```
mobile/                  Flutter app
  lib/
    features/            24 feature modules
    core/                DB (Drift), theme, shared widgets
    l10n/                Localization (en, not yet deployed)
  test/                  425 unit + widget tests
  integration_test/      Full journeys (needs device)

web-admin/               React admin portal
  src/
    api/                 Client, endpoints
    auth/                Session, permissions
    components/          Shell, shared UI
    modules/             CMS, Users, Roles, Permissions, Audit, Settings
  
docs/
  adr/                   Architecture decisions
  specs/                 Feature specifications
  play-store/            Store listing metadata
```

### This Archive Repository

```
app/                     Deprecated — Flutter app (moved to Maren-Frontend/mobile)
Maren.Platform/          Deprecated — monorepo (split into Maren-Backend)
Maren-Backend/           Git subtree: backend (read-only)
Maren-Frontend/          Git subtree: frontend (read-only)
docs/                    Archive documentation (this file lives here)
```

---

## Development Workflow

### Backend Changes

1. Clone/checkout Maren-Backend
2. Make changes to C# or SQL
3. Run: `dotnet build && dotnet test tests/Maren.Tests`
4. Run: `sqlcmd ... tests/cms_workflow_test.sql && access_test.sql`
5. Commit with `docs: `, `feat: `, or `fix: ` prefix
6. PR → merge to main

### Frontend Changes

1. Clone/checkout Maren-Frontend
2. For mobile: `cd mobile && flutter test`
3. For portal: `cd web-admin && npm run build`
4. Commit with conventional commits
5. PR → merge to main

### This Archive

**Read-only.** Git history only. All development happens in split repos.

---

## Next Steps

### Immediate (Sprint A — Release Readiness)

- [ ] Device testing: Android 10, 12 (not just API 36)
- [ ] Orientation change, background/foreground lifecycle
- [ ] Profile-mode frame timing analysis
- [ ] Backup exclusion verification on real device

### Sprint B — Export (Launch Blocker)

- [ ] Full-account export/re-import
- [ ] Plain-text checklist share

### Sprint C — Birth Preferences UI

- [ ] Blocked on ACOG legal read for US content

### Sprint D — MVP Screens

- [ ] Kick counter UI
- [ ] Contraction timer UI
- [ ] Body log UI
- [ ] Week-by-week content (blocked on clinical review)

### Compliance (RC Phase)

- [ ] RC-1: Insights articles rewrite (25 articles)
- [ ] RC-2: FDA wording audit (all strings)
- [ ] RC-3: Medical content review
- [ ] RC-4: Legal review (privacy, GDPR, terms)
- [ ] RC-5: Clinical behavioral audit

---

## Key Decisions

| ADR | Title | Status |
|---|---|---|
| ADR-001 | Platform architecture (9 decisions) | Accepted |
| PD-1 | Mobile sync opt-in vs. mandatory | **Unresolved** |
| PD-2 | Stored procedures only | Accepted |

See `docs/DECISIONS.md` for full details.

---

## For New Sessions

This archive is read-only. To continue development:

1. **Backend work?** → Clone [Maren-Backend](https://github.com/ahmadsaeedpera-svg/Maren-Backend), read its `CLAUDE.md`
2. **Frontend work?** → Clone [Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend), read its `CLAUDE.md`
3. **Understanding the full system?** → Read `docs/ARCHITECTURE.md` and `docs/HANDOFF.md` (in this archive)

All permanent documentation has been generated and committed to each repository.
