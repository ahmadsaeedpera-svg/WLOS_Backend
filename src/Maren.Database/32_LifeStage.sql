/*  32_LifeStage.sql

    The life-stage model. This is the foundation the platform pivot rests on.

    Why this exists
    ---------------
    Maren is becoming a companion for a woman's whole life rather than a
    pregnancy app, and until now the database had no concept of a life stage at
    all - not a column, not a table, not a string. Identity.Profile, the only
    place that could have carried it, is written once and empty by
    usp_User_Register and then never read or written by any procedure, so even
    DateOfBirth and TimeZoneId were unreachable.

    Two dimensions, not nineteen
    ----------------------------
    The product describes nineteen kinds of user - teen girl, university
    student, freelancer, busy professional mother, perimenopause, senior, and so
    on. Modelling nineteen experiences would mean nineteen code paths and a
    release every time a twentieth is imagined.

    They are not nineteen things. They are combinations of two independent
    dimensions:

      life stage  - where she is in her life (adolescence ... senior).
                    Exactly one at a time. Changes rarely. Often biological.
      role mode   - what she is doing (student, professional, homemaker,
                    caregiver ...). Several at once. Changes often. Never
                    biological.

    "Busy professional mother" is motherhood + professional. "University
    student" is young_adult + student. Twelve stages and eight modes cover all
    nineteen with room to spare, and the twentieth category somebody thinks of
    next year is an INSERT rather than a sprint.

    Stage is history, not a column
    ------------------------------
    UserLifeStage keeps rows with a start and an end rather than overwriting a
    single value. That is deliberate and it is the most important decision in
    this file.

    The longitudinal record is the entire moat of the AI companion: an
    assistant that knows she had irregular cycles at nineteen, was trying to
    conceive at twenty-nine and is describing perimenopause at forty-four can
    prepare her for a ten-minute appointment in a way no general model can. A
    single mutable column throws that away on every transition, silently, and it
    cannot be recovered afterwards.

    Declared, never inferred
    ------------------------
    Nothing in this schema advances a stage automatically. Source records who
    said so. A system that moved a woman from pregnancy to postpartum on a due
    date would, on the worst day of some women's lives, be cruel - and it would
    be wrong often enough to be untrustworthy the rest of the time.

    Compatibility
    -------------
    Purely additive. No existing table, column or procedure is altered.
    Identity.Profile keeps its pregnancy-shaped fields (BabyTerm,
    ExpectingMultiples, PartnerTerm) because the shipped app reads them; they
    are superseded rather than removed, and their retirement is tracked in
    TECHNICAL_DEBT.md.

    Idempotent. Safe to re-run.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Reference: the stages themselves
-- ---------------------------------------------------------------------------

/*  A table rather than a CHECK constraint. Stages carry display copy that needs
    localising and ordering, and a product that expects to add stages should not
    need a schema change to do it. */
IF OBJECT_ID('Identity.LifeStage') IS NULL
CREATE TABLE [Identity].[LifeStage] (
    LifeStageCode   VARCHAR(30)  NOT NULL,
    DisplayName     NVARCHAR(80) NOT NULL,
    Description     NVARCHAR(400) NULL,
    /*  Rough life order, for presenting a picker. Deliberately not a rule:
        stages are not required to be entered in order, and several are
        legitimately revisited. */
    SortOrder       INT NOT NULL,
    IsSelectable    BIT NOT NULL
        CONSTRAINT DF_LifeStage_IsSelectable DEFAULT 1,
    CONSTRAINT PK_LifeStage PRIMARY KEY CLUSTERED (LifeStageCode)
);
GO

-- ---------------------------------------------------------------------------
-- Reference: role modes
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Identity.RoleMode') IS NULL
CREATE TABLE [Identity].[RoleMode] (
    RoleModeCode    VARCHAR(30)  NOT NULL,
    DisplayName     NVARCHAR(80) NOT NULL,
    Description     NVARCHAR(400) NULL,
    SortOrder       INT NOT NULL,
    CONSTRAINT PK_RoleMode PRIMARY KEY CLUSTERED (RoleModeCode)
);
GO

-- ---------------------------------------------------------------------------
-- Her stage history
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Identity.UserLifeStage') IS NULL
CREATE TABLE [Identity].[UserLifeStage] (
    UserLifeStageId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT DF_UserLifeStage_Id DEFAULT NEWSEQUENTIALID(),
    UserId          UNIQUEIDENTIFIER NOT NULL,
    LifeStageCode   VARCHAR(30) NOT NULL,

    StartedOn       DATE NOT NULL
        CONSTRAINT DF_UserLifeStage_StartedOn DEFAULT CAST(SYSUTCDATETIME() AS DATE),
    /*  NULL means current. Exactly one open row per user, enforced by
        UX_UserLifeStage_Current below. */
    EndedOn         DATE NULL,

    /*  Who decided. 'user' is the only value that should ever be common;
        'operator' exists for support correcting a mistake, and 'import' for
        migration. Nothing writes 'system' today and nothing should without a
        product decision - see the header. */
    Source          VARCHAR(20) NOT NULL
        CONSTRAINT DF_UserLifeStage_Source DEFAULT 'user',

    Note            NVARCHAR(300) NULL,

    CONSTRAINT PK_UserLifeStage PRIMARY KEY CLUSTERED (UserLifeStageId),
    CONSTRAINT FK_UserLifeStage_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT FK_UserLifeStage_Stage FOREIGN KEY (LifeStageCode)
        REFERENCES [Identity].[LifeStage](LifeStageCode),
    CONSTRAINT CK_UserLifeStage_Source
        CHECK (Source IN ('user', 'operator', 'import')),
    CONSTRAINT CK_UserLifeStage_Dates
        CHECK (EndedOn IS NULL OR EndedOn >= StartedOn)
);
GO

/*  One current stage per user. A filtered unique index rather than application
    logic: two open rows would make "what stage is she in" ambiguous, and every
    dashboard, notification and AI turn asks that question. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'UX_UserLifeStage_Current'
                 AND object_id = OBJECT_ID('[Identity].[UserLifeStage]'))
    CREATE UNIQUE INDEX [UX_UserLifeStage_Current]
        ON [Identity].[UserLifeStage] (UserId)
        WHERE EndedOn IS NULL;
GO

/*  Unfiltered, for the foreign key and for reading a whole history including
    closed rows. The filtered index above cannot serve either - see
    30_Indexes_ForeignKeys.sql for why that distinction matters. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_UserLifeStage_UserId'
                 AND object_id = OBJECT_ID('[Identity].[UserLifeStage]'))
    CREATE INDEX [IX_UserLifeStage_UserId]
        ON [Identity].[UserLifeStage] (UserId, StartedOn DESC);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_UserLifeStage_LifeStageCode'
                 AND object_id = OBJECT_ID('[Identity].[UserLifeStage]'))
    CREATE INDEX [IX_UserLifeStage_LifeStageCode]
        ON [Identity].[UserLifeStage] (LifeStageCode);
GO

-- ---------------------------------------------------------------------------
-- Her role modes
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Identity.UserRoleMode') IS NULL
CREATE TABLE [Identity].[UserRoleMode] (
    UserId       UNIQUEIDENTIFIER NOT NULL,
    RoleModeCode VARCHAR(30) NOT NULL,
    AddedOn      DATETIME2(3) NOT NULL
        CONSTRAINT DF_UserRoleMode_AddedOn DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_UserRoleMode PRIMARY KEY CLUSTERED (UserId, RoleModeCode),
    CONSTRAINT FK_UserRoleMode_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT FK_UserRoleMode_Mode FOREIGN KEY (RoleModeCode)
        REFERENCES [Identity].[RoleMode](RoleModeCode)
);
GO

/*  UserId already leads the primary key, so the FK on it is covered.
    RoleModeCode is not, and "who is a caregiver" is a real query. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_UserRoleMode_RoleModeCode'
                 AND object_id = OBJECT_ID('[Identity].[UserRoleMode]'))
    CREATE INDEX [IX_UserRoleMode_RoleModeCode]
        ON [Identity].[UserRoleMode] (RoleModeCode);
GO

-- ---------------------------------------------------------------------------
-- Seed
-- ---------------------------------------------------------------------------

/*  Twelve stages. Copy is written from her side of the screen, not the
    system's: she picks "Expecting", not "pregnancy_trimester_state". */
MERGE [Identity].[LifeStage] AS target
USING (VALUES
    ('adolescence',      N'Growing up',        N'Learning how my body works',                        10),
    ('young_adult',      N'Finding my feet',   N'Studying or starting out, figuring things out',      20),
    ('independent',      N'On my own terms',   N'Working, living independently',                      30),
    ('partnership',      N'Building a life',   N'Partnered or newly married',                         40),
    ('planning',         N'Hoping for a baby', N'Trying to conceive, or getting ready to',            50),
    ('pregnancy',        N'Expecting',         N'Pregnant',                                           60),
    ('postpartum',       N'Just had a baby',   N'Recovering and adjusting, the first months',         70),
    ('motherhood',       N'Raising children',  N'Life with children beyond the first year',           80),
    ('midlife',          N'Midlife',           N'Forties, things changing',                           90),
    ('perimenopause',    N'Things changing',   N'Cycles and sleep shifting, before menopause',        100),
    ('menopause',        N'Menopause',         N'Through and beyond menopause',                       110),
    ('senior',           N'Later years',       N'Staying well and independent',                       120)
) AS source (LifeStageCode, DisplayName, [Description], SortOrder)
    ON target.LifeStageCode = source.LifeStageCode
WHEN NOT MATCHED THEN
    INSERT (LifeStageCode, DisplayName, [Description], SortOrder)
    VALUES (source.LifeStageCode, source.DisplayName, source.[Description], source.SortOrder);
GO

/*  Eight modes. Several may be true at once, which is the point: the product's
    "busy professional mother" is motherhood plus professional plus caregiver,
    not a thirteenth stage. */
MERGE [Identity].[RoleMode] AS target
USING (VALUES
    ('student',       N'Studying',        N'School, college or university',                10),
    ('professional',  N'Employed',        N'Working for an employer',                      20),
    ('freelancer',    N'Freelancing',     N'Self-employed or contracting',                 30),
    ('entrepreneur',  N'Running a business', N'Building something of my own',              40),
    ('remote_worker', N'Working remotely', N'Working from home or anywhere',               50),
    ('homemaker',     N'Running a home',  N'Managing the household full time',             60),
    ('caregiver',     N'Caring for someone', N'Looking after a child, parent or partner',  70),
    ('partner',       N'In a relationship', N'Partnered or married',                       80)
) AS source (RoleModeCode, DisplayName, [Description], SortOrder)
    ON target.RoleModeCode = source.RoleModeCode
WHEN NOT MATCHED THEN
    INSERT (RoleModeCode, DisplayName, [Description], SortOrder)
    VALUES (source.RoleModeCode, source.DisplayName, source.[Description], source.SortOrder);
GO
