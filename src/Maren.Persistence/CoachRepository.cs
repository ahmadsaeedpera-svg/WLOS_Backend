using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Coaching;
using Maren.Contracts;

namespace Maren.Persistence;

/// <summary>
/// Reads the coach.
/// </summary>
/// <remarks>
/// Four procedures, no SQL. Every message originates in
/// <c>Coach.fn_ExplainFrom</c>, which fills in a tone pattern from a
/// recommendation that already exists.
/// </remarks>
public sealed class CoachRepository(IDbConnectionFactory factory) : ICoachRepository
{
    public async Task<IReadOnlyList<CoachMessage>> ResolveAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<MessageRow>(new CommandDefinition(
            "[Coach].[usp_Coach_Resolve]",
            new
            {
                UserId = userId,
                AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue),
                Persist = true,
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(Map).ToList();
    }

    public async Task<IReadOnlyList<CoachMessage>> GetAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<MessageRow>(new CommandDefinition(
            "[Coach].[usp_Coach_Get]",
            new { UserId = userId, AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue) },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(Map).ToList();
    }

    public async Task<IReadOnlyList<CoachToneSummary>> ListTonesAsync(CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<ToneRow>(new CommandDefinition(
            "[Coach].[usp_Coach_ListTones]",
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new CoachToneSummary(
            r.ToneCode, r.DisplayName, r.Description, r.Pattern, r.Weight,
            r.IsDefault, r.IsActive, r.RuleCount, r.RulesText)).ToList();
    }

    public async Task<SimulateCoachResponse> SimulateAsync(
        string evidenceCsv, int confidence, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        /*  Two result sets: the messages, then every tone with whether this
            evidence selected it. The second answers "why is it not being
            gentle", which a chosen tone alone cannot. */
        using var multi = await connection.QueryMultipleAsync(new CommandDefinition(
            "[Dashboard].[usp_Inspector_SimulateCoach]",
            new { EvidenceCsv = evidenceCsv, Confidence = confidence },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        var messages = (await multi.ReadAsync<MessageRow>()).Select(Map).ToList();
        var tones = (await multi.ReadAsync<SimToneRow>()).Select(t => new SimulatedTone(
            t.ToneCode, t.DisplayName, t.Pattern, t.Weight, t.IsDefault,
            t.IsActive, t.InputKind, t.InputKey, t.Comparison, t.ThresholdValue,
            t.RationaleText, t.WasSupplied, t.IsMatch, t.SuppliedValue)).ToList();

        return new SimulateCoachResponse(messages, tones);
    }

    private static CoachMessage Map(MessageRow r) => new(
        r.RecommendationKey, r.DisplayName, r.ToneCode, r.ToneName,
        r.ToneRationale, r.ToneFromRule, r.MessageText, r.Priority,
        r.Confidence, r.ExpectedEffort, Split(r.EvidenceCsv), r.ExpiresUtc,
        r.EngineVersion);

    private static IReadOnlyList<string> Split(string? csv) =>
        string.IsNullOrWhiteSpace(csv)
            ? []
            : csv.Split(',', StringSplitOptions.RemoveEmptyEntries
                          | StringSplitOptions.TrimEntries);

    private sealed class MessageRow
    {
        public string RecommendationKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string ToneCode { get; init; } = "";
        public string ToneName { get; init; } = "";
        public string ToneRationale { get; init; } = "";
        public bool ToneFromRule { get; init; }
        public string MessageText { get; init; } = "";
        public int Priority { get; init; }
        public int Confidence { get; init; }
        public byte ExpectedEffort { get; init; }
        public string? EvidenceCsv { get; init; }
        public DateTime ExpiresUtc { get; init; }

        /*  The simulation result set carries no version — nothing was stored, so
            there is nothing to attribute. Defaulted rather than made nullable,
            so a client never has to branch on it. */
        public string EngineVersion { get; init; } = "simulated";
    }

    private sealed class ToneRow
    {
        public string ToneCode { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string Description { get; init; } = "";
        public string Pattern { get; init; } = "";
        public int Weight { get; init; }
        public bool IsDefault { get; init; }
        public bool IsActive { get; init; }
        public int RuleCount { get; init; }
        public string RulesText { get; init; } = "";
    }

    private sealed class SimToneRow
    {
        public string ToneCode { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string Pattern { get; init; } = "";
        public int Weight { get; init; }
        public bool IsDefault { get; init; }
        public bool IsActive { get; init; }
        public string? InputKind { get; init; }
        public string? InputKey { get; init; }
        public string? Comparison { get; init; }
        public decimal? ThresholdValue { get; init; }
        public string? RationaleText { get; init; }
        public bool WasSupplied { get; init; }
        public bool IsMatch { get; init; }
        public decimal? SuppliedValue { get; init; }
    }
}
