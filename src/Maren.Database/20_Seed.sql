/* Required for filtered indexes and indexes on computed columns. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Reference data.

    Idempotent throughout — this runs on every deployment, so every insert is
    guarded. Seed data that only works on an empty database is seed data that
    stops being run, and then drifts.
*/

-- Languages ------------------------------------------------------------------
MERGE [Identity].[Language] AS t
USING (VALUES
    ('en-GB','English (UK)',0),
    ('en-US','English (US)',0),
    ('es-ES','Espanol',0),
    ('fr-FR','Francais',0),
    ('de-DE','Deutsch',0),
    ('ur-PK','Urdu',1),
    ('ar-SA','Arabic',1)
) AS s(Code, Name, IsRightToLeft) ON t.Code = s.Code
WHEN NOT MATCHED THEN INSERT (Code, Name, IsRightToLeft)
VALUES (s.Code, s.Name, s.IsRightToLeft);
GO

-- Countries ------------------------------------------------------------------
MERGE [Identity].[Country] AS t
USING (VALUES
    ('GB','United Kingdom','en-GB'),
    ('US','United States','en-US'),
    ('IE','Ireland','en-GB'),
    ('AU','Australia','en-GB'),
    ('CA','Canada','en-US'),
    ('NZ','New Zealand','en-GB'),
    ('PK','Pakistan','en-GB'),
    ('IN','India','en-GB'),
    ('ES','Spain','es-ES'),
    ('FR','France','fr-FR'),
    ('DE','Germany','de-DE')
) AS s(IsoCode, Name, DefaultLanguageCode) ON t.IsoCode = s.IsoCode
WHEN NOT MATCHED THEN INSERT (IsoCode, Name, DefaultLanguageCode)
VALUES (s.IsoCode, s.Name, s.DefaultLanguageCode);
GO

-- Permissions ----------------------------------------------------------------
/*  Codes are module.action. Grouped by Category so the admin portal can
    render a permission matrix without a hardcoded layout. */
MERGE [Identity].[Permission] AS t
USING (VALUES
    ('users.read','View users','Users'),
    ('users.write','Edit users','Users'),
    ('users.delete','Delete or erase users','Users'),
    ('users.impersonate','Impersonate a user','Users'),
    ('content.read','View content','Content'),
    ('content.write','Create and edit content','Content'),
    ('content.publish','Publish content','Content'),
    ('content.translate','Manage translations','Content'),
    ('media.read','View media library','Content'),
    ('media.write','Upload and delete media','Content'),
    ('flags.read','View feature flags','Configuration'),
    ('flags.write','Change feature flags','Configuration'),
    ('settings.read','View settings','Configuration'),
    ('settings.write','Change settings','Configuration'),
    ('notifications.read','View campaigns','Notifications'),
    ('notifications.write','Create and edit campaigns','Notifications'),
    ('notifications.send','Send or schedule campaigns','Notifications'),
    ('reports.read','View reports','Reporting'),
    ('reports.export','Export reports','Reporting'),
    ('analytics.read','View analytics','Reporting'),
    ('support.read','View support tickets','Support'),
    ('support.write','Respond to tickets','Support'),
    ('audit.read','View audit logs','Security'),
    ('roles.read','View roles and permissions','Security'),
    ('roles.write','Change roles and permissions','Security')
) AS s(Code, Description, Category) ON t.Code = s.Code
WHEN NOT MATCHED THEN INSERT (Code, Description, Category)
VALUES (s.Code, s.Description, s.Category);
GO

-- Roles ----------------------------------------------------------------------
MERGE [Identity].[Role] AS t
USING (VALUES
    ('Member','An app user',1),
    ('SuperAdmin','Full access',1),
    ('ContentEditor','Writes and publishes content',1),
    ('Translator','Manages translations only',1),
    ('SupportAgent','Handles tickets and user lookups',1),
    ('Marketing','Runs campaigns and reads analytics',1),
    ('Doctor','Reads shared summaries only',1)
) AS s(Name, Description, IsSystem) ON t.Name = s.Name
WHEN NOT MATCHED THEN INSERT (Name, Description, IsSystem)
VALUES (s.Name, s.Description, s.IsSystem);
GO

-- Role permissions -----------------------------------------------------------
/*  SuperAdmin is granted everything by joining rather than by listing, so a
    permission added later is picked up on the next deployment instead of
    silently missing. */
INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM [Identity].[Role] r
CROSS JOIN [Identity].[Permission] p
WHERE r.Name = 'SuperAdmin'
  AND NOT EXISTS (SELECT 1 FROM [Identity].[RolePermission] rp
                  WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM [Identity].[Role] r
JOIN [Identity].[Permission] p ON p.Code IN (
    'content.read','content.write','content.publish','content.translate',
    'media.read','media.write')
WHERE r.Name = 'ContentEditor'
  AND NOT EXISTS (SELECT 1 FROM [Identity].[RolePermission] rp
                  WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM [Identity].[Role] r
JOIN [Identity].[Permission] p ON p.Code IN (
    'content.read','content.translate')
WHERE r.Name = 'Translator'
  AND NOT EXISTS (SELECT 1 FROM [Identity].[RolePermission] rp
                  WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM [Identity].[Role] r
JOIN [Identity].[Permission] p ON p.Code IN (
    'users.read','support.read','support.write')
WHERE r.Name = 'SupportAgent'
  AND NOT EXISTS (SELECT 1 FROM [Identity].[RolePermission] rp
                  WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM [Identity].[Role] r
JOIN [Identity].[Permission] p ON p.Code IN (
    'notifications.read','notifications.write','notifications.send',
    'analytics.read','reports.read')
WHERE r.Name = 'Marketing'
  AND NOT EXISTS (SELECT 1 FROM [Identity].[RolePermission] rp
                  WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

-- Settings -------------------------------------------------------------------
MERGE [Administration].[Setting] AS t
USING (VALUES
    ('app.maintenance_mode','false','bool','General','Blocks the app with a maintenance screen',1),
    ('app.maintenance_message','','string','General','Shown during maintenance',1),
    ('app.privacy_url','','string','Legal','Privacy policy URL',1),
    ('app.terms_url','','string','Legal','Terms of use URL',1),
    ('app.support_email','','string','Support','Shown on the support screen',1),
    ('sync.interval_minutes','60','int','Sync','How often the client attempts a background sync',1),
    ('sync.batch_size','200','int','Sync','Rows per sync page',1),
    ('reminders.default_morning','08:30','string','Reminders','Default morning check-in time',1),
    ('reminders.quiet_start','22:00','string','Reminders','Default quiet hours start',1),
    ('reminders.quiet_end','07:30','string','Reminders','Default quiet hours end',1),
    ('content.rotation_window_days','30','int','Content','Minimum days before a snippet may repeat',1)
) AS s([Key],[Value],DataType,Category,Description,IsClientVisible)
   ON t.[Key] = s.[Key]
WHEN NOT MATCHED THEN INSERT ([Key],[Value],DataType,Category,Description,IsClientVisible)
VALUES (s.[Key],s.[Value],s.DataType,s.Category,s.Description,s.IsClientVisible);
GO

-- Content categories ---------------------------------------------------------
MERGE [Content].[Category] AS t
USING (VALUES
    ('nutrition',1),('movement',2),('mentalHealth',3),('sleep',4),
    ('hydration',5),('relationships',6),('partner',7),('birthPrep',8),
    ('recovery',9),('womensHealth',10),('cycle',11),('period',12),('hormones',13)
) AS s([Key], SortOrder) ON t.[Key] = s.[Key]
WHEN NOT MATCHED THEN INSERT ([Key], SortOrder) VALUES (s.[Key], s.SortOrder);
GO
