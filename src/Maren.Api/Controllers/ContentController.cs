using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Maren.Application.Abstractions;
using Maren.Application.Content;
using Maren.Contracts;
using Maren.Shared;
using MediatR;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api.Controllers;

/// <summary>
/// Content administration.
/// </summary>
/// <remarks>
/// Authorization is enforced by the MediatR pipeline via
/// <c>IRequirePermission</c> on each request, not by attributes here.
/// <c>[Authorize]</c> only establishes that there is an authenticated caller;
/// which permission a given operation needs travels with the operation, so a
/// second entry point to the same command cannot forget to check it.
/// </remarks>
[ApiController]
[Route("api/v1/content")]
[Authorize]
[Produces("application/json")]
public sealed class ContentController(ISender sender) : MarenControllerBase
{
    /// <summary>Searches content with paging, filtering and sorting.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<PagedResult<ContentListItemDto>>), 200)]
    public async Task<IActionResult> Search(
        [FromQuery] string? query,
        [FromQuery] string? contentType,
        [FromQuery] string? categoryKey,
        [FromQuery] string? status,
        [FromQuery] string? languageCode,
        [FromQuery] Guid? authorId,
        [FromQuery] string? tag,
        [FromQuery] bool includeDeleted = false,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 25,
        [FromQuery] string sortBy = "modified",
        [FromQuery] bool sortDescending = true,
        CancellationToken ct = default)
    {
        var result = await sender.Send(new SearchContentQuery(
            new ContentSearchQuery(query, contentType, categoryKey, status,
                languageCode, authorId, tag, includeDeleted, page, pageSize,
                sortBy, sortDescending)), ct);

        if (result.Succeeded)
        {
            var paging = result.Value!;
            // Paging metadata in headers as well as the body, so a client can
            // decide whether to fetch more without parsing the payload.
            Response.Headers["X-Total-Count"] =
                paging.TotalCount.ToString(CultureInfo.InvariantCulture);
            Response.Headers["X-Total-Pages"] =
                paging.TotalPages.ToString(CultureInfo.InvariantCulture);
        }

        return FromResult(result);
    }

    /// <summary>Reads one item with all localisations and tags.</summary>
    /// <remarks>
    /// Returns an <c>ETag</c> derived from the item's version number. A client
    /// that sends it back as <c>If-None-Match</c> gets a 304, and the same tag
    /// is what a save should send as <c>If-Match</c> to detect a concurrent
    /// edit.
    /// </remarks>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(ApiResponse<ContentItemDto>), 200)]
    [ProducesResponseType(304)]
    [ProducesResponseType(typeof(ApiResponse<ContentItemDto>), 404)]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct)
    {
        var result = await sender.Send(new GetContentQuery(id), ct);
        if (!result.Succeeded) return FromResult(result);

        var etag = ETagFor(result.Value!.VersionNumber);

        if (Request.Headers.IfNoneMatch.Any(v => v == etag))
            return StatusCode(StatusCodes.Status304NotModified);

        Response.Headers.ETag = etag;
        return Ok(ApiResponse<ContentItemDto>.Ok(result.Value!));
    }

    /// <summary>Creates or updates an item, producing a new version.</summary>
    /// <remarks>
    /// Honours <c>If-Match</c> for optimistic concurrency. Two editors on one
    /// article is ordinary in a CMS, and a silent last-write-wins is how an
    /// afternoon of work disappears with nobody noticing.
    /// </remarks>
    [HttpPut]
    [ProducesResponseType(typeof(ApiResponse<SaveContentResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<SaveContentResponse>), 409)]
    public async Task<IActionResult> Save(
        [FromBody] SaveContentRequest request, CancellationToken ct)
    {
        var expected = request.ExpectedVersionNumber ?? ParseIfMatch();

        var result = await sender.Send(new SaveContentCommand(
            request with { ExpectedVersionNumber = expected }), ct);

        if (result.Succeeded)
            Response.Headers.ETag = ETagFor(result.Value!.VersionNumber);

        return FromResult(result);
    }

    [HttpPost("{id:guid}/publish")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    [ProducesResponseType(typeof(ApiResponse<object>), 409)]
    public async Task<IActionResult> Publish(
        Guid id, [FromBody] PublishContentRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new PublishContentCommand(id, request), ct));

    [HttpPost("{id:guid}/unpublish")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public async Task<IActionResult> Unpublish(Guid id, CancellationToken ct) =>
        FromResult(await sender.Send(new UnpublishContentCommand(id), ct));

    [HttpPost("{id:guid}/approve")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public async Task<IActionResult> Approve(
        Guid id, [FromBody] ApproveContentRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new ApproveContentCommand(id, request), ct));

    [HttpPost("{id:guid}/review")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public async Task<IActionResult> Review(
        Guid id, [FromBody] ReviewContentRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new ReviewContentCommand(id, request), ct));

    [HttpDelete("{id:guid}")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public async Task<IActionResult> Delete(Guid id, CancellationToken ct) =>
        FromResult(await sender.Send(new DeleteContentCommand(id), ct));

    /// <summary>Version history, newest first.</summary>
    [HttpGet("{id:guid}/versions")]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<ContentVersionDto>>), 200)]
    public async Task<IActionResult> Versions(Guid id, CancellationToken ct) =>
        FromResult(await sender.Send(new GetVersionsQuery(id), ct));

    /// <summary>Restores a version by writing it forward as a new one.</summary>
    [HttpPost("{id:guid}/restore")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public async Task<IActionResult> Restore(
        Guid id, [FromBody] RestoreVersionRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(
            new RestoreVersionCommand(id, request.ContentVersionId), ct));

    [HttpPost("{id:guid}/schedule")]
    [ProducesResponseType(typeof(ApiResponse<object>), 200)]
    public async Task<IActionResult> Schedule(
        Guid id, [FromBody] ScheduleContentRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new ScheduleContentCommand(id, request), ct));

    /// <summary>Applies one operation to many items, all or nothing.</summary>
    [HttpPost("bulk")]
    [ProducesResponseType(typeof(ApiResponse<BulkContentResponse>), 200)]
    [ProducesResponseType(typeof(ApiResponse<BulkContentResponse>), 400)]
    public async Task<IActionResult> Bulk(
        [FromBody] BulkContentRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new BulkContentCommand(request), ct));

    [HttpGet("categories")]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<ContentCategoryDto>>), 200)]
    public async Task<IActionResult> Categories(CancellationToken ct) =>
        FromResult(await sender.Send(new GetCategoriesQuery(), ct));

    [HttpPut("authors")]
    [ProducesResponseType(typeof(ApiResponse<ContentAuthorDto>), 200)]
    public async Task<IActionResult> SaveAuthor(
        [FromBody] SaveAuthorRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new SaveAuthorCommand(request), ct));

    /// <summary>
    /// Registers a blob that has already been uploaded to storage.
    /// </summary>
    /// <remarks>
    /// Metadata only — the bytes live in Blob Storage and only the key is
    /// stored. Registering after the upload means a row never points at a blob
    /// that failed to arrive, which would render as a broken image.
    /// </remarks>
    [HttpPut("media")]
    [ProducesResponseType(typeof(ApiResponse<MediaDto>), 200)]
    public async Task<IActionResult> SaveMedia(
        [FromBody] SaveMediaRequest request, CancellationToken ct) =>
        FromResult(await sender.Send(new SaveMediaCommand(request), ct));

    // -----------------------------------------------------------------------

    private int? ParseIfMatch()
    {
        var header = Request.Headers.IfMatch.FirstOrDefault();
        if (string.IsNullOrWhiteSpace(header)) return null;

        var trimmed = header.Trim('"', 'W', '/');
        return int.TryParse(trimmed, out var version) ? version : null;
    }

    /// <summary>
    /// A weak ETag over the version number.
    /// </summary>
    /// <remarks>
    /// The version number rather than a content hash: it already changes on
    /// every write by construction, and hashing the payload would mean loading
    /// and serialising the whole item just to answer a conditional GET.
    /// </remarks>
    private static string ETagFor(int versionNumber) => $"\"{versionNumber}\"";
}

/// <summary>
/// Content for the mobile client.
/// </summary>
/// <remarks>
/// Anonymous. The published library is not secret, and requiring a token would
/// mean a user who has not signed in sees an empty app.
/// </remarks>
[ApiController]
[Route("api/v1/client/content")]
[AllowAnonymous]
[Produces("application/json")]
public sealed class ClientContentController(ISender sender) : MarenControllerBase
{
    /// <summary>Published content matching the caller's context.</summary>
    /// <param name="modifiedSince">
    /// Delta sync. Only items changed after this are returned, so a client
    /// that already has the library re-downloads nothing.
    /// </param>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResponse<IReadOnlyList<ClientContentDto>>), 200)]
    public async Task<IActionResult> Get(
        [FromQuery] string? contentType,
        [FromQuery] string language = "en-GB",
        [FromQuery] string? country = null,
        [FromQuery] string? appVersion = null,
        [FromQuery] byte? week = null,
        [FromQuery] string? season = null,
        [FromQuery] DateTime? modifiedSince = null,
        CancellationToken ct = default)
    {
        var result = await sender.Send(new GetClientContentQuery(
            contentType, language, country,
            appVersion is null ? null : VersionCode.Parse(appVersion),
            week, season, modifiedSince), ct);

        if (!result.Succeeded) return FromResult(result);

        var items = result.Value!;

        // ETag over the newest ModifiedOn and the row count. Together those
        // change whenever the set changes — a publish moves the timestamp, an
        // unpublish moves the count — without hashing every body.
        var newest = items.Count == 0
            ? DateTime.MinValue
            : items.Max(i => i.ModifiedOn);

        var etag = WeakETag($"{newest:O}:{items.Count}");

        if (Request.Headers.IfNoneMatch.Any(v => v == etag))
            return StatusCode(StatusCodes.Status304NotModified);

        Response.Headers.ETag = etag;
        return Ok(ApiResponse<IReadOnlyList<ClientContentDto>>.Ok(items));
    }

    private static string WeakETag(string seed)
    {
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(seed));
        return $"W/\"{Convert.ToHexString(hash)[..16]}\"";
    }
}
