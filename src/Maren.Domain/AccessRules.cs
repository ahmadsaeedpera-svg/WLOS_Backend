namespace Maren.Domain;

/// <summary>
/// The access-control invariants, stated once.
/// </summary>
/// <remarks>
/// These are also enforced in the stored procedures, deliberately. A privilege
/// check that exists only in the application layer is bypassed by anything that
/// connects to the database instead — an import job, a support script, a future
/// service.
///
/// <para>
/// The duplication is not accidental and is not "duplicated business logic" in
/// the sense worth removing: the procedure is the boundary that cannot be
/// bypassed, and this class is what lets the API refuse early with a clear
/// message instead of making a round trip to be told no. If they ever disagree,
/// the procedure wins and the tests say so.
/// </para>
/// </remarks>
public static class AccessRules
{
    /// <summary>Roles the platform cannot function without.</summary>
    /// <remarks>
    /// <c>SuperAdmin</c> is granted every permission by join in the seed rather
    /// than by an explicit list, so deleting it leaves a database that only raw
    /// SQL can administer.
    /// </remarks>
    public static readonly IReadOnlySet<string> ProtectedRoleNames =
        new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "SuperAdmin", "Member"
        };

    /// <summary>
    /// Whether <paramref name="actorPermissions"/> covers everything in
    /// <paramref name="required"/>.
    /// </summary>
    /// <remarks>
    /// The rule that keeps <c>roles.write</c> from being equivalent to
    /// <c>SuperAdmin</c>. Without it, the holder edits any role to include
    /// every permission, or assigns themselves a role that already has them —
    /// and the check meant to stop them is the one they just used.
    /// </remarks>
    public static bool CanGrant(
        IReadOnlyCollection<string> actorPermissions,
        IReadOnlyCollection<string> required)
    {
        var held = new HashSet<string>(actorPermissions, StringComparer.Ordinal);
        return required.All(held.Contains);
    }

    /// <summary>
    /// Permissions in <paramref name="required"/> the actor does not hold.
    /// </summary>
    /// <remarks>
    /// Returned so the API can name them. "You cannot grant users.delete"
    /// tells an operator what to ask for; "forbidden" starts a support ticket.
    /// </remarks>
    public static IReadOnlyList<string> MissingToGrant(
        IReadOnlyCollection<string> actorPermissions,
        IReadOnlyCollection<string> required)
    {
        var held = new HashSet<string>(actorPermissions, StringComparer.Ordinal);
        return required.Where(p => !held.Contains(p)).OrderBy(p => p).ToList();
    }

    /// <summary>
    /// Whether an actor may change their own access.
    /// </summary>
    /// <remarks>
    /// Always false. This is an availability rule rather than a security one:
    /// it prevents the case where the only administrator removes their own role
    /// or locks their own account, and the recovery path becomes raw SQL against
    /// production. Another administrator can always do it.
    /// </remarks>
    public static bool CanActOnSelf(Guid actorUserId, Guid targetUserId) =>
        actorUserId != targetUserId;

    public static bool IsProtectedRole(string roleName, bool isSystem) =>
        isSystem || ProtectedRoleNames.Contains(roleName);
}

/// <summary>Failure codes the access slice returns.</summary>
public static class AccessFailureCodes
{
    /// <summary>The caller tried to grant something they do not hold.</summary>
    public const string PrivilegeEscalation = "PRIVILEGE_ESCALATION";

    /// <summary>The caller tried to change their own access.</summary>
    public const string SelfDemotion = "SELF_DEMOTION";

    public const string SystemRole = "SYSTEM_ROLE";
    public const string RoleInUse = "ROLE_IN_USE";
    public const string UnknownPermission = "UNKNOWN_PERMISSION";
    public const string LastAdministrator = "LAST_ADMINISTRATOR";
    public const string InvalidPayload = "INVALID_PAYLOAD";
}
