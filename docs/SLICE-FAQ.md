# Help Center / FAQ — operator-managed vertical

**Status:** Design accepted, implementing
**Date:** 2026-07-22
**Sprint:** 3 (content migration — converting the "ready" column of the coverage
report to "covered")

---

## The point of this slice

A content editor authors FAQ entries in the Admin Portal and publishes them. A
Help Center screen in the running Flutter app shows them, updates when the
operator changes one, and works offline — with no APK release.

It is the first of the content-migration verticals, and it exists partly to
prove a claim from the last coverage report: that a new content surface now
needs **no backend work**, only a renderer and content. If that claim is true,
this slice touches the platform's data and the app's UI, and nothing in between.

---

## Why the backend does not change

FAQ (`faq`) is already a content type in `ContentCatalog`. Every layer between
the database and the app is generic over content type:

- `usp_Content_Save` / `_Publish` / `_GetDelta` take a content type; none is
  hardcoded to a set of types.
- The delivery endpoint `/api/v1/client/content/delta?contentType=faq` already
  serves it.
- The Flutter `ContentRepository.ofType('faq')` already fetches, caches and
  renders it.
- The portal's content module already lists, edits, approves and publishes any
  type.

So this slice adds no procedure, no repository method, no API, no CQRS handler,
no portal code. Adding any of those would be duplicating a generic pipeline for
one type — the exact anti-pattern the platform was built to avoid.

---

## Data model

FAQ maps onto the existing `ContentItem` with no new columns:

| FAQ concept | ContentItem field |
|---|---|
| Question | `Title` |
| Answer | `Body` (markdown-capable) |
| Topic group | `CategoryKey` |
| Order in group | `Weight` (higher first) |

### The one database addition: FAQ topic categories (data, not schema)

`Content.Category` exists and is referenced by `ContentItem` through a foreign
key that `usp_Content_Save` resolves from `CategoryKey`. Today it holds
wellness categories (`nutrition`, `sleep`, …), which are wrong groupings for
FAQ. So this slice seeds FAQ topic categories:

- `faq.gettingStarted`
- `faq.tracking`
- `faq.privacy`
- `faq.account`

These are rows, not DDL. They are operator-manageable through the same category
administration the CMS already has, so an editor can add a topic later without
a developer.

---

## Flutter

New, and only here:

- **`FaqList`** — a content widget (the rendering engine's "FAQWidget"). Reads
  `repo.ofType('faq')`, groups by `categoryKey`, renders each entry as an
  expandable question/answer. Rebuilds on `repo.onChanged`, so a publish shows
  up with no restart. Never blank: the repository's cache→bundled fall-through
  guarantees content.
- **`HelpScreen`** — hosts `FaqList` with the standard scaffold and disclaimer.
- **Bundled fallback** — a few core FAQ entries added to `MarenBundledContent`,
  so a first-launch offline user still has help. Same text the platform serves,
  so migrating regresses nothing offline.
- **Navigation** — a "Help & FAQ" row in Settings, beside "About Maren",
  matching the existing `_ActionRow` pattern.

---

## Security, audit, offline — all inherited

- **Authorization**: publishing an FAQ needs `content.publish`, enforced by the
  MediatR pipeline. Unchanged.
- **Audit**: every FAQ save/approve/publish is already recorded in
  `Audit.AuditLog`. Unchanged.
- **Approval**: an FAQ answer is health-adjacent copy; it goes through the same
  approve-before-publish gate as every other content type, and the client reads
  the approved snapshot, never a live draft. Unchanged.
- **Offline**: the SDK's three-tier cache and silent-failure behaviour apply
  unchanged.

That these are all inherited is the measure of the platform working.

---

## Definition of Done

- [ ] FAQ topic categories seeded (idempotent)
- [ ] Real FAQ content authored and published through the platform
- [ ] `FaqList` widget renders grouped, expandable Q&A from the SDK
- [ ] `HelpScreen` reachable from Settings
- [ ] Bundled FAQ fallback, so offline first-launch is not blank
- [ ] Widget test: FaqList renders and groups from a fake repository
- [ ] Live demonstration extended: edit an FAQ in the portal → the running app
      shows it, no rebuild
- [ ] Coverage report updated
- [ ] Full suite green: backend, SQL, Flutter, release build

---

## What "done" means here

Changing an FAQ answer in the Portal changes the running Flutter app without a
rebuild. Verified live, not asserted.
