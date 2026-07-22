# Multi-stage: the runtime image carries no SDK, no source and no build cache.
# A production image with a compiler in it is a larger attack surface for no
# operational benefit.

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy project files alone first so `restore` is cached independently of source
# changes. Editing a .cs file must not re-download every package.
COPY *.slnx ./
COPY src/Maren.Api/*.csproj             src/Maren.Api/
COPY src/Maren.Application/*.csproj     src/Maren.Application/
COPY src/Maren.Contracts/*.csproj       src/Maren.Contracts/
COPY src/Maren.Domain/*.csproj          src/Maren.Domain/
COPY src/Maren.Infrastructure/*.csproj  src/Maren.Infrastructure/
COPY src/Maren.Persistence/*.csproj     src/Maren.Persistence/
COPY src/Maren.Shared/*.csproj          src/Maren.Shared/
COPY tests/Maren.Tests/*.csproj         tests/Maren.Tests/
RUN dotnet restore src/Maren.Api/Maren.Api.csproj

COPY . .
RUN dotnet publish src/Maren.Api/Maren.Api.csproj \
    -c Release -o /app/publish --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# Non-root. A container process that does not need to write to its own image
# should not be able to.
RUN groupadd --system --gid 64198 maren \
 && useradd --system --uid 64198 --gid maren --no-create-home maren
USER 64198:64198

COPY --from=build --chown=64198:64198 /app/publish .

EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_RUNNING_IN_CONTAINER=true

# Liveness only. Readiness touches the database, and an orchestrator restarting
# every instance because SQL Server blinked takes the platform down harder than
# the blink did.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["dotnet", "Maren.Api.dll", "--healthcheck"]

ENTRYPOINT ["dotnet", "Maren.Api.dll"]
