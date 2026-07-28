using FluentValidation;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Onboarding;

// ---------------------------------------------------------------------------
// Data access this slice needs
// ---------------------------------------------------------------------------

public interface IOnboardingRepository
{
    Task<OnboardingOptionsResponse> GetOptionsAsync(CancellationToken ct);

    Task<ProfileDto?> GetProfileAsync(Guid userId, CancellationToken ct);

    Task<Result> SaveProfileAsync(
        Guid userId, SaveProfileRequest request, CancellationToken ct);

    Task<Result> SetLifeStageAsync(
        Guid userId, string lifeStageCode, string? note, CancellationToken ct);

    Task<Result> SetRoleModesAsync(
        Guid userId, IReadOnlyList<string> codes, CancellationToken ct);

    Task<IReadOnlyList<LifeStageHistoryEntry>> GetLifeStageHistoryAsync(
        Guid userId, CancellationToken ct);
}

/// <summary>Failure codes this slice returns. Stable strings, never enums.</summary>
/// <remarks>
/// A shipped app switches on these, and a renumbered enum breaks a client that
/// cannot be updated quickly — the same reasoning as <see cref="FailureCodes"/>.
/// </remarks>
public static class OnboardingFailureCodes
{
    public const string UserNotFound = "USER_NOT_FOUND";
    public const string UnknownLifeStage = "UNKNOWN_LIFE_STAGE";
    public const string UnknownRoleMode = "UNKNOWN_ROLE_MODE";
    public const string InvalidDateOfBirth = "INVALID_DATE_OF_BIRTH";
    public const string ProfileNotFound = "PROFILE_NOT_FOUND";
}

// ---------------------------------------------------------------------------
// Options — what onboarding offers
// ---------------------------------------------------------------------------

/// <summary>The stages, modes and domains onboarding draws its questions from.</summary>
public sealed record GetOnboardingOptionsQuery
    : IRequest<Result<OnboardingOptionsResponse>>, ICacheableQuery
{
    /*  Reference data, identical for everyone, changing only when an editor
        adds a stage. Cached because this is read on the first screen after
        registration by every new account, and it would otherwise be three
        table reads per signup for data that changes monthly at most. */
    public string CacheKey => "onboarding:options";

    public TimeSpan CacheDuration => TimeSpan.FromMinutes(10);
}

public sealed class GetOnboardingOptionsHandler(IOnboardingRepository repository)
    : IRequestHandler<GetOnboardingOptionsQuery, Result<OnboardingOptionsResponse>>
{
    public async Task<Result<OnboardingOptionsResponse>> Handle(
        GetOnboardingOptionsQuery query, CancellationToken ct) =>
        Result<OnboardingOptionsResponse>.Success(
            await repository.GetOptionsAsync(ct));
}

// ---------------------------------------------------------------------------
// Reading her profile
// ---------------------------------------------------------------------------

/// <summary>Her profile, current stage and role modes.</summary>
/// <remarks>
/// Deliberately not cached. Onboarding writes and immediately re-reads, and a
/// stale profile there shows a woman the answer she just corrected.
/// </remarks>
public sealed record GetMyProfileQuery(Guid UserId) : IRequest<Result<ProfileDto>>;

public sealed class GetMyProfileHandler(IOnboardingRepository repository)
    : IRequestHandler<GetMyProfileQuery, Result<ProfileDto>>
{
    public async Task<Result<ProfileDto>> Handle(
        GetMyProfileQuery query, CancellationToken ct)
    {
        var profile = await repository.GetProfileAsync(query.UserId, ct);

        return profile is null
            ? Result<ProfileDto>.Failure(
                OnboardingFailureCodes.ProfileNotFound,
                "We could not find your profile.")
            : Result<ProfileDto>.Success(profile);
    }
}

// ---------------------------------------------------------------------------
// Saving her profile
// ---------------------------------------------------------------------------

public sealed record SaveMyProfileCommand(Guid UserId, SaveProfileRequest Request)
    : IRequest<Result>, ITransactional;

public sealed class SaveMyProfileValidator : AbstractValidator<SaveMyProfileCommand>
{
    public SaveMyProfileValidator()
    {
        RuleFor(x => x.Request.DisplayName)
            .MaximumLength(120)
            .WithMessage("A display name can be up to 120 characters.");

        /*  Checked here as well as in the procedure. The procedure is the
            enforcing copy — anything connecting to the database goes through
            it — but validating here means she gets a field-level message
            instead of a generic failure. */
        RuleFor(x => x.Request.DateOfBirth)
            .Must(BeAPlausibleBirthDate)
            .When(x => x.Request.DateOfBirth.HasValue)
            .WithMessage("That date of birth does not look right. Please check it.");

        RuleFor(x => x.Request.TimeZoneId)
            .MaximumLength(64)
            .WithMessage("That time zone name is too long.");
    }

    private static bool BeAPlausibleBirthDate(DateOnly? value)
    {
        if (value is null) return true;
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        return value.Value <= today && value.Value >= today.AddYears(-120);
    }
}

public sealed class SaveMyProfileHandler(IOnboardingRepository repository)
    : IRequestHandler<SaveMyProfileCommand, Result>
{
    public async Task<Result> Handle(SaveMyProfileCommand command, CancellationToken ct) =>
        await repository.SaveProfileAsync(command.UserId, command.Request, ct);
}

// ---------------------------------------------------------------------------
// Setting her life stage
// ---------------------------------------------------------------------------

public sealed record SetMyLifeStageCommand(Guid UserId, SetLifeStageRequest Request)
    : IRequest<Result>, ITransactional;

public sealed class SetMyLifeStageValidator : AbstractValidator<SetMyLifeStageCommand>
{
    public SetMyLifeStageValidator()
    {
        /*  Only shape is checked here. Whether the code exists is the
            database's question, because the list of stages is data and a
            validator holding a copy would be wrong the day an editor adds one. */
        RuleFor(x => x.Request.LifeStageCode)
            .NotEmpty().WithMessage("Please choose where you are in your life.")
            .MaximumLength(30);

        RuleFor(x => x.Request.Note).MaximumLength(300);
    }
}

public sealed class SetMyLifeStageHandler(IOnboardingRepository repository)
    : IRequestHandler<SetMyLifeStageCommand, Result>
{
    public async Task<Result> Handle(SetMyLifeStageCommand command, CancellationToken ct) =>
        await repository.SetLifeStageAsync(
            command.UserId, command.Request.LifeStageCode, command.Request.Note, ct);
}

// ---------------------------------------------------------------------------
// Setting her role modes
// ---------------------------------------------------------------------------

public sealed record SetMyRoleModesCommand(Guid UserId, SetRoleModesRequest Request)
    : IRequest<Result>, ITransactional;

public sealed class SetMyRoleModesValidator : AbstractValidator<SetMyRoleModesCommand>
{
    public SetMyRoleModesValidator()
    {
        RuleFor(x => x.Request.RoleModeCodes)
            .NotNull().WithMessage("Send an empty list to clear your roles.");

        /*  Bounded. There are eight modes; a request carrying hundreds is a
            defect or an attack, and an unbounded list is a denial-of-service
            vector however unlikely it looks. */
        RuleFor(x => x.Request.RoleModeCodes)
            .Must(codes => codes is null || codes.Count <= 32)
            .WithMessage("That is more roles than we support.");

        RuleForEach(x => x.Request.RoleModeCodes)
            .NotEmpty().MaximumLength(30);
    }
}

public sealed class SetMyRoleModesHandler(IOnboardingRepository repository)
    : IRequestHandler<SetMyRoleModesCommand, Result>
{
    public async Task<Result> Handle(SetMyRoleModesCommand command, CancellationToken ct) =>
        await repository.SetRoleModesAsync(
            command.UserId, command.Request.RoleModeCodes ?? [], ct);
}

// ---------------------------------------------------------------------------
// Her journey so far
// ---------------------------------------------------------------------------

/// <summary>Every stage she has been through, newest first.</summary>
/// <remarks>
/// The longitudinal record is what makes a companion rather than a tracker, so
/// it is exposed from the start even though nothing displays it yet.
/// </remarks>
public sealed record GetMyLifeStageHistoryQuery(Guid UserId)
    : IRequest<Result<IReadOnlyList<LifeStageHistoryEntry>>>;

public sealed class GetMyLifeStageHistoryHandler(IOnboardingRepository repository)
    : IRequestHandler<GetMyLifeStageHistoryQuery,
        Result<IReadOnlyList<LifeStageHistoryEntry>>>
{
    public async Task<Result<IReadOnlyList<LifeStageHistoryEntry>>> Handle(
        GetMyLifeStageHistoryQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<LifeStageHistoryEntry>>.Success(
            await repository.GetLifeStageHistoryAsync(query.UserId, ct));
}
