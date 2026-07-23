# Module Status & Implementation Matrix

Complete inventory of all modules and features with Definition of Done checklist.

---

## Implementation Matrix Summary

| Module | DB | SP | Repo | CQRS | API | Portal | Mobile | Tests | Status |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|---|
| **Authentication** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Register, Login, Refresh |
| **Authorization & Permissions** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Permission-based ACL |
| **Users & Roles** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | CRUD, assignments |
| **Audit Trail** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Append-only viewer |
| **Feature Flags** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | CMS content delivery |
| **Settings & Config** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Global settings |
| **CMS Core** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 | ✅ | Search, read, version history |
| **CMS Approval Workflow** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ⛔ | ✅ | Publish gate |
| **Content Localization** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 | ✅ | en-GB fallback |
| **Content Targeting** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 🟡 | ✅ | Country, week, season |
| **Content Scheduling** | ✅ | ✅ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | **Partial** — schema only |
| **Due Date Calculator** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ✅ | Offline, complete |
| **Onboarding** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ✅ | Address terms, offline |
| **Hospital Bag Checklist** | ✅ | ✅ | ✅ | ⛔ | ⛔ | ⛔ | ✅ | ✅ | Complete, phased items |
| **Birth Preferences** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | ✅ | **Blocked:** ACOG legal |
| **Kick Counter** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Data model only |
| **Contraction Timer** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Data model only |
| **Body Log** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Data model only |
| **Weekly Content Delivery** | ✅ | ✅ | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | **Blocked:** clinical review |
| **Daily Check-in** | ✅ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | UI only |
| **Wellness Insights** | ✅ | ✅ | ✅ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | **RC-1:** rewrite articles |
| **Global Search** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ✅ | ✅ | Offline index |
| **Export/Import** | ✅ | ✅ | ✅ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Schema ready, UI partial |
| **Notifications** | 🟡 | 🟡 | 🟡 | ⛔ | ⛔ | ⛔ | 🟡 | ⛔ | **Slice 2 — Backend blocked** |
| **Analytics** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | Slice 3 |
| **Subscriptions** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | Slice 4 |
| **Widgets (Home widget)** | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | ⛔ | 🟡 | 🟡 | Partial |

**Legend:**
- ✅ Complete
- 🟡 Partial / In Progress
- ⛔ Not Started
- Database: ✅ = schema exists
- SP: ✅ = stored procedures exist
- Repo: ✅ = repository methods exist
- CQRS: ✅ = handlers + validators + behaviors
- API: ✅ = endpoints defined and tested
- Portal: ✅ = admin UI built
- Mobile: ✅ = user-facing feature complete
- Tests: ✅ = unit + integration tests passing

---

## Detailed Module Breakdown

### Backend Platform Foundation (Slice 1)

#### 1. Authentication

**Purpose:** User registration, login, session management

**Current Implementation:**
- Database: `Identity.User`, `RefreshToken`, `SecurityStamp`
- Stored Procedures: `usp_User_Register`, `usp_User_GetForLogin`, `usp_User_RefreshToken`
- Repository: `AuthRepository.RegisterAsync`, `LoginAsync`, `RefreshAsync`
- CQRS: `RegisterCommand`, `LoginCommand`, `RefreshCommand` + validators
- API: `POST /api/v1/auth/register`, `login`, `refresh`
- Tests: `AuthIntegrationTests` (register, login, token rotation, reuse detection)

**Completed Work:**
- ✅ PBKDF2-HMAC-SHA256 hashing (210k iterations, per-row count)
- ✅ JWT access tokens (15 min) + opaque refresh tokens (30 day)
- ✅ Refresh token rotation on use + reuse detection
- ✅ Security stamp for session revocation (~30s)
- ✅ Email validation (RFC 5321)
- ✅ Password strength requirements
- ✅ Account lockout after failed attempts (not yet tuned)

**Remaining Work:**
- Account lockout tuning (threshold, duration)
- Email verification (optional—currently unverified)

**Status:** ✅ Complete — Platform ready

---

#### 2. Authorization & Permissions

**Purpose:** Permission-based access control, privilege escalation prevention

**Current Implementation:**
- Database: `Access.Permission`, `Identity.Role`, `Identity.UserRole`
- Stored Procedures: `usp_Role_SetPermissions`, `usp_User_AssignRole`, `usp_User_HasPermission`
- Repository: `AccessRepository.UserHasPermissionAsync`
- CQRS: `AuthorizationBehavior` (pipeline middleware)
- API: All endpoints check `IRequirePermission`
- Portal: Role management UI with permission matrix
- Tests: `PermissionEscalationTests`, `SeparationOfDutiesTests`, `access_test.sql`

**Completed Work:**
- ✅ Permission-based authorization (not role-based)
- ✅ Privilege escalation prevention (cannot grant permissions you do not hold)
- ✅ Separation of duties (ContentEditor ≠ ContentApprover)
- ✅ Authorization in pipeline (before validation, before handler)
- ✅ 30+ permission codes with role mapping
- ✅ Drift test (portal permission codes = database permission codes)
- ✅ Audit on every permission grant/revoke
- ✅ Security event logging on refusal (outside transaction)

**Remaining Work:**
- Impersonation (deliberately unimplemented—needs legal review)

**Status:** ✅ Complete — Production ready

---

#### 3. Users & Roles Management

**Purpose:** User administration, role CRUD, role assignment

**Current Implementation:**
- Database: `Identity.User`, `Identity.Role`, `Identity.UserRole`, `Identity.UserDevice`
- Stored Procedures: `usp_User_Search`, `usp_User_Get`, `usp_User_SetLockout`, `usp_User_ChangePassword`, `usp_Role_Create`, `usp_Role_SetPermissions`
- Repository: `UserRepository`, `RoleRepository`
- CQRS: `SearchUsersQuery`, `GetUserQuery`, `SetLockoutCommand`, `CreateRoleCommand`, etc.
- API: `GET /api/v1/admin/users`, `{id}`, `{id}/lock`, `POST /api/v1/admin/roles`
- Portal: Users list + detail, roles CRUD, role matrix
- Tests: `UserManagementTests`, `RoleManagementTests`

**Completed Work:**
- ✅ User search (paging, filtering by role/status)
- ✅ User detail (with roles, devices, recent activity)
- ✅ Account lockout/unlock (ends all live sessions)
- ✅ Password change
- ✅ Role CRUD (with permission mapping)
- ✅ SuperAdmin bootstrap (only manual SQL for first account)
- ✅ Device tracking (for security stamp revocation)
- ✅ Last administrator guard (cannot demote final admin)
- ✅ System role protection (cannot delete built-in roles)

**Remaining Work:**
- None — feature complete

**Status:** ✅ Complete — Production ready

---

#### 4. Audit Trail

**Purpose:** Immutable record of all state changes

**Current Implementation:**
- Database: `Audit.AuditLog` (append-only), `Security.SecurityEvent`
- Stored Procedures: `usp_Audit_Log` (called by every command), `usp_SecurityEvent_Record`
- API: Query endpoint for audit history (via CMS endpoints)
- Portal: Audit viewer with filtering and search
- Tests: `AuditAppendOnlyTest`, `AuditContractTest`

**Completed Work:**
- ✅ Append-only audit table (no update/delete)
- ✅ Before/after state on commands (for content edits, role changes)
- ✅ Security event logging (login, lockout, permission grant, refusal)
- ✅ Actor identification (user id)
- ✅ Timestamp (UTC)
- ✅ Portal viewer with filtering
- ✅ Tested: audit never updated or deleted

**Remaining Work:**
- Audit retention policy (log rotation/archive)
- Performance optimization for large volumes (table partitioning by date)

**Status:** ✅ Complete — Production ready

---

#### 5. Feature Flags

**Purpose:** Runtime on/off switch for features, gradual rollout, kill switches

**Current Implementation:**
- Database: `Configuration.FeatureFlag`
- Stored Procedures: `usp_FeatureFlag_GetAll` (cached), `usp_FeatureFlag_Set`
- Repository: `FeatureFlagRepository`
- CQRS: `FeatureFlagBehavior` (pipeline middleware)
- API: All endpoints check `IRequireFeature`
- Portal: Feature flag UI (on/off per environment)
- Tests: `FeatureFlagTests`, seed tests assert no stale flag names

**Completed Work:**
- ✅ Binary feature flags (on/off)
- ✅ Deterministic bucketing (same user always same bucket)
- ✅ 30-second cache (kill-switches take ~30s to bite)
- ✅ Default-to-enabled (typo in flag name disables gate, not feature)
- ✅ Gradual rollout via bucketing
- ✅ Audit on every flag change

**Remaining Work:**
- Multi-variant flags (not just on/off)
- User segment targeting (only flag for certain roles)

**Status:** ✅ Complete — Production ready

---

#### 6. Settings & Configuration

**Purpose:** Global settings (notification quiet hours, data retention, etc.)

**Current Implementation:**
- Database: `Configuration.Setting`
- Stored Procedures: `usp_Setting_Get`, `usp_Setting_Set`
- Repository: `SettingRepository`
- CQRS: `GetSettingQuery`, `SetSettingCommand`
- API: `GET /api/v1/admin/settings/{key}`, `POST /api/v1/admin/settings/{key}`
- Portal: Settings form
- Tests: `SettingTests`

**Completed Work:**
- ✅ Key-value store for configuration
- ✅ Per-environment settings (dev/staging/prod)
- ✅ Audit on every change

**Remaining Work:**
- Typed settings (currently all strings—needs abstraction)

**Status:** ✅ Complete — Production ready

---

### Content Management (CMS)

#### 7. CMS Core

**Purpose:** Write, translate, review, publish health content

**Current Implementation:**
- Database: `CMS.Content`, `CMS.ContentTranslation`, `CMS.ContentVersion`, `CMS.Approval`, `CMS.ContentPublished`
- Stored Procedures: `usp_Content_Search`, `usp_Content_Create`, `usp_Content_Get`, `usp_Content_GetForClient`, `usp_Content_Publish`, `usp_Content_Restore`
- Repository: `ContentRepository`
- CQRS: `SearchContentQuery`, `GetContentQuery`, `CreateContentCommand`, `PublishContentCommand`, `RestoreContentCommand`, etc.
- API: `GET /api/v1/admin/content`, `POST /api/v1/admin/content`, `GET /api/v1/client/content/{id}`
- Portal: Content list, editor with tabs per language, approval workflow UI
- Mobile: Read-only access via sync (currently offline only—see PD-1)
- Tests: `ContentManagementTests`, `cms_workflow_test.sql`

**Completed Work:**
- ✅ Content CRUD (create, read, update, delete)
- ✅ Versioning (every edit creates an immutable version)
- ✅ JSON snapshots (complete item state per version)
- ✅ Approval workflow (editor → approver → publish)
- ✅ Publish as a pointer move (cheap, atomic, no cascade)
- ✅ Restore (writes forward, never backward)
- ✅ Version history viewer in portal
- ✅ ETag (If-Match) for optimistic concurrency
- ✅ Search (full-text on title and body)
- ✅ Bulk operations (publish, delete, restore)
- ✅ Audit (before/after state on every change)
- ✅ Tested: approval workflow enforced in database

**Remaining Work:**
- Content scheduling UI (schema ready, handler pending)
- Draft/published lane in portal (schema ready)

**Status:** ✅ Mostly complete — Ready for production use

---

#### 8. Content Localization

**Purpose:** Multi-language content with fallback chain

**Current Implementation:**
- Database: `CMS.ContentTranslation` (language_code, translatable strings)
- Stored Procedures: `usp_Content_GetForClient` (returns en-GB with fallback)
- API: `GET /api/v1/client/content/{id}?language=fr-FR` (falls back to en-GB)
- Mobile: `l10n.yaml` configured for en-GB, fr (partial, not deployed)
- Portal: Per-language tabs in content editor
- Tests: `LocalizationTests`

**Completed Work:**
- ✅ Multi-language storage (en-GB, en-US, fr-FR, etc.)
- ✅ Fallback to en-GB if target language missing
- ✅ Localization sourced from published version snapshots
- ✅ Portal editing per language in tabs

**Remaining Work:**
- Mobile app localization (partial—not yet in Play Store)
- Non-English marketing copy translation

**Status:** ✅ Complete — Ready for deployment

---

#### 9. Content Targeting

**Purpose:** Show/hide content based on geography, pregnancy week, season, app version

**Current Implementation:**
- Database: `CMS.ContentSchedule` (country_code, week_min, week_max, season, min_app_version, publish_window)
- Stored Procedures: `usp_Content_GetForClient` (filters by all targeting dimensions)
- API: Automatic (passed to client via content detail)
- Mobile: Filters content list by week, season, etc.
- Portal: Targeting UI (checkboxes per dimension)
- Tests: `TargetingTests`

**Completed Work:**
- ✅ Country targeting (country_code filter)
- ✅ Week targeting (pregnancy week range)
- ✅ Season targeting (calendar months)
- ✅ App version targeting (min_app_version gate)
- ✅ Publish window (scheduled show/hide)
- ✅ Narrowing distribution during incident (operator control, not approval-gated)

**Remaining Work:**
- Publish window implementation (scheduled batch job)

**Status:** ✅ Mostly complete — Scheduling pending

---

#### 10. Content Scheduling

**Purpose:** Scheduled publication and hiding of content

**Current Implementation:**
- Database: `CMS.ContentSchedule` has `publish_window_start`, `publish_window_end`
- Stored Procedures: None yet for scheduled ops
- CQRS: None yet
- API: None yet
- Portal: UI exists to set dates, but enforcement is manual
- Tests: None yet

**Completed Work:**
- ✅ Schema design

**Remaining Work:**
- ❌ Stored procedures for time-based filtering
- ❌ Scheduled job to publish/hide at time
- ❌ Tests

**Status:** 🟡 Partial — Schema designed, implementation pending

---

### Health Features (Mobile-First)

#### 11. Due Date Calculator

**Purpose:** Obstetric dating methods (LMP, ultrasound, etc.) with ACOG redating

**Current Implementation:**
- Mobile: `lib/features/due_date/`
- Domain: `DueDateCalculation` (ACOG-compliant math)
- UI: Shows all methods side-by-side, never picks one as "correct"
- Tests: ✅ 15+ tests (ACOG table verified)
- Status: ✅ Complete, offline, no backend sync

**Completed Work:**
- ✅ Last menstrual period (LMP) dating
- ✅ Ultrasound dating (10–13 weeks, 14+ weeks, third trimester)
- ✅ ACOG redating table (automatically reconciles conflicting dates)
- ✅ All methods shown, none preferred (regulatory compliance)
- ✅ Accessible date pickers (semantic labels, high contrast)

**Remaining Work:**
- None — feature complete

**Status:** ✅ Production ready — This is an ASO keyword

---

#### 12. Onboarding

**Purpose:** First launch setup (address terms, GDPR consent, etc.)

**Current Implementation:**
- Mobile: `lib/features/onboarding/`
- UI: Four screens (welcome, address terms, consent, ready)
- Tests: ✅ Widget tests
- Status: ✅ Complete, offline, no backend sync

**Completed Work:**
- ✅ Customizable address terms (the app says "pregnant person", you can choose pronouns)
- ✅ GDPR consent flow
- ✅ Localization support (l10n)
- ✅ One-time flow (persist in local DB)

**Remaining Work:**
- None — feature complete

**Status:** ✅ Production ready

---

#### 13. Hospital Bag Checklist

**Purpose:** Prepare for hospital or birth center visit with categorized checklist

**Current Implementation:**
- Database: `Health.HospitalBagItem`, `Health.HospitalBagPhase`
- Mobile: `lib/features/checklist/` (full CRUD)
- UI: Phased items (Trimester 1, 2, 3, Labor, Postpartum)
- Tests: ✅ Complete widget tests
- Status: ✅ Complete, offline, no backend sync

**Completed Work:**
- ✅ Phased item visibility (show/hide by pregnancy stage)
- ✅ Add/edit/delete items (user customization)
- ✅ Categories (Mother, Baby, Partner, etc.)
- ✅ Checked/unchecked state (persistent in local DB)
- ✅ Plain-text export
- ✅ No "Optional" category (regulatory decision in ADR)
- ✅ No "Mother" heading (inclusive language)

**Remaining Work:**
- None — feature complete

**Status:** ✅ Production ready

---

#### 14. Birth Preferences

**Purpose:** Document birth plan (pain relief, delivery position, etc.)

**Current Implementation:**
- Database: `Health.BirthPreference`
- Mobile: `lib/features/birth_preferences/`
- Schema: Complete (supports all ACOG preference categories)
- UI: Partial (data layer done, UI blocked on legal review)
- Tests: ✅ Domain tests
- Status: 🟡 Blocked — ACOG legal review of content pending

**Completed Work:**
- ✅ Database schema
- ✅ Domain model
- ✅ Data layer (Drift DAO)
- ✅ Export support

**Remaining Work:**
- ❌ US content (ACOG review needed)
- ❌ UI screens

**Status:** 🟡 Blocked on legal — UK content can ship independently

---

#### 15. Kick Counter

**Purpose:** Track fetal movement (no threshold, no alert)

**Current Implementation:**
- Database: `Health.KickEntry`
- Mobile: `lib/features/kick_counter/`
- Domain: `KickCounterModel` (tracks entries, time between movements)
- UI: Partial (buttons work, history partial)
- Tests: 🟡 Partial
- Status: 🟡 Data model complete, UI in progress

**Completed Work:**
- ✅ Database schema
- ✅ Domain model
- ✅ Drift DAO
- ✅ Entry logging (tap to count)
- ✅ No thresholds (regulatory compliance)

**Remaining Work:**
- ❌ UI polish (history, analytics graph)
- ❌ Export/share
- ❌ Full test coverage

**Status:** 🟡 Partial — Data layer complete, UI pending

---

#### 16. Contraction Timer

**Purpose:** Time and log contractions (no alert)

**Current Implementation:**
- Database: `Health.ContractionEntry`
- Mobile: `lib/features/contraction_timer/`
- Domain: `ContractionTimerModel`
- UI: Partial (timer works, history partial)
- Tests: 🟡 Partial
- Status: 🟡 Data model complete, UI in progress

**Completed Work:**
- ✅ Database schema
- ✅ Domain model (tracks duration, interval)
- ✅ Drift DAO
- ✅ Stopwatch UI

**Remaining Work:**
- ❌ History view
- ❌ Stats (average interval, contraction duration)
- ❌ Export
- ❌ Full test coverage

**Status:** 🟡 Partial — Data model complete, UI pending

---

#### 17. Body Log

**Purpose:** Log symptoms or observations

**Current Implementation:**
- Database: `Health.BodyLogEntry`
- Mobile: `lib/features/body_log/`
- Domain: `BodyLogModel`
- UI: Partial (entry form works, history partial)
- Tests: 🟡 Partial
- Status: 🟡 Data model complete, UI in progress

**Completed Work:**
- ✅ Database schema
- ✅ Domain model
- ✅ Drift DAO
- ✅ Entry form with categories

**Remaining Work:**
- ❌ History view
- ❌ Timeline visualization
- ❌ Export
- ❌ Full test coverage

**Status:** 🟡 Partial — Data model complete, UI pending

---

#### 18. Weekly Content Delivery

**Purpose:** Show pregnancy stage-appropriate wellness content (snippets, articles)

**Current Implementation:**
- Database: `CMS.Content` (tagged with week range)
- Mobile: `lib/features/content/`
- API: Not yet (currently offline)
- Status: ⛔ Blocked — Clinical review required before any content ships

**Blocked On:**
- Clinical review of content wellness snippets (midwife or OB review)
- ACOG guidance clearance

**Remaining Work:**
- ❌ Backend API for content sync
- ❌ UI screens
- ❌ Tests

**Status:** ⛔ Not started — Blocked on compliance

---

#### 19. Daily Check-in

**Purpose:** Simple questions about today (mood, energy, symptoms)

**Current Implementation:**
- Database: Schema exists
- Mobile: `lib/features/checkin/` partial
- Domain: Partial
- UI: Partial (questions work, history partial)
- Tests: 🟡 Partial

**Completed Work:**
- ✅ Database schema
- ✅ Question list
- ✅ Entry form

**Remaining Work:**
- ❌ History view
- ❌ Trends/insights (carefully worded to avoid advice)
- ❌ Repeat pattern (daily reminders)
- ❌ Export

**Status:** 🟡 Partial — UI in progress

---

#### 20. Wellness Insights

**Purpose:** Articles and snippets (pregnancy tips, nutrition, exercise)

**Current Implementation:**
- Mobile: `lib/features/insights/`
- Content: 300+ snippets (inline, not from CMS)
- Tests: ✅ 425 total (plus guards)
- Status: 🟡 Partial — Articles need compliance rewrite

**Completed Work:**
- ✅ 300+ snippets (carefully worded)
- ✅ Categories (nutrition, exercise, sleep, mental health, etc.)
- ✅ Browsable UI

**Blocked On:**
- **RC-1:** 25 articles need FDA compliance rewrite (dose targets, outcome claims)
- **RC-2:** All user-facing strings need compliance audit

**Remaining Work:**
- ❌ Rewrite 25 articles to compliance standard
- ❌ Add insights module to guard tests
- ❌ Clinical review

**Status:** 🟡 Partial — **Blocked on RC-1, RC-2**

---

#### 21. Global Search

**Purpose:** Full-text search across all content (offline index)

**Current Implementation:**
- Mobile: `lib/features/search/`
- Index: Offline, built at launch
- Tests: ✅ Complete

**Completed Work:**
- ✅ Offline search index (built from local DB)
- ✅ Full-text search (title, body, snippet text)
- ✅ Relevance ranking
- ✅ Instant results as you type
- ✅ Recently searched tracking

**Remaining Work:**
- None — feature complete

**Status:** ✅ Production ready

---

#### 22. Export & Import

**Purpose:** Backup/restore all user data (pregnancy record, preferences, logs)

**Current Implementation:**
- Database: Full schema supports export
- Mobile: `lib/features/backup/`
- Format: JSON or plain text
- UI: Partial (export works, import partial)
- Tests: 🟡 Partial

**Completed Work:**
- ✅ Full JSON export (all health data, preferences, settings)
- ✅ Plain-text checklist export (shareable with partner)
- ✅ File sharing (email, messaging)
- ✅ Re-import from JSON

**Remaining Work:**
- ❌ Import UI polish
- ❌ Migration from old app (if applicable)
- ❌ CloudKit sync (blocked on PD-1)
- ❌ Full test coverage

**Blocked On:**
- **PD-1:** Cloud sync decision

**Status:** 🟡 Partial — **Launch blocker for Sprint B**

---

#### 23. Notifications

**Purpose:** Reminders for tracking, content, events

**Current Implementation:**
- Database: `Notifications.NotificationTemplate`, `NotificationSchedule`
- Mobile: Partial (receiving notifications from device)
- Backend: Schema designed, handlers not yet built
- Status: 🟡 Partial — **Blocked on backend**

**Completed Work:**
- ✅ Database schema (templates, campaigns, schedule)
- ✅ Mobile permissions framework
- ✅ Android notification integration

**Remaining Work (Slice 2):**
- ❌ Backend handlers (CreateCampaignCommand, SendNotificationCommand)
- ❌ FCM integration
- ❌ Scheduling job
- ❌ Quiet hours enforcement
- ❌ Per-user preferences

**Status:** 🟡 Partial — **Slice 2 (Backend Notifications)**

---

#### 24. Analytics

**Purpose:** Event tracking, funnels, retention, cohort analysis

**Current Implementation:**
- None yet

**Remaining Work (Slice 3):**
- ❌ Database schema
- ❌ Event ingestion API
- ❌ Query builder
- ❌ Portal dashboard

**Status:** ⛔ Not started — **Slice 3 (Backend Analytics)**

---

#### 25. Subscriptions

**Purpose:** Premium features, store receipt validation

**Current Implementation:**
- None yet

**Remaining Work (Slice 4):**
- ❌ Database schema (plans, entitlements, receipts)
- ❌ Store receipt validation (Google Play, iOS)
- ❌ Entitlement gating
- ❌ Portal management

**Status:** ⛔ Not started — **Slice 4 (Subscriptions)**

---

#### 26. Widgets

**Purpose:** Home screen widget (next appointment, today's mood, etc.)

**Current Implementation:**
- Mobile: `lib/features/widgets/` partial
- Android: Home widget framework integrated
- Status: 🟡 Partial

**Completed Work:**
- ✅ Android home widget framework
- ✅ Quick actions (launch app, log contraction)
- 🟡 Today's summary widget (partial)

**Remaining Work:**
- ❌ Appointment/reminder widget
- ❌ Dashboard widget (stats, mood trends)
- ❌ Interactive widget actions

**Status:** 🟡 Partial — Basic widget working

---

## Definition of Done (Per Module)

Each module is "complete" when:

1. **Database**
   - ✅ Schema exists (tables, indexes, constraints)
   - ✅ No stale migrations or orphaned tables
   - ✅ Audit logging on all mutations
   - ✅ Referential integrity (FK constraints)

2. **Stored Procedures**
   - ✅ All procedures named correctly (`usp_<Area>_<Action>`)
   - ✅ Named result columns (no `SELECT *`)
   - ✅ Idempotent (safe to re-run)
   - ✅ Tested by assertion suite

3. **Repository**
   - ✅ One method per procedure
   - ✅ Result materialization only (no business logic)
   - ✅ Connection opened once, closed after
   - ✅ No LINQ or query builders

4. **CQRS**
   - ✅ Command/Query request class
   - ✅ Handler (orchestration only)
   - ✅ Validator (FluentValidation)
   - ✅ Marks `IRequirePermission` if applicable
   - ✅ Marks `IRequireFeature` if behind a flag

5. **API**
   - ✅ Endpoint defined (GET/POST/PUT/DELETE)
   - ✅ Route correct (`/api/v1/...`)
   - ✅ Authorization header checked
   - ✅ Response documented (ApiResponse<T>)
   - ✅ Status codes honest (not all 200s)

6. **Portal UI**
   - ✅ Component built (React + MUI)
   - ✅ Form validation (client-side + server-side)
   - ✅ Error messages from API (not replaced)
   - ✅ ETag support (If-Match on writes)
   - ✅ No direct `fetch()` calls (use client.ts)

7. **Mobile UI**
   - ✅ Screen built (StatelessWidget)
   - ✅ State management (Riverpod controller)
   - ✅ Accessibility (semantic labels)
   - ✅ Localization (all strings via l10n)
   - ✅ Offline-first (no network calls yet—see PD-1)

8. **Tests**
   - ✅ Unit tests (domain logic)
   - ✅ Widget tests (mobile UI)
   - ✅ Integration tests (real database for backend)
   - ✅ All guards passing
   - ✅ Coverage >70% (excluding generated code)

9. **Documentation**
   - ✅ API documented at `/scalar/v1` (backend)
   - ✅ Module README with compliance notes
   - ✅ Known issues tracked
   - ✅ Roadmap entry updated

10. **Security**
    - ✅ No hardcoded secrets
    - ✅ No health data in logs/errors
    - ✅ No SQL injection vectors
    - ✅ Password material only in login path

---

## Next Steps by Priority

### Immediate (Sprint A — Release Readiness)

- **Mobile device testing** (Android 10, 12—not just API 36)
- **Orientation & lifecycle** testing
- **RC compliance phase** (FDA audit, legal review, medical review)

### Sprint B (Launch Blocker)

- **Export complete** (schema done, UI needs polish)
- **Backup exclusion** verified

### Sprint C (Birth Preferences)

- **ACOG legal review** (unblocks US content)
- Birth preferences UI

### Sprint D (MVP Screens)

- Kick counter UI
- Contraction timer UI
- Body log UI
- Weekly content (blocked on clinical review)

### Slices 2+ (Future)

| Slice | Contents | Unblocks |
|---|---|---|
| **2. Notifications** | Templates, campaigns, FCM | Four-eyes approval, operator password reset |
| **3. Analytics** | Event ingestion, funnels, cohorts | Data-informed roadmap |
| **4. Subscriptions** | Plans, store receipt validation | Revenue |
| **5. Privacy** | Account deletion, GDPR export, consent ledger | **Blocked on PD-1** |
| **6. Impersonation** | Consent model, time limit, banner | Support workflows |
| **7. Clinician** | Shared summaries, scoped access | Clinical partnerships |

---

## For Detailed Information

- **Backend architecture:** `docs/ARCHITECTURE.md`
- **API endpoints:** `docs/API_CONTRACTS.md`
- **Database schema:** `docs/DATABASE.md`
- **Deployment:** `docs/DEPLOYMENT.md`
- **Testing:** `docs/TESTING.md`
