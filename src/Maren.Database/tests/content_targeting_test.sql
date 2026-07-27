SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Content targeting verification.

    The rule the whole platform pivot leans on is "the right content reaches
    the right woman", and every failure mode here is quiet. Content that
    reaches nobody produces no error; content that reaches the wrong woman
    produces no error either. Only assertions catch these.

    The case worth reading is 8: an item that targets a life stage must not
    reach somebody whose life stage we never learned. Showing pregnancy content
    to a woman we know nothing about is worse than showing her nothing.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/content_targeting_test.sql -I
    Expect: TOTAL: 12  FAILED: 0

    Re-runnable: owns its content items and removes them at both ends.
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));
DECLARE @res TABLE (Succeeded BIT, FailureCode VARCHAR(50));
DECLARE @actor UNIQUEIDENTIFIER = (SELECT TOP 1 UserId FROM [Identity].[User]);
DECLARE @universal UNIQUEIDENTIFIER, @pregOnly UNIQUEIDENTIFIER;
DECLARE @multi UNIQUEIDENTIFIER, @ageRanged UNIQUEIDENTIFIER, @excluded UNIQUEIDENTIFIER;
DECLARE @n INT, @ok BIT, @code VARCHAR(50);

CREATE TABLE #saved (ContentItemId UNIQUEIDENTIFIER,
                     ContentVersionId UNIQUEIDENTIFIER, VersionNumber INT);

DELETE FROM [Content].[ContentItem]
WHERE [Key] IN ('tgt-universal','tgt-preg','tgt-multi','tgt-age','tgt-excl');

/*  Her context: pregnant, working, caring for someone, 34 years old, in GB. */
DECLARE @pregnantPro NVARCHAR(MAX) = N'[
    {"dimension":"life_stage","value":"pregnancy"},
    {"dimension":"role_mode","value":"professional"},
    {"dimension":"role_mode","value":"caregiver"},
    {"dimension":"age","value":"34"},
    {"dimension":"country","value":"GB"}]';

/*  A woman we know almost nothing about yet - mid-onboarding. */
DECLARE @unknown NVARCHAR(MAX) = N'[{"dimension":"country","value":"GB"}]';

DECLARE @teen NVARCHAR(MAX) = N'[
    {"dimension":"life_stage","value":"adolescence"},
    {"dimension":"age","value":"14"},
    {"dimension":"country","value":"PK"}]';

-- Fixtures ------------------------------------------------------------------
DELETE #saved;
INSERT #saved EXEC [Content].[usp_Content_Save] @ContentType='article',
    @Key='tgt-universal', @CategoryKey='nutrition',
    @LocalizationsJson=N'[{"languageCode":"en-GB","title":"Everyone","body":"x"}]',
    @ActorUserId=@actor;
SELECT @universal = ContentItemId FROM #saved;

DELETE #saved;
INSERT #saved EXEC [Content].[usp_Content_Save] @ContentType='article',
    @Key='tgt-preg', @CategoryKey='nutrition',
    @LocalizationsJson=N'[{"languageCode":"en-GB","title":"Pregnancy","body":"x"}]',
    @ActorUserId=@actor;
SELECT @pregOnly = ContentItemId FROM #saved;

DELETE #saved;
INSERT #saved EXEC [Content].[usp_Content_Save] @ContentType='article',
    @Key='tgt-multi', @CategoryKey='nutrition',
    @LocalizationsJson=N'[{"languageCode":"en-GB","title":"Multi","body":"x"}]',
    @ActorUserId=@actor;
SELECT @multi = ContentItemId FROM #saved;

DELETE #saved;
INSERT #saved EXEC [Content].[usp_Content_Save] @ContentType='article',
    @Key='tgt-age', @CategoryKey='nutrition',
    @LocalizationsJson=N'[{"languageCode":"en-GB","title":"Age","body":"x"}]',
    @ActorUserId=@actor;
SELECT @ageRanged = ContentItemId FROM #saved;

DELETE #saved;
INSERT #saved EXEC [Content].[usp_Content_Save] @ContentType='article',
    @Key='tgt-excl', @CategoryKey='nutrition',
    @LocalizationsJson=N'[{"languageCode":"en-GB","title":"Excluded","body":"x"}]',
    @ActorUserId=@actor;
SELECT @excluded = ContentItemId FROM #saved;

-- 1 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Content].[TargetingDimension];
INSERT @results VALUES ('ten targeting dimensions are seeded', CONCAT(@n, ' dimensions'),
    CASE WHEN @n = 10 THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
/*  No rules means everyone. Targeting is the exception, not the default. */
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@pregnantPro)
WHERE ContentItemId = @universal;
INSERT @results VALUES ('untargeted content reaches everyone', CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_SetTargetingRules]
    @ContentItemId = @pregOnly,
    @RulesJson = N'[{"dimension":"life_stage","operator":"in","values":["pregnancy"]}]',
    @ActorUserId = @actor;
SELECT @ok = Succeeded FROM @res;
INSERT @results VALUES ('a targeting rule can be set', 'life_stage in [pregnancy]',
    CASE WHEN @ok = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@pregnantPro)
WHERE ContentItemId = @pregOnly;
INSERT @results VALUES ('targeted content reaches a matching woman', CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@teen)
WHERE ContentItemId = @pregOnly;
INSERT @results VALUES ('and not a non-matching one', CONCAT(@n, ' match'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
/*  AND across dimensions: both must hold. */
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_SetTargetingRules]
    @ContentItemId = @multi,
    @RulesJson = N'[{"dimension":"life_stage","operator":"in","values":["pregnancy","postpartum"]},
                    {"dimension":"country","operator":"in","values":["GB","IE"]}]',
    @ActorUserId = @actor;
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@pregnantPro)
WHERE ContentItemId = @multi;
INSERT @results VALUES ('AND across dimensions, OR within one', CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 7 -------------------------------------------------------------------------
/*  Same item, a woman in Pakistan: the country dimension fails, so the item
    does not reach her even though her life stage matched. */
DECLARE @pregPk NVARCHAR(MAX) = N'[
    {"dimension":"life_stage","value":"pregnancy"},
    {"dimension":"country","value":"PK"}]';
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@pregPk)
WHERE ContentItemId = @multi;
INSERT @results VALUES ('one failing dimension excludes the item', CONCAT(@n, ' match'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 8 -------------------------------------------------------------------------
/*  The conservative case. We know only her country. Content targeted at a
    life stage must not reach her: guessing is worse than silence. */
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@unknown)
WHERE ContentItemId = @pregOnly;
INSERT @results VALUES ('unknown context does not receive targeted content',
    CONCAT(@n, ' match'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 9 -------------------------------------------------------------------------
/*  ...but untargeted content still reaches her. Onboarding is not a blackout. */
SELECT @n = COUNT(*) FROM [Content].[fn_TargetedItems](@unknown)
WHERE ContentItemId = @universal;
INSERT @results VALUES ('unknown context still receives untargeted content',
    CONCAT(@n, ' match'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 10 ------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_SetTargetingRules]
    @ContentItemId = @ageRanged,
    @RulesJson = N'[{"dimension":"age","operator":"between","values":["30","45"]}]',
    @ActorUserId = @actor;
DECLARE @in INT, @out INT;
SELECT @in  = COUNT(*) FROM [Content].[fn_TargetedItems](@pregnantPro) WHERE ContentItemId = @ageRanged;
SELECT @out = COUNT(*) FROM [Content].[fn_TargetedItems](@teen)        WHERE ContentItemId = @ageRanged;
INSERT @results VALUES ('a numeric range includes 34 and excludes 14',
    CONCAT('in=', @in, ' out=', @out),
    CASE WHEN @in = 1 AND @out = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 11 ------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_SetTargetingRules]
    @ContentItemId = @excluded,
    @RulesJson = N'[{"dimension":"life_stage","operator":"not_in","values":["adolescence"]}]',
    @ActorUserId = @actor;
SELECT @in  = COUNT(*) FROM [Content].[fn_TargetedItems](@pregnantPro) WHERE ContentItemId = @excluded;
SELECT @out = COUNT(*) FROM [Content].[fn_TargetedItems](@teen)        WHERE ContentItemId = @excluded;
INSERT @results VALUES ('not_in excludes the named stage only',
    CONCAT('adult=', @in, ' teen=', @out),
    CASE WHEN @in = 1 AND @out = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 12 ------------------------------------------------------------------------
/*  A malformed range must be refused at authoring time. Left to serving time
    it becomes content that reaches nobody and reports nothing. */
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_SetTargetingRules]
    @ContentItemId = @ageRanged,
    @RulesJson = N'[{"dimension":"age","operator":"between","values":["young","old"]}]',
    @ActorUserId = @actor;
SELECT @ok = Succeeded, @code = FailureCode FROM @res;
INSERT @results VALUES ('a non-numeric range is refused', ISNULL(@code, '(none)'),
    CASE WHEN @ok = 0 AND @code = 'INVALID_RANGE' THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 60), 60) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 22), 22) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DELETE FROM [Content].[ContentItem]
WHERE [Key] IN ('tgt-universal','tgt-preg','tgt-multi','tgt-age','tgt-excl');
DROP TABLE #saved;

IF @failed > 0
    THROW 51000, 'Content targeting assertions failed.', 1;
GO
