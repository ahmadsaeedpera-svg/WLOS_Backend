# RECOVERY_PLAN

**Companion to:** `BACKUP_PLAN.md`, `DEPLOYMENT_PLAN.md`

> **Status: not exercisable today.** There are no backups, no deployed environment, and no monitoring, so nothing below has been performed. This is the plan to make true, and the rehearsal in §7 is what converts it from a document into a capability.

---

## 1. Scope

What to do when the platform is down, damaged, or compromised. Written for the person on call at 03:00 who did not build it.

---

## 2. Severity and response

| Sev | Meaning | Example | Response |
|---|---|---|---|
| **1** | Data loss, or health data exposed | Database destroyed; unauthorised access | Immediate, all hands, legal notified |
| **2** | Platform down | API unreachable; database unreachable | Immediate |
| **3** | Degraded | Slow responses; one screen broken | Same day |
| **4** | Cosmetic | Copy error | Backlog |

**Sev 1 has a legal clock.** UK/EU GDPR requires notification of a personal data breach to the supervisory authority **within 72 hours** of becoming aware. Health data raises the stakes. Involve counsel at declaration, not after triage — the clock does not pause while engineers investigate.

---

## 3. First ten minutes

1. **Declare.** Say the severity out loud in the incident channel. An unnamed incident has no owner.
2. **Assign** an incident lead. The lead coordinates and does not debug.
3. **Check the obvious**, in this order:
   - `GET /health/live` — is the process up?
   - `GET /health/ready` — can it reach SQL? (returns 503 when it cannot)
   - Database reachable independently?
   - What deployed most recently?
4. **Prefer rollback over diagnosis.** If a deploy preceded the incident, roll back first and investigate afterwards. Restoring service is not the same job as understanding the fault.
5. **Write down what you do, as you do it.** Memory after an incident is unreliable, and the timeline is what the post-mortem and any regulator will need.

---

## 4. Scenarios

### 4.1 Bad deploy
**Detect:** errors spike immediately after a release.
**Do:** redeploy the previous image SHA. This is why images are tagged by commit and never only `latest`.
**RTO:** minutes.

### 4.2 Database unreachable, data intact
**Detect:** `/health/ready` returns 503; `/health/live` still 200 (the split is deliberate — a database blip must not restart every API instance).
**Do:** confirm the database service state, check credentials and firewall, check for failover. Restart the API only after the database answers.
**RTO:** under 1 hour.

### 4.3 Data corruption or destructive change
**Detect:** wrong or missing rows; a migration or script that did more than intended.
**Do:**
1. **Stop writes immediately** — take the API down. Every minute of continued writing widens the gap between now and the last good point.
2. Identify the last known-good timestamp from the audit log.
3. Point-in-time restore to **a new database**, never over the live one.
4. Verify the restore (§6) before switching anything.
5. Repoint the connection string; bring the API up.
6. Replay the erasure log (`BACKUP_PLAN.md` §7) — a restore can resurrect data a user asked to be erased.
**RTO:** ≤ 4 hours. **RPO:** ≤ 15 minutes, once PITR exists.

Step 6 is easy to forget and is a compliance failure if skipped.

### 4.4 Total loss of the environment
**Do:** provision infrastructure → restore database from geo-redundant backup → deploy the last known-good image tag → restore secrets from the vault → verify → cut DNS over.
**Depends on:** infrastructure being reproducible. Today it is not, which is why "no IaC" is a recovery risk and not merely an inconvenience.
**RTO:** ≤ 8 hours realistically.

### 4.5 Compromised credentials
**Do:** rotate the credential first, then investigate. Specifically:
- **`Jwt__SigningKey`** — rotating it invalidates **every access token in circulation**. Every user is signed out. Do it anyway; a leaked signing key lets anyone mint a valid administrator token.
- Database credentials, registry credentials, third-party keys.
- Revoke sessions: the platform already supports this — security-stamp revocation takes effect within ~30 seconds.
- Preserve `Audit.AuditLog` and `AI.SafetyEvent`; both are append-only and are the evidence.

### 4.6 Health data exposure
Treat as **Sev 1**. Contain, preserve evidence, notify counsel immediately, assess scope from the audit log, and follow the 72-hour clock. Do not delete anything — deleting evidence during a breach investigation converts a technical incident into a legal one.

---

## 5. What we cannot currently recover from

Stated plainly, because a recovery plan that omits its own gaps is worse than none:

| Scenario | Today |
|---|---|
| Database destroyed | ❌ **Total, permanent loss.** No backups exist |
| Point-in-time recovery | ❌ Impossible — `SIMPLE` recovery model |
| Environment rebuild | ❌ No IaC; would be rebuilt from memory |
| Detecting an outage | ❌ No monitoring; users would tell us |
| Investigating an incident | ❌ Console-only logs die with the container; `CorrelationId` never populated |
| Rolling back a deploy | ❌ No deployment to roll back |

Every row becomes recoverable through `DEPLOYMENT_PLAN.md` §6 and `BACKUP_PLAN.md` §8.

---

## 6. Verifying a restore

Never return a restored database to service on the assumption it worked.

```bash
./ops/db/restore-drill.sh <source-db> <full-backup> [log-backup] [--stopat '<utc>']
```

It restores to a **scratch** database, runs `DBCC CHECKDB` and **every**
assertion suite on disk against the restored copy, records the result in
`Ops.RestoreDrill`, and drops the scratch database. Exit code 0 only when every
check passed.

### Why this is not a list of expected counts any more

Until 2026-07-29 this section read *"expect 45 tables, expect 47 procedures"*
and named five assertion suites.

By then the schema had roughly doubled — **84 tables and 102 procedures** — and
twenty suites existed. The thresholds had gone stale silently, because nothing
executes a number written in a document. Worse than useless: a database
restored from a backup taken before ten entire feature schemas existed matches
45/47 *exactly*, so the gate would have reported a clean verification of a
catastrophically incomplete restore, during an incident, to somebody deciding
whether to return it to service.

That was demonstrated rather than reasoned about. A real database on the
verification instance still sits at exactly 45/47; restoring it through the
drill fails 15 of 21 checks, where the old gate passes it.

The drill therefore checks **behaviour, not shape**, and enumerates the suites
from disk rather than from a list. Assertion suites cannot rot quietly the way a
number can, because they gate CI.

The old commands also omitted `-S`, so they could not connect to the LocalDB
instance the rest of the documentation uses. They had never been run as written.

Then spot-check recency: the newest `Audit.AuditLog` row tells you how much time the restore actually lost. Compare it against the claimed RPO — that comparison is the only honest measure of whether the backup policy works.

---

## 7. Rehearsal

**Quarterly, and once before launch.** A backup nobody has restored is a belief.

Rehearsal is: restore the most recent backup into a scratch database, run §6 end to end, **time it**, and record the result. Then compare the measured time against the 4-hour RTO and correct whichever is wrong — the process or the target.

Record: date, who, backup timestamp used, wall-clock duration, verification outcome, and anything that surprised you. The surprises are the valuable part; they are the steps missing from this document.

---

## 8. After the incident

Blameless post-mortem within five working days: timeline, contributing causes, what worked, what did not, and actions with owners and dates.

The test of a post-mortem is whether the same incident could happen again next week. If the answer is yes, it produced sympathy rather than actions.
