using FluentValidation;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

/*  Named Predicting rather than Predict so the namespace does not shadow the
    Predict schema's vocabulary in code that uses both, the same reason
    Coaching is not Coach. */
namespace Maren.Application.Predicting;

// ---------------------------------------------------------------------------
// Prediction Platform — CQRS
//
// Framing only. Nothing here computes a probability, and nothing here can: a
// prediction type may only name a measure Behaviour publishes as a probability,
// and the database refuses anything else. Behavioural, never clinical.
// ---------------------------------------------------------------------------

public interface IPredictionRepository
{
    Task<IReadOnlyList<Prediction>> ResolveAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct);

    Task<IReadOnlyList<Prediction>> GetAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct);

    Task<IReadOnlyList<PredictionTypeSummary>> ListTypesAsync(CancellationToken ct);

    Task<SimulatePredictionResponse> SimulateAsync(
        string observationCsv, int confidence, int defaultSpanDays,
        CancellationToken ct);
}

/// <summary>What the platform would say about her behaviour going forward.</summary>
/// <remarks>Her own predictions, with the user id taken from the token.</remarks>
public sealed record GetMyPredictionsQuery(Guid UserId, DateOnly? AsOfDate)
    : IRequest<Result<IReadOnlyList<Prediction>>>;

public sealed class GetMyPredictionsHandler(IPredictionRepository repository)
    : IRequestHandler<GetMyPredictionsQuery, Result<IReadOnlyList<Prediction>>>
{
    public async Task<Result<IReadOnlyList<Prediction>>> Handle(
        GetMyPredictionsQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<Prediction>>.Success(
            await repository.GetAsync(
                query.UserId,
                query.AsOfDate ?? DateOnly.FromDateTime(DateTime.UtcNow),
                ct));
}

/// <summary>The prediction catalogue, for operators. Configuration, not anybody's data.</summary>
public sealed record ListPredictionTypesQuery
    : IRequest<Result<IReadOnlyList<PredictionTypeSummary>>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class ListPredictionTypesHandler(IPredictionRepository repository)
    : IRequestHandler<ListPredictionTypesQuery,
                      Result<IReadOnlyList<PredictionTypeSummary>>>
{
    public async Task<Result<IReadOnlyList<PredictionTypeSummary>>> Handle(
        ListPredictionTypesQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<PredictionTypeSummary>>.Success(
            await repository.ListTypesAsync(ct));
}

/// <summary>What the platform would predict, given observations an operator described.</summary>
/// <remarks>
/// Account-free like the rest of the inspector. It frames with the only copy of
/// the framing, so what an operator sees is what she would actually be told —
/// including everything that would be withheld, and why.
/// </remarks>
public sealed record SimulatePredictionQuery(SimulatePredictionRequest Request)
    : IRequest<Result<SimulatePredictionResponse>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class SimulatePredictionValidator
    : AbstractValidator<SimulatePredictionQuery>
{
    public SimulatePredictionValidator()
    {
        /*  Bounded, like every other simulator here. An unbounded string
            reaching a string-split is a denial-of-service vector. */
        RuleFor(x => x.Request.ObservationCsv)
            .NotEmpty().WithMessage("Describe at least one observation.")
            .MaximumLength(4000)
            .WithMessage("That is more observation than a scenario needs.");

        RuleFor(x => x.Request.Confidence)
            .InclusiveBetween(0, 100)
            .When(x => x.Request.Confidence.HasValue)
            .WithMessage("Confidence is a percentage.");

        /*  A year, matching the widest span the behaviour engine will observe
            over. Beyond that the number is not support, it is a typo. */
        RuleFor(x => x.Request.DefaultSpanDays)
            .InclusiveBetween(1, 365)
            .When(x => x.Request.DefaultSpanDays.HasValue)
            .WithMessage("Support is a number of days between 1 and 365.");
    }
}

public sealed class SimulatePredictionHandler(IPredictionRepository repository)
    : IRequestHandler<SimulatePredictionQuery, Result<SimulatePredictionResponse>>
{
    public async Task<Result<SimulatePredictionResponse>> Handle(
        SimulatePredictionQuery query, CancellationToken ct) =>
        Result<SimulatePredictionResponse>.Success(
            await repository.SimulateAsync(
                query.Request.ObservationCsv,
                query.Request.Confidence ?? 100,
                query.Request.DefaultSpanDays ?? 28,
                ct));
}
