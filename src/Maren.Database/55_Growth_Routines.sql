/*  55_Growth_Routines.sql

    The Personal Growth Platform: routines.

    A routine is several behaviours done together - a wind-down, a morning, a
    study block. The platform already models exactly that: a Behaviour subject
    of kind 'routine', with required parts and a rule for how many make a day
    count. evening_routine has been one since Behaviour Intelligence shipped.

    So this schema is deliberately thin, and that thinness is the point
    ----------------------------------------------------------------------
    A routine here does NOT own a step list. It points at a Behaviour subject
    and the composition lives there, once. Two step lists would be two answers
    to "what is in my evening routine", and the day they disagree is the day her
    checklist shows four steps while her streak is computed from three.

    What a routine adds is everything Behaviour deliberately has no opinion
    about: when in the day it belongs, what it is called when presented to her,
    why it exists, and who it is offered to. Those are presentation and
    planning concerns, and putting a time-of-day window on Behaviour.Subject
    would give 'hydration' a column that is always null and push presentation
    into the observation layer.

    Completion comes only from the timeline
    ---------------------------------------
    There is no percentage column here, no "mark complete", no manual progress.
    Whether a routine was done is derived from logged events by
    Behaviour.fn_Read, and which steps are done today by Behaviour.fn_ReadSteps.
    growth_routines_test.sql fails if this schema reaches past those interfaces.

    Applicability
    -------------
    Rules.fn_Match under a 'routine' scope, like content, dashboard cards and
    goals. A postpartum routine is a rule row. A fourth applicability mechanism
    would be a fourth place life stage is interpreted.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- Routine
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Growth.Routine') IS NULL
BEGIN
    CREATE TABLE [Growth].[Routine] (
        RoutineKey    VARCHAR(40)  NOT NULL,
        DisplayName   NVARCHAR(80) NOT NULL,

        /*  The Behaviour subject that observes it. This is the whole
            single-source decision in one column: composition, required parts
            and the done-today rule all live on the subject, and a routine
            cannot exist without one to observe it. */
        SubjectKey    VARCHAR(40)  NOT NULL,

        /*  Why it exists, in the platform's words. */
        PurposeText   NVARCHAR(300) NOT NULL,

        DomainCode    VARCHAR(30)  NOT NULL,

        /*  The part of the day it belongs to. Local hours, inclusive start and
            exclusive end, because a routine is a time of day rather than a
            deadline - "your evening" is 20:00 to midnight, not "by 23:59".

            A window that wraps midnight is allowed: a night routine may run
            22:00 to 02:00, and refusing that would be the schema deciding when
            a woman's day ends. */
        StartHour     TINYINT NOT NULL,
        EndHour       TINYINT NOT NULL,

        /*  What to call the window when telling her. Derived text would have to
            guess between "evening", "before bed" and "tonight". */
        WindowText    NVARCHAR(40) NOT NULL,

        BasePriority  INT NOT NULL CONSTRAINT DF_Routine_BasePriority DEFAULT 50,

        IsHealthSensitive BIT NOT NULL
            CONSTRAINT DF_Routine_IsHealthSensitive DEFAULT 0,

        SortOrder     INT NOT NULL,
        IsActive      BIT NOT NULL CONSTRAINT DF_Routine_IsActive DEFAULT 1,

        CONSTRAINT PK_Routine PRIMARY KEY CLUSTERED (RoutineKey),

        CONSTRAINT CK_Routine_Hours
            CHECK (StartHour BETWEEN 0 AND 23 AND EndHour BETWEEN 0 AND 24),

        /*  A zero-length window would make a routine that is never due. */
        CONSTRAINT CK_Routine_WindowNotEmpty CHECK (StartHour <> EndHour),

        CONSTRAINT CK_Routine_Priority CHECK (BasePriority BETWEEN 0 AND 100),

        CONSTRAINT FK_Routine_Subject FOREIGN KEY (SubjectKey)
            REFERENCES [Behaviour].[Subject] (SubjectKey),

        CONSTRAINT FK_Routine_Domain FOREIGN KEY (DomainCode)
            REFERENCES [Content].[LifeDomain] (DomainCode)
    );

    /*  Non-filtered, for the foreign keys. A reference check has to find every
        referencing row, including ones a filtered index would exclude. */
    CREATE INDEX IX_Routine_Subject
        ON [Growth].[Routine] (SubjectKey) INCLUDE (DisplayName, SortOrder);
    CREATE INDEX IX_Routine_Domain
        ON [Growth].[Routine] (DomainCode) INCLUDE (DisplayName);
END
GO

/*  A routine must observe a subject that is actually a routine.

    Pointing one at 'hydration' - an event subject with one part - would produce
    a "routine" that is complete the moment she logs a glass of water. Enforced
    as a trigger rather than a check constraint because the condition lives on
    another table, and a comment saying "please only use routine subjects" is
    not a constraint. */
IF OBJECT_ID('Growth.tr_Routine_SubjectMustBeRoutine') IS NOT NULL
    DROP TRIGGER [Growth].[tr_Routine_SubjectMustBeRoutine];
GO
CREATE TRIGGER [Growth].[tr_Routine_SubjectMustBeRoutine]
ON [Growth].[Routine]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN [Behaviour].[Subject] s ON s.SubjectKey = i.SubjectKey
        WHERE s.SubjectKind <> 'routine')
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 51100,
            'A routine must observe a Behaviour subject of kind ''routine''. An event subject would complete on a single logged event.',
            1;
    END
END
GO

-- ---------------------------------------------------------------------------
-- Applicability: the same matcher, a new scope
-- ---------------------------------------------------------------------------
MERGE [Rules].[TargetScope] AS target
USING (VALUES
    ('routine', N'Routine',
     'Growth.Routine', 'RoutineKey',
     N'Which routines the platform offers, by life stage, role, country and '
     + N'language. A postpartum routine is a rule row like every other '
     + N'targeting decision in the platform.', 50)
) AS source (ScopeCode, DisplayName, TargetTable, TargetColumn, [Description], SortOrder)
    ON target.ScopeCode = source.ScopeCode
WHEN NOT MATCHED THEN
    INSERT (ScopeCode, DisplayName, TargetTable, TargetColumn, [Description], SortOrder)
    VALUES (source.ScopeCode, source.DisplayName, source.TargetTable,
            source.TargetColumn, source.[Description], source.SortOrder);
GO

-- ---------------------------------------------------------------------------
-- Seed
-- ---------------------------------------------------------------------------
/*  Only where the Behaviour subject exists and is a routine. A routine seeded
    against a missing subject would be a routine nothing can observe - which is
    the exact failure this design exists to prevent, so it must not be created
    by the seed either. */
MERGE [Growth].[Routine] AS target
USING (VALUES
    ('evening_winddown', N'Evening wind-down', 'evening_routine',
     N'Finish the day the same way often enough that it stops taking effort.',
     'lifestyle', 20, 24, N'this evening', 60, 0, 10)
) AS source (RoutineKey, DisplayName, SubjectKey, PurposeText, DomainCode,
             StartHour, EndHour, WindowText, BasePriority, IsHealthSensitive,
             SortOrder)
    ON target.RoutineKey = source.RoutineKey
WHEN NOT MATCHED AND EXISTS (
        SELECT 1 FROM [Behaviour].[Subject] s
        WHERE s.SubjectKey = source.SubjectKey AND s.SubjectKind = 'routine')
     AND EXISTS (
        SELECT 1 FROM [Content].[LifeDomain] d
        WHERE d.DomainCode = source.DomainCode) THEN
    INSERT (RoutineKey, DisplayName, SubjectKey, PurposeText, DomainCode,
            StartHour, EndHour, WindowText, BasePriority, IsHealthSensitive,
            SortOrder)
    VALUES (source.RoutineKey, source.DisplayName, source.SubjectKey,
            source.PurposeText, source.DomainCode, source.StartHour,
            source.EndHour, source.WindowText, source.BasePriority,
            source.IsHealthSensitive, source.SortOrder);
GO

PRINT 'Personal Growth Platform — routines schema ready.';
GO
