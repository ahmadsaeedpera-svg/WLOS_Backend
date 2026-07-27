# ROADMAP 2030

**From:** a pregnancy app that cannot yet ship
**To:** a lifelong AI companion for women's health

Grounded in what is verifiably built (`FINAL_REPORT.md`), not in what has been described.

---

## Where we actually are

A well-engineered offline pregnancy app and a genuinely strong platform backbone — CMS, identity, permissions, audit — with **no deployment, no backups, no monitoring**, an unverified mobile client, and revenue that is a stub. Production readiness **32/100**.

Everything below is gated on fixing that, and no amount of roadmap changes it.

---

## 2026 H2 — Make it real

**Theme: ship something, to someone, safely.**

- Backups with a **performed restore**; monitoring; a real deployment; container healthcheck fixed
- Release signing; PD-1 resolved; Data Safety corrected
- RC-1…RC-5 cleared — clinician and legal sign-off
- Flutter suite running in CI
- **Free app on Play Store**

*Exit test: a woman who is not on the team is using it, and we would know within minutes if it broke.*

---

## 2027 — Earn, and stop losing her

**Theme: revenue, and the retention save.**

- Billing: store SDK, paywall, subscriptions backend with receipt validation
- **Postpartum module** — the single highest-value build in the plan. Every pregnancy app loses the user at birth; this is where a 40-week product becomes a lifetime one, and where PPD (~1 in 7, chronically under-detected) makes it matter beyond retention
- Notifications — the missing engagement loop
- Opt-in encrypted cloud sync; GDPR erasure and export actually implemented
- Portal defects fixed; accessibility brought to standard

*Exit test: women stay past birth, and some of them pay.*

---

## 2028 — The companion, and the years before pregnancy

**Theme: from event to habit.**

- **Cycle core** — brings women in years earlier and holds them between life events. Pregnancy is a 40-week window; cycle tracking is a daily habit
- Planning/TTC with grief-aware handling
- **AI companion, internal → limited rollout.** Guardrails first, per `AI_PIPELINE.md`: safety ledger (done), classifier, output screen, retrieval, then generation. Never the other order
- Analytics; the empty `Reporting` schema finally populated

*Exit test: daily active use that is not driven by a life event.*

---

## 2029 — The underserved decades

**Theme: the market nobody serves well.**

- **Perimenopause and menopause** — roughly a quarter of women, chronically dismissed, high willingness to pay, almost no serious competition. The flagship content investment
- Doctor advocacy packs — months of logs into one page a clinician takes seriously in ten minutes
- Family health hub; mother→daughter and grandmother bridges (the cross-generational growth loop)
- Second language; accessibility to standard across every stage

*Exit test: women who joined at 28 are still here at 45, and paying more.*

---

## 2030 — Platform

**Theme: where the real revenue is.**

- **Multi-tenancy** — decided and built. It is the most expensive retrofit on the list and gets harder every year it waits
- B2B2C: employers, insurers, clinics — and public-health programmes, which the offline-first, low-data, local-language architecture suits unusually well
- Clinician surfaces: scoped, revocable, consented
- Senior stage: medication management, emergency, caregiver sharing
- HIPAA/SOC 2 posture; SLA; DR with a tested RTO

*Exit test: revenue that does not depend on individual consumers.*

---

## The three decisions that shape everything

**1. Is this a consumer product or a public-health one?**
The code is a US/UK consumer Play Store app. The auditing context is a Punjab government address. These are different products with different compliance regimes, funding and roadmaps. **Unresolved, and it should not stay that way** — most of the plan above changes depending on the answer.

**2. Multi-tenancy: now or never cheaply.**
No tenant dimension exists on any of the 45 tables. Adding it later rewrites every table, index, procedure and permission check. If B2B2C is real, decide **before** the health procedure layer is written.

**3. How far does the AI go?**
The design holds the line at describe-organise-educate-refer. Every step past it — interpretation, triage, risk scoring — trades the general-wellness exclusion for regulatory exposure. That trade may one day be worth making deliberately. It must never be made accidentally.

---

## What would make this a real company

Not features. Three things:

- **A woman who is not on the team, using it every week, who would be annoyed if it disappeared.** Nothing in the codebase proves this exists yet.
- **Someone paying.** Billing is a stub; revenue is currently zero by construction, not by market conditions.
- **A clinician who recommends it.** The doctor-prep pack is the feature most likely to earn that, and it is the one worth building before almost anything else in 2027.

Everything else in this roadmap is downstream of those three.
