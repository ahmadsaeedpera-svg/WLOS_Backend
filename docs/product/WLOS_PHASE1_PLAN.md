# WLOS Phase 1 — audit and implementation plan

**Date:** 23 September 2026
**Status:** plan only. **No code written.** Approval required before implementation.
**Supersedes:** the Phase A interview gate in `PROJECT_STATE.md` §9.

---

## 0. How the gate changed, recorded honestly

Phase A interviews were **not run**. The freeze was lifted by product decision,
with the validation risk knowingly accepted — not because evidence arrived.

That distinction matters for one practical reason: the interviews were designed
to answer five questions, and those questions do not disappear because the gate
moved. They transfer to the product:

| Phase A would have asked | Phase 1 must instrument instead |
|---|---|
| Does she experience the interaction? | Does she *record* enough for one to be visible? |
| Is there an unmet gap? | Does she return after the first week? |
| Does remembering help? | Does she engage with a surfaced memory? |
| Does she permit that memory? | Does she keep memory on when offered the control? |
| Does it recur often enough? | Day-7, day-30 return rate |

**Build the instrumentation into Phase 1**, or the risk is accepted and never
measured, which is the worse outcome. Specified in §5.

**The constitution is unchanged and remains binding.** Changing the validation
gate does not relax a single safety, privacy or retention rule.

---

## 1. Audit — the seven capabilities against what exists

Measured against deployed `WlosPlatform` and the C# source, 23 September.

| # | Capability | Data | Procedures | C# / API | Verdict |
|---|---|---|---|---|---|
| 1 | Personal profile | `Identity.Profile`, `User`, `UserLifeStage`, `UserRoleMode` | 9 write procs | **Yes** | **EXISTS** |
| 2 | Preferences & boundaries | only `Health.BirthPreference` *(pregnancy-specific)* | none | none | **ABSENT** |
| 3 | Daily check-in | `Health.DailyLog` — `Mood`, `Energy`, `SleepQuality`, `WaterGlasses`, `Note` | **0** | **0** | **TABLE ONLY** |
| 4 | Events / reminders | `Timeline.Event`, `EventType`, `Appointment`; `Notifications` ×4 | `usp_Timeline_Record` **exists**; Notifications **0** | **0** | **SQL ONLY** |
| 5 | Goals | `Growth.*` ×6 | 1 write proc | partial | **MOSTLY EXISTS** |
| 6 | Personal memories | none | none | none | **ABSENT** |
| 7 | Companion conversation | none | none | `aiContextResolution` is an `UnbuiltStage` | **ABSENT** |

### The finding that shapes everything

**`Health` has 9 tables, 0 stored procedures and 0 C# references.
`Timeline` has 6 procedures — including `usp_Timeline_Record` — and 0 C#
references.**

Verified: `grep -rn "usp_Timeline_\|Health\." --include="*.cs" src` returns
**nothing**.

So the platform has a rich read and evaluation layer and **no ingestion layer**.
This is better than it first looks — the `Timeline` write procedure already
exists, so part of Phase 1 is **wiring, not inventing**. But `Health` needs its
procedures written from scratch.

### One correction to an earlier report

I previously wrote that no write path exists at all. `usp_Timeline_Record`
exists. What does not exist is any repository, handler or endpoint that calls
it. The gap is the C# layer, not the database, for Timeline; for Health the gap
is both.

---

## 2. Phase 1 scope

### In scope — the loop, end to end, once

```
Profile/preferences -> daily input -> stored -> context -> Today -> memory -> next Today
```

| Item | Work | Basis |
|---|---|---|
| **Write path: Timeline** | wire | `usp_Timeline_Record` exists; needs repository + handler + endpoint |
| **Write path: check-in** | build | `Health.DailyLog` exists; needs procedures + C# + endpoint |
| **Preferences & boundaries** | build | Nothing exists. Applied at the single context assembly point |
| **Memories** | build | Nothing exists. Smallest possible: text + when + why it matters |
| **Today screen** | build | `/me/today` already returns decisions with `reason`/`evidence`/`confidence`/`source` |
| **"Why am I seeing this?"** | surface | Provenance exists in the response and is never shown. Cheapest differentiator available |
| **Auth + session** | wire | Endpoints exist; app has `tokenProvider: () async => null` |
| **Goals** | wire | `Growth.*` largely exists |

### Explicitly out of scope for Phase 1

Conversation / LLM · camera · relationships and sharing · notifications backend ·
responsibility load · country safety configuration · content expansion beyond
seeds · the other 15 life domains · pregnancy module gating · streak redesign ·
deployment and Cloudflare.

**Conversation is out deliberately.** It is capability 7, it has no schema, no
guardrail integration and no trust basis — research measured **3–6% trust in AI
health advice without professional oversight**. Shipping a chatbot first makes
WLOS a worse ChatGPT. The structured context is the differentiator; conversation
can sit on top of it later.

---

## 3. Build order

Each step is usable on its own and unblocks the next.

**1 · Authentication** — wire the existing endpoints; replace the null token
provider. Nothing personal works without it.

**2 · Profile + life stage** — `GET`/`PUT /me/profile`, `/me/life-stage`. First
point at which WLOS knows anything. **Today it is impossible to set a life stage
from the app.**

**3 · Preferences, boundaries, personalization controls** — new. Applied once,
at the context assembly point in `LifeOsRepository`, so every downstream feature
inherits them. **Before** the features, not after; retrofitted it becomes fifty
enforcement points. Constitution §1.5 and §4 bind this.

**4 · Daily check-in (write path)** — `Health.DailyLog` procedures + repository
+ endpoint. First user-generated data in the system.

**5 · Timeline write (wiring)** — repository + handler + endpoint over
`usp_Timeline_Record`. Feeds signals, state, behaviour, goals, recommendations,
coaching, prediction — all of which already exist and currently receive nothing.

**6 · Today screen** — render `/me/today`. The pipeline already produces
explainable decisions; nothing consumes them.

**7 · "Why am I seeing this?"** — surface `reason`, `evidence`, `confidence`,
`source`. Already in the payload. **This is the highest value-to-cost item in
the entire plan.**

**8 · Memories** — new, minimal. What she asked WLOS to remember, when, and why.

**9 · Goals** — wire the existing `Growth.*` surface.

**10 · Instrumentation** — §5. Not optional.

---

## 4. Constitution constraints binding every item

- **Never infer** pregnancy, fertility, relationship status, religion,
  motherhood, diagnosis, or emotion from an image. Each may be *stated*.
- **UNKNOWN is valid** — `Intelligence.StateDimension.UnknownText` already
  supplies the per-dimension wording. Use it; do not invent empty states.
- **Boundaries beat inferences.** A boundary overrides any signal, rule or
  model.
- **Needs decay.** If a need is added, it expires in hours, not months.
- **Retention from accumulated value, never pressure** (§1.9). The inherited
  streak ring is subject to this and must not ship unchanged.
- **Marketing copy is in scope** (§1.10). Store text determines regulatory
  classification.
- **No automatic sharing.** Nothing in Phase 1 shares anything with anyone.

---

## 5. Instrumentation — the price of skipping the gate

Phase 1 must measure what the interviews would have told us. All of it is
first-party, aggregate, and subject to the same privacy rules.

| Question | Metric |
|---|---|
| Does she come back? | Day-1, day-7, day-30 return rate |
| Is the join perceived? | Tap-through rate on "Why am I seeing this?" |
| Does memory earn its place? | Engagement with a surfaced memory vs a generic card |
| Does trust hold? | Share of users who *keep* personalization controls on when offered |
| Is there enough signal? | Median entries per user per week |

**Pre-commit the numbers that would mean this is not working**, in the same
spirit as the locked research thresholds. A metric with no threshold set in
advance becomes a number that is always interpreted favourably.

Suggested, to be agreed before build: day-30 return **below 10%** (category
median is 5%), or personalization switched **off by more than half** of users,
is a signal to stop and reconsider rather than to add features.

---

## 6. Decisions needed before code — ALL FIVE RESOLVED

Locked by decision before Slice 1. Do not reopen unless an implementation
contradiction makes one impossible.

| # | Decision | Answer | Where it now lives |
|---|---|---|---|
| 1 | Canonical WLOS API port | **5299** | `launchSettings.json`, `CLAUDE.md`, `README.md`, `docs/DEPLOYMENT.md`, `docs/PLATFORM_RUNBOOK.md`. Maren keeps 5199 and the two must never collide. |
| 2 | Launch age | **18+** | `Identity.fn_MinimumAge()`, enforced in `usp_User_Register` and `usp_Profile_Save` |
| 3 | Deletion semantics | **Hard, for Phase-1 user-owned data** | `usp_User_DeleteAccount`; the one named exception to the append-only rule (CLAUDE.md §4.8) |
| 4 | Does the app write to the server in Phase 1? | **Yes — server-backed, local cache for offline/performance/drafts** | `core/auth/` in the app; About screen claims rewritten in the same change |
| 5 | Instrumentation | **From day one**, thresholds pre-committed separately | Six account events in `AnalyticsEvent.allowlist` |

**On decision 3, the part that was not obvious.** Hard deletion collides with
two standing rules — the audit log is append-only, and so is the AI safety
ledger. Both were resolved the same way: `usp_User_DeleteAccount` is a single
named exception in all three assertion suites that enforce the rule, it refuses
any account holding a role beyond `Member`, and it appends a tombstone so the
fact of an erasure outlives the account. The reasoning is that append-only
protects the platform from an operator tidying up after themselves, and a woman
closing her own account is the subject of those logs rather than an actor in
them.

### The original framing, kept for the record

**Decision 4 is the largest.** The app currently makes three GETs and zero
writes, and the About screen claims no network code. A write path changes the
Play Store Data Safety declaration and the privacy posture. It may be that
Phase 1 stores locally and syncs later — that is a legitimate design, and it
changes the build order substantially.

**Decision 3 must be settled before the first user record is written.**
Retrofitting hard delete across 83 soft-deleting tables is far harder than
choosing now.

---

## 7. What happens on approval

Implementation proceeds against the existing repositories, preserving everything
established. Work is committed in reviewable slices, one per build-order step,
and the slice is not "done" because it compiles — it is done when the loop runs
end to end and passes privacy, authorization, deletion, audit, safety and error
handling.

**No code has been written for this plan.**
