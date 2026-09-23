# WLOS Implementation Cost Map

**Date:** 23 September 2026
**Measured against:** deployed `WlosPlatform` · `WLOS_Backend` `39dbca3` · `WLOS_App` `7b8c7ec`
**Status:** reference artifact. **Nothing in this document is authorised to be built.**

---

## 0. What this document is, and what it is not

The product is in frozen discovery. `PROJECT_STATE.md` §9.0 suspends implementation
until the Phase A Findings Report exists, and §9.1 makes the one next action
recruitment, not engineering.

**This is a cost map, not a plan.** Its only purpose is that when evidence
arrives, the team can size the work in an afternoon instead of re-deriving it
from the schema. It is written now precisely *because* nothing is being built:
measuring is cheap while the code is still, and a measurement taken during
construction is already stale.

It contains:

- no sequence
- no calendar estimate, in days, weeks or sprints — the product is not defined,
  so any duration would be fiction dressed as evidence
- no recommendation to start anything
- no design

Relative size only: **trivial · small · medium · large · unknown**.

**A line item in this document is not a decision that the item should exist.**
Several items priced here may never be built, because the Findings Report may
say the product is a different product.

---

## 1. Classification key

Exactly one classification per line item, per tier.

| Class | Meaning |
|---|---|
| **EXISTS** | Measured present and working. The tier's requirement is already met. No work. |
| **REUSE** | Present and correct in shape. Meeting the tier needs configuration, seed rows or wiring only — no new structure. |
| **MODIFY** | Present, but its current shape is wrong for the tier and must change. |
| **BUILD** | Absent. Measured absent, not assumed absent. |
| **UNKNOWN** | The cost cannot be stated, because it depends on a product decision that has no evidence behind it. **An UNKNOWN is not a large. It is a refusal to guess.** |

### Size key

| Size | Meaning |
|---|---|
| trivial | A seed row, a flag, a config value, a single call site |
| small | One table or one screen, contained, no cross-cutting change |
| medium | Several tables or screens, or one cross-cutting contract touched in one place |
| large | A new subsystem, or a contract enforced in many places |
| unknown | See above |

---

## 2. How this was measured

Direct queries against the deployed database and direct reads of the two
repositories. Nothing below is inferred from documentation, including from the
documentation in this same folder.

**Database — `WlosPlatform`, measured 23 September 2026**

| Measure | Value |
|---|---|
| Tables | **87** |
| Stored procedures | **107** |
| Functions and table-valued functions | **23** |
| Deployment journal rows | **57** |
| Registered users | **0** |

**Seed and content state**

| Object | Rows |
|---|---|
| `Content.ContentItem` | **6** |
| `Content.ContentTranslation` | 6 |
| `Content.ContentTargetingRule` | **0** |
| `Content.TargetingDimension` | 10 |
| `Content.LifeDomain` | 28 (22 root + 6 child) |
| `Identity.LifeStage` | 12, all `IsSelectable` |
| `Identity.RoleMode` | 8 |
| `Identity.Country` | 11 |
| `Identity.Language` | 7 |
| `Identity.Permission` / `Role` / `RolePermission` | 31 / 8 / 56 |
| `Intelligence.StateDimension` | 9 |
| `Knowledge.Signal` / `SignalRelation` / `SignalRule` | 12 / 13 / 7 |
| `Coach.ToneProfile` / `ToneRule` | 4 / 5 |
| `Timeline.EventType` | 32 |
| `Administration.FeatureFlag` | 9 |
| `Notifications.Template` / `TemplateTranslation` / `Campaign` / `Delivery` | **0 / 0 / 0 / 0** |
| `AI.SafetyEvent` | **0** |
| `Health.ShareGrant` and every other `Health.*` table | **0** |

**Backend code**

- 10 controllers, **68 HTTP endpoints** (counted from attributes, matching
  `PROJECT_STATE.md` §4 exactly)
- 24 pipeline stages, of which **3 are `UnbuiltStage`**:
  `notificationResolution`, `conversationContextResolution`, `aiContextResolution`
- 6 MediatR pipeline behaviours: Logging, Authorization, FeatureFlag,
  Validation, Caching, Transaction
- 57 ordered SQL scripts in `src/Maren.Database`
- 18 test files, **222 test methods**
- **Zero stored procedures in the `Health` schema. Zero `Health.*` references in
  any `.cs` file.** The tables exist; nothing reads or writes them.
- No AI client of any kind: no `openai`, `anthropic` or equivalent reference in
  any source file

**Mobile code**

- 141 Dart files, 21 screens, 6-tab shell, **480 test cases** across 48 files
- **3 of 68 endpoints consumed**, all GET: `/api/v1/me/today`,
  `/api/v1/client/content/delta`, `/api/v1/config/bootstrap`
- **No sign-in surface.** `AuthTokenProvider` in
  `lib/features/today/data/platform_today_repository.dart` is a seam that
  returns null; the ordinary case is `TodayUnavailable.notSignedIn`
- **No upload path.** `pubspec.yaml` describes the client as download-only
- Local store: Drift, **20 tables**, all pregnancy-shaped
- Bundled content: **325 snippets** in `lib/features/content/data/wellness_library.dart`
- Localisation: **3 locales, all English** (`en`, `en_GB`, `en_US`); 90 keys in
  `app_en.arb`, 3 each in the two variants
- Notifications: local only (`flutter_local_notifications`, `zonedSchedule`,
  `POST_NOTIFICATIONS`)

### 2.1 A measured finding not previously recorded

Four tables in `WlosPlatform` lack the audit-contract columns. Two are documented
exemptions (`Audit.AuditLog`, `AI.SafetyEvent` — append-only by design). One is
the exemption register itself. **The fourth is `Content.ContentTargetingRule`,
and it is not exempt.**

`sys.tables.create_date` shows why:

```
ContentItem          created 11:39:17
TargetingDimension   created 11:39:48     <- main deploy pass
ContentTargetingRule created 11:42:57     <- manual re-run of script 34
```

Script 74 applies the audit contract by cursor over `sys.tables`. It ran during
the main pass, before the manual re-run created the rules table, so the table
missed it. It carries `CreatedBy` and `CreatedOn` only — **no `ModifiedBy`, no
`RowVersion`, no soft-delete columns**.

Consequence, stated without recommending action: **in the one deployed WLOS
database, changes to content targeting rules are outside the audit contract and
have no optimistic-concurrency column.** This is a second consequence of the
`ContentTargetingRule` deploy defect recorded in `WLOS_FOUNDATION.md` §2.8, and
that defect is FROZEN (§7 below).

---

## 3. Tier 1 — Minimal prototype

> **Purpose:** only enough to test whether a woman perceives value when WLOS
> connects two parts of her life. Throwaway code is acceptable at this tier.

The tier's governing property is that **it has no users**, so it owes nothing to
consent, deletion, export, audit, localisation or age assurance. That is what
makes it cheap, and it is the only tier where that is true.

**The single most important measured fact for this tier:** the join it must test
is a *read*, and the read path already exists end to end. `/me/today` resolves
through 24 stages and the app already renders it, including the explain sheet.
The expensive half of WLOS is the write path, and Tier 1 does not need it.

| # | Item | What this tier requires | Class | Size | Evidence / note |
|---|---|---|---|---|---|
| 1 | **Identity and auth** | None. Device-local, no accounts | EXISTS | trivial | App runs with no account today; the auth seam returns null and the screen degrades honestly |
| 2 | **Profile** | A name and a date of birth, on device | MODIFY | small | `Identity.Profile` carries `PartnerTerm`, `BabyTerm`, `ExpectingMultiples` — pregnancy-shaped. On-device onboarding is the Maren pregnancy flow |
| 3 | **Life stage** | She declares one stage; it changes what she sees | BUILD | small | Backend is REUSE (12 stages, `usp_UserLifeStage_Set`, history with `Source`). **Mobile has no screen that sets or reads `lifeStageCode`**; `features/life_profile` is a controller and an in-memory repository with no UI |
| 4 | **Context assembly** | One object carrying stage + one other dimension | EXISTS | trivial | `ResolveLifeOsHandler` over `LifeOsRepository`. **One assembly point** — the single most valuable architectural fact in the platform |
| 5 | **Targeting** | Content filtered by that object | REUSE | trivial | `fn_TargetedItems` works: 3 operators, OR within / AND across, unknown never excluded, no-rules means universal. Zero rules exist; a prototype needs a handful of seed rows |
| 6 | **Content delivery** | Enough content that the join is visible at all | EXISTS | trivial | 325 snippets already bundled on device with deterministic rotation. Server holds 6 items — **the server is the smaller library** |
| 7 | **Needs** | She says what she needs now | BUILD | small | Nothing exists. Backend cost is a reference table, a user table with expiry, and an eleventh `TargetingDimension` seed row. A throwaway on-device picker is smaller still. **FROZEN** |
| 8 | **Preferences and boundaries** | One hard-coded boundary, to prove the shape | BUILD | small | Nothing exists anywhere. The only per-user preference tables are `Identity.Profile` and `Health.BirthPreference` (pregnancy-specific); `Administration.Setting` has no `UserId`. **FROZEN** |
| 9 | **Personalization controls** | Not required | BUILD | small | Filters on the context object at the one assembly point. Cheap here, cross-cutting later. **FROZEN** |
| 10 | **Explainability surface** | Every card answers "why am I seeing this" | EXISTS | trivial | `today_screen.dart` already opens an explain sheet; `LifeDecision` carries the explain payload; `Coach.Explained` and 6 Inspector endpoints exist server-side |
| 11 | **Mobile shell** | Something to hang the screen on | EXISTS | trivial | 6 tabs, 21 screens, 480 tests passing |
| 12 | **One screen** | The Today screen | EXISTS | trivial | 467 lines, renders exactly one endpoint, with honest offline and staleness states. **Changing it is FROZEN** |
| 13 | **Sync** | Not required | EXISTS | trivial | Content delta download works. Write sync is absent and not needed here |
| 14 | **Offline** | The screen survives no network | EXISTS | trivial | Drift store, 20 tables; cache written only on success, so a failed fetch never costs her the day she could see a minute ago |
| 15 | **Notifications** | Local only, if any | EXISTS | trivial | `zonedSchedule`, permission request, boot-completed receiver. Server side is absent |
| 16 | **AI safety boundary** | No generation. Nothing to bound | EXISTS | trivial | No AI client in any source file. `aiContextResolution` is a deliberate `UnbuiltStage` reading *"Guardrails ship before generation."* **The boundary holds only while nothing generative ships** |
| 17 | **Audit** | Not required at this tier | EXISTS | trivial | Append-only log applied by cursor over `sys.tables`, so a new table is audited by default. See §2.1 for the one hole |
| 18 | **Privacy operations** | On-device export, so a participant can take her data | EXISTS | trivial | `BackupService` exports and re-imports with a SHA-256 checksum and a hand-maintained table list, so a new table cannot join the export unnoticed |
| 19 | **Localisation** | English, one market | EXISTS | trivial | 3 English locales. 90 ARB keys across 21 screens implies substantial hardcoded copy — measured as a count, not audited |
| 20 | **Country safety configuration** | Not required. One country, researcher present | BUILD | trivial | Absent. Deliberately out of scope at this tier |

**Tier 1 shape:** two MODIFY, three BUILD, everything else already standing. The
prototype is not blocked by architecture. It is blocked by evidence, which is the
correct blocker and the one §9.1 names.

---

## 4. Tier 2 — MVP

> **Purpose:** enough for a real limited release to real users.

The moment there are real users, three things become non-optional that Tier 1
could ignore: **an account, a write path, and the ability to leave.**

| # | Item | What this tier requires | Class | Size | Evidence / note |
|---|---|---|---|---|---|
| 1 | **Identity and auth** | Real accounts, sessions, revocation | **BUILD** | **medium** | Backend is REUSE: register / login / refresh, JWT bearer, security-stamp revocation, 31 permissions over 8 roles, permission-based `AuthorizationBehavior`. **Mobile is BUILD**: no sign-in screen, no token store, no secure-storage dependency in `pubspec.yaml`, no refresh handling |
| 2 | **Profile** | Neutral profile, not a pregnancy profile | MODIFY | small | Drop or gate `PartnerTerm` / `BabyTerm` / `ExpectingMultiples`; `usp_Profile_Save` already treats null as unchanged, which the app side must preserve |
| 3 | **Life stage** | She sets it, changes it, sees the history | BUILD | small | Backend REUSE (`usp_UserLifeStage_Set`, `_GetHistory`, `Source` column). Mobile UI is the whole cost |
| 4 | **Context assembly** | Unchanged | EXISTS | trivial | One assembly point holds for everything below |
| 5 | **Targeting** | Real rules on real content | REUSE | small | Evaluator is done. Cost is editorial, not engineering. **But see §7: a clean deploy does not create the rules table, and the fix is frozen — so the environment is not reproducible** |
| 6 | **Content delivery** | A library worth opening | **UNKNOWN** | **unknown** | 6 items server-side; 11 of 12 life stages have no content. `WLOS_FOUNDATION.md` §3 shows ~165–185 of the app's 325 snippets are universal and could migrate with no rules, and 36 (11%) **must** be gated before a non-pregnant user sees them. Volume required is a product decision with no evidence behind it. **Content expansion is FROZEN** |
| 7 | **Needs** | Self-reported, decaying | BUILD | small | Structure is small and known. **The taxonomy and the decay window are UNKNOWN** — "hours" is a constitutional principle, not a measured number. **FROZEN** |
| 8 | **Preferences and boundaries** | Boundary beats inference, everywhere | **BUILD** | **medium** | The whole reason it is medium rather than large is that there is exactly one assembly point today. Built after features, it becomes an enforcement point per feature. **FROZEN** |
| 9 | **Personalization controls** | She can switch dimensions off, and it degrades gracefully | BUILD | medium | Each toggle removes a dimension from the context object. `AI learning OFF` decomposes into at least four distinct controls — **which four is UNKNOWN**. **FROZEN** |
| 10 | **Explainability surface** | Every surface, not just Today | REUSE | small | The contract exists on every decision; extending it costs UI, not architecture |
| 11 | **Mobile shell** | Navigation that matches the product | **UNKNOWN** | **unknown** | The 6 tabs are Maren's information architecture. Whether WLOS has tabs at all depends on what the Findings Report says the product is |
| 12 | **One screen** | Today, fed by live context | EXISTS | trivial | Already built. **FROZEN for further work** |
| 13 | **Sync** | Her data reaches the server and survives two devices | **BUILD** | **large** | The single largest line in this document. Absent: upload transport, queue, idempotency, delta cursors for user data, and **every server-side write procedure for user records — there are zero stored procedures in the `Health` schema**. Present and reusable: `ConflictResolver`, which is pure logic with a per-record-type strategy and refuses last-write-wins for append-only observations, plus `usp_Timeline_GetDelta` and `usp_Content_GetDelta` as precedent for the read direction |
| 13a | **Sync opt-in or mandatory** | A policy, before the transport | **UNKNOWN** | **unknown** | The WLOS analogue of Maren's unresolved PD-1. It determines the data-safety declaration, the GDPR basis and the privacy claims, and it cannot be answered by engineering |
| 14 | **Offline** | Offline-first, with a real store | EXISTS | small | Drift store works. Cost is extending the schema to whatever WLOS actually records, which is undefined |
| 15 | **Notifications** | Server-driven, tied to what she is doing | BUILD | medium | 4 tables, **0 rows, 0 procedures**, and `notificationResolution` is an `UnbuiltStage`. §1.9 of the constitution independently bars notifications unrelated to what she is actually doing, which narrows what may be built here |
| 16 | **AI safety boundary** | Guardrails, if anything generative ships | REUSE→BUILD | medium | `AI.SafetyEvent` records `Decision`, `RefusalCategory`, `ClinicalScore`, `CrisisScore`, `PromptVersion`, `ModelId` — a reviewable ledger built before any model. **The ledger exists; the guardrail that writes to it does not, and neither does any model integration.** Whether WLOS generates at all is a product decision |
| 17 | **Audit** | Real access recorded, including operator access | EXISTS | small | Append-only, refusals audited as well as successes, applied by default to new tables. §2.1 is the one measured hole |
| 18 | **Privacy operations** | Export and delete, on request | **BUILD** | **medium** | **None of the 107 stored procedures exports a user or deletes one.** And a contract conflict must be resolved first: the audit contract gives **83 of 87 tables** `IsDeleted` soft-delete columns, while §1.3 of the constitution says *deletion means deletion — not a flag*. Reconciling that is a change to a cross-cutting contract, not a feature |
| 19 | **Localisation** | Whatever the launch market speaks | MODIFY | medium | Strong foundations: `Language.IsRightToLeft`, `ContentTranslation.IsMachineTranslated`, `ContentReview`, `ContentPublishSchedule`. Mobile is 3 English locales and 90 keys. **Which languages is UNKNOWN — country selection is frozen** |
| 20 | **Country safety configuration** | Emergency pathway for the launch market | BUILD | medium | `Identity.Country` holds `IsoCode`, `Name`, `DefaultLanguageCode`, `IsSupported` and nothing else. No emergency number, no crisis pathway, no healthcare model, no regulatory profile, no units, no calendar. **FROZEN** |
| 21 | **Age assurance** | Some gate, of some kind | **UNKNOWN** | **unknown** | `Identity.Profile.DateOfBirth` is the only age input and nothing verifies or gates on it. 16+ and 18+ both remain candidates and no decision has been made. The EU KIDS Act makes the consequences of the two answers structurally different, not merely numerically different |

**Tier 2 shape:** one large (write sync), five medium, and **five UNKNOWNs that
are not engineering questions at all.** A team that priced this tier today would
be pricing five product decisions as though they were tickets.

---

## 5. Tier 3 — Production foundation

> **Purpose:** what is required for safe international production — consent,
> deletion, export, audit, localisation, regulatory boundary, age assurance.

Tier 3 differs from Tier 2 in kind, not degree. Tier 2 items are features. **Most
Tier 3 items are contracts that must hold in every place, forever**, and a
contract enforced in one place is cheap while a contract enforced in fifty is
not. That is the entire economic argument of this section and the reason
`PROJECT_STATE.md` §5 calls preference and boundary *"medium — do first"*.

| # | Item | What this tier requires | Class | Size | Evidence / note |
|---|---|---|---|---|---|
| 1 | **Identity and auth** | Recovery, lockout, session revocation, device trust | REUSE | medium | Lockout, security-stamp rotation, revocation list and refresh-token redemption all exist. `Identity.Device` exists with `FcmToken` and `LastSyncUtc`. Recovery flows and their abuse cases are the gap |
| 2 | **Consent record** | A record of what she agreed to, when, and under which version | **BUILD** | **medium** | **Measured absent.** `Identity.Profile` records acceptance of terms as profile state, not as a versioned consent ledger. Without it, export, deletion, GDPR basis and age assurance each lack the thing they cite |
| 3 | **Profile / life stage** | Correctable, and visibly hers | REUSE | small | §1.3 requires she can see what WLOS believes about her and correct it. `Source` on `UserLifeStage` already distinguishes declared from derived, which is the hard half |
| 4 | **Context assembly** | Every consumer reads context through the filter, with no bypass | MODIFY | medium | One assembly point today. Its value is entirely conditional on it staying one |
| 5 | **Targeting** | Reproducible across environments | **MODIFY** | **small** | The engineering fix is small and reproduced. **It is frozen, and the freeze is correct**: it blocks no interview. But every environment built before it is fixed inherits §2.1 |
| 6 | **Content delivery** | Reviewed, expiring, translated by humans where clinical | MODIFY | medium | `ContentReview` records that a review happened; **nothing records when guidance stops being current.** An international platform serving clinical content without a review-by date will eventually serve stale guidance in a market whose guidelines moved |
| 7 | **Needs / intent / response mode** | Stable taxonomy across languages | **UNKNOWN** | **unknown** | `Coach.ToneProfile` covers *how* WLOS speaks (4 tones). *Listen*, *Help me decide* and *Help me plan* change **what the system does**, not the phrasing, and none exists. **FROZEN** |
| 8 | **Preferences and boundaries** | Boundary beats inference at every call site, provably | BUILD | medium→large | Medium if built at the assembly point. **Large if retrofitted**, and the enforcement point that is missed is the one that shows pregnancy content to a woman who asked never to see it again. **FROZEN** |
| 9 | **Personalization controls** | Each control provably removes a dimension; graceful degradation tested | BUILD | medium | The pipeline already has a `noResult` discipline to model this on |
| 10 | **Explainability surface** | Regulator-legible, not just user-legible | REUSE | medium | Explain contract on every decision, plus `SignalRelation` using `commonly_precedes` / `commonly_co_occurs` with `Strength` and `SourceNote` — deliberately non-causal language, already implemented |
| 11 | **Mobile shell** | Accessibility, RTL layout, dynamic type | MODIFY | medium | RTL is modelled in the database; **no RTL locale has ever been rendered by this app** |
| 12 | **One screen → many** | Zero dead UI | REUSE | medium | `lib/features/today/MIGRATION.md` already lists every legacy widget's disposition. The audit it records found two screens reachable by nobody, both with passing widget tests |
| 13 | **Sync** | Conflict-safe, resumable, auditable, cross-device | BUILD | large | As Tier 2, plus audit of every write and reconciliation of §2.1 |
| 14 | **Offline** | Encryption at rest, key handling, safe wipe | BUILD | medium | The Drift store is unencrypted and the device may be shared. §1.7 exists because *the person she most needs privacy from is sometimes the person asking for access* |
| 15 | **Notifications** | Localised, quiet-hours aware, constitutionally compliant | BUILD | medium | `TemplateTranslation` exists and is empty. §1.9 bars streaks that penalise non-return and anything rewarding frequency for its own sake; **streak redesign is FROZEN** |
| 16 | **AI safety boundary** | Refusal taxonomy, crisis routing, model and prompt versioning | REUSE→BUILD | large | The ledger is genuinely ahead of the field. What is absent is everything that would write to it, and crisis routing is meaningless without item 20 |
| 17 | **Audit** | Complete, append-only, operator access included | MODIFY | small | **One table is outside the contract and is not exempt** (§2.1). Closing it requires the frozen deploy fix |
| 18 | **Privacy operations** | Export in a readable format without asking; deletion that is deletion | **BUILD** | **large** | Across 87 tables, with the soft-delete contract reconciled, backups and restore drills in scope (`Ops.RestoreDrill` exists), and deletion propagating to anything shared. §1.3 states this operationally, not rhetorically |
| 19 | **Localisation** | Real languages, RTL, units, calendars, formats | MODIFY | large | Foundations are unusually good. The volume is content, not code, and the content volume is UNKNOWN |
| 20 | **Country safety configuration** | Emergency numbers, crisis pathways, healthcare model, regulatory profile | BUILD | medium | *"The difference between supports many countries and is safe in many countries."* **FROZEN** |
| 21 | **Regulatory boundary** | Intended use controlled across product, AI, content **and marketing copy** | **UNKNOWN** | **unknown** | §1.10 governs four layers, and layer 4 is store and marketing copy. Classification follows **intended use and marketing copy, not technology** — so this cost is a function of the claims made, and no claims have been decided |
| 22 | **Age assurance** | A verifiable gate matched to the launch jurisdiction | **UNKNOWN** | **unknown** | Italy's Garante fined Replika's developer €5M partly over age verification **despite an 18+ policy** — a stated policy was not a defence. Cost is unknowable until launch age and market are decided |
| 23 | **Support network / relationships** | Account-to-account, with trust and emergency roles | **UNKNOWN** | **large at minimum** | `Health.ShareGrant` is a sound consent primitive — scoped, expiring, revocable, view-counted, and **asymmetric in the right direction: she can see who looked; the recipient cannot see that she looked.** Everything else is absent. §1.7's three safety rules must be settled *before* the model, not after |
| 24 | **Camera** | Policy before subsystem | **UNKNOWN** | **unknown** | Nothing exists: no media dependency, no permission, no capture path. `AvatarMediaId` is a column with no upload behind it. **This is the one item where the ordering is currently right**, and §1.5 already forbids inferring emotion from an image of her face. **FROZEN** |

---

## 6. Where the money actually is

Four observations that survive whatever the Findings Report says.

**1. The read path is built and the write path is not.** 68 endpoints, 107
procedures, 24 pipeline stages — and the app consumes 3 endpoints, all GET, and
uploads nothing. **There are zero stored procedures in the `Health` schema and
zero `Health.*` references in any C# file.** Every user-generated record WLOS
would collect has tables waiting and no server-side path to reach them. Anything
that sounds like "let her record something and see it on another device" is the
large line, every time.

**2. Content is the project, and it is not an engineering cost.** 22 domains, 10
dimensions, 12 stages, 24 stages, 68 endpoints — and **6 content items**. The app
carries 325 snippets the server does not have. The constraint is editorial, and
no amount of architecture moves it.

**3. Two contracts contradict each other and neither is a feature.** The audit
contract puts `IsDeleted` on 83 of 87 tables; §1.3 says deletion means deletion.
That is resolved once, centrally, before there is data to delete — or fifty times
afterwards.

**4. The one assembly point is the whole economic argument.** Preference,
boundary and personalization controls are `medium` **only because**
`ResolveLifeOsHandler` is the single place context is built. Every feature added
before them that reads context directly converts that medium into a large. This
is an observation about cost, **not an argument for starting** — §9.0 freezes
these items and §7 below restates that.

---

## 7. FROZEN — must not be started, however cheap they look

`PROJECT_STATE.md` §9.0 lists sixteen items, none authorised, all waiting on the
Phase A Findings Report:

> `ContentTargetingRule` fix · Need implementation · preference and boundary
> tables · personalization controls · response modes · content expansion · Today
> screen · AI implementation · camera implementation · relationship model ·
> country safety configuration · market ranking · country selection · pricing ·
> B2B2C implementation · streak redesign

**A recommendation in a research document is not authorisation to build**, and
that includes every recommendation in this document, which contains none.

Mapping the freeze onto the line items priced above:

| Frozen item | Line items it blocks | Note on temptation |
|---|---|---|
| `ContentTargetingRule` fix | T2-5, T3-5, T3-17 | Small, reproduced, and it is the **highest-priority backend defect on record** — which is exactly why it will look safe to do "while waiting". It blocks no interview. It stays frozen |
| Need implementation | T1-7, T2-7, T3-7 | A reference table and a seed row. Trivially cheap, and the taxonomy is unvalidated |
| Preference and boundary tables | T1-8, T2-8, T3-8 | The one item that is genuinely cheaper now than later. **That argument is not authorisation.** It is the argument most likely to be mistaken for one |
| Personalization controls | T1-9, T2-9, T3-9 | Filters at one call site |
| Response modes | T3-7 | Tone exists; intent does not |
| Content expansion | T2-6, T3-6, T3-19 | ~165 snippets could migrate with no rules and zero behavioural change. Still frozen |
| Today screen | T1-12, T2-12 | **It already exists.** The freeze is on changing it, which is the easier freeze to forget |
| AI implementation | T2-16, T3-16 | The ledger exists and invites use |
| Camera implementation | T3-24 | Nothing exists; policy is correctly ahead of code |
| Relationship model | T3-23 | Safety rules first, per §1.7 |
| Country safety configuration | T2-20, T3-20 | 4 columns today |
| Market ranking · country selection | T2-19, T3-19, T3-22 | Also blocks knowing which languages |
| Pricing · B2B2C implementation | not priced here | Out of scope; both unresolved |
| Streak redesign | T3-15 | Inherited from Maren and constitutionally non-compliant as it stands |

**Ten of the twenty-four Tier 3 line items are frozen in whole or in part.** The
cost map is therefore mostly a map of things that may not be touched — which is
the correct state for a product in frozen discovery, and the reason this document
carries no sequence.

---

## 8. The UNKNOWNs, and what would retire each

An UNKNOWN here is an item whose cost depends on a decision no evidence
supports. Listing what would resolve each is not a plan to resolve them.

| UNKNOWN | Why it cannot be sized | What retires it |
|---|---|---|
| Content volume (T2-6) | Nobody knows how much content makes the join perceptible | Phase A item 3 — interaction evidence with verbatim chains |
| Mobile shell / IA (T2-11) | The 6 tabs are Maren's, not WLOS's | Findings Report item 13 — Phase B, narrow, or change the product |
| Sync opt-in vs mandatory (T2-13a) | Determines data-safety declaration, GDPR basis, privacy claims | A policy decision, then legal review. The WLOS analogue of Maren's PD-1 |
| Needs taxonomy and decay (T2-7) | The ten needs are proposed, not observed; "hours" is a principle, not a measurement | Phase A items 4–6 — recurrence, gap, memory value |
| Personalization control granularity (T2-9) | One toggle hides at least four controls; which four is a design question with no data | Phase A item 7 — personalization need |
| Age assurance (T2-21, T3-22) | 16+ and 18+ are structurally different products, not different numbers | Legal review per jurisdiction, then the architectural question: **is a non-personalised, streak-free WLOS still WLOS?** |
| Regulatory boundary (T3-21) | Classification follows intended use and marketing copy; no claims are decided | Marketing and store copy reviewed against §1.5 and §1.9 before publication |
| Response mode / intent (T3-7) | *Help me decide* changes what the system does, and what it does is undefined | Phase A items 8–10 — trust, frequency, action taken |
| Support network (T3-23) | Consent half is sound; the safety rules that must precede the model are unsettled | §1.7's three rules, settled |
| Camera (T3-24) | Nothing exists and no use has been established | A written policy, before any subsystem |

**Ten UNKNOWNs. Seven of them are product or legal questions wearing engineering
clothes.** Pricing them as engineering is the specific failure this document
exists to prevent.

---

## 9. What this document does not say

- It does not say the prototype is cheap enough to start. §9.1 says recruit C4.
- It does not say preference and boundary should be built first. §9.0 freezes
  them. That the freeze has a cost is a fact, not a counter-argument.
- It does not rank the tiers by attractiveness. Tier 1 is the cheapest and it is
  still downstream of fourteen interviews that have not happened.
- It does not estimate anything in days or weeks, and a reader who converts
  `medium` into a calendar has reintroduced exactly the false precision the
  frozen state exists to avoid.

> **Nothing above is authorised. When the Phase A Findings Report exists, this
> document makes the estimate fast. Until then it makes no argument at all.**
