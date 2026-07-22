namespace Maren.Shared;

/// <summary>
/// Every permission code the platform recognises.
/// </summary>
/// <remarks>
/// Mirrors the rows seeded into <c>Identity.Permission</c>. Duplicated here so
/// the API can register an authorization policy per permission at startup
/// without a database round trip before the first request — and so a typo in a
/// controller is a compile error rather than a policy that silently never
/// matches.
///
/// <para>
/// A test asserts this list and the seeded table agree. They are two
/// representations of one fact, and the failure mode when they drift is an
/// endpoint that nobody can reach.
/// </para>
/// </remarks>
public static class PlatformPermissions
{
    public const string UsersRead = "users.read";
    public const string UsersWrite = "users.write";
    public const string UsersDelete = "users.delete";
    public const string UsersImpersonate = "users.impersonate";

    public const string ContentRead = "content.read";
    public const string ContentWrite = "content.write";
    public const string ContentPublish = "content.publish";
    public const string ContentReview = "content.review";
    public const string ContentDelete = "content.delete";
    public const string ContentRestore = "content.restore";
    public const string ContentTranslate = "content.translate";

    public const string MediaRead = "media.read";
    public const string MediaWrite = "media.write";
    public const string MediaManage = "media.manage";
    public const string CategoryManage = "category.manage";

    public const string FlagsRead = "flags.read";
    public const string FlagsWrite = "flags.write";
    public const string SettingsRead = "settings.read";
    public const string SettingsWrite = "settings.write";
    public const string SettingsManage = "settings.manage";

    public const string NotificationsRead = "notifications.read";
    public const string NotificationsWrite = "notifications.write";
    public const string NotificationsSend = "notifications.send";

    public const string ReportsRead = "reports.read";
    public const string ReportsExport = "reports.export";
    public const string AnalyticsRead = "analytics.read";

    public const string SupportRead = "support.read";
    public const string SupportWrite = "support.write";

    public const string AuditRead = "audit.read";
    public const string RolesRead = "roles.read";
    public const string RolesWrite = "roles.write";

    public static readonly IReadOnlyList<string> All =
    [
        UsersRead, UsersWrite, UsersDelete, UsersImpersonate,
        ContentRead, ContentWrite, ContentPublish, ContentReview,
        ContentDelete, ContentRestore, ContentTranslate,
        MediaRead, MediaWrite, MediaManage, CategoryManage,
        FlagsRead, FlagsWrite, SettingsRead, SettingsWrite, SettingsManage,
        NotificationsRead, NotificationsWrite, NotificationsSend,
        ReportsRead, ReportsExport, AnalyticsRead,
        SupportRead, SupportWrite,
        AuditRead, RolesRead, RolesWrite
    ];
}
