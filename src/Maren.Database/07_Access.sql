/*  07_Access.sql
    ---------------------------------------------------------------------------
    Tables added by the Users & Access Management slice.

    Almost nothing: Identity.User, Role, Permission, RolePermission and UserRole
    already exist and already carry IsLockedOut, SecurityStamp and RowVersion.
    This slice builds the administration layer over them rather than reshaping
    them.

    Re-runnable.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Identity.SecurityStampRevocation
-- ---------------------------------------------------------------------------
/*
    Closes the window between revoking someone's access and their access token
    expiring.

    Permissions travel as claims in a 15-minute access token. Without this
    table, locking a compromised account or removing an administrator's role
    leaves them fully privileged for up to fifteen minutes — which is precisely
    the situation the action was taken to end.

    The API caches this for 30 seconds and compares each request's token stamp
    against the current one. One row per revoked user, upserted, so it stays
    small enough to load whole.
*/
IF OBJECT_ID('Identity.SecurityStampRevocation') IS NULL
BEGIN
    CREATE TABLE [Identity].[SecurityStampRevocation] (
        UserId        UNIQUEIDENTIFIER NOT NULL,
        /*  The stamp that is now current. A token carrying anything else is
            stale and must be refused. */
        SecurityStamp UNIQUEIDENTIFIER NOT NULL,
        RevokedUtc    DATETIME2(3) NOT NULL
                      CONSTRAINT DF_SecurityStampRevocation_RevokedUtc
                      DEFAULT SYSUTCDATETIME(),
        RevokedBy     UNIQUEIDENTIFIER NULL,
        /*  Shown in the audit trail. "Why is this person signed out" is the
            first question asked and the hardest to answer after the fact. */
        Reason        NVARCHAR(300) NULL,

        CONSTRAINT PK_SecurityStampRevocation PRIMARY KEY CLUSTERED (UserId),
        CONSTRAINT FK_SecurityStampRevocation_User FOREIGN KEY (UserId)
            REFERENCES [Identity].[User](UserId)
    );
END
GO

/*  Supports the periodic load of everything revoked recently. The API does not
    need rows older than the longest possible token lifetime, but keeping them
    costs nothing and they are useful evidence during an incident. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_SecurityStampRevocation_RevokedUtc')
    CREATE INDEX IX_SecurityStampRevocation_RevokedUtc
        ON [Identity].[SecurityStampRevocation](RevokedUtc DESC);
GO

-- ---------------------------------------------------------------------------
-- Supporting indexes on existing tables
-- ---------------------------------------------------------------------------
/*  User search filters on these. Without them the admin user list is a scan of
    every account on the platform, which is fine at a thousand users and not at
    a million. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_User_Search')
    CREATE INDEX IX_User_Search
        ON [Identity].[User](IsDeleted, IsLockedOut, CreatedOn DESC)
        INCLUDE (Email, LanguageCode, IsEmailConfirmed);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_UserRole_RoleId')
    CREATE INDEX IX_UserRole_RoleId
        ON [Identity].[UserRole](RoleId) INCLUDE (UserId);
GO

/*  The audit viewer's three filters. Descending on time because every query
    this table serves is "what happened recently". */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditLog_Occurred')
    CREATE INDEX IX_AuditLog_Occurred
        ON [Audit].[AuditLog](OccurredUtc DESC)
        INCLUDE (ActorUserId, [Action], EntityType, EntityId);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditLog_Entity')
    CREATE INDEX IX_AuditLog_Entity
        ON [Audit].[AuditLog](EntityType, EntityId, OccurredUtc DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditLog_Actor')
    CREATE INDEX IX_AuditLog_Actor
        ON [Audit].[AuditLog](ActorUserId, OccurredUtc DESC);
GO

PRINT 'Access schema applied.';
GO
