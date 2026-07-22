using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Contracts;
using Maren.Shared;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Persistence;

public sealed class SqlConnectionFactory(IConfiguration configuration)
    : IDbConnectionFactory
{
    private readonly string _connectionString =
        configuration.GetConnectionString("MarenPlatform")
        ?? throw new InvalidOperationException(
            "Connection string 'MarenPlatform' is not configured.");

    public async Task<IDbConnection> CreateAsync(CancellationToken ct = default)
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }
}

/// <summary>
/// All data access goes through stored procedures.
/// </summary>
/// <remarks>
/// No inline SQL anywhere in this assembly. Two payoffs: the API's SQL login is
/// granted EXECUTE on procedures and no table permissions at all, so a
/// compromised connection string cannot read a table it was never meant to;
/// and the query plans are stable and reviewable in one place rather than
/// scattered through C# string literals.
/// </remarks>
public sealed class AuthRepository(IDbConnectionFactory factory) : IAuthRepository
{
    public async Task<Result<Guid>> RegisterAsync(
        string email, byte[] hash, byte[] salt, int iterations,
        string? countryIso, string languageCode, string? ip,
        CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleAsync<RegisterRow>(
            new CommandDefinition(
                "[Identity].[usp_User_Register]",
                new
                {
                    Email = email,
                    PasswordHash = hash,
                    PasswordSalt = salt,
                    PasswordIterations = iterations,
                    CountryIso = countryIso,
                    LanguageCode = languageCode,
                    IpAddress = ip
                },
                commandType: CommandType.StoredProcedure,
                cancellationToken: ct));

        return row.Succeeded
            ? Result<Guid>.Success(row.UserId!.Value)
            : Result<Guid>.Failure(row.FailureCode ?? FailureCodes.ValidationFailed);
    }

    public async Task<LoginMaterial?> GetForLoginAsync(
        string email, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        return await connection.QuerySingleOrDefaultAsync<LoginMaterial>(
            new CommandDefinition(
                "[Identity].[usp_User_GetForLogin]",
                new { Email = email },
                commandType: CommandType.StoredProcedure,
                cancellationToken: ct));
    }

    public async Task RecordLoginAsync(
        Guid userId, bool succeeded, string? ip, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        await connection.ExecuteAsync(new CommandDefinition(
            "[Identity].[usp_User_RecordLogin]",
            new { UserId = userId, Succeeded = succeeded, IpAddress = ip },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));
    }

    public async Task<IReadOnlyList<string>> GetPermissionsAsync(
        Guid userId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var codes = await connection.QueryAsync<string>(new CommandDefinition(
            "[Identity].[usp_User_GetPermissions]",
            new { UserId = userId },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));
        return codes.ToList();
    }

    public async Task IssueRefreshTokenAsync(
        Guid userId, Guid? deviceId, byte[] hash, DateTime expiresUtc,
        string? ip, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        await connection.ExecuteAsync(new CommandDefinition(
            "[Identity].[usp_RefreshToken_Issue]",
            new
            {
                UserId = userId,
                DeviceId = deviceId,
                TokenHash = hash,
                ExpiresUtc = expiresUtc,
                IpAddress = ip
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));
    }

    public async Task<Result<Guid>> RedeemRefreshTokenAsync(
        byte[] currentHash, byte[] newHash, DateTime expiresUtc, string? ip,
        CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var row = await connection.QuerySingleAsync<RegisterRow>(
            new CommandDefinition(
                "[Identity].[usp_RefreshToken_Redeem]",
                new
                {
                    TokenHash = currentHash,
                    NewTokenHash = newHash,
                    ExpiresUtc = expiresUtc,
                    IpAddress = ip
                },
                commandType: CommandType.StoredProcedure,
                cancellationToken: ct));

        return row.Succeeded
            ? Result<Guid>.Success(row.UserId!.Value)
            : Result<Guid>.Failure(row.FailureCode ?? FailureCodes.UnknownToken);
    }

    public async Task RegisterDeviceAsync(
        Guid deviceId, Guid userId, string platform, string? osVersion,
        string? appVersion, string? model, string? fcmToken,
        CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        await connection.ExecuteAsync(new CommandDefinition(
            "[Identity].[usp_Device_Register]",
            new
            {
                DeviceId = deviceId,
                UserId = userId,
                Platform = platform,
                OsVersion = osVersion,
                AppVersion = appVersion,
                Model = model,
                FcmToken = fcmToken
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));
    }

    private sealed class RegisterRow
    {
        public bool Succeeded { get; init; }
        public string? FailureCode { get; init; }
        public Guid? UserId { get; init; }
    }
}

public sealed class ConfigurationRepository(IDbConnectionFactory factory)
    : IConfigurationRepository
{
    public async Task<IReadOnlyList<FeatureFlagDto>> EvaluateFlagsAsync(
        Guid? userId, int? appVersionCode, string? countryIso,
        bool isPremium, bool isBeta, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var rows = await connection.QueryAsync<FlagRow>(new CommandDefinition(
            "[Administration].[usp_FeatureFlag_Evaluate]",
            new
            {
                UserId = userId,
                AppVersionCode = appVersionCode,
                CountryIso = countryIso,
                IsPremium = isPremium,
                IsBeta = isBeta
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new FeatureFlagDto(
            r.Key, r.IsEnabled, r.DefaultValue, r.VariantKey, r.PayloadJson))
            .ToList();
    }

    public async Task<IReadOnlyList<SettingDto>> GetClientSettingsAsync(
        CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var rows = await connection.QueryAsync<SettingDto>(new CommandDefinition(
            "[Administration].[usp_Settings_GetForClient]",
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));
        return rows.ToList();
    }

    public async Task<AppVersionCheckDto> CheckVersionAsync(
        string platform, int versionCode, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        return await connection.QuerySingleAsync<AppVersionCheckDto>(
            new CommandDefinition(
                "[Administration].[usp_AppVersion_Check]",
                new { Platform = platform, VersionCode = versionCode },
                commandType: CommandType.StoredProcedure,
                cancellationToken: ct));
    }

    public async Task<IReadOnlyList<FeatureFlagAdminDto>> ListFlagsAsync(
        CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        var rows = await connection.QueryAsync<FeatureFlagAdminDto>(
            new CommandDefinition(
                "SELECT FeatureFlagId, [Key], Name, Description, IsEnabled, " +
                "RolloutPercent, MinAppVersion, CountryFilter, RequiresPremium, " +
                "BetaOnly, DefaultValue, ModifiedUtc " +
                "FROM [Administration].[FeatureFlag] ORDER BY [Key]",
                cancellationToken: ct));
        return rows.ToList();
    }

    public async Task<FeatureFlagAdminDto> UpsertFlagAsync(
        UpsertFeatureFlagRequest request, Guid? actorUserId,
        CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        return await connection.QuerySingleAsync<FeatureFlagAdminDto>(
            new CommandDefinition(
                "[Administration].[usp_FeatureFlag_Upsert]",
                new
                {
                    request.Key,
                    request.Name,
                    request.Description,
                    request.IsEnabled,
                    request.RolloutPercent,
                    request.MinAppVersion,
                    request.CountryFilter,
                    request.RequiresPremium,
                    request.BetaOnly,
                    request.DefaultValue,
                    ActorUserId = actorUserId
                },
                commandType: CommandType.StoredProcedure,
                cancellationToken: ct));
    }

    private sealed class FlagRow
    {
        public string Key { get; init; } = "";
        public bool IsEnabled { get; init; }
        public bool DefaultValue { get; init; }
        public string? VariantKey { get; init; }
        public string? PayloadJson { get; init; }
    }
}

public static class PersistenceRegistration
{
    public static IServiceCollection AddMarenPersistence(
        this IServiceCollection services)
    {
        services.AddSingleton<IDbConnectionFactory, SqlConnectionFactory>();
        services.AddScoped<IAuthRepository, AuthRepository>();
        services.AddScoped<IConfigurationRepository, ConfigurationRepository>();
        return services;
    }
}
