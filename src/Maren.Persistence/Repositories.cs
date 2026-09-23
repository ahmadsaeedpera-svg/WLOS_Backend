using System.Data;
using Dapper;
using Maren.Application;
using Maren.Application.Abstractions;
using Maren.Application.Access;
using Maren.Application.Behaviour;
using Maren.Application.Coaching;
using Maren.Application.Config;
using Maren.Application.Growth;
using Maren.Application.Inspector;
using Maren.Application.Onboarding;
using Maren.Application.Predicting;
using Maren.Application.Recommend;
using Maren.Application.Wlos;
using Maren.Contracts;
using Maren.Shared;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace Maren.Persistence;

public sealed class SqlConnectionFactory(
    IConfiguration configuration,
    ICorrelationContext correlation)
    : IDbConnectionFactory
{
    private readonly string _connectionString =
        configuration.GetConnectionString("WlosPlatform")
        ?? throw new InvalidOperationException(
            "Connection string 'WlosPlatform' is not configured.");

    public async Task<IDbConnection> CreateAsync(CancellationToken ct = default)
    {
        var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        await StampCorrelationAsync(connection, correlation.CorrelationId, ct);
        return connection;
    }

    /// <summary>
    /// Puts the request's correlation id where the audit defaults can find it.
    /// </summary>
    /// <remarks>
    /// <para>
    /// This is the only place it is set, and it is set on <em>every</em>
    /// connection — including when there is nothing to set, in which case the
    /// value is cleared to NULL.
    /// </para>
    /// <para>
    /// It clears to NULL when there is nothing to set, rather than skipping the
    /// call. This was written believing it was the only thing standing between a
    /// pooled connection and one request's correlation id landing in another
    /// request's audit rows — and that turned out to be false. Removing the
    /// clear entirely does not reproduce the leak: <c>sp_reset_connection</c>,
    /// which the pool issues when handing a connection on, already discards
    /// session context. That was checked by deleting this behaviour and watching
    /// the test still pass, not assumed.
    /// </para>
    /// <para>
    /// It stays because the guarantee it relies on is the pool's, not ours.
    /// <c>Pooling=false</c>, a driver change, or a connection opened outside this
    /// factory would each remove the reset, and the failure mode is silent
    /// misattribution in the one record that gets believed. Cheap insurance
    /// against an assumption held somewhere else — but insurance, and described
    /// as such rather than as the barrier.
    /// </para>
    /// <para>
    /// One extra round trip per connection. That is the cost of the audit trail
    /// being able to say "these rows were one action", and it buys back the 33
    /// procedure signatures the parameter-passing alternative would have
    /// changed.
    /// </para>
    /// </remarks>
    private static async Task StampCorrelationAsync(
        SqlConnection connection, Guid correlationId, CancellationToken ct)
    {
        await using var command = connection.CreateCommand();
        command.CommandText = "EXEC sp_set_session_context @key = N'CorrelationId', @value = @value;";
        command.CommandType = CommandType.Text;

        var parameter = command.CreateParameter();
        parameter.ParameterName = "@value";
        parameter.DbType = DbType.Guid;
        parameter.Value = correlationId == Guid.Empty
            ? DBNull.Value
            : correlationId;
        command.Parameters.Add(parameter);

        await command.ExecuteNonQueryAsync(ct);
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

    public async Task<Guid> GetSecurityStampAsync(Guid userId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);
        return await connection.ExecuteScalarAsync<Guid>(new CommandDefinition(
            "[Identity].[usp_User_GetSecurityStamp]",
            new { UserId = userId },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));
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
                "BetaOnly, DefaultValue, ModifiedOn " +
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
        /*  Registered here, with TryAdd, so any host able to construct a
            connection factory automatically has what the factory needs. A web
            host replaces the source with one that reads the request; a test
            host or a background worker keeps the null object and correlates
            through CorrelationScope instead. Neither has to remember. */
        services.TryAddSingleton<IHttpCorrelationSource, NoHttpCorrelationSource>();
        services.TryAddSingleton<ICorrelationContext, CorrelationContext>();

        services.AddSingleton<IDbConnectionFactory, SqlConnectionFactory>();

        // Scoped so one request shares one unit of work, and so a repository
        // enlisted in a transaction sees the same connection as its siblings.
        services.AddScoped<SqlUnitOfWork>();
        services.AddScoped<IUnitOfWork>(sp => sp.GetRequiredService<SqlUnitOfWork>());
        services.AddScoped<IAmbientConnection>(sp => sp.GetRequiredService<SqlUnitOfWork>());

        services.AddScoped<IAuthRepository, AuthRepository>();
        services.AddScoped<IConfigurationRepository, ConfigurationRepository>();
        services.AddScoped<IContentRepository, ContentRepository>();
        services.AddScoped<IAccessRepository, AccessRepository>();
        services.AddScoped<ISettingRepository, SettingRepository>();
        services.AddScoped<IOnboardingRepository, OnboardingRepository>();
        services.AddScoped<ILifeOsRepository, LifeOsRepository>();
        services.AddScoped<IInspectorRepository, InspectorRepository>();
        services.AddScoped<IBehaviourRepository, BehaviourRepository>();
        services.AddScoped<IGoalRepository, GoalRepository>();
        services.AddScoped<IRoutineRepository, RoutineRepository>();
        services.AddScoped<IRecommendationRepository, RecommendationRepository>();
        services.AddScoped<ICoachRepository, CoachRepository>();
        services.AddScoped<IPredictionRepository, PredictionRepository>();

        /*  The Women's Life OS pipeline, in order.

            Registration order is execution order, and it lives here rather
            than inside the handler so the whole pipeline is readable in one
            place. Stages whose engines do not exist yet are registered
            deliberately: they report themselves as unavailable in the trace,
            which is how an operator sees what the platform cannot yet decide
            instead of inferring it from silence. */
        services.AddScoped<IIntelligenceStage, ContextResolutionStage>();
        services.AddScoped<IIntelligenceStage, ProfileResolutionStage>();
        services.AddScoped<IIntelligenceStage, SignalAnalysisStage>();

        // Computes every dimension once; the nine below present them.
        services.AddScoped<IIntelligenceStage, StateResolutionStage>();
        services.AddScoped<IIntelligenceStage, EnergyResolutionStage>();
        services.AddScoped<IIntelligenceStage, FocusResolutionStage>();
        services.AddScoped<IIntelligenceStage, ConsistencyResolutionStage>();
        services.AddScoped<IIntelligenceStage, WellnessResolutionStage>();
        services.AddScoped<IIntelligenceStage, BalanceResolutionStage>();
        services.AddScoped<IIntelligenceStage, RoutineStateStage>();
        services.AddScoped<IIntelligenceStage, MomentumResolutionStage>();
        services.AddScoped<IIntelligenceStage, LoadResolutionStage>();
        services.AddScoped<IIntelligenceStage, RiskResolutionStage>();

        /*  Behaviour before every engine that reads it. Registration order is
            execution order, and habit, routine, goal, recommendation, coach and
            prediction are all orchestration over what this stage publishes. */
        services.AddScoped<IIntelligenceStage, BehaviourResolutionStage>();
        services.AddScoped<IIntelligenceStage, HabitResolutionStage>();
        /*  Goals after behaviour, because goal progress is the distance
            between what behaviour observed and what the goal asks for. */
        services.AddScoped<IIntelligenceStage, GoalResolutionStage>();
        services.AddScoped<IIntelligenceStage, RoutinePlanResolutionStage>();
        services.AddScoped<IIntelligenceStage, RecommendationResolutionStage>();
        services.AddScoped<IIntelligenceStage, CoachResolutionStage>();
        services.AddScoped<IIntelligenceStage, DashboardResolutionStage>();
        services.AddScoped<IIntelligenceStage, NotificationResolutionStage>();
        services.AddScoped<IIntelligenceStage, PredictionResolutionStage>();
        services.AddScoped<IIntelligenceStage, ConversationContextStage>();
        services.AddScoped<IIntelligenceStage, AiContextResolutionStage>();
        return services;
    }
}
