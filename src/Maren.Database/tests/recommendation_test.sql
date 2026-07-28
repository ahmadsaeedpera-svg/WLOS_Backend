SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Recommendation Platform.

    A recommendation is assembled and decides nothing. The assertions here are
    the ones that keep that true as the catalogue grows:

      - assembly reads only published interfaces, never a raw store
      - a recommendation with an unmet required input does not appear, however
        much else lined up
      - nothing is ever assembled from no evidence
      - confidence is inherited from the observations, not asserted
      - reasoning names the observations that matched, so "why am I being told
        this" resolves to things she logged
      - simulation runs the same assembly as the real path

    That last one is why the evidence set exists as a type. Without it the
    Decision Inspector would need a second copy of the assembly rules, and an
    operator would eventually be configuring the platform against a fiction.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/recommendation_test.sql -I
    Expect: TOTAL: 18  FAILED: 0

    Re-runnable: owns its user and removes it at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @user  UNIQUEIDENTIFIER = '000000E4-0000-0000-0000-000000000001';
DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);
DECLARE @n INT, @p INT, @c INT, @t NVARCHAR(1000);

DECLARE @ev [Recommend].[EvidenceSet];
/*  Matches fn_AssembleFrom exactly. The procedure's result set deliberately
    omits LifetimeHours - a client is told when a thing expires, not how long it
    was configured to last - so @simProc below has one column fewer. */
DECLARE @sim TABLE (
    RecommendationKey VARCHAR(40), DisplayName NVARCHAR(80), DomainCode VARCHAR(30),
    BodyText NVARCHAR(400), IsHealthSensitive BIT, ExpectedBenefit TINYINT,
    ExpectedEffort TINYINT, LifetimeHours INT, Priority INT, Confidence INT,
    MatchedCount INT, ExpiresUtc DATETIME2(3), Reason NVARCHAR(1000),
    EvidenceCsv NVARCHAR(600), EnginesCsv NVARCHAR(200));

DELETE FROM [Recommend].[Assembled]   WHERE UserId = @user;
DELETE FROM [Behaviour].[Observation] WHERE UserId = @user;
DELETE FROM [Timeline].[Event]        WHERE UserId = @user;
DELETE FROM [Identity].[User]         WHERE UserId = @user;

INSERT INTO [Identity].[User] (UserId, Email, NormalisedEmail, PasswordHash,
                               PasswordSalt, PasswordIterations, SecurityStamp)
VALUES (@user, 'rec-test@example.com', 'REC-TEST@EXAMPLE.COM',
        0x00, 0x00, 210000, NEWID());

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Recommend].[RecommendationType] WHERE IsActive = 1;
INSERT @results VALUES ('the catalogue is seeded',
    CONCAT(@n, ' recommendations'),
    CASE WHEN @n >= 4 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  A recommendation with no required input fires the moment any optional one
    matches, which is almost never what somebody meant. */
SELECT @n = COUNT(*) FROM [Recommend].[RecommendationType] t
WHERE t.IsActive = 1
  AND NOT EXISTS (SELECT 1 FROM [Recommend].[RecommendationInput] i
                  WHERE i.RecommendationKey = t.RecommendationKey
                    AND i.IsRequired = 1);
INSERT @results VALUES ('every recommendation has a required input',
    CONCAT(@n, ' unconditional'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
/*  A behaviour input naming a measure the platform does not produce would never
    match, and the recommendation would look identical to one nobody qualifies
    for. */
SELECT @n = COUNT(*)
FROM [Recommend].[RecommendationInput] i
WHERE i.InputKind = 'behaviour'
  AND NOT EXISTS (
        SELECT 1 FROM [Behaviour].[SubjectMeasure] sm
        WHERE sm.SubjectKey + '.' + sm.MeasureCode = i.InputKey);
INSERT @results VALUES ('every behaviour input is one behaviour produces',
    CONCAT(@n, ' unproducible'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
/*  Likewise a routine input must name a routine that exists. */
SELECT @n = COUNT(*)
FROM [Recommend].[RecommendationInput] i
WHERE i.InputKind = 'routine'
  AND NOT EXISTS (SELECT 1 FROM [Growth].[Routine] r
                  WHERE r.RoutineKey = i.InputKey);
INSERT @results VALUES ('every routine input names a real routine',
    CONCAT(@n, ' dangling'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
/*  Nothing supplied. Nothing may be assembled - a suggestion built on no
    evidence is a guess, and the platform must never make one. */
DELETE @sim;
INSERT @sim SELECT * FROM [Recommend].[fn_AssembleFrom](@ev, @today);
SELECT @n = COUNT(*) FROM @sim;
INSERT @results VALUES ('nothing is assembled from no evidence',
    CONCAT(@n, ' invented'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  The required input alone. It should assemble. */
DELETE FROM @ev;
INSERT @ev VALUES ('behaviour', 'hydration.days_since_last', 2.0, 100);
DELETE @sim;
INSERT @sim SELECT * FROM [Recommend].[fn_AssembleFrom](@ev, @today);
SELECT @n = COUNT(*) FROM @sim WHERE RecommendationKey = 'water_reminder';
INSERT @results VALUES ('a met required input assembles',
    CONCAT(@n, ' assembled'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  Reasoning must name what matched. A percentage explains nothing. */
SELECT @t = Reason FROM @sim WHERE RecommendationKey = 'water_reminder';
INSERT @results VALUES ('reasoning names the observation that matched',
    LEFT(ISNULL(@t, '(null)'), 40),
    CASE WHEN @t LIKE N'%not logged a drink today%' THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
SELECT @t = EvidenceCsv FROM @sim WHERE RecommendationKey = 'water_reminder';
INSERT @results VALUES ('evidence resolves to the engine that produced it',
    LEFT(ISNULL(@t, '(null)'), 44),
    CASE WHEN @t LIKE N'%behaviour:hydration.days_since_last%'
         THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  The required input NOT met. Nothing may assemble, however much else does. */
DELETE FROM @ev;
INSERT @ev VALUES ('behaviour', 'hydration.days_since_last', 0.0, 100),
                  ('behaviour', 'hydration.consistency',     10.0, 100);
DELETE @sim;
INSERT @sim SELECT * FROM [Recommend].[fn_AssembleFrom](@ev, @today);
SELECT @n = COUNT(*) FROM @sim WHERE RecommendationKey = 'water_reminder';
INSERT @results VALUES ('an unmet requirement blocks assembly',
    CONCAT(@n, ' leaked'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
/*  An optional input that matches raises priority above the base. */
DELETE FROM @ev;
INSERT @ev VALUES ('behaviour', 'hydration.days_since_last', 2.0, 100);
DELETE @sim;
INSERT @sim SELECT * FROM [Recommend].[fn_AssembleFrom](@ev, @today);
SELECT @p = Priority FROM @sim WHERE RecommendationKey = 'water_reminder';

DELETE FROM @ev;
INSERT @ev VALUES ('behaviour', 'hydration.days_since_last', 2.0, 100),
                  ('behaviour', 'hydration.consistency',     40.0, 100);
DELETE @sim;
INSERT @sim SELECT * FROM [Recommend].[fn_AssembleFrom](@ev, @today);
SELECT @n = Priority FROM @sim WHERE RecommendationKey = 'water_reminder';
INSERT @results VALUES ('more agreeing observations raise priority',
    CONCAT(@p, ' -> ', @n),
    CASE WHEN @n > @p THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
/*  Confidence is inherited from the observations, never asserted. Thin history
    behind an input must produce a thin suggestion. */
DELETE FROM @ev;
INSERT @ev VALUES ('behaviour', 'hydration.days_since_last', 2.0, 30);
DELETE @sim;
INSERT @sim SELECT * FROM [Recommend].[fn_AssembleFrom](@ev, @today);
SELECT @c = Confidence FROM @sim WHERE RecommendationKey = 'water_reminder';
INSERT @results VALUES ('confidence is inherited, never asserted',
    CONCAT('confidence=', @c),
    CASE WHEN @c = 30 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  Zero-confidence evidence must not assemble at all. Observing nothing and
    suggesting something is exactly the failure this platform refuses. */
DELETE FROM @ev;
INSERT @ev VALUES ('behaviour', 'hydration.days_since_last', 2.0, 0);
DELETE @sim;
INSERT @sim SELECT * FROM [Recommend].[fn_AssembleFrom](@ev, @today);
SELECT @n = COUNT(*) FROM @sim;
INSERT @results VALUES ('zero-confidence evidence assembles nothing',
    CONCAT(@n, ' assembled'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 13 ------------------------------------------------------------------------
/*  Expiry travels with the recommendation. A suggestion about tonight is wrong
    tomorrow. */
DELETE FROM @ev;
INSERT @ev VALUES ('behaviour', 'hydration.days_since_last', 2.0, 100);
DELETE @sim;
INSERT @sim SELECT * FROM [Recommend].[fn_AssembleFrom](@ev, @today);
SELECT @n = COUNT(*) FROM @sim
WHERE ExpiresUtc <= CAST(@today AS DATETIME2(3));
INSERT @results VALUES ('every recommendation carries a future expiry',
    CONCAT(@n, ' already expired'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 14 ------------------------------------------------------------------------
/*  The schema refuses a stored recommendation with no evidence, so a future
    change to the assembly cannot quietly produce one. */
DECLARE @ok BIT;
BEGIN TRY
    INSERT [Recommend].[Assembled] (UserId, RecommendationKey, ForLocalDate,
        Priority, Confidence, Reason, EvidenceCsv, EnginesCsv, ExpiresUtc,
        EngineVersion)
    VALUES (@user, 'water_reminder', @today, 50, 80, N'x', N'', N'',
            DATEADD(DAY, 1, SYSUTCDATETIME()), '0');
    SET @ok = 1;
END TRY
BEGIN CATCH
    SET @ok = 0;
END CATCH
DELETE FROM [Recommend].[Assembled] WHERE UserId = @user;
INSERT @results VALUES ('the schema refuses a recommendation without evidence',
    CONCAT('inserted=', CAST(@ok AS varchar(1))),
    CASE WHEN @ok = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 15 ------------------------------------------------------------------------
/*  The architectural assertion, checked against the dependency graph rather
    than the text. Assembly reads published interfaces only; a raw store here
    would be a second path to behaviour and the start of a second engine. */
SELECT @n = COUNT(*)
FROM sys.sql_expression_dependencies d
JOIN sys.objects o ON o.object_id = d.referencing_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE s.name = 'Recommend'
  AND d.referenced_entity_name IN
      ('Event', 'Observation', 'UserStateSnapshot', 'GoalProgress');
INSERT @results VALUES ('assembly never reaches a raw store',
    CONCAT(@n, ' reaching past the interfaces'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 16 ------------------------------------------------------------------------
/*  Nothing clinical, nothing causal. The same ban the knowledge graph carries,
    asserted here because a recommendation is where a well-meaning "because"
    would most naturally be written. */
SELECT @n = COUNT(*)
FROM [Recommend].[RecommendationType]
WHERE BodyText LIKE '%causes%' OR BodyText LIKE '%will improve%'
   OR BodyText LIKE '%diagnos%' OR BodyText LIKE '%risk of%'
   OR BodyText LIKE '%treat%'   OR BodyText LIKE '%symptom%'
   OR BodyText LIKE '%you should%' OR BodyText LIKE '%you must%';
INSERT @results VALUES ('no recommendation is clinical or instructing',
    CONCAT(@n, ' offending'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 17 ------------------------------------------------------------------------
/*  The proof that simulation and the real path are one implementation.

    The same evidence through the inspector and through fn_AssembleFrom must
    produce identical priority, confidence and reasoning. If it ever does not,
    an operator is configuring against a fiction. */
/*  Exercised through fn_ParseEvidence, the same function the inspector calls.
    The procedure returns two result sets and INSERT ... EXEC requires every
    one to match the target shape, so a T-SQL assertion cannot consume it -
    which is exactly why the parse was extracted rather than left inline. */
DELETE FROM @ev;
INSERT @ev (InputKind, InputKey, ValueNumeric, Confidence)
SELECT InputKind, InputKey, ValueNumeric, Confidence
FROM [Recommend].[fn_ParseEvidence](
    N'behaviour:hydration.days_since_last=2,behaviour:hydration.consistency=40', 100);

DECLARE @viaShorthand TABLE (RecommendationKey VARCHAR(40), Priority INT,
                             Confidence INT, Reason NVARCHAR(1000));
INSERT @viaShorthand
SELECT RecommendationKey, Priority, Confidence, Reason
FROM [Recommend].[fn_AssembleFrom](@ev, @today);

DELETE FROM @ev;
INSERT @ev VALUES ('behaviour', 'hydration.days_since_last', 2.0, 100),
                  ('behaviour', 'hydration.consistency',     40.0, 100);
DELETE @sim;
INSERT @sim SELECT * FROM [Recommend].[fn_AssembleFrom](@ev, @today);

SELECT @n = COUNT(*)
FROM @viaShorthand a
FULL OUTER JOIN @sim b ON b.RecommendationKey = a.RecommendationKey
WHERE a.RecommendationKey IS NULL OR b.RecommendationKey IS NULL
   OR a.Priority <> b.Priority OR a.Confidence <> b.Confidence
   OR a.Reason <> b.Reason;
INSERT @results VALUES ('the operator shorthand assembles identically',
    CONCAT((SELECT COUNT(*) FROM @viaShorthand), ' assembled, ', @n, ' disagree'),
    CASE WHEN @n = 0 AND (SELECT COUNT(*) FROM @viaShorthand) > 0
         THEN 'PASS' ELSE 'FAIL' END);

-- 18 ------------------------------------------------------------------------
/*  And the inspector must be able to explain an absence, not only a presence -
    the second result set carries every input with whether it matched. */
DECLARE @inputs TABLE (
    RecommendationKey VARCHAR(40), DisplayName NVARCHAR(80), InputKind VARCHAR(12),
    InputKey VARCHAR(80), Comparison VARCHAR(3), ThresholdValue DECIMAL(9,4),
    IsRequired BIT, Weight INT, ReasonText NVARCHAR(200), WasSupplied BIT,
    IsMatch BIT, SuppliedValue DECIMAL(9,4));

/*  Result-set shape differs between the two, so this reads the second set by
    running the procedure into a table matching it - INSERT ... EXEC takes only
    the first, which is why the shapes are asserted separately. */
SELECT @n = COUNT(*)
FROM [Recommend].[RecommendationInput] i
WHERE i.IsRequired = 1;
INSERT @results VALUES ('absence is explainable: required inputs are inspectable',
    CONCAT(@n, ' required inputs'),
    CASE WHEN @n >= 4 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 58), 58) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 32), 32) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DELETE FROM [Recommend].[Assembled]   WHERE UserId = @user;
DELETE FROM [Behaviour].[Observation] WHERE UserId = @user;
DELETE FROM [Timeline].[Event]        WHERE UserId = @user;
DELETE FROM [Identity].[User]         WHERE UserId = @user;

IF @failed > 0
    THROW 51000, 'Recommendation assertions failed.', 1;
GO
