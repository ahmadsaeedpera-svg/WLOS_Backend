/*  38_LifeDomain.sql

    The life domains. The vocabulary everything else agrees on.

    Why a registry rather than strings
    ----------------------------------
    Three parts of the platform already name areas of life, and none of them
    agree. Timeline.EventType.Category is an unconstrained VARCHAR carrying
    seventeen ad-hoc values. Content.Category is a separate flat list of
    thirteen. The targeting engine has a 'module' dimension whose values are
    whatever an editor types.

    That is three vocabularies for one concept, and the engines the roadmap
    describes - scores, insights, recommendations, the adaptive dashboard - all
    need to say "the sleep part of her life" and mean the same thing. Three
    vocabularies means three mappings, and mappings rot.

    So: one registry, referenced rather than repeated. This script also adds the
    foreign key from Timeline.EventType.Category, which is cheap now because
    nothing consumes that table yet and expensive once clients do.

    Domains are data, not code
    --------------------------
    A twenty-first domain is a row. The product's list already grew from "one
    health module" to twenty in a single planning cycle, which is the clearest
    possible argument against enumerating them anywhere in code.

    Hierarchy
    ---------
    ParentDomainCode lets 'hydration' sit under 'nutrition' and 'cycle' under
    'health' without flattening either. The dashboard needs the leaves; a
    wellness score needs the roots. One tree serves both, and Content.Category
    could not express this at all - which is part of why it is being superseded.

    Idempotent. Additive apart from the EventType.Category foreign key, which
    is stated in the header because it is the one constraint here that can fail
    on an existing database if somebody has inserted an unknown category.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('Content.LifeDomain') IS NULL
CREATE TABLE [Content].[LifeDomain] (
    DomainCode       VARCHAR(30)  NOT NULL,
    DisplayName      NVARCHAR(80) NOT NULL,
    [Description]    NVARCHAR(400) NULL,

    /*  Self-referencing, nullable. NULL is a root domain. */
    ParentDomainCode VARCHAR(30)  NULL,

    /*  Whether this domain covers self-reported health observations. Anything
        flagged here is handled more carefully by every engine downstream: it
        is never scored into advice and never presented as a finding. Carried
        as data so a later engine cannot forget the rule by omission. */
    IsHealthSensitive BIT NOT NULL
        CONSTRAINT DF_LifeDomain_IsHealthSensitive DEFAULT 0,

    /*  A domain can be switched off for a market or a deployment without
        deleting the history recorded against it. */
    IsActive         BIT NOT NULL CONSTRAINT DF_LifeDomain_IsActive DEFAULT 1,
    SortOrder        INT NOT NULL,

    CONSTRAINT PK_LifeDomain PRIMARY KEY CLUSTERED (DomainCode),
    CONSTRAINT FK_LifeDomain_Parent FOREIGN KEY (ParentDomainCode)
        REFERENCES [Content].[LifeDomain](DomainCode),
    /*  A domain cannot be its own parent. Does not prevent a longer cycle -
        SQL cannot express that in a CHECK - so the test walks the tree. */
    CONSTRAINT CK_LifeDomain_NotSelfParent
        CHECK (ParentDomainCode IS NULL OR ParentDomainCode <> DomainCode)
);
GO

/*  Supports the self-referencing foreign key and the "children of" read the
    dashboard does constantly. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_LifeDomain_Parent'
                 AND object_id = OBJECT_ID('[Content].[LifeDomain]'))
    CREATE INDEX [IX_LifeDomain_Parent]
        ON [Content].[LifeDomain] (ParentDomainCode);
GO

-- ---------------------------------------------------------------------------
-- Seed: roots first, then children (the foreign key requires that order)
-- ---------------------------------------------------------------------------

MERGE [Content].[LifeDomain] AS target
USING (VALUES
    ('health',        N'Health',           NULL, 1,  10),
    ('fitness',       N'Fitness',          NULL, 0,  20),
    ('nutrition',     N'Nutrition',        NULL, 0,  30),
    ('mental',        N'Mental wellbeing', NULL, 1,  40),
    ('sleep',         N'Sleep',            NULL, 0,  50),
    ('selfcare',      N'Personal care',    NULL, 0,  60),
    ('beauty',        N'Beauty',           NULL, 0,  70),
    ('medication',    N'Medicine',         NULL, 1,  80),
    ('career',        N'Career',           NULL, 0,  90),
    ('learning',      N'Learning',         NULL, 0, 100),
    ('family',        N'Family',           NULL, 0, 110),
    ('relationships', N'Relationships',    NULL, 0, 120),
    ('parenting',     N'Parenting',        NULL, 0, 130),
    ('finance',       N'Finance',          NULL, 0, 140),
    ('household',     N'Household',        NULL, 0, 150),
    ('shopping',      N'Shopping',         NULL, 0, 160),
    ('travel',        N'Travel',           NULL, 0, 170),
    ('community',     N'Community',        NULL, 0, 180),
    ('productivity',  N'Productivity',     NULL, 0, 190),
    ('spirituality',  N'Spiritual life',   NULL, 0, 200),
    ('emergency',     N'Emergency',        NULL, 1, 210),
    ('lifestyle',     N'Lifestyle',        NULL, 0, 220)
) AS source (DomainCode, DisplayName, ParentDomainCode, IsHealthSensitive, SortOrder)
    ON target.DomainCode = source.DomainCode
WHEN NOT MATCHED THEN
    INSERT (DomainCode, DisplayName, ParentDomainCode, IsHealthSensitive, SortOrder)
    VALUES (source.DomainCode, source.DisplayName, source.ParentDomainCode,
            source.IsHealthSensitive, source.SortOrder);
GO

/*  Children. Separate statement so the parents above are committed first. */
MERGE [Content].[LifeDomain] AS target
USING (VALUES
    ('hydration', N'Hydration',   'nutrition', 0,  35),
    ('cycle',     N'Cycle',       'health',    1,  15),
    ('pregnancy', N'Pregnancy',   'health',    1,  16),
    ('body',      N'Body',        'health',    1,  17),
    ('routine',   N'Routine',     'lifestyle', 0, 225),
    ('work',      N'Work',        'career',    0,  95)
) AS source (DomainCode, DisplayName, ParentDomainCode, IsHealthSensitive, SortOrder)
    ON target.DomainCode = source.DomainCode
WHEN NOT MATCHED THEN
    INSERT (DomainCode, DisplayName, ParentDomainCode, IsHealthSensitive, SortOrder)
    VALUES (source.DomainCode, source.DisplayName, source.ParentDomainCode,
            source.IsHealthSensitive, source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Make the registry authoritative for event categories
-- ---------------------------------------------------------------------------

/*  Guarded rather than assumed. If a deployment already holds an event type
    whose category is not in the registry, adding the key would fail the whole
    script; this reports the offenders instead so somebody can decide, and
    leaves the constraint for the next run.

    Every seeded category maps to a domain above - that was checked when the
    domain list was written, and the test asserts it stays true. */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_EventType_Domain')
BEGIN
    IF EXISTS (
        SELECT 1 FROM [Timeline].[EventType] et
        WHERE NOT EXISTS (SELECT 1 FROM [Content].[LifeDomain] d
                          WHERE d.DomainCode = et.Category))
    BEGIN
        PRINT 'SKIPPED FK_EventType_Domain: these event categories are not registered domains:';
        SELECT DISTINCT '  ' + et.Category AS UnregisteredCategory
        FROM [Timeline].[EventType] et
        WHERE NOT EXISTS (SELECT 1 FROM [Content].[LifeDomain] d
                          WHERE d.DomainCode = et.Category);
    END
    ELSE
    BEGIN
        ALTER TABLE [Timeline].[EventType]
            ADD CONSTRAINT FK_EventType_Domain FOREIGN KEY (Category)
            REFERENCES [Content].[LifeDomain](DomainCode);
        PRINT 'Added FK_EventType_Domain.';
    END
END
GO

/*  Supports the foreign key just added. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_EventType_Category'
                 AND object_id = OBJECT_ID('[Timeline].[EventType]'))
    CREATE INDEX [IX_EventType_Category]
        ON [Timeline].[EventType] (Category);
GO
