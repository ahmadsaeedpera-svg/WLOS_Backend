/* Required for filtered indexes and indexes on computed columns. Set here
   rather than relying on the client, so the scripts deploy identically from
   sqlcmd, SSMS, Azure Data Studio or a CI runner. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Content, Notifications, Audit.

    Content is the CMS side: everything currently compiled into the Flutter
    binary — articles, wellness snippets, greetings, challenges, notification
    copy — moves here so it can change without a release.

    All content is versioned and localised. A translation is a row, not a
    column, so adding a language is data rather than a schema change.
*/

-- ---------------------------------------------------------------------------
-- Content
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Content.Category') IS NULL
CREATE TABLE [Content].[Category] (
    CategoryId  INT IDENTITY(1,1) NOT NULL,
    [Key]       VARCHAR(64) NOT NULL,
    SortOrder   INT NOT NULL DEFAULT 0,
    IsActive    BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_Category PRIMARY KEY CLUSTERED (CategoryId),
    CONSTRAINT UQ_Category_Key UNIQUE ([Key])
);
GO

/*  One row per content item, whatever kind it is.

    Articles, wellness snippets, greetings, challenges and notification copy
    share a table because they share a lifecycle — draft, review, publish,
    schedule, retire — and three near-identical CMS modules is how an admin
    portal rots. ContentType keeps them apart. */
IF OBJECT_ID('Content.ContentItem') IS NULL
CREATE TABLE [Content].[ContentItem] (
    ContentItemId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContentType   VARCHAR(40) NOT NULL,
    [Key]         VARCHAR(150) NULL,
    CategoryId    INT NULL,

    Status        VARCHAR(20) NOT NULL DEFAULT 'draft',
    PublishFromUtc DATETIME2(3) NULL,
    PublishUntilUtc DATETIME2(3) NULL,

    /*  Targeting. All nullable — null means "no restriction", which is the
        common case and should not require filling anything in. */
    CountryFilter NVARCHAR(MAX) NULL,
    MinAppVersion NVARCHAR(20) NULL,
    /*  Gestational week range, for content that only makes sense in context. */
    FromWeek      TINYINT NULL,
    ToWeek        TINYINT NULL,
    Season        VARCHAR(20) NULL,

    /*  Editorial weighting for the rotation. Higher appears more often; it
        does not pin an item to a date, because a fixed calendar is how a
        content schedule becomes a maintenance burden. */
    Weight        INT NOT NULL DEFAULT 100,

    /*  Every clinical claim carries its source and review date, as the mobile
        app already does. Not decoration — the About screen renders these. */
    SourceCitation NVARCHAR(300) NULL,
    ReviewedUtc    DATETIME2(3) NULL,
    ReviewedBy     NVARCHAR(200) NULL,

    IsDeleted     BIT NOT NULL DEFAULT 0,
    CreatedOn    DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy     UNIQUEIDENTIFIER NULL,
    ModifiedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedBy    UNIQUEIDENTIFIER NULL,
    RowVersion    ROWVERSION NOT NULL,

    CONSTRAINT PK_ContentItem PRIMARY KEY CLUSTERED (ContentItemId),
    CONSTRAINT FK_ContentItem_Category FOREIGN KEY (CategoryId)
        REFERENCES [Content].[Category](CategoryId),
    CONSTRAINT CK_ContentItem_Status
        CHECK (Status IN ('draft','review','published','retired')),
    CONSTRAINT CK_ContentItem_Type CHECK (ContentType IN (
        'article','wellnessSnippet','greeting','seasonalNote','challenge',
        'encouragement','notificationCopy','onboardingPage','insightTopic',
        'hospitalBagTemplate','birthPreferenceOption'
    ))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ContentItem_Type_Status')
CREATE INDEX IX_ContentItem_Type_Status
    ON [Content].[ContentItem](ContentType, Status, IsDeleted)
    INCLUDE (CategoryId, Weight, FromWeek, ToWeek, Season);
GO

IF OBJECT_ID('Content.ContentTranslation') IS NULL
CREATE TABLE [Content].[ContentTranslation] (
    TranslationId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContentItemId UNIQUEIDENTIFIER NOT NULL,
    LanguageCode  CHAR(5) NOT NULL,
    Title         NVARCHAR(300) NULL,
    Body          NVARCHAR(MAX) NULL,
    Summary       NVARCHAR(1000) NULL,
    /*  Free-form extras that differ by content type — an emoji for a size
        comparison, an icon name for a challenge. JSON rather than twenty
        mostly-null columns. */
    MetadataJson  NVARCHAR(MAX) NULL,
    IsMachineTranslated BIT NOT NULL DEFAULT 0,
    ModifiedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion    ROWVERSION NOT NULL,
    CONSTRAINT PK_ContentTranslation PRIMARY KEY CLUSTERED (TranslationId),
    CONSTRAINT FK_ContentTranslation_Item FOREIGN KEY (ContentItemId)
        REFERENCES [Content].[ContentItem](ContentItemId) ON DELETE CASCADE,
    CONSTRAINT UQ_ContentTranslation UNIQUE (ContentItemId, LanguageCode)
);
GO

IF OBJECT_ID('Content.Media') IS NULL
CREATE TABLE [Content].[Media] (
    MediaId      UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    [FileName]   NVARCHAR(300) NOT NULL,
    ContentType  NVARCHAR(100) NOT NULL,
    SizeBytes    BIGINT NOT NULL,
    /*  Storage-agnostic. The blob lives behind IBlobStorage, so moving from
        Azure to S3 is a configuration change rather than a migration. */
    StorageKey   NVARCHAR(500) NOT NULL,
    Width        INT NULL,
    Height       INT NULL,
    AltText      NVARCHAR(300) NULL,
    UploadedBy   UNIQUEIDENTIFIER NULL,
    CreatedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    IsDeleted    BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Media PRIMARY KEY CLUSTERED (MediaId)
);
GO

-- ---------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Notifications.Template') IS NULL
CREATE TABLE [Notifications].[Template] (
    TemplateId   INT IDENTITY(1,1) NOT NULL,
    [Key]        VARCHAR(100) NOT NULL,
    ReminderKind VARCHAR(50) NULL,
    Description  NVARCHAR(500) NULL,
    IsActive     BIT NOT NULL DEFAULT 1,
    CreatedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_NotificationTemplate PRIMARY KEY CLUSTERED (TemplateId),
    CONSTRAINT UQ_NotificationTemplate_Key UNIQUE ([Key])
);
GO

IF OBJECT_ID('Notifications.TemplateTranslation') IS NULL
CREATE TABLE [Notifications].[TemplateTranslation] (
    TemplateId   INT NOT NULL,
    LanguageCode CHAR(5) NOT NULL,
    Title        NVARCHAR(200) NOT NULL,
    Body         NVARCHAR(500) NOT NULL,
    CONSTRAINT PK_TemplateTranslation PRIMARY KEY CLUSTERED (TemplateId, LanguageCode),
    CONSTRAINT FK_TemplateTranslation_Template FOREIGN KEY (TemplateId)
        REFERENCES [Notifications].[Template](TemplateId) ON DELETE CASCADE
);
GO

IF OBJECT_ID('Notifications.Campaign') IS NULL
CREATE TABLE [Notifications].[Campaign] (
    CampaignId   UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    Name         NVARCHAR(200) NOT NULL,
    TemplateId   INT NULL,
    Status       VARCHAR(20) NOT NULL DEFAULT 'draft',
    /*  JSON predicate describing who receives it — country, app version,
        pregnancy week range, days since last open. Evaluated server-side so
        the segment is auditable after the fact. */
    SegmentJson  NVARCHAR(MAX) NULL,
    ScheduledUtc DATETIME2(3) NULL,
    StartedUtc   DATETIME2(3) NULL,
    CompletedUtc DATETIME2(3) NULL,
    /*  Counters rather than a computed join. A campaign to 100k users should
        not require scanning the delivery table to render a dashboard row. */
    TargetCount  INT NOT NULL DEFAULT 0,
    SentCount    INT NOT NULL DEFAULT 0,
    FailedCount  INT NOT NULL DEFAULT 0,
    OpenedCount  INT NOT NULL DEFAULT 0,
    CreatedBy    UNIQUEIDENTIFIER NULL,
    CreatedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    RowVersion   ROWVERSION NOT NULL,
    CONSTRAINT PK_Campaign PRIMARY KEY CLUSTERED (CampaignId),
    CONSTRAINT FK_Campaign_Template FOREIGN KEY (TemplateId)
        REFERENCES [Notifications].[Template](TemplateId),
    CONSTRAINT CK_Campaign_Status CHECK (Status IN
        ('draft','scheduled','sending','paused','completed','cancelled'))
);
GO

IF OBJECT_ID('Notifications.Delivery') IS NULL
CREATE TABLE [Notifications].[Delivery] (
    DeliveryId  BIGINT IDENTITY(1,1) NOT NULL,
    CampaignId  UNIQUEIDENTIFIER NULL,
    UserId      UNIQUEIDENTIFIER NOT NULL,
    DeviceId    UNIQUEIDENTIFIER NULL,
    Status      VARCHAR(20) NOT NULL DEFAULT 'pending',
    Title       NVARCHAR(200) NULL,
    Body        NVARCHAR(500) NULL,
    ProviderMessageId NVARCHAR(200) NULL,
    ErrorCode   NVARCHAR(100) NULL,
    QueuedUtc   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    SentUtc     DATETIME2(3) NULL,
    OpenedUtc   DATETIME2(3) NULL,
    CONSTRAINT PK_Delivery PRIMARY KEY CLUSTERED (DeliveryId),
    CONSTRAINT FK_Delivery_Campaign FOREIGN KEY (CampaignId)
        REFERENCES [Notifications].[Campaign](CampaignId),
    CONSTRAINT CK_Delivery_Status CHECK (Status IN
        ('pending','sent','failed','opened','suppressed'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Delivery_Campaign')
CREATE INDEX IX_Delivery_Campaign ON [Notifications].[Delivery](CampaignId, Status);
GO

-- ---------------------------------------------------------------------------
-- Audit
-- ---------------------------------------------------------------------------

/*  Append-only.

    No UPDATE or DELETE stored procedure exists for this table, and the
    application login is granted INSERT and SELECT only. An audit log that the
    application can rewrite is not an audit log.
*/
IF OBJECT_ID('Audit.AuditLog') IS NULL
CREATE TABLE [Audit].[AuditLog] (
    AuditLogId  BIGINT IDENTITY(1,1) NOT NULL,
    OccurredUtc DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    ActorUserId UNIQUEIDENTIFIER NULL,
    ActorKind   VARCHAR(20) NOT NULL DEFAULT 'user',
    [Action]    VARCHAR(100) NOT NULL,
    EntityType  VARCHAR(100) NULL,
    EntityId    NVARCHAR(100) NULL,
    /*  Before/after for admin changes. Never populated for health rows: an
        audit trail that copies symptom data doubles the exposure of the thing
        it is meant to protect. */
    BeforeJson  NVARCHAR(MAX) NULL,
    AfterJson   NVARCHAR(MAX) NULL,
    IpAddress   VARCHAR(45) NULL,
    UserAgent   NVARCHAR(500) NULL,
    CorrelationId UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_AuditLog PRIMARY KEY CLUSTERED (AuditLogId)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditLog_Occurred')
CREATE INDEX IX_AuditLog_Occurred ON [Audit].[AuditLog](OccurredUtc DESC)
    INCLUDE (ActorUserId, [Action], EntityType);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_AuditLog_Entity')
CREATE INDEX IX_AuditLog_Entity ON [Audit].[AuditLog](EntityType, EntityId, OccurredUtc DESC);
GO
