namespace Maren.Shared;

/// <summary>
/// The outcome of an operation that is expected to fail sometimes.
/// </summary>
/// <remarks>
/// Used instead of exceptions for expected failures — a wrong password, an
/// email already in use, a token that has expired. Exceptions are reserved for
/// the genuinely unexpected, which keeps stack traces meaningful and stops the
/// logs filling with "failures" that are really just users typing things.
///
/// <para>
/// The failure code is a stable machine-readable string rather than an enum,
/// because the mobile client and the admin portal both switch on it and a
/// renumbered enum would break a shipped app that cannot be updated quickly.
/// </para>
/// </remarks>
public readonly record struct Result
{
    private Result(bool succeeded, string? failureCode, string? message)
    {
        Succeeded = succeeded;
        FailureCode = failureCode;
        Message = message;
    }

    public bool Succeeded { get; }
    public string? FailureCode { get; }
    public string? Message { get; }

    public static Result Success() => new(true, null, null);

    public static Result Failure(string code, string? message = null) =>
        new(false, code, message);
}

public readonly record struct Result<T>
{
    private Result(bool succeeded, T? value, string? failureCode, string? message)
    {
        Succeeded = succeeded;
        Value = value;
        FailureCode = failureCode;
        Message = message;
    }

    public bool Succeeded { get; }
    public T? Value { get; }
    public string? FailureCode { get; }
    public string? Message { get; }

    public static Result<T> Success(T value) => new(true, value, null, null);

    public static Result<T> Failure(string code, string? message = null) =>
        new(false, default, code, message);
}

/// <summary>Failure codes shared between the API, the app and the portal.</summary>
public static class FailureCodes
{
    public const string EmailInUse = "EMAIL_IN_USE";

    /// <summary>
    /// Returned for both "no such account" and "wrong password".
    /// </summary>
    /// <remarks>
    /// Deliberately indistinguishable. A response that reveals whether an email
    /// is registered lets anyone test addresses against a pregnancy app, which
    /// is a disclosure worth avoiding on its own.
    /// </remarks>
    public const string InvalidCredentials = "INVALID_CREDENTIALS";

    public const string AccountLocked = "ACCOUNT_LOCKED";
    public const string UnknownToken = "UNKNOWN_TOKEN";
    public const string TokenExpired = "TOKEN_EXPIRED";
    public const string TokenReused = "TOKEN_REUSED";
    public const string NotFound = "NOT_FOUND";
    public const string Forbidden = "FORBIDDEN";
    public const string ValidationFailed = "VALIDATION_FAILED";

    /// <summary>The date of birth given is below the launch age.</summary>
    /// <remarks>
    /// Distinct from <see cref="InvalidDateOfBirth"/> on purpose. One is a
    /// refusal and the other is a typo, and a client that cannot tell them
    /// apart either accuses someone of being under age for slipping on a date
    /// picker, or tells a fifteen-year-old to check her spelling.
    /// </remarks>
    public const string UnderMinimumAge = "UNDER_MINIMUM_AGE";

    /// <summary>In the future, or implying an age no human has reached.</summary>
    public const string InvalidDateOfBirth = "INVALID_DATE_OF_BIRTH";

    /// <summary>Self-service deletion refused: the account holds operator roles.</summary>
    /// <remarks>
    /// Operators are woven into the platform's own history — approvals,
    /// publications, role grants — and erasing one leaves that history pointing
    /// at nothing. Offboarding an operator is a separate procedure with
    /// different rules; letting the self-service endpoint do it would mean an
    /// administrator could quietly dismantle themselves.
    /// </remarks>
    public const string OperatorAccount = "OPERATOR_ACCOUNT";
}

/// <summary>
/// Failure codes the content subsystem returns.
/// </summary>
/// <remarks>
/// In Shared rather than Persistence, where they were first written. The
/// repository produces them, the API maps them to status codes and the tests
/// assert on them; a definition living in the layer that only produces them
/// forces the other two to spell the strings by hand, and a typo in a
/// hand-spelled status mapping is silent — the endpoint just returns the wrong
/// code forever.
/// </remarks>
public static class ContentFailureCodes
{
    public const string DuplicateKey = "DUPLICATE_KEY";
    public const string ReferenceViolation = "REFERENCE_VIOLATION";
    public const string Deadlock = "DEADLOCK";
    public const string Timeout = "TIMEOUT";
    public const string StorageFailure = "STORAGE_FAILURE";

    /// <summary>Publish was attempted on a version nobody approved.</summary>
    public const string NotApproved = "NOT_APPROVED";

    public const string NoVersion = "NO_VERSION";

    /// <summary>The caller's copy was stale — somebody else saved first.</summary>
    public const string VersionConflict = "VERSION_CONFLICT";
}
