/*  access_test.sql
    ---------------------------------------------------------------------------
    Assertions for the Users & Access Management slice.

    Re-runnable: creates its own fixtures under a known prefix and removes them
    first. Safe against a populated database.

    The escalation assertions are the point of this file. Everything else in
    the slice is administration; those two are the security boundary.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @results TABLE (
    Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
    Detail NVARCHAR(300), Outcome VARCHAR(6));

DECLARE @res TABLE (Succeeded BIT, FailureCode VARCHAR(40));
DECLARE @resRole TABLE (Succeeded BIT, FailureCode VARCHAR(40), RoleId INT);

-- Fixtures ------------------------------------------------------------------
DECLARE @prefix NVARCHAR(50) = N'atest-';
DECLARE @superId UNIQUEIDENTIFIER = NEWID();   -- holds everything
DECLARE @editorId UNIQUEIDENTIFIER = NEWID();  -- holds content only
DECLARE @targetId UNIQUEIDENTIFIER = NEWID();  -- the person being administered
DECLARE @weakRoleId INT, @strongRoleId INT, @tempRoleId INT;

/*  Clean up a previous run. Children first. */
DELETE FROM [Identity].[SecurityStampRevocation]
WHERE UserId IN (SELECT UserId FROM [Identity].[User] WHERE Email LIKE @prefix + '%');
DELETE FROM [Identity].[RefreshToken]
WHERE UserId IN (SELECT UserId FROM [Identity].[User] WHERE Email LIKE @prefix + '%');
DELETE FROM [Identity].[UserRole]
WHERE UserId IN (SELECT UserId FROM [Identity].[User] WHERE Email LIKE @prefix + '%');
DELETE FROM [Audit].[AuditLog]
WHERE ActorUserId IN (SELECT UserId FROM [Identity].[User] WHERE Email LIKE @prefix + '%');
DELETE FROM [Identity].[User] WHERE Email LIKE @prefix + '%';
DELETE FROM [Identity].[RolePermission]
WHERE RoleId IN (SELECT RoleId FROM [Identity].[Role] WHERE Name LIKE @prefix + '%');
DELETE FROM [Identity].[Role] WHERE Name LIKE @prefix + '%';

INSERT INTO [Identity].[User]
    (UserId, Email, NormalisedEmail, SecurityStamp, LanguageCode,
     IsEmailConfirmed, IsLockedOut, FailedLoginCount, IsDeleted)
VALUES
    (@superId,  @prefix + N'super@test',  UPPER(@prefix + N'super@test'),
     NEWID(), 'en-GB', 1, 0, 0, 0),
    (@editorId, @prefix + N'editor@test', UPPER(@prefix + N'editor@test'),
     NEWID(), 'en-GB', 1, 0, 0, 0),
    (@targetId, @prefix + N'target@test', UPPER(@prefix + N'target@test'),
     NEWID(), 'en-GB', 1, 0, 0, 0);

/*  Weak role: content.read only. Strong role: everything that exists. */
INSERT INTO [Identity].[Role] (Name, Description, IsSystem)
VALUES (@prefix + N'weak', N'Fixture', 0);
SET @weakRoleId = SCOPE_IDENTITY();

INSERT INTO [Identity].[Role] (Name, Description, IsSystem)
VALUES (@prefix + N'strong', N'Fixture', 0);
SET @strongRoleId = SCOPE_IDENTITY();

INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT @weakRoleId, PermissionId FROM [Identity].[Permission]
WHERE Code = 'content.read';

INSERT INTO [Identity].[RolePermission] (RoleId, PermissionId)
SELECT @strongRoleId, PermissionId FROM [Identity].[Permission];

/*  The super fixture holds the strong role; the editor holds only the weak. */
INSERT INTO [Identity].[UserRole] (UserId, RoleId)
VALUES (@superId, @strongRoleId), (@editorId, @weakRoleId);

-- 1 --------------------------------------------------------------------------
/*  THE assertion. A holder of roles.write who does not hold the target role's
    permissions must not be able to assign it — otherwise roles.write is
    SuperAdmin by another name. */
DELETE @res;
INSERT @res EXEC [Identity].[usp_User_AssignRole]
    @UserId = @targetId, @RoleId = @strongRoleId, @ActorUserId = @editorId;

INSERT @results
SELECT 'weak actor cannot assign a role stronger than their own',
       ISNULL(FailureCode, 'allowed'),
       CASE WHEN Succeeded = 0 AND FailureCode = 'PRIVILEGE_ESCALATION'
            THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 2 --------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_User_AssignRole]
    @UserId = @targetId, @RoleId = @strongRoleId, @ActorUserId = @superId;

INSERT @results
SELECT 'strong actor can assign a role they fully hold',
       CONCAT('succeeded=', Succeeded),
       CASE WHEN Succeeded = 1 THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 3 --------------------------------------------------------------------------
/*  The indirect route: edit a role to contain a permission you lack. Must be
    refused in exactly the same way as the direct route. */
INSERT INTO [Identity].[Role] (Name, Description, IsSystem)
VALUES (@prefix + N'temp', N'Fixture', 0);
SET @tempRoleId = SCOPE_IDENTITY();

DELETE @res;
INSERT @res EXEC [Identity].[usp_Role_SetPermissions]
    @RoleId = @tempRoleId,
    @PermissionCodes = N'["users.delete","roles.write"]',
    @ActorUserId = @editorId;

INSERT @results
SELECT 'weak actor cannot grant permissions they lack via a role',
       ISNULL(FailureCode, 'allowed'),
       CASE WHEN Succeeded = 0 AND FailureCode = 'PRIVILEGE_ESCALATION'
            THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 4 --------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_Role_SetPermissions]
    @RoleId = @tempRoleId,
    @PermissionCodes = N'["content.read"]',
    @ActorUserId = @editorId;

INSERT @results
SELECT 'weak actor can grant a permission they do hold',
       CONCAT('succeeded=', Succeeded),
       CASE WHEN Succeeded = 1 THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 5 --------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_Role_SetPermissions]
    @RoleId = @tempRoleId,
    @PermissionCodes = N'["content.read","not.a.real.permission"]',
    @ActorUserId = @superId;

INSERT @results
SELECT 'an unknown permission code is refused, not silently dropped',
       ISNULL(FailureCode, 'allowed'),
       CASE WHEN Succeeded = 0 AND FailureCode = 'UNKNOWN_PERMISSION'
            THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 6 --------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_User_RemoveRole]
    @UserId = @superId, @RoleId = @strongRoleId, @ActorUserId = @superId;

INSERT @results
SELECT 'an actor cannot remove their own role',
       ISNULL(FailureCode, 'allowed'),
       CASE WHEN Succeeded = 0 AND FailureCode = 'SELF_DEMOTION'
            THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 7 --------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_User_SetLockout]
    @UserId = @superId, @IsLocked = 1, @ActorUserId = @superId;

INSERT @results
SELECT 'an actor cannot lock themselves out',
       ISNULL(FailureCode, 'allowed'),
       CASE WHEN Succeeded = 0 AND FailureCode = 'SELF_DEMOTION'
            THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 8 --------------------------------------------------------------------------
/*  Locking must end sessions that already exist, or the account stays usable
    for the life of its access token. */
DECLARE @stampBefore UNIQUEIDENTIFIER =
    (SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @targetId);

DELETE @res;
INSERT @res EXEC [Identity].[usp_User_SetLockout]
    @UserId = @targetId, @IsLocked = 1, @Reason = N'Test lock',
    @ActorUserId = @superId;

DECLARE @stampAfter UNIQUEIDENTIFIER =
    (SELECT SecurityStamp FROM [Identity].[User] WHERE UserId = @targetId);

INSERT @results VALUES (
    'locking rotates the security stamp',
    CASE WHEN @stampBefore <> @stampAfter THEN 'rotated' ELSE 'unchanged' END,
    CASE WHEN @stampBefore <> @stampAfter THEN 'PASS' ELSE 'FAIL' END);

-- 9 --------------------------------------------------------------------------
INSERT @results
SELECT 'a locked user appears in the revocation set',
       CONCAT('rows=', COUNT(*)),
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM [Identity].[SecurityStampRevocation]
WHERE UserId = @targetId AND SecurityStamp = @stampAfter;

-- 10 -------------------------------------------------------------------------
/*  Unlocking must clear the failed-login counter, or the account re-locks on
    the next single mistyped password. */
UPDATE [Identity].[User] SET FailedLoginCount = 9 WHERE UserId = @targetId;

DELETE @res;
INSERT @res EXEC [Identity].[usp_User_SetLockout]
    @UserId = @targetId, @IsLocked = 0, @ActorUserId = @superId;

INSERT @results
SELECT 'unlocking clears the failed login counter',
       CONCAT('count=', FailedLoginCount),
       CASE WHEN FailedLoginCount = 0 AND IsLockedOut = 0 THEN 'PASS' ELSE 'FAIL' END
FROM [Identity].[User] WHERE UserId = @targetId;

-- 11 -------------------------------------------------------------------------
DECLARE @sysRoleId INT =
    (SELECT RoleId FROM [Identity].[Role] WHERE Name = 'SuperAdmin');

DELETE @res;
INSERT @res EXEC [Identity].[usp_Role_Delete]
    @RoleId = @sysRoleId, @ActorUserId = @superId;

INSERT @results
SELECT 'a system role cannot be deleted',
       ISNULL(FailureCode, 'allowed'),
       CASE WHEN Succeeded = 0 AND FailureCode = 'SYSTEM_ROLE'
            THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 12 -------------------------------------------------------------------------
DELETE @resRole;
INSERT @resRole EXEC [Identity].[usp_Role_Save]
    @RoleId = @sysRoleId, @Name = N'RenamedAdmin', @ActorUserId = @superId;

INSERT @results
SELECT 'a system role cannot be renamed',
       ISNULL(FailureCode, 'allowed'),
       CASE WHEN Succeeded = 0 AND FailureCode = 'SYSTEM_ROLE'
            THEN 'PASS' ELSE 'FAIL' END
FROM @resRole;

-- 13 -------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Identity].[usp_Role_Delete]
    @RoleId = @strongRoleId, @ActorUserId = @superId;

INSERT @results
SELECT 'a role with members cannot be deleted',
       ISNULL(FailureCode, 'allowed'),
       CASE WHEN Succeeded = 0 AND FailureCode = 'ROLE_IN_USE'
            THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 14 -------------------------------------------------------------------------
/*  Password material must never reach a result set. This is the assertion that
    would catch somebody "fixing" a proc with SELECT *. */
DECLARE @userCols TABLE (
    UserId UNIQUEIDENTIFIER, Email NVARCHAR(256), LanguageCode CHAR(5),
    IsEmailConfirmed BIT, IsLockedOut BIT, LockoutEndUtc DATETIME2(3),
    FailedLoginCount INT, IsDeleted BIT, CreatedOn DATETIME2(3),
    CountryIso CHAR(2), RoleNames NVARCHAR(MAX), TotalCount INT);

INSERT @userCols EXEC [Identity].[usp_User_Search]
    @Query = @prefix, @PageSize = 50;

INSERT @results
SELECT 'user search returns the expected fixtures and no password columns',
       CONCAT('rows=', COUNT(*)),
       CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END
FROM @userCols;

-- 15 -------------------------------------------------------------------------
/*  Static check across every procedure in the platform, not just this slice. */
INSERT @results
SELECT 'no procedure selects password material',
       CONCAT('offenders=', COUNT(*)),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.type = 'P'
  AND o.name NOT IN ('usp_User_GetForLogin', 'usp_User_Register')
  AND (m.definition LIKE '%PasswordHash%' OR m.definition LIKE '%PasswordSalt%');

-- 16 -------------------------------------------------------------------------
INSERT @results
SELECT 'every successful access command is audited',
       CONCAT('rows=', COUNT(*)),
       CASE WHEN COUNT(*) = 3 THEN 'PASS' ELSE 'FAIL' END
FROM [Audit].[AuditLog]
WHERE ActorUserId = @superId
  AND [Action] IN ('User.Lock', 'User.Unlock', 'User.RoleAssigned');

-- 16b ------------------------------------------------------------------------
/*  Refused escalations must leave a trail. Auditing only successes means
    somebody probing for a way to escalate is invisible until they find one. */
INSERT @results
SELECT 'a refused escalation attempt is audited',
       CONCAT('rows=', COUNT(*)),
       CASE WHEN COUNT(*) >= 2 THEN 'PASS' ELSE 'FAIL' END
FROM [Audit].[AuditLog]
WHERE ActorUserId = @editorId
  AND [Action] = 'Security.EscalationRefused';

-- 17 -------------------------------------------------------------------------
DECLARE @auditRows TABLE (
    AuditLogId BIGINT, OccurredUtc DATETIME2(3), ActorUserId UNIQUEIDENTIFIER,
    ActorEmail NVARCHAR(256), ActorKind VARCHAR(20), [Action] VARCHAR(80),
    EntityType VARCHAR(60), EntityId NVARCHAR(100), BeforeJson NVARCHAR(MAX),
    AfterJson NVARCHAR(MAX), IpAddress VARCHAR(45),
    CorrelationId UNIQUEIDENTIFIER, TotalCount INT);

INSERT @auditRows EXEC [Audit].[usp_Audit_Search]
    @ActorUserId = @superId, @PageSize = 50;

INSERT @results
SELECT 'audit search filters by actor and resolves their email',
       CONCAT('rows=', COUNT(*)),
       CASE WHEN COUNT(*) > 0 AND MIN(ActorEmail) LIKE @prefix + '%'
            THEN 'PASS' ELSE 'FAIL' END
FROM @auditRows;

-- 18 -------------------------------------------------------------------------
/*  The audit trail must have no write path other than append. */
INSERT @results
SELECT 'no procedure updates or deletes the audit log',
       CONCAT('offenders=', COUNT(*)),
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM sys.sql_modules m
JOIN sys.objects o ON o.object_id = m.object_id
WHERE o.type = 'P'
  /*  Brackets escaped as [[] and []]. Unescaped, [Audit] is a LIKE character
      class matching a single char from {A,u,d,i,t} — the original form of this
      assertion reported five false positives. */
  AND (m.definition LIKE '%UPDATE [[]Audit[]].[[]AuditLog[]]%'
    OR m.definition LIKE '%DELETE FROM [[]Audit[]].[[]AuditLog[]]%');

-- Teardown ------------------------------------------------------------------
DELETE FROM [Identity].[SecurityStampRevocation]
WHERE UserId IN (@superId, @editorId, @targetId);
DELETE FROM [Identity].[UserRole]
WHERE UserId IN (@superId, @editorId, @targetId);
DELETE FROM [Audit].[AuditLog]
WHERE ActorUserId IN (@superId, @editorId, @targetId);
DELETE FROM [Identity].[User] WHERE UserId IN (@superId, @editorId, @targetId);
DELETE FROM [Identity].[RolePermission]
WHERE RoleId IN (@weakRoleId, @strongRoleId, @tempRoleId);
DELETE FROM [Identity].[Role]
WHERE RoleId IN (@weakRoleId, @strongRoleId, @tempRoleId);

-- Report --------------------------------------------------------------------
SELECT Seq, Assertion, Detail, Outcome FROM @results ORDER BY Seq;

SELECT CONCAT('TOTAL: ', COUNT(*), '  FAILED: ',
              SUM(CASE WHEN Outcome = 'FAIL' THEN 1 ELSE 0 END)) AS Summary
FROM @results;
GO
