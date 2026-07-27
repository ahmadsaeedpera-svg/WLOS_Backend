SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Scheduled publish verification.

    usp_Content_Publish refuses to publish a version nobody approved. The
    whole CMS is built around that rule: clients read approved snapshots, and
    in a health product an unreviewed sentence reaching a device is a clinical
    safety problem before it is a workflow one.

    A scheduled publish must obey the same rule. It is the same act, deferred.
    These assertions exist because it did not: usp_Content_RunDueSchedules
    published without consulting ContentApproval at all, and the only reason
    it never caused harm is that nothing has ever called it.

    They also pin the version actually published. The runner used to write
    COALESCE(PublishedVersionId, CurrentVersionId), which for an item that had
    been published before resolves to the version already live - so an editor
    scheduling their new draft got a silent no-op.

    Run: sqlcmd -S "$SERVER" -d "$DB" -i tests/scheduled_publish_test.sql -I

    Expect: TOTAL: 6  FAILED: 0
*/

SET NOCOUNT ON;

DECLARE @results TABLE (Seq INT IDENTITY(1,1), Assertion NVARCHAR(200),
                        Detail NVARCHAR(200), Outcome CHAR(4));

DECLARE @actor UNIQUEIDENTIFIER = (SELECT TOP 1 UserId FROM [Identity].[User]);
DECLARE @unapproved UNIQUEIDENTIFIER, @approved UNIQUEIDENTIFIER;
DECLARE @v UNIQUEIDENTIFIER, @v2 UNIQUEIDENTIFIER;
DECLARE @status VARCHAR(20), @schedStatus VARCHAR(20), @published UNIQUEIDENTIFIER;

CREATE TABLE #saved (ContentItemId UNIQUEIDENTIFIER,
                     ContentVersionId UNIQUEIDENTIFIER, VersionNumber INT);

/*  Re-runnable: ON DELETE CASCADE clears versions, approvals and schedules. */
DELETE FROM [Content].[ContentItem]
WHERE [Key] IN ('sched-unapproved', 'sched-approved', 'sched-republish');

-- 1 -------------------------------------------------------------------------
-- An unapproved item whose publish falls due must not be published.
DELETE #saved;
INSERT #saved EXEC [Content].[usp_Content_Save]
    @ContentType = 'article', @Key = 'sched-unapproved', @CategoryKey = 'nutrition',
    @LocalizationsJson = N'[{"languageCode":"en-GB","title":"Not reviewed","body":"Draft text."}]',
    @ChangeSummary = 'Draft', @ActorUserId = @actor;
SELECT @unapproved = ContentItemId FROM #saved;

EXEC [Content].[usp_Content_Schedule]
    @ContentItemId = @unapproved, @Action = 'publish',
    @ScheduledUtc = '2020-01-01T00:00:00', @ActorUserId = @actor;

EXEC [Content].[usp_Content_RunDueSchedules] @BatchSize = 50;

SELECT @status = Status, @published = PublishedVersionId
FROM [Content].[ContentItem] WHERE ContentItemId = @unapproved;

INSERT @results VALUES ('unapproved item is not published by the scheduler',
    CONCAT('status=', @status),
    CASE WHEN @status <> 'published' THEN 'PASS' ELSE 'FAIL' END);

-- 2 -------------------------------------------------------------------------
INSERT @results VALUES ('unapproved item gets no published version',
    CONCAT('publishedVersionId=', ISNULL(CONVERT(NVARCHAR(50), @published), '(null)')),
    CASE WHEN @published IS NULL THEN 'PASS' ELSE 'FAIL' END);

-- 3 -------------------------------------------------------------------------
-- The schedule must record why it did not run, not silently claim success.
SELECT @schedStatus = Status FROM [Content].[ContentPublishSchedule]
WHERE ContentItemId = @unapproved;

INSERT @results VALUES ('refused schedule is marked failed, not executed',
    CONCAT('schedule status=', @schedStatus),
    CASE WHEN @schedStatus = 'failed' THEN 'PASS' ELSE 'FAIL' END);

-- 4 -------------------------------------------------------------------------
-- The refusal must say why, so an editor can act on it.
DECLARE @reason NVARCHAR(500) = (
    SELECT FailureReason FROM [Content].[ContentPublishSchedule]
    WHERE ContentItemId = @unapproved);

INSERT @results VALUES ('refused schedule records a reason',
    ISNULL(@reason, '(null)'),
    CASE WHEN @reason IS NOT NULL THEN 'PASS' ELSE 'FAIL' END);

-- 5 -------------------------------------------------------------------------
-- An approved item must publish normally. The gate must not block real work.
DELETE #saved;
INSERT #saved EXEC [Content].[usp_Content_Save]
    @ContentType = 'article', @Key = 'sched-approved', @CategoryKey = 'nutrition',
    @LocalizationsJson = N'[{"languageCode":"en-GB","title":"Reviewed","body":"Approved text."}]',
    @ChangeSummary = 'Draft', @ActorUserId = @actor;
SELECT @approved = ContentItemId, @v = ContentVersionId FROM #saved;

EXEC [Content].[usp_Content_Approve]
    @ContentItemId = @approved, @ContentVersionId = @v,
    @IsApproved = 1, @ActorUserId = @actor;

EXEC [Content].[usp_Content_Schedule]
    @ContentItemId = @approved, @Action = 'publish',
    @ScheduledUtc = '2020-01-01T00:00:00', @ActorUserId = @actor;

EXEC [Content].[usp_Content_RunDueSchedules] @BatchSize = 50;

SELECT @status = Status FROM [Content].[ContentItem] WHERE ContentItemId = @approved;

INSERT @results VALUES ('approved item is published by the scheduler',
    CONCAT('status=', @status),
    CASE WHEN @status = 'published' THEN 'PASS' ELSE 'FAIL' END);

-- 6 -------------------------------------------------------------------------
-- A second, approved edit must go live - not the version already published.
DELETE #saved;
INSERT #saved EXEC [Content].[usp_Content_Save]
    @ContentItemId = @approved,
    @ContentType = 'article', @Key = 'sched-approved', @CategoryKey = 'nutrition',
    @LocalizationsJson = N'[{"languageCode":"en-GB","title":"Reviewed","body":"Second approved text."}]',
    @ChangeSummary = 'Second draft', @ActorUserId = @actor;
SELECT @v2 = ContentVersionId FROM #saved;

EXEC [Content].[usp_Content_Approve]
    @ContentItemId = @approved, @ContentVersionId = @v2,
    @IsApproved = 1, @ActorUserId = @actor;

EXEC [Content].[usp_Content_Schedule]
    @ContentItemId = @approved, @Action = 'publish',
    @ScheduledUtc = '2020-01-01T00:00:00', @ActorUserId = @actor;

EXEC [Content].[usp_Content_RunDueSchedules] @BatchSize = 50;

SELECT @published = PublishedVersionId
FROM [Content].[ContentItem] WHERE ContentItemId = @approved;

INSERT @results VALUES ('scheduler publishes the newest approved version',
    CASE WHEN @published = @v2 THEN 'newest'
         WHEN @published = @v  THEN 'stale (still v1)'
         ELSE '(unexpected)' END,
    CASE WHEN @published = @v2 THEN 'PASS' ELSE 'FAIL' END);

-- Report --------------------------------------------------------------------
SELECT RIGHT('  ' + CAST(Seq AS varchar(3)), 3) + ' ' +
       LEFT(Assertion + REPLICATE('.', 70), 70) + ' ' +
       LEFT(ISNULL(Detail, '') + REPLICATE(' ', 34), 34) + ' ' + Outcome
FROM @results ORDER BY Seq;

DECLARE @total INT = (SELECT COUNT(*) FROM @results);
DECLARE @failed INT = (SELECT COUNT(*) FROM @results WHERE Outcome = 'FAIL');

PRINT '';
PRINT '---------------------------------------------';
PRINT CONCAT('TOTAL: ', @total, '  FAILED: ', @failed);
PRINT '---------------------------------------------';

DROP TABLE #saved;

IF @failed > 0
    THROW 51000, 'Scheduled publish assertions failed.', 1;
GO
