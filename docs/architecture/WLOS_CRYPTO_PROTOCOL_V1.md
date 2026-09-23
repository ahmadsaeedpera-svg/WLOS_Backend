# WLOS Crypto Protocol v1 — Specification & Decision Lock

**Status:** final protocol specification for approval. **No implementation.**

**Decisions carried in:** D1 approved with condition (protocol below) · **D2
not frozen — corrected here** · D3 approved · D4 approved · D5 approved.

---

## 1. D2 correction — the recovery key, precisely

You were right to stop this. *"12 BIP39 words = 128-bit key"* conflates three
different things.

### 1.1 What WLOS does

```
  1.  CSPRNG  ──►  128 bits of entropy        ← THIS IS THE SECRET
  2.  BIP39 encode: entropy ‖ checksum(4 bits) → 132 bits → 12 words
  3.  Display the 12 words. She writes them down.
  4.  On input: words → validate checksum → recover the SAME 128 bits
  5.  recovery_secret = those 128 bits
  6.  KEK_recovery = HKDF-SHA256(recovery_secret, info="WLOS/v1/kek/recovery")
```

**BIP39 is used as an encoding, not as key material.** The secret is the
entropy. The words are a transcription format chosen for three properties:

| Property | Why it matters here |
|---|---|
| 2048-word list, unambiguous in the first 4 letters | A 70-year-old copying by hand |
| 4-bit checksum | A mistyped word is **detected**, not silently wrong |
| Widely implemented, well-specified | No bespoke encoding to get wrong |

### 1.2 What WLOS explicitly does *not* do

**We do not use the BIP39 seed derivation.** BIP39 defines
`PBKDF2-HMAC-SHA512(mnemonic, "mnemonic"+passphrase, 2048, 64)` for
hierarchical wallets. That is a different purpose, and 2048 iterations is far
below what we would choose if stretching were needed.

**It is not needed at all.** The entropy is already 128-bit uniform, so there
is nothing to stretch — HKDF alone is correct and sufficient. Applying a slow
KDF to a uniform random secret adds cost without adding security.

### 1.3 Wordlist

**English only in v1**, regardless of UI language. A recovery phrase must
decode identically on any device in any locale; a phrase written in one
wordlist and typed on a device defaulting to another would fail the checksum
and read as "wrong key". Localised wordlists are a **recovery-format version**
change, not a v1 option.

### 1.4 No user-chosen recovery keys

A memorable phrase is low-entropy and HKDF applies no stretching. Only
generated entropy is accepted.

---

## 2. Key topology — exact

```
                        ┌───────────────────────────┐
                        │  DEK   256-bit CSPRNG     │
                        │  generated ON DEVICE      │  encrypts every record
                        │  never derived            │
                        └────────────┬──────────────┘
                                     │  sealed independently under each KEK
         ┌───────────────────────────┼───────────────────────────┐
         │                           │                           │
   KEK_password              KEK_recovery                 KEK_device (0..N)
   HKDF(MASTER,              HKDF(recovery_secret,        platform keystore
     "…/kek/pw")               "…/kek/recovery")          (biometric unlock)
```

### Wrapped blob inventory

| Blob | Count | Created | Deleted |
|---|---|---|---|
| `wrap/pw/{generation}` | **1 per password generation** | registration; password change; reset | §5.4 rules |
| `wrap/recovery` | **exactly 1** | registration | on recovery-key regeneration (replaced) |
| `wrap/device/{deviceId}` | **0..N** | when she enables biometric unlock on a device | device removal · sign-out · rotation |

**Minimum at rest: 2.** Typical: 2 + one per biometric-enabled device.

Each blob is independently addressable and independently deletable. Every blob
is AEAD-sealed with `AD = userId ‖ purpose ‖ generation ‖ wrapVersion`, so a
recovery blob cannot be presented as a password blob.

---

## 3. D1 — the complete protocol

### 3.1 Registration

```
  DEVICE                                             SERVER
  ──────                                             ──────
  salt_master  = CSPRNG(16)
  MASTER       = Argon2id(password, salt_master, P)
  auth_secret  = HKDF(MASTER, "WLOS/v1/auth")
  KEK_password = HKDF(MASTER, "WLOS/v1/kek/pw")

  recovery_entropy = CSPRNG(16)         → shown as 12 words
  KEK_recovery = HKDF(recovery_entropy, "WLOS/v1/kek/recovery")

  DEK = CSPRNG(32)
  wrap_pw  = seal(KEK_password, DEK)
  wrap_rec = seal(KEK_recovery,  DEK)

  ──── POST /auth/register ───────────────────────►
       email, dateOfBirth, countryIso, languageCode,
       auth_secret,
       salt_master, kdf_version, m, t, p,
       wrap_pw, wrap_rec, wrap_version
                                                    stores PBKDF2(auth_secret, srv_salt)
                                                    stores salt_master + params
                                                    stores wrap_pw, wrap_rec
  ◄─────────────────── session ────────────────────
```

**Sent:** `auth_secret` (a 256-bit HKDF output), public salts and parameters,
two sealed blobs.
**Never sent:** password · `MASTER` · `KEK_*` · `DEK` · recovery entropy.

### 3.2 Login

```
  ──── GET /auth/kdf-params?email ────────────────►   returns salt_master,
  ◄────────────────────────────────────────────────   kdf_version, m, t, p

  MASTER      = Argon2id(password, salt_master, P)
  auth_secret = HKDF(MASTER, "WLOS/v1/auth")

  ──── POST /auth/login { email, auth_secret } ───►   PBKDF2 verify (unchanged)
  ◄──────────── session + wrap_pw ─────────────────

  KEK_password = HKDF(MASTER, "WLOS/v1/kek/pw")
  DEK          = open(KEK_password, wrap_pw)        ← fails loudly if tampered
```

**The params endpoint is pre-authentication and leaks that an address is
registered.** Mitigation: it returns **plausible deterministic parameters** for
unknown addresses — derived from HMAC(server_key, email) — so registered and
unregistered addresses are indistinguishable. Login then fails as it always
does. This preserves the Slice 1 property that WLOS never reveals whether an
address is registered.

### 3.3 Your nine questions, answered

| | Answer |
|---|---|
| **What is sent at registration?** | §3.1 — `auth_secret`, public params, two sealed blobs |
| **What is sent at login?** | `email`, `auth_secret`. Nothing else. |
| **Is `auth_secret` password-equivalent to the server?** | **Yes — and it must be treated as a live credential.** Anyone holding it can authenticate. TLS-only, never logged, never in a URL, never in an error. It is *not* password-equivalent for **decryption**, which is the entire point. |
| **Can someone with the database verifier authenticate?** | **No.** The verifier is `PBKDF2(auth_secret)`. Authentication requires `auth_secret`; the verifier does not yield it. PBKDF2's iteration count adds nothing against a 256-bit uniform input — **its job here is to stop the stored value from *being* the credential**, which it does. |
| **Does reset establish a new `auth_secret`?** | Yes. New password → new `MASTER` → new `auth_secret`, new `KEK_password`, new `wrap/pw/{gen+1}`. |
| **Does reset destroy DEK unwrap?** | **Only without the recovery key.** With it: unwrap, re-wrap, nothing lost. Without: §5.4. |
| **Can a compromised API obtain or replace wrapped keys?** | **Obtain: no** — it never holds a KEK. **Replace: it can substitute a blob, and the client detects it** — the AEAD tag fails to verify and the client refuses rather than proceeding. See §3.4 for the attacks it *can* attempt. |
| **Any endpoint still accepting a password?** | **None.** Fitness-tested: no server contract has a `password` field; no client path sends one. |
| **Can mobile logging capture the password pre-derivation?** | §3.5 — **honestly, partially.** |

### 3.4 Active-server attacks and their defences

| Attack | Defence |
|---|---|
| **Substitute a wrapped blob** | AEAD tag fails. Client shows a tamper warning and **refuses to proceed** — it does not silently re-wrap. |
| **KDF downgrade** — serve `m=1 MiB, t=1` | **Client enforces a hard-coded floor** and refuses parameters below it. Floor is compiled in, not server-supplied. |
| **Salt substitution** | Different salt → different `auth_secret` → login fails. Detectable, not exploitable. |
| **Replay an old wrapped blob** | `AD` binds `generation`; an old blob presented as current fails. |
| **Serve a malicious client** | **Not defended by cryptography.** Signed releases, store review, reproducible builds. Out of scope for the protocol and stated as such. |
| **Account takeover via reset** | Attacker gets a new password and a locked journal. They cannot unwrap the DEK. |

### 3.5 Password handling on device — honest limits

> *"The password does not cross the wire" is necessary and not sufficient.*

| Control | Status |
|---|---|
| Password never in a log | Enforceable |
| Password never in an exception message | Enforceable |
| Password never in analytics or crash payload | Enforceable — scrubbing exists |
| Password never persisted | Enforceable |
| Password held only in `Uint8List`, overwritten after derivation | Enforceable **in our code** |
| **Password exists as a Dart `String` in `TextEditingController`** | **Not eliminable.** Flutter text input produces immutable Strings; copies may persist until GC and cannot be overwritten. |

**Mitigations:** clear the controller immediately after derivation · disable
autofill-save prompts for the field · exclude the auth screen from screenshots
(`FLAG_SECURE`) · exclude widget state from crash reports.

**Residual, stated plainly:** an attacker with memory-read on an unlocked
device during sign-in can recover the password. That is threat 9/11/12 —
already out of scope, and no protocol change alters it.

---

## 4. Envelope format and padding

### 4.1 Envelope

```
  offset  size  field
  ──────  ────  ─────────────────────────────────────
     0      4   magic        "WLOS"
     4      1   version      0x01
     5      1   aead_id      0x01 = XChaCha20-Poly1305
     6      2   dek_gen      uint16, key generation
     8     24   nonce        192-bit CSPRNG, fresh per seal
    32      N   ciphertext   sealed(padded plaintext)
  32+N     16   tag          Poly1305

  AD = recordId(16) ‖ version(4) ‖ schemaVersion(2)
```

### 4.2 Plaintext, before padding

```
  CBOR {
    type            journal | state | observation
    authoredUtc     her clock, never the server's
    title?          journal only
    body            prose
    refs[]          person / area ids
    schemaVersion
  }
```

**Every field the server must not see lives here** — including the record type
and the authored time.

### 4.3 Padding (D5)

```
  padded = len(4, uint32) ‖ content ‖ zeros(bucket − 4 − len)

  bucket(n) =  256                        if n ≤ 252
               1024                       if n ≤ 1020
               4096                       if n ≤ 4092
               16384                      if n ≤ 16380
               65536                      if n ≤ 65532
               65536 × ⌈(n+4)/65536⌉      otherwise
```

**The algorithm is fixed; the bucket table is an implementation parameter.**
Changing the table changes future records only — old records stay valid
because the length prefix makes padding self-describing. This is deliberate:
the table can be tuned from real data without re-encrypting anything.

**What it costs:** a one-line check-in occupies 256 bytes instead of ~60.
Negligible.

**What it buys:** a server seeing only lengths cannot distinguish a one-line
entry from a four-line one, which removes the length-to-emotional-intensity
correlation identified earlier.

---

## 5. Lifecycle protocols

### 5.1 Second-device enrolment

```
  1. Sign in with password (§3.2)          → session + wrap_pw
  2. KEK_password = HKDF(MASTER, "…/kek/pw")
  3. DEK = open(KEK_password, wrap_pw)
  4. Pull envelopes from ServerSeq = 0, decrypt locally
  5. Optional: wrap_device = seal(KEK_device, DEK)  → upload for biometric unlock
  6. All other devices are notified: "a new device signed in"
```

**No key material crosses the network at any step.** The server's only role is
to hand over a blob it cannot open.

### 5.2 Password change (she knows the current one)

```
  MASTER_old → KEK_pw_old → DEK = open(wrap_pw_old)
  MASTER_new ← Argon2id(new password, salt_master_new)
  wrap_pw_new = seal(KEK_pw_new, DEK)

  POST /auth/change-password
    { auth_secret_old, auth_secret_new, salt_master_new, params, wrap_pw_new }

  Server: verify old → store new verifier → store new blob → DELETE old blob
```

**Content is never re-encrypted.** The DEK is unchanged. `wrap/recovery` is
untouched and still opens the DEK.

### 5.3 Password reset *with* recovery key

```
  DEK = open(KEK_recovery, wrap_recovery)
  new password → wrap_pw_new = seal(KEK_pw_new, DEK)
  Server: reset verifier → store new blob → DELETE all old wrap/pw blobs
```

Nothing is lost.

### 5.4 Password reset *without* recovery key — corrected

> **This is where I had a flaw, and it matters.**

My earlier design implied keeping old `wrap/pw` blobs so a remembered password
could still recover. **That is dangerous:** if she is resetting *because the
password was compromised*, retaining a blob openable by that password leaves
the attacker able to decrypt her journal forever.

**Corrected rule:**

```
  Reset without recovery key
        │
        ├─► she is asked, explicitly, which is true:
        │
        │    "I forgot my password"        → keep the old wrap/pw blob
        │                                     (she may remember it later)
        │
        │    "Someone else may know it"    → DELETE the old wrap/pw blob
        │                                     immediately and permanently
        │
        └─► either way: new password, new auth_secret, new DEK generated,
            new wrap/pw + new wrap/recovery for everything written from now on
```

**Two DEK generations coexist.** Old records stay under `dek_gen = k` (locked
or recoverable per her answer); new records use `dek_gen = k+1`. `dek_gen` is
already in the envelope header, so this needs no format change.

**She must be asked, because only she knows the answer, and the two answers
have opposite security consequences.** Defaulting either way would be wrong.

### 5.5 Recovery-key loss (password still known)

Generate new entropy → `wrap_recovery_new = seal(KEK_recovery_new, DEK)` →
**old blob deleted**. Nothing re-encrypted.

### 5.6 Device removal and rotation

| Action | Effect |
|---|---|
| **Sign out** | Refresh tokens revoked; security stamp rotated. **The DEK on that device is untouched.** |
| **Remove device** | Above, plus `wrap/device/{id}` deleted. Prevents future biometric unlock; **does not** reach a cached DEK. |
| **Rotation** | New DEK. Re-encrypt every record, bumping `dek_gen`. Re-wrap. Resumable — both generations remain readable mid-rotation. Other devices detect the generation change and re-enrol. |

**When rotation is required:** suspected device compromise · recovery key
exposed · at her request. **Not** on password change.

**The claim we make:** *"Signing out stops that device reaching your account.
If it may be in someone else's hands, change your key."* **No remote key
revocation is claimed anywhere.**

### 5.7 Account deletion

Live rows and every wrapped blob deleted; local store wiped. **Backups age out
on their own schedule** and the deletion copy must say so — deletion is
immediate in the live system, not instantaneous across every backup generation.

---

## 6. Server-visible metadata — exhaustive

| Visible | Not visible |
|---|---|
| `RecordId`, `UserId` | record type |
| ciphertext **bucket** size | true length |
| `Version`, `ServerSeq` | authored time |
| `ServerReceivedUtc` | title, body, refs |
| tombstone existence | what was deleted |
| record count | observation substance |
| `salt_master`, KDF params | password, `MASTER`, any KEK, the DEK |
| wrapped blobs, `dek_gen` | anything inside them |
| email, Life Record, Catalogue, Governance, Delivery | — |

**Current unavoidable leakage under Release 1:** count · bucket size · sync
timing · operation rate · tombstone existence.
**Future mitigations, not Release 1:** decoy records · batched/delayed sync ·
uniform operation shapes.

---

## 7. The Life Record boundary — stated explicitly

You are right that this has not been elevated enough.

```
  PRIVATE JOURNAL          encrypted · device-only · server cannot read
        │
        │  SHE explicitly selects and confirms
        ▼
  CONFIRMED MEMORY         plaintext · server-side
        │
        ├──► Context
        └──► Server AI
```

### The promise, precisely

> **WLOS cannot read your private journal.**

**Not:** *"WLOS never knows anything sensitive about you."*

She may deliberately save *"I am struggling badly with X"* as a confirmed
memory. At that moment she has moved it **outside Interiority on purpose**, and
it is plaintext, server-side, and may reach Context and server AI. **That is
the system working as designed, not a leak.**

### What may enter Life Record

| May | May not |
|---|---|
| A fact **she selected and confirmed** | Anything auto-extracted |
| Her own edit of that fact | Surrounding journal text |
| `kind`, optional refs, `provenance = confirmed` | The journal `RecordId` (§8) |

### The UI obligation

The confirmation screen states the destination **every time**, for every
confirmation, regardless of content:

> *"Remembering this saves it to your life record, outside your private
> journal. It can then help WLOS understand your day."*

**Uniform wording, never conditional.** Varying it by how sensitive the content
looks would require classifying her words — which is inference, and forbidden.

---

## 8. Memory crossing — exact payload

| Crosses | Never crosses |
|---|---|
| `fact` — her text, as she edited it | Original entry text |
| `kind` — operational \| biographical | Surrounding content |
| `refs[]` — optional area / person | Unselected content |
| `provenance = confirmed` | **The journal `RecordId`** |
| `confirmationId` — opaque, device-generated | Anything re-identifying the entry |

**Why the journal id must not cross:** a plaintext `sourceEntryId` on a Memory
would give the server a map of which encrypted entries produced facts — and
therefore which entries she considered significant. The link is kept
**device-side only**, so she still sees *"from an entry on 14 March"* while the
server cannot.

---

## 9. Threat-model assumptions

**Assumed:** TLS is intact · the client build is authentic · the device OS is
uncompromised · the CSPRNG is sound · Argon2id and XChaCha20-Poly1305 hold.

**Not defended against:** a compromised or rooted device · a malicious client
build · a stolen or reused password · phishing · an unlocked lost device ·
memory extraction during sign-in.

**E2EE protects her data from the server. It does not protect a user from her
own device.** Stated here so it is never implied otherwise in product copy.

---

## 10. D3 — wording correction accepted

Not *"cryptographically gone"*. The ciphertext still exists.

> **Cryptographically inaccessible under the new credentials unless the
> original recovery material is supplied.**

Which is exactly why the locked state (§3.4 of the prior paper) is correct
rather than deleting the records.

---

## 11. D4 — confirmed

Remove all nine `Health.*` tables. Audit stands: **0 rows · 0 procedures · 0
references**. `ShareGrant` named as the reason — a live sharing-permission
table while connections are deferred is a misleading affordance. Removal also
takes nine entries out of the erasure cascade that can never hold data.

---

# BLOCKED — one decision

| | Decision |
|---|---|
| **D2-R** | **Re-approve `WLOS-CRYPTO-v1` as corrected in §1 and §5.4.** |

You withheld D2 pending correction. Two things changed materially:

**§1 — recovery key.** BIP39 is an **encoding**, not key material; the secret
is the 128-bit entropy; the BIP39 seed derivation is **not** used; English
wordlist only in v1.

**§5.4 — reset without recovery key.** My earlier design retained old wrapped
blobs so a remembered password could recover. **That leaves a compromised
password able to decrypt her journal forever.** Corrected to ask her which
situation she is in, because the two answers have opposite security
consequences and only she knows.

**Everything else is specified and ready:** D1 protocol proven end to end ·
D3 approved with your wording · D4 approved · D5 approved with the padding
algorithm fixed and the bucket table left tunable.

**On D2-R approval this becomes IMPLEMENTATION READY — CRYPTO PROTOCOL LOCKED.**

**No code. No migrations. Nothing committed.**
