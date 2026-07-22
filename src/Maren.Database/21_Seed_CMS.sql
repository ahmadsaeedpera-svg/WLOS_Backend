/*  21_Seed_CMS.sql
    ---------------------------------------------------------------------------
    Permissions, the approver role, role grants and feature flags that the CMS
    needs to be operable.

    Separate from 20_Seed.sql because these rows arrived with the CMS and the
    original seed predates it. Keeping the split makes it obvious which rows a
    deployment gains when the CMS ships, and both files are idempotent so
    running them in either order converges on the same state.

    Re-runnable. Every statement is a MERGE or a guarded INSERT.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

/*  No USE. The database name is a deployment concern, and the other scripts in
    this folder are run with sqlcmd -d. Hardcoding it here would mean this one
    file silently targets the wrong database on any environment that names it
    differently. */

-- Permissions the CMS added ---------------------------------------------------
/*  content.review and content.publish are deliberately distinct. The workflow
    refuses to publish a version nobody approved, and that check is worthless if
    the same person holds both by default — separation of duties is the point of
    an approval step, not the paperwork around it. */
MERGE [Identity].[Permission] AS t
USING (VALUES
    ('content.review','Submit content for review and approve or reject it','Content'),
    ('content.delete','Delete content','Content'),
    ('content.restore','Restore an earlier version','Content'),
    ('media.manage','Manage the media library and its metadata','Content'),
    ('category.manage','Create and reorganise content categories','Content'),
    ('settings.manage','Change platform-wide settings','Configuration')
) AS s(Code, Description, Category) ON t.Code = s.Code
WHEN NOT MATCHED THEN INSERT (Code, Description, Category)
VALUES (s.Code, s.Description, s.Category);
GO

-- The eighth role -------------------------------------------------------------
/*  An approver reads and reviews but cannot write. Somebody who can edit the
    thing they are approving can approve their own change by editing it after
    approval, and the version pointer would still name an approved snapshot. */
MERGE [Identity].[Role] AS t
USING (VALUES
    ('ContentApprover','Reviews and approves content for publication',1)
) AS s(Name, Description, IsSystem) ON t.Name = s.Name
WHEN NOT MATCHED THEN INSERT (Name, Description, IsSystem)
VALUES (s.Name, s.Description, s.IsSystem);
GO

INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM [Identity].[Role] r
JOIN [Identity].[Permission] p ON p.Code IN (
    'content.read','content.review','content.publish','media.read','audit.read')
WHERE r.Name = 'ContentApprover'
  AND NOT EXISTS (SELECT 1 FROM [Identity].[RolePermission] rp
                  WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

/*  ContentEditor gains the new authoring permissions but NOT content.review:
    an editor submits for review, an approver decides. It also gains
    content.restore, because restoring writes a new version forward and is
    therefore an editing action, not a destructive one. */
INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM [Identity].[Role] r
JOIN [Identity].[Permission] p ON p.Code IN (
    'content.delete','content.restore','media.manage','category.manage')
WHERE r.Name = 'ContentEditor'
  AND NOT EXISTS (SELECT 1 FROM [Identity].[RolePermission] rp
                  WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

/*  SuperAdmin is re-granted by join so the six new codes are picked up. Same
    statement as 20_Seed.sql; repeated here so this file stands alone. */
INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM [Identity].[Role] r
CROSS JOIN [Identity].[Permission] p
WHERE r.Name = 'SuperAdmin'
  AND NOT EXISTS (SELECT 1 FROM [Identity].[RolePermission] rp
                  WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

-- CMS feature flags -----------------------------------------------------------
/*  All seeded enabled at 100%. These name capabilities that already work, so
    the flag is an off-switch for an incident, not a rollout gate — the one
    exception is the experimental editor, which is off and exists to be turned
    on for a named audience.

    RolloutPercent is meaningless for an admin-facing capability: an editor
    whose bulk publish works on Tuesday and not on Wednesday would file a bug,
    correctly. These are all-or-nothing. */
MERGE [Administration].[FeatureFlag] AS t
USING (VALUES
    ('cms_scheduling','Content scheduling',
     'Publish and unpublish at a future time.',1,100),
    ('cms_localization','Content localisation',
     'Per-language titles and bodies with fallback to en-GB.',1,100),
    ('cms_media','Media library',
     'Attach images and documents to content.',1,100),
    ('cms_version_compare','Version comparison',
     'Diff two versions of an item side by side.',1,100),
    ('cms_approval_workflow','Approval workflow',
     'Require an approval before an item can be published.',1,100),
    ('cms_bulk_publish','Bulk operations',
     'Apply publish, unpublish or delete to many items at once.',1,100),
    ('cms_preview','Content preview',
     'Render a draft as the mobile client would show it.',1,100),
    ('cms_search','Content search',
     'Full-text search across titles and bodies.',1,100),
    ('cms_experimental_editor','Experimental editor',
     'The rich block editor. Off until it has been through review.',0,0)
) AS s([Key], Name, Description, IsEnabled, RolloutPercent)
    ON t.[Key] = s.[Key]
WHEN NOT MATCHED THEN
    INSERT ([Key], Name, Description, IsEnabled, RolloutPercent)
    VALUES (s.[Key], s.Name, s.Description, s.IsEnabled, s.RolloutPercent);
GO

PRINT 'CMS seed applied.';
GO
