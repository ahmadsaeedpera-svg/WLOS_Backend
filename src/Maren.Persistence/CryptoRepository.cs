using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Contracts;
using Maren.Shared;

namespace Maren.Persistence;

/// <summary>
/// The key hierarchy and the encrypted records.
/// </summary>
/// <remarks>
/// Calls named procedures and materialises rows, like every other repository
/// here. It composes no SQL and contains no rule — which matters more than
/// usual on this path, because the rules it would be tempting to put here
/// (which generation is active, whether a version is the next one) are the
/// ones that must hold for every caller the database will ever have.
/// </remarks>
public sealed class CryptoRepository(IDbConnectionFactory factory) : ICryptoRepository
{
    // Parallelism, SaltBytes and OutputBytes are TINYINT in the schema, so they
    // are byte here. Dapper binds a positional record by exact constructor
    // signature: an int where the column is a tinyint fails at materialisation,
    // not at compile time.
    private sealed record KdfProfileRow(
        int KdfProfileId, string Algorithm, int MemoryKiB, int Iterations,
        byte Parallelism, byte SaltBytes, byte OutputBytes, bool IsProvisional);

    private sealed record KdfParametersRow(
        byte[] AuthSecretSalt, int KdfProfileId, string Algorithm, int MemoryKiB,
        int Iterations, byte Parallelism, byte OutputBytes);

    private sealed record RegisterRow(
        bool Succeeded, string? FailureCode, Guid? UserId, Guid? GenerationId);

    private sealed record LoginRow(
        Guid UserId, byte CredentialVersion, byte[]? AuthSecretHash,
        byte[]? AuthSecretSalt, int? KdfProfileId, bool IsLockedOut,
        DateTime? LockoutEndUtc);

    private sealed record GenerationRow(
        Guid GenerationId, int GenerationNumber, string State, DateTime CreatedOn);

    private sealed record WrapperRow(string WrapperKind, Guid? DeviceId, byte[] Envelope);

    private sealed record SaveRow(bool Succeeded, string? FailureCode, int? CurrentVersion);

    private sealed record RecordRow(
        Guid RecordId, string RecordKind, int SchemaVersion, int Version,
        byte[] Envelope, int GenerationNumber, DateTime CreatedOn, DateTime ModifiedOn);

    private sealed record DeleteRow(bool Succeeded, string? FailureCode);

    private sealed record SummaryRow(
        Guid UserId, string? Email, int GenerationCount, int ActiveGenerationNumber,
        int RecordCount, bool HasRecoveryWrapper,
        DateTime? FirstRecordOn, DateTime? LastRecordOn);

    public async Task<StoredKdfProfile?> GetCurrentKdfProfileAsync(CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleOrDefaultAsync<KdfProfileRow>(
            new CommandDefinition(
                "[Identity].[usp_UserCredential_GetCurrentKdfProfile]",
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row is null
            ? null
            : new StoredKdfProfile(row.KdfProfileId, row.Algorithm, row.MemoryKiB,
                row.Iterations, row.Parallelism, row.SaltBytes, row.OutputBytes,
                row.IsProvisional);
    }

    public async Task<(byte[] Salt, StoredKdfProfile Profile)?> GetKdfParametersAsync(
        string email, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleOrDefaultAsync<KdfParametersRow>(
            new CommandDefinition(
                "[Identity].[usp_UserCredential_GetKdfParameters]",
                new { Email = email },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        if (row is null) return null;

        /*  The salt's own length is the only honest source for SaltBytes: it
            is what the credential was actually written with, whatever the
            profile row says today. */
        return (row.AuthSecretSalt, new StoredKdfProfile(
            row.KdfProfileId,
            row.Algorithm, row.MemoryKiB, row.Iterations, row.Parallelism,
            SaltBytes: row.AuthSecretSalt.Length,
            row.OutputBytes,
            IsProvisional: false));
    }

    public async Task<Result<Guid>> RegisterClientDerivedAsync(
        RegisterClientDerivedRequest request, byte[] authSecretVerifier,
        string? ip, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleAsync<RegisterRow>(
            new CommandDefinition(
                "[Identity].[usp_User_RegisterClientDerived]",
                new
                {
                    request.Email,
                    request.DateOfBirth,
                    request.GenerationId,
                    AuthSecretHash = authSecretVerifier,
                    request.AuthSecretSalt,
                    request.KdfProfileId,
                    request.PasswordWrapper,
                    request.RecoveryWrapper,
                    request.RecoveryPublicKey,
                    CountryIso = request.CountryIso,
                    LanguageCode = request.LanguageCode ?? "en-GB",
                    IpAddress = ip
                },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row.Succeeded
            ? Result<Guid>.Success(row.UserId!.Value)
            : Result<Guid>.Failure(row.FailureCode!);
    }

    public async Task<ClientDerivedLoginMaterial?> GetForLoginAsync(
        string email, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleOrDefaultAsync<LoginRow>(
            new CommandDefinition(
                "[Identity].[usp_UserCredential_GetForLogin]",
                new { Email = email },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row is null
            ? null
            : new ClientDerivedLoginMaterial(row.UserId, row.CredentialVersion,
                row.AuthSecretHash, row.AuthSecretSalt, row.KdfProfileId,
                row.IsLockedOut, row.LockoutEndUtc);
    }

    public async Task<StoredGeneration?> GetActiveGenerationAsync(
        Guid userId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleOrDefaultAsync<GenerationRow>(
            new CommandDefinition(
                "[Crypto].[usp_Generation_GetActive]",
                new { UserId = userId },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row is null
            ? null
            : new StoredGeneration(row.GenerationId, row.GenerationNumber,
                row.State, row.CreatedOn);
    }

    public async Task<IReadOnlyList<StoredWrapper>> GetWrappersAsync(
        Guid userId, Guid generationId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var rows = await connection.QueryAsync<WrapperRow>(
            new CommandDefinition(
                "[Crypto].[usp_Wrapper_GetForGeneration]",
                new { UserId = userId, GenerationId = generationId },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return rows.Select(r => new StoredWrapper(r.WrapperKind, r.DeviceId, r.Envelope))
                   .ToList();
    }

    public async Task<Result<int>> SaveRecordAsync(
        Guid userId, SaveRecordRequest request, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleAsync<SaveRow>(
            new CommandDefinition(
                "[Crypto].[usp_Record_Save]",
                new
                {
                    UserId = userId,
                    request.RecordId,
                    request.RecordKind,
                    request.SchemaVersion,
                    request.Version,
                    request.Envelope
                },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row.Succeeded
            ? Result<int>.Success(row.CurrentVersion ?? request.Version)
            : Result<int>.Failure(row.FailureCode!);
    }

    public async Task<RecordResponse?> GetRecordAsync(
        Guid userId, Guid recordId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleOrDefaultAsync<RecordRow>(
            new CommandDefinition(
                "[Crypto].[usp_Record_Get]",
                new { UserId = userId, RecordId = recordId },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row is null ? null : ToResponse(row);
    }

    public async Task<IReadOnlyList<RecordResponse>> GetRecordPageAsync(
        Guid userId, string? recordKind, int skip, int take, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var rows = await connection.QueryAsync<RecordRow>(
            new CommandDefinition(
                "[Crypto].[usp_Record_GetPage]",
                new { UserId = userId, RecordKind = recordKind, Skip = skip, Take = take },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return rows.Select(ToResponse).ToList();
    }

    public async Task<bool> DeleteRecordAsync(
        Guid userId, Guid recordId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleAsync<DeleteRow>(
            new CommandDefinition(
                "[Crypto].[usp_Record_Delete]",
                new { UserId = userId, RecordId = recordId },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row.Succeeded;
    }

    public async Task<CryptoAccountSummary?> GetAccountSummaryAsync(
        Guid userId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleOrDefaultAsync<SummaryRow>(
            new CommandDefinition(
                "[Crypto].[usp_Crypto_GetAccountSummary]",
                new { UserId = userId },
                commandType: CommandType.StoredProcedure, cancellationToken: ct));

        return row is null
            ? null
            : new CryptoAccountSummary(row.UserId, row.Email, row.GenerationCount,
                row.ActiveGenerationNumber, row.RecordCount, row.HasRecoveryWrapper,
                row.FirstRecordOn, row.LastRecordOn);
    }

    private static RecordResponse ToResponse(RecordRow r) => new(
        r.RecordId, r.RecordKind, r.SchemaVersion, r.Version, r.Envelope,
        r.GenerationNumber, r.CreatedOn, r.ModifiedOn);
}
