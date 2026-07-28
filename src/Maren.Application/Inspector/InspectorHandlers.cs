using FluentValidation;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Inspector;

// ---------------------------------------------------------------------------
// Decision inspector — CQRS
//
// Read-only and account-free. Nothing here takes a user id, which is the
// privacy property the whole inspector exists under and is asserted in SQL as
// well as respected here.
// ---------------------------------------------------------------------------

public interface IInspectorRepository
{
    Task<IReadOnlyList<SimulatedCard>> SimulateAsync(
        string contextJson, string signalsCsv, CancellationToken ct);

    Task<IReadOnlyList<InspectableSignal>> ListSignalsAsync(CancellationToken ct);

    Task<ExplainCardResponse?> ExplainCardAsync(
        string cardTypeCode, string contextJson, CancellationToken ct);
}

// ---------------------------------------------------------------------------
// Simulate
// ---------------------------------------------------------------------------

public sealed record SimulateDashboardQuery(SimulateRequest Request)
    : IRequest<Result<SimulateResponse>>, IRequirePermission
{
    /*  Gated on content.read rather than a permission of its own. The
        inspector reveals which life stages and domains configuration targets -
        the same information the content editor already shows - and inventing a
        permission would mean seeding it and granting it before anybody could
        use a read-only preview. */
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class SimulateDashboardValidator : AbstractValidator<SimulateDashboardQuery>
{
    public SimulateDashboardValidator()
    {
        RuleFor(x => x.Request.LifeStageCode).MaximumLength(30);
        RuleFor(x => x.Request.CountryIso).MaximumLength(10);
        RuleFor(x => x.Request.LanguageCode).MaximumLength(10);

        /*  Bounded. There are eight role modes and a dozen signals; a request
            carrying hundreds is a defect or an attack, and an unbounded list
            reaching a string-join is a denial-of-service vector. */
        RuleFor(x => x.Request.RoleModeCodes)
            .Must(r => r is null || r.Count <= 32)
            .WithMessage("That is more roles than the platform supports.");

        RuleFor(x => x.Request.Signals)
            .Must(s => s is null || s.Count <= 64)
            .WithMessage("That is more signals than the platform supports.");

        RuleForEach(x => x.Request.RoleModeCodes).NotEmpty().MaximumLength(30);
        RuleForEach(x => x.Request.Signals).NotEmpty().MaximumLength(40);
    }
}

public sealed class SimulateDashboardHandler(IInspectorRepository repository)
    : IRequestHandler<SimulateDashboardQuery, Result<SimulateResponse>>
{
    public async Task<Result<SimulateResponse>> Handle(
        SimulateDashboardQuery query, CancellationToken ct)
    {
        var contextJson = InspectorContext.Build(query.Request);
        var signals = query.Request.Signals ?? [];
        var signalsCsv = string.Join(",", signals);

        var cards = await repository.SimulateAsync(contextJson, signalsCsv, ct);

        return Result<SimulateResponse>.Success(
            new SimulateResponse(contextJson, signals, cards));
    }
}

// ---------------------------------------------------------------------------
// Explain one card
// ---------------------------------------------------------------------------

public sealed record ExplainCardQuery(string CardTypeCode, SimulateRequest Request)
    : IRequest<Result<ExplainCardResponse>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class ExplainCardValidator : AbstractValidator<ExplainCardQuery>
{
    public ExplainCardValidator()
    {
        RuleFor(x => x.CardTypeCode)
            .NotEmpty().WithMessage("Choose a card to explain.")
            .MaximumLength(40);
    }
}

public sealed class ExplainCardHandler(IInspectorRepository repository)
    : IRequestHandler<ExplainCardQuery, Result<ExplainCardResponse>>
{
    public async Task<Result<ExplainCardResponse>> Handle(
        ExplainCardQuery query, CancellationToken ct)
    {
        var contextJson = InspectorContext.Build(query.Request);

        var explanation = await repository.ExplainCardAsync(
            query.CardTypeCode, contextJson, ct);

        return explanation is null
            ? Result<ExplainCardResponse>.Failure(
                "NOT_FOUND", "We could not find that card.")
            : Result<ExplainCardResponse>.Success(explanation);
    }
}

/// <summary>The signals an operator may simulate.</summary>
public sealed record ListInspectableSignalsQuery
    : IRequest<Result<IReadOnlyList<InspectableSignal>>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class ListInspectableSignalsHandler(IInspectorRepository repository)
    : IRequestHandler<ListInspectableSignalsQuery, Result<IReadOnlyList<InspectableSignal>>>
{
    public async Task<Result<IReadOnlyList<InspectableSignal>>> Handle(
        ListInspectableSignalsQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<InspectableSignal>>.Success(
            await repository.ListSignalsAsync(ct));
}

// ---------------------------------------------------------------------------
// Context construction
// ---------------------------------------------------------------------------

/// <summary>Builds the targeting context from an operator's hypothetical.</summary>
/// <remarks>
/// The same shape the pipeline's profile resolution produces, so the inspector
/// asks the engines exactly the question the live path asks. A second format
/// here would make the preview subtly disagree with production, which is worse
/// than having no preview.
/// </remarks>
internal static class InspectorContext
{
    public static string Build(SimulateRequest request)
    {
        var parts = new List<string>();

        Add(parts, "life_stage", request.LifeStageCode);

        foreach (var role in request.RoleModeCodes ?? [])
            Add(parts, "role_mode", role);

        Add(parts, "country", request.CountryIso);
        Add(parts, "language", request.LanguageCode);

        return "[" + string.Join(",", parts) + "]";
    }

    private static void Add(List<string> parts, string dimension, string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return;
        parts.Add($$"""{"dimension":"{{Escape(dimension)}}","value":"{{Escape(value)}}"}""");
    }

    /*  These values come from an operator's browser rather than from the
        database's own enumerations, so unlike the pipeline's version this
        escaping is load-bearing rather than defensive: a quote in the input
        would otherwise break out of the JSON string and change which
        dimensions the engine sees. */
    private static string Escape(string value) =>
        value.Replace("\\", "\\\\", StringComparison.Ordinal)
             .Replace("\"", "\\\"", StringComparison.Ordinal);
}
