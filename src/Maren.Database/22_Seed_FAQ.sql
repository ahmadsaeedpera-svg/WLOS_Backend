/*  22_Seed_FAQ.sql
    ---------------------------------------------------------------------------
    FAQ topic categories, and a starter set of published FAQ content.

    FAQ needs no new schema — it rides the generic content pipeline. What it
    needs is topic categories to group by (Content.Category holds wellness
    groups today, which are the wrong buckets for help content) and some real
    content to launch with.

    Both are data. The categories are rows an operator can extend through the
    existing category administration; the content is authored, approved and
    published through the same procedures the CMS portal calls, so this seed is
    also a rehearsal of the operator's own authoring path.

    Re-runnable: categories MERGE, content is created only if its key is absent.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

-- FAQ topic categories --------------------------------------------------------
MERGE [Content].[Category] AS target
USING (VALUES
    ('faq.gettingStarted', 10),
    ('faq.tracking',       20),
    ('faq.privacy',        30),
    ('faq.account',        40)
) AS source ([Key], SortOrder) ON target.[Key] = source.[Key]
WHEN NOT MATCHED THEN
    INSERT ([Key], SortOrder, IsActive)
    VALUES (source.[Key], source.SortOrder, 1);
GO

-- Starter FAQ content ---------------------------------------------------------
/*  Each entry is authored -> approved -> published in one pass, exactly as an
    operator would through the portal. Skipped if the key already exists, so a
    re-run does not duplicate or overwrite an operator's later edits. */
DECLARE @actor UNIQUEIDENTIFIER =
    (SELECT TOP 1 UserId FROM [Identity].[User]
     WHERE Email = 'portal-admin@maren.local' AND IsDeleted = 0);

/*  A system actor is acceptable for a seed, but if the bootstrap admin exists
    we attribute to them so the audit trail is honest about who published. */

DECLARE @faq TABLE (
    [Key] VARCHAR(150), CategoryKey VARCHAR(64), Weight INT,
    Question NVARCHAR(400), Answer NVARCHAR(MAX));

INSERT INTO @faq VALUES
    ('faq.whatIsMaren', 'faq.gettingStarted', 100,
     N'What is Maren?',
     N'Maren is a companion for pregnancy and maternal wellness. It helps you '
     + N'track how you are feeling, prepare for birth, and read guidance '
     + N'written and reviewed by people who know the subject.'),
    ('faq.offline', 'faq.gettingStarted', 90,
     N'Does Maren work without a connection?',
     N'Yes. Everything you track is stored on your device and stays usable '
     + N'with no signal. Maren downloads its guidance and settings when it can '
     + N'reach the internet, but nothing you enter is ever uploaded.'),
    ('faq.dataLeaveDevice', 'faq.privacy', 100,
     N'Does anything I track leave my phone?',
     N'No. Symptoms, dates, notes and measurements are stored only on your '
     + N'device. Maren downloads content from our servers but never sends your '
     + N'personal information back.'),
    ('faq.exportData', 'faq.account', 100,
     N'Can I move my data to a new phone?',
     N'Yes. In Settings, under "Export, restore or delete", you can save an '
     + N'archive of everything you have tracked and restore it on another '
     + N'device.'),
    ('faq.trackKicks', 'faq.tracking', 100,
     N'How do I count kicks?',
     N'Open the Track tab and choose Kick counter. Tap once for each movement '
     + N'you feel. Maren records the session so you can look back at it later.'),
    ('faq.contractions', 'faq.tracking', 90,
     N'How does the contraction timer work?',
     N'On the Track tab, choose Contraction timer and tap to start and stop '
     + N'each contraction. Maren shows the length and the gap between them, and '
     + N'you can export a summary to share with your midwife.');

DECLARE @key VARCHAR(150), @cat VARCHAR(64), @w INT,
        @q NVARCHAR(400), @a NVARCHAR(MAX);
DECLARE @id UNIQUEIDENTIFIER, @vid UNIQUEIDENTIFIER;
DECLARE @saved TABLE (ContentItemId UNIQUEIDENTIFIER, ContentVersionId UNIQUEIDENTIFIER, VersionNumber INT);
DECLARE @res TABLE (Succeeded BIT, FailureCode VARCHAR(40));

DECLARE faq_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT [Key], CategoryKey, Weight, Question, Answer FROM @faq;
OPEN faq_cursor;
FETCH NEXT FROM faq_cursor INTO @key, @cat, @w, @q, @a;

WHILE @@FETCH_STATUS = 0
BEGIN
    IF NOT EXISTS (SELECT 1 FROM [Content].[ContentItem] WHERE [Key] = @key)
    BEGIN
        -- FOR JSON PATH (no WITHOUT_ARRAY_WRAPPER) yields the [{...}] array the
        -- proc's OPENJSON expects, and escapes the quotes and apostrophes in
        -- the answers correctly. Built into a variable first because a stored
        -- procedure parameter cannot take a subquery expression directly.
        DECLARE @json NVARCHAR(MAX) =
            (SELECT 'en-GB' AS languageCode, @q AS title, @a AS body
             FOR JSON PATH);

        DELETE @saved;
        INSERT @saved EXEC [Content].[usp_Content_Save]
            @ContentType = 'faq', @Key = @key, @CategoryKey = @cat, @Weight = @w,
            @LocalizationsJson = @json,
            @ChangeSummary = 'FAQ seed', @ActorUserId = @actor;

        SELECT @id = ContentItemId, @vid = ContentVersionId FROM @saved;

        DELETE @res;
        INSERT @res EXEC [Content].[usp_Content_Approve]
            @ContentItemId = @id, @ContentVersionId = @vid,
            @IsApproved = 1, @Reason = 'FAQ seed', @ActorUserId = @actor;

        DELETE @res;
        INSERT @res EXEC [Content].[usp_Content_Publish]
            @ContentItemId = @id, @ActorUserId = @actor;
    END

    FETCH NEXT FROM faq_cursor INTO @key, @cat, @w, @q, @a;
END
CLOSE faq_cursor;
DEALLOCATE faq_cursor;

SELECT CONCAT('FAQ published: ',
    (SELECT COUNT(*) FROM [Content].[ContentItem]
     WHERE ContentType = 'faq' AND Status = 'published')) AS Result;
GO
