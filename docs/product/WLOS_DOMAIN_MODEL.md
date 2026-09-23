# WLOS Core Life Model + Care & Connection Model

**Status:** domain model for review. **No code, no schema, no API, no UI.**
Supersedes and consolidates `WLOS_LIFE_MODEL_PROPOSAL.md`,
`WLOS_CARE_AND_CONNECTION.md` and `WLOS_WORLDS.md`.

**Launch scope: 18+. The age gate is unchanged and is not lowered here.**
§12 validates that the model *could* extend to a younger world later. That is
a flexibility check, not a plan.

---

## 1. The four systems

```
                              WLOS
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
      HER LIFE             HER GROWTH            HER CARE
   what exists          who she is becoming    ├── care for self
          │                    │               └── care for others
          └────────────────────┼────────────────────┘
                               │
                        HER CONNECTIONS
                     relationship-care, not social
                               │
                    ┌──────────┴──────────┐
                 PRIVATE                SHARED
            journal · memory ·     care signals ·
            state · observation    shared context
                    └──────────┬──────────┘
                               │
                       CONTEXT + MEMORY
                               │
                      GUIDANCE + ACTION
```

**Care is first-class.** It is not a feature hanging off Relationships. A
relationship system with notifications bolted on is a contact list; Care is the
thing WLOS is actually for, and it exists in two directions — toward herself
and toward the people she loves. **Most care requires no connection at all.**

### The two constitutional principles

> **WLOS should make her better at loving people — not make her legible to
> them.**

> **WLOS helps her care for herself and helps the people she loves care for
> her — while preserving her private inner world.**

Every concept below was tested against both. Three failed and are listed in
§14 as dangerous.

---

## 2. Concept catalogue

**Privacy class** is the load-bearing column:

- `private` — never crosses a boundary, under any permission
- `releasable` — may cross **only** by an explicit act, per instance
- `relational` — exists *between* two parties by nature
- `system` — infrastructure; she sees it, it is not content

| Concept | Owner | Privacy | Mutable | Expires | Can cause | Must never imply |
|---|---|---|---|---|---|---|
| **World** | platform | system | by age band only | no | which catalogue applies | anything about who she is |
| **Life Stage** | her | releasable | yes, with history | no | capabilities offered | a change in what WLOS believes |
| **Life Area Type** | operator | system | yes | no | what an area can hold | that her life fits a category |
| **Life Area** | her | releasable | yes | archivable | grouping, suggestions | importance or priority |
| **Person** | her | releasable | yes | no | relationships, areas | that they are a WLOS user |
| **Relationship** | her | releasable | yes | yes | tone, reminders | access of any kind |
| **Event** | her | releasable | yes | past | reminders, context | attendance or obligation |
| **Goal** | her | releasable | yes | yes | plans, prompts | failure when unmet |
| **Habit / Behaviour** | her | releasable | yes | yes | reminders, reflection | a streak or a score |
| **Journal** | her | **private** | editable | no | *(nothing, unless she lifts from it)* | that WLOS has read it as data |
| **Memory** | her | releasable | yes | only if she says | recall, context | that it was taken |
| **State** | her | **private** | per entry | no | prompts to *her* | a mood score, a trend, a diagnosis |
| **Observation** | her | **private** | yes | no | reflection offered to *her* | a claim about another person |
| **Pattern** | WLOS | **private** | recomputed | **yes, decays** | one question to her | a fact, a verdict, a diagnosis |
| **Preference** | her | releasable | yes | no | manner, tone | a rule that overrides a Boundary |
| **Boundary** | her | **private** | yes | no | refusal | anything negotiable |
| **Context** | WLOS | **private, never stored** | recomputed | per request | what is shown now | a stored belief about her |
| **Care** | — | — | — | — | *the purpose* | a duty or an obligation |
| **Connection** | both | relational | yes | yes | permissions may exist | that permissions exist |
| **Permission** | her | relational | yes | yes | one category may cross | that more may follow |
| **Recipient** | himself | system | — | on exit | receiving | a view of her |
| **Care Signal** | her | relational | no, once sent | **yes** | a care action | an ongoing state |
| **Care Request** | her | relational | withdrawable | yes | a care action | that refusal is failure |
| **Care Reminder** | WLOS | **private to her** | — | yes | her own action | that anyone is watching |
| **Shared Context** | both | relational | by either | on exit | recall for both | access to anything else |
| **Care Action** | recipient | relational | — | — | a response | a report back on her |
| **Provenance** | system | attached | **no** | no | what may be acted on | that all facts are equal |

### Four that carry the most weight

**Journal — `private`, absolutely.** It has no permission category, no share
action, no "summarise for" option. A connection cannot open it. The only way
anything leaves a journal entry is that **she** lifts one fact out and confirms
it as a Memory. The entry itself never moves.

**State — `private`.** She states it; WLOS never reads it from her writing, her
typing, her hours or her face. There is no "state" permission category. What
crosses is a Care Signal **she composed**, never her state.

**Context — computed, never stored.** The moment it persists it becomes a
belief about her that can go stale silently. It is assembled per request and
discarded.

**Pattern — decays.** The only concept that expires by design. An unconfirmed
pattern is a question, asked at most once, that goes quiet. It can never
promote itself to a fact, whatever the evidence.

---

## 3. The distinctions that must not collapse

```
  Person          Amira                   a human being
     ↓
  Relationship    "my daughter"           who she is to me
     ↓
  Life Area       "Amira's school"        context I keep about part of my life
                  "Me and Amira"          — and I may keep more than one
     ↓
  Connection      Amira's WLOS link       how we are connected in WLOS
     ↓
  Permission      dates + practical facts what may cross, per category
     ↓
  Shared Context  "her sports day matters to her"
     ↓
  Care Action     "remind me the week before"
```

**Separately, and never touching any of the above:**

```
  Journal         "I've been exhausted lately."        PRIVATE
```

Being connected to her mother does not make that entry visible. Nothing does.

| Pair | The difference |
|---|---|
| Person / Life Area | A person is a person. An area is *her context around part of her life*. One person → zero, one or several areas. |
| Relationship / Connection | *Who they are to me* vs *how we are linked in WLOS*. **A relationship never implies a connection**, and a connection never implies a permission. |
| Connection / Permission | *We are connected* vs *this specific thing may cross, under these conditions*. Connecting grants nothing. |
| Journal / Memory | What she wrote vs what she asked WLOS to hold. Extraction **requires confirmation**, always. |
| Memory / Context | Durable vs relevant-now. Context is assembled from memory; memory is never assembled from context. |
| Fact / Pattern | A pattern is never a fact. Repetition is not evidence of a verdict. |

**No `MotherEntity`, `StudentEntity`, `PartnerEntity`, `RetiredEntity`.**
Different lives are represented by composition — §11 tests this.

---

## 4. Care is not sharing

The most common way this product could go wrong is modelling care as
`A → shares → B`. That is a data pipe with a warm name.

```
        HER PRIVATE CONTEXT
                 │
      user-controlled selection        ← she chooses: who, what, this once
                 │
           CARE INTENT                 ← composed, previewed, approved
                 │
     ═══════════ BOUNDARY ═══════════
                 │
     Care Signal │ Care Request │ Shared Context
                 │
            RECIPIENT
                 │
            CARE ACTION                ← what he can actually do
```

**Most care never reaches this diagram.** Care for herself, and care reminders
pointed at her, involve no connection, no recipient and no boundary crossing.
That is the majority of the product and it must stay the majority.

---

## 5. The primitives — challenged

You asked me not to assume the list is right. It is nearly right; **three gaps
and one hazard.**

### The five, as given

| | Primitive | Direction | Needs connection? |
|---|---|---|---|
| 1 | **Share** — *"I want you to know this"* | her → him | yes |
| 2 | **Ask for Care** — *"I could use support"* | her → him | yes |
| 3 | **Suggest Care** — *"she may appreciate this"* | WLOS → him | yes |
| 4 | **Remember Together** — a date, a memory | mutual | yes |
| 5 | **Care Reminder** — *"you haven't called your mum"* | WLOS → **her** | **no** |

### ▸ Gap 1 — Respond is missing

Nothing returns. She asks her partner for support and never learns whether
anything happened. A care system where care disappears into silence teaches her
not to ask.

**Proposed primitive 6 — Respond.** *He* chooses to send something back: a
message, an acknowledgement, a thing he did. It is **his** act, so it is not a
read receipt and not a tracking signal. Crucially it is **optional on his
side** — she must never see "delivered", "seen" or "ignored", because those
turn his silence into data about him and her checking into anxiety.

### ▸ Gap 2 — Decline is missing

She receives a suggestion, a reminder, a care action. Can she say *"not now"*
in a way that is **respected and remembered**? Without it, WLOS nags, and a
nagging care system is the thing people uninstall.

**Proposed primitive 7 — Decline.** Applies to WLOS's own prompts and to
incoming care. Declining is not a rejection event and is **never** reported to
the other side.

### ▸ Gap 3 — Care *about a third person* is missing

Two sisters caring for the same mother. This is one of the most common care
situations in real life and no primitive covers it: it is not Share (the
subject is not her), not Suggest (the beneficiary is not the recipient).

**Proposed primitive 8 — Coordinate.** *"Can you check on Mum this week?"*

**But it carries a hazard I cannot resolve here:** Mum is a third party who has
consented to nothing, and coordination means two people exchanging information
about her. My recommendation is **defer it** — it is valuable, it is real, and
it needs its own consent model. Listed in §14 as ambiguous.

### ▸ Hazard — "Suggest Care" is the one that can leak

Primitive 3 is WLOS speaking to him, generated from *her* context. If it may
draw on anything she has not explicitly released, inference has crossed the
boundary wearing a helpful face.

**Constraint: Suggest Care may only use facts she has explicitly released.**
Never a pattern, never a state, never a journal entry, never a derivation. If
WLOS cannot name the released fact a suggestion came from, the suggestion must
not be made.

### Revised set

**Her-side, no connection:** Care Reminder · Decline
**Her → him:** Share · Ask for Care · *(Coordinate — deferred)*
**Him-side:** Care Action · Respond · Decline
**WLOS → him, constrained:** Suggest Care
**Mutual:** Remember Together

---

## 6. The recipient experience

Four categories of information. **Only two may ever cross.**

| Category | Example | Crosses? |
|---|---|---|
| **Raw private** | her journal, her state, her observations | **Never** |
| **Explicitly shared** | *"I've had a difficult week"* — her words, released by her | Yes |
| **Care translation** | *"She may appreciate kindness and company more than advice"* | Yes — **if she previews and approves it** |
| **AI inference** | *"She has been low for four days"*, a mood score, a trend | **Never** |

**Care translation is the interesting one.** It is WLOS rewording what she
released into something actionable. It is only safe under two conditions:

1. **She sees the exact words he will see, before he sees them.**
2. **It adds no fact she did not release.** Rewording is allowed; adding is not.

```
  SHE RELEASES        "I've had a difficult week."
         │
  WLOS TRANSLATES     "She has had a difficult week. She may appreciate
         │             kindness and company more than advice right now."
         │             ← the second sentence comes from a RELEASED preference,
         │               not from an inference about her mood
         ▼
  SHE APPROVES  ──►  he receives exactly that
```

**What he never gets:** a dashboard, a history, a trend, a last-active, an
absence indicator, a score, a diagnosis, or anything he can query.
A moment arrives. It does not accumulate into a picture.

---

## 7. The privacy boundary — semantics

| Question | Answer |
|---|---|
| Can she leave a connection without a conversation? | **Yes.** Required. Leaving is silent and needs no reason. |
| Can he request access? | **No.** There is no request mechanism — a request is pressure, and pressure is the coercion. He may not even see what categories exist. |
| Can he pull, or only she push? | **Only she pushes.** Nothing is readable on demand. This is the difference between care and monitoring. |
| Can she revoke one permission without ending the relationship? | **Yes**, per category, and he is not told. |
| What happens to what was already delivered? | It was read. We cannot unring it. WLOS **expires its own copies** and he cannot archive or export them — but **we must not claim recall we cannot deliver.** Screenshots exist. |
| Can he retain history? | **No.** Signals expire; WLOS keeps no timeline on his side. |
| Can shared information be copied? | Within WLOS, no. Outside it, we cannot prevent it and must say so plainly. |
| What does *revoked* mean? | **(a)** nothing further crosses · **(b)** WLOS expires its held copies · **(c)** **he is not notified** · **(d)** no indicator changes on his side. |

### Invisible-off, as a first-class requirement

```
  Sharing ON   →  signals arrive when she sends them
  Sharing OFF  →  nothing arrives, and nothing announces it

  NO paused badge · NO last-seen · NO delivery status
  NO read receipt · NO "she used to share this"
```

**His experience of *"she stopped"* must be indistinguishable from *"she had an
ordinary week"*.** Any indicator added for his convenience becomes a coercion
tool and will be used as one.

This is why there is no *"sharing paused"* state in the product: a state that
can be displayed is a state that can be demanded.

---

## 8. Reciprocal and asymmetric care

**Connections need not be symmetrical.** Forcing symmetry would mean a daughter
who wants to send care to her mother must accept receiving from her.

| Shape | Example | Supported |
|---|---|---|
| One-way outbound | she sends to her mother; receives nothing | yes |
| One-way inbound | her sister may send her care; she sends none | yes |
| Mutual | both send | yes |
| Temporary | during an illness, an exam period | yes — connections may expire |
| Dormant | connected, no permissions | yes — the normal resting state |

**Each direction is permissioned independently.** Granting outbound grants
nothing inbound.

**Invisible-off is the one thing that must be symmetrical.** Both sides can go
quiet without the other detecting it.

No hard-coded mother/father/sister/partner systems. A Relationship carries a
**type** used for tone and for targeting safety work — never for capability.

---

## 9. Partner connections — scrutiny

Not removed from the vision. Tested against the failure modes.

| Risk | What in the model prevents it |
|---|---|
| Monitoring | Pull does not exist. Nothing is readable on demand. |
| Emotional surveillance | State has no permission category. It cannot be shared. |
| Coercive expansion | Permissions are per-category and never bundled; there is no "share everything". |
| Pressure to disclose | He cannot see what categories exist, so he cannot name what she is withholding. |
| Silence read as concealment | Invisible-off. There is no signal to interpret. |
| Cannot leave privately | Leaving is silent and requires no conversation. |

**The residual risk the model cannot remove.** For a woman in a controlling
relationship, *the existence of the feature is the coercion*: *"if you have
nothing to hide, turn it on."* No consent screen fixes that.

Two mitigations, both outside the data model:
- The product must be **fully valuable with zero connections** (§15) — so
  declining to connect is not declining the product.
- Safety resources reachable **without searching**, from inside the connection
  screens themselves.

**Recommendation stands: partners are not in the first connection release.**

---

## 10. Reflection instead of verdicts

The valid problem: *a woman sometimes knows something is wrong and cannot see
the pattern.* The invalid solution: WLOS judging the person.

```
  SAFE                                     UNSAFE
  ────                                     ──────
  "You've written three times this         "He is toxic."
   month that you felt smaller
   afterwards. Would you like to           "This person is bad for you."
   look at what you noticed?"
                                           "Relationship health: 32%"
  → her words, her count, her choice       → a verdict about a human being
```

**The structural guarantee, not a copy rule:** an Observation records *her
experience* — what happened in her words, how she felt before and after, what
she wanted, what she did, whether she felt respected, what she wants next.

**There is no field in which a trait can be stored about a person.** So there
is no verdict for a model to learn, a partner to find, or a court to demand.
Safety by construction survives a model change; safety by policy does not.

---

## 11. Stress test — five lives, one model

Abbreviated; full working in the earlier drafts. **The test: no life may need
an entity of its own.**

| | 19 student | 28 engineer | 40 mother + owner | 55 doctor | 70 retired |
|---|---|---|---|---|---|
| **Areas** | Psychology · Halls · Rowing · Me | Work · Flutter · Flat · Running | The bakery · Amira's school · Me and Amira · Mum's care · Me | The practice · Mum and Dad · Menopause · Garden · Pension | Health · Medication · Choir · Allotment · My story |
| **People** | tutor · flatmate · mum | manager · partner | children · mother · two bakers | parents · colleague | children · grandchildren · GP |
| **Goals** | pass stats `binary` | promotion `qualitative` · deposit `measurable` | hire a baker `binary` | revalidation `binary` | walk daily `ongoing` · write my story |
| **Habits** | asleep by 1am | laptop off by 9 | laptop closed by 8 | strength ×2 | medication at 8 |
| **Care for others** | checks on mum | remembers partner's dates | children · mother | parents | grandchildren |
| **Connection** | mum, outbound | partner *(later)* | sister — **coordinating Mum's care** ← deferred | sibling | children, inbound |
| **Private** | journal · state · observations | same | same | same | journal · biographical memory |
| **Shared** | *"could use a call"* | dates · preferences | school dates · practical facts | appointment dates | *"a call would mean a lot"* |

**Result: no new entity types.** Every life is *Life Areas + People +
Relationships + Events + Goals + Habits + Memories + Stage + Care*.

**The 40-year-old surfaces the Coordinate gap** (§5) — two sisters, one mother.
Real, common, deferred.

---

## 12. Younger-world flexibility — validation only

**The gate is not lowered. Nothing below is a plan.**

The Life Model is reusable; the **connection model is not**.

| Layer | Reusable for a younger world? |
|---|---|
| Life Areas, People, Events, Goals, Habits, Memory, State, Observation | **Yes** — swap the catalogue |
| Preference, Boundary, Pattern, Context | **Yes** — different configured sets |
| **Connection, Permission, Care Signal** | **No.** Must be redesigned. |

**Why the connection model cannot be copied:** it rests on two adults who can
each freely decline and freely leave. A minor can do neither with a guardian.
Copying it would produce guardian monitoring with a care label — the exact
inversion of the principle.

A younger world needs its own consent, guardian, escalation and content models.
**Confirmed: the underlying life model is flexible enough. The connection model
is not, and must never be assumed to be.**

---

## 13. Journeys

| | Journey | Path | Boundary crossed? |
|---|---|---|---|
| **A** | Fix her sleep | State → Pattern → *she confirms* → Goal → Habit → reminders | none |
| **B** | Mother's birthday | Person → Relationship → Event → Memory *(what she liked last year)* → Care Reminder → Action | none |
| **C** | Ask partner for support | Journal `private` → she selects → Care Request → preview → approve → delivered | one, explicit |
| **D** | Partner receives | Care Request → translation → *"kindness and company rather than advice"* — no journal, no state, no history | — |
| **E** | Sister's exam | Memory *(her exam date)* → Care Reminder **to her** → she sends | none until she acts |
| **F** | Repeated discomfort | Observations ×3 → Pattern `private` → **one question to her** → she explores → her own conclusion | none — and **no verdict stored** |
| **G** | Revoke | Permission off → no further delivery · WLOS copies expire · **he is not told** · no indicator changes | — |
| **H** | Leave a connection | Silent · no reason · no notification · Shared Context splits, each keeps their own copy, neither sees the other's | — |

**Five of eight cross no boundary at all.** That is the correct proportion and
it is the strongest evidence the model is a care product rather than a sharing
product.

---

## 14. Status

### Approved — clear enough to proceed

World · Life Stage · Life Area Type · Life Area · Person · Relationship ·
Event · Goal · Habit · Journal · Memory · State · Observation · Pattern ·
Preference · Boundary · Context · Provenance · Care Reminder · Connection ·
Permission · Care Signal · Care Request · Care Action · Invisible-off ·
metadata-only guardian · adult↔adult first

### Ambiguous — need a decision before architecture

| | Why |
|---|---|
| **Coordinate** (primitive 8) | Real and common; involves a third party who consented to nothing |
| **Respond** (primitive 6) | Needed, but the line between *response* and *read receipt* must be drawn precisely |
| **Shared Context after exit** | Proposed: each keeps their own copy, neither sees the other's |
| **Recipient accounts** | Proposed: minimal account — a non-user receiving a stream is worse |
| **Care signal expiry** | Proposed: they expire, and he cannot archive |
| **Relationship type recorded?** | Useful for safety targeting; is itself sensitive |

### Dangerous — named so they are never built by accident

| | Becomes |
|---|---|
| Any **pull** mechanism | monitoring |
| **State** as a permission category | emotional surveillance |
| **Visible** sharing status | coercive control |
| **Traits stored about third parties** | automated judgment · a legal liability |
| **Streaks, scores, mood trends** | dependency · shame |
| A **feed** of her moments | social media |
| **Suggest Care drawing on inference** | inference laundering |
| **Care that cannot be declined** | nagging · dependency |
| Connection required for core value | **the failure in §15** |

### Open decisions

1. Do recipients need WLOS accounts? — *proposed: minimal account*
2. Are connections always mutual? — **no**, independently permissioned
3. Can recipients request access? — **no**, and this should be firm
4. Can delivered information be recalled? — **no**, and we must not claim it
5. May care suggestions be AI-generated? — **only from explicitly released facts**
6. What may become Shared Context? — *proposed: dates, practical facts, mutual memories*
7. Can she delete connection history permanently? — *proposed: yes, both sides*
8. How does connection exit work? — *silent, unilateral, no notification*
9. What do partner connections need beyond the general model? — *not in release one*
10. Minimum viable first connection? — **adult↔adult, one category: dates and practical facts**

---

## 15. The final test

> If WLOS became extremely successful, would women open it because it helps
> them live, grow, remember, care and love better — or because other people
> expect access to them?

**The model supports the first. One mechanism could flip it, and it is
structural rather than ethical.**

If the best features require a connection, social pressure does the rest.
*"Everyone's family is connected — why isn't yours?"* becomes the reason she
opens it, and at that point WLOS has become a channel through which she is
expected to be reachable.

**The defence is a product constraint, not a value statement:**

> **WLOS must be fully valuable with zero connections.**

Care reminders, goals, habits, memory, reflection, journal, growth — all of it
works alone. Connection is an addition for a woman who wants it, never the
thing that makes the product worth having.

**Concretely:** if a feature's value depends on someone else being connected,
it does not ship in release one. §13 already reflects this — five of the eight
journeys cross no boundary at all.

The test to re-run before every release:

> *Would a woman with no connections still open this tomorrow?*

If the answer ever becomes no, WLOS has become the second product.
