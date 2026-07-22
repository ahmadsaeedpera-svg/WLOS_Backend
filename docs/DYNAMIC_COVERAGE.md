# Dynamic Coverage Report

**How much of the mobile app can an operator change without publishing an APK?**

| | |
|---|---|
| **Report** | #1 |
| **Date** | 2026-07-22 |
| **After sprint** | Sprint 1 — Remote Configuration |
| **Coverage** | **11%** (6 of 55 surfaces) |
| **Previous** | 0% |

---

## How this is measured

The denominator is every distinct thing about the running app an operator might
reasonably want to change. It was built by walking the app's feature folders,
not by listing what the platform happens to support — otherwise the percentage
measures ambition rather than capability.

A surface counts as **covered** only when all six hold:

1. Schema exists
2. Stored procedures exist
3. API serves it
4. Permission gates it
5. Admin portal edits it
6. **The running app reflects a change with no rebuild** — verified, not assumed

Anything short of all six is **not covered**. Partial credit would make this
report comfortable and useless.

---

## Coverage

```
Covered      ██░░░░░░░░░░░░░░░░░░  11%   6 / 55
Plumbed      ████░░░░░░░░░░░░░░░░  20%  11 / 55   backend exists, app does not read it
Not started  ██████████████░░░░░░  69%  38 / 55
```

### Covered — verified end to end (6)

| Surface | Key | Proof |
|---|---|---|
| Support contact | `app.support_email` | Live round-trip test |
| Maintenance flag | `app.maintenance_mode` | Bootstrap payload |
| Maintenance message | `app.maintenance_message` | Bootstrap payload |
| Privacy policy URL | `app.privacy_url` | Bootstrap payload |
| Terms URL | `app.terms_url` | Bootstrap payload |
| Content rotation window | `content.rotation_window_days` | Bootstrap payload |

Verified by `mobile/test/platform_config_live_test.dart`, which changes a value
through the admin API and asserts that **the same running client instance** sees
the new value. No mocks, no rebuild.

### Plumbed but not consumed (11)

The platform can serve these. The app does not read them yet, so they are **not
counted as covered.**

| Surface | Why not yet |
|---|---|
| Feature flags (9 CMS flags) | App has no flag reader |
| Reminder defaults, quiet hours | App reads local settings only |
| Sync interval, batch size | No sync to configure |
| Version gate / force upgrade | `AppVersion` table unreachable by API |
| All CMS content (articles, tips, FAQ, legal) | **App still ships its library inside the APK** |

The last row is the largest single gap in the product. The CMS is complete —
authoring, translation, approval, versioning, publishing — and no user has ever
seen a word of it, because the app reads its own compiled content files.

### Not started (38)

Splash screens · announcement banners · home cards · journey timeline ·
questionnaires · achievements · badges · challenges · checklist templates ·
hospital bag templates · birth plan templates · emergency numbers · doctor lists
· deep links · A/B tests · push campaigns · notification templates · store
listing assets · UI string catalogue · onboarding copy and steps · theme and
colour · nav structure · empty-state copy · error copy · disclaimer text ·
paywall copy and pricing · streak rules · milestone definitions · seasonal
content windows · widget layout · quick actions · export format · search
weighting · content categories · tag taxonomy · locale list · country
availability · legal document versioning

---

## What changed this sprint

**Before:** 0%. The app had no networking dependency at all. Every string,
threshold and piece of content was compiled into the APK. Changing a support
email address required a store release.

**After:** the mechanism exists and is proven. Six surfaces move today, and the
marginal cost of the seventh is small — the client, the cache, the offline
fallback and the admin UI are built once.

The honest framing: **11% is a small number and the right one.** Sprint 1's
value was the enabling mechanism, not the count. Sprints 2 and 3 should move
this far faster because they inherit the client.

---

## The single highest-value next move

**Content delivery.** Eleven of the thirty-eight uncovered surfaces are content
the CMS already manages. The app reading its library from the platform instead
of from the APK would take coverage from 11% to roughly **35% in one sprint**,
and it is the only change that makes the finished CMS worth anything to a user.

Everything else — banners, home cards, questionnaires — is downstream of the
same delivery mechanism.

---

## Sprint order by coverage gained

| Sprint | Capability | Surfaces | Projected |
|---|---|---|---|
| 2 | **Content delivery** — app reads CMS library | +13 | **35%** |
| 3 | Feature flags + version gates + maintenance enforcement | +11 | **55%** |
| 4 | Announcement banners, splash, onboarding copy | +6 | **65%** |
| 5 | Home cards, journey timeline | +5 | **75%** |
| 6 | Questionnaires, checklist and birth plan templates | +5 | **84%** |
| 7 | Notifications and push campaigns | +4 | **91%** |
| 8 | Achievements, challenges, A/B tests | +5 | **100%** |

---

## What this number does not claim

- **It is not a quality measure.** A surface counts when it is controllable, not
  when it is well designed.
- **It excludes anything requiring an upload.** Health sync, accounts and GDPR
  export are a different risk class and are governed by SR-002 and SR-003.
- **100% is not the goal.** Some things should stay compiled — the offline
  database schema, the crash handler, the encryption routines. The target is
  every surface an operator has a legitimate reason to change, and that ceiling
  is closer to 90% of this list.
- **Coverage is not adoption.** Six controllable surfaces with no operator
  trained to use them is still zero operational value.
