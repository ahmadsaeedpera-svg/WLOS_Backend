# Database Schema Overview

SQL Server 2025 schema with all tables, stored procedures, and business rules.

---

## Schema Organization

Database: `MarenPlatform`

### Schemas

| Schema | Purpose | Tables |
|---|---|---|
| `Identity` | Users, authentication, roles, tokens | User, Role, UserRole, RefreshToken, SecurityStamp |
| `Administration` | Administrators, system configuration | AdminFlag, SystemRole |
| `Health` | User health data (pregnancy, preferences, logs) | BirthPreference, HospitalBagItem, HospitalBagPhase, ContractionEntry, KickEntry, BodyLogEntry |
| `Content` | CMS (articles, snippets, wellness content) | Content, ContentTranslation, ContentVersion, ContentSchedule |
| `CMS` | Content management (approval, publishing) | Approval, ContentPublished, ContentMetadata |
| `Notifications` | Notification system | NotificationTemplate, NotificationCampaign, NotificationSchedule, NotificationLog, NotificationPreference |
| `Audit` | Immutable audit trail | AuditLog |
| `Security` | Security events (logins, permission changes, lockouts) | SecurityEvent |
| `Access` | Permissions and role assignments | Permission, PermissionRole |
| `Configuration` | Configurable settings | FeatureFlag, Setting |

---

## Key Tables

### Identity Schema

**User**
- PK: `UserId` (GUID)
- Email, DisplayName
- PasswordHash, PasswordSalt, PasswordIterations (PBKDF2-HMAC-SHA256)
- CreatedUtc, LastLoginUtc
- LockedUntilUtc (account lockout)
- SecurityStampId (for session revocation)

**Role**
- PK: `RoleId` (INT)
- Name (e.g., "SuperAdmin", "ContentEditor", "ContentApprover")
- IsSystemRole (cannot delete built-in roles)

**UserRole**
- FK: UserId, RoleId
- CreatedUtc
- PK: (UserId, RoleId)

**RefreshToken**
- PK: `TokenId` (GUID)
- FK: UserId
- TokenHash (SHA-256 of actual token)
- ExpiresUtc, CreatedUtc
- ReusedByTokenId (for reuse detection)

**SecurityStamp**
- PK: `StampId` (GUID)
- FK: UserId
- Version (incremented on lockout)
- UpdatedUtc
- TTL: ~30 seconds before revocation kicks in

---

### Health Schema

**BirthPreference**
- FK: UserId (optional—null for offline)
- PreferenceCategory (pain relief, position, environment, etc.)
- SelectedOption, Notes
- UpdatedUtc

**HospitalBagItem**
- PK: `ItemId` (INT)
- Content (text of the item)
- HospitalBagPhase (Trimester 1/2/3, Labor, Postpartum)
- Category (Baby, Partner, Mother, etc.)
- Order (sort sequence)

**ContractionEntry, KickEntry, BodyLogEntry**
- FK: UserId (optional—null for offline)
- EntryTime, Duration/Intensity
- SyncedUtc (null until synced)

---

### CMS Schema

**Content**
- PK: `ContentId` (GUID)
- Type (snippet, article, checklist_item, etc.)
- Slug (URL-safe name)
- CurrentVersionId (pointer to latest)
- PublishedVersionId (pointer to approved version clients read)
- CreatedUtc, UpdatedUtc

**ContentTranslation**
- FK: ContentId, Language (en, fr, de, etc.)
- Title, Body, Summary
- UpdatedUtc
- **Note:** This is live working copy. Clients read snapshots instead.

**ContentVersion**
- PK: `VersionId` (GUID)
- FK: ContentId
- SnapshotJson (complete item as JSON)
- CreatedByUserId, CreatedUtc
- Immutable (never updated)

**Approval**
- FK: VersionId
- ApprovedByUserId
- ApprovedUtc
- Immutable

**ContentPublished**
- FK: ContentId, VersionId (approved version)
- PublishedUtc
- UpdatedUtc (when pointer moved)

**ContentSchedule**
- FK: ContentId
- CountryCode (nullable for global)
- WeekMin, WeekMax (pregnancy weeks)
- Season (Jan-Feb, Mar-Apr, etc.)
- MinAppVersion
- PublishWindowStart, PublishWindowEnd
- UpdatedUtc

---

### Notifications Schema

**NotificationTemplate**
- PK: `TemplateId` (GUID)
- Name, Subject (email) or Title (push)
- BodyTemplate (with placeholders)
- Channel (email, sms, push)
- CreatedUtc

**NotificationCampaign**
- PK: `CampaignId` (GUID)
- TemplateId
- Name, Status (draft, scheduled, sent)
- ScheduledFor, SentUtc
- CreatedUtc

**NotificationSchedule**
- FK: CampaignId
- DayOfWeek, HourUtc (when to send)
- TimezoneName (user timezone)

**NotificationLog**
- FK: CampaignId, UserId
- SentUtc, Channel, Status
- ErrorMessage (if failed)
- Audit trail

**NotificationPreference**
- FK: UserId
- Channel (which channels user accepts)
- QuietHoursStart, QuietHoursEnd
- PreferredTimezone

---

### Access Schema

**Permission**
- PK: `PermissionCode` (string, e.g., "content.write")
- Description
- Created, Category (Auth, Content, Users, etc.)
- Over 30 permission codes defined

**PermissionRole**
- FK: PermissionCode, RoleId
- Immutable per design (changes go through procedures)

---

### Audit Schema

**AuditLog**
- PK: `LogId` (BIGINT, sequential)
- ActorUserId (who did it)
- CommandName (e.g., "PublishContent", "SetUserLockout")
- EntityType (Content, User, Role, etc.)
- EntityId (what was changed)
- BeforeState, AfterState (JSON snapshots for content edits)
- OccurredUtc (UTC timestamp)
- **Immutable:** No update, no delete (verified by test)

**SecurityEvent**
- PK: `EventId` (GUID)
- EventType (login_failure, login_success, lockout, permission_grant, permission_denied)
- ActorUserId, TargetUserId
- Details (reason for denial, etc.)
- OccurredUtc
- **Outside transaction:** Written even if command rolled back

---

### Configuration Schema

**FeatureFlag**
- PK: `FlagId` (INT)
- Name (e.g., "notifications_v1", "analytics_beta")
- Enabled (bool)
- BucketPercentage (0-100, for gradual rollout)
- UpdatedUtc

**Setting**
- PK: `SettingKey` (string)
- Value (string—typed by application)
- UpdatedUtc
- Examples: "notification_quiet_hours_start", "data_retention_days"

---

## Stored Procedures

### Authentication (11_Procs_Identity.sql)

- `usp_User_Register` — Create account, hash password
- `usp_User_GetForLogin` — Fetch for login (only proc touching password)
- `usp_User_RefreshToken` — Rotate refresh token, detect reuse
- `usp_User_ChangePassword` — Update password
- `usp_User_SetLockout` — Lock/unlock account, end all sessions

### Content Management (12_Procs_Content.sql)

- `usp_Content_Search` — Full-text search with paging
- `usp_Content_Create` — Create new content item
- `usp_Content_Get` — Fetch one (with version history)
- `usp_Content_GetForClient` — Fetch approved version snapshot (for sync/API)
- `usp_Content_CreateVersion` — New version (immutable snapshot)
- `usp_Content_Publish` — Move published pointer (if approved)
- `usp_Content_Restore` — Restore prior version (writes forward)
- `usp_Content_Delete` — Soft delete (mark archived)
- `usp_Content_Approve` — Record approval
- `usp_Content_BulkPublish` — Publish multiple

### Access Management (13_Procs_Access.sql)

- `usp_User_Search` — Find users (with paging, filtering)
- `usp_User_Get` — User detail (with roles, devices, activity)
- `usp_User_HasPermission` — Check if user has permission
- `usp_Role_Create` — Create custom role
- `usp_Role_SetPermissions` — Grant/revoke permissions (privilege escalation checks)
- `usp_User_AssignRole` — Assign role to user (checks escalation)
- `usp_User_RemoveRole` — Remove role (checks last admin)
- `usp_Audit_Get` — Fetch audit entries (for audit viewer)

### Configuration (14_Procs_Config.sql)

- `usp_FeatureFlag_GetAll` — Get all flags (cached)
- `usp_FeatureFlag_Set` — Enable/disable flag
- `usp_Setting_Get` — Fetch setting value
- `usp_Setting_Set` — Update setting

### Health (4_Health.sql, procedures pending)

- `usp_BirthPreference_Upsert` — Save preference
- `usp_BirthPreference_Get` — Fetch user's preferences
- `usp_HospitalBag_Search` — Search checklist items (by phase)

### Notifications (5_Content_Notifications_Audit.sql, handlers pending)

- `usp_Notification_Send` — Send one notification
- `usp_NotificationLog_Record` — Log delivery
- `usp_NotificationPreference_Get` — Fetch user preferences

---

## Assertion Suites

**cms_workflow_test.sql** — 17 assertions

- Content creation works
- Approval workflow enforced (cannot publish unapproved)
- Restore writes forward only (never backward)
- Version snapshot is immutable
- Published pointer moves atomically
- Targeting filters work (country, week, season)
- Content is soft-deletable

**access_test.sql** — 19 assertions

- Privilege escalation prevented
- User cannot grant own elevated permissions
- Self-demotion prevented
- Role deletion prevented if in use
- Last administrator cannot be demoted
- Permission enforcement on procedures
- Audit is append-only during account lifetime; account erasure is the one
  named exception (`usp_User_DeleteAccount`)

---

## Indexes

**Performance-critical indexes:**

- `Identity.User` — PK on UserId, unique on Email
- `Content` — FK on CurrentVersionId, PublishedVersionId
- `ContentVersion` — FK on ContentId, createdUtc
- `AuditLog` — Clustered on LogId (append-only, inserted sequentially)
- `FeatureFlag` — PK on FlagId, unique on Name
- `PermissionRole` — Composite (PermissionCode, RoleId)

**Filtered indexes:**

- `Identity.User` — on LockedUntilUtc > GETUTCDATE() (find locked users)
- `AuditLog` — on EntityType = 'Content' (content audit history)
- `SecurityEvent` — on EventType IN ('login_failure', 'permission_denied') (security events)

---

## Key Constraints

### Referential Integrity

- UserRole → User (cascade delete on user deletion)
- UserRole → Role (prevent delete if assigned)
- Approval → User, Content (restrict delete)
- ContentPublished → Content, Version (prevent delete)
- AuditLog → User (update, not delete—audit should survive user deletion)

### Business Rules (in procedures, not constraints)

- Only usp_User_GetForLogin and usp_User_Register may touch PasswordHash
- Only usp_Content_Publish may move ContentPublished
- Approval required before publish (usp_Content_Publish checks Approval exists)
- Privilege escalation prevented (usp_User_AssignRole checks permissions)

---

## For Detailed Information

- **Full schema:** `Maren-Backend/src/Maren.Database/` (SQL scripts)
- **Test procedures:** `Maren-Backend/src/Maren.Database/tests/`
- **Repositories:** `Maren-Backend/src/Maren.Persistence/` (Dapper data access)
- **Architecture:** `docs/ARCHITECTURE.md`
