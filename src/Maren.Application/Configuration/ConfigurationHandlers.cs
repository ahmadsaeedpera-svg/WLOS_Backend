using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Configuration;

// ---------------------------------------------------------------------------
// Bootstrap — what the app asks for on launch
// ---------------------------------------------------------------------------

public sealed record BootstrapQuery(
    Guid? UserId,
    string Platform,
    string? AppVersion,
    string? CountryIso,
    bool IsPremium,
    bool IsBeta) : IRequest<Result<BootstrapResponse>>;

public sealed class BootstrapHandler(IConfigurationRepository repository)
    : IRequestHandler<BootstrapQuery, Result<BootstrapResponse>>
{
    public async Task<Result<BootstrapResponse>> Handle(
        BootstrapQuery query, CancellationToken ct)
    {
        var versionCode = VersionCode.Parse(query.AppVersion);

        /*  Sequential rather than parallel.

            Dapper takes a connection per call and these share one pool; firing
            three at once from every launching client triples peak pool
            pressure for a saving measured in single-digit milliseconds against
            a local database. */
        var flags = await repository.EvaluateFlagsAsync(
            query.UserId, versionCode, query.CountryIso,
            query.IsPremium, query.IsBeta, ct);

        var settings = await repository.GetClientSettingsAsync(ct);

        var version = await repository.CheckVersionAsync(
            query.Platform, versionCode, ct);

        return Result<BootstrapResponse>.Success(new BootstrapResponse(
            flags, settings, version, DateTime.UtcNow));
    }
}

// ---------------------------------------------------------------------------
// Admin — list and upsert flags
// ---------------------------------------------------------------------------

public sealed record ListFeatureFlagsQuery
    : IRequest<Result<IReadOnlyList<FeatureFlagAdminDto>>>;

public sealed class ListFeatureFlagsHandler(IConfigurationRepository repository)
    : IRequestHandler<ListFeatureFlagsQuery,
        Result<IReadOnlyList<FeatureFlagAdminDto>>>
{
    public async Task<Result<IReadOnlyList<FeatureFlagAdminDto>>> Handle(
        ListFeatureFlagsQuery query, CancellationToken ct) =>
        Result<IReadOnlyList<FeatureFlagAdminDto>>.Success(
            await repository.ListFlagsAsync(ct));
}

public sealed record UpsertFeatureFlagCommand(UpsertFeatureFlagRequest Request)
    : IRequest<Result<FeatureFlagAdminDto>>;

public sealed class UpsertFeatureFlagValidator
    : AbstractValidator<UpsertFeatureFlagCommand>
{
    public UpsertFeatureFlagValidator()
    {
        RuleFor(x => x.Request.Key)
            .NotEmpty()
            .MaximumLength(100)
            .Matches("^[a-z0-9_]+$")
            .WithMessage("Use lower case, digits and underscores only.");

        RuleFor(x => x.Request.Name).NotEmpty().MaximumLength(200);

        RuleFor(x => x.Request.RolloutPercent)
            .InclusiveBetween((byte)0, (byte)100);

        RuleFor(x => x.Request.MinAppVersion)
            .Matches(@"^\d+\.\d+(\.\d+)?$")
            .When(x => !string.IsNullOrWhiteSpace(x.Request.MinAppVersion))
            .WithMessage("Use a version like 2.1 or 2.1.0.");

        /*  Validated as JSON here rather than trusted at read time. A malformed
            filter would make OPENJSON throw inside flag evaluation, which is on
            the launch path for every client. */
        RuleFor(x => x.Request.CountryFilter)
            .Must(BeAJsonArray)
            .When(x => !string.IsNullOrWhiteSpace(x.Request.CountryFilter))
            .WithMessage("Country filter must be a JSON array, e.g. [\"GB\",\"IE\"].");
    }

    private static bool BeAJsonArray(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return true;
        try
        {
            using var document = System.Text.Json.JsonDocument.Parse(value);
            return document.RootElement.ValueKind ==
                   System.Text.Json.JsonValueKind.Array;
        }
        catch (System.Text.Json.JsonException)
        {
            return false;
        }
    }
}

public sealed class UpsertFeatureFlagHandler(
    IConfigurationRepository repository,
    ICurrentUser currentUser)
    : IRequestHandler<UpsertFeatureFlagCommand, Result<FeatureFlagAdminDto>>
{
    public async Task<Result<FeatureFlagAdminDto>> Handle(
        UpsertFeatureFlagCommand command, CancellationToken ct)
    {
        if (!currentUser.Has("flags.write"))
            return Result<FeatureFlagAdminDto>.Failure(FailureCodes.Forbidden);

        var saved = await repository.UpsertFlagAsync(
            command.Request, currentUser.UserId, ct);

        return Result<FeatureFlagAdminDto>.Success(saved);
    }
}
