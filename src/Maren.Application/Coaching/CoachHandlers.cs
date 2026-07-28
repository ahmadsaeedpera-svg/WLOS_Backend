using FluentValidation;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

/*  Named Coaching rather than Coach so the namespace does not shadow a future
    Coach type, the way Recommendation shadowed its own contract before it
    became Recommend. */
namespace Maren.Application.Coaching;

// ---------------------------------------------------------------------------
// Coach Platform — CQRS
//
// Explanation only. Nothing here assembles, decides, predicts or observes. The
// coach is handed recommendations that already exist and evidence that has
// already been gathered, and fills in a tone pattern.
// ---------------------------------------------------------------------------

public interface ICoachRepository
{
    Task<IReadOnlyList<CoachMessage>> ResolveAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct);

    Task<IReadOnlyList<CoachMessage>> GetAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct);

    Task<IReadOnlyList<CoachToneSummary>> ListTonesAsync(CancellationToken ct);

    Task<SimulateCoachResponse> SimulateAsync(
        string evidenceCsv, int confidence, CancellationToken ct);
}

/// <summary>What the platform is saying to her today, and why in that voice.</summary>
/// <remarks>Her own messages, with the user id taken from the token.</remarks>
public sealed record GetMyCoachQuery(Guid UserId, DateOnly? AsOfDate)
    : IRequest<Result<IReadOnlyList<CoachMessage>>>;

public sealed class GetMyCoachHandler(ICoachRepository repository)
    : IRequestHandler<GetMyCoachQuery, Result<IReadOnlyList<CoachMessage>>>
{
    public async Task<Result<IReadOnlyList<CoachMessage>>> Handle(
        GetMyCoachQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<CoachMessage>>.Success(
            await repository.GetAsync(
                query.UserId,
                query.AsOfDate ?? DateOnly.FromDateTime(DateTime.UtcNow),
                ct));
}

/// <summary>The tone library, for operators. Configuration, not anybody's data.</summary>
public sealed record ListCoachTonesQuery
    : IRequest<Result<IReadOnlyList<CoachToneSummary>>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class ListCoachTonesHandler(ICoachRepository repository)
    : IRequestHandler<ListCoachTonesQuery, Result<IReadOnlyList<CoachToneSummary>>>
{
    public async Task<Result<IReadOnlyList<CoachToneSummary>>> Handle(
        ListCoachTonesQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<CoachToneSummary>>.Success(
            await repository.ListTonesAsync(ct));
}

/// <summary>What the platform would say, given evidence an operator described.</summary>
/// <remarks>
/// Account-free like the rest of the inspector. It assembles with the only copy
/// of the assembly and explains with the only copy of the explanation, so what
/// an operator hears is what she would actually be told.
/// </remarks>
public sealed record SimulateCoachQuery(SimulateRecommendationsRequest Request)
    : IRequest<Result<SimulateCoachResponse>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class SimulateCoachValidator : AbstractValidator<SimulateCoachQuery>
{
    public SimulateCoachValidator()
    {
        /*  Bounded, like the recommendation simulator it shares a request shape
            with. An unbounded string reaching a string-split is a
            denial-of-service vector. */
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

public sealed class SimulateCoachHandler(ICoachRepository repository)
    : IRequestHandler<SimulateCoachQuery, Result<SimulateCoachResponse>>
{
    public async Task<Result<SimulateCoachResponse>> Handle(
        SimulateCoachQuery query, CancellationToken ct) =>
        Result<SimulateCoachResponse>.Success(
            await repository.SimulateAsync(
                query.Request.EvidenceCsv,
                query.Request.Confidence ?? 100,
                ct));
}
