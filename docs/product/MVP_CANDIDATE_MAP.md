# WLOS — MVP Candidate Map

**Date:** 23 September 2026
**Status:** **CANDIDATE MAP. NOTHING HERE IS APPROVED.**
**Sources:** `WLOS_CONSTITUTION.md` · `WLOS_LIFE_MODEL.md` ·
`WLOS_HUMAN_MODEL_REVIEW.md` · `WLOS_MARKET_RESEARCH_II.md` ·
`PROJECT_STATE.md` · `WLOS_INTERVIEW_PROTOCOL.md`
**Invents nothing.** Every candidate below is already named in one of those
documents. No new market claim, no new user claim, no new capability claim is
introduced here.

---

## 0. What this document is, and what it is not

`PROJECT_STATE.md` §9.0 lists the things that are **not authorised**, and the
Today screen, Need implementation, response modes, preference and boundary
tables and AI implementation are all on that list. §9.1 says the one next action
is **recruit C4**. Nothing in this document changes that.

**This is a map, not a plan.**

| This document does | This document does not |
|---|---|
| Lay out six first-experience candidates already named in the research | Choose one |
| Record what each would require, cost and risk | Rank them |
| Record what evidence would support or kill each | Recommend any |
| Make the candidates comparable *in advance* of evidence | Authorise any build |

**Why it exists now.** Phase A is 14 interviews. When the Findings Report lands,
item 13 is a decision — *Phase B · narrow · or change the product*. If the
thesis survives, the team should not then spend two weeks re-deriving what the
options were. The options are written down here, cold, before the evidence
arrives, so that the evidence cannot be bent to fit a design that was already
half-built.

**Freshness warning.** This map is written against a hypothesis that has not
been tested. The Phase A Findings Report supersedes it. If the Findings Report
contradicts a candidate, the Findings Report wins and the candidate is struck,
not adjusted.

### 0.1 The binding constraints, restated

Every candidate below is subject to these, without exception. They are not
per-candidate trade-offs; they are the floor.

1. **Never inferred** (`WLOS_CONSTITUTION.md` §1.5): pregnancy or intent to
   become pregnant · fertility status · sexual activity, orientation or partners
   · marital or relationship status · religion or observance · whether she has,
   wants or has lost children · mental-health diagnoses · any medical diagnosis ·
   **emotion from an image of her face**. Each may be *stated*. None may be
   *deduced*.
2. **Retention is earned, never engineered** (§1.9). No streaks that make absence
   feel like failure, no guilt, no loss-framing, no manufactured urgency, no
   notifications unrelated to what she is doing, nothing that rewards frequency
   for its own sake, nothing that fosters emotional dependency. Any candidate
   that needs daily return *to function* is in tension with this clause and the
   tension must be stated, not designed around.
3. **UNKNOWN is a valid state.** `Intelligence.StateDimension.UnknownText` gives
   every one of the nine dimensions its own user-facing sentence for having no
   answer — *"Not enough logged to tell yet."* A candidate that cannot behave
   well while knowing nothing is a candidate that fails on day one, which is
   where 77% of users are lost (`WLOS_MARKET_RESEARCH_II.md` §6).
4. **Boundary beats inference** (§4.1). Precedence is SAFETY RULE → BOUNDARY →
   PREFERENCE → INFERRED CONTEXT. Nothing downstream may reintroduce what she
   has excluded.
5. **No automatic sharing, ever** (§1.7). Revocation is silent; nothing reveals
   that private content exists; sharing is never a default or an onboarding step.

### 0.2 The primitive inventory these candidates draw on

**Existing, reusable without modification** (`WLOS_HUMAN_MODEL_REVIEW.md` Q17):

| Primitive | What it gives a candidate |
|---|---|
| `Content.LifeDomain` | 22 domains, hierarchical (`pregnancy` is a child of `health`) |
| `Identity.LifeStage` / `UserLifeStage` | 12 stages, with history and `Source` (declared vs derived) |
| `Identity.RoleMode` / `UserRoleMode` | 8 role modes, multi-select |
| `Identity.Profile` | display name, terms, `DateOfBirth` (age band derived, never stored), timezone, `AvatarMediaId` (no upload path behind it) |
| `Identity.Country` / `Language` | ISO code, default language, `IsRightToLeft` |
| `Content.TargetingDimension` + `ContentTargetingRule` + `fn_TargetedItems(@ContextJson)` | 10 dimensions; 3 operators (`in`, `not_in`, `between`); OR within a dimension, AND across. **An item with no rules matches everyone. `not_in` cannot exclude an unknown.** |
| `Knowledge.Signal` / `SignalRelation` / `SignalRule` | 12 signals; `RelationKind` (`commonly_precedes`, `commonly_co_occurs` — deliberately non-causal), `Strength` (confidence), `SourceNote` (provenance) |
| `Intelligence.StateDimension` / `StateRule` / `UserStateSnapshot` | 9 dimensions — energy, focus, consistency, wellness, balance, routine, momentum, load, risk — each with `BaselineScore` and `UnknownText` |
| `Timeline.Event` / `EventType` | 17 categories, `IsHealthSensitive` |
| `Growth.UserGoal` / `GoalTemplate` | user-defined goals |
| `Coach.ToneProfile` / `ToneRule` | 4 tones — `steady`, `gentle`, `encouraging`, `brief` — with `Pattern`, `Weight`, `IsDefault` |
| `Rules.Rule` / `TargetScope`, `Recommend.*`, `Predict.*` | the care layer |
| 24-stage pipeline | explainability contract on every decision: `reason`, `evidence`, `confidence`, `source` |
| `LifeOsRepository` → `LifeOsContextRow` → `ResolveLifeOsHandler` | **one assembly point** for user context |
| `AI.SafetyEvent` | `Domain`, `Decision`, `RefusalCategory`, `ClinicalScore`, `CrisisScore`, `PromptVersion`, `ModelId`, `CorrelationId`. `aiContextResolution` is a deliberate `UnbuiltStage`: *"Guardrails ship before generation."* |
| `Audit.AuditLog` | append-only; `ActorUserId`, `ActorKind`, `BeforeJson`, `AfterJson`. Refusals are audited, not just successes |
| `Health.ShareGrant` | `ScopesJson`, `ExpiresUtc`, `RevokedUtc`, `LastViewedUtc`, `ViewCount` — the consent primitive only |
| `Content.ContentTranslation` / `ContentReview` / `ContentPublishSchedule` | `IsMachineTranslated` flag, clinical review workflow, scheduled publish |

**Missing — the six** (`PROJECT_STATE.md` §5, `WLOS_HUMAN_MODEL_REVIEW.md` Q18),
referenced throughout as **M1–M6**:

| # | Missing primitive | Cost | Note from the research |
|---|---|---|---|
| **M1** | **Need** | small | reference table + user table with expiry + one seed row in `TargetingDimension` |
| **M2** | **Intent / response mode** | small | tone exists; intent does not. `gentle`/`brief` map onto *Comfort*/*Space*; nothing maps onto *Listen*, *Help me decide*, *Help me plan* |
| **M3** | **Preference + boundary + controls** | **medium — do first** | nothing exists; one assembly point to apply it |
| **M4** | **Responsibility load** | medium | self-declared only; no dependents model anywhere |
| **M5** | **Country safety configuration** | medium | `Identity.Country` has 4 columns; no emergency pathway, healthcare model, units, calendar or regulatory profile |
| **M6** | **Support network** | **large** | account-to-account; §1.7 safety rules first |

**The context dimensions** a candidate may declare a requirement on
(`WLOS_HUMAN_MODEL_REVIEW.md` Q20):

```
EXISTS TODAY                              NEW (M1–M3)
──────────────────────────────────        ──────────────────────
life_stage    country / language          need         (self-reported, decays)
role_mode     season                      intent       (how she wants answering)
age (derived) goal                        boundary     (never show me X)
module        condition                   preference   (I care about X)
week (pregnancy only)                     personalization controls
state (9 dimensions)
```

### 0.3 How to read each candidate

`Required context` names dimensions from the list above.
`Minimum data` is the honest answer to *"how long before this can say anything
that is not a placeholder?"*
`Longitudinal dependency` is **none / weak / strong** and is the axis that the
closing question in §8 cuts along.

---

## 1. Candidate A — "What do you need today?" (the needs entry loop)

> ### ⚠️ HYPOTHESIS — NOT APPROVED

**Named in:** `WLOS_LIFE_MODEL.md` §2.1 and §5.3 (*"This is where I would
start"*) · `WLOS_CONSTITUTION.md` §2.2 · `WLOS_MARKET_RESEARCH_II.md` §6, Loop 1
· `PROJECT_STATE.md` §8 (*"only loop that works on day one with no data"* —
recorded there as **hypothesis, not decided**).

### User situation

She opens WLOS. It may be her first session or her hundredth. The system may
know nothing about her beyond a country and a date of birth. She has not logged
sleep, has not connected a calendar, and has not written anything.

### Trigger

She opens the app. The question is the surface, not a notification — a push
notification asking her what she needs would be *"notifications unrelated to what
she is actually doing"* under §1.9 unless it is tied to something she has
already set up.

### User action

She picks one of ten, each phrased as she would say it (`WLOS_LIFE_MODEL.md`
§5.3):

`rest` · `company` · `calm` · `clarity` · `motivation` · `to talk` · `space` ·
`organising` · `enjoyment` · `care`

Or she picks nothing, which must be a first-class outcome and not a nag.

### WLOS response

The selected need enters the context object as an eleventh targeting dimension
and `fn_TargetedItems` returns differently. What comes back is content, tone and
ordering that changed *because she said so*.

The two properties that define this candidate (`WLOS_LIFE_MODEL.md` §5.3):

1. **A need is self-reported, never inferred.** WLOS may offer the question. It
   may not answer it on her behalf.
2. **A need decays.** `WLOS_CONSTITUTION.md` §1.6: needs live **hours**. *"I need
   space"* is true this evening, not this month.

`need = space` is the hard case and the test of whether the candidate is honest:
the correct response to *space* is **less**, not a differently-worded more.

### Required context

`need` (**M1**) — and, strictly, nothing else. Optionally reads `life_stage`,
`role_mode`, `country`, `language` where those already exist. Degrades to
universal content, which `fn_TargetedItems` already serves for free: *an item
with no rules matches everyone*.

### Expected value to her

She is asked rather than assumed at. `WLOS_CONSTITUTION.md` states the whole
product position in one line — *"Demographics produce possible relevance. Only
she produces personalization."* This is the cheapest place that line becomes
visible.

### Minimum data required before it can say anything useful

**One tap, and content to serve.** This is the only candidate here with no data
warm-up.

**But the real floor is editorial, not technical.** `PROJECT_STATE.md` §4:
22 domains, 10 dimensions, 12 life stages, 24 pipeline stages, 68 endpoints —
and **6 content items**. A needs loop that routes ten needs into six FAQ entries
is a survey with extra steps. *"The constraint is editorial, not technical"*
applies to this candidate more sharply than to any other, because it is the one
whose entire value is what comes back.

### Privacy risk

**Lowest of the six, and not zero.**

- The ten values are innocuous individually. A **sequence** of them is not:
  `to talk` → `to talk` → `company` → `space`, logged and retained, is an
  emotional record she did not agree to keep. §1.6's *hours* lifetime is what
  keeps this a state and not a dossier, and it must be enforced by expiry, not
  by policy.
- `care` and `to talk` sit close to `IsHealthSensitive` territory under
  `Content.LifeDomain`.
- **The §1.5 trap:** repeated `care` must never be allowed to imply a health
  event, and no need value may ever be chained into an inference about
  pregnancy, diagnosis or mental-health status.

### Dependency on longitudinal memory

**None.** It is the defining property of this candidate. It also means this
candidate proves nothing about the thesis in `PROJECT_STATE.md` §8 — that
longitudinal context beats a sharp single job at day 31.

### Platform primitives consumed

`Content.TargetingDimension` + `ContentTargetingRule` + `fn_TargetedItems`
(eleventh dimension is a seed row) · `Content.LifeDomain` · `Coach.ToneProfile`
(partial — `gentle` and `brief` exist) · `Audit.AuditLog` · 24-stage pipeline.

### Missing primitives required

- **M1 Need** — required. The whole candidate.
- **M3 Preference + boundary + controls** — required if any need selection is
  retained beyond its expiry window, or feeds anything she can switch off.
- M2 Intent — not required, but Candidate D is its natural pair.

### What experiment would validate it

A prototype test, not a survey. `PROJECT_STATE.md` §9.0 puts the Today screen on
the do-not-touch list; this is what would be tested **after** item 13 of the
Findings Report, if the thesis survives.

- Show the question and **two different result sets** for two different needs to
  the same participant.
- Measure whether she can tell they are different, and whether the difference
  matches what she asked for.
- The `space` case tested explicitly: does WLOS give her less?
- Day-31 read: does selection frequency hold without any prompting mechanic?
  Category D30 median is 5%, strong is 8–12% (`WLOS_MARKET_RESEARCH_II.md` §6).

### What would falsify it

- She picks the same value every time, or stops picking within a week — it is a
  toll gate, not a loop.
- **She cannot tell that anything changed.** `WLOS_MARKET_RESEARCH_II.md` §6
  names this exactly: *"Needs to visibly change what she sees, or it is a
  survey."*
- She says the ten words are not how she would describe it — the vocabulary is
  wrong, which is a content finding, not an architecture finding.
- She reports the daily question as pressure, which puts it in breach of §1.9
  regardless of its retention numbers.

---

## 2. Candidate B — "Noticing" (a change from her own baseline)

> ### ⚠️ HYPOTHESIS — NOT APPROVED

**Named in:** `WLOS_MARKET_RESEARCH_II.md` §6, Loop 2 · `WLOS_CONSTITUTION.md`
§1.4 (*"Change from **her own** baseline"* is on the permitted-inference list) ·
`WLOS_LIFE_MODEL.md` §3.3.

### User situation

She has been using WLOS long enough for `Intelligence.UserStateSnapshot` to hold
history — some combination of logged sleep, mood, activity, cycle or events. She
is not looking for anything. She has not asked a question.

### Trigger

**System-initiated.** A `StateRule` fires because a dimension has moved from her
`BaselineScore`. This is the only candidate in this map where WLOS speaks first,
and that is its whole risk profile.

### User action

She reads it. She may confirm, correct, dismiss, or set a boundary against that
class of observation. Correction must be as easy as acceptance —
`WLOS_CONSTITUTION.md` §1.3: *"She can see what WLOS believes about her, in her
own words, and correct it."*

### WLOS response

A statement about herself measured against herself, in the non-causal vocabulary
`Knowledge.SignalRelation` already enforces — `commonly_precedes`,
`commonly_co_occurs`, never *caused*.

The line the research draws, and it is precise
(`WLOS_MARKET_RESEARCH_II.md` §6): *"your sleep has been below your range for
four days"* — **not** a diagnosis, **not** a population comparison, **not** an
emotion label.

`WLOS_LIFE_MODEL.md` §3.3 states the defensible and indefensible sides:
change from a personal baseline is a measurement against herself and makes no
population claim; emotion inference from facial expression rests on a contested
premise, performs unevenly across skin tones, ages and cultures, and is
restricted by the EU AI Act in several contexts. **Ship baseline-change only.
Never emit an emotion label from an image.**

### Required context

`state` (9 dimensions, with `BaselineScore` and `UnknownText`) · `life_stage` ·
`season` · whatever she has logged. Reads `boundary` and `personalization
controls` before it is permitted to speak at all.

### Expected value to her

The one thing no other app on her phone does.
`WLOS_MARKET_RESEARCH_II.md` §5: *"Her phone — sleep, steps, calendar already
there. **Nothing joins them.** Apple Health has the data and draws no
conclusion."* And §3: *"Burnout is diagnosed by interaction, not by any single
metric. A sleep app sees sleep. A calendar sees load. Neither sees the loop."*

This is the candidate that most directly tests the only defensible claim WLOS
has — **the join**.

### Minimum data required before it can say anything useful

**High, and it is the candidate's central problem.**
`WLOS_MARKET_RESEARCH_II.md` §6 states the risk plainly: *"Requires data density
before it can say anything."*

A baseline needs enough observations to distinguish a change from noise. Until
then the honest output is the one already built:
`StateDimension.UnknownText` — *"Not enough logged to tell yet."* ·
*"Needs a few days before this means anything."* · *"Nothing to flag."*

**So this candidate is silent exactly where the funnel is worst** — day one,
where 77% of users are lost. A version of it that fills the silence with
something less rigorous is no longer this candidate.

### Privacy risk

**High, and of a different kind to the others.**

- It is WLOS **asserting something about her**, unprompted. A wrong assertion
  about her own body or mood costs more trust than a wrong content
  recommendation.
- **§1.5 is live here.** A noticing engine that fires on cycle + mood + sleep
  sits one careless sentence away from implying pregnancy, a diagnosis or a
  mental-health state. The permitted output is a change from her baseline. The
  prohibited output is what that change *means*.
- **Notification surface.** If noticing arrives as a push, §1.9 applies —
  notifications must relate to what she is actually doing, and timing-aligned
  nudges beat volume (`WLOS_MARKET_RESEARCH_II.md` §6).
- **Observation in a shared context.** `WLOS_MARKET_RESEARCH_II.md` §1.1: in
  LMIC markets the woman may share a handset; the smartphone ownership gender
  gap is 13% and 810M women in LMICs are not using mobile internet. A lock-screen
  line about her sleep or cycle is visible to whoever holds the phone. §1.7's
  rule — *nothing reveals that private content exists* — has a direct
  notification-design consequence here.
- Camera is **not** a route to this. `WLOS_HUMAN_MODEL_REVIEW.md` Q14: the
  camera subsystem does not exist — no media dependency, no permission, no
  capture path, no baseline storage. §1.6: camera frames are **never stored**,
  derived baseline deltas only. Writing that policy before the subsystem exists
  is the right order and this candidate must not reverse it.

### Dependency on longitudinal memory

**Strong.** Without history there is no baseline, and without a baseline this
candidate has nothing to say. It is the purest test of the Memory value and
Trust dimensions in the Phase A scoring.

### Platform primitives consumed

`Intelligence.StateDimension` / `StateRule` / `UserStateSnapshot` (including
`BaselineScore` and `UnknownText`) · `Knowledge.Signal` / `SignalRelation`
(`RelationKind`, `Strength`, `SourceNote`) / `SignalRule` · `Timeline.Event` /
`EventType` (`IsHealthSensitive`) · 24-stage pipeline explainability contract ·
`Rules.Rule` · `Audit.AuditLog` · `AI.SafetyEvent` if any generated language is
involved.

### Missing primitives required

- **M3 Preference + boundary + controls** — **hard requirement, not optional.**
  This is the candidate §4.3's toggles were described for: *Cycle OFF*,
  *Mood ON*, *Camera OFF*. A noticing engine with no way to say *stop noticing
  that* is the exact asymmetry Part 0 of the constitution exists to correct.
- **M5 Country safety configuration** — required before any observation can
  approach a *"you may want to seek care"* framing, because that depends on the
  healthcare system and emergency pathway, and `Identity.Country` holds four
  columns.
- M1 Need — not required, but `need = space` must suppress noticing.
- M4 Responsibility load — would sharpen it. `load` today derives from workload
  signals (`long_work`), not from dependents, so the 38-year-old with two
  children and an elderly parent is indistinguishable from the 38-year-old
  living alone, if both work.

### What experiment would validate it

- Retrospective: reconstruct a participant's last bad week from data she already
  has on her phone, and show her what a noticing statement would have said at
  day 2. Ask whether it would have told her something she did not know.
- Wizard-of-Oz over real personal data, so the data density problem is not
  simulated away.
- Measure **correction rate** as a first-class metric, not an error rate. High
  correction may mean it is engaging her, or may mean it is wrong; both matter.

### What would falsify it

- **She already knew.** If noticing only ever tells her what she could see
  herself, the join is not perceptible and
  `WLOS_MARKET_RESEARCH_II.md` §5 applies: *"If the join is not perceptibly
  better than the parts, WLOS is a worse version of six apps she already has."*
- Time-to-first-useful-statement exceeds the point at which she has already
  churned. Category D30 median is 5%.
- She experiences it as surveillance rather than attention. Phase A kill
  condition: **Trust ≤ 1 in ≥ 7 of 14 kills it independently of everything
  else.**
- She describes her bad week as **one problem**, not a loop — which is the
  thesis-level kill condition in `WLOS_INTERVIEW_PROTOCOL.md` §1, claim 2.

---

## 3. Candidate C — "Protect tomorrow" (acting on load rather than reporting it)

> ### ⚠️ HYPOTHESIS — NOT APPROVED

**Named in:** `WLOS_MARKET_RESEARCH_II.md` §6, Loop 3 (*"make tomorrow
lighter"*) · `WLOS_CONSTITUTION.md` §1.4 (*"Workload from a calendar she
connected"* is permitted inference) · `WLOS_LIFE_MODEL.md` §4 (*"Cycle +
workload + sleep intersection — needs her context: the whole point. **Build**"*).

### User situation

Tomorrow is heavy and she has not noticed yet, or has noticed and has not acted.
She has connected a calendar, or has told WLOS what is coming.

### Trigger

Either — and which one it is changes the candidate materially:

- **She asks.** *"Make tomorrow lighter."* Low risk, low reach.
- **WLOS offers**, on the evening before a day whose load is visible. Higher
  value, and it inherits every notification constraint in Candidate B.

### User action

She accepts, edits, or declines a small concrete change to tomorrow. Declining
must be free of consequence and must not be recorded as a failure — §1.9 forbids
anything that makes absence or non-compliance feel like failure.

### WLOS response

**An action, not a report.** This is what separates this candidate from
Candidate B: `WLOS_MARKET_RESEARCH_II.md` §6 describes it as *"Acts rather than
reports."*

`long_work → high_stress` and `long_work → low_selfcare` are already seeded in
`Knowledge.SignalRelation`, so the chain this candidate acts on exists in the
schema today.

**The boundary test applies here harder than anywhere else**
(`WLOS_CONSTITUTION.md` §1.2, `WLOS_LIFE_MODEL.md` §4): *does this need her
context to be better than a standalone app already on her phone?* Protecting
tomorrow using her load and her cycle and her sleep passes. Anything that drifts
toward owning her calendar, her tasks or her shopping fails — `finance`,
`shopping` and `travel` are **context WLOS may read, never features WLOS owns.**

### Required context

`state.load` · `state.risk` · calendar-derived workload · `role_mode` ·
`life_stage` · `season` · `goal`. Optionally `need` and `intent`.
Genuinely wants `responsibility load` (**M4**), which does not exist.

### Expected value to her

It is the only candidate that changes an outcome rather than her understanding
of one. It maps directly onto the candidate job statement in
`WLOS_MARKET_RESEARCH_II.md` §3 — *"Help me notice what is actually going on
with me, before it becomes the week I fall apart"* — and onto the burnout
evidence: 74% Gen Z burnout, 96% of women reporting high or extreme pressure,
and burned-out women working longer hours (25% vs 7%).

It also lands on the part of the problem that is *unspeakable in its own
context*: women are less comfortable than men raising stress with a manager,
which is an argument for a private system that understands it.

### Minimum data required before it can say anything useful

**Highest of the six.**
`WLOS_MARKET_RESEARCH_II.md` §6: *"Requires calendar/context integration."*

It needs (a) a connected calendar or equivalent declared load, and (b) enough
baseline to know what *heavy* means **for her**. A universal threshold is a
population claim, which is exactly what §1.4 does not permit —
the permitted inference is change from **her own** baseline.

### Privacy risk

**Highest of the six.**

- **A calendar is the most revealing thing on her phone.** Event titles leak
  religion (observance), relationship status, medical appointments, job
  interviews and childcare — five items on the §1.5 never-infer list, present as
  plain text. A calendar integration must be treated as a source that must be
  *read without being mined*, and §4.2's list must be enforced against parsed
  titles, not just against explicit questions.
- **B2B2C makes this worse, not better.**
  `WLOS_MARKET_RESEARCH_II.md` §1.4 records B2B2C as the strongest commercial
  signal found (Maven: 2,000+ companies, 6.7M lives, 175 countries; 69% of large
  US employers). `PROJECT_STATE.md` §8 records the counterweight in the same
  breath: *"an employer-funded product raises a trust question that may matter
  more than acquisition cost."* A feature that reads her work calendar, in a
  product her employer pays for, is where that question is sharpest. §1.2 is
  unambiguous that WLOS is **not** *"a monitoring system for families or
  partners"* — an employer is not on that list only because it was not
  contemplated.
- **Shared-device and shared-calendar contexts** inherit everything in
  Candidate B's privacy section.

### Dependency on longitudinal memory

**Strong.** Both for the personal load baseline and for knowing which protective
actions she previously accepted or declined.

### Platform primitives consumed

`Intelligence.StateDimension` (`load`, `risk`, `balance`, `routine`) ·
`Knowledge.SignalRelation` (`long_work → high_stress`, `long_work →
low_selfcare`) · `Rules.Rule` / `TargetScope` · `Recommend.*` · `Predict.*` ·
`Timeline.Event` / `EventType` · `Coach.ToneProfile` · `Audit.AuditLog`.

**Note a gap:** there is no calendar integration anywhere in the platform today,
and `WLOS_HUMAN_MODEL_REVIEW.md` Q15 records that `WLOS_App` consumes **3 of 68
endpoints, all GET**. This candidate is the furthest from what exists.

### Missing primitives required

- **M3 Preference + boundary + controls** — required, including a control for
  calendar reading specifically.
- **M4 Responsibility load** — required for this to mean anything for a
  caregiver. `Identity.RoleMode` includes `caregiver` and `homemaker`, but
  *"a role is a label, not a load."*
- **M5 Country safety configuration** — required if protection ever touches
  care-seeking or emergency pathways.
- M1 Need, M2 Intent — would shape it; `need = space` and `intent = Space` must
  both suppress it.

### What experiment would validate it

- Concierge test: a human reads a consenting participant's real calendar for two
  weeks and sends one protective suggestion the evening before a heavy day.
  No code. This is the cheapest way to test the highest-cost candidate.
- Measure **acted-on rate**, not open rate.
- Separately and explicitly: ask whether she would grant calendar access at all,
  and then ask again under the condition *"your employer pays for this."* The
  delta between those two answers is the finding.

### What would falsify it

- She will not connect a calendar. **This kills the candidate outright** and is
  the single most likely failure mode.
- She connects it but will not act on the suggestions — the constraint on her
  day is not hers to move, which makes the suggestion a reminder of
  powerlessness rather than help.
- Suggestions are generic enough that a calendar app's own features match them —
  boundary test failed.
- The employer-funded framing collapses trust (`Employer trust` is a descriptive
  dimension in the Phase A coding frame, 0–2).

---

## 4. Candidate D — Response-mode selection (Advice / Listen / Help me decide / Comfort / Space)

> ### ⚠️ HYPOTHESIS — NOT APPROVED

**Named in:** `WLOS_LIFE_MODEL.md` §5.4 (*"the second-best idea in the vision"*)
· `WLOS_CONSTITUTION.md` §2.3 · `WLOS_HUMAN_MODEL_REVIEW.md` Q5.

**Note on the list.** The research documents name **six** modes:
`Advice · Listen · Help me decide · Help me plan · Comfort · Space`. This
candidate is scoped to the five in the task framing; *Help me plan* is recorded
here as a sixth that exists in the source and has not been excluded by any
evidence.

### User situation

She has something to bring — a question, a bad day, a decision — and the way she
wants it received is not the same every time. `WLOS_LIFE_MODEL.md` §5.4 quotes
the vision directly: *"WLOS should understand I don't want advice."*

### Trigger

She initiates. Response mode is a property of **an exchange**, not a profile
setting — the same woman wants *Advice* on Tuesday and *Space* on Thursday.

### User action

She selects a mode, before or during the exchange, and can change it mid-way.
Changing it mid-way is the interesting case: it is the moment WLOS is told it
got the register wrong.

### WLOS response

The response changes in **kind**, not only in wording. This is the distinction
`WLOS_HUMAN_MODEL_REVIEW.md` Q5 draws, and it determines the real cost:

| Mode | Maps onto existing? | Why |
|---|---|---|
| **Comfort** | ⚠️ partially — `ToneProfile.gentle` | tone-only change |
| **Space** | ⚠️ partially — `ToneProfile.brief` | tone-only change, plus doing less |
| **Advice** | ⚠️ closest to `steady`/`encouraging` | tone-only change |
| **Listen** | ❌ nothing | changes **what the system does** — it must not answer |
| **Help me decide** | ❌ nothing | changes **what the system does** — it must structure, not conclude |

*"Tone exists; intent does not."* Two of the five modes are a weight on an
existing `ToneRule`. Two are a different behaviour.

**`Listen` is the mode that tests whether WLOS means it.** A system that cannot
receive something without responding to it is a system that responds *at* her —
the exact failure `WLOS_LIFE_MODEL.md` §5.4 says this dimension exists to
prevent. It is also the mode most likely to be quietly dropped under schedule
pressure, because it is the one that produces no visible output.

### Required context

`intent` (**M2**) — and nothing else strictly required. Reads `need`,
`life_stage`, `role_mode` where present.

### Expected value to her

*"The difference between a system that responds to her and one that responds at
her"* (`WLOS_CONSTITUTION.md` §2.3).

It is also a trust instrument. `WLOS_MARKET_RESEARCH_II.md` §0.2: trust in a
chatbot **without** professional oversight is **3–6%**; **with** oversight,
**49–55%**. A system that can be told *do not advise me* is positioned on the
right side of that 10-to-1 gap by construction, because the refusal to advise is
hers to command rather than a limitation she discovers.

### Minimum data required before it can say anything useful

**One selection**, like Candidate A. No history required.

**But the same editorial floor applies, and harder.** Five modes over six
content items is five ways to receive the same thing. And `Listen` and
`Help me decide` have no implementation behind them at all — `Coach.ToneRule`
cannot express *do not answer*.

### Privacy risk

**Low as a standalone selection. Non-trivial as an accumulated record.**

- Mode choice over time is an emotional pattern. `Comfort` selected repeatedly
  is a signal that §1.5 forbids turning into a mental-health inference, and
  §1.6 caps emotional state at *days, as a data point; never a label that
  sticks*.
- **The retention trap:** a system that learns she usually wants *Comfort* and
  starts pre-selecting it has begun to decide for her, which inverts the
  candidate. Pre-selection is the failure mode to watch for, not a refinement.
- `AI.SafetyEvent` already separates `Decision`, `RefusalCategory`,
  `PromptVersion` and `ModelId`, so mode-conditioned behaviour is recordable and
  reviewable if generation is ever involved.

### Dependency on longitudinal memory

**None to weak.** None as specified — the mode is per-exchange. **Weak** only if
a default is remembered, and remembering a default is precisely where the
privacy risk above begins.

### Platform primitives consumed

`Coach.ToneProfile` (4 tones: `steady`, `gentle`, `encouraging`, `brief`) and
`Coach.ToneRule` (`Pattern`, `Weight`, `IsDefault`) · `Content.TargetingDimension`
(intent as a seed row) · `AI.SafetyEvent` if generation is involved ·
`Audit.AuditLog`.

### Missing primitives required

- **M2 Intent / response mode** — required. Half exists as tone; the half that
  changes behaviour does not.
- **M3 Preference + boundary + controls** — required if a default mode is ever
  stored or learned.
- M1 Need — natural pair, not a dependency. `need = space` and `intent = Space`
  are different statements and should not be collapsed into one.

### What experiment would validate it

- Same scenario, same participant, two modes. Does she perceive a difference in
  **kind**, or only in wording?
- Test `Listen` specifically, because it is the mode that is hardest to build and
  easiest to fake. Does a WLOS that does not answer feel like restraint or like
  a broken feature?
- Test whether she will use the control at all, or whether choosing how to be
  answered is itself friction she does not want.

### What would falsify it

- She does not want to choose — she wants WLOS to know, which converts this into
  an inference problem and collides with §1.5 and the retention trap above.
- The modes are indistinguishable in practice, making this a tone weight and not
  a dimension.
- `Listen` is experienced as the app not working.
- The five words do not match how she thinks about being answered, which is a
  vocabulary finding rather than an architecture finding.

---

## 5. Candidate E — "Why am I seeing this?" (provenance made visible)

> ### ⚠️ HYPOTHESIS — NOT APPROVED

**Named in:** `WLOS_CONSTITUTION.md` §1.3 (*"She can see what WLOS believes
about her, in her own words, and correct it"*) · `WLOS_HUMAN_MODEL_REVIEW.md`
headline and Q4 · `WLOS_MARKET_RESEARCH_II.md` §0.2 and §5 (*"No memory of her
life, **no provenance**"* as the gap against ChatGPT) · `PROJECT_STATE.md` §4.

### User situation

WLOS has shown her something — a piece of content, an observation, a suggestion
— and she wants to know why. Often because it is **wrong**, or because it is
close enough to be unsettling.

### Trigger

She taps through from any surfaced item. This candidate is a **modifier on the
other five**, not a destination, and that is the most important structural fact
about it.

### User action

She reads the reason, and then — the part that makes it more than a disclosure —
**she corrects it, or sets a boundary from it.** Provenance that is read-only is
transparency theatre. Provenance that is the entry point to the boundary control
is the mechanism §1.3 describes.

### WLOS response

It shows what it actually has, using the explainability contract that already
exists on every one of the 24 pipeline stages: `reason`, `evidence`,
`confidence`, `source`.

The vocabulary is already non-causal and already honest:

- `Knowledge.SignalRelation.RelationKind` — `commonly_precedes`,
  `commonly_co_occurs`. *"The platform already refuses to say 'your work caused
  your low mood.'"*
- `SignalRelation.Strength` — confidence.
- `SignalRelation.SourceNote` — provenance.
- `Identity.UserLifeStage.Source` — distinguishes *she declared it* from *the
  system derived it*. This is the FACT/INTERPRETATION distinction, already in a
  column.
- `Intelligence.StateDimension.UnknownText` — the per-dimension sentence for
  having no answer. **UNKNOWN is a designed message here, not a null.**

**"Because you told us" and "because we worked it out" must be visibly different
answers.** That is the whole candidate.

### Required context

Whatever the item it explains consumed. Adds nothing of its own. It does need
read access to `boundary` and `personalization controls` in order to be the
place they are set (**M3**).

### Expected value to her

It is the answer to the strongest negative finding in the market research.
`WLOS_MARKET_RESEARCH_II.md` §0.2: **3–6%** trust in a chatbot without
professional oversight, **49–55%** with it. *"The gap between 49–55% and 3–6% is
the entire finding. Unsupervised AI health advice has almost no trust."* And
§5's honest differentiator against ChatGPT: *"No memory of her life, no
provenance."*

It is also the only candidate that improves **every other candidate's** worst
case. A wrong observation with a visible, correctable reason is a conversation.
A wrong observation with no reason is a reason to uninstall.

### Minimum data required before it can say anything useful

**None — and this is its distinguishing property.** *"Nothing to flag"* and
*"Not enough logged to tell yet"* are already the correct, shippable answers on
day one. The candidate works perfectly while knowing nothing, because *knowing
nothing, and saying so* is the feature.

### Privacy risk

**Lowest of the six as a disclosure. But it has a specific and serious failure
mode.**

- **It must not reveal inference the constitution forbids making.** If a reason
  string ever reads *"because you may be pregnant"* or *"because your entries
  suggest anxiety"*, the provenance feature has not created the violation — it
  has **exposed** one that §1.5 already prohibits. Building this candidate early
  is therefore a compliance instrument: it makes §1.5 violations visible rather
  than latent.
- **§1.7 collision.** Provenance must never reveal that private or withheld
  content exists. *"Not a locked icon, not a greyed row, not a count. Absence
  must be indistinguishable from nothing-to-show."* A reason string saying
  *"hidden by your boundary"* breaks this in a shared-device or coerced-access
  situation.
- `Audit.AuditLog` records access including by operators, and refusals are
  audited (`Security.OperatorClaimRefused`), so the disclosure surface itself is
  accountable.

### Dependency on longitudinal memory

**None.** It explains whatever exists, including nothing.

### Platform primitives consumed

24-stage pipeline explainability contract (`reason`, `evidence`, `confidence`,
`source`) · `Knowledge.SignalRelation` (`RelationKind`, `Strength`,
`SourceNote`) · `Identity.UserLifeStage.Source` ·
`Intelligence.StateDimension.UnknownText` · `Audit.AuditLog` ·
`AI.SafetyEvent` (`Decision`, `RefusalCategory`, `ClinicalScore`, `CrisisScore`,
`PromptVersion`, `ModelId`) · `Content.ContentReview` for content provenance ·
`ContentTranslation.IsMachineTranslated` — *this content was machine-translated*
is itself a provenance statement.

**This candidate consumes more existing platform than any other and builds least
that is new.**

### Missing primitives required

- **M3 Preference + boundary + controls** — required for the correction half.
  Without it, provenance is read-only and §1.3's *"and correct it"* is
  unfulfilled. `WLOS_CONSTITUTION.md` Part 0 is exactly this gap: *"The platform
  can personalise. It has no model of her saying no."*
- **M5 Country safety configuration** — only where a reason cites a
  country-specific rule or pathway.
- No other missing primitive is required.

### What experiment would validate it

- Show a **deliberately wrong** recommendation with and without a reason string.
  Measure the difference in stated trust and in willingness to continue.
- Test whether she can distinguish *because you told us* from *because we worked
  it out* without being coached.
- Test the UNKNOWN path on its own: does *"Not enough logged to tell yet"* read
  as honest or as broken?
- Test whether the reason string leads her to correct or to set a boundary — the
  action, not the read.

### What would falsify it

- She does not look. Provenance that nobody opens is cost without return, and
  the finding would be that trust is bought some other way.
- The reason strings are unintelligible, which turns transparency into noise.
- Seeing the reasoning **reduces** trust — a real possibility. A thin reason
  exposes how little WLOS knows, and the honest version may be less reassuring
  than silence.
- She wants a conclusion, not a derivation, in which case §0.2's trust finding
  does not translate into this particular mechanism.

---

## 6. Candidate F — Memory of what matters (she said something months ago, WLOS remembers)

> ### ⚠️ HYPOTHESIS — NOT APPROVED

**Named in:** `WLOS_CONSTITUTION.md` §1.9 — permitted retention includes
*"It remembers what matters to her without being asked"* and *"It understands
her better this month than last"* · `PROJECT_STATE.md` §3 (*"remember for me"*)
and §9.2 (**Memory value** is a scored viability dimension) ·
`WLOS_MARKET_RESEARCH_II.md` §5 (the ChatGPT gap: *"No memory of her life"*).

### User situation

Something she told WLOS months ago is relevant again — a goal, an event she
marked, a stated preference, a thing she said mattered. She has almost certainly
forgotten telling it.

### Trigger

Contextual recurrence: an anniversary in `Timeline.Event`, a `Growth.UserGoal`
becoming relevant again, a life-stage transition in `UserLifeStage`, or a return
to a topic.

### User action

She recognises it — or she does not, which is the failure case and must be
survivable. She can correct it, let it expire, or delete it, and deletion means
deletion (§1.3: *"not a flag"*).

### WLOS response

It surfaces the thing **in her own words**, with its date and its source. Not a
summary of her. Not a profile. §1.3's standard is *"She can see what WLOS
believes about her, **in her own words**, and correct it."*

**The retention lifetimes in §1.6 are binding and they are what make this
candidate legitimate rather than creepy:**

| Kind | Lifetime |
|---|---|
| Profile, preferences, boundaries | Until she changes them |
| Goals, events, journey | Until she deletes them |
| Health entries | Until she deletes them |
| **Needs** | **Hours. A need is about now** |
| **Emotional state** | **Days, as a data point; never a label that sticks** |
| Sharing grants | Until expiry or revocation, whichever first |
| Camera frames | **Never stored.** Derived baseline deltas only |

So this candidate may remember **goals, events, journey and stated preferences**.
It may **not** remember needs, and it may **not** turn emotional states into a
standing characterisation. *"I need space"* in March is not available in
September. That is not a limitation to engineer around; it is the boundary of
the candidate.

`WLOS_HUMAN_MODEL_REVIEW.md` Q8 confirms the architecture already respects this:
*"Nothing about her is stored as a conclusion. Snapshots are stored as history,
not as a standing belief."*

### Required context

`goal` · `Timeline.Event` / `EventType` · `life_stage` history with `Source` ·
`preference` (**M3**) · `boundary` (**M3**). Needs `intent` (**M2**) to know
whether raising the past is wanted at this moment.

### Expected value to her

It is the **only** permitted retention mechanism in §1.9 that is also a product
feature rather than a restraint. And it is the direct counter to the strongest
competitive threat: `WLOS_MARKET_RESEARCH_II.md` §5 — ChatGPT is *"Free, answers
anything"* but has *"No memory of her life, no provenance."*

`WLOS_CONSTITUTION.md` §1.9's permitted list is effectively this candidate's
value statement:
*"She has years of context here, and leaving means losing it"* ·
*"It understands her better this month than last"* ·
*"It remembers what matters to her without being asked."*

### Minimum data required before it can say anything useful

**Months.** Structurally the longest lead time of the six, and the value is
defined by the gap between saying and recalling. A version tested at two weeks
is not testing this candidate.

Nothing to surface at all until she has volunteered something durable, which
means this candidate **cannot be the first experience** — it can only be the
reason a first experience is worth repeating. That is a real constraint on where
it can sit, not a criticism of it.

### Privacy risk

**The highest stakes, though not the highest surface.**

- **Recall is also disclosure.** Something surfaced on a lock screen, or on a
  shared handset (§1.1 of the market research: 13% smartphone ownership gender
  gap, 810M women in LMICs not using mobile internet), is disclosed to whoever
  is holding the phone. §1.7's rule that *nothing reveals that private content
  exists* means a memory surface needs a locked-state policy before it has a
  design.
- **The person she needs privacy from is sometimes the person asking for
  access** (§1.7, `WLOS_LIFE_MODEL.md` §3.2). *"In many markets WLOS would
  serve, family monitoring of women is a safety issue rather than a
  hypothetical."*
- **Memory is what makes deletion meaningful.** §1.3 requires export of
  everything in readable form without asking, and deletion that is deletion.
  A memory feature is the feature that tests whether those are real.
- **§1.6 expiry is a hard boundary, not a default.** A memory engine that
  quietly retains needs beyond hours, or emotional states beyond days, has
  violated the constitution regardless of how useful the result is.
- **§1.5 applies to accumulation.** Remembering three stated facts is permitted.
  Deducing a fourth from them — pregnancy, relationship status, religion,
  diagnosis — is not, and an accumulating memory is where that temptation lives.

### Dependency on longitudinal memory

**Strong. It is the definition.** This candidate *is* the longitudinal
hypothesis, tested directly.

### Platform primitives consumed

`Timeline.Event` / `EventType` · `Growth.UserGoal` / `GoalTemplate` ·
`Identity.UserLifeStage` with `StartedOn`, `EndedOn`, `Source`, `Note` ·
`Intelligence.UserStateSnapshot` (as history, never as standing belief) ·
`Audit.AuditLog` · `Coach.ToneProfile`.

**Note:** `WLOS_HUMAN_MODEL_REVIEW.md` Q1 records that non-stage transitions —
moving country, job loss, starting university, bereavement, divorce — have **no
representation** unless they happen to be life-stage changes. The 17
`EventType` categories are domains (`work`, `health`, `learning`), not
transitions. The things most worth remembering may be the things there is
currently nowhere to put.

### Missing primitives required

- **M3 Preference + boundary + controls** — required. Includes the
  *AI learning OFF* control in §4.3, which `WLOS_HUMAN_MODEL_REVIEW.md` flags as
  *"one toggle hides four different controls."* Memory is where that
  decomposition has to be resolved.
- **M2 Intent / response mode** — required to know whether raising the past is
  welcome now. Raising a hard anniversary while she is in `Space` is the
  candidate's worst failure.
- **M4 Responsibility load** — would extend it to caregiving continuity.
- **M6 Support network** — **only** if memory ever extends across accounts. All
  three §1.7 rules must be settled and written down first, and
  `WLOS_LIFE_MODEL.md` §3.2 is explicit: *"This feature is worth building. It is
  not worth building quickly."*

### What experiment would validate it

- Cannot be tested in a two-week prototype. Either a longitudinal diary study,
  or a retrospective: ask a participant what she told an app six months ago and
  whether its remembering would have changed anything.
- `WLOS_INTERVIEW_PROTOCOL.md` already scores this: **Memory value** 0–2, where
  0 = *would not help* and 2 = *spontaneously wants continuity*. Threshold:
  **≥1 in ≥9 of 14.**
- Test the **unwanted** recall explicitly — a memory she would rather WLOS had
  not kept. The response to that is the candidate's real design.

### What would falsify it

- **Trust.** `WLOS_INTERVIEW_PROTOCOL.md`: *Trust ≤ 1 in ≥ 7 of 14* —
  *"Longitudinal context is a liability, not an asset. **Kills it independently
  of everything else.**"*
- Memory value < 1 in more than 5 of 14 — remembering would not have changed
  anything.
- She finds recall intrusive rather than caring, at any meaningful rate.
- Lock-in framing. If the only reason she stays is that leaving costs her years
  of context, §1.9's permitted list has been read as permission for a trap. The
  clause permits *accumulated value*, and the difference between value and
  hostage-taking is whether §1.3's export and deletion are effortless.

---

## 7. Cross-candidate summary table

**All six are HYPOTHESIS — NOT APPROVED. This table is deliberately in the order
the task listed them. It is not a ranking, and no column should be read as a
score.**

| | A · Needs | B · Noticing | C · Protect tomorrow | D · Response mode | E · Why this? | F · Memory |
|---|---|---|---|---|---|---|
| **Initiated by** | her | **system** | either | her | her | system |
| **Longitudinal dependency** | none | **strong** | **strong** | none–weak | none | **strong** |
| **Works on day one** | yes | no | no | yes | yes | no |
| **Minimum data** | one tap | days–weeks | calendar + baseline | one selection | none | **months** |
| **Existing primitives used** | targeting, tone | state, signals, rules | state, signals, recommend, predict | tone | **explainability, signals, audit, safety** | timeline, goals, life-stage history |
| **Missing primitives** | **M1**, M3 | **M3**, M5 (M1, M4) | **M3**, **M4**, M5 (M1, M2) | **M2**, M3 (M1) | **M3** (M5) | **M3**, **M2** (M4, M6) |
| **Privacy surface** | low | high | **highest** | low | low | high stakes, low surface |
| **Editorial floor** | **high** — needs content | medium | medium | **high** — needs content | none | low |
| **§1.5 pressure point** | need sequences | cycle+mood+sleep chains | calendar titles | mode patterns | **exposes violations** | accumulation |
| **Primary kill signal** | "nothing changed" | "I already knew" | "won't connect calendar" | "just know for me" | "didn't look" | Trust ≤1 in ≥7/14 |

**M3 — preference, boundary and personalization controls — appears in all six.**
It is the only row with no exceptions.

---

## 8. What all candidates share, and the one question

### 8.1 What all six share

**1. All six need M3 — preference, boundary and controls — and none of them can
be made safe without it.**
`WLOS_CONSTITUTION.md` Part 0 is the finding: *"The platform can personalise. It
has no model of her saying no."* Ten targeting dimensions, twelve life stages,
eight role modes, nine state dimensions — and the only per-user preference
tables in the entire platform are `Identity.Profile` and
`Health.BirthPreference`, which is pregnancy-specific. `Administration.Setting`
has no `UserId`.
§4.4 states the cost curve: there is **one assembly point** (`LifeOsRepository` →
`LifeOsContextRow` → `ResolveLifeOsHandler`), and a boundary applied there is
inherited by every feature. Retrofitted after fifty features, *"it becomes fifty
places to enforce a boundary, and the one that is missed is the one that shows
pregnancy content to a woman who asked never to see it again."*
**This is an observation about all six candidates, not an authorisation to build
M3.** `PROJECT_STATE.md` §9.0 lists preference and boundary tables as not
authorised.

**2. All six are gated on content, not architecture.**
22 domains · 10 targeting dimensions · 12 life stages · 8 role modes · 12
signals · 24 pipeline stages · 68 endpoints — and **6 content items**.
`WLOS_LIFE_MODEL.md` §3.4: *"What does not exist is anything to say."* Candidates
A and D are affected most; Candidate E least, because explaining nothing is a
valid output.

**3. All six are subject to §1.5, and each has its own pressure point.**
The never-infer list is not an edge case for any of them. Need sequences,
signal chains, calendar text, mode patterns and accumulated memory are five
different routes to the same prohibited deduction.

**4. All six must behave well while knowing nothing.**
`StateDimension.UnknownText` already implements this at the presentation layer,
per dimension. **UNKNOWN is a designed message, not a null.** Any candidate that
fills the unknown with something less rigorous has stopped being that candidate.

**5. None of them may buy retention with pressure.**
§1.9 permits retention from accumulated value and forbids streaks, guilt,
loss-framing, manufactured urgency and dependency. The external evidence agrees
that the prohibition is also commercially correct: **44% motivation drop-off
after breaking a streak**, and the EU KIDS Act (17 Sep 2026) bans
non-return-penalising streaks for minors with penalties to **6% of global
turnover**. The inherited streak ring on the home screen is subject to this
clause — and streak redesign is itself on §9.0's not-authorised list.

**6. All six are downstream of the same unproven claim.**
`WLOS_MARKET_RESEARCH_II.md` §5: *"Every alternative holds one axis of her life.
WLOS's only defensible claim is the **join**."* And `PROJECT_STATE.md` §8 lists
*"whether the join is perceptible in use"* as **the largest unknown**. If a
woman's bad week is one problem rather than a loop, all six candidates are
competing against a better single-purpose app.

**7. None is authorised.**
`PROJECT_STATE.md` §9.0 — Today screen, Need implementation, preference and
boundary tables, personalization controls, response modes, content expansion, AI
implementation, camera implementation, relationship model, country safety
configuration, streak redesign: **not authorised.** §9.1: the one next action is
**recruit C4** — the woman who started a health, fitness or habit app within the
last year, stopped, and will explain what was happening around the time she
stopped. She is marked non-substitutable because she is the only person who can
explain day 31.

### 8.2 The single question that would eliminate most of them

> ## *"Would she permit WLOS to remember the context of her life across months — and does she believe that remembering would have changed what happened?"*

This is not a new question. It is the pair of viability dimensions already
locked into the Phase A coding frame — **Trust** (0–2, *would she permit that
memory*) and **Memory value** (0–2, *could remembering context change what
happens next*) — each requiring **≥1 in ≥9 of 14**, with the kill condition
**Trust ≤ 1 in ≥ 7 of 14**, which *"kills it independently of everything
else."*

**Why this question and not another.** It is the only question that cuts the map
rather than shading it:

| If the answer is **no** | |
|---|---|
| **B · Noticing** | eliminated — no permitted baseline, nothing to notice from |
| **C · Protect tomorrow** | eliminated — no personal load baseline, and the calendar grant is a larger version of the same refusal |
| **F · Memory of what matters** | eliminated — it *is* the question |
| **E · Why am I seeing this?** | survives, but shrinks to explaining single-session decisions rather than a longitudinal understanding |
| **A · Needs entry loop** | survives intact — session-scoped, decays in hours, needs no history |
| **D · Response mode** | survives intact — per-exchange, needs no history |

Three of six gone, one diminished, on one answer.

**And the residue is the harder finding.** What survives — A and D — is a
system that asks her what she needs and how she wants to be answered, and
forgets. That may be a good product. It is **not the product in
`PROJECT_STATE.md` §3**, whose north star is *a lifelong personal companion*
that helps her *remember what matters*, and it does not require most of the
platform that has been built. `WLOS_CONSTITUTION.md` Part 5.4 asks an
architectural question in the same shape for minors — *"is a non-personalised,
streak-free WLOS still WLOS?"* — and a no to this question asks it for everyone.

**The answer is not in this document, and it is not desk-researchable.**
`WLOS_MARKET_RESEARCH_II.md` §9: *"Stop researching and start interviewing. The
remaining unknowns are about whether women recognise the problem WLOS solves —
and no amount of market data answers that."*

`PROJECT_STATE.md` §9.2 sets the discipline that this map must not violate:
code within 24 hours, lock the row, **no running totals**, no interpretation
during fieldwork, no AI analysis mid-study, and **do not compute or look at
aggregate scores until all 14 rows are locked.**

Nothing on this map is designed, chosen or built until item 13 of the Phase A
Findings Report exists.

---

## 9. Document status

| | |
|---|---|
| **Candidates approved** | **0 of 6** |
| **Candidates ranked** | **none** |
| **Candidates recommended** | **none** |
| **New market claims introduced** | **none** |
| **Files modified** | **none** |
| **Code touched** | **none** |
| **Supersedes** | nothing |
| **Superseded by** | the Phase A Findings Report, when it exists |

