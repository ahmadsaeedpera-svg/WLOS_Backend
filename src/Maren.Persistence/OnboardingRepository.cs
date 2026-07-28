using System.Data;
using Dapper;
using Maren.Application.Abstractions;
using Maren.Application.Onboarding;
using Maren.Contracts;
using Maren.Shared;

namespace Maren.Persistence;

/// <summary>
/// Reads and writes the profile and life-stage model.
/// </summary>
/// <remarks>
/// Calls named stored procedures and materialises the result, like every other
/// repository here. No business rules live in this class: whether a stage code
/// is real, whether a partial save clears untouched fields and whether a
/// transition preserves history are all decided in SQL, where they hold
/// regardless of who connects.
/// </remarks>
public sealed class OnboardingRepository(
    IDbConnectionFactory factory,
    IAmbientConnection ambient) : IOnboardingRepository
{
    public async Task<OnboardingOptionsResponse> GetOptionsAsync(CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        /*  usp_LifeStage_List returns stages and modes in one call; domains
            come from their own procedure. Two round trips rather than three,
            and the two that belong together arrive together. */
        using var multi = await connection.QueryMultipleAsync(new CommandDefinition(
            "[Identity].[usp_LifeStage_List]",
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        var stages = (await multi.ReadAsync<LifeStageOption>()).ToList();
        var modes = (await multi.ReadAsync<RoleModeOption>()).ToList();

        var domains = (await connection.QueryAsync<LifeDomainOption>(
            new CommandDefinition(
                "[Content].[usp_LifeDomain_List]",
                commandType: CommandType.StoredProcedure,
                cancellationToken: ct))).ToList();

        return new OnboardingOptionsResponse(stages, modes, domains);
    }

    public async Task<ProfileDto?> GetProfileAsync(Guid userId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        using var multi = await connection.QueryMultipleAsync(new CommandDefinition(
            "[Identity].[usp_Profile_Get]",
            new { UserId = userId },
            commandType: CommandType.StoredProcedure,
            cancellationToken: ct));

        /*  Three result sets, read in the order the procedure returns them.
            Reading them out of order silently mis-binds — the failure Dapper
            gives is a type error a long way from the cause. */
        var profile = await multi.ReadSingleOrDefaultAsync<ProfileRow>();
        if (profile is null) return null;

        var stageRow = await multi.ReadSingleOrDefaultAsync<CurrentStageRow>();
        var modes = (await multi.ReadAsync<RoleModeOption>()).ToList();

        var stage = stageRow is null ? null : new CurrentLifeStageDto(
            stageRow.LifeStageCode,
            stageRow.DisplayName,
            DateOnly.FromDateTime(stageRow.StartedOn),
            stageRow.Source);

        return new ProfileDto(
            profile.UserId,
            profile.DisplayName,
            profile.DateOfBirth is { } dob ? DateOnly.FromDateTime(dob) : null,
            profile.TimeZoneId,
            profile.LanguageCode,
            stage,
            modes,
            profile.ModifiedOn);
    }

    public async Task<Result> SaveProfileAsync(
        Guid userId, SaveProfileRequest request, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var row = await connection.QuerySingleAsync<OutcomeRow>(
                new CommandDefinition(
                    "[Identity].[usp_Profile_Save]",
                    new
                    {
                        UserId = userId,
                        request.DisplayName,
                        /*  Dapper cannot bind a DateOnly as a parameter value,
                            just as it cannot materialise one from a SQL DATE.
                            Converted here rather than weakening the contract:
                            a date of birth genuinely has no time of day, and
                            the DTO should keep saying so. */
                        DateOfBirth = request.DateOfBirth is { } dob
                            ? dob.ToDateTime(TimeOnly.MinValue)
                            : (DateTime?)null,
                        request.TimeZoneId,
                        ActorUserId = userId
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            return ToResult(row);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<Result> SetLifeStageAsync(
        Guid userId, string lifeStageCode, string? note, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var row = await connection.QuerySingleAsync<OutcomeRow>(
                new CommandDefinition(
                    "[Identity].[usp_UserLifeStage_Set]",
                    new
                    {
                        UserId = userId,
                        LifeStageCode = lifeStageCode,
                        /*  'user', always, from this path. An operator
                            correcting a mistake goes through a support
                            endpoint that does not exist yet, and defaulting
                            to 'user' here would make her history claim she
                            chose something somebody else chose for her. */
                        Source = "user",
                        Note = note,
                        ActorUserId = userId
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            return ToResult(row);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<Result> SetRoleModesAsync(
        Guid userId, IReadOnlyList<string> codes, CancellationToken ct)
    {
        var (connection, transaction, owned) = await ambient.GetAsync(ct);
        try
        {
            var row = await connection.QuerySingleAsync<OutcomeRow>(
                new CommandDefinition(
                    "[Identity].[usp_UserRoleMode_Set]",
                    new
                    {
                        UserId = userId,
                        ModeCodesJson = System.Text.Json.JsonSerializer.Serialize(codes),
                        ActorUserId = userId
                    },
                    transaction, commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));

            return ToResult(row);
        }
        finally
        {
            if (owned) connection.Dispose();
        }
    }

    public async Task<IReadOnlyList<LifeStageHistoryEntry>> GetLifeStageHistoryAsync(
        Guid userId, CancellationToken ct)
    {
        using var connection = await factory.CreateAsync(ct);

        var rows = await connection.QueryAsync<HistoryRow>(
            new CommandDefinition(
                "[Identity].[usp_UserLifeStage_GetHistory]",
                new { UserId = userId },
                commandType: CommandType.StoredProcedure,
                cancellationToken: ct));

        return rows.Select(r => new LifeStageHistoryEntry(
            r.LifeStageCode,
            r.DisplayName,
            DateOnly.FromDateTime(r.StartedOn),
            r.EndedOn is { } ended ? DateOnly.FromDateTime(ended) : null,
            r.Source,
            r.Note)).ToList();
    }

    /*  The procedures all answer with the same two columns, so the mapping
        lives once. Messages are written for the woman reading them: "we could
        not find that option" tells her to pick again, where the raw code would
        become a support ticket. */
    private static Result ToResult(OutcomeRow row) =>
        row.Succeeded
            ? Result.Success()
            : Result.Failure(row.FailureCode ?? "UNKNOWN", MessageFor(row.FailureCode));

    private static string MessageFor(string? code) => code switch
    {
        OnboardingFailureCodes.UserNotFound =>
            "We could not find your account.",
        OnboardingFailureCodes.UnknownLifeStage =>
            "We could not find that option. Please choose again.",
        OnboardingFailureCodes.UnknownRoleMode =>
            "One of those roles is not available. Please choose again.",
        OnboardingFailureCodes.InvalidDateOfBirth =>
            "That date of birth does not look right. Please check it.",
        "INVALID_JSON" =>
            "We could not read that request.",
        _ => "We could not save that. Please try again."
    };

    /// <summary>The shape usp_Profile_Get returns for the profile itself.</summary>
    /// <remarks>
    /// Every column the procedure selects, in the order it selects them.
    /// Dapper materialises a positional record by matching the result set to
    /// the constructor, so omitting one — AvatarMediaId, on the first attempt
    /// at this — throws at runtime rather than at compile time. That is the
    /// failure CLAUDE.md §4.2 describes, and it is why the DTO the API returns
    /// is mapped from this row rather than being read directly.
    /// </remarks>
    private sealed record ProfileRow(
        Guid UserId,
        string? DisplayName,
        DateTime? DateOfBirth,
        string? TimeZoneId,
        Guid? AvatarMediaId,
        string? LanguageCode,
        int? CountryId,
        DateTime? ModifiedOn);

    /// <summary>Her current stage as the procedure returns it.</summary>
    /// <remarks>
    /// <see cref="DateTime"/> rather than <see cref="DateOnly"/>: Dapper does
    /// not bind a SQL <c>DATE</c> to a <c>DateOnly</c> constructor parameter on
    /// a positional record, and the failure is a runtime materialisation error
    /// rather than anything the compiler catches. Converted at this boundary so
    /// the contract can still express "a date with no time", which is what a
    /// life stage actually has.
    /// </remarks>
    private sealed record CurrentStageRow(
        string LifeStageCode,
        string DisplayName,
        DateTime StartedOn,
        string Source);

    /// <summary>
    /// The shape usp_UserLifeStage_GetHistory returns, column for column.
    /// </summary>
    /// <remarks>
    /// Mapped to <see cref="LifeStageHistoryEntry"/> rather than read into it
    /// directly. The DTO is a published contract with the mobile app, and
    /// binding it positionally to a result set would mean every future column
    /// added to the procedure — for a support tool, say — became a breaking
    /// change for a client that cannot be updated quickly.
    /// </remarks>
    private sealed record HistoryRow(
        Guid UserLifeStageId,
        string LifeStageCode,
        string DisplayName,
        DateTime StartedOn,
        DateTime? EndedOn,
        string Source,
        string? Note);

    private sealed record OutcomeRow(bool Succeeded, string? FailureCode);
}
