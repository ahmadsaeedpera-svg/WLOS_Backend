/*  47_Procs_Inspector.sql

    The decision inspector's data: simulate the engines against a hypothetical
    woman.

    Why this simulates rather than loads a real account
    ---------------------------------------------------
    An inspector that resolved a named user's pipeline would show an operator
    her life stage, her raised signals and the timeline evidence behind them.
    That is impersonation with a different label, and CLAUDE.md section 8
    forbids it until there is a consent model, a time limit, a visible banner
    and legal review - specifically because it means an operator reading a
    woman's symptom history.

    It is also not what an operator needs. The question they actually have is
    "does my configuration do what I intended", and that is answered better by
    a hypothetical than by a real person: they can try a pregnant student in
    Pakistan with high stress without any such woman existing, and without
    anybody's data being opened.

    So nothing here takes a user id, and nothing here touches Timeline.Event or
    Intelligence.UserStateSnapshot. Signals are supplied by the operator as a
    what-if rather than derived from anyone.

    The engines themselves are reused unchanged. If this file computed
    eligibility or priority its own way, the inspector would show an operator
    something the platform does not actually do - which is worse than having no
    inspector at all.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- usp_Inspector_SimulateDashboard
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Dashboard.usp_Inspector_SimulateDashboard') IS NOT NULL
    DROP PROCEDURE [Dashboard].[usp_Inspector_SimulateDashboard];
GO
/*  What the dashboard engine would produce for this context and these signals.

    Mirrors usp_Dashboard_Resolve exactly, with one difference: the signals are
    given rather than evaluated from a timeline. Every other decision -
    eligibility through the shared rule engine, base priority, adjustments,
    suppression below zero, the assembled reason - is the same code path.

    @SignalsCsv is a comma-separated list of signal codes the operator wants to
    pretend are raised. Empty means an ordinary day. */
CREATE PROCEDURE [Dashboard].[usp_Inspector_SimulateDashboard]
    @ContextJson NVARCHAR(MAX) = NULL,
    @SignalsCsv  NVARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @signals TABLE (SignalCode VARCHAR(40) PRIMARY KEY);

    IF @SignalsCsv IS NOT NULL AND LEN(LTRIM(@SignalsCsv)) > 0
        INSERT INTO @signals (SignalCode)
        SELECT DISTINCT LTRIM(RTRIM([value]))
        FROM STRING_SPLIT(@SignalsCsv, ',')
        WHERE LTRIM(RTRIM([value])) <> ''
          /*  Unknown codes are dropped rather than refused. An operator typing
              into a what-if box should see the effect of what the platform
              recognises, not an error about a name it does not. */
          AND EXISTS (SELECT 1 FROM [Knowledge].[Signal] s
                      WHERE s.SignalCode = LTRIM(RTRIM([value])));

    ;WITH eligible AS (
        SELECT e.CardTypeCode
        FROM [Dashboard].[fn_EligibleCards](@ContextJson) e
    ),
    fired AS (
        SELECT
            pa.CardTypeCode,
            pa.AdjustmentKind,
            pa.Amount,
            pa.ReasonText,
            pa.Confidence,
            pa.SignalCode
        FROM [Dashboard].[PriorityAdjustment] pa
        JOIN @signals sg ON sg.SignalCode = pa.SignalCode
        JOIN eligible el ON el.CardTypeCode = pa.CardTypeCode
        WHERE pa.IsActive = 1
    ),
    scored AS (
        SELECT
            ct.CardTypeCode,
            ct.DisplayName,
            ct.DomainCode,
            ct.BasePriority,
            ct.IsHealthSensitive,
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
            ISNULL((SELECT MIN(f.Confidence) FROM fired f
                    WHERE f.CardTypeCode = ct.CardTypeCode), 1.00) AS Confidence,
            (SELECT COUNT(*) FROM fired f
             WHERE f.CardTypeCode = ct.CardTypeCode) AS AdjustmentCount
        FROM [Dashboard].[CardType] ct
        JOIN eligible el ON el.CardTypeCode = ct.CardTypeCode
    )
    SELECT
        s.CardTypeCode,
        s.DisplayName,
        s.DomainCode,
        s.Priority,
        s.BasePriority,
        s.Confidence,
        s.IsHealthSensitive,

        /*  Suppressed cards are returned too, flagged, which is the whole
            point of an inspector. On the real path they simply vanish; an
            operator asking "why is my card missing" needs to see that it was
            eligible and then driven below zero, not an empty list. */
        CAST(CASE WHEN s.Priority > 0 THEN 0 ELSE 1 END AS BIT) AS IsSuppressed,

        ISNULL(
            STUFF((SELECT N' ' + f.ReasonText
                   FROM fired f
                   WHERE f.CardTypeCode = s.CardTypeCode
                   ORDER BY f.Amount DESC
                   FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'Part of your usual day.') AS Reason,

        ISNULL(
            STUFF((SELECT N',' + f.SignalCode
                   FROM fired f
                   WHERE f.CardTypeCode = s.CardTypeCode
                   ORDER BY f.SignalCode
                   FOR XML PATH(''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 1, N''),
            N'') AS EvidenceSignals,

        CASE WHEN s.AdjustmentCount > 0 THEN 'signal' ELSE 'baseline' END AS [Source]
    FROM scored s
    ORDER BY s.Priority DESC, s.DisplayName;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Inspector_ListSignals
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Dashboard.usp_Inspector_ListSignals') IS NOT NULL
    DROP PROCEDURE [Dashboard].[usp_Inspector_ListSignals];
GO
/*  The signals an operator can pretend are raised.

    Server-driven for the same reason the life stages are: a signal added by an
    editor should appear in the inspector without a portal release. A hardcoded
    list in the browser would be wrong the day somebody adds one, and wrong
    silently - the toggle simply would not exist.

    Only signals that actually move a card are offered. A signal with no
    priority adjustment changes nothing, and showing it would invite an
    operator to toggle it and conclude the engine is broken. */
CREATE PROCEDURE [Dashboard].[usp_Inspector_ListSignals]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        s.SignalCode,
        s.DisplayName,
        s.DomainCode,
        s.ObservationText,
        s.IsHealthSensitive,
        COUNT(pa.PriorityAdjustmentId) AS AffectsCardCount
    FROM [Knowledge].[Signal] s
    JOIN [Dashboard].[PriorityAdjustment] pa
          ON pa.SignalCode = s.SignalCode AND pa.IsActive = 1
    WHERE s.IsActive = 1
    GROUP BY s.SignalCode, s.DisplayName, s.DomainCode,
             s.ObservationText, s.IsHealthSensitive, s.SortOrder
    ORDER BY s.SortOrder;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Inspector_ExplainCard
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Dashboard.usp_Inspector_ExplainCard') IS NOT NULL
    DROP PROCEDURE [Dashboard].[usp_Inspector_ExplainCard];
GO
/*  Every rule and adjustment governing one card, and whether each one matched.

    This is what turns "my card did not appear" into an answer. It returns the
    rules that passed as well as the ones that failed, because an operator
    debugging an absence needs to see which condition rejected it - a list of
    only the matching rules explains a card's presence and never its absence. */
CREATE PROCEDURE [Dashboard].[usp_Inspector_ExplainCard]
    @CardTypeCode VARCHAR(40),
    @ContextJson  NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- The card itself.
    SELECT
        ct.CardTypeCode, ct.DisplayName, ct.DomainCode, ct.BasePriority,
        ct.RefreshSeconds, ct.LifetimeSeconds, ct.IsDismissible,
        ct.IsHealthSensitive, ct.IsActive
    FROM [Dashboard].[CardType] ct
    WHERE ct.CardTypeCode = @CardTypeCode;

    -- Each eligibility rule, and whether this context satisfies it.
    ;WITH matched AS (
        SELECT TargetKey FROM [Rules].[fn_Match]('dashboardCard', @ContextJson)
    )
    SELECT
        r.RuleId,
        r.DimensionCode,
        d.DisplayName AS DimensionName,
        r.[Operator],
        r.ValuesJson,
        r.RuleNote,
        /*  A card passes only if every dimension it constrains passes, so the
            per-rule answer is the whole card's answer for that dimension. */
        CAST(CASE WHEN EXISTS (SELECT 1 FROM matched m
                               WHERE m.TargetKey = r.TargetKey)
                  THEN 1 ELSE 0 END AS BIT) AS ContextPasses
    FROM [Rules].[Rule] r
    JOIN [Content].[TargetingDimension] d ON d.DimensionCode = r.DimensionCode
    WHERE r.ScopeCode = 'dashboardCard'
      AND r.TargetKey = CONVERT(NVARCHAR(100), @CardTypeCode)
    ORDER BY d.SortOrder;

    -- Every signal that could move it, and by how much.
    SELECT
        pa.SignalCode,
        s.DisplayName AS SignalName,
        pa.AdjustmentKind,
        pa.Amount,
        pa.ReasonText,
        pa.Confidence,
        pa.IsActive
    FROM [Dashboard].[PriorityAdjustment] pa
    JOIN [Knowledge].[Signal] s ON s.SignalCode = pa.SignalCode
    WHERE pa.CardTypeCode = @CardTypeCode
    ORDER BY ABS(pa.Amount) DESC;
END
GO

