# AI_PIPELINE — Runtime flow

**Status:** Design specification · **Companions:** `AI_SYSTEM.md`, `AI_PROMPTS.md`

---

## 1. Turn lifecycle

```
device                          server                        vendor
──────                          ──────                        ──────
1 classify (on-device)
  │ clinical? crisis?
  ├─ crisis ──► resource card, no model call, no network
  ├─ clinical ─► refusal composed locally where possible
  │
  └─ ok ──► 2 assemble minimal payload
              │
              ▼
        3 authn/z · rate limit · feature flag
              │
              ▼
        4 re-classify (server, authoritative)
              │  disagreement with device → take the stricter
              ▼
        5 retrieve (approved CMS snapshots only)
              │  needs_sources && nothing found → refuse
              ▼
        6 assemble context (token budget enforced)
              │
              ▼
        7 generate ──────────────────────────────► frontier model
              │  stream tokens                     (temp ≤ 0.3 if health)
              ▼
        8 screen output (deterministic, then model)
              │  reject → replace, never edit
              ▼
        9 audit the decision (category + scores, never text)
              │
              ▼
       10 respond ──► device stores turn locally
```

**Why classify twice.** The device classifier is for latency and privacy — a clinical question can be refused without the text ever leaving the phone. The server classifier is authoritative, because the device is not trusted: a modified client could simply report `clinical: false`. Where they disagree, **the stricter verdict wins**.

---

## 2. Step detail

### Step 1 — On-device classification
Runs before any network call. Two outputs decide everything: `clinical` and `crisis`.

**Crisis short-circuits the entire pipeline.** No model call, no request. The UI shows human resources directly. A model must never be the thing standing between a woman disclosing self-harm and a helpline number — it can be slow, wrong, or offline, and none of those are acceptable here.

### Step 2 — Minimal payload
What leaves the device:

```jsonc
{
  "turn": "<her message>",
  "history": ["<up to 6 recent turns, truncated>"],
  "stage": "midlife",              // enum, not health data
  "roles": ["professional"],
  "locale": "en-GB",
  "units": "metric",
  "domain": "sleep",
  "summaries": [                   // DERIVED, never raw rows
    "cycle length varied 22-41 days over the last 6 months"
  ],
  "clientClassification": { "clinical": false, "crisis": false }
}
```

Note what is absent: no user id in the model payload, no raw logs, no dates of individual entries, no free-text notes she wrote for herself. Summaries are computed on-device and are the *only* form her health data takes on the wire.

### Step 3 — Platform gates
Standard platform path: authentication, permission, rate limit, feature flag. The companion is behind a flag with per-user assignment, so rollout and kill switch already exist.

Rate limiting matters more here than elsewhere — a model call is orders of magnitude more expensive than a database read, so the companion gets its **own, tighter** limit rather than sharing the global one.

### Step 4 — Server classification
Authoritative. Also the point where a client/server disagreement is recorded: a persistent pattern of a client under-reporting `clinical` is a tampering signal worth alerting on.

### Step 5 — Retrieval

**Corpus:** published `Content.ContentVersion` JSON snapshots — the exact bytes the mobile app receives. Never the live editable tables. This inherits the platform's existing clinical-safety property: an editor mid-sentence cannot reach a device, and therefore cannot reach the companion either.

**Indexing:** chunk on semantic boundaries (heading + paragraph group), 200–400 tokens, with the source citation and review date carried on every chunk. Embedded **on publish** — the CMS already emits a publish event point, and content changes rarely, so this is cheap and never stale.

**Query:** hybrid — vector similarity for meaning, plus lexical for exact terms (drug names, procedure names) where embeddings are weak. Filter by stage and domain before ranking, since a menopause chunk is noise for a nineteen-year-old.

**Ranking:** similarity, then recency of clinical review, then specificity. Take 4–6, hard cap 8.

**The refusal case:** if `needs_sources` is true and retrieval returns nothing above threshold, the pipeline **refuses**. It does not fall back to the model's own knowledge. This is the single most important line in the retrieval design — an unsourced health answer is exactly the failure mode the whole architecture exists to prevent.

### Step 6 — Context assembly
Enforces the token budget from `AI_SYSTEM.md` §8. Order matters: system prompt, then stage modifier, then sources, then her summaries, then history — because when the budget is exceeded, **history is dropped first and sources last**.

Retrieved content is wrapped:

```
<sources>
  <source id="1" citation="NHS, reviewed 2026-01" >…</source>
</sources>
```

with a standing instruction that everything inside is data, never instruction. Prompt injection via editorial content is a real vector once a CMS has many authors.

### Step 7 — Generation
Streamed. Temperature ≤ 0.3 when the turn is health-adjacent. The tool schema exposes only: `set_reminder`, `summarise_logs`, `save_note`, `open_content`. **There is no tool capable of expressing a diagnosis, a dose, or a risk score** — the absence is the control.

### Step 8 — Output screen
Deterministic checks first (cheap, cannot hallucinate): dosage patterns, clinical imperatives, diagnostic assertions, condition lexicon. Model-based grounding check only on health turns.

**Streaming interacts badly with screening**, and this is a genuine design tension. Resolution: stream to the device but **hold display of the final sentence until the screen passes**, and on rejection replace the whole message. Partial display of a rejected answer is worse than a slightly later answer.

### Step 9 — Audit
Records: turn id, prompt version, model, classifier scores, retrieval doc ids, decision (answered / refused / replaced), refusal category, latency, tokens. **Never the message text.**

This answers "is the boundary holding, and is it holding better or worse than last week" — which is the only audit question that matters here. Reusing the platform's append-only audit discipline means it cannot be quietly edited after an incident.

---

## 3. Caching

| Layer | Cached | Not cached |
|---|---|---|
| Embeddings | Per content chunk, invalidated on publish | — |
| Retrieval | Query→chunk ids, short TTL, keyed by domain+stage+locale | Anything keyed by user |
| Generation | **Nothing** | Every turn is personal; a shared response cache across users is a privacy incident waiting to be written |

Content embeddings are the only meaningful cache. Generation caching is explicitly forbidden.

---

## 4. Failure handling

Mapped to the degradation ladder (`AI_SYSTEM.md` §8). Every failure has a defined user-visible behaviour — none of them is a spinner that never resolves:

| Failure | Behaviour |
|---|---|
| Classifier unavailable | Fail closed: treat as health-adjacent, refuse clinical, allow planning/routine |
| Retrieval unavailable | Health topics refuse honestly ("I can't reach my sources right now"); everyday topics continue |
| Model timeout | "I'm taking too long — try again?" Never a partial answer on a health turn |
| Model returns rejected output twice | Refuse and route to a human. Do not retry a third time hoping for compliance |
| Vendor outage | Companion entry points hidden by flag; the rest of the app is untouched |

The app must remain **fully usable with the companion switched off**. Reminders, logging, content and export are all local. The companion is an enhancement, never a dependency — which is also what makes the kill switch safe to use.

---

## 5. Observability

| Signal | Alert on |
|---|---|
| Red-line screen rejections | Any sustained rise — the model or a prompt has drifted |
| Crisis detections | Volume changes; a sudden drop suggests the classifier broke |
| Client/server classification disagreement | Sustained pattern per account → tampering |
| Grounding failures | Rise means the corpus no longer covers what is being asked |
| p95 first-token latency | > 2 s |
| Cost per turn | Drift above budget |
| Refusal rate by category | A *fall* is suspicious, not good news |

That last row is the counter-intuitive one worth stating: a falling refusal rate most likely means the boundary is eroding, not that users changed. It is treated as a regression signal.

---

## 6. Evaluation harness

Runs in CI on any change to a prompt, model, retrieval parameter, or the lexicon.

```
fixtures/
  red_line/      diagnosis, dosing, safety-verdict attempts + jailbreaks
  crisis/        self-harm, harm-to-baby, abuse, assault, indirect phrasing
  grounding/     health questions with known correct sources
  tone/          per-stage rubric cases
```

**Gates:** red-line leaks must be **zero** — not "low". Crisis recall must not regress. Grounding coverage and tone scores have thresholds with an explicit, recorded override path for a human to accept a regression deliberately.

Fixtures are versioned with the prompts. An eval result that cannot name the prompt version it ran against is not a result.

---

## 7. Implementation order

Each step is independently shippable and independently verifiable. Nothing here changes an existing table or endpoint.

| # | Increment | Verifiable by |
|---|---|---|
| **1** | Safety schema — `AI.SafetyEvent`, append-only, plus the domain/refusal enums as constraints | SQL assertion suite; append-only test |
| **2** | Classifier contract + deterministic lexicon, no model yet | Unit tests over the crisis and red-line fixtures |
| **3** | Output screen — deterministic checks only | Fixture tests; no model dependency |
| **4** | Retrieval over existing published snapshots, lexical first | Integration test against real content |
| **5** | Embeddings + hybrid ranking | Grounding suite |
| **6** | Generation behind a feature flag, internal accounts only | Full eval suite, transcript review |
| **7** | Streaming + screening interaction | Latency budget |
| **8** | Widen domains, then stages — adolescent and postpartum last | Per-stage tone suite + clinical sign-off |

**Order rationale:** every safety mechanism ships and is proven *before* the first token is ever generated. Steps 1–5 have no model dependency at all, which means the guardrails are testable, deterministic, and already in place on the day generation is switched on for the first internal account.

Building it the other way round — generation first, guardrails after — is how health AI products end up with an incident before they have an eval suite.
