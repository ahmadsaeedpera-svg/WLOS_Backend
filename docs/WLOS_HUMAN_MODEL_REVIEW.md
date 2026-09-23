# WLOS Human Model Review — constitution reconciled against the schema

**Date:** 23 September 2026
**Measured against:** `WlosPlatform` (deployed, 57/57) · `WLOS_Backend` `6d2cc2e`
**Method:** direct queries against the deployed database. Nothing inferred from
documentation.
**Constraint honoured:** no schema modified, nothing implemented, no capability
invented. Where something does not exist, this says so.

---

## The headline

**The four-concept hierarchy the review proposes — FACT → OBSERVATION → PATTERN
→ INTERPRETATION — is already implemented, and so is confidence.**

`Knowledge.SignalRelation` carries `RelationKind`, `Strength` and `SourceNote`.
Its seeded rows are the vision's own example:

```
long_work        → high_stress     (commonly_precedes)
long_work        → low_selfcare    (commonly_co_occurs)
high_stress      → low_mood        (commonly_co_occurs)
high_stress      → short_sleep     (commonly_precedes)
high_screen_time → short_sleep     (commonly_precedes)
late_wake        → missed_breakfast(commonly_precedes)
```

`commonly_precedes` and `commonly_co_occurs` are **deliberately not causal
language**, `Strength` is the confidence, and `SourceNote` is the provenance.
The platform already refuses to say "your work caused your low mood."

---

## The twenty questions

### 1. Is TRANSITION already represented?

**Partially, and better than expected.** `Identity.UserLifeStage` holds
`LifeStageCode`, `StartedOn`, `EndedOn`, **`Source`** and `Note`.

A stage with a start, an end and a recorded source *is* a transition record. The
history is there; `Source` distinguishes "she declared it" from "the system
derived it", which is exactly the FACT/INTERPRETATION distinction.

**What is missing:** non-stage transitions. Moving country, job loss, starting
university, bereavement and divorce have no representation unless they happen to
be life-stage changes. `Timeline.EventType` has 17 categories but they are
domains (`work`, `health`, `learning`), not transitions.

**Verdict:** the mechanism exists. The taxonomy does not. Transition may not
need a new table — it may need event types and a flag.

### 2. Is RESPONSIBILITY LOAD represented?

**No.** There is no table for children, dependents, caregiving relationships or
household responsibilities anywhere in the schema. Queried explicitly.

Two near-misses that are not the same thing:

- `Identity.RoleMode` includes `caregiver` and `homemaker` — but a role is a
  label, not a load. It says she cares for someone, not for how many, how
  dependent, or at what cost.
- `Intelligence.StateDimension` includes `load` — but it is derived from
  workload signals (`long_work`), not from dependents.

**Verdict: genuinely new.** The 38-year-old with two children and an elderly
parent is indistinguishable from the 38-year-old living alone, if both work.

### 3. Is SUPPORT NETWORK represented?

**No — only the consent half.** `Health.ShareGrant` holds `RecipientKind`,
`RecipientLabel` (free text), `TokenHash`, `ScopesJson`, `ExpiresUtc`,
`RevokedUtc`, `LastViewedUtc`, `ViewCount`.

That is link-based sharing with a stranger — a midwife — not a modelled person.
There is no `Person`, no trust role, no emergency role, no "Person B helps
practically, Person C is my emergency contact."

**Verdict:** the review's richer model (person / relationship / trust role /
sharing scope / emergency role / consent) is new work. The consent primitive
underneath it is sound and should be reused rather than replaced.

### 4. What is `Intelligence.StateDimension`?

Nine dimensions — `energy`, `focus`, `consistency`, `wellness`, `balance`,
`routine`, `momentum`, `load`, `risk` — each with `ValueKind`, `BaselineScore`
and **`UnknownText`**.

`UnknownText` is the significant column. Each dimension carries its own
user-facing sentence for having no answer:

> energy · "Not enough logged to tell yet."
> momentum · "Needs a few days before this means anything."
> risk · "Nothing to flag."

**UNKNOWN is not a null here. It is a designed, per-dimension message.** The
principle the constitution states in prose is implemented at the presentation
layer.

### 5. What is `Coach.ToneProfile`?

Four tones — `steady`, `gentle`, `encouraging`, `brief` — with `Pattern`,
`Weight`, `IsDefault` and an accompanying `Coach.ToneRule`.

This is **how WLOS speaks**, selected by rule and weight. It is roughly half of
the proposed response mode: `gentle` and `brief` map onto *Comfort* and
*Space*; there is nothing for *Listen*, *Help me decide* or *Help me plan*,
because those change **what the system does**, not merely how it phrases it.

**Verdict:** tone exists; intent does not.

### 6. What can `fn_TargetedItems` consume?

A single `@ContextJson` — a JSON array of `{dimension, value}` pairs. It
evaluates rules with three operators (`in`, `not_in`, `between`), ORs within a
dimension and ANDs across them, and returns matching content ids.

Two properties matter for everything proposed:

- **An item with no rules matches everyone.** Universal content is free.
- **`not_in` requires she has a value for that dimension before it can
  exclude** — an unknown is never excluded.

**Adding a dimension is a seed row.** Need, transition, responsibility load and
access all become targetable without schema change to the evaluator.

### 7. What is the current source of truth for user context?

`LifeOsRepository` assembles `LifeOsContextRow` from stored procedures:
life stage, role modes, country ISO, language, timezone. The 24-stage pipeline
then publishes into an `IntelligenceContext`, and `ResolveLifeOsHandler` returns
it as `LifeContext`.

**There is one assembly point.** That is the single most valuable architectural
fact in this document: preferences, boundaries and controls can be applied in
one place and every feature inherits them.

### 8. What is persisted versus calculated?

| Persisted | Calculated per request |
|---|---|
| Profile, life stage history, role modes | Age band (from `DateOfBirth`) |
| Timeline events, goals, health entries | State dimension values |
| Signals and their relations (reference) | Signal firing |
| Content, rules, translations | Targeting matches |
| `Intelligence.UserStateSnapshot` | Decisions, recommendations, coaching |
| Audit log | The whole `/me/today` response |

Nothing about *her* is stored as a conclusion. Snapshots are stored as history,
not as a standing belief.

### 9. What data is sensitive according to the schema?

Sensitivity is **a property of the taxonomy, not a guess at query time**:

- `Content.LifeDomain.IsHealthSensitive`
- `Timeline.EventType.IsHealthSensitive`
- `Administration.Setting.IsSecret`
- `Identity.SecurityStampRevocation` — session revocation
- `dbo.AuditContractExemption` — tables deliberately outside audit

The audit contract is applied by cursor over `sys.tables`, so a new table is
audited by default rather than by remembering to opt in.

### 10. What audit events already exist?

`Audit.AuditLog` is append-only with `ActorUserId`, `ActorKind`, `Action`,
`EntityType`, `EntityId`, `BeforeJson`, `AfterJson`, `IpAddress`,
`CorrelationId`.

Only **3 distinct actions** exist in this fresh database, because it has barely
been used — the taxonomy is written by the procedures, not seeded. Observed
elsewhere: `User.Register`, `User.LoginSucceeded`, `Identity.OperatorClaimed`,
`Content.Create/Approve/Publish`, and notably
`Security.OperatorClaimRefused` — **refusals are audited, not just successes.**

### 11. What does `Health.ShareGrant` actually expose?

`ScopesJson` — a scope list, not an account. Plus expiry, revocation, and
`LastViewedUtc` / `ViewCount`.

**She can see who looked and when. The recipient cannot see that she looked.**
That asymmetry is the right one and must survive into anything built on it.

### 12. What is missing for account-to-account relationships?

Everything except consent: a `Person` concept, linkage between two WLOS
accounts, invitation and acceptance, trust roles, emergency roles, and
per-relationship scope defaults.

**And the three safety rules must be settled before any of it** — silent
revocation, no signal that private content exists, never a default or an
onboarding step.

### 13. What does the AI safety architecture actually protect?

More than expected. `AI.SafetyEvent` records `Domain`, `Decision`,
`RefusalCategory`, **`ClinicalScore`**, **`CrisisScore`**, `PromptVersion`,
`ModelId`, `LatencyMs`, `CorrelationId`.

Two separate risk scores — clinical and crisis — with refusal categories, and
both the prompt version and model id recorded against every decision. That is a
reviewable audit trail for AI behaviour, built before any model was integrated.

`aiContextResolution` remains a deliberate `UnbuiltStage` reading *"Guardrails
ship before generation."* The guardrails are the part that exists.

### 14. What can the camera subsystem currently do?

**Nothing. It does not exist.** No media dependency in `pubspec.yaml`, no
camera permission, no capture path, no feature extraction, no baseline storage.

`Identity.Profile.AvatarMediaId` is a column with no upload path behind it.

**Verdict:** the review's question about derived-feature retention is not yet a
policy gap — it is a policy that can be written before anything is built, which
is the right order.

### 15. What is the current mobile representation of all this?

Minimal. `WLOS_App` consumes **3 of 68 endpoints**, all GET. No screen reads
`lifeStageCode`. There is no UI for setting a life stage, no preference screen,
no needs, no relationships.

**The platform models a rich person. The app shows almost none of it.**

### 16. Where does international configuration stop?

`Identity.Country` holds four columns: `IsoCode`, `Name`,
`DefaultLanguageCode`, `IsSupported`.

It stops there. No region, no emergency pathway, no measurement system, no
calendar convention, no healthcare model, no regulatory profile.

Stronger than expected elsewhere: `Identity.Language.IsRightToLeft`,
`Content.ContentTranslation.IsMachineTranslated`, `Content.ContentReview`.

**Verdict:** localisation is well served. **Regional safety is not served at
all**, and the review is right that location, locale and culture must be three
concepts rather than one.

### 17. Which primitives can be reused without modification?

`Content.LifeDomain` (22, hierarchical) · `Identity.LifeStage` (12) ·
`RoleMode` (8, multi-select) · `TargetingDimension` + `ContentTargetingRule` +
`fn_TargetedItems` · `Knowledge.Signal` / `SignalRelation` / `SignalRule` ·
`Intelligence.StateDimension` · `Timeline.Event` / `EventType` · `Growth.*` ·
`Coach.ToneProfile` / `ToneRule` · `Audit.AuditLog` · `AI.SafetyEvent` ·
`ContentTranslation` / `ContentReview` / `ContentPublishSchedule` ·
`Health.ShareGrant` as a consent primitive.

### 18. Which proposed concepts are genuinely new?

**Six**, in order of cost:

| Concept | Cost | Note |
|---|---|---|
| Need | small | reference table + user table with expiry + seed row |
| Intent / response mode | small | tone exists; intent does not |
| Preference + boundary + controls | **medium — do first** | nothing exists; one assembly point to apply it |
| Responsibility load | medium | self-declared only |
| Country safety configuration | medium | emergency, healthcare, regulatory, units |
| Support network | **large** | §12, and safety rules first |

### 19. Which concepts should stay conceptual rather than become tables?

- **The seven worlds.** A grouping of 22 existing domains. A second taxonomy
  beside the first is the most damaging thing available to us.
- **Age band.** Derive from `DateOfBirth`. Storing it guarantees it goes stale.
- **FACT / OBSERVATION / PATTERN / INTERPRETATION.** Already expressed through
  `Source`, `SignalRelation.RelationKind` and `Strength`. It is a discipline,
  not a table.
- **Transition**, probably. Likely event types plus a flag, not a new entity.
- **Access / accessibility.** A targeting dimension and a recommendation
  constraint, not an entity.

### 20. What is the minimum viable WLOS Core Context Object?

What `fn_TargetedItems` already consumes, plus what she controls:

```
EXISTS TODAY                   NEW
─────────────────────────      ──────────────────────
life_stage                     need            (self-reported, decays)
role_mode  (multi)             intent          (how she wants answering)
age        (derived)           boundary        (never show me X)
country / language             preference      (I care about X)
season                         personalization controls
goal
condition
module
state      (9 dimensions)
week       (pregnancy only)
```

Ten dimensions exist. Five are new. **All five are seed rows plus one filter
applied at the single assembly point in question 7** — not an architecture.

---

## What this changes about the sequence

The review proposes: Human Model → Trust → Market → Personalization. Measurement
suggests one amendment.

**The human model is already 10 of 15 dimensions, and the trust philosophy is
already implemented in three places** — `Source` on life stage,
`RelationKind`/`Strength`/`SourceNote` on signals, and `UnknownText` on state.
FACT/OBSERVATION/PATTERN/INTERPRETATION is not a decision to make. It is a
convention already followed that should be **written down and enforced**, not
designed.

What is genuinely undecided is narrower than the constitution implied:

1. **Preference, boundary and personalization controls** — nothing exists, and
   there is exactly one place to apply them. Cheap now; fifty enforcement points
   later.
2. **"AI learning OFF" decomposed** — the review is right that one toggle hides
   four different controls. `AI.SafetyEvent` already separates decision, model
   and prompt version, so the distinctions are recordable.
3. **Camera policy** — write it before the subsystem exists, which is now.
4. **Support network safety rules** — before the model, not after.
5. **Country safety configuration** — the one real international gap.

Everything else is either built, or a seed row.

---

## What has not changed

**22 domains, 10 targeting dimensions, 12 life stages, 8 role modes, 12 signals,
24 pipeline stages, 68 endpoints — and 6 content items.**

Every architectural question in this review resolves to *small*, *medium*, or
*already built*. The content gap resolves to *the entire project*.
