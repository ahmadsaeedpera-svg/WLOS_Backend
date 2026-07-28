using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Inspector;
using Maren.Contracts;

namespace Maren.Persistence;

/// <summary>
/// Reads the inspector's simulations.
/// </summary>
/// <remarks>
/// Calls the two inspector procedures and nothing else. Both are account-free
/// by construction — a SQL assertion fails the build if either ever references
/// a user id, the timeline or a state snapshot.
/// </remarks>
public sealed class InspectorRepository(IDbConnectionFactory factory) : IInspectorRepository
{
    public async Task<IReadOnlyList<SimulatedCard>> SimulateAsync(
        string contextJson, string signalsCsv, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<SimulatedCardRow>(new CommandDefinition(
            "[Dashboard].[usp_Inspector_SimulateDashboard]",
            new { ContextJson = contextJson, SignalsCsv = signalsCsv },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new SimulatedCard(
            r.CardTypeCode, r.DisplayName, r.DomainCode, r.Priority, r.BasePriority,
            r.Confidence, r.IsHealthSensitive, r.IsSuppressed, r.Reason,
            Split(r.EvidenceSignals), r.Source)).ToList();
    }

    public async Task<ExplainCardResponse?> ExplainCardAsync(
        string cardTypeCode, string contextJson, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        /*  Three result sets in one round trip. The procedure returns the card,
            its rules and its adjustments together because an operator opening
            a card wants all three, and three calls would be three chances for
            them to disagree about the context. */
        using var multi = await connection.QueryMultipleAsync(new CommandDefinition(
            "[Dashboard].[usp_Inspector_ExplainCard]",
            new { CardTypeCode = cardTypeCode, ContextJson = contextJson },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        var card = await multi.ReadSingleOrDefaultAsync<CardRow>();
        if (card is null) return null;

        var rules = (await multi.ReadAsync<RuleRow>()).ToList();
        var adjustments = (await multi.ReadAsync<AdjustmentRow>()).ToList();

        return new ExplainCardResponse(
            card.CardTypeCode, card.DisplayName, card.DomainCode, card.BasePriority,
            card.RefreshSeconds, card.LifetimeSeconds, card.IsDismissible,
            card.IsHealthSensitive, card.IsActive,
            rules.Select(r => new InspectedRule(
                r.RuleId, r.DimensionCode, r.DimensionName, r.Operator,
                r.ValuesJson, r.RuleNote, r.ContextPasses)).ToList(),
            adjustments.Select(a => new InspectedAdjustment(
                a.SignalCode, a.SignalName, a.AdjustmentKind, a.Amount,
                a.ReasonText, a.Confidence, a.IsActive)).ToList());
    }

    private static IReadOnlyList<string> Split(string? csv) =>
        string.IsNullOrWhiteSpace(csv)
            ? []
            : csv.Split(',', StringSplitOptions.RemoveEmptyEntries);

    /*  Private row types matching each result set column for column. Dapper
        materialises positional records by matching the result set to the
        constructor, so binding a published contract directly would make every
        column added to a procedure a breaking change for the portal — the trap
        CLAUDE.md 4.2 describes and this project has met repeatedly. */

    private sealed record SimulatedCardRow(
        string CardTypeCode, string DisplayName, string DomainCode, int Priority,
        int BasePriority, decimal Confidence, bool IsHealthSensitive,
        bool IsSuppressed, string Reason, string? EvidenceSignals, string Source);

    private sealed record CardRow(
        string CardTypeCode, string DisplayName, string DomainCode, int BasePriority,
        int RefreshSeconds, int? LifetimeSeconds, bool IsDismissible,
        bool IsHealthSensitive, bool IsActive);

    private sealed record RuleRow(
        Guid RuleId, string DimensionCode, string DimensionName, string Operator,
        string ValuesJson, string RuleNote, bool ContextPasses);

    private sealed record AdjustmentRow(
        string SignalCode, string SignalName, string AdjustmentKind, int Amount,
        string ReasonText, decimal Confidence, bool IsActive);
}
