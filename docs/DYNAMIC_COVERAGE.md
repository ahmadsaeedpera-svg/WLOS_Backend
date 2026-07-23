# Dynamic Coverage Report

**How much of the mobile app can an operator change without publishing an APK?**

| | |
|---|---|
| **Report** | #2 |
| **Date** | 2026-07-22 |
| **After sprint** | Sprint 2 — Dynamic Content Delivery |
| **Coverage** | **15%** (8 of 55 surfaces) |
| **Previous** | 11% (6 of 55) |

---

## How this is measured

The denominator is every distinct user-visible surface an operator might
reasonably want to change, built by walking the app's feature folders. A surface
counts as **covered** only when all six hold:

1. Schema exists
2. Stored procedures exist
3. API serves it
4. Permission gates it
5. Admin portal edits it
6. **The running app reflects a change with no rebuild** — verified live

Anything short of all six is not covered. No partial credit.

---

## What changed this sprint

The number moved from 11% to 15% — two surfaces newly covered end to end
(**daily tip**, **weekly text**). But the number understates the sprint, and the
honest framing matters:

**Sprint 2 built the delivery platform, not a pile of wired screens.** Before
it, moving content to the platform meant hand-writing an HTTP call, a cache, an
offline fallback and a refresh mechanism for every surface. Now it is one call:
`repo.pickOne(type)` or a `ContentTipCard`. The 40 remaining content surfaces
are a mechanical migration, not an engineering one — each is a content-type
constant, a seed, and swapping a hardcoded read for an SDK read.

The delivery mechanism itself is what was verified:

- **Delta sync with tombstones** — changes AND removals, so a rollback reaches
  the phone. Rowversion cursor, no lost-update race.
- **Three-tier cache** — memory → SQLite → bundled. A read never returns blank.
- **Offline-first** — a failed sync changes nothing and is never shown.
- **Auto-refresh** — the running app pulls on resume and on an interval, no
  restart.

All proven in the **ten-step live demonstration** (`content_live_demo_test.dart`,
run against the real API): edit → publish → the same running app shows it →
offline still works → roll back → the app reverts → audit records everything.

---

## Coverage

```
Covered      ███░░░░░░░░░░░░░░░░░  15%   8 / 55
Ready        ██████████░░░░░░░░░░  ~50%       migration mechanical, SDK exists
Not started  ███████░░░░░░░░░░░░░  35%        needs a new backend module
```

### Covered — verified end to end (8)

| Surface | Type | Since |
|---|---|---|
| Support contact | setting | Sprint 1 |
| Maintenance flag | setting | Sprint 1 |
| Maintenance message | setting | Sprint 1 |
| Privacy policy URL | setting | Sprint 1 |
| Terms URL | setting | Sprint 1 |
| Content rotation window | setting | Sprint 1 |
| **Daily tip** | `dailyTip` | **Sprint 2** |
| **Weekly text** | `weeklyText` | **Sprint 2** |

### Ready — the platform can carry these now; migration is mechanical (≈27)

Every one of these has a content type in the taxonomy, a delivery endpoint, and
an SDK that already fetches, caches and renders it. Migrating each is: seed the
content, swap the hardcoded read in the app for `ContentScope.of(context)`, and
delete the compiled list (keeping a slice as the bundled floor).

FAQ · articles · wellness snippets (300+) · insight topics · trimester content ·
symptom info · coach messages · onboarding copy · greetings · seasonal notes ·
encouragements · empty states · error messages · loading messages · success
messages · offline messages · dialogs · **home banners** · **announcement
banners** · calendar help · release notes · disclaimers · legal pages · terms ·
privacy text · emergency numbers · home cards.

That is the bulk of the app's text. Sprint 3 should be a migration sprint: it
adds no platform capability, only moves content onto the capability that now
exists. Projected coverage after it: **~60%**.

### Not started — needs a new backend module (≈20)

Journey timeline · questionnaires · achievements · badges · challenges ·
hospital bag templates · birth plan templates · deep links · A/B tests · push
campaigns · notification templates · store listing assets · home feed layout ·
achievement rules · seasonal windows · widget layout · quick actions · theme ·
nav structure · symptom taxonomy.

These are structured or interactive, not plain text — they need schema and
procedures a content type alone does not provide.

---

## The honest picture

**15% covered, ~50% ready, 35% needs new modules.**

The jump from 11% to 15% is small because coverage counts only surfaces wired
AND verified, and Sprint 2 spent its effort on the mechanism rather than on
wiring dozens of screens. That was the right order: wiring one surface well and
proving the whole delivery loop is worth more than forty half-wired ones. The
next sprint converts the "ready" column, and that is where the number moves
fast.

---

## Sprint order by coverage gained

| Sprint | Capability | Surfaces | Projected |
|---|---|---|---|
| 3 | **Content migration** — move the ready column onto the SDK | +27 | **~60%** |
| 4 | Home feed layout, journey timeline, home cards | +5 | **~70%** |
| 5 | Questionnaires, checklist and birth-plan templates | +5 | **~80%** |
| 6 | Notifications and push campaigns | +4 | **~87%** |
| 7 | Achievements, challenges, A/B tests | +5 | **~96%** |

---

## What this number still does not claim

- **Not a quality measure.** A surface counts when controllable, not when well
  designed.
- **Excludes anything requiring an upload.** Health sync, accounts and GDPR
  export are a different risk class (SR-002, SR-003).
- **100% is not the goal.** Some surfaces should stay compiled — the offline
  schema, the crash handler, the encryption routines. The real ceiling is
  ~90% of this list.
- **Coverage is not adoption.** A controllable surface with no operator trained
  to use it is still zero operational value.
