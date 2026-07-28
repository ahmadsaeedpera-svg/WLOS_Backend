/*  33_Procs_Profile.sql

    Procedures for the profile and the life-stage model.

    Identity.Profile has existed since the first schema script and has never
    been readable. usp_User_Register inserts one empty row and nothing else in
    the database touches it, so DateOfBirth, TimeZoneId and DisplayName have
    been write-once-never-read since the platform was built. These procedures
    are what make the table, and the new stage model beside it, reachable at all.

    Every procedure here follows the house rules: named result columns, no
    dynamic SQL, XACT_ABORT on anything transactional, expected failures as a
    Result row rather than an exception, and audit written inside the same
    transaction as the change it describes.

    Purely additive. No existing procedure is altered.
*/

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- usp_Profile_Get
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_Profile_Get') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Profile_Get];
GO
/*  Her profile, her current stage and her modes in one call.

    Three result sets rather than three round trips: this is read on app launch,
    which is the highest-volume authenticated path in the platform, and it is
    the one place a needless round trip is paid on every session. */
CREATE PROCEDURE [Identity].[usp_Profile_Get]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        p.UserId,
        p.DisplayName,
        p.DateOfBirth,
        p.TimeZoneId,
        p.AvatarMediaId,
        u.LanguageCode,
        u.CountryId,
        p.ModifiedOn
    FROM [Identity].[Profile] p
    JOIN [Identity].[User] u ON u.UserId = p.UserId
    WHERE p.UserId = @UserId
      AND p.IsDeleted = 0;

    /*  The open row is the current one. Joined to LifeStage so the caller gets
        display copy without a second lookup and without hardcoding the codes
        in a client that ships to a store and cannot be corrected quickly. */
    SELECT
        uls.LifeStageCode,
        ls.DisplayName,
        uls.StartedOn,
        uls.Source
    FROM [Identity].[UserLifeStage] uls
    JOIN [Identity].[LifeStage] ls ON ls.LifeStageCode = uls.LifeStageCode
    WHERE uls.UserId = @UserId
      AND uls.EndedOn IS NULL;

    /*  The same four columns usp_LifeStage_List returns for a role mode, in
        the same order. A client renders her roles and the pickable roles with
        one shape, and a narrower result set here would force a second type
        that means the same thing. */
    SELECT
        urm.RoleModeCode,
        rm.DisplayName,
        rm.[Description],
        rm.SortOrder
    FROM [Identity].[UserRoleMode] urm
    JOIN [Identity].[RoleMode] rm ON rm.RoleModeCode = urm.RoleModeCode
    WHERE urm.UserId = @UserId
    ORDER BY rm.SortOrder;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Profile_Save
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_Profile_Save') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Profile_Save];
GO
/*  Updates the profile fields a woman controls.

    Every parameter is optional and NULL means "leave alone" rather than
    "clear". Onboarding sets these a few at a time as it learns them, and a
    save that blanked what it was not told would lose answers she had already
    given - the same defect the portal has on secrets today. */
CREATE PROCEDURE [Identity].[usp_Profile_Save]
    @UserId       UNIQUEIDENTIFIER,
    @DisplayName  NVARCHAR(120) = NULL,
    @DateOfBirth  DATE = NULL,
    @TimeZoneId   NVARCHAR(64) = NULL,
    @ActorUserId  UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User]
                   WHERE UserId = @UserId AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'USER_NOT_FOUND' AS FailureCode;
        RETURN;
    END

    /*  A date of birth in the future, or implying an age past any recorded
        human lifespan, is a typo rather than a fact. Refused here because the
        value drives stage suggestions and age gating downstream. */
    IF @DateOfBirth IS NOT NULL
       AND (@DateOfBirth > CAST(SYSUTCDATETIME() AS DATE)
            OR @DateOfBirth < DATEADD(YEAR, -120, CAST(SYSUTCDATETIME() AS DATE)))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_DATE_OF_BIRTH' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        /*  Defensive: the row is created at registration, but a profile that
            went missing must not make the whole call fail. */
        IF NOT EXISTS (SELECT 1 FROM [Identity].[Profile] WHERE UserId = @UserId)
            INSERT INTO [Identity].[Profile] (UserId) VALUES (@UserId);

        UPDATE [Identity].[Profile]
        SET DisplayName = COALESCE(@DisplayName, DisplayName),
            DateOfBirth = COALESCE(@DateOfBirth, DateOfBirth),
            TimeZoneId  = COALESCE(@TimeZoneId,  TimeZoneId),
            ModifiedOn  = SYSUTCDATETIME(),
            ModifiedBy  = @ActorUserId
        WHERE UserId = @UserId;

        /*  No health data in the audit trail, deliberately - the same rule the
            rest of the platform follows. That a profile changed is recorded;
            what it changed to is not. */
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@ActorUserId, 'user', 'Profile.Save', 'Profile',
             CONVERT(NVARCHAR(50), @UserId));

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_UserLifeStage_Set
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_UserLifeStage_Set') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_UserLifeStage_Set];
GO
/*  Moves her to a stage, closing the previous one.

    History is preserved rather than overwritten. The closed row keeps its dates
    so the record of where she has been survives every transition - see
    32_LifeStage.sql for why that matters more than anything else in this model.

    Setting the stage she is already in is a no-op that succeeds. Onboarding can
    be re-run, a client can retry, and neither should produce a spurious
    one-day stage in her history. */
CREATE PROCEDURE [Identity].[usp_UserLifeStage_Set]
    @UserId        UNIQUEIDENTIFIER,
    @LifeStageCode VARCHAR(30),
    @Source        VARCHAR(20) = 'user',
    @Note          NVARCHAR(300) = NULL,
    @ActorUserId   UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User]
                   WHERE UserId = @UserId AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'USER_NOT_FOUND' AS FailureCode;
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM [Identity].[LifeStage]
                   WHERE LifeStageCode = @LifeStageCode AND IsSelectable = 1)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNKNOWN_LIFE_STAGE' AS FailureCode;
        RETURN;
    END

    -- Already there. Succeed without touching the history.
    IF EXISTS (SELECT 1 FROM [Identity].[UserLifeStage]
               WHERE UserId = @UserId
                 AND LifeStageCode = @LifeStageCode
                 AND EndedOn IS NULL)
    BEGIN
        SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        DECLARE @today DATE = CAST(SYSUTCDATETIME() AS DATE);

        /*  Close the open row first. UX_UserLifeStage_Current allows only one,
            so this must happen before the insert or the index refuses it -
            which is the index doing its job. */
        UPDATE [Identity].[UserLifeStage]
        SET EndedOn = @today
        WHERE UserId = @UserId AND EndedOn IS NULL;

        INSERT INTO [Identity].[UserLifeStage]
            (UserId, LifeStageCode, StartedOn, Source, Note)
        VALUES
            (@UserId, @LifeStageCode, @today, @Source, @Note);

        /*  The stage code is recorded because it is not health data - it is a
            product state she chose, and support cannot help with "her stage
            changed" alone. */
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@ActorUserId,
             CASE WHEN @Source = 'operator' THEN 'operator' ELSE 'user' END,
             'LifeStage.Set', 'User', CONVERT(NVARCHAR(50), @UserId),
             (SELECT @LifeStageCode AS lifeStageCode, @Source AS source
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_UserLifeStage_GetHistory
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_UserLifeStage_GetHistory') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_UserLifeStage_GetHistory];
GO
/*  Her whole journey, newest first.

    Bounded: a life has a small number of stages, but a support tool correcting
    a mistake could produce many rows, and an unbounded result set is a
    denial-of-service vector however unlikely the data. */
CREATE PROCEDURE [Identity].[usp_UserLifeStage_GetHistory]
    @UserId UNIQUEIDENTIFIER,
    @Top    INT = 100
AS
BEGIN
    SET NOCOUNT ON;

    IF @Top IS NULL OR @Top < 1 SET @Top = 100;
    IF @Top > 500 SET @Top = 500;

    SELECT TOP (@Top)
        uls.UserLifeStageId,
        uls.LifeStageCode,
        ls.DisplayName,
        uls.StartedOn,
        uls.EndedOn,
        uls.Source,
        uls.Note
    FROM [Identity].[UserLifeStage] uls
    JOIN [Identity].[LifeStage] ls ON ls.LifeStageCode = uls.LifeStageCode
    WHERE uls.UserId = @UserId
    ORDER BY uls.StartedOn DESC, uls.EndedOn DESC;
END
GO

-- ---------------------------------------------------------------------------
-- usp_UserRoleMode_Set
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_UserRoleMode_Set') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_UserRoleMode_Set];
GO
/*  Replaces her role modes with the given set.

    Replace-all rather than add and remove: modes are presented as a group of
    toggles, so the client always knows the whole answer, and a partial update
    protocol would invent a synchronisation problem that the UI does not have.

    An empty list is valid and clears them. A woman who no longer wants to be
    described as a caregiver must be able to say so. */
CREATE PROCEDURE [Identity].[usp_UserRoleMode_Set]
    @UserId       UNIQUEIDENTIFIER,
    @ModeCodesJson NVARCHAR(MAX) = NULL,
    @ActorUserId  UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User]
                   WHERE UserId = @UserId AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'USER_NOT_FOUND' AS FailureCode;
        RETURN;
    END

    IF @ModeCodesJson IS NOT NULL AND ISJSON(@ModeCodesJson) = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_JSON' AS FailureCode;
        RETURN;
    END

    DECLARE @requested TABLE (RoleModeCode VARCHAR(30) PRIMARY KEY);

    IF @ModeCodesJson IS NOT NULL
        INSERT INTO @requested (RoleModeCode)
        SELECT DISTINCT LTRIM(RTRIM([value]))
        FROM OPENJSON(@ModeCodesJson)
        WHERE LTRIM(RTRIM([value])) <> '';

    /*  Refuse the whole call on an unknown code rather than silently dropping
        it. A client sending a mode this database has never heard of has a bug,
        and discarding it quietly turns that into a support ticket about a
        toggle that will not stay on. */
    IF EXISTS (SELECT 1 FROM @requested r
               WHERE NOT EXISTS (SELECT 1 FROM [Identity].[RoleMode] m
                                 WHERE m.RoleModeCode = r.RoleModeCode))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNKNOWN_ROLE_MODE' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        DELETE urm
        FROM [Identity].[UserRoleMode] urm
        WHERE urm.UserId = @UserId
          AND NOT EXISTS (SELECT 1 FROM @requested r
                          WHERE r.RoleModeCode = urm.RoleModeCode);

        INSERT INTO [Identity].[UserRoleMode] (UserId, RoleModeCode)
        SELECT @UserId, r.RoleModeCode
        FROM @requested r
        WHERE NOT EXISTS (SELECT 1 FROM [Identity].[UserRoleMode] urm
                          WHERE urm.UserId = @UserId
                            AND urm.RoleModeCode = r.RoleModeCode);

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@ActorUserId, 'user', 'RoleMode.Set', 'User',
             CONVERT(NVARCHAR(50), @UserId));

    COMMIT;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_LifeStage_List
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Identity.usp_LifeStage_List') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_LifeStage_List];
GO
/*  The pickers for onboarding. Two result sets, one call: onboarding needs both
    and asking twice on the first screen a woman ever sees is a poor trade. */
CREATE PROCEDURE [Identity].[usp_LifeStage_List]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT LifeStageCode, DisplayName, [Description], SortOrder
    FROM [Identity].[LifeStage]
    WHERE IsSelectable = 1
    ORDER BY SortOrder;

    SELECT RoleModeCode, DisplayName, [Description], SortOrder
    FROM [Identity].[RoleMode]
    ORDER BY SortOrder;
END
GO
