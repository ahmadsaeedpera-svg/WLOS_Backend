/*  34_ContentTargeting.sql

    Content targeting as data rather than as columns.

    The problem this solves
    -----------------------
    Targeting today is a fixed set of columns on Content.ContentItem -
    CountryFilter, MinAppVersion, FromWeek, ToWeek, Season - and each of them
    is referenced in six places: the table, usp_Content_Save's parameters and
    both its INSERT and UPDATE, the version snapshot payload,
    usp_Content_GetForClient, usp_Content_GetDelta, and the DTOs in
    Maren.Contracts, which are a published contract with two shipped clients.

    Adding one dimension means editing all six and breaking a mobile app that
    cannot be updated quickly. The platform now needs to target life stage,
    role mode, age, language, country, season, goal, health condition and
    module - nine and growing. That is fifty-four edit sites and nine breaking
    changes, which is not a design, it is a warning.

    Translations were moved from columns to rows early in this schema's life
    for exactly the same reason, and the comment there makes the argument:
    adding a language should be data. Adding a targeting dimension should be
    data too.

    Semantics
    ---------
    AND across dimensions, OR within one. An item carrying life_stage rules
    for pregnancy and postpartum, plus a country rule for GB, reaches a
    pregnant woman in Great Britain and nobody else.

    A dimension with no rules is not a constraint. Content with no rules at all
    reaches everyone, which is what almost all content should do - targeting is
    the exception, not the default.

    Compatibility
    -------------
    Purely additive. Not one existing column, procedure or DTO is touched, and
    nothing here is wired into the serving path yet. The legacy columns keep
    working exactly as they do today; callers opt in by joining the evaluation
    function in 35_Procs_ContentTargeting.sql. Migrating the old columns onto
    rules is tracked as debt, not done here - a serving-path change belongs in
    its own commit with its own evidence.

    Idempotent.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Reference: the dimensions we can target on
-- ---------------------------------------------------------------------------

/*  A table, so a tenth dimension is a seed row. ValueKind tells the evaluator
    how to compare - the difference between "is her stage in this list" and "is
    her age between these numbers" is the only real variation, and encoding it
    as data keeps the evaluator from growing a branch per dimension. */
IF OBJECT_ID('Content.TargetingDimension') IS NULL
CREATE TABLE [Content].[TargetingDimension] (
    DimensionCode VARCHAR(30)  NOT NULL,
    DisplayName   NVARCHAR(80) NOT NULL,
    /*  'string' - compared as a set membership test
        'number' - compared numerically, supports ranges */
    ValueKind     VARCHAR(10)  NOT NULL,
    Description   NVARCHAR(300) NULL,
    SortOrder     INT NOT NULL,
    CONSTRAINT PK_TargetingDimension PRIMARY KEY CLUSTERED (DimensionCode),
    CONSTRAINT CK_TargetingDimension_ValueKind
        CHECK (ValueKind IN ('string', 'number'))
);
GO

-- ---------------------------------------------------------------------------
-- The rules themselves
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Content.ContentTargetingRule') IS NULL
CREATE TABLE [Content].[ContentTargetingRule] (
    TargetingRuleId UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT DF_ContentTargetingRule_Id DEFAULT NEWSEQUENTIALID(),
    ContentItemId   UNIQUEIDENTIFIER NOT NULL,
    DimensionCode   VARCHAR(30) NOT NULL,

    /*  'in'      - matches when her value appears in ValuesJson
        'not_in'  - matches when it does not
        'between' - numeric, inclusive, ValuesJson is [min, max]

        Deliberately small. Every additional operator is a branch in the
        evaluator and a case in its tests, and these three express every
        targeting rule the product has asked for. */
    [Operator]      VARCHAR(10) NOT NULL,

    /*  A JSON array, always - even for a single value. One shape means the
        evaluator has one path, and "country is GB" and "country is GB or IE"
        stop being different kinds of rule. */
    ValuesJson      NVARCHAR(2000) NOT NULL,

    CreatedBy       UNIQUEIDENTIFIER NULL,
    CreatedOn       DATETIME2(3) NOT NULL
        CONSTRAINT DF_ContentTargetingRule_CreatedOn DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_ContentTargetingRule PRIMARY KEY CLUSTERED (TargetingRuleId),
    CONSTRAINT FK_ContentTargetingRule_Item FOREIGN KEY (ContentItemId)
        REFERENCES [Content].[ContentItem](ContentItemId) ON DELETE CASCADE,
    CONSTRAINT FK_ContentTargetingRule_Dimension FOREIGN KEY (DimensionCode)
        REFERENCES [Content].[TargetingDimension](DimensionCode),
    CONSTRAINT CK_ContentTargetingRule_Operator
        CHECK ([Operator] IN ('in', 'not_in', 'between')),
    /*  A rule whose values are not valid JSON cannot be evaluated, and finding
        that out at serving time means content silently reaching nobody. */
    CONSTRAINT CK_ContentTargetingRule_ValuesJson
        CHECK (ISJSON(ValuesJson) = 1)
);
GO

/*  The evaluation path reads every rule for a candidate item, so this is the
    index that matters. Unfiltered because the FK cascades - see
    30_Indexes_ForeignKeys.sql for why a filtered index cannot serve that. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentTargetingRule_Item'
                 AND object_id = OBJECT_ID('[Content].[ContentTargetingRule]'))
    CREATE INDEX [IX_ContentTargetingRule_Item]
        ON [Content].[ContentTargetingRule] (ContentItemId)
        INCLUDE (DimensionCode, [Operator], ValuesJson);
GO

/*  "What targets perimenopause" is a real editorial question, and without this
    it is a scan of every rule in the system. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_ContentTargetingRule_Dimension'
                 AND object_id = OBJECT_ID('[Content].[ContentTargetingRule]'))
    CREATE INDEX [IX_ContentTargetingRule_Dimension]
        ON [Content].[ContentTargetingRule] (DimensionCode);
GO

-- ---------------------------------------------------------------------------
-- Seed the dimensions
-- ---------------------------------------------------------------------------

MERGE [Content].[TargetingDimension] AS target
USING (VALUES
    ('life_stage', N'Life stage',       'string', N'adolescence ... senior. Matches Identity.LifeStage', 10),
    ('role_mode',  N'Role',             'string', N'student, professional, caregiver and the rest',      20),
    ('age',        N'Age',              'number', N'Years. Use between for a range',                     30),
    ('country',    N'Country',          'string', N'ISO country code',                                   40),
    ('language',   N'Language',         'string', N'Language tag such as en-GB',                         50),
    ('season',     N'Season',           'string', N'spring, summer, autumn, winter',                     60),
    ('goal',       N'Goal',             'string', N'What she told us she is working towards',            70),
    ('condition',  N'Health condition', 'string', N'Self-reported, e.g. pcos. Never a diagnosis',         80),
    ('module',     N'Module',           'string', N'sleep, nutrition, habits and the rest',              90),
    ('week',       N'Pregnancy week',   'number', N'Gestational week, for pregnancy content',           100)
) AS source (DimensionCode, DisplayName, ValueKind, [Description], SortOrder)
    ON target.DimensionCode = source.DimensionCode
WHEN NOT MATCHED THEN
    INSERT (DimensionCode, DisplayName, ValueKind, [Description], SortOrder)
    VALUES (source.DimensionCode, source.DisplayName, source.ValueKind,
            source.[Description], source.SortOrder);
GO
