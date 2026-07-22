using System.Security.Claims;
using Maren.Application.Access;
using Maren.Contracts;

namespace Maren.Api;

/// <summary>
/// Refuses tokens whose sessions have since been revoked.
/// </summary>
/// <remarks>
/// Middleware rather than a MediatR behaviour, deliberately. A pipeline
/// behaviour only runs for requests that reach a handler; a revoked token must
/// be refused at every authenticated endpoint, including ones that never send
/// a MediatR request. Putting it here means there is one place to reason about
/// and no endpoint can opt out by accident.
///
/// <para>
/// Runs after authentication so the claims exist, and skips anonymous requests
/// entirely — the published content endpoints have no user to check.
/// </para>
/// </remarks>
public sealed class SecurityStampMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(
        HttpContext context, ISecurityStampValidator validator)
    {
        if (context.User.Identity?.IsAuthenticated != true)
        {
            await next(context);
            return;
        }

        var subject = context.User.FindFirstValue(ClaimTypes.NameIdentifier)
                      ?? context.User.FindFirstValue("sub");

        var stampClaim = context.User.FindFirstValue("stamp");

        // A token with no stamp predates this check. Refusing it would sign out
        // everybody holding one the moment this deploys; they expire within
        // fifteen minutes and the next token carries a stamp.
        if (!Guid.TryParse(subject, out var userId) ||
            !Guid.TryParse(stampClaim, out var stamp))
        {
            await next(context);
            return;
        }

        if (await validator.IsCurrentAsync(userId, stamp, context.RequestAborted))
        {
            await next(context);
            return;
        }

        // 401, not 403: the token itself is no longer valid, so a client should
        // try to refresh or sign in again rather than treat it as a permission
        // problem it cannot fix. The refresh will also fail — revocation
        // deletes the refresh tokens — which lands them at sign-in.
        context.Response.StatusCode = StatusCodes.Status401Unauthorized;
        await context.Response.WriteAsJsonAsync(
            ApiResponse<object>.Fail(
                "SESSION_REVOKED",
                "This session has ended. Sign in again."),
            context.RequestAborted);
    }
}
