# WLOS Privacy Architecture — Decision Paper (O3 · O1 · O4)

**Status:** decision paper for review. **No code, no schema, no migrations, no
API, no SDK integration, no infrastructure.** Nothing committed.

**Resolves:** where AI executes · where journal data lives · whether journal
synchronises. Plus the infrastructure-backdoor test on the Interiority
boundary.

---

## 0. The reframing that changes O3

Before comparing options, one observation from the approved architecture that
alters the question.

**Under AD9/B1, AI reads Context and nothing else. Journal is explicitly not an
input to Context.** So in ordinary operation, AI already never sees journal
text.

Journal text meets a model in exactly **two** places:

| | Where | Needs a model? |
|---|---|---|
| 1 | **Memory extraction** — WLOS proposes a fact from an entry | Yes |
| 2 | **Reflection** — *"you've written three times this month…"* | **No.** It is a **count over structured Observation fields.** Arithmetic, not inference. |

**So O3 is not one question.** It is:

> **O3a** — where does guidance AI run, over Context that contains no journal?
> **O3b** — where does the one journal-touching operation run?

Answering them separately produces a far stronger position than answering
"on-device or server" as a single choice.

---

## 1. O3 — Where does AI execute?

### Options

| | Option | Capability | Journal leaves device? | Works on all devices? |
|---|---|---|---|---|
| **A** | On-device only | Small models (~2–4B), short context | **No** | **No** — mid/low-range Android lacks on-device GenAI |
| **B** | Server-side only | Full capability, instantly updatable | **Yes, for O3b** | Yes |
| **C** | **Hybrid, split by data class** | Full for Context; small for journal | **No** | Yes for O3a; **O3b degrades honestly** |

**C is not a compromise between A and B.** The split is drawn by *what data the
operation touches*, not by *how much capability we want*.

### Recommendation — **C, with a hard rule**

> **Any operation that touches journal text runs on device. If the device
> cannot, the feature is absent — never relocated to the server.**
>
> **Any operation over Context runs server-side**, because Context is already
> boundary-filtered and contains no private interiority.

| | |
|---|---|
| **Benefits** | Full model capability where it is safe · a promise that is absolute rather than hedged · server-side guidance stays updatable without app releases |
| **Costs** | Memory-extraction proposals unavailable on devices without on-device GenAI · two inference paths to build and test · on-device model size in the APK or downloaded |
| **Privacy** | **Journal text never reaches a server, in any mode, for any reason.** Not "encrypted in transit" — never sent. |
| **Product** | Manual extraction is the universal fallback: she selects text → *"remember this"*. **The AI proposal is a convenience, never the only route.** A woman on a £90 phone loses a suggestion, not the capability. |
| **Architectural** | Guidance module calls a server inference port. Memory-extraction calls a **device-only** port with no server implementation — so there is no server code path to misconfigure. |
| **Deletion** | Nothing to erase server-side: no prompt logs, no embeddings, no cache of her words. |
| **Failure** | Server AI down → plainer deterministic guidance (P7). Device AI absent → manual extraction. **Neither failure moves data.** |
| **Future** | On-device capability is improving. The rule needs no revision as models improve — more becomes possible on-device without the boundary moving. |

### The product promise this creates

> **"What you write in your journal never leaves your phone. Not to us, not to
> our AI, not to anyone."**

Checkable, absolute, and unusual. Most competitors cannot say it.

---

## 2. O1 — Where does journal data live?

### Options

| | Option | Operator can read? | Erasure | Backups |
|---|---|---|---|---|
| **A** | Same database as Life Record, plaintext | **Yes** | One transaction | Contain plaintext |
| **B** | Separate store, server-managed encryption | Effectively yes — the tier holds the key | Two stores to coordinate | Ciphertext, key nearby |
| **C** | **Same database, client-side encrypted** | **No — ciphertext only** | One transaction | **Ciphertext, no key** |
| **D** | Device-only, never stored | No | Trivial | None — and see O4 |

### Recommendation — **C**

Client-side encryption, ciphertext stored in the same database as everything
else, in its own schema.

**Why same database rather than a separate store:** AD4 exists because erasure
completeness is a product promise. Splitting the store to gain isolation would
trade a guarantee for a property that **encryption already provides more
strongly** — a separate plaintext store is still readable by whoever
administers it.

**Key model:**

```
  her password ──┐
                 ├──► key-encryption key ──► wraps ──► DATA KEY ──► journal text
  recovery key ──┘        (two wrappings of one data key)
```

Password change re-wraps the data key; it does not re-encrypt her journal.
Password *reset* without the recovery key **cannot** recover it.

| | |
|---|---|
| **Benefits** | Operators, DBAs, backups, support and debugging tools see ciphertext · erasure stays one transaction · no second store to operate |
| **Costs** | **Recovery-key friction** · no server-side journal search · export is a device operation · support literally cannot help with journal content |
| **Privacy** | The strongest realistic posture. "We cannot read it" is a structural fact, not a policy. |
| **Product** | Onboarding gains a recovery-key step. **This is a real cost and should be designed as a moment of trust rather than a dialog to dismiss.** |
| **Architectural** | Interiority is the only module holding encrypted payloads. Crypto lives in the client; the server stores opaque blobs and never has a decrypt path. |
| **Deletion** | Delete the rows. Also: a lost key is *cryptographic* deletion — worth stating to her plainly. |
| **Failure** | Lost password **and** lost recovery key = journal unrecoverable. **We must say this before she writes, not after.** |
| **Future** | Compatible with multi-device (O4) and with on-device AI (O3). |

### What this extends to

**State and Observation are `private` too, and get the same treatment.**

Observation is where she records how she felt around someone — the single most
sensitive record in WLOS. Leaving it in plaintext while encrypting the journal
would protect the prose and expose the substance.

**Consequence worth naming:** if Observation is encrypted, **pattern detection
must run on device.** That is acceptable and arguably correct — patterns about
her interior life should be computed on her hardware. And per §0, reflection is
**counting, not inference**, so it works on every device regardless of AI
capability.

**This changes the approved architecture:** the Signals module moves
client-side. Flagged in §6 as an amendment, not smuggled in.

---

## 3. O4 — Does journal synchronise?

### Options

| | Option | Device loss | Multi-device | Server sees |
|---|---|---|---|---|
| **A** | Full server sync, plaintext | Recoverable | Yes | **Everything** |
| **B** | Device-local only | **Total loss** | No | Nothing |
| **C** | **Encrypted sync** | Recoverable *with recovery key* | Yes | Ciphertext |
| **D** | Hybrid — recent local, archive synced | Partial loss | Partial | Ciphertext |

### Recommendation — **C**

**B is the option to argue against, and the 70-year-old is why.** *"My story"*
is an area whose content is almost entirely biographical memory. A dropped
phone erasing a woman's life history is not a privacy win; it is the product
failing at the thing she valued most. It also contradicts *"she can export
everything"*, which implies the thing survives long enough to be exported.

| | |
|---|---|
| **Benefits** | Survives device loss · multi-device · normal backup operations · server never holds plaintext |
| **Costs** | Recovery-key management · conflict resolution across devices · larger sync payloads |
| **Privacy** | Equivalent to device-local **from the server's perspective**, because the server holds only ciphertext |
| **Product** | She can change phones without losing her interior life — which is what an account is *for* |
| **Architectural** | Interiority sync moves opaque blobs. Conflict resolution operates on envelopes and timestamps, never content. |
| **Deletion** | Rows deleted server-side; local store wiped. Both required. |
| **Failure** | Offline → local writes queue and sync later. Sync failure is never a write failure. |
| **Future** | Multi-device, device migration, and a future export-to-file all work unchanged. |

---

## 4. Combined decision — the three interlock

They are one decision:

```
        O3  journal-touching AI on device
              │  (because the server cannot read the journal)
              ▼
        O1  client-side encryption
              │  (which is what makes that true)
              ▼
        O4  encrypted sync
              │  (which makes encryption survivable)
              ▼
        one coherent posture
```

**Each depends on the others.** Server-side journal AI would make encryption
pointless. Encryption without sync would make device loss catastrophic. Sync
without encryption would make the AI rule cosmetic.

### The contract

> **Your journal, your check-ins and what you notice about your life are
> encrypted on your phone before they are stored.**
>
> **We keep them so you never lose them, and we cannot read them. Neither can
> our AI — anything that touches what you wrote runs on your phone, or does
> not run.**
>
> **If you lose your password and your recovery key, we cannot get it back.
> That is the cost of the promise, and we are telling you now rather than
> later.**

### What changes in existing promises

| | Before | After |
|---|---|---|
| Journal privacy | "private" — from other users and operators | **"we cannot read it"** — structural |
| Password reset | Not built; a pure convenience gap | **Now interacts with key recovery.** A reset that orphans her journal is unacceptable — recovery key must be designed *with* reset, not after |
| Support | Could in principle inspect data | **Cannot**, and must say so |
| Export | Server operation | **Device operation** |
| Data Safety declaration | "stored on our servers" | "stored encrypted; we hold no key" |

---

## 5. Infrastructure backdoor test

> *A generic infrastructure component must not become an accidental backdoor
> around the module boundary.*

Client-side encryption closes the **server-side** channels structurally — there
is no plaintext to leak. That shifts the whole risk surface **on-device**,
which is where this table now concentrates.

| Channel | Server-side | On-device | Control |
|---|---|---|---|
| Application logs | ciphertext only | **risk** | Interiority logger accepts identifiers only; **no overload takes its content types** |
| Exception messages | ciphertext | **risk** | Never interpolate record content into an exception |
| Telemetry / analytics | n/a | **risk** | Closed allowlist + runtime value screening *(built)* |
| Crash reports | n/a | **risk** | Scrubbed *(built)* — must extend to decrypted buffers |
| Search index | **impossible** | **risk** | Index lives on device, in the encrypted store, never a plaintext sidecar |
| Caches | ciphertext | **risk** | Decrypted content is request-scoped and never written to disk |
| Notifications | rendered text only | **risk** | Delivery receives a rendered string; **journal text never becomes a notification body** |
| Backups | ciphertext | **risk** | App excluded from cloud backup *(built)*; device backup would capture the local store — must be excluded |
| DBAs / operators | **ciphertext — structurally blind** | n/a | No decrypt path exists server-side |
| Debugging tools | ciphertext | **risk** | No debug view renders journal content; no "dump state" that includes it |
| Event bus / queues | ciphertext or ids | **risk** | Events carry **identifiers and types**, never payloads |
| AI pipelines | **never receives it** | controlled | Device-only port, no server implementation |
| Exports | ciphertext | controlled | Decrypt on device, user-initiated, written where she chooses |
| Support tooling | **ciphertext** | n/a | Support sees metadata only — the Slice 1 principle |
| Audit logs | ids only | ids only | Records *that* an entry changed, never what it said |

### The structural rule

> **Interiority's content types are never accepted by any generic
> infrastructure signature.**

Not "we agree not to log it" — **there is no logger overload, no serialiser
registration, no event payload type, and no telemetry property type that will
take them.** Passing journal content to infrastructure must be a compile error,
enforced by the same architecture fitness tests as the module boundary (AD3).

`ConfirmMemoryFromEntry` remains the **only** deliberate semantic crossing.

---

## 6. New invariants

Added to the architecture. **I6 is an amendment to the approved architecture
and should be approved explicitly.**

| | Invariant |
|---|---|
| **I1** | **Journal text never leaves the device in plaintext**, for any purpose, including AI. |
| **I2** | **The server holds no key** capable of decrypting Interiority content. |
| **I3** | **Any operation touching journal text runs on device, or does not run.** It is never relocated to the server on capability grounds. |
| **I4** | **Manual memory extraction always works**, on every device. AI proposal is a convenience, never the only route. |
| **I5** | **Journal, State and Observation are all client-encrypted.** Encrypting prose and exposing substance is not a privacy posture. |
| **I6** | **Pattern detection runs on device.** *(Amendment: moves the Signals module client-side.)* |
| **I7** | **Reflection is deterministic counting, not inference** — so it works on every device regardless of AI capability. |
| **I8** | **Interiority content types are not accepted by any generic infrastructure signature.** Compile error, not convention. |
| **I9** | **Loss of password and recovery key means cryptographic deletion**, and she is told this before she writes, not after. |
| **I10** | **Password reset must be designed together with key recovery.** A reset that orphans her journal is not shippable. |

---

## 7. Are O1, O3 and O4 stable enough for detailed technical design?

> ## **Yes — with one amendment requiring your approval.**

**Decided and stable:**

| | |
|---|---|
| **O3** | Hybrid, split by data class. Journal-touching → device-only. Context-based → server. |
| **O1** | Client-side encryption, ciphertext in the same database, own schema. Extends to State and Observation. |
| **O4** | Encrypted sync — survives device loss, server stays blind. |

**Requiring explicit approval — I6.** Encrypting Observation means pattern
detection moves client-side, relocating the Signals module from server to
device. It is the right consequence rather than a workaround, but it changes an
approved architecture and I will not slip it through.

**Two things pulled forward by this decision:**

**Password reset is now architecturally coupled** to key recovery (I10). It was
a launch-blocking product gap; it is now a design input, and building reset
without the recovery model would produce a reset that destroys journals.

**The recovery-key moment needs product design.** It is the one point where
this posture costs her something, and a dismissible dialog would be the worst
possible handling of the most important promise WLOS makes.

**Stopping here.** No detailed design in this document.
