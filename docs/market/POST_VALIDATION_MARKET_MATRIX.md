# WLOS Post-Validation Market Matrix — the instrument

**Date created:** 23 September 2026
**Status:** **TEMPLATE. EMPTY BY DESIGN.**
**Fill only after:** the Phase A Findings Report reaches item 13
(`Phase B · narrow · or change the product`) — see `docs/PROJECT_STATE.md` §9.

---

## 0. What this document is, and what it is not

### It is

A blank instrument. Twelve columns, each defined precisely enough that two
different researchers filling it for the same country would produce
comparable answers. Rows are candidate markets and are **deliberately
unpopulated**.

### It is not

- **Not market research.** No research is performed here.
- **Not a ranking.** No country is scored, ordered or compared.
- **Not a recommendation.** No market is named as a candidate, a favourite
  or a shortlist entry.
- **Not authorisation.** `docs/PROJECT_STATE.md` §9.0 lists `market ranking`
  and `country selection` among the fifteen suspended items. Building the
  instrument does not unsuspend them.

The existing research — `WLOS_MARKET_RESEARCH.md` and
`WLOS_MARKET_RESEARCH_II.md` — is **sufficient for the current phase**. This
file exists so that when country selection *does* become a live question, the
answer is produced by a pre-agreed instrument rather than by whoever argues
most confidently on the day.

### Why an empty instrument is worth building now

Because the instrument is honest only while it is empty. A matrix designed
after a preferred country exists will, without anyone intending it, weight
the columns that favour that country. Designing the measurement before
knowing the answer is the whole point.

---

## 1. Rules of use

1. **Do not populate a row before Phase A item 13.** A country filled in
   early becomes an anchor, and every later cell gets read as support for it.
2. **Every cell carries a status marker.** No cell is ever left ambiguous:

   | Marker | Meaning |
   |---|---|
   | **ESTABLISHED** | A figure exists in prior research. Cite the document and section. Do not re-research. |
   | **NEEDED** | Not researched. Leave the value blank. **Never estimate.** |
   | **N/A** | The column does not apply to this market, with a stated reason. |

3. **A blank cell is a finding.** It is not a failure to fill in. The prior
   research established the discipline: *"Recorded as a gap. Not estimated."*
   (`WLOS_MARKET_RESEARCH_II.md` §1.7).
4. **Global figures are not country figures.** Every ESTABLISHED global
   baseline in §2 below still needs country-level confirmation before it is
   used to discriminate between markets. Carrying a global number into a
   country cell is the most likely way this instrument gets misused.
5. **Read §4 before filling anything.** The matrix cannot be summed. It
   produces different winners depending on which of six objectives is being
   optimised, and the objective must be stated first.
6. **No composite score.** Do not add a weighted-total column. Weighting is
   an argument about objectives (§4), not an arithmetic operation, and a
   single number hides which objective was chosen.

---

## 2. Global baseline carried forward — ESTABLISHED, do not re-research

These are established in prior research at global or regional level. They are
reproduced here so the instrument is self-contained, and so that nobody
re-runs research that is already done.

**They are inputs to the instrument, not rows in it.** Regional figures below
name regions and countries only because the source research did; naming is
not nomination, and nothing here constitutes a shortlist.

### 2.1 Market size and growth

| Metric | Figure | Source |
|---|---|---|
| Global women's health app market, 2026 | **USD 6.3B** | `WLOS_MARKET_RESEARCH.md` §1 |
| Projected 2033 | **USD 23.4B** | §1 |
| CAGR 2026–2033 | **20.5%** | §1 |
| Femtech market 2026 | **USD 9.78B** → 18.98B by 2031 | `WLOS_MARKET_RESEARCH_II.md` §1.4 |
| Femtech CAGR | **14.2%** | §1.4 |

### 2.2 Regional share

| Region | Figure | Source |
|---|---|---|
| North America share of market | **38.2%** (largest) | `WLOS_MARKET_RESEARCH.md` §1 |
| Asia Pacific CAGR | **15.8%** (fastest) | §1 |
| Europe share | **NEEDED** — segmented in sources, not separately quantified | §1, §7 |

APAC growth is attributed to smartphone penetration, rising female workforce
participation and mobile-first healthcare adoption.

### 2.3 CPI benchmarks by region

| Segment | CPI | Source |
|---|---|---|
| Health & Fitness, global | **$4.30–5.50** | `WLOS_MARKET_RESEARCH_II.md` §1.2 |
| iOS, global Q1 2026 | **$5.84** (+19% YoY) | §1.2 |
| Android, global | **$1.92** (+8% YoY) | §1.2 |
| North America | **$2.50–5.00** | §1.2 |
| Western Europe | **$3.40 iOS / $1.85 Android** | §1.2 |
| India | **₹30–90 (~$0.32–0.96)** | §1.2 |
| Tier-1 health & wellness | **£2–7**, D7 ROAS 100–120% | §1.2 |

**Trend fact, not a country fact:** iOS CPI rose **19% year over year**. Paid
acquisition is getting worse everywhere, which raises the value of the one
column this instrument cannot yet fill (C1/C2).

### 2.4 Smartphone gender gap

| Metric (low- and middle-income countries) | Figure | Source |
|---|---|---|
| Gender gap, mobile ownership | **7%** | `WLOS_MARKET_RESEARCH_II.md` §1.1 |
| **Gender gap, smartphone ownership** | **13%** | §1.1 |
| Women less likely than men to use mobile internet | **12%** | §1.1 |
| Women not using mobile internet in LMICs | **810 million** | §1.1 |
| Sub-Saharan Africa mobile internet gap | **30% (2024) → 26% (2025)** | §1.1 |
| Worst surveyed (Ethiopia) | **36% internet, 34% smartphone** | §1.1 |

Named barriers: handset affordability, literacy, digital skills, social
norms, lower income.

### 2.5 AI trust

| Finding | Figure | Source |
|---|---|---|
| US adults who used an AI chatbot for health info in the past year | **32%** | `WLOS_MARKET_RESEARCH_II.md` §0.2 |
| Still trust their doctor over the chatbot | **74%** | §0.2 |
| Trust a chatbot **with** healthcare-professional oversight | **49–55%** | §0.2 |
| Trust a chatbot **without** professional oversight | **3–6%** | §0.2 |
| AI-health users who uploaded personal medical info anyway | **41%** | §0.2 |

The ~10:1 gap between supervised and unsupervised trust is the finding. It is
US-sourced; a cross-country dataset exists (*Nature*, 1.7M health-related
conversations, 109 countries, Jan–Mar 2026) and is named in §1.3 as worth
commissioning properly rather than inferring.

### 2.6 Retention benchmarks

| Benchmark | Figure | Source |
|---|---|---|
| Day-1 retention, health & fitness | **~23%** | `WLOS_MARKET_RESEARCH.md` §3 |
| **Day-30 retention, median** | **5%** (strong 8–12%) | §3 |
| Monthly subscription churn | **7–10%** | §3 |
| Annual plan retention | **33%** | §3 |
| Monthly plan retention | **17%** | §3 |
| Users willing to pay for premium | **71%** | §3 |
| Churn stabilises | **~24 months** | §3 |
| Motivation drop-off after breaking a streak | **44%** | `WLOS_MARKET_RESEARCH_II.md` §0.1 |

**Category-wide. Not established by country** — see C4 and C11.

### 2.7 Employer / B2B2C signals

| Finding | Figure | Source |
|---|---|---|
| Large US employers viewing holistic women's health as critical to recruitment | **69%** | `WLOS_MARKET_RESEARCH_II.md` §1.4 |
| Intending to extend telehealth/clinic access | **75%** | §1.4 |
| US employers offering fertility coverage | **30% (2020) → 40% (2024)** | §1.4 |
| Maven Clinic (B2B2C reference) | **2,000+ companies, 6.7M lives, 175 countries** | §1.4 |

Category shift recorded: away from women's health as an HR perk, toward part
of the core risk pool for health systems and insurers. Private equity is
specifically seeking sticky B2B distribution.

**US-sourced. B2B2C maturity outside the US is NEEDED** — see C12.

### 2.8 Localisation unit economics

| Item | Cost | Source |
|---|---|---|
| Human translation | **$0.12–0.20 per word** | `WLOS_MARKET_RESEARCH_II.md` §1.5 |
| ~10,000-word app | **$1,000–3,000 per language** | §1.5 |
| Cultural adaptation premium | **+30–50%** | §1.5 |
| Full market localisation incl. marketing and support | **$10,000–50,000+ per market** | §1.5 |

### 2.9 Payment rails, global

| Finding | Figure | Source |
|---|---|---|
| Digital wallets, share of transaction value | **52%** | `WLOS_MARKET_RESEARCH_II.md` §1.6 |
| Credit cards | **22%** | §1.6 |
| Debit cards | **12%** | §1.6 |
| Emerging economies, transactions still cash | **>50%** | §1.6 |
| Emerging economies, non-card payment methods | **~60%** | §1.6 |
| In-app purchase market 2026 | **$322.81B (+26.2%)** | §1.6 |

### 2.10 The one dimension with no baseline at all

**Search demand and ASO difficulty (C1, C2) are the known unfilled gap.**
Prior research states it explicitly:

> *"I could not obtain category-level, country-level app-store search volume
> from open sources. It needs a paid ASO tool... Recorded as a gap. Not
> estimated."* — `WLOS_MARKET_RESEARCH_II.md` §1.7

And in §4 of the same document, for every market considered: **ASO demand —
unknown**. This is the only column where the gap is total: no global figure,
no regional figure, no proxy. **It requires a paid tool and a budget line.**

---

## 3. The instrument

One logical matrix, presented as three panels for legibility. **Rows are
candidate markets and are left blank. Do not populate.**

Row identity convention when the matrix is eventually used: one row per
**market**, where a market is a country plus a language plus a store
front — not a country alone. A country with two store languages is two rows,
because C7 (localisation) and C1/C2 (search) differ per language.

### Panel A — demand and competition

| Market | C1 Search demand | C2 ASO difficulty | C3 Competitor density | C4 Purchasing power |
|---|---|---|---|---|
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |

### Panel B — access and adoption

| Market | C5 Smartphone usage among women | C6 AI acceptance | C7 Localisation burden | C8 Payment feasibility |
|---|---|---|---|---|
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |

### Panel C — risk and route to market

| Market | C9 Regulatory burden | C10 Healthcare navigation | C11 Acquisition cost | C12 Partnership routes |
|---|---|---|---|---|
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |
| *(blank)* | | | | |

### Cell format

Each cell carries three parts, so a filled matrix can be audited:

```
<value> | <STATUS> | <source + date>
```

Example of the required shape (illustrative format only, no market named):

```
[figure] | NEEDED | —
[figure] | ESTABLISHED | WLOS_MARKET_RESEARCH_II.md §1.2, Sep 2026
```

---

## 4. Column definitions

Twelve columns. For each: the question it answers, the source or tool that
answers it, what good and bad look like **for WLOS specifically**, and
whether prior research already established it.

---

### C1 · Search demand

**Question it answers**
How many women in this market are already searching an app store, in their
own language, for the problem WLOS addresses — and are they searching for
*symptoms and single jobs* (sleep, stress, cycle, journal) or for
*life-context* language? The second question matters more than the first,
because it tells us whether the category WLOS is entering exists in her head
or has to be created.

**Source or tool**
- **Sensor Tower** — app-store keyword volume and download estimates by
  country.
- **data.ai** (formerly App Annie) — market-level category demand,
  cross-country comparison.
- **AppTweak** — keyword volume, search-ads difficulty, long-tail discovery.
- **Google Keyword Planner / Google Trends** — web-search demand as an
  imperfect leading proxy for app-store demand; free, and useful for
  *relative* language patterns rather than absolute volume.
- **Apple Search Ads** popularity scores — directional, free with an
  advertiser account.
- **Google Play Console** peer-group data — only once an app is listed.

Required before any of these are useful: a **defined keyword set**, agreed in
advance and versioned, covering (a) single-job terms, (b) life-context terms,
(c) competitor brand terms, (d) translated equivalents per language.

**Good for WLOS**
Meaningful volume on life-context and interaction language ("why am I so
tired all the time", "burnout", "overwhelmed", "keep track of how I'm doing")
rather than only on single-axis terms. This would mean she already frames her
problem the way WLOS frames it, and organic discovery is possible.

**Bad for WLOS**
All demand concentrated on single-job terms owned by incumbents. That means
WLOS can only be found by describing itself as something it is not, or by
paying — and §2.3 shows paying is getting worse annually.

**Status**
**NEEDED — the known unfilled gap.** No figure exists at global, regional or
country level. Prior research explicitly refused to estimate it
(`WLOS_MARKET_RESEARCH_II.md` §1.7, and "unknown" for every market in §4).
Requires a paid tool and a budget line. **This is the single most
consequential blank in the instrument**, because organic discovery is the
only acquisition route that survives a $5.84 iOS CPI.

---

### C2 · ASO difficulty

**Question it answers**
Given whatever demand C1 finds, how hard is it to rank for it? Who holds the
top slots, how entrenched are they by rating count and download velocity, and
is there a long tail that a new entrant can actually take?

**Source or tool**
- **AppTweak** — keyword difficulty scores, competitor ranking history.
- **Sensor Tower** — top-chart and keyword-ranking share by country.
- **data.ai** — category concentration.
- **App Store / Play Store manual inspection** — the cheapest first pass:
  search the keyword set by hand in each store front and record the top ten.
- **Apple Search Ads** — bid costs as a direct read on contested terms.

Distinguish two sub-measures and record both: **head difficulty** (can we
rank for the obvious term) and **tail availability** (is there a cluster of
lower-volume terms with weak incumbents).

**Good for WLOS**
A long tail of life-context terms with weak or irrelevant incumbents, where a
small, well-targeted listing can rank without paid support.

**Bad for WLOS**
Head terms locked by apps with hundreds of thousands of ratings — the shape
§2.2 and the competitive landscape imply — with no usable tail. Then
discovery is a paid-only problem and C11 becomes the binding constraint.

**Status**
**NEEDED — same gap as C1, same tool, same budget line.** Not established at
any level.

---

### C3 · Competitor density

**Question it answers**
Who else is already in front of this woman in this market — not only women's
health apps, but every app holding one axis of her life: cycle, sleep,
journaling, habits, meditation, therapy. And critically: **is anyone claiming
the join?**

**Source or tool**
- **Sensor Tower / data.ai** — category top charts and download share per
  country, including local players that never appear in Western coverage.
- **App Store / Play Store category browsing per store front** — the only way
  to see local incumbents.
- **Crunchbase / PitchBook** — local funding activity in femtech and digital
  wellness.
- **Local press and femtech trackers** — regional consolidation.

**Good for WLOS**
Many single-axis apps, none claiming life-context integration. Prior research
frames the differentiator precisely: *"Every alternative holds one axis of
her life. WLOS's only defensible claim is the join"*
(`WLOS_MARKET_RESEARCH_II.md` §5). Fragmentation across axes is the
opportunity.

**Bad for WLOS**
A strong local incumbent already positioned on integration or on "understands
your whole life", or a dominant super-app with a wellness surface she already
opens daily. Also bad: a market where the category is actively consolidating,
as prior research found for midlife in 2026.

**Status**
**ESTABLISHED globally and by segment; NEEDED by country.**
Established (`WLOS_MARKET_RESEARCH.md` §2): **Flo 420M+ registered users**;
**Clue** launched Perimenopause mode in 2026; **Natural Cycles** holds
regulated contraception; **Midi Health $1B valuation, Feb 2026**. Established
finding that the category consolidated toward midlife in 2026, invalidating
an earlier perimenopause-first position. Established that the apparently
unclaimed space is **18–35 non-reproductive** — *in any market*, which is
exactly why country-level density is still needed.
**NEEDED:** per-country density, and specifically local non-Western
incumbents.

---

### C4 · Purchasing power

**Question it answers**
Can enough women in this market pay a recurring subscription at a price that
sustains the product, and what is the realistic local price point — not the
converted US price? Distinct from C8: C4 asks whether she *can* pay, C8 asks
whether the rails *let* her.

**Source or tool**
- **World Bank** — GNI per capita, PPP-adjusted.
- **OECD** — household disposable income.
- **IMF World Economic Outlook** — purchasing power parity series.
- **Sensor Tower / data.ai** — actual in-app revenue per download by country,
  which is the only figure that reflects willingness rather than capacity.
- **Apple / Google local pricing tiers** — the practical price grid.
- **Numbeo** — discretionary-spend context, directional only.

Record **revenue per download**, not just income. Income is capacity;
revenue per download in the health category is the evidenced behaviour.

**Good for WLOS**
A local price point that clears CAC with margin at annual billing. Prior
research favours annual-first (**33% annual vs 17% monthly retention**,
§2.6), so the relevant test is whether an *annual* price is payable in one
instalment, which is a harder test than monthly affordability.

**Bad for WLOS**
A market where only a monthly price is payable. That combines the worse
retention curve (17%) with the renewal friction flagged in C8, and prior
research warns the combination compounds: *"Cheap to acquire is not cheap to
retain."*

**Status**
**Partially ESTABLISHED globally; NEEDED by country.**
Established: **71% of users are willing to pay for premium** and the annual
33% / monthly 17% split (`WLOS_MARKET_RESEARCH.md` §3). Established
qualitatively by region in `WLOS_MARKET_RESEARCH_II.md` §4 (US highest,
Western Europe high, India lower).
**NEEDED:** country-level revenue per download, local price grid, and annual
affordability.

---

### C5 · Smartphone usage among women

**Question it answers**
Does the woman WLOS is designed for own a smartphone, privately, that she
does not share? WLOS assumes private journaling, personal data and camera
access. Sole private ownership is a **product precondition**, not a nice-to-have.

**Source or tool**
- **GSMA Mobile Gender Gap Report** — the primary source; ownership, mobile
  internet use, and the gap, by country.
- **GSMA Mobile Economy** regional reports — penetration and growth.
- **ITU (International Telecommunication Union)** — ICT indicators by gender.
- **Pew Research Center** — smartphone ownership in higher-income markets.
- **National statistics offices** — census and household ICT surveys.
- **StatCounter** — iOS/Android split, which also feeds C11.

Record three separate numbers, not one: ownership, *sole* ownership, and
mobile-internet use. The gap between ownership and sole ownership is the one
that matters for a private journal.

**Good for WLOS**
High smartphone ownership among women with a small gender gap, high mobile
internet use, and cultural norms supporting private personal device use.

**Bad for WLOS**
A large gender gap, or high ownership with low *private* ownership. Prior
research states the consequence directly: a product requiring a personal
device, private journaling and camera access *"is itself a segmentation
decision, and one that quietly excludes the women with the least support."*
That is an ethical finding as much as a commercial one, and it should be
recorded in the cell, not filtered out.

**Status**
**ESTABLISHED globally (LMIC aggregate); NEEDED by country.**
Established (`WLOS_MARKET_RESEARCH_II.md` §1.1): mobile ownership gap **7%**,
**smartphone ownership gap 13%**, women 12% less likely to use mobile
internet, **810 million** women in LMICs not using mobile internet, Sub-Saharan
Africa gap 30% (2024) → 26% (2025), worst surveyed Ethiopia at 36% internet /
34% smartphone.
**NEEDED:** per-country figures, and *sole* ownership, which the aggregate
does not report.

---

### C6 · AI acceptance

**Question it answers**
In this market, will she accept an AI system reasoning about her personal
life — and specifically, does the supervised/unsupervised trust gap hold
here? Also: is there a local regulatory or cultural position on AI in health
that changes the answer?

**Source or tool**
- **KFF health-information polling** — the source of the established US
  figures; US-only.
- ***Nature* Health, "Global analysis of country-level factors associated
  with chatbot usage for health"** — 1.7M health conversations, 109
  countries, Jan–Mar 2026. Prior research names this as *"worth commissioning
  properly rather than inferring"*.
- **Edelman Trust Barometer** — trust in technology and in institutions by
  country, annual.
- **Eurobarometer** — EU attitudes to AI.
- **Ipsos Global AI Monitor** — cross-country AI comfort and concern.
- **Commissioned local survey** — the only route to WLOS-specific wording.

**Good for WLOS**
A market where AI-with-oversight is trusted and provenance is valued. That is
the side of the trust gap WLOS's constitution already sits on: a system that
refuses to diagnose, shows its reasoning and cites reviewed content.

**Bad for WLOS**
Either extreme. Low AI trust means the product must be sold on something
other than its intelligence. *Uncritically high* AI trust is also bad, and
less obviously so: it invites her to treat WLOS as a clinician, which the
constitution forbids and which pushes intended use toward device
classification (see §5).

**Status**
**ESTABLISHED (US); NEEDED by country.**
Established (`WLOS_MARKET_RESEARCH_II.md` §0.2): **32%** of US adults used an
AI chatbot for health info in the past year; **74%** still trust their doctor
more; trust **with** professional oversight **49–55%**; **without** oversight
**3–6%**; **41%** of AI-health users uploaded personal medical information
anyway. The ~10:1 supervised/unsupervised gap is the finding.
**NEEDED:** whether the gap holds outside the US, and local AI-in-health
regulation.

---

### C7 · Localisation burden

**Question it answers**
What does it actually cost to make WLOS feel native here — not the
translation bill, but the **cultural adaptation** bill, which for health
guidance is the larger and riskier number?

**Source or tool**
- **Translation vendor quotes** (Lionbridge, RWS, Smartling, Gengo) against
  the actual string count.
- **Clinical review costing** — local clinician review of health content,
  which is the part that cannot be machine-translated.
- **String-count extraction** from the repo — the base multiplier.
- **Store-front language requirements** — Apple and Google listing
  localisation rules per territory.
- **Local UX research** — date formats, name formats, body and menstruation
  vocabulary, how directly health topics can be named.

Record four sub-costs separately: UI strings, clinical/health content,
marketing and store listing, and support.

**Good for WLOS**
English is viable, or one additional language covers the market. A single
script direction. Health topics can be named directly in local vocabulary
without euphemism.

**Bad for WLOS**
Multiple languages needed for one market; RTL script; or a market where
health and body topics require substantial euphemistic reframing — because
that is content redesign, not translation, and it sits in the +30–50%
cultural-adaptation band or above.

**Note on an existing platform lever.** `ContentTranslation.IsMachineTranslated`
and `Identity.Language.IsRightToLeft` already exist
(`docs/PROJECT_STATE.md` §4). Prior research identifies the first as the lever
that makes this cost structure viable: clinical content gated to human
translation, everything else machine-translated. That is an observation about
what the schema already supports, **not a work item** — §9.0 remains in force.

**Status**
**ESTABLISHED as unit economics; NEEDED per market.**
Established (`WLOS_MARKET_RESEARCH_II.md` §1.5): human translation
**$0.12–0.20 per word**; ~10,000-word app **$1,000–3,000 per language**;
cultural adaptation **+30–50%**; full market localisation including marketing
and support **$10,000–50,000+ per market**.
**NEEDED:** the per-market total, and the clinical-review component, which
the unit costs above do not include.

---

### C8 · Payment feasibility

**Question it answers**
Can she subscribe and *stay* subscribed without re-authorising every renewal?
This is a retention question disguised as a payments question.

**Source or tool**
- **Worldpay Global Payments Report** — payment-method share by country; the
  source of the established global split.
- **AppsFlyer subscription reports** — subscription behaviour by market,
  including emerging-market renewal friction.
- **Apple / Google supported payment methods by territory** — the binding
  constraint, since store billing is mandatory for digital subscriptions.
- **Adyen / Stripe local-method documentation** — where store billing is not
  the only route.
- **Local wallet documentation** (UPI, Pix, GrabPay, M-Pesa, etc.) — for
  auto-debit support specifically.

The one question to answer per market: **does the dominant local payment
method support automatic recurring debit?**

**Good for WLOS**
Card or wallet penetration with genuine auto-renewal support, so the annual
plan (33% retention) is actually purchasable and renewable.

**Bad for WLOS**
The pattern prior research names explicitly: *"Low card penetration in
emerging markets forced subscription merchants to rely on one-off payment
workarounds... these approaches eroded retention because every renewal
required the customer to pay again, manually."* A market like this can look
excellent on C11 and still fail commercially — the established warning is
that low CPI is *offset* by renewal friction.

**Status**
**ESTABLISHED globally; NEEDED by country.**
Established (`WLOS_MARKET_RESEARCH_II.md` §1.6): digital wallets **52%** of
transaction value, credit cards **22%**, debit **12%**; emerging economies
**>50%** cash and **~60%** non-card; in-app purchase market **$322.81B
(+26.2%)**. APAC is the fastest-growing recurring-payments region.
**NEEDED:** per-country method mix and, specifically, auto-debit support.

---

### C9 · Regulatory burden

**Question it answers**
What must be true about the product for it to be lawful here, and does that
make it a *different product*? Three sub-questions, screened separately —
see §5 for the full screening procedure.

1. Minors: is the WLOS mechanism lawful for the intended age band?
2. Device classification: does the intended use, **as expressed in marketing
   copy**, make it a regulated medical device?
3. Data protection: what does processing health data require here?

**Source or tool**
- **Local counsel in the target jurisdiction.** No substitute. Everything
  below is preparation for that conversation, not a replacement for it.
- **EU:** KIDS Act texts and Commission FAQ; MDR Rule 11 and MDCG guidance;
  GDPR Art. 9 (special-category data); national DPA guidance; EU AI Act
  obligations.
- **US:** FDA *General Wellness: Policy for Low Risk Devices* (revised 6 Jan
  2026); FTC Health Breach Notification Rule; state minor-safety and
  age-verification statutes; state privacy laws (CCPA/CPRA and successors);
  HIPAA applicability analysis (usually not applicable direct-to-consumer,
  but must be confirmed, not assumed).
- **Other jurisdictions:** national medicines/device agency guidance on
  software; national data protection authority guidance.
- **IAPP** and major law-firm trackers (Bird & Bird, Freshfields) for
  cross-jurisdiction monitoring.

**Good for WLOS**
A market with a clear general-wellness safe harbour, a workable minors
position for the chosen age band, and health-data rules the platform's
existing consent model can meet.

**Bad for WLOS**
A market where the core mechanism — personalised recommendation, longitudinal
memory, streaks — is restricted for the intended age band. Prior research
states the consequence: serving EU under-18s *"is not a configuration of
WLOS. It is a materially different product."* Also bad: any market where the
general-wellness line is narrower than the FDA's, since that would force
either Class IIa conformity or a reduced product.

**Status**
**ESTABLISHED for EU and US at framework level; NEEDED by country.**
Established (`WLOS_MARKET_RESEARCH.md` §0, §4): **EU KIDS Act published 17
September 2026**, penalties to **6% of global turnover**; Italy's Garante
fined Replika's developer **€5 million** partly for inadequate age
verification *despite an 18+ policy*; **FDA General Wellness policy finalised
6 January 2026**; **EU MDR Rule 11** places most medical device software at
**Class IIa or higher**.
**NEEDED:** US state-level minor laws, APAC regulation entirely, country-level
health-claim rules, and local counsel everywhere.

---

### C10 · Healthcare navigation

**Question it answers**
When WLOS notices something and says *"this is worth raising with a
clinician"* — what happens next in this market? Can she reach one, at what
cost, in what time? This column measures the **destination of the handoff**,
and the handoff is the line the constitution draws.

**Source or tool**
- **OECD Health at a Glance** — access, waiting times, out-of-pocket share.
- **WHO Global Health Observatory** — clinician density, coverage.
- **Commonwealth Fund International Health Policy Surveys** — access and
  wait times, cross-country.
- **National health ministry statistics** — referral pathways.
- **Local insurer and telehealth coverage data** — the practical route.
- **Local clinician interviews** — the only way to learn what she is actually
  told to do.

Record specifically: emergency number, routine appointment wait, out-of-pocket
cost of a first consultation, whether women's health is a distinct specialty
route, and whether telehealth is a real option.

**Good for WLOS**
Reachable, affordable care. Then "notice → raise it with someone" is a
complete and honest loop, and WLOS keeps its position on the right side of
the trust gap: a system with professional oversight downstream (C6: 49–55%
trust) rather than one operating alone (3–6%).

**Bad for WLOS**
Care that is unreachable or unaffordable. This is the subtle failure mode and
the reason this column exists: in such a market, users will press WLOS to be
the clinician, reviewers and press will judge it as one, and the commercial
pull toward diagnostic language becomes strong. That is precisely the pull
that changes classification under C9 and §5. **A market with high unmet need
and no reachable care is not automatically a good market — it is the market
where the constitution is under the most pressure.**

**Status**
**NEEDED entirely.** Not researched at any level in either prior document.

Note for whoever fills it: `Identity.Country` currently has four columns and
no emergency, healthcare or regulatory profile, and "country safety
configuration" is listed in `docs/PROJECT_STATE.md` §5 as a medium-cost
missing primitive **and** in §9.0 as suspended. The column records a research
finding; it does not authorise the schema work.

---

### C11 · Acquisition cost

**Question it answers**
What does it cost to put WLOS in front of one woman here, by channel and
platform, and how does that compare to what she is worth (C4)? And is paid
acquisition viable at all, or is the market organic-or-nothing?

**Source or tool**
- **Liftoff Mobile Ad Creative Index** and **AppsFlyer Performance Index** —
  CPI and ROAS benchmarks by country, platform and vertical.
- **Sensor Tower** — paid-UA share and spend estimates by competitor.
- **Meta / Google / TikTok ad platform** planning tools — live auction costs
  for the actual target audience, which is more accurate than any benchmark.
- **Apple Search Ads** — cost per tap and per install against the C1 keyword
  set; also directly informs C2.
- **StatCounter** — iOS/Android split, which drives blended CPI given the
  ~3× platform gap.

Record blended CPI, platform-split CPI, and **CPI for the actual segment**,
not the category. Category CPI understates the cost of reaching a narrow
audience.

**Good for WLOS**
CPI low relative to expected LTV at annual pricing, on a platform mix that
matches where the target women are — **and** a viable organic route from
C1/C2, since paid-only is a worsening position.

**Bad for WLOS**
High CPI with no organic route. Also bad, and easy to miss: very low CPI in a
market where C8 shows renewal friction and C4 shows low ARPU. Prior research
makes this a single compound finding — low CPI is *offset* by subscription
mechanics that work against retention.

**Status**
**ESTABLISHED by region; NEEDED by country and segment.**
Established (`WLOS_MARKET_RESEARCH_II.md` §1.2, reproduced at §2.3 above):
Health & Fitness global **$4.30–5.50**; iOS global Q1 2026 **$5.84 (+19%
YoY)**; Android global **$1.92 (+8% YoY)**; North America **$2.50–5.00**;
Western Europe **$3.40 iOS / $1.85 Android**; India **~$0.32–0.96**; Tier-1
health & wellness **£2–7** at D7 ROAS 100–120%.
**NEEDED:** country-level CPI for the chosen segment, and the blended figure
against the local platform split.

---

### C12 · Partnership routes

**Question it answers**
Is there a non-app-store route to her here — employer, insurer, health
system, telecom, retailer, NGO? Prior research identifies B2B2C as the
strongest commercial signal found in the entire study, so this column asks
whether that route exists in *this* market or only in the one where it was
measured.

**Source or tool**
- **Mordor Intelligence / CB Insights** — femtech market structure by region.
- **Mercer** and **WTW** employer benefits surveys — by country; the
  equivalent of the US employer figures.
- **Business Group on Health** — US employer benchmark (source of the
  established 69% / 75% figures).
- **National insurer and health-system procurement portals** — whether
  digital wellness is a purchasable category.
- **Maven Clinic, Peppy, Carrot** market footprints — where B2B2C already
  operates (Maven: 175 countries).
- **Local benefits brokers and telecom bundling teams** — direct enquiry.

**Good for WLOS**
Employers or insurers already buying women's health benefits, with a
procurement route a small company can enter. This addresses WLOS's two
weakest positions simultaneously: acquisition cost (C11) and day-30 retention
(§2.6), because an employer channel shortcuts both.

**Bad for WLOS**
No institutional buyer, or a procurement cycle too long to survive. And one
risk that is not commercial: `docs/PROJECT_STATE.md` §8 records that *"an
employer-funded product raises a trust question that may matter more than
acquisition cost."* The evidence in §2 of the prior research is that women are
**less comfortable raising stress with a manager** — so an employer-branded
product may be least trusted by exactly the woman with the strongest need.
**Record the trust risk in the cell alongside the commercial figure.** A high
C12 score is not unambiguously good.

**Status**
**ESTABLISHED (US); NEEDED by country.**
Established (`WLOS_MARKET_RESEARCH_II.md` §1.4): femtech **$9.78B (2026) →
$18.98B (2031)**, CAGR **14.2%**; **69%** of large US employers view holistic
women's health as critical to recruitment; **75%** intend to extend
telehealth/clinic access; US employers offering fertility coverage **30%
(2020) → 40% (2024)**; **Maven Clinic: 2,000+ companies, 6.7M lives, 175
countries**. Established that private equity is specifically seeking sticky
B2B distribution.
**NEEDED:** B2B2C maturity outside the US — prior research records it as
"Emerging" for Western Europe and "Not researched" elsewhere.

---

## 5. The six meanings of "where it needs more"

**Read this before filling a single cell.**

"Where does WLOS need to go?" and "where is it needed more?" sound like one
question. They are six. Each is legitimate. Each is answerable. **Each points
at a different country**, and none of them is more correct than the others in
the abstract — only relative to a stated objective.

| # | Meaning | The question it really asks | Columns that decide it |
|---|---|---|---|
| **M1** | **Highest demand** | Where are most women already looking for this? | C1, C2, C3 |
| **M2** | **Highest unmet need** | Where is the problem worst and the least served? | C5, C10, plus segment evidence |
| **M3** | **Highest willingness to pay** | Where will she pay most, most reliably? | C4, C8 |
| **M4** | **Highest growth** | Where is the market expanding fastest? | §2.1, §2.2, C5 trajectory |
| **M5** | **Lowest competition** | Where is the join unclaimed? | C3, C2 |
| **M6** | **Best launch economics** | Where does the first cohort cost least and retain best? | C11, C7, C9, C12 |

### Why they diverge

The prior research already demonstrates the divergence without naming a
winner. From `WLOS_MARKET_RESEARCH_II.md` §4, as established facts:

- The market with **the best economics also has the worst competition** —
  M3 and M6 pull one way, M5 pulls the other.
- The market with **the best acquisition cost has the worst renewal
  mechanics** — M6 splits against itself, because CPI and retention are both
  launch economics.
- The market with **the heaviest regulatory load** (KIDS Act, MDR Rule 11,
  per-language cultural adaptation) may still rank high on M1 and M3.
- **M4 and M3 are structurally opposed** in this category: the established
  figures put the largest share in one region (38.2%) and the fastest growth
  in another (15.8% CAGR).
- **M2 is the most dangerous when taken alone.** The market with the highest
  unmet need is likely to be the market with the largest smartphone gender
  gap (C5), the weakest payment rails (C8) and the least reachable care
  (C10). Highest need can correlate with lowest feasibility — and, per C10,
  with the greatest pressure on the constitution.

### The rule this section exists to impose

> **The strategy must state which of M1–M6 it optimises for, in writing,
> BEFORE any country is named.**

Not after. If the objective is chosen after the country, the objective will
be chosen to justify the country, and the instrument will have been used as
decoration.

### Procedure when the matrix is eventually filled

1. State the objective. One of M1–M6, or an explicitly ordered combination
   with the priority written down.
2. State the reason the objective follows from the Phase A findings — not
   from preference.
3. State what would make the objective wrong, and what evidence would
   overturn it.
4. **Only then** read the matrix against it.
5. Report the answer the matrix gives under **at least one competing
   objective**, so the cost of the choice is visible. If M6 selects one
   market and M2 selects another, both go in the report.

### One thing the matrix cannot decide

None of M1–M6 answers whether **the join is perceptible in use** — recorded
in `docs/PROJECT_STATE.md` §8 as the largest unknown, and in
`WLOS_MARKET_RESEARCH_II.md` §8 as needing prototype testing rather than
research. A market chosen for a product that does not yet work is a market
chosen for nothing. **This instrument selects a market. It does not validate
a product.**

---

## 6. Regulatory screening per market

C9 is too large for one cell. Every candidate market gets the screen below
completed **before** it is scored on any other column, because a failed screen
can eliminate a market that looks excellent everywhere else — or, worse, can
convert it into a market requiring a second product.

### 6.1 Screen A — minors and the core mechanism

Triggered by the **EU KIDS Act** (published **17 September 2026**), and to be
run against the equivalent statute in every jurisdiction, because the EU is
unlikely to remain alone.

The Act's scope explicitly covers **AI companions and chatbots**, not only
social media. Penalties reach **6% of global turnover**.

| Restriction (for minors) | WLOS mechanism affected |
|---|---|
| **Profiling-based recommender feeds prohibited**; recommenders must prioritise **non-personalised** content | The targeting engine — 10 dimensions, `fn_TargetedItems` |
| **Streaks that penalise a child for not returning daily** prohibited | The streak ring on the home screen, computed by `Behaviour` |
| Engagement-driven reward loops prohibited | `Growth.*`, momentum state dimension |
| **AI companions off by default; banned entirely under 13** | The companion direction in the vision |
| Conversation memory with a minor must be deleted when the conversation ends | Longitudinal memory — the thesis itself |
| Push notifications during sleeping hours prohibited | Quiet hours already exist |

**Per market, record:**

1. Is there a minor-protection statute restricting profiling-based
   recommendation, engagement loops or AI companions?
2. What is the age threshold, and does it differ for AI companions
   specifically?
3. What age-assurance standard applies? **Italy's Garante fined Replika's
   developer €5 million partly for inadequate age verification despite an 18+
   policy — declaring 18+ is not a defence.** Record the *assurance* standard,
   not the stated policy.
4. What is the penalty exposure?
5. **The architectural question:** if minors are in scope here, is a
   non-personalised, streak-free, memory-limited WLOS still WLOS — or is it a
   second product with its own budget?

Note on the launch age: `docs/PROJECT_STATE.md` §8 records it as **unresolved,
with 16+ and 18+ both candidates**. This screen **informs** that decision per
jurisdiction; it does not make it, and nothing in this template should be read
as settling it.

### 6.2 Screen B — device classification, assessed from marketing copy

**The rule, established and load-bearing:** regulators assess intended use
from *"marketing materials, app store descriptions, website copy, social
media, and user instructions."* **Internal documentation does not override
external copy.**

| Regime | Position |
|---|---|
| **FDA** | *General Wellness: Policy for Low Risk Devices*, revised **6 January 2026**. Non-invasive, sensor-based tools may claim general wellness **if they avoid disease, diagnostic or clinical-management claims**. |
| **EU MDR Rule 11** | Most medical device software is **Class IIa or higher** — Notified Body assessment plus a full quality management system. |

The boundary, as the prior research states it concretely:

| Claim | Classification |
|---|---|
| "Your appearance differs from your usual morning baseline" | General wellness |
| "You may be anaemic" / "you appear depressed" | **Medical device** |

**Per market, record:**

1. Which regime governs software as a medical device here?
2. Is there a general-wellness carve-out, and is it narrower than the FDA's?
3. What conformity route applies if the line is crossed — and what does it
   cost in time and money?
4. **Does the local marketing copy, in the local language, stay inside the
   line?** This is the actual risk. Translation and local marketing can cross
   a line the English copy respects, and per the rule above, the copy is the
   evidence. Every translated store listing and campaign is a regulatory
   artefact.

The prior research draws the conclusion that this screen enforces:

> **The constitution is binding on marketing, not just engineering.**

Practical consequence for this instrument: a market cannot be screened by
reading the product. It must be screened by reading **the copy that would ship
there**, which means local marketing copy is a regulatory deliverable, not a
growth deliverable.

### 6.3 Screen C — health data and AI

**Per market, record:**

1. Is health data a special category requiring explicit consent? (EU: GDPR
   Art. 9. Elsewhere: varies.)
2. Are there data residency or localisation requirements?
3. Does an AI-specific regime apply (EU AI Act, or local equivalent), and at
   what risk tier?
4. What are the breach notification obligations and timelines?
5. Are there restrictions on automated decision-making affecting
   individuals?
6. What deletion and portability rights apply, and can they be met against a
   longitudinal memory model?

Note: `Health.ShareGrant` (scoped, expiring, revocable, view-counted) and
`AI.SafetyEvent` (clinical and crisis scores, refusal category, model and
prompt version) already exist in the platform per `docs/PROJECT_STATE.md` §4.
Record whether they are **sufficient** for this market. That is an assessment,
not a work item.

### 6.4 Screen outcome

Each market's screen resolves to exactly one of:

| Outcome | Meaning |
|---|---|
| **CLEAR** | Product as conceived is lawful for the intended age band. Proceed to the other eleven columns. |
| **CONSTRAINED** | Lawful with specific restrictions. **Record the restrictions and their cost**, and treat that cost as part of C7 and C11. |
| **SECOND PRODUCT** | Lawful only as a materially different product. **Not a configuration. Budget it separately or exclude the market.** |
| **BLOCKED** | Not lawful as conceived at any age band. |
| **UNKNOWN** | Screen not completed. **A market with an incomplete screen is not eligible for scoring on any other column.** |

---

## 7. Provenance

Every ESTABLISHED figure in this template is carried forward from research
already completed. Nothing here is newly researched, estimated, inferred or
extrapolated.

| Source document | Contribution |
|---|---|
| `docs/WLOS_MARKET_RESEARCH.md` (23 Sep 2026) | Market size and CAGR, regional share, competitive landscape, retention benchmarks, EU KIDS Act, FDA/MDR classification boundary |
| `docs/WLOS_MARKET_RESEARCH_II.md` (23 Sep 2026) | Smartphone gender gap, CPI benchmarks, AI trust, localisation costs, payment rails, employer/B2B2C signals, the ASO gap |
| `docs/PROJECT_STATE.md` (23 Sep 2026, LOCKED) | Platform capabilities, suspended-work list, decided/hypothesis/unproven status board |

Original external sources are listed in full at the end of both research
documents and are not duplicated here.

### Standing constraints this template operates under

- `docs/PROJECT_STATE.md` §9.0: **`market ranking` and `country selection` are
  suspended.** This template is the instrument for that work, not the work.
- `docs/PROJECT_STATE.md` §9.1: the one next action is **recruit C4**.
- `docs/PROJECT_STATE.md` §10: `Market research — GREEN, sufficient for
  discovery`. More market research is not the bottleneck.
- *"A recommendation in a research document is not authorisation to build."*

---

**This document contains no ranking, no recommendation, and no country.
If a future revision contains any of the three, check first that Phase A item
13 has been reached and that an objective from §5 has been stated in writing.**
