/*  68_Procs_Inspector_Prediction.sql

    The Decision Inspector, extended to prediction.

    An operator describes observations and sees exactly what the platform would
    say about them — and, for everything it would not say, why not. It is the
    same framing the live path runs, because Predict.fn_PredictFrom is the only
    copy and this procedure hands it an observation set built by the only copy
    of the shorthand.

    Placed after the Prediction schema because it declares a variable of
    Predict.ObservationSet. A procedure cannot reference a type created by a
    later script — that mistake stopped a whole deployment once, at position 36
    of 44.

    No user id, no timeline, no snapshot.

    Why the second result set is the important one
    ----------------------------------------------
    A prediction that appears explains itself. A prediction that does not is
    indistinguishable from a bug, and this engine withholds deliberately and
    often: under the confidence floor, under the support floor, or with no
    observation at all. An operator who cannot tell "withheld on purpose" from
    "broken" will eventually lower a floor to make the screen look busier,
    which is the one change here that would make the platform overstate what it
    knows.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID('Dashboard.usp_Inspector_SimulatePrediction') IS NOT NULL
    DROP PROCEDURE [Dashboard].[usp_Inspector_SimulatePrediction];
GO
/*  What the platform would predict from these observations, and what it would
    withhold.

    @ObservationCsv is "subject.measure=value@span", comma separated. The span
    suffix is optional and falls back to @DefaultSpanDays. */
CREATE PROCEDURE [Dashboard].[usp_Inspector_SimulatePrediction]
    @ObservationCsv   NVARCHAR(MAX),
    @Confidence       INT = 100,
    @DefaultSpanDays  INT = 28
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @obs [Predict].[ObservationSet];

    INSERT @obs (SubjectKey, MeasureCode, ValueNumeric, Confidence, SpanDays)
    SELECT SubjectKey, MeasureCode, ValueNumeric, Confidence, SpanDays
    FROM [Predict].[fn_ParseObservations](
        @ObservationCsv, @Confidence, @DefaultSpanDays);

    /*  Framed by the only copy of the framing. The inspector adds nothing. */
    SELECT
        p.PredictionKey,
        p.DisplayName,
        p.SubjectKey,
        p.SubjectName,
        p.HorizonCode,
        p.HorizonName,
        p.WindowDays,
        p.ProbabilityPercent,
        p.SupportDays,
        p.Confidence,
        p.StatementText,
        p.EvidenceCsv,
        p.SourceMeasureCode,
        p.ExpiresUtc
    FROM [Predict].[fn_PredictFrom](@obs) p
    ORDER BY p.ProbabilityPercent DESC, p.PredictionKey, p.SubjectKey;

    /*  Every prediction type against every observation that could feed it,
        including the types nothing was supplied for. The reason is written for
        the person reading it, because "no rows" is not an answer an operator
        can act on. */
    SELECT
        pt.PredictionKey,
        pt.DisplayName,
        pt.SourceMeasureCode,
        pt.HorizonCode,
        pt.MinConfidence,
        pt.MinSupportDays,
        pt.IsActive,
        o.SubjectKey,
        o.ValueNumeric AS SuppliedValue,
        o.Confidence   AS SuppliedConfidence,
        o.SpanDays     AS SuppliedSpanDays,
        CAST(CASE WHEN o.SubjectKey IS NULL THEN 0 ELSE 1 END AS BIT) AS WasSupplied,
        CAST(CASE
            WHEN o.SubjectKey IS NULL THEN 0
            WHEN pt.IsActive = 0 THEN 0
            WHEN o.ValueNumeric IS NULL THEN 0
            WHEN o.Confidence < pt.MinConfidence THEN 0
            WHEN o.SpanDays  < pt.MinSupportDays THEN 0
            ELSE 1
        END AS BIT) AS IsPredicted,
        CASE
            WHEN o.SubjectKey IS NULL
                THEN N'Nothing was observed for ' + pt.SourceMeasureCode
                   + N', so there is no number to frame.'
            WHEN pt.IsActive = 0
                THEN N'This prediction is switched off.'
            WHEN o.ValueNumeric IS NULL
                THEN N'The observation carried no value.'
            WHEN o.Confidence < pt.MinConfidence
                THEN N'Confidence ' + CAST(o.Confidence AS NVARCHAR(10))
                   + N' is under the floor of ' + CAST(pt.MinConfidence AS NVARCHAR(10))
                   + N'; withheld rather than hedged.'
            WHEN o.SpanDays < pt.MinSupportDays
                THEN N'Only ' + CAST(o.SpanDays AS NVARCHAR(10))
                   + N' days of history against a floor of '
                   + CAST(pt.MinSupportDays AS NVARCHAR(10)) + N'; withheld.'
            ELSE N'Predicted.'
        END AS Explanation
    FROM [Predict].[PredictionType] pt
    LEFT JOIN @obs o ON o.MeasureCode = pt.SourceMeasureCode
    ORDER BY pt.SortOrder, pt.PredictionKey, o.SubjectKey;
END
GO

PRINT 'Prediction Platform — inspector simulation ready.';
GO
