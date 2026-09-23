# WLOS Reuse Map — a measurement of existing platform capability

**Date:** 23 September 2026
**Measured against:**
- Deployed database `WlosPlatform` on `localhost` (Windows auth), queried directly
- Source at `D:\MobileApp\WLOS_Backend` (read only)
- Source at `D:\MobileApp\WLOS_App` (read only)

**Method:** direct `sqlcmd` queries against the deployed database, and reading
the actual source files. Nothing in this document is inferred from other
documentation. Where a claim in an existing document disagreed with the
database, the database is recorded and the disagreement is noted.

**What this document is not:** there are no recommendations here, no sequence,
no plan, no proposal and no design. Every sentence is either a measured fact or
an explicit statement that something could not be verified. Nothing was
modified. No migration was run. No code was touched.

**Classification vocabulary used throughout:**

| Term | Meaning as used here |
|---|---|
| **FULLY BUILT** | Tables exist, are seeded where seeding applies, a stored procedure reads or writes them, the API exposes them, and something consumes the API |
| **BUILT BUT UNCONSUMED** | Tables and procedures exist and are seeded, but no caller reaches them — either no C# references the procedure, or no client calls the endpoint |
| **PARTIAL** | Some layers exist and others measurably do not |
| **ABSENT** | No table, no column, no procedure, no endpoint. Verified by name search across `sys.tables` and `sys.columns` |

---

## 0. Headline counts, measured

| Thing | Count | How measured |
|---|---|---|
| Tables in `WlosPlatform` | **87** | `sys.tables` |
| Stored procedures | **107** | `sys.objects` where `type='P'` |
| Functions (scalar, inline TVF, multi-statement TVF) | **28** | `sys.objects` where `type IN ('FN','IF','TF')` |
| Stored procedures referenced by any `.cs` file | **83** | grep of `[Schema].[usp_Name]` across `src`, excluding `bin`/`obj` |
| Stored procedures referenced by **no** `.cs` file | **24** | set difference of the two above |
| API endpoints (`[Http*]` attributes across 10 controllers) | **68** | grep of `src/Maren.Api/Controllers` |
| API endpoints consumed by `WLOS_App` | **3** | grep of `api/v1` across `WLOS_App/lib` |
| Intelligence pipeline stages registered in DI | **24** | `Maren.Persistence/Repositories.cs:394-425` |
| Pipeline stages that are `UnbuiltStage` | **3** | `notificationResolution`, `conversationContextResolution`, `aiContextResolution` |
| Deployment journal rows | **57**, all `Outcome = 'succeeded'`, one `RunId` | `Ops.DeploymentJournal` |
| Users in the database | **0** | `Identity.User` |
| Content items | **6** | `Content.ContentItem` |

**The 24 stored procedures no C# file references:**

```
Content.usp_Content_GetTargetingRules      Ops.usp_Deployment_Record
Content.usp_Content_SetTargetingRules      Ops.usp_Deployment_Status
Content.usp_TargetingDimension_List        Ops.usp_RestoreDrill_Record
Dashboard.usp_Dashboard_ListCardTypes      Ops.usp_RestoreDrill_Status
Dashboard.usp_Inspector_SimulateBehaviour  Rules.usp_Rules_ListForScope
Identity.usp_Access_RotateSecurityStamp    Rules.usp_Rules_PruneOrphans
Identity.usp_Operator_Claim                Rules.usp_Rules_SetForTarget
Intelligence.usp_Intelligence_History      Timeline.usp_EventType_List
Intelligence.usp_Intelligence_ListDimensions  Timeline.usp_Timeline_Aggregate
Knowledge.usp_Knowledge_Related            Timeline.usp_Timeline_Delete
dbo.usp_ApplyAuditContract                 Timeline.usp_Timeline_Get
                                           Timeline.usp_Timeline_GetDelta
                                           Timeline.usp_Timeline_Record
```

`dbo.usp_ApplyAuditContract` is invoked by `74_AuditContract_Apply.sql` at
deploy time, not from C#; its absence from the C# set is expected.
The other 23 have no measured caller in either C# or any deployed SQL module.

---

## 1. Identity — users, profile, life stages, role modes

### Tables

| Table | Rows | Note |
|---|---|---|
| `Identity.User` | 0 | |
| `Identity.Profile` | 0 | `DisplayName, SelfTerm, PartnerTerm, BabyTerm, ExpectingMultiples, DateOfBirth, TimeZoneId, AvatarMediaId` |
| `Identity.LifeStage` | **12** | |
| `Identity.UserLifeStage` | 0 | `LifeStageCode, StartedOn, EndedOn, Source, Note` |
| `Identity.RoleMode` | **8** | |
| `Identity.UserRoleMode` | 0 | multi-select join |
| `Identity.Role` / `Permission` / `RolePermission` | 8 / **31** / 56 | operator RBAC |
| `Identity.Country` | **11** | `IsoCode, Name, DefaultLanguageCode, IsSupported` — four meaningful columns |
| `Identity.Language` | **7** | `Code, Name, IsRightToLeft, IsActive` |
| `Identity.Device`, `RefreshToken`, `SecurityStampRevocation` | 0 | |

`Identity.Profile` has **no country column**. Country reaches the targeting
context from the profile procedure as an id, resolved in
`Maren.Persistence/LifeOsRepository.cs:37`.

**12 life stages seeded:** `adolescence, young_adult, independent, partnership,
planning, pregnancy, postpartum, motherhood, midlife, perimenopause, menopause,
senior` — each with `SortOrder` 10..120, all `IsActive = 1`.

**8 role modes seeded:** `student, professional, freelancer, entrepreneur,
remote_worker, homemaker, caregiver, partner`.

**7 languages seeded:** `en-GB, en-US, es-ES, fr-FR, de-DE, ur-PK, ar-SA`.
`ur-PK` and `ar-SA` carry `IsRightToLeft = 1`. Measured mismatch: no seeded
country selects either as its `DefaultLanguageCode` — `PK` defaults to `en-GB`,
and no country maps to `ar-SA`. The two RTL languages are reachable only by
explicit selection, and no surface that performs that selection was found.

### Procedures

`usp_User_Register`, `usp_User_GetForLogin`, `usp_User_RecordLogin`,
`usp_User_Search`, `usp_User_GetDetail`, `usp_User_SetLockout`,
`usp_User_AssignRole`, `usp_User_RemoveRole`, `usp_User_GetPermissions`,
`usp_User_GetSecurityStamp`, `usp_User_RevokeSessions`, `usp_Profile_Get`,
`usp_Profile_Save`, `usp_LifeStage_List`, `usp_UserLifeStage_Set`,
`usp_UserLifeStage_GetHistory`, `usp_UserRoleMode_Set`, `usp_Device_Register`,
`usp_RefreshToken_Issue`, `usp_RefreshToken_Redeem`, `usp_Role_*`,
`usp_Permission_List`, `usp_Access_GetRevocations`,
`usp_Access_RecordSecurityEvent` — all referenced from C#.

Not referenced from C#: `usp_Operator_Claim`, `usp_Access_RotateSecurityStamp`.

### API

`AuthController` — `POST api/v1/auth/register`, `/login`, `/refresh` (3).
`OnboardingController` — `GET api/v1/me/onboarding/options`, `GET/PUT
api/v1/me/profile`, `PUT api/v1/me/life-stage`, `PUT api/v1/me/role-modes`,
`GET api/v1/me/life-stage/history`, `GET api/v1/me/today` (7).
`AccessController` — 15 admin endpoints over users, roles, audit, settings.

### Mobile

`WLOS_App` has **no sign-in surface**. `lib/home_shell.dart:90` wires the today
repository with `tokenProvider: () async => null`, a literal. The repository's
own comment at `lib/features/today/data/platform_today_repository.dart:14-17`
states that returning null "is the ordinary case today". Every call therefore
short-circuits to `TodayUnavailable.notSignedIn` before a request is issued.

`lib/features/life_profile/` exists and contains `life_profile_models.dart`,
`life_profile_repository.dart` (interface plus `InMemoryLifeProfileRepository`)
and `life_profile_controller.dart`. There is **no screen** in its `ui/`
directory, and a grep across `lib` and `test` outside that directory returns
**zero** references to it. Its own `README.md` states "Status: architecture
only. Not built, not analysed, not tested" and records that no network
implementation may be written pending PD-1.

**Classification:**
- Registration / login / token: **FULLY BUILT** (backend), **ABSENT** in mobile
- Profile, life stage, role modes, history: **BUILT BUT UNCONSUMED** — full
  table/procedure/endpoint chain exists; no client calls it, and the app module
  written against it is unreferenced by the app
- Operator RBAC: **FULLY BUILT** for the admin portal surface; all 31
  permissions are operator permissions. None is a user-facing control

---

## 2. Life stages (12) and their history

`Identity.UserLifeStage` carries `StartedOn`, `EndedOn`, `Source` and `Note` —
a closed interval with recorded provenance. `usp_UserLifeStage_Set` and
`usp_UserLifeStage_GetHistory` both exist and are both referenced from
`OnboardingController` (`PUT api/v1/me/life-stage`, `GET
api/v1/me/life-stage/history`).

`Identity.UserLifeStage` holds **0 rows** — no user exists.

`ContextResolutionStage` (`IntelligenceStages.cs:40`) emits the warning
`"No life stage set. Stage-targeted decisions will not reach her."` when
`LifeStageCode` is null, so the pipeline treats an unset stage as a first-class
state rather than an error.

**Classification: BUILT BUT UNCONSUMED.** Schema, history semantics, procedures
and endpoints are complete. No client writes or reads them.

---

## 3. Life domains (22 top level, 28 total, hierarchical)

`Content.LifeDomain` holds **28 rows**, not 22. Measured breakdown:

- **22 rows with `ParentDomainCode IS NULL`:** `beauty, career, community,
  emergency, family, finance, fitness, health, household, learning, lifestyle,
  medication, mental, nutrition, parenting, productivity, relationships,
  selfcare, shopping, sleep, spirituality, travel`
- **6 child rows:** `work → career`, `body → health`, `cycle → health`,
  `pregnancy → health`, `routine → lifestyle`, `hydration → nutrition`

All 28 are `IsActive = 1`. Five carry `IsHealthSensitive = 1`: `emergency`,
`health`, `medication`, `mental`, and the children `body`, `cycle`, `pregnancy`
(seven rows in total flagged).

Consumed by `Content.usp_LifeDomain_List`, referenced at
`Maren.Persistence/OnboardingRepository.cs:41`, exposed through
`GET api/v1/me/onboarding/options`. Not consumed by the mobile app (that
endpoint is not among the three it calls).

`DomainCode` is also the foreign key target for `Dashboard.CardType.DomainCode`
and `Timeline.EventType.Category`.

**Classification: BUILT BUT UNCONSUMED.** Fully seeded, hierarchical, wired
into three other subsystems by foreign key, reachable over the API, called by
nothing.

**Correction on the record:** existing documents state "22, hierarchical". The
measured row count is 28; 22 is the count of top-level rows.

---

## 4. Targeting — dimensions, rules, `fn_TargetedItems`

This area is the most significant measured divergence between the documented
model and the deployed one.

### What is seeded

`Content.TargetingDimension` — **10 rows**, all `IsActive`:

| Code | ValueKind | SortOrder |
|---|---|---|
| `life_stage` | string | 10 |
| `role_mode` | string | 20 |
| `age` | number | 30 |
| `country` | string | 40 |
| `language` | string | 50 |
| `season` | string | 60 |
| `goal` | string | 70 |
| `condition` | string | 80 |
| `module` | string | 90 |
| `week` | number | 100 |

### There are two rule stores, and only one is live

`Content.ContentTargetingRule` exists in `WlosPlatform` with **0 rows** and the
columns `TargetingRuleId, ContentItemId, DimensionCode, Operator, ValuesJson,
CreatedBy, CreatedOn`.

**No deployed SQL module references it.** Measured by querying
`sys.sql_modules` for `definition LIKE '%ContentTargetingRule%'` — the result
set is empty. No `.cs` file references it either.

`Rules.Rule` holds **8 rows** and is the store everything actually reads.
Columns: `RuleId, ScopeCode, TargetKey, DimensionCode, Operator, ValuesJson,
RuleNote`. `Rules.TargetScope` holds **5 rows**:

| ScopeCode | TargetTable | TargetColumn |
|---|---|---|
| `content` | `Content.ContentItem` | `ContentItemId` |
| `dashboardCard` | `Dashboard.CardType` | `CardTypeCode` |
| `goalTemplate` | `Growth.GoalTemplate` | `GoalTemplateKey` |
| `routine` | `Growth.Routine` | `RoutineKey` |
| `recommendation` | `Recommend.RecommendationType` | `RecommendationKey` |

**All 8 seeded rules have `ScopeCode = 'dashboardCard'`. Zero rules exist in
any other scope, including `content`.**

```
dashboardCard  baby_development   life_stage  in      ["pregnancy"]
dashboardCard  checklist_today    role_mode   in      ["homemaker","caregiver"]
dashboardCard  cycle_log          life_stage  not_in  ["pregnancy","menopause","senior"]
dashboardCard  exam_countdown     role_mode   in      ["student"]
dashboardCard  family_call        life_stage  in      ["senior","menopause","midlife"]
dashboardCard  kick_counter       life_stage  in      ["pregnancy"]
dashboardCard  study_focus        role_mode   in      ["student"]
dashboardCard  work_break         role_mode   in      ["professional","remote_worker","freelancer","entrepreneur"]
```

### The evaluator

`Rules.fn_Match(@ScopeCode, @ContextJson)` is the evaluator. Read from
`sys.sql_modules`, it implements three operators — `in`, `not_in`, `between` —
with OR within a dimension and AND across dimensions, and it declines to apply
`not_in` unless the context carries a value for that dimension. Its own comment:
*"An exclusion cannot be applied to something we do not know."* `between` uses
`TRY_CAST` so a malformed rule fails that rule rather than the query.

`Content.fn_TargetedItems(@ContextJson)` as deployed is **a thin wrapper over
`Rules.fn_Match`**, not an independent evaluator. Its full body:

```sql
SELECT ci.ContentItemId
FROM [Content].[ContentItem] ci
WHERE NOT EXISTS (
          SELECT 1 FROM [Rules].[Rule] r
          WHERE r.ScopeCode = 'content'
            AND r.TargetKey = CONVERT(NVARCHAR(100), ci.ContentItemId))
   OR EXISTS (
          SELECT 1 FROM [Rules].[fn_Match]('content', @ContextJson) m
          WHERE m.TargetKey = CONVERT(NVARCHAR(100), ci.ContentItemId));
```

Universal-by-default is confirmed: an item with no rule row in scope `content`
is returned to every context.

`Content.usp_Content_GetTargetingRules` and `usp_Content_SetTargetingRules`
also read and write `Rules.Rule`, not `ContentTargetingRule`. `SetTargetingRules`
delegates entirely to `Rules.usp_Rules_SetForTarget` with `@ScopeCode='content'`;
its header comment reads *"Unchanged signature and unchanged failure codes; the
storage moved beneath it."*

### Who calls what

Modules calling `Rules.fn_Match`, measured from `sys.sql_modules`:

```
Dashboard.fn_EligibleCards
Dashboard.usp_Inspector_ExplainCard
Recommend.usp_Recommendation_Resolve
Growth.usp_Goal_Offer
Growth.usp_Routine_Today
Content.fn_TargetedItems
```

Modules calling `Content.fn_TargetedItems`: **none**. C# files referencing it:
**none**.

The client content path does **not** use targeting. Reading
`Content.usp_Content_GetForClient` in full, it filters on
`ContentItem.MinAppVersion`, `CountryFilter` (a JSON array on the item),
`FromWeek`/`ToWeek`, `Season`, `PublishFromUtc`/`PublishUntilUtc` and
`Status='published'` — the pre-existing Maren column filters. Its own comment
distinguishes these as *"operational controls"* governed by an operator, from
text governed by approval. `usp_Content_GetDelta` feeds the same shape.

### What the pipeline puts into the targeting context

`ProfileResolutionStage` (`IntelligenceStages.cs:54-95`) composes
`@ContextJson` from exactly **four** of the ten dimensions:

- `life_stage` (when set)
- `role_mode` (one entry per role, repeated)
- `country` (when set)
- `language` (when set)

`age`, `season`, `goal`, `condition`, `module` and `week` are **never placed in
the context by the running pipeline**. They are seeded dimensions with no
producer. This was verified by reading the stage body, not inferred.

**Classification:**
- `Rules.Rule` / `Rules.TargetScope` / `Rules.fn_Match`: **FULLY BUILT** for
  the `dashboardCard` scope, and reached by dashboard, recommendation, goal
  offer and routine resolution
- `Content.ContentTargetingRule`: **ABSENT in effect** — present as an empty
  table with no reader anywhere in the deployed database
- `Content.fn_TargetedItems`: **BUILT BUT UNCONSUMED** — a correct wrapper with
  zero callers and zero rules in its scope
- `Rules.usp_Rules_ListForScope` / `SetForTarget` / `PruneOrphans`,
  `Content.usp_Content_GetTargetingRules` / `SetTargetingRules`,
  `usp_TargetingDimension_List`: **BUILT BUT UNCONSUMED** — no C# reference and
  no endpoint. There is no way to author a targeting rule through the API
- 6 of the 10 seeded dimensions: **PARTIAL** — targetable by the evaluator, but
  no code path supplies a value for them

---

## 5. Knowledge signals and signal relations

### Seeded

`Knowledge.Signal` — **12 rows**: `short_sleep, late_wake, high_stress,
low_mood, low_hydration, missed_breakfast, low_activity, high_screen_time,
long_work, low_selfcare, headache, symptom_reported`. Each carries
`DomainCode`, a user-facing `DescriptionText`, `IsHealthSensitive` and
`SortOrder`. Two are health sensitive: `headache`, `symptom_reported`.

`Knowledge.SignalRelation` — **13 rows**, columns `FromSignalCode`,
`ToSignalCode`, `RelationKind`, `Strength`, `SourceNote`.

**Three relation kinds are seeded, not two:**

| RelationKind | Rows |
|---|---|
| `commonly_precedes` | 6 |
| `commonly_co_occurs` | 4 |
| `may_relate_to` | 3 |

The three `may_relate_to` rows (`low_hydration→headache`,
`short_sleep→headache`, `low_activity→low_mood`) carry the distinct
`SourceNote` value *"Self-reported association only. Never presented as a
cause."* and the lowest `Strength` values (0.35–0.40). The other ten carry
*"Widely reported pattern; not clinically reviewed."* or, for
`high_stress→short_sleep`, *"Reported in both directions; see the reverse
edge."* No relation kind in the seed uses causal language.

`Knowledge.SignalRule` — **7 rows**, columns `SignalCode, MeasureCode,
Operator, Threshold, WindowDays, MinOccurrences, IsActive`. Thresholds:

```
short_sleep       sleep        lt   360      over 3 days, min 2
low_hydration     water        lt   1500     over 3 days, min 2
high_stress       stress       gte  4        over 3 days, min 2
low_mood          mood         lte  2        over 3 days, min 2
low_activity      steps        lt   3000     over 3 days, min 2
high_screen_time  screen_time  gt   300      over 3 days, min 2
long_work         work         gt   600      over 3 days, min 2
```

**Five of the twelve signals have no firing rule** and therefore cannot fire:
`headache`, `late_wake`, `low_selfcare`, `missed_breakfast`,
`symptom_reported`. Four of those five appear as endpoints of seeded relations
(`late_wake`, `missed_breakfast`, `low_selfcare`, `headache`), so four relation
edges reference a signal that no rule can raise.

### Procedures and consumption

`Knowledge.fn_EvaluateSignals` and `usp_Knowledge_EvaluateSignals` exist;
the latter is referenced at `Maren.Persistence/LifeOsRepository.cs:64` and runs
as pipeline stage `signalAnalysis`. `Knowledge.usp_Knowledge_Related` exists
and is referenced by **no** C# file — the relation graph has no reader.

No endpoint exposes signals or relations directly. `Dashboard.usp_Inspector_ListSignals`
exposes signal *configuration* to operators via `GET api/v1/admin/inspector/signals`.

**Classification:**
- `Knowledge.Signal` + `SignalRule` + evaluation: **FULLY BUILT** within the
  pipeline, for the 7 signals that have rules
- The other 5 signals: **PARTIAL** — reference rows with no firing path
- `Knowledge.SignalRelation`: **BUILT BUT UNCONSUMED** — 13 seeded edges with
  strength and provenance, and `usp_Knowledge_Related` has no caller in C# or
  in any deployed SQL module

---

## 6. Intelligence state dimensions

`Intelligence.StateDimension` — **9 rows**: `energy, focus, consistency,
wellness, balance, routine, momentum, load, risk`. Columns include `ValueKind`
(`score` or `categorical`), `BaselineScore` and **`UnknownText`**.

Four are `score` with a baseline (`energy` 70, `focus` 70, `consistency` 60,
`wellness` 70). Five are `categorical` with no baseline.

`UnknownText` is populated on all nine, with three distinct values:
`"Not enough logged to tell yet."` (7 dimensions), `"Needs a few days before
this means anything."` (`momentum`), `"Nothing to flag."` (`risk`).

`Intelligence.StateInput` — **24 rows**, mapping dimensions to timeline event
types with a weight. Nine source measures are used: `sleep` (7 dimensions),
`steps` (4), `water` (4), `work` (3), `screen_time` (2), `mood`, `stress`,
`family_time` (1 each).

`Intelligence.StateRule` — **19 rows**, columns `DimensionCode, SignalCode,
ScoreDelta, ValueCode, ValueText, ReasonText, IsActive`. Distribution:
`energy` 3, `focus` 3, `wellness` 3, `balance` 2, `consistency` 2, `load` 2,
`risk` 2, `routine` 2. **`momentum` has zero rules** — it is the one dimension
of nine with inputs but no rule to move it.

`Intelligence.UserStateSnapshot` — 0 rows. Columns `UserId, DimensionCode,
ForLocalDate, ValueCode, ValueText, Score, Confidence, Reason, EvidenceCsv,
ComputedUtc`.

### Consumption

`Intelligence.fn_ResolveState` and `usp_Intelligence_Resolve` exist;
`usp_Intelligence_Resolve` is referenced at `LifeOsRepository.cs:78` and runs as
pipeline stage `stateResolution`. `usp_Intelligence_History` and
`usp_Intelligence_ListDimensions` are referenced by **no** C# file. There is no
endpoint for state history or for listing dimensions.

The state readings reach the client only inside the `/api/v1/me/today` payload.
`WLOS_App` models them fully in `today_models.dart` as `LifeStateReading`
(`dimensionCode, displayName, valueCode, valueText, score, confidence, reason,
evidence, trend, previousScore`) — but that payload never arrives, because the
token provider is a null literal.

**Classification: PARTIAL.**
- Dimensions, inputs, rules, snapshot, resolution, pipeline stage: built and
  running
- `momentum`: **PARTIAL** — declared, given inputs, never moved by a rule
- History and dimension listing: **BUILT BUT UNCONSUMED**
- Delivery to a client: **ABSENT in effect** — the only carrier is `/me/today`,
  which the app cannot authenticate to

---

## 7. Timeline events and event types

`Timeline.EventType` — **32 rows** across **17 categories**. Categories are
`LifeDomain` codes. (Existing documents state "17"; 17 is the category count,
32 is the row count.)

```
body:        weight                          medication:    medication
cycle:       cycle_end, cycle_start          mental:        journal, meditation, mood, stress
fitness:     exercise, steps, walk, yoga     nutrition:     caffeine, meal
health:      appointment, symptom            pregnancy:     baby_movement
household:   shopping                        relationships: family_time
hydration:   water                           routine:       prayer
learning:    reading                         selfcare:      brush_teeth, face_care,
lifestyle:   screen_time                                    hair_oil, hair_wash, skin_care
sleep:       nap, sleep, sleep_quality       work:          work
```

Seven are `IsHealthSensitive = 1`: `weight`, `cycle_end`, `cycle_start`,
`appointment`, `symptom`, `medication`, `baby_movement`. Columns also carry
`ValueKind`, `DefaultUnit`, `IsCumulative`.

`Timeline.Event` — **0 rows**. Columns `EventId, UserId, EventTypeCode,
OccurredUtc, OccurredLocalDate, RecordedUtc, Source, ValueNumeric, ValueText,
Unit, MetadataJson` plus audit-contract columns.

### The measured gap

**Six timeline procedures exist and none is referenced by any C# file:**
`usp_Timeline_Record`, `usp_Timeline_Get`, `usp_Timeline_GetDelta`,
`usp_Timeline_Delete`, `usp_Timeline_Aggregate`, `usp_EventType_List`.

**No controller exposes a timeline route.** All 68 endpoints were enumerated;
none writes or reads an event.

Within SQL, `Timeline.Event` is read by exactly two modules: `Behaviour.fn_Measure`
and `Dashboard.usp_Inspector_SimulateBehaviour`.

`Timeline.Event` is therefore the sole input to signals, state, behaviour,
goals, recommendations, coaching and predictions — and **there is no path by
which a row can enter it**. Every downstream engine resolves against an empty
table by construction, not by coincidence of an empty database.

**Classification: BUILT BUT UNCONSUMED**, with the write path specifically
**ABSENT** at the API layer. The taxonomy (32 types, 17 categories, sensitivity
flags, units, cumulativeness) is complete and seeded.

---

## 8. Goals and growth

| Table | Rows |
|---|---|
| `Growth.GoalTemplate` | **5** |
| `Growth.GoalMeasure` | **10** (2 per template) |
| `Growth.Routine` | **1** |
| `Growth.UserGoal` | 0 |
| `Growth.GoalProgress` | 0 |
| `Growth.GoalKnowledge` | **0** |

**5 goal templates:** `steady_sleep`, `drink_more_water`, `move_most_days`,
`check_in_weekly`, `keep_evening_routine`. Each carries `DomainCode`,
`BaselineConfidence`, a horizon in days, a `MotivationPrompt` and a
`MeasurementNote`. The measurement notes are explicit about what is not being
measured — `steady_sleep`'s reads *"It describes your logging, not your sleep
quality."*

**10 goal measures**, each with `Operator`, `Threshold`, `Weight` and a
user-facing `MeasureText`, against `Behaviour` measure codes (`consistency`,
`streak_current`, `streak_best`, `days_since_last`).

**1 routine:** `evening_winddown`, subject `evening_routine`.

`Growth.GoalKnowledge` (`GoalTemplateKey, SignalCode, RelationText, SortOrder`)
is the join between a goal and the knowledge graph. It holds **0 rows** — the
link between goals and signals is declared in schema and never populated.

### Behaviour, the substrate goals measure against

`Behaviour.Subject` — **6**: `sleep, hydration, movement, skincare,
evening_routine, reflection`.
`Behaviour.MeasureType` — **15**: `consistency, days_active, days_since_last,
streak_current, streak_best, momentum, preferred_hour, hardest_hour,
rhythm_weekday_best, rhythm_weekday_worst, rhythm_month_best,
rhythm_season_best, completion_probability, dropoff_probability,
engagement_probability`.
`Behaviour.SubjectEvent` — 12; `Behaviour.SubjectMeasure` — 88.
`Behaviour.Observation` — 0.

### Consumption

`usp_Goal_ListTemplates`, `usp_Goal_Offer`, `usp_Goal_Adopt`, `usp_Goal_Resolve`,
`usp_Goal_SetStatus`, `usp_Routine_ListTemplates`, `usp_Routine_Today` — all
referenced from C#. `GoalController` exposes 7 endpoints including
`POST api/v1/me/goals` and `PUT api/v1/me/goals/{id}/status` — **the only
non-admin write endpoints for user data in the entire API**.

Not consumed by the mobile app.

**Classification: PARTIAL.**
- Templates, measures, offer/adopt/resolve, routines, endpoints: **FULLY BUILT**
  server-side
- `Growth.GoalKnowledge`: **PARTIAL** — table exists, zero rows, so no goal is
  connected to any signal
- Client consumption: **ABSENT**
- Note that goal progress is computed from `Behaviour`, which reads
  `Timeline.Event`, which has no write path (§7)

---

## 9. AI safety (`AI.SafetyEvent`)

`AI.SafetyEvent` — **0 rows**. Columns, measured with types:

```
SafetyEventId    bigint
OccurredUtc      datetime2
UserId           uniqueidentifier
Domain           varchar(30)
Decision         varchar(20)
RefusalCategory  varchar(40)
ClinicalScore    decimal(5,?)
CrisisScore      decimal(5,?)
PromptVersion    varchar(60)
ModelId          varchar(100)
LatencyMs        int
CorrelationId    uniqueidentifier
```

It is one of exactly **two** rows in `dbo.AuditContractExemption`, with the
recorded reason: *"Append-only by design, like Audit.AuditLog. No procedure
updates or deletes it and ai_safety_test.sql asserts that. Soft-delete columns
would advertise a capability that must never exist on a safety ledger."*

**No stored procedure or function in the deployed database references it.**
Measured by `sys.sql_modules` search for `%SafetyEvent%` — empty.
**No `.cs` file references it.** Measured by grep — empty.
No endpoint touches it.

The two pipeline stages that would produce it are declared unbuilt:

```
AiContextResolutionStage : UnbuiltStage("aiContextResolution",
    "No model integration. Guardrails ship before generation — see docs/ai/AI_PIPELINE.md.")
ConversationContextStage : UnbuiltStage("conversationContextResolution",
    "No conversation engine yet.")
```

There is also `src/Maren.Database/tests/ai_safety_test.sql`, which was not
executed as part of this measurement.

**Classification: BUILT BUT UNCONSUMED.** The ledger schema, the two-score
separation (clinical and crisis), the refusal category, the model and prompt
version columns, and the append-only exemption all exist. Nothing writes to it,
and the subsystem it would record does not exist.

---

## 10. Explainability and provenance — reason, evidence, confidence, source

This contract recurs across five engines. Measured column sets:

| Table | Reason | Evidence | Confidence | Other provenance |
|---|---|---|---|---|
| `Intelligence.UserStateSnapshot` | `Reason` | `EvidenceCsv` | `Confidence` | `ComputedUtc` |
| `Growth.GoalProgress` | `Reason` | `EvidenceCsv` | `Confidence` | `EngineVersion`, `ComputedUtc`, `MeasuresMet`/`MeasureCount` |
| `Recommend.Assembled` | `Reason` | `EvidenceCsv` | `Confidence` | `EnginesCsv`, `EngineVersion`, `ExpiresUtc`, `ComputedUtc` |
| `Coach.Explained` | `ToneRationale` | `EvidenceCsv` | `Confidence` | `ToneCode`, `EngineVersion`, `ExpiresUtc` |
| `Predict.Predicted` | `StatementText` | `EvidenceCsv` | `Confidence` | `ProbabilityPercent`, `WindowDays`, `SupportDays`, `EngineVersion` |

Additional provenance carriers measured elsewhere:

- `Identity.UserLifeStage.Source` — declared versus derived
- `Knowledge.SignalRelation.RelationKind` + `Strength` + `SourceNote`
- `Intelligence.StateDimension.UnknownText` — a per-dimension sentence for
  having no answer, populated on all nine
- `Intelligence.StateRule.ReasonText`, `Growth.GoalMeasure.MeasureText`,
  `Coach.ToneRule.ToneRationale` — human-readable rationale stored as
  configuration data, not generated at runtime
- `Content.ContentItem.SourceCitation`, `ReviewedUtc`, `ReviewedBy`
- `Content.ContentTranslation.IsMachineTranslated`
- `dbo.fn_CurrentCorrelation` and `CorrelationId` on audit and safety rows

`Coach.ToneProfile` — **4 rows**: `steady, gentle, encouraging, brief`.
`Coach.ToneRule` — **5 rows**, each naming the condition and the rationale, e.g.
`gentle / state / energy.low / "she has low energy today, so the suggestion is
offered rather than urged"`.

The client-side model mirrors the contract in full: `WLOS_App`'s
`today_models.dart` defines `LifeStateReading` and `LifeDecision` with
`reason`, `evidence`, `confidence`, `source`, `trend`, `dependsOn`,
`expiresUtc`, `refreshSeconds` and `isHealthSensitive`, plus
`IntelligenceStageReport` carrying `stage, status, reason, warnings, evidence,
elapsedMs` — the per-stage trace.

**Classification: FULLY BUILT** as a schema and pipeline contract, uniformly
applied across five engines and mirrored in the client's data model.
**BUILT BUT UNCONSUMED** as a delivered capability — the only transport is
`/api/v1/me/today`, and no client reaches it.

---

## 11. Content — items, translations, review, publish schedule

| Table | Rows |
|---|---|
| `Content.ContentItem` | **6** |
| `Content.ContentVersion` | 6 |
| `Content.ContentTranslation` | 6 |
| `Content.ContentApproval` | 6 |
| `Content.Category` | **17** |
| `Content.ContentReview` | **0** |
| `Content.ContentPublishSchedule` | **0** |
| `Content.ContentTag` / `ContentItemTag` / `ContentAuthor` / `Media` | 0 |

`ContentItem` carries `Status`, `PublishFromUtc`, `PublishUntilUtc`,
`CountryFilter`, `MinAppVersion`, `FromWeek`, `ToWeek`, `Season`, `Weight`,
`SourceCitation`, `ReviewedUtc`, `ReviewedBy`, `CurrentVersionId`,
`PublishedVersionId`, `VersionNumber`.

`ContentTranslation` carries `LanguageCode, Title, Body, Summary,
MetadataJson, IsMachineTranslated`.

`ContentReview` carries `ContentVersionId, ReviewerUserId, ReviewKind,
Outcome, Comments` — a versioned review record, zero rows.

`ContentPublishSchedule` carries `Action, ScheduledUtc, Status, ExecutedUtc,
FailureReason` — zero rows. Its runner `usp_Content_RunDueSchedules` exists
and is referenced from C#.

### The approval boundary, measured

`usp_Content_GetForClient` reads text from `ContentVersion.SnapshotJson`, not
from `ContentTranslation`. Its comment records why: reading the live
translation table *"made the approval workflow decorative"* because an editor's
untyped-through edit would reach devices without approval. Targeting fields
(country, week, season, app version, publish window) are deliberately read live
from the item, because *"Text is what approval governs; reach is what an
operator governs."*

Language fallback to `en-GB` is implemented via `OUTER APPLY` with an
`IsFallback` bit returned to the client.

### Consumption

17 endpoints on `ContentController` (`api/v1/content` admin surface) plus 2 on
`api/v1/client/content`. Nine feature flags govern the CMS
(`cms_scheduling, cms_localization, cms_media, cms_version_compare,
cms_approval_workflow, cms_bulk_publish, cms_preview, cms_search` all enabled;
`cms_experimental_editor` disabled).

`WLOS_App` consumes `GET api/v1/client/content/delta` through
`lib/core/content/content_api.dart`, which sends `language`, optional `since`,
`contentType`, `country`, `week`, `season`, `appVersion` — all query
parameters, GET only, no body, no identifier. It handles 304, treats an empty
payload as a failure, and returns `ContentDelta.empty` on any error.

18 audit rows exist, in exactly **3 actions**: `Content.Create` (6),
`Content.Approve` (6), `Content.Publish` (6) — the trail of the 6 seeded items.

**Classification: FULLY BUILT.** This is the one capability in this document
with a complete chain: table, procedure, endpoint, and a live client consumer.
`ContentReview` and `ContentPublishSchedule` are **BUILT BUT UNCONSUMED** (zero
rows, no endpoint traffic measured, though `POST /content/{id}/review` and
`/schedule` exist). The measured constraint is editorial: **6 items**.

---

## 12. Sharing (`Health.ShareGrant`)

`Health.ShareGrant` — **0 rows**. Columns:

```
ShareGrantId    uniqueidentifier
UserId          uniqueidentifier
RecipientKind   varchar
RecipientLabel  nvarchar      -- free text, not a modelled person
TokenHash       varbinary
ScopesJson      nvarchar      -- a scope list, not an account
ExpiresUtc      datetime2
RevokedUtc      datetime2
LastViewedUtc   datetime2
ViewCount       int
```

**No stored procedure or function references it.** Measured via
`sys.sql_modules` search for `%ShareGrant%` — empty.
**No `.cs` file references it.** Measured by grep — empty.
No endpoint exposes it.

The asymmetry is structural: `LastViewedUtc` and `ViewCount` record the
recipient's access for the grantor. There is no reciprocal column.

The other `Health.*` tables — `Appointment`, `BirthPreference`,
`BodyMeasurement`, `Cycle`, `DailyLog`, `HospitalBagItem`, `Pregnancy`,
`Symptom` — are all 0 rows and likewise have **no procedure, no endpoint and no
C# reference** in this codebase. There is no `HealthController`.

**Classification: BUILT BUT UNCONSUMED.** The consent primitive — scoped,
expiring, revocable, hashed-token, view-counted — exists as a table definition
only. Nothing in the deployed platform can create, read, redeem or revoke a
grant.

---

## 13. Audit

`Audit.AuditLog` — **18 rows**. Columns: `AuditLogId, OccurredUtc,
ActorUserId, ActorKind, Action, EntityType, EntityId, BeforeJson, AfterJson,
IpAddress, UserAgent, CorrelationId`.

Append-only by contract. It is one of the two `dbo.AuditContractExemption`
rows, with the reason: *"Append-only by design. No procedure updates or deletes
it and a test asserts that. Soft-delete columns would advertise a capability
that must never exist."*

Actions present in this database: `Content.Create` (6), `Content.Approve` (6),
`Content.Publish` (6). No other action has ever been written here, because no
user has ever registered.

### The audit contract

`dbo.usp_ApplyAuditContract` (defined in `08_AuditContract.sql`, applied by
`74_AuditContract_Apply.sql`) adds `CreatedBy/CreatedOn/ModifiedBy/ModifiedOn/
DeletedBy/DeletedOn/IsDeleted/RowVersion` by cursor over `sys.tables`, so a new
table is audited unless explicitly exempted. Measured: **2 of 87 tables** carry
an exemption row; both are append-only ledgers.

`Audit.usp_Audit_Search` is referenced from C# and exposed at
`GET api/v1/admin/audit`.

Operational ledgers measured alongside: `Ops.DeploymentJournal` (57 rows, one
run, all `Outcome='succeeded'`), `Ops.RestoreDrill` (0 rows). All four `Ops.*`
procedures are referenced by **no** C# file.

**Classification: FULLY BUILT** as a mechanism (append-only, contract applied
by cursor, exemptions recorded with reasons, search endpoint exists).
**PARTIAL** as a taxonomy — actions are written by procedures rather than
seeded, so only three action strings are observable in this database.
`Ops.*` is **BUILT BUT UNCONSUMED** from the application.

---

## 14. What is measurably ABSENT

The following were searched for by name across `sys.tables` and `sys.columns`
in `WlosPlatform`, using `LIKE` patterns on `Need`, `Intent`, `Preference`,
`Boundary`, `Consent`, `Control`, `Depend`, `Child`, `Relation`, `Person`,
`Contact`, `Emergency`, `Region`, `Responsib`, `Household`, `Invit`, `Trust`,
`OptIn`, `OptOut`.

The **entire** result set was:

```
TABLE: Health.BirthPreference
TABLE: Knowledge.SignalRelation
COL:   Health.BirthPreference.PreferenceId
```

Both are unrelated to the concepts below.

### Need — ABSENT

No table, no column, no reference row, no targeting dimension, no endpoint.
There is no representation of what she needs today, and no decay or expiry
mechanism for a self-reported state of any kind.

Nearest measured structure: `Content.TargetingDimension` contains `goal` and
`condition` as seeded dimension codes — but neither has a producer in the
pipeline (§4), and no table stores a per-user value for either.

### Intent / response mode — ABSENT

`Coach.ToneProfile` (4 rows) and `Coach.ToneRule` (5 rows) exist and govern
**how** a message is phrased — `steady`, `gentle`, `encouraging`, `brief` —
selected by rule against state, behaviour and goal conditions.

There is no structure governing **what the system does** in response: no
listen/decide/plan/comfort distinction, no column, no table, no dimension.
Tone is selected by the platform from her data; nothing in the schema records a
choice she made about how to be answered.

### Preference — ABSENT

No per-user preference table exists.

Measured: `Administration.Setting` (11 rows) has **no `UserId` column**. Its
keys are `app.maintenance_mode`, `app.maintenance_message`, `app.privacy_url`,
`app.terms_url`, `app.support_email`, `sync.interval_minutes`,
`sync.batch_size`, `reminders.default_morning`, `reminders.quiet_start`,
`reminders.quiet_end`, `content.rotation_window_days` — all platform-wide.

Measured: of 87 tables, **30 carry a `UserId` column**. Of those 30, the only
two that hold anything a person chose about herself are `Identity.Profile`
(display name, terms, date of birth, timezone) and `Health.BirthPreference`
(0 rows, no procedure, no endpoint — see §12).

`Administration.FeatureFlagAssignment` carries `UserId` but holds 0 rows and is
an operator targeting mechanism, not a user control.

### Boundary — ABSENT

No structure records something she does not want shown, asked, tracked or
inferred. The `not_in` operator in `Rules.fn_Match` expresses an *operator's*
exclusion of an audience; there is no table in which a *user's* exclusion could
be stored, and no scope in `Rules.TargetScope` whose `TargetTable` is a user.

### Personalization controls — ABSENT

All **31** rows of `Identity.Permission` are operator permissions
(`content.*`, `users.*`, `roles.*`, `settings.*`, `flags.*`, `media.*`,
`notifications.*`, `reports.*`, `support.read/write`, `audit.read`,
`analytics.read`). None is a control a subject of the system holds over her own
data.

There is no column anywhere that switches inference, learning, retention,
derivation or sharing on or off for a user. Searched for `OptIn`, `OptOut`,
`Consent`, `Control` — zero matches.

`AI.SafetyEvent` separates `Decision`, `ModelId` and `PromptVersion`, which
means AI behaviour is *recordable* at that granularity; nothing reads or writes
those columns (§9), and no corresponding control exists.

### Responsibility load — ABSENT

No table for children, dependents, caregiving relationships, household size or
responsibility of any kind. Searched `Depend`, `Child`, `Household`,
`Responsib` — zero matches.

Two measured near-neighbours, neither of which is the concept:

- `Identity.RoleMode` includes `caregiver` and `homemaker`. These are labels
  with `DisplayName` and `Description`; no row carries a count, an intensity or
  a relationship
- `Intelligence.StateDimension` includes `load` (categorical, 2 rules). Its
  inputs, measured from `Intelligence.StateInput`, are `work` (weight 2),
  `screen_time` (1) and `sleep` (1) — derived from logged activity, never from
  people she is responsible for

### Account-to-account relationships — ABSENT

No `Person`, no link between two `Identity.User` rows, no invitation, no
acceptance, no trust role, no emergency role, no per-relationship scope.

`Health.ShareGrant` is the nearest structure and is not this: `RecipientLabel`
is free text and `RecipientKind` a varchar, so the recipient is a label on a
token, not an account. It holds 0 rows and has no procedure or endpoint (§12).

The only user-to-user relationship expressible in the schema is
`Identity.UserRole` — an operator grant, not a human relationship.

### Country safety configuration — ABSENT

`Identity.Country` has exactly four meaningful columns: `IsoCode`, `Name`,
`DefaultLanguageCode`, `IsSupported`. Eleven rows: `GB, US, IE, AU, CA, NZ, PK,
IN, ES, FR, DE`, all `IsSupported = 1`.

There is no region, no emergency number or pathway, no healthcare model, no
regulatory profile, no measurement system, no calendar convention, no age-of-
majority, no data-residency flag. Searched `Emergency` and `Region` across all
columns — the only match anywhere is the `emergency` **life domain** code in
`Content.LifeDomain`, which is a content category, not a configuration.

Content-level country control exists separately and is unrelated:
`Content.ContentItem.CountryFilter`, a JSON array matched in
`usp_Content_GetForClient`.

---

## 15. The `Content.ContentTargetingRule` deploy behaviour

Recorded here as a measurement only. **Nothing was fixed, and no fix is
proposed.** This area is frozen.

### What was reported

`docs/WLOS_FOUNDATION.md` §2.8 and `docs/PROJECT_STATE.md` §6 record that a
clean 57-script deploy does not create `Content.ContentTargetingRule` while
reporting success, and state *"The mechanism is not yet established."*

### What is measured

The deployment journal in `WlosPlatform` shows **one run**, 57 scripts, every
row `Outcome = 'succeeded'`, including `34_ContentTargeting.sql` and
`45_RuleEngine.sql` in that order within the same run.

Reading the source, `src/Maren.Database/45_RuleEngine.sql` contains, at lines
171–202, a migration that copies every row of `Content.ContentTargetingRule`
into `Rules.Rule` under `ScopeCode = 'content'`, verifies the count, and throws
`51001` if rows were lost. Then at lines 242–246:

```sql
/*  Only now. Both functions are rewritten in 46_Procs_RuleEngine.sql to read
    from Rules.Rule, so these tables have no reader left. */
IF OBJECT_ID('Content.ContentTargetingRule') IS NOT NULL
BEGIN
    DROP TABLE [Content].[ContentTargetingRule];
    PRINT 'Dropped Content.ContentTargetingRule - superseded by Rules.Rule.';
END
GO
```

The same script performs the identical copy-verify-drop for
`Dashboard.CardRule` (lines 205–241 and following). `Dashboard.CardRule` is
correspondingly **absent** from the 87 deployed tables, and its 8 rules are the
8 rows now in `Rules.Rule` under `ScopeCode = 'dashboardCard'` (§4).

Script `46_Procs_RuleEngine.sql` rewrites `Content.fn_TargetedItems`,
`Content.usp_Content_GetTargetingRules` and `usp_Content_SetTargetingRules` to
read `Rules.Rule`. All three deployed bodies were read from `sys.sql_modules`
and confirm this (§4).

### What this establishes

A clean 57-script deploy creates `Content.ContentTargetingRule` at script 34
and deliberately drops it at script 45, after migrating its contents. The
deploy reports success because the drop is an intended step, not a failure. The
`IF OBJECT_ID(...) IS NULL CREATE TABLE` guard at script 34 behaves correctly;
the table's later absence is not caused by that guard.

`WlosPlatform` contains the table, empty, because script 34 was re-run by hand
after the deploy — as `docs/WLOS_FOUNDATION.md` §2.8 itself records. Because
script 46 had already rewritten the three procedures to read `Rules.Rule`, that
re-created table has **no reader anywhere in the deployed database** (verified
against `sys.sql_modules` and against every `.cs` file). Its presence and its
0 rows have no effect on any code path.

`src/Maren.Database/tests/rule_engine_test.sql:48` asserts on
`OBJECT_ID('Content.ContentTargetingRule') IS NULL`. That test was **not run**
as part of this measurement.

**Not verified:** whether the effective absence of the table causes any failure
in any environment. No failure mechanism was found, but no environment other
than `WlosPlatform` was examined.

---

## 16. Summary classification table

| Area | Classification | The measured reason |
|---|---|---|
| Identity — registration, login, tokens, RBAC | FULLY BUILT (backend) | 31 permissions, 18 procedures, 18 endpoints, all referenced |
| Identity — profile, life stage, role modes | BUILT BUT UNCONSUMED | Complete chain to the endpoint; no client, and `life_profile` is unreferenced in the app |
| Life stages (12) and history | BUILT BUT UNCONSUMED | `Source`, `StartedOn`, `EndedOn` present; 0 rows; 2 endpoints, no caller |
| Life domains (22 root / 28 total) | BUILT BUT UNCONSUMED | Seeded, hierarchical, FK target for 2 subsystems; endpoint uncalled |
| Targeting — `Rules.Rule` / `fn_Match` | FULLY BUILT for `dashboardCard` | 8 rules, 6 SQL modules call `fn_Match`, reached via `/me/today` |
| Targeting — `Content.ContentTargetingRule` | ABSENT in effect | Empty table, zero readers in SQL and C# |
| Targeting — `fn_TargetedItems` | BUILT BUT UNCONSUMED | Correct wrapper, zero callers, zero rules in scope `content` |
| Targeting — rule-authoring procedures | BUILT BUT UNCONSUMED | 6 procedures, no C# reference, no endpoint |
| Targeting — 6 of 10 dimensions | PARTIAL | `age, season, goal, condition, module, week` have no producer |
| Knowledge signals | PARTIAL | 7 of 12 have firing rules; 5 cannot fire |
| Signal relations | BUILT BUT UNCONSUMED | 13 edges, 3 relation kinds, `usp_Knowledge_Related` has no caller |
| Intelligence state | PARTIAL | 9 dimensions resolve; `momentum` has 0 rules; history/list procedures uncalled |
| Timeline event types | BUILT BUT UNCONSUMED | 32 types, 17 categories, fully seeded |
| Timeline events (write path) | ABSENT | 6 procedures, 0 C# references, 0 endpoints |
| Goals and growth | PARTIAL | 5 templates, 10 measures, 7 endpoints — the only user write path; no client; `GoalKnowledge` empty |
| Behaviour | FULLY BUILT (backend) | 6 subjects, 15 measures, 5 procedures, 4 endpoints, all referenced |
| Coach tone | FULLY BUILT (backend) | 4 tones, 5 rules, rationale stored per rule |
| AI safety | BUILT BUT UNCONSUMED | 12-column ledger, audit-exempt, zero readers and writers anywhere |
| Explainability / provenance | FULLY BUILT as contract | reason + evidence + confidence on 5 engines, mirrored in the app's models |
| Content — items, versions, approval, translation | FULLY BUILT | The only chain with a live client consumer; 6 items |
| Content — review, publish schedule | BUILT BUT UNCONSUMED | Tables and endpoints exist; 0 rows |
| Sharing (`Health.ShareGrant`) | BUILT BUT UNCONSUMED | 10-column consent primitive, zero procedures, zero endpoints |
| All other `Health.*` | BUILT BUT UNCONSUMED | 8 tables, 0 rows, no controller exists |
| Audit | FULLY BUILT mechanism / PARTIAL taxonomy | Append-only, contract by cursor, 2 exemptions; only 3 action strings observable |
| `Ops.*` | BUILT BUT UNCONSUMED | 57 journal rows written by the deploy script; 4 procedures with no C# caller |
| Need | ABSENT | Zero name matches in `sys.tables` / `sys.columns` |
| Intent / response mode | ABSENT | Tone exists; response mode has no structure |
| Preference | ABSENT | `Administration.Setting` has no `UserId`; no per-user preference table |
| Boundary | ABSENT | No user-owned exclusion anywhere |
| Personalization controls | ABSENT | All 31 permissions are operator permissions |
| Responsibility load | ABSENT | No dependents model; `caregiver` is a label, `load` is derived from workload |
| Account-to-account relationships | ABSENT | No person, link, invitation, trust or emergency role |
| Country safety configuration | ABSENT | `Identity.Country` has 4 meaningful columns and no safety, regulatory or unit profile |

---

## 17. What was not verified

Stated explicitly rather than guessed:

- **No test suite was executed.** Neither the 24 SQL assertion scripts in
  `src/Maren.Database/tests/` nor the `tests/` project nor any Flutter test was
  run. Claims about test coverage in other documents are not corroborated here
- **The API was not started.** No endpoint was called. Endpoint counts come
  from `[Http*]` attributes in source; response shapes were not observed
- **No other database was examined.** `MarenPlatform` and any other environment
  were not queried. Findings apply to `WlosPlatform` as deployed on this machine
- **The 57-script deploy was not re-run**, in any database. §15 rests on the
  journal in `WlosPlatform`, the deployed module bodies, and reading the source
  of scripts 34, 35, 45 and 46
- **`WLOS_App` was not compiled or run.** No `flutter analyze`, no build.
  Findings come from reading source and from grep
- **`WLOS_FrontEnd` was out of scope** and was not examined
- **Whether the effective absence of `Content.ContentTargetingRule` causes any
  failure anywhere: not verified.** No mechanism was found by which it could,
  given zero readers, but only one environment was examined
- **`Behaviour.SubjectMeasure` (88 rows) and `SubjectEvent` (12 rows)** were
  counted but their contents were not enumerated
- **`decimal` precision on `AI.SafetyEvent.ClinicalScore` / `CrisisScore`** was
  read as `max_length = 5` (storage bytes); the declared precision and scale
  were not separately queried

---

*Measurement only. No recommendation, no sequence, no plan. Nothing in either
repository was modified; this file is the only artefact created.*
