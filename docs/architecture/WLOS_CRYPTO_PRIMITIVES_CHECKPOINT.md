# WLOS — Crypto Primitives & Envelope Checkpoint

**Purpose.** The agreed stop between *"schema and procedures exist"* and
*"the first real encrypted record is written."* Short by design: it asks for
decisions on libraries and on the envelope, and nothing else.

**Status:** schema applied, procedures applied, 31 crypto assertions green.
**No client crypto written yet. No envelope code written yet.**

---

## 1. What has to be chosen, and where each runs

| Primitive | Client (Flutter) | Server (.NET 10) |
|---|---|---|
| **Argon2id** — password → MASTER | **Yes** | **No, and never.** The server has no password to stretch |
| **HKDF-SHA256** — MASTER → `auth_secret`, `KEK_password`; entropy → `KEK_recovery`, Ed25519 seed | **Yes** | No |
| **XChaCha20-Poly1305** — records and wrappers | **Yes** | **No.** The server stores envelopes; it never opens one |
| **Ed25519** — recovery proof of possession | **Sign** | **Verify only** |
| **ECDSA P-256** — device approval | Sign (platform key store) | **Verify only** — `System.Security.Cryptography.ECDsa`, built in |
| **SHA-256 / HMAC-SHA256** | Yes | Yes |
| **Constant-time compare** | Yes | `CryptographicOperations.FixedTimeEquals`, already in use |
| **BIP39 wordlist + checksum** | **Encode/decode only** | No |

> The server list is deliberately short. **If a primitive appears on the server
> that is not "verify" or "hash", something has crossed the boundary.**

---

## 2. Library choices — recommendation and the question behind each

### 2.1 Client: libsodium, via Dart FFI bindings

**Recommendation: libsodium.** It supplies Argon2id (`crypto_pwhash`,
ARGON2ID13), XChaCha20-Poly1305 IETF (24-byte nonce — exactly the envelope's
shape), and Ed25519 with **deterministic key generation from a seed**, which the
recovery key requires: the same phrase must produce the same key pair on any
device, forever.

A pure-Dart Argon2id is the alternative and should be rejected for the main
path: Argon2id at 64 MiB is memory- and compute-bound, and running it in the
Dart VM on a low-end phone is the difference between a two-second unlock and an
unusable one.

**Open questions, which are the reason this is a checkpoint:**

| | Question |
|---|---|
| **P1** | Native binary size and ABI coverage — arm64, armv7, x86_64 on Android; arm64 + simulator on iOS. This adds megabytes to the APK and must be measured, not assumed |
| **P2** | libsodium's key-derivation function is `crypto_kdf_blake2b`, **not HKDF-SHA256.** The protocol specifies HKDF-SHA256 with WLOS domain labels. **Recommendation: keep HKDF-SHA256** and implement it over libsodium's HMAC-SHA256 — HKDF is extract-then-expand over HMAC and is a few lines. Switching to BLAKE2b to avoid those lines would change every derived key and is not worth it |
| **P3** | Argon2id at 64 MiB on a minimum-spec device risks an OOM kill, not just slowness. **This is D6/D7 in concrete form** |

### 2.2 Server: Ed25519 verification is the only gap

.NET has ECDSA, SHA-2, HMAC and constant-time comparison built in. **It has no
Ed25519.** One dependency is required.

| Option | Note |
|---|---|
| **NSec.Cryptography** | libsodium-backed, modern typed API, small surface. **Recommended** — the same primitive implementation as the client, which removes a class of interop bug |
| BouncyCastle | Managed, no native dependency, very large surface for one function |

**Question S1:** native dependency on the server host, or managed? The platform
already runs a native SQL client, so a native dependency is not new — but it is
a deployment consideration and should be an explicit choice.

### 2.3 Hashing `auth_secret` on the server

`auth_secret` arrives as a 256-bit Argon2id output — already high-entropy and
already expensive to produce. **Recommendation: salted HMAC-SHA256, per-row
salt** (`Identity.UserCredential.AuthSecretSalt`, already in the schema).

Stretching it again would be theatre: an attacker who steals the verifier table
still has to run Argon2id once per password guess, and that cost dominates by
orders of magnitude. **Question S2:** accept this, or add a moderate PBKDF2 pass
as defence in depth at negligible cost?

### 2.4 BIP39

`mnemonicToEntropy` / `entropyToMnemonic` only. **`mnemonicToSeed` must never be
called** — it is the PBKDF2-HMAC-SHA512 derivation the protocol explicitly does
not use.

**Recommendation: a guard test asserting no call site references the seed
function**, in the same spirit as the "no procedure accepts a password"
assertion that now runs in CI.

---

## 3. The envelope — what implementation has to pin down

```
  magic(4) ‖ version(1) ‖ aead_id(1) ‖ dek_gen(2) ‖ nonce(24) ‖ ciphertext ‖ tag(16)
                                                                 └── 48 bytes of header+tag
  AD = recordId ‖ version ‖ schemaVersion
```

The 48-byte floor is already enforced as a check constraint on both
`Crypto.Wrapper` and `Crypto.Record`.

| | Decision needed |
|---|---|
| **E1** | **Byte order and exact widths** for `dek_gen` (uint16) and for the `version` / `schemaVersion` fields inside `AD`. Big-endian recommended, fixed-width, no varints. Once a record is sealed this can never change |
| **E2** | **`AD` is a byte string, not a struct.** Its encoding must be unambiguous — fixed-width fields concatenated, never length-prefixed strings, never a JSON blob whose key order can drift |
| **E3** | **`dek_gen` is a uint16**, so an account is capped at 65,535 generations. That is not a real limit; confirm rather than assume |
| **E4** | **Padding**: buckets 256 / 1K / 4K / 16K / 64K, `capacity(B) = B − 48 − 4`, with a 4-byte length prefix inside the plaintext. Confirm the prefix is **inside** the AEAD, so padding length is itself authenticated |
| **E5** | **Records above 64K** — chunk, or reject? Not yet decided, and a journal entry with an image attached reaches it immediately |
| **E6** | **Nonce generation**: 24 random bytes per seal, from the platform CSPRNG. XChaCha20's nonce space makes random generation safe; a counter would need per-device state and is the usual way this goes wrong |

---

## 4. The limitation to state now, not later

> **Dart cannot reliably scrub secrets from memory.**

`Uint8List` can be overwritten and should be, for the MASTER, the DEKs and the
KEKs. **Strings cannot.** The password she types and the mnemonic she is shown
are Dart `String`s — immutable, garbage-collected, possibly copied by the VM —
and there is no supported way to guarantee they are gone.

Consequences to accept explicitly:

- On a device an attacker can dump memory on, secrets may be recoverable
  regardless of what the code does. That is threat **D**, already stated as
  unprotected.
- **This must not be described as "keys are wiped from memory."** Keys held in
  `Uint8List` are overwritten on a best-effort basis; the password and the
  mnemonic are not.

---

## 5. Resolved — checkpoint approved, decisions locked

| | Decision | Built |
|---|---|---|
| **P2** | **HKDF-SHA256**, not libsodium's BLAKE2b KDF. WLOS labels are authoritative | `KeyHierarchy`, four labels, pinned by vectors |
| **S2** | **Salted HMAC-SHA256** for the server's `auth_secret` verifier. No PBKDF2 on top | `AuthSecretVerifier` |
| **E1** | **Fixed-width, explicit big-endian** | `CanonicalBytes` / `WlosCanonicalBytes` |
| **E2** | **Canonical byte-string AD.** No JSON, no framework serialisation | `WlosEnvelope.associatedData`, 56 fixed bytes |
| **E3** | **uint16 `dek_gen`.** Generation 0 does not exist; the first is 1 | Enforced in the codec *and* by `CK_Generation_Number BETWEEN 1 AND 65535` |
| **E4** | **4-byte length prefix inside the AEAD**, then content, then padding | `WlosEnvelope` |
| **E5** | **Reject over-size in v1.** No chunking; attachments are a later capability | See the correction below |
| **E6** | **24-byte CSPRNG nonce per seal** | Caller-supplied so the codec stays deterministic |
| **S1** | **BouncyCastle**, after confirming .NET 10 has no Ed25519 | `RecoverySignatureVerifier` |
| **P1** | libsodium accepted in principle; size measured during implementation | `AeadCipher` interface; pure-Dart implementation behind it |
| **P3 / D6 / D7** | Argon2id parameters stay versioned and configurable | `KdfProfile`, `isProvisional` surfaced to callers |

### The one number that needed correcting

**E5's "64 KiB" is the envelope, not the payload.** Buckets are envelope sizes,
so:

```
  capacity(B) = B − 48 − 4          48 = header(32) + tag(16),  4 = length prefix
  max payload = 65536 − 52          =  65,484 bytes
```

Calling the limit 64 KiB would be wrong by 52 bytes — the kind of error that
only shows up on a real record months later. The constant is
`WlosEnvelope.maxPayloadBytes = 65484` and a test asserts the bucket
boundaries exactly.

### One strengthening, flagged rather than slipped in

**The header is inside the associated data.** The earlier specification text
said `AD = recordId ‖ version ‖ schemaVersion`. Without the header in there,
header tamper-detection rests on indirect arguments — a changed generation
happens to select the wrong key, a changed version happens to be rejected
structurally. Those are all true today and all fragile. `AD` is now
`header(32) ‖ recordId(16) ‖ version(4) ‖ schemaVersion(4)`, every header byte
is unconditionally tamper-evident, and it costs nothing.

### Cross-language vectors — done

`wlos_crypto_vectors.json`, generated deliberately by
`WLOS_App/tool/generate_crypto_vectors.dart`, **never by a test run**. Committed
identically to both repositories; both suites assert its SHA-256, so a copy
edited on one side fails on that side.

Twelve assertions each side. A signature produced in Dart is verified in .NET.
UUID byte order, HKDF labels, integer widths and the auth-secret verifier all
agree byte for byte.

Argon2id and the envelope are pinned on the client only — the server runs
neither, and a .NET implementation of either would be production code holding
keys it must never touch.

---

## 6. What this checkpoint originally asked for

| | Decision |
|---|---|
| **P1** | Accept the native-binary cost, once measured? |
| **P2** | Keep HKDF-SHA256 over libsodium HMAC — **recommended** |
| **P3** | Argon2id memory on minimum-spec hardware — **this is D6/D7** |
| **S1** | NSec (native) or BouncyCastle (managed) for Ed25519 verification |
| **S2** | Salted HMAC-SHA256 for `auth_secret` — **recommended** — or add PBKDF2 |
| **E1–E6** | Envelope encoding, padding prefix placement, oversize records, nonce source |

**Nothing below the schema and procedures has been written.** The next code
after this checkpoint is the client key hierarchy and the envelope codec, and
both are irreversible once a real record is sealed — which is exactly why the
stop is here.
