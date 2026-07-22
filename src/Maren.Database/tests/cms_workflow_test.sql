SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    CMS workflow verification.

    Exercises the properties the design depends on, against the real
    procedures. Results are collected into a table and reported at the end
    rather than printed inline — PRINT CONCAT() cannot take a subquery, and
    threading every assertion through a variable first makes the intent harder
    to read than it needs to be.

    Run: sqlcmd -S "(localdb)\MSSQLLocalDB" -d MarenPlatform
                -i tests/cms_workflow_test.sql -I
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @actor UNIQUEIDENTIFIER = (SELECT TOP 1 UserId FROM [Identity].[User]);
DECLARE @id UNIQUEIDENTIFIER, @v1 UNIQUEIDENTIFIER, @ukId UNIQUEIDENTIFIER;
DECLARE @n INT, @ok BIT;

CREATE TABLE #saved (ContentItemId UNIQUEIDENTIFIER,
                     ContentVersionId UNIQUEIDENTIFIER, VersionNumber INT);
CREATE TABLE #client (
    ContentItemId UNIQUEIDENTIFIER, ContentType VARCHAR(40), [Key] VARCHAR(150),
    Weight INT, SourceCitation NVARCHAR(300), FromWeek TINYINT, ToWeek TINYINT,
    Season VARCHAR(20), ModifiedUtc DATETIME2(3), CategoryKey VARCHAR(64),
    Title NVARCHAR(300), Body NVARCHAR(MAX), Summary NVARCHAR(1000),
    MetadataJson NVARCHAR(MAX), IsFallback BIT);

DECLARE @res TABLE (Succeeded BIT, FailureCode VARCHAR(50));

/*  Re-runnable. Without this the second run creates a second 'folate-foods'
    and the single-row assertions fail for a reason that has nothing to do
    with the behaviour under test. */
DELETE FROM [Content].[ContentItem]
WHERE [Key] IN ('folate-foods', 'uk-only', 'debug-1', 'dbg-min');

-- 1 ------------------------------------------------------------------------
INSERT #saved EXEC [Content].[usp_Content_Save]
    @ContentType = 'article', @Key = 'folate-foods', @CategoryKey = 'nutrition',
    @SourceCitation = 'NHS, reviewed 2026',
    @LocalizationsJson = N'[{"languageCode":"en-GB","title":"Where folate turns up","body":"Leafy greens, beans and citrus."}]',
    @ChangeSummary = 'First draft', @ActorUserId = @actor;

SELECT @id = ContentItemId, @v1 = ContentVersionId, @n = VersionNumber FROM #saved;
INSERT @results VALUES ('save creates version 1', CONCAT('v', @n),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 2 ------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_Publish] @ContentItemId = @id, @ActorUserId = @actor;
SELECT @ok = Succeeded, @n = 0 FROM @res;
INSERT @results
SELECT 'publish without approval is refused', ISNULL(FailureCode, '(none)'),
       CASE WHEN Succeeded = 0 AND FailureCode = 'NOT_APPROVED' THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 3 ------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_Approve]
    @ContentItemId = @id, @IsApproved = 1, @Reason = 'Reviewed', @ActorUserId = @actor;
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_Publish] @ContentItemId = @id, @ActorUserId = @actor;
INSERT @results
SELECT 'publish after approval succeeds', CONCAT('succeeded=', Succeeded),
       CASE WHEN Succeeded = 1 THEN 'PASS' ELSE 'FAIL' END
FROM @res;

-- 4 ------------------------------------------------------------------------
DELETE FROM #saved;
INSERT #saved EXEC [Content].[usp_Content_Save]
    @ContentItemId = @id, @ContentType = 'article', @Key = 'folate-foods',
    @CategoryKey = 'nutrition',
    @LocalizationsJson = N'[{"languageCode":"en-GB","title":"EDITED DRAFT","body":"Work in progress."}]',
    @ChangeSummary = 'Second pass', @ActorUserId = @actor;

SELECT @n = VersionNumber FROM [Content].[ContentItem] WHERE ContentItemId = @id;
SELECT @ok = CASE WHEN PublishedVersionId = @v1 THEN 1 ELSE 0 END
FROM [Content].[ContentItem] WHERE ContentItemId = @id;
INSERT @results VALUES ('editing does not move the published pointer',
    CONCAT('current=v', @n, ', published=v1'),
    CASE WHEN @ok = 1 AND @n = 2 THEN 'PASS' ELSE 'FAIL' END);

-- 5 ------------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_RestoreVersion]
    @ContentItemId = @id, @ContentVersionId = @v1, @ActorUserId = @actor;
SELECT @n = VersionNumber FROM [Content].[ContentItem] WHERE ContentItemId = @id;
INSERT @results VALUES ('restore writes forward, never rewinds',
    CONCAT('now v', @n), CASE WHEN @n = 3 THEN 'PASS' ELSE 'FAIL' END);

-- 5b -----------------------------------------------------------------------
-- Regression: restore once delegated to usp_Content_Save with an empty
-- localisations array, which deleted every translation it was meant to bring
-- back. The restored title must be the original, not blank.
DECLARE @restoredTitle NVARCHAR(300) = (
    SELECT TOP 1 Title FROM [Content].[ContentTranslation]
    WHERE ContentItemId = @id AND LanguageCode = 'en-GB');
INSERT @results VALUES ('restore brings translations back',
    ISNULL(@restoredTitle, '(blank)'),
    CASE WHEN @restoredTitle = N'Where folate turns up' THEN 'PASS' ELSE 'FAIL' END);

-- 6 ------------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Content].[ContentVersion] WHERE ContentItemId = @id;
INSERT @results VALUES ('full history retained', CONCAT(@n, ' versions'),
    CASE WHEN @n = 3 THEN 'PASS' ELSE 'FAIL' END);

-- 7 ------------------------------------------------------------------------
TRUNCATE TABLE #client;
INSERT #client EXEC [Content].[usp_Content_GetForClient]
    @ContentType = 'article', @LanguageCode = 'en-GB', @CountryIso = 'GB';
SELECT @n = COUNT(*) FROM #client WHERE [Key] = 'folate-foods';
INSERT @results VALUES ('client sees the published article', CONCAT(@n, ' row'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 8 ------------------------------------------------------------------------
TRUNCATE TABLE #client;
INSERT #client EXEC [Content].[usp_Content_GetForClient]
    @ContentType = 'article', @LanguageCode = 'fr-FR', @CountryIso = 'FR';
SELECT TOP 1 @ok = IsFallback FROM #client WHERE [Key] = 'folate-foods';
INSERT @results VALUES ('missing translation falls back to en-GB',
    CONCAT('isFallback=', ISNULL(CAST(@ok AS VARCHAR(1)), 'none')),
    CASE WHEN @ok = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 9 ------------------------------------------------------------------------
DELETE FROM #saved;
INSERT #saved EXEC [Content].[usp_Content_Save]
    @ContentType = 'article', @Key = 'uk-only', @CategoryKey = 'nutrition',
    @CountryFilter = N'["GB"]',
    @LocalizationsJson = N'[{"languageCode":"en-GB","title":"UK only","body":"Region gated."}]',
    @ActorUserId = @actor;
SELECT @ukId = ContentItemId FROM #saved;

DELETE @res;
INSERT @res EXEC [Content].[usp_Content_Approve] @ContentItemId = @ukId, @IsApproved = 1, @ActorUserId = @actor;
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_Publish] @ContentItemId = @ukId, @ActorUserId = @actor;

TRUNCATE TABLE #client;
INSERT #client EXEC [Content].[usp_Content_GetForClient]
    @ContentType = 'article', @LanguageCode = 'en-GB', @CountryIso = 'US';
SELECT @n = COUNT(*) FROM #client WHERE [Key] = 'uk-only';
INSERT @results VALUES ('country filter excludes a US client', CONCAT(@n, ' rows'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 10 -----------------------------------------------------------------------
TRUNCATE TABLE #client;
INSERT #client EXEC [Content].[usp_Content_GetForClient]
    @ContentType = 'article', @LanguageCode = 'en-GB', @CountryIso = 'GB';
SELECT @n = COUNT(*) FROM #client WHERE [Key] = 'uk-only';
INSERT @results VALUES ('country filter includes a GB client', CONCAT(@n, ' row'),
    CASE WHEN @n = 1 THEN 'PASS' ELSE 'FAIL' END);

-- 11 -----------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_Delete] @ContentItemId = @ukId, @ActorUserId = @actor;
TRUNCATE TABLE #client;
INSERT #client EXEC [Content].[usp_Content_GetForClient]
    @ContentType = 'article', @LanguageCode = 'en-GB', @CountryIso = 'GB';
SELECT @n = COUNT(*) FROM #client WHERE [Key] = 'uk-only';
DECLARE @kept INT = (SELECT COUNT(*) FROM [Content].[ContentVersion] WHERE ContentItemId = @ukId);
INSERT @results VALUES ('soft delete hides from client but keeps history',
    CONCAT('client=', @n, ', versions=', @kept),
    CASE WHEN @n = 0 AND @kept > 0 THEN 'PASS' ELSE 'FAIL' END);

-- 12 -----------------------------------------------------------------------
DELETE @res;
INSERT @res EXEC [Content].[usp_Content_Schedule]
    @ContentItemId = @id, @Action = 'unpublish',
    @ScheduledUtc = '2020-01-01', @ActorUserId = @actor;

DECLARE @ran TABLE (Executed INT);
INSERT @ran EXEC [Content].[usp_Content_RunDueSchedules];
DECLARE @first INT = (SELECT Executed FROM @ran);
DELETE @ran;
INSERT @ran EXEC [Content].[usp_Content_RunDueSchedules];
DECLARE @second INT = (SELECT Executed FROM @ran);
INSERT @results VALUES ('due schedule is claimed exactly once',
    CONCAT('first=', @first, ', second=', @second),
    CASE WHEN @first >= 1 AND @second = 0 THEN 'PASS' ELSE 'FAIL' END);

-- 13 -----------------------------------------------------------------------
SELECT @n = COUNT(*) FROM [Audit].[AuditLog] WHERE EntityType = 'ContentItem';
INSERT @results VALUES ('every content operation is audited', CONCAT(@n, ' rows'),
    CASE WHEN @n >= 10 THEN 'PASS' ELSE 'FAIL' END);

-- 14 -----------------------------------------------------------------------
DECLARE @search TABLE (
    ContentItemId UNIQUEIDENTIFIER, ContentType VARCHAR(40), [Key] VARCHAR(150),
    Status VARCHAR(20), Weight INT, FromWeek TINYINT, ToWeek TINYINT,
    Season VARCHAR(20), SourceCitation NVARCHAR(300), VersionNumber INT,
    PublishedVersionId UNIQUEIDENTIFIER, IsDeleted BIT, CreatedUtc DATETIME2(3),
    ModifiedUtc DATETIME2(3), CategoryKey VARCHAR(64), AuthorName NVARCHAR(200),
    Title NVARCHAR(300), TotalCount INT);
INSERT @search EXEC [Content].[usp_Content_Search] @Query = N'folate', @PageSize = 10;
SELECT @n = COUNT(*) FROM @search;
INSERT @results VALUES ('admin search finds by body text', CONCAT(@n, ' hit'),
    CASE WHEN @n >= 1 THEN 'PASS' ELSE 'FAIL' END);

-- 15 -----------------------------------------------------------------------
DELETE @search;
INSERT @search EXEC [Content].[usp_Content_Search] @Status = 'published', @PageSize = 50;
SELECT @n = COUNT(*) FROM @search WHERE IsDeleted = 1;
INSERT @results VALUES ('search excludes deleted by default', CONCAT(@n, ' deleted shown'),
    CASE WHEN @n = 0 THEN 'PASS' ELSE 'FAIL' END);

DROP TABLE #saved;
DROP TABLE #client;

SELECT Seq, Assertion, Detail, Outcome FROM @results ORDER BY Seq;

DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');
SELECT CONCAT('TOTAL: ', (SELECT COUNT(*) FROM @results), '  FAILED: ', @failed) AS Summary;
IF @failed > 0 RAISERROR('CMS workflow assertions failed.', 16, 1);
GO
