using Maren.Application.Abstractions;
using Maren.Application.Crypto;
using Maren.Contracts;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// The client-derived credential path: the parameters a device needs, and the
/// two ways an account comes into existence or comes back.
/// </summary>
/// <remarks>
/// <para>
/// <b>No endpoint here accepts a password.</b> What arrives is an
/// authentication secret her device derived with Argon2id; the key that opens
/// her journal is a different HKDF output of the same master and never leaves
/// the phone. A server that saw the password could derive that key itself,
/// which is the whole reason this path exists alongside the version 1 one.
/// </para>
/// <para>
/// <c>[Authorize]</c> is on the class and <c>[AllowAnonymous]</c> on the three
/// actions that need it. The reverse — anonymous on the class — is how Slice 1
/// shipped a logout endpoint whose <c>[Authorize]</c> was silently overridden,
/// with every test still green.
/// </para>
/// </remarks>
[Route("api/v1/auth/crypto")]
[Authorize]
public sealed class CryptoAuthController(ISender sender) : MarenControllerBase
{
    /// <summary>The Argon2id parameters a device needs before it can derive.</summary>
    /// <remarks>
    /// Answers for every address. It has to be anonymous — a device cannot
    /// prove anything before it has the key these parameters produce — so the
    /// only defence against enumeration is that an unregistered address gets
    /// an answer of the same shape, with a salt derived from the address under
    /// a server-held key.
    /// </remarks>
    [AllowAnonymous]
    [HttpGet("kdf-parameters")]
    public async Task<IActionResult> KdfParameters(
        [FromQuery] string email, CancellationToken ct) =>
        FromResult(await sender.Send(new GetKdfParametersQuery(email), ct));

    [AllowAnonymous]
    [HttpPost("register")]
    public async Task<IActionResult> Register(
        [FromBody] RegisterClientDerivedRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new RegisterClientDerivedCommand(request), ct));

    [AllowAnonymous]
    [HttpPost("login")]
    public async Task<IActionResult> Login(
        [FromBody] LoginClientDerivedRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new LoginClientDerivedCommand(request), ct));

    /// <summary>The generation her records are written under, and its wrapped keys.</summary>
    /// <remarks>
    /// The subject comes from the token. There is no route or body parameter
    /// that could name another account's generation.
    /// </remarks>
    [HttpGet("~/api/v1/me/crypto/generation")]
    public async Task<IActionResult> ActiveGeneration(CancellationToken ct) =>
        FromResult(await sender.Send(new GetActiveGenerationQuery(), ct));

    /// <summary>A new password, and the data key resealed under it.</summary>
    /// <remarks>
    /// Returns a fresh token pair. The change revokes every session including
    /// this one, which is right for a password change and would otherwise sign
    /// her out of the phone she is holding.
    /// </remarks>
    [HttpPost("~/api/v1/me/crypto/password")]
    public async Task<IActionResult> ChangePassword(
        [FromBody] ChangePasswordRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new ChangePasswordCommand(request), ct));

    /// <summary>New twelve words. The old ones stop working.</summary>
    /// <remarks>
    /// Her journal is untouched — this changes which words open the data key,
    /// not the key itself. Both halves of the phrase, what it opens and what
    /// it proves, are replaced in one write.
    /// </remarks>
    [HttpPost("~/api/v1/me/crypto/recovery-phrase")]
    public async Task<IActionResult> ReplaceRecoveryPhrase(
        [FromBody] ReplaceRecoveryPhraseRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new ReplaceRecoveryPhraseCommand(request), ct));
}

/// <summary>
/// Her encrypted records.
/// </summary>
/// <remarks>
/// <para>
/// Everything that passes through here is ciphertext. This API has never seen
/// the contents of a record and cannot: the key is derived on her device from
/// a password this server never receives.
/// </para>
/// <para>
/// Every action is scoped to the account in the token. Nothing takes a user id,
/// and nothing takes a generation — a caller that could name a generation
/// could write new entries under a key that has been retired.
/// </para>
/// </remarks>
[Route("api/v1/me/records")]
[Authorize]
public sealed class RecordsController(ISender sender) : MarenControllerBase
{
    /// <remarks>
    /// The version is supplied by the caller because the envelope was sealed
    /// with it bound into the associated data, so the client has to know it
    /// before sealing. The server accepts the write only if it is exactly one
    /// past what is stored, which makes the concurrency check and the
    /// cryptographic binding the same check.
    /// </remarks>
    [HttpPut("{recordId:guid}")]
    public async Task<IActionResult> Save(
        Guid recordId, [FromBody] SaveRecordRequest request, CancellationToken ct)
    {
        /*  The route is the identity, not the body. Accepting a body id that
            disagreed with the route would give two answers to "which record is
            this", and the interesting bugs live in that gap. */
        if (request.RecordId != recordId)
            return BadRequest(ApiResponse<object>.Fail(
                "RECORD_ID_MISMATCH", "The record id in the body does not match the URL."));

        return FromResult(await sender.Send(new SaveRecordCommand(request), ct));
    }

    [HttpGet]
    public async Task<IActionResult> List(
        [FromQuery] string? kind, [FromQuery] int skip = 0,
        [FromQuery] int take = 50, CancellationToken ct = default) =>
        FromResult(await sender.Send(new GetRecordsQuery(kind, skip, take), ct));

    [HttpGet("{recordId:guid}")]
    public async Task<IActionResult> Get(Guid recordId, CancellationToken ct) =>
        FromResult(await sender.Send(new GetRecordQuery(recordId), ct));

    [HttpDelete("{recordId:guid}")]
    public async Task<IActionResult> Delete(Guid recordId, CancellationToken ct) =>
        FromResult(await sender.Send(new DeleteRecordCommand(recordId), ct));
}

/// <summary>
/// What an operator may see about an account's encrypted records.
/// </summary>
/// <remarks>
/// Counts and states. No content, no per-record timestamps, no sizes, no
/// breakdown by kind — a shape that starts as "how much is there" turns into a
/// behavioural profile one reasonable-sounding request at a time, so it is
/// refused at the contract rather than in a screen.
/// </remarks>
[Route("api/v1/admin/users/{userId:guid}/crypto")]
[Authorize]
public sealed class CryptoAdminController(ISender sender) : MarenControllerBase
{
    [HttpGet]
    public async Task<IActionResult> Summary(Guid userId, CancellationToken ct) =>
        FromResult(await sender.Send(new GetCryptoAccountSummaryQuery(userId), ct));
}

/// <summary>
/// Path R: getting back in with the recovery phrase.
/// </summary>
/// <remarks>
/// <para>
/// Anonymous, necessarily. She is here because she has lost the thing she
/// would authenticate with; requiring authentication would make this endpoint
/// useful only to people who do not need it.
/// </para>
/// <para>
/// So everything here answers for every address, in the same shape, and every
/// refusal is the same code. <b>No endpoint accepts the phrase, the entropy
/// behind it, or a password.</b> What arrives is a signature, and at
/// completion, material her device produced.
/// </para>
/// </remarks>
[Route("api/v1/auth/recovery")]
[AllowAnonymous]
public sealed class RecoveryController(ISender sender) : MarenControllerBase
{
    /// <summary>Something to sign. Issued for any address.</summary>
    [HttpPost("challenge")]
    public async Task<IActionResult> Challenge(
        [FromBody] RecoveryChallengeRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new RecoveryChallengeCommand(request), ct));

    /// <summary>The proof. On success, the wrapped key and a grant.</summary>
    [HttpPost("verify")]
    public async Task<IActionResult> Verify(
        [FromBody] RecoveryVerifyRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new RecoveryVerifyCommand(request), ct));

    /// <summary>The wrapper opened. Her generation and her journal survive.</summary>
    [HttpPost("complete")]
    public async Task<IActionResult> Complete(
        [FromBody] RecoveryCompleteRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new RecoveryCompleteCommand(request), ct));

    /// <summary>
    /// The wrapper did not open. She gets the account and a new key, and the
    /// old generation is not recovered.
    /// </summary>
    [HttpPost("complete-unrecoverable")]
    public async Task<IActionResult> CompleteUnrecoverable(
        [FromBody] RecoveryCompleteUnrecoverableRequest request,
        CancellationToken ct) =>
        FromResult(await sender.Send(
            new RecoveryCompleteUnrecoverableCommand(request), ct));
}
