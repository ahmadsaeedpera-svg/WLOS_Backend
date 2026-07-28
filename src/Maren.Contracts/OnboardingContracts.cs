namespace Maren.Contracts;

// ---------------------------------------------------------------------------
// Onboarding and the personal profile
//
// These are a published contract with the mobile app. Changing a property here
// is a breaking change for a client that cannot be updated quickly, so
// everything optional is genuinely optional: onboarding learns a woman's life
// a few answers at a time and must be able to stop halfway without losing what
// she has already said.
// ---------------------------------------------------------------------------

/// <summary>A life stage she can choose from.</summary>
/// <remarks>
/// Sent from the server rather than compiled into the app so the wording can be
/// corrected, translated or extended without a store release — the constraint
/// the whole platform is organised around.
/// </remarks>
public sealed record LifeStageOption(
    string LifeStageCode,
    string DisplayName,
    string? Description,
    int SortOrder);

/// <summary>Something she is doing — several may be true at once.</summary>
public sealed record RoleModeOption(
    string RoleModeCode,
    string DisplayName,
    string? Description,
    int SortOrder);

/// <summary>An area of life the platform can organise.</summary>
public sealed record LifeDomainOption(
    string DomainCode,
    string DisplayName,
    string? Description,
    string? ParentDomainCode,
    bool IsHealthSensitive,
    int SortOrder);

/// <summary>Everything onboarding needs to draw its questions.</summary>
/// <remarks>
/// One call rather than three. This is the first screen after registration and
/// the point at which a woman is most likely to abandon; three sequential round
/// trips on a poor connection is a measurable part of that.
/// </remarks>
public sealed record OnboardingOptionsResponse(
    IReadOnlyList<LifeStageOption> LifeStages,
    IReadOnlyList<RoleModeOption> RoleModes,
    IReadOnlyList<LifeDomainOption> Domains);

/// <summary>Her current stage, as she last told us.</summary>
public sealed record CurrentLifeStageDto(
    string LifeStageCode,
    string DisplayName,
    DateOnly StartedOn,
    string Source);

/// <summary>Who she is, as far as the platform knows.</summary>
public sealed record ProfileDto(
    Guid UserId,
    string? DisplayName,
    DateOnly? DateOfBirth,
    string? TimeZoneId,
    string? LanguageCode,
    CurrentLifeStageDto? CurrentLifeStage,
    IReadOnlyList<RoleModeOption> RoleModes,
    DateTime? ModifiedOn);

/// <summary>Updates the details she controls.</summary>
/// <remarks>
/// Every field is nullable and null means "leave this alone", never "clear it".
/// Onboarding sets these a few at a time, and a save that blanked what it was
/// not told would silently discard answers she had already given.
/// </remarks>
public sealed record SaveProfileRequest(
    string? DisplayName,
    DateOnly? DateOfBirth,
    string? TimeZoneId);

/// <summary>Moves her to a life stage.</summary>
public sealed record SetLifeStageRequest(
    string LifeStageCode,
    string? Note);

/// <summary>Replaces her role modes with this set.</summary>
/// <remarks>
/// Replace-all rather than add and remove: the client shows the whole group of
/// toggles, so it always knows the complete answer. An empty list is valid and
/// clears them — a woman who no longer wants to be described as a caregiver has
/// to be able to say so.
/// </remarks>
public sealed record SetRoleModesRequest(
    IReadOnlyList<string> RoleModeCodes);

/// <summary>One stage she has been through.</summary>
public sealed record LifeStageHistoryEntry(
    string LifeStageCode,
    string DisplayName,
    DateOnly StartedOn,
    DateOnly? EndedOn,
    string Source,
    string? Note);
