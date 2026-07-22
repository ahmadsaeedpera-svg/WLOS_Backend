/* Required for filtered indexes and indexes on computed columns. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Enterprise CMS.

    Extends the Content schema already deployed rather than replacing it.
    `Content.ContentItem`, `Content.Category`, `Content.ContentTranslation` and
    `Content.Media` are live and referenced; the tables below add versioning,
    an editorial workflow, scheduling, tags and authorship around them.

    Naming note: the specification calls these ContentCategory,
    ContentLocalization and MediaAsset. The deployed names are kept — renaming
    a working table buys nothing and breaks the repository, the seed and the
    search index that already point at it.

    ## The property that matters

    Nothing is ever overwritten. An edit writes a new ContentVersion and moves
    a pointer. That is what makes "restore version" a pointer move rather than
    an archaeology exercise, and it is what lets an approval refer to exactly
    the bytes that were approved rather than to whatever the row says today.
*/

-- ---------------------------------------------------------------------------
-- Authors
-- ---------------------------------------------------------------------------

/*  Separate from Identity.User on purpose.

    A byline outlives an account. A clinician who reviewed an article in 2026
    and left in 2027 must still be creditable on that article, and deleting
    their login must not blank the attribution on published content. */
IF OBJECT_ID('Content.ContentAuthor') IS NULL
CREATE TABLE [Content].[ContentAuthor] (
    AuthorId     UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    UserId       UNIQUEIDENTIFIER NULL,
    DisplayName  NVARCHAR(200) NOT NULL,
    Credentials  NVARCHAR(200) NULL,
    Bio          NVARCHAR(MAX) NULL,
    AvatarMediaId UNIQUEIDENTIFIER NULL,
    IsActive     BIT NOT NULL DEFAULT 1,
    CreatedOn   DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ContentAuthor PRIMARY KEY CLUSTERED (AuthorId),
    CONSTRAINT FK_ContentAuthor_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT FK_ContentAuthor_Media FOREIGN KEY (AvatarMediaId)
        REFERENCES [Content].[Media](MediaId)
);
GO

-- ---------------------------------------------------------------------------
-- Versions
-- ---------------------------------------------------------------------------

/*  An immutable snapshot of an item's translatable payload at one moment.

    Stored as JSON rather than mirroring the translation columns. A version has
    to survive a schema change to ContentTranslation — the whole point is to
    read back what was published two years ago — and a mirrored column set
    would need migrating in lockstep, which is how version history quietly
    becomes lossy. */
IF OBJECT_ID('Content.ContentVersion') IS NULL
CREATE TABLE [Content].[ContentVersion] (
    ContentVersionId UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContentItemId    UNIQUEIDENTIFIER NOT NULL,
    VersionNumber    INT NOT NULL,
    /*  Full payload: every localisation plus the item's own targeting fields,
        exactly as they stood. */
    SnapshotJson     NVARCHAR(MAX) NOT NULL,
    ChangeSummary    NVARCHAR(500) NULL,
    CreatedOn       DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy        UNIQUEIDENTIFIER NULL,
    CONSTRAINT PK_ContentVersion PRIMARY KEY CLUSTERED (ContentVersionId),
    CONSTRAINT FK_ContentVersion_Item FOREIGN KEY (ContentItemId)
        REFERENCES [Content].[ContentItem](ContentItemId) ON DELETE CASCADE,
    CONSTRAINT UQ_ContentVersion UNIQUE (ContentItemId, VersionNumber)
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ContentVersion_Item')
CREATE INDEX IX_ContentVersion_Item
    ON [Content].[ContentVersion](ContentItemId, VersionNumber DESC);
GO

-- ---------------------------------------------------------------------------
-- Review and approval
-- ---------------------------------------------------------------------------

/*  Review is the editorial read; approval is the gate before publish.

    Kept apart because they answer different questions and are done by
    different people. A clinician approves that an article is not misleading;
    an editor reviews that it reads well. Collapsing them would mean one
    sign-off standing for both, which is exactly the failure the medical
    review process exists to prevent. */
IF OBJECT_ID('Content.ContentReview') IS NULL
CREATE TABLE [Content].[ContentReview] (
    ReviewId       UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContentItemId  UNIQUEIDENTIFIER NOT NULL,
    ContentVersionId UNIQUEIDENTIFIER NULL,
    ReviewerUserId UNIQUEIDENTIFIER NULL,
    ReviewKind     VARCHAR(30) NOT NULL DEFAULT 'editorial',
    Outcome        VARCHAR(20) NOT NULL,
    Comments       NVARCHAR(MAX) NULL,
    CreatedOn     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ContentReview PRIMARY KEY CLUSTERED (ReviewId),
    CONSTRAINT FK_ContentReview_Item FOREIGN KEY (ContentItemId)
        REFERENCES [Content].[ContentItem](ContentItemId) ON DELETE CASCADE,
    CONSTRAINT FK_ContentReview_Version FOREIGN KEY (ContentVersionId)
        REFERENCES [Content].[ContentVersion](ContentVersionId),
    CONSTRAINT CK_ContentReview_Kind
        CHECK (ReviewKind IN ('editorial','clinical','legal','translation')),
    CONSTRAINT CK_ContentReview_Outcome
        CHECK (Outcome IN ('pending','approved','rejected','changesRequested'))
);
GO

IF OBJECT_ID('Content.ContentApproval') IS NULL
CREATE TABLE [Content].[ContentApproval] (
    ApprovalId       UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContentItemId    UNIQUEIDENTIFIER NOT NULL,
    /*  Not nullable. An approval that does not name the exact bytes it
        approved is worthless the moment the item changes again. */
    ContentVersionId UNIQUEIDENTIFIER NOT NULL,
    ApproverUserId   UNIQUEIDENTIFIER NULL,
    IsApproved       BIT NOT NULL,
    Reason           NVARCHAR(MAX) NULL,
    CreatedOn       DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ContentApproval PRIMARY KEY CLUSTERED (ApprovalId),
    CONSTRAINT FK_ContentApproval_Item FOREIGN KEY (ContentItemId)
        REFERENCES [Content].[ContentItem](ContentItemId) ON DELETE CASCADE,
    CONSTRAINT FK_ContentApproval_Version FOREIGN KEY (ContentVersionId)
        REFERENCES [Content].[ContentVersion](ContentVersionId)
);
GO

-- ---------------------------------------------------------------------------
-- Scheduling
-- ---------------------------------------------------------------------------

/*  A future publish or unpublish, executed by a background job.

    A row rather than a column on ContentItem so an item can carry several
    scheduled transitions — publish on Monday, retire at the end of the month
    — and so a cancelled schedule leaves a record of having existed. */
IF OBJECT_ID('Content.ContentPublishSchedule') IS NULL
CREATE TABLE [Content].[ContentPublishSchedule] (
    ScheduleId     UNIQUEIDENTIFIER NOT NULL DEFAULT NEWSEQUENTIALID(),
    ContentItemId  UNIQUEIDENTIFIER NOT NULL,
    [Action]       VARCHAR(20) NOT NULL,
    ScheduledUtc   DATETIME2(3) NOT NULL,
    Status         VARCHAR(20) NOT NULL DEFAULT 'pending',
    ExecutedUtc    DATETIME2(3) NULL,
    FailureReason  NVARCHAR(500) NULL,
    CreatedBy      UNIQUEIDENTIFIER NULL,
    CreatedOn     DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_ContentPublishSchedule PRIMARY KEY CLUSTERED (ScheduleId),
    CONSTRAINT FK_ContentSchedule_Item FOREIGN KEY (ContentItemId)
        REFERENCES [Content].[ContentItem](ContentItemId) ON DELETE CASCADE,
    CONSTRAINT CK_ContentSchedule_Action
        CHECK ([Action] IN ('publish','unpublish','retire')),
    CONSTRAINT CK_ContentSchedule_Status
        CHECK (Status IN ('pending','executed','cancelled','failed'))
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ContentSchedule_Due')
CREATE INDEX IX_ContentSchedule_Due
    ON [Content].[ContentPublishSchedule](Status, ScheduledUtc)
    WHERE Status = 'pending';
GO

-- ---------------------------------------------------------------------------
-- Tags
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Content.ContentTag') IS NULL
CREATE TABLE [Content].[ContentTag] (
    TagId      INT IDENTITY(1,1) NOT NULL,
    [Key]      VARCHAR(64) NOT NULL,
    Label      NVARCHAR(100) NOT NULL,
    IsActive   BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_ContentTag PRIMARY KEY CLUSTERED (TagId),
    CONSTRAINT UQ_ContentTag_Key UNIQUE ([Key])
);
GO

IF OBJECT_ID('Content.ContentItemTag') IS NULL
CREATE TABLE [Content].[ContentItemTag] (
    ContentItemId UNIQUEIDENTIFIER NOT NULL,
    TagId         INT NOT NULL,
    CONSTRAINT PK_ContentItemTag PRIMARY KEY CLUSTERED (ContentItemId, TagId),
    CONSTRAINT FK_ContentItemTag_Item FOREIGN KEY (ContentItemId)
        REFERENCES [Content].[ContentItem](ContentItemId) ON DELETE CASCADE,
    CONSTRAINT FK_ContentItemTag_Tag FOREIGN KEY (TagId)
        REFERENCES [Content].[ContentTag](TagId) ON DELETE CASCADE
);
GO

-- ---------------------------------------------------------------------------
-- Columns added to the existing ContentItem
-- ---------------------------------------------------------------------------

IF COL_LENGTH('Content.ContentItem', 'CurrentVersionId') IS NULL
    ALTER TABLE [Content].[ContentItem]
        ADD CurrentVersionId UNIQUEIDENTIFIER NULL;
GO

IF COL_LENGTH('Content.ContentItem', 'PublishedVersionId') IS NULL
    /*  What the app is actually serving, which is not necessarily the latest.
        An editor may be four drafts ahead of what is live. */
    ALTER TABLE [Content].[ContentItem]
        ADD PublishedVersionId UNIQUEIDENTIFIER NULL;
GO

IF COL_LENGTH('Content.ContentItem', 'AuthorId') IS NULL
    ALTER TABLE [Content].[ContentItem]
        ADD AuthorId UNIQUEIDENTIFIER NULL;
GO

IF COL_LENGTH('Content.ContentItem', 'VersionNumber') IS NULL
    ALTER TABLE [Content].[ContentItem]
        ADD VersionNumber INT NOT NULL DEFAULT 0;
GO

-- ---------------------------------------------------------------------------
-- Key uniqueness
-- ---------------------------------------------------------------------------

/*  A key identifies one item within its type.

    Without this, two rows could share 'greeting.morning' and
    usp_Content_GetForClient would return both — the app would render a
    duplicate, or pick one arbitrarily depending on row order. Found by the
    workflow test returning two rows where it expected one.

    Filtered so it only binds where a key is actually set (most snippets have
    none) and ignores soft-deleted rows, since a retired item should not block
    its replacement from taking the same key. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_ContentItem_Type_Key')
CREATE UNIQUE INDEX UX_ContentItem_Type_Key
    ON [Content].[ContentItem](ContentType, [Key])
    WHERE [Key] IS NOT NULL AND IsDeleted = 0;
GO
