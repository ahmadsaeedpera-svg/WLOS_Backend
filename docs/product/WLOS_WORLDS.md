# WLOS Worlds

**Status:** proposal for review. Nothing built, nothing approved.
Supersedes the earlier `WLOS_AGE_WORLDS.md` draft, which was withdrawn — its
name implied WLOS continuously estimates age, which is precisely what this
document forbids.

---

## 1. A World is eligibility, not classification

```
  Account  ──►  verified age band  ──►  WORLD  ──►  what is available
                (stated once,            (eligibility)
                 never inferred)
```

**WLOS never estimates age.** Not from her writing, her vocabulary, her
interests, her hours, her music, her friends or her typing. Age-guessing from
behaviour is the same category of inference as guessing pregnancy, and it is
refused for the same reason.

A World decides **what the product offers**. It never becomes a belief about
who she is. Nothing in her life model records "she is a teenager" as a fact
about her — the band sits on the account, governs eligibility, and is invisible
to the model underneath.

> Age influences the available product world.
> It must never become a hidden classifier of the person.

---

## 2. The architecture

One reusable structure, all the way down:

```
  WORLD
    ↓
  CATALOGUE              ← admin-configured
    ↓
  LIFE AREA TYPE
    ↓
  USER LIFE AREA         ← hers
    ↓
  USER CONTENT           ← hers, invisible to every operator
```

A World selects **which catalogue** is in play. Everything below the catalogue
line is the same machinery in every world.

| A World selects | Adult | Younger |
|---|---|---|
| Life Area types | work · business · property · caring · pension · health | school · learning · creativity · hobbies · friends · family · routines |
| State dimensions | energy · sleep · stress · pain | sleep · mood · worry |
| Goal & Behaviour templates | career · finance · training | revision · practice · sleep routine · digital habits |
| Boundary subjects | the adult list | **longer, and more closed by default** |
| Pattern definitions | the adult set | **very nearly empty** |
| Action types | remind · guide · organise · draft · schedule | remind · encourage · organise |
| Content | adult library | age-appropriate library |
| Sharing | scoped, expiring, revocable | heavily restricted |
| Safety policy | adult duties | escalation duties, retention limits, consent model |

All of it admin-configured. Adding a type, or moving one between worlds, is
configuration — not a release.

---

## 3. One product, not three

**The Life Model is shared and identical in every world.**

```
  Person · Life Area · People · Events · Goals · Behaviours
  Journal · Memory · State · Life Stage · Preference · Boundary
  Context · Pattern · Action
```

What changes is **vocabulary, capability, content and policy** around those
entities. Never the entities.

The alternative — `WLOS Adult`, `WLOS Teen`, `WLOS Kids` as three codebases —
means three schemas, three safety models, three sets of bugs, and a girl who
turns eighteen having to migrate between products. It is also how the youth
version ends up being the adult version with things crossed out.

---

## 4. A younger world is not a smaller one

The trap is building the adult product and subtracting.

Exams are not a smaller work deadline. A friendship ending at fifteen is not a
smaller divorce. The younger world gets **its own catalogue, its own language
and its own weight** — a product that treats a teenager's life as practice for
a real one has already lost her.

This is why the catalogue is swapped rather than filtered. *Pension* is not
hidden from a fifteen-year-old; it is not in her world at all. And *coursework*,
*friendships* and *practice* are not adult types she has been granted early —
they are hers.

---

## 5. Test: three lives, one model

**The rule:** represent all three using only the fifteen concepts. If any needs
`Student`, `Employee`, `Mother` or `RetiredPerson`, the model carries hidden
assumptions about what a life is supposed to look like.

### Adult — 32, software engineer

| Her life | Concept |
|---|---|
| *Work at Nexa* · *The flat* · *Money* · *Learning system design* · *Running* | Areas |
| Manager, partner, two friends | People |
| Sprint review (recurring) · mortgage renewal · 10k race | Events |
| Promotion | Goal `qualitative` + milestones |
| Save a deposit | Goal `measurable` |
| Evening walk · laptop off by nine | Behaviours |
| "1:1 with Priya is Thursdays" | Memory `operational` |
| energy · sleep · stress | State |

### Younger — 15, school student

| Her life | Concept |
|---|---|
| *Year 10* · *Art* · *Football* · *Friends* · *Home* · *Me* | Areas |
| Best friend, mum, form tutor | People |
| Mock exams · match on Saturday · coursework deadline | Events |
| Pass the mocks | Goal `binary` |
| Get better at drawing | Goal `qualitative` |
| Phone down by ten · thirty minutes of revision | Behaviours |
| "Coursework is due 14 March" | Memory `operational` |
| "First time I scored" | Memory `biographical` |
| sleep · mood · worry | State — **a different dimension set, not fewer** |

No new entity. What differs is entirely catalogue and policy: no *pension*, no
*caring*, no *business*; `worry` instead of `stress`; a longer boundary list;
almost no patterns; and no *draft a message* action.

> **▸ Finding 7: a guardian is not a Person in her life model.**
>
> Consent and guardianship are **account-layer** concepts. If the legal
> guardian were recorded as a Person, her guardian would appear in her People
> list as though she had chosen to put them there.
>
> Her mum may *also* be a Person in her life — because she said so, in *Home*
> or in *Me and Mum*. That is her choice and it is a different record from the
> consent one. Conflating them would make the legal relationship look like a
> personal one, and make the personal one impossible to remove.

### Older — 68, retired professional

| Her life | Concept |
|---|---|
| *Health* · *Medication* · *Family* · *Choir* · *The allotment* · *Money* · *My story* | Areas |
| Children, grandchildren, a choir friend, her GP | People |
| Cardiology review · grandson's birthday · choir (recurring) | Events |
| Walk every day | Goal `ongoing` |
| Write down my story | Goal `qualitative` + milestones |
| Medication at eight | Behaviour `scheduled` + Action `remind` |
| "I met Tom at the dance hall in 1974" | Memory `biographical` |
| energy · sleep · pain | State |

> **▸ Finding 8: she does not need a third world, and giving her one would be
> the error.**
>
> Everything above is the **Adult** catalogue. Her life differs from the
> engineer's in *content*, not in *capability* — and that is exactly what Life
> Areas, Life Stages and Goals are for.
>
> A "senior world" would define her by a number, which is the thing §1
> forbids. The only honest reason to split a world is **differing legal
> obligation**, and there is none here.
>
> **Her passing this test is the proof that the Adult world is not a
> working-age world in disguise.** That was the real risk, and it is why she
> belongs in the test.

One catalogue addition falls out: a `legacy` / life-story area type. It is
**available to everyone** — a thirty-two-year-old may want to write her story
too — and it is an admin change, not a world.

> **▸ Finding 9: accessibility is not a world.**
>
> Larger type, higher contrast, simpler interactions, fewer things per screen.
> These belong in **Preferences, available to everyone**. A thirty-year-old
> with low vision needs them; a sharp-eyed seventy-year-old does not want them
> imposed.
>
> Tying accessibility to an age band would be classification wearing a helpful
> face.

### Result

| | |
|---|---|
| New core entity types | **none** |
| Worlds actually required | **two** — Adult and Younger |
| Basis for the split | **legal obligation only**, never capability or life shape |
| New catalogue types discovered | `legacy` (all worlds) |
| New findings | guardian ≠ Person (7) · no senior world (8) · accessibility ≠ world (9) |

**The model holds.** Engineer, student and retiree are all *Life Areas + People
+ Events + Goals + Behaviours + Memories + Stage*, and none of them needed a
type of her own.

---

## 6. The unresolved problem

**Guardian access, for the Younger world.** Child-protection law in most
regimes gives a guardian rights to review and delete a minor's data. WLOS's
core promise is a private space where she can write honestly.

> A fifteen-year-old writing about something difficult **at home**, and a
> guardian with a legal right to read it.

| Posture | Cost |
|---|---|
| Guardian sees nothing | Hardest to square with consent regimes |
| Guardian sees metadata only | Defensible; needs legal sign-off per market |
| Guardian sees content | **Destroys the product** for the user who needs it most |
| Journal disabled below an age | Honest, but removes the most valuable surface |

**Recommendation: metadata only, stated plainly to both of them at sign-up.**
She must know exactly what her guardian can and cannot see *before* she writes
anything. A private space she wrongly believes is private is worse than no
private space at all.

**This is a legal and safeguarding decision, not an engineering one, and it
gates any Younger-world UI.**

---

## 7. Also unresolved

- **Age assurance.** A date-of-birth field is not age assurance. Several
  regimes now require more. Vendor cost, user friction, and it lands on the
  first screen.
- **Safety escalation.** A disclosure of self-harm or abuse from a minor
  carries duties that vary by jurisdiction. `AI.SafetyEvent` exists; the duty
  model does not. Needs clinical and legal input.
- **Deletion conflict.** Hard deletion removes everything. For a minor,
  retention duties may *require* keeping certain safety records — the opposite
  obligation.
- **Regulatory surface.** EU KIDS Act (in force 17 September 2026) · UK Age
  Appropriate Design Code (DPIA required) · GDPR Art. 8 (consent age 13–16 by
  member state) · COPPA (verifiable consent under 13) · Play Families and Apple
  Kids review tracks.
- **Under-13.** Materially a different product — verifiable consent, separate
  store track, separate content standards. **Recommendation: its own programme,
  not this one.** Attempting it alongside means the hardest case sets the pace
  for everything.
- **The eighteenth birthday.** Proposal: **content never changes, capabilities
  expand, and she is told exactly what changed.** Her journal from fifteen
  stays hers, unaltered.

---

## 8. What this changes in the Life Model

Small, which is the point.

| Concept | Change |
|---|---|
| **Life Area** | catalogue gains a world dimension |
| **State** | dimensions become per-world |
| **Boundary** | subject list becomes per-world |
| **Pattern** | definitions become per-world |
| **Action** | types become per-world |
| **Person** | unchanged — **guardianship lives in the account layer** (finding 7) |
| Everything else | unchanged |

`Identity.fn_MinimumAge()` becomes a world lookup rather than a yes/no gate.
