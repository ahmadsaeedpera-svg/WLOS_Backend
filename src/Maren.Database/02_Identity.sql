/* Required for filtered indexes and indexes on computed columns. Set here
   rather than relying on the client, so the scripts deploy identically from
   sqlcmd, SSMS, Azure Data Studio or a CI runner. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Identity.

    ## Why the user id is a GUID and not an INT

    The mobile client creates records offline and syncs later, so ids have to
    be assignable by a client that cannot see the server's sequence. A
    sequential INT would force every offline insert to be re-keyed on arrival,
    which breaks every foreign key the client already wrote against it.

    GUIDs are NEWSEQUENTIALID() where the server assigns them so the clustered
    index does not fragment, and client-generated V4 elsewhere.

    ## Why deletion is soft

    A hard DELETE on a user cascades into their entire health history, and the
    one thing this product cannot do is lose that by accident. Erasure for GDPR
    purposes is a separate, deliberate operation — see usp_User_Erase — which
    overwrites rather than removes, so audit rows keep their shape.
*/

IF OBJECT_ID('Identity.Country') IS NULL
CREATE TABLE [Identity].[Country] (
    CountryId           INT IDENTITY(1,1) NOT NULL,
    IsoCode             CHAR(2) NOT NULL,
    Name                NVARCHAR(100) NOT NULL,
    DefaultLanguageCode CHAR(5) NOT NULL DEFAULT 'en-GB',
    IsSupported         BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_Country PRIMARY KEY CLUSTERED (CountryId),
    CONSTRAINT UQ_Country_IsoCode UNIQUE (IsoCode)
);
GO

IF OBJECT_ID('Identity.Language') IS NULL
CREATE TABLE [Identity].[Language] (
    LanguageId   INT IDENTITY(1,1) NOT NULL,
    Code         CHAR(5) NOT NULL,
    Name         NVARCHAR(100) NOT NULL,
    IsRightToLeft BIT NOT NULL DEFAULT 0,
    IsActive     BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_Language PRIMARY KEY CLUSTERED (LanguageId),
    CONSTRAINT UQ_Language_Code UNIQUE (Code)
);
GO

IF OBJECT_ID('Identity.[User]') IS NULL
CREATE TABLE [Identity].[User] (
    UserId              UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    Email               NVARCHAR(256) NULL,
    NormalisedEmail     NVARCHAR(256) NULL,
    PasswordHash        VARBINARY(256) NULL,
    PasswordSalt        VARBINARY(128) NULL,
    /*  Iteration count is stored per row, not as a constant. When the cost is
        raised the existing rows must still verify against the count they were
        written with, and rehash on next successful login. */
    PasswordIterations  INT NULL,
    SecurityStamp       UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
    CountryId           INT NULL,
    LanguageCode        CHAR(5) NOT NULL DEFAULT 'en-GB',
    IsEmailConfirmed    BIT NOT NULL DEFAULT 0,
    IsLockedOut         BIT NOT NULL DEFAULT 0,
    LockoutEndUtc       DATETIME2(3) NULL,
    FailedLoginCount    INT NOT NULL DEFAULT 0,
    IsDeleted           BIT NOT NULL DEFAULT 0,
    DeletedUtc          DATETIME2(3) NULL,
    CreatedUtc          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedUtc         DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion          ROWVERSION NOT NULL,
    CONSTRAINT PK_User PRIMARY KEY CLUSTERED (UserId),
    CONSTRAINT FK_User_Country FOREIGN KEY (CountryId)
        REFERENCES [Identity].[Country](CountryId)
);
GO

/*  Filtered unique index rather than a plain one: soft-deleted users keep
    their row, and two deleted accounts may legitimately share an address. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_User_NormalisedEmail')
CREATE UNIQUE INDEX UX_User_NormalisedEmail
    ON [Identity].[User](NormalisedEmail)
    WHERE NormalisedEmail IS NOT NULL AND IsDeleted = 0;
GO

IF OBJECT_ID('Identity.Profile') IS NULL
CREATE TABLE [Identity].[Profile] (
    UserId              UNIQUEIDENTIFIER NOT NULL,
    DisplayName         NVARCHAR(100) NULL,
    /*  How the app addresses her — "Mama", "Mum", or empty for plain "you".
        Stored verbatim because it is rendered verbatim. */
    SelfTerm            NVARCHAR(50) NULL,
    PartnerTerm         NVARCHAR(50) NULL,
    BabyTerm            NVARCHAR(50) NULL,
    ExpectingMultiples  BIT NOT NULL DEFAULT 0,
    DateOfBirth         DATE NULL,
    TimeZoneId          NVARCHAR(100) NULL,
    AvatarMediaId       UNIQUEIDENTIFIER NULL,
    CreatedUtc          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedUtc         DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion          ROWVERSION NOT NULL,
    CONSTRAINT PK_Profile PRIMARY KEY CLUSTERED (UserId),
    CONSTRAINT FK_Profile_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId)
);
GO

IF OBJECT_ID('Identity.Device') IS NULL
CREATE TABLE [Identity].[Device] (
    DeviceId            UNIQUEIDENTIFIER NOT NULL,
    UserId              UNIQUEIDENTIFIER NOT NULL,
    Platform            VARCHAR(20) NOT NULL,
    OsVersion           NVARCHAR(50) NULL,
    AppVersion          NVARCHAR(20) NULL,
    Model               NVARCHAR(100) NULL,
    /*  Nullable: a user may decline notification permission and still sync. */
    FcmToken            NVARCHAR(512) NULL,
    IsActive            BIT NOT NULL DEFAULT 1,
    LastSeenUtc         DATETIME2(3) NULL,
    /*  Watermark for delta sync. Everything changed after this has not yet
        reached the device. Per-device rather than per-user, because two of a
        user's devices are legitimately at different points. */
    LastSyncUtc         DATETIME2(3) NULL,
    CreatedUtc          DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion          ROWVERSION NOT NULL,
    CONSTRAINT PK_Device PRIMARY KEY CLUSTERED (DeviceId),
    CONSTRAINT FK_Device_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT CK_Device_Platform CHECK (Platform IN ('android','ios','web'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Device_UserId')
CREATE INDEX IX_Device_UserId ON [Identity].[Device](UserId) INCLUDE (FcmToken, IsActive);
GO

IF OBJECT_ID('Identity.RefreshToken') IS NULL
CREATE TABLE [Identity].[RefreshToken] (
    RefreshTokenId  BIGINT IDENTITY(1,1) NOT NULL,
    UserId          UNIQUEIDENTIFIER NOT NULL,
    DeviceId        UNIQUEIDENTIFIER NULL,
    /*  The token itself is never stored. A leaked backup of this table must
        not be usable to mint access tokens. */
    TokenHash       VARBINARY(64) NOT NULL,
    ExpiresUtc      DATETIME2(3) NOT NULL,
    RevokedUtc      DATETIME2(3) NULL,
    ReplacedByHash  VARBINARY(64) NULL,
    CreatedUtc      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedByIp     VARCHAR(45) NULL,
    CONSTRAINT PK_RefreshToken PRIMARY KEY CLUSTERED (RefreshTokenId),
    CONSTRAINT FK_RefreshToken_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_RefreshToken_Hash')
CREATE UNIQUE INDEX UX_RefreshToken_Hash ON [Identity].[RefreshToken](TokenHash);
GO

IF OBJECT_ID('Identity.Role') IS NULL
CREATE TABLE [Identity].[Role] (
    RoleId      INT IDENTITY(1,1) NOT NULL,
    Name        NVARCHAR(64) NOT NULL,
    Description NVARCHAR(256) NULL,
    IsSystem    BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Role PRIMARY KEY CLUSTERED (RoleId),
    CONSTRAINT UQ_Role_Name UNIQUE (Name)
);
GO

IF OBJECT_ID('Identity.Permission') IS NULL
CREATE TABLE [Identity].[Permission] (
    PermissionId INT IDENTITY(1,1) NOT NULL,
    Code         VARCHAR(100) NOT NULL,
    Description  NVARCHAR(256) NULL,
    Category     NVARCHAR(64) NOT NULL,
    CONSTRAINT PK_Permission PRIMARY KEY CLUSTERED (PermissionId),
    CONSTRAINT UQ_Permission_Code UNIQUE (Code)
);
GO

IF OBJECT_ID('Identity.RolePermission') IS NULL
CREATE TABLE [Identity].[RolePermission] (
    RoleId       INT NOT NULL,
    PermissionId INT NOT NULL,
    CONSTRAINT PK_RolePermission PRIMARY KEY CLUSTERED (RoleId, PermissionId),
    CONSTRAINT FK_RolePermission_Role FOREIGN KEY (RoleId)
        REFERENCES [Identity].[Role](RoleId) ON DELETE CASCADE,
    CONSTRAINT FK_RolePermission_Permission FOREIGN KEY (PermissionId)
        REFERENCES [Identity].[Permission](PermissionId) ON DELETE CASCADE
);
GO

IF OBJECT_ID('Identity.UserRole') IS NULL
CREATE TABLE [Identity].[UserRole] (
    UserId     UNIQUEIDENTIFIER NOT NULL,
    RoleId     INT NOT NULL,
    AssignedUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    AssignedBy UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_UserRole PRIMARY KEY CLUSTERED (UserId, RoleId),
    CONSTRAINT FK_UserRole_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT FK_UserRole_Role FOREIGN KEY (RoleId)
        REFERENCES [Identity].[Role](RoleId)
);
GO
