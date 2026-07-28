/*  60_Procs_Inspector_Recommendation.sql

    The Decision Inspector, extended to recommendations.

    An operator describes evidence - these signals raised, this behaviour
    measure at this value, this goal nearly done - and sees exactly what the
    platform would suggest, at what priority, with what confidence, and the
    sentence-by-sentence reasoning.

    It is the same assembly the real path runs, because Recommend.fn_AssembleFrom
    is the only copy of it and this procedure simply hands it a different
    evidence set. That is why the evidence set exists as a type rather than the
    assembly reading the engines directly, and it is the same shape
    Behaviour.fn_Measure already has.

    After Behaviour, this file is placed after the Recommendation schema for the
    same ordering reason: it declares a variable of Recommend.EvidenceSet, and a
    procedure cannot reference a type created by a later script. That mistake
    stopped a whole deployment once already.

    No user id, no timeline, no snapshot. inspector_test.sql asserts that of
    every procedure named usp_Inspector%, wherever it is defined, against the
    dependency graph rather than the text.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('Dashboard.usp_Inspector_SimulateRecommendations') IS NOT NULL
    DROP PROCEDURE [Dashboard].[usp_Inspector_SimulateRecommendations];
GO
/*  What the platform would suggest, given this evidence.

    Evidence arrives as a compact string an operator can type and a screen can
    build: "kind:key" for presence, "kind:key=value" for a magnitude. Confidence
    defaults to full, because an operator simulating "her consistency is 40" is
    asking what happens when the platform is sure of that - the interesting
    question is the assembly, not the observation quality. @Confidence lowers it
    for anybody checking how a thin-history suggestion reads.

    Two result sets: what was assembled, then every input of every active
    recommendation with whether this evidence matched it. The second is what
    answers "why did my recommendation NOT appear", which the first cannot -
    the same reason the dashboard inspector returns suppressed cards. */
CREATE PROCEDURE [Dashboard].[usp_Inspector_SimulateRecommendations]
    @EvidenceCsv NVARCHAR(MAX),
    @Confidence  INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    IF @Confidence IS NULL OR @Confidence < 0 SET @Confidence = 0;
    IF @Confidence > 100 SET @Confidence = 100;

    /*  Anchored to today. The inspector has no account to read a date from, and
        expiry is relative to when a thing was assembled. */
    DECLARE @asOf DATE = CAST(SYSUTCDATETIME() AS DATE);

    DECLARE @evidence [Recommend].[EvidenceSet];

    /*  The shorthand is parsed by Recommend.fn_ParseEvidence rather than here,
        so the format an operator types has one definition and the assertion
        suite can exercise it without going through this procedure. */
    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT InputKind, InputKey, ValueNumeric, Confidence
    FROM [Recommend].[fn_ParseEvidence](@EvidenceCsv, @Confidence);

    SELECT
        a.RecommendationKey,
        a.DisplayName,
        a.DomainCode,
        a.BodyText,
        a.IsHealthSensitive,
        a.ExpectedBenefit,
        a.ExpectedEffort,
        a.Priority,
        a.Confidence,
        a.MatchedCount,
        a.ExpiresUtc,
        a.Reason,
        a.EvidenceCsv,
        a.EnginesCsv
    FROM [Recommend].[fn_AssembleFrom](@evidence, @asOf) a
    ORDER BY a.Priority DESC, a.RecommendationKey;

    /*  Every input of every active recommendation, matched or not. A list of
        only what fired explains presence and never absence, and absence is
        what an operator is usually investigating. */
    SELECT
        t.RecommendationKey,
        t.DisplayName,
        i.InputKind,
        i.InputKey,
        i.Comparison,
        i.ThresholdValue,
        i.IsRequired,
        i.Weight,
        i.ReasonText,
        CAST(CASE WHEN e.InputKey IS NULL THEN 0 ELSE 1 END AS BIT) AS WasSupplied,
        CAST(CASE
            WHEN e.InputKey IS NULL THEN 0
            WHEN i.Comparison = 'is' THEN 1
            WHEN e.ValueNumeric IS NULL THEN 0
            WHEN i.Comparison = 'gte' AND e.ValueNumeric >= i.ThresholdValue THEN 1
            WHEN i.Comparison = 'lte' AND e.ValueNumeric <= i.ThresholdValue THEN 1
            ELSE 0
        END AS BIT) AS IsMatch,
        e.ValueNumeric AS SuppliedValue
    FROM [Recommend].[RecommendationType] t
    JOIN [Recommend].[RecommendationInput] i
          ON i.RecommendationKey = t.RecommendationKey
    LEFT JOIN @evidence e
          ON e.InputKind = i.InputKind AND e.InputKey = i.InputKey
    WHERE t.IsActive = 1
    ORDER BY t.SortOrder, t.RecommendationKey, i.IsRequired DESC, i.SortOrder;
END
GO

PRINT 'Recommendation Platform — inspector simulation ready.';
GO
