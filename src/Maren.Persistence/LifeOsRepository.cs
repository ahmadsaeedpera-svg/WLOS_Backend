using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Wlos;

namespace Maren.Persistence;

/// <summary>
/// Data access for the orchestration layer.
/// </summary>
/// <remarks>
/// Wraps engines that already exist rather than reaching past them. Every
/// method calls one named procedure and materialises the result; no rule about
/// eligibility, priority or what a signal means lives here.
/// </remarks>
public sealed class LifeOsRepository(IDbConnectionFactory factory) : ILifeOsRepository
{
    public async Task<LifeOsContextRow?> GetContextAsync(Guid userId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        /*  usp_Profile_Get returns three result sets. Read in order, then
            flattened here into the single row the pipeline wants — a stage
            should not have to know the procedure's shape. */
        using var multi = await connection.QueryMultipleAsync(new CommandDefinition(
            "[Identity].[usp_Profile_Get]",
            new { UserId = userId },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        var profile = await multi.ReadSingleOrDefaultAsync<ProfileRow>();
        if (profile is null) return null;

        var stage = await multi.ReadSingleOrDefaultAsync<StageRow>();
        var modes = (await multi.ReadAsync<ModeRow>()).ToList();

        /*  Country is returned as an id by the profile procedure; the targeting
            vocabulary speaks ISO codes. Resolved here rather than in the stage
            so the pipeline stays free of schema knowledge. */
        string? countryIso = null;
        if (profile.CountryId is { } countryId)
        {
            countryIso = await connection.QuerySingleOrDefaultAsync<string?>(
                new CommandDefinition(
                    "SELECT Iso2 FROM [Identity].[Country] WHERE CountryId = @countryId",
                    new { countryId },
                    cancellationToken: ct));
        }

        return new LifeOsContextRow(
            stage?.LifeStageCode,
            countryIso,
            profile.LanguageCode,
            profile.TimeZoneId,
            string.Join(",", modes.Select(m => m.RoleModeCode)));
    }

    public async Task<IReadOnlyList<string>> GetRaisedSignalsAsync(
        Guid userId, DateOnly asOf, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<SignalRow>(new CommandDefinition(
            "[Knowledge].[usp_Knowledge_EvaluateSignals]",
            new { UserId = userId, AsOfDate = asOf.ToDateTime(TimeOnly.MinValue) },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => r.SignalCode).ToList();
    }

    public async Task<IReadOnlyList<Maren.Contracts.LifeStateReading>> ResolveStateAsync(
        Guid userId, DateOnly asOf, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<StateRow>(new CommandDefinition(
            "[Intelligence].[usp_Intelligence_Resolve]",
            new
            {
                UserId = userId,
                AsOfDate = asOf.ToDateTime(TimeOnly.MinValue),
                WindowDays = 3,
                Persist = true
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new Maren.Contracts.LifeStateReading(
            r.DimensionCode, r.DisplayName, r.ValueCode, r.ValueText, r.Score,
            r.Confidence, r.Reason,
            string.IsNullOrWhiteSpace(r.EvidenceCsv)
                ? []
                : r.EvidenceCsv.Split(',', StringSplitOptions.RemoveEmptyEntries),
            r.Trend, r.PreviousScore)).ToList();
    }

    public async Task<IReadOnlyList<DashboardCardRow>> ResolveDashboardAsync(
        Guid userId, string contextJson, DateOnly asOf, int take, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<CardRow>(new CommandDefinition(
            "[Dashboard].[usp_Dashboard_Resolve]",
            new
            {
                UserId = userId,
                ContextJson = contextJson,
                AsOfDate = asOf.ToDateTime(TimeOnly.MinValue),
                Take = take
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new DashboardCardRow(
            r.CardTypeCode, r.DisplayName, r.DomainCode, r.Priority, r.Confidence,
            r.RefreshSeconds, r.LifetimeSeconds, r.IsHealthSensitive,
            r.Reason, r.EvidenceSignals ?? string.Empty, r.Source)).ToList();
    }

    /*  Private row types matching each procedure's result set column for
        column. Dapper materialises positional records by matching the result
        set to the constructor, so binding a public contract directly would
        make every column added to a procedure a breaking change for the
        clients — the trap CLAUDE.md 4.2 describes, met four times while
        building the onboarding slice. */

    private sealed record ProfileRow(
        Guid UserId, string? DisplayName, DateTime? DateOfBirth, string? TimeZoneId,
        Guid? AvatarMediaId, string? LanguageCode, int? CountryId, DateTime? ModifiedOn);

    private sealed record StageRow(
        string LifeStageCode, string DisplayName, DateTime StartedOn, string Source);

    private sealed record ModeRow(
        string RoleModeCode, string DisplayName, string? Description, int SortOrder);

    private sealed record SignalRow(
        string SignalCode, string DisplayName, string DomainCode,
        string ObservationText, bool IsHealthSensitive, int BreachDays);

    /// <summary>usp_Intelligence_Resolve's result set, column for column.</summary>
    private sealed record StateRow(
        string DimensionCode, string DisplayName, string ValueKind,
        string ValueCode, string ValueText, int? Score, int Confidence,
        string Reason, string? EvidenceCsv, int? PreviousScore,
        DateTime? PreviousDate, string Trend, int SortOrder);

    private sealed record CardRow(
        string CardTypeCode, string DisplayName, string DomainCode, int Priority,
        int BasePriority, decimal Confidence, int RefreshSeconds, int? LifetimeSeconds,
        bool IsDismissible, bool IsHealthSensitive, string Reason,
        string? EvidenceSignals, string Source);
}
