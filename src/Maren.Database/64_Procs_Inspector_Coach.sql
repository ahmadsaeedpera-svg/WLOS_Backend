/*  64_Procs_Inspector_Coach.sql

    The Decision Inspector, extended to the coach.

    An operator describes evidence, sees what the platform would suggest, and
    then hears exactly how it would say it. It is the same explanation the live
    path runs, because Coach.fn_ExplainFrom is the only copy and this procedure
    hands it recommendations assembled by the only copy of the assembly.

    Placed after the Coach schema because it declares variables of
    Coach.ExplainSet and Recommend.EvidenceSet. A procedure cannot reference a
    type created by a later script - that mistake stopped a whole deployment
    once, at position 36 of 44.

    No user id, no timeline, no snapshot.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('Dashboard.usp_Inspector_SimulateCoach') IS NOT NULL
    DROP PROCEDURE [Dashboard].[usp_Inspector_SimulateCoach];
GO
/*  What the platform would say, and in what voice.

    Two result sets: the messages, then every tone with whether this evidence
    selected it and why. The second answers "why is it speaking to her like
    that", and equally "why is it not being gentle" - which the first cannot,
    because a chosen tone says nothing about the ones that were not.
*/
CREATE PROCEDURE [Dashboard].[usp_Inspector_SimulateCoach]
    @EvidenceCsv NVARCHAR(MAX),
    @Confidence  INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @evidence [Recommend].[EvidenceSet];
    DECLARE @recs [Coach].[ExplainSet];

    INSERT @evidence (InputKind, InputKey, ValueNumeric, Confidence)
    SELECT InputKind, InputKey, ValueNumeric, Confidence
    FROM [Recommend].[fn_ParseEvidence](@EvidenceCsv, @Confidence);

    /*  Assembled by the only copy of the assembly, then explained by the only
        copy of the explanation. The inspector adds nothing to either. */
    INSERT @recs (RecommendationKey, DisplayName, BodyText, Reason, EvidenceCsv,
                  Priority, Confidence, ExpectedEffort)
    SELECT a.RecommendationKey, a.DisplayName, a.BodyText, a.Reason,
           a.EvidenceCsv, a.Priority, a.Confidence, a.ExpectedEffort
    FROM [Recommend].[fn_AssembleFrom](@evidence, CAST(SYSUTCDATETIME() AS DATE)) a;

    SELECT
        e.RecommendationKey,
        e.DisplayName,
        e.ToneCode,
        e.ToneName,
        e.ToneRationale,
        e.ToneFromRule,
        e.MessageText,
        e.Priority,
        e.Confidence,
        e.ExpectedEffort,
        e.EvidenceCsv,
        e.ExpiresUtc
    FROM [Coach].[fn_ExplainFrom](@recs, @evidence, 24) e
    ORDER BY e.Priority DESC, e.RecommendationKey;

    /*  Every tone, and why each did or did not apply. A chosen tone explains
        itself; the ones passed over do not, and "why is it not being gentle"
        is the question an operator actually arrives with. */
    SELECT
        t.ToneCode,
        t.DisplayName,
        t.Pattern,
        t.Weight,
        t.IsDefault,
        t.IsActive,
        r.InputKind,
        r.InputKey,
        r.Comparison,
        r.ThresholdValue,
        r.RationaleText,
        CAST(CASE WHEN ev.InputKey IS NULL THEN 0 ELSE 1 END AS BIT) AS WasSupplied,
        CAST(CASE
            WHEN ev.InputKey IS NULL THEN 0
            WHEN r.Comparison = 'is' THEN 1
            WHEN ev.ValueNumeric IS NULL THEN 0
            WHEN r.Comparison = 'gte' AND ev.ValueNumeric >= r.ThresholdValue THEN 1
            WHEN r.Comparison = 'lte' AND ev.ValueNumeric <= r.ThresholdValue THEN 1
            ELSE 0
        END AS BIT) AS IsMatch,
        ev.ValueNumeric AS SuppliedValue
    FROM [Coach].[ToneProfile] t
    LEFT JOIN [Coach].[ToneRule] r ON r.ToneCode = t.ToneCode
    LEFT JOIN @evidence ev
          ON ev.InputKind = r.InputKind AND ev.InputKey = r.InputKey
    ORDER BY t.Weight DESC, t.ToneCode, r.InputKey;
END
GO

PRINT 'Coach Platform — inspector simulation ready.';
GO
