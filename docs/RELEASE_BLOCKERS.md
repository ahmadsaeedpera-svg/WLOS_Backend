# Release Blockers — Release Candidate Tasks

Work that must be completed before Maren ships to production, but which is
**deliberately not being executed during feature development**. Roadmap
execution continues; these are gathered here so nothing is lost.

Nothing in this file is a build, crash, data-loss or security issue. Those are
fixed immediately when found and never deferred here.

---

## RC-1 — Insights article compliance rewrite

**Status:** Open · **Severity:** Blocker for store submission

`lib/features/insights/data/insight_content.dart` predates the compliance bar
applied to the 325-snippet wellness library, and contains language that would
not pass it:

| Location | Text | Problem |
|---|---|---|
| `nutritionArticles` — Staying hydrated | "Aim for about 8–10 glasses a day" | Dose / quantity target |
| `nutritionArticles` — Folate-rich foods | "Many health organisations recommend…" | Recommendation framing |
| `nutritionArticles` — Iron and protein | "Iron needs increase during pregnancy" | States what the reader's body is doing |
| `nutritionArticles` — Iron and protein | "helps absorption" | Outcome claim |
| `exerciseArticles` — Prenatal yoga | "poses that are not recommended during pregnancy" | Recommendation framing |
| `exerciseArticles` — Walking | "Even 20–30 minutes a day can support…" | Duration target + outcome claim |

Roughly 25 articles across five collections need rewriting to the same standard
as `lib/features/content/` — describe, never prescribe.

**Exposure has increased:** these articles are now indexed by global search
(`lib/features/search/data/search_index.dart`), so they surface on more paths
than the Insights tab alone.

**Definition of done:**
- Every article rewritten to clear the four rules in
  `lib/features/content/README.md`
- `lib/features/insights` added to `guardedPaths` in
  `test/guards/no_interpretation_test.dart`
- A `README.md` added to the insights module citing the controlling guidance
  and date, as the guard requires
- Full test suite green

---

## RC-2 — FDA wording audit

**Status:** Open · **Severity:** Blocker for store submission

A sweep of every user-facing string in the app against the General Wellness
exclusion (guidance 6 Jan 2026, Section III p.6), not just the guarded modules.

Covers strings the automated guard cannot catch, because the guard matches
identifiers rather than reading prose for meaning. Includes `lib/l10n/`,
notification copy, onboarding copy, empty and error states, and the Play Store
listing copy under `docs/play-store/`.

**Definition of done:** a documented pass over every string with a
sign-off list of anything reworded.

---

## RC-3 — Medical content review

**Status:** Open · **Severity:** Blocker for store submission

External review of all health-adjacent content by a qualified clinician
(midwife or obstetrician). Distinct from RC-2: that one checks regulatory
wording, this one checks the content is not misleading.

Scope: insights articles, wellness library, hospital bag defaults, birth
preference options, due date calculator presentation.

**Definition of done:** written sign-off, reviewer named, date recorded, and
the review date surfaced on the About screen next to the clinical sources.

---

## RC-4 — Legal review

**Status:** Open · **Severity:** Blocker for store submission

- Privacy policy (`docs/play-store/privacy-policy.md`) reviewed by counsel
- All `[TO FILL: …]` markers resolved — legal entity, contact address,
  support email, hosted policy URL
- Terms of use drafted (none exists yet)
- Play Data Safety declarations verified against the shipped binary
- Confirm the General Wellness position is defensible for the target markets,
  not the UK/US only
- UK/EU GDPR position confirmed — likely minimal given no data leaves the
  device, but the conclusion needs to be recorded rather than assumed

---

## RC-5 — Clinical review

**Status:** Open · **Severity:** Blocker for store submission

Review of the *behaviour* of the tools, not their words:

- Contraction timer and kick counter present raw observations only, with no
  implied thresholds anywhere in the UI
- Due date calculator shows its working and never picks between a user's
  competing dates
- Nothing in the daily check-in, calendar or review screens aggregates into
  something that reads as an assessment
- Notification triggers are time-based only, never condition-based

**Definition of done:** clinician sign-off that no screen implies a clinical
judgement.

---

## Working rule

These are **Release Candidate tasks**. They do not interrupt roadmap
execution. Feature work continues; this file is updated whenever a new
compliance concern is found so the RC pass has a complete list to work from.
