/*  14_Procs_Config.sql
    ---------------------------------------------------------------------------
    Remote configuration administration.

    Administration.Setting already had a read path for clients
    (usp_Settings_GetForClient) and no way for an operator to write one. Remote
    config was therefore a table somebody had to UPDATE by hand — which is the
    same problem the role-grant runbook had before the access slice.

    ## The point of this file

    An operator changes a value here and the running mobile app picks it up on
    its next bootstrap. No APK, no store review, no waiting.

    ## Why IsClientVisible is not just a filter

    Settings hold operational values that clients must never see — internal
    endpoints, batch sizes, thresholds that reveal how detection works.
    IsClientVisible = 0 keeps them server-side, and IsSecret = 1 additionally
    masks the value in the admin UI. The client read applies BOTH as a backstop:
    a row where somebody set one flag without thinking about the other still
    does not leak.
*/
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- ---------------------------------------------------------------------------
-- usp_Setting_Search — admin list
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Administration.usp_Setting_Search') IS NOT NULL
    DROP PROCEDURE [Administration].[usp_Setting_Search];
GO
CREATE PROCEDURE [Administration].[usp_Setting_Search]
    @Query    NVARCHAR(200) = NULL,
    @Category NVARCHAR(100) = NULL,
    @Page     INT = 1,
    @PageSize INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @offset INT = (@Page - 1) * @PageSize;

    SELECT
        s.SettingId,
        s.[Key],
        /*  A secret's value never leaves the database, not even for an
            administrator. Showing it in a grid puts it in a browser cache, a
            screenshot and a support ticket. The operator can replace it; they
            cannot read it back. */
        CASE WHEN s.IsSecret = 1 THEN NULL ELSE s.[Value] END AS [Value],
        s.DataType,
        s.Category,
        s.Description,
        s.IsClientVisible,
        s.IsSecret,
        s.ModifiedOn,
        s.ModifiedBy,
        u.Email AS ModifiedByEmail,
        COUNT(*) OVER() AS TotalCount
    FROM [Administration].[Setting] s
    LEFT JOIN [Identity].[User] u ON u.UserId = s.ModifiedBy
    WHERE s.IsDeleted = 0
      AND (@Query IS NULL OR s.[Key] LIKE '%' + @Query + '%'
                          OR s.Description LIKE '%' + @Query + '%')
      AND (@Category IS NULL OR s.Category = @Category)
    ORDER BY s.Category, s.[Key]
    OFFSET @offset ROWS FETCH NEXT @PageSize ROWS ONLY;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Setting_Save
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Administration.usp_Setting_Save') IS NOT NULL
    DROP PROCEDURE [Administration].[usp_Setting_Save];
GO
CREATE PROCEDURE [Administration].[usp_Setting_Save]
    @Key             VARCHAR(100),
    @Value           NVARCHAR(MAX),
    @DataType        VARCHAR(20) = NULL,
    @Category        NVARCHAR(100) = NULL,
    @Description     NVARCHAR(500) = NULL,
    @IsClientVisible BIT = NULL,
    @IsSecret        BIT = NULL,
    @ActorUserId     UNIQUEIDENTIFIER = NULL,
    /*  Optimistic concurrency. Two operators editing the same setting is
        ordinary; silent last-write-wins on a value that changes app behaviour
        for every user is not acceptable. */
    @ExpectedRowVersion BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @exists BIT = CASE WHEN EXISTS (
        SELECT 1 FROM [Administration].[Setting]
        WHERE [Key] = @Key AND IsDeleted = 0) THEN 1 ELSE 0 END;

    IF @exists = 1 AND @ExpectedRowVersion IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM [Administration].[Setting]
                       WHERE [Key] = @Key AND RowVersion = @ExpectedRowVersion)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'VERSION_CONFLICT' AS FailureCode;
        RETURN;
    END

    /*  Type is validated here rather than only in the API. A malformed value
        reaches every client on the next bootstrap, and a client parsing "abc"
        as an integer at launch is a crash loop that no server fix can reach
        until the app is restarted. */
    DECLARE @type VARCHAR(20) = COALESCE(
        @DataType,
        (SELECT DataType FROM [Administration].[Setting] WHERE [Key] = @Key),
        'string');

    IF @type = 'int' AND TRY_CAST(@Value AS BIGINT) IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_VALUE' AS FailureCode;
        RETURN;
    END

    IF @type = 'bool' AND LOWER(@Value) NOT IN ('true', 'false', '0', '1')
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_VALUE' AS FailureCode;
        RETURN;
    END

    IF @type = 'decimal' AND TRY_CAST(@Value AS DECIMAL(18, 6)) IS NULL
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_VALUE' AS FailureCode;
        RETURN;
    END

    IF @type = 'json' AND ISJSON(@Value) <> 1
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'INVALID_VALUE' AS FailureCode;
        RETURN;
    END

    DECLARE @before NVARCHAR(MAX) = (
        SELECT [Key], [Value], DataType, IsClientVisible, IsSecret
        FROM [Administration].[Setting]
        WHERE [Key] = @Key FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    BEGIN TRAN;

        IF @exists = 1
        BEGIN
            UPDATE [Administration].[Setting]
            SET [Value]        = @Value,
                DataType       = @type,
                Category       = COALESCE(@Category, Category),
                Description    = COALESCE(@Description, Description),
                IsClientVisible= COALESCE(@IsClientVisible, IsClientVisible),
                IsSecret       = COALESCE(@IsSecret, IsSecret),
                ModifiedOn     = SYSUTCDATETIME(),
                ModifiedBy     = @ActorUserId
            WHERE [Key] = @Key;
        END
        ELSE
        BEGIN
            INSERT INTO [Administration].[Setting]
                ([Key], [Value], DataType, Category, Description,
                 IsClientVisible, IsSecret, CreatedBy, CreatedOn,
                 ModifiedBy, ModifiedOn)
            VALUES
                /*  Category is NOT NULL on the table. Defaulting here rather
                    than rejecting the request: an operator adding a setting in
                    a hurry should not be blocked on filing it, and 'General' is
                    an honest answer they can change later. */
                (@Key, @Value, @type, ISNULL(@Category, N'General'), @Description,
                 ISNULL(@IsClientVisible, 0), ISNULL(@IsSecret, 0),
                 @ActorUserId, SYSUTCDATETIME(),
                 @ActorUserId, SYSUTCDATETIME());
        END

        /*  A configuration change alters behaviour for every user of the app
            without a release. It is audited for the same reason a publish is:
            somebody will ask why the app changed on a Tuesday. */
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId,
             BeforeJson, AfterJson)
        SELECT
            @ActorUserId, 'admin',
            CASE WHEN @exists = 1 THEN 'Setting.Update' ELSE 'Setting.Create' END,
            'Setting', @Key,
            @before,
            (SELECT [Key],
                    /*  A secret's value is never written to the audit trail
                        either. The audit records that it changed and who
                        changed it, which is the useful part. */
                    CASE WHEN IsSecret = 1 THEN '***' ELSE [Value] END AS [Value],
                    DataType, IsClientVisible, IsSecret
             FROM [Administration].[Setting]
             WHERE [Key] = @Key FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Setting_Delete — soft
-- ---------------------------------------------------------------------------
IF OBJECT_ID('Administration.usp_Setting_Delete') IS NOT NULL
    DROP PROCEDURE [Administration].[usp_Setting_Delete];
GO
CREATE PROCEDURE [Administration].[usp_Setting_Delete]
    @Key         VARCHAR(100),
    @ActorUserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Administration].[Setting]
                   WHERE [Key] = @Key AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        DECLARE @before NVARCHAR(MAX) = (
            SELECT [Key], [Value], DataType FROM [Administration].[Setting]
            WHERE [Key] = @Key FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);

        /*  Soft delete. A client that still reads this key falls back to its
            compiled default; a hard delete would make the audit row reference
            a key that resolves to nothing. */
        UPDATE [Administration].[Setting]
        SET IsDeleted = 1,
            DeletedOn = SYSUTCDATETIME(),
            DeletedBy = @ActorUserId
        WHERE [Key] = @Key;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, BeforeJson)
        VALUES
            (@ActorUserId, 'admin', 'Setting.Delete', 'Setting', @Key, @before);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
END
GO

PRINT 'Config procedures applied.';
GO
