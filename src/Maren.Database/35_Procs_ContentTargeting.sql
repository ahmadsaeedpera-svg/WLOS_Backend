/*  35_Procs_ContentTargeting.sql

    Evaluating and managing targeting rules.

    Nothing here is wired into the serving path. usp_Content_GetForClient and
    usp_Content_GetDelta are untouched and behave exactly as before; a caller
    opts in by joining fn_TargetedItems. Switching the serving path over is a
    separate change with its own evidence, because getting it wrong means
    content silently reaching nobody, which is the kind of failure that is
    discovered weeks later by an editor asking why nothing published.

    Evaluation semantics, stated once so the tests can hold them to it:

      - AND across dimensions, OR within one.
      - A dimension with no rules places no constraint.
      - An item with no rules at all reaches everyone. Targeting is the
        exception, not the default.
      - A dimension that HAS rules requires a context value. If we do not know
        her life stage, content targeted at a life stage does not reach her.
        Conservative on purpose: showing pregnancy content to somebody whose
        stage we never learned is worse than showing her nothing.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_TargetedItems
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.fn_TargetedItems') IS NOT NULL
    DROP FUNCTION [Content].[fn_TargetedItems];
GO
/*  Every content item whose targeting rules the given context satisfies.

    @ContextJson is what we know about her, as an array of dimension/value
    pairs. A dimension may appear more than once: she can be a professional and
    a caregiver at the same time, and either should satisfy a role_mode rule.

      [{"dimension":"life_stage","value":"pregnancy"},
       {"dimension":"role_mode","value":"professional"},
       {"dimension":"role_mode","value":"caregiver"},
       {"dimension":"age","value":"34"}]

    An inline table-valued function rather than a scalar one: a scalar function
    called per row is evaluated per row, and this sits on the read path that
    serves every client. Inline means the optimiser folds it into the caller's
    plan instead. */
CREATE FUNCTION [Content].[fn_TargetedItems] (@ContextJson NVARCHAR(MAX))
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
            r.ContentItemId,
            r.DimensionCode,
            CASE r.[Operator]

                /*  Any of her values for this dimension appearing in the list. */
                WHEN 'in' THEN
                    CASE WHEN EXISTS (
                        SELECT 1
                        FROM ctx
                        CROSS APPLY OPENJSON(r.ValuesJson) vj
                        WHERE ctx.DimensionCode = r.DimensionCode
                          AND vj.[value] = ctx.Val)
                    THEN 1 ELSE 0 END

                /*  She has a value for this dimension and none of her values
                    appear in the list. The first half matters: an exclusion
                    cannot be judged against something we do not know. */
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

                /*  Numeric, inclusive. TRY_CAST rather than CAST: a rule
                    holding text where a number belongs is an editorial
                    mistake, and it should make that rule fail to match rather
                    than fail the whole query for every reader. */
                WHEN 'between' THEN
                    CASE WHEN EXISTS (
                        SELECT 1
                        FROM ctx
                        WHERE ctx.DimensionCode = r.DimensionCode
                          AND TRY_CAST(ctx.Val AS DECIMAL(18, 4)) IS NOT NULL
                          AND TRY_CAST(ctx.Val AS DECIMAL(18, 4)) >=
                              TRY_CAST(JSON_VALUE(r.ValuesJson, '$[0]') AS DECIMAL(18, 4))
                          AND TRY_CAST(ctx.Val AS DECIMAL(18, 4)) <=
                              TRY_CAST(JSON_VALUE(r.ValuesJson, '$[1]') AS DECIMAL(18, 4)))
                    THEN 1 ELSE 0 END

                ELSE 0
            END AS Matched
        FROM [Content].[ContentTargetingRule] r
    ),
    /*  OR within a dimension: one matching rule carries it. */
    dimEval AS (
        SELECT ContentItemId, DimensionCode, MAX(Matched) AS DimensionPassed
        FROM ruleEval
        GROUP BY ContentItemId, DimensionCode
    )
    /*  AND across dimensions, expressed as the absence of a failing one. This
        shape also gives items with no rules the right answer for free: they
        have nothing in dimEval, so nothing fails. */
    SELECT ci.ContentItemId
    FROM [Content].[ContentItem] ci
    WHERE NOT EXISTS (
        SELECT 1 FROM dimEval d
        WHERE d.ContentItemId = ci.ContentItemId
          AND d.DimensionPassed = 0);
GO

-- ---------------------------------------------------------------------------
-- usp_Content_SetTargetingRules
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_Content_SetTargetingRules') IS NOT NULL
    DROP PROCEDURE [Content].[usp_Content_SetTargetingRules];
GO
/*  Replaces every targeting rule on an item.

    Replace-all, like role permissions: the editor is looking at the whole set
    on one screen, so the client always knows the complete answer, and a
    partial protocol would invent a merge problem the UI does not have.

    An empty list clears targeting, which makes the item universal again. That
    has to be expressible - narrowing distribution during an incident is only
    useful if it can also be undone. */
CREATE PROCEDURE [Content].[usp_Content_SetTargetingRules]
    @ContentItemId UNIQUEIDENTIFIER,
    @RulesJson     NVARCHAR(MAX) = NULL,
    @ActorUserId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Content].[ContentItem]
                   WHERE ContentItemId = @ContentItemId AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode;
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
        ValuesJson    NVARCHAR(2000));

    IF @RulesJson IS NOT NULL
        INSERT INTO @incoming (DimensionCode, [Operator], ValuesJson)
        SELECT
            JSON_VALUE(r.[value], '$.dimension'),
            LOWER(ISNULL(JSON_VALUE(r.[value], '$.operator'), 'in')),
            JSON_QUERY(r.[value], '$.values')
        FROM OPENJSON(@RulesJson) r;

    /*  Every refusal below names exactly what is wrong. An editor who is told
        "invalid" learns nothing; one who is told the dimension is unknown can
        fix it without opening a ticket. */
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

    IF EXISTS (SELECT 1 FROM @incoming WHERE [Operator] NOT IN ('in', 'not_in', 'between'))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNKNOWN_OPERATOR' AS FailureCode;
        RETURN;
    END

    /*  between needs exactly two numbers. Caught here rather than at serving
        time, where a malformed range means the item quietly reaches nobody. */
    IF EXISTS (
        SELECT 1 FROM @incoming
        WHERE [Operator] = 'between'
          AND (TRY_CAST(JSON_VALUE(ValuesJson, '$[0]') AS DECIMAL(18, 4)) IS NULL
            OR TRY_CAST(JSON_VALUE(ValuesJson, '$[1]') AS DECIMAL(18, 4)) IS NULL))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_RANGE' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        DELETE FROM [Content].[ContentTargetingRule]
        WHERE ContentItemId = @ContentItemId;

        INSERT INTO [Content].[ContentTargetingRule]
            (ContentItemId, DimensionCode, [Operator], ValuesJson, CreatedBy)
        SELECT @ContentItemId, DimensionCode, [Operator], ValuesJson, @ActorUserId
        FROM @incoming;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId, 'user', 'Content.SetTargeting', 'ContentItem',
             CONVERT(NVARCHAR(50), @ContentItemId), @RulesJson);

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Content_GetTargetingRules
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
        r.TargetingRuleId,
        r.DimensionCode,
        d.DisplayName,
        d.ValueKind,
        r.[Operator],
        r.ValuesJson
    FROM [Content].[ContentTargetingRule] r
    JOIN [Content].[TargetingDimension] d ON d.DimensionCode = r.DimensionCode
    WHERE r.ContentItemId = @ContentItemId
    ORDER BY d.SortOrder, r.CreatedOn;
END
GO

-- ---------------------------------------------------------------------------
-- usp_TargetingDimension_List
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Content.usp_TargetingDimension_List') IS NOT NULL
    DROP PROCEDURE [Content].[usp_TargetingDimension_List];
GO
/*  What the portal offers an editor. Data-driven, so a new dimension appears
    in the editor without a portal release. */
CREATE PROCEDURE [Content].[usp_TargetingDimension_List]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DimensionCode, DisplayName, ValueKind, [Description], SortOrder
    FROM [Content].[TargetingDimension]
    ORDER BY SortOrder;
END
GO
