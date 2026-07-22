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
}
