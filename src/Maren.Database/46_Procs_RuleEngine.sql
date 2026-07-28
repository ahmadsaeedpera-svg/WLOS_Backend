/*  46_Procs_RuleEngine.sql

    The one matcher, and the wrappers that keep every existing caller working.

    Rules.fn_Match holds the algorithm. Content.fn_TargetedItems and
    Dashboard.fn_EligibleCards keep their names and signatures and delegate to
    it, so nothing that called them changes. The existing targeting and
    dashboard assertion suites passing unchanged is the proof.

    Semantics, stated once here and nowhere else:

      - AND across dimensions, OR within one
      - a dimension with no rules is not a constraint
      - a target with no rules at all matches everyone
      - a dimension that HAS rules requires a context value

    That last one is the conservative case and the reason it is worth having a
    single implementation: content targeted at a life stage must not reach a
    woman whose stage was never learned, and getting that right in one place is
    considerably easier than getting it right in seven.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Rules.fn_Match
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Rules.fn_Match') IS NOT NULL
    DROP FUNCTION [Rules].[fn_Match];
GO
/*  Every target in a scope whose rules the given context satisfies.

    @ContextJson is what we know about her, as dimension/value pairs. A
    dimension may repeat: she can be a professional and a caregiver at once,
    and either should satisfy a role_mode rule.

    Returns only targets that HAVE rules and pass them. Targets with no rules
    are universal and are added by the callers, which know their own universe -
    this function cannot enumerate content items and card types without
    knowing about both, which is exactly the coupling it exists to avoid.

    Inline, so the optimiser folds it into the caller's plan rather than
    evaluating it per row. */
CREATE FUNCTION [Rules].[fn_Match]
    (@ScopeCode VARCHAR(30), @ContextJson NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN
    WITH ctx AS (
        SELECT
            JSON_VALUE(c.[value], '$.dimension') AS DimensionCode,
            JSON_VALUE(c.[value], '$.value')     AS Val
        FROM OPENJSON(ISNULL(@ContextJson, N'[]')) c
    ),
    ruleEval AS (
        SELECT
            r.TargetKey,
            r.DimensionCode,
            CASE r.[Operator]

                WHEN 'in' THEN
                    CASE WHEN EXISTS (
                        SELECT 1
                        FROM ctx
                        CROSS APPLY OPENJSON(r.ValuesJson) vj
                        WHERE ctx.DimensionCode = r.DimensionCode
                          AND vj.[value] = ctx.Val)
                    THEN 1 ELSE 0 END

                /*  She must have a value for this dimension before an
                    exclusion can be judged. An exclusion cannot be applied to
                    something we do not know. */
                WHEN 'not_in' THEN
                    CASE WHEN EXISTS (
                            SELECT 1 FROM ctx WHERE ctx.DimensionCode = r.DimensionCode)
                         AND NOT EXISTS (
                            SELECT 1
                            FROM ctx
                            CROSS APPLY OPENJSON(r.ValuesJson) vj
                            WHERE ctx.DimensionCode = r.DimensionCode
                              AND vj.[value] = ctx.Val)
                    THEN 1 ELSE 0 END

                /*  TRY_CAST, so a rule holding text where a number belongs
                    fails that rule rather than the whole query for every
                    reader. */
                WHEN 'between' THEN
                    CASE WHEN EXISTS (
                        SELECT 1
                        FROM ctx
                        WHERE ctx.DimensionCode = r.DimensionCode
                          AND TRY_CAST(ctx.Val AS DECIMAL(18,4)) IS NOT NULL
                          AND TRY_CAST(ctx.Val AS DECIMAL(18,4)) >=
                              TRY_CAST(JSON_VALUE(r.ValuesJson, '$[0]') AS DECIMAL(18,4))
                          AND TRY_CAST(ctx.Val AS DECIMAL(18,4)) <=
                              TRY_CAST(JSON_VALUE(r.ValuesJson, '$[1]') AS DECIMAL(18,4)))
                    THEN 1 ELSE 0 END

                ELSE 0
            END AS Matched
        FROM [Rules].[Rule] r
        WHERE r.ScopeCode = @ScopeCode
    ),
    /*  OR within a dimension: one matching rule carries it. */
    dimEval AS (
        SELECT TargetKey, DimensionCode, MAX(Matched) AS DimensionPassed
        FROM ruleEval
        GROUP BY TargetKey, DimensionCode
    )
    /*  AND across dimensions, expressed as the absence of a failing one. */
    SELECT DISTINCT d.TargetKey
    FROM dimEval d
    WHERE NOT EXISTS (
        SELECT 1 FROM dimEval f
        WHERE f.TargetKey = d.TargetKey
          AND f.DimensionPassed = 0);
GO

-- ---------------------------------------------------------------------------
-- Content.fn_TargetedItems — unchanged signature, one line of logic
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.fn_TargetedItems') IS NOT NULL
    DROP FUNCTION [Content].[fn_TargetedItems];
GO
/*  Every content item the given context may see.

    Items with no rules are universal, so the set is "everything, minus the
    ones that have rules and fail them". Expressed that way rather than as a
    union so an item cannot appear twice. */
CREATE FUNCTION [Content].[fn_TargetedItems] (@ContextJson NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN
    SELECT ci.ContentItemId
    FROM [Content].[ContentItem] ci
    WHERE NOT EXISTS (
              SELECT 1 FROM [Rules].[Rule] r
              WHERE r.ScopeCode = 'content'
                AND r.TargetKey = CONVERT(NVARCHAR(100), ci.ContentItemId))
       OR EXISTS (
              SELECT 1 FROM [Rules].[fn_Match]('content', @ContextJson) m
              WHERE m.TargetKey = CONVERT(NVARCHAR(100), ci.ContentItemId));
GO

-- ---------------------------------------------------------------------------
-- Dashboard.fn_EligibleCards — unchanged signature
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Dashboard.fn_EligibleCards') IS NOT NULL
    DROP FUNCTION [Dashboard].[fn_EligibleCards];
GO
CREATE FUNCTION [Dashboard].[fn_EligibleCards] (@ContextJson NVARCHAR(MAX))
RETURNS TABLE
AS
RETURN
    SELECT ct.CardTypeCode
    FROM [Dashboard].[CardType] ct
    WHERE ct.IsActive = 1
      AND (NOT EXISTS (
               SELECT 1 FROM [Rules].[Rule] r
               WHERE r.ScopeCode = 'dashboardCard'
                 AND r.TargetKey = CONVERT(NVARCHAR(100), ct.CardTypeCode))
           OR EXISTS (
               SELECT 1 FROM [Rules].[fn_Match]('dashboardCard', @ContextJson) m
               WHERE m.TargetKey = CONVERT(NVARCHAR(100), ct.CardTypeCode)));
GO

-- ---------------------------------------------------------------------------
-- Management
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Rules.usp_Rules_SetForTarget') IS NOT NULL
    DROP PROCEDURE [Rules].[usp_Rules_SetForTarget];
GO
/*  Replaces every rule on one target.

    Replace-all rather than add and remove: an editor sees the whole set on one
    screen, so the client always knows the complete answer. An empty list
    clears the rules and makes the target universal again - narrowing
    distribution during an incident is only useful if it can be undone.

    Refuses the whole call on an unknown dimension or operator rather than
    dropping the offending rule quietly, which would leave an editor looking at
    a rule they saved and the platform ignoring it. */
CREATE PROCEDURE [Rules].[usp_Rules_SetForTarget]
    @ScopeCode   VARCHAR(30),
    @TargetKey   NVARCHAR(100),
    @RulesJson   NVARCHAR(MAX) = NULL,
    @ActorUserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Rules].[TargetScope] WHERE ScopeCode = @ScopeCode)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNKNOWN_SCOPE' AS FailureCode;
        RETURN;
    END

    IF @RulesJson IS NOT NULL AND ISJSON(@RulesJson) = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_JSON' AS FailureCode;
        RETURN;
    END

    DECLARE @incoming TABLE (
        DimensionCode VARCHAR(30),
        [Operator]    VARCHAR(10),
        ValuesJson    NVARCHAR(2000),
        RuleNote      NVARCHAR(200));

    IF @RulesJson IS NOT NULL
        INSERT INTO @incoming (DimensionCode, [Operator], ValuesJson, RuleNote)
        SELECT
            JSON_VALUE(r.[value], '$.dimension'),
            LOWER(ISNULL(JSON_VALUE(r.[value], '$.operator'), 'in')),
            JSON_QUERY(r.[value], '$.values'),
            ISNULL(JSON_VALUE(r.[value], '$.note'), N'')
        FROM OPENJSON(@RulesJson) r;

    IF EXISTS (SELECT 1 FROM @incoming WHERE DimensionCode IS NULL OR ValuesJson IS NULL)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'RULE_INCOMPLETE' AS FailureCode;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @incoming i
               WHERE NOT EXISTS (SELECT 1 FROM [Content].[TargetingDimension] d
                                 WHERE d.DimensionCode = i.DimensionCode))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNKNOWN_DIMENSION' AS FailureCode;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @incoming WHERE [Operator] NOT IN ('in','not_in','between'))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNKNOWN_OPERATOR' AS FailureCode;
        RETURN;
    END

    /*  A malformed range would otherwise mean a target that reaches nobody and
        reports nothing - discovered weeks later by an editor asking why. */
    IF EXISTS (
        SELECT 1 FROM @incoming
        WHERE [Operator] = 'between'
          AND (TRY_CAST(JSON_VALUE(ValuesJson, '$[0]') AS DECIMAL(18,4)) IS NULL
            OR TRY_CAST(JSON_VALUE(ValuesJson, '$[1]') AS DECIMAL(18,4)) IS NULL))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_RANGE' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        DELETE FROM [Rules].[Rule]
        WHERE ScopeCode = @ScopeCode AND TargetKey = @TargetKey;

        INSERT INTO [Rules].[Rule]
            (ScopeCode, TargetKey, DimensionCode, [Operator], ValuesJson,
             RuleNote, CreatedBy)
        SELECT @ScopeCode, @TargetKey, DimensionCode, [Operator], ValuesJson,
               RuleNote, @ActorUserId
        FROM @incoming;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'user', 'Rules.SetForTarget', @ScopeCode,
             @TargetKey, @RulesJson);

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_SetTargetingRules — kept, now writing to the one store
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_SetTargetingRules') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_SetTargetingRules];
GO
/*  Unchanged signature and unchanged failure codes; the storage moved beneath
    it. Callers and their tests are untouched. */
CREATE PROCEDURE [Content].[usp_Content_SetTargetingRules]
    @ContentItemId UNIQUEIDENTIFIER,
    @RulesJson     NVARCHAR(MAX) = NULL,
    @ActorUserId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM [Content].[ContentItem]
                   WHERE ContentItemId = @ContentItemId AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode;
        RETURN;
    END

    EXEC [Rules].[usp_Rules_SetForTarget]
        @ScopeCode = 'content',
        @TargetKey = @ContentItemId,
        @RulesJson = @RulesJson,
        @ActorUserId = @ActorUserId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_GetTargetingRules — kept, reading the one store
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_GetTargetingRules') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_GetTargetingRules];
GO
CREATE PROCEDURE [Content].[usp_Content_GetTargetingRules]
    @ContentItemId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.RuleId AS TargetingRuleId,
        r.DimensionCode,
        d.DisplayName,
        d.ValueKind,
        r.[Operator],
        r.ValuesJson
    FROM [Rules].[Rule] r
    JOIN [Content].[TargetingDimension] d ON d.DimensionCode = r.DimensionCode
    WHERE r.ScopeCode = 'content'
      AND r.TargetKey = CONVERT(NVARCHAR(100), @ContentItemId)
    ORDER BY d.SortOrder, r.CreatedOn;
END
GO

-- ---------------------------------------------------------------------------
-- Cleanup: what replaces the lost cascade
-- ---------------------------------------------------------------------------

/*  Dashboard.CardRule had ON DELETE CASCADE to CardType, and
    ContentTargetingRule had one to ContentItem. A generic rule table cannot
    carry either, because TargetKey points at a different table per scope.

    These triggers restore that behaviour explicitly. They were not written
    speculatively: the invariant test failed on a fresh database the first time
    this ran, with five rules left behind by content items a test had deleted -
    exactly the cost recorded in 45_RuleEngine.sql, arriving immediately.

    A trigger is implicit behaviour and worth being uncomfortable about. It is
    justified here because it replaces something already implicit, and because
    the alternative - remembering to clean rules at every site that deletes a
    target - is the kind of discipline that holds until the first new delete
    path. */

IF OBJECT_ID('Content.trg_ContentItem_CleanRules') IS NOT NULL
    DROP TRIGGER [Content].[trg_ContentItem_CleanRules];
GO
CREATE TRIGGER [Content].[trg_ContentItem_CleanRules]
ON [Content].[ContentItem]
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DELETE r
    FROM [Rules].[Rule] r
    JOIN deleted d ON CONVERT(NVARCHAR(100), d.ContentItemId) = r.TargetKey
    WHERE r.ScopeCode = 'content';
END
GO

IF OBJECT_ID('Dashboard.trg_CardType_CleanRules') IS NOT NULL
    DROP TRIGGER [Dashboard].[trg_CardType_CleanRules];
GO
CREATE TRIGGER [Dashboard].[trg_CardType_CleanRules]
ON [Dashboard].[CardType]
AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    DELETE r
    FROM [Rules].[Rule] r
    JOIN deleted d ON CONVERT(NVARCHAR(100), d.CardTypeCode) = r.TargetKey
    WHERE r.ScopeCode = 'dashboardCard';
END
GO

-- ---------------------------------------------------------------------------
-- usp_Rules_PruneOrphans
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Rules.usp_Rules_PruneOrphans') IS NOT NULL
    DROP PROCEDURE [Rules].[usp_Rules_PruneOrphans];
GO
/*  Removes rules whose target no longer exists.

    The triggers above prevent orphans from being created going forward; this
    clears any that predate them, and gives an operator a way to repair the
    table if a scope is ever removed. Returns what it removed rather than
    working silently - a cleanup that reports nothing is one nobody trusts. */
CREATE PROCEDURE [Rules].[usp_Rules_PruneOrphans]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @removed TABLE (ScopeCode VARCHAR(30), TargetKey NVARCHAR(100));

    DELETE r
    OUTPUT deleted.ScopeCode, deleted.TargetKey INTO @removed
    FROM [Rules].[Rule] r
    WHERE (r.ScopeCode = 'content'
           AND NOT EXISTS (SELECT 1 FROM [Content].[ContentItem] ci
                           WHERE CONVERT(NVARCHAR(100), ci.ContentItemId) = r.TargetKey))
       OR (r.ScopeCode = 'dashboardCard'
           AND NOT EXISTS (SELECT 1 FROM [Dashboard].[CardType] ct
                           WHERE CONVERT(NVARCHAR(100), ct.CardTypeCode) = r.TargetKey));

    SELECT ScopeCode, TargetKey FROM @removed;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Rules_ListForScope — for the portal's rule builder
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Rules.usp_Rules_ListForScope') IS NOT NULL
    DROP PROCEDURE [Rules].[usp_Rules_ListForScope];
GO
CREATE PROCEDURE [Rules].[usp_Rules_ListForScope]
    @ScopeCode VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        r.RuleId,
        r.TargetKey,
        r.DimensionCode,
        d.DisplayName,
        d.ValueKind,
        r.[Operator],
        r.ValuesJson,
        r.RuleNote,
        r.CreatedOn
    FROM [Rules].[Rule] r
    JOIN [Content].[TargetingDimension] d ON d.DimensionCode = r.DimensionCode
    WHERE r.ScopeCode = @ScopeCode
    ORDER BY r.TargetKey, d.SortOrder;
END
GO
