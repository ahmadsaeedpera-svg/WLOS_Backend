/*  67_Procs_Prediction.sql

    Framing, and only framing.

    fn_PredictFrom is the whole of it. It takes probabilities Behaviour has
    already observed, keeps the ones with enough behind them, attaches a
    window, and fills in a pattern. There is no arithmetic on the probability
    itself beyond expressing a 0–1 decimal as a whole percent, and
    prediction_test.sql asserts that round trip against the source measure.

    The fourth engine on the simulate-from-a-set split, after
    Behaviour.fn_Measure, Recommend.fn_AssembleFrom and Coach.fn_ExplainFrom.
    The live path passes what Behaviour observed and the Decision Inspector
    passes a hypothetical; both reach this one implementation, so an operator
    tuning a threshold is tuning the thing that actually runs.

    Withholding is a feature, not an error path
    -------------------------------------------
    A prediction whose confidence or support is under the type's floor is not
    returned at all — not as zero, not as unknown, absent. The same rule
    Behaviour applies to a measure it has not seen enough of. The inspector
    reports *why* each one was withheld, because "nothing appeared" and "it
    was deliberately withheld" look identical from outside and only one of
    them is a bug.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- fn_ParseObservations — the operator-facing shorthand
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Predict.fn_ParseObservations') IS NOT NULL
    DROP FUNCTION [Predict].[fn_ParseObservations];
GO
/*  Turns "hydration.completion_probability=0.7@21" into an observation set.

    A function rather than a parse inlined in the inspector, for the reason the
    recommender extracted its own: the inspector returns several result sets
    and INSERT ... EXEC takes only the first, so a T-SQL assertion cannot
    consume the procedure. With the parse extracted, the suite can prove the
    shorthand and the framing agree without a second copy of either.

    The @span suffix is optional and falls back to @DefaultSpanDays. It exists
    because support is what decides whether a prediction is made at all, so an
    operator asking "why is this withheld" needs to be able to vary it.

    Malformed entries are dropped rather than refused: an operator mid-edit
    should see a partial answer, not an error. */
CREATE FUNCTION [Predict].[fn_ParseObservations]
    (@ObservationCsv NVARCHAR(MAX),
     @Confidence     INT,
     @DefaultSpanDays INT)
RETURNS TABLE
AS
RETURN
    WITH parts AS (
        SELECT LTRIM(RTRIM(s.[value])) AS part
        FROM STRING_SPLIT(ISNULL(@ObservationCsv, N''), ',') s
    ),
    split AS (
        SELECT
            LEFT(part, CHARINDEX('=', part) - 1) AS keyPart,
            CASE WHEN CHARINDEX('@', part) > CHARINDEX('=', part)
                 THEN SUBSTRING(part, CHARINDEX('=', part) + 1,
                                CHARINDEX('@', part) - CHARINDEX('=', part) - 1)
                 ELSE SUBSTRING(part, CHARINDEX('=', part) + 1, 40)
            END AS valuePart,
            CASE WHEN CHARINDEX('@', part) > CHARINDEX('=', part)
                 THEN SUBSTRING(part, CHARINDEX('@', part) + 1, 20)
                 ELSE NULL
            END AS spanPart
        FROM parts
        WHERE CHARINDEX('=', part) > 1
          AND CHARINDEX('.', part) > 1
          AND CHARINDEX('.', part) < CHARINDEX('=', part)
    )
    SELECT DISTINCT
        LEFT(keyPart, CHARINDEX('.', keyPart) - 1) AS SubjectKey,
        SUBSTRING(keyPart, CHARINDEX('.', keyPart) + 1, 30) AS MeasureCode,
        TRY_CAST(valuePart AS DECIMAL(9, 4)) AS ValueNumeric,
        CASE WHEN @Confidence IS NULL THEN 100
             WHEN @Confidence < 0 THEN 0
             WHEN @Confidence > 100 THEN 100
             ELSE @Confidence END AS Confidence,
        CASE WHEN TRY_CAST(spanPart AS INT) > 0 THEN TRY_CAST(spanPart AS INT)
             WHEN @DefaultSpanDays > 0 THEN @DefaultSpanDays
             ELSE 1 END AS SpanDays
    FROM split
    WHERE TRY_CAST(valuePart AS DECIMAL(9, 4)) IS NOT NULL;
GO

-- ---------------------------------------------------------------------------
-- fn_PredictFrom — the only framing logic
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Predict.fn_PredictFrom') IS NOT NULL
    DROP FUNCTION [Predict].[fn_PredictFrom];
GO
/*  One statement per prediction type per subject, for the observations that
    carry enough behind them.

    Given no observations this returns nothing, and that is the strongest
    statement of what this engine is: with nothing observed it predicts
    nothing. It has no other source of numbers.

    The probability, the confidence and the support are all carried through
    unchanged. The join is on SourceMeasureCode, and a prediction type can
    only name a measure Behaviour publishes as a probability — the foreign key
    in 66_Prediction.sql sees to that — so there is no path by which a number
    arrives here that the behaviour engine did not compute. */
CREATE FUNCTION [Predict].[fn_PredictFrom]
    (@Observations [Predict].[ObservationSet] READONLY)
RETURNS TABLE
AS
RETURN
    SELECT
        pt.PredictionKey,
        pt.DisplayName,
        o.SubjectKey,
        s.DisplayName AS SubjectName,
        h.HorizonCode,
        h.DisplayName AS HorizonName,
        h.WindowDays,

        /*  A 0–1 probability said as a whole percent. The only transformation
            in this engine, and it is presentation: 0.7 and 70% are the same
            observation. */
        CAST(ROUND(o.ValueNumeric * 100, 0) AS INT) AS ProbabilityPercent,

        o.SpanDays AS SupportDays,
        o.Confidence,

        /*  Substitution, not composition. {chance}, {window} and {support} are
            all required by a constraint, so a framing cannot state a
            likelihood without also stating when it applies and what it rests
            on. The rest of the pattern is connective phrasing. */
        LTRIM(RTRIM(
            REPLACE(
              REPLACE(
                REPLACE(pt.FramingPattern, '{chance}',
                        CAST(CAST(ROUND(o.ValueNumeric * 100, 0) AS INT) AS NVARCHAR(10)) + N'%'),
                '{window}', h.PhraseText),
              '{support}',
              CAST(o.SpanDays AS NVARCHAR(10))
                + CASE WHEN o.SpanDays = 1 THEN N' day of history'
                       ELSE N' days of history' END)
        )) AS StatementText,

        /*  Resolves back to the row in Behaviour that produced the number. */
        CAST('behaviour:' + o.SubjectKey + '.' + o.MeasureCode
             AS NVARCHAR(600)) AS EvidenceCsv,

        pt.SourceMeasureCode,
        DATEADD(HOUR, pt.LifetimeHours, SYSUTCDATETIME()) AS ExpiresUtc
    FROM @Observations o
    JOIN [Predict].[PredictionType] pt
          ON pt.SourceMeasureCode = o.MeasureCode
    JOIN [Predict].[Horizon] h ON h.HorizonCode = pt.HorizonCode
    JOIN [Behaviour].[Subject] s ON s.SubjectKey = o.SubjectKey
    WHERE pt.IsActive = 1
      AND o.ValueNumeric IS NOT NULL
      /*  Withheld rather than hedged. A statement about her behaviour built on
          nine days is not a weaker statement, it is a different kind of thing. */
      AND o.Confidence >= pt.MinConfidence
      AND o.SpanDays  >= pt.MinSupportDays;
GO

-- ---------------------------------------------------------------------------
-- usp_Prediction_Resolve
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Predict.usp_Prediction_Resolve') IS NOT NULL
    DROP PROCEDURE [Predict].[usp_Prediction_Resolve];
GO
/*  Frame what Behaviour has already observed about her.

    Reads Behaviour.fn_Read — the published interface — and never the
    observation table beneath it. That is the whole boundary: an engine
    reaching past fn_Read would be a second reader of behaviour, and the two
    would answer differently the day either changed. */
CREATE PROCEDURE [Predict].[usp_Prediction_Resolve]
    @UserId   UNIQUEIDENTIFIER,
    @AsOfDate DATE = NULL,
    @Persist  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    DECLARE @version VARCHAR(20) = '1.0.0';

    DECLARE @obs [Predict].[ObservationSet];

    /*  Everything Behaviour published for her. The join inside fn_PredictFrom
        keeps the probabilities and ignores the rest, so this procedure does
        not need to know which measures are predictable — the catalogue and its
        foreign key already decide that. */
    INSERT @obs (SubjectKey, MeasureCode, ValueNumeric, Confidence, SpanDays)
    SELECT b.SubjectKey, b.MeasureCode, b.ValueNumeric, b.Confidence, b.SpanDays
    FROM [Behaviour].[fn_Read](@UserId, @AsOfDate) b
    WHERE b.SpanDays >= 1;

    DECLARE @predicted TABLE (
        PredictionKey VARCHAR(40), DisplayName NVARCHAR(80),
        SubjectKey VARCHAR(40), SubjectName NVARCHAR(80),
        HorizonCode VARCHAR(20), HorizonName NVARCHAR(60), WindowDays INT,
        ProbabilityPercent INT, SupportDays INT, Confidence INT,
        StatementText NVARCHAR(600), EvidenceCsv NVARCHAR(600),
        SourceMeasureCode VARCHAR(30), ExpiresUtc DATETIME2(3));

    INSERT @predicted
    SELECT PredictionKey, DisplayName, SubjectKey, SubjectName, HorizonCode,
           HorizonName, WindowDays, ProbabilityPercent, SupportDays, Confidence,
           StatementText, EvidenceCsv, SourceMeasureCode, ExpiresUtc
    FROM [Predict].[fn_PredictFrom](@obs);

    IF @Persist = 1
    BEGIN
        MERGE [Predict].[Predicted] AS target
        USING (SELECT * FROM @predicted) AS source
            ON  target.UserId = @UserId
            AND target.ForLocalDate = @AsOfDate
            AND target.PredictionKey = source.PredictionKey
            AND target.SubjectKey = source.SubjectKey
        WHEN MATCHED THEN UPDATE SET
            ProbabilityPercent = source.ProbabilityPercent,
            WindowDays    = source.WindowDays,
            SupportDays   = source.SupportDays,
            Confidence    = source.Confidence,
            StatementText = source.StatementText,
            EvidenceCsv   = source.EvidenceCsv,
            ExpiresUtc    = source.ExpiresUtc,
            EngineVersion = @version,
            ComputedUtc   = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT
            (UserId, PredictionKey, SubjectKey, ForLocalDate, ProbabilityPercent,
             WindowDays, SupportDays, Confidence, StatementText, EvidenceCsv,
             ExpiresUtc, EngineVersion)
        VALUES
            (@UserId, source.PredictionKey, source.SubjectKey, @AsOfDate,
             source.ProbabilityPercent, source.WindowDays, source.SupportDays,
             source.Confidence, source.StatementText, source.EvidenceCsv,
             source.ExpiresUtc, @version);
    END

    SELECT PredictionKey, DisplayName, SubjectKey, SubjectName, HorizonCode,
           HorizonName, WindowDays, ProbabilityPercent, SupportDays, Confidence,
           StatementText, EvidenceCsv, SourceMeasureCode, ExpiresUtc,
           @version AS EngineVersion
    FROM @predicted
    ORDER BY ProbabilityPercent DESC, PredictionKey, SubjectKey;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Prediction_Get
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Predict.usp_Prediction_Get') IS NOT NULL
    DROP PROCEDURE [Predict].[usp_Prediction_Get];
GO
/*  What was said about her behaviour, and has not lapsed. */
CREATE PROCEDURE [Predict].[usp_Prediction_Get]
    @UserId   UNIQUEIDENTIFIER,
    @AsOfDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @AsOfDate IS NULL SET @AsOfDate = CAST(SYSUTCDATETIME() AS DATE);

    SELECT
        p.PredictionKey,
        pt.DisplayName,
        p.SubjectKey,
        s.DisplayName AS SubjectName,
        pt.HorizonCode,
        h.DisplayName AS HorizonName,
        p.WindowDays,
        p.ProbabilityPercent,
        p.SupportDays,
        p.Confidence,
        p.StatementText,
        p.EvidenceCsv,
        pt.SourceMeasureCode,
        p.ExpiresUtc,
        p.EngineVersion
    FROM [Predict].[Predicted] p
    JOIN [Predict].[PredictionType] pt ON pt.PredictionKey = p.PredictionKey
    JOIN [Predict].[Horizon] h ON h.HorizonCode = pt.HorizonCode
    JOIN [Behaviour].[Subject] s ON s.SubjectKey = p.SubjectKey
    WHERE p.UserId = @UserId
      AND p.ForLocalDate = @AsOfDate
      AND p.ExpiresUtc > SYSUTCDATETIME()
    ORDER BY p.ProbabilityPercent DESC, p.PredictionKey, p.SubjectKey;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Prediction_ListTypes
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Predict.usp_Prediction_ListTypes') IS NOT NULL
    DROP PROCEDURE [Predict].[usp_Prediction_ListTypes];
GO
/*  The prediction catalogue, for operators. Configuration, not anybody's data.

    Carries the source measure and its family beside each framing, because the
    question an operator arrives with is "where does this number come from" and
    the honest answer is the name of a measure in another engine. */
CREATE PROCEDURE [Predict].[usp_Prediction_ListTypes]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        pt.PredictionKey,
        pt.DisplayName,
        pt.[Description],
        pt.HorizonCode,
        h.DisplayName AS HorizonName,
        h.PhraseText,
        h.WindowDays,
        pt.SourceMeasureCode,
        m.DisplayName AS SourceMeasureName,
        m.Family AS SourceFamily,
        m.MinSpanDays AS SourceMinSpanDays,
        pt.FramingPattern,
        pt.MinConfidence,
        pt.MinSupportDays,
        pt.LifetimeHours,
        pt.IsActive,
        /*  A prediction whose source measure has been switched off can never
            fire. It looks identical to one nobody qualifies for, which is the
            same trap the coach's rule count exists to expose. */
        m.IsActive AS SourceIsActive
    FROM [Predict].[PredictionType] pt
    JOIN [Predict].[Horizon] h ON h.HorizonCode = pt.HorizonCode
    JOIN [Behaviour].[MeasureType] m ON m.MeasureCode = pt.SourceMeasureCode
    ORDER BY pt.SortOrder, pt.PredictionKey;
END
GO

PRINT 'Prediction Platform — procedures ready.';
GO
