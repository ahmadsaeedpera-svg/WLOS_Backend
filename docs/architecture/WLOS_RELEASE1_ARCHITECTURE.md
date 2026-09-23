# WLOS Release 1 — Architecture Definition

**Status:** architecture artifact for review. **No code, no schema, no
migrations, no API, no UI.** Nothing committed.

**Derived from** the approved product model, **not** from the Slice 1 / 2
codebase. Where the existing structure works against the model, §13 says so.

**Scope:** the **zero-connection** product. No connection subsystem, no
recipient, no shared context, no placeholder for any of it.

---

## 1. Architecture principles

Seven, each traced to a product invariant rather than to engineering taste.

| # | Principle | Comes from |
|---|---|---|
| **P1** | **Privacy class is the primary boundary.** Modules are drawn by what may cross, not by entity name. | Journal/State/Observation are `private`; Life/Memory are `releasable` |
| **P2** | **Context is computed, never stored.** No context table, no cross-request cache. | "Context is computed, never stored as truth" |
| **P3** | **Provenance is structurally unavoidable.** No write path accepts a fact without it. | "Provenance is immutable and attached to everything meaningful" |
| **P4** | **Observation cannot become assertion.** No code path writes AI output into a stated-fact store. | "`observed` never becomes `stated` without her" |
| **P5** | **Guidance returns its sources.** Output is `(content, sources[])`, never bare content. | "Why am I seeing this?" answerable everywhere |
| **P6** | **User-owned data is declared, not discovered.** Every module declares what it owns; erasure iterates the declaration. | Hard deletion must be complete and verifiable |
| **P7** | **Degrade to truth, never to plausibility.** A failed component shows less, never something invented. | "Where the platform says unknown, the screen says unknown" |

---

## 2. Bounded contexts

### The options, compared honestly

| Option | Verdict |
|---|---|
| **Separate services** | **Rejected.** No independent scaling need, no team boundary requiring it, and it makes the deletion promise *harder* — erasure would need distributed coordination across services. Splitting for conceptual tidiness would trade a product guarantee for an org chart we do not have. |
| **Layered monolith** *(current)* | **Rejected as the primary structure.** Layers organise by technical concern — controller, handler, repository — so every handler lives in one assembly and anything may call anything. **The model's most important invariant, "journal never crosses", would be enforced by discipline alone.** See §13 R1. |
| **Vertical slices** | **Adopted, but inside modules.** A slice is how one capability is written; it is not a boundary. |
| **Modular monolith** | **Adopted.** Modules = bounded contexts, with compile-time-enforced boundaries and explicit public contracts. One deployable, one database, one transaction scope — and a barrier where the product model requires one. |

### The modules

```
  ┌────────────────────────────────────────────────────────────┐
  │  IDENTITY          account · session · erasure orchestration│
  ├────────────────────────────────────────────────────────────┤
  │  CATALOGUE         operator-owned vocabulary (no user data) │
  ├────────────────────────────────────────────────────────────┤
  │  LIFE RECORD       areas · people · relationships · events  │
  │                    goals · habits · memories                │
  │                    ── releasable ──                         │
  ├────────────────────────────────────────────────────────────┤
  │  INTERIORITY       journal · state · observation            │
  │                    ── PRIVATE. One outbound operation. ──   │
  ├────────────────────────────────────────────────────────────┤
  │  SIGNALS           patterns (decaying, never facts)         │
  ├────────────────────────────────────────────────────────────┤
  │  GOVERNANCE        preferences · boundaries · provenance    │
  │                    rules · audit                            │
  ├────────────────────────────────────────────────────────────┤
  │  CONTEXT           stateless assembly. Reads, never writes. │
  ├────────────────────────────────────────────────────────────┤
  │  GUIDANCE          what to say, with sources. Stateless.    │
  ├────────────────────────────────────────────────────────────┤
  │  DELIVERY          reminders · scheduling · notification    │
  └────────────────────────────────────────────────────────────┘
```

**Why Life Record is one module, not four.** Areas, people, events, goals,
habits and memories share a privacy class, a lifecycle and an owner, and they
reference each other constantly. Splitting them would create chatty
cross-module calls for no isolation benefit. **Granularity follows P1, not
vocabulary.**

**Why Interiority is separate.** Journal, state and observation are the only
`private` content. A separate module means the Context module *cannot compile*
a call into journal storage — the boundary is a build error, not a code review.

**Why Signals is separate from Life Record.** A pattern must never sit in the
same store as a fact, or one query away from being read as one. Physical
separation makes P4 checkable.

**Why Catalogue is separate.** It is operator-owned. The admin surface reaches
Catalogue and **has no reference to any user-data module** — the Slice 1
principle (operators configure vocabulary, never content) becomes structural.

---

## 3. Ownership boundaries

| Capability | Source of truth | Owner | Privacy | May become Context? | May influence Guidance? |
|---|---|---|---|---|---|
| Account, session | Identity | platform | system | no | no |
| Area types, state dimensions, boundary subjects, templates, copy | Catalogue | **operator** | system | yes (vocabulary) | yes (as vocabulary) |
| Life Areas, People, Relationships | Life Record | **her** | releasable | yes | yes |
| Events, Goals, Habits | Life Record | **her** | releasable | yes | yes |
| Memory | Life Record | **her** | releasable | yes | yes |
| **Journal** | Interiority | **her** | **private** | **no** | **no** |
| **State** | Interiority | **her** | **private** | yes — **to her own surfaces only** | yes — **to her only** |
| **Observation** | Interiority | **her** | **private** | yes — **to her own reflection only** | yes — **to her only** |
| **Pattern** | Signals | WLOS | private, decays | **no** — may only produce *one question to her* | **no** |
| Preferences, Boundaries | Governance | **her** | releasable / private | yes | yes — Boundary as a veto |
| Context | *(none — computed)* | — | private | — | yes |
| Guidance | *(none — computed)* | — | private | no | — |
| Reminders | Delivery | **her** | private | no | no |

### The five that must never collapse

```
  JOURNAL    what she wrote            private, never input to anything
     │       ── one narrow crossing: she confirms a fact ──
     ▼
  MEMORY     what she asked us to hold  durable, feeds context
     │
     ▼
  CONTEXT    what is true now           computed per request, discarded
     │
     ▼
  GUIDANCE   what to say                stateless, carries its sources

  PATTERN    what we noticed            isolated. Produces a question, never
                                        an input to any of the above.
```

**Interiority exposes exactly one outbound operation:**
`ConfirmMemoryFromEntry(entryId, extractedFact, userConfirmation)`.

It requires a user-confirmation record, it emits a Memory with provenance
`confirmed` and a source reference, and **the entry text does not travel with
it.** There is no other way journal content leaves the module — and because
Interiority is a separate module with no other public read for its text, that
is enforced by the compiler rather than by review.

---

## 4. Provenance through transformations

Provenance is a **property of every fact-carrying write**, not a column someone
remembers to set.

```
  Journal Entry            provenance: stated      (her words)
        │
        │  WLOS proposes a fact  ──►  proposal carries provenance: observed
        │
   she confirms
        ▼
  Memory                   provenance: confirmed
                           source: entry#, confirmation#
        │
        ▼
  Context                  provenance: derived
                           sources: [memory#, event#, preference#]
        │
        ▼
  Guidance                 provenance: derived
                           sources: [context inputs, verbatim]
```

**Structural rules:**

| Rule | Mechanism |
|---|---|
| No fact without provenance | Write contracts take provenance as a **required** argument; there is no defaulting overload |
| Provenance is immutable | No update path exposes it |
| `observed` cannot be written to a fact store | Life Record write contracts **accept only** `stated`, `confirmed`, `imported`. `observed` is not in the accepted set — a compile error, not a validation failure. |
| Derived output must list sources | Context and Guidance return `(value, sources[])`; there is no constructor without sources |

**This is P3 and P4 made unavoidable rather than instructed.**

---

## 5. Privacy architecture

### Erasure (P6)

Every module declares its user-owned data. Erasure iterates the declarations;
a conformance test proves the declarations are complete.

```
  ErasureRegistry
    Identity      → account, sessions, revocation tombstone
    Life Record   → areas, people, relationships, events, goals, habits, memories
    Interiority   → journal, state, observation
    Signals       → patterns
    Governance    → preferences, boundaries, her audit rows
    Delivery      → reminders, schedules
```

**Conformance test:** after erasing a test account, sweep **every** store for
the identifier. Anything found that is not a declared tombstone fails the
build. This elevates the Slice 1 sweep from a test to an architectural
mechanism, and it is what makes a module that adds a store fail rather than
quietly survive erasure.

### Leak surfaces

Sensitive data must not escape through side channels. Each gets a structural
control, not a guideline:

| Surface | Control |
|---|---|
| **Logs** | Request/response bodies are never logged (existing rule). Interiority module logs **identifiers only** — a logger that can accept its content types does not exist |
| **Telemetry / analytics** | Closed allowlist of opaque event names, runtime screening of keys and values (built, Slice 1) |
| **Error messages** | Generic mapped text; never a raw store error |
| **Admin tools** | **Catalogue module has no reference to any user-data module.** Structural, not policy |
| **API responses** | Contracts are explicit records; no pass-through of internal shapes |
| **Search** | Interiority is searchable **only within her own session**, never by an operator surface |
| **Caches** | Context is never cached beyond a request (P2). Nothing else caches user content |
| **Notifications** | Delivery receives a **rendered string plus a route**, never the underlying record |
| **Crash reports** | Scrubbed (built) |

### Explainability

> *"I suggested this because…"*

Guidance carries `sources[]` — typed references with provenance. The answer to
*"why?"* is a projection of that list into her language, **never a second
generated explanation.** A generated rationalisation would be a plausible story
about a decision rather than the decision's actual inputs.

---

## 6. AI boundaries

"AI" is not one service. Six distinct things, with different permissions.

| Layer | What it is | May read | May write |
|---|---|---|---|
| **Deterministic rules** | Catalogue-configured logic | Life Record, Governance, Catalogue | proposals only |
| **User-authored facts** | What she typed | — | she writes |
| **Confirmed memory** | What she approved | — | via confirmation only |
| **Pattern observation** | Statistical noticing | Life Record, Interiority *(counts and shape, not content)* | **Signals only** |
| **Context assembly** | Deterministic gather | permitted sources | **nothing** |
| **AI interpretation / generation** | Language | **Context output only** | **nothing durable** |

### The three hard boundaries

**B1 — AI reads Context, never stores.** The generation layer is handed an
assembled context and produces language. It has no repository access at all.
This means every restriction applied during assembly automatically applies to
AI, without AI needing to know the rules.

**B2 — AI output is never durable.** It is ephemeral guidance, or a
**proposal** requiring confirmation. There is no path from a generated string
to a fact store.

**B3 — AI output is never shareable.** Release 1 has no sharing, and the
constraint is recorded now so the connection subsystem inherits it: *Suggest
Care may only use explicitly released facts.*

### Where AI is prohibited

Inferring state from her writing · inferring age · inferring any of the seven
sensitive subjects · attributing traits to a person · producing a verdict about
a relationship · generating an explanation in place of real sources ·
determining her life stage or her world.

---

## 7. Today / Context architecture

**Today is a projection. There is no Today store.**

```
  Life Record ─┐
  Interiority ─┤   (hers only)
  Governance  ─┼──►  CONTEXT ASSEMBLY  ──►  GUIDANCE  ──►  Today
  Catalogue   ─┤      stateless              stateless
  Signals     ─┘      per request            + sources[]
      │
      └── contributes at most ONE question, never an input
```

**Assembly is a pure function** of (her data, her governance, the catalogue,
now). It:

- reads through **read-only** module contracts
- applies Boundary as a **veto before** anything is gathered, not as a filter
  after — a closed boundary means the data is never read, so it cannot leak
  through a bug in a later filter
- returns values **with their sources**
- persists nothing

**Caching:** request-scoped only. A cross-request cache would be a stored
context wearing a performance justification, and it would go stale silently —
the exact failure P2 exists to prevent.

**Where the budget goes:** assembly touches several modules per request. In one
database with one connection this is joins, not network calls. If it becomes
slow, the answer is narrowing what Today asks for — **not** caching the answer.

---

## 8. Notification and action architecture

**Delivery knows nothing about her.**

```
  GUIDANCE  ──►  (rendered text, route, when)  ──►  DELIVERY  ──►  device
```

Delivery receives a **rendered string**, never a record, never an identifier it
could resolve. A notification payload that contained a memory id would be a
memory on a lock screen.

| Rule | Why |
|---|---|
| Content is rendered **before** it reaches Delivery | Nothing sensitive sits in a queue |
| A reminder that fails **retries silently**, never duplicates | Two identical nudges read as nagging |
| A Boundary closed since scheduling **cancels delivery** | Boundary is a veto at send time, not only at creation |
| Declined reminders do not re-present | Product invariant 18 |
| Nothing is delivered that she has not seen the shape of | Invariant 16, applied to her own surfaces |

**Actions** in Release 1 are limited to: create/modify her own records, schedule
a reminder, confirm a proposal, decline. Every action traces to a user act, and
every action is reversible or confirmable **before** it happens.

---

## 9. Deletion and export architecture

| | |
|---|---|
| **Deletion** | Identity orchestrates; each module erases what it declared; conformance test sweeps everything (§5). Two honest survivors: the erasure tombstone, and — **when connections exist** — copies other people hold. Not applicable in Release 1. |
| **Export** | The same registry, read instead of deleted. **Her journal exports as she wrote it**, never summarised. Export includes **provenance**, so she can see what she said versus what WLOS derived. |
| **Correction** | Every stated fact is editable. Correcting a fact **invalidates derived context automatically**, because context is never stored (P2). This is a direct dividend of that decision. |

---

## 10. Future-extension boundaries

Clean seams, **no infrastructure built for hypotheticals**.

| Future | The seam that already exists | Built now? |
|---|---|---|
| Connections | Life Record and Memory are `releasable` — a release operation attaches later at the module contract | **No** |
| Recipient experience | A separate module, added later | **No** |
| Younger worlds | Catalogue is already world-dimensioned in the product model; **the connection model must never be copied** | **No** |
| More life stages, more area types | Catalogue rows | Configuration, not code |
| More guidance systems | Guidance is stateless and source-carrying; a second one plugs into the same contract | **No** |

**What "no placeholder" means here:** no `ConnectionId` column, no `shared`
flag, no `recipient` enum value, no interface with one implementation awaiting
a second. A seam is *the absence of an obstacle*, not the presence of a stub.

---

## 11. Five-life validation

| | 19 student | 28 engineer | 40 mother + owner | 55 doctor | 70 retired |
|---|---|---|---|---|---|
| Modules used | all | all | all | all | all |
| Module unique to her | **none** | **none** | **none** | **none** | **none** |
| Special service needed | **none** | **none** | **none** | **none** | **none** |
| Catalogue rows differ | yes | yes | yes | yes | yes |
| **Code differs** | **no** | **no** | **no** | **no** | **no** |

**No `StudentService`, `MotherService`, `RetirementService`.** Every life is the
same modules over different Catalogue rows and different user content. The
difference between a nineteen-year-old and a seventy-year-old is **data**, and
architecture that made it code would be the failure.

**Probe:** the 70-year-old's medication reminder is a Habit with a schedule
plus a Delivery entry — the same path as the student's revision reminder. The
*clinical safety* question about medication is a product decision, and it
correctly changes **nothing** structurally.

---

## 12. Zero-connection validation

```
  Capture     Life Record · Interiority              ✓ no connection
  Remember    Memory                                 ✓
  Understand  Context assembly                       ✓
  Reflect     Observation + Signals → one question   ✓
  Plan        Goals · Habits                         ✓
  Act         Delivery · Actions                     ✓
  Learn       Confirmed memory feeds context         ✓
  Improve     Behaviour change over time             ✓
```

**The complete loop closes inside her own WLOS.** No module in §2 requires a
second person to exist. **No connection module is present in Release 1 at all**
— not disabled, not feature-flagged: absent.

**Verdict: passes.**

---

## 13. Architecture risks

| | Risk | Mitigation |
|---|---|---|
| **R1** | **The existing single `Maren.Application` assembly.** Every handler lives together; a future Context handler could call Journal storage directly and nothing would stop it. **This is the highest architectural risk and it comes from the existing code, not the model.** | Modules as **separate projects**, plus an **architecture fitness test** that fails the build on a forbidden reference. The codebase already enforces rules by test (audit contract, password material) — this is the same pattern applied to module boundaries. |
| **R2** | Context assembly latency — touches several modules per request | One database, joins not network calls. If slow, narrow the request, never cache the answer |
| **R3** | Provenance forgotten on a new write path | Required constructor argument; no defaulting overload |
| **R4** | A new module forgets to declare user-owned data | Erasure conformance sweep fails the build |
| **R5** | Pattern read as fact by a future feature | Physical store separation + `observed` not accepted by fact-store contracts |
| **R6** | Admin tooling reaching user content | Catalogue module has **no reference** to user-data modules |
| **R7** | Sensitive content in a notification payload | Delivery accepts rendered text only; it has no type that could carry a record |
| **R8** | Over-modularisation — boundaries nobody needs | Life Record deliberately kept whole; granularity follows privacy class (P1) |

### Failure behaviour (P7)

| Failure | Behaviour |
|---|---|
| **AI unavailable** | Today renders from deterministic sources. Language is plainer. **Nothing is invented and no card is faked.** |
| **Context assembly fails** | She sees her own raw records — her events, her goals. **Never a guess, never an empty screen pretending nothing exists.** |
| **A single module fails** | Its section is absent and **says it is unavailable**. Other sections render. |
| **Notification delivery fails** | Silent retry with backoff. **Never a duplicate.** |
| **Catalogue unavailable** | Last known catalogue; her own data always renders. |
| **Signals unavailable** | No reflection question. **Nothing else is affected** — proof the module is genuinely peripheral. |

**The rule: degrade to less, never to plausible.**

---

## 14. Architecture decisions

| | Decision | Rationale |
|---|---|---|
| **AD1** | **Modular monolith**, modules = bounded contexts | Boundaries where the model needs them; erasure stays a single transaction |
| **AD2** | **Vertical slices inside modules** | A slice is how a capability is written, not a boundary |
| **AD3** | **Modules are separate projects with enforced references** | Makes the journal boundary a build error (R1) |
| **AD4** | **One database** | Erasure completeness and referential integrity are product promises |
| **AD5** | **Rules stay in the database** *(existing platform rule retained)* | Every client obeys them, not only this API — and the age gate already proved the pattern |
| **AD6** | **Context is stateless, request-scoped** | P2 |
| **AD7** | **Guidance returns `(content, sources[])`** | P5 — explainability cannot be retrofitted |
| **AD8** | **Erasure registry + conformance sweep** | P6 |
| **AD9** | **AI reads Context only, writes nothing durable** | B1, B2 — restrictions apply automatically |
| **AD10** | **Delivery receives rendered text only** | No sensitive payload in a queue or on a lock screen |
| **AD11** | **Boundary is a veto before read, not a filter after** | A filter can be bypassed by a bug; an ungathered read cannot leak |
| **AD12** | **No connection infrastructure of any kind in Release 1** | Zero-connection principle; no stubs |

---

## 15. Open decisions

Genuine blockers for **detailed technical design**, not for this architecture.

| | Decision | Why it matters |
|---|---|---|
| **O1** | **Does journal text live in the same database?** Separate store, separate key, or same store with column encryption. | The single largest privacy-posture decision remaining. Affects backup, export, erasure and operator access. |
| **O2** | **Per-user encryption keys?** | Strong protection; complicates search, export and support. Needs a deliberate answer, not a default. |
| **O3** | **Where does AI run — on device or server?** | If server-side over her journal, her most private content leaves the device. Materially changes the privacy claim and the Data Safety declaration. **Recommend deciding before any AI work.** |
| **O4** | **Does journal sync at all, or stay device-local?** | Server-backed was decided for the product; journal may warrant an exception. Interacts with O1–O3. |
| **O5** | **Context assembly latency budget** | Sets how much Today may ask for. |
| **O6** | **Offline write model** | Which modules accept offline writes and how they reconcile. |

**Deliberately not decided here** (§12 of the brief): schema, table names,
procedures, routes, widgets, components, cloud provider, deployment topology.

---

## 16. Verdict

> ### Is the Release 1 architecture stable enough to begin detailed technical design?
>
> ## **Yes.**

The boundaries are derived from product invariants rather than from
convenience, every invariant has a structural mechanism rather than a
convention, and the five-life and zero-connection validations both pass with no
special-casing.

**Two things I want on the record:**

**1. The largest risk is the existing codebase, not the model (R1).** The
current single `Maren.Application` assembly would leave the model's most
important invariant — *journal never crosses* — enforced by discipline alone.
AD3 addresses it, and it means Release 1 restructures modules rather than
adding to the existing layering. That is a real cost and I would rather name it
than discover it.

**2. O3 — where AI runs — should be decided early.** It is listed as a detailed
design decision, but it determines a public privacy claim, and retrofitting
on-device inference after a server-side implementation is close to a rewrite.

**Stopping here.** No detailed design in this document.
