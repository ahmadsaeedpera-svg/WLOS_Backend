# WLOS International Product Constitution, Human Model and Context Model

**Date:** 23 September 2026
**Validated against:** `WlosPlatform` (deployed, 57/57) · `WLOS_Backend` `a3720f6`
**Status:** Phase 0–4 artifact. Implementation paused. No code written.

Every claim about the existing platform below was measured against the deployed
schema, not inferred from documentation.

---

## Part 0 — The finding that should shape the constitution

**The platform can personalise. It has no model of her saying no.**

| Capability | Tables | Status |
|---|---|---|
| Targeting dimensions | `Content.TargetingDimension` | **10, working** |
| Life stages | `Identity.LifeStage` | **12** |
| Role modes | `Identity.RoleMode` + `UserRoleMode` | **8, multi-select** |
| Life domains | `Content.LifeDomain` | **22, hierarchical** |
| Right-to-left languages | `Identity.Language.IsRightToLeft` | **modelled** |
| Machine-translation flag | `Content.ContentTranslation.IsMachineTranslated` | **modelled** |
| Clinical review workflow | `Content.ContentReview` | **modelled** |
| **User preferences** | — | **❌ none** |
| **Topic boundaries ("never show me X")** | — | **❌ none** |
| **Personalization controls ("don't use my cycle")** | — | **❌ none** |
| **Consent record** | — | **❌ none** |

The only per-user preference tables in the entire platform are
`Identity.Profile` (display name, terms, date of birth, timezone, avatar) and
`Health.BirthPreference` — which is pregnancy-specific.
`Administration.Setting` has no `UserId`; it is global remote config.

So personalization today is **entirely system-side**. The system decides what is
relevant to her; she has no representation in that decision. Sections 4, 5, 20
and 21 of the vision — preference, boundary, and "do not personalize" — are not
refinements of an existing model. **There is no existing model.**

That asymmetry is what this constitution exists to correct.

---

## Part 1 — Product Constitution

### 1.1 What WLOS is

> WLOS builds a longitudinal understanding of a girl or woman's life — who she
> is, where she is, what is happening, how she feels, what matters to her, who
> she trusts, and what she needs — and uses it to help her understand, plan, act
> and connect.

### 1.2 What WLOS is not

It is not a diagnostic tool, a medical device, a therapist, a social network, a
monitoring system for families or partners, a productivity suite, or a general
assistant. It does not own her finances, her documents or her shopping.

**The boundary test**, applied to every proposed feature:

> Does this need *her context* to be better than a standalone app already on her
> phone? If not, WLOS does not build it.

`finance`, `shopping` and `travel` exist as life domains and stay that way:
**context WLOS may read, never features WLOS owns.** Knowing she has a money
worry can shape care. Paying her bill cannot.

### 1.3 Who owns the data

She does. Operationally, not rhetorically:

- She can export everything, in a readable format, without asking.
- She can delete everything, and deletion means deletion — not a flag.
- She can see what WLOS believes about her, in her own words, and correct it.
- `Audit.AuditLog` and `AI.SafetyEvent` are append-only **for as long as her
  account exists**, and record access, including by operators.

**On the third and fourth points together**, because they pull against each
other and the resolution is a decision rather than a detail:

> Operational audit and AI-safety records are append-only **during account
> lifetime**. Account deletion may erase records belonging to the deleted user.
> The deletion operation itself creates only a minimal system tombstone
> containing no personal payload.

Append-only exists so an **operator** cannot erase evidence of what they did. It
was never meant to outlive the woman it describes. Deleting an account must not
leave behind a permanent history of her mood, her crisis signals, her clinical
scores, her refusals, her IP addresses or her behaviour — a product that kept
those after she asked to be gone would be the thing this document exists to
prevent, whatever the record was called.

This is **not** a general mutable-audit system. The erasure path is one named
stored procedure, it may only remove rows belonging to the account being
erased, it refuses any account holding operator roles, and three assertion
suites fail if a second name is ever added. Confirmed 23 September 2026; see
`CLAUDE.md` §4.8 and `docs/product/SLICE_1_AUTHENTICATION.md` §5.

### 1.4 What WLOS may infer

Only from what she has given it, and only where being wrong is harmless:

- Season, timezone and local date from country
- Age band from date of birth
- Patterns in data she entered — sleep, cycle, mood, activity
- Change from **her own** baseline
- Workload from a calendar she connected

### 1.5 What WLOS may never infer

This list is binding:

- **Pregnancy, or intent to become pregnant**
- Fertility status or difficulty conceiving
- Sexual activity, orientation or partners
- Marital or relationship status
- Religion or religious observance
- Whether she has, wants or has lost children
- Mental-health diagnoses
- Any medical diagnosis
- **Emotion, from an image of her face**

Each may be *stated*. None may be *deduced*. A 29-year-old in any country is not
assumed to want fertility content; a 50-year-old is not assumed to be
menopausal; a 35-year-old is not assumed to be a mother.

> **Demographics produce possible relevance. Only she produces personalization.**

### 1.6 What WLOS may remember, and what expires

| Kind | Lifetime |
|---|---|
| Profile, preferences, boundaries | Until she changes them |
| Goals, events, journey | Until she deletes them |
| Health entries | Until she deletes them |
| **Needs** | **Hours. A need is about now** |
| **Emotional state** | **Days, as a data point; never a label that sticks** |
| Sharing grants | Until expiry or revocation, whichever first |
| Camera frames | **Never stored.** Derived baseline deltas only |

### 1.7 What WLOS may never share automatically

Nothing. There is no automatic sharing. Every grant is explicit, scoped,
expiring, revocable, and shows her who looked and when — the shape
`Health.ShareGrant` already implements.

Three rules bind anything built on it:

1. **Revocation is silent.** No recipient is ever told access ended.
2. **Nothing reveals that private content exists** — no locked icon, no greyed
   row, no count. Absence is indistinguishable from nothing-to-show.
3. **Sharing is never a default and never an onboarding step.** A flow that asks
   a 13-year-old to connect a parent during setup will be completed under
   supervision, which makes the consent worthless.

These exist because the person she most needs privacy from is sometimes the
person asking for access. In many markets WLOS would serve, family monitoring of
women is a safety issue rather than a hypothetical.

### 1.8 The governing principle

> **WLOS adapts to the woman. The woman does not adapt to WLOS.**
>
> Country, age, culture, marital status and life stage are *contextual signals*.
> None of them defines her.

### 1.9 Retention is earned, never engineered

> **We are not trying to make WLOS impossible to uninstall. We are trying to
> make WLOS valuable enough that users choose to keep it.**

These are different products, and only one of them is the one we are building.

**Permitted** — retention that comes from accumulated value:

- She has years of context here, and leaving means losing it
- It understands her better this month than last
- It remembers what matters to her without being asked

**Not permitted** — retention that comes from pressure:

- Streaks that make absence feel like failure
- Guilt, loss-framing, or manufactured urgency
- Notifications unrelated to what she is actually doing
- Anything that rewards frequency for its own sake
- Any design that fosters emotional dependency on the product

This is not only an ethical position. The EU KIDS Act bans engagement-driven
reward loops and streaks that penalise non-return for minors, and research finds
**44% of users report motivation drop-off after breaking a streak**, many
uninstalling entirely. **Pressure-based retention is both prohibited and
counterproductive.**

The inherited streak ring is subject to this clause and must be reconsidered
before it ships in WLOS — replaced by a concept rewarding continuity or being
understood, not not-missing-a-day.

### 1.10 What this constitution governs

**Four layers, not one.** Safe code with unsafe copy is still an unsafe product.

| Layer | Governs |
|---|---|
| **1 · Product behaviour** | What WLOS actually does |
| **2 · AI behaviour** | What the model may infer, say, recommend, remember or refuse |
| **3 · Content and editorial** | What the CMS publishes |
| **4 · Marketing and store positioning** | **What we claim WLOS does** |

Layer 4 is not a formality. Regulators assess intended use from *"marketing
materials, app store descriptions, website copy, social media, and user
instructions"* — external copy overrides internal documentation. A store listing
saying *"detects early signs of anaemia from your face"* makes WLOS a medical
device regardless of what the code does, and *"helps you stay healthy"* is a
health claim requiring the same scrutiny.

**Every piece of public copy is reviewed against §1.5 (never inferred) and §1.9
(retention) before publication.** Two specific traps:

- Language marketing to "girls" conflicts with the 18+ launch hypothesis and
  invites minors regulation
- Language promising she will *want to open it every day* is the
  engagement-maximising framing §1.9 forbids

---

## Part 2 — The Human Model

Twelve dimensions. **Nine exist in the schema.**

| # | Dimension | Values | Schema | Status |
|---|---|---|---|---|
| 1 | Age band | 11 bands, derived from `DateOfBirth` | `Identity.Profile` | ✅ |
| 2 | Life stage | 12 | `Identity.LifeStage`, `UserLifeStage` (with history) | ✅ |
| 3 | Role mode | 8, multi-select | `Identity.RoleMode`, `UserRoleMode` | ✅ |
| 4 | Domain | 22, hierarchical | `Content.LifeDomain` | ✅ |
| 5 | Event | 17 categories | `Timeline.Event`, `EventType` | ✅ |
| 6 | Goal | user-defined | `Growth.UserGoal`, `GoalTemplate` | ✅ |
| 7 | Condition | self-reported, never a diagnosis | targeting dimension | ✅ |
| 8 | State | 9 dimensions | `Intelligence.StateDimension` | ✅ |
| 9 | Country / language / season | — | `Identity.Country`, `Language` | ✅ |
| 10 | **Need** | 10 | — | ❌ **new** |
| 11 | **Emotion** | ~15 | column on a daily log | ⚠️ **promote** |
| 12 | **Relationship** | 8 kinds | `Health.ShareGrant` is the consent half | ⚠️ **half** |

### 2.1 Age bands — a signal, never a gate

Derived, never stored, so it cannot go stale: `under 11` · `11–13` · `14–17` ·
`18–21` · `22–29` · `30–39` · `40–49` · `50–59` · `60–69` · `70–79` · `80+`

A 45-year-old may be pregnant. A 60-year-old may be a new student. A
30-year-old may be perimenopausal. The band adjusts emphasis; `life_stage` and
`role_mode` decide what appears.

### 2.2 Needs — new, and the highest-value addition

`rest` · `company` · `calm` · `clarity` · `motivation` · `to talk` · `space` ·
`organising` · `enjoyment` · `care`

Two properties matter more than the list:

1. **A need is self-reported, never inferred.** WLOS may ask. It may not answer
   on her behalf.
2. **A need decays.** "I need space" is true this evening, not this month.

Cost: a reference table, a user-need table with expiry, and an eleventh row in
`TargetingDimension` — which was explicitly built so "a tenth dimension is a
seed row."

### 2.3 Response mode — how she wants to be answered

`Advice` · `Listen` · `Help me decide` · `Help me plan` · `Comfort` · `Space`

Maps onto `Coach.ToneProfile` and `Coach.ToneRule`, which already exist. This is
the difference between a system that responds *to* her and one that responds
*at* her.

### 2.4 Support language — what helps *her*

Not assumed. She selects: someone checking in · quiet time · encouraging words ·
practical help · talking · going outside · spiritual practice · being left alone ·
entertainment · sleep.

WLOS learns *her* answer rather than a universal claim about what women want.

---

## Part 3 — The International Context Model

### 3.1 Country is context, not identity

```
Country → possible relevance → her preference → actual experience
```

Two people in one country differ in religion, family structure, language, diet,
education, employment, privacy expectations and attitudes to healthcare.
**Country ≠ culture.** Country supplies context. She supplies what applies.

### 3.2 What country must configure — and what it must never

| Country configures | Country never configures |
|---|---|
| Language default, units, date format, calendar | What she believes |
| Timezone, seasons, holidays | What she needs |
| Emergency numbers and pathways | Her family structure |
| Healthcare system terminology | Her relationship status |
| Local services and referral routes | Her religion |
| Regulatory content rules | Her goals |

### 3.3 Schema validation — international readiness

**Already modelled, and better than expected:**

- `Identity.Language.IsRightToLeft` — **RTL is a first-class concept.** Arabic,
  Urdu and Hebrew are structurally supported today.
- `Content.ContentTranslation.IsMachineTranslated` — machine translation is
  **flagged**, so clinical content can be gated to human translation only. This
  is a significant piece of foresight.
- `Content.ContentReview` with `ReviewKind` and `Outcome` — clinical review
  workflow exists.
- `Content.ContentPublishSchedule` — scheduled publish and unpublish.
- `Content.LifeDomain.IsHealthSensitive` and `Timeline.EventType.IsHealthSensitive`
  — sensitivity is already a property of the taxonomy.

**Missing, and needed for international:**

`Identity.Country` holds only `IsoCode`, `Name`, `DefaultLanguageCode`,
`IsSupported`. It does not hold:

- region grouping
- emergency number or crisis pathway
- measurement system (metric/imperial)
- date and calendar convention
- healthcare-system model
- regulatory profile

That is the **Regional Safety Configuration** gap, and it is the difference
between "supports many countries" and "is safe in many countries".

**Also missing: content expiry.** `ContentReview` records that a review
happened; nothing records when guidance *stops being current*. Health
information ages, and an international platform serving clinical content without
a review-by date will eventually serve stale guidance in a market whose
guidelines moved.

### 3.4 Content model — global to local

```
GLOBAL concept → REGION → COUNTRY → LANGUAGE → USER
```

"Understanding menstrual cramps" is global. "When to seek care" is country-
specific, because it depends on the healthcare system. `TargetingDimension`
already supports `country` and `language`; `region` and `expiry` are the gaps.

---

## Part 4 — The Personalization Model

This is Part 0's gap, specified.

### 4.1 Four layers, in precedence order

```
1. SAFETY RULE      — non-negotiable, cannot be overridden
2. BOUNDARY         — "never show me this". Overrides everything below
3. PREFERENCE       — "I care about this". Raises relevance
4. INFERRED CONTEXT — season, age band, patterns. Lowest precedence
```

A boundary always beats an inference. If she says "no pregnancy content", no
signal, rule or model may reintroduce it.

### 4.2 What must be asked, never inferred

Pregnancy and intent · fertility · relationship status · religion · sexuality ·
whether she has children · mental-health status · any diagnosis.

### 4.3 Personalization controls — she can switch off the machinery

```
Personalization
───────────────
Age            ON
Location       ON
Cycle          OFF
Camera         OFF
Mood           ON
Relationships  OFF
AI learning    OFF
```

Each toggle removes that dimension from the context object that
`fn_TargetedItems` consumes. Switching one off must **degrade gracefully**, not
break the experience — the same discipline the pipeline already applies when a
stage returns `noResult`.

### 4.4 Why this is cheap to build and expensive to retrofit

The context object already exists — `fn_TargetedItems(@ContextJson)` takes it,
and every feature reads her through it. Preferences, boundaries and controls are
**filters on that object**, applied once. Nothing downstream changes.

Retrofitted later, after fifty features each read context directly, it becomes
fifty places to enforce a boundary, and the one that is missed is the one that
shows pregnancy content to a woman who asked never to see it again.

**Build it before the features, not after.**

---

## Part 5 — Market selection framework

The framework is agreed. **The research has not been done, and this document
will not pretend otherwise.**

I have not run market research, and I will not rank countries from memory —
market share, willingness to pay, competitive density and regulatory burden all
move, and a confident ranking built on recollection is worse than no ranking,
because it looks like evidence.

What can be stated now:

### 5.1 The framework

Score each candidate on: smartphone penetration among women · digital health
adoption · demonstrated demand · competitive density · localization burden ·
number of languages required · healthcare navigability · regulatory obligations ·
privacy regime · app-store constraints · payment feasibility · purchasing power ·
acquisition cost · search demand versus competition · natural retention ·
cultural fit · AI acceptance · partnership routes.

### 5.2 "Where it needs more" has six different answers

Highest demand · highest unmet need · highest willingness to pay · highest growth ·
lowest competition · best launch economics. **These point at different
countries.** The strategy must say which it optimises for before any country is
named.

### 5.3 The decision this framework serves

Not "which country is best" but: **what global architecture supports
country-by-country adaptation, and which market is entered first on evidence.**
The first is an engineering question answered in Part 3. The second needs
research.

### 5.4 What I recommend on minors

Design the data model to accommodate younger users. **Do not launch them first.**

Age 8 with camera, emotional journaling, AI and parental sharing engages COPPA,
GDPR Article 8, Google Play Families, Apple's Kids frameworks and the UK Age
Appropriate Design Code simultaneously — and the regulatory position for minors
and AI companions is moving. That combination is a second product with a
different review process, not a life stage.

> **Launch age is an unresolved hypothesis. 16+ and 18+ both remain candidates.
> No launch-age decision has been made.**
>
> This section originally recommended 16+. `WLOS_MARKET_RESEARCH.md` later
> argued 18+ on the EU KIDS Act. **Neither is a decision** — both are
> recommendations awaiting legal review per jurisdiction, and a recommendation
> must not become a decision by repetition.

What both candidates share, and what is not in doubt: **design the data model to
accommodate younger users; do not launch them first.** The 11–13 and 14–17 bands
stay in the human model, unshipped, either way.

The stronger question is architectural rather than legal: given that minors
require non-personalised recommendation and no streaks, **is a non-personalised,
streak-free WLOS still WLOS?** If it is not, minors are a second product and the
age number is a consequence, not the decision.

---

## Part 6 — The four foundational decisions

These settle together, not in sequence:

| Decision | Question | Blocks |
|---|---|---|
| **Who is it for** | Minimum age at launch | youngest bands, camera, parent sharing |
| **Where** | Launch market, on evidence | content language, regulatory profile, safety config |
| **What data** | What may be inferred, stored, shared | consent model, AI scope, camera |
| **How personal** | Preference, boundary, controls | **everything — it is the filter all features read** |

**Design hypothesis, not a product decision:** *if* the thesis survives Phase A,
preference, boundary and personalization control is currently expected to be a
**foundational cross-cutting requirement** rather than a feature — it is cheap
now and expensive later, Part 0 shows there is nothing there at all, and the
candidate map found it required by all six candidate experiences with no
exceptions.

**That is an architectural argument, not authorisation.** It does not mean we
have decided to build personalization first. Nothing is built before the Phase A
Findings Report.

---

## Part 7 — Engineering gap, measured

| Required | Exists | Work |
|---|---|---|
| 22 life domains, hierarchical | ✅ | none |
| 12 life stages with history | ✅ | none |
| 8 role modes, multi-select | ✅ | none |
| 10 targeting dimensions | ✅ | none |
| RTL language support | ✅ | none |
| Machine-translation flag | ✅ | none |
| Clinical review workflow | ✅ | none |
| Signal graph and rules engine | ✅ | none |
| Explainability contract | ✅ | none |
| **Need dimension** | ❌ | small |
| **Response mode** | ⚠️ partial (`Coach.ToneProfile`) | small |
| **Preference + boundary + controls** | ❌ | **medium — do first** |
| **Emotion as a dimension** | ⚠️ column | medium |
| **Country safety configuration** | ❌ | medium |
| **Content expiry / review-by** | ❌ | small |
| **Account-to-account relationships** | ⚠️ consent half exists | **large — §1.7 first** |
| **Content for 11 of 12 life stages** | ❌ | **the actual project** |

Every architectural row is small or medium. The last row is the product.

---

## Part 8 — What happens next

> **Superseded, 23 September 2026.** This section previously listed an
> engineering sequence — settle personalization, fix `ContentTargetingRule`, add
> Need and response mode, then content. **That sequence is suspended.** It
> assumed the product hypothesis had survived. It has not been tested.

The governing sequence is:

```
LOCK PROJECT STATE
        |
Recruit C4 first
        |
Phase A - 14 interviews
        |
Lock all 14 rows
        |
Phase A Findings Report
        |
   thesis survives?
        |
Design first WLOS experience
        |
Prototype and test "the join"
        |
Validate perceived value
        |
   THEN architecture gaps
        |
   THEN market and country
        |
   THEN implementation
```

**Nothing in Parts 2–5 is built before the Phase A Findings Report exists.**
Architecture cannot tell us whether women want the product. Implementing
preferences, Need, response modes, targeting fixes or content now would quietly
assume the answer.

> **Correction, 23 September 2026.** This paragraph previously described a
> `ContentTargetingRule` deployment defect. **That finding is retracted.** The
> table is intentionally superseded by `Rules.Rule` during the ordered
> deployment: script 34 creates it, script 45 migrates its rows and drops it,
> script 46 rewrites the functions onto `Rules.Rule`, and `fn_TargetedItems` was
> verified reading `Rules.Rule`. The investigation recreated the superseded
> table manually in the deployed environment; **that orphan is not evidence of a
> clean-deploy defect.** See `PROJECT_STATE.md` §6.4. Do not reopen it.

Everything in this constitution remains binding as **policy**. None of it is
authorisation to build.
