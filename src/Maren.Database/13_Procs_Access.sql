/*  13_Procs_Access.sql
    ---------------------------------------------------------------------------
    Users, roles, permissions and audit.

    ## Two rules live here, not in C#

    A privilege check that only exists in the application layer is bypassed by
    anything that connects to the database instead — an import job, a support
    script, a future service. These two are enforced in the procedures:

      1. You cannot grant a permission you do not hold.
      2. You cannot remove your own access or lock yourself out.

    Rule 1 is the one that matters. Without it, `roles.write` IS `SuperAdmin`:
    the holder simply edits a role to include everything, or assigns themselves
    a role that already does.

    ## No password material, ever

    Identity.User holds PasswordHash, PasswordSalt and PasswordIterations. No
    procedure here selects them. Every result set names its columns — partly for
    the Dapper materialisation reason that broke three endpoints previously, and
    partly because SELECT * on this table puts password material on the wire to
    a browser.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_UserHoldsAllPermissionsOf — the escalation guard
-- ---------------------------------------------------------------------------
/*
    True when @ActorUserId's effective permissions are a superset of @RoleId's.

    A NULL actor is the system (migrations, scheduled jobs) and passes. That is
    deliberate: a background job has no interactive session to escalate from,
    and every API path supplies a real actor because ICurrentUser is required
    before the pipeline reaches a handler.
*/
IF OBJECT_ID('Identity.fn_UserHoldsAllPermissionsOfRole') IS NOT NULL
    DROP FUNCTION [Identity].[fn_UserHoldsAllPermissionsOfRole];
GO
CREATE FUNCTION [Identity].[fn_UserHoldsAllPermissionsOfRole](
    @ActorUserId UNIQUEIDENTIFIER,
    @RoleId      INT)
RETURNS BIT
AS
BEGIN
    IF @ActorUserId IS NULL RETURN 1;

    IF EXISTS (
        SELECT rp.PermissionId
        FROM [Identity].[RolePermission] rp
        WHERE rp.RoleId = @RoleId
        EXCEPT
        SELECT rp2.PermissionId
        FROM [Identity].[UserRole] ur
        JOIN [Identity].[RolePermission] rp2 ON rp2.RoleId = ur.RoleId
        WHERE ur.UserId = @ActorUserId)
        RETURN 0;

    RETURN 1;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Access_RotateSecurityStamp — internal
-- ---------------------------------------------------------------------------
/*
    Invalidates every live session for a user.

    Rotating the stamp makes existing access tokens stale within the API's
    30-second revocation cache; deleting refresh tokens stops the session being
    extended past the current token regardless. Both are needed: the stamp alone
    leaves a valid refresh token, and the token deletion alone leaves up to
    fifteen minutes of access.
*/
IF OBJECT_ID('Identity.usp_Access_RotateSecurityStamp') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Access_RotateSecurityStamp];
GO
CREATE PROCEDURE [Identity].[usp_Access_RotateSecurityStamp]
    @UserId      UNIQUEIDENTIFIER,
    @ActorUserId UNIQUEIDENTIFIER = NULL,
    @Reason      NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @stamp UNIQUEIDENTIFIER = NEWID();

    UPDATE [Identity].[User]
    SET SecurityStamp = @stamp, ModifiedUtc = SYSUTCDATETIME()
    WHERE UserId = @UserId;

    MERGE [Identity].[SecurityStampRevocation] AS target
    USING (SELECT @UserId AS UserId) AS source ON target.UserId = source.UserId
    WHEN MATCHED THEN UPDATE SET
        SecurityStamp = @stamp,
        RevokedUtc = SYSUTCDATETIME(),
        RevokedBy = @ActorUserId,
        Reason = @Reason
    WHEN NOT MATCHED THEN
        INSERT (UserId, SecurityStamp, RevokedBy, Reason)
        VALUES (@UserId, @stamp, @ActorUserId, @Reason);

    DELETE FROM [Identity].[RefreshToken] WHERE UserId = @UserId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_Search
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_User_Search') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_Search];
GO
CREATE PROCEDURE [Identity].[usp_User_Search]
    @Query          NVARCHAR(200) = NULL,
    @RoleId         INT = NULL,
    /*  any | active | locked | unconfirmed | deleted */
    @Status         VARCHAR(20) = 'any',
    @Page           INT = 1,
    @PageSize       INT = 25,
    @SortBy         VARCHAR(30) = 'created',
    @SortDescending BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @offset INT = (@Page - 1) * @PageSize;

    ;WITH filtered AS (
        SELECT u.UserId
        FROM [Identity].[User] u
        WHERE (@Query IS NULL OR u.Email LIKE '%' + @Query + '%')
          AND (@RoleId IS NULL OR EXISTS (
                SELECT 1 FROM [Identity].[UserRole] ur
                WHERE ur.UserId = u.UserId AND ur.RoleId = @RoleId))
          AND (
            /*  Deleted accounts are excluded unless asked for by name. A
                support agent searching for somebody should not silently match
                an account that no longer exists. */
                (@Status = 'any'         AND u.IsDeleted = 0)
             OR (@Status = 'active'      AND u.IsDeleted = 0 AND u.IsLockedOut = 0)
             OR (@Status = 'locked'      AND u.IsDeleted = 0 AND u.IsLockedOut = 1)
             OR (@Status = 'unconfirmed' AND u.IsDeleted = 0 AND u.IsEmailConfirmed = 0)
             OR (@Status = 'deleted'     AND u.IsDeleted = 1))
    )
    SELECT
        u.UserId,
        u.Email,
        u.LanguageCode,
        u.IsEmailConfirmed,
        u.IsLockedOut,
        u.LockoutEndUtc,
        u.FailedLoginCount,
        u.IsDeleted,
        u.CreatedUtc,
        c.IsoCode AS CountryIso,
        /*  Comma-separated rather than a second result set: the grid shows them
            as chips and never needs the ids, and one round trip beats two. */
        ISNULL(STUFF((
            SELECT ', ' + r.Name
            FROM [Identity].[UserRole] ur
            JOIN [Identity].[Role] r ON r.RoleId = ur.RoleId
            WHERE ur.UserId = u.UserId
            ORDER BY r.Name
            FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, ''), '')
            AS RoleNames,
        COUNT(*) OVER() AS TotalCount
    FROM filtered f
    JOIN [Identity].[User] u ON u.UserId = f.UserId
    LEFT JOIN [Identity].[Country] c ON c.CountryId = u.CountryId
    ORDER BY
        CASE WHEN @SortDescending = 1 AND @SortBy = 'created'  THEN u.CreatedUtc END DESC,
        CASE WHEN @SortDescending = 0 AND @SortBy = 'created'  THEN u.CreatedUtc END ASC,
        CASE WHEN @SortDescending = 1 AND @SortBy = 'email'    THEN u.Email END DESC,
        CASE WHEN @SortDescending = 0 AND @SortBy = 'email'    THEN u.Email END ASC,
        u.UserId
    OFFSET @offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_GetDetail
-- ---------------------------------------------------------------------------
/*  Four result sets: the user, their roles, their devices, their recent
    activity. */
IF OBJECT_ID('Identity.usp_User_GetDetail') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_GetDetail];
GO
CREATE PROCEDURE [Identity].[usp_User_GetDetail]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserId, u.Email, u.LanguageCode, u.IsEmailConfirmed,
        u.IsLockedOut, u.LockoutEndUtc, u.FailedLoginCount,
        u.IsDeleted, u.DeletedUtc, u.CreatedUtc, u.ModifiedUtc,
        c.IsoCode AS CountryIso
    FROM [Identity].[User] u
    LEFT JOIN [Identity].[Country] c ON c.CountryId = u.CountryId
    WHERE u.UserId = @UserId;

    SELECT r.RoleId, r.Name, r.Description, r.IsSystem,
           ur.AssignedUtc, ur.AssignedBy
    FROM [Identity].[UserRole] ur
    JOIN [Identity].[Role] r ON r.RoleId = ur.RoleId
    WHERE ur.UserId = @UserId
    ORDER BY r.Name;

    /*  No FcmToken. It is a push credential and the operator has no use for
        its value — only for knowing the device exists. */
    SELECT d.DeviceId, d.Platform, d.OsVersion, d.AppVersion, d.Model,
           d.IsActive, d.LastSeenUtc
    FROM [Identity].[Device] d
    WHERE d.UserId = @UserId
    ORDER BY d.LastSeenUtc DESC;

    SELECT TOP 25
        a.AuditLogId, a.OccurredUtc, a.[Action], a.EntityType, a.EntityId,
        a.IpAddress
    FROM [Audit].[AuditLog] a
    WHERE a.ActorUserId = @UserId
    ORDER BY a.OccurredUtc DESC;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_SetLockout
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_User_SetLockout') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_SetLockout];
GO
CREATE PROCEDURE [Identity].[usp_User_SetLockout]
    @UserId        UNIQUEIDENTIFIER,
    @IsLocked      BIT,
    @Reason        NVARCHAR(300) = NULL,
    @LockoutEndUtc DATETIME2(3) = NULL,
    @ActorUserId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*  Availability guard, not a security one. It stops the failure where the
        only administrator locks themselves out and the recovery path is raw
        SQL against production at 2am. */
    IF @ActorUserId IS NOT NULL AND @UserId = @ActorUserId AND @IsLocked = 1
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'SELF_DEMOTION' AS FailureCode;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User] WHERE UserId = @UserId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode;
        RETURN;
    END

    DECLARE @before NVARCHAR(MAX) = (
        SELECT IsLockedOut, LockoutEndUtc FROM [Identity].[User]
        WHERE UserId = @UserId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    BEGIN TRAN;

        UPDATE [Identity].[User]
        SET IsLockedOut = @IsLocked,
            LockoutEndUtc = CASE WHEN @IsLocked = 1 THEN @LockoutEndUtc END,
            /*  Unlocking clears the counter. Leaving it would re-lock the
                account on the next single mistyped password. */
            FailedLoginCount = CASE WHEN @IsLocked = 0 THEN 0
                                    ELSE FailedLoginCount END,
            ModifiedUtc = SYSUTCDATETIME()
        WHERE UserId = @UserId;

        /*  Locking must end the sessions that already exist. An account locked
            while its owner is signed in stays usable for the life of the
            access token otherwise, which defeats the point of locking it. */
        IF @IsLocked = 1
            EXEC [Identity].[usp_Access_RotateSecurityStamp]
                @UserId = @UserId, @ActorUserId = @ActorUserId, @Reason = @Reason;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId,
             BeforeJson, AfterJson)
        VALUES
            (@ActorUserId, 'admin',
             CASE WHEN @IsLocked = 1 THEN 'User.Lock' ELSE 'User.Unlock' END,
             'User', CONVERT(NVARCHAR(50), @UserId),
             @before,
             (SELECT IsLockedOut, LockoutEndUtc, @Reason AS Reason
              FROM [Identity].[User] WHERE UserId = @UserId
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_AssignRole
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_User_AssignRole') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_AssignRole];
GO
CREATE PROCEDURE [Identity].[usp_User_AssignRole]
    @UserId      UNIQUEIDENTIFIER,
    @RoleId      INT,
    @ActorUserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User] WHERE UserId = @UserId)
        OR NOT EXISTS (SELECT 1 FROM [Identity].[Role] WHERE RoleId = @RoleId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode;
        RETURN;
    END

    /*  THE escalation guard. Without it, holding roles.write is holding every
        permission: assign yourself SuperAdmin and the check that was supposed
        to stop you is the one you just bypassed. */
    IF [Identity].[fn_UserHoldsAllPermissionsOfRole](@ActorUserId, @RoleId) = 0
    BEGIN
        /*  A refused escalation is a security event and is recorded as one.
            Auditing only successes means somebody probing for a way to
            escalate leaves no trace at all — and the probing is exactly what
            a security team needs to see, because success would be too late. */
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'admin', 'Security.EscalationRefused', 'User',
             CONVERT(NVARCHAR(50), @UserId),
             (SELECT @RoleId AS AttemptedRoleId, 'AssignRole' AS Operation
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

        SELECT CAST(0 AS BIT) AS Succeeded, 'PRIVILEGE_ESCALATION' AS FailureCode;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM [Identity].[UserRole]
               WHERE UserId = @UserId AND RoleId = @RoleId)
    BEGIN
        /*  Idempotent. Assigning a role somebody already has is not an error
            worth showing an operator. */
        SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        INSERT INTO [Identity].[UserRole] (UserId, RoleId, AssignedBy)
        VALUES (@UserId, @RoleId, @ActorUserId);

        /*  Gaining a role must take effect promptly, not on next sign-in.
            Rotating here means the user re-authenticates and picks up the new
            claims rather than waiting out a stale token. */
        EXEC [Identity].[usp_Access_RotateSecurityStamp]
            @UserId = @UserId, @ActorUserId = @ActorUserId,
            @Reason = N'Role assigned';

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        SELECT
            @ActorUserId, 'admin', 'User.RoleAssigned', 'User',
            CONVERT(NVARCHAR(50), @UserId),
            (SELECT r.RoleId, r.Name FROM [Identity].[Role] r
             WHERE r.RoleId = @RoleId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_RemoveRole
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_User_RemoveRole') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_RemoveRole];
GO
CREATE PROCEDURE [Identity].[usp_User_RemoveRole]
    @UserId      UNIQUEIDENTIFIER,
    @RoleId      INT,
    @ActorUserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*  Removing your own role is how an administrator accidentally locks the
        whole team out of role management. Another administrator can do it. */
    IF @ActorUserId IS NOT NULL AND @UserId = @ActorUserId
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'SELF_DEMOTION' AS FailureCode;
        RETURN;
    END

    /*  The platform must keep at least one account that can administer it.
        Removing the last SuperAdmin leaves a database only raw SQL can fix. */
    IF EXISTS (SELECT 1 FROM [Identity].[Role]
               WHERE RoleId = @RoleId AND Name = 'SuperAdmin')
       AND (SELECT COUNT(*) FROM [Identity].[UserRole] ur
            JOIN [Identity].[User] u ON u.UserId = ur.UserId
            WHERE ur.RoleId = @RoleId AND u.IsDeleted = 0) <= 1
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'LAST_ADMINISTRATOR' AS FailureCode;
        RETURN;
    END

    IF [Identity].[fn_UserHoldsAllPermissionsOfRole](@ActorUserId, @RoleId) = 0
    BEGIN
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'admin', 'Security.EscalationRefused', 'User',
             CONVERT(NVARCHAR(50), @UserId),
             (SELECT @RoleId AS AttemptedRoleId, 'RemoveRole' AS Operation
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

        SELECT CAST(0 AS BIT) AS Succeeded, 'PRIVILEGE_ESCALATION' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        DELETE FROM [Identity].[UserRole]
        WHERE UserId = @UserId AND RoleId = @RoleId;

        /*  This is a revocation. It must bite now, not in fifteen minutes. */
        EXEC [Identity].[usp_Access_RotateSecurityStamp]
            @UserId = @UserId, @ActorUserId = @ActorUserId,
            @Reason = N'Role removed';

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, BeforeJson)
        SELECT
            @ActorUserId, 'admin', 'User.RoleRemoved', 'User',
            CONVERT(NVARCHAR(50), @UserId),
            (SELECT r.RoleId, r.Name FROM [Identity].[Role] r
             WHERE r.RoleId = @RoleId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_RevokeSessions
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_User_RevokeSessions') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_RevokeSessions];
GO
CREATE PROCEDURE [Identity].[usp_User_RevokeSessions]
    @UserId      UNIQUEIDENTIFIER,
    @Reason      NVARCHAR(300) = NULL,
    @ActorUserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User] WHERE UserId = @UserId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        EXEC [Identity].[usp_Access_RotateSecurityStamp]
            @UserId = @UserId, @ActorUserId = @ActorUserId, @Reason = @Reason;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'admin', 'User.SessionsRevoked', 'User',
             CONVERT(NVARCHAR(50), @UserId),
             (SELECT @Reason AS Reason FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Role_List / usp_Permission_List
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_Role_List') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Role_List];
GO
CREATE PROCEDURE [Identity].[usp_Role_List]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.RoleId, r.Name, r.Description, r.IsSystem,
        (SELECT COUNT(*) FROM [Identity].[RolePermission] rp
         WHERE rp.RoleId = r.RoleId) AS PermissionCount,
        (SELECT COUNT(*) FROM [Identity].[UserRole] ur
         JOIN [Identity].[User] u ON u.UserId = ur.UserId
         WHERE ur.RoleId = r.RoleId AND u.IsDeleted = 0) AS MemberCount
    FROM [Identity].[Role] r
    ORDER BY r.Name;

    /*  The full grant matrix as a second set. The portal renders roles down and
        permissions across, and fetching it per role would be one request per
        row of the grid. */
    SELECT rp.RoleId, p.Code
    FROM [Identity].[RolePermission] rp
    JOIN [Identity].[Permission] p ON p.PermissionId = rp.PermissionId
    ORDER BY rp.RoleId, p.Code;
END
GO

IF OBJECT_ID('Identity.usp_Permission_List') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Permission_List];
GO
CREATE PROCEDURE [Identity].[usp_Permission_List]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PermissionId, Code, Description, Category
    FROM [Identity].[Permission]
    ORDER BY Category, Code;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Role_Save
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_Role_Save') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Role_Save];
GO
CREATE PROCEDURE [Identity].[usp_Role_Save]
    @RoleId      INT = NULL,
    @Name        NVARCHAR(100),
    @Description NVARCHAR(400) = NULL,
    @ActorUserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /*  A system role's name is referenced by the seed scripts and by operator
        runbooks. Its description is free to change; its name is not. */
    IF @RoleId IS NOT NULL AND EXISTS (
        SELECT 1 FROM [Identity].[Role]
        WHERE RoleId = @RoleId AND IsSystem = 1 AND Name <> @Name)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'SYSTEM_ROLE' AS FailureCode,
               CAST(NULL AS INT) AS RoleId;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM [Identity].[Role]
               WHERE Name = @Name AND (@RoleId IS NULL OR RoleId <> @RoleId))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'DUPLICATE_KEY' AS FailureCode,
               CAST(NULL AS INT) AS RoleId;
        RETURN;
    END

    BEGIN TRAN;

        IF @RoleId IS NULL
        BEGIN
            INSERT INTO [Identity].[Role] (Name, Description, IsSystem)
            VALUES (@Name, @Description, 0);
            SET @RoleId = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [Identity].[Role]
            SET Name = @Name, Description = @Description
            WHERE RoleId = @RoleId;
        END

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'admin', 'Role.Save', 'Role',
             CONVERT(NVARCHAR(50), @RoleId),
             (SELECT @Name AS Name, @Description AS Description
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode,
           @RoleId AS RoleId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Role_Delete
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_Role_Delete') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Role_Delete];
GO
CREATE PROCEDURE [Identity].[usp_Role_Delete]
    @RoleId      INT,
    @ActorUserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF EXISTS (SELECT 1 FROM [Identity].[Role]
               WHERE RoleId = @RoleId AND IsSystem = 1)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'SYSTEM_ROLE' AS FailureCode;
        RETURN;
    END

    /*  Deleting a role with members silently strips their access. Making the
        operator remove people first means the consequence is visible before it
        happens rather than discovered afterwards. */
    IF EXISTS (SELECT 1 FROM [Identity].[UserRole] WHERE RoleId = @RoleId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'ROLE_IN_USE' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        DECLARE @before NVARCHAR(MAX) = (
            SELECT RoleId, Name, Description FROM [Identity].[Role]
            WHERE RoleId = @RoleId FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        DELETE FROM [Identity].[RolePermission] WHERE RoleId = @RoleId;
        DELETE FROM [Identity].[Role] WHERE RoleId = @RoleId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, BeforeJson)
        VALUES
            (@ActorUserId, 'admin', 'Role.Delete', 'Role',
             CONVERT(NVARCHAR(50), @RoleId), @before);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Role_SetPermissions
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_Role_SetPermissions') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Role_SetPermissions];
GO
CREATE PROCEDURE [Identity].[usp_Role_SetPermissions]
    @RoleId          INT,
    /*  JSON array of permission codes: ["content.read","content.write"] */
    @PermissionCodes NVARCHAR(MAX),
    @ActorUserId     UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF ISJSON(@PermissionCodes) <> 1
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_PAYLOAD' AS FailureCode;
        RETURN;
    END

    DECLARE @requested TABLE (PermissionId INT PRIMARY KEY);
    INSERT INTO @requested (PermissionId)
    SELECT DISTINCT p.PermissionId
    FROM OPENJSON(@PermissionCodes) j
    JOIN [Identity].[Permission] p ON p.Code = j.[value];

    /*  An unknown code is a caller bug, and silently dropping it would leave
        the operator believing they granted something they did not. */
    IF (SELECT COUNT(*) FROM OPENJSON(@PermissionCodes)) <>
       (SELECT COUNT(*) FROM @requested)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNKNOWN_PERMISSION' AS FailureCode;
        RETURN;
    END

    /*  The escalation guard again, in its other form: you cannot put a
        permission into a role unless you hold it. Editing a role is the
        indirect route to granting yourself anything, and it has to be closed
        in the same place as the direct route. */
    IF @ActorUserId IS NOT NULL AND EXISTS (
        SELECT PermissionId FROM @requested
        EXCEPT
        SELECT rp.PermissionId
        FROM [Identity].[UserRole] ur
        JOIN [Identity].[RolePermission] rp ON rp.RoleId = ur.RoleId
        WHERE ur.UserId = @ActorUserId)
    BEGIN
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'admin', 'Security.EscalationRefused', 'Role',
             CONVERT(NVARCHAR(50), @RoleId), @PermissionCodes);

        SELECT CAST(0 AS BIT) AS Succeeded, 'PRIVILEGE_ESCALATION' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        DECLARE @before NVARCHAR(MAX) = (
            SELECT p.Code FROM [Identity].[RolePermission] rp
            JOIN [Identity].[Permission] p ON p.PermissionId = rp.PermissionId
            WHERE rp.RoleId = @RoleId FOR JSON PATH);

        DELETE FROM [Identity].[RolePermission] WHERE RoleId = @RoleId;

        INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
        SELECT @RoleId, PermissionId FROM @requested;

        /*  Everyone holding this role now has a different permission set, so
            every one of their sessions has to pick it up. This is the reason
            role edits are audited as heavily as they are. */
        DECLARE @affected TABLE (UserId UNIQUEIDENTIFIER);
        INSERT INTO @affected (UserId)
        SELECT UserId FROM [Identity].[UserRole] WHERE RoleId = @RoleId;

        DECLARE @uid UNIQUEIDENTIFIER;
        DECLARE affected_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT UserId FROM @affected;
        OPEN affected_cursor;
        FETCH NEXT FROM affected_cursor INTO @uid;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC [Identity].[usp_Access_RotateSecurityStamp]
                @UserId = @uid, @ActorUserId = @ActorUserId,
                @Reason = N'Role permissions changed';
            FETCH NEXT FROM affected_cursor INTO @uid;
        END
        CLOSE affected_cursor;
        DEALLOCATE affected_cursor;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId,
             BeforeJson, AfterJson)
        VALUES
            (@ActorUserId, 'admin', 'Role.SetPermissions', 'Role',
             CONVERT(NVARCHAR(50), @RoleId),
             @before, @PermissionCodes);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Audit_Search
-- ---------------------------------------------------------------------------
/*  Read-only by construction. There is no update or delete path to AuditLog in
    any procedure in this platform; an audit trail somebody can edit is not
    one. */
IF OBJECT_ID('Audit.usp_Audit_Search') IS NOT NULL
    DROP PROCEDURE [Audit].[usp_Audit_Search];
GO
CREATE PROCEDURE [Audit].[usp_Audit_Search]
    @ActorUserId UNIQUEIDENTIFIER = NULL,
    @EntityType  VARCHAR(60) = NULL,
    @EntityId    NVARCHAR(100) = NULL,
    @Action      VARCHAR(80) = NULL,
    @FromUtc     DATETIME2(3) = NULL,
    @ToUtc       DATETIME2(3) = NULL,
    @Page        INT = 1,
    @PageSize    INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @offset INT = (@Page - 1) * @PageSize;

    SELECT
        a.AuditLogId, a.OccurredUtc, a.ActorUserId,
        u.Email AS ActorEmail,
        a.ActorKind, a.[Action], a.EntityType, a.EntityId,
        a.BeforeJson, a.AfterJson, a.IpAddress, a.CorrelationId,
        COUNT(*) OVER() AS TotalCount
    FROM [Audit].[AuditLog] a
    LEFT JOIN [Identity].[User] u ON u.UserId = a.ActorUserId
    WHERE (@ActorUserId IS NULL OR a.ActorUserId = @ActorUserId)
      AND (@EntityType  IS NULL OR a.EntityType = @EntityType)
      AND (@EntityId    IS NULL OR a.EntityId = @EntityId)
      AND (@Action      IS NULL OR a.[Action] LIKE @Action + '%')
      AND (@FromUtc     IS NULL OR a.OccurredUtc >= @FromUtc)
      AND (@ToUtc       IS NULL OR a.OccurredUtc <= @ToUtc)
    ORDER BY a.OccurredUtc DESC, a.AuditLogId DESC
    OFFSET @offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Access_GetRevocations
-- ---------------------------------------------------------------------------
/*  Feeds the API's 30-second revocation cache. Returns every current stamp for
    users who have ever been revoked; the API compares a request token's stamp
    against this and refuses a mismatch. */
IF OBJECT_ID('Identity.usp_Access_GetRevocations') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Access_GetRevocations];
GO
CREATE PROCEDURE [Identity].[usp_Access_GetRevocations]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT UserId, SecurityStamp
    FROM [Identity].[SecurityStampRevocation];
END
GO

PRINT 'Access procedures applied.';
GO

-- ---------------------------------------------------------------------------
-- usp_User_GetSecurityStamp
-- ---------------------------------------------------------------------------
/*  Read on login and refresh so the minted access token can carry the stamp.

    A dedicated procedure rather than widening usp_User_GetForLogin: that one
    sits on an unauthenticated path and was deliberately narrowed once already
    (it returned twelve columns for a six-field record and broke Dapper). Login
    and refresh happen rarely enough that one extra round trip costs nothing
    measurable, and the alternative reshapes two procedures and their records.
*/
IF OBJECT_ID('Identity.usp_User_GetSecurityStamp') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_GetSecurityStamp];
GO
CREATE PROCEDURE [Identity].[usp_User_GetSecurityStamp]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @UserId;
END
GO

PRINT 'Security stamp lookup applied.';
GO

-- ---------------------------------------------------------------------------
-- usp_Access_RecordSecurityEvent
-- ---------------------------------------------------------------------------
/*  Lets the application layer write a security event.

    The API refuses an escalation before it reaches the procedure that would
    have audited it — the handler checks first so it can name which permissions
    are missing rather than returning a bare code. That short-circuit meant the
    refusal was recorded only for callers going straight to the database, and
    invisible for the one path anybody actually uses.

    The probing is what matters here. Success would be too late to detect.
*/
IF OBJECT_ID('Identity.usp_Access_RecordSecurityEvent') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Access_RecordSecurityEvent];
GO
CREATE PROCEDURE [Identity].[usp_Access_RecordSecurityEvent]
    @ActorUserId UNIQUEIDENTIFIER = NULL,
    @Action      VARCHAR(80),
    @EntityType  VARCHAR(60) = NULL,
    @EntityId    NVARCHAR(100) = NULL,
    @DetailJson  NVARCHAR(MAX) = NULL,
    @IpAddress   VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [Audit].[AuditLog]
        (ActorUserId, ActorKind, [Action], EntityType, EntityId,
         AfterJson, IpAddress)
    VALUES
        (@ActorUserId, 'admin', @Action, @EntityType, @EntityId,
         @DetailJson, @IpAddress);
END
GO

PRINT 'Security event recorder applied.';
GO
