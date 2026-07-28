/*  42_Procs_Dashboard.sql

    Resolving a dashboard.

    One procedure answers the whole question: given who she is and what the
    timeline currently says about her, which cards should she see, in what
    order, and why.

    The "why" is not decoration. Every card comes back with the reason it is
    there, the evidence behind it and a confidence, because an adaptive surface
    nobody can explain is one nobody can debug, configure or defend - and
    because the AI companion that will eventually phrase these cards must be
    reading a decision rather than making one.

    Order of operations:

      1. eligibility  - which cards may she see at all
      2. signals      - what the timeline currently says
      3. priority     - base, then adjustments
      4. suppression  - anything at or below zero is dropped
      5. reason       - assembled from the rules that actually fired

    Deterministic throughout. No model, no inference. Given the same context
    and the same timeline this returns the same dashboard, which is what makes
    it testable and what makes an incident reproducible.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_EligibleCards
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Dashboard.fn_EligibleCards') IS NOT NULL
    DROP FUNCTION [Dashboard].[fn_EligibleCards];
GO
/*  Which cards the given context is allowed to see.

    Same semantics as content targeting, deliberately: AND across dimensions,
    OR within one, a dimension with no rules is no constraint, and a card with
    no rules at all is universal. A woman should not have to learn two mental
    models for why something did or did not appear.

    A dimension that HAS rules requires a context value. If we do not know her
    life stage, a card gated on life stage does not appear - guessing produces
    a pregnancy card for somebody who never said she was pregnant. */
CREATE FUNCTION [Dashboard].[fn_EligibleCards] (@ContextJson NVARCHAR(MAX))
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
            r.CardTypeCode,
            r.DimensionCode,
            CASE r.[Operator]
                WHEN 'in' THEN
                    CASE WHEN EXISTS (
                        SELECT 1 FROM ctx
                        CROSS APPLY OPENJSON(r.ValuesJson) vj
                        WHERE ctx.DimensionCode = r.DimensionCode
                          AND vj.[value] = ctx.Val)
                    THEN 1 ELSE 0 END
                WHEN 'not_in' THEN
                    CASE WHEN EXISTS (
                            SELECT 1 FROM ctx WHERE ctx.DimensionCode = r.DimensionCode)
                         AND NOT EXISTS (
                            SELECT 1 FROM ctx
                            CROSS APPLY OPENJSON(r.ValuesJson) vj
                            WHERE ctx.DimensionCode = r.DimensionCode
                              AND vj.[value] = ctx.Val)
                    THEN 1 ELSE 0 END
                WHEN 'between' THEN
                    CASE WHEN EXISTS (
                        SELECT 1 FROM ctx
                        WHERE ctx.DimensionCode = r.DimensionCode
                          AND TRY_CAST(ctx.Val AS DECIMAL(18,4)) IS NOT NULL
                          AND TRY_CAST(ctx.Val AS DECIMAL(18,4)) >=
                              TRY_CAST(JSON_VALUE(r.ValuesJson, '$[0]') AS DECIMAL(18,4))
                          AND TRY_CAST(ctx.Val AS DECIMAL(18,4)) <=
                              TRY_CAST(JSON_VALUE(r.ValuesJson, '$[1]') AS DECIMAL(18,4)))
                    THEN 1 ELSE 0 END
                ELSE 0
            END AS Matched
        FROM [Dashboard].[CardRule] r
    ),
    dimEval AS (
        SELECT CardTypeCode, DimensionCode, MAX(Matched) AS DimensionPassed
        FROM ruleEval
        GROUP BY CardTypeCode, DimensionCode
    )
    SELECT ct.CardTypeCode
    FROM [Dashboard].[CardType] ct
    WHERE ct.IsActive = 1
      AND NOT EXISTS (
          SELECT 1 FROM dimEval d
          WHERE d.CardTypeCode = ct.CardTypeCode
            AND d.DimensionPassed = 0);
GO

-- ---------------------------------------------------------------------------
-- usp_Dashboard_Resolve
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Dashboard.usp_Dashboard_Resolve') IS NOT NULL
    DROP PROCEDURE [Dashboard].[usp_Dashboard_Resolve];
GO
/*  Her dashboard, ordered, with the reasoning attached.

    @ContextJson is what we know about her right now - life stage, roles,
    country, age and anything else the targeting vocabulary covers - in the
    same shape the content engine takes.

    Returns one row per card. Reason is assembled from the adjustments that
    actually fired, so a card that is simply eligible says so plainly rather
    than inventing a justification it does not have. */
CREATE PROCEDURE [Dashboard].[usp_Dashboard_Resolve]
    @UserId      UNIQUEIDENTIFIER,
    @ContextJson NVARCHAR(MAX) = NULL,
    @AsOfDate    DATE = NULL,
    @Take        INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);
    IF @Take IS NULL OR @Take < 1 SET @Take = 20;
    IF @Take > 50 SET @Take = 50;

    /*  What the timeline currently says. Reuses the knowledge engine rather
        than re-deriving anything: a dashboard and an insight must never
        disagree about whether she has been sleeping badly. */
    /*  Joined, not executed. fn_EvaluateSignals holds the one definition of
        what a raised signal means, and duplicating it here would be a second
        copy that disagrees with the first the moment either changes.

        It has to be a function rather than a procedure because T-SQL forbids
        nesting INSERT ... EXEC. This procedure is itself collected by its
        caller, so an inner INSERT ... EXEC fails at runtime while returning an
        empty set - every card silently falls back to its baseline and the
        dashboard looks plausible while being wrong. The suppression and
        reordering assertions caught exactly that. */
    ;WITH signals AS (
        SELECT SignalCode, BreachDays
        FROM [Knowledge].[fn_EvaluateSignals](@UserId, @AsOfDate)
    ),
    eligible AS (
        SELECT e.CardTypeCode
        FROM [Dashboard].[fn_EligibleCards](@ContextJson) e
    ),
    /*  Every adjustment that fired, kept as rows so the reason can name them. */
    fired AS (
        SELECT
            pa.CardTypeCode,
            pa.AdjustmentKind,
            pa.Amount,
            pa.ReasonText,
            pa.Confidence,
            pa.SignalCode,
            sg.BreachDays
        FROM [Dashboard].[PriorityAdjustment] pa
        JOIN signals sg ON sg.SignalCode = pa.SignalCode
        JOIN eligible el ON el.CardTypeCode = pa.CardTypeCode
        WHERE pa.IsActive = 1
    ),
    scored AS (
        SELECT
            ct.CardTypeCode,
            ct.DisplayName,
            ct.DomainCode,
            ct.BasePriority,
            ct.RefreshSeconds,
            ct.LifetimeSeconds,
            ct.IsDismissible,
            ct.IsHealthSensitive,

            /*  A 'set' wins outright and the strongest one wins among several -
                nothing should outrank an overdue medication by accumulating
                small additions. Otherwise the additions are summed onto the
                base. */
            CASE
                WHEN (SELECT MAX(f.Amount) FROM fired f
                      WHERE f.CardTypeCode = ct.CardTypeCode
                        AND f.AdjustmentKind = 'set') IS NOT NULL
                THEN (SELECT MAX(f.Amount) FROM fired f
                      WHERE f.CardTypeCode = ct.CardTypeCode
                        AND f.AdjustmentKind = 'set')
                ELSE ct.BasePriority + ISNULL(
                    (SELECT SUM(f.Amount) FROM fired f
                     WHERE f.CardTypeCode = ct.CardTypeCode
                       AND f.AdjustmentKind = 'add'), 0)
            END AS Priority,

            /*  Lowest confidence of anything that moved it. A card is only as
                trustworthy as the weakest reason behind it. */
            ISNULL((SELECT MIN(f.Confidence) FROM fired f
                    WHERE f.CardTypeCode = ct.CardTypeCode), 1.00) AS Confidence,

            (SELECT COUNT(*) FROM fired f
             WHERE f.CardTypeCode = ct.CardTypeCode) AS AdjustmentCount
        FROM [Dashboard].[CardType] ct
        JOIN eligible el ON el.CardTypeCode = ct.CardTypeCode
    )
    SELECT TOP (@Take)
        s.CardTypeCode,
        s.DisplayName,
        s.DomainCode,
        s.Priority,
        s.BasePriority,
        s.Confidence,
        s.RefreshSeconds,
        s.LifetimeSeconds,
        s.IsDismissible,
        s.IsHealthSensitive,

        /*  Why she is seeing this. The reasons that actually fired, joined;
            otherwise an honest statement that it is simply part of her day.
            Never a fabricated justification - a card claiming a reason it does
            not have is worse than one admitting it is routine. */
        ISNULL(
            STUFF((SELECT N' ' + f.ReasonText
                   FROM fired f
                   WHERE f.CardTypeCode = s.CardTypeCode
                   ORDER BY f.Amount DESC
                   FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'Part of your usual day.') AS Reason,

        /*  The signals behind it, as codes, for a client or an AI layer that
            wants the evidence rather than the sentence. */
        ISNULL(
            STUFF((SELECT N',' + f.SignalCode
                   FROM fired f
                   WHERE f.CardTypeCode = s.CardTypeCode
                   ORDER BY f.SignalCode
                   FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS EvidenceSignals,

        CASE WHEN s.AdjustmentCount > 0 THEN 'signal' ELSE 'baseline' END AS [Source]
    FROM scored s
    /*  Suppression. Anything driven to zero or below is not shown, which is how
        "a long working day hides the reading nudge" works without a second
        mechanism. */
    WHERE s.Priority > 0
    ORDER BY s.Priority DESC, s.DisplayName;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Dashboard_ListCardTypes
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Dashboard.usp_Dashboard_ListCardTypes') IS NOT NULL
    DROP PROCEDURE [Dashboard].[usp_Dashboard_ListCardTypes];
GO
/*  The registry, for the portal. An operator sees every card, its base
    priority and how many rules and adjustments govern it, so the dashboard is
    configurable by somebody who does not read SQL. */
CREATE PROCEDURE [Dashboard].[usp_Dashboard_ListCardTypes]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ct.CardTypeCode,
        ct.DisplayName,
        ct.DomainCode,
        ct.BasePriority,
        ct.RefreshSeconds,
        ct.LifetimeSeconds,
        ct.IsDismissible,
        ct.IsHealthSensitive,
        ct.IsActive,
        (SELECT COUNT(*) FROM [Dashboard].[CardRule] r
         WHERE r.CardTypeCode = ct.CardTypeCode) AS RuleCount,
        (SELECT COUNT(*) FROM [Dashboard].[PriorityAdjustment] pa
         WHERE pa.CardTypeCode = ct.CardTypeCode AND pa.IsActive = 1) AS AdjustmentCount
    FROM [Dashboard].[CardType] ct
    ORDER BY ct.BasePriority DESC, ct.DisplayName;
END
GO
