# WLOS Care & Connection Model

**Status:** proposal. Extends `WLOS_LIFE_MODEL_PROPOSAL.md`. Nothing built.

**Three decisions are now fixed** and everything here is built on them:

| Decision | Status |
|---|---|
| Guardian sees **metadata only**, never content | **APPROVED** |
| **Invisible-off** — stopping a share is undetectable to the other side | **APPROVED, non-negotiable** |
| **Adult ↔ adult first** — no minors, no partners, in the first connection release | **APPROVED** |

---

## 1. The architecture

The recipient never receives her record. They receive something **she composed
from it**.

```
        HER PRIVATE CONTEXT          ← never crosses, ever
                 │
        WLOS UNDERSTANDING
                 │
           she chooses              ← a person, a thing, a moment
                 │
           CARE INTENT              ← composed, previewed, approved by her
                 │
        ═══════ BOUNDARY ═══════
                 │
            RECIPIENT
                 │
          CARE ACTION               ← what he can actually do
```

**Two rules that make the boundary real:**

1. Nothing crosses that she has not seen in the exact form it will arrive.
2. **She can always see precisely what he sees.** There is no view of her she
   cannot herself view.

---

## 2. The concepts

The fifteen in the Life Model, plus these.

**Connection** — a link between two accounts. Typed (mother, sister, friend,
partner), mutual, and **leaveable without a conversation**.

**Permission** — what a Connection allows, per category, revocable
individually. Default is nothing.

**Recipient** — the person at the other end. Holds a minimal account, because
a non-user receiving a stream about her is worse than a user we can govern.

**Care Signal** — what crosses. Composed by her from her context, previewed by
her, approved by her. It is a *message she sent*, never a *state he can read*.

**Care Request** — a Signal that asks for something. *"I could use company this
week."*

**Shared Context** — something both hold, by agreement. An anniversary, a
family memory, a child's achievement. The only two-way object.

**Observation** — §4. The most important new concept here.

**World** and **Life Stage** — from `WLOS_WORLDS.md`.

---

## 3. The five primitives

| | Primitive | Direction | Needs sharing? |
|---|---|---|---|
| 1 | **Share** — *"I want you to know this"* | her → them | yes |
| 2 | **Ask for care** — *"I could use support"* | her → them | yes |
| 3 | **Suggest care** — *"she may appreciate this"* | WLOS → them | yes |
| 4 | **Remember together** — a date, a memory | mutual | yes |
| 5 | **Care reminder** — *"you haven't called your mum"* | WLOS → **her** | **no** |

**Primitive 5 needs no connection at all**, and it is the one I would build
first. Helping her show up for people costs nothing in privacy and is
immediately valuable — even to a woman who never connects a single account.

### What a Signal looks like

```
  She records:   "I'm exhausted today."
                          │
  WLOS asks:     "Would you like your mother to know you could use
                  some care today?"                    ← a prompt, not a send
                          │
                    she approves
                          ▼
  Her mother:    "She could use a little extra care today.
                  A call or some time together might mean a lot."
```

Never *"her emotional score is 37"*. Never *"she has been low four days"*.
Never her journal.

---

## 4. Observation — she records her circle

> *"She records her surroundings and her circle, like telling her best friend.
> The app reads from those records, understands the habits, and guides on
> vibes. Later an AI model will work on this."*

This is the right instinct and it needs one structural rule to be safe.

### The rule

> **What she records about another person is a record of HER EXPERIENCE,
> never a record of THEM.**

```
  ALLOWED  (hers)                    REFUSED  (a claim about a third party)
  ─────────────                      ────────────────────────────────
  "I felt small afterwards"          "He is belittling"
  "I didn't say what I meant"        "She is manipulative"
  "I was looking forward to it,      "He has a temper"
   then I wasn't"
```

The left column is her inner life, which is hers to keep and hers to be helped
with. The right column is a stored judgment about a named human being who is
not a user, has consented to nothing, and may one day be a party to a divorce,
a custody case, or a subpoena.

**This is not a copy rule. It is the shape of the record.** There is no field
in which a trait can be stored about a person, so there is no "person score"
for a future model to learn, a controlling partner to find, or a court to
demand.

### The structure

Your own reflection questions turn out to *be* the schema:

```
  Observation
    when
    relates to        → a Person, a Life Area, or nothing at all
    what happened     → her words
    how I felt before → her words / a State dimension
    how I felt after  → her words / a State dimension
    what I wanted     → her words
    what I did        → her words
    did I feel respected?
    what I want next  → her words
```

Every field is **hers**. Not one is a conclusion. And an observation may relate
to nothing — she can simply record a day.

### What this gives the future model

An AI working over this can only ever surface patterns **in her own
experience**, because that is the only thing in the database:

> *"You have written three times this month that you felt smaller afterwards.
> Would you like to look at what you noticed?"*

It cannot say *"he is bad for you"* — not because we forbade the sentence, but
because **nothing in the data supports it.** Safety by construction rather than
by policy, which is the only kind that survives a model change.

### What must be recorded now

To be useful later without being dangerous later:

| Record | Why it matters to the model |
|---|---|
| **Timestamp** | pattern requires sequence |
| **Before and after** | the delta is the signal, not the absolute |
| **Her exact words** | never a summary — a summary is an interpretation, made once and frozen |
| **What she wanted vs. what she did** | the gap is where help lives |
| **Provenance** | `stated` — always, for observations |
| **Relation** | to a Person or Area, optional |

| Never record | Why |
|---|---|
| A trait attributed to a person | Creates the dataset that must not exist |
| A score, rating or classification of anyone | Same |
| A derived summary stored *as* the record | Freezes an interpretation as fact |
| Anything about a third party they did not consent to | They are a data subject too |

---

## 5. Permission is per-category and per-connection

Defaults are **nothing**. Every permission is granted individually, revoked
individually, and **revocation is invisible**.

| Category | Example | Default |
|---|---|---|
| Care signals | *"she could use company"* | off |
| Dates | birthdays, anniversaries | off |
| Preferences about her | *"she prefers company to advice"* | off |
| Shared memories | a family moment | off |
| Practical facts | *"Amira is allergic to sesame"* | off |
| **Her state** | — | **does not exist as a category** |
| **Her journal** | — | **does not exist as a category** |
| **Her location** | — | **does not exist as a category** |

The last three are absent from the permission model entirely. Not "off by
default" — **not expressible**. A permission that can be granted is a
permission that can be demanded.

### How invisible-off works

```
  Sharing ON   →  he receives signals she sends
  Sharing OFF  →  he receives nothing, and nothing announces it
                  no "sharing paused" badge
                  no last-seen
                  no read receipt
                  no delivery status he can check
```

His experience of *"she has stopped sharing"* must be indistinguishable from
*"she has had an ordinary week"*. Any indicator we add for his convenience is a
coercion tool, and it will be used as one.

---

## 6. The recipient side

The part with the most upside and the least risk, because none of it requires
seeing her.

**He is told how to show up:**

> *"She has had a heavy week. She usually wants company rather than advice."*
> *"Her mum's anniversary is Sunday. She found it hard last year."*
> *"She mentioned wanting to start swimming again."*

**He is helped to remember:** her dates, her preferences, the things she said
she liked. Grounded entirely in what **she** recorded and released — never
inferred from him, and never inferred about him.

**He gets no dashboard.** No history, no trend, no absence indicator, no
"last active". A moment arrives; it does not accumulate into a picture.

---

## 7. Test: does this hold across lives?

| Life | Connection | Holds? |
|---|---|---|
| 32, engineer, lives alone | sister, mum | Yes. Primitive 5 alone is valuable — reminders to call, without connecting anyone. |
| 40, mother, business owner | husband, mother, sister | Yes. *Shared Context* carries the children's dates without exposing her. |
| 68, retired | children, grandchildren | Yes. Her children get *"a call would mean a lot"* and never her health record. |
| 19, student, first flat | mum | Yes — adult↔adult. She controls every signal. |
| 15, school | guardian | **Not in scope.** Metadata only, and no care signals in the first release. |

No new primitive was required by any of them.

---

## 8. What I would build, in order

1. **Primitive 5 — care reminders to her.** No connections, no sharing, no
   consent surface. Pure value.
2. **Observation + reflection.** Hers alone. Nothing crosses. This is the
   record the future model needs, and it earns its place before any AI exists.
3. **Connection + permission, adult↔adult, one category:** dates and practical
   facts. The least sensitive thing that is genuinely useful.
4. **Care signals**, once 3 has proven the consent and revocation model in the
   wild.

Partners and minors follow only after the safety model has been exercised on
the easy case.

---

## 9. Still to decide

1. **Do care signals expire?** A signal that persists becomes a record he
   keeps. My proposal: **signals expire**, and he cannot archive them.
2. **Can he see that a signal was sent and then withdrawn?** My proposal: **no**
   — withdrawal is invisible, consistent with invisible-off.
3. **Does a Connection have a type at all?** Typing it lets safety work target
   partner connections; it also records a relationship she may not want
   recorded. My proposal: **yes, typed, and she can change or blank it.**
4. **What happens to Shared Context when a connection ends?** A shared
   anniversary after a breakup. My proposal: **each side keeps their own copy,
   neither can see the other's.**
5. **Does the recipient's minimal account get a Life Model of his own?** My
   proposal: **no** — he is a recipient, not a user, until he chooses to be one.
