# WLOS — Deferred Decisions & Hardening Register

**Purpose.** One place for every open item that implementation is permitted to
proceed past, with the reason it is safe to defer and the condition that would
force it open again.

**The admission rule, as set at the move-forward decision:**

> **An open decision may remain open if the next implementation phase can
> preserve both possible outcomes without rework and without weakening an
> invariant.**

An item that fails this rule is **not** deferrable and belongs in
`WLOS_RESET_AUTHORIZATION_V1.md` §A as a correction required before lock.

**Status:** 🟢 implementation proceeding. Nothing in this register blocks it.

---

## 1. How each item is held open

Every deferred item names the mechanism that preserves both outcomes. **The
mechanism is a deliverable, not a note** — if it is not built, the item is not
actually deferred.

| | Item | Held open by | Rework if decided late |
|---|---|---|---|
| **D12** | E3a or E3b | `ResetApprovalPolicy` strategy, one configuration value. `E3a` → no-response commits at t+24 h; `E3b` → no-response expires at t+24 h. **Both branches implemented and both tested** | **None.** One config value |
| **D11** | Destroy delay | `DestroyDelay` as a configured duration, `0` meaning immediate. The `DESTROY_PENDING` state and its cancellation exist regardless | **None.** One config value |
| **D6** | Minimum supported Android device | Nothing in the schema or protocol references a device class | **None** |
| **D7** | Argon2id p95 ceiling | `Crypto.KdfProfile` — **versioned KDF parameters as data, not constants.** Each credential row names its profile; the platform already does exactly this for PBKDF2 via per-row `PasswordIterations`. **First real measurement taken 2026-09-24 — see §1b. It does not close this.** | **None.** Insert a profile row and let rehash-on-login upgrade carry accounts forward |
| **A3** | Is a `BE = 0` platform credential obtainable on target OS versions? | `IDeviceApprovalCredential` with two adapters — WebAuthn and DBK (Keystore / Secure Enclave). The protocol-level `approval_context` is identical for both | **None**, provided both adapters exist behind the interface |
| **P1** | libsodium's real binary and ABI cost on device | `AeadCipher` interface, with a pure-Dart XChaCha20-Poly1305 behind it today. **An Argon2id and an envelope vector are frozen**, so swapping the implementation is checked against fixed bytes rather than assumed to be equivalent | **None.** One class, one vector run |

## 1b. The first Argon2id measurement — and why it does not close D6 or D7

**Taken 2026-09-24**, the first time the app was run on Android at all. Seeded
profile: `m=65536 KiB, t=3, p=4`, pure-Dart Argon2id.

| Build | Cost | What it is |
|---|---|---|
| debug (`flutter test integration_test/`) | **4,827 ms** | Dart under the JIT. **Not a slow version of the real number — a different execution mode from any a phone runs.** Recorded only so nobody quotes it |
| profile (`flutter drive --profile`) | **1,545 ms** | AOT, the mode a release build uses. 3.1× faster than debug |

**Both figures are from an Android emulator**, which is a desktop CPU wearing a
costume. A low-end phone — the device class D6 is about — will be slower, and
nothing here says by how much. The honest reading is: *on the fastest thing we
have, sign-in costs a second and a half.* That is the floor, not the answer.

**Why this is not enough to close either decision:**

- D6 asks which devices are supported. One emulator is not a device class.
- D7 asks for a **p95 ceiling**. A single measurement on one machine has no
  p95 in it, and the instruction at the checkpoint was explicit: *do not
  invent a production benchmark result.*

**What it is good for.** It moves the question from unmeasured to bounded, and
it already says something uncomfortable: 1.5 s is the optimistic end, and the
same derivation runs on sign-in, on password change, and on closing an
account. If a real low-end device lands at 4–6 s, the profile needs revisiting
before launch rather than after — and because parameters are data, revisiting
it is a row, not a release.

The measurement lives in `WLOS_App/integration_test/crypto_flow_test.dart` and
is asserted only against 30 s, as a smoke alarm rather than a threshold.

---

## 1a. Resolved since the register was opened

| | Decision | Outcome |
|---|---|---|
| **S1** | Ed25519 on the server | **Resolved by inspection and a spike, not by reasoning.** .NET 10 has no standalone Ed25519 — the only framework references are composite post-quantum identifiers (`MLDsa44WithEd25519`), confirmed by searching the ref pack. BouncyCastle and NSec were both spiked against RFC 8032 test vector 1; both passed. **BouncyCastle selected**: managed-only, no native assets, against NSec's per-RID libsodium binary. NSec is smaller and roughly twice as fast (0.14 ms vs 0.26 ms per verification), and neither matters on a path used once in an account's lifetime. What matters is that the path must work when a woman is already locked out, and a missing or mismatched native binary fails exactly there |
| **Cross-language vectors** | Mandatory before the first sealed record | **Done.** `wlos_crypto_vectors.json`, generated deliberately by the client and committed identically to both repositories, both asserting its SHA-256. 12 assertions each side. A signature produced in Dart is verified in .NET; UUID order, HKDF labels, integer widths and the auth-secret verifier all agree byte for byte |
| **A7** | Reset-during-migration: Option A, B or C | Migration is **not implemented in the first slices.** Generation recovery is a later slice, so the choice is made before any code depends on it | **None while migration is unbuilt** |
| **A9** | Security-stamp validation cache TTL | Already a configured value in `Maren.Infrastructure`. The E4 / R2 / R3 transactions bump the stamp regardless | **None.** One config value |
| **H1** | Anti-rollback / deletion detection | v1 has none, and §10 of the protocol says so. A future client-side state commitment is **additive** — it adds a manifest, it does not change the envelope or the key hierarchy | **None.** Additive |
| **H2** | WebAuthn attestation enforcement | Attestation is **stored at registration** from the first slice. Enforcing it later is a policy change over data already captured | **None**, because the blob is captured now |
| **H3** | Backup / export behaviour | Export is a separate capability. The envelope format and padding are already fixed | **None** |
| **H4** | Localized BIP39 wordlists | English wordlist pinned in v1; the mnemonic records its wordlist id | Low. A second wordlist is additive |

---

## 2. What is *not* deferrable

These are in the protocol because deferring them would ship a weaker system than
the documentation claims. They are listed here so nobody mistakes them for
register items.

| | Requirement | Why it cannot wait |
|---|---|---|
| **A1** | Staged `pk_rec` excluded from every verifier set | **Without it, D9 and D12 are both bypassable** by the attacker who initiates Path E. It is a security defect, not a decision |
| **AUTH-1** | Exactly one authoritative credential verifier per account, in every committed state | Enforced as a database constraint from the first schema script. Retrofitting it means auditing every write path |
| **Generation invariants** | Exactly one ACTIVE, at most one MIGRATING, per account | Same — filtered unique indexes from the first script |
| **A2** | `BE = 0` is never described as hardware backing | Terminology that becomes a false public claim if it leaks into documentation |
| **A5** | Destroy: the guarantee is the first transaction, not bulk erasure | Designing it the other way produces a lock-and-log failure at scale and a guarantee stated in the wrong place |
| **A8** | R3 is `GENERATION_UNRECOVERABLE`, not "degraded" | It determines what the UX promises a woman about entries she cannot get back |
| **A10** | BIP39 is an encoding; the seed derivation is not used | Ambiguity here changes the bytes that derive every key |
| **A12** | The malicious-server confidentiality claim depends on the client binary not being server-delivered | A standing constraint on architecture, not a decision |

---

## 3. Deferred by scope, not by uncertainty

| | Item | Standing instruction |
|---|---|---|
| **Connection architecture** | Care, sharing, reciprocal reminders | **Do not touch.** WLOS must be fully valuable with zero connections; Release 1 is the zero-connection product |
| **Public privacy wording** | *"We cannot read your journal."* | **Do not freeze.** Intended architectural property, pending verification against the shipped implementation. §10.3 of the protocol lists what may and may not be said in the meantime |
| **Today intelligence** | Derived context, suggestions | Depends on the Life / Context model. Not started |
| **Conversation / AI companion** | — | **Not to be implemented** |
| **Sensitive inference** | — | **Never.** The prohibited-inference list stands |

---

## 4. Triggers that reopen a deferred item

| Item | Reopens immediately if |
|---|---|
| **D12** | A web client is ever proposed, or the device-approval adapters cannot both ship |
| **D7 / KDF profiles** | Any code hard-codes Argon2id parameters instead of reading a profile row |
| **D7 / profile pickup** | **A second KDF profile exists.** A password change generates a fresh salt but reuses the profile her credential already names, because the only lookup that returns a profile is keyed by address and returns hers rather than the current one. Harmless while there is one profile; the moment there are two, a password change silently declines a strengthened profile, and the authenticated client needs a way to ask for the current one. Found while implementing the change-password slice and recorded here rather than left to be discovered by a profile rotation that appeared to do nothing |
| **P1 / pure-Dart Argon2id** | **A second crash in the Argon2id path, anywhere.** One occurred on 2026-09-24: the end-to-end tool died with an access violation (`0xC0000005`) inside an isolate named `argon2-0`, on Dart 3.12.2 / Windows x64, after 27 completed steps and roughly fifteen derivations in one process. It is recorded rather than explained, because it was **not reproduced**: 30 sequential and 40 concurrent derivations at the same parameters were clean, and an identical re-run of the whole tool completed. No user-facing path performs more than two derivations in a session, so nothing about it is known to reach a device. If it happens again — especially on a phone — the question it reopens is whether the pure-Dart implementation stays, and the `AeadCipher`-style swap that P1 already provides for the cipher does **not** cover the KDF |
| **A3** | Neither adapter can produce a non-syncable credential on a target device — then **E3b becomes unimplementable** and D12 resolves itself by elimination |
| **A7** | Generation recovery enters a slice |
| **H1 anti-rollback** | Any document claims integrity or completeness rather than confidentiality |
| **A12** | A web client, a server-delivered bundle, or an OTA JavaScript update path is proposed |

---

## 5. Review cadence

This register is reviewed **at the start of every slice**, and an item is either
carried, resolved, or promoted to a blocker. An item carried three slices without
its holding mechanism being built is escalated — that is the failure mode this
register exists to catch.

**Nothing in this register is a reason to stop implementing.**
