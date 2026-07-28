using FluentValidation;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

/*  Named for the SQL schema rather than for the noun. A namespace called
    Recommendation would shadow the Recommendation contract type inside its own
    files, and every reference would need qualifying. */
namespace Maren.Application.Recommend;

// ---------------------------------------------------------------------------
// Recommendation Platform — CQRS
//
// Assembly only. Nothing here decides what to suggest, computes a behavioural
// number or applies a threshold; all of that is configured data evaluated by
// Recommend.fn_AssembleFrom, which reads an evidence set and nothing else.
//
// There is deliberately no command to accept or dismiss a recommendation. What
// she does about a suggestion is a timeline event like everything else the
// platform observes, and a separate acceptance store would be a second record
// of her behaviour that Behaviour Intelligence could not see.
// ---------------------------------------------------------------------------

public interface IRecommendationRepository
{
    /// <summary>Assemble and persist. Called by the pipeline, not by every screen.</summary>
    Task<IReadOnlyList<Recommendation>> ResolveAsync(
        Guid userId, DateOnly asOfDate, string? contextJson, CancellationToken ct);

    /// <summary>Read what was assembled and has not expired.</summary>
    Task<IReadOnlyList<Recommendation>> GetAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct);

    Task<IReadOnlyList<RecommendationSummary>> ListAsync(CancellationToken ct);

    Task<SimulateRecommendationsResponse> SimulateAsync(
        string evidenceCsv, int confidence, CancellationToken ct);
}

/// <summary>What the platform is suggesting to her today.</summary>
/// <remarks>
/// No permission marker: her own suggestions, on her own account, with the user
/// id taken from the token.
/// </remarks>
public sealed record GetMyRecommendationsQuery(Guid UserId, DateOnly? AsOfDate)
    : IRequest<Result<IReadOnlyList<Recommendation>>>;

public sealed class GetMyRecommendationsHandler(IRecommendationRepository repository)
    : IRequestHandler<GetMyRecommendationsQuery, Result<IReadOnlyList<Recommendation>>>
{
    public async Task<Result<IReadOnlyList<Recommendation>>> Handle(
        GetMyRecommendationsQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<Recommendation>>.Success(
            await repository.GetAsync(
                query.UserId,
                query.AsOfDate ?? DateOnly.FromDateTime(DateTime.UtcNow),
                ct));
}

/// <summary>The catalogue, for operators. Configuration, not anybody's data.</summary>
public sealed record ListRecommendationsQuery
    : IRequest<Result<IReadOnlyList<RecommendationSummary>>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class ListRecommendationsHandler(IRecommendationRepository repository)
    : IRequestHandler<ListRecommendationsQuery, Result<IReadOnlyList<RecommendationSummary>>>
{
    public async Task<Result<IReadOnlyList<RecommendationSummary>>> Handle(
        ListRecommendationsQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<RecommendationSummary>>.Success(
            await repository.ListAsync(ct));
}

/// <summary>
/// What the platform would suggest, given evidence an operator described.
/// </summary>
/// <remarks>
/// Account-free by construction, like the rest of the inspector: the procedure
/// takes evidence and never a user id, and a SQL assertion fails if any
/// inspector procedure gains one. It runs the same assembly as the real path,
/// because there is only one copy of it.
/// </remarks>
public sealed record SimulateRecommendationsQuery(SimulateRecommendationsRequest Request)
    : IRequest<Result<SimulateRecommendationsResponse>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class SimulateRecommendationsValidator
    : AbstractValidator<SimulateRecommendationsQuery>
{
    public SimulateRecommendationsValidator()
    {
        /*  Bounded. The shorthand is split on commas and each part parsed; an
            unbounded string reaching a string-split is a denial-of-service
            vector, and no real scenario needs more than a few dozen inputs. */
        RuleFor(x => x.Request.EvidenceCsv)
            .NotEmpty().WithMessage("Describe at least one observation.")
            .MaximumLength(4000)
            .WithMessage("That is more evidence than a scenario needs.");

        RuleFor(x => x.Request.Confidence)
            .InclusiveBetween(0, 100)
            .When(x => x.Request.Confidence.HasValue)
            .WithMessage("Confidence is a percentage.");
    }
}

public sealed class SimulateRecommendationsHandler(IRecommendationRepository repository)
    : IRequestHandler<SimulateRecommendationsQuery, Result<SimulateRecommendationsResponse>>
{
    public async Task<Result<SimulateRecommendationsResponse>> Handle(
        SimulateRecommendationsQuery query, CancellationToken ct) =>
        Result<SimulateRecommendationsResponse>.Success(
            await repository.SimulateAsync(
                query.Request.EvidenceCsv,
                query.Request.Confidence ?? 100,
                ct));
}
