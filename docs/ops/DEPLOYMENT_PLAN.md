# DEPLOYMENT_PLAN

**Date:** 2026-07-27 · **Author role:** Senior DevOps Engineer
**Companions:** `CI_CD_PLAN.md`, `BACKUP_PLAN.md`, `RECOVERY_PLAN.md`

---

## 1. What exists today — verified, not assumed

I searched all three repositories for `wrangler.toml`, `render.yaml`, `railway.*`, `fly.toml`, `*.tf`, `*.bicep`, `Chart.yaml`, `azure-pipelines*`, `nginx*.conf`, and k8s manifests.

| Platform | Status |
|---|---|
| **Cloudflare** | ❌ Nothing. No tunnel, no Workers, no wrangler config, no DNS as code |
| **Docker** | ✅ Multi-stage Dockerfile + dev `docker-compose.yml` |
| **Render** | ❌ Nothing |
| **Azure** | ❌ Nothing (named in docs only) |
| **Railway** | ❌ Nothing |
| **Kubernetes / Helm / Terraform** | ❌ Nothing |
| **GitHub Actions** | 🟡 One workflow, backend only, **build+test only — no deploy** |
| **Monitoring** | ❌ Nothing. No APM, no metrics, no uptime check, no alerting |
| **Logging** | 🟡 Serilog to **console only**. No sink, no aggregation, no retention |
| **Backups** | ❌ Nothing. SIMPLE recovery, zero backups ever taken |
| **Secrets** | 🟡 Env vars with dev fallbacks. No vault, no rotation |
| **Disaster recovery** | ❌ Nothing. No RTO, no RPO, no tested restore |

**Bottom line: there is no deployment.** The platform runs via `dotnet run` or `docker compose up` on a developer machine. `docs/DEPLOYMENT.md` describes a Kubernetes/Azure pipeline with blue-green cutover and a CDN — **none of it exists**, and it should be read as intent, not documentation.

Production readiness: **~20%.**

---

## 2. Findings

### D-1 · 🔴 The container healthcheck is broken and only fails in production

```dockerfile
HEALTHCHECK ... CMD ["dotnet", "Maren.Api.dll", "--healthcheck"]
ENTRYPOINT ["dotnet", "Maren.Api.dll"]
```

`Program.cs` has **no argument handling**. So every 30 seconds the healthcheck starts a *second* full API instance, which tries to bind `:8080` — already held by the entrypoint process — fails, and exits non-zero. After 3 retries the container is marked **unhealthy** and any orchestrator restarts it. Forever.

**Why nobody has hit it:** `docker-compose.yml` overrides the healthcheck with an HTTP probe against `/health/live`, so development is fine. The Dockerfile's own healthcheck only applies where compose does not — `docker run`, ECS, Swarm, Nomad, or a Kubernetes probe copied from it. **The defect is invisible in dev and fatal in prod.**

**Fix:** implement the `--healthcheck` argument the Dockerfile already assumes. The Dockerfile is right; the application is missing the handler. A `curl`-based probe is the wrong fix — the `aspnet` runtime image ships neither `curl` nor `wget`.

### D-2 · 🔴 CI is red on `main`

`dotnet build --no-restore -c Release -warnaserror` fails with 5 `CA1310` errors in `ContentDeltaTests.cs`. Every commit since is unvalidated. A permanently-red pipeline is worse than none: people stop reading it.

### D-3 · 🔴 No backups of any kind

Recovery model `SIMPLE`, `msdb.dbo.backupset` empty. No point-in-time recovery, no tested restore. See `BACKUP_PLAN.md`.

### D-4 · 🟠 No deployment automation at all

CI ends at test. Nothing builds an image, nothing pushes a registry tag, nothing deploys. Releases would be manual, unversioned, and unrepeatable.

### D-5 · 🟠 Frontend has no CI

`Maren-Frontend/.github/` contains issue and PR templates but **no `workflows/` directory**. The Flutter app and React portal are never built, linted or tested automatically.

### D-6 · 🟠 Logs go to the console and nowhere else

Serilog writes to console with no sink. In a container that means logs die with the container. No correlation IDs (the `Audit.AuditLog.CorrelationId` column is never populated), no aggregation, no retention, no search. An incident would be uninvestigable.

### D-7 · 🟠 No monitoring or alerting

No APM, no metrics, no uptime probe, no error tracking, no dashboards, no on-call path. Failures are discovered by users.

### D-8 · 🟡 Secrets are environment variables with committed dev fallbacks

`docker-compose.yml` carries `${MSSQL_SA_PASSWORD:-Local!Dev!Passw0rd#2026}` and a dev JWT key; `ci.yml` falls back to `Local!CI!Passw0rd#2026`. Correct for local work, and clearly labelled — but there is no secret store, no rotation, and no separation between environments. The JWT signing key in particular has no rotation story, and rotating it invalidates every access token in circulation.

### D-9 · 🟡 `.dockerignore` excludes `docs/` and `*.md`

Good for image size. Worth noting it also excludes the SQL scripts' sibling docs — harmless today, but the image cannot self-document its schema version.

### D-10 · 🟡 No image tagging or provenance

Nothing stamps a build with its commit SHA. Given a running container, there is no way to determine which commit produced it.

---

## 3. Target architecture

Deliberately modest. The platform has no paying users and a two-person team; a Kubernetes cluster would be a second full-time job.

```
GitHub  ──push──►  Actions CI  ──►  build image  ──►  GHCR (tagged :sha)
                       │                                   │
                       │ tests + SQL suites                 │
                       ▼                                    ▼
                    red? stop                    staging (auto-deploy)
                                                            │ smoke test
                                                            ▼
                                                 production (manual approval)
                                                            │
                          ┌─────────────────────────────────┼──────────────┐
                          ▼                                 ▼              ▼
                   Azure SQL (or managed SQL)        log sink        uptime probe
                   PITR + geo-backup                 + alerts        + error tracking
```

**Platform choice: a managed container host plus managed SQL.** Azure App Service for Containers with Azure SQL is the natural fit — the stack is .NET and SQL Server, and managed SQL solves `BACKUP_PLAN.md` almost entirely by configuration rather than by cron jobs somebody has to maintain.

**Cloudflare** earns its place for exactly three things, none of which require the app to change: DNS, TLS, and WAF/rate limiting in front of the origin. Cloudflare Tunnel is worth it only if the origin must stay off the public internet — a decision for later, not now.

**Explicitly rejected for now:** Kubernetes (operational cost far exceeds benefit at this scale), multi-region (no users to justify it), service mesh, self-hosted observability.

---

## 4. Environments

| Environment | Purpose | Data | Deploy |
|---|---|---|---|
| **local** | Development | Throwaway; `docker compose up` | n/a |
| **ci** | Verification | Ephemeral SQL container, destroyed per run | Automatic |
| **staging** | Pre-production | Anonymised or synthetic — **never a production copy of health data** | Auto on merge to `main` |
| **production** | Live | Real | Manual approval |

**Staging must not hold real user health data.** Copying production into staging is the most common way health data ends up somewhere it was never risk-assessed.

---

## 5. Configuration and secrets

**Rule:** nothing but local development defaults may exist in a committed file. Everything else comes from the environment or a secret store.

| Secret | Where | Rotation |
|---|---|---|
| `ConnectionStrings__WlosPlatform` | Key Vault / platform secret | On credential change |
| `Jwt__SigningKey` | Key Vault | Quarterly — **invalidates all access tokens**, so rotate at a low-traffic hour and expect a re-auth wave |
| `Cors__AdminPortalOrigins__*` | Platform config (not secret) | On origin change |
| Registry credentials | GitHub OIDC, not a stored PAT | n/a |

**Prefer GitHub OIDC federation over long-lived cloud credentials.** A stored deploy secret is a credential that never expires and that nobody remembers to rotate.

`Program.cs` already fails fast at startup if `Jwt:SigningKey` is missing or under 32 characters — the correct behaviour, and it means a misconfigured deploy dies immediately rather than issuing forgeable tokens.

---

## 6. Rollout order

Sequenced so each step is independently useful, and nothing depends on a platform decision that has not been made.

| # | Improvement | Blocks | Risk |
|---|---|---|---|
| **1** | Fix the red CI build | Everything — no gate works while it is red | None |
| **2** | Fix the container healthcheck (D-1) | Any real container deploy | None (dev unaffected; compose overrides) |
| **3** | Frontend CI workflow (D-5) | Portal/app quality gate | None |
| **4** | Build and push a tagged image on merge | Deployment | Low |
| **5** | Structured log sink + correlation IDs (D-6) | Incident investigation | Low |
| **6** | Managed SQL with PITR (`BACKUP_PLAN.md`) | **Production launch** | Medium — needs a platform decision |
| **7** | Uptime + error alerting (D-7) | Knowing before users do | Low |
| **8** | Staging environment + auto-deploy | Safe releases | Medium |
| **9** | Production deploy with manual approval | Launch | Medium |
| **10** | Restore rehearsal (`RECOVERY_PLAN.md`) | **Launch sign-off** | None |

**Steps 1–5 need no cloud account and no spending decision.** They are pure repository work and should not wait for the platform question to be settled.

---

## 7. Pre-launch gate

Do not launch without every one of these:

- [ ] CI green, and required for merge
- [ ] Container healthcheck verified against a real `docker run`
- [ ] Automated backups on, with **a restore actually performed** (`RECOVERY_PLAN.md`)
- [ ] Secrets in a store, not environment files; no dev fallback reachable in production
- [ ] Logs leaving the container to a searchable sink
- [ ] Uptime and error alerting with a named on-call
- [ ] Rollback path tested, not assumed
- [ ] `docs/DEPLOYMENT.md` rewritten to describe what exists, not what was imagined

That last one matters more than it looks. A runbook describing an imaginary Kubernetes cluster is worse than no runbook — in an incident, somebody will follow it.
