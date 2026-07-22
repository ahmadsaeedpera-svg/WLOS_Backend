/* Required for filtered indexes and indexes on computed columns. Set here
   rather than relying on the client, so the scripts deploy identically from
   sqlcmd, SSMS, Azure Data Studio or a CI runner. */
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/*
    Administration procedures.
*/

-- ---------------------------------------------------------------------------
-- usp_FeatureFlag_Evaluate
-- ---------------------------------------------------------------------------
/*
    Resolves every flag for one caller in a single round trip.

    ## Why assignment is hashed, not random

    A percentage rollout implemented with RAND() re-rolls on every call, so a
    user sees the feature, closes the app, and it is gone. Hashing the user id
    with the flag key gives a stable bucket: the same user always lands in the
    same position, and raising the percentage only ever adds users.

    HASHBYTES over (key + userId) rather than a checksum, because CHECKSUM
    clusters badly on sequential GUIDs and would put most of a cohort in the
    same bucket.

    ## Why assignments are persisted

    Only for A/B variants. Percentage inclusion is recomputed each time and is
    stable by construction; a variant is written once so that changing the
    weights later cannot move users between arms mid-experiment.
*/
IF OBJECT_ID('Administration.usp_FeatureFlag_Evaluate') IS NOT NULL
    DROP PROCEDURE [Administration].[usp_FeatureFlag_Evaluate];
GO
CREATE PROCEDURE [Administration].[usp_FeatureFlag_Evaluate]
    @UserId         UNIQUEIDENTIFIER = NULL,
    @AppVersionCode INT = NULL,
    @CountryIso     CHAR(2) = NULL,
    @IsPremium      BIT = 0,
    @IsBeta         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        f.[Key],
        CAST(
            CASE
                WHEN f.IsEnabled = 0 THEN 0

                /*  A build too old to render the feature must not be told it
                    is on, or it shows a broken screen. */
                WHEN f.MinAppVersion IS NOT NULL
                     AND @AppVersionCode IS NOT NULL
                     AND @AppVersionCode <
                         [Administration].[fn_VersionToCode](f.MinAppVersion)
                    THEN 0

                WHEN f.CountryFilter IS NOT NULL
                     AND (@CountryIso IS NULL
                          OR NOT EXISTS (
                              SELECT 1 FROM OPENJSON(f.CountryFilter)
                              WHERE [value] = @CountryIso))
                    THEN 0

                WHEN f.RequiresPremium = 1 AND @IsPremium = 0 THEN 0
                WHEN f.BetaOnly = 1 AND @IsBeta = 0 THEN 0

                WHEN f.RolloutPercent >= 100 THEN 1
                WHEN f.RolloutPercent <= 0 THEN 0

                /*  Anonymous callers get the flag only at full rollout —
                    handled above — because there is no stable identity to
                    bucket them by. */
                WHEN @UserId IS NULL THEN 0

                WHEN (
                    ABS(CHECKSUM(
                        HASHBYTES('SHA2_256',
                            CONCAT(f.[Key], '|', CONVERT(CHAR(36), @UserId)))
                    )) % 100
                ) < f.RolloutPercent THEN 1

                ELSE 0
            END
        AS BIT) AS IsEnabled,
        f.DefaultValue,
        a.VariantId,
        v.[Key] AS VariantKey,
        v.PayloadJson
    FROM [Administration].[FeatureFlag] f
    LEFT JOIN [Administration].[FeatureFlagAssignment] a
           ON a.FeatureFlagId = f.FeatureFlagId
          AND a.UserId = @UserId
    LEFT JOIN [Administration].[FeatureFlagVariant] v
           ON v.VariantId = a.VariantId
    ORDER BY f.[Key];
END
GO

-- ---------------------------------------------------------------------------
-- fn_VersionToCode
-- ---------------------------------------------------------------------------
/*
    Turns "1.4.12" into a comparable integer.

    String comparison gets this wrong in the way that matters: "1.10.0" sorts
    before "1.9.0", so a minimum-version gate would let through exactly the
    builds it was meant to block.
*/
IF OBJECT_ID('Administration.fn_VersionToCode') IS NOT NULL
    DROP FUNCTION [Administration].[fn_VersionToCode];
GO
CREATE FUNCTION [Administration].[fn_VersionToCode](@Version NVARCHAR(20))
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    IF @Version IS NULL RETURN 0;

    DECLARE @major INT = 0, @minor INT = 0, @patch INT = 0;
    DECLARE @p1 INT = CHARINDEX('.', @Version);
    DECLARE @p2 INT = CASE WHEN @p1 > 0
                           THEN CHARINDEX('.', @Version, @p1 + 1) ELSE 0 END;

    IF @p1 = 0
        SET @major = TRY_CAST(@Version AS INT);
    ELSE
    BEGIN
        SET @major = TRY_CAST(LEFT(@Version, @p1 - 1) AS INT);
        IF @p2 = 0
            SET @minor = TRY_CAST(SUBSTRING(@Version, @p1 + 1, 20) AS INT);
        ELSE
        BEGIN
            SET @minor = TRY_CAST(
                SUBSTRING(@Version, @p1 + 1, @p2 - @p1 - 1) AS INT);
            SET @patch = TRY_CAST(
                SUBSTRING(@Version, @p2 + 1, 20) AS INT);
        END
    END

    RETURN (ISNULL(@major,0) * 1000000)
         + (ISNULL(@minor,0) * 1000)
         +  ISNULL(@patch,0);
END
GO

-- ---------------------------------------------------------------------------
-- usp_FeatureFlag_Upsert
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Administration.usp_FeatureFlag_Upsert') IS NOT NULL
    DROP PROCEDURE [Administration].[usp_FeatureFlag_Upsert];
GO
CREATE PROCEDURE [Administration].[usp_FeatureFlag_Upsert]
    @Key            VARCHAR(100),
    @Name           NVARCHAR(200),
    @Description    NVARCHAR(1000) = NULL,
    @IsEnabled      BIT,
    @RolloutPercent TINYINT = 0,
    @MinAppVersion  NVARCHAR(20) = NULL,
    @CountryFilter  NVARCHAR(MAX) = NULL,
    @RequiresPremium BIT = 0,
    @BetaOnly       BIT = 0,
    @DefaultValue   BIT = 0,
    @ActorUserId    UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @before NVARCHAR(MAX);

    BEGIN TRAN;

        SELECT @before = (
            SELECT * FROM [Administration].[FeatureFlag]
            WHERE [Key] = @Key FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        MERGE [Administration].[FeatureFlag] AS target
        USING (SELECT @Key AS [Key]) AS source
           ON target.[Key] = source.[Key]
        WHEN MATCHED THEN UPDATE SET
            Name = @Name,
            Description = @Description,
            IsEnabled = @IsEnabled,
            RolloutPercent = @RolloutPercent,
            MinAppVersion = @MinAppVersion,
            CountryFilter = @CountryFilter,
            RequiresPremium = @RequiresPremium,
            BetaOnly = @BetaOnly,
            DefaultValue = @DefaultValue,
            ModifiedUtc = SYSUTCDATETIME(),
            ModifiedBy = @ActorUserId
        WHEN NOT MATCHED THEN INSERT
            ([Key], Name, Description, IsEnabled, RolloutPercent,
             MinAppVersion, CountryFilter, RequiresPremium, BetaOnly,
             DefaultValue, ModifiedBy)
            VALUES
            (@Key, @Name, @Description, @IsEnabled, @RolloutPercent,
             @MinAppVersion, @CountryFilter, @RequiresPremium, @BetaOnly,
             @DefaultValue, @ActorUserId);

        /*  Toggling a flag changes what every user sees. It is audited for the
            same reason a permission change is. */
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId,
             BeforeJson, AfterJson)
        SELECT
            @ActorUserId, 'admin', 'FeatureFlag.Upsert', 'FeatureFlag', @Key,
            @before,
            (SELECT * FROM [Administration].[FeatureFlag]
             WHERE [Key] = @Key FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    COMMIT TRAN;

    /*  Named columns, matching FeatureFlagAdminDto exactly.

        SELECT * returned all fifteen columns for a twelve-field record, and
        Dapper cannot materialise a positional record from a wider result set —
        so this endpoint returned 500 on every call. Listing the columns means
        adding one to the table is a compile-time conversation rather than a
        runtime failure, and it keeps RowVersion and ModifiedBy off the wire. */
    SELECT
        FeatureFlagId, [Key], Name, Description, IsEnabled, RolloutPercent,
        MinAppVersion, CountryFilter, RequiresPremium, BetaOnly, DefaultValue,
        ModifiedUtc
    FROM [Administration].[FeatureFlag]
    WHERE [Key] = @Key;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Settings_GetForClient
-- ---------------------------------------------------------------------------
/*
    Only rows explicitly marked client-visible, and never a secret.

    Two filters rather than one. IsClientVisible is the intent; the IsSecret
    check is the backstop for a row where somebody set the first flag without
    thinking about the second.
*/
IF OBJECT_ID('Administration.usp_Settings_GetForClient') IS NOT NULL
    DROP PROCEDURE [Administration].[usp_Settings_GetForClient];
GO
CREATE PROCEDURE [Administration].[usp_Settings_GetForClient]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT [Key], [Value], DataType
    FROM [Administration].[Setting]
    WHERE IsClientVisible = 1 AND IsSecret = 0
    ORDER BY [Key];
END
GO

-- ---------------------------------------------------------------------------
-- usp_AppVersion_Check
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Administration.usp_AppVersion_Check') IS NOT NULL
    DROP PROCEDURE [Administration].[usp_AppVersion_Check];
GO
CREATE PROCEDURE [Administration].[usp_AppVersion_Check]
    @Platform    VARCHAR(20),
    @VersionCode INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @minCode INT = (
        SELECT MAX(BuildNumber) FROM [Administration].[AppVersion]
        WHERE Platform = @Platform AND IsMinimumSupported = 1);

    SELECT
        CAST(CASE WHEN @minCode IS NOT NULL AND @VersionCode < @minCode
                  THEN 1 ELSE 0 END AS BIT) AS UpdateRequired,
        (SELECT TOP 1 [Version] FROM [Administration].[AppVersion]
         WHERE Platform = @Platform AND IsLatest = 1
         ORDER BY BuildNumber DESC) AS LatestVersion,
        (SELECT TOP 1 ReleaseNotes FROM [Administration].[AppVersion]
         WHERE Platform = @Platform AND IsLatest = 1
         ORDER BY BuildNumber DESC) AS ReleaseNotes;
END
GO
