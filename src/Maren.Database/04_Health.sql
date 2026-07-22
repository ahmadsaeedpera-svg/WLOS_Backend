/* Required for filtered indexes and indexes on computed columns. Set here
   rather than relying on the client, so the scripts deploy identically from
   sqlcmd, SSMS, Azure Data Studio or a CI runner. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Health.

    ## Sync shape

    Every table here is written by an offline client and reconciled on arrival,
    so all of them carry the same four columns:

      - a client-assignable GUID primary key
      - ModifiedOn, for last-writer-wins on a field-level conflict
      - IsDeleted, because a delete has to sync as an event rather than an
        absence — a row that simply vanished from the client is
        indistinguishable from one that never reached it
      - RowVersion, for the server-side delta watermark

    ## No derived health values

    Nothing here stores an interpretation. There is no "cycle regularity", no
    "risk", no computed score. The mobile app is built so it cannot produce
    those, and a server that produced them and synced them down would
    reintroduce exactly the regulatory exposure the client avoids.
*/

IF OBJECT_ID('Health.Pregnancy') IS NULL
CREATE TABLE [Health].[Pregnancy] (
    PregnancyId       UNIQUEIDENTIFIER NOT NULL,
    UserId            UNIQUEIDENTIFIER NOT NULL,
    DueDate           DATE NOT NULL,
    /*  Which method produced DueDate, kept so the app can show its working
        rather than presenting a bare date of unknown origin. */
    DatingMethod      VARCHAR(30) NOT NULL,
    BasisDate         DATE NULL,
    ScanWeeks         TINYINT NULL,
    ScanDays          TINYINT NULL,
    StartedTrackingOn DATE NULL,
    ExpectingMultiples BIT NOT NULL DEFAULT 0,
    BabyCount         TINYINT NOT NULL DEFAULT 1,
    Status            VARCHAR(20) NOT NULL DEFAULT 'active',
    EndedUtc          DATETIME2(3) NULL,
    IsDeleted         BIT NOT NULL DEFAULT 0,
    CreatedOn        DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedOn       DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion        ROWVERSION NOT NULL,
    CONSTRAINT PK_Pregnancy PRIMARY KEY CLUSTERED (PregnancyId),
    CONSTRAINT FK_Pregnancy_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT CK_Pregnancy_Status
        CHECK (Status IN ('active','completed','ended'))
);
GO

IF OBJECT_ID('Health.Cycle') IS NULL
CREATE TABLE [Health].[Cycle] (
    CycleId     UNIQUEIDENTIFIER NOT NULL,
    UserId      UNIQUEIDENTIFIER NOT NULL,
    StartDate   DATE NOT NULL,
    EndDate     DATE NULL,
    /*  Recorded, never predicted. The app does not forecast a period, because
        a forecast is a clinical inference. */
    FlowLevel   VARCHAR(20) NULL,
    Notes       NVARCHAR(1000) NULL,
    IsDeleted   BIT NOT NULL DEFAULT 0,
    CreatedOn  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedOn DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion  ROWVERSION NOT NULL,
    CONSTRAINT PK_Cycle PRIMARY KEY CLUSTERED (CycleId),
    CONSTRAINT FK_Cycle_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Cycle_User_Start')
CREATE INDEX IX_Cycle_User_Start ON [Health].[Cycle](UserId, StartDate DESC);
GO

/*  The daily check-in, one row per user per day.

    Denormalised deliberately. The client writes it as a unit and the calendar
    reads it as a unit, and joining four tables to render one grid cell is how
    a month view becomes slow at 100k users. */
IF OBJECT_ID('Health.DailyLog') IS NULL
CREATE TABLE [Health].[DailyLog] (
    DailyLogId   UNIQUEIDENTIFIER NOT NULL,
    UserId       UNIQUEIDENTIFIER NOT NULL,
    LogDate      DATE NOT NULL,
    Mood         VARCHAR(20) NULL,
    Energy       VARCHAR(20) NULL,
    SleepQuality VARCHAR(20) NULL,
    WaterGlasses SMALLINT NOT NULL DEFAULT 0,
    Note         NVARCHAR(MAX) NULL,
    IsDeleted    BIT NOT NULL DEFAULT 0,
    CreatedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedOn  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion   ROWVERSION NOT NULL,
    CONSTRAINT PK_DailyLog PRIMARY KEY CLUSTERED (DailyLogId),
    CONSTRAINT FK_DailyLog_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId)
);
GO

/*  One check-in per calendar day. Enforced here rather than in the app,
    because two devices syncing the same day would otherwise both insert. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_DailyLog_User_Date')
CREATE UNIQUE INDEX UX_DailyLog_User_Date
    ON [Health].[DailyLog](UserId, LogDate) WHERE IsDeleted = 0;
GO

IF OBJECT_ID('Health.Symptom') IS NULL
CREATE TABLE [Health].[Symptom] (
    SymptomId   UNIQUEIDENTIFIER NOT NULL,
    UserId      UNIQUEIDENTIFIER NOT NULL,
    RecordedUtc DATETIME2(3) NOT NULL,
    LogDate     AS CAST(RecordedUtc AS DATE) PERSISTED,
    Kind        VARCHAR(40) NOT NULL,
    Intensity   VARCHAR(20) NULL,
    Label       NVARCHAR(100) NULL,
    Note        NVARCHAR(MAX) NULL,
    IsDeleted   BIT NOT NULL DEFAULT 0,
    CreatedOn  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedOn DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion  ROWVERSION NOT NULL,
    CONSTRAINT PK_Symptom PRIMARY KEY CLUSTERED (SymptomId),
    CONSTRAINT FK_Symptom_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Symptom_User_Date')
CREATE INDEX IX_Symptom_User_Date ON [Health].[Symptom](UserId, LogDate DESC)
    INCLUDE (Kind, Intensity);
GO

IF OBJECT_ID('Health.BodyMeasurement') IS NULL
CREATE TABLE [Health].[BodyMeasurement] (
    MeasurementId UNIQUEIDENTIFIER NOT NULL,
    UserId        UNIQUEIDENTIFIER NOT NULL,
    RecordedUtc   DATETIME2(3) NOT NULL,
    MeasurementType VARCHAR(30) NOT NULL DEFAULT 'weight',
    [Value]       DECIMAL(9,3) NOT NULL,
    Unit          VARCHAR(20) NOT NULL,
    Note          NVARCHAR(500) NULL,
    IsDeleted     BIT NOT NULL DEFAULT 0,
    CreatedOn    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion    ROWVERSION NOT NULL,
    CONSTRAINT PK_BodyMeasurement PRIMARY KEY CLUSTERED (MeasurementId),
    CONSTRAINT FK_BodyMeasurement_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_BodyMeasurement_User')
CREATE INDEX IX_BodyMeasurement_User
    ON [Health].[BodyMeasurement](UserId, RecordedUtc DESC);
GO

IF OBJECT_ID('Health.Appointment') IS NULL
CREATE TABLE [Health].[Appointment] (
    AppointmentId UNIQUEIDENTIFIER NOT NULL,
    UserId        UNIQUEIDENTIFIER NOT NULL,
    Title         NVARCHAR(200) NOT NULL,
    ScheduledUtc  DATETIME2(3) NOT NULL,
    Location      NVARCHAR(300) NULL,
    Practitioner  NVARCHAR(200) NULL,
    Notes         NVARCHAR(MAX) NULL,
    ReminderMinutesBefore INT NULL,
    IsDeleted     BIT NOT NULL DEFAULT 0,
    CreatedOn    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion    ROWVERSION NOT NULL,
    CONSTRAINT PK_Appointment PRIMARY KEY CLUSTERED (AppointmentId),
    CONSTRAINT FK_Appointment_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Appointment_User_Scheduled')
CREATE INDEX IX_Appointment_User_Scheduled
    ON [Health].[Appointment](UserId, ScheduledUtc);
GO

IF OBJECT_ID('Health.HospitalBagItem') IS NULL
CREATE TABLE [Health].[HospitalBagItem] (
    ItemId      UNIQUEIDENTIFIER NOT NULL,
    UserId      UNIQUEIDENTIFIER NOT NULL,
    /*  Null for user-added items; set when the row came from a seeded
        template, so a template revision can be reconciled later. */
    TemplateKey VARCHAR(100) NULL,
    Label       NVARCHAR(200) NOT NULL,
    Phase       VARCHAR(30) NOT NULL,
    Audience    VARCHAR(30) NOT NULL DEFAULT 'forYou',
    IsPacked    BIT NOT NULL DEFAULT 0,
    IsHidden    BIT NOT NULL DEFAULT 0,
    SortOrder   INT NOT NULL DEFAULT 0,
    IsDeleted   BIT NOT NULL DEFAULT 0,
    CreatedOn  DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedOn DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion  ROWVERSION NOT NULL,
    CONSTRAINT PK_HospitalBagItem PRIMARY KEY CLUSTERED (ItemId),
    CONSTRAINT FK_HospitalBagItem_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId)
);
GO

IF OBJECT_ID('Health.BirthPreference') IS NULL
CREATE TABLE [Health].[BirthPreference] (
    PreferenceId  UNIQUEIDENTIFIER NOT NULL,
    UserId        UNIQUEIDENTIFIER NOT NULL,
    SectionKey    VARCHAR(100) NOT NULL,
    OptionKey     VARCHAR(100) NOT NULL,
    IsSelected    BIT NOT NULL DEFAULT 0,
    CustomText    NVARCHAR(500) NULL,
    IsDeleted     BIT NOT NULL DEFAULT 0,
    CreatedOn    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion    ROWVERSION NOT NULL,
    CONSTRAINT PK_BirthPreference PRIMARY KEY CLUSTERED (PreferenceId),
    CONSTRAINT FK_BirthPreference_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT UQ_BirthPreference UNIQUE (UserId, SectionKey, OptionKey)
);
GO

/*  Sharing with a partner, midwife or doctor.

    A grant, not an account. The recipient does not get a login — they get a
    time-limited token that resolves to a read-only snapshot. That keeps the
    blast radius of a shared link small and means revocation is a single UPDATE
    rather than an account deletion. */
IF OBJECT_ID('Health.ShareGrant') IS NULL
CREATE TABLE [Health].[ShareGrant] (
    ShareGrantId  UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    UserId        UNIQUEIDENTIFIER NOT NULL,
    RecipientKind VARCHAR(20) NOT NULL,
    RecipientLabel NVARCHAR(200) NULL,
    /*  Hashed, like refresh tokens. A leaked table must not yield working
        share links. */
    TokenHash     VARBINARY(64) NOT NULL,
    /*  Which sections the recipient may see, as a JSON array of scope keys.
        A midwife summary and a partner summary are the same mechanism with
        different scopes. */
    ScopesJson    NVARCHAR(MAX) NOT NULL,
    ExpiresUtc    DATETIME2(3) NOT NULL,
    RevokedUtc    DATETIME2(3) NULL,
    LastViewedUtc DATETIME2(3) NULL,
    ViewCount     INT NOT NULL DEFAULT 0,
    CreatedOn    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ShareGrant PRIMARY KEY CLUSTERED (ShareGrantId),
    CONSTRAINT FK_ShareGrant_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT CK_ShareGrant_Kind
        CHECK (RecipientKind IN ('partner','midwife','doctor','other'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_ShareGrant_TokenHash')
CREATE UNIQUE INDEX UX_ShareGrant_TokenHash ON [Health].[ShareGrant](TokenHash);
GO
