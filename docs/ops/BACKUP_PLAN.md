# BACKUP_PLAN

**Companion to:** `RECOVERY_PLAN.md`, `DEPLOYMENT_PLAN.md`

---

## 1. Current state: there are no backups

Verified against a live instance:

```
recovery_model_desc          SIMPLE
msdb.dbo.backupset           0 rows for this database
```

`SIMPLE` recovery means **the transaction log is not retained, so point-in-time recovery is impossible by definition** — even if a full backup existed, which it does not.

There is no backup job, no schedule, no retention policy, no offsite copy, and no restore has ever been attempted. **Current data loss exposure: everything, permanently.**

This is acceptable for LocalDB development. It is the single largest launch blocker in the infrastructure, and no amount of application quality compensates for it.

---

## 2. What has to be protected

| Asset | Loss impact | Rebuildable? |
|---|---|---|
| **User health data** (`Health.*`) | Irreplaceable. Kick counts, contractions, symptom history — a woman's own record of her pregnancy | ❌ Never |
| **Identity + access** | Everyone locked out; role grants lost | ❌ |
| **CMS content + version history** | Editorial work and the approval record destroyed | ❌ In practice |
| **`Audit.AuditLog`** | Append-only compliance record. Losing it is a regulatory problem, not just an operational one | ❌ |
| **`AI.SafetyEvent`** | Evidence the AI boundary held | ❌ |
| **Feature flags / settings** | Recoverable from seed, minus operator changes | 🟡 Partly |
| **Schema and procedures** | In git, fully reproducible | ✅ |

The mobile app's own data lives on-device in SQLite with checksummed export, so a server loss does not destroy a user's local record. That is a genuine mitigation and worth stating — but it does not cover anything server-side, and it is not a backup strategy.

---

## 3. Targets

| Objective | Target | Rationale |
|---|---|---|
| **RPO** (max data loss) | **≤ 15 minutes** | Achievable with managed PITR at no meaningful cost |
| **RTO** (max downtime) | **≤ 4 hours** | Realistic for a two-person team without a hot standby |
| **Backup retention** | 35 days PITR + 12 monthly long-term | Covers "we noticed last month" |
| **Restore rehearsal** | Quarterly, and before launch | An untested backup is a belief, not a backup |

RTO is deliberately honest. A two-person team with no runbook will not restore in fifteen minutes, and publishing a target nobody can hit is how incidents become worse.

---

## 4. Strategy: buy it, don't build it

**Use managed database backups.** Azure SQL (or an equivalent managed SQL service) provides automated full/differential/log backups, point-in-time restore, and geo-redundant storage **as configuration**. A hand-rolled `sqlcmd BACKUP DATABASE` cron job on a VM is more work, more failure modes, and — critically — it is the one that silently stops running and nobody notices until a restore is needed.

| Layer | Mechanism | Frequency | Retention |
|---|---|---|---|
| Transaction log | Managed, automatic | ~10 min | 35 days (PITR) |
| Full | Managed, automatic | Weekly | 35 days |
| Differential | Managed, automatic | ~12 h | 35 days |
| Long-term | Managed LTR policy | Monthly | 12 months |
| **Geo-redundant copy** | Managed, different region | Continuous | Per policy |
| Schema + procedures | Git | Every commit | Forever |

**Required change:** recovery model must be **FULL** in production. `SIMPLE` cannot do point-in-time recovery. This is a one-line configuration change and it is non-negotiable for launch.

---

## 5. If self-hosting is chosen instead

Only if a managed service is ruled out. Then all of this becomes your responsibility:

- Full backup nightly, differential every 6h, **log backup every 15 min** (this is what buys the RPO)
- `WITH CHECKSUM` on every backup, and `RESTORE VERIFYONLY` immediately after
- Copy offsite the same night; a backup on the same host is not a backup
- Encrypt at rest; this is health data
- **Monitor the backup job itself** and alert on absence, not only on failure — a job that stopped running produces no failures at all
- Rotate and prune on a schedule so the volume does not fill and stop the instance

The monitoring line is where self-hosted backup strategies usually die: everybody alerts on a failed backup, almost nobody alerts on a backup that simply never ran.

---

## 6. Things a database backup does not cover

| Gap | Handling |
|---|---|
| **Secrets** | Not in the database. Key Vault with soft-delete and purge protection; losing the JWT signing key invalidates every token |
| **Blob/media** | Schema stores keys only; the objects need their own versioned, soft-delete-enabled storage |
| **Container images** | Retain tagged images so a rollback target still exists |
| **Config** | Environment settings must be in code (IaC), or a rebuilt environment is guesswork |

---

## 7. GDPR interaction — the one that catches people

Backups and the right to erasure conflict directly, and the conflict must be *decided*, not discovered.

- An erasure request cannot practically rewrite 35 days of backups.
- The defensible position: **erase from the live database immediately; backups age out on their documented retention; restored backups are re-processed against the erasure log before returning to service.**
- That requires an **erasure log** that survives a restore, and a documented restore step that replays it.

This depends on `usp_User_Erase`, which is referenced in a comment in `02_Identity.sql` and **does not exist** (see `DATABASE_REVIEW.md` C-4). Backup policy and erasure capability have to land together; a retention policy written before erasure exists is a promise the system cannot keep.

---

## 8. Implementation order

| # | Step | Blocks |
|---|---|---|
| 1 | Choose the database platform | Everything below |
| 2 | Set recovery model **FULL** | PITR |
| 3 | Enable automated backups + geo-redundancy | RPO |
| 4 | Configure 35-day PITR + 12-month LTR | Retention |
| 5 | Alert on backup age, not only on failure | Silent-stop detection |
| 6 | **Perform a real restore** (`RECOVERY_PLAN.md`) | **Launch sign-off** |
| 7 | Document erasure-vs-backup and build `usp_User_Erase` | GDPR posture |

Step 6 is the one that converts this document from a plan into a capability. Until a restore has actually been performed and timed, the RTO above is a guess.
