using FluentValidation;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Behaviour;

// ---------------------------------------------------------------------------
// Behaviour Intelligence — CQRS
//
// This layer is orchestration and nothing else. Every behavioural number comes
// from Behaviour.fn_Observe; no streak, consistency figure or probability is
// computed here, and a SQL assertion fails if one appears anywhere outside the
// Behaviour schema.
//
// The reason is not tidiness. Six engines each deciding "did she do this on
// that day" is six chances to decide it differently, and the failure mode is a
// woman reading two screens that disagree about her own week.
// ---------------------------------------------------------------------------

public interface IBehaviourRepository
{
    /// <summary>Observe and persist. Called by the pipeline, not by six engines.</summary>
    Task<IReadOnlyList<BehaviourObservation>> ResolveAsync(
        Guid userId, DateOnly asOfDate, int windowDays, CancellationToken ct);

    /// <summary>Read the last snapshot without recomputing.</summary>
    Task<IReadOnlyList<BehaviourObservation>> GetAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct);

    Task<IReadOnlyList<BehaviourHistoryPoint>> HistoryAsync(
        Guid userId, string subjectKey, string measureCode, int days,
        CancellationToken ct);

    Task<IReadOnlyList<BehaviourSubject>> ListSubjectsAsync(CancellationToken ct);

    Task<IReadOnlyList<BehaviourMeasure>> ListMeasuresAsync(CancellationToken ct);
}

// ---------------------------------------------------------------------------
// Her behaviour
// ---------------------------------------------------------------------------

/// <summary>What the platform has observed about how she lives.</summary>
/// <remarks>
/// No permission marker. This is her own behaviour on her own account, reached
/// through <c>/api/v1/me</c>, and the user id comes from the token rather than
/// the request. A permission here would be the platform asking whether she may
/// see herself.
/// </remarks>
public sealed record GetMyBehaviourQuery(Guid UserId, DateOnly? AsOfDate)
    : IRequest<Result<BehaviourProfile>>;

public sealed class GetMyBehaviourHandler(IBehaviourRepository repository)
    : IRequestHandler<GetMyBehaviourQuery, Result<BehaviourProfile>>
{
    public async Task<Result<BehaviourProfile>> Handle(
        GetMyBehaviourQuery query, CancellationToken ct)
    {
        var asOf = query.AsOfDate ?? DateOnly.FromDateTime(DateTime.UtcNow);

        /*  Reads the snapshot rather than resolving. Resolution is the
            pipeline's job and happens once per request; a read that resolved
            would observe the same woman again on every screen that asked. */
        var observations = await repository.GetAsync(query.UserId, asOf, ct);

        return Result<BehaviourProfile>.Success(
            new BehaviourProfile(asOf, observations));
    }
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

public sealed record GetMyBehaviourHistoryQuery(
    Guid UserId, string SubjectKey, string MeasureCode, int Days)
    : IRequest<Result<IReadOnlyList<BehaviourHistoryPoint>>>;

public sealed class GetMyBehaviourHistoryValidator
    : AbstractValidator<GetMyBehaviourHistoryQuery>
{
    public GetMyBehaviourHistoryValidator()
    {
        RuleFor(x => x.SubjectKey).NotEmpty().MaximumLength(40);
        RuleFor(x => x.MeasureCode).NotEmpty().MaximumLength(30);

        /*  Bounded, like every page size in this platform. A year is the most
            history any measure spans, so more would return nothing but cost
            the read. */
        RuleFor(x => x.Days).InclusiveBetween(1, 365)
            .WithMessage("Ask for between 1 and 365 days.");
    }
}

public sealed class GetMyBehaviourHistoryHandler(IBehaviourRepository repository)
    : IRequestHandler<GetMyBehaviourHistoryQuery, Result<IReadOnlyList<BehaviourHistoryPoint>>>
{
    public async Task<Result<IReadOnlyList<BehaviourHistoryPoint>>> Handle(
        GetMyBehaviourHistoryQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<BehaviourHistoryPoint>>.Success(
            await repository.HistoryAsync(
                query.UserId, query.SubjectKey, query.MeasureCode, query.Days, ct));
}

// ---------------------------------------------------------------------------
// The subject catalogue — for operators
// ---------------------------------------------------------------------------

/// <summary>
/// What the platform is configured to observe.
/// </summary>
/// <remarks>
/// Gated on <c>content.read</c>, matching the inspector and the onboarding
/// configuration. It reveals which timeline events compose which behaviour and
/// how the platform decides a day counts — configuration, not anybody's data.
/// No woman's behaviour is reachable through it.
/// </remarks>
public sealed record ListBehaviourSubjectsQuery
    : IRequest<Result<IReadOnlyList<BehaviourSubject>>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class ListBehaviourSubjectsHandler(IBehaviourRepository repository)
    : IRequestHandler<ListBehaviourSubjectsQuery, Result<IReadOnlyList<BehaviourSubject>>>
{
    public async Task<Result<IReadOnlyList<BehaviourSubject>>> Handle(
        ListBehaviourSubjectsQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<BehaviourSubject>>.Success(
            await repository.ListSubjectsAsync(ct));
}

/// <summary>
/// The measure vocabulary and the spans that gate it.
/// </summary>
/// <remarks>
/// Same gate as the subject catalogue, and for the same reason: it is
/// configuration, not anybody's data.
/// </remarks>
public sealed record ListBehaviourMeasuresQuery
    : IRequest<Result<IReadOnlyList<BehaviourMeasure>>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class ListBehaviourMeasuresHandler(IBehaviourRepository repository)
    : IRequestHandler<ListBehaviourMeasuresQuery, Result<IReadOnlyList<BehaviourMeasure>>>
{
    public async Task<Result<IReadOnlyList<BehaviourMeasure>>> Handle(
        ListBehaviourMeasuresQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<BehaviourMeasure>>.Success(
            await repository.ListMeasuresAsync(ct));
}
