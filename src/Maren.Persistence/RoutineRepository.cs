using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Growth;
using Maren.Contracts;

namespace Maren.Persistence;

/// <summary>
/// Reads routines.
/// </summary>
/// <remarks>
/// <para>
/// <c>usp_Routine_Today</c> returns two result sets in one round trip — the
/// routines, then every step of each. A client rendering a checklist needs
/// both, and two calls would be two chances for them to describe different
/// days.
/// </para>
/// <para>
/// Row types use settable properties rather than positional records, because
/// Dapper matches a positional record by position and a procedure that grows a
/// column throws at runtime (CLAUDE.md §4.2).
/// </para>
/// </remarks>
public sealed class RoutineRepository(IDbConnectionFactory factory) : IRoutineRepository
{
    public async Task<IReadOnlyList<RoutineToday>> TodayAsync(
        Guid userId, DateOnly asOfDate, string? contextJson, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        using var multi = await connection.QueryMultipleAsync(new CommandDefinition(
            "[Growth].[usp_Routine_Today]",
            new
            {
                UserId = userId,
                AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue),
                ContextJson = contextJson,
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        var routines = (await multi.ReadAsync<RoutineRow>()).ToList();
        var steps = (await multi.ReadAsync<StepRow>()).ToList();

        /*  Grouped once here rather than by each client. Two clients grouping
            separately is two chances to drop the optional steps. */
        var byRoutine = steps
            .GroupBy(s => s.RoutineKey)
            .ToDictionary(
                g => g.Key,
                g => (IReadOnlyList<RoutineStep>)g
                    .OrderBy(s => s.SortOrder)
                    .ThenBy(s => s.EventTypeCode, StringComparer.Ordinal)
                    .Select(s => new RoutineStep(
                        s.EventTypeCode, s.StepName, s.IsRequired, s.SortOrder,
                        s.IsDoneToday,
                        s.LastDoneDate is null
                            ? null
                            : DateOnly.FromDateTime(s.LastDoneDate.Value)))
                    .ToList());

        return routines.Select(r => new RoutineToday(
            r.RoutineKey, r.DisplayName, r.SubjectKey, r.PurposeText,
            r.DomainCode, r.StartHour, r.EndHour, r.WindowText, r.BasePriority,
            r.IsHealthSensitive, r.TargetPerDay, r.StepCount, r.RequiredCount,
            r.StepsDoneToday, r.RequiredDoneToday, r.IsDoneToday, r.IsStarted,
            r.Consistency, r.CurrentStreak, r.CompletionProbability,
            r.Confidence, r.StatusText,
            byRoutine.TryGetValue(r.RoutineKey, out var s) ? s : [])).ToList();
    }

    public async Task<IReadOnlyList<RoutineSummary>> ListAsync(CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<SummaryRow>(new CommandDefinition(
            "[Growth].[usp_Routine_ListTemplates]",
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new RoutineSummary(
            r.RoutineKey, r.DisplayName, r.SubjectKey, r.PurposeText,
            r.DomainCode, r.StartHour, r.EndHour, r.WindowText, r.BasePriority,
            r.IsHealthSensitive, r.IsActive, r.TargetPerDay, r.StepCount,
            r.RequiredCount, r.RuleCount, Split(r.StepsCsv))).ToList();
    }

    private static IReadOnlyList<string> Split(string? csv) =>
        string.IsNullOrWhiteSpace(csv)
            ? []
            : csv.Split(',', StringSplitOptions.RemoveEmptyEntries
                          | StringSplitOptions.TrimEntries);

    private sealed class RoutineRow
    {
        public string RoutineKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string SubjectKey { get; init; } = "";
        public string PurposeText { get; init; } = "";
        public string DomainCode { get; init; } = "";
        public byte StartHour { get; init; }
        public byte EndHour { get; init; }
        public string WindowText { get; init; } = "";
        public int BasePriority { get; init; }
        public bool IsHealthSensitive { get; init; }
        public int TargetPerDay { get; init; }
        public int StepCount { get; init; }
        public int RequiredCount { get; init; }
        public int StepsDoneToday { get; init; }
        public int RequiredDoneToday { get; init; }
        public bool IsDoneToday { get; init; }
        public bool IsStarted { get; init; }
        public decimal? Consistency { get; init; }
        public decimal? CurrentStreak { get; init; }
        public decimal? CompletionProbability { get; init; }
        public int Confidence { get; init; }
        public string StatusText { get; init; } = "";
    }

    private sealed class StepRow
    {
        public string RoutineKey { get; init; } = "";
        public string EventTypeCode { get; init; } = "";
        public string StepName { get; init; } = "";
        public bool IsRequired { get; init; }
        public int SortOrder { get; init; }
        public bool IsDoneToday { get; init; }
        public DateTime? LastDoneDate { get; init; }
    }

    private sealed class SummaryRow
    {
        public string RoutineKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string SubjectKey { get; init; } = "";
        public string PurposeText { get; init; } = "";
        public string DomainCode { get; init; } = "";
        public byte StartHour { get; init; }
        public byte EndHour { get; init; }
        public string WindowText { get; init; } = "";
        public int BasePriority { get; init; }
        public bool IsHealthSensitive { get; init; }
        public bool IsActive { get; init; }
        public int TargetPerDay { get; init; }
        public int StepCount { get; init; }
        public int RequiredCount { get; init; }
        public int RuleCount { get; init; }
        public string? StepsCsv { get; init; }
    }
}
