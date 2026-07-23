# Screen 3 — Hospital bag checklist + birth preferences

**Status: draft for review. No branch created, no feature code written.**

Sourced 2026-07-20. Every content decision below traces to a named authority;
where it does not, that is stated rather than filled in.

---

## 1. Why this screen is worth building

`hospital bag checklist` returned **28 results on Play with zero exact-title
matches** — results degrade into generic checklist apps, a travel packing app,
MyChart, and a hospital *simulation game*. When the index serves a game for your
query, the intent is unserved rather than contested. It is the cleanest measured
opening in the whole competitive analysis.

Birth plan is the second title keyword (`Maren: Due Date & Birth Plan`), so this
screen is what the store listing promises.

---

## 2. Blockers and scope calls — read before reviewing the rest

### 2.1 ⚠️ ACOG content is all-rights-reserved

The ACOG *Sample Birth Plan* (HT001, © August 2022) was retrieved and read in
full. Its notice states no part may be reproduced or transmitted in any form
without prior written permission.

**We therefore cannot lift ACOG's option wording into the app.** What we can use
is the *set of choices that exists* — facts about available options are not
themselves copyrightable, on the same principle that makes a recipe's ingredient
list unprotectable while its prose is protected. So: derive the option set from
ACOG, write our own phrasing, attribute the source.

**Action required:** legal sign-off on that reading before US content ships, or
a permission request to ACOG. This is the one item on this spec that could
change the shipping plan.

NHS content is likely reusable under the Open Government Licence with
attribution — **not verified**, and it needs to be before launch.

### 2.2 ACOG deliberately does not enumerate pain relief — and we should copy that

The most useful finding in the sourcing pass. ACOG's own patient-facing plan
offers exactly three anesthesia choices:

> I do not want anesthesia offered to me during labor unless I specifically
> request it. / I would like anesthesia. Please discuss the options with me. /
> I do not know whether I want anesthesia. Please discuss the options with me.

It names no specific technique. The NHS, by contrast, enumerates eight options
in its pain relief guidance.

That is not an oversight on either side — it reflects what each authority thinks
belongs in a patient's written plan versus a conversation with a clinician.

**Design consequence: the US template captures a stance, not a technique list.**
This is both safer for us and more faithful to the source. It also neatly
sidesteps the meperidine/pethidine terminology problem and the unverified US
nitrous oxide prevalence figures.

### 2.3 Sections we are NOT building, and why

| Section | Why excluded |
|---|---|
| **Cord clamping timing** | Appears in **neither** the NHS nor the ACOG template. Adding a timing option means authoring clinical content, not sourcing it. |
| **Third stage / placenta delivery** (physiological vs active management) | Same — absent from every verified template. A significant clinical choice that must not be app-authored. |
| **Vitamin K trade-offs** | NHS lists it as a plan field ("if they need it") and we will too — as a field to discuss. We will not explain the decision. |
| **Intervention consent** (forceps, ventouse) | NHS covers only *who may accompany you*. We capture the companion question, not consent. |

Earlier drafts of this spec listed cord clamping and third stage as typical
sections. They were wrong, and the sourcing pass is what caught it.

### 2.4 Locale scope: `en-GB` and `en-US` only in v1

Western Europe is a stated target market and **neither list transfers**. Dutch
home-birth norms in particular differ substantially, and France and Germany
diverge again. That needs its own research pass; it is out of scope here and
recorded as a gap rather than guessed at.

### 2.5 Sources that could not be verified

Tommy's (403, and its search snippet was contaminated with US content — nothing
attributed to Tommy's is usable), NHS Scotland *Ready Steady Baby* (403, worth
retrieving since Scottish guidance can differ), Johns Hopkins and Brigham &
Women's (blocked). **No verified US academic-hospital template exists in our
sourcing**; ACOG plus MedlinePlus carry the US side alone.

---

## 3. The divergence that justifies the locale model

A single list is quietly wrong for half our users. This is the core content
deliverable, all rows fetched from primary sources on both sides.

| Item | UK (NHS / NCT) | US (Cleveland Clinic / MedlinePlus) |
|---|---|---|
| **Nappies / diapers** | **You bring them** — NCT: "6–8 should cover the first couple of days" | **Hospital provides** diapers, wipes, bottles, pacifiers |
| **Maternity pads** | **You bring them** — NHS: "2 packets of super-absorbent sanitary or maternity pads" | **Hospital provides**; sent home with mesh underwear and pads |
| **Towels** | **You bring them** — NHS lists "Towels" | Not on either US list — hospital-supplied |
| **Baby clothes during stay** | **You bring them** — vests, sleepsuits, hat, mittens | **Hospital provides** during stay; US lists only sleepers + going-home outfit |
| **Labour clothing** | You bring loose clothing | **Hospital gown provided** |
| **Documentation** | **Maternity notes** (paper or digital) + birth plan. NCT calls the notes the *only* essential item. No insurance concept. | **Photo ID + insurance card + admissions paperwork.** No equivalent of maternity notes. |
| **Car seat** | NHS lists it; NCT frames it as required "for transport home **by car**" — conditional, since UK discharge on foot or by bus is normal | MedlinePlus: *"required by law and should be properly installed in your car before you go to the hospital"* |
| **Birth pool swimwear** | NHS lists it for the birth partner | Absent — water birth far less common |
| **TENS machine** | On the NHS bag list, with spare batteries | Absent from US lists entirely |
| **Formula** | NCT: some hospitals cannot make up formula → starter packs | Bottles and nipples hospital-provided |

**The two highest-risk rows are documentation and car seat.** A US field labelled
"insurance card" is meaningless on the NHS; a UK app omitting it could cause a
real admission problem. And presenting the US legal framing to a UK user is
wrong, while presenting the UK conditional to a US user could cause a failed
discharge.

**Do not include the "red book"** in a UK packing list. The Personal Child Health
Record is issued at or after birth and appears on no verified NHS or NCT bag
list. It would read as a UK-authenticity error to exactly the users we are trying
to serve well.

---

## 4. Data model

```
lib/features/checklist/
  data/
    checklist_models.dart        ChecklistItem, ChecklistSection, ChecklistState
    checklist_defaults.dart      locale-keyed default content, each item sourced
    checklist_repository.dart    interface + InMemoryChecklistRepository
  ui/
  README.md

lib/features/birth_preferences/
  data/
    preference_models.dart       PreferenceSection, PreferenceOption, Selection
    preference_defaults.dart     locale-keyed sections and options, each sourced
    preference_repository.dart   interface + InMemoryPreferenceRepository
  ui/
  README.md
```

### 4.1 Checklist

```dart
enum ChecklistAudience { forYou, forBaby, forPartner, documents }

class ChecklistItem {
  final String id;              // stable across locales where the item is shared
  final String label;
  final ChecklistAudience audience;
  final ClinicalSource source;  // required — same pattern as DueDateResult
  final String? localeNote;     // e.g. "The hospital usually provides these"
  final bool isUserAdded;
}
```

Checked state is stored separately from item definitions, so updating default
content in a later release never disturbs what a user has already ticked or
added. Defaults are seeded once at first open, not re-merged on every launch —
re-merging is how competitors lose user edits.

`ClinicalSource` is a required field, reusing the citation pattern from the due
date calculator. `ClinicalSources` gains `nhsHospitalBag`, `nctHospitalBag`,
`clevelandClinicBag`, `medlinePlusBag`, `nhsBirthPlan`, `nctBirthPlan`,
`acogBirthPlan`.

### 4.2 Birth preferences

Named **birth preferences**, not birth plan, in the UI. All three authorities
converge on flexibility framing, and NCT explicitly reports the suggestion of
reframing plans as "preferences", "wishes" or "desires". The store listing keeps
"Birth Plan" because that is the search term.

```dart
class PreferenceOption {
  final String id;
  final String label;
  final ClinicalSource source;
}

class PreferenceSection {
  final String id;
  final String title;
  final List<PreferenceOption> options;
  final bool allowsMultiple;
  final String freeTextPrompt;   // never null — no section is exhaustive
}

class Selection {
  final String sectionId;
  final Set<String> chosenOptionIds;   // empty is valid and means "not decided"
  final String freeText;
}
```

**Nothing in this module may compute, rank, score or derive anything from a
selection.** It stores what the user said, exactly as `SelfReportedIntensity`
does in the body log. That is what makes it survive the guard.

### 4.3 Sections, by locale

**`en-GB`** — from the NHS birth plan page and NCT, both fetched:
birth location · birth companions · companions for operative delivery ·
equipment (mats, beanbags) · special facilities (birthing pool) · movement
during labour · positions for birth · immediate skin-to-skin · presence of
trainees · pain relief · infant feeding · vitamin K · plans for travelling home
(NCT) · preferences if circumstances change (NCT).

**`en-US`** — option *set* derived from ACOG HT001, phrasing ours:
movement during labor · fluids during labor · IV vs saline lock · people present
during labor · trainees present · labor tools (birthing ball, stool, chair,
squat bar, shower or bath) · **anesthesia stance only, no technique list** ·
people present at delivery · episiotomy preference · cord blood storage
arrangements · delivery environment (lights, quiet, mirror, who cuts the cord,
photography) · skin-to-skin · early breastfeeding · caesarean support person ·
eye drops timing · newborn feeding · pacifier / sugar water / formula ·
rooming-in · circumcision.

Note **circumcision and rooming-in are US-only** and have no UK counterpart;
**birthing pool and TENS are UK-weighted**. This is not cosmetic localisation —
the sections themselves differ.

---

## 5. Phrasing rules

Enforced by review, and by guard where testable.

1. **Ordering carries meaning.** As-published or alphabetical. Never by
   popularity, never "most people choose". Ordering by prevalence is a
   recommendation wearing a UI convention.
2. **No option is marked default, standard, recommended or usual.** No
   pre-selected controls anywhere. An unselected section means "not decided",
   which is a real and common state.
3. **No consequence language.** Not "may help you relax", not "can slow labour",
   not "reduces the need for". Every one of those is clinical guidance and is
   the specific thing that would pull us out of the general-wellness lane.
4. **"I'm not sure yet — I'd like to discuss this" is a first-class option in
   every section.** ACOG ships exactly this for anesthesia; a builder that
   forces a binary manufactures a decision the person has not made.
5. **Free text on every section**, so the list never reads as exhaustive.
6. **Preference framing.** "I'd prefer", not "I want".
7. **Quote clinical claims, never paraphrase them.** The NHS line that most
   complementary techniques "are not proven to provide effective pain relief" is
   an efficacy claim: quote it verbatim with attribution, or omit it. In our own
   voice it becomes our claim.
8. **Attribute legal claims.** The US "car seat required by law" framing varies
   by state. Attribute to MedlinePlus; do not assert it.
9. **NCT's dried-fruit item** ships as an item; its "helps get the digestive
   system moving, particularly important after a caesarean" rationale is a
   post-operative recovery claim — attribute it or drop the clause.

### 5.1 Framing copy to surface at point of use

Quotable, attributed, and better than anything we would write:

> A good plan is not rigid, as circumstances may change during pregnancy, labour
> and birth. — NCT

> Giving birth doesn't always go perfectly to plan, and things may have to
> change at the last minute. — NHS

NCT also advises considering whether *all* plans need to change when
circumstances do, or whether parts can be kept. That translates directly into a
UX rule: **plan items are individually revisable, never all-or-nothing.**

---

## 6. Guard coverage

`birth_preferences` is added to `guardedPaths` in the **existing**
`test/guards/no_interpretation_test.dart` — not a new guard file. It inherits
the README requirement, so the module README must name a controlling FDA
guidance and its date.

`checklist` is **not** added. A packing list is logistical, not clinical, and
guarding it would dilute what the guard means.

Both modules are covered by the existing `inclusive_copy_test.dart` — birth
preferences especially, since partner references appear throughout and must read
from `AddressTerms`.

---

## 7. Export

| Feature | Format | Rationale |
|---|---|---|
| Checklist | Plain text via share sheet | It is a shopping list. PDF would be ceremony. |
| Birth preferences | **PDF** via `pdf` + `printing` | It is handed to a midwife or ob-gyn. Same "legibility to a clinician" principle as the body log export. |

Both packages are pure Dart with no network or telemetry, so they do not widen
the SDK surface the way an analytics-bearing dependency would.

The PDF must carry the flexibility framing and the source attributions. A birth
preferences document that arrives at a hospital looking like a demand list
serves the user badly.

---

## 8. Test plan — 35–50 behaviour-driven tests

Not a count target. Coverage of behaviour, per unit of risk.

**Checklist (~15)** — defaults seed once and never re-merge over user edits ·
checked state survives a defaults update · user-added items persist and are
distinguishable · locale switch swaps content without losing checked state ·
every default item carries a source · UK and US lists differ on the ten
divergence rows · export round-trips.

**Birth preferences (~20)** — empty selection is valid and distinct from an
explicit "not sure" · no option is pre-selected in any section · every section
has a free-text prompt · every section offers a "not sure yet" option · every
option carries a source · US anesthesia section contains no technique names ·
UK and US section sets differ as specified · selections round-trip · PDF
generation includes framing text and attributions.

**Guards (~5)** — `birth_preferences` added to `no_interpretation_test`,
verified failing on an injected ranking or consequence string · both modules
pass `inclusive_copy_test`, verified failing on an injected hardcoded term ·
module READMEs cite guidance and date.

---

## 9. Open items

**For you:**

1. **Legal read on the ACOG reproduction notice** (§2.1). Deriving the option
   set while writing our own phrasing is the position I would take; it needs
   confirming before US content ships.
2. **Verify NHS content licensing** — likely Open Government Licence, unverified.
3. **Clinical QA, narrowly scoped:** is each option in §4.3 real and currently
   available in that locale? Not a general content review — that specific
   question.

**For me, before or during the branch:**

4. Retrieve NHS Scotland *Ready Steady Baby* via browser (403 to curl).
5. Re-source Tommy's via browser, or drop it — nothing from it is currently
   usable.
6. Confirm whether NHS lists sterile water injections as a pain relief option
   (snippet only).

**Deferred:**

7. Western European locales — separate research pass.
8. No US academic-hospital template verified; ACOG + MedlinePlus carry the US
   side alone.

---

## 10. What I am NOT doing without sign-off

- Creating the branch or writing feature code.
- Shipping any US birth preference content until §9.1 is resolved.
- Generating store assets of any kind — the trademark clearance gate in
  `app/README.md` still stands.
