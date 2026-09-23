# WLOS Market Research II — the seven open dimensions, and WHO / WHAT / WHERE / WHY / RETENTION

**Date:** 23 September 2026
**Method:** web research, September 2026. Sources at the end.
**Status:** evidence matrix. **No market, segment or age decision is made here.**
Earlier positions are recorded as hypotheses, per instruction.

---

## 0. Two findings that outrank the rest

### 0.1 The retention mechanism WLOS already ships is a trap

Research on habit and wellness apps says streaks and visible progress are
**critical** to retention — and that **44% of users report motivation drop-off
after breaking a streak, with many uninstalling entirely.**

WLOS inherits a streak ring on its home screen. So the mechanism that drives
return is also the mechanism that drives uninstall on the first bad week — and
the EU KIDS Act separately bans, for minors, *"streaks that penalise a child for
not returning daily."*

The literature's answer is **forgiving mechanics plus context-aware
personalisation**: *"context-aware personalization improves retention without
relying on aggressive nudging."*

That is a direct, external endorsement of WLOS's actual thesis — and a direct
warning about the one retention feature it already has.

> **The streak should be redesigned before it is inherited, not after.**

### 0.2 AI-first positioning is not supported by the trust data

| Finding | Figure |
|---|---|
| US adults who used an AI chatbot for health info in the past year | **32%** |
| Still trust their doctor over the chatbot | **74%** |
| Trust a chatbot **with** healthcare-professional oversight | **49–55%** |
| Trust a chatbot **without** professional oversight | **3–6%** |
| AI-health users who uploaded personal medical info anyway | 41% |

The gap between 49–55% and 3–6% is the entire finding. **Unsupervised AI health
advice has almost no trust.** Usage is real; trust is not.

This cuts two ways for WLOS:

- **Against** leading with an AI companion as the headline.
- **For** the constitution's position. A system that explicitly refuses to
  diagnose, shows its reasoning, and cites reviewed content is positioned on the
  right side of a 10-to-1 trust gap.

---

## 1. The seven dimensions

### 1.1 Smartphone access among women — the equity constraint

| Metric (low- and middle-income countries) | Figure |
|---|---|
| Gender gap, mobile ownership | 7% |
| **Gender gap, smartphone ownership** | **13%** |
| Women less likely than men to use mobile internet | 12% |
| Women not using mobile internet in LMICs | **810 million** |
| Sub-Saharan Africa mobile internet gap | 30% (2024) → 26% (2025) |
| Worst surveyed — Ethiopia | 36% internet, 34% smartphone |

Barriers are **handset affordability, literacy and digital skills**, with women
disproportionately affected by social norms and lower income.

**Implication.** In LMIC markets, the woman WLOS is designed for may share a
handset or not own a smartphone. A product requiring a personal device, private
journaling and camera access assumes sole, private device ownership — which is
**itself a segmentation decision**, and one that quietly excludes the women with
the least support.

### 1.2 Acquisition cost

| Market | CPI |
|---|---|
| Health & Fitness, global | **$4.30–5.50** |
| iOS, global Q1 2026 | **$5.84** (+19% YoY) |
| Android, global | $1.92 (+8% YoY) |
| North America | $2.50–5.00 |
| Western Europe | $3.40 iOS / $1.85 Android |
| **India** | **₹30–90 (~$0.32–0.96)** |
| Tier-1 health & wellness | £2–7, D7 ROAS 100–120% |

India is roughly **6–15× cheaper** to acquire than Tier 1. iOS costs rose 19%
year over year — paid acquisition is getting worse, not better.

### 1.3 AI acceptance

See §0.2. Additionally, a *Nature* analysis covered **1.7 million health-related
conversations across 109 countries** (Jan–Mar 2026), so cross-country intent
data exists and is worth commissioning properly rather than inferring.

### 1.4 Partnership routes — the strongest commercial signal found

| Finding | Figure |
|---|---|
| Femtech market 2026 | **$9.78B** → $18.98B by 2031 (14.2% CAGR) |
| Large US employers viewing holistic women's health as critical to recruitment | **69%** |
| Intending to extend telehealth/clinic access | 75% |
| US employers offering fertility coverage | 30% (2020) → **40%** (2024) |
| **Maven Clinic** — B2B2C reference | **2,000+ companies, 6.7M lives, 175 countries** |

The category is shifting *"away from fertility or menopause support being framed
purely as an HR benefit, towards being treated as part of the core risk pool for
health systems and insurers."* Private equity is specifically seeking **sticky
B2B distribution**.

**Implication.** B2B2C is the proven distribution path in this category, and it
is where capital is going. It also fits WLOS's weakest spot — acquisition cost
and day-30 retention both improve when an employer is the channel.

**And it reframes the segment question.** An employer buys for *working women* —
which overlaps heavily with the burnout evidence in §2.

### 1.5 Localisation burden

| Item | Cost |
|---|---|
| Human translation | $0.12–0.20 per word |
| ~10,000-word app | **$1,000–3,000 per language** |
| Cultural adaptation | **+30–50%** |
| Full market localisation incl. marketing and support | **$10,000–50,000+ per market** |

Cheap per language; expensive per *market*. The 30–50% cultural-adaptation
premium is the part that matters for WLOS, because health guidance is not
translatable without adaptation.

**This validates a schema decision.**
`ContentTranslation.IsMachineTranslated` means clinical content can be gated to
human translation while everything else is machine-translated — exactly the
lever that makes multi-language viable at this cost structure.

### 1.6 Payment rails

| Finding | Figure |
|---|---|
| Digital wallets, share of transaction value | **52%** |
| Credit cards | 22% |
| Debit cards | 12% |
| Emerging economies — transactions still cash | **>50%** |
| Emerging economies — non-card payment methods | ~60% |
| In-app purchase market 2026 | $322.81B (+26.2%) |

The critical line: *"Low card penetration in emerging markets forced
subscription merchants to rely on one-off payment workarounds... and these
approaches eroded retention because every renewal required the customer to pay
again, manually."*

**Implication.** Low CPI in India (§1.2) is partly offset by subscription
mechanics that work against retention. **Cheap to acquire is not cheap to
retain.** APAC is nonetheless the fastest-growing recurring-payments region.

### 1.7 ASO and search demand — **still not researched**

I could not obtain category-level, country-level app-store search volume from
open sources. It needs a paid ASO tool (Sensor Tower, data.ai,
AppTweak) against a defined keyword set.

**Recorded as a gap. Not estimated.**

---

## 2. WHO — the segment evidence

Evidence found, not ranked:

| Finding | Figure |
|---|---|
| **Gen Z (18–27) burnout rate** | **74% — highest of any generation** |
| US employees reporting burnout | 66% |
| **Women reporting high/extreme pressure in last year** | **96%** (men: 86%) |
| Women uncomfortable raising stress with their manager | higher than men |
| Burned-out women working longer hours | 25% (vs 7% not burned out) |
| Burned-out women reporting worsening work-life balance | 31% (vs 5%) |

Named pressures: **high workload, job insecurity, isolation, poor sleep, money
worries.** Burnout correlates with insomnia, non-restorative sleep and early
waking.

### Segment comparison, with evidence status

| Segment | Recurring problem | Evidence | Competitive density |
|---|---|---|---|
| **18–27 early career** | Burnout, sleep, identity, transition | **Strongest** — 74% burnout | Low for life-context; high for generic wellness |
| 22–35 working women | Workload/sleep/stress/mood interaction | Strong — 96% pressure | Low |
| 25–40 mothers | Responsibility load, self-care | Not researched | High (parenting apps) |
| 30–45 in transition | Career/family/relationship change | Not researched | Low |
| 40–55 midlife | Body change + work + family + identity | Not researched | **High — Clue, Midi** |
| 55+ | Wellbeing, independence, connection | Not researched | Low, but hardest to acquire |

**Only two of six segments have evidence.** The 18–35 hypothesis is the
best-evidenced, not the proven best. Three segments were not researched at all
and could be stronger.

**Note the convergence:** the burnout evidence (§2) and the B2B2C evidence
(§1.4) point at the same woman from different directions — she is both the most
affected and the most reachable through an employer.

---

## 3. WHAT — the recurring job

The evidence describes an **interaction**, not a symptom:

```
high workload → poor sleep → stress → low mood → longer hours → worse balance
```

And `Knowledge.SignalRelation` already models it:
`long_work → high_stress → low_mood`, `long_work → low_selfcare`.

Two details make this WLOS-shaped rather than generic-wellness-shaped:

1. **Women are less comfortable raising stress with a manager.** The problem is
   partly unspeakable in its own context, which is an argument for a private
   system that understands it.
2. **Burnout is diagnosed by interaction, not by any single metric.** A sleep
   app sees sleep. A calendar sees load. Neither sees the loop.

Candidate job statement, to be validated by interview, not desk research:

> *"Help me notice what is actually going on with me, before it becomes the
> week I fall apart."*

---

## 4. WHERE — economics, with the gap named

| | US | Western Europe | India |
|---|---|---|---|
| Market share / growth | 38.2% share | not quantified | APAC 15.8% CAGR |
| CPI | $2.50–5.00 | $1.85–3.40 | **$0.32–0.96** |
| Willingness to pay | Highest | High | Lower |
| Payment rails | Card + wallet | Card + wallet | **Wallet/cash, weak card** |
| Subscription mechanics | Strong | Strong | **Renewal friction** |
| Minors regulation | State-level patchwork | **EU KIDS Act** | Not researched |
| Device regulation | FDA General Wellness | **MDR Rule 11 — Class IIa+** | Not researched |
| B2B2C maturity | **Proven (Maven, CVS)** | Emerging | Not researched |
| Localisation | English | +30–50% per language | English viable + local |
| **ASO demand** | **unknown** | **unknown** | **unknown** |

**No ranking is offered.** ASO demand is unresearched for every candidate, and
it is the dimension that determines whether organic acquisition is viable — the
only route that survives a $5.84 iOS CPI.

What the evidence does support: **the US has the best economics and the worst
competition; India has the best acquisition cost and the worst renewal
mechanics; Europe has the heaviest regulatory load** (KIDS Act plus MDR Rule 11
plus per-language cultural adaptation).

---

## 5. WHY WLOS — against each real alternative

| Alternative | Why she might not need WLOS | WLOS's actual answer |
|---|---|---|
| **Flo** (420M users) | Already tracks her cycle | Reaches her *through her cycle*. If she is not tracking a cycle question, it has no entry point |
| **ChatGPT** | Free, answers anything | **No memory of her life, no provenance, and 3–6% trust without professional oversight.** Answers questions; does not notice patterns |
| **Journaling apps** | Private, simple | No context, no signals, no connection between entries |
| **Habit trackers** | Proven retention loops | **44% quit after breaking a streak.** Tracks compliance, not life |
| **Calm / Headspace** | Strong brand, content | Content, not context. Same session regardless of her week |
| **Her phone** | Sleep, steps, calendar already there | **Nothing joins them.** Apple Health has the data and draws no conclusion |
| **Midi / Clue** | Clinical depth in midlife | Different life stage, and both are specialists |

The honest version of the differentiator:

> Every alternative holds **one axis** of her life. WLOS's only defensible claim
> is the **join** — and `SignalRelation` is the one piece of it that already
> exists.

If the join is not perceptibly better than the parts, WLOS is a worse version of
six apps she already has.

---

## 6. RETENTION — the day-31 question

Category benchmarks: D1 ~23%, **D30 median 5%** (strong 8–12%), monthly churn
7–10%, annual retention 33% vs monthly 17%.

What the research says actually works:

1. **Streaks work and punish failure.** 44% motivation drop-off on a break.
   Forgiving mechanics and streak recovery are named as the fix.
2. **Context-aware personalisation improves retention without aggressive
   nudging** — externally stated, and it is WLOS's thesis.
3. Timing-aligned nudges beat volume.
4. Reward systems should encourage engagement *without creating dependency* —
   which coincides with the constitution's anti-dependency position.

### The day-31 test, three candidate loops

| Loop | Why she returns tomorrow | Risk |
|---|---|---|
| **"What do you need today?"** | Takes seconds, is about now, and is hers | Needs to visibly change what she sees, or it is a survey |
| **Noticing** — "your sleep has been below your range for four days" | Tells her something she did not know | Requires data density before it can say anything |
| **Protecting tomorrow** — "make tomorrow lighter" | Acts rather than reports | Requires calendar/context integration |

Loop 1 is the only one that works on **day one with no data**, which is exactly
where 77% of users are lost. It is also the cheapest thing in the entire
backlog: a reference table and a seed row.

---

## 7. Hypotheses, explicitly not decisions

| Hypothesis | Status |
|---|---|
| Launch 18+ | **Hypothesis.** Needs legal review per jurisdiction. The stronger question is architectural: does serving minors require a different product, given non-personalised recommendation and no streaks? |
| 18–35 non-reproductive is the open segment | **Best-evidenced of six; three segments unresearched** |
| Life-context join beats single-axis apps | **Unproven by anyone.** The opportunity and the risk |
| B2B2C is the distribution path | **Strongest commercial evidence found** (§1.4) |
| Day-31 loop is "what do you need today" | **Hypothesis.** Testable cheaply |

## 8. What still cannot be answered from desk research

1. **ASO/search demand** — needs a paid tool.
2. **Whether the join is perceptible** — needs prototype testing, not research.
3. **Segment truth** — needs interviews across all six segments.
4. **Minors architecture** — needs legal review plus a design spike on whether
   a non-personalised WLOS is still WLOS.

## 9. Recommended next step

**Stop researching and start interviewing.** The remaining unknowns are about
whether women recognise the problem WLOS solves — and no amount of market data
answers that.

Twenty conversations across the six segments, asking only:

> *"Tell me about the last week that went badly. What did you notice first?"*

If she describes an interaction, WLOS has a market. If she describes a single
problem, she already has an app for it.

---

## Sources

- [GSMA — The Mobile Gender Gap Report 2026](https://www.gsma.com/gender-gap/)
- [GSMA — 810 million women still not using mobile internet in LMICs](https://www.gsma.com/newsroom/press-release/810-million-women-still-not-using-mobile-internet-in-low-and-middle-income-countries-compared-to-595-million-men/)
- [Linkrunner — Cost per install benchmarks by country, platform, category](https://linkrunner.io/tools/cost-per-install-benchmark)
- [The Social Outline — Mobile App CPI Benchmarks 2026](https://thesocialoutline.com/blog/mobile-app-cpi-benchmarks-2026)
- [SEM Nexus — CPI by Country 2026](https://semnexus.com/cpi-by-country-where-app-budget-goes-furthest-2026)
- [KFF — 1 in 3 Adults Are Turning to AI Chatbots for Health Information](https://www.kff.org/health-information-trust/poll-1-in-3-adults-are-turning-to-ai-chatbots-for-health-information-equaling-the-share-who-use-social-media-for-health/)
- [Nature Health — Global analysis of country-level factors associated with chatbot usage for health](https://www.nature.com/articles/s44360-026-00174-2)
- [Mordor Intelligence — Femtech Market Size, Trends & Analysis](https://www.mordorintelligence.com/industry-reports/femtech-market)
- [HTD Health — HealthTech Business Models: Benefits of B2B2C](https://htdhealth.com/insights/healthtech-business-models-explained-benefits-of-b2b2c/)
- [Healthcare Digital — FemTech Mid 2026: Landscape, Capital Trends & AI Threats](https://www.healthcare.digital/single-post/femtech-mid-2026-future-landscape-ipo-pipeline-capital-trends-ai-threats)
- [Kanopy — App Localization Costs 2026](https://kanopylabs.com/blog/how-much-does-app-localization-cost)
- [Worldpay — Global Payments Report 2026: digital wallets](https://www.worldpay.com/en/insights/articles/gpr-2026-trend-3)
- [AppsFlyer — Subscription trends shift to emerging markets](https://www.appsflyer.com/company/newsroom/pr/subscription-trends-report/)
- [CNBC/SurveyMonkey — Women at Work 2026](https://www.surveymonkey.com/curiosity/cnbc-women-at-work-2026/)
- [Grow Therapy — Workplace mental health statistics 2026](https://growtherapy.com/blog/workplace-mental-health-statistics/)
- [Riskex — Burnout Report 2026](https://riskex.com/burnout-report-2026-key-findings)
- [KeyToTech — Wellness App Retention Design Playbook](https://keytotech.com/blog/wellness-app-retention-design-playbook)
- [Habit-Streak — The State of Habit Tracking in 2026](https://habit-streak.com/en/blog/habit-tracking/state-of-habit-tracking-2026)
