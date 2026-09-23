# WLOS Life Model — Layers 2 and 5

**Status:** proposal for review. Nothing here is built, and nothing should be
built from it until it is accepted.

**Scope:** what exists in her life (Layer 2) and what WLOS keeps (Layer 5),
plus the concepts they cannot be defined without. Fifteen concepts, how they
connect, where every fact came from, and which parts an operator configures.

**Age scope is not settled and is not decided here.** The model is designed to be
lifelong-capable — a sixteen-year-old and a seventy-year-old must both fit it
without a second schema. Whether WLOS opens to minors, and how, is a separate
safety, consent and regulatory programme; a draft of it exists in
`WLOS_WORLDS.md` and is **explicitly unapproved**. Nothing in this document
depends on that decision.

---

## 1. The one decision everything else depends on

> **Is a Life Area a category WLOS defines, or a thing she names?**

**Both, and the split is the whole design.**

A fixed list — Health, Work, Family, Finance — cannot hold *"the bakery"*,
*"Amira"*, *"my MSc"*, *"Dad's care"*, *"Islamic learning"* or *"the
allotment"*. A purely free-form list cannot be reasoned about, targeted,
translated, or configured by anyone but her.

So:

```
  ADMIN curates a CATALOGUE          SHE instantiates AREAS
  ─────────────────────────          ──────────────────────
  area types, names, icons,          "The bakery"     → type: work.business
  what each type can hold,     →     "Amira"          → type: family.child
  what to suggest per stage          "My MSc"         → type: education.study
                                     "Dad"            → type: family.care
                                     "The allotment"  → type: hobby
```

The **type** is admin-configured vocabulary. The **area** is hers, named by
her, invisible to every operator. Adding `faith`, `caring`, `business` or
`creative-practice` as a type is an admin change and ships without a release —
the same way content and rules already work on this platform.

**Corollary:** WLOS never asks *"what kind of woman is she?"* It asks *"what is
in her life, and what changed?"* The type exists so WLOS can offer the right
help, never so it can classify her.

---

## 2. The fifteen concepts

Grouped by the question each answers, rather than listed flat.

### WHO

**Person** — the account holder. One per account. Name, how she wants to be
addressed, locale, accessibility needs. Identity, not biography.

**Relationship** — a person in her life: her mother, a child, a manager, a
friend, a consultant. Holds only what she has told WLOS. **Not** a contact
list, **not** a social graph, and never synced from her phone without an
explicit act.

> **A Person is not a Life Area, and a Life Area may be *about* a Person.**
>
> The person is the entity. The area is **the context she has chosen to keep
> around that entity** — which means one person can have several, or none.
>
> ```
>   Person: Amira
>     ├── Life Area: "Amira's school"        (type: education)
>     └── Life Area: "Me and Amira"          (type: relationship)
> ```
>
> Collapsing the two would force a choice between a child in a contact list
> with no life attached, or an area with no person behind it. Keeping them
> separate is what lets *"my relationship with my mother"* and *"Mum's care"*
> be different things about the same person — which for a woman in the middle
> of both, they very much are.

### WHAT EXISTS

**Life Area** — a named part of her life. Two halves, and the split is the
whole design:

```
  Life Area TYPE          (admin catalogue — what WLOS understands)
        ↓
  Life Area INSTANCE      (hers — what exists in her life)

  Type: Work        →  "My bakery"
  Type: Education   →  "My MSc"
  Type: Family      →  "Amira's school"
  Type: Personal    →  "Me"
```

> **Admin defines what WLOS understands. She defines what exists in her life.**

Optionally *about* a Person. The spine: almost everything else attaches to one
or more areas. She creates, renames, archives and reorders them.

**Event** — something with a time. Appointment, deadline, birthday, delivery,
exam. Past or future. Belongs to zero or more areas.

### WHAT SHE IS CHANGING

**Goal** — an outcome she is working towards. Has a shape (a finish, a level, a
maintenance) rather than a progress bar by default.

**Habit / Behaviour** — a repeated thing she is trying to adopt or stop.
Distinct from a Goal: a goal completes, a behaviour is ongoing.

> The product difference from every habit tracker: WLOS holds **the direction
> she chose** and **how long she has been at it**, not a streak. A streak makes
> the day she most needs to be honest the day honesty costs her something.

### HOW SHE IS

**State** — a check-in on a dimension she has opted into: energy, sleep, mood,
stress, pain. Dimensions are admin-configured, each with its own *unknown*
text, and **every one is optional**. A dimension she has not enabled does not
exist for her; a day she did not answer is unknown and stays unknown.

### WHAT SHE KEEPS

**Journal** — something she wrote, in her words, kept as written. A document.
WLOS does not summarise, score or interpret it.

**Memory** — a fact she has asked WLOS to hold. *"Amira is allergic to
sesame."* *"My tutor is Dr Okafor."* *"I met Tom at the dance hall in 1974."*

> **Journal and Memory are not the same object and conflating them is the most
> likely modelling error here.** A journal entry is a text she authored. A
> memory is a fact WLOS may use. A memory may be *extracted from* a journal
> entry — **only with her explicit confirmation**, never silently.

Memory has a **kind**, because two very different intents share the word:

| Kind | What it is for | Example |
|---|---|---|
| `operational` | So she never has to say it twice | "I work Tuesdays from home" |
| `biographical` | Part of her story, preserved | "We moved to Leeds in 1998" |

User 5 below is why. For a seventy-year-old, Memory is substantially life
history; for a twenty-eight-year-old it is substantially working context. One
object, two intents, different surfaces.

### WHAT SHAPES IT

**Life Stage** — a stage she has explicitly entered. Admin defines the stages
and **which capabilities each one unlocks**. A stage never changes what WLOS
believes about her, only what it offers.

**Preference** — how WLOS behaves: how much it says, what it does when
something is hard, how much it keeps.

**Boundary** — what WLOS may do, and the subjects it must never infer. Sits
above Preference in the precedence rule.

```
  Safety  >  Boundary  >  Preference  >  Derived  >  Observed  >  Ambient
```

### WHAT WLOS DERIVES

**Context** — the resolved answer to *"what is true right now?"* Assembled on
demand from everything above. **Context is computed, never stored as truth** —
the moment it is persisted it becomes a belief about her that can go stale
without anyone noticing.

**Pattern** — something WLOS has noticed. *"Exercise is usually skipped on days
with a morning meeting."*

> **A Pattern is never a fact.** It is a candidate, and it has exactly two
> futures: she confirms it, and it becomes something she has stated — or she
> does not, and it decays. A pattern may never cross a Boundary, may never be
> used as evidence for a decision until confirmed, and may never be presented
> as a conclusion about her.
>
> *"I noticed this."* — allowed.
> *"You are avoiding exercise."* — never.

### WHAT WLOS DOES

**Action** — the only thing that changes the world: create a reminder, move a
plan, start a habit, record a memory, draft a message. Every Action traces to
something she authorised, and every Action is reversible or confirmable before
it happens.

---

## 3. Provenance — the spine of the whole model

Every fact in WLOS carries where it came from. Without this, a guess and a
statement become indistinguishable the moment they are stored, and that is the
failure this product exists to avoid.

| Provenance | Meaning | May WLOS act on it? |
|---|---|---|
| `stated` | She said it | Yes |
| `confirmed` | WLOS proposed, she agreed | Yes |
| `imported` | From a source she connected | Yes, marked as such |
| `derived` | Computed from stated facts, deterministic and explainable | Yes, with the working shown |
| `observed` | A pattern WLOS noticed | **No** — may only be offered for confirmation |
| `ambient` | Temporary context: time, day, weather | Yes, and never stored |

**Three rules that follow:**

1. `observed` never becomes `stated` without her. There is no path, no
   threshold, no confidence score that promotes it.
2. Nothing `observed` may touch a subject she has closed in Boundaries. Not to
   act on, not to offer, not to store.
3. `derived` must be able to show its working. If WLOS cannot explain how it
   got there, it is `observed`.

This is what makes *"Why am I seeing this?"* answerable on every surface rather
than a card on Today.

---

## 4. How they connect

```
        Person
          │
          ├── Preferences ── Boundaries ─────┐
          │                                   │  govern everything below
          ├── Life Stage ──── unlocks ────────┤
          │                                   │
          ├── Life Areas ──── about ──► Relationship
          │     │
          │     ├── Events        (when)
          │     ├── Goals         (towards)
          │     ├── Behaviours    (change)
          │     ├── Journal       (wrote)
          │     └── Memories      (hold)
          │
          └── State              (how)
                    │
                    ▼
            ┌───────────────┐
            │    CONTEXT    │  computed, never stored
            └───────┬───────┘
                    │
                    ▼
                 PATTERN ──── she confirms ────► Memory / Goal
                    │
                    │ (unconfirmed: offered once, then decays)
                    ▼
            ┌───────────────┐
            │    ACTION     │  remind · guide · do
            └───────────────┘
                    │
                    ▼
                 Memory        (what happened becomes context later)
```

**Four journeys this has to support:**

```
Event ──► Context ──► Goal ──► Action ──► Memory
Journal ──► Pattern ──► she confirms ──► Behaviour change
Life Stage ──► capabilities offered ──► areas suggested
Memory ──► future Context ──► better help
```

The loop at the bottom is the product. What happened becomes what WLOS knows,
which makes the next day's help better. Without Memory feeding Context, WLOS is
a dashboard.

---

## 5. What the admin panel configures — and what it must never see

The requirement is that everything is configured from the admin panel. The
resolution is that **operators configure the vocabulary; she owns the
content.** This extends the Slice 1 principle: the portal got age-gate *status*
and never her date of birth.

### Operators configure

| | |
|---|---|
| **Life Area catalogue** | types, names, icons, what each can hold, which to suggest per stage |
| **Life Stages** | the stages, and what capabilities each unlocks |
| **Event types** | appointment, deadline, occasion, and their defaults |
| **Goal & Behaviour templates** | the starter library she can adopt from |
| **State dimensions** | which exist, their scales, and each one's *unknown* text |
| **Preference dimensions** | the questions and the options |
| **Boundary subjects** | **the never-infer list itself** — so a new sensitive subject can be added without a release |
| **Pattern definitions** | what WLOS is permitted to look for at all |
| **Action types** | what WLOS may do, and what each requires before doing it |
| **Copy** | every string, translatable, versioned, approved |

### Operators never see

Her areas · her people · her events · her goals · her behaviours · her journal ·
her memories · her state · her patterns.

**Not because the endpoints are missing. Because they must not exist.** The
enforcement belongs in stored procedures, the way `usp_User_GetDetail` returns
`IsAgeVerified` as a computed bit and cannot return her date of birth however
the client asks.

Support answers *"is the platform working for this account"*, never *"what is
she going through."*

---

## 6. The five-user test

If the model only works for one of these, the model is wrong. Working them
through is what produced the two structural findings marked **▸** below.

### 18 — university student

> Areas: *Second year Psychology* · *Halls* · *Money* · *Rowing* · *Home*
> People: flatmate, mum, personal tutor
> Goals: pass the stats module · Behaviours: asleep before 1am
> Events: exam, rent due · State: sleep, stress
> Memory: *"My tutor is Dr Okafor, office hours Wednesday"* `operational`

Holds. Note *Home* is her parents' house, not hers — the area is about
belonging, not property.

### 28 — software engineer

> Areas: *Work at Nexa* · *Learning Flutter* · *The flat* · *Money* · *Running*
> People: manager, two close friends
> Goals: ship the migration · learn Flutter
> Behaviours: evening walk · Events: 1:1s, standups
> Memory: *"1:1 with Priya is Thursdays"* `operational`

Holds. *Learning Flutter* is an area, not a goal — it has its own events,
memories and sub-goals. **An area is anything with enough life in it to hold
things.**

### 40 — bakery owner, two children, mother needing care

> Areas: *The bakery* · *Amira (7)* · *Yusuf (4)* · *Mum* · *Home* · *Me*
> Goals: hire a second baker · Behaviours: laptop closed by 8
> Events: parents' evening, supplier delivery, Mum's consultant
> Memory: *"Amira is allergic to sesame"* `operational`

**▸ Finding 1: a Life Area may be about a Person.** *Amira* is a relationship
and an area. Without this the model forces her to choose between a child in a
contact list with no life attached, or an area with no person behind it. Both
are wrong.

**▸ Finding 2: *Me* is a Life Area.** For a woman whose life is mostly other
people, her own self is a part of life that can be neglected — and it must be
nameable and visible. This is the single strongest argument that areas are hers
to create rather than ours to enumerate.

### 55 — professional, caring for parents, mid-career

> Areas: *Work* · *Mum and Dad* · *Menopause* · *Pension* · *The garden* ·
> *MSc (part-time)*
> Goals: finish the dissertation · Behaviours: strength training twice a week
> Events: Dad's cardiology appointment, dissertation deadline
> Memory: *"Dad's consultant is at St Mary's, Dr Reyes"* `operational`

Holds, and shows the model must let a health subject (*Menopause*) be an area
she named — **not a mode WLOS switched her into.** Exactly the pregnancy
boundary, generalised.

### 70 — retired

> Areas: *Health* · *Medication* · *Family* · *Choir* · *The allotment* ·
> *My story*
> Goals: walk every day · Behaviours: medication at 8
> Events: cardiology review, grandson's birthday
> Memories: *"I met Tom at the dance hall in 1974"* `biographical`

**▸ Finding 3: Memory has two intents.** *My story* is an area whose content is
almost entirely biographical memory. Modelling Memory only as
"remember-this-so-I-need-not-repeat-it" would have made WLOS useless for the
part of her life she most wants held.

---

## 7. What this changes about Today

Today stops being a screen with cards on it and becomes **the rendering of
Context**. Not "today's tasks, today's habits, today's mood" but:

> Your day is fairly full. The presentation and the dentist are fixed. The walk
> is flexible — shall I move it to tomorrow?

Which requires, in order: Events (fixed vs flexible) · Goals (the walk belongs
to one) · State (yesterday's energy) · Memory (she said she wanted to restart
the walks) · Pattern (she usually skips it on full days, **confirmed**) ·
Preference (how much to say) · Boundary (whether to raise it at all).

**Today is the last thing to build, not the first.** It has no content of its
own. It is the surface where the model becomes visible, which is why the
current Today is a shell — there is nothing yet for it to render.

---

## 8. The six questions — decided

Settled in review. These are now part of the model, not open.

**A. Nesting — two levels, no more.**

```
  ALLOWED                    REFUSED
  My work                    Life ▸ Family ▸ Daughter ▸ School ▸ Class ▸ Teacher
    └── My bakery
  My daughter
    └── School
```

Deeper turns WLOS into a project-management hierarchy. Revisit only if real
use demands it.

**B. Shared areas — yes eventually, as a separate permission layer.**

Never "sharing this area gives him everything". Scoped, expiring and revocable,
per the existing sharing principles:

```
  "Amira"  ──shared with partner──►  school events
                                     appointments
                                     selected memories   ← and nothing else
```

**C. Calendar — a source, never the authority.**

```
  External calendar  ──►  Imported Event  ──►  WLOS Event
```

`imported` stays distinguishable from WLOS-owned for the life of the record.
An external system must never become the authority over her life.

**D. Unconfirmed patterns — no timer in the model.**

A Pattern carries `observed`, `last observed`, `occurrence history` and
`status`. Lifecycle rules are a product decision to be made later against real
behaviour. The rule that is fixed now: **an unconfirmed pattern can never
become permanent personal truth.** It may decay; it may never promote itself.

**E. Goals — measurement is optional, never imposed.**

| Kind | Example | Measurable? |
|---|---|---|
| Measurable | *Save Rs. 500,000* | yes |
| Binary | *Complete MSc* | no — done or not |
| Qualitative | *Become more confident* | no |
| Ongoing | *Improve things with my mother* | no |

```
  Goal
   ├── desired outcome
   ├── status
   ├── milestones            (optional)
   ├── measurable progress   (optional)
   └── supporting actions
```

A progress bar appears **only** where progress is genuinely measurable. Forcing
one turns a hope into a metric and a qualitative goal into a failure.

**F. Journal — a capability of a Life Area, plus a global view.**

Entries belong to an area — *Me*, *My work*, *My child*, *My MSc* — and a
global journal shows everything in one place. Attachment is **optional**: she
can write first and file later, or never. Capture must never be heavier than
the thought.

---

## 9. What this does not cover

Layer 7 (Intelligence) and Layer 8 (Actions) are sketched only as far as
needed to keep Layers 2 and 5 honest. Conversation is deliberately absent —
it is **one interface to the intelligence, not the product**, and modelling it
now would pull the data model toward a chat log.

---

## 10. Resilience test — five lives, no new entity types

**The rule:** represent five radically different lives using only the fifteen
concepts. If the model needs `StudentEntity`, `MotherEntity`, `BusinessEntity`
or `RetirementEntity`, it is a category app wearing a whole-life label and it
has failed.

Everything below resolves to: **Life Area · Person · Event · Goal · Behaviour ·
State · Journal · Memory · Life Stage · Preference · Boundary · Pattern ·
Context · Action.**

### 1 — 19, university student

| Her life | Concept |
|---|---|
| *Second year Psychology* | Area `education` |
| *Halls*, *Money*, *Rowing*, *Home* | Areas |
| Flatmate, mum, personal tutor | People |
| Stats exam, 12 May | Event |
| Pass the stats module | Goal `binary` |
| Asleep before 1am | Behaviour |
| "My tutor is Dr Okafor" | Memory `operational` |
| Sleep, stress | State dimensions |

**Modules and grades?** A module is an Area (*Stats*) or a Goal, depending on
whether she wants to keep things in it. Her choice, not ours. **No new type.**

### 2 — 28, software engineer

| Her life | Concept |
|---|---|
| *Work at Nexa*, *Learning Flutter*, *The flat*, *Running* | Areas |
| Priya (manager), two friends | People |
| 1:1 Thursdays, sprint review | Events `recurring` |
| Ship the migration | Goal `binary` + milestones |
| Learn Flutter | Goal `qualitative`, and also an Area |
| Evening walk | Behaviour |

**▸ Finding 4: the same thing can be a Goal *and* an Area.** *Learning Flutter*
is an outcome she wants and a part of her life with its own events, memories
and sub-goals. The model must let her promote a goal into an area without
losing what is attached. **No new type** — but it is a real relationship the
schema will have to carry.

### 3 — 40, mother of two, bakery owner

| Her life | Concept |
|---|---|
| *The bakery*, *Home*, *Me* | Areas |
| *Amira's school*, *Me and Amira* | Areas **about** Person: Amira |
| *Mum's care* | Area about Person: her mother |
| Yusuf, two bakers, a supplier | People |
| Parents' evening, flour delivery, Mum's consultant | Events |
| Hire a second baker | Goal `binary` |
| Save Rs. 500,000 | Goal `measurable` |
| Laptop closed by 8 | Behaviour |
| "Amira is allergic to sesame" | Memory `operational` |

The Person/Area split earns its keep here: *Amira's school* and *Me and Amira*
are different contexts around one child, and a mother in the middle of both
knows they are not the same thing.

**Twelve staff?** She records the two she thinks about. The model permits many
and requires none — a Person exists because she named them, never because an
org chart did.

### 4 — 55, doctor, mid-career

| Her life | Concept |
|---|---|
| *The practice*, *Mum and Dad*, *Pension*, *The garden* | Areas |
| Revalidation portfolio | Goal `binary` + milestones |
| CPD hours | Goal `measurable` |
| On-call Thursday, appraisal | Events `recurring` |
| Strength training twice a week | Behaviour |
| *Menopause* | Area **she named** — not a mode WLOS put her in |

**▸ Finding 5: a professional boundary, and it is a hard rule.**

> **Her patients are not People in WLOS.** Nor are a teacher's pupils, a
> manager's reports or a lawyer's clients.

WLOS holds **her** life. The moment it holds the people she is professionally
responsible for, it becomes a clinical record with none of the governance one
requires, and it takes on other people's data through a product designed around
her consent alone. The model must state this and the product must refuse it.

*The practice* is an Area. Her patients are nowhere.

### 5 — 70, retired

| Her life | Concept |
|---|---|
| *Health*, *Family*, *Choir*, *The allotment*, *My story* | Areas |
| Cardiology review | Event |
| Medication at 8am | Behaviour `scheduled` + Action `remind` |
| Walk every day | Goal `ongoing` |
| "I met Tom at the dance hall in 1974" | Memory `biographical` |
| Grandchildren, choir friend | People |

**▸ Finding 6: medication is a Behaviour with a schedule — and a safety
question the model cannot answer.**

Structurally it needs nothing new. But a missed-medication reminder is not a
missed-walk reminder, and whether WLOS should handle medication *at all* is a
clinical decision, not a modelling one. **Flagged, not resolved.**

*My story* is an Area whose content is almost entirely `biographical` Memory —
which is why Memory needed two kinds.

### Result

| | |
|---|---|
| New core entity types required | **none** |
| New relationships discovered | Goal↔Area (finding 4) |
| Hard rules discovered | professional boundary (finding 5) |
| Flagged, unresolved | medication safety (finding 6) |
| Special-cased lives | **none** — student, mother, doctor and retiree use the same fifteen |

**The model holds.** Student, engineer, mother, doctor and retiree are all
*Life Areas + People + Events + Goals + Behaviours + Memories + Stage*, and
none of them needed a type of her own.

---

## 11. Authorship — the question every record must answer

> **Who said this?**

Not a field on some records. A property of every record that carries meaning.

```
  "I want to lose 10kg"            → she stated
  "She prefers mornings"           → she stated (preference)
  "Her appointment is Tuesday"     → imported (calendar)
  "MSc completed"                  → she confirmed (from a journal entry)
  "She often postpones exercise"   → WLOS observed — NOT a fact
  "Her friend suggested..."        → quoted inside a journal entry, hers to keep
```

The last two are the point. When the intelligence layer arrives it must be able
to tell **what she said** from **what WLOS thinks it noticed** — at the moment
of use, not by reconstruction. A system that cannot make that distinction ends
up telling a woman things about herself that she never said, in a voice that
sounds like it knows.

### The confirmation flow, concretely

```
  Journal entry
  "Today I finally finished my MSc thesis. I was exhausted but really proud."
                              │
                              ▼
  WLOS:  "You mentioned finishing your MSc today.
          Would you like me to remember this as a milestone?"
                              │
                        she says yes
                              ▼
  Memory   "MSc thesis completed"
           kind        biographical
           date        ...
           source      journal entry #...
           provenance  confirmed
```

**The entry is never silently mined.** The whole text stays hers, as written;
one fact is lifted out, and only because she said so.
