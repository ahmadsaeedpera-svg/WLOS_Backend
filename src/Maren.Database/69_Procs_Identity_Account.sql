/*  ===========================================================================
    69_Procs_Identity_Account.sql

    Account lifecycle: the age gate, ending one session, and erasing an account.

    Three things the identity schema did not have, and one product rule that
    had nowhere to live.

    1.  A minimum age. WLOS launches 18+. Nothing enforced that, and
        registration never asked for a date of birth, so the gate was a claim
        in a document rather than a rule in the system.

    2.  A way to end a session. Tokens were issued, rotated and revoked
        wholesale by an administrator, but a woman signing out on her own phone
        had no procedure to call.

    3.  A way to leave. The constitution is unambiguous — "she can delete
        everything, and deletion means deletion, not a flag" — and every table
        in this database soft-deletes. For the platform's own records that is
        right. For hers it is not.

    Numbered 69 because 74_AuditContract_Apply.sql must stay last: it applies
    the contract with a cursor over sys.tables, so anything created after it is
    invisible to that pass. 69 is the gap before the operations scripts.
    =========================================================================== */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- ---------------------------------------------------------------------------
-- fn_MinimumAge
-- ---------------------------------------------------------------------------
/*  The launch age, in one place.

    Two procedures gate on it — registration and the profile save that could
    otherwise lower a date of birth afterwards — and a number written twice is
    a number that will eventually disagree with itself. Changing the launch age
    is meant to be one edit here plus a deliberate decision about the accounts
    already through the gate.

    18 is a product decision, not a legal minimum. The EU KIDS Act obligations
    that land in September 2026 attach to minors; launching adult-only keeps
    WLOS out of that surface entirely for Phase 1. */

/*  The dependent comes down first. fn_IsOfMinimumAge is SCHEMABINDING against
    this one, which is the point — the binding is what stops the constant being
    dropped out from under the gate — but it also means a second run of this
    script fails on the DROP unless the order is right. Re-running a numbered
    script has to be safe; that is the whole contract of the deployment
    journal. */
IF OBJECT_ID('Identity.fn_IsOfMinimumAge') IS NOT NULL
    DROP FUNCTION [Identity].[fn_IsOfMinimumAge];
GO
IF OBJECT_ID('Identity.fn_MinimumAge') IS NOT NULL
    DROP FUNCTION [Identity].[fn_MinimumAge];
GO
CREATE FUNCTION [Identity].[fn_MinimumAge]()
RETURNS INT
WITH SCHEMABINDING
AS
BEGIN
    RETURN 18;
END
GO

-- ---------------------------------------------------------------------------
-- fn_IsOfMinimumAge
-- ---------------------------------------------------------------------------
/*  Whether a date of birth clears the gate, as of now.

    Birthday arithmetic done with DATEADD on the date of birth rather than
    DATEDIFF(YEAR, ...) on its own: DATEDIFF counts year boundaries crossed, so
    someone born on 31 December 2008 would read as 18 on 1 January 2026 — a
    fortnight early, and wrong in exactly the direction that matters.

    A NULL date of birth is not of age. Unknown is refused, never assumed. */
IF OBJECT_ID('Identity.fn_IsOfMinimumAge') IS NOT NULL
    DROP FUNCTION [Identity].[fn_IsOfMinimumAge];
GO
CREATE FUNCTION [Identity].[fn_IsOfMinimumAge](@DateOfBirth DATE)
RETURNS BIT
WITH SCHEMABINDING
AS
BEGIN
    IF @DateOfBirth IS NULL RETURN CAST(0 AS BIT);

    RETURN CASE
        WHEN DATEADD(YEAR, [Identity].[fn_MinimumAge](), @DateOfBirth)
             <= CAST(SYSUTCDATETIME() AS DATE)
        THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT)
    END;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_Register  (replaces the definition in 11_Procs_Identity.sql)
-- ---------------------------------------------------------------------------
/*  Creates an account, now behind the age gate.

    @DateOfBirth is required. It was previously collected during onboarding, if
    at all, which put the gate after the account existed — the wrong side of
    the line. An account that should never have been created is worse than a
    registration that fails.

    The date is checked three ways and the order matters: implausible first
    (a typo deserves a different message from a refusal), then the gate. A date
    in the future or past any recorded human lifespan is a slipped finger on a
    picker, not a fact about a person.

    Redefined here rather than edited in 11_Procs_Identity.sql so the numbered
    scripts stay append-only and a deployment that stops halfway is still
    legible afterwards. 11 creates it; 69 is the current definition. */
IF OBJECT_ID('Identity.usp_User_Register') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_Register];
GO
CREATE PROCEDURE [Identity].[usp_User_Register]
    @Email              NVARCHAR(256),
    @PasswordHash       VARBINARY(256),
    @PasswordSalt       VARBINARY(128),
    @PasswordIterations INT,
    @DateOfBirth        DATE,
    @CountryIso         CHAR(2) = NULL,
    @LanguageCode       CHAR(5) = 'en-GB',
    @IpAddress          VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @normalised NVARCHAR(256) = UPPER(LTRIM(RTRIM(@Email)));
    DECLARE @userId UNIQUEIDENTIFIER;
    DECLARE @countryId INT =
        (SELECT CountryId FROM [Identity].[Country] WHERE IsoCode = @CountryIso);

    IF @DateOfBirth IS NULL
       OR @DateOfBirth > CAST(SYSUTCDATETIME() AS DATE)
       OR @DateOfBirth < DATEADD(YEAR, -120, CAST(SYSUTCDATETIME() AS DATE))
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded,
               'INVALID_DATE_OF_BIRTH' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId;
        RETURN;
    END

    IF [Identity].[fn_IsOfMinimumAge](@DateOfBirth) = 0
    BEGIN
        /*  No account, no row, no audit entry naming her.

            Recording a refused under-age registration would mean storing a
            child's email address and date of birth as the permanent record of
            having turned her away, which is the opposite of what the gate is
            for. The attempt is not kept. */
        SELECT CAST(0 AS BIT) AS Succeeded,
               'UNDER_MINIMUM_AGE' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM [Identity].[User]
               WHERE NormalisedEmail = @normalised AND IsDeleted = 0)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded,
               'EMAIL_IN_USE' AS FailureCode,
               CAST(NULL AS UNIQUEIDENTIFIER) AS UserId;
        RETURN;
    END

    BEGIN TRAN;

        INSERT INTO [Identity].[User]
            (Email, NormalisedEmail, PasswordHash, PasswordSalt,
             PasswordIterations, CountryId, LanguageCode)
        VALUES
            (@Email, @normalised, @PasswordHash, @PasswordSalt,
             @PasswordIterations, @countryId, @LanguageCode);

        SET @userId = (SELECT UserId FROM [Identity].[User]
                       WHERE NormalisedEmail = @normalised AND IsDeleted = 0);

        INSERT INTO [Identity].[Profile] (UserId, DateOfBirth)
        VALUES (@userId, @DateOfBirth);

        /*  Every new account gets the Member role. Roles are additive from
            there; nobody is created with elevated access. */
        INSERT INTO [Identity].[UserRole] (UserId, RoleId)
        SELECT @userId, RoleId FROM [Identity].[Role] WHERE Name = 'Member';

        /*  That she registered, not what she told us. The date of birth is not
            in the audit payload for the same reason health data never is. */
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, IpAddress)
        VALUES
            (@userId, 'user', 'User.Register', 'User',
             CONVERT(NVARCHAR(50), @userId), @IpAddress);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded,
           CAST(NULL AS VARCHAR(50)) AS FailureCode,
           @userId AS UserId;
END
GO

-- ---------------------------------------------------------------------------
-- usp_Profile_Save  (replaces the definition in 33_Procs_Profile.sql)
-- ---------------------------------------------------------------------------
/*  Updates the profile fields a woman controls, now with the same age gate.

    Identical to the 33 definition but for one added check. Without it the gate
    is trivially defeated: register at a date that clears 18, then save a real
    one. The rule has to hold wherever the value can be written, not only where
    it is first written.

    Every parameter is still optional and NULL still means "leave alone" rather
    than "clear" — onboarding sets these a few at a time as it learns them, and
    a save that blanked what it was not told would lose answers she had already
    given. */
IF OBJECT_ID('Identity.usp_Profile_Save') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Profile_Save];
GO
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

    /*  The gate again. Registration is not the only door. */
    IF @DateOfBirth IS NOT NULL
       AND [Identity].[fn_IsOfMinimumAge](@DateOfBirth) = 0
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'UNDER_MINIMUM_AGE' AS FailureCode;
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
-- usp_User_SetPassword
-- ---------------------------------------------------------------------------
/*  Replaces the stored password material for an account.

    Written for the rehash-on-login path, which has never worked. When the
    verifier reported that a stored hash was below the current iteration count,
    the handler called usp_User_Register again — which found the address
    already in use, returned EMAIL_IN_USE, and did nothing. The upgrade has
    been silently failing since the cost was last raised, and every account
    created before that is still at the old count.

    Does not rotate the security stamp. The stamp exists to invalidate live
    sessions, and rehashing the same password at a higher cost is not a
    credential change — signing her out because the work factor moved would be
    a logout she cannot explain. A genuine password change is a different
    procedure and it will rotate the stamp. */
IF OBJECT_ID('Identity.usp_User_SetPassword') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_SetPassword];
GO
CREATE PROCEDURE [Identity].[usp_User_SetPassword]
    @UserId             UNIQUEIDENTIFIER,
    @PasswordHash       VARBINARY(256),
    @PasswordSalt       VARBINARY(128),
    @PasswordIterations INT,
    @Reason             VARCHAR(30) = 'rehash'
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

    BEGIN TRAN;

        UPDATE [Identity].[User]
        SET PasswordHash       = @PasswordHash,
            PasswordSalt       = @PasswordSalt,
            PasswordIterations = @PasswordIterations,
            ModifiedOn         = SYSUTCDATETIME(),
            ModifiedBy         = @UserId
        WHERE UserId = @UserId;

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (@UserId, 'system', 'User.SetPassword', 'User',
             CONVERT(NVARCHAR(50), @UserId));

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- Identity.SecurityStampRevocation: the foreign key comes off
-- ---------------------------------------------------------------------------
/*  A revocation has to be able to outlive the account it revokes.

    The stamp validator reads this table into a map of user id to current
    stamp, and treats "no row" as "nothing has ever invalidated this user's
    sessions, so any correctly signed token is current". That is right for a
    live account and exactly wrong for a deleted one: erasing a woman's rows
    took her revocation row with them, so her still-signed access token sailed
    through the middleware and reached a handler. The endpoint answered
    PROFILE_NOT_FOUND with a 400, which tells a second device holding that
    token to stay where it is rather than to sign out.

    With the foreign key gone, deletion can leave a tombstone revocation
    carrying a fresh random stamp that no issued token will ever match, and
    every live session for that account dies at the middleware with a 401 the
    moment the row lands.

    The row is a user id and a random GUID. After deletion the id refers to
    nothing — no email, no profile, no entry — so this is a tombstone in the
    same sense as the audit one, and usp_User_DeleteAccount prunes tombstones
    older than a day so the table cannot grow without bound. */
IF EXISTS (SELECT 1 FROM sys.foreign_keys
           WHERE name = 'FK_SecurityStampRevocation_User')
BEGIN
    ALTER TABLE [Identity].[SecurityStampRevocation]
        DROP CONSTRAINT [FK_SecurityStampRevocation_User];
    PRINT 'Dropped FK_SecurityStampRevocation_User - a revocation must outlive the account.';
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_GetDetail  (replaces the definition in 13_Procs_Access.sql)
-- ---------------------------------------------------------------------------
/*  Adds two facts an operator needs and could not previously see.

    IsAgeVerified — whether a date of birth is on file and clears the launch
    age. NOT the date itself, and this is the point: an operator supporting an
    account needs to know the gate was satisfied, and has no business knowing
    her birthday. A support screen that shows a date of birth is a support
    screen that leaks one every time somebody glances at a shared monitor.

    ActiveSessionCount — live, unrevoked, unexpired refresh tokens. The portal
    could previously show devices that had ever registered but nothing about
    whether any session was still usable, which is the question actually being
    asked when someone reports "I think somebody else is in my account".

    Redefined here rather than edited in 13 so the numbered scripts stay
    append-only. 13 creates it; 69 is the current definition. */
IF OBJECT_ID('Identity.usp_User_GetDetail') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_GetDetail];
GO
CREATE PROCEDURE [Identity].[usp_User_GetDetail]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserId, u.Email, u.LanguageCode, u.IsEmailConfirmed,
        u.IsLockedOut, u.LockoutEndUtc, u.FailedLoginCount,
        u.IsDeleted, u.DeletedOn, u.CreatedOn, u.ModifiedOn,
        c.IsoCode AS CountryIso,
        CAST(ISNULL([Identity].[fn_IsOfMinimumAge](p.DateOfBirth), 0) AS BIT)
            AS IsAgeVerified,
        (SELECT COUNT(*) FROM [Identity].[RefreshToken] rt
         WHERE rt.UserId = u.UserId
           AND rt.RevokedUtc IS NULL
           AND rt.ExpiresUtc > SYSUTCDATETIME()) AS ActiveSessionCount
    FROM [Identity].[User] u
    LEFT JOIN [Identity].[Country] c ON c.CountryId = u.CountryId
    LEFT JOIN [Identity].[Profile] p ON p.UserId = u.UserId
    WHERE u.UserId = @UserId;

    SELECT r.RoleId, r.Name, r.Description, r.IsSystem,
           ur.AssignedUtc, ur.AssignedBy
    FROM [Identity].[UserRole] ur
    JOIN [Identity].[Role] r ON r.RoleId = ur.RoleId
    WHERE ur.UserId = @UserId
    ORDER BY r.Name;

    /*  No FcmToken. It is a push credential and the operator has no use for
        its value — only for knowing the device exists. */
    SELECT d.DeviceId, d.Platform, d.OsVersion, d.AppVersion, d.Model,
           d.IsActive, d.LastSeenUtc
    FROM [Identity].[Device] d
    WHERE d.UserId = @UserId
    ORDER BY d.LastSeenUtc DESC;

    SELECT TOP 25
        a.AuditLogId, a.OccurredUtc, a.[Action], a.EntityType, a.EntityId,
        a.IpAddress
    FROM [Audit].[AuditLog] a
    WHERE a.ActorUserId = @UserId
    ORDER BY a.OccurredUtc DESC;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_GetLoginMaterial
-- ---------------------------------------------------------------------------
/*  The same six columns usp_User_GetForLogin returns, found by user id.

    For re-confirming a password when the caller is already authenticated —
    closing an account, and later changing a password. usp_User_GetForLogin
    takes an email address, which would mean an authenticated endpoint asking
    a client for an identifier it has no business sending: the account is
    already known from the token, and accepting an address alongside it would
    be a second, weaker way to say who is being acted on.

    Six columns and no more, for the same reason as the email version. This
    one runs for a caller who has authenticated, but the returned material is
    still password material. */
IF OBJECT_ID('Identity.usp_User_GetLoginMaterial') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_GetLoginMaterial];
GO
CREATE PROCEDURE [Identity].[usp_User_GetLoginMaterial]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 1
           UserId,
           PasswordHash,
           PasswordSalt,
           PasswordIterations,
           IsLockedOut,
           LockoutEndUtc
    FROM [Identity].[User]
    WHERE UserId = @UserId AND IsDeleted = 0;
END
GO

-- ---------------------------------------------------------------------------
-- usp_RefreshToken_Revoke
-- ---------------------------------------------------------------------------
/*  Signing out: ends one session, on one device.

    @UserId is not decoration. The token hash alone would be enough to find the
    row, and revoking by hash alone would let anyone holding a stolen hash sign
    a stranger out. The caller has already authenticated, so the owner is known,
    and the procedure refuses a token that is not hers.

    Idempotent by design. A token that is already revoked, or expired, or was
    never ours, all come back as success. Sign-out is a thing the client must be
    able to complete and forget; there is no useful recovery from "your sign-out
    failed", and the client has discarded the token either way. The one case
    that is not success is a token belonging to someone else, which is reported
    so it can be seen.

    @AllDevices ends every live session instead, for "sign out everywhere" and
    for the account deletion below. */
IF OBJECT_ID('Identity.usp_RefreshToken_Revoke') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_RefreshToken_Revoke];
GO
CREATE PROCEDURE [Identity].[usp_RefreshToken_Revoke]
    @UserId     UNIQUEIDENTIFIER,
    @TokenHash  VARBINARY(64) = NULL,
    @AllDevices BIT = 0,
    @IpAddress  VARCHAR(45) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @AllDevices = 0 AND @TokenHash IS NOT NULL
    BEGIN
        DECLARE @owner UNIQUEIDENTIFIER =
            (SELECT UserId FROM [Identity].[RefreshToken] WHERE TokenHash = @TokenHash);

        IF @owner IS NOT NULL AND @owner <> @UserId
        BEGIN
            /*  Someone presenting a token that is not theirs. Recorded, because
                the only ways to reach here are a client bug and an attempt. */
            INSERT INTO [Audit].[AuditLog]
                (ActorUserId, ActorKind, [Action], EntityType, EntityId, IpAddress)
            VALUES
                (@UserId, 'user', 'RefreshToken.RevokeForeignToken', 'User',
                 CONVERT(NVARCHAR(50), @UserId), @IpAddress);

            SELECT CAST(0 AS BIT) AS Succeeded, 'FORBIDDEN' AS FailureCode;
            RETURN;
        END
    END

    BEGIN TRAN;

        UPDATE [Identity].[RefreshToken]
        SET RevokedUtc = SYSUTCDATETIME()
        WHERE UserId = @UserId
          AND RevokedUtc IS NULL
          AND (@AllDevices = 1 OR TokenHash = @TokenHash);

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, IpAddress)
        VALUES
            (@UserId, 'user',
             CASE WHEN @AllDevices = 1 THEN 'User.SignOutEverywhere'
                  ELSE 'User.SignOut' END,
             'User', CONVERT(NVARCHAR(50), @UserId), @IpAddress);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

-- ---------------------------------------------------------------------------
-- usp_User_DeleteAccount
-- ---------------------------------------------------------------------------
/*  Erases an account and everything behind it. Not a flag.

    The constitution says deletion means deletion. Every other table in this
    database soft-deletes, and for platform records — content, roles, feature
    flags, the things an operator owns — that is correct, because an editor
    needs to see what was removed and by whom. None of that reasoning applies
    to a woman's own account. She is not an operator's audit subject.

    THE INVARIANT THIS PROCEDURE IS THE EXCEPTION TO

    Operational audit and AI-safety records are append-only DURING ACCOUNT
    LIFETIME. Account deletion may erase records belonging to the deleted user.
    The deletion operation itself creates only a minimal system tombstone
    containing no personal payload.

    This is the only procedure in the database permitted to remove rows from
    Audit.AuditLog or AI.SafetyEvent, it may only remove rows belonging to the
    account being erased, and it refuses operator accounts outright. It is not a
    licence to mutate either table for any other purpose. See CLAUDE.md §4.8.

    WHAT SURVIVES

    One row in Audit.AuditLog saying an account with this identifier was
    deleted, at this time. Nothing else of hers: her historic audit rows go
    with the rest, because an audit trail of what she did is still a record of
    what she did.

    The surviving row is a tombstone, not a record about a person. After this
    procedure the identifier refers to nothing — no email, no profile, no
    device, no entry. Keeping it means the fact of an erasure is provable,
    which is the one thing an erasure log is for.

    The rows are deleted rather than scrubbed in place so nothing in the
    retained log is ever rewritten. Append-only holds: this procedure only ever
    appends to what remains.

    WHAT IS REFUSED

    An account holding any role beyond Member. Operators are woven into the
    platform's own history — approvals, publications, role grants — and
    removing one leaves that history pointing at nothing. Operator offboarding
    is a different procedure with different rules, and conflating the two here
    would mean the self-service endpoint could quietly dismantle an
    administrator. She can always have her operator roles removed first and
    then delete.

    ORDER

    Every foreign key to Identity.User is NO_ACTION, so the order below is the
    contract, not a suggestion. Children before parents; Growth.GoalProgress
    before Growth.UserGoal is the only second-level edge in the graph. Tables
    carrying a UserId without a declared foreign key are deleted too — they are
    no less hers for the constraint being absent, and they are the rows most
    likely to be missed. The test for this asserts zero remaining rows across
    every table with a UserId column rather than across the list below, so a
    table added later fails the test instead of quietly surviving a deletion. */
IF OBJECT_ID('Identity.usp_User_DeleteAccount') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_User_DeleteAccount];
GO
/*  No @IpAddress parameter, unlike every other procedure here. There is
    nowhere honest to put it: the tombstone deliberately carries no address,
    and a parameter accepted and dropped on the floor reads like the value is
    being recorded somewhere. */
CREATE PROCEDURE [Identity].[usp_User_DeleteAccount]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM [Identity].[User] WHERE UserId = @UserId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'USER_NOT_FOUND' AS FailureCode;
        RETURN;
    END

    IF EXISTS (SELECT 1
               FROM [Identity].[UserRole] ur
               JOIN [Identity].[Role] r ON r.RoleId = ur.RoleId
               WHERE ur.UserId = @UserId AND r.Name <> 'Member')
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'OPERATOR_ACCOUNT' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        -- Derived rows: predictions, recommendations, explanations, snapshots.
        -- Everything the platform inferred about her, which is hers as much as
        -- anything she typed.
        DELETE FROM [Predict].[Predicted]            WHERE UserId = @UserId;
        DELETE FROM [Recommend].[Assembled]          WHERE UserId = @UserId;
        DELETE FROM [Coach].[Explained]              WHERE UserId = @UserId;
        DELETE FROM [Intelligence].[UserStateSnapshot] WHERE UserId = @UserId;
        DELETE FROM [Behaviour].[Observation]        WHERE UserId = @UserId;
        DELETE FROM [AI].[SafetyEvent]               WHERE UserId = @UserId;
        DELETE FROM [Notifications].[Delivery]       WHERE UserId = @UserId;

        -- Growth: progress before the goal it belongs to.
        DELETE FROM [Growth].[GoalProgress]          WHERE UserId = @UserId;
        DELETE FROM [Growth].[UserGoal]              WHERE UserId = @UserId;

        -- Health. The most sensitive rows in the database.
        DELETE FROM [Health].[ShareGrant]            WHERE UserId = @UserId;
        DELETE FROM [Health].[BirthPreference]       WHERE UserId = @UserId;
        DELETE FROM [Health].[HospitalBagItem]       WHERE UserId = @UserId;
        DELETE FROM [Health].[Appointment]           WHERE UserId = @UserId;
        DELETE FROM [Health].[BodyMeasurement]       WHERE UserId = @UserId;
        DELETE FROM [Health].[Symptom]               WHERE UserId = @UserId;
        DELETE FROM [Health].[DailyLog]              WHERE UserId = @UserId;
        DELETE FROM [Health].[Cycle]                 WHERE UserId = @UserId;
        DELETE FROM [Health].[Pregnancy]             WHERE UserId = @UserId;

        DELETE FROM [Timeline].[Event]               WHERE UserId = @UserId;

        -- Platform associations.
        DELETE FROM [Administration].[FeatureFlagAssignment] WHERE UserId = @UserId;
        DELETE FROM [Administration].[SupportTicket] WHERE UserId = @UserId;
        DELETE FROM [Content].[ContentAuthor]        WHERE UserId = @UserId;

        /*  Her sessions die here, not in fifteen minutes.

            Refresh tokens go below, which stops her getting a NEW access
            token. This stops the one she is holding: the stamp validator
            compares the token's stamp against this row and refuses anything
            that does not match, so a random replacement kills every token ever
            issued for this account. Without it a second device would keep a
            working token until it expired, and would be told PROFILE_NOT_FOUND
            rather than to sign out.

            Replaced rather than deleted, and kept after the User row goes —
            which is why the foreign key above had to come off. */
        DELETE FROM [Identity].[SecurityStampRevocation] WHERE UserId = @UserId;
        INSERT INTO [Identity].[SecurityStampRevocation]
            (UserId, SecurityStamp, RevokedUtc, Reason)
        VALUES
            (@UserId, NEWID(), SYSUTCDATETIME(), 'Account deleted');

        DELETE FROM [Identity].[RefreshToken]        WHERE UserId = @UserId;
        DELETE FROM [Identity].[Device]              WHERE UserId = @UserId;
        DELETE FROM [Identity].[UserRoleMode]        WHERE UserId = @UserId;
        DELETE FROM [Identity].[UserLifeStage]       WHERE UserId = @UserId;
        DELETE FROM [Identity].[UserRole]            WHERE UserId = @UserId;
        DELETE FROM [Identity].[Profile]             WHERE UserId = @UserId;

        /*  Encrypted records and the key hierarchy that opens them.
            74_Crypto.sql.

            The ciphertext goes too. It would be defensible to argue that
            deleting the wrappers is enough — without them the records are
            bytes nobody can decrypt, including us. It is not enough. "Deletion
            means deletion, not a flag" does not become satisfied by leaving
            her journal on disk in a form we merely promise not to read, and a
            future key-recovery bug would turn that promise into a breach of
            data we had already told her was gone.

            Order is forced by the foreign keys: records and the things hanging
            off a generation, then the generations, then the credentials. */
        DELETE FROM [Crypto].[Record]                WHERE UserId = @UserId;

        /*  Recovery challenges, including the failed ones. They record that
            somebody tried her phrase and when, which is a history of attempts
            on her account and goes with the account. */
        DELETE FROM [Crypto].[RecoveryChallenge]     WHERE UserId = @UserId;

        DELETE FROM [Crypto].[RecoveryVerifier]
        WHERE GenerationId IN (SELECT GenerationId FROM [Crypto].[Generation]
                               WHERE UserId = @UserId);

        DELETE FROM [Crypto].[Wrapper]
        WHERE GenerationId IN (SELECT GenerationId FROM [Crypto].[Generation]
                               WHERE UserId = @UserId);

        DELETE FROM [Crypto].[Generation]            WHERE UserId = @UserId;
        DELETE FROM [Identity].[UserCredential]      WHERE UserId = @UserId;

        DELETE FROM [Identity].[User]                WHERE UserId = @UserId;

        /*  Her audit history goes with her. A log of everything she did is
            still a record of everything she did. */
        DELETE FROM [Audit].[AuditLog] WHERE ActorUserId = @UserId;

        /*  The tombstone. ActorKind is 'system' because by the time this row
            is written there is no user to be the actor, and no IP address
            because the address belonged to a person who has just asked to stop
            being one. */
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId)
        VALUES
            (NULL, 'system', 'User.DeleteAccount', 'User',
             CONVERT(NVARCHAR(50), @UserId));

        /*  Old tombstone revocations, pruned.

            A revocation only has to outlive the longest-lived access token,
            which is fifteen minutes. A day is generous by three orders of
            magnitude and still bounds a table every authenticated request
            reads through a cache. Rows belonging to accounts that still exist
            are left alone — those are real revocations doing a job. */
        DELETE r
        FROM [Identity].[SecurityStampRevocation] r
        WHERE r.Reason = 'Account deleted'
          AND r.RevokedUtc < DATEADD(DAY, -1, SYSUTCDATETIME())
          AND NOT EXISTS (SELECT 1 FROM [Identity].[User] u
                          WHERE u.UserId = r.UserId);

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(50)) AS FailureCode;
END
GO

PRINT '69_Procs_Identity_Account.sql applied.';
GO
