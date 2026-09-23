# WLOS International Market Research

**Date:** 23 September 2026
**Method:** web research, September 2026. Sources listed at the end.
**Status:** factual market matrix. **No country is ranked or recommended** —
that decision needs the segment research that follows this.

Researched across categories rather than within women's health alone, per the
instruction not to define WLOS against Flo and Clue by accident.

---

## 0. The finding that changes the product decision

**The EU KIDS Act was published on 17 September 2026 — six days ago — and it
prohibits, for minors, the specific mechanisms WLOS is built on.**

For under-18s it bans:

| Banned for minors | WLOS status |
|---|---|
| **Profiling-based recommender feeds**; recommenders must prioritise **non-personalised** content | **This is the entire targeting engine** — 10 dimensions, `fn_TargetedItems` |
| **Streaks that penalise a child for not returning daily** | **Already built** — streak ring on the home screen, computed by `Behaviour` |
| Engagement-driven reward loops | `Growth.*`, momentum state dimension |
| **AI companions off by default**; **banned entirely under 13** | The companion direction in the vision |
| Conversation memory with a minor, deleted when it ends | Longitudinal memory is the thesis |
| Push notifications during sleeping hours | Quiet hours already exist ✅ |

Scope explicitly covers **AI companions and chatbots**, not only social media.
Penalties reach **6% of global turnover**.

Separately, Italy's Garante fined Replika's developer **€5 million** in 2025,
partly for inadequate age verification *despite an 18+ policy*. **Declaring 18+
is not a defence.**

### What this means

The thing that makes WLOS valuable — personalised, contextual, longitudinal
understanding — is **restricted for exactly the youngest users the vision most
wants to serve**, in one of the two largest regulated markets.

Serving EU under-18s is not a configuration of WLOS. It is a **materially
different product**: non-personalised content, no streaks, no companion by
default, no persistent conversation memory.

> **Hypothesis, not decision: launch 18+, model lifelong.** 16+ and 18+ both
> remain candidates pending legal review per jurisdiction. **No launch-age
> decision has been made.** The 11–13 and 14–17 bands stay in the human model,
> unshipped, under either. Revisit only with a deliberate decision to build the
> constrained variant, and budget for it as a second product.

This is not an argument that girls don't deserve WLOS. It is that the EU has
just decided the mechanism by which WLOS would serve them is harmful, and
shipping into that without a purpose-built variant risks the company.

---

## 1. Market size and regional shape

| Metric | Figure |
|---|---|
| Global women's health app market, 2026 | **USD 6.3B** |
| Projected 2033 | USD 23.4B |
| CAGR 2026–2033 | 20.5% |
| North America share | **38.2%** (largest) |
| Asia Pacific CAGR | **15.8%** (fastest) |

North America is the money; Asia Pacific is the growth. Europe is segmented in
the sources but not separately quantified in what I could verify — **noted as a
gap, not filled with a guess.**

APAC growth is attributed to smartphone penetration, rising female workforce
participation and mobile-first healthcare adoption in India and Southeast Asia.

---

## 2. Competitive landscape — and it consolidated this year

| Player | Position | Scale |
|---|---|---|
| **Flo** | Cycle, ovulation, pregnancy. The consumer funnel | **420M+ registered users** |
| **Clue** | Science, privacy — **launched Perimenopause mode in 2026** | Much smaller |
| **Natural Cycles** | Regulated contraception (cleared device) | Smaller, defensible |
| **Midi Health** | Clinical menopause and midlife care | **$1B valuation, Feb 2026** |

### This invalidates one of my earlier recommendations

In the product audit I identified perimenopause and menopause as the least-served
life stages and recommended content there first.

**The market moved in 2026.** Clue shipped perimenopause; Midi reached $1B on
clinical midlife care. The category is actively consolidating toward midlife.
Entering there now means competing with a funded clinical platform and an
established brand, not filling a gap.

### Where the gap actually appears to be

Mapping the players onto the life model:

```
adolescence  young_adult  independent  partnership  planning
    ???          ???          ???          ???       Flo
pregnancy   postpartum  motherhood  midlife  perimenopause  menopause  senior
   Flo         Flo         ???        Midi       Clue/Midi     Midi      ???
```

**Unclaimed: adolescence, young adulthood, independent adult life, motherhood
as a life stage rather than a baby-tracking phase, and senior years.**

Adolescence and senior are unclaimed partly *because they are hard* — minors are
now heavily regulated (§0), and older users are the hardest to acquire through
app stores.

**The genuinely open space is 18–35 non-reproductive**: the woman who is not
pregnant, not trying, and not perimenopausal, whose actual problem is that work,
sleep, stress and life are interacting badly. Every incumbent reaches her
through her cycle. None reaches her through her life.

That is precisely the intersection WLOS's `SignalRelation` graph already models:
`long_work → high_stress → low_mood`.

---

## 3. Retention economics — the hardest fact in this document

| Benchmark | Figure |
|---|---|
| Day-1 retention, health & fitness | ~23% (70–80% never return after first session) |
| **Day-30 retention, median** | **5%** (strong performers 8–12%) |
| Monthly subscription churn | 7–10% |
| Annual plan retention | 33% |
| Monthly plan retention | 17% |
| Users willing to pay for premium | 71% |
| Churn stabilises | ~24 months, second annual renewal |

### What this means for the WLOS thesis

The vision is "install at 13, still using at 83." The category median is
**5% still present at day 30.**

Two readings, and the strategy must pick one:

1. **The thesis is the differentiator.** Every incumbent has a natural exit —
   she stops menstruating, gives birth, finishes menopause. WLOS is the only one
   with no exit. Retention *is* the product.
2. **The thesis is untested.** Nobody has demonstrated that longitudinal life
   context beats a single sharp job-to-be-done at keeping someone past day 30.

The annual-versus-monthly gap (33% vs 17%) matters commercially: WLOS's value
compounds over time, which argues for annual-first pricing — but annual pricing
demands confidence in the first week, which is the weakest part of any
longitudinal product.

**This is the single number that should discipline the MVP: what makes her come
back on day 31?**

---

## 4. Regulatory classification — the constitution is also a market strategy

The boundary is **intended use and marketing claims**, not technology. FDA and
EU regulators assess intent from *"marketing materials, app store descriptions,
website copy, social media, and user instructions"* — internal documentation
does not override external copy.

- **FDA**: revised *General Wellness: Policy for Low Risk Devices* finalised
  **6 January 2026**. Non-invasive, sensor-based tools may claim general
  wellness **if they avoid disease, diagnostic or clinical-management claims**.
- **EU MDR Rule 11**: most medical device software is **Class IIa or higher**,
  requiring Notified Body assessment and a full quality management system.

### The direct consequence for WLOS

The constitution's rule — *never infer diagnosis; report change from her own
baseline* — is not only an ethical position. **It is the line between a wellness
app and a Class IIa device.**

Concretely, for the camera direction:

| Claim | Classification |
|---|---|
| "Your appearance differs from your usual morning baseline" | General wellness |
| "You may be anaemic" / "you appear depressed" | **Medical device** |

And because *app store copy counts as evidence of intent*, a marketing page
saying "WLOS detects health conditions from a photo" makes it a device
regardless of what the code does.

**The constitution should be binding on marketing, not just engineering.**

---

## 5. Market matrix — what is known and what is not

Per the instruction to produce a factual matrix rather than a premature ranking:

| Dimension | Established | Not yet researched |
|---|---|---|
| Global market size and CAGR | ✅ $6.3B → $23.4B, 20.5% | — |
| Regional share | ✅ NA 38.2%, APAC 15.8% CAGR | Europe share; country-level |
| Competitive density | ✅ by segment | by country |
| Regulatory — minors | ✅ EU KIDS Act, Garante precedent | US state laws; APAC |
| Regulatory — device | ✅ FDA + EU MDR boundary | country-level health-claim rules |
| Retention benchmarks | ✅ category-wide | by country |
| Willingness to pay | ✅ 71% premium-willing | by country and purchasing power |
| Smartphone penetration among women | — | **needed** |
| Search/ASO demand | — | **needed, per country and language** |
| Acquisition cost | — | **needed** |
| Localisation burden | — | **needed per candidate** |
| Payment rails | — | **needed** |
| AI acceptance | — | **needed** |
| Partnership routes | — | **needed** |

**Seven of fourteen dimensions remain unresearched.** A country recommendation
on this basis would be assertion, not evidence.

---

## 6. What the research changes

| Earlier position | Revised |
|---|---|
| Minimum age 16+ recommended | **Both 16+ and 18+ are now candidates, neither decided.** The EU KIDS Act restricts the core mechanism for under-18s, which strengthens the 18+ case without settling it |
| Content first for perimenopause/menopause | **Reconsider.** Clue and Midi moved there in 2026; it is no longer the open gap |
| "Where it needs more" is a country question | It is **country × segment × job**. The open segment looks like 18–35 non-reproductive, in any market |
| Constitution is an ethics document | It is **also the regulatory boundary and must bind marketing copy** |

## 7. What I still cannot answer

- Which country to enter first. Seven framework dimensions are unresearched.
- Whether longitudinal context beats a sharp single job at day-30 retention.
  **No competitor has proven it, which is both the opportunity and the risk.**
- Europe's market share, which the sources segment but do not quantify in what I
  could verify.

## 8. Recommended next research

1. **Segment and job research** on 18–35 non-reproductive women — the one
   apparently unclaimed space. Interviews, not desk research.
2. **Country-level ASO and search demand** for the top three candidate markets
   once segment is confirmed.
3. **Day-31 question**: what single job would bring her back? This disciplines
   the MVP more than any country choice.

---

## Sources

- [Grand View Research — Women's Health App Market Size & Share Report 2026-2033](https://www.grandviewresearch.com/industry-analysis/womens-health-app-market)
- [Coherent Market Insights — Women Health App Market 2026-2033](https://www.coherentmarketinsights.com/market-insight/women-health-app-market-5656)
- [New Market Pitch — Flo Health update](https://newmarketpitch.com/blogs/news/femtech-flo-health-update)
- [IAPP — European Commission unveils EU KIDS Act](https://iapp.org/news/a/european-commission-unveils-eu-kids-act)
- [Freshfields — The EU KIDS Act: beyond social media bans](https://www.freshfields.com/en/our-thinking/blogs/technology-quotient/the-eu-kids-act-europe-moves-online-child-safety-beyond-social-media-bans-102o1ld)
- [Bird & Bird — The EU KIDS Act: A New Generation of Rules for Child Online Safety](https://www.twobirds.com/en/insights/2026/the-eu-kids-act-a-new-generation-of-rules-for-child-online-safety)
- [European Commission — The KIDS Act explained](https://digital-strategy.ec.europa.eu/en/faqs/kids-act-explained)
- [Martin Cid Magazine — EU Kids Act and AI companion chatbots](https://www.martincid.com/technology-sv/eu-kids-act-ai-companion-chatbot-ban-minors/)
- [MedEnvoy — FDA Guidance on General Wellness: Policy for Low-Risk Devices](https://medenvoyglobal.com/blog/fda-guidance-on-general-wellness-policy-for-low-risk-devices/)
- [Greenlight Guru — SaMD: Classification, FDA & EU Rules](https://www.greenlight.guru/blog/samd-software-as-a-medical-device)
- [Adapty — In-app subscription benchmarks for Health & Fitness apps](https://adapty.io/blog/health-fitness-app-subscription-benchmarks/)
- [Sahha — Why Most Health App Users Churn Within 90 Days](https://sahha.ai/blog/health-app-churn-retention/)
- [Business of Apps — Health & Fitness App Benchmarks 2026](https://www.businessofapps.com/data/health-fitness-app-benchmarks/)
