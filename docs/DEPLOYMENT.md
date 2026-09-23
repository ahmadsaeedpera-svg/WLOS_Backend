# Deployment: Environments & Processes

Development, staging, production environments and release procedures.

---

## Environments

### Development (Local)

**Backend:**
- SQL Server LocalDB (ships with Visual Studio)
- API runs on `http://localhost:5299`
- Scalar API reference at `/scalar/v1`
- Configuration: `appsettings.Development.json` (committed)

**Mobile:**
- Emulator or real device
- App runs offline, no network calls
- Local Drift SQLite database

**Portal:**
- `npm run dev` → `http://localhost:5173`
- API base: `http://localhost:5299` (via `.env.development`)

### Staging

**Purpose:** Pre-production testing

**Backend:**
- SQL Server (staging database)
- API deployed to staging environment (Azure App Service or equivalent)
- Configuration via environment variables (not committed files)

**Mobile:**
- Build with staging API base URL (`--dart-define API_BASE=https://staging-api.example.com`)
- Signed with staging keystore (not release keystore)

**Portal:**
- Built from main branch
- Deployed to staging host (S3, Netlify, etc.)
- Configured with staging API base (`VITE_API_BASE=https://staging-api.example.com`)

### Production

**Purpose:** Live users

**Backend:**
- SQL Server (production database, encrypted, backed up daily)
- API deployed to production environment (horizontally scalable)
- Zero downtime deployment (blue/green or rolling)
- Monitoring and alerting enabled
- Disaster recovery plan

**Mobile:**
- Build with production API base URL
- Signed with production keystore (kept secure)
- Submitted to Google Play
- 7-day review + testing before live

**Portal:**
- Built from main branch
- Deployed to production host (CDN-backed)
- HTTPS only
- Security headers (Content-Security-Policy, X-Frame-Options, etc.)

---

## Deployment Process

### Backend (Continuous)

**Trigger:** Merge to `main` branch

**Pipeline:**
```
1. Build
   dotnet build --configuration Release

2. Test
   dotnet test tests/Maren.Tests
   sqlcmd ... tests/cms_workflow_test.sql
   sqlcmd ... tests/access_test.sql

3. Package
   dotnet publish -c Release -o publish/

4. Build Docker image
   docker build -t maren-api:latest .
   docker push registry.example.com/maren-api:latest

5. Deploy to staging
   kubectl set image deployment/maren-api container=registry.example.com/maren-api:latest

6. Health check
   curl https://staging-api.example.com/health/ready

7. Deploy to production (blue/green)
   - Route new instances (green) with latest image
   - Verify healthy (status 200)
   - Switch traffic from blue to green
   - Keep blue running (instant rollback if needed)

8. Post-deployment
   - Monitor logs
   - Monitor metrics (latency, error rate)
   - Alert if anomalies
```

**Rollback (if issues):**
```
kubectl rollout undo deployment/maren-api
# Switch traffic back to previous version
```

**Database migrations:**
- All SQL scripts are idempotent (can run multiple times safely)
- Migrations run as part of the deployment pipeline
- Schema versioning via script numbering (01_*, 02_*, etc.)

### Mobile (Manual, 2-week cycle)

**Prerequisite checklist:**
- [ ] All tests passing (`flutter test`)
- [ ] No analyzer warnings (`flutter analyze`)
- [ ] Tested on Android 10, 12
- [ ] Release blockers resolved
- [ ] Version number bumped (Android Gradle)
- [ ] Commit tagged with version
- [ ] Release notes updated

**Submission process:**
```bash
flutter build appbundle --release  # Creates .aab file

# Google Play Console:
# 1. Open https://play.google.com/console
# 2. Upload .aab to Internal Testing
# 3. Test internally (if needed)
# 4. Promote to Closed Testing or Production
# 5. Add release notes
# 6. Submit for review

# Wait 7 days for Google's review and testing
# Once approved, gradually roll out to users
```

**Timeline:** 7-14 days from submission to live users

**Rollback (if critical bug):**
- Can halt rollout mid-way
- Previous version still available for redownload (Play keeps old versions)
- New version required for new installs only

### Portal (Continuous)

**Trigger:** Merge to `main` branch

**Pipeline:**
```
1. Build
   npm install
   npm run build  # tsc -b + vite

2. Test
   (manual testing in this phase, add tests later)

3. Deploy to staging
   sync dist/ to staging-portal.example.com

4. Smoke test
   Check login, CMS editor, user admin work

5. Deploy to production
   sync dist/ to production-portal.example.com
   Invalidate CDN cache (if behind CloudFront/CDN)

6. Post-deployment
   - Check availability
   - Test operator workflows
   - Monitor error logs
```

**Rollback (if issues):**
```bash
# Previous version is in git history
git checkout <previous-commit>
npm run build
sync dist/ to production
```

---

## Configuration Management

### Backend

**Development** (committed `appsettings.Development.json`):
```json
{
  "ConnectionStrings": {
    "WlosPlatform": "Server=(localdb)\\MSSQLLocalDB;Database=WlosPlatform;Integrated Security=true;"
  },
  "Jwt": {
    "SigningKey": "dev-only-key-32-characters-long",
    "AccessTokenMinutes": 15,
    "RefreshTokenDays": 30
  },
  "Cors": {
    "AdminPortalOrigins": ["http://localhost:5173"]
  }
}
```

**Staging & Production** (via environment variables, never committed):
```bash
export ConnectionStrings__WlosPlatform="Server=staging-db.azure.com;Database=WlosPlatform;User Id=sa;Password=...;Encrypt=True"
export Jwt__SigningKey="<random-32-character-key-from-vault>"
export Cors__AdminPortalOrigins__0="https://admin.example.com"
```

### Mobile

**API base URL** (compile-time, via `--dart-define`):
```bash
# Development
flutter run --dart-define=API_BASE=http://localhost:5299

# Staging
flutter build appbundle --dart-define=API_BASE=https://staging-api.example.com

# Production
flutter build appbundle --dart-define=API_BASE=https://api.example.com
```

### Portal

**.env.development** (committed template):
```bash
VITE_API_BASE=http://localhost:5299
```

**.env.production** (NOT committed, set via build/deploy system):
```bash
VITE_API_BASE=https://api.example.com
```

---

## Health Checks

**Backend:**

| Endpoint | Touches DB | Purpose | Frequency |
|---|---|---|---|
| `GET /health/live` | No | Process is up | 10s (restart probe) |
| `GET /health/ready` | Yes | Database reachable | 30s (load balancer) |

**Response:**
```json
{ "status": "Healthy" }
```

**If database is down:**
- `/health/live` → 200 (process OK)
- `/health/ready` → 503 (dependency unavailable)

**Load balancer behavior:**
- 200 = route traffic to instance
- 503 = remove from load balancer, don't route traffic

This prevents cascading failures (don't route traffic to instances that can't reach the database).

---

## Monitoring & Alerting

### Backend

**Metrics to monitor:**
- API response time (p50, p95, p99)
- Error rate (5xx responses)
- Database connection pool saturation
- JWT validation errors (401 spikes = possible attack)
- Audit log volume

**Alerts:**
- Error rate > 5% → page on-call engineer
- Response time p95 > 5 seconds → investigate query performance
- Database connection pool > 90% → scale up
- JWT failures > 100/minute → investigate

### Mobile

**Metrics from Play Console:**
- Crash rate (should be < 0.5%)
- ANR rate (should be < 0.1%)
- Uninstall rate
- Daily active users

**Alerting:**
- Crash rate spike → investigate
- Uninstall rate increase → check reviews for complaints

### Portal

**Metrics:**
- Page load time
- API call latency
- Error rate (JavaScript errors)

**Alerting:**
- Page load > 3 seconds → investigate
- API errors > 5% → check backend

---

## Disaster Recovery

### Database Backup

**Frequency:** Daily (minimum)

**Retention:** 30 days (or longer per compliance)

**Testing:** Weekly restore to staging, verify data integrity

**Location:** Geo-redundant storage (different region from production)

**Recovery time objective (RTO):** < 1 hour
**Recovery point objective (RPO):** < 24 hours

### API Instances

**Redundancy:** Multiple instances (minimum 2 in production)

**Failover:** Automatic (load balancer detects unhealthy instances, routes around)

**Stateless:** API instances can be replaced without disruption

**Rolling update:** Drain connections, update, health check, switch traffic

### Portal

**Redundancy:** Cached by CDN (fast recovery if origin down)

**Failback:** Redeploy from git if origin completely lost

### Mobile App

**Version history:** Older app versions remain available on Play Store

**Users on old version:** Can continue using (offline app)

**Critical security fix:** Can force upgrade via feature flag (if sync implemented)

---

## Release Checklist

### Backend

- [ ] All tests passing (111/111)
- [ ] SQL assertions passing (cms, access)
- [ ] No analyzer warnings
- [ ] Database migrations idempotent (tested re-run)
- [ ] Configuration correct for environment
- [ ] Secrets in vault, not in code
- [ ] API reference documentation up to date
- [ ] Deployment pipeline verified
- [ ] Monitoring and alerting configured
- [ ] Rollback plan documented

### Mobile

- [ ] All tests passing (425/425)
- [ ] Guard tests passing (5/5)
- [ ] No analyzer warnings
- [ ] Tested on Android 10, 12 (real devices)
- [ ] Release blockers resolved
- [ ] Version number bumped
- [ ] Release notes written
- [ ] Screenshots updated (if changed)
- [ ] Store listing reviewed
- [ ] Signed with correct keystore

### Portal

- [ ] Build succeeds (TypeScript strict)
- [ ] No console errors
- [ ] Tested against staging API
- [ ] No hardcoded secrets or API keys
- [ ] Performance acceptable
- [ ] Forms validated (client + server)
- [ ] Accessibility verified
- [ ] Security headers configured
- [ ] Deployment pipeline verified

---

## For More Information

- **Architecture:** `docs/ARCHITECTURE.md`
- **Git workflow:** `docs/GIT_WORKFLOW.md`
- **Testing:** `docs/TESTING.md`
- **Backend setup:** `Maren-Backend/README.md`
- **Frontend setup:** `Maren-Frontend/README.md`
