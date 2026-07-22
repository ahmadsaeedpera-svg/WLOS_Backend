/* Required for filtered indexes and indexes on computed columns. Set here
   rather than relying on the client, so the scripts deploy identically from
   sqlcmd, SSMS, Azure Data Studio or a CI runner. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Administration — feature flags, settings, app versions.

    This schema is what delivers the actual objective: changing what the app
    does without shipping a build. Everything here is read by the client on
    launch and cached, so it has to be cheap to read and safe to get wrong —
    a flag the server cannot answer for must fall back to the client's
    compiled-in default rather than failing the launch.
*/

IF OBJECT_ID('Administration.FeatureFlag') IS NULL
CREATE TABLE [Administration].[FeatureFlag] (
    FeatureFlagId   INT IDENTITY(1,1) NOT NULL,
    [Key]           VARCHAR(100) NOT NULL,
    Name            NVARCHAR(200) NOT NULL,
    Description     NVARCHAR(1000) NULL,

    /*  The master switch. When 0 the flag is off for everyone regardless of
        every rule below — an operator killing a feature at 3am should not
        have to reason about rollout percentages. */
    IsEnabled       BIT NOT NULL DEFAULT 0,

    /*  0-100. Assignment is deterministic per user, not random: see
        usp_FeatureFlag_Evaluate. A user who gets the feature must keep it
        across launches, or the app appears to flicker between two products. */
    RolloutPercent  TINYINT NOT NULL DEFAULT 0,

    /*  Below this the client is told the flag is off, whatever else says.
        Lets a server-side feature ship ahead of the client that renders it. */
    MinAppVersion   NVARCHAR(20) NULL,

    /*  Comma-free JSON array of ISO codes. NULL means everywhere. */
    CountryFilter   NVARCHAR(MAX) NULL,

    RequiresPremium BIT NOT NULL DEFAULT 0,
    BetaOnly        BIT NOT NULL DEFAULT 0,

    /*  What the client should use if it cannot reach the server at all. Kept
        server-side too so the admin can see what an offline client is
        currently doing. */
    DefaultValue    BIT NOT NULL DEFAULT 0,

    CreatedUtc      DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedUtc     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedBy      UNIQUEIDENTIFIER NULL,
    RowVersion      ROWVERSION NOT NULL,

    CONSTRAINT PK_FeatureFlag PRIMARY KEY CLUSTERED (FeatureFlagId),
    CONSTRAINT UQ_FeatureFlag_Key UNIQUE ([Key]),
    CONSTRAINT CK_FeatureFlag_Rollout CHECK (RolloutPercent BETWEEN 0 AND 100)
);
GO

/*  A/B variants hang off a flag rather than being a separate concept, so an
    experiment can be wound down by switching its parent flag off. */
IF OBJECT_ID('Administration.FeatureFlagVariant') IS NULL
CREATE TABLE [Administration].[FeatureFlagVariant] (
    VariantId       INT IDENTITY(1,1) NOT NULL,
    FeatureFlagId   INT NOT NULL,
    [Key]           VARCHAR(50) NOT NULL,
    Weight          TINYINT NOT NULL DEFAULT 50,
    PayloadJson     NVARCHAR(MAX) NULL,
    CONSTRAINT PK_FeatureFlagVariant PRIMARY KEY CLUSTERED (VariantId),
    CONSTRAINT FK_FeatureFlagVariant_Flag FOREIGN KEY (FeatureFlagId)
        REFERENCES [Administration].[FeatureFlag](FeatureFlagId) ON DELETE CASCADE,
    CONSTRAINT UQ_FeatureFlagVariant UNIQUE (FeatureFlagId, [Key])
);
GO

/*  Records which variant a user landed on.

    Written once and never recomputed. Without it, changing a variant's weight
    would silently move users between arms mid-experiment and invalidate the
    result. */
IF OBJECT_ID('Administration.FeatureFlagAssignment') IS NULL
CREATE TABLE [Administration].[FeatureFlagAssignment] (
    FeatureFlagId INT NOT NULL,
    UserId        UNIQUEIDENTIFIER NOT NULL,
    VariantId     INT NULL,
    IsEnabled     BIT NOT NULL,
    AssignedUtc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_FeatureFlagAssignment PRIMARY KEY CLUSTERED (FeatureFlagId, UserId),
    CONSTRAINT FK_FFAssignment_Flag FOREIGN KEY (FeatureFlagId)
        REFERENCES [Administration].[FeatureFlag](FeatureFlagId) ON DELETE CASCADE,
    CONSTRAINT FK_FFAssignment_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId)
);
GO

IF OBJECT_ID('Administration.Setting') IS NULL
CREATE TABLE [Administration].[Setting] (
    SettingId     INT IDENTITY(1,1) NOT NULL,
    [Key]         VARCHAR(100) NOT NULL,
    [Value]       NVARCHAR(MAX) NULL,
    DataType      VARCHAR(20) NOT NULL DEFAULT 'string',
    Category      NVARCHAR(64) NOT NULL DEFAULT 'General',
    Description   NVARCHAR(500) NULL,

    /*  Whether the mobile client may read it. Off by default: a setting is
        server-side until someone decides it is safe to publish, rather than
        the reverse. */
    IsClientVisible BIT NOT NULL DEFAULT 0,

    IsSecret      BIT NOT NULL DEFAULT 0,
    ModifiedUtc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedBy    UNIQUEIDENTIFIER NULL,
    RowVersion    ROWVERSION NOT NULL,
    CONSTRAINT PK_Setting PRIMARY KEY CLUSTERED (SettingId),
    CONSTRAINT UQ_Setting_Key UNIQUE ([Key]),
    CONSTRAINT CK_Setting_DataType
        CHECK (DataType IN ('string','int','bool','json','decimal'))
);
GO

IF OBJECT_ID('Administration.AppVersion') IS NULL
CREATE TABLE [Administration].[AppVersion] (
    AppVersionId  INT IDENTITY(1,1) NOT NULL,
    Platform      VARCHAR(20) NOT NULL,
    [Version]     NVARCHAR(20) NOT NULL,
    BuildNumber   INT NOT NULL,
    /*  Below this the client shows a blocking update screen. The kill switch
        for a build with a data-corrupting bug in it. */
    IsMinimumSupported BIT NOT NULL DEFAULT 0,
    IsLatest      BIT NOT NULL DEFAULT 0,
    ReleaseNotes  NVARCHAR(MAX) NULL,
    ReleasedUtc   DATETIME2(3) NULL,
    CreatedUtc    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_AppVersion PRIMARY KEY CLUSTERED (AppVersionId),
    CONSTRAINT UQ_AppVersion UNIQUE (Platform, [Version]),
    CONSTRAINT CK_AppVersion_Platform CHECK (Platform IN ('android','ios','web'))
);
GO

IF OBJECT_ID('Administration.SupportTicket') IS NULL
CREATE TABLE [Administration].[SupportTicket] (
    TicketId      UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    UserId        UNIQUEIDENTIFIER NULL,
    Subject       NVARCHAR(200) NOT NULL,
    Body          NVARCHAR(MAX) NOT NULL,
    Status        VARCHAR(20) NOT NULL DEFAULT 'open',
    Priority      VARCHAR(20) NOT NULL DEFAULT 'normal',
    AssignedTo    UNIQUEIDENTIFIER NULL,
    AppVersion    NVARCHAR(20) NULL,
    Platform      VARCHAR(20) NULL,
    CreatedUtc    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ResolvedUtc   DATETIME2(3) NULL,
    CONSTRAINT PK_SupportTicket PRIMARY KEY CLUSTERED (TicketId),
    CONSTRAINT FK_SupportTicket_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT CK_SupportTicket_Status
        CHECK (Status IN ('open','pending','resolved','closed'))
);
GO

/*  Crash reports arrive scrubbed by the client — see the mobile app's
    CrashReporter. The server does not attempt to re-scrub: it cannot know
    what was personal, and a second pass that mangles a stack trace makes the
    report useless without making it safer. */
IF OBJECT_ID('Administration.CrashReport') IS NULL
CREATE TABLE [Administration].[CrashReport] (
    CrashReportId BIGINT IDENTITY(1,1) NOT NULL,
    DeviceId      UNIQUEIDENTIFIER NULL,
    Platform      VARCHAR(20) NOT NULL,
    AppVersion    NVARCHAR(20) NOT NULL,
    OsVersion     NVARCHAR(50) NULL,
    ExceptionType NVARCHAR(200) NOT NULL,
    /*  A hash of the normalised stack, so identical crashes group without
        having to compare the full text on every insert. */
    Fingerprint   CHAR(64) NOT NULL,
    StackTrace    NVARCHAR(MAX) NULL,
    OccurredUtc   DATETIME2(3) NOT NULL,
    ReceivedUtc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_CrashReport PRIMARY KEY CLUSTERED (CrashReportId)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_CrashReport_Fingerprint')
CREATE INDEX IX_CrashReport_Fingerprint
    ON [Administration].[CrashReport](Fingerprint, OccurredUtc DESC);
GO
