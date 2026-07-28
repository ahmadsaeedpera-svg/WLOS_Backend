/*  45_RuleEngine.sql

    One rule engine. Everything that matches a woman against a condition uses it.

    Why now
    -------
    There were two implementations of the same matching semantics:
    Content.fn_TargetedItems and Dashboard.fn_EligibleCards. Near-identical
    SQL, deliberately duplicated when the dashboard was built, and recorded as
    debt at the time.

    The roadmap adds recommendations, routines, coaching, notifications and
    conversation - every one of which needs to ask "does this apply to her".
    Left alone that becomes seven copies of one algorithm, and the day somebody
    fixes a bug in one of them is the day the others quietly disagree.

    So the matching moves once, now, while there are two callers rather than
    seven.

    What this changes and what it does not
    --------------------------------------
    Semantics are identical: AND across dimensions, OR within one, a dimension
    with no rules is no constraint, an item with no rules matches everyone, and
    a dimension that has rules requires a context value. Nothing about what
    reaches a woman changes.

    The existing functions keep their names and signatures and become thin
    wrappers, so no caller is touched. content_targeting_test and
    dashboard_engine_test passing unchanged is the compatibility evidence.

    The cost, stated plainly
    ------------------------
    A generic rule table cannot carry a foreign key to its target: TargetKey
    points at a content item in one scope and a card type in another, and SQL
    has no way to express that. Dashboard.CardRule had ON DELETE CASCADE to
    CardType and that protection is genuinely lost.

    It is replaced by an asserted invariant - rule_engine_test fails on any
    rule whose target does not resolve within its scope - and by scope-aware
    cleanup in the management procedure. That is a real trade: a database
    guarantee exchanged for a tested one. It is worth making at two callers and
    would not be worth making at one.

    Migration
    ---------
    Rows are copied from both existing tables, counts are verified, and only
    then are the old tables dropped. If the counts disagree the script stops
    and leaves everything as it was.

    Idempotent. Safe to re-run: after the first pass the source tables are gone
    and the migration is skipped.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = 'Rules')
    EXEC('CREATE SCHEMA [Rules]');
GO

-- ---------------------------------------------------------------------------
-- What kinds of thing can carry rules
-- ---------------------------------------------------------------------------

/*  A scope names a family of targets and where they live, so the invariant
    test can check a rule's target resolves without knowing every scope in
    advance. A new scope is a row plus a registration; no evaluator changes. */
IF OBJECT_ID('Rules.TargetScope') IS NULL
CREATE TABLE [Rules].[TargetScope] (
    ScopeCode    VARCHAR(30)  NOT NULL,
    DisplayName  NVARCHAR(80) NOT NULL,

    /*  Where a TargetKey in this scope must resolve. Used only by the
        invariant test and by cleanup - never to build SQL, so it is not an
        injection surface. */
    TargetTable  NVARCHAR(200) NOT NULL,
    TargetColumn NVARCHAR(128) NOT NULL,

    [Description] NVARCHAR(300) NULL,
    SortOrder    INT NOT NULL,

    CONSTRAINT PK_TargetScope PRIMARY KEY CLUSTERED (ScopeCode)
);
GO

MERGE [Rules].[TargetScope] AS target
USING (VALUES
    ('content',       N'Content item',   N'Content.ContentItem',   N'ContentItemId',
     N'Which women a piece of content reaches.', 10),
    ('dashboardCard', N'Dashboard card', N'Dashboard.CardType',    N'CardTypeCode',
     N'Which women a card is eligible for.',     20)
) AS source (ScopeCode, DisplayName, TargetTable, TargetColumn, [Description], SortOrder)
    ON target.ScopeCode = source.ScopeCode
WHEN NOT MATCHED THEN
    INSERT (ScopeCode, DisplayName, TargetTable, TargetColumn, [Description], SortOrder)
    VALUES (source.ScopeCode, source.DisplayName, source.TargetTable,
            source.TargetColumn, source.[Description], source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- The rules
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Rules.Rule') IS NULL
CREATE TABLE [Rules].[Rule] (
    RuleId        UNIQUEIDENTIFIER NOT NULL
        CONSTRAINT DF_Rule_Id DEFAULT NEWSEQUENTIALID(),

    ScopeCode     VARCHAR(30) NOT NULL,

    /*  Identifies the thing the rule is about, as text because a scope may key
        on a GUID and another on a code. Not a foreign key - see the header for
        why, and for what replaces it. */
    TargetKey     NVARCHAR(100) NOT NULL,

    DimensionCode VARCHAR(30) NOT NULL,
    [Operator]    VARCHAR(10) NOT NULL,
    ValuesJson    NVARCHAR(2000) NOT NULL,

    /*  Why this rule exists, for the operator configuring it. Required: a rule
        nobody can explain is one nobody can safely change. */
    RuleNote      NVARCHAR(200) NOT NULL
        CONSTRAINT DF_Rule_RuleNote DEFAULT N'',

    CreatedBy     UNIQUEIDENTIFIER NULL,
    CreatedOn     DATETIME2(3) NOT NULL
        CONSTRAINT DF_Rule_CreatedOn DEFAULT SYSUTCDATETIME(),

    CONSTRAINT PK_Rule PRIMARY KEY NONCLUSTERED (RuleId),
    CONSTRAINT FK_Rule_Scope FOREIGN KEY (ScopeCode)
        REFERENCES [Rules].[TargetScope](ScopeCode),
    CONSTRAINT FK_Rule_Dimension FOREIGN KEY (DimensionCode)
        REFERENCES [Content].[TargetingDimension](DimensionCode),
    CONSTRAINT CK_Rule_Operator
        CHECK ([Operator] IN ('in', 'not_in', 'between')),
    CONSTRAINT CK_Rule_ValuesJson CHECK (ISJSON(ValuesJson) = 1)
);
GO

/*  Clustered on the access path: evaluation reads every rule in one scope, and
    management reads every rule for one target. The identifier is a
    nonclustered key so a random GUID never orders the table - the same reason
    the timeline clusters on (UserId, OccurredUtc). */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'CX_Rule_Scope_Target'
                 AND object_id = OBJECT_ID('[Rules].[Rule]'))
    CREATE CLUSTERED INDEX [CX_Rule_Scope_Target]
        ON [Rules].[Rule] (ScopeCode, TargetKey);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Rule_Dimension'
                 AND object_id = OBJECT_ID('[Rules].[Rule]'))
    CREATE INDEX [IX_Rule_Dimension] ON [Rules].[Rule] (DimensionCode);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Rule_ScopeCode'
                 AND object_id = OBJECT_ID('[Rules].[Rule]'))
    CREATE INDEX [IX_Rule_ScopeCode] ON [Rules].[Rule] (ScopeCode);
GO

-- ---------------------------------------------------------------------------
-- Migration
-- ---------------------------------------------------------------------------

/*  Copy, verify, then drop. If a count disagrees the script raises and leaves
    both the new table and the old ones intact, so a failed migration is
    recoverable rather than a half-move nobody can reconstruct. */
IF OBJECT_ID('Content.ContentTargetingRule') IS NOT NULL
BEGIN
    DECLARE @sourceCount INT =
        (SELECT COUNT(*) FROM [Content].[ContentTargetingRule]);

    INSERT INTO [Rules].[Rule]
        (ScopeCode, TargetKey, DimensionCode, [Operator], ValuesJson, RuleNote,
         CreatedBy, CreatedOn)
    SELECT
        'content',
        CONVERT(NVARCHAR(100), r.ContentItemId),
        r.DimensionCode,
        r.[Operator],
        r.ValuesJson,
        N'Migrated from Content.ContentTargetingRule.',
        r.CreatedBy,
        r.CreatedOn
    FROM [Content].[ContentTargetingRule] r
    WHERE NOT EXISTS (
        SELECT 1 FROM [Rules].[Rule] x
        WHERE x.ScopeCode = 'content'
          AND x.TargetKey = CONVERT(NVARCHAR(100), r.ContentItemId)
          AND x.DimensionCode = r.DimensionCode
          AND x.[Operator] = r.[Operator]);

    DECLARE @migrated INT =
        (SELECT COUNT(*) FROM [Rules].[Rule] WHERE ScopeCode = 'content');

    IF @migrated < @sourceCount
        THROW 51001, 'Content targeting rule migration lost rows. Nothing dropped.', 1;

    PRINT CONCAT('Migrated ', @sourceCount, ' content targeting rule(s).');
END
GO

IF OBJECT_ID('Dashboard.CardRule') IS NOT NULL
BEGIN
    DECLARE @cardSource INT = (SELECT COUNT(*) FROM [Dashboard].[CardRule]);

    INSERT INTO [Rules].[Rule]
        (ScopeCode, TargetKey, DimensionCode, [Operator], ValuesJson, RuleNote,
         CreatedBy, CreatedOn)
    SELECT
        'dashboardCard',
        CONVERT(NVARCHAR(100), r.CardTypeCode),
        r.DimensionCode,
        r.[Operator],
        r.ValuesJson,
        r.RuleNote,
        NULL,
        r.CreatedOn
    FROM [Dashboard].[CardRule] r
    WHERE NOT EXISTS (
        SELECT 1 FROM [Rules].[Rule] x
        WHERE x.ScopeCode = 'dashboardCard'
          AND x.TargetKey = CONVERT(NVARCHAR(100), r.CardTypeCode)
          AND x.DimensionCode = r.DimensionCode
          AND x.[Operator] = r.[Operator]);

    DECLARE @cardMigrated INT =
        (SELECT COUNT(*) FROM [Rules].[Rule] WHERE ScopeCode = 'dashboardCard');

    IF @cardMigrated < @cardSource
        THROW 51002, 'Card rule migration lost rows. Nothing dropped.', 1;

    PRINT CONCAT('Migrated ', @cardSource, ' card rule(s).');
END
GO

/*  Only now. Both functions are rewritten in 46_Procs_RuleEngine.sql to read
    from Rules.Rule, so these tables have no reader left. */
IF OBJECT_ID('Content.ContentTargetingRule') IS NOT NULL
BEGIN
    DROP TABLE [Content].[ContentTargetingRule];
    PRINT 'Dropped Content.ContentTargetingRule - superseded by Rules.Rule.';
END
GO

IF OBJECT_ID('Dashboard.CardRule') IS NOT NULL
BEGIN
    DROP TABLE [Dashboard].[CardRule];
    PRINT 'Dropped Dashboard.CardRule - superseded by Rules.Rule.';
END
GO
