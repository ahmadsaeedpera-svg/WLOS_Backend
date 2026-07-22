using System.Data;
using Dapper;
using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Application.Behaviors;
using Maren.Contracts;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;

namespace Maren.Api;

/// <summary>
/// Turns exceptions the MediatR pipeline throws into the right HTTP status.
/// </summary>
/// <remarks>
/// Without this the pipeline's own refusals arrive as bare 500s: the
/// authorization behaviour throws <see cref="UnauthorizedRequestException"/>,
/// which is the platform's primary access control, and a 500 tells the caller
/// "we broke" rather than "you may not". A client cannot distinguish a denial
/// it should surface to the user from an outage it should retry, and every
/// denial pages whoever watches the error rate.
///
/// <para>
/// Responses use the same <see cref="ApiResponse{T}"/> envelope as success
/// paths rather than raw <see cref="ProblemDetails"/>, so a client has one
/// shape to parse. The status code carries the ProblemDetails semantics for
/// anything in between that only reads headers.
/// </para>
/// </remarks>
public sealed class MarenExceptionHandler(
    ILogger<MarenExceptionHandler> logger) : IExceptionHandler
{
    /// <summary>
    /// 499. ASP.NET does not define it; nginx and most log pipelines read it
    /// as "the client went away", which keeps an abandoned request out of the
    /// 5xx rate.
    /// </summary>
    private const int ClientClosedRequest = 499;

    public async ValueTask<bool> TryHandleAsync(
        HttpContext context, Exception exception, CancellationToken ct)
    {
        var (status, code, message, errors) = Map(exception);

        // Denials and validation failures are expected traffic, not incidents.
        // Logging them at Error makes the error rate meaningless.
        if (status >= StatusCodes.Status500InternalServerError)
        {
            logger.LogError(exception, "Unhandled {Type} on {Path}",
                exception.GetType().Name, context.Request.Path);
        }
        else
        {
            logger.LogInformation("{Type} on {Path}: {Code}",
                exception.GetType().Name, context.Request.Path, code);
        }

        context.Response.StatusCode = status;

        var body = errors is null
            ? ApiResponse<object>.Fail(code, message)
            : ApiResponse<object>.Invalid(errors);

        await context.Response.WriteAsJsonAsync(body, ct);
        return true;
    }

    private static (int Status, string Code, string Message,
        IReadOnlyDictionary<string, string[]>? Errors) Map(Exception exception) =>
        exception switch
        {
            ValidationException v => (
                StatusCodes.Status400BadRequest,
                "VALIDATION_FAILED",
                "One or more fields need attention.",
                v.Errors
                    .GroupBy(e => e.PropertyName)
                    .ToDictionary(g => g.Key,
                        g => g.Select(e => e.ErrorMessage).ToArray())
                    as IReadOnlyDictionary<string, string[]>),

            // 403, not 401: the caller authenticated fine, they simply lack the
            // permission. A 401 would send a client into a token refresh loop
            // that can never succeed.
            UnauthorizedRequestException u => (
                StatusCodes.Status403Forbidden,
                "FORBIDDEN",
                $"You do not have permission to do this ({u.Permission}).",
                null),

            // 404 rather than 403. A disabled feature should look like it does
            // not exist — telling an unreleased-feature prober that the
            // endpoint is real but switched off leaks the roadmap.
            FeatureDisabledException => (
                StatusCodes.Status404NotFound,
                "NOT_FOUND",
                "This feature is not available.",
                null),

            OperationCanceledException => (
                ClientClosedRequest,
                "CANCELLED",
                "The request was cancelled.",
                null),

            _ => (
                StatusCodes.Status500InternalServerError,
                "INTERNAL_ERROR",
                // Never the exception message. It can carry table names,
                // connection strings and row values.
                "Something went wrong. The problem has been logged.",
                null)
        };
}

/// <summary>
/// Liveness and readiness.
/// </summary>
/// <remarks>
/// Split deliberately. Liveness answers "is this process running" and must not
/// touch the database — a restart loop caused by a database blip takes the API
/// down harder than the blip did. Readiness answers "should traffic come here"
/// and must check the database, because an instance that cannot reach SQL
/// serves nothing but errors and should be taken out of rotation.
/// </remarks>
public static class HealthEndpoints
{
    public static void MapMarenHealth(this WebApplication app)
    {
        app.MapGet("/health/live", () => Results.Ok(new
        {
            status = "alive",
            utc = DateTime.UtcNow
        })).AllowAnonymous().ExcludeFromDescription();

        app.MapGet("/health/ready", async (
            IDbConnectionFactory factory, CancellationToken ct) =>
        {
            try
            {
                using var connection = await factory.CreateAsync(ct);

                // Cheap, and confirms the connection actually round-trips
                // rather than merely opening from the pool.
                await connection.ExecuteScalarAsync<int>(
                    new CommandDefinition("SELECT 1", cancellationToken: ct));

                return Results.Ok(new
                {
                    status = "ready",
                    database = "ok",
                    utc = DateTime.UtcNow
                });
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                // 503 so a load balancer stops routing here. No exception
                // detail: this endpoint is typically reachable without a token.
                return Results.Json(new
                {
                    status = "degraded",
                    database = "unreachable",
                    utc = DateTime.UtcNow
                }, statusCode: StatusCodes.Status503ServiceUnavailable);
            }
        }).AllowAnonymous().ExcludeFromDescription();
    }
}
