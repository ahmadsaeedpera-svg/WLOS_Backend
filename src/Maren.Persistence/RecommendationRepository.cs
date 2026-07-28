using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Recommend;
using Maren.Contracts;

namespace Maren.Persistence;

/// <summary>
/// Reads and assembles recommendations.
/// </summary>
/// <remarks>
/// Four procedures, no SQL. Every recommendation originates in
/// <c>Recommend.fn_AssembleFrom</c>, which reads an evidence set; nothing here
/// decides anything.
///
/// Row types use settable properties rather than positional records, because
/// Dapper matches a positional record by position and a procedure that grows a
/// column throws at runtime (CLAUDE.md §4.2).
/// </remarks>
public sealed class RecommendationRepository(IDbConnectionFactory factory)
    : IRecommendationRepository
{
    public async Task<IReadOnlyList<Recommendation>> ResolveAsync(
        Guid userId, DateOnly asOfDate, string? contextJson, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<RecommendationRow>(new CommandDefinition(
            "[Recommend].[usp_Recommendation_Resolve]",
            new
            {
                UserId = userId,
                AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue),
                ContextJson = contextJson,
                Persist = true,
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(Map).ToList();
    }

    public async Task<IReadOnlyList<Recommendation>> GetAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<RecommendationRow>(new CommandDefinition(
            "[Recommend].[usp_Recommendation_Get]",
            new { UserId = userId, AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue) },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(Map).ToList();
    }

    public async Task<IReadOnlyList<RecommendationSummary>> ListAsync(CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<SummaryRow>(new CommandDefinition(
            "[Recommend].[usp_Recommendation_ListTemplates]",
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new RecommendationSummary(
            r.RecommendationKey, r.DisplayName, r.DomainCode, r.BodyText,
            r.BasePriority, r.ExpectedBenefit, r.ExpectedEffort, r.LifetimeHours,
            r.IsHealthSensitive, r.IsActive, r.InputCount, r.RequiredCount,
            r.RuleCount, r.InputsText)).ToList();
    }

    public async Task<SimulateRecommendationsResponse> SimulateAsync(
        string evidenceCsv, int confidence, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        /*  Two result sets in one round trip: what assembled, then every input
            with whether it matched. An operator opening the screen wants both,
            and two calls would be two chances for them to describe different
            evidence. */
        using var multi = await connection.QueryMultipleAsync(new CommandDefinition(
            "[Dashboard].[usp_Inspector_SimulateRecommendations]",
            new { EvidenceCsv = evidenceCsv, Confidence = confidence },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        var assembled = (await multi.ReadAsync<RecommendationRow>()).Select(Map).ToList();
        var inputs = (await multi.ReadAsync<InputRow>()).Select(i => new SimulatedInput(
            i.RecommendationKey, i.DisplayName, i.InputKind, i.InputKey,
            i.Comparison, i.ThresholdValue, i.IsRequired, i.Weight, i.ReasonText,
            i.WasSupplied, i.IsMatch, i.SuppliedValue)).ToList();

        return new SimulateRecommendationsResponse(assembled, inputs);
    }

    // -----------------------------------------------------------------------

    private static Recommendation Map(RecommendationRow r) => new(
        r.RecommendationKey, r.DisplayName, r.DomainCode, r.BodyText,
        r.IsHealthSensitive, r.ExpectedBenefit, r.ExpectedEffort, r.Priority,
        r.Confidence, r.MatchedCount, r.ExpiresUtc, r.Reason,
        Split(r.EvidenceCsv), Split(r.EnginesCsv), r.EngineVersion);

    private static IReadOnlyList<string> Split(string? csv) =>
        string.IsNullOrWhiteSpace(csv)
            ? []
            : csv.Split(',', StringSplitOptions.RemoveEmptyEntries
                          | StringSplitOptions.TrimEntries);

    private sealed class RecommendationRow
    {
        public string RecommendationKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string DomainCode { get; init; } = "";
        public string BodyText { get; init; } = "";
        public bool IsHealthSensitive { get; init; }
        public byte ExpectedBenefit { get; init; }
        public byte ExpectedEffort { get; init; }
        public int Priority { get; init; }
        public int Confidence { get; init; }
        public int MatchedCount { get; init; }
        public DateTime ExpiresUtc { get; init; }
        public string Reason { get; init; } = "";
        public string? EvidenceCsv { get; init; }
        public string? EnginesCsv { get; init; }

        /*  The simulation result set carries no version - nothing was stored,
            so there is nothing to attribute. Defaulted rather than made
            nullable, so a client never has to branch on it. */
        public string EngineVersion { get; init; } = "simulated";
    }

    private sealed class SummaryRow
    {
        public string RecommendationKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string DomainCode { get; init; } = "";
        public string BodyText { get; init; } = "";
        public int BasePriority { get; init; }
        public byte ExpectedBenefit { get; init; }
        public byte ExpectedEffort { get; init; }
        public int LifetimeHours { get; init; }
        public bool IsHealthSensitive { get; init; }
        public bool IsActive { get; init; }
        public int InputCount { get; init; }
        public int RequiredCount { get; init; }
        public int RuleCount { get; init; }
        public string InputsText { get; init; } = "";
    }

    private sealed class InputRow
    {
        public string RecommendationKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string InputKind { get; init; } = "";
        public string InputKey { get; init; } = "";
        public string Comparison { get; init; } = "";
        public decimal? ThresholdValue { get; init; }
        public bool IsRequired { get; init; }
        public int Weight { get; init; }
        public string ReasonText { get; init; } = "";
        public bool WasSupplied { get; init; }
        public bool IsMatch { get; init; }
        public decimal? SuppliedValue { get; init; }
    }
}
