/*  30_Indexes_ForeignKeys.sql

    Adds a supporting index to every foreign key that lacked one.

    Why
    ---
    A foreign key without an index on its own column costs twice. Joining
    parent to child scans the child, and deleting a parent scans the child
    again to check (or cascade) the reference. Twelve of this schema's
    foreign keys are ON DELETE CASCADE, so the second cost is not theoretical.

    Measured before this script, against a real instance:

        SELECT p.PregnancyId FROM Health.Pregnancy p WHERE p.UserId = '...'
        --> Clustered Index Scan(OBJECT:([Health].[Pregnancy].[PK_Pregnancy]),
            WHERE:([UserId]=CONVERT_IMPLICIT(...)))

    "Get my pregnancy" - the most common read in the health domain - was a
    full table scan. Eighteen foreign keys were in this state; see
    docs/DATABASE_REVIEW.md finding C-1 for the full list and evidence.

    Why these are not filtered indexes
    ----------------------------------
    Most tables here carry IsDeleted, and a filtered index
    (WHERE IsDeleted = 0) would be narrower and cheaper. It is the wrong
    choice for this particular job. A foreign key check and a cascade
    delete must be able to find *every* referencing row, including
    soft-deleted ones. An index that excludes them cannot serve the check,
    so the scan would remain on exactly the path this script exists to fix.

    Plain indexes serve both purposes: the optimiser seeks the foreign key
    column, then applies IsDeleted as a residual predicate.

    Naming follows the established convention: IX_<Table>_<Column>, matching
    the hand-written IX_Device_UserId already in 02_Identity.sql.

    Idempotent. Safe to re-run; each index is created only if absent.
    Purely additive - no table, column, procedure or contract is altered.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---------------------------------------------------------------------
   Identity
   --------------------------------------------------------------------- */

/*  RefreshToken is the highest-write table in the schema: rotation issues
    a row on every refresh. Revoking a user's sessions and listing their
    tokens both filter by UserId and both scanned. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_RefreshToken_UserId'
                 AND object_id = OBJECT_ID('[Identity].[RefreshToken]'))
    CREATE INDEX [IX_RefreshToken_UserId]
        ON [Identity].[RefreshToken] ([UserId]);
GO

/*  ON DELETE CASCADE. Removing a permission had to scan RolePermission to
    find the grants it must remove. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_RolePermission_PermissionId'
                 AND object_id = OBJECT_ID('[Identity].[RolePermission]'))
    CREATE INDEX [IX_RolePermission_PermissionId]
        ON [Identity].[RolePermission] ([PermissionId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_User_CountryId'
                 AND object_id = OBJECT_ID('[Identity].[User]'))
    CREATE INDEX [IX_User_CountryId]
        ON [Identity].[User] ([CountryId]);
GO

/* ---------------------------------------------------------------------
   Health

   Every table here is keyed by UserId in practice - the whole domain is
   "rows belonging to one person". None of these columns was indexed, so
   every per-user read scanned the table.
   --------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Pregnancy_UserId'
                 AND object_id = OBJECT_ID('[Health].[Pregnancy]'))
    CREATE INDEX [IX_Pregnancy_UserId]
        ON [Health].[Pregnancy] ([UserId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_HospitalBagItem_UserId'
                 AND object_id = OBJECT_ID('[Health].[HospitalBagItem]'))
    CREATE INDEX [IX_HospitalBagItem_UserId]
        ON [Health].[HospitalBagItem] ([UserId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ShareGrant_UserId'
                 AND object_id = OBJECT_ID('[Health].[ShareGrant]'))
    CREATE INDEX [IX_ShareGrant_UserId]
        ON [Health].[ShareGrant] ([UserId]);
GO

/*  DailyLog is a subtler case, and the reason the coverage test checks for
    filtered indexes separately.

    UX_DailyLog_User_Date already leads on UserId, so a naive check reports
    this foreign key as covered. It is filtered to IsDeleted = 0, which means
    it serves ordinary reads perfectly and cannot serve anything that must
    see soft-deleted rows: the reference check itself, and a GDPR export or
    admin view that deliberately includes deleted entries.

    The filtered index stays - it is the better index for the common path.
    This one exists for the paths it cannot reach. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_DailyLog_UserId'
                 AND object_id = OBJECT_ID('[Health].[DailyLog]'))
    CREATE INDEX [IX_DailyLog_UserId]
        ON [Health].[DailyLog] ([UserId]);
GO

/* ---------------------------------------------------------------------
   Content

   ContentApproval and ContentReview each hold two foreign keys. Each gets
   its own single-column index rather than one composite: a composite only
   supports a seek on its leading column, and both columns are used
   independently - by item when reading an item's history, by version when
   cascading a version delete.
   --------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentItem_CategoryId'
                 AND object_id = OBJECT_ID('[Content].[ContentItem]'))
    CREATE INDEX [IX_ContentItem_CategoryId]
        ON [Content].[ContentItem] ([CategoryId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentApproval_ContentItemId'
                 AND object_id = OBJECT_ID('[Content].[ContentApproval]'))
    CREATE INDEX [IX_ContentApproval_ContentItemId]
        ON [Content].[ContentApproval] ([ContentItemId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentApproval_ContentVersionId'
                 AND object_id = OBJECT_ID('[Content].[ContentApproval]'))
    CREATE INDEX [IX_ContentApproval_ContentVersionId]
        ON [Content].[ContentApproval] ([ContentVersionId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentReview_ContentItemId'
                 AND object_id = OBJECT_ID('[Content].[ContentReview]'))
    CREATE INDEX [IX_ContentReview_ContentItemId]
        ON [Content].[ContentReview] ([ContentItemId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentReview_ContentVersionId'
                 AND object_id = OBJECT_ID('[Content].[ContentReview]'))
    CREATE INDEX [IX_ContentReview_ContentVersionId]
        ON [Content].[ContentReview] ([ContentVersionId]);
GO

/*  IX_ContentSchedule_Due already exists but is filtered to
    Status = 'pending', so it cannot serve the cascade from ContentItem.
    This one is unfiltered and deliberately so. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentPublishSchedule_ContentItemId'
                 AND object_id = OBJECT_ID('[Content].[ContentPublishSchedule]'))
    CREATE INDEX [IX_ContentPublishSchedule_ContentItemId]
        ON [Content].[ContentPublishSchedule] ([ContentItemId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentItemTag_TagId'
                 AND object_id = OBJECT_ID('[Content].[ContentItemTag]'))
    CREATE INDEX [IX_ContentItemTag_TagId]
        ON [Content].[ContentItemTag] ([TagId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentAuthor_UserId'
                 AND object_id = OBJECT_ID('[Content].[ContentAuthor]'))
    CREATE INDEX [IX_ContentAuthor_UserId]
        ON [Content].[ContentAuthor] ([UserId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentAuthor_AvatarMediaId'
                 AND object_id = OBJECT_ID('[Content].[ContentAuthor]'))
    CREATE INDEX [IX_ContentAuthor_AvatarMediaId]
        ON [Content].[ContentAuthor] ([AvatarMediaId]);
GO

/* ---------------------------------------------------------------------
   Administration
   --------------------------------------------------------------------- */

/*  Feature flag evaluation reads a user's per-user overrides on the
    authenticated path, so this one sat behind a scan on a hot request. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_FeatureFlagAssignment_UserId'
                 AND object_id = OBJECT_ID('[Administration].[FeatureFlagAssignment]'))
    CREATE INDEX [IX_FeatureFlagAssignment_UserId]
        ON [Administration].[FeatureFlagAssignment] ([UserId]);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_SupportTicket_UserId'
                 AND object_id = OBJECT_ID('[Administration].[SupportTicket]'))
    CREATE INDEX [IX_SupportTicket_UserId]
        ON [Administration].[SupportTicket] ([UserId]);
GO

/* ---------------------------------------------------------------------
   Notifications
   --------------------------------------------------------------------- */

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Campaign_TemplateId'
                 AND object_id = OBJECT_ID('[Notifications].[Campaign]'))
    CREATE INDEX [IX_Campaign_TemplateId]
        ON [Notifications].[Campaign] ([TemplateId]);
GO
