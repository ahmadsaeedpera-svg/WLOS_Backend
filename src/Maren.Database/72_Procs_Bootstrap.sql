/*  ===========================================================================
    Bootstrap — the first administrator
    ===========================================================================

    A freshly deployed database could not be administered.

    `usp_User_Register` grants `Member` and nothing else. Nothing else grants
    anything. And §4.6 — you cannot grant a permission you do not hold, enforced
    in `usp_User_AssignRole` through `fn_UserHoldsAllPermissionsOfRole`, not
    merely in C# — means no account can ever reach `SuperAdmin` through the API.

    So every correct deployment produced an unadministrable platform, and the
    only way in was hand-written SQL against production: exactly the thing the
    stored-procedure discipline exists to prevent. `22_Seed_FAQ.sql` already
    refers to "the bootstrap admin" as though one existed.

    It went unnoticed because every verification database already had an
    operator. The platform had never once been started from nothing.

    ---------------------------------------------------------------------------
    Why there is no table here, and no flag

    The question "may this be claimed?" is answered by asking whether any
    account already holds `users.write`. That is derived on every call, never
    stored.

    A `BootstrapCompleted` flag would be a second statement of a fact the
    permission tables already make, and the copy that drifts is the one nobody
    reads. It also could not be trusted: a flag saying "claimed" while no
    account holds `users.write` locks the platform out permanently, and a flag
    saying "unclaimed" beside a live administrator is an open door. The derived
    form cannot disagree with itself.

    This makes the procedure self-disabling by construction rather than by
    bookkeeping. The moment a claim succeeds, the claimant holds `users.write`,
    so the next call is refused — by the same query, not by a second mechanism
    that has to be remembered.

    ---------------------------------------------------------------------------
    The reopening case, which is deliberate

    Removing every `users.write` holder reopens the claim. That is a recovery
    path, not an oversight: a platform whose only administrator is gone would
    otherwise need the hand-written SQL this procedure exists to abolish.

    It is safe because it is not the only gate. The API refuses the claim unless
    the caller presents a deployment secret that is never stored in this
    database and is compared in fixed time (see BootstrapHandlers.cs). Reaching
    an unclaimed platform over the network is not sufficient; you must also hold
    a secret placed there by whoever deployed it.

    That split is deliberate. The database owns the state rule — is it claimed —
    because that is a fact about rows and must hold regardless of who connects.
    Configuration owns the deployment secret, because the database cannot know
    it without storing it, and a secret stored beside the thing it protects is
    not a secret.

    ---------------------------------------------------------------------------
    No script number changes: this file creates no table, so the audit contract
    in 74_AuditContract_Apply.sql has nothing new to cover and stays where it is.
    =========================================================================== */

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('Identity.usp_Operator_Claim') IS NOT NULL
    DROP PROCEDURE [Identity].[usp_Operator_Claim];
GO

CREATE PROCEDURE [Identity].[usp_Operator_Claim]
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @roleName NVARCHAR(64) = N'SuperAdmin';
    DECLARE @roleId INT = (SELECT RoleId FROM [Identity].[Role] WHERE Name = @roleName);

    IF @roleId IS NULL OR NOT EXISTS (SELECT 1 FROM [Identity].[User] WHERE UserId = @UserId)
    BEGIN
        SELECT CAST(0 AS BIT) AS Succeeded, 'NOT_FOUND' AS FailureCode;
        RETURN;
    END

    /*  The whole gate, and the reason no flag exists. Derived every time from
        the permission tables, so it cannot disagree with who can actually
        administer the platform. */
    IF EXISTS (
        SELECT 1
        FROM [Identity].[UserRole]       ur
        JOIN [Identity].[RolePermission] rp ON rp.RoleId = ur.RoleId
        JOIN [Identity].[Permission]     p  ON p.PermissionId = rp.PermissionId
        WHERE p.Code = 'users.write')
    BEGIN
        /*  A refused claim is recorded, like a refused escalation in
            usp_User_AssignRole. Somebody probing a deployed platform for an
            open bootstrap leaves a trail; auditing only the success would mean
            the first evidence of an attempt is the attempt that worked.

            ActorKind is 'user', not 'admin': by definition the caller holds no
            administrative permission, and recording them as an admin would put
            a false actor kind on a security row. */
        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@UserId, 'user', 'Security.OperatorClaimRefused', 'User',
             CONVERT(NVARCHAR(50), @UserId),
             (SELECT 'ALREADY_CLAIMED' AS Reason, @roleName AS RequestedRole
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

        SELECT CAST(0 AS BIT) AS Succeeded, 'ALREADY_CLAIMED' AS FailureCode;
        RETURN;
    END

    BEGIN TRAN;

        /*  Written directly rather than through usp_User_AssignRole, and the
            reason matters. That procedure asks whether the actor already holds
            every permission of the role being granted. Here nobody does, and
            nobody can — that is the condition this procedure exists to resolve.
            Calling it would either fail by design or require passing
            @ActorUserId = NULL, whose documented meaning is "system actor,
            skip the escalation guard". Reaching for a NULL to disable a
            security check is how a guard quietly stops guarding everywhere it
            is used. The narrow path is written once, here, where the
            surrounding refusal is visible on the same screen. */
        INSERT INTO [Identity].[UserRole] (UserId, RoleId, AssignedBy)
        VALUES (@UserId, @roleId, @UserId);

        /*  Same reason as usp_User_AssignRole: the session that made the claim
            is carrying a token minted before the role existed. Rotating forces
            re-authentication so the new permissions are actually held rather
            than waited for. */
        EXEC [Identity].[usp_Access_RotateSecurityStamp]
            @UserId = @UserId, @ActorUserId = @UserId,
            @Reason = N'Operator claimed';

        INSERT INTO [Audit].[AuditLog]
            (ActorUserId, ActorKind, [Action], EntityType, EntityId, AfterJson)
        VALUES
            (@UserId, 'user', 'Identity.OperatorClaimed', 'User',
             CONVERT(NVARCHAR(50), @UserId),
             (SELECT @roleId AS RoleId, @roleName AS RoleName
              FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));

    COMMIT TRAN;

    SELECT CAST(1 AS BIT) AS Succeeded, CAST(NULL AS VARCHAR(40)) AS FailureCode;
END
GO
