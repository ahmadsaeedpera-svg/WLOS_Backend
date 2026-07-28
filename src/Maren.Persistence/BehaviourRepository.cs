using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Behaviour;
using Maren.Contracts;

namespace Maren.Persistence;

/// <summary>
/// Reads Behaviour Intelligence.
/// </summary>
/// <remarks>
/// <para>
/// Four procedures, no SQL. Every behavioural number originates in
/// <c>Behaviour.fn_Observe</c>; nothing here derives one.
/// </para>
/// <para>
/// Row types are declared with settable properties rather than positional
/// records. A positional record is matched by Dapper against the result set by
/// position, so a procedure that grows a column throws at runtime — three
/// endpoints shipped returning 500 on every call for exactly that reason
/// (CLAUDE.md §4.2). <c>DateOnly</c> is also mapped by hand: Dapper binds it
/// neither as a parameter nor from a SQL <c>DATE</c>.
/// </para>
/// </remarks>
public sealed class BehaviourRepository(IDbConnectionFactory factory) : IBehaviourRepository
{
    public async Task<IReadOnlyList<BehaviourObservation>> ResolveAsync(
        Guid userId, DateOnly asOfDate, int windowDays, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<ObservationRow>(new CommandDefinition(
            "[Behaviour].[usp_Behaviour_Resolve]",
            new
            {
                UserId = userId,
                AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue),
                WindowDays = windowDays,
                Persist = true,
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(Map).ToList();
    }

    public async Task<IReadOnlyList<BehaviourObservation>> GetAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<ObservationRow>(new CommandDefinition(
            "[Behaviour].[usp_Behaviour_Get]",
            new { UserId = userId, AsOfDate = asOfDate.ToDateTime(TimeOnly.MinValue) },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(Map).ToList();
    }

    public async Task<IReadOnlyList<BehaviourHistoryPoint>> HistoryAsync(
        Guid userId, string subjectKey, string measureCode, int days,
        CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<HistoryRow>(new CommandDefinition(
            "[Behaviour].[usp_Behaviour_History]",
            new
            {
                UserId = userId,
                SubjectKey = subjectKey,
                MeasureCode = measureCode,
                Days = days,
            },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new BehaviourHistoryPoint(
            DateOnly.FromDateTime(r.ForLocalDate),
            r.ValueNumeric,
            r.ValueText,
            r.Confidence,
            r.SpanDays,
            r.SupportingEventCount,
            r.EngineVersion)).ToList();
    }

    public async Task<IReadOnlyList<BehaviourSubject>> ListSubjectsAsync(CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<SubjectRow>(new CommandDefinition(
            "[Behaviour].[usp_Behaviour_ListSubjects]",
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        return rows.Select(r => new BehaviourSubject(
            r.SubjectKey, r.DisplayName, r.SubjectKind, r.DomainCode,
            r.IsHealthSensitive, r.TargetPerDay, r.ObservationText, r.IsActive,
            r.PartCount, r.MeasureCount, Split(r.EventTypesCsv))).ToList();
    }

    // -----------------------------------------------------------------------

    private static BehaviourObservation Map(ObservationRow r) => new(
        r.SubjectKey, r.SubjectName, r.DomainCode, r.IsHealthSensitive,
        r.MeasureCode, r.MeasureName, r.Family, r.ValueKind, r.Unit,
        r.ValueNumeric, r.ValueText, r.Confidence, r.SpanDays,
        r.SupportingEventCount,
        r.FirstObservedDate is null ? null : DateOnly.FromDateTime(r.FirstObservedDate.Value),
        r.LastObservedDate is null ? null : DateOnly.FromDateTime(r.LastObservedDate.Value),
        r.Reason, Split(r.EvidenceCsv), r.EngineVersion);

    private static IReadOnlyList<string> Split(string? csv) =>
        string.IsNullOrWhiteSpace(csv)
            ? []
            : csv.Split(',', StringSplitOptions.RemoveEmptyEntries
                          | StringSplitOptions.TrimEntries);

    private sealed class ObservationRow
    {
        public string SubjectKey { get; init; } = "";
        public string SubjectName { get; init; } = "";
        public string DomainCode { get; init; } = "";
        public bool IsHealthSensitive { get; init; }
        public string MeasureCode { get; init; } = "";
        public string MeasureName { get; init; } = "";
        public string Family { get; init; } = "";
        public string ValueKind { get; init; } = "";
        public string? Unit { get; init; }
        public decimal? ValueNumeric { get; init; }
        public string ValueText { get; init; } = "";
        public int Confidence { get; init; }
        public int SpanDays { get; init; }
        public int SupportingEventCount { get; init; }
        public DateTime? FirstObservedDate { get; init; }
        public DateTime? LastObservedDate { get; init; }
        public string Reason { get; init; } = "";
        public string? EvidenceCsv { get; init; }
        public string EngineVersion { get; init; } = "";
    }

    private sealed class HistoryRow
    {
        public DateTime ForLocalDate { get; init; }
        public decimal? ValueNumeric { get; init; }
        public string ValueText { get; init; } = "";
        public int Confidence { get; init; }
        public int SpanDays { get; init; }
        public int SupportingEventCount { get; init; }
        public string EngineVersion { get; init; } = "";
    }

    private sealed class SubjectRow
    {
        public string SubjectKey { get; init; } = "";
        public string DisplayName { get; init; } = "";
        public string SubjectKind { get; init; } = "";
        public string DomainCode { get; init; } = "";
        public bool IsHealthSensitive { get; init; }
        public int TargetPerDay { get; init; }
        public string ObservationText { get; init; } = "";
        public bool IsActive { get; init; }
        public int PartCount { get; init; }
        public int MeasureCount { get; init; }
        public string? EventTypesCsv { get; init; }
    }
}
