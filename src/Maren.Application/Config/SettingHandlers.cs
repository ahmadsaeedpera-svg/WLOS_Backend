using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Maren.Shared;
using MediatR;

namespace Maren.Application.Config;

/// <summary>
/// Remote configuration — the operator's most direct lever on the running app.
/// </summary>
/// <remarks>
/// A value changed here reaches every client on its next bootstrap. No APK, no
/// store review. That is also why the write path is permission-gated, audited
/// and type-validated: the blast radius of a bad value is every user of the
/// app, and a client cannot be fixed as quickly as it can be broken.
/// </remarks>
public interface ISettingRepository
{
    Task<PagedResult<SettingAdminDto>> SearchAsync(
        SettingSearchQuery criteria, CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode)> SaveAsync(
        SaveSettingRequest request, Guid? actorUserId, CancellationToken ct);

    Task<(bool Succeeded, string? FailureCode)> DeleteAsync(
        string key, Guid? actorUserId, CancellationToken ct);
}

public static class ConfigPermissions
{
    public const string Read = "settings.read";
    public const string Write = "settings.write";
    public const string Manage = "settings.manage";
}

// ---------------------------------------------------------------------------

public sealed record SearchSettingsQuery(SettingSearchQuery Criteria)
    : IRequest<Result<PagedResult<SettingAdminDto>>>, IRequirePermission
{
    public string Permission => ConfigPermissions.Read;
}

public sealed class SearchSettingsHandler(ISettingRepository repository)
    : IRequestHandler<SearchSettingsQuery, Result<PagedResult<SettingAdminDto>>>
{
    public async Task<Result<PagedResult<SettingAdminDto>>> Handle(
        SearchSettingsQuery request, CancellationToken ct) =>
        Result<PagedResult<SettingAdminDto>>.Success(
            await repository.SearchAsync(request.Criteria, ct));
}

public sealed class SearchSettingsValidator : AbstractValidator<SearchSettingsQuery>
{
    public SearchSettingsValidator()
    {
        RuleFor(x => x.Criteria.Page).GreaterThan(0);
        RuleFor(x => x.Criteria.PageSize).InclusiveBetween(1, 200);
    }
}

// ---------------------------------------------------------------------------

public sealed record SaveSettingCommand(SaveSettingRequest Request)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    public string Permission => ConfigPermissions.Write;
}

public sealed class SaveSettingHandler(
    ISettingRepository repository, ICurrentUser currentUser, IQueryCache cache)
    : IRequestHandler<SaveSettingCommand, Result>
{
    public async Task<Result> Handle(SaveSettingCommand request, CancellationToken ct)
    {
        var (succeeded, failureCode) = await repository.SaveAsync(
            request.Request, currentUser.UserId, ct);

        if (!succeeded)
        {
            return Result.Failure(failureCode!, failureCode switch
            {
                "INVALID_VALUE" =>
                    "That value does not parse as the setting's type. A client "
                    + "reading it would fail at launch.",
                ContentFailureCodes.VersionConflict =>
                    "Somebody else changed this setting while you were editing.",
                _ => "The setting could not be saved."
            });
        }

        // The client bootstrap is cached. Without this the operator changes a
        // value, sees the grid update, and the app keeps serving the old one
        // until the TTL expires — which reads as the feature not working.
        cache.RemoveByPrefix("bootstrap:");
        cache.RemoveByPrefix("settings:");

        return Result.Success();
    }
}

public sealed class SaveSettingValidator : AbstractValidator<SaveSettingCommand>
{
    private static readonly string[] DataTypes =
        ["string", "int", "bool", "decimal", "json"];

    public SaveSettingValidator()
    {
        RuleFor(x => x.Request.Key)
            .NotEmpty().MaximumLength(100)
            // Dotted lower-case segments. The key appears in client code as a
            // constant, so a space or a quote in it is a bug in three languages.
            .Matches("^[a-z][a-z0-9]*(\\.[a-z0-9_]+)*$")
            .WithMessage(
                "A key is dotted lower-case, for example app.support_email.");

        RuleFor(x => x.Request.Value)
            .NotNull()
            .MaximumLength(4000)
            .WithMessage(
                "A configuration value over 4000 characters belongs in the CMS, "
                + "not in config — every client downloads this on every launch.");

        RuleFor(x => x.Request.DataType)
            .Must(t => t is null || DataTypes.Contains(t))
            .WithMessage("Type must be one of: " + string.Join(", ", DataTypes));

        // A secret that is also client-visible is a contradiction that would
        // publish the secret to every device on the next bootstrap.
        RuleFor(x => x.Request)
            .Must(r => !(r.IsSecret == true && r.IsClientVisible == true))
            .WithMessage(
                "A secret cannot be client-visible — every device would receive "
                + "it on the next bootstrap.");
    }
}

// ---------------------------------------------------------------------------

public sealed record DeleteSettingCommand(string Key)
    : IRequest<Result>, IRequirePermission, ITransactional
{
    // Deletion is gated harder than editing. Removing a key silently reverts
    // every client to its compiled default, which is a behaviour change nobody
    // sees in the grid.
    public string Permission => ConfigPermissions.Manage;
}

public sealed class DeleteSettingHandler(
    ISettingRepository repository, ICurrentUser currentUser, IQueryCache cache)
    : IRequestHandler<DeleteSettingCommand, Result>
{
    public async Task<Result> Handle(DeleteSettingCommand request, CancellationToken ct)
    {
        var (succeeded, failureCode) = await repository.DeleteAsync(
            request.Key, currentUser.UserId, ct);

        if (!succeeded)
            return Result.Failure(failureCode!, "The setting could not be deleted.");

        cache.RemoveByPrefix("bootstrap:");
        cache.RemoveByPrefix("settings:");

        return Result.Success();
    }
}
