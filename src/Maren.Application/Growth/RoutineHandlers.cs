using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Growth;

// ---------------------------------------------------------------------------
// Personal Growth Platform — routines
//
// Orchestration only, and thinner than goals. A routine is several behaviours
// done together, which Behaviour already models as a subject with required
// parts; this layer adds when in the day it belongs and who it is offered to,
// and nothing else.
//
// There is deliberately no command to complete a routine. Completion is derived
// from logged events every time it is asked for. A "mark done" endpoint would
// be a second definition of done, and the first time it disagreed with the
// timeline a woman would see a completed routine beside a broken streak.
// ---------------------------------------------------------------------------

public interface IRoutineRepository
{
    Task<IReadOnlyList<RoutineToday>> TodayAsync(
        Guid userId, DateOnly asOfDate, string? contextJson, CancellationToken ct);

    Task<IReadOnlyList<RoutineSummary>> ListAsync(CancellationToken ct);
}

/// <summary>Her routines for today, in the order they belong to the day.</summary>
/// <remarks>
/// No permission marker: her own routines on her own account, with the user id
/// taken from the token.
/// </remarks>
public sealed record GetMyRoutinesQuery(Guid UserId, DateOnly? AsOfDate)
    : IRequest<Result<IReadOnlyList<RoutineToday>>>;

public sealed class GetMyRoutinesHandler(IRoutineRepository repository)
    : IRequestHandler<GetMyRoutinesQuery, Result<IReadOnlyList<RoutineToday>>>
{
    public async Task<Result<IReadOnlyList<RoutineToday>>> Handle(
        GetMyRoutinesQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<RoutineToday>>.Success(
            await repository.TodayAsync(
                query.UserId,
                query.AsOfDate ?? DateOnly.FromDateTime(DateTime.UtcNow),
                /*  The targeting context is derived server-side by the
                    pipeline, never accepted from the client. A client that
                    supplied it could ask for postpartum routines by claiming to
                    be postpartum. */
                null,
                ct));
}

/// <summary>The routine library, for operators.</summary>
/// <remarks>
/// Configuration, not anybody's data. Gated on <c>content.read</c> like the
/// other catalogues.
/// </remarks>
public sealed record ListRoutinesQuery
    : IRequest<Result<IReadOnlyList<RoutineSummary>>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class ListRoutinesHandler(IRoutineRepository repository)
    : IRequestHandler<ListRoutinesQuery, Result<IReadOnlyList<RoutineSummary>>>
{
    public async Task<Result<IReadOnlyList<RoutineSummary>>> Handle(
        ListRoutinesQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<RoutineSummary>>.Success(
            await repository.ListAsync(ct));
}
