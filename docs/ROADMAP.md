# Roadmap: Remaining Work

Sequenced by dependency. Blockers noted.

---

## Now (Phase: Completion & Compliance)

**Priority:** Sprint A + RC phase (parallel)

### Sprint A — Release Readiness (Mobile)

**Not user-facing. No feature work until these pass.**

- [ ] Device testing (Android 10, 12—only API 36 tested)
- [ ] Orientation change, background/foreground lifecycle
- [ ] Profile-mode frame timing (1576ms first frame—analyze and optimize)
- [ ] Backup exclusion verification on real device
- [ ] Crash report scrubbing (no PII in stack traces)

**Blocker release if:** Any regression on real devices

### RC Phase — Compliance (Mobile + Legal)

**Requirement:** Before Play Store submission

- **RC-1** — Rewrite 25 wellness articles to FDA compliance standard (2-3 weeks)
  - Scan `lib/features/insights/data/` for dose/outcome claims
  - Rewrite to "describe, never prescribe"
  - Add module to guard tests
  - Add README with compliance citations

- **RC-2** — FDA wording audit of all strings (1-2 weeks)
  - Every user-facing string in code, l10n, store listing
  - Check against General Wellness exclusion (guidance 6 Jan 2026)
  - Sign-off list of changes

- **RC-3** — Medical content review (external, 1-2 weeks)
  - Clinician review of insights, wellness library, hospital bag, birth preferences
  - Due date calculator presentation
  - Written sign-off, reviewer named, date recorded
  - Surface review date on About screen

- **RC-4** — Legal review (external, 2-4 weeks)
  - Privacy policy review and finalization
  - Terms of use drafted
  - Play Data Safety verification
  - GDPR position confirmed
  - Legal entity, contact, support email resolved

- **RC-5** — Clinical behavioral review (external, 1-2 weeks)
  - Contraction timer shows raw data only (no time-to-hospital)
  - Kick counter shows raw data only (no threshold)
  - Body log shows data only (no aggregation)
  - Due date never picks a single correct date
  - Clinician sign-off

**Blocker:** All 5 tasks gate production release

---

## Sprint B — Export/Import (Launch Blocker)

**Requirement:** Before shipping to users (backup is disabled)

- [ ] Full-account export (JSON) — schema ready, UI partial
- [ ] Full-account import — schema ready, UI partial
- [ ] Plain-text checklist export (shareable)
- [ ] Migration from old app (if applicable)
- [ ] Full test coverage
- [ ] File size verification (40MB+ export possible?)

**Blocker:** Users lose everything on a new phone without this

---

## Sprint C — Birth Preferences UI

**Requirement:** Legal review of US content (ACOG)

- [ ] ACOG legal read — US content approval
- [ ] Birth preferences screen UI
- [ ] Partner preferences
- [ ] PDF export (for hospital)
- [ ] Backup/restore

**Blocker:** ACOG legal review (may take 2-4 weeks)

**UK status:** Can ship independently without US content

---

## Sprint D — MVP Screens

**Requirement:** Compliance approval (RC phase)

- [ ] Kick counter — UI complete (model + tests done)
- [ ] Contraction timer — UI complete (model + tests done)
- [ ] Body log — UI complete (model + tests done)
- [ ] Daily check-in — UI complete (model + tests done)
- [ ] Wellness insights — RC-1 rewrite of articles

**Blocker:** RC compliance (RC-1, RC-2, RC-3, RC-4, RC-5 must pass first)

---

## Slice 2 — Notifications (Backend)

**Requirement:** After Sprint D

**Backend:**
- [ ] Create `CreateNotificationCampaignCommand` handler
- [ ] Create `SendNotificationCommand` handler
- [ ] Create `usp_Notification_Send` procedure
- [ ] Create `usp_NotificationLog_Record` procedure
- [ ] FCM (Firebase Cloud Messaging) integration
- [ ] Scheduling job (send campaigns at scheduled time)
- [ ] Tests (real database)

**Mobile:**
- [ ] Receive notifications (device permission, handler)
- [ ] Quiet hours enforcement (don't wake user)
- [ ] Notification preferences (opt-in by type)
- [ ] Tests

**Portal:**
- [ ] Campaign CRUD
- [ ] Template management
- [ ] Scheduling UI
- [ ] Delivery log viewer

**Unblocks:**
- Four-eyes approval (operator-initiated password reset)
- Reminder notifications (contraction timer, check-in)

---

## Slice 3 — Analytics (Backend)

**Requirement:** Data-informed roadmap decisions

**Backend:**
- [ ] Database schema (Event, EventProperty, Query)
- [ ] Event ingestion API (`POST /api/v1/events`)
- [ ] Retention queries (DAU, WAU, MAU)
- [ ] Funnel queries (onboarding flow, feature adoption)
- [ ] Cohort queries (by install date, location, etc.)
- [ ] Tests

**Mobile:**
- [ ] Event tracking (guard test: no health data in events)
- [ ] Event batching and sending
- [ ] Optional (opt-in)

**Portal:**
- [ ] Dashboard (key metrics)
- [ ] Funnel builder
- [ ] Cohort viewer
- [ ] Export (CSV)

**Unblocks:**
- Product team data (retention curves, feature adoption)
- Marketing (campaign effectiveness)

---

## Slice 4 — Subscriptions (Backend)

**Requirement:** Revenue model

**Backend:**
- [ ] Database schema (Plan, Entitlement, Receipt)
- [ ] Store receipt validation (Google Play)
- [ ] Entitlement gating (which features by plan)
- [ ] Tests

**Mobile:**
- [ ] Purchase flow
- [ ] Receipt validation
- [ ] Entitlement checking (UI gates premium features)

**Portal:**
- [ ] Plan management
- [ ] Subscription viewer (admin can see who has what)

**Unblocks:**
- Revenue (sustainable development)

---

## Slice 5 — Privacy (Backend + Mobile)

**Requirement:** GDPR compliance, data subject rights

**Blocked on:** PD-1 (mobile sync decision)

**Backend:**
- [ ] Account deletion (cascade all health data)
- [ ] GDPR export (all personal data, machine-readable)
- [ ] Consent ledger (which features user has consented to)
- [ ] Data retention policy (delete old logs after N months)
- [ ] Tests

**Mobile:**
- [ ] Delete account UI
- [ ] Export GDPR package UI

**Portal:**
- [ ] Manual deletion (admin can delete users)
- [ ] GDPR exports (admin can trigger export for user)

**Unblocks:**
- Legal compliance (GDPR)
- Trust (users control their data)

---

## Slice 6 — Impersonation (Backend)

**Requirement:** Support workflows

**Blocked on:** Legal review (consent model, time limit, banner)

**Backend:**
- [ ] Consent model (user explicitly approves this operator viewing their data)
- [ ] Time limit (session expires after N minutes)
- [ ] User-visible banner (operator sees warning, user notified)
- [ ] Separate audit trail (logged as impersonation, not operator's account)
- [ ] Tests

**Portal:**
- [ ] User list with impersonate button (if authorized)
- [ ] Consent UI

**Unblocks:**
- Support workflows (help users without them calling support)
- Operator troubleshooting (see what the user sees)

---

## Slice 7 — Clinician (Backend)

**Requirement:** Partnerships with healthcare providers

**Backend:**
- [ ] Shared summaries (encrypted, read-only)
- [ ] Clinician role (scoped access, can see assigned users only)
- [ ] Revocable links (user controls who can see what, revoke anytime)
- [ ] HIPAA compliance audit
- [ ] Tests

**Mobile:**
- [ ] Share with clinician UI (generate revocable link)
- [ ] Share weekly summaries (optional)

**Clinician portal (future):**
- [ ] Shared summaries viewer
- [ ] Notes (read-only, audit logged)

**Unblocks:**
- Clinical partnerships
- Care provider integration

---

## Scalability (Infrastructure)

**Requirement:** Before production at scale

- [ ] Redis cache (behind `IQueryCache`, replace in-process)
  - Feature flags
  - Content
  - Permission checks
  - Avoids database storms

- [ ] Audit table partitioning (by month, archive old data)
  - Current: Single table, append-only
  - Future: Partitioned, cold data archived to cheaper storage

- [ ] Database replicas (read scaling)
  - Complex due to procedures
  - May need read-only replicas with eventual consistency

- [ ] API horizontal scaling
  - Stateless today, ready for multiple instances
  - Needs Redis (see above)
  - Load balancer (Azure, AWS, etc.)

- [ ] Rate limiting (DOS protection)
  - Schema designed, middleware not yet implemented

**Timeline:** After initial launch and usage monitoring

---

## Dependency Graph

```
NOW (Sprint A + RC):
├─ Sprint A ✓ (parallel with RC)
├─ RC Phase ✓ (gates production)
│
NEXT (Sprint B):
├─ Export/Import (launch blocker)
│
THEN (Sprint C):
├─ Birth Preferences UI (blocked on ACOG legal)
│
THEN (Sprint D):
├─ MVP Screens (blocked on RC completion)
│
THEN (Slices 2-7, parallel):
├─ Slice 2 — Notifications
├─ Slice 3 — Analytics
├─ Slice 4 — Subscriptions
├─ Slice 5 — Privacy (blocked on PD-1)
├─ Slice 6 — Impersonation (blocked on legal)
└─ Slice 7 — Clinician
   
   Scalability (concurrent, as needed)
   ├─ Redis cache
   ├─ Audit partitioning
   ├─ Database replicas
   ├─ API horizontal scaling
   └─ Rate limiting
```

---

## Metrics for Success

| Metric | Target | Current |
|---|---|---|
| **Mobile screens** | 9 of 9 | 3/9 (33%) |
| **Backend tests** | 100% passing | 111/111 ✅ |
| **Compliance** | All RC tasks done | 0/5 (0%) |
| **Device testing** | Android 10, 12, 14 | API 36 only |
| **Play Store listing** | Live | Pending |
| **Users** | 1000+ | 0 (pre-launch) |
| **Daily active** | TBD | 0 |
| **Churn** | <5%/month | N/A |

---

## Timeline Estimate

| Phase | Effort | Timeline |
|---|---|---|
| Sprint A (release readiness) | 2-3 weeks | Mobile team |
| RC (compliance) | 6-8 weeks | Mobile + external (legal, medical) |
| Sprint B (export) | 1-2 weeks | Mobile team |
| Sprint C (birth prefs) | 2-3 weeks | Mobile + legal |
| Sprint D (MVP screens) | 3-4 weeks | Mobile team |
| **Total to production:** | | **~4-5 months** |
| Slice 2 (notifications) | 3-4 weeks | Backend + mobile |
| Slice 3 (analytics) | 4-5 weeks | Backend + mobile + portal |
| Slice 4 (subscriptions) | 2-3 weeks | Backend + mobile + portal |
| Slices 5-7 | 8-12 weeks total | Backend, legal involvement |

---

## For More Information

- **Current status:** `docs/PROJECT_STATUS.md`
- **Module inventory:** `docs/MODULE_STATUS.md`
- **Release blockers:** `Maren-Frontend/RELEASE_BLOCKERS.md`
- **Architectural decisions:** `docs/DECISIONS.md`
