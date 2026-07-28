using FluentValidation;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Growth;

// ---------------------------------------------------------------------------
// Personal Growth Platform — goals
//
// Orchestration only. Progress comes from Growth.fn_ResolveGoals, which reads
// Behaviour through its published interface; nothing here counts a day, derives
// a streak or decides whether a goal is met.
//
// Achievement is deliberately not settable. It is the one number in the
// platform that has to be earned from what she logged, and a command that
// declared it would turn it into one that can be asked for.
// ---------------------------------------------------------------------------

public interface IGoalRepository
{
    Task<IReadOnlyList<GoalProgress>> ResolveAsync(
        Guid userId, DateOnly asOfDate, CancellationToken ct);

    Task<IReadOnlyList<GoalOffer>> OfferAsync(
        Guid userId, string? contextJson, CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode, Guid? UserGoalId)> AdoptAsync(
        Guid userId, AdoptGoalRequest request, DateOnly asOfDate, CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode)> SetStatusAsync(
        Guid userId, Guid userGoalId, string status, CancellationToken ct);

    Task<IReadOnlyList<GoalTemplateSummary>> ListTemplatesAsync(CancellationToken ct);
}

// ---------------------------------------------------------------------------
// Her goals
// ---------------------------------------------------------------------------

/// <summary>Where she stands on every goal she is holding.</summary>
/// <remarks>
/// No permission marker: her own goals, on her own account, with the user id
/// taken from the token. A permission here would be the platform asking whether
/// she may see what she is working towards.
/// </remarks>
public sealed record GetMyGoalsQuery(Guid UserId, DateOnly? AsOfDate)
    : IRequest<Result<IReadOnlyList<GoalProgress>>>;

public sealed class GetMyGoalsHandler(IGoalRepository repository)
    : IRequestHandler<GetMyGoalsQuery, Result<IReadOnlyList<GoalProgress>>>
{
    public async Task<Result<IReadOnlyList<GoalProgress>>> Handle(
        GetMyGoalsQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<GoalProgress>>.Success(
            await repository.ResolveAsync(
                query.UserId,
                query.AsOfDate ?? DateOnly.FromDateTime(DateTime.UtcNow),
                ct));
}

/// <summary>The goals worth offering her.</summary>
public sealed record GetGoalOffersQuery(Guid UserId, string? ContextJson)
    : IRequest<Result<IReadOnlyList<GoalOffer>>>;

public sealed class GetGoalOffersHandler(IGoalRepository repository)
    : IRequestHandler<GetGoalOffersQuery, Result<IReadOnlyList<GoalOffer>>>
{
    public async Task<Result<IReadOnlyList<GoalOffer>>> Handle(
        GetGoalOffersQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<GoalOffer>>.Success(
            await repository.OfferAsync(query.UserId, query.ContextJson, ct));
}

// ---------------------------------------------------------------------------
// Taking one on
// ---------------------------------------------------------------------------

public sealed record AdoptGoalCommand(Guid UserId, AdoptGoalRequest Request)
    : IRequest<Result<Guid>>, ITransactional;

public sealed class AdoptGoalValidator : AbstractValidator<AdoptGoalCommand>
{
    public AdoptGoalValidator()
    {
        RuleFor(x => x.Request.GoalTemplateKey).NotEmpty().MaximumLength(40);

        /*  Her words, and the column's limit. Told before she loses them rather
            than after the database refuses the row. */
        RuleFor(x => x.Request.MotivationText).MaximumLength(300)
            .WithMessage("Keep your reason under 300 characters.");

        RuleFor(x => x.Request.Priority)
            .InclusiveBetween(0, 100)
            .When(x => x.Request.Priority.HasValue);
    }
}

public sealed class AdoptGoalHandler(IGoalRepository repository)
    : IRequestHandler<AdoptGoalCommand, Result<Guid>>
{
    public async Task<Result<Guid>> Handle(AdoptGoalCommand command, CancellationToken ct)
    {
        var (succeeded, failureCode, userGoalId) = await repository.AdoptAsync(
            command.UserId, command.Request,
            DateOnly.FromDateTime(DateTime.UtcNow), ct);

        return succeeded && userGoalId is { } id
            ? Result<Guid>.Success(id)
            : Result<Guid>.Failure(
                failureCode ?? FailureCodes.NotFound,
                "That goal is not one the platform offers.");
    }
}

// ---------------------------------------------------------------------------
// Pausing or letting one go
// ---------------------------------------------------------------------------

public sealed record SetGoalStatusCommand(Guid UserId, Guid UserGoalId, string Status)
    : IRequest<Result>, ITransactional;

public sealed class SetGoalStatusValidator : AbstractValidator<SetGoalStatusCommand>
{
    /*  'achieved' is absent deliberately. Achievement is decided by the engine
        from what she logged; accepting it here would make the one number that
        has to be earned into one that can be asked for. The procedure refuses
        it as well - this message exists so she is told why rather than getting
        a bare rejection. */
    private static readonly string[] Settable = ["active", "paused", "abandoned"];

    public SetGoalStatusValidator()
    {
        RuleFor(x => x.Status)
            .Must(s => Settable.Contains(s))
            .WithMessage("A goal can be resumed, paused or let go. Achieving one "
                       + "comes from what you log.");
    }
}

public sealed class SetGoalStatusHandler(IGoalRepository repository)
    : IRequestHandler<SetGoalStatusCommand, Result>
{
    public async Task<Result> Handle(SetGoalStatusCommand command, CancellationToken ct)
    {
        var (succeeded, failureCode) = await repository.SetStatusAsync(
            command.UserId, command.UserGoalId, command.Status, ct);

        return succeeded
            ? Result.Success()
            : Result.Failure(failureCode ?? FailureCodes.NotFound,
                "That goal is not one of yours.");
    }
}

// ---------------------------------------------------------------------------
// The library — for operators
// ---------------------------------------------------------------------------

/// <summary>
/// The goal library as configured.
/// </summary>
/// <remarks>
/// Gated on <c>content.read</c>, matching the inspector, onboarding and
/// behaviour catalogues. It shows what the platform offers and what each goal
/// is measured by — configuration, not anybody's data. No woman's goals or
/// progress are reachable through it.
/// </remarks>
public sealed record ListGoalTemplatesQuery
    : IRequest<Result<IReadOnlyList<GoalTemplateSummary>>>, IRequirePermission
{
    public string Permission => PlatformPermissions.ContentRead;
}

public sealed class ListGoalTemplatesHandler(IGoalRepository repository)
    : IRequestHandler<ListGoalTemplatesQuery, Result<IReadOnlyList<GoalTemplateSummary>>>
{
    public async Task<Result<IReadOnlyList<GoalTemplateSummary>>> Handle(
        ListGoalTemplatesQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<GoalTemplateSummary>>.Success(
            await repository.ListTemplatesAsync(ct));
}
