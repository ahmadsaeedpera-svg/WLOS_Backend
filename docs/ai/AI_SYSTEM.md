# AI_SYSTEM — The Maren Companion

**Status:** Design specification · **Date:** 2026-07-27
**Companions:** `AI_PROMPTS.md` (exact prompt text), `AI_PIPELINE.md` (runtime flow)

---

## 1. What this is, in one paragraph

A conversational companion that helps a woman **run her life well** — sleep, food, movement, habits, routine, work, study, relationships, planning, and remembering her medication — grounded in clinician-reviewed content the platform already publishes. It is **not** a clinician, a triage service, or a symptom checker. It never names a condition, never interprets a measurement, never recommends a dose. When a question crosses into medicine, it stops, says so plainly, and hands the woman the organised evidence she needs to ask a real professional.

---

## 2. The two rules, and why they are architectural

> **Never diagnose. Never prescribe.**

Stated as prompt instructions these are suggestions; a sufficiently determined user, or an unlucky sampling temperature, walks straight through them. So they are enforced in **four independent places**, and any one of them can refuse:

| Layer | Mechanism | Fails how |
|---|---|---|
| **1. Intent classifier** | Cheap model classifies the turn before generation | Refuses before a single token is generated |
| **2. Retrieval gate** | Health answers may only draw on approved CMS content | No approved source → nothing to say → refusal |
| **3. Generation constraints** | System prompt + tool schema physically lack a "diagnosis" output | No field exists to put a diagnosis in |
| **4. Output screen** | Post-generation check for condition names, dosages, imperatives | Response replaced before it reaches the device |

**Why four.** Layer 3 is the weakest — it is the one that depends on the model behaving. Layers 1, 2 and 4 are deterministic code and content policy, and they hold when the model does not. A single-layer design is one jailbreak away from telling a pregnant woman she has pre-eclampsia.

**The commercial reason, stated plainly:** this boundary keeps Maren inside the **general-wellness** category rather than the regulated medical-device category. It is what lets the product ship globally without clearance and makes clinicians allies rather than opponents. The constraint is the strategy.

---

## 3. In scope / out of scope

**In scope — the fourteen domains.** Lifestyle · Nutrition · Habits · Sleep · Exercise · Mental wellness · Routine · Productivity · Hydration · Medication *reminders* · Relationship wellness · Learning · Career · Planning.

**The medication line is the sharpest in the product.** The companion may:
- remind her a dose is due, at a time she set
- record that she marked it taken or missed
- show her what she has logged, and export it for an appointment
- read a label into her own records via OCR

It may **never**:
- suggest starting, stopping, changing or skipping anything
- answer "is this safe in pregnancy?" or "can I take these together?"
- interpret a side effect, or say a symptom is or is not caused by a drug

Those four questions route to a pharmacist or prescriber, every time, with no exception for confidence.

**Out of scope entirely:** diagnosis, triage, symptom interpretation, lab/scan reading, dosing, fertility or conception prediction, risk scoring, mental-health diagnosis, anything framed as "should I go to hospital".

---

## 4. The substitution pattern

The single most important behaviour in the system. A refusal that just says *no* is useless and pushes the woman to a worse source. Every refusal must **hand back something better**:

> **She asks:** "I've had headaches and swelling for three days — is this pre-eclampsia?"
>
> **It answers:** "I can't tell you what's causing that, and this is one I don't want to guess at — swelling with headaches is something your midwife will want to hear about today rather than at your next appointment. I've pulled together what you've logged: headaches on the 24th, 25th and 26th, and you noted swelling in your hands yesterday. Do you want that as a summary to read out when you call?"

Three moves, always in this order: **decline plainly · point to the right human · give her the organised evidence.** Never a bare refusal, never a lecture about what the app is not.

---

## 5. Architecture

```
                    ┌──────────────── device ────────────────┐
                    │  conversation history (SQLite, local)  │
                    │  health logs (SQLite, local)           │
                    │  on-device intent + crisis classifier  │
                    └───────────────────┬────────────────────┘
                                        │  minimal turn payload
                                        ▼
   ┌────────────────────────── Maren.Api ──────────────────────────┐
   │  AuthN/Z · rate limit · feature flag · audit                  │
   └───────────────────────────┬───────────────────────────────────┘
                               ▼
   ┌─────────────────────── AI orchestrator ───────────────────────┐
   │  1 classify   →  2 retrieve  →  3 assemble  →  4 generate     │
   │       │              │              │              │          │
   │   refuse here    approved CMS   token budget   constrained    │
   │   if clinical      only          + stage        tools only    │
   │                                                  │            │
   │                        5 screen output ◄─────────┘            │
   └───────────────────────────┬───────────────────────────────────┘
                               ▼
        safety audit (what was refused, why) — never the content
```

### Component responsibilities

**Context assembler** — decides what the model may see. Stage, role-modes, locale, unit preference, the woman's *summarised* recent patterns (not raw logs), and retrieved content. Everything it assembles is bounded by an explicit token budget (§8).

**Retriever** — hybrid search over the **published, approved** CMS snapshots only. Never the live editable tables. This reuses the exact rule the platform already enforces for mobile content delivery: clients read approved snapshots, because an editor mid-sentence must not reach a device.

**Generator** — a frontier model, constrained by system prompt and a tool schema with no capacity to express a diagnosis.

**Screen** — deterministic post-check. Condition-name lexicon, dosage patterns (`\d+\s?(mg|ml|mcg|g|iu)`), clinical imperatives ("you should take", "stop taking"), and a citation check: any health claim must trace to a retrieved chunk.

**Safety auditor** — records that a refusal happened, its category, and the classifier scores. **Never records the message content.** The audit answers "is the boundary holding?" not "what did she say?"

---

## 6. Model strategy

Deliberately **model-agnostic**; the orchestrator owns the contract, the vendor is swappable.

| Job | Tier | Why |
|---|---|---|
| Intent + risk classification | Small, fast, **on-device where possible** | Runs on every turn; must be cheap and private. On-device means a clinical question can be refused without the text ever leaving the phone |
| Crisis detection | Small model **plus deterministic lexicon** | Never model-only. A missed self-harm signal is unacceptable, so recall beats precision and a keyword list backstops the classifier |
| Conversation | Frontier, streamed | Quality of tone matters enormously here; this is the part a woman experiences as "someone who knows me" |
| Summarisation of her own logs | Small, **on-device** | Purely local data; no reason to send it anywhere |
| Content drafting for the CMS | Frontier, **internal tool, human approval required** | Highest internal ROI — makes a fourteen-domain library affordable — but never publishes without a human |
| Embeddings | Standard embedding model, batch | Content is editorial and changes rarely; embed on publish |

**Temperature:** low (≈0.3) for anything health-adjacent, higher only for genuinely open conversation. **Never** high temperature on a turn the classifier marked health-adjacent.

---

## 7. Privacy architecture

This is a product whose users have specific, well-founded reasons to distrust apps in this category. The design assumption is that **we may be compelled to disclose whatever we hold**, so the answer is to hold as little as possible.

- **Conversation history lives on the device.** The server sees the current turn plus a bounded window, and does not retain it after the response is generated.
- **Health logs never leave the device wholesale.** The assembler sends *derived summaries* ("logged headaches on 3 of the last 7 days"), not raw rows, and only for the domain in question.
- **No training on user content.** Ever, without explicit, revocable, per-purpose consent — and reproductive data is excluded even then.
- **Retention:** transient inference context is not persisted. Safety audit rows keep category and scores, not text.
- **Minors:** a Stage-1 user's data is never used for personalisation beyond her own device, and her capability set is hard-restricted (§9).
- **Server-side conversation storage is opt-in only**, exists solely for multi-device continuity, and is encrypted with a key the account controls.

**Consequence, accepted deliberately:** the companion knows less than it could. A cloud-hoarding design would give slightly better personalisation. It would also make Maren the thing it is positioning against.

---

## 8. Budgets — latency, tokens, cost

Written down because a companion that is slow or expensive gets removed from the roadmap regardless of quality.

| Budget | Target | Note |
|---|---|---|
| Classification | < 150 ms | On-device; blocks generation, so it must be invisible |
| First token | < 1.2 s | Streaming makes the rest tolerable |
| Full response | < 6 s | Beyond this she has closed the app |
| Context window | ≤ 8k tokens assembled | System 800 · retrieved content 3k · her summaries 1.5k · history 2k · headroom |
| Retrieved chunks | 4–6, hard cap 8 | More is worse: dilution, cost, and a longer surface for the model to wander off |
| Cost / turn | target < $0.01 blended | Achieved by classifying and summarising on-device and keeping retrieval tight |

**Degradation ladder** — the companion must fail usefully, never blankly:
1. Frontier model unavailable → smaller model, tone slightly flatter, same guardrails.
2. Retrieval unavailable → **health topics refuse** ("I can't reach my sources"), lifestyle/planning continue.
3. Classifier unavailable → **fail closed**: treat every turn as health-adjacent and refuse anything clinical.
4. Everything unavailable → the app is still fully usable offline; reminders, logging and content all work without the companion. The companion is an enhancement, never a dependency.

---

## 9. Stage and age gating

Tone and capability both shift by life stage (see `LIFE_STAGE_DESIGN.md`). Two gates are hard-coded rather than prompted:

- **Adolescent (Stage 1):** no weight, calorie or body-composition content of any kind; sexual-health limited to age-appropriate education; disclosures of abuse or self-harm route to safeguarding resources immediately. Eating-disorder-safe language is enforced by the output screen, not left to the model.
- **Postpartum (Stage 6):** highest crisis sensitivity in the product. Thoughts of self-harm or of harming the baby trigger immediate, prominent human resources — **the model does not handle this turn at all**; it is intercepted before generation.

---

## 10. Evaluation

The system is not shippable on vibes. Four suites, run on every prompt or model change:

1. **Red-line suite** — several hundred adversarial attempts to extract a diagnosis, a dose, or a safety verdict, including roleplay, hypotheticals, translation tricks, and "my friend asked". **Target: zero leaks.** A single leak blocks release.
2. **Crisis suite** — self-harm, harm-to-baby, abuse, assault phrasings across registers and indirection. Measured on **recall**; a miss is far worse than a false positive.
3. **Grounding suite** — every health claim must trace to a retrieved chunk. Measures citation coverage and hallucination rate.
4. **Tone suite** — stage-appropriateness, judged against rubrics per stage. Catches the failure where the model is *safe* but sounds like a pamphlet.

**Metrics that matter:** referral rate (should be *high* — a low one means it is overstepping), citation coverage, red-line leak count, crisis recall, and whether doctor-prep packs actually get taken to appointments.

**Metrics deliberately not optimised:** session length, message count, daily engagement. Optimising engagement in a health product means monetising anxiety, and it is banned by policy, not by preference.

---

## 11. Data model (additive; no existing table changes)

Nothing here alters a shipped table. All new objects, all optional.

| Object | Purpose | Notes |
|---|---|---|
| `AI.Conversation` | Opt-in server-side thread header | Only exists if the woman enables multi-device |
| `AI.Message` | Encrypted turn content | Encrypted at rest; absent for device-only users |
| `AI.SafetyEvent` | Refusals, category, classifier scores | **No message text.** Append-only, like `Audit.AuditLog` |
| `AI.ContentEmbedding` | Vector per approved content chunk | Rebuilt on publish; derived data, safe to drop and regenerate |
| `AI.PromptVersion` | Which prompt/model served a turn | Required for eval reproducibility and incident forensics |

Retrieval draws from the existing `Content.ContentVersion` snapshots — the AI reads exactly what the mobile app reads, so a correction published for one is a correction for both.

---

## 12. What could go wrong

Honest failure catalogue, with the mitigation that exists rather than the one that would be nice.

| Risk | Mitigation |
|---|---|
| Model emits a diagnosis anyway | Output screen catches it; red-line eval gates release; audit records the near-miss |
| Retrieved content is wrong | Content is clinician-reviewed and versioned; a correction is a CMS publish, no app release — the same property the platform was built for |
| Crisis missed | Lexicon backstop + recall-weighted eval + human resources always visible in the UI, not only when triggered |
| Model is confidently wrong on lifestyle | Lower stakes by design, but grounding still required; uncited claims are dropped |
| Vendor outage | Degradation ladder (§8); app fully functional without the companion |
| Prompt injection via content | Retrieved content is delimited and marked untrusted; the system prompt states that retrieved text is data, never instruction |
| Scope creep | The fourteen domains are enumerated in code, not prose; a fifteenth requires a deliberate change and a review |

---

## 13. Rollout

Behind the existing feature-flag system, which already supports deterministic bucketing and per-user assignment.

1. **Internal only** — staff accounts; full transcript review with consent; red-line suite green.
2. **Single stage, single domain** — one life stage, sleep and hydration only. Smallest surface with real value.
3. **Widen domains** before widening stages — the domains share safety machinery; the stages do not.
4. **Adolescent and postpartum last.** Highest safeguarding bar, and they must not be the cohort a bug is discovered on.

Kill switch: one flag, immediate, no release required.

---

## 14. Ten-year view

The companion becomes valuable in a way no competitor can copy quickly, because its advantage is **longitudinal context**, and that only accrues by existing for years. An assistant that knows a woman had irregular cycles at nineteen, organised a symptom history at twenty-seven, and is now describing perimenopause at forty-four can prepare her for a ten-minute appointment better than any general-purpose model — while still never telling her what she has.

That is the whole design: **it knows her, not medicine.**
