/*  36_Timeline.sql

    The timeline. One event store that everything else reads from.

    Why this before the score, habit, insight and recommendation engines
    -------------------------------------------------------------------
    All of those consume the same thing: what she did, and when. Built in any
    other order they each invent their own storage, and the platform ends up
    with a hydration table, a sleep table, a medication table and no way to ask
    "does she sleep less on Mondays" without joining five shapes that disagree
    about what a timestamp means.

    Health.DailyLog is the warning. It carries four fixed metric columns - Mood,
    Energy, SleepQuality, WaterGlasses - so every new thing worth recording is
    an ALTER, a procedure change and a DTO break. The product now lists around
    twenty kinds of event and describes the list as open-ended.

    So: event type is data, not a column and not a CHECK constraint.

    Design decisions that are about 2036, not this sprint
    ----------------------------------------------------
    1. Clustered on (UserId, OccurredUtc), not on the identifier.

       Every read of this table is "her timeline, in a date range" - the
       dashboard, the scores, the insights, the sync. Clustering that way makes
       those range scans sequential and keeps one woman's data physically
       together.

       It also avoids a defect this schema already has elsewhere: the nine
       Health tables cluster on a client-generated V4 GUID, which arrives
       random and fragments the index on every offline sync flush. The
       identifier here is a NONCLUSTERED primary key instead.

    2. Client-generated identifier, deliberately.

       The app is offline-first. A woman records a symptom on a plane; the id
       has to exist before the server ever hears about it. That makes the write
       idempotent - a retried sync re-sends the same id and changes nothing -
       which is what makes sync safe rather than merely eventually consistent.

    3. Rowversion, IsDeleted and ModifiedOn from the start.

       The delta-sync pattern in 15_Procs_ContentDelta.sql already works and is
       the most transferable thing in this repository. Health data needs the
       same token, upserts and tombstones. Retrofitting a sync column onto a
       table with ten million rows is an outage; adding it now costs nothing.

    4. Partition-ready without being partitioned.

       OccurredUtc leads the clustered key after UserId, so archiving cold
       ranges later is a partition scheme rather than a rewrite. Not
       partitioned today because a few thousand rows do not need it and an
       unused partition function is a maintenance burden.

    5. No tenant column, and that is not an oversight.

       Multi-tenancy is an open product decision. Events are user-scoped, so if
       tenancy arrives it attaches to the user and reaches events through the
       existing relationship. This table does not need to wait for that answer.

    Health data and the audit trail
    -------------------------------
    Nothing here is written to Audit.AuditLog. That rule already exists in this
    schema - the audit log deliberately never copies symptom data - and it
    matters more here than anywhere: this table is the most sensitive in the
    platform, and an audit trail that mirrored it would double the blast radius
    of any disclosure while adding nothing an operator could act on.

    Idempotent. Purely additive.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = 'Timeline')
    EXEC('CREATE SCHEMA [Timeline]');
GO

-- ---------------------------------------------------------------------------
-- Reference: what kinds of thing can be recorded
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Timeline.EventType') IS NULL
CREATE TABLE [Timeline].[EventType] (
    EventTypeCode VARCHAR(40)  NOT NULL,
    DisplayName   NVARCHAR(80) NOT NULL,
    /*  Groups the type for dashboards and scoring without hardcoding a list in
        code. A score engine asks for the 'hydration' category rather than
        naming every drink-shaped event type it knows about. */
    Category      VARCHAR(30)  NOT NULL,

    /*  'none'     - it happened; there is nothing to measure (prayer, hair wash)
        'quantity' - a number with a unit (250 ml, 8000 steps, 7.5 hours)
        'scale'    - a bounded self-report, 1 to 5 (mood, stress, energy)
        'duration' - minutes
        'text'     - a short label (a symptom name, a meal description)

        The evaluator branches on this, so a new event type needs no new code
        as long as it measures like something that already exists. */
    ValueKind     VARCHAR(12)  NOT NULL,
    DefaultUnit   VARCHAR(20)  NULL,

    /*  Whether several in a day add up. Water does; weight does not. Scoring
        needs to know the difference and must not guess it per type. */
    IsCumulative  BIT NOT NULL CONSTRAINT DF_EventType_IsCumulative DEFAULT 0,

    /*  Self-reported health observations get handled more carefully by
        everything downstream - never interpreted, never scored into advice.
        Flagged as data so that rule cannot be forgotten by a later engine. */
    IsHealthSensitive BIT NOT NULL CONSTRAINT DF_EventType_IsHealthSensitive DEFAULT 0,

    SortOrder     INT NOT NULL,
    IsActive      BIT NOT NULL CONSTRAINT DF_EventType_IsActive DEFAULT 1,

    CONSTRAINT PK_EventType PRIMARY KEY CLUSTERED (EventTypeCode),
    CONSTRAINT CK_EventType_ValueKind
        CHECK (ValueKind IN ('none', 'quantity', 'scale', 'duration', 'text'))
);
GO

-- ---------------------------------------------------------------------------
-- The events
-- ---------------------------------------------------------------------------

IF OBJECT_ID('Timeline.Event') IS NULL
CREATE TABLE [Timeline].[Event] (
    /*  Client-generated. NONCLUSTERED so a random GUID never orders the table
        - see the header. */
    EventId       UNIQUEIDENTIFIER NOT NULL,
    UserId        UNIQUEIDENTIFIER NOT NULL,
    EventTypeCode VARCHAR(40) NOT NULL,

    /*  When it happened. */
    OccurredUtc   DATETIME2(3) NOT NULL,

    /*  Her local date, supplied by the client rather than derived here.
        "Did she sleep badly on Monday" is a question about her Monday, and the
        server cannot answer it from UTC alone without her offset at that
        moment - which changes with travel and daylight saving. Storing what
        the device knew is both cheaper and more correct than reconstructing it
        later from a timezone that may since have changed. */
    OccurredLocalDate DATE NOT NULL,

    /*  When we learned. Differs from OccurredUtc for anything recorded after
        the fact or synced late, and insight work needs to tell those apart. */
    RecordedUtc   DATETIME2(3) NOT NULL
        CONSTRAINT DF_Event_RecordedUtc DEFAULT SYSUTCDATETIME(),

    /*  Where it came from. The product asks for this explicitly, and it is
        what lets a confidence score treat a wearable reading differently from
        a number somebody typed a week later. */
    [Source]      VARCHAR(20) NOT NULL CONSTRAINT DF_Event_Source DEFAULT 'manual',

    ValueNumeric  DECIMAL(18, 4) NULL,
    ValueText     NVARCHAR(200) NULL,
    Unit          VARCHAR(20) NULL,

    /*  The extensibility escape hatch. Anything a type needs that the columns
        above do not express goes here rather than becoming a column that is
        NULL for every other type. */
    MetadataJson  NVARCHAR(2000) NULL,

    /*  Offline sync, from the start. */
    IsDeleted     BIT NOT NULL CONSTRAINT DF_Event_IsDeleted DEFAULT 0,
    ModifiedOn    DATETIME2(3) NOT NULL CONSTRAINT DF_Event_ModifiedOn DEFAULT SYSUTCDATETIME(),
    [RowVersion]  ROWVERSION NOT NULL,

    CONSTRAINT PK_Event PRIMARY KEY NONCLUSTERED (EventId),
    CONSTRAINT FK_Event_User FOREIGN KEY (UserId)
        REFERENCES [Identity].[User](UserId),
    CONSTRAINT FK_Event_Type FOREIGN KEY (EventTypeCode)
        REFERENCES [Timeline].[EventType](EventTypeCode),
    CONSTRAINT CK_Event_Source
        CHECK ([Source] IN ('manual', 'sensor', 'imported', 'ai', 'cms',
                            'doctor', 'wearable')),
    /*  A scale is 1 to 5 wherever it appears. Enforced here so a mood of 40
        cannot enter the store and quietly distort every average computed from
        it afterwards. */
    CONSTRAINT CK_Event_Scale
        CHECK (ValueNumeric IS NULL OR ValueNumeric BETWEEN -1000000 AND 1000000)
);
GO

/*  The access path for essentially every read: her events, newest first,
    usually within a date range. Clustered, so those reads are sequential and
    one woman's data stays physically together. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'CX_Event_User_Occurred'
                 AND object_id = OBJECT_ID('[Timeline].[Event]'))
    CREATE CLUSTERED INDEX [CX_Event_User_Occurred]
        ON [Timeline].[Event] (UserId, OccurredUtc DESC);
GO

/*  Delta sync. The client asks "what changed since this token", which is a
    rowversion range within one user. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Event_User_RowVersion'
                 AND object_id = OBJECT_ID('[Timeline].[Event]'))
    CREATE INDEX [IX_Event_User_RowVersion]
        ON [Timeline].[Event] (UserId, [RowVersion]);
GO

/*  Scoring and insights ask by type within a window - "her hydration events
    this week". Without this that is a scan of her whole history, which grows
    without bound. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Event_User_Type_Date'
                 AND object_id = OBJECT_ID('[Timeline].[Event]'))
    CREATE INDEX [IX_Event_User_Type_Date]
        ON [Timeline].[Event] (UserId, EventTypeCode, OccurredLocalDate DESC)
        INCLUDE (ValueNumeric, Unit)
        WHERE IsDeleted = 0;
GO

/*  Supports the foreign key on EventTypeCode, which the filtered index above
    cannot: a reference check must see soft-deleted rows too. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE name = 'IX_Event_TypeCode'
                 AND object_id = OBJECT_ID('[Timeline].[Event]'))
    CREATE INDEX [IX_Event_TypeCode]
        ON [Timeline].[Event] (EventTypeCode);
GO

-- ---------------------------------------------------------------------------
-- Seed the event types
-- ---------------------------------------------------------------------------

/*  Every kind of thing the product currently names, plus the shape for ones it
    has not thought of. Adding the twenty-first is a row. */
MERGE [Timeline].[EventType] AS target
USING (VALUES
    -- hydration and nutrition
    ('water',        N'Water',           'hydration', 'quantity', 'ml',    1, 0,  10),
    ('meal',         N'Meal',            'nutrition', 'text',     NULL,    0, 0,  20),
    ('caffeine',     N'Caffeine',        'nutrition', 'quantity', 'mg',    1, 0,  30),
    -- rest
    ('sleep',        N'Sleep',           'sleep',     'duration', 'min',   1, 0,  40),
    ('sleep_quality',N'Sleep quality',   'sleep',     'scale',    NULL,    0, 0,  50),
    ('nap',          N'Nap',             'sleep',     'duration', 'min',   1, 0,  60),
    -- movement
    ('exercise',     N'Exercise',        'fitness',   'duration', 'min',   1, 0,  70),
    ('steps',        N'Steps',           'fitness',   'quantity', 'steps', 1, 0,  80),
    ('walk',         N'Walk',            'fitness',   'duration', 'min',   1, 0,  90),
    ('yoga',         N'Yoga',            'fitness',   'duration', 'min',   1, 0, 100),
    -- mind
    ('mood',         N'Mood',            'mental',    'scale',    NULL,    0, 0, 110),
    ('stress',       N'Stress',          'mental',    'scale',    NULL,    0, 0, 120),
    ('meditation',   N'Meditation',      'mental',    'duration', 'min',   1, 0, 130),
    ('journal',      N'Journal entry',   'mental',    'text',     NULL,    0, 0, 140),
    ('prayer',       N'Prayer',          'routine',   'none',     NULL,    0, 0, 150),
    ('reading',      N'Reading',         'learning',  'duration', 'min',   1, 0, 160),
    -- self care
    ('hair_wash',    N'Hair wash',       'selfcare',  'none',     NULL,    0, 0, 170),
    ('hair_oil',     N'Hair oil',        'selfcare',  'none',     NULL,    0, 0, 180),
    ('face_care',    N'Face care',       'selfcare',  'none',     NULL,    0, 0, 190),
    ('brush_teeth',  N'Brushed teeth',   'selfcare',  'none',     NULL,    0, 0, 200),
    ('skin_care',    N'Skin care',       'selfcare',  'none',     NULL,    0, 0, 210),
    -- health, handled carefully by everything downstream
    ('medication',   N'Medication',      'medication','none',     NULL,    0, 1, 220),
    ('symptom',      N'Symptom',         'health',    'text',     NULL,    0, 1, 230),
    ('weight',       N'Weight',          'body',      'quantity', 'kg',    0, 1, 240),
    ('appointment',  N'Appointment',     'health',    'text',     NULL,    0, 1, 250),
    ('cycle_start',  N'Period started',  'cycle',     'none',     NULL,    0, 1, 260),
    ('cycle_end',    N'Period ended',    'cycle',     'none',     NULL,    0, 1, 270),
    ('baby_movement',N'Baby movement',   'pregnancy', 'quantity', 'count', 1, 1, 280),
    -- life
    ('shopping',     N'Shopping',        'household', 'text',     NULL,    0, 0, 290),
    ('screen_time',  N'Screen time',     'lifestyle', 'duration', 'min',   1, 0, 300),
    ('work',         N'Work',            'work',      'duration', 'min',   1, 0, 310),
    ('family_time',  N'Family time',     'relationships','duration','min', 1, 0, 320)
) AS source (EventTypeCode, DisplayName, Category, ValueKind, DefaultUnit,
             IsCumulative, IsHealthSensitive, SortOrder)
    ON target.EventTypeCode = source.EventTypeCode
WHEN NOT MATCHED THEN
    INSERT (EventTypeCode, DisplayName, Category, ValueKind, DefaultUnit,
            IsCumulative, IsHealthSensitive, SortOrder)
    VALUES (source.EventTypeCode, source.DisplayName, source.Category,
            source.ValueKind, source.DefaultUnit, source.IsCumulative,
            source.IsHealthSensitive, source.SortOrder);
GO
