using System.Security.Claims;
using System.Text;
using FluentValidation;
using Maren.Application.Abstractions;
using Maren.Application.Auth;
using Maren.Infrastructure;
using Maren.Persistence;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Scalar.AspNetCore;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

Log.Logger = new LoggerConfiguration()
    .Enrich.FromLogContext()
    .WriteTo.Console()
    .CreateLogger();

builder.Host.UseSerilog();

builder.Services.Configure<JwtOptions>(
    builder.Configuration.GetSection(JwtOptions.SectionName));

builder.Services.AddMarenPersistence();
builder.Services.AddMarenInfrastructure();

builder.Services.AddMediatR(cfg =>
    cfg.RegisterServicesFromAssembly(typeof(RegisterCommand).Assembly));

builder.Services.AddValidatorsFromAssembly(typeof(RegisterCommand).Assembly);

builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentUser, HttpCurrentUser>();

var signingKey = builder.Configuration["Jwt:SigningKey"];
if (string.IsNullOrWhiteSpace(signingKey) || signingKey.Length < 32)
{
    // Fail at startup rather than at first request. A short or missing signing
    // key produces tokens anyone can forge, and discovering that in production
    // is discovering it too late.
    throw new InvalidOperationException(
        "Jwt:SigningKey must be configured and at least 32 characters.");
}

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = builder.Configuration["Jwt:Issuer"],
            ValidAudience = builder.Configuration["Jwt:Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(signingKey)),
            // No grace period. The default five minutes is a meaningful
            // extension of a fifteen-minute token's life.
            ClockSkew = TimeSpan.Zero
        };
    });

builder.Services.AddAuthorization();
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();

// .NET 10 ships OpenAPI document generation in the framework. Swashbuckle is
// deliberately not used: it pulls Microsoft.OpenApi 1.x, which conflicts with
// the 2.x the framework package already brings in.
builder.Services.AddOpenApi(options =>
{
    options.AddDocumentTransformer((document, _, _) =>
    {
        document.Info = new Microsoft.OpenApi.OpenApiInfo
        {
            Title = "Maren Platform API",
            Version = "v1",
            Description = "Backend for the Maren mobile app and admin portal."
        };
        return Task.CompletedTask;
    });
});

var app = builder.Build();

app.UseSerilogRequestLogging();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
}

app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.MapGet("/health", () =>
        Results.Ok(new { status = "ok", utc = DateTime.UtcNow }))
   .AllowAnonymous();

app.Run();

/// <summary>Reads the caller out of the current HTTP context.</summary>
internal sealed class HttpCurrentUser(IHttpContextAccessor accessor) : ICurrentUser
{
    private HttpContext? Context => accessor.HttpContext;

    public Guid? UserId =>
        Guid.TryParse(
            Context?.User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? Context?.User.FindFirstValue("sub"),
            out var id)
            ? id
            : null;

    public string? IpAddress => Context?.Connection.RemoteIpAddress?.ToString();

    public string? UserAgent => Context?.Request.Headers.UserAgent.ToString();

    public IReadOnlyList<string> Permissions =>
        Context?.User.FindAll("perm").Select(c => c.Value).ToList() ?? [];

    public bool Has(string permission) => Permissions.Contains(permission);
}

/// <summary>Exposed so an integration test project can reference the host.</summary>
public partial class Program;
