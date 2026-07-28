using Dapper;
using FluentAssertions;
using Maren.Application.Onboarding;
using Maren.Contracts;
using Microsoft.Extensions.DependencyInjection;

namespace Maren.Tests;

/// <summary>
/// Adaptive onboarding, end to end against a real database.
/// </summary>
/// <remarks>
/// These go through the handlers and the real procedures rather than mocking
/// the repository. The rules worth testing here — that a partial save does not
/// clear what it was not told, that a transition keeps her history, that an
/// unknown code is refused — all live in SQL, and a suite that mocked the
/// repository would verify the mocks instead.
/// </remarks>
[Collection("database")]
public sealed class OnboardingIntegrationTests(DatabaseFixture fixture)
{
    private const string Prefix = "onboard-test-";

    private async Task<Guid> CreateUserAsync()
    {
        var id = Guid.NewGuid();
        using var connection = DatabaseFixture.Open();

        await connection.ExecuteAsync(
            """
            INSERT INTO [Identity].[User]
                (UserId, Email, NormalisedEmail, PasswordHash, PasswordSalt,
                 PasswordIterations, SecurityStamp)
            VALUES (@id, @email, UPPER(@email), 0x00, 0x00, 210000, NEWID());
            INSERT INTO [Identity].[Profile] (UserId) VALUES (@id);
            """,
            new { id, email = Prefix + id.ToString("N") + "@example.com" });

        return id;
    }

    private static async Task CleanupAsync()
    {
        using var connection = DatabaseFixture.Open();
        await connection.ExecuteAsync(
            """
            DELETE uls FROM [Identity].[UserLifeStage] uls
              JOIN [Identity].[User] u ON u.UserId = uls.UserId
              WHERE u.Email LIKE @p;
            DELETE urm FROM [Identity].[UserRoleMode] urm
              JOIN [Identity].[User] u ON u.UserId = urm.UserId
              WHERE u.Email LIKE @p;
            DELETE p FROM [Identity].[Profile] p
              JOIN [Identity].[User] u ON u.UserId = p.UserId
              WHERE u.Email LIKE @p;
            DELETE FROM [Identity].[User] WHERE Email LIKE @p;
            """,
            new { p = Prefix + "%" });
    }

    private async Task<T> SendAsync<T>(Func<IServiceProvider, Task<T>> work)
    {
        await using var scope = fixture.Provider.CreateAsyncScope();
        return await work(scope.ServiceProvider);
    }

    // -----------------------------------------------------------------------

    [Fact]
    public async Task Onboarding_offers_stages_roles_and_domains()
    {
        var options = await SendAsync(sp =>
            sp.GetRequiredService<IOnboardingRepository>().GetOptionsAsync(default));

        // Server-driven so the wording ships without a store release.
        options.LifeStages.Should().HaveCountGreaterThanOrEqualTo(12);
        options.RoleModes.Should().HaveCountGreaterThanOrEqualTo(8);
        options.Domains.Should().HaveCountGreaterThanOrEqualTo(25);

        options.LifeStages.Should().Contain(s => s.LifeStageCode == "pregnancy");
        options.LifeStages.Should().Contain(s => s.LifeStageCode == "menopause",
            "the platform serves women well beyond pregnancy");
    }

    [Fact]
    public async Task A_new_account_has_a_profile_but_no_stage_yet()
    {
        var userId = await CreateUserAsync();
        try
        {
            var profile = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetProfileAsync(userId, default));

            profile.Should().NotBeNull();
            profile!.UserId.Should().Be(userId);
            profile.CurrentLifeStage.Should().BeNull(
                "she has not been asked yet, and guessing would be wrong");
            profile.RoleModes.Should().BeEmpty();
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task Her_answers_are_saved_and_read_back()
    {
        var userId = await CreateUserAsync();
        try
        {
            var saved = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>().SaveProfileAsync(
                    userId,
                    new SaveProfileRequest("Aisha", new DateOnly(1994, 3, 2), "Asia/Karachi"),
                    default));
            saved.Succeeded.Should().BeTrue();

            var profile = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetProfileAsync(userId, default));

            profile!.DisplayName.Should().Be("Aisha");
            profile.DateOfBirth.Should().Be(new DateOnly(1994, 3, 2));
            profile.TimeZoneId.Should().Be("Asia/Karachi");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task A_partial_save_does_not_erase_earlier_answers()
    {
        // Onboarding saves each answer as she gives it. A save that blanked
        // what it was not told would discard everything she said before.
        var userId = await CreateUserAsync();
        try
        {
            var repository = fixture.Provider.GetRequiredService<IOnboardingRepository>();

            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SaveProfileAsync(userId,
                    new SaveProfileRequest("Aisha", new DateOnly(1994, 3, 2), "Asia/Karachi"),
                    default));

            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SaveProfileAsync(userId,
                    new SaveProfileRequest(null, null, "Europe/London"), default));

            var profile = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetProfileAsync(userId, default));

            profile!.TimeZoneId.Should().Be("Europe/London");
            profile.DisplayName.Should().Be("Aisha", "it was not part of the update");
            profile.DateOfBirth.Should().Be(new DateOnly(1994, 3, 2));

            _ = repository;
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task A_stage_transition_keeps_her_history()
    {
        // The longitudinal record is what makes a companion rather than a
        // tracker, and it cannot be recovered once a transition discards it.
        var userId = await CreateUserAsync();
        try
        {
            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SetLifeStageAsync(userId, "planning", null, default));
            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SetLifeStageAsync(userId, "pregnancy", null, default));

            var history = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetLifeStageHistoryAsync(userId, default));

            history.Should().HaveCount(2);
            history.Should().Contain(h => h.LifeStageCode == "planning" && h.EndedOn != null);
            history.Should().Contain(h => h.LifeStageCode == "pregnancy" && h.EndedOn == null);

            var profile = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetProfileAsync(userId, default));
            profile!.CurrentLifeStage!.LifeStageCode.Should().Be("pregnancy");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task An_unknown_life_stage_is_refused_with_a_usable_message()
    {
        var userId = await CreateUserAsync();
        try
        {
            var result = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .SetLifeStageAsync(userId, "astronaut", null, default));

            result.Succeeded.Should().BeFalse();
            result.FailureCode.Should().Be(OnboardingFailureCodes.UnknownLifeStage);
            // Surfaced verbatim to her, so it has to say what to do next.
            result.Message.Should().Contain("choose again");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task She_can_hold_several_roles_at_once_and_clear_them()
    {
        // "Busy professional mother" is not a thirteenth life stage; it is a
        // stage plus several roles.
        var userId = await CreateUserAsync();
        try
        {
            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SetRoleModesAsync(userId, ["professional", "caregiver", "partner"], default));

            var profile = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetProfileAsync(userId, default));
            profile!.RoleModes.Should().HaveCount(3);

            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SetRoleModesAsync(userId, [], default));

            profile = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetProfileAsync(userId, default));
            profile!.RoleModes.Should().BeEmpty(
                "she must be able to stop being described a way she no longer is");
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task An_unknown_role_is_refused_rather_than_silently_dropped()
    {
        var userId = await CreateUserAsync();
        try
        {
            var result = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .SetRoleModesAsync(userId, ["professional", "astronaut"], default));

            result.Succeeded.Should().BeFalse();
            result.FailureCode.Should().Be(OnboardingFailureCodes.UnknownRoleMode);

            // Nothing was written: a partial apply would leave her toggles
            // disagreeing with what she pressed.
            var profile = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetProfileAsync(userId, default));
            profile!.RoleModes.Should().BeEmpty();
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task Re_running_onboarding_does_not_litter_her_history()
    {
        // Clients retry and onboarding can be re-entered. Neither should
        // produce a one-day stage she never lived through.
        var userId = await CreateUserAsync();
        try
        {
            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SetLifeStageAsync(userId, "motherhood", null, default));
            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SetLifeStageAsync(userId, "motherhood", null, default));

            var history = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetLifeStageHistoryAsync(userId, default));

            history.Should().HaveCount(1);
        }
        finally { await CleanupAsync(); }
    }

    [Fact]
    public async Task One_womans_answers_never_touch_another_account()
    {
        // The repository is always given the caller's own id — the controller
        // takes it from the token and never from the body. This is the
        // isolation that decision protects.
        var first = await CreateUserAsync();
        var second = await CreateUserAsync();
        try
        {
            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SetLifeStageAsync(first, "pregnancy", null, default));
            await SendAsync(sp => sp.GetRequiredService<IOnboardingRepository>()
                .SaveProfileAsync(first, new SaveProfileRequest("First", null, null), default));

            var other = await SendAsync(sp =>
                sp.GetRequiredService<IOnboardingRepository>()
                  .GetProfileAsync(second, default));

            other!.CurrentLifeStage.Should().BeNull();
            other.DisplayName.Should().BeNull();
        }
        finally { await CleanupAsync(); }
    }
}
