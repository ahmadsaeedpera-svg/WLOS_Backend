# WLOS Release 1 — Detailed Technical Design

**Status:** design for review. **No implementation.** Nothing committed.

**Claim discipline:** *"we cannot read it"* is treated throughout as an
**intended property pending verification**, never as a settled claim. §6.9
verifies it across the full lifecycle and **finds one place where it currently
fails.**

---

## 1. Finding first — the claim does not hold against Slice 1 auth

> **Slice 1 sends the plaintext password to the server.**
> `usp_User_GetForLogin` returns password material; the API computes
> PBKDF2 server-side.

If the same password derives the key that wraps her data key, then **a
compromised or malicious server can derive that key from a live login** and
decrypt everything. Under that design *"we cannot read it"* is false.

**This is not a Release 1 addition. It is an existing behaviour that must
change before any Interiority content is written.**

### Required change

Two independent values derived from one password, on the device, with
different salts and different purposes:

```
  password
     ├── Argon2id(password, salt_auth)  ──► auth_secret  ──► sent to server
     │                                                        (server PBKDF2s
     │                                                         this for storage)
     └── Argon2id(password, salt_kek)   ──► KEK_password  ──► NEVER LEAVES DEVICE
```

The server receives `auth_secret` and stores a hash of it. `auth_secret` is a
**password-equivalent for authentication only** — it cannot derive
`KEK_password`, because the salts differ and Argon2id is one-way.

**Consequence for Slice 1:** the login contract changes, `usp_User_GetForLogin`
keeps working unchanged (it verifies a secret; it does not care that the secret
is derived), and `usp_User_Register` takes a derived secret instead of a
password. The **server-side hashing stays** — defence against a stolen
database — but the plaintext password stops crossing the wire.

---

## 2. Solution structure

### Existing → required

| Existing | Disposition |
|---|---|
| `Maren.Api` | **Retained, renamed** → `Wlos.Host`. Composition root only. |
| `Maren.Application` | **Split.** This is the R1 risk from the architecture review — one assembly holding every handler cannot enforce the Interiority boundary. Dissolved into per-module application folders. |
| `Maren.Domain` | **Split** into each module's internal domain. |
| `Maren.Contracts` | **Retained, split** per module's public contract. |
| `Maren.Persistence` | **Split** per module. |
| `Maren.Infrastructure` | **Retained, narrowed** — crypto verification, tokens, caching. Loses anything module-specific. |
| `Maren.Shared` | **Retained** → `Wlos.Shared`. `Result`, failure codes, **provenance types**. |
| `Maren.Database` | **Retained.** Numbered idempotent scripts, stored procedures (AD5). |
| Onboarding / LifeOs / Today handlers | **Replaced.** Pregnancy-shaped; superseded by Context + Guidance. |
| `Health.*` schema | **Not WLOS's.** Belongs to Maren. Flagged in §12 — removal is a decision, not a default. |
| Content / CMS | **Becomes Catalogue.** Mechanism reused, vocabulary changed. |
| Access, Audit | **Becomes Governance.** |

### Target projects

```
  Wlos.Host                    composition root, controllers, middleware
  Wlos.Shared                  Result · failure codes · Provenance
  Wlos.Contracts               public DTOs

  Wlos.Identity                account · session · erasure orchestration
  Wlos.Catalogue               operator vocabulary   (no user data, ever)
  Wlos.LifeRecord              areas · people · events · goals · habits · memories
  Wlos.Interiority             OPAQUE ENVELOPE STORE — no domain logic
  Wlos.Governance              preferences · boundaries · audit
  Wlos.Context                 stateless assembly
  Wlos.Guidance                stateless, returns sources
  Wlos.Delivery                reminders · scheduling

  Wlos.ArchitectureTests       fitness tests
```

**One project per module, not three.** `Wlos.LifeRecord.Domain/.Application/
.Persistence` would be 24 projects enforcing a boundary nobody is at risk of
crossing. The boundary that matters is *between* modules, so: **the contract
folder is `public`; everything else is `internal`.** Layering lives in folders
inside the module, where it is a readability concern rather than a safety one.

**No `Wlos.Signals` server project exists.** Pattern detection is client-side
(I6). Its absence is the enforcement.

**`Wlos.Interiority` is deliberately anaemic** — it stores and returns opaque
envelopes. It has no domain model, because the server has nothing it could
model. The real Interiority logic lives in the Flutter client.

### Client structure (Flutter)

```
  lib/core/crypto/             key derivation · wrapping · envelope seal/open
  lib/core/sync/               envelope sync engine
  lib/modules/interiority/     journal · state · observation  (plaintext local)
  lib/modules/signals/         pattern detection              (device-only, I6)
  lib/modules/life_record/     areas · people · events · goals · habits
  lib/modules/context/         request assembly for Today
```

---

## 3. Client / server responsibilities

| Capability | Client | Server |
|---|---|---|
| Life Record CRUD | UI, offline cache | **source of truth**, plaintext |
| **Journal / State / Observation** | **plaintext, encryption, all logic** | **ciphertext envelopes only** |
| **Pattern detection** | **all of it** | **nothing** |
| Reflection (counting) | **all of it** | nothing |
| Memory extraction (AI proposal) | **device model** | nothing |
| Memory (confirmed) | UI | source of truth, plaintext |
| Context assembly | request | **assembles from plaintext sources** |
| Guidance | render | generate + sources |
| Server AI | — | over Context only |
| Reminders | local notifications for Interiority-derived | scheduling for Life Record-derived |
| Catalogue | cache | source of truth |

**Note the split in reminders.** A reflection nudge derives from encrypted
Observation, so the server cannot know it is due. **It is scheduled locally.**
A goal reminder derives from plaintext Life Record and can be scheduled
server-side.

---

## 4. Persistence strategy

One SQL Server database (AD4 — erasure completeness). Schema per module.
Stored procedures (AD5).

### The Interiority table — everything the server knows

| Column | Visible to server | Why |
|---|---|---|
| `RecordId` | yes | client-generated UUID; idempotency |
| `UserId` | yes | ownership, erasure |
| `Envelope` | **ciphertext** | the content |
| `Version` | yes | optimistic concurrency |
| `ServerSeq` | yes | pull ordering |
| `ServerReceivedUtc` | yes | when it **synced** |
| `IsDeleted`, `DeletedUtc` | yes | tombstone for other devices |

**Deliberately absent:**

| Not stored | Why |
|---|---|
| **Record type** | Journal vs check-in vs observation is itself informative. **One opaque type.** The device fetches all and filters locally. |
| **Authored timestamp** | Inside the ciphertext. The server learns when she *synced*, not that she wrote at 3am. |
| **References** to Person or Area | Inside the ciphertext. The server must not learn she observes one person often. |
| Size buckets, counts by kind | Not exposed on any read path |

**Residual metadata leakage, stated honestly:** the server knows how many
Interiority records exist, their sizes, and when they synced. Sync frequency
and volume are visible. This is the irreducible minimum for synchronisation to
work at all, and it is the full extent of it.

---

## 5. Encryption and key management

### 5.1 The hierarchy

```
                    ┌──────────────────────────────┐
                    │  DEK  (256-bit, random)      │  encrypts every
                    │  generated ON DEVICE         │  Interiority record
                    └───────────┬──────────────────┘
                                │  wrapped by each of:
         ┌──────────────────────┼──────────────────────┐
         │                      │                      │
  KEK_password           KEK_recovery            KEK_device
  Argon2id(pw,           Argon2id(recovery       platform keystore
  salt_kek)              key, salt_rec)          (convenience unlock)

  server stores:  wrapped_DEK ×3  ·  salts  ·  KDF params
  server never has:  DEK  ·  any KEK  ·  the password  ·  the recovery key
```

**Per-record encryption:** AES-256-GCM, fresh 96-bit nonce per record, record
id + version as associated data (binds ciphertext to its identity, so a record
cannot be substituted for another).

**Why one DEK rather than per-record keys:** device enrolment would otherwise
require transferring thousands of keys. One DEK, rotatable, is the standard
shape and keeps enrolment to a single unwrap.

### 5.2 Lifecycle

| Event | What happens | Server sees |
|---|---|---|
| **Account creation** | Device generates DEK + recovery key. Derives `KEK_password`, `KEK_recovery`. Wraps DEK twice. Uploads wrapped blobs + salts. | wrapped blobs, salts |
| **First device** | Already holds the DEK | — |
| **Second device** | Sign in → derive `KEK_password` from password → fetch `wrapped_DEK_password` → unwrap → has DEK | an authenticated fetch |
| **Password change** | Derive new `KEK_password` → re-wrap DEK → upload. **Content is never re-encrypted.** Also rotates `auth_secret`. | a new wrapped blob |
| **Password reset, recovery key held** | Unwrap DEK via `KEK_recovery` → set new password → re-wrap | new wrapped blob |
| **Password reset, no recovery key** | Auth resets. **DEK is unrecoverable.** She keeps Life Record; Interiority is cryptographically gone (I9). | nothing new |
| **Recovery key regenerated** | New recovery key → re-wrap DEK → **old wrapped blob deleted** | replaced blob |
| **Device loss** | Nothing to revoke server-side — that device holds the DEK. **The only real remedy is rotation.** | — |
| **Key rotation** | New DEK → device re-encrypts all Interiority → re-wraps → uploads. Expensive, user-initiated, offered after a suspected compromise. | new ciphertext + blobs |
| **Deletion** | Rows + wrapped blobs deleted; local store wiped. Both required. | deletion |
| **Export** | Device decrypts, writes file. **The server cannot produce an Interiority export.** | nothing |

### 5.3 What the server can see — completely

`auth_secret` hash · wrapped DEK blobs · salts and KDF parameters ·
ciphertext envelopes · record ids, versions, sync sequence and sync times ·
plaintext Life Record, Catalogue, Governance, Delivery.

**Nothing in that list yields plaintext Interiority.**

### 5.4 Device revocation — honest limits

**We cannot revoke a key a device already holds.** Signing a device out ends
its session; it does not remove the DEK from its storage. The truthful
position:

> *"Signing out a device stops it reaching your account. If you believe a
> device is in someone else's hands, change your key — that re-encrypts
> everything and the old device's copy stops working."*

Rotation is the remedy. It must exist before we make any claim about device
security.

---

## 6. Synchronisation

### 6.1 Semantics

| Operation | Behaviour |
|---|---|
| **Create** | Device generates UUID, seals envelope, POSTs. Server assigns `ServerSeq`. |
| **Update** | Re-seal, PUT with expected `Version`. Mismatch → 409 with the server's envelope returned. |
| **Delete** | Tombstone. Retained until all known devices have pulled past it, then purged. |
| **Offline** | Local write-ahead queue, ordered. Writes never block on connectivity. |
| **Reconnect** | Pull `since=lastServerSeq`, then push the queue. Pull before push, so conflicts surface before they are overwritten. |
| **Duplicate delivery** | Idempotent on `(RecordId, Version)`. A replayed PUT is a no-op. |
| **Ordering** | Per-record `Version` for correctness; global `ServerSeq` for pull paging. |
| **Device replacement** | Enrol → unwrap DEK → pull from `ServerSeq = 0` → decrypt locally. |

### 6.2 Conflict — the rule that matters

**The server cannot merge ciphertext**, and it must not try.

```
  409  ──►  device holds both versions  ──►  resolved ON DEVICE
```

**For journal entries, resolution is never a merge and never a
last-writer-wins.** Both versions are kept as separate entries, marked as
having come from a conflict.

> Silently discarding a version of something she wrote is the worst failure
> this system could have. Two entries is an inconvenience; a lost paragraph is
> a broken promise.

For State, last-writer-wins is acceptable — a check-in is a point observation
and the later one is the one she meant.

### 6.3 The invariant

**No sync operation requires the server to decrypt anything.** Conflict
detection uses `Version`. Ordering uses `ServerSeq`. Tombstones use ids.
Nothing reads an envelope.

---

## 7. AI boundary

```
                    PRIVATE INTERIORITY
              journal · state · observation
                   (client-encrypted)
                            │
            ┌───────────────┴───────────────┐
            │                               │
     DEVICE-ONLY                   ConfirmMemoryFromEntry
     ├── pattern detection                  │  she confirms
     ├── reflection (counting)              │  ONE FACT
     ├── memory-extraction proposal         ▼
     └── local reminders            ┌──────────────────┐
                                    │ LIFE RECORD      │ plaintext
                                    │ (permitted)      │ provenance:
                                    └────────┬─────────┘ confirmed
                                             │
                          Life Record · Governance · Catalogue
                                             │
                                             ▼
                                       CONTEXT ASSEMBLY
                                       (server, plaintext,
                                        boundary-vetoed)
                                             │
                                             ▼
                                        SERVER AI
                                    (reads Context only)
```

**The server never receives Journal, State or Observation plaintext.** It is
not a rule the server obeys — it has no key.

**One thing the UI must make explicit.** `ConfirmMemoryFromEntry` **moves a
fact out of the encrypted zone** into plaintext Life Record. That is by design
and she chose it, but she must understand she is doing it:

> *"Remembering this saves it to your life record, outside your private
> journal."*

---

## 8. Context, Guidance, Delivery

**Context** — a stateless server service. Boundary veto **before** gathering
(AD11). Returns `(values, sources[])`. Request-scoped only; no cache that
outlives a request (P2).

**Guidance** — stateless. Returns `(content, sources[])`. "Why am I seeing
this?" is a projection of `sources`, **never a generated explanation.**

**Delivery** — receives a **rendered string plus a route**. It has no type that
could carry a record. Two schedulers:

| Source | Scheduled | Why |
|---|---|---|
| Life Record (goal, event, habit) | server | plaintext, server knows when |
| Interiority (reflection nudge) | **device, local notification** | the server cannot know it is due |

---

## 9. Export, deletion, governance

**Export** — one archive, assembled on device. Life Record and Governance
pulled from the server; Interiority decrypted locally. **Journal exports as she
wrote it, never summarised.** Provenance is included, so she can see what she
said versus what WLOS derived.

**Deletion** — Identity orchestrates; every module erases what it declared in
the `ErasureRegistry`; the conformance sweep scans **every** store for the
identifier and fails the build on anything undeclared. Local store wiped
independently. Both are required for the promise to hold.

**Governance / audit** — records *that* an Interiority record changed, never
what it said. Audit rows carry ids and types only.

---

## 10. Architecture fitness tests

Build-failing, not advisory.

| Test | Asserts |
|---|---|
| **Module references** | `Context`, `Guidance`, `Delivery` have **no reference** to `Interiority`. `Catalogue` has no reference to any user-data module. |
| **No server Signals** | No server project exposes pattern detection |
| **Interiority surface** | Its public contract exposes **envelopes only** — no type carrying decrypted content exists server-side |
| **Infrastructure backdoor (I8)** | No logger, serialiser, telemetry, event or queue signature accepts an Interiority content type. Client-side, enforced on the Flutter equivalents. |
| **Provenance required** | No fact-store write path has an overload omitting provenance |
| **`observed` rejected** | Life Record write contracts accept `stated`/`confirmed`/`imported` only |
| **Erasure registry complete** | Post-erasure sweep finds nothing undeclared |
| **Guidance carries sources** | No constructor produces content without sources |
| **No plaintext password** | No client path sends a raw password; no server path accepts one |

---

## 11. Failure and degradation

| Failure | Behaviour |
|---|---|
| Server AI down | Deterministic guidance, plainer language. **Nothing invented.** |
| Device AI absent | Manual memory extraction. Reflection unaffected — it is counting (I7). |
| Context assembly fails | Her raw records render. Never a guess, never a fake-empty screen. |
| Sync fails | Local writes succeed and queue. **Never a write failure.** |
| DEK unavailable (locked) | Interiority surfaces show a locked state. Life Record works normally. |
| Catalogue unavailable | Last known catalogue. |
| Signals unavailable | No reflection question. Nothing else affected. |

**Degrade to less, never to plausible.**

---

## 12. Migration from Slice 1

| Action | Items |
|---|---|
| **Retained** | Identity (with §1 change) · stored-procedure discipline · erasure cascade · audit · Catalogue mechanism (from Content) · numbered scripts · the 18+ gate |
| **Moved** | `Maren.Application` handlers → per-module application folders · persistence → per-module |
| **Split** | Contracts, Domain, Persistence → per module |
| **Replaced** | Login/registration contract (§1) · Onboarding/LifeOs/Today handlers → Context + Guidance |
| **Deleted** | *(decision required)* `Health.*` schema — pregnancy-shaped, belongs to Maren, unused in WLOS. **Flagged, not assumed.** |
| **Protected by tests** | Everything in §10 |

**Sequencing:** §1 first — the auth change must land **before any Interiority
content exists**, because retrofitting it would require every user to
re-encrypt.

---

## 13. Five-life and zero-connection — reconfirmed

No life needs a module, a table or a code path of its own; the difference is
Catalogue rows and her content. The full loop — capture, remember, understand,
reflect, plan, act, learn, improve — closes with **no connection module
present in the solution at all.**

---

## 14. Implementation readiness

> ## **BLOCKED — on four questions.**

Everything else is ready. The blockers are small in number and genuinely
blocking, not deferrable detail.

| | Blocking question | Why it blocks |
|---|---|---|
| **B1** | **Confirm the §1 auth change.** The client must derive `auth_secret`; the server must stop accepting plaintext passwords. | It changes a shipped, tested Slice 1 contract, and it must land before any Interiority content exists. **Until it lands, the privacy claim is not true.** |
| **B2** | **Argon2id parameters and the recovery-key format.** Memory/iterations/parallelism must work on a low-end Android device *and* resist offline attack on a stolen backup. | Determines brute-force resistance of every wrapped DEK. Cannot be changed later without re-wrapping for every user. |
| **B3** | **Does password reset without a recovery key proceed at all?** She regains her account and Life Record; her journal is gone. | Either answer is defensible. It is a product decision about the worst day a user will have, and it shapes the whole recovery UX. |
| **B4** | **`Health.*` schema — drop from WLOS?** | Affects the migration plan and the erasure registry. |

**Not blocking, decide during build:** offline write model per module · Context
latency budget · tombstone retention window · on-device model selection.

**What is ready the moment B1–B4 are answered:** project restructure, module
boundaries, fitness tests, Interiority envelope store, sync engine, key
management, Context and Guidance, Delivery, export and deletion.

---

## 15. Claim status

> **"We cannot read your journal."**

**Not yet true.** It becomes true when **B1 ships**. Verified across the
lifecycle in §5.2 and §5.3 with that one exception, which is why it is the
first blocker rather than a footnote.

**Recommendation: do not publish the claim in any form — store listing, privacy
policy, onboarding copy — until B1 is implemented and its fitness test passes.**

**Stopping here. No implementation.**
