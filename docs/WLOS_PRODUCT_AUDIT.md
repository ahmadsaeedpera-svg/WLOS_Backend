# WLOS Product Audit

**Date:** 23 September 2026
**Repos audited:**
`WLOS_Backend` `813fd15` · `WLOS_App` `3a8da93` · `WLOS_FrontEnd` `29c1e25`
**Seeded from:** `Maren-Backend` `813fd15b` and `Maren-Frontend` `2bc60307`
**Status:** audit only. No code changed. No redesign started.

Measurements were taken against fresh clones of the three WLOS remotes and the
SQL sources in `WLOS_Backend/src/Maren.Database`. Facts are marked **measured**;
everything else is labelled **judgment**.

This audit does **not** repeat the mobile UX analysis. That work exists as
`WLOS_MOBILE_REORIENTATION_AUDIT.md` in `Maren-Frontend/docs/` and its findings
hold for `WLOS_App`, which is byte-identical to Maren's `mobile/` at the seed
commit. **That document did not travel into any WLOS repo** — it sits at the
Maren repo root, outside both subtree paths. Carrying it across is item 1 below.

---

## 1. The headline

**The platform WLOS needs already exists. The content does not.**

Two measurements, side by side:

| | |
|---|---|
| Targeting dimensions the platform supports | **10** |
| Life stages modelled | **12** |
| Role modes modelled | **8** |
| Content items in the platform CMS | **6** (all FAQ) |

The architecture models 12 stages × 8 roles and can target content on ten
dimensions. It holds six pieces of content. WLOS is not blocked on engineering;
it is blocked on authoring.

---

## 2. What WLOS inherits, verified

**Measured.** All three repos build from a clean clone:

| Repo | Commits | Build |
|---|---|---|
| `WLOS_Backend` | 65 | `dotnet build -c Release` — 0 errors |
| `WLOS_App` | 40 | `flutter analyze` — no issues |
| `WLOS_FrontEnd` | 15 | `vite build` — succeeded |

### 2.1 The targeting model is already life-first, not pregnancy-first

**Measured**, from `34_ContentTargeting.sql`. Ten dimensions, seeded with sort
order:

| Order | Dimension | Meaning |
|---|---|---|
| 10 | `life_stage` | adolescence … senior. Matches `Identity.LifeStage` |
| 20 | `role_mode` | student, professional, caregiver and the rest |
| 30 | `age` | years, supports ranges |
| 40 | `country` | ISO code |
| 50 | `language` | e.g. `en-GB` |
| 60 | `season` | spring, summer, autumn, winter |
| 70 | `goal` | what she said she is working towards |
| 80 | `condition` | self-reported, *"never a diagnosis"* |
| 90 | `module` | sleep, nutrition, habits… |
| **100** | **`week`** | **gestational week, for pregnancy content** |

Pregnancy is dimension **ten of ten**, last by sort order, scoped to
"pregnancy content". The data model already expresses the product thesis: an
operating system for a woman's life, in which pregnancy is one dimension.

Rules combine **AND across dimensions, OR within one**, so
`life_stage ∈ {perimenopause, menopause} AND module = sleep` is expressible
today with no schema change.

### 2.2 The life model

**Measured.** 12 stages: `adolescence`, `young_adult`, `independent`,
`partnership`, `planning`, `pregnancy`, `postpartum`, `motherhood`, `midlife`,
`perimenopause`, `menopause`, `senior`.

8 role modes: `student`, `professional`, `freelancer`, `entrepreneur`,
`remote_worker`, `homemaker`, `caregiver`, `partner`.

That is 96 stage×role combinations before age, country, goal or condition. It
maps directly onto the intended audience — adolescents through older women,
students through shift workers, mothers and non-mothers.

**Verified live (23 Sep):** setting each of the twelve stages and re-reading
`/api/v1/me/today` executes 24 pipeline stages with **zero failures** for every
stage.

### 2.3 Schema names are product-neutral

**Measured.** The SQL schemas are `Identity`, `Health`, `Content`,
`Administration`, `Notifications`, `Reporting`, `Audit`. Not one is
pregnancy-shaped. The data model needs no renaming for WLOS.

---

## 3. The content reality

**Measured.**

| Where | What | Count |
|---|---|---|
| Platform CMS (`Content.ContentItem`) | FAQ only | **6** |
| App bundled floor (`bundled_content.dart`) | emergency offline tier | ~4, 106 lines |
| App wellness library (`wellness_library.dart`) | daily snippets | **325**, 2,011 lines |

### 3.1 The 325 snippets are a genuine WLOS asset

**Measured**, by category:

| Category | Count | WLOS relevance (judgment) |
|---|---|---|
| nutrition | 45 | Universal |
| hydration | 35 | Universal |
| movement | 30 | Universal |
| sleep | 28 | Universal |
| mental | 27 | Universal |
| womens | 22 | Broad |
| relationships | 22 | Broad |
| partner | 22 | Broad — assumes a partner exists |
| birth | 22 | Pregnancy-specific |
| cycle | 20 | Reproductive years |
| period | 19 | Reproductive years |
| hormones | 19 | Broad, incl. perimenopause |
| recovery | 14 | Postpartum-leaning |

Roughly **165 are fully universal**, 66 broad, 58 cycle/hormonal, 36
pregnancy-or-postpartum. Only 27 lines in the whole 2,011-line file mention
pregnancy terms.

This is the single most valuable thing WLOS inherits, and it was written to be
stage-neutral even when the product was not.

### 3.2 But the snippet model cannot be targeted

**Measured.** `WellnessSnippet` has exactly three fields: `category`, `title`,
`body`. There is **no life-stage dimension, no age, no role**. The rotation is a
fixed permutation over the whole library.

Consequence: a 13-year-old and a 70-year-old receive the same rotation,
including the 22 `birth` snippets. The app cannot filter what it cannot
describe.

**The bridge already exists.** The platform can target on `life_stage`; the app
library cannot. Migrating these 325 snippets into the CMS with targeting rules
is the highest-value content action available, and needs no new engineering —
the dimension, the rules table and the delivery path are all built.

---

## 4. Product identity debt

**Measured.** Files mentioning "Maren" per repo:

| Repo | Files | Of total | Nature |
|---|---|---|---|
| `WLOS_Backend` | 142 | 235 (60%) | Namespaces, solution, docs |
| `WLOS_App` | 78 | 288 (27%) | Identity, copy, docs |
| `WLOS_FrontEnd` | 12 | 63 (19%) | Docs, titles |

### 4.1 Hard identity — blocks shipping

| Artefact | Current | Problem |
|---|---|---|
| `applicationId` | `com.ostrevo.maren` | **Identical to Maren.** Both apps cannot coexist on one device, and the Play listing collides |
| Android `namespace` | `com.ostrevo.maren` | same |
| `android:label` | `Maren` | User-visible app name |
| iOS `CFBundleName` | `Maren` | User-visible |
| `pubspec.yaml` name | `maren` | Dart package name |
| Release signing | debug keys | Play will reject; also shared with Maren |

**This is the only category that genuinely blocks a WLOS build being installed
alongside Maren.** It is small and mechanical.

### 4.2 Soft identity — cosmetic, deliberately deferred

The .NET surface is `Maren.*`: solution `Maren.Backend.slnx`, 8 projects, 23
distinct namespaces, database `MarenPlatform`. **Judgment: do not rename these
yet.** They are invisible to users, a rename touches every file in the backend,
and `WLOS_MIGRATION_PLAN.md`'s standing advice — *gate before rename* — applies
with equal force here. Rename when there is a reason beyond tidiness.

---

## 5. Capability gaps

**Measured**, and unchanged from the platform Maren runs on:

| Capability | State | Consequence for WLOS |
|---|---|---|
| Life stages, roles, targeting | **Built and working** | Ready |
| Content per stage | 6 items, none targeted | **The product gap** |
| Notifications backend | **4 tables, 0 procedures** | The adaptive-reminder vision has nothing behind it |
| `notificationResolution` stage | `UnbuiltStage` — returns `unavailable` | Confirmed live |
| `conversationContextResolution` | `UnbuiltStage` | No conversation engine |
| `aiContextResolution` | `UnbuiltStage` | No model integration |
| Calendar / location / motion signals | **None anywhere** | Context-aware timing cannot be built yet |
| Mobile write path to server | **None** — 3 GETs, 0 writes | See §7 |

Three of 24 pipeline stages are deliberate `UnbuiltStage` placeholders. They
report themselves rather than returning silence — *"ran and found nothing" and
"was never built" are different facts* — which is the correct behaviour and
should be preserved.

---

## 6. Runtime and infrastructure independence

**Measured, and this is a real finding.**

`WLOS_Backend` and `Maren-Backend` both default to the database named
**`MarenPlatform`**, and both bind port **5199**; both portals bind **4173**.

Repository independence is proven (§8). **Runtime independence is not.** Running
both products on one machine today would have them share a database and fight
over ports. Before WLOS is hosted anywhere it needs:

- its own database name
- its own ports
- its own connection string and signing key
- its own hostnames

Also noted: the **deployed `MarenPlatform` database is stale** against the
current scripts. `Content.ContentTargetingRule` does not exist in it and
`TargetingDimension` lacks columns the source defines, because it was deployed
from the pre-fetch checkout. Maren's staging database needs redeploying from
`813fd15` before any targeting work is tested against it.

---

## 7. Open decisions

- **PD-1 — privacy and sync.** The app makes 3 GETs and zero writes; no user
  data leaves the device. Stated direction is an **on-device AI model
  (photo/video → health signals) running locally**, which would preserve that
  guarantee. Nothing in any repo implements it. Until it is written down, the
  Coach, Prediction and Recommendation engines cannot personalise from observed
  behaviour, because they never observe any.
- **Life stage: declared or inferred?** The backend exposes
  `PUT /me/life-stage`, implying she declares. Inference cannot know she is
  pregnant. Likely: she declares transitions, behaviour adapts the rest.
- **Content ownership.** Who authors for eleven life stages? This is the
  critical path and it is not engineering.
- **Profile photos, cover photos, posts.** Measured as absent from every repo —
  no media dependency, no upload path, no social tables. If intended, they are a
  new capability across mobile, API, storage and moderation, and they change the
  privacy posture that the on-device-AI direction is meant to protect.

---

## 8. Independence verification

**Measured at seed time:**

- Five repos, five distinct remotes, no shared origin
- `WLOS_App` contains zero `.cs` files and zero `web-admin` paths
- `WLOS_FrontEnd` contains zero `.dart` files and zero `mobile/` paths
- `WLOS_App` head `3a8da93` is **not reachable** from `Maren-Frontend/main`
- Full history preserved — `WLOS_Backend` reaches `ef25b94`, `WLOS_App`
  `8a6a6b5`, `WLOS_FrontEnd` `ef9747e`
- No keystores, signing keys or credentials in any tree

**Two items that are not clean:**

1. `WLOS_FrontEnd/vite.config.ts:19` carries
   `allowedHosts: ['maren-app.hamzadecor.com']` — Maren hosting config in a WLOS
   repo. Inert, one line.
2. `WLOS_Backend` references Maren repo URLs in 20 files — 19 Markdown, 1 YAML,
   **zero `.cs`**. Documentation pointers, no code coupling.

---

## 9. Recommended sequence

Dependency-aware. Nothing here is UX redesign; that follows the IA and
life-stage phases.

**Step 1 — carry the analysis across (hours)**
Copy `WLOS_MOBILE_REORIENTATION_AUDIT.md` and `WLOS_MIGRATION_PLAN.md` into
`WLOS_App/docs/`. They are the mobile plan of record and currently exist only in
Maren.

**Step 2 — product identity, hard parts only (small)**
`applicationId`, `namespace`, `android:label`, `CFBundleName`, pubspec name, and
a real signing config. Enough that a WLOS build installs beside Maren. Leave the
.NET namespaces alone.

**Step 3 — runtime separation (small, blocks hosting)**
WLOS database name, ports, connection string, signing key, hostnames. Redeploy a
WLOS database from `813fd15` scripts.

**Step 4 — migrate the 325 snippets into the CMS with targeting (the big one)**
Load `wellness_library.dart` into `Content.ContentItem` with `life_stage` rules.
This alone converts a stage-blind rotation into stage-appropriate content, and
it is the first change a 16-year-old and a 63-year-old would both notice.

**Step 5 — author for the eleven under-served stages**
The critical path. Authoring, not engineering.

**Step 6 onward — IA, life-stage model, UX**
Per the agreed phase order, after the above.

**Later — notifications and adaptive reminders**
Backend slice. Requires signals that do not exist. Sequence last, and it must
consume `Behaviour` observations rather than compute its own.

---

## 10. Summary

**Ready:** the platform. 10 targeting dimensions, 12 life stages, 8 role modes,
neutral schemas, 24-stage pipeline running clean, 68 endpoints, three repos that
build.

**Not ready:** the content. 6 items in the CMS, 325 untargetable snippets in the
app, and no author assigned for eleven life stages.

**Blocking a WLOS build:** the shared `com.ostrevo.maren` application id and
debug signing.

**Blocking WLOS hosting:** shared database name and ports with Maren.

**Blocking the adaptive vision:** PD-1, and a notifications backend that is four
tables and no procedures.

The honest summary is that WLOS is much further along than a new product
normally is, because it inherited a platform built for it — and that the
remaining work is disproportionately **content and product decisions**, not
architecture.
