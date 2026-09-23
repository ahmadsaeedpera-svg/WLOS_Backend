# WLOS — Reset Authorization Protocol v1

**Revision 2 — technical reconciliation.** Supersedes revision 1 of this file in
full. Corrections to revision 1 are listed in §13; corrections to
`WLOS_CRYPTO_PROTOCOL_V1_FINAL.md` are listed in §14.

**Status:** specification under review. **No implementation, no migrations, no
tables, no application code, nothing committed.**

**Locked before this revision:** D8 = Model A · D9 = 24 hours · D10 = E3.
**This revision changes no locked decision**, and says so explicitly wherever it
recommends something adjacent to one.

**Still open:** D12 · D11 · D6 · D7.

---

## 0. What revision 2 changes

Revision 1 contained four defects that would have shipped a weaker protocol than
it claimed. Each is corrected below and each is listed in §13.

1. **A complete bypass of D9 and D12.** Revision 1 stored `pk_rec(k+1)` as
   pending material at Path E initiation without saying which verifier set Path
   R reads. An attacker who initiates Path E generates that key pair himself; if
   the server verified against pending keys he would sign a Path R proof
   immediately and skip the window and the approval entirely. §2.2, §5.3.
2. **`BE = 0` was used as though it evidenced hardware backing.** It does not.
   It is an anti-sync property, not an anti-extraction property. §3.
3. **Destruction was described as one atomic transaction over every record.**
   That is not implementable at scale and the guarantee was stated in the wrong
   place. §11.1.
4. **"No records are lost" in the reset-during-migration case was wrong.** It is
   true only if she still holds the *target* generation's recovery phrase, which
   she very often will not. §7.

---

## 1. D12 — defined precisely

D10 approved *"device approval where a signed-in device exists."* Specifying the
mechanics exposes a branch that changes what D10 is worth.

### 1.1 The two options

**E3a — enrolled-device approval is a fast path.**

```
  Path E initiated · new material STAGED · window opens (D9 = 24 h)
        │
        ├─ device APPROVES (signed) ─────────► commit immediately
        ├─ device DECLINES (signed), or any
        │  live session cancels      ────────► CANCELLED
        └─ no response by t+24 h     ────────► commit
```

**E3b — enrolled-device approval is a hard gate.**

```
  Path E initiated · new material STAGED · request enters AWAITING_APPROVAL
        │
        ├─ device APPROVES (signed) ─────────► commit immediately
        ├─ device DECLINES (signed), or any
        │  live session cancels      ────────► CANCELLED
        └─ no response by t+24 h     ────────► EXPIRED · reset does NOT complete
```

Under **E3b** the 24-hour figure stops being a delay and becomes a deadline.
Under **E3a** it remains a delay.

### 1.2 What each is, stated without flattery

| | **E3a** | **E3b** |
|---|---|---|
| Honest name | **E1 plus a high-visibility notification channel and a one-tap decline.** It is *not* a second factor — mailbox control alone still completes the reset | **E2, with a device-bound credential as the second factor.** Mailbox control alone is insufficient |
| What it adds over email-only | Push is noticed where email is not; decline is instant; the request is visible on a device the attacker does not hold | A cryptographic requirement the mailbox cannot satisfy |
| Failure mode | Attacker waits 24 h and wins if she does not look at her phone | She cannot reset when her only enrolled device is **lost, broken, flat, wiped, factory-reset, offline for a day — or has silently invalidated its approval key** (§3.7) |
| Residual route when it fails her | — | **Path R only.** Under D8 = Model A she may never have recorded a phrase, or may have lost it. Then the account is unrecoverable |
| Residual route when it fails against her | Path R, if she has the phrase; or she notices in-window | — |

**E3a is not a second factor, and this document never calls it one.**

### 1.3 The decision is about which loss you prefer

- **E3a** accepts that a compromised mailbox eventually yields the Life Record,
  in exchange for never locking a woman out of her own account.
- **E3b** refuses the mailbox-only takeover, in exchange for a real population of
  women who will permanently lose an account they still own.

Under D8 = Model A the journal is protected in **both** options: `wrap/pw/{k}` is
deleted at reset, and `wrap/recovery/{k}` cannot be opened by anyone who does not
hold the phrase. **D12 decides who reaches the Life Record, not the journal.**

### 1.4 What is common to both

Everything in §2–§12 holds under either option. **The proof in §3 is required for
approval in both** — under E3a to make an approval trustworthy enough to
short-circuit the window, and under E3b to make a gate mean anything.

> **A push notification is a delivery hint, not a proof.** Anyone who can reach
> the notification surface — the push provider, a shoulder-surfer at a lock
> screen, a notification mirror on a paired laptop, a malicious accessibility
> service — can see, and in some configurations act on, a notification. Approval
> must be a signature under a key the server can verify and the notification
> channel cannot produce.

---

## 2. Global authentication invariants

These bind every path in this document. They are stated once, here, because
revision 1 stated them per-path and the per-path statements did not agree.

### 2.1 AUTH-1 — one authoritative credential per account, always

> **Every committed database state contains exactly one authoritative
> `auth_secret` verifier for an account.**

There is never a committed state in which old and new authentication material
both authenticate a login. This holds across Path R completion (R2, R3), Path E
completion (E4) and an ordinary password change. Staged material is not on the
login path; see §2.2.

### 2.2 AUTH-2 — the staging boundary

> **Staged material is inert. It authenticates nothing, verifies nothing,
> decrypts nothing and is referenced by no record, until the single transaction
> that makes it authoritative commits.**

Concretely, for material staged at Path E initiation (E1):

| Staged item | Where it must **not** appear before E4 |
|---|---|
| `H(auth_secret')` | The login path. `usp_User_GetForLogin` reads the authoritative credential column only. Staging lives in the reset-request store, which the login path does not join |
| `pk_rec(k+1)` | **The Path R verifier set.** This is the bypass named in §0.1 |
| `wrap/pw/{k+1}`, `wrap/recovery/{k+1}` | Any unwrap path |
| generation `k+1` | **No generation row exists for `k+1` before E4.** Staging holds opaque blobs keyed to the reset request, not a generation. Nothing can reference a generation that does not exist |
| `DEK(k+1)` | Held only by the initiating client, in memory. If the reset is cancelled it is discarded and never existed anywhere else |

### 2.3 AUTH-3 — verifier sets are disjoint by purpose

| Operation | Verifier set |
|---|---|
| **Path R reset** (§5) | `pk_rec` of the **ACTIVE** generation **only** |
| **Generation recovery** (§8) | `pk_rec` of a **DORMANT** generation, **and an authenticated session in addition** |
| **Device approval** (§3) | `pk_dev` of an eligible, non-revoked device (§4.3) |
| Anything else | — |

A `pk_rec` in staging belongs to no set. A `pk_rec` of an ORPHANED generation
belongs to no set.

---

## 3. The device-approval credential

### 3.1 Eight concepts that revision 1 blurred

Revision 1 used these interchangeably. They are independent, and three of them
are claims rather than proofs.

| Concept | What it actually is | Proves hardware backing? | Proves not-synced? |
|---|---|---|---|
| **WebAuthn / FIDO2 platform credential** | A credential created through the WebAuthn ceremony with `authenticatorAttachment: "platform"`. A protocol object: credential ID, public key, AAGUID, flags, signature counter | **No** | No |
| **Platform attachment** | The authenticator is built into the client device rather than roaming. Reported by the client, not signed by the authenticator in the assertion | **No** | No |
| **`BE` — backup eligibility** | Flag bit 3 of `authenticatorData`. **Set at credential creation and immutable for that credential's life.** `BE = 1`: the authenticator may sync or back up the private key. `BE = 0`: it will not | **No** | **It is the authenticator's assertion that it will not.** Not a proof |
| **`BS` — backup state** | Flag bit 4. **Mutable.** `BS = 1` means the credential is *currently* backed up. `BS` can only be 1 where `BE = 1` | No | No — and `BE = 1, BS = 0` can become `BS = 1` later with no notice to us |
| **`UV` — user verification** | Flag bit 2. The authenticator asserts a verification gesture occurred — biometric, PIN, or device credential | No | No |
| **Hardware-backed key material** | The private key lives in a TEE, StrongBox or Secure Enclave and is non-exportable | This **is** the property. Nothing above evidences it | Implied — such a key cannot be exported, so it cannot sync |
| **Attestation** | A signature by a key *not* derived from the credential, chaining to a manufacturer root, asserting properties of the authenticator | **This is the only mechanism that evidences it**, and only where the platform provides it | Indirectly, via the key's authorization list |
| **Android Keystore / iOS Secure Enclave key** (the DBK path, §3.5) | A key generated directly in platform key storage, outside the WebAuthn ceremony | Attestation can evidence it on Android. On iOS, App Attest attests *the app*, not the key | **Structurally, not by assertion** — such keys cannot be exported or synced at all |

### 3.2 `BE = 0` is not hardware backing — stated so it cannot be repeated

```
  BE = 0        says  "this credential will not be synced or backed up"
                      ├─ it is an ANTI-SYNC property
                      └─ it is the authenticator's own claim

  hardware-backed says "the private key cannot be extracted from this device"
                      └─ an ANTI-EXTRACTION property

  These are ORTHOGONAL. A pure-software authenticator can report BE = 0.
  A synced iCloud Keychain passkey is Secure-Enclave-protected on each device
  AND reports BE = 1.
```

**What `BE = 0` buys WLOS, exactly:** the credential is not recoverable from the
platform account, so an attacker who takes her email account does not thereby
take the approval factor (§3.3). That is the property D12/E3b needs.

**What `BE = 0` does not buy:** any protection against malware or an attacker
holding the unlocked device. Threat **D** in §10 remains unprotected.

### 3.3 Why `BE = 0` matters at all

```
  her email account  =  her Google / Apple account
        │
        └─ also holds the synced passkey
                 │
                 └─ an attacker who takes the mailbox takes the factor too
                          │
                          └─ E3b degrades silently to E3a, with nobody told
```

A credential reporting `BE = 1` at registration is stored as a **convenience
credential** and is **not eligible to approve a reset** (§4.3). `BE` is immutable
per credential, so the registered value is re-checked on every assertion; a
mismatch is a protocol violation, rejected and recorded as a security event.

### 3.4 What `UV = 1` proves, and does not

`UV = 1` is the **authenticator's assertion**, inside signed data, that a
verification gesture occurred. Without attestation we cannot verify the
authenticator is honest about it. And on every mainstream platform UV is
satisfied by the **device unlock credential**, so:

> **`UV = 1` proves "someone who can unlock this device approved", not "the
> account owner approved".** An attacker holding the phone and its PIN satisfies
> it. This is threat **D**, and neither E3a nor E3b defends against it.

### 3.5 The DBK path — a separate mechanism, specified separately

Revision 1 described the raw-key path as *"signing the same context"*, which
implied WebAuthn's guarantees carried over. They do not. **The DBK path is not
WebAuthn and is specified here in full.**

**Why it is retained, and why it may be the primary mechanism rather than the
fallback:** the standard platform-authenticator APIs on both Android (Credential
Manager, into Google Password Manager) and iOS (`ASAuthorization`, into iCloud
Keychain) produce **synced** credentials — `BE = 1` — in the ordinary case. **A
`BE = 0` platform credential may not be obtainable at all through those APIs on
the versions WLOS targets.** A Keystore or Secure Enclave key, by contrast,
*structurally* cannot sync. **This must be verified on the target OS versions
before the protocol is locked** — §15, item A3 — and if it cannot be obtained,
DBK is the mechanism and WebAuthn is the convenience, not the reverse.

#### 3.5.1 DBK registration

```
  requires: an authenticated session AND current-password reauthentication

  1  CLIENT generates an ECDSA P-256 key pair in platform key storage
       Android  Keystore, StrongBox where available
                setUserAuthenticationRequired(true)
                setUserAuthenticationParameters(0, BIOMETRIC_STRONG | DEVICE_CREDENTIAL)
                setInvalidatedByBiometricEnrollment(true)
       iOS      Secure Enclave, kSecAttrTokenIDSecureEnclave
                access control .privateKeyUsage + .biometryCurrentSet

  2  CLIENT → GET  /devices/register/challenge      (session-authenticated)
  3  SERVER → { regChallengeId, nonce(32), expiresAt }   TTL 5 min

  4  CLIENT   reg_context = "WLOS/v1/dbk-register" ‖ accountRef ‖ deviceId
                          ‖ regChallengeId ‖ nonce ‖ SPKI(pk_dev)
                          ‖ platform ‖ claimed_key_properties
              sig_reg = ECDSA_P256_sign(sk_dev, SHA-256(reg_context))   low-S, raw r‖s

  5  CLIENT → POST /devices/register { pk_dev(SPKI DER), sig_reg, deviceId,
                                       attestation?, password reauth proof }

  6  SERVER   verify sig_reg under the SUBMITTED pk_dev
              → proof of possession at registration; blocks key substitution
              store pk_dev, deviceId, platform, claimed properties,
                    attestation blob if present, enrolledAt, enrolling credential
```

Step 6's self-signature is why registration cannot be used to enrol a public key
the client does not hold the private half of.

#### 3.5.2 DBK attestation — recorded, never enforced

| Platform | Available | What it evidences |
|---|---|---|
| Android | Key Attestation chain to a Google root | `attestationSecurityLevel` (`TrustedEnvironment` / `StrongBox`), and the key's **authorization list**, which includes `userAuthType` and `authTimeout` |
| iOS | App Attest | **The app binary and its genuineness — not the key.** It does not evidence Secure Enclave residency for this key |

Android's authorization list is the **only** server-verifiable evidence in the
whole protocol that a key requires user authentication — and it is
**registration-time evidence about the key's policy**, never use-time evidence
that a gesture happened.

Enforcement is refused for the reason in §4.2: under E3b a failed attestation on
a legitimate device means a permanently unrecoverable account.

#### 3.5.3 DBK user verification — the honest asymmetry

| | WebAuthn | DBK |
|---|---|---|
| Gesture occurred | `UV = 1` inside signed data — an authenticator claim the server can read | **Nothing.** There is no UV bit, and a client-set flag would be worthless |
| Server-verifiable handle | The `UV` flag | Android attestation's `userAuthType` / `authTimeout`, **at registration only** |
| Actual enforcement | Authenticator | **The OS, at signing time.** The key is unusable without a fresh authentication, because signing goes through a `BiometricPrompt`-bound `CryptoObject` (Android) or an `LAContext`-gated Secure Enclave operation (iOS) |

> **Stated plainly: under DBK the server cannot verify that user verification
> happened.** It can verify that the key was *created* requiring it, on Android
> with attestation, and nowhere on iOS. Enforcement is real but client-side.

#### 3.5.4 DBK verification of an approval

Identical `approval_context` to §4.1. Signature is **ECDSA P-256 over
`SHA-256(approval_context)`, low-S normalised, transmitted as raw 64-byte
`r ‖ s`** — never DER, to remove an encoding-malleability class entirely.

#### 3.5.5 DBK lifecycle — invalidation

Platform key storage invalidates or deletes keys on events WLOS does not
control:

| Event | Effect |
|---|---|
| New biometric enrolled (`setInvalidatedByBiometricEnrollment`) | Key **permanently invalidated** |
| Screen lock removed | Key invalidated |
| Factory reset | Key gone |
| App uninstalled / storage cleared | Key gone (Android). iOS keychain behaviour varies by version and must be pinned per target version before lock |
| OS migration to a new device | Key **not** transferred — this is the point of the mechanism |

On detecting `KeyPermanentlyInvalidatedException` or the iOS equivalent, the
client **must self-report**. The server marks the device `KEY_INVALIDATED`:
**not revoked** — she still holds the device — but **not eligible to approve**
until re-registered.

> **This is a silent lockout vector under E3b.** Her phone is fine; she added a
> fingerprint; the approval key is gone and nothing told her. The mitigation is
> §4.7: the device re-proves `sk_dev` on **every sign-in**, so invalidation
> surfaces within one sign-in rather than at the moment she needs a reset. Under
> E3b this re-proof is not an optimisation — it is what keeps E3b survivable.

#### 3.5.6 DBK revocation

Identical to WebAuthn credentials (§4.6): current-password reauthentication to
revoke; `pk_dev` marked revoked and **retained**, never deleted, so a late
signature is rejected as *revoked* rather than *unknown* and recorded as a
security event. The client deletes the platform key best-effort; a
revoked-but-present key is inert because the server rejects it.

#### 3.5.7 What DBK does not provide

**No clone detection.** WebAuthn carries a signature counter for exactly this;
DBK has none, because platform key storage exposes none. In practice neither
gives it — mainstream platform authenticators report a counter of 0 — but the
absence must be stated rather than assumed away.

### 3.6 Which mechanism, when

| Condition | Mechanism |
|---|---|
| A platform credential can be created with `BE = 0`, verified on the target OS version | **WebAuthn**, ES256 (COSE `-7`), `UV` required, `BE = 0` required, platform attachment |
| It cannot | **DBK**, §3.5 |
| Neither is available | **The device is not an eligible approver.** Under E3a the request falls to the plain window; under E3b, §4.6 |

Both are registered, tracked and revoked through the same device record, and
both sign the same `approval_context`. **They are not the same mechanism and the
security properties differ** — §3.5.3, §3.5.7.

### 3.7 Key material held by the enrolled device

| Held on device | What it is | Exportable | Used for |
|---|---|---|---|
| `sk_dev` | ES256 / P-256 private key, UV-gated, device-bound | **No** | Signing reset-approval assertions. **Nothing else** |
| `wrap/device/{deviceId}/{k}` | DEK(k) wrapped under a device-held KEK | server-stored blob, opened locally | Unlocking the journal without re-entering the password |
| cached `DEK(k)` | A plaintext key in app memory / secure storage | — | Decryption |
| session + refresh token | Opaque | — | API authorisation |

**`sk_dev` wraps nothing and decrypts nothing.** It is a signature key with one
context string. It is not the device KEK, it is not derived from the password, it
is not derived from the recovery entropy, and it cannot be reconstructed from
anything the server holds.

---

## 4. The approval exchange

### 4.1 Binding approval to the exact reset request

```
  staged_payload = { H(auth_secret'), wrap/pw/{k+1}, wrap/recovery/{k+1},
                     pk_rec(k+1), generation metadata }        ← INERT, §2.2

  fingerprint = SHA-256( resetRequestId ‖ "path-E" ‖ initiatedAt
                       ‖ accountRef ‖ H(staged_payload)
                       ‖ H(initiator_ip) ‖ H(initiator_user_agent) )

  approval_context = "WLOS/v1/reset-approval"
                   ‖ accountRef ‖ resetRequestId ‖ approvalChallengeId
                   ‖ nonce(32) ‖ fingerprint ‖ decision ‖ deviceId

  WebAuthn: challenge = SHA-256(approval_context)
  DBK:      sign SHA-256(approval_context) directly
```

- **`decision` is inside the signature.** An `approve` cannot be replayed as a
  `decline`, or the reverse.
- **`fingerprint` covers the staged payload.** An approval cannot be harvested
  for one reset and applied to another carrying different new credentials.
- **`deviceId` and `resetRequestId` are inside the signature.** Nothing carries
  between devices or between requests.

**What she is shown before she approves**, and it must not be softened:

> *Someone asked to reset your password using your email address. **They have
> already chosen a new password.** If you approve, they will be signed in and you
> will not. Requested ⟨time⟩ from ⟨coarse location⟩, ⟨browser / app⟩.*

### 4.2 Server-side verification material

| Server holds | Sensitivity |
|---|---|
| `deviceId`, `pk_dev`, `credentialId`, mechanism (WebAuthn / DBK), signature counter where present | Public. Harmless |
| `BE` / `BS` **recorded at registration**; `BE` re-checked on every assertion | Determines approval eligibility |
| `aaguid` + attestation statement where supplied | Recorded, **never gated on** |
| enrolment timestamp, enrolling-credential reference, revocation state, `KEY_INVALIDATED` state | Ordering and eligibility |
| the device label she chose, platform, last-seen | Shown to her when approving |

**Enrolment authorisation.** Registering any approval credential requires an
authenticated session **and** current-password reauthentication. The first device
is enrolled during registration under the credential that created the account.
**A mailbox alone can never enrol a device**, which is what stops an attacker on
Path E from enrolling his own approver.

**Attestation is recorded, not enforced**, per §3.5.2.

### 4.3 Which devices may approve

All of:

1. currently enrolled, **not revoked**, **not `KEY_INVALIDATED`**;
2. **enrolled strictly before** `resetRequest.initiatedAt`;
3. registered with **`BE = 0`** (WebAuthn) or as a **DBK** key;
4. the assertion carries **`UV = 1`** (WebAuthn). For DBK, §3.5.3 — the server
   cannot check this and the limitation is recorded rather than hidden;
5. **it is not the device that initiated the request.**

There is **no primary device**: designating one would create a single point of
permanent loss, which is the whole objection to E3b in miniature.

### 4.4 Freshness, single use, expiry, replay

| Property | Rule |
|---|---|
| Freshness | A 32-byte server nonce per `(resetRequestId, deviceId)` issuance, never reused, stored and compared |
| Single use | `approvalChallengeId` consumed **atomically on the first verification attempt, valid or not** |
| Expiry — approval challenge | **10 minutes** |
| Expiry — reset request | **24 hours** (D9). Under E3b also the approval deadline |
| Expiry — reset grant (Path R) | 5 minutes, single use |
| Expiry — DBK registration challenge | 5 minutes, single use |
| Replay | Consumed id, stored nonce, `resetRequestId` binding, TTL |
| Cross-context replay | Six disjoint context strings, §4.8 |
| Malleability | Low-S required; raw `r ‖ s`; a signature is never a key, id or dedupe token |

**Burning a challenge is not a denial of approval.** A device may request a fresh
challenge up to 10 times per reset request, and **cancellation never requires the
device key** (§4.5).

### 4.5 Cancellation and decline — deliberately asymmetric

**Approval is made as hard as possible; cancellation as easy as possible.** A
false decline costs her one retry. A false approval costs the Life Record.

| Action | Requires | Effect |
|---|---|---|
| **Cancel** | Any live authenticated session, or the emailed cancel token | Request → `CANCELLED`. No generation change, no wrapper change, no session revocation, staging discarded |
| **Signed decline** | An assertion with `decision = "decline"` | → `DECLINED`, **plus**: all devices and the mailbox notified, Path E locked 72 h, rotation prompted |
| **Path R completion** | Ed25519 proof of possession | Cancels any pending Path E |
| **Account deletion** | Its own authorisation | Cancels any pending reset |

> **The emailed cancel link protects against almost nothing.** Path E initiation
> requires clicking a link sent to the mailbox, so an attacker on Path E already
> holds the mailbox and receives the cancel link himself. **The cancellations
> that matter are a live session and a device decline.**

### 4.6 Conflicts, removal, and the last approver

| Situation | Resolution |
|---|---|
| Two devices approve | The **first verified assertion to commit** applies the reset; the second finds the request no longer approvable and receives the generic failure. One atomic transition — the generation change cannot apply twice |
| Approve and decline, both before commit | **Decline wins, unconditionally** |
| Decline arrives **after** commit | **It cannot undo the reset.** Treated as a compromise report: all sessions revoked, security stamp bumped, everything notified, Path E locked 72 h, rotation prompted. **She has lost the Life Record of that moment. She has not lost the journal** |
| Transport-layer race | Resolved by commit order on one row. The protocol guarantees exactly one terminal state, not an ordering of two independent network arrivals |
| A device is removed mid-request | Removal needs current-password reauthentication, so a mailbox-only attacker cannot strip approvers |
| **Last eligible approver removed or invalidated** | **E3a** — degrades to the plain 24-hour window. **E3b** — the request **fails immediately**, `EXPIRED / NO_ELIGIBLE_APPROVER`, rather than hanging for 24 hours; she is told her remaining route is Path R |

### 4.7 After a completed reset

| Item | Disposition | Reason |
|---|---|---|
| Sessions and refresh tokens | **All revoked at completion**, and the **security stamp is bumped in the same transaction** | §6.4, §9.4 |
| Device **enrolment** and `pk_dev` | **Survive** | The reset did not change which physical devices she holds. Destroying approval keys at reset would mean **an attacker's first successful reset strips the protection guarding his second** |
| `wrap/device/*/{k}` | **Deleted** on Path E | §9.4 |
| Cached `DEK(k)` on a device | Retained locally until that device discards it | **Not reachable by any server action.** §10.2 |
| Device re-link | On next sign-in the device proves `sk_dev` over a sign-in context — which is also how `KEY_INVALIDATED` is discovered, §3.5.5 | — |

**Stated so it is not mistaken for protection:** after an attacker completes a
Path E reset he holds the new password, and the new password lets him remove her
devices. Surviving enrolment helps *her* in the ordinary case. It is not a
defence once he is already in.

### 4.8 Separation from every other credential

| Credential | Material | Server-side verifier | Context string | Anything else? |
|---|---|---|---|---|
| **Password authentication** | `auth_secret` = HKDF(MASTER, `"WLOS/v1/auth"`) | `H(auth_secret)`, salted | — | No. Not a KEK; wraps nothing |
| **DEK encryption** | `KEK_password` = HKDF(MASTER, `"WLOS/v1/kek/pw"`) | **none — never leaves the device** | — | No |
| **Recovery-phrase reset** | `sk_rec(k)` = Ed25519 from HKDF(entropy, `"WLOS/v1/recovery/sign"`) | `pk_rec(ACTIVE)` only | `"WLOS/v1/recovery-reset"` | No. Authenticates no session |
| **Generation recovery** | the same `sk_rec(k)` | `pk_rec(DORMANT)` + a session | `"WLOS/v1/generation-recovery"` | **No.** Recovers a generation; does **not** reset the account |
| **Recovery wrapping** | `KEK_recovery(k)` = HKDF(entropy, `"WLOS/v1/kek/recovery"`) | **none** | — | No |
| **Device approval** | `sk_dev` | `pk_dev` | `"WLOS/v1/reset-approval"` | No. Signature-only |
| **Device registration** | `sk_dev` | the submitted `pk_dev` | `"WLOS/v1/dbk-register"` | No |
| **Session authentication** | opaque access + refresh token | hashed refresh token + security stamp | — | No. **A session never yields the DEK** |
| **Email reset token** | opaque single-use link token | hashed | — | Proves mailbox control only |
| **Reset grant** | opaque, 5 min, single use | hashed | — | One completion of one reset |

---

## 5. Path R — complete state machine

### 5.1 Three outcomes, not one

```
R0 · challenge issued
  proof      none — issued for any address, in constant time
  active     k · dormant unchanged · wrappers unchanged · sessions unchanged
  request    CHALLENGE_ISSUED · TTL 10 min
  notify     none — issuing on any address must not confirm an address exists
  cancel     n/a · completion n/a · fail  an unused challenge simply expires

R1 · proof verified  →  wrapper released
  proof      Ed25519 over "WLOS/v1/recovery-reset", verified against
             pk_rec(ACTIVE) ONLY (§2.3); challenge CONSUMED atomically
  active     k unchanged · dormant unchanged
  wrap/pw    unchanged — not yet
  wrap/rec   wrap/recovery/{k} RELEASED to the client, in this response only
  wrap/dev   unchanged · sessions unchanged
  request    VERIFIED · reset grant issued, 5 minutes, single use
  notify     all devices + mailbox: "your recovery phrase was used" — sent NOW,
             before completion, so an illegitimate use is visible immediately
  cancel     the grant may be abandoned; nothing has changed yet
  fail       invalid / expired / consumed / unknown → ONE generic failure

R2 · completion, wrapper opened   (the normal case)
  proof      the reset grant (consumed) + a client-supplied wrap/pw/{k}'
  active     k UNCHANGED — Path R never rotates
  dormant    unchanged
  wrap/pw    REPLACED by wrap/pw/{k}' under the new KEK_password
  wrap/rec   UNCHANGED — the phrase still works afterwards
  wrap/dev   RETAINED — the DEK did not change and the devices are still hers
  sessions   ALL revoked + security stamp bumped, in the commit transaction
  request    COMPLETED · also cancels any DESTROY_PENDING (§11.3)
  notify     all devices + mailbox
  cancel     not cancellable — the commit is atomic
  fail       grant expired → nothing changed; she repeats from R0

R3 · GENERATION_UNRECOVERABLE   (§6 — not "degraded")
```

**R1 releasing the wrapper only after verification** closes a real gap:
`wrap/recovery/{k}` is the target of any offline attack on the phrase. Serving it
to anyone who knows an email address would hand every attacker an offline oracle.
Releasing it only to a caller who has already proved possession costs the
legitimate holder nothing and gives an attacker nothing he did not have.

### 5.2 Path R proves possession of a specific generation

`pk_rec` is **per generation**, and the server holds one for every generation the
account has had. A Path R exchange therefore identifies *which* generation's
phrase was used — and §2.3 routes it accordingly.

### 5.3 An old phrase does not reset the account

```
  proof over pk_rec(ACTIVE)   ──► Path R reset · §5.1 · account + journal
  proof over pk_rec(DORMANT)  ──► generation recovery ONLY · §8 ·
                                   requires an authenticated session IN ADDITION
  proof over a STAGED pk_rec  ──► NOTHING. Not in any verifier set (§2.2)
```

The third line is the bypass from §0.1. Without it, an attacker who initiates
Path E holds `sk_rec(k+1)` — he generated it — and would sign an immediate Path R
proof, skipping D9's window and D12's approval entirely.

**Consequence for a woman who reset by email, later found her old phrase, and has
also lost her current password:** Path E first to regain the account, then
generation recovery. Two steps, in that order.

---

## 6. R3 — cryptographic data loss for generation k

### 6.1 Classification

Path R proof succeeded, so the entropy is correct. `wrap/recovery/{k}` did not
open — absent, truncated, or the AEAD tag failed.

> **This is cryptographic data loss for generation k.** It is not a degraded
> mode, not a partial success, and not a state from which recovery is expected.
> The key that opened those records is gone and no party — not she, not WLOS, not
> an operator — can derive it.

State code: **`GENERATION_UNRECOVERABLE`**.

### 6.2 Before declaring it — two mandatory steps

1. **Retry and verify the blob.** A transient decode or transport error must not
   burn a generation. The client re-fetches, re-verifies length and header, and
   retries the unwrap before classifying.
2. **Offer to abort.** Completing R3 deletes `wrap/pw/{k}` and creates a new
   generation. **If she has another device that still holds a cached `DEK(k)`,
   completing the reset *from that device instead* preserves access** — that
   device can re-wrap `DEK(k)` under the new password. She must be offered this
   before R3 is committed, in plain terms, because afterwards it is too late.

### 6.3 The transition, if she proceeds

```
R3 · completion as GENERATION_UNRECOVERABLE
  proof      the same reset grant; the client declares a new generation
  active     k → DORMANT · NEW ACTIVE k+1, fresh DEK, fresh recovery entropy
  dormant    k added
  wrap/pw    wrap/pw/{k} DELETED · wrap/pw/{k+1} created
  wrap/rec   wrap/recovery/{k} RETAINED as-is (Model A) — it is unopenable, and
             deleting it would destroy evidence of what happened
             wrap/recovery/{k+1} created
  wrap/dev   */{k} DELETED · */{k+1} lazily, on next sign-in
  sessions   ALL revoked + security stamp bumped
  request    COMPLETED_GENERATION_UNRECOVERABLE
  notify     all devices + mailbox, plus the in-app statement in §6.4
```

Generation k is marked `ORPHANED` only once nothing can open it (§7.4). While a
device somewhere may still hold `DEK(k)`, it remains `DORMANT`, because the
server cannot know.

### 6.4 What the UX must say, and must not

**Must say, all four:**

1. **Account recovery succeeded.** She is signed in and WLOS works normally.
2. **Her older encrypted entries still exist only if their ciphertext survived**
   on the server. The protocol cannot tell her more than that.
3. **They are currently inaccessible**, because the wrapper holding their key did
   not open.
4. **There is no promise of later recovery.** They become readable only if a
   valid wrapper and a matching credential still exist somewhere — for example a
   device that still holds a cached `DEK(k)`. If none does, they are
   **permanently unreadable**.

**Must not say:** "temporarily unavailable" · "we will try to recover these" ·
"contact support" — there is nothing support can do, and an operator who could
would contradict the entire architecture · "degraded" · any wording implying the
entries are merely locked rather than keyless.

---

## 7. Generation invariants, and four operation classes

### 7.1 The invariant, corrected

Revision 1 said *"exactly one ACTIVE at all times"*, which is false during any
multi-statement operation and unimplementable as written. The correct form:

> **Every committed database state contains, per account, exactly one **ACTIVE**
> generation and at most one **MIGRATING** generation.**

It is a **committed-state** invariant. It says nothing about intra-transaction
states, and it is the form a fitness test can actually assert.

Corollaries a test must not get wrong:

- **Records do not share a generation.** During migration some records name k and
  some name the target. That is legal and expected. The invariant is about
  generations, not about records being uniform.
- **Staged material is not a generation** (§2.2), so it cannot violate the
  invariant.

### 7.2 Four operation classes, which are not alike

| Class | Atomicity | Scale | Duration |
|---|---|---|---|
| **Generation-state transition** — ACTIVE→DORMANT, DORMANT→MIGRATING, →ORPHANED, insert new ACTIVE, and the E4 / R2 / R3 commits | **One database transaction.** A bounded, small number of rows | tens of rows | milliseconds |
| **Per-record migration** | **Not one transaction, and must never be described as one.** Decrypt and re-encrypt happen **on the client**; batches are uploaded and each batch is its own short transaction. Idempotent per record, resumable from a cursor | thousands of records | minutes to hours |
| **Local-device operations** — cache purge, key discard, re-wrap | **Not transactional at all.** Best-effort, eventually consistent, **may never happen** | — | unbounded |
| **Server-side destructive deletion** — §11 | **One transaction makes the generation permanently unopenable.** Bulk row erasure proceeds in **batches** afterwards | thousands of rows | first commit instant; erasure minutes |

> **No design in this protocol requires thousands of record migrations inside one
> database transaction.** Where a guarantee must be atomic, it is expressed as a
> small metadata transaction — §7.3, §11.1.

### 7.3 Migration is client-executed; only its boundaries are atomic

```
  start:     one transaction   DORMANT(k) → MIGRATING(k), target recorded
  body:      N batches         client decrypts under DEK(k), re-encrypts under
                               DEK(target), uploads; each batch its own
                               short transaction; cursor advanced
  end:       one transaction   MIGRATING(k) → ORPHANED(k)
```

Per-record idempotency means a dropped connection costs progress, not
correctness.

### 7.4 ORPHANED, defined

`ORPHANED` = **ciphertext may exist and no wrapper the server holds can open
it.** It is not a claim that no copy of the key exists anywhere — §10.2 makes
that claim impossible. Two sub-cases are distinguished by a `destroyedAt` marker;
see §11.2.

---

## 8. Generation recovery

### 8.1 The mechanism

```
  authenticated session  +  proof over pk_rec(k) · "WLOS/v1/generation-recovery"
        │
        ├─ server:  k → MIGRATING · target := the CURRENT ACTIVE · releases wrap/recovery/{k}
        ├─ client:  DEK(k) = unwrap(KEK_recovery(k), wrap/recovery/{k})
        ├─ client:  per record — decrypt under DEK(k), re-encrypt under DEK(target)
        └─ server:  cursor complete → k → ORPHANED
```

**The migration target is always the generation ACTIVE at migration start**,
recorded on the migration row. Intermediate generations are skipped entirely; she
never needs their phrases.

### 8.2 Concurrency

- A second generation recovery while one is MIGRATING: **refused**,
  `GEN_RECOVERY_BUSY`.
- A voluntary rotation while MIGRATING: **refused**, `ROTATION_BUSY`.
- **No cursor progress for seven days → MIGRATING reverts to DORMANT.** Records
  already migrated stay migrated; the remainder are still under `DEK(k)` and
  still recoverable with the same phrase. Without this, one abandoned migration
  blocks every future one.

### 8.3 A Path R reset during migration

**No effect.** Path R does not rotate, so the target is still ACTIVE and
migration continues.

### 8.4 A Path E reset during migration — see §9.6

This is the case revision 1 got wrong, and it is analysed on its own in §9.6
rather than asserted here.

---

## 9. Path E — complete state machine

### 9.1 Initiation requires mailbox control

Initiation requires clicking a link delivered to the mailbox. Without it, any
stranger holding an email address could put an account into a pending-reset state
and flood her devices with notifications.

### 9.2 E1 — what is staged, and what is emphatically not

The client generates, **locally**: a new password → `MASTER'` → `auth_secret'`
and `KEK_password'`; a fresh `DEK(k+1)`; fresh recovery entropy →
`KEK_recovery(k+1)`, `sk_rec(k+1)`, `pk_rec(k+1)`; and the wrappers.

**At E1, all of the following are true and each must be separately assertable:**

| | State at E1 |
|---|---|
| Generation **k** | **remains ACTIVE** |
| `wrap/pw/{k}`, `wrap/recovery/{k}`, `wrap/device/*/{k}` | **remain authoritative.** They are the only wrappers any client may use |
| The old password | **still authenticates.** It is the only credential that does |
| `H(auth_secret')` | **cannot authenticate.** It is in the reset-request store, which the login path does not read |
| `pk_rec(k+1)` | **is in no verifier set** (§2.2, §2.3). A Path R proof over it fails |
| Generation **k+1** | **does not exist.** No generation row, no state, nothing can reference it |
| `DEK(k+1)` | exists **only in the initiating client's memory** |
| Sessions | **unchanged** — §9.4 |
| The staged payload | **staged only.** It becomes authoritative at E4 and at no earlier moment |

> **The staged payload is opaque bytes plus one password verifier, held in a
> store that no authentication or decryption path joins.** That is what makes
> "staged" a security property rather than a description.

### 9.3 Transitions

```
E0 · initiation link requested
  proof      an email address only
  active     k · dormant unchanged · all wrappers unchanged · sessions unchanged
  request    NONE
  notify     a link to the mailbox. NO device notification yet — otherwise anyone
             knowing her address could buzz her phone at will
  fail       silently identical for unknown addresses

E1 · link clicked, new material STAGED          (§9.2)
  proof      the single-use mailbox token, consumed
  request    created. ANY existing request → SUPERSEDED, same transaction (§12.2)
             staged_payload stored · fingerprint computed
             state = AWAITING_APPROVAL if an eligible device exists (§4.3),
                     otherwise AWAITING_WINDOW
  notify     every device (push + in-app) AND the mailbox, immediately
  cancel     any live session · the emailed cancel token · a signed decline
  fail       token expired or consumed → generic failure, no request created

E2a · device APPROVES                          [E3a and E3b]   → commit, E4
E2b · device DECLINES                          [both]
        → DECLINED · staging discarded · nothing else changes ·
          all notified · Path E locked 72 h · rotation prompted
E2c · she cancels from a live session          [both]
        → CANCELLED · staging discarded · nothing else changes
E2d · no response by t+24 h
        E3a → commit, E4
        E3b → EXPIRED · staging discarded · nothing changes · all notified

E3  · AWAITING_WINDOW reaches t+24 h  [no eligible device existed at E1]
        → commit, E4, under BOTH options. D12 is only about the device case

E4  · COMMIT — §9.4
```

### 9.4 E4 — the atomic activation

One transaction. It takes an update lock on the account credential row **first**,
which is what serialises it against a concurrent R2 / R3 commit.

```
BEGIN TRANSACTION
  lock and re-read the account credential row
  assert  request state is commit-eligible          (else abort, no change)
  assert  generation k is ACTIVE
  assert  no generation row exists for k+1

  INSERT  generation k+1, state = ACTIVE
  UPDATE  generation k       : ACTIVE → DORMANT
  UPDATE  credential         : H(auth_secret) := staged H(auth_secret')   ← AUTH-1
  INSERT  wrap/pw/{k+1}, wrap/recovery/{k+1}, pk_rec(k+1)
  DELETE  wrap/pw/{k}
  DELETE  wrap/device/*/{k}
  UPDATE  refresh tokens     : all revoked
  UPDATE  security stamp     : bumped                                     ← §9.5
  UPDATE  request            : COMPLETED · staging cleared
  CANCEL  any DESTROY_PENDING                                             (§11.3)
  MARK    any MIGRATING generation                                        (§9.6)
COMMIT
```

**The credential is set exactly once, in the same transaction that flips the
generations and revokes the sessions.** Before the commit only the old
`auth_secret` authenticates; after it, only the new one. **There is no committed
state in which both are valid** — AUTH-1, §2.1.

Row counts are bounded and small: one credential row, two generation rows, three
wrapper inserts, a handful of deletes, and a session sweep. This is a §7.2
class-one operation. **No record ciphertext is touched at E4.**

If the staged payload fails structural validation, the transaction **aborts
whole**. There is no half-applied reset.

### 9.5 The security stamp — why revocation is not otherwise instant

Revoking refresh tokens kills renewal. It does **not** kill an access token
already issued, which lives up to 15 minutes. Bumping the security stamp in the
same transaction is what invalidates those, through the existing
security-stamp validation in `Maren.Infrastructure`.

> **Residual exposure is bounded by the stamp-validation cache TTL, not by zero.**
> If that validation is cached, an attacker's — or her — already-issued access
> token survives for the cache lifetime after a reset completes. **The TTL must
> be named before lock**; it belongs with the revocation-cache item already
> carried from Slice 1.

### 9.6 A Path E reset during a migration — three options compared

Revision 1 asserted Option A and claimed *"nothing is lost"*. **That claim was
wrong**, and the correction is the reason this section exists.

**Why a split happens at all:** migration moves records *into* the generation
that a Path E reset is about to retire. Rolling the migration back would require
`DEK(k)` on the server, which it must never hold. So once any record has moved,
retiring the target splits them — **unless the migration never writes live
records until it is complete.** That is the whole design space.

#### Option A — permit, with `MIGRATION_STALE` (revision 1)

The reset completes; the migration halts; k reverts to DORMANT; already-migrated
records remain in the target, which E4 has just made DORMANT.

#### Option B — serialize: the reset may not complete while MIGRATING

**As literally stated, Option B does not work**, and this must be said rather
than papered over:

- If the reset **waits**, it waits past D9's 24 hours. Under E3b it is guaranteed
  to expire. Under E3a it breaks the window's meaning. If the migration is
  stalled, the wait is **seven days** (§8.2) — and she is locked out, so she
  cannot cancel the migration, because cancelling needs the session she has lost.
- If the reset **refuses**, a locked-out woman is told to come back in a week.
- If the reset instead **force-reverts** the migration, that is Option A with
  extra steps: the already-migrated records still sit in the target, and the
  target is still retired.

#### Option C — staged migration with an atomic commit marker

Migration writes re-encrypted records into a **staging area**, not over the live
records. Live reads never consult staging. At the end, **one transaction sets one
flag** — the migration's commit marker — after which the staged envelopes are
authoritative; a background job then collapses staging into the main store and
deletes the originals.

A Path E reset during migration **discards the staging**. Generation k is
untouched, still whole, still DORMANT, still openable with its one phrase. She
re-runs the migration later into the new ACTIVE.

#### The comparison

| | **A — permit + stale** | **B — serialize** | **C — staged + commit marker** |
|---|---|---|---|
| **Correctness** | Sound. No record becomes unopenable *by the protocol* | Sound, but **only if the wait is unbounded**, which it cannot be | Sound. The reset and the migration are independent |
| **Recoverability** | **Two phrases needed**: k's and the target's. ⚠ The target's phrase was issued at a *previous* Path E initiation and labelled provisional (§9.2). **If she did not record it, the migrated records are permanently unopenable — real data loss** | n/a | **One phrase, k's.** Nothing new is required of her |
| **Concurrency complexity** | Highest. Needs `MIGRATION_STALE`, stale detection, target tracking, and a three-way interaction test | Needs a wait state with a deadline that conflicts with D9 | Low. Staging is discarded; no new generation state |
| **Possible generations** | **Grows unboundedly** — every reset-during-migration adds one more dormant generation to a lifelong account | Unchanged | **Unchanged** |
| **User-visible complexity** | High: *"your journal is in three places, each needing a different phrase"* | A lockout she cannot act on | Low: *"that recovery didn't finish; start it again"* |
| **Failure / restart** | Cursor must be preserved to know what moved | — | Restart from zero. **Work is wasted, nothing is at risk** |
| **Implementation / test** | The hardest case in the protocol | Simple to write, wrong to ship | Moderate: a staging table, a commit marker, and a read-path branch during a bounded window — all directly testable |
| **Cost** | — | — | **Double storage for the duration of a migration**, and a read-path join until collapse completes |

#### Recommendation

> **Option C produces the cleaner v1 protocol.** It removes `MIGRATION_STALE`,
> removes the split, removes unbounded dormant-generation growth, and removes the
> only case in this protocol where WLOS can cause permanent data loss *through
> its own design* rather than through lost credentials. Its costs — transient
> double storage and a bounded read-path branch — are ordinary and testable.
>
> **Option B should be rejected outright**, because every concrete form of it
> either locks a woman out for up to seven days or collapses into Option A.

**This recommendation changes no locked decision.** D8, D9 and D10 are untouched:
Option C changes how a *migration* is staged, not what a reset does, how long it
waits, or what approves it. It is a recommendation, not a change — **§9.6 is
recorded as open** in §15.

---

## 10. The v1 threat boundary

### 10.1 The security-property matrix

| Property | v1 | Precisely |
|---|---|---|
| **Journal confidentiality — honest-but-curious server** | **YES** | The server holds ciphertext and public keys. No server-held material derives any KEK or DEK |
| **Journal confidentiality — malicious server** | **YES, conditionally** | It never holds a KEK or DEK, so it cannot decrypt what it stores. **This depends entirely on the client binary not being delivered by the server.** WLOS ships through app stores; a malicious server cannot substitute code. **If a web client is ever added, this answer becomes NO** |
| **Ciphertext integrity (per record)** | **YES** | XChaCha20-Poly1305 with `AD = recordId ‖ version ‖ schemaVersion`. Tampering with a stored record is detected on decryption |
| **Deletion detection** | **NO** | A server that deletes records is indistinguishable from a server that never had them. No client-side manifest, no signed state |
| **Rollback detection** | **NO** | `AD` binds a version number, so serving an older version of a record *is* detectable — but only by a client that already knows the expected version, and in v1 the client has no trustworthy source for that expectation. Net: not provided |
| **Public-key substitution detection** | **NO** | `pk_rec` and `pk_dev` are stored by the server and never verified out of band. **A malicious server can replace them with keys of its own and thereby seize the account, forge approvals, and take the Life Record. This is the largest gap in the malicious-server model** |
| **Server-side availability** | **NO** | The server can refuse to serve, and a client without a local copy cannot read the record |
| **Device compromise protection** | **NO** | Cached DEK, live session, device wrapper, and — if unlocked — the approval key. §3.4 |
| **Email compromise protection** | **Journal: YES. Account and Life Record: DEPENDS ON D12** | E3a: no. E3b: yes, unless she approves |
| **Recovery-phrase compromise protection** | **NO** for the current generation; **PARTIAL** for a superseded one | §5.3 |
| **Forward secrecy** | **NO** | Rotation is not forward secrecy. A compromised `DEK(k)` exposes every record ever written under k |

### 10.2 The sentence that governs every future document

> ## "The server cannot decrypt" is not "the server cannot manipulate."
>
> WLOS v1 provides **confidentiality** of journal plaintext against the server.
> It provides **no integrity of the collection**, **no availability guarantee**,
> and **no detection of key substitution**. A malicious server cannot read her
> journal. It can delete it, withhold it, roll it back, and take her account.

And its companion:

> **Rotating or changing a key cannot revoke plaintext, ciphertext or key
> material that has already been copied to a device or to attacker-controlled
> storage.**

- An attacker who copied `wrap/recovery/{k}` and holds the phrase for k keeps
  `DEK(k)` **forever**, however often she rotates afterwards.
- A device that cached `DEK(k)` keeps it until that device discards it. Session
  revocation does not remove it, and no mechanism can.
- **"Destroy earlier entries" deletes the server's copy. It does not delete
  his.**

### 10.3 Approved and forbidden phrasings

| A future document **may** say | A future document **may not** say |
|---|---|
| "We cannot read your journal." | "Your journal is safe." |
| "Your journal is encrypted with a key only your devices hold." | "Your data cannot be tampered with." |
| "Even we cannot decrypt your entries." | "Even we cannot touch your entries." |
| "Resetting by email does not give anyone your journal." | "Resetting by email is safe." |
| "Rotating your key protects entries written from now on." | "Rotating your key makes old entries unreadable to anyone who copied them." |
| "Destroying earlier entries removes them from our servers." | "Destroying earlier entries makes them gone everywhere." |

**Pending verification:** *"We cannot read your journal"* remains an intended
architectural property, not yet frozen as a marketing claim — carried forward
unchanged from the standing instruction.

---

## 11. "Destroy earlier entries"

### 11.1 The atomicity correction

Revision 1 said the operation *"deletes the recovery wrapper and the encrypted
records atomically."* Deleting a lifetime of records in one transaction is a lock
and log problem, not a design. The guarantee belongs in a different place:

```
  TRANSACTION 1  (atomic, small, bounded — this is the whole user-facing guarantee)
      DELETE  wrap/recovery/{k}
      DELETE  pk_rec(k)
      DELETE  wrap/device/*/{k}
      SET     generation k : destroyedAt := now, state := ORPHANED
    ─► FROM THIS COMMIT ONWARD THE GENERATION IS PERMANENTLY UNOPENABLE.
       What remains is ciphertext no party can decrypt.

  THEN  batched erasure of generation k's records, each batch its own
        transaction, run to completion and verified; a residual-row check
        asserts zero remaining
```

**The user-visible promise — "no one can open these again" — is satisfied at the
first commit.** Physical erasure follows and is verified; it is a storage
obligation, not the security boundary.

### 11.2 The other six properties, confirmed

| # | Property | Confirmed |
|---|---|---|
| 1 | **Cannot target a MIGRATING generation** | ✔ `GEN_BUSY`. **Nor the ACTIVE generation** — destroying what she is writing into is not what the operation means |
| 2 | **Requires current-password reauthentication** | ✔ Never a session. A session is strictly weaker than a password; the platform precedent is `usp_User_GetLoginMaterial` |
| 3 | **Atomic server-side** | ✔ As corrected in §11.1 |
| 4 | **Cannot be undone with its recovery phrase** | ✔ The phrase still derives `KEK_recovery(k)`, but there is no wrapper and no key. **The phrase becomes inert.** A proof over `pk_rec(k)` now fails with the **same generic failure** as every other Path R failure, so it is not an oracle for which generations were destroyed |
| 5 | **Local device copies are best-effort** | ✔ A purge instruction is pushed and applied on next connection. **A device that never reconnects keeps its copy; an export already made is outside the protocol.** Told to her in those words |
| 6 | **Does not affect other DORMANT generations** | ✔ Scoped to one `generationId`. **No bulk destroy in v1** |

**End state.** A tombstone row — id, `destroyedAt`, record count at destruction,
no content — distinguishes the two meanings of ORPHANED:

| | Meaning | Told to her as |
|---|---|---|
| ORPHANED, no `destroyedAt` | The wrapper was lost; ciphertext may survive, unopenable | *"This cannot be opened."* |
| ORPHANED, with `destroyedAt` | She destroyed it deliberately | *"You destroyed this on ⟨date⟩."* |

### 11.3 D11 — re-audited independently of D9

**D9 and D11 do not share a threat model, and D11 must not inherit 24 hours by
analogy.** D9 delays an attacker *gaining* access. D11 delays her *losing data* —
and simultaneously blocks an erasure she may urgently need.

| Situation | Does a delay help? |
|---|---|
| **Stolen session** | **Irrelevant.** Destroy requires the current password. A session cannot destroy at all |
| **Stolen current password** | **Helps.** He can destroy; the window lets her cancel — if she notices, via device and mailbox notification. Note he already holds the DEK, so he can read everything first: **destruction is vandalism or coercion, not exfiltration** |
| **Compromised enrolled device** | **Helps only partially.** If he also has the password, as above; the window is useful only if she can reach another surface to cancel from |
| **Compromised mailbox** | Cannot destroy directly. **But it chains:** mailbox → E4 → he holds the password → destroy. The delay adds a second window on top of D9's, so she has up to 48 h of notice. **Helps** |
| **Attacker who can initiate but not cancel** | **The delay works against him.** Re-initiating **restarts** the window (§12.3's rule, applied here), so he can never shorten it, and she can always cancel from any live session |
| **Accidental user action** | **The strongest argument for a delay.** Years of journal, one tap, irreversible. A window is a plain undo |
| **She changes her mind** | Same — and sharper: she may destroy in distress, which is precisely the population WLOS exists for. **This is a safety argument before it is a security one** |
| **Recovery during `DESTROY_PENDING`** | Recovering generation k **cancels the destruction** — she has plainly changed her mind. Recovery of a *different* generation is unaffected |

**The argument against a delay, which has no analogue in D9:**

> A woman destroying entries because someone is about to gain access to her phone
> needs them **gone now**. A 24-hour delay means they are not gone when she needs
> them gone. In an intimate-partner-surveillance scenario — squarely within
> WLOS's population — a mandatory delay is the wrong answer, and it is the
> **only** row in the table that points the other way.

**Recommendation, offered as a recommendation and not a lock:**

**Two operations, not one.**

| | Delay | Confirmation | For |
|---|---|---|---|
| **Destroy earlier entries** | **24 h**, cancellable from any live session; re-initiating restarts it | Current-password reauthentication | The default. Protects the accidental and the regretted |
| **Destroy immediately** | **None** | Current-password reauthentication **and** typing the generation's date range | The urgent case. Explicitly labelled irreversible and immediate |

A shorter single default — one hour — is the middle road: it preserves an undo
while barely blocking urgency. **It is worth considering instead of two
operations if the second path's discoverability is a concern.**

**D11 = PENDING USER DECISION.**

---

## 12. Reset-request concurrency

### 12.1 How many requests

| Count | Permitted |
|---|---|
| **Zero** | Yes — the normal state |
| **Exactly one**, in `INITIATED` / `AWAITING_APPROVAL` / `AWAITING_WINDOW` / `COMMITTING` | Yes |
| **Two or more** | **Never** |

Enforced as a single-active-request uniqueness rule **in the database**, not in
the application layer — a rule enforced in C# is a rule the next caller bypasses.

### 12.2 Supersede is atomic

Creating a new request supersedes the old one **inside the same transaction**:
old → `SUPERSEDED`, its staging discarded, its approval challenges invalidated,
the new request written. **There is never an instant at which two live requests
exist, and never an instant at which an approval could be applied to staging that
was just replaced.**

### 12.3 Superseding restarts the window; it never shortens it

- **An attacker can never shorten a window** by re-initiating.
- **Every re-initiation gives her a fresh full window** in which to notice.
- An attacker who keeps re-initiating never completes anything. He denies
  himself.

### 12.4 Sessions are revoked at completion, never at initiation

- Revoking at initiation would hand any attacker reaching the initiation endpoint
  a free **"sign every one of her devices out"** primitive.
- It would destroy **her single most reliable way to cancel**, at the moment she
  needs it.
- It would remove the live sessions that make device approval possible at all,
  turning every E3b request into an immediate `NO_ELIGIBLE_APPROVER` failure.

**Revocation is a consequence of a reset, not a step toward one.**

### 12.5 Rate limiting

| Surface | Limit |
|---|---|
| Path E initiation, per account | 5 / hour, 20 / day |
| Path E initiation, per IP | 20 / hour |
| Approval challenge issuance, per request per device | 10 |
| Verification attempts, per challenge | **1** |
| Signature-verification failures, per account | 10 / day, then the approval path locks 24 h |
| Push deliveries, per request per device | 1 initial + 3 reminders (t+1 h, t+6 h, t+20 h) |
| Cancel-token use | 1 |

**Under E3b, locking the approval path locks the reset** — fail-closed and
correct, and also a denial-of-service primitive. The failure counter must be
keyed to *verified-device* attempts wherever possible, and the lock must be
surfaced to her rather than silent.

---

## 13. Recovery-phrase terminology, pinned

> **128-bit recovery entropy from a CSPRNG, encoded as a 12-word BIP39 mnemonic.**

**BIP39 is used as an encoding only.** Explicitly:

| | v1 |
|---|---|
| CSPRNG, 128 bits | **Used.** This is the credential |
| BIP39 English wordlist + checksum | **Used**, for transcription and typo detection. The checksum is the entire reason to use BIP39 rather than raw hex |
| **BIP39 seed derivation** — PBKDF2-HMAC-SHA512, 2048 iterations, salt `"mnemonic" ‖ passphrase` | **NOT used.** No part of it |
| BIP39 passphrase / "25th word" | **Not used** |
| BIP32 / SLIP-0010 hierarchical derivation | **Not used** |
| What consumes the entropy | The raw 128 bits, fed directly into **HKDF-SHA256** under WLOS domain labels — `"WLOS/v1/kek/recovery"`, `"WLOS/v1/recovery/sign"` |
| Wordlist | **English only in v1.** A localized wordlist changes the encoding and must be pinned before it ships |
| Input normalisation | NFKD, lowercase, single-space-joined before word lookup. Pinned, because it changes which words parse |

> **"BIP39" in WLOS means the wordlist and its checksum. It does not mean the
> BIP39 key derivation, and no WLOS key is a BIP39 seed.**

---

## 14. Corrections

### 14.1 To revision 1 of this document

| # | Revision 1 | Correction |
|---|---|---|
| 1 | Staged `pk_rec(k+1)` stored, verifier set unstated | **Excluded from every verifier set.** Otherwise a Path E initiator signs an immediate Path R proof and bypasses D9 and D12 entirely — §2.2, §5.3 |
| 2 | `BE = 0` treated as evidence of hardware backing | **It is an anti-sync property, not an anti-extraction one.** §3.1, §3.2 |
| 3 | Raw ECDSA described as "the same context" as WebAuthn | **A separate mechanism with its own registration, verification, UV story, lifecycle and revocation** — §3.5. It cannot prove UV to the server and has no clone detection |
| 4 | A `BE = 0` platform credential assumed obtainable | **It may not be, on either platform.** Must be verified on target OS versions; DBK may be the primary mechanism — §3.5 |
| 5 | "exactly one ACTIVE at all times" | **A committed-state invariant** — §7.1. And records do not share a generation during migration |
| 6 | Destroy "deletes the wrapper and every record atomically" | **One small transaction makes the generation unopenable; erasure is batched** — §11.1 |
| 7 | Reset during migration: "nothing is lost" | **Wrong.** Lost if she lacks the target generation's phrase, which was issued provisionally at a previous initiation — §9.6. Option C recommended |
| 8 | R3 called "degraded" | **`GENERATION_UNRECOVERABLE` — cryptographic data loss**, with a mandatory retry, an abort offer, and four things the UX must say — §6 |
| 9 | E4 revoked sessions; the security stamp was unmentioned | **Bumped in the same transaction**, or access tokens outlive the reset by up to 15 minutes — §9.5 |
| 10 | BIP39 referenced without scope | **Encoding only; the seed derivation is explicitly not used** — §13 |
| 11 | E1 staging semantics implicit | **Enumerated and separately assertable** — §9.2 |
| 12 | Security claims prose-only | **A property matrix**, plus approved and forbidden phrasings — §10 |

### 14.2 To `WLOS_CRYPTO_PROTOCOL_V1_FINAL.md`

| # | That document | Correction |
|---|---|---|
| 1 | Case G: *"attacker knows the recovery phrase → everything"* | True only of the **current** generation's phrase — §5.3 |
| 2 | Path R: one outcome | **Three** — R2, R3 (§6), and generation recovery, which is not a reset |
| 3 | `wrap/recovery/{k}` release unspecified | Released **only after** proof of possession — §5.1 |
| 4 | Path E new material set at completion | **Staged at initiation** — §9.2 |
| 5 | E3 approval arriving "via notification" | A notification is a delivery hint; approval is a signature — §3, §4 |
| 6 | Device wrappers on Path R unstated | **Retained** on Path R, **deleted** on Path E |
| 7 | Migration target under later rotations unstated | Always the generation ACTIVE at migration start — §8.1 |
| 8 | Stalled migration unhandled | Seven days without progress → DORMANT — §8.2 |
| 9 | Emailed cancel link implied a safety net | It is not — §4.5 |
| 10 | Threat model prose | §10.1 supersedes it |

---

## 15. Fitness tests

| Test | Asserts |
|---|---|
| **Staged keys are inert** | A Path R proof over a staged `pk_rec` fails; staged `H(auth_secret')` never authenticates; no record can reference a staged generation |
| **AUTH-1** | No committed state has two valid `auth_secret` verifiers for one account |
| **E4 atomicity** | Credential change, generation flip, wrapper deletes, revocation and stamp bump share one transaction; a forced failure leaves the account exactly as it was at E1 |
| **Security stamp bumped at E4 / R2 / R3** | An access token issued before the reset fails after it, within the named cache TTL |
| Approval requires a signature | No path completes a reset on a notification acknowledgement, a session, or any non-assertion input |
| `BE = 0` enforced | A credential registered backup-eligible is never eligible to approve; a `BE` mismatch between registration and assertion is rejected and recorded |
| `UV = 1` enforced (WebAuthn) | An assertion without user verification is refused |
| **DBK registration self-signature** | A registration whose `sig_reg` does not verify under the submitted `pk_dev` is refused |
| **`KEY_INVALIDATED` surfaces at sign-in** | A device whose platform key was invalidated is not an eligible approver, and is discovered at the next sign-in, not at reset time |
| Context separation | Each of the six context strings verifies in exactly one operation |
| Approval binds the payload | An assertion for request X fails for request Y, and fails if the staged payload changed |
| Decline precedence | A decline before commit always beats a concurrent approve |
| Self-approval refused · post-initiation enrolment refused | §4.3 |
| Single active request · supersede atomic | Two live requests for one account is unreachable |
| Sessions revoked at completion | No path revokes at initiation |
| **Committed-state generation invariant** | Every commit leaves exactly one ACTIVE and at most one MIGRATING — asserted after each transaction, never mid-transaction |
| **Records may span generations** | A migration in progress does not violate any invariant |
| At most one MIGRATING | A second concurrent generation recovery is refused |
| Wrapper release gated | `wrap/recovery/{k}` is unreachable without a verified proof |
| **Destroy first-transaction guarantee** | After transaction 1, no credential in the system opens generation k, whatever the erasure job has done |
| Destroy scoping · atomicity · cannot target ACTIVE or MIGRATING | §11 |
| Path R failure uniformity | Unknown account, expired, consumed, bad signature and destroyed generation return one identical response |
| **BIP39 scope** | No code path performs BIP39 seed derivation; entropy reaches HKDF directly |

---

# A. Corrections required before crypto lock

| | Item | Kind |
|---|---|---|
| **A1** | **Staged `pk_rec` excluded from the Path R verifier set.** Without it, D9 and D12 are both bypassable by the attacker who initiates Path E — §2.2, §5.3 | **Security defect.** Must be in the spec before lock |
| **A2** | **`BE = 0` must never be described as hardware backing** anywhere in this protocol or any document derived from it — §3.2 | Terminology, load-bearing |
| **A3** | **Verify on the target OS versions whether a `BE = 0` platform credential is obtainable at all.** If it is not, DBK (§3.5) is the mechanism and WebAuthn is the convenience. **This cannot be settled from documentation and requires devices** | **Measurement.** Blocks the §3.6 choice |
| **A4** | **The DBK path is fully specified separately (§3.5) and its two gaps recorded**: the server cannot verify UV, and there is no clone detection | Done here; must survive into implementation |
| **A5** | **Destroy: the guarantee is transaction 1, not bulk erasure** — §11.1 | Corrected here |
| **A6** | **Generation invariant restated as a committed-state invariant**, with per-record migration explicitly outside it — §7.1, §7.2 | Corrected here |
| **A7** | **Decide §9.6.** Option C recommended; Option B rejected; Option A carries a real data-loss case. **This is open and is not a locked decision** | **Open design question** |
| **A8** | **R3 is `GENERATION_UNRECOVERABLE`**, with the mandatory retry, the abort offer, and the four required UX statements — §6 | Corrected here |
| **A9** | **Name the security-stamp validation cache TTL.** Until it is named, "sessions are revoked" is true only up to that TTL — §9.5 | **Open value.** Carries the Slice 1 revocation-cache item |
| **A10** | **BIP39 is an encoding; the seed derivation is not used** — §13 | Corrected here |
| **A11** | **Public-key substitution is undetectable in v1** and must appear in any statement about a malicious server — §10.1 | Disclosure |
| **A12** | **The malicious-server confidentiality claim depends on the client binary not being server-delivered.** If a web client is ever added, the claim must be withdrawn — §10.1 | Standing constraint |

---

# B. D12 — the decision

## E3a — enrolled-device approval is a **fast path**

A signed approval commits the reset immediately. **No response within 24 hours
commits it anyway.**

| | |
|---|---|
| **Security consequence** | Mailbox control alone still yields the account and the Life Record. The device adds a **high-visibility channel and an instant decline**, not a barrier. **It is not a second factor** |
| **Recovery consequence** | **No lockout is introduced.** Every woman who controls her mailbox can always recover her account |
| **Journal** | Unaffected. Protected under both options |
| **Honest one-line description** | *"We tell your phone loudly, and you can stop it with one tap."* |

## E3b — enrolled-device approval is a **hard gate**

A signed approval commits the reset. **No response within 24 hours fails it.**

| | |
|---|---|
| **Security consequence** | Mailbox control alone is **insufficient**. A genuine second factor, subject to §3.2 and §3.4: it resists a mailbox attacker; it does **not** resist someone holding her unlocked phone |
| **Recovery consequence** | **A real lockout class.** Her only enrolled device lost, broken, flat, wiped, offline for a day, or silently `KEY_INVALIDATED` (§3.5.5) → **no reset at all.** Her remaining route is Path R, and under D8 = Model A she may never have recorded a phrase. **Then the account is gone** |
| **Journal** | Unaffected |
| **Prerequisites that become mandatory** | A3 must resolve in favour of an obtainable device-bound credential, **and** the §3.5.5 sign-in re-proof must ship, or E3b's lockout rate will be driven by silent key invalidation rather than by lost phones |
| **Honest one-line description** | *"Your phone must say yes. If it can't, nobody can."* |

**The trade is not security against convenience. It is one population's exposure
against another population's permanent loss**, and only you can weigh which of
those WLOS should prefer.

---

# C. Decision register

## Locked

| | Decision | |
|---|---|---|
| **D8** | **Model A** — `wrap/recovery/{k}` and `pk_rec(k)` retained on an email-only reset. "Destroy earlier entries" is the deliberate route to Model B | ✔ |
| **D9** | **24 hours** — the maximum window. Device approval short-circuits it. Under E3b it is also the approval deadline | ✔ |
| **D10** | **E3** — device approval where an eligible signed-in device exists, degrading to the window where none does. Path R is settled and out of scope | ✔ |

**Revision 2 changes none of these.**

## Pending

| | Decision | Blocking | Recommendation |
|---|---|---|---|
| **D12** | **E3a or E3b** — §B | The reset protocol; and the wording of any public claim about email compromise | **None offered.** §B states both consequences; the weighing is yours |
| **D11** | Delay on "destroy earlier entries" | The destroy operation only | **Recommendation, not a lock:** 24 h default **plus an explicit immediate path** with heavier confirmation — §11.3. D9's reasoning does **not** transfer |
| **D6** | Minimum supported Android device | The Argon2id benchmark | — |
| **D7** | Argon2id p95 ceiling — **2 s proposed** | Must be fixed *before* measuring | — |

## Open technical questions, distinct from decisions

| | | |
|---|---|---|
| **A3** | Is a `BE = 0` platform credential obtainable on the target OS versions? | Needs real devices |
| **A7** | §9.6 — Option A, B or C. **Option C recommended, B rejected** | Design |
| **A9** | The security-stamp validation cache TTL | Value |

---

# D. Implementation readiness

**NOT READY. Nothing implemented. No migrations. No tables. No application code.
Nothing committed.**

| Gate | State |
|---|---|
| Cryptographic design | **Complete and internally consistent**, with §0's four defects corrected |
| Protocol decisions | **D12 open.** D11 open |
| Device-credential mechanism | **A3 unresolved** — needs devices, not documentation |
| Migration-vs-reset design | **A7 open** — Option C recommended |
| Revocation semantics | **A9 open** — one value |
| Argon2id parameters | **Blocked on D6 and D7.** The benchmark cannot run on an x86_64 emulator and produce a number worth writing down |
| Threat boundary | **Formalised** — §10 |

**When D12 and D11 are decided, A3, A7 and A9 are resolved, and the measured
Argon2id parameters are written in, this becomes IMPLEMENTATION READY — CRYPTO
PROTOCOL LOCKED.**
