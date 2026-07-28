using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Growth;
using Maren.Contracts;

namespace Maren.Persistence;

/// <summary>
/// Reads and writes goals.
/// </summary>
/// <remarks>
/// Five procedures, no SQL. Progress originates in <c>Growth.fn_ResolveGoals</c>,
/// which reads Behaviour through its published interface; nothing here derives
/// a number.
///
/// Row types use settable properties rather than positional records — Dapper
/// matches a positional record by position, so a procedure that grows a column
/// throws at runtime (CLAUDE.md §4.2). <c>DateOnly</c> is mapped by hand
/// because Dapper binds it neither as a parameter nor from a SQL <c>DATE</c>.
/// </remarks>
public sealed class GoalRepository(IDbConnectionFactory factory) : IGoalRepository
{
    public async Task<IReadOnlyList<GoalProgress>> ResolveAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<GoalRow>(new CommandDefinition(
            "[Growth].[usp_Goal_Resolve]",
            new
            {
                UserId = userId,
                AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue),
                Persist = true,
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new GoalProgress(
            r.UserGoalId, r.GoalTemplateKey, r.DisplayName, r.DomainCode,
            r.PurposeText, r.ExplanationText, r.IsHealthSensitive, r.Status,
            r.MotivationText, r.Priority,
            DateOnly.FromDateTime(r.StartedOn),
            r.TargetDate is null ? null : DateOnly.FromDateTime(r.TargetDate.Value),
            r.AchievedOn is null ? null : DateOnly.FromDateTime(r.AchievedOn.Value),
            r.ExpectedDurationDays, r.MeasureCount, r.MeasuresMet, r.Confidence,
            r.ProgressPercent, r.IsComplete, r.Reason, Split(r.EvidenceCsv),
            r.EngineVersion)).ToList();
    }

    public async Task<IReadOnlyList<GoalOffer>> OfferAsync(
        Guid userId, string? contextJson, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<OfferRow>(new CommandDefinition(
            "[Growth].[usp_Goal_Offer]",
            new { UserId = userId, ContextJson = contextJson },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new GoalOffer(
            r.GoalTemplateKey, r.DisplayName, r.DomainCode, r.PurposeText,
            r.ExplanationText, r.MotivationPrompt, r.BasePriority,
            r.ExpectedDurationDays, r.IsHealthSensitive, r.MeasureCount,
            r.TargetsText)).ToList();
    }

    public async Task<(bool Succeeded, string? FailureCode, Guid? UserGoalId)> AdoptAsync(
        Guid userId, AdoptGoalRequest request, DateOnly asOfDate, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var row = await connection.QuerySingleAsync<AdoptRow>(new CommandDefinition(
            "[Growth].[usp_Goal_Adopt]",
            new
            {
                UserId = userId,
                request.GoalTemplateKey,
                request.MotivationText,
                request.Priority,
                TargetDate = request.TargetDate?.ToDateTime(TimeOnly.MinValue),
                AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue),
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return (row.Succeeded, row.FailureCode, row.UserGoalId);
    }

    public async Task<(bool Succeeded, string? FailureCode)> SetStatusAsync(
        Guid userId, Guid userGoalId, string status, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var row = await connection.QuerySingleAsync<StatusRow>(new CommandDefinition(
            "[Growth].[usp_Goal_SetStatus]",
            new { UserId = userId, UserGoalId = userGoalId, Status = status },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return (row.Succeeded, row.FailureCode);
    }

    public async Task<IReadOnlyList<GoalTemplateSummary>> ListTemplatesAsync(CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<TemplateRow>(new CommandDefinition(
            "[Growth].[usp_Goal_ListTemplates]",
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new GoalTemplateSummary(
            r.GoalTemplateKey, r.DisplayName, r.DomainCode, r.PurposeText,
            r.ExplanationText, r.MotivationPrompt, r.BasePriority,
            r.ExpectedDurationDays, r.IsHealthSensitive, r.IsActive,
            r.MeasureCount, r.RuleCount, r.TargetsText,
            Split(r.MeasuresCsv))).ToList();
    }

    // -----------------------------------------------------------------------

    private static IReadOnlyList<string> Split(string? csv) =>
        string.IsNullOrWhiteSpace(csv)
            ? []
            : csv.Split(',', StringSplitOptions.RemoveEmptyEntries
                          | StringSplitOptions.TrimEntries);

    private sealed class GoalRow
    {
        public Guid UserGoalId { get; init; }
        public string GoalTemplateKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string DomainCode { get; init; } = "";
        public string PurposeText { get; init; } = "";
        public string ExplanationText { get; init; } = "";
        public bool IsHealthSensitive { get; init; }
        public string Status { get; init; } = "";
        public string? MotivationText { get; init; }
        public int Priority { get; init; }
        public DateTime StartedOn { get; init; }
        public DateTime? TargetDate { get; init; }
        public DateTime? AchievedOn { get; init; }
        public int? ExpectedDurationDays { get; init; }
        public int MeasureCount { get; init; }
        public int MeasuresMet { get; init; }
        public int Confidence { get; init; }
        public decimal? ProgressPercent { get; init; }
        public bool IsComplete { get; init; }
        public string Reason { get; init; } = "";
        public string? EvidenceCsv { get; init; }
        public string EngineVersion { get; init; } = "";
    }

    private sealed class OfferRow
    {
        public string GoalTemplateKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string DomainCode { get; init; } = "";
        public string PurposeText { get; init; } = "";
        public string ExplanationText { get; init; } = "";
        public string MotivationPrompt { get; init; } = "";
        public int BasePriority { get; init; }
        public int? ExpectedDurationDays { get; init; }
        public bool IsHealthSensitive { get; init; }
        public int MeasureCount { get; init; }
        public string TargetsText { get; init; } = "";
    }

    private sealed class AdoptRow
    {
        public bool Succeeded { get; init; }
        public string? FailureCode { get; init; }
        public Guid? UserGoalId { get; init; }
    }

    private sealed class StatusRow
    {
        public bool Succeeded { get; init; }
        public string? FailureCode { get; init; }
    }

    private sealed class TemplateRow
    {
        public string GoalTemplateKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string DomainCode { get; init; } = "";
        public string PurposeText { get; init; } = "";
        public string ExplanationText { get; init; } = "";
        public string MotivationPrompt { get; init; } = "";
        public int BasePriority { get; init; }
        public int? ExpectedDurationDays { get; init; }
        public bool IsHealthSensitive { get; init; }
        public bool IsActive { get; init; }
        public int MeasureCount { get; init; }
        public int RuleCount { get; init; }
        public string TargetsText { get; init; } = "";
        public string? MeasuresCsv { get; init; }
    }
}
