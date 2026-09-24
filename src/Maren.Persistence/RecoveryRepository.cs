using System.Data;
using Dapper;
using Maren.Application.Abstractions;

namespace Maren.Persistence;

/// <summary>
/// Path R, against the procedures that hold its state machine.
/// </summary>
/// <remarks>
/// Every method maps to one procedure. The interesting property is what is
/// absent: no method takes a recovery phrase, entropy, a key or a password,
/// and none could be added here without one appearing in a procedure
/// signature, which the crypto assertion suite scans for by name.
/// </remarks>
public sealed class RecoveryRepository(IDbConnectionFactory factory) : IRecoveryRepository
{
    private sealed record ChallengeRow(
        Guid ChallengeId, byte[] Nonce, DateTime ExpiresOn);

    private sealed record ConsumedRow(
        Guid? UserId, Guid? GenerationId, byte[]? Nonce,
        byte[]? PublicKey, int? GenerationNumber);

    private sealed record GrantRow(
        bool Succeeded, string? FailureCode, Guid? UserId, Guid? GenerationId,
        int? GenerationNumber, byte[]? RecoveryWrapper);

    private sealed record OutcomeRow(bool Succeeded, string? FailureCode);

    private sealed record DegradedRow(
        bool Succeeded, string? FailureCode, int? GenerationNumber);

    public async Task<RecoveryChallenge> IssueChallengeAsync(
        string email, byte[] nonce, string? ip, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleAsync<ChallengeRow>(
            new CommandDefinition(
                "[Crypto].[usp_Recovery_IssueChallenge]",
                new { Email = email, Nonce = nonce, IpAddress = ip },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return new RecoveryChallenge(row.ChallengeId, row.Nonce, row.ExpiresOn);
    }

    public async Task<RecoveryAttempt?> ConsumeChallengeAsync(
        Guid challengeId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleOrDefaultAsync<ConsumedRow>(
            new CommandDefinition(
                "[Crypto].[usp_Recovery_ConsumeChallenge]",
                new { ChallengeId = challengeId },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        /*  A row with no user is a challenge that was issued for an address
            with no account, or one the rate limiter detached. Both are the
            same answer to the caller, and neither is distinguishable from an
            unknown challenge id — which is the point. */
        if (row?.UserId is null || row.PublicKey is null || row.Nonce is null)
            return null;

        return new RecoveryAttempt(
            row.UserId.Value, row.GenerationId!.Value, row.Nonce,
            row.PublicKey, row.GenerationNumber ?? 0);
    }

    public async Task<RecoveryGrant?> IssueGrantAsync(
        Guid challengeId, byte[] grantHash, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleAsync<GrantRow>(
            new CommandDefinition(
                "[Crypto].[usp_Recovery_IssueGrant]",
                new { ChallengeId = challengeId, GrantHash = grantHash },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        if (!row.Succeeded) return null;

        return new RecoveryGrant(
            row.UserId!.Value, row.GenerationId!.Value,
            row.GenerationNumber ?? 0, row.RecoveryWrapper);
    }

    public async Task<bool> CompleteAsync(
        byte[] grantHash, byte[] authSecretVerifier, byte[] authSecretSalt,
        int kdfProfileId, byte[] passwordWrapper, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleAsync<OutcomeRow>(
            new CommandDefinition(
                "[Crypto].[usp_Recovery_Complete]",
                new
                {
                    GrantHash = grantHash,
                    AuthSecretHash = authSecretVerifier,
                    AuthSecretSalt = authSecretSalt,
                    KdfProfileId = kdfProfileId,
                    PasswordWrapper = passwordWrapper
                },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row.Succeeded;
    }

    public async Task<int?> CompleteUnrecoverableAsync(
        byte[] grantHash, byte[] authSecretVerifier, byte[] authSecretSalt,
        int kdfProfileId, Guid newGenerationId, byte[] passwordWrapper,
        byte[] recoveryWrapper, byte[] recoveryPublicKey, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleAsync<DegradedRow>(
            new CommandDefinition(
                "[Crypto].[usp_Recovery_CompleteUnrecoverable]",
                new
                {
                    GrantHash = grantHash,
                    AuthSecretHash = authSecretVerifier,
                    AuthSecretSalt = authSecretSalt,
                    KdfProfileId = kdfProfileId,
                    NewGenerationId = newGenerationId,
                    PasswordWrapper = passwordWrapper,
                    RecoveryWrapper = recoveryWrapper,
                    RecoveryPublicKey = recoveryPublicKey
                },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row.Succeeded ? row.GenerationNumber : null;
    }
}
