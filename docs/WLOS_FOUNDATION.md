# WLOS Foundation — database, targeting model, content mapping

**Date:** 23 September 2026
**Repos:** `WLOS_Backend` · `WLOS_App` · `WLOS_FrontEnd`
**Scope:** verification and documentation only. No schema redesigned, no content
migrated, no UI changed.

---

## 1. Database environments

**Measured** on this machine, 23 September 2026.

| Database | Created | Purpose | Contains | Safe to recreate? |
|---|---|---|---|---|
| `MarenPlatform` | 2026-09-23 | Maren staging | 1 user, 6 content items, 55 audit rows — **all generated during today's session** | Yes. No real user data has ever been in it |
| `WlosPlatform` | 2026-09-23 | **WLOS development** | 0 users, seed data only | Yes |
| `PERA_IMS` | 2026-08-12 | Unrelated project | — | **Not ours. Do not touch** |

Answers to the questions posed:

1. **What does Maren use?** `MarenPlatform` on `localhost`.
2. **What should WLOS use?** `WlosPlatform`. Created today from WLOS's own
   scripts. The connection-string key is `WlosPlatform`, not `MarenPlatform`, so
   a misconfigured environment fails loudly rather than connecting to Maren.
3. **What migrations exist in source?** 57 ordered SQL scripts in
   `src/Maren.Database`, order read from `docs/PLATFORM_RUNBOOK.md`.
4. **Which state is deployed?** `WlosPlatform` — all 57, clean. `MarenPlatform` —
   deployed from a stale checkout; its journal records
   `76_AuditContract_Apply.sql | failed`.
5. **Development?** `WlosPlatform`.
6. **Staging?** `MarenPlatform` serves Maren staging today. WLOS has none yet.
7. **Production?** **None exists.** Neither product is in production.
8. **Safely recreatable?** Both `MarenPlatform` and `WlosPlatform`.
9. **Real user data?** **None, anywhere.** The single Maren account is the
   session's test administrator.

### The audit contract, resolved

`MarenPlatform` has **43 of 86 tables** missing the audit-contract columns,
because its deploy failed at script 74. `WlosPlatform` has **3 of 86**, which are
the documented exemptions — script 74 succeeded on the clean deploy.

This retires an earlier finding: `usp_ApplyAuditContract` is **not** missing. It
is defined at `08_AuditContract.sql:105`. The earlier report was measured against
a stale checkout.

---

## 2. Content targeting — what actually exists

**Measured** from `34_ContentTargeting.sql`, `35_Procs_ContentTargeting.sql` and
the deployed `WlosPlatform`.

### 2.1 Storage

| Object | Role |
|---|---|
| `Content.ContentItem` | The content |
| `Content.TargetingDimension` | The 10 dimensions, as **data** — a new dimension is a seed row, not a schema change |
| `Content.ContentTargetingRule` | `ContentItemId`, `DimensionCode`, `Operator`, `ValuesJson` |
| `Content.fn_TargetedItems(@ContextJson)` | Inline table-valued function — the evaluator |
| `usp_Content_GetTargetingRules` / `SetTargetingRules` / `usp_TargetingDimension_List` | The API surface |

### 2.2 Operators — three, deliberately

`in`, `not_in`, `between`. `ValuesJson` is **always a JSON array**, even for a
single value, enforced by `CHECK (ISJSON(ValuesJson) = 1)`. The source states the
reason: one shape means the evaluator has one path.

### 2.3 AND/OR semantics — implemented, not aspirational

**Verified in the function body:**

- **OR within a dimension** — `MAX(Matched)` grouped by `ContentItemId, DimensionCode`
- **AND across dimensions** — `NOT EXISTS (… DimensionPassed = 0)`

So `life_stage ∈ {perimenopause, menopause} AND module = sleep` works today.

### 2.4 Universal fallback — free, by construction

An item with no rules has no rows in `dimEval`, so nothing can fail for it, and
it is returned to everyone. **Untargeted content is universal content.** This
matters for migration: the 325 snippets can be loaded with no rules at all and
behave exactly as they do now, then be targeted incrementally.

### 2.5 UNKNOWN is honoured in the evaluator

`not_in` requires that she *has* a value for the dimension before it can exclude.
The source comment: *"an exclusion cannot be judged against something we do not
know."*

That is the UNKNOWN-is-valid principle implemented in SQL, not just stated in a
document. A woman who has declared no life stage is not excluded by
`life_stage not_in [...]` rules.

### 2.6 Enforcement is server-side

The evaluator is a SQL function joined into the query that serves content. A
client cannot widen its own targeting.

### 2.7 Ordering and rotation is client-side

`fn_TargetedItems` returns a matching set, not an order. Rotation lives in
`content_rotation.dart` as a fixed permutation — deterministic and identical on
every device, chosen so nothing repeats within 30 days. **Targeting and rotation
are separate concerns**, which is correct; but it means a smaller targeted set
rotates faster, and that interaction is untested.

### 2.8 ~~A reproducible deployment defect~~ — RETRACTED

> **CORRECTION, 23 September 2026. This section was wrong. There is no defect.**
>
> `45_RuleEngine.sql:242–246` **deliberately drops** `Content.ContentTargetingRule`
> after migrating its rows to a generic `Rules.Rule` engine:
>
> > *"Both functions are rewritten in 46_Procs_RuleEngine.sql to read from
> > Rules.Rule, so these tables have no reader left."*
> > `DROP TABLE [Content].[ContentTargetingRule];`
> > `PRINT 'Dropped Content.ContentTargetingRule - superseded by Rules.Rule.'`
>
> `Dashboard.CardRule` is dropped identically at line 251 and is likewise
> absent. **Verified in the deployed database:** `Content.fn_TargetedItems` now
> reads `Rules.Rule`.
>
> Script 34 creates the table; script 45, later in the same ordered deploy,
> migrates and removes it. A clean deploy producing no `ContentTargetingRule` is
> **correct**, and the deploy reporting success was accurate.
>
> **Consequence of the error.** Script 34 was re-run by hand against
> `WlosPlatform` to "restore" the table. That re-created an orphan with no
> reader, *after* script 74 had applied the audit contract — leaving the only
> non-exempt table in the database outside that contract, with no `RowVersion`
> and no audit trail. **It should be dropped to match a clean deploy.**
>
> §§2.1–2.7 below describe the **superseded** evaluator. The operators, the
> OR-within / AND-across semantics, the universal fallback and the UNKNOWN
> handling were read from `34_ContentTargeting.sql`. Whether `Rules.fn_Match`
> preserves all four properties is **not verified** and must be re-measured
> before any of it is relied on.

The original text follows, retained so the error is legible rather than erased.

**~~A full ordered deploy does not create `Content.ContentTargetingRule`, and
reports success.~~**

Reproduced in a clean-room database (`WlosProbe`, created and dropped for the
test):

- `deploy.sh` reports `23/57 ok 34_ContentTargeting.sql`
- `Content.TargetingDimension` is created, with all 10 seed rows
- `Content.ContentTargetingRule` is **absent**
- Running the same script standalone afterwards **does** create it
- Running only its batch (lines 78–115) creates it, exit 0, no output

The table is guarded by `IF OBJECT_ID(...) IS NULL CREATE TABLE`, identical in
shape to the `TargetingDimension` guard immediately above it, which does work.
Nothing in any of the 57 scripts drops it.

**The mechanism is not yet established** and is not guessed at here. What is
established is that a clean deploy silently produces a targeting system with no
rules table — so targeting cannot be configured on a freshly deployed database,
and nothing reports a problem.

`WlosPlatform` has the table because script 34 was re-run against it by hand.
That is a workaround, not a fix, and it must not be how WLOS environments are
built.

**This is the highest-priority backend defect found.**

---

## 3. Representative content mapping

**Phase 6 as briefed: a sample, not a migration.** The library is unchanged; no
content has been copied, altered or deleted.

Proposed classification against the ten dimensions. Judgment, from sampled
titles.

| Category | Count | Sample titles | Proposed targeting |
|---|---|---|---|
| nutrition | 45 | "Lemon over lentils", "Where folate turns up", "Omega-3 in oily fish" | **Universal** — no rules. "Where folate turns up" is pregnancy-adjacent but true and useful at any stage |
| hydration | 35 | "Water at any hour", "Herbal teas, hot or cold", "Watermelon is mostly water" | **Universal** — no rules |
| sleep | 28 | "A cooler bedroom", "Curtains that actually block light", "The right pillow height" | **Universal**, optional `module = sleep` |
| movement | 30 | "Something good on a walk", "An evening kitchen dance", "Lengths at your own pace" | **Universal** |
| mental | 27 | "Three lines a day", "Naming a feeling plainly", "Noticing small pleasures" | **Universal** |
| womens | 22 | "Building your own baseline", "Left out of the research", "Body literacy is a skill" | **Universal** — these are the most WLOS-native in the library |
| relationships | 22 | "Friendships find a new rhythm", "Boundaries with well-meaning family" | **Universal**. One sampled title, "Sharing news in your own time", reads as pregnancy-announcement and needs individual review |
| partner | 22 | "Naming the invisible work", "Asking specifically", "Appointments as a shared task" | `role_mode in ['partner']` — **must not be universal**. Assuming a partner is exactly the assumption WLOS forbids |
| cycle | 20 | "What a cycle counts", "Four phases, one loop", "The follicular phase" | `life_stage not_in ['menopause','senior']` — note §2.5: a woman with no declared stage still receives them |
| period | 19 | "Pads, a quick history", "Tampons, how they work", "Menstrual cups, the basics" | Same. Age-appropriate for adolescence onward — genuinely useful to a 13-year-old |
| hormones | 19 | "Oestrogen, an introduction", "Progesterone…", "LH, the surge hormone" | **Universal** — relevant from adolescence through menopause |
| birth | 22 | "The route, timed twice", "Who gets the first call", "A bag by the door" | `life_stage in ['pregnancy']` — **must be gated**. These are labour-preparation |
| recovery | 14 | "The fourth trimester", "Visitors with a job", "Help, accepted specifically" | `life_stage in ['postpartum']` |

### What the sample proves

1. **The model can represent the content.** Every sampled snippet maps to either
   no rules (universal) or a single `in`/`not_in` rule on one dimension. Nothing
   needed an operator that does not exist.
2. **Roughly 165–185 are genuinely universal** and can migrate with **no rules
   at all**, behaving identically to today.
3. **Only two categories must be gated before WLOS ships to a non-pregnant
   user**: `birth` (22) and `recovery` (14). That is **36 of 325 — 11%**.
4. **`partner` (22) is the subtle one.** It is not a life-stage problem; it is a
   circumstance assumption. `role_mode` already models it.
5. **Category is not the same as dimension.** The existing `WellnessCategory`
   enum maps naturally onto `module`, not onto `life_stage`. Both are needed.

### What the sample does not prove

- Per-snippet accuracy. Categories are coarse; "Sharing news in your own time"
  sits in `relationships` and reads as pregnancy-specific. **Bulk migration by
  category will misclassify some.**
- Rotation behaviour once the set is filtered (§2.7).
- Whether the 13 categories are the right `module` taxonomy for WLOS.

**Recommendation:** migrate in two passes. First the ~165 unambiguous universal
snippets with no rules — zero behavioural change, fully reversible. Then the
gated categories individually, with editorial review. Do not bulk-migrate all
325 by category.

---

## 4. What remains untouched

- The original `wellness_library.dart` — unchanged, not deleted
- `MarenPlatform` — not modified during any of this work
- Maren's repositories — not modified
- Pregnancy functionality — fully present in all three WLOS repos
- Backend schemas — not redesigned
- Navigation, onboarding, dashboards — not touched
