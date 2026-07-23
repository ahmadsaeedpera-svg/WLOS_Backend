/*  16_ContentTaxonomy.sql
    ---------------------------------------------------------------------------
    Widens the ContentType check constraint to the enterprise taxonomy.

    ContentType maps to a RENDERER in the app — a dailyTip draws differently
    from an faq from a banner. It is an engineering-bounded set, not something
    an operator invents at runtime, so a CHECK constraint is the right guard:
    an unknown type has no renderer and must never reach a device.

    The constraint and the C# ContentCatalog.All list are two representations
    of one fact. A test (ContentTaxonomyTests) asserts they agree, so widening
    one without the other fails the build rather than silently rejecting valid
    content at the database.

    Re-runnable: drops the existing constraint by name if present, then adds the
    current definition.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_ContentItem_Type')
    ALTER TABLE [Content].[ContentItem] DROP CONSTRAINT CK_ContentItem_Type;
GO

ALTER TABLE [Content].[ContentItem] WITH CHECK
ADD CONSTRAINT CK_ContentItem_Type CHECK (ContentType IN (
    -- Home and journey
    'homeBanner', 'homeCard', 'dailyTip', 'weeklyText', 'journeyCard', 'article',
    -- Guidance
    'faq', 'wellnessSnippet', 'insightTopic', 'trimesterContent', 'symptomInfo',
    'coachMessage',
    -- Lifecycle copy
    'onboardingPage', 'greeting', 'seasonalNote', 'challenge', 'encouragement',
    'achievement',
    -- System surfaces
    'emptyState', 'errorMessage', 'loadingMessage', 'successMessage',
    'offlineMessage', 'dialog', 'banner', 'calendarHelp', 'releaseNote',
    -- Notifications
    'notificationCopy',
    -- Legal and safety
    'legal', 'privacy', 'terms', 'disclaimer', 'emergency',
    -- Templates
    'hospitalBagTemplate', 'birthPreferenceOption'
));
GO

PRINT 'Content taxonomy constraint widened.';
GO
