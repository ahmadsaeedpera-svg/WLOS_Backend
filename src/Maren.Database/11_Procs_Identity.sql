/* Required for filtered indexes and indexes on computed columns. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Identity procedures.

    ## Hashing happens in the application, not here

    PBKDF2 is computed by Maren.Infrastructure and only the resulting bytes
    reach SQL. Two reasons: T-SQL has no constant-time comparison primitive,
    and a hash computed server-side would travel as a parameter in plaintext
    through the query plan cache and any trace running on the instance.

    So these procedures store and return hashes; they never compute or compare
    passwords beyond an equality check on bytes already derived.

    ## Enumeration

    usp_User_Login returns the same shape whether the account exists or not.
    A "no such user" that differs from "wrong password" tells an attacker which
    email addresses are registered, which for a pregnancy app is a meaningful
    disclosure on its own.
*/

-- ---------------------------------------------------------------------------
-- usp_User_Register
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_User_Register') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_Register];
GO
CREATE PROCEDURE [Identity].[usp_User_Register]
    @Email              NVARCHAR(256),
    @PasswordHash       VARBINARY(256),
    @PasswordSalt       VARBINARY(128),
    @PasswordIterations INT,
    @CountryIso         CHAR(2) = NULL,
    @LanguageCode       CHAR(5) = 'en-GB',
    @IpAddress          VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @normalised NVARCHAR(256) = UPPER(LTRIM(RTRIM(@Email)));
    DECLARE @userId UNIQUEIDENTIFIER;
    DECLARE @countryId INT =
        (SELECT CountryId FROM [Identity].[Country] WHERE IsoCode = @CountryIso);

    IF EXISTS (SELECT 1 FROM [Identity].[User]
               WHERE NormalisedEmail = @normalised AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded,
               'EMAIL_IN_USE' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId;
        RETURN;
    END

    BEGIN TRAN;

        INSERT INTO [Identity].[User]
            (Email, NormalisedEmail, PasswordHash, PasswordSalt,
             PasswordIterations, CountryId, LanguageCode)
        VALUES
            (@Email, @normalised, @PasswordHash, @PasswordSalt,
             @PasswordIterations, @countryId, @LanguageCode);

        SET @userId = (SELECT UserId FROM [Identity].[User]
                       WHERE NormalisedEmail = @normalised AND IsDeleted = 0);

        INSERT INTO [Identity].[Profile] (UserId) VALUES (@userId);

        /*  Every new account gets the Member role. Roles are additive from
            there; nobody is created with elevated access. */
        INSERT INTO [Identity].[UserRole] (UserId, RoleId)
        SELECT @userId, RoleId FROM [Identity].[Role] WHERE Name = 'Member';

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, IpAddress)
        VALUES
            (@userId, 'user', 'User.Register', 'User',
             CONVERT(NVARCHAR(50), @userId), @IpAddress);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded,
           CAST(NULL AS VARCHAR(50)) AS FailureCode,
           @userId AS UserId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_GetForLogin
-- ---------------------------------------------------------------------------
/*
    Returns the material needed to verify a password, and nothing else.

    Deliberately split from the login write path: verification happens in the
    application, so this reads, the app compares, then usp_User_RecordLogin
    writes the outcome. A single procedure that did all three would have to
    receive the plaintext password.
*/
IF OBJECT_ID('Identity.usp_User_GetForLogin') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_GetForLogin];
GO
CREATE PROCEDURE [Identity].[usp_User_GetForLogin]
    @Email NVARCHAR(256)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @normalised NVARCHAR(256) = UPPER(LTRIM(RTRIM(@Email)));

    /*  Exactly the six columns the verifier needs, and no more.

        An earlier version also returned the email, security stamp and country.
        None of it was used, and every extra column is one more piece of
        account data crossing a process boundary on an unauthenticated code
        path — the caller has not proved anything yet at this point. */
    SELECT TOP 1
        u.UserId,
        u.PasswordHash,
        u.PasswordSalt,
        u.PasswordIterations,
        u.IsLockedOut,
        u.LockoutEndUtc
    FROM [Identity].[User] u
    WHERE u.NormalisedEmail = @normalised AND u.IsDeleted = 0;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_RecordLogin
-- ---------------------------------------------------------------------------
/*
    Records the outcome and applies lockout.

    Lockout is a counter plus a window rather than a permanent flag: a
    permanent lock on a health record the user cannot recover without support
    is worse than the brute-force risk it prevents, given the rate limiting
    already in front of this.
*/
IF OBJECT_ID('Identity.usp_User_RecordLogin') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_RecordLogin];
GO
CREATE PROCEDURE [Identity].[usp_User_RecordLogin]
    @UserId     UNIQUEIDENTIFIER,
    @Succeeded  BIT,
    @IpAddress  VARCHAR(45) = NULL,
    @MaxAttempts INT = 10,
    @LockoutMinutes INT = 15
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRAN;

        IF @Succeeded = 1
        BEGIN
            UPDATE [Identity].[User]
            SET FailedLoginCount = 0,
                IsLockedOut = 0,
                LockoutEndUtc = NULL,
                ModifiedUtc = SYSUTCDATETIME()
            WHERE UserId = @UserId;
        END
        ELSE
        BEGIN
            UPDATE [Identity].[User]
            SET FailedLoginCount = FailedLoginCount + 1,
                IsLockedOut = CASE WHEN FailedLoginCount + 1 >= @MaxAttempts
                                   THEN 1 ELSE IsLockedOut END,
                LockoutEndUtc = CASE WHEN FailedLoginCount + 1 >= @MaxAttempts
                                     THEN DATEADD(MINUTE, @LockoutMinutes, SYSUTCDATETIME())
                                     ELSE LockoutEndUtc END,
                ModifiedUtc = SYSUTCDATETIME()
            WHERE UserId = @UserId;
        END

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, IpAddress)
        VALUES
            (@UserId, 'user',
             CASE WHEN @Succeeded = 1 THEN 'User.LoginSucceeded'
                  ELSE 'User.LoginFailed' END,
             'User', CONVERT(NVARCHAR(50), @UserId), @IpAddress);

    COMMIT TRAN;
END
GO

-- ---------------------------------------------------------------------------
-- usp_RefreshToken_Issue
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_RefreshToken_Issue') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_RefreshToken_Issue];
GO
CREATE PROCEDURE [Identity].[usp_RefreshToken_Issue]
    @UserId     UNIQUEIDENTIFIER,
    @DeviceId   UNIQUEIDENTIFIER = NULL,
    @TokenHash  VARBINARY(64),
    @ExpiresUtc DATETIME2(3),
    @IpAddress  VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [Identity].[RefreshToken]
        (UserId, DeviceId, TokenHash, ExpiresUtc, CreatedByIp)
    VALUES
        (@UserId, @DeviceId, @TokenHash, @ExpiresUtc, @IpAddress);

    SELECT SCOPE_IDENTITY() AS RefreshTokenId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_RefreshToken_Redeem
-- ---------------------------------------------------------------------------
/*
    Rotates a refresh token, and detects reuse.

    A token presented twice means either a race or a stolen token, and the two
    are indistinguishable from here. The safe response is to revoke the whole
    chain for that user: a legitimate client recovers by logging in again,
    while a thief loses the session immediately. Silently issuing a new token
    would leave an attacker with permanent access.
*/
IF OBJECT_ID('Identity.usp_RefreshToken_Redeem') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_RefreshToken_Redeem];
GO
CREATE PROCEDURE [Identity].[usp_RefreshToken_Redeem]
    @TokenHash    VARBINARY(64),
    @NewTokenHash VARBINARY(64),
    @ExpiresUtc   DATETIME2(3),
    @IpAddress    VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @userId UNIQUEIDENTIFIER, @deviceId UNIQUEIDENTIFIER;
    DECLARE @revoked DATETIME2(3), @expires DATETIME2(3);

    SELECT @userId = UserId, @deviceId = DeviceId,
           @revoked = RevokedUtc, @expires = ExpiresUtc
    FROM [Identity].[RefreshToken]
    WHERE TokenHash = @TokenHash;

    IF @userId IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNKNOWN_TOKEN' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId;
        RETURN;
    END

    IF @revoked IS NOT NULL
    BEGIN
        /*  Reuse of an already-rotated token. Burn the chain. */
        BEGIN TRAN;
            UPDATE [Identity].[RefreshToken]
            SET RevokedUtc = SYSUTCDATETIME()
            WHERE UserId = @userId AND RevokedUtc IS NULL;

            INSERT INTO [Audit].[AuditLog]
                (ActorUserId, ActorKind, [Action], EntityType, EntityId, IpAddress)
            VALUES
                (@userId, 'system', 'RefreshToken.ReuseDetected', 'User',
                 CONVERT(NVARCHAR(50), @userId), @IpAddress);
        COMMIT TRAN;

        SELECT CAST(0 AS BIT) AS Succeeded, 'TOKEN_REUSED' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId;
        RETURN;
    END

    IF @expires <= SYSUTCDATETIME()
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'TOKEN_EXPIRED' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId;
        RETURN;
    END

    BEGIN TRAN;
        UPDATE [Identity].[RefreshToken]
        SET RevokedUtc = SYSUTCDATETIME(), ReplacedByHash = @NewTokenHash
        WHERE TokenHash = @TokenHash;

        INSERT INTO [Identity].[RefreshToken]
            (UserId, DeviceId, TokenHash, ExpiresUtc, CreatedByIp)
        VALUES
            (@userId, @deviceId, @NewTokenHash, @ExpiresUtc, @IpAddress);
    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode,
           @userId AS UserId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_GetPermissions
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_User_GetPermissions') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_GetPermissions];
GO
CREATE PROCEDURE [Identity].[usp_User_GetPermissions]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DISTINCT p.Code
    FROM [Identity].[UserRole] ur
    JOIN [Identity].[RolePermission] rp ON rp.RoleId = ur.RoleId
    JOIN [Identity].[Permission] p ON p.PermissionId = rp.PermissionId
    WHERE ur.UserId = @UserId
    ORDER BY p.Code;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Device_Register
-- ---------------------------------------------------------------------------
/*
    Upsert by DeviceId, which the client generates and keeps.

    Keyed on the client's id rather than the FCM token because tokens rotate:
    keying on the token would create a new device row every few weeks and leave
    a trail of dead rows that push campaigns would keep targeting.
*/
IF OBJECT_ID('Identity.usp_Device_Register') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Device_Register];
GO
CREATE PROCEDURE [Identity].[usp_Device_Register]
    @DeviceId   UNIQUEIDENTIFIER,
    @UserId     UNIQUEIDENTIFIER,
    @Platform   VARCHAR(20),
    @OsVersion  NVARCHAR(50) = NULL,
    @AppVersion NVARCHAR(20) = NULL,
    @Model      NVARCHAR(100) = NULL,
    @FcmToken   NVARCHAR(512) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    MERGE [Identity].[Device] AS target
    USING (SELECT @DeviceId AS DeviceId) AS source
       ON target.DeviceId = source.DeviceId
    WHEN MATCHED THEN UPDATE SET
        UserId = @UserId,
        Platform = @Platform,
        OsVersion = @OsVersion,
        AppVersion = @AppVersion,
        Model = @Model,
        FcmToken = COALESCE(@FcmToken, target.FcmToken),
        IsActive = 1,
        LastSeenUtc = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN INSERT
        (DeviceId, UserId, Platform, OsVersion, AppVersion, Model,
         FcmToken, LastSeenUtc)
        VALUES
        (@DeviceId, @UserId, @Platform, @OsVersion, @AppVersion, @Model,
         @FcmToken, SYSUTCDATETIME());

    /*  No result set. The caller uses ExecuteAsync and reads nothing, and the
        row carries an FCM token — a push credential that should not travel
        anywhere it is not needed. */
END
GO
