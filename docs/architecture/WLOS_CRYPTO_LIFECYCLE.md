# WLOS Release 1 — Crypto Lifecycle & Blocker Resolution

**Status:** design for review. **No implementation, no migrations, no tests,
no code.** Nothing committed.

**Purpose:** make the cryptographic and privacy lifecycle reviewable *before*
the first Interiority record can exist.

---

## 1. B1 — Authentication / encryption key separation

### 1.1 The flaw, precisely

Slice 1 sends the plaintext password to the server. If that same password also
derives the key wrapping her data key, a server that observes one login can
derive the key and decrypt everything. **Salts alone do not fix this** — the
server would hold the password itself, and salts are not secret.

### 1.2 The corrected derivation

**One expensive KDF run, then HKDF domain separation.** Two independent
Argon2id runs would double the cost on a low-end phone for no additional
security; HKDF with distinct `info` labels is the correct primitive for
splitting one secret into independent purposes.

```
  password ─┐
            ├─► Argon2id(password, salt_master, params)  ──►  MASTER
  salt_master┘        (one run, device only, never stored, never sent)
                             │
                             ├─ HKDF-SHA256(MASTER, info="WLOS/v1/auth")   ──► auth_secret
                             │                                                 ↓ LEAVES DEVICE
                             │
                             └─ HKDF-SHA256(MASTER, info="WLOS/v1/kek/pw") ──► KEK_password
                                                                               ↓ NEVER LEAVES
                                                                            wraps DEK
```

**Why this holds:** `auth_secret` is an HKDF output. Recovering `MASTER` from
it is infeasible, and without `MASTER` the `kek/pw` label yields nothing. The
two branches are computationally independent even though both come from one
password.

**Domain separation labels** are versioned strings, not just different salts:
`WLOS/v1/auth` · `WLOS/v1/kek/pw` · `WLOS/v1/kek/recovery` ·
`WLOS/v1/kek/device`. A future protocol version changes the label, which
guarantees a v1 secret cannot be reused as a v2 secret.

### 1.3 Verifier construction

The server receives `auth_secret` and **must not store it directly** — a
database leak would yield a login-equivalent value.

**Server-side storage is unchanged from Slice 1:** PBKDF2-HMAC-SHA256, 210,000
iterations, per-row salt, `FixedTimeEquals`. From the server's point of view,
`auth_secret` simply *is* the password. `usp_User_GetForLogin` and
`usp_User_SetPassword` need no change at all — they verify a secret and do not
care how the client produced it.

> Only the **client** changes, plus the registration contract's parameter name.
> This is a smaller migration than it first appears.

### 1.4 Salts

| Salt | Size | Generated | Stored | Secret? |
|---|---|---|---|---|
| `salt_master` | 128-bit | device, at registration | **server** — required for device enrolment | **No.** Salts prevent precomputation; they are not secrets |
| server verifier salt | 128-bit | server | server | No |
| per-record nonce | 192-bit | device, per encryption | with the ciphertext | No |

### 1.5 The proof

> **Can a compromised server, database, API, admin account or SQL login derive
> the Interiority decryption key from authentication material?**

| Attacker holds | Can derive DEK? | Why not |
|---|---|---|
| `auth_secret` (from a live login) | **No** | HKDF is one-way; `MASTER` is not recoverable |
| PBKDF2 hash of `auth_secret` | **No** | One further one-way step |
| `salt_master`, KDF params | **No** | Public values; useless without the password |
| All wrapped DEK blobs | **No** | AEAD-sealed under KEKs the server never holds |
| Every ciphertext record | **No** | XChaCha20-Poly1305 without the key |
| **All of the above together** | **No** | The missing element in every case is `MASTER`, which exists only on her device |
| The **password itself** | **Yes** | Which is why it must never be sent — §1.2 |

**Residual, stated honestly:**

1. **Client integrity.** A malicious app build could capture the password
   before derivation. E2EE cannot defend against a compromised client. Mitigated
   by signed releases and reproducible builds — **not by cryptography**.
2. **Offline attack on a stolen backup.** An attacker with `salt_master`, the
   wrapped blob and a guess can test passwords offline. Resisted by Argon2id
   cost (§2) — **not eliminated**. A weak password remains weak.

---

## 2. B2 — Frozen cryptographic specification

**`WLOS-CRYPTO-v1`.** Every parameter carries a version so migration is
possible without ambiguity.

### 2.1 Parameters

| Parameter | Value | Why required | Property | If changed later | Re-work needed |
|---|---|---|---|---|---|
| **Password KDF** | Argon2id (RFC 9106) | Memory-hard; resists GPU/ASIC | Offline-guess resistance | new `kdf_version` | **Re-wrap only** — on next login |
| memory cost `m` | **64 MiB** | Fits low-end Android native alloc; forces attacker memory | GPU resistance | ↑ = stronger, slower | Re-wrap only |
| time cost `t` | **3** | ≈0.5–1.5 s low-end, ≈0.2 s flagship | Work factor | ↑ = stronger | Re-wrap only |
| parallelism `p` | **1** | Deterministic across devices | Reproducibility | changes output | Re-wrap only |
| output | **32 bytes** | Feeds HKDF | — | — | — |
| salt | **16 bytes** CSPRNG | Prevents precomputation | Uniqueness | per user | — |
| **Domain separation** | HKDF-SHA256, versioned `info` | Independent keys from one secret | Cross-purpose isolation | new label | Re-derive, re-wrap |
| **AEAD (records)** | **XChaCha20-Poly1305** | 192-bit nonce; no reuse anxiety; fast without AES-NI | Confidentiality + integrity | new `aead_version` | **Full re-encryption** |
| record key | 256-bit | — | — | — | — |
| nonce | **192-bit random** | Random-nonce collision is negligible at this size | Misuse resistance | — | — |
| associated data | `recordId ‖ version ‖ schemaVersion` | Binds ciphertext to identity | Prevents substitution | — | — |
| **Key wrapping** | XChaCha20-Poly1305, AD = `userId ‖ purpose ‖ wrapVersion` | A recovery blob cannot masquerade as a password blob | Confusion resistance | new wrap version | Re-wrap only |
| **DEK** | 256-bit CSPRNG, **on device** | Independent of password | Password change ≠ re-encryption | rotation | Full re-encryption |
| **Recovery key** | **128-bit → 12 BIP39 words** | Transcribable by a 70-year-old on paper | Recoverability | new format | Re-wrap only |
| recovery KDF | HKDF only, **no Argon2id** | Input is already 128-bit uniform; stretching adds nothing | — | — | — |

### 2.2 Why AES-GCM was not chosen

AES-256-GCM is more widely audited and hardware-accelerated. **XChaCha20-Poly1305
wins on one property that matters more here:** a 192-bit random nonce makes
reuse statistically impossible, whereas GCM's 96-bit nonce has a birthday bound
that a future bug in rotation or multi-device could approach. Nonce reuse is
the classic AEAD footgun and it is catastrophic — total loss of confidentiality
and authenticity for the affected key.

AES-256-GCM remains an acceptable alternative **if** nonces are counter-based
per key. That is a constraint we would have to maintain forever across two
platforms. XChaCha removes the obligation.

### 2.3 Why 12 words rather than base32

For an elderly or non-technical user, `K7M2-9XQR-4BNP-…` is transcribed
incorrectly far more often than twelve dictionary words. BIP39 carries a
checksum, so a mistyped word is *detected* rather than silently producing a
wrong key. **This is a usability decision with a security consequence** — a
recovery key that cannot be transcribed correctly is not a recovery key.

**User-chosen recovery keys are not permitted.** A memorable phrase would be
low-entropy and HKDF applies no stretching.

### 2.4 Parameter migration

Stored per user: `kdf_version`, `m`, `t`, `p`, `salt_master`, `aead_version`,
`wrap_version`.

**Upgrade path:** on the next successful login we hold the password legitimately.
Re-derive under new parameters, re-wrap the DEK, upload. **Content is never
re-encrypted** — the DEK is unchanged. This is the central advantage of
separating DEK from KEK and it makes parameter increases nearly free.

**Only an AEAD change forces full re-encryption**, which is why the record
cipher should be chosen once and left alone.

### 2.5 Secret lifetime in memory

| Secret | Lives | Cleared |
|---|---|---|
| password | one call frame | overwritten immediately after derivation |
| `MASTER` | derivation only | overwritten after HKDF |
| `auth_secret` | until the request completes | overwritten |
| **DEK** | while unlocked | on lock, on background timeout, on sign-out |
| `KEK_device` | platform keystore | on device removal |

**Honest limitation:** Dart and the JVM cannot guarantee zeroisation —
immutable `String` copies and GC movement may leave residue. Mitigation: hold
secrets in `Uint8List` and overwrite; never place them in `String`. **This is
mitigation, not a guarantee**, and a memory-dump attacker on an unlocked device
is out of scope for Release 1.

---

## 3. B3 — Password reset without a recovery key

### 3.1 The comparison

| | **Policy A** — reset restores account + Life Record | **Policy B** — reset also restricted |
|---|---|---|
| UX | She gets back in; journal is locked | Slower or blocked; more permanent lockouts |
| Accidental loss | Journal only | Journal **and** potentially the account |
| Privacy | Journal protected | Marginally better against takeover |
| Supportability | Support can help with access, never content | Support can do less |
| Attack resistance | Reset is the weak link for **Life Record** | Stronger |
| Takeover consequence | Attacker gets people, events, goals — **not** the journal | Attacker gets less |
| Elderly / non-technical | Recoverable account | **Risk of total lockout** |
| Device replacement | Works with password | Works |

### 3.2 The thing that decides it

**Life Record is not trivial data.** It holds her people, her children's names,
her appointments, her goals. A reset that hands that to an attacker is a real
harm — so the argument for Policy B is stronger than it first appears.

But Policy B's cost falls hardest on exactly the users WLOS is for: a
seventy-year-old who has lost both her password and a piece of paper should not
lose her whole account as well.

### 3.3 Recommendation

> **Policy A for the data outcome, with hardened reset mechanics.**

| | |
|---|---|
| Data outcome | Account and Life Record recoverable. **Interiority is not** — no server mechanism, no operator bypass. |
| Reset requires | Email possession **plus a delay window** |
| During the window | Every device is notified; she can cancel |
| On completion | **All sessions revoked** |
| Interiority | Records are **retained as locked ciphertext**, not deleted |

### 3.4 The locked state — never "empty"

The ciphertext still exists. Presenting it as an empty journal would be a lie
about what happened.

> *"Your journal entries from before 14 March are still here, but they were
> locked with a key that was lost when you reset your password. We cannot open
> them and neither can anyone else. If you find your recovery key, they will
> open again."*
>
> **[ Keep them locked ]   [ Delete them permanently ]**

Retaining them matters: she may find the recovery key months later.

### 3.5 Product judgment vs cryptographic fact

| Cryptographic fact | Product judgment |
|---|---|
| Without the DEK, ciphertext is unrecoverable. No policy changes this. | Whether she regains her *account* |
| No server bypass can exist without breaking the model | The delay window, notifications, and locked-state UX |

**Not to be implemented until explicitly approved.**

---

## 4. B4 — Health module audit

### 4.1 Measured state

| Measurement | Result |
|---|---|
| Tables in `Health.*` | **9** |
| Rows across all nine | **0** |
| Stored procedures in `Health` | **0** |
| Procedures **anywhere** referencing `Health.` | **0** |
| C# references | **0** |
| References in the erasure cascade | **9** |

**`Health.*` is completely inert** — schema with no read path, no write path
and no code. It is not a live risk today.

### 4.2 Classification

| Component | Class | Note |
|---|---|---|
| `Pregnancy`, `Cycle`, `DailyLog`, `Symptom`, `BodyMeasurement`, `BirthPreference`, `HospitalBagItem` | **Obsolete in WLOS** | Maren's domain. No Release 1 requirement. |
| `Appointment` | **Superseded** | WLOS models appointments as `Event` in Life Record |
| **`ShareGrant`** | **Incompatible — flag** | See §4.3 |

### 4.3 `ShareGrant` — the one that matters

A sharing-permission table, live in the schema, while **connections are
deferred and no sharing exists in Release 1.**

It is precisely the shape the architecture warned about: *a generic
infrastructure component becoming an accidental backdoor.* A future developer
looking for "how do we share something" will find a ready-made table with a
`UserId`, a `Kind` and a foreign key — and may wire it up without the consent
model that connections are deferred *for*.

**It has no procedures and no code, so there is no exposure path today.** The
risk is entirely future and entirely human.

### 4.4 Recommendation — decision required, not taken

**Drop all nine tables from WLOS in a numbered script**, with `ShareGrant`
named as the reason:

1. Zero rows — nothing is lost.
2. Zero code — nothing breaks.
3. Removes nine tables from the erasure cascade that can never contain data.
4. `ShareGrant` stops being a tempting shortcut around a deliberate deferral.

**Counter-argument, recorded fairly:** if WLOS ever hosts a pregnancy module,
these tables are a reasonable starting point — and the product direction is
that Maren stays a separate, independently deployed product, so they would not
be reused here anyway.

**Nothing modified or deleted. Decision B4 remains open.**

---

## 5. Encrypted record envelope

### 5.1 What the server stores

| Field | Server sees | In ciphertext |
|---|---|---|
| `RecordId` (UUID) | ✓ | — |
| `UserId` | ✓ | — |
| `Envelope` | ciphertext | everything below |
| `Version` | ✓ | — |
| `ServerSeq` | ✓ | — |
| `ServerReceivedUtc` | ✓ | — |
| `IsDeleted`, `DeletedUtc` | ✓ | — |
| record **type** | ✗ | ✓ |
| **authored timestamp** | ✗ | ✓ |
| title | ✗ | ✓ |
| people / area references | ✗ | ✓ |
| journal body | ✗ | ✓ |
| observation substance | ✗ | ✓ |

### 5.2 Current unavoidable leakage under Release 1

Not "irreducible minimum" — **current, under this design, with known future
mitigations.**

| Leaks | What it reveals | Future mitigation *(not Release 1)* |
|---|---|---|
| Record count | Roughly how much she writes | Decoy records |
| **Ciphertext length** | **Entry length — see §5.3** | **Bounded padding** |
| Sync timing | When she uses WLOS | Batched or randomly delayed sync |
| Create / update / delete rate | Editing behaviour | Uniform operation shapes |
| Tombstone existence | That something was deleted | Tombstone indistinguishability |

### 5.3 Does length leak materially? — Yes.

A 40-byte record and a 4,000-byte record are visibly different. Over time this
distinguishes a one-line check-in from a long distressed entry, **and length
correlates with emotional intensity.** A server observing only lengths and
timestamps could plausibly identify her hardest days.

> That is a real inference about her interior life, drawn from metadata alone.

**Recommendation: bounded padding in Release 1.** Pad each envelope to the next
bucket — 256 B, 1 KiB, 4 KiB, 16 KiB, 64 KiB, then 64 KiB steps. Cost is
storage and bandwidth; the coarse buckets defeat the correlation. **This is
cheap now and expensive to retrofit**, because retrofitting means re-encrypting
everything.

I am recommending this be **added to Release 1** rather than deferred.

---

## 6. Conflict semantics

**Approved invariant — no contradiction found:** *journal content is never
silently discarded.*

### 6.1 Prose (journal)

```
  409 conflict
       │
  device holds both versions
       │
  BOTH KEPT as separate records, linked and marked
```

Never last-write-wins. Never automatic merge. She is shown both and may keep,
merge manually, or delete one.

> Two entries is an inconvenience. A lost paragraph is a broken promise.

### 6.2 Point state (State, Observation)

Last-write-wins is acceptable **only** with an authored timestamp inside the
ciphertext:

| Rule | Reason |
|---|---|
| Compare **authored** time, not server-received | A device offline for a week must not overwrite a newer check-in on reconnect |
| Device clock skew > 5 min → treat as a conflict | Prevents a wrong clock silently winning |
| Same authored second → keep both | Ties are not resolvable; do not guess |
| **Observation is prose-bearing** → **treat as prose** | Its free-text fields make it closer to journal than to a scale |

**Correction to the earlier design:** Observation was grouped with State.
Because it contains her words, it takes **prose semantics** — both versions
kept.

---

## 7. Device lifecycle

### 7.1 What sign-out actually does

| Action | Effect | **Does not** |
|---|---|---|
| Sign out | Revokes refresh tokens; rotates the security stamp; access tokens die within the revocation window | **Remove the DEK from that device** |
| Remove device (server) | Same, plus the device is no longer listed | Reach the device's storage |
| App uninstall | Local store removed by the OS | Guarantee media erasure |
| **Key rotation** | New DEK, everything re-encrypted, old copies become undecryptable | — |

### 7.2 The honest statement

> **We cannot remotely erase a key from a device we no longer control.**
> Signing a device out stops it reaching your account. If you believe a device
> is in someone else's hands, change your key — that re-encrypts everything,
> and the copy on that device stops working.

**No claim of remote key revocation is made anywhere in the product.**

### 7.3 Rotation

Device-driven: new DEK → re-encrypt all records → re-wrap → upload atomically
per record. Interruptible and resumable; records carry `dek_generation` so a
half-finished rotation is readable by both generations. Other devices detect a
new generation and re-enrol.

**When required:** suspected device compromise · recovery key exposed · at her
request. **Not** on password change — that re-wraps only.

---

## 8. Memory boundary — the exact crossing

**Before confirmation:** encrypted, device-only, Interiority.
**After confirmation:** plaintext Life Record, may enter Context, may reach
server AI.

### 8.1 What crosses

| Crosses | Never crosses |
|---|---|
| The **selected fact**, as she edited it | Original journal text |
| `kind` (`operational` / `biographical`) | Surrounding entry content |
| Optional area / person reference | Unselected content |
| `provenance = confirmed` | The journal `RecordId` |
| An **opaque** confirmation receipt | Anything enabling re-identification of the entry |

### 8.2 Why the journal id does not cross

Storing `sourceEntryId` on the Memory would create a plaintext server-side
pointer into encrypted content — a map of which entries produced which facts,
and therefore which entries she considered significant.

**The link is kept device-side only**, so she can still see "this came from an
entry on 14 March" while the server cannot.

### 8.3 What she is told

> *"Remembering this saves it to your life record, outside your private
> journal."*

Plain, before confirmation, every time — not a one-off notice.

---

## 9. Local reflection — verification

| Requirement | Status |
|---|---|
| Observation stays Interiority | ✓ client-encrypted |
| Pattern detection on device | ✓ no server project exists (I6) |
| Reflection is deterministic counting | ✓ arithmetic, not inference |
| No server fallback | ✓ no server implementation to fall back to |
| No server access to journal text | ✓ no key |

**Leak-channel verification:**

| Channel | Verified by |
|---|---|
| Local model prompts/outputs sent remotely | On-device inference has no network permission in its code path; fitness test asserts no HTTP client reachable from the Signals module |
| Model telemetry | On-device APIs configured with telemetry disabled; no content in any analytics call (closed allowlist, runtime screening) |
| Crash reports | Scrubbed — **must extend to decrypted buffers**, which is new work |
| Logs | Interiority types not accepted by any logger signature (I8) |
| Analytics | Closed allowlist; opaque event names; value screening |

---

## 10. Notification privacy

| Source | Scheduled | Why |
|---|---|---|
| Life Record (goal, event, habit) | **server** | Plaintext; server knows when |
| **Interiority (reflection nudge)** | **device, local notification** | Server cannot know it is due |

### Lock screen

| Vector | Rule |
|---|---|
| Title | Generic and fixed: *"WLOS"* |
| Body | **Never** contains journal, observation or state content |
| Preview | Interiority notifications set `VISIBILITY_PRIVATE` — hidden until unlock |
| Analytics | Delivery events carry an opaque type, never content |
| History | Not retained server-side for Interiority-derived reminders |
| Server payload | **None exists** — these never leave the device |

> A reflection nudge says *"You have something to look at when you're ready."*
> It never says what.

---

## 11. Threat model

| # | Threat | Attacker capability | Asset | Protection | Still exposed | R1? |
|---|---|---|---|---|---|---|
| 1 | Compromised API server | Read requests, alter code | Interiority | No key; no plaintext path | Life Record; future logins if client is replaced | ✓ |
| 2 | Compromised database | Full read | Interiority | Ciphertext + wrapped DEK | Life Record; offline password attack | ✓ |
| 3 | DBA / operator | Query anything | Interiority | Structurally blind | Life Record | ✓ |
| 4 | Admin portal compromise | Operator actions | User content | Catalogue module has no user-data reference | Catalogue vandalism | ✓ |
| 5 | Stolen access/refresh token | Act as her | Life Record | 15-min access; rotation; reuse detection | **Life Record fully** | Partial |
| 6 | Password DB compromise | All verifier hashes | Accounts | PBKDF2 over a 256-bit `auth_secret` — nothing to brute-force | — | ✓ |
| 7 | Password reuse elsewhere | Known password | Everything | **None** — password is the root | **Interiority and Life Record** | ✗ |
| 8 | Phishing | Password | Everything | None cryptographic | Everything | ✗ |
| 9 | Lost **unlocked** device | Full access | Everything | None | Everything | ✗ |
| 10 | Lost **locked** device | Encrypted storage | Interiority | OS encryption + DEK not at rest in plaintext | Depends on device passcode | Partial |
| 11 | Compromised device | Root on device | Everything | None | Everything | ✗ |
| 12 | Rooted / jailbroken | Read app storage | Everything | Keystore weakened | Everything | ✗ |
| 13 | Malicious device enrolment | Valid password | Interiority | Requires the password; all devices notified | Enrolment with a stolen password | Partial |
| 14 | Account takeover via reset | Email access | Life Record | Delay window, device notification, session revocation | **Life Record. Journal protected.** | Partial |
| 15 | Malicious support employee | Support tooling | Everything | Metadata only; no decrypt path | Metadata | ✓ |
| 16 | Crash / telemetry leak | Read reports | Interiority | Scrubbing; I8 type barrier | Decrypted buffers — **new work** | Partial |
| 17 | Notification leak | Shoulder-surf | Interiority | No content in payloads; private visibility | Existence of a nudge | ✓ |
| 18 | Backup leak | Server backup | Interiority | Ciphertext; no key in backup | Offline password attack | ✓ |
| 19 | Export leak | Exported file | Everything | Plaintext by design — it is hers | **Everything, once exported** | ✗ by design |
| 20 | Deleted-account remnants | Backups/replicas | Erased data | Rows deleted; backups roll off | **Backup retention window** — must be disclosed | Partial |
| 21 | Offline replay | Replay old sync | Consistency | Idempotent on `(RecordId, Version)`; AD binding | — | ✓ |
| 22 | Conflict manipulation | Forge a conflict | Journal | Both versions kept; nothing discarded | Duplicate clutter | ✓ |

**Not claimed to be secure against:** a compromised device (9, 11, 12), a
stolen or reused password (7, 8), or a malicious client build. **E2EE protects
data from the server, not a user from her own device.**

**#20 must be disclosed:** deletion removes live rows immediately; database
backups age out on their own schedule. The deletion copy must say so rather
than imply instantaneous global erasure.

---

## 12. Architecture fitness tests

| Test | Asserts |
|---|---|
| **Server cannot decrypt** | No server assembly references a crypto primitive capable of decrypting Interiority; no type represents a DEK, KEK or plaintext Interiority record |
| **Auth separation** | No client path sends a raw password; no server path accepts one; the `kek/*` HKDF labels appear **only** in client code |
| **Data boundary (I8)** | No logger, telemetry, serialiser, event, queue, notification, audit, cache, search, support or AI signature accepts an Interiority content type |
| **AI boundary** | No reachable call graph from Interiority plaintext to any server client. The only path is `ConfirmMemoryFromEntry` → Life Record → Context → server AI |
| **No server Signals** | No server project exposes pattern detection |
| **Envelope opacity** | The Interiority store's public surface exposes envelopes and sync metadata only — no type carries record kind, authored time or references |
| **Padding applied** | Every stored envelope length is a bucket boundary (§5.3) |
| **Memory crossing** | `ConfirmMemoryFromEntry` payloads carry no journal `RecordId` and no unselected text |
| **Deletion** | Post-erasure sweep finds no undeclared identifier; wrapped DEKs removed; local wipe verified |
| **Provenance** | No fact-store write omits provenance; Life Record rejects `observed` |

---

## 13. Unresolved questions

Not blocking; decide during build.

1. Offline write model per module.
2. Tombstone retention window.
3. On-device model selection and its availability matrix.
4. Whether `KEK_device` (biometric convenience unlock) ships in Release 1.
5. Context latency budget.
6. Backup retention period to disclose for threat #20.

---

## 14. Implementation prerequisites

1. **B1 approved and implemented before any Interiority record exists.** Retrofitting requires every user to re-encrypt.
2. **B2 frozen** — parameters cannot change without re-wrapping.
3. **B3 approved** — recovery UX is product-critical.
4. **B4 decided** — affects migration and the erasure registry.
5. **Padding decision (§5.3)** — cheap now, requires full re-encryption later.
6. **Observation conflict correction (§6.2)** — prose semantics, not point-state.
7. Crash-report scrubbing extended to decrypted buffers.

---

# BLOCKED

Five decisions genuinely require human approval.

| | Decision | Why it needs you |
|---|---|---|
| **D1** | **Approve the §1.2 derivation and the Slice 1 auth change** | Changes a shipped contract. **Until it lands, the privacy claim is false.** |
| **D2** | **Freeze `WLOS-CRYPTO-v1`** (§2.1) — Argon2id 64 MiB / t=3 / p=1, XChaCha20-Poly1305, 12-word recovery | Cannot change later without re-wrapping or re-encrypting for every user |
| **D3** | **Approve Policy A with hardened reset** (§3.3) and the locked-state UX (§3.4) | A product decision about the worst day a user will have |
| **D4** | **Decide `Health.*`** — recommend dropping all nine (§4.4), `ShareGrant` named as the reason | Zero rows, zero code; the risk is future and human |
| **D5** | **Approve bounded padding in Release 1** (§5.3) | Length correlates with emotional intensity. Cheap now; requires full re-encryption later. **I recommend adding it.** |

**No implementation. No migrations. No production code. Nothing committed.**
