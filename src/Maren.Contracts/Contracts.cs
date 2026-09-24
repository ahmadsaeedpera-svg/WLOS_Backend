namespace Maren.Contracts;

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// <param name="DateOfBirth">
/// Required. WLOS launches 18+ and the gate sits at registration, not at
/// onboarding: collecting it later means the account already exists by the time
/// anyone knows whether it should.
/// </param>
public sealed record RegisterRequest(
    string Email,
    string Password,
    DateOnly DateOfBirth,
    string? CountryIso,
    string? LanguageCode);

public sealed record LoginRequest(
    string Email,
    string Password,
    DeviceInfo? Device);

public sealed record RefreshRequest(string RefreshToken);

/// <summary>Signing out.</summary>
/// <param name="RefreshToken">
/// The token to end. Optional: a client that has already lost it can still
/// sign out, and the access token identifies who is asking either way.
/// </param>
/// <param name="AllDevices">
/// Ends every live session instead of this one. For "signed in somewhere I
/// don't recognise", which is the moment someone most needs the control and
/// least wants to hunt for it.
/// </param>
public sealed record LogoutRequest(
    string? RefreshToken,
    bool AllDevices = false);

/// <summary>Closing an account for good.</summary>
/// <remarks>
/// <para>
/// Exactly one of the two fields is sent, and which one depends on how the
/// account stores its credential rather than on anything the client chooses.
/// The handler decides from the account, not from what arrived: an account
/// holding a client-derived credential will not accept a password, because
/// there is nothing on this server to check one against.
/// </para>
/// <para>
/// <b>This shape exists because the encrypted path had no way to close an
/// account at all.</b> A client-derived account holds no server-side password
/// — an assertion in <c>crypto_test.sql</c> insists on it — so the original
/// single-field request could only ever fail for one, and "deletion means
/// deletion" was true for version 1 accounts only.
/// </para>
/// </remarks>
/// <param name="Password">
/// Re-entered to confirm, for an account on the version 1 credential. The
/// action is irreversible and there is no undo to fall back on, so an
/// unattended phone should not be enough to do it.
/// </param>
/// <param name="AuthSecret">
/// The same confirmation for an account on the client-derived credential: a
/// 32-byte Argon2id output her device produced from the password she has just
/// typed, under her own stored salt. <b>The password itself does not travel</b>
/// — that is the whole point of the scheme, and closing an account is not a
/// reason to make an exception to it.
/// </param>
public sealed record DeleteAccountRequest(
    string? Password = null, byte[]? AuthSecret = null);

public sealed record DeviceInfo(
    Guid DeviceId,
    string Platform,
    string? OsVersion,
    string? AppVersion,
    string? Model,
    string? FcmToken);

public sealed record AuthResponse(
    Guid UserId,
    string AccessToken,
    DateTime AccessTokenExpiresUtc,
    string RefreshToken,
    DateTime RefreshTokenExpiresUtc,
    IReadOnlyList<string> Permissions);

// ---------------------------------------------------------------------------
// Feature flags and configuration
// ---------------------------------------------------------------------------

/// <summary>One flag as the client sees it.</summary>
/// <param name="DefaultValue">
/// What the client should fall back to when it cannot reach the server.
/// Sent alongside the live value so a client that later goes offline has
/// something considered to use rather than its own compiled-in guess.
/// </param>
public sealed record FeatureFlagDto(
    string Key,
    bool IsEnabled,
    bool DefaultValue,
    string? VariantKey,
    string? PayloadJson);

public sealed record SettingDto(string Key, string? Value, string DataType);

public sealed record AppVersionCheckDto(
    bool UpdateRequired,
    string? LatestVersion,
    string? ReleaseNotes);

/// <summary>
/// Everything the app needs on launch, in one call.
/// </summary>
/// <remarks>
/// Deliberately a single endpoint rather than three. A cold start on a poor
/// connection should not need three round trips before it can decide what to
/// render, and three separate caches would let flags, settings and the version
/// gate drift out of step with each other.
/// </remarks>
public sealed record BootstrapResponse(
    IReadOnlyList<FeatureFlagDto> Flags,
    IReadOnlyList<SettingDto> Settings,
    AppVersionCheckDto VersionCheck,
    DateTime ServerTimeUtc);

// ---------------------------------------------------------------------------
// Admin
// ---------------------------------------------------------------------------

public sealed record FeatureFlagAdminDto(
    int FeatureFlagId,
    string Key,
    string Name,
    string? Description,
    bool IsEnabled,
    byte RolloutPercent,
    string? MinAppVersion,
    string? CountryFilter,
    bool RequiresPremium,
    bool BetaOnly,
    bool DefaultValue,
    DateTime ModifiedOn);

public sealed record UpsertFeatureFlagRequest(
    string Key,
    string Name,
    string? Description,
    bool IsEnabled,
    byte RolloutPercent,
    string? MinAppVersion,
    string? CountryFilter,
    bool RequiresPremium,
    bool BetaOnly,
    bool DefaultValue);

// ---------------------------------------------------------------------------
// Envelope
// ---------------------------------------------------------------------------

/// <summary>
/// Uniform response shape.
/// </summary>
/// <remarks>
/// Every endpoint returns this, including failures, so the mobile client has
/// one parser and one error path rather than branching on status code shape.
/// The HTTP status still carries the semantics for anything in between.
/// </remarks>
public sealed record ApiResponse<T>(
    bool Succeeded,
    T? Data,
    string? FailureCode,
    string? Message,
    IReadOnlyDictionary<string, string[]>? ValidationErrors = null)
{
    public static ApiResponse<T> Ok(T data) => new(true, data, null, null);

    public static ApiResponse<T> Fail(string code, string? message = null) =>
        new(false, default, code, message);

    public static ApiResponse<T> Invalid(
        IReadOnlyDictionary<string, string[]> errors) =>
        new(false, default, "VALIDATION_FAILED", "One or more fields are invalid.", errors);
}

// ---------------------------------------------------------------------------
// Remote configuration administration
// ---------------------------------------------------------------------------

/// <summary>A setting as an operator sees it.</summary>
/// <remarks>
/// <c>Value</c> is null for a secret. The value never leaves the database for
/// a secret, not even for an administrator — showing it in a grid puts it in a
/// browser cache, a screenshot and a support ticket. An operator can replace a
/// secret; they cannot read it back.
/// </remarks>
public sealed record SettingAdminDto(
    int SettingId,
    string Key,
    string? Value,
    string DataType,
    string? Category,
    string? Description,
    bool IsClientVisible,
    bool IsSecret,
    DateTime ModifiedOn,
    Guid? ModifiedBy,
    string? ModifiedByEmail);

public sealed record SaveSettingRequest(
    string Key,
    string Value,
    string? DataType,
    string? Category,
    string? Description,
    bool? IsClientVisible,
    bool? IsSecret);

public sealed record SettingSearchQuery(
    string? Query = null,
    string? Category = null,
    int Page = 1,
    int PageSize = 50);
