using System.Diagnostics;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Wlos;

// ---------------------------------------------------------------------------
// The orchestrator, and the data the stages need.
// ---------------------------------------------------------------------------

/// <summary>Data access for the intelligence pipeline, wrapping existing engines.</summary>
public interface ILifeOsRepository
{
    Task<LifeOsContextRow?> GetContextAsync(Guid userId, CancellationToken ct);

    Task<IReadOnlyList<string>> GetRaisedSignalsAsync(
        Guid userId, DateOnly asOf, CancellationToken ct);

    Task<IReadOnlyList<LifeStateReading>> ResolveStateAsync(
        Guid userId, DateOnly asOf, CancellationToken ct);

    Task<IReadOnlyList<DashboardCardRow>> ResolveDashboardAsync(
        Guid userId, string contextJson, DateOnly asOf, int take, CancellationToken ct);
}

public sealed record LifeOsContextRow(
    string? LifeStageCode,
    string? CountryIso,
    string? LanguageCode,
    string? TimeZoneId,
    string RoleModesCsv);

public sealed record DashboardCardRow(
    string CardTypeCode,
    string DisplayName,
    string DomainCode,
    int Priority,
    decimal Confidence,
    int RefreshSeconds,
    int? LifetimeSeconds,
    bool IsHealthSensitive,
    string Reason,
    string EvidenceSignals,
    string Source);

/// <summary>Ask the platform what a woman should see right now.</summary>
public sealed record ResolveLifeOsQuery(Guid UserId, DateOnly? AsOfLocalDate = null)
    : IRequest<Result<LifeOsResponse>>;

/// <summary>Runs the stages in order and assembles one answer.</summary>
/// <remarks>
/// Order is registration order, set in composition root, so the whole pipeline
/// is readable in one place rather than buried in a method here.
/// <para>
/// No stage may fail the pipeline. A stage that throws is recorded as
/// <c>failed</c> with its reason and the run continues — a woman whose
/// recommendation engine broke should still get her dashboard, and an answer
/// missing one section beats no answer at all.
/// </para>
/// </remarks>
public sealed class ResolveLifeOsHandler(IEnumerable<IIntelligenceStage> stages)
    : IRequestHandler<ResolveLifeOsQuery, Result<LifeOsResponse>>
{
    public async Task<Result<LifeOsResponse>> Handle(
        ResolveLifeOsQuery query, CancellationToken ct)
    {
        var asOf = query.AsOfLocalDate ?? DateOnly.FromDateTime(DateTime.UtcNow);

        var context = new IntelligenceContext
        {
            UserId = query.UserId,
            AsOfLocalDate = asOf,
        };

        var trace = new List<IntelligenceStageReport>();

        foreach (var stage in stages)
        {
            context.BeginStage(stage.Name);

            var started = Stopwatch.GetTimestamp();
            IntelligenceResult result;

            try
            {
                result = await stage.ExecuteAsync(context, ct);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                /*  The message, not the exception. This reaches an operator
                    through the inspector, and a stack trace there would leak
                    schema detail into a browser. */
                result = new IntelligenceResult("failed", ex.Message);
            }

            var elapsed = (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds;

            trace.Add(new IntelligenceStageReport(
                Stage: stage.Name,
                Status: result.Status,
                Reason: result.Reason,
                Confidence: result.Confidence,
                ConfidenceFactors: result.ConfidenceFactors ?? [],
                /*  Observed, not declared. A stage cannot misreport what it
                    read or wrote because it never says — the context recorded
                    it. */
                InputsUsed: context.ReadsFor(stage.Name),
                OutputsProduced: context.WritesFor(stage.Name),
                Evidence: result.Evidence ?? [],
                Warnings: result.Warnings ?? [],
                Diagnostics: result.Diagnostics ?? new Dictionary<string, string>(),
                Version: stage.Version,
                ElapsedMs: elapsed));
        }

        context.TryGet<LifeOsContextRow>(IntelligenceKeys.Profile, out var profile);
        context.TryGet<IReadOnlyList<string>>(IntelligenceKeys.RaisedSignals, out var signals);

        var lifeContext = new LifeContext(
            profile?.LifeStageCode,
            ProfileResolutionStage.SplitRoles(profile?.RoleModesCsv).ToList(),
            profile?.CountryIso,
            profile?.LanguageCode,
            profile?.TimeZoneId,
            asOf,
            signals ?? []);

        /*  Sorted once, here. A client that re-sorted would be disagreeing
            with the platform rather than presenting it. */
        var decisions = context.Decisions
            .OrderByDescending(d => d.Priority)
            .ThenBy(d => d.Title, StringComparer.Ordinal)
            .ToList();

        return Result<LifeOsResponse>.Success(new LifeOsResponse(
            query.UserId, DateTime.UtcNow, lifeContext,
            context.State, decisions, trace));
    }
}
