# WLOS Life Model — review of the vision, and the blueprint

**Date:** 23 September 2026
**Measured against:** `WlosPlatform` (deployed, 57/57) and `WLOS_Backend` `bd26fcf`
**Status:** product review and model definition. No code written.

---

## Part 1 — The finding that should change the plan

**The vision assumes WLOS needs a new architecture built around seven worlds. It
does not. Most of it is already in the schema.**

`Content.LifeDomain` is seeded with **22 life domains in a hierarchy**:

```
health ──┬── cycle          career ──── work
         ├── pregnancy      nutrition ── hydration
         └── body           lifestyle ── routine

fitness    nutrition   mental      sleep       selfcare
beauty     medication  career      learning    family
relationships          parenting   finance     household
shopping   travel      community   productivity
spirituality           emergency   lifestyle
```

**`pregnancy` is already a child of `health`, at depth two.** The subordination
the vision argues for is not a change to make — it is the shape of the data.

`Timeline.EventType` carries 17 matching categories: body, cycle, fitness,
health, household, hydration, learning, lifestyle, medication, mental,
nutrition, pregnancy, relationships, routine, selfcare, sleep, work.

So the seven worlds are not a new model. They are **a grouping of 22 domains
that already exist**. Creating a second taxonomy beside this one would be the
single most damaging thing we could do — two competing structures, and the one
that drifts is the one nobody reads.

### Mapping the seven worlds onto what exists

| World | Existing domains | Status |
|---|---|---|
| **BODY** | health, cycle, pregnancy, body, fitness, nutrition, hydration, sleep, medication, selfcare, beauty | **Complete** |
| **MIND** | mental | **Thin** — one domain, no emotion model |
| **SELF** | learning, productivity, spirituality | **Partial** — no identity, values or strengths |
| **LIFE** | career, work, household, finance, shopping, travel, emergency, lifestyle, routine | **Complete** |
| **PEOPLE** | family, relationships, parenting, community | **Domains exist, the model does not** |
| **ENVIRONMENT** | `Identity.Country`, `Identity.Language`, season targeting | **Partial** |
| **JOURNEY** | `Timeline.Event`, `Identity.UserLifeStage` (with history) | **Complete** |

Five of seven are substantially built.

### The intersection engine already exists too

Section 15 of the vision — "the real intelligence is the intersection" — names
the most important idea in the document. It is also already modelled:

- `Knowledge.Signal`, `SignalRelation`, `SignalRule` — 12 signals seeded
- `Intelligence.StateDimension`, `StateRule`, `UserStateSnapshot` — 9 dimensions
- `Rules.Rule`, `Rules.TargetScope`
- `Recommend.*`, `Coach.*`, `Predict.*` — the care layer
- A 24-stage pipeline that runs them in order, with explainability
  (`reason`, `evidence`, `confidence`, `source`) as a contract

**Poor sleep + high workload + approaching period + low mood → overload → care**
is expressible in `SignalRelation` and `Rules.Rule` today.

---

## Part 2 — What is genuinely missing

Three things. Only three.

### 2.1 NEED — the best idea in the vision, and absent from the schema

"What do you need right now?" with `I need rest / someone / calm / space / to
talk / help organising` has **no representation anywhere**. There is no `Need`
table, no need dimension in targeting, nothing.

It is also the cheapest thing on the list: a reference table, a user-selected
value, and an eleventh targeting dimension. `TargetingDimension` was explicitly
designed so "a tenth dimension is a seed row" — an eleventh is the same.

**This is where I would start.** It changes what the product *is* — from a
system that infers what she needs to one that asks — for a fraction of the cost
of anything else in the vision.

### 2.2 EMOTION as first class

`mental` is one domain among 22, and mood currently lives as a field on a daily
log. The vision wants emotional state to be a dimension the whole system reads:
*"I don't know what's wrong with me"* answered with *"would you like to talk
about what happened today?"*

That needs emotion as a modelled concept, not a column.

### 2.3 RELATIONSHIP — and this one is not simple

`Health.ShareGrant` already exists and is better designed than most sharing
features:

| Column | Why it matters |
|---|---|
| `ScopesJson` | Share a scope, not an account |
| `ExpiresUtc` | Access ends by default |
| `RevokedUtc` | Revocable |
| `LastViewedUtc`, `ViewCount` | **She can see who looked, and when** |

That last pair is anti-surveillance by construction and should be preserved in
anything built on top.

But it is **token-based** — `TokenHash` and a free-text `RecipientLabel`. It
shares a link with a midwife. It does not connect her account to her mother's.
The PEOPLE world needs account-to-account relationships, and that is genuinely
new work.

**Before any of it is built, read Part 3.**

---

## Part 3 — Where the vision needs hard challenge

Four things. The first two are not refinements; they are decisions that change
what the product is allowed to be.

### 3.1 Children are not a life stage. They are a different legal product.

The vision includes age 8, and an `adolescence` stage exists. Combined with
camera capture, emotional journaling and parental sharing, that is one of the
most heavily regulated categories in software:

- **COPPA** (US) — verifiable parental consent under 13
- **GDPR Article 8** (EU) — digital consent age 13–16 depending on member state
- **Google Play Families** and **App Store Kids Category** — separate review,
  ad restrictions, SDK restrictions
- **UK Age Appropriate Design Code** — 15 standards, default high privacy

This is not a compliance task to schedule later. It determines consent flows,
data retention, whether behavioural personalisation is permitted at all, and
possibly whether under-13 needs a **separate app listing**.

> **Decide the minimum age before writing the Life Model's youngest bands.**
> If the answer is 13+, the model is simpler and one product ships. If it is 8+,
> accept that a second, heavily constrained product is being built alongside.

### 3.2 The mother/daughter sharing model is the highest-risk feature in the vision

"Connection without surveillance" is exactly the right intent. The risk is that
the person a girl most needs privacy *from* is sometimes the person asking for
access — and the same is true of a controlling partner.

The vision's own framing already protects against the obvious failure
("*not* here is Mom's complete medical record"). Three further rules are needed,
and they are design constraints, not features:

1. **Revocation must be silent.** If revoking sharing notifies the recipient, or
   if the recipient can tell something is hidden, revocation becomes unsafe to
   use. A "she stopped sharing" signal is a coercion trigger.
2. **There must be nothing that reveals the existence of private content.** Not
   a locked icon, not a greyed row, not a count. Absence must be indistinguishable
   from nothing-to-show.
3. **Sharing is never a default and never a setup step.** Any flow that asks a
   13-year-old to connect a parent during onboarding will be completed under
   supervision, which makes the consent meaningless.

`ShareGrant`'s `ViewCount` and `LastViewedUtc` support rule 1 well: she can see
access without the recipient being told she looked.

**In many of the cultural contexts WLOS is aimed at, family monitoring of women
is a genuine safety issue rather than a hypothetical.** This feature is worth
building. It is not worth building quickly.

### 3.3 Face analysis: baseline-change is defensible, emotion classification is not

The vision already draws the right line — *"your appearance looks different from
your usual morning baseline"* rather than *"you have anemia."* Hold that line
precisely, because the two sides of it are scientifically different:

- **Change from a personal baseline** is a measurement against herself. It makes
  no population claim and no diagnosis.
- **Emotion inference from facial expression** rests on a contested premise —
  that discrete emotions map reliably onto facial configurations — and performs
  unevenly across skin tones, ages and cultures. The EU AI Act restricts emotion
  inference in several contexts.

`AI.SafetyEvent` already exists in the schema, and the `aiContextResolution`
stage is a deliberate `UnbuiltStage` whose stated reason is *"Guardrails ship
before generation."* That ordering is correct and should not be reversed under
schedule pressure.

**Recommendation:** ship baseline-change only. Never emit an emotion label from
an image. If she says how she feels, use that; it is better data and it is hers.

### 3.4 The vastness is not the bottleneck — and expanding it will not help

This is the uncomfortable one.

| The platform has | Count |
|---|---|
| Life domains | 22 |
| Targeting dimensions | 10 |
| Life stages | 12 |
| Role modes | 8 |
| Knowledge signals | 12 |
| Pipeline stages | 24 |
| API endpoints | 68 |
| **Content items** | **6** |

Every architectural concept in the vision is either present or a seed row away.
**What does not exist is anything to say.** A woman opening WLOS today gets six
FAQ entries.

Adding seven worlds of architecture moves nothing. Writing content for
adolescence, perimenopause, menopause and healthy aging moves everything.

> The constraint on WLOS is editorial, not technical. Any plan that adds
> architecture before content is optimising the part that is already finished.

---

## Part 4 — The boundary test

The vision names the "everything app" risk and answers it well:

> WLOS does not own every part of her life. It understands the parts she chooses
> to bring into WLOS and helps connect them.

That needs to be operational, so here is the test:

> **Does this feature need *her context* to be better than a standalone app
> already on her phone?**

| Feature | Needs her context? | Verdict |
|---|---|---|
| "What do you need today?" | Yes — meaningless without it | **Build** |
| Cycle + workload + sleep intersection | Yes — the whole point | **Build** |
| Life-stage-appropriate content | Yes | **Build** |
| Support-language preference | Yes | **Build** |
| Relationship sharing | Yes | **Build, carefully (3.2)** |
| Bill payment, subscriptions | No | **Don't** |
| Shopping lists | No | **Don't** |
| Travel booking | No | **Don't** |
| Document storage | No | **Don't** |
| Generic chatbot | No | **Don't** |

`finance`, `shopping` and `travel` exist as domains, and that is fine — they can
be *context* WLOS reads without being *features* WLOS owns. Knowing she has a
financial worry can shape care. Paying her bill cannot.

---

## Part 5 — The Life Model

The blueprint, expressed in primitives that already exist wherever possible.

### 5.1 The dimensions

| Dimension | Values | Where it lives | Status |
|---|---|---|---|
| **Age band** | 11 bands (below) | derived from `Identity.Profile.DateOfBirth` | ✅ exists |
| **Life stage** | 12 | `Identity.LifeStage` | ✅ exists |
| **Role mode** | 8, multi-select | `Identity.RoleMode` + `UserRoleMode` | ✅ exists |
| **Domain** | 22, hierarchical | `Content.LifeDomain` | ✅ exists |
| **Event** | 17 categories | `Timeline.EventType` | ✅ exists |
| **Goal** | user-defined | `Growth.UserGoal`, `GoalTemplate` | ✅ exists |
| **Condition** | self-reported, never a diagnosis | targeting dimension `condition` | ✅ exists |
| **Country / language / season** | — | `Identity.Country`, `Language`, targeting | ✅ exists |
| **State** | 9 dimensions | `Intelligence.StateDimension` | ✅ exists |
| **NEED** | 10 (below) | — | ❌ **new** |
| **EMOTION** | ~15 | partial, in daily log | ⚠️ **promote** |
| **RELATIONSHIP** | 8 kinds | `Health.ShareGrant` is the consent half | ⚠️ **half exists** |

**Nine of twelve dimensions exist.** Three are the work.

### 5.2 Age bands

Derived, never stored — so it cannot go stale:

| Band | Typical focus | Regulatory note |
|---|---|---|
| under 11 | *(out of scope unless 3.1 says otherwise)* | **COPPA / AADC** |
| 11–13 | puberty, hygiene, body literacy, friendship, school | **GDPR Art. 8 boundary** |
| 14–17 | cycle, identity, exams, confidence, relationships | minor |
| 18–21 | independence, university, career direction | adult |
| 22–29 | career, finances, relationships, cycle health |  |
| 30–39 | career, partnership, pregnancy *if chosen*, parenting |  |
| 40–49 | caregiving, perimenopause, career, parents aging |  |
| 50–59 | menopause, purpose, career transition |  |
| 60–69 | healthy aging, social connection, purpose |  |
| 70–79 | mobility, medication routines, connection |  |
| 80+ | independence, dignity, caregiving |  |

**Age band is a signal, never a gate.** A 45-year-old may be pregnant; a
30-year-old may be perimenopausal; a 60-year-old may be a new student. The band
adjusts emphasis; `life_stage` and `role_mode` decide what appears.

### 5.3 Needs — the new dimension

Ten, deliberately few, each phrased as she would say it:

`rest` · `company` · `calm` · `clarity` · `motivation` · `to talk` ·
`space` · `organising` · `enjoyment` · `care`

Two properties matter more than the list:

1. **A need is a self-report, never an inference.** The system may *offer* the
   question. It may not answer it on her behalf.
2. **A need decays.** "I need space" is true this evening, not this month. Needs
   are stateful and short-lived, unlike goals.

Implementation: a reference table, a user-need table with expiry, and an
eleventh row in `TargetingDimension`. Everything downstream — content, coach,
recommendation — reads it through machinery that already exists.

### 5.4 Response mode — the second-best idea in the vision

Section 16: *"WLOS should understand I don't want advice."*

`Advice · Listen · Help me decide · Help me plan · Comfort · Space`

This belongs beside needs and is equally cheap. It maps onto `Coach.ToneProfile`
and `Coach.ToneRule`, which already exist. It is the difference between a system
that responds to her and one that responds at her.

### 5.5 Relationship kinds

`mother` · `daughter` · `partner` · `sibling` · `friend` · `care recipient` ·
`care giver` · `clinician`

Each is a `ShareGrant`-style scoped, expiring, revocable, view-counted grant —
**never a role with standing access**. Subject to all three rules in §3.2.

### 5.6 The rule that keeps this coherent

Everything above is **one context object**, consumed by every feature:

```
Identity → Profile → LifeStage + RoleModes + AgeBand
        → State (9 dimensions) + Needs + Emotion
        → Goals + Events + Relationships
        → Country + Language + Season
```

That is what `fn_TargetedItems(@ContextJson)` already takes. Its ten dimensions
become twelve. **No feature computes its own view of her.** That single rule is
what prevents fifty disconnected modules, and it is already enforced by the
architecture.

---

## Part 6 — Sequence

1. **Decide the minimum age** (§3.1). Blocks the youngest bands, the camera and
   anything involving parents.
2. **Fix the `ContentTargetingRule` deploy defect.** Targeting is the spine of
   all of this and a clean deploy currently omits its rules table.
3. **Add NEED** — table, user-need with expiry, eleventh targeting dimension.
4. **Add response mode** onto the existing `Coach.ToneProfile`.
5. **Content.** The actual bottleneck. Adolescence, perimenopause, menopause,
   healthy aging first — the four least served and the furthest from pregnancy.
6. **Promote emotion** to a first-class dimension.
7. **Relationships**, once §3.2's three rules are agreed and written down.
8. **Baseline-change sensing**, guardrails first, never emotion labels.

Steps 1–4 are small. Step 5 is the product.

---

## Part 7 — Two corrections to earlier reports

- **`Identity.Profile` has `AvatarMediaId`.** My earlier statement that profile
  photos were entirely absent was wrong about the schema: a slot exists. What
  does not exist is any upload path, media dependency, or moderation — so the
  conclusion (photos are not a current capability) stands, but the schema is
  further along than I said.
- **`Identity.Profile` also carries `BabyTerm` and `ExpectingMultiples`** —
  pregnancy-specific fields on the core profile table. Minor pregnancy-first
  residue in an otherwise neutral model. Worth noting, not worth migrating yet.
