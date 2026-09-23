# WLOS Product Model — Architecture Readiness Review

**Purpose:** determine whether the conceptual model is stable enough to hand to
engineering. **No architecture is designed here.**

**Model approved** with: `Respond` added · `Decline` added · `Coordinate Care`
deferred · Suggest Care constrained · privacy decisions binding · zero-
connection principle binding · 18+ unchanged.

---

## A. Frozen concepts

Stable. Architecture may be derived from these without further product input.

### Life

`World` · `Life Stage` · `Life Area Type` · `Life Area` · `Person` ·
`Relationship` · `Event` · `Goal` · `Habit / Behaviour`

Settled: Type (operator) vs Instance (hers) · Person ≠ Life Area, one Person →
zero, one or many Areas · two-level nesting maximum · goal measurement optional
and never imposed · no `MotherEntity` / `StudentEntity` / `PartnerEntity` — all
lives by composition.

### Memory and interiority

`Journal` **(private, absolutely)** · `Memory` (`operational` | `biographical`)
· `State` **(private)** · `Observation` **(private)** · `Pattern`
**(private, decays)** · `Context` **(computed, never stored)**

Settled: Journal → Memory requires explicit confirmation, never silent
extraction · Observation records *her experience*, never a trait about a person
· Pattern is never a fact and cannot promote itself.

### Governance

`Preference` · `Boundary` · `Provenance`

Settled: `Safety > Boundary > Preference > Derived > Observed > Ambient` ·
provenance is immutable and attached to everything meaningful · `observed`
never becomes `stated` without her.

### Care and connection

`Care` (first-class) · `Connection` · `Permission` · `Recipient` ·
`Care Signal` · `Care Request` · `Care Reminder` · `Shared Context` ·
`Care Action` · `Respond` · `Decline`

### The seven primitives

| | Primitive | Direction | Connection needed |
|---|---|---|---|
| 1 | Share | her → him | yes |
| 2 | Ask for Care | her → him | yes |
| 3 | Suggest Care | WLOS → him *(constrained)* | yes |
| 4 | Remember Together | mutual | yes |
| 5 | Care Reminder | WLOS → **her** | **no** |
| 6 | **Respond** | him → her, voluntary | yes |
| 7 | **Decline** | either side | no |

---

## B. Deferred

**No placeholder, no schema, no API, no UI, no enum value, no "reserved for
later" column.** A deferred concept that leaves a stub in the model is a
concept that gets built by accident.

| Deferred | Why |
|---|---|
| **Coordinate Care / third-person care** | The person being cared for is a third party who consented to nothing. Needs its own consent and ownership model. |
| **Younger-user connection model** | **Permanent constraint: the adult connection model must never be copied to minors.** It rests on two adults who can each freely decline and freely leave; a minor can do neither with a guardian. |
| **Partner connections** | Not in release one. Model supports them; the safety model is exercised on the easy case first. |
| **Recipient full accounts** | A recipient holds a minimal account. Whether he becomes a full WLOS user is his own decision, separately. |
| **Layers 7–8 (Intelligence, Actions)** | Sketched only far enough to keep Layers 2 and 5 honest. |
| **Conversation / AI companion** | One interface to intelligence, never the product. Modelling it now would pull the data model toward a chat log. |

---

## C. Remaining decisions that genuinely block architecture

Five. Each blocks a structural choice, not a detail. I am not reopening settled
questions — **three of these are contradictions discovered during this review.**

### C1 — Connection exit: what does he eventually see? ▸ *contradiction*

Exit is silent and unilateral. But consider the sequence:

```
  she leaves the connection
        │
  he sends a Respond to an earlier signal
        │
        ?
```

| Option | Problem |
|---|---|
| Appears to send, goes nowhere | Dishonest to him; he waits for an answer that cannot come |
| Error / "no longer connected" | Reveals she left, and roughly when — **breaks invisible exit** |
| Silently discarded forever | Same dishonesty, permanently |

**Proposal:** the connection **disappears from his side after a delay**, with
no reason, no timestamp and no correlation to anything she did. He learns the
connection ended; he cannot learn *when she decided* or *what triggered it*.
Decoupling the *fact* from the *moment* is what preserves her safety while not
deceiving him indefinitely.

**Blocks:** whether connection state is one shared record or two independent
per-side records. That is a foundational choice.

### C2 — Shared Context and account deletion ▸ *contradiction*

Slice 1 hard-deletes **everything belonging to her**. `Shared Context` is held
by both parties by design. Her mother's copy is **her mother's data** — WLOS
cannot delete another user's records as part of her erasure.

So *"deletion means deletion"* and *"Shared Context is mutual"* cannot both be
absolutely true.

**Proposal:** Shared Context is **two copies from the moment of creation**, not
one shared row. Her deletion removes hers entirely. Her mother keeps her own,
which after erasure refers to an identifier resolving to nothing.

**This changes what we may honestly promise.** The deletion copy must say:
*"Anything you chose to share with someone stays with them."* Saying "we delete
everything" while another person holds a copy would be the same class of
dishonesty as claiming revocation recalls what was read.

**Blocks:** the erasure cascade, and the deletion copy.

### C3 — Recipient account lifecycle

A minimal account exists because she connected him. If she deletes her account
and he is connected to no one else, does his account remain?

**Proposal:** a recipient account with zero remaining connections is **dormant
for a defined window, then erased**. He may convert to a full WLOS account at
any point before that, at which point he owns it outright.

**Blocks:** recipient identity, and whether recipient erasure is automatic.

### C4 — Care signal retention

*"Signals expire"* is approved; **no duration is set**, and this determines
whether the recipient side is a queue or a store.

**Proposal:** a **short fixed window** — long enough to act on, short enough
that nothing accumulates into a picture. Not configurable per connection: a
recipient who could extend retention would be building the history the model
forbids.

**Blocks:** whether recipient-side storage exists at all.

### C5 — Where a recipient's Decline lives ▸ *contradiction*

Decline is approved for **either side**. If *he* declines a care suggestion,
that is a record about **him**.

If she could see it, *"he declined"* becomes telemetry about him — the exact
mirror of the problem invisible-off solves for her.

**Proposal: Decline is invisible in both directions.** His decline shapes what
WLOS suggests *to him* and is never surfaced to her. Symmetry here is not
courtesy; it is the same principle applied honestly.

**Also needs settling:** whether `not now` and `never` are distinct, since it
determines whether Decline carries a lifetime.

**Blocks:** where decline records live and who can read them.

---

## D. Invariants

Architecture must preserve every one of these. A design that cannot is the
wrong design.

### Privacy and boundary

1. **Journal never crosses.** No permission category, no share action, no
   summary-for, no export-to. The only exit is a fact she lifts and confirms.
2. **State never crosses.** No permission category exists for it.
3. **Observation never crosses**, and contains **no field in which a trait
   about another person can be stored.**
4. **Context is computed and never persisted as truth.**
5. **Pattern is never a fact**, decays, and cannot promote itself at any
   confidence.
6. **No pull.** Nothing about her is readable on demand by anyone.
7. **No access-request mechanism.** A request is pressure.
8. **No sharing-paused state.** Not expressible — a state that can be
   displayed can be demanded.
9. **Invisible-off.** *"She stopped"* must be indistinguishable from *"an
   ordinary week"*. No paused badge, last-seen, delivery status or read
   receipt.
10. **No read receipts, ever.** Silence must never become observable
    relationship telemetry.
11. **Decline is invisible in both directions** (C5).
12. **Revocation** = no further delivery · WLOS stops using the permission ·
    WLOS expires its own copies · **he is not notified**. It **does not** mean
    recall, and we must never claim it does.
13. **She can always see exactly what he sees.** No view of her she cannot view.
14. **Exit is silent and unilateral**, requiring no reason and no conversation.

### Care

15. **Suggest Care may only use explicitly released facts**, and every
    suggestion must be explainable back to one. **If the released source cannot
    be named, the suggestion is not generated.** Never from journal, private
    memory, pattern, inference, or any derived state.
16. **Nothing crosses that she has not seen in the exact form it will arrive.**
17. **Care translation may reword; it may never add a fact.**
18. **Declining creates no guilt, no score, no reduced access, and no repeat**
    unless she revisits it or circumstances materially change.
19. **A Boundary silences care reminders in its domain.** A closed boundary
    outranks a helpful nudge.

### Product shape

20. **WLOS is fully valuable with zero connections.** If a feature's value
    depends on another person being connected, it does not ship in release one.
21. **No streaks, no scores, no mood trends, no relationship health metrics.**
22. **Provenance is immutable** and attached to everything meaningful.
23. **Age: 18+.** Gate unchanged. **The adult connection model must never be
    copied into a younger world.**

---

## E. Lifecycle tests

| Operation | Behaviour | Invariant |
|---|---|---|
| **Create** | Everything she makes is `stated`, private by default, attached to zero or more areas. Attachment is optional — capture is never heavier than the thought. | 22 |
| **Change** | Anything hers is editable. Provenance never changes; an edited `stated` fact stays `stated`. Life Stage changes keep history. | 22 |
| **Share** | She selects → WLOS composes → **she previews the exact words** → approved → delivered once. Not a subscription. | 16, 17 |
| **Respond** | His voluntary act. She sees a response when one arrives. **No pending state, no "awaiting", no distinction between "didn't see" and "chose not to".** | 10 |
| **Decline** | Either side. Respected, optionally remembered, never repeated, **never surfaced to the other party.** | 11, 18 |
| **Revoke** | Per category. No further delivery · WLOS copies expire · **no notification, no indicator change.** Delivered material is not recalled and we do not claim it is. | 9, 12 |
| **Expire** | Signals expire on a fixed short window (C4). Patterns decay. Context is discarded per request. Connections may expire by design. | 5, 9 |
| **Leave connection** | Silent, unilateral, no reason. Shared Context splits — each keeps their own, neither sees the other's. He learns the connection ended, decoupled in time from her decision (C1). | 14 |
| **Delete account** | Hard deletion of everything hers across every table. Two honest exceptions: the **erasure tombstone** (no personal payload) and **copies other people hold** (C2). The copy must say so. | 12, C2 |

---

## F. Zero-connection test

**A woman who connects no one must still have a complete product.**

| System | Works alone? | What she gets |
|---|---|---|
| Her Life | **Yes** | Areas, people, events, goals, habits — her whole life, recorded and organised |
| Her Growth | **Yes** | Sleep, exercise, study, screen time, punctuality, confidence — reminders, plans, reflection |
| Her Care (self) | **Yes** | Check-ins, boundaries, reflection on her own observations |
| Her Care (others) | **Yes** | **Care Reminders — primitive 5.** *"You haven't called your mum."* *"Your sister's exam is tomorrow."* |
| Memory | **Yes** | Operational and biographical. Her story, kept. |
| Reflection | **Yes** | *"You've written three times this month that you felt smaller afterwards."* |
| Connection | requires a connection | The only thing she loses |

**Of the eight journeys, five cross no boundary at all** (A, B, E, F, and the
whole of Growth). The two most emotionally valuable — reflection, and being
reminded to care for the people she loves — **require nobody**.

**Verdict: passes.** Connection is an addition for a woman who wants it, never
the thing that makes WLOS worth having.

**The test to re-run before every release:**
> *Would a woman with zero connections still open this tomorrow?*

---

## G. Five-life stress test — reconfirmed

| | 19 student | 28 engineer | 40 mother + owner | 55 doctor | 70 retired |
|---|---|---|---|---|---|
| Areas | Psychology · Halls · Rowing · Me | Work · Flutter · Flat · Running | Bakery · Amira's school · Me and Amira · Mum's care · Me | Practice · Mum and Dad · Menopause · Garden · Pension | Health · Medication · Choir · Allotment · My story |
| Goals | pass stats `binary` | promotion `qualitative` · deposit `measurable` | hire a baker · save `measurable` | revalidation `binary` | walk daily `ongoing` · write my story |
| Habits | asleep by 1am | laptop off by 9 | laptop closed by 8 | strength ×2 | medication at 8 |
| Memory | tutor's name `op` | 1:1 Thursdays `op` | sesame allergy `op` | consultant `op` | the dance hall, 1974 `bio` |
| Care to others | checks on mum | partner's dates | children · mother | parents | grandchildren |
| Zero-connection value | **full** | **full** | **full** | **full** | **full** |
| New entity needed | none | none | none | none | none |

**No life required an entity of its own.** The 40-year-old still surfaces the
Coordinate gap (two sisters, one mother) — correctly **deferred**, not
worked around.

**Verdict: passes.**

---

## H. Architecture handoff

> ### Is the product model stable enough for engineering architecture to be derived from it?
>
> ## **Yes — conditional on C1, C2 and C5.**

**Frozen and safe to build from now:** the entire Life Model (Layer 2), the
entire Memory model (Layer 5), Governance, and the **zero-connection product**
— which is Release 1 and the large majority of WLOS.

**Blocked until C1, C2 and C5 are decided:** the connection subsystem only.
Each of the three is a genuine contradiction, not a detail, and each determines
a foundational structure:

| | Determines |
|---|---|
| **C1** connection exit | one shared connection record, or two per-side records |
| **C2** Shared Context on deletion | the erasure cascade, and what the deletion copy may honestly promise |
| **C5** recipient Decline | where decline records live and who may read them |

**Recommended sequencing:** architecture for the zero-connection product may
begin as soon as this review is approved. The connection subsystem waits for
three decisions, and by the zero-connection principle it is not Release 1
anyway — so this does not block delivery.

**C3 and C4** are smaller and can be decided during connection architecture
rather than before it.

**Stopping here.** No architecture is designed in this document.
