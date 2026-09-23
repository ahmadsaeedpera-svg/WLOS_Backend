# WLOS Crypto Protocol v1 — Final Specification

**Status:** specification under review. **No implementation, no migrations, no
code, nothing committed.**

**Resolved in earlier revisions:** recovery-wrapper semantics · generation
states · offline-device lifecycle · padding invariant · rotation-vs-DORMANT ·
rotation claim · reset authorization · destructive deletion · Model-A threat
argument.

**Resolved in this revision:** Path R proof-of-possession (§2) · D10 split by
path (§3) · reset state machine (§4) · possession taxonomy (§5).

---

## 1. The gap this revision closes

Path R was specified as *"recovery phrase → immediate reset"*, with no
mechanism by which the server could tell a genuine holder from a client that
simply **claims** to hold one.

```
  attacker: "I have the recovery phrase"
       → server accepts Path R
       → attacker resets the password, skipping the delay window
```

The phrase, `KEK_recovery` and the DEK must never reach the server. So the
server needs a proof that reveals none of them.

---

## 2. Path R — proof of possession

### 2.1 Construction: **Ed25519 signature over a server challenge**

Standard, widely implemented, no bespoke cryptography.

**At registration**, a third value is derived from the same recovery entropy:

```
  recovery_entropy (128-bit)
        ├─ HKDF(…, "WLOS/v1/kek/recovery")      ─► KEK_recovery   (wraps DEK)
        └─ HKDF(…, "WLOS/v1/recovery/sign")     ─► Ed25519 seed
                                                       │
                                                  (sk_rec, pk_rec)
                                                       │
                              server stores ──────► pk_rec   (public; harmless)
```

**Path R exchange:**

```
  1  CLIENT → GET  /auth/recovery/challenge?email
  2  SERVER → { challengeId, nonce(32), expiresAt }
              issued for ANY address, existing or not, in constant time

  3  CLIENT   context = "WLOS/v1/recovery-reset" ‖ accountRef ‖ challengeId
                        ‖ nonce ‖ newAuthSecretHash
              sig = Ed25519_sign(sk_rec, context)

  4  CLIENT → POST /auth/recovery/complete { challengeId, sig, new material }
  5  SERVER   verify(pk_rec, context, sig) · consume challengeId · reset
```

### 2.2 Requirements, satisfied

| Requirement | How |
|---|---|
| Phrase never leaves the device | Only a signature is transmitted |
| `KEK_recovery` never leaves | Derived under a different HKDF label; unrelated to `sk_rec` |
| DEK never leaves | Unwrapped locally, after the reset |
| Bound to the account | `accountRef` is inside the signed context |
| Bound to a fresh challenge | `nonce` + `challengeId`, server-generated |
| Single-use | `challengeId` consumed atomically on first verification |
| Replay fails | Consumed id, plus a short TTL |
| **Not a reusable auth credential** | The context string is `recovery-reset`. A signature over it is **not valid** for session authentication, which signs a different context. A captured signature authorises nothing else and nothing twice |
| Server learns nothing | `pk_rec` is a public key; a signature leaks nothing about the seed |
| A claim alone is insufficient | A valid signature is required; there is no "I have it" flag |
| Failure reveals nothing | §2.4 |

### 2.3 What is proved — and what is not

> The signature proves **possession of the recovery entropy**, which is the
> credential that authorises reset.

**It does not prove the wrapper will open.** That is verified locally by the
AEAD tag when `wrap/recovery/{k}` is unwrapped. If the entropy is right but the
blob is corrupt or absent, she regains her account and **not** her old
generation — a distinct, client-side outcome she is told about plainly.

**Proving DEK possession to the server is impossible by construction**, because
the server must never hold anything that could verify it. Authorisation and
decryption are deliberately separate proofs against separate parties.

### 2.4 Failure indistinguishability

The server returns **one generic failure** for: unknown address · expired
challenge · consumed challenge · invalid signature · account locked. Identical
body, identical status, constant-time comparison.

**An attacker cannot use the endpoint to test whether a candidate phrase is
correct**, nor to learn whether an address is registered.

> `pk_rec` does permit offline verification of a guessed phrase by anyone who
> obtains it. Against 128 bits of entropy that search is infeasible, and it is
> the same exposure as any public key. Stated rather than omitted.

### 2.5 Rate limiting

| Surface | Limit |
|---|---|
| Challenge issuance, per account | 5 / hour, 20 / day |
| Challenge issuance, per IP | 20 / hour |
| Verification attempts, per challenge | **1** — consumed on any attempt, valid or not |
| Verification failures, per account | 10 / day, then Path R locks for 24 h; Path E remains open |
| Challenge TTL | 10 minutes |

Consuming the challenge on a *failed* attempt is deliberate: it makes each
guess cost a fresh round trip and removes any oracle from repeated tries
against one nonce.

### 2.6 Concurrency — deterministic

| Race | Resolution |
|---|---|
| Two Path E initiations | The second **supersedes** the first and **restarts** the window. Never shortens it. Rate-limited to prevent notification flooding |
| **Path R while Path E is pending** | **Path R completes immediately and cancels the pending E.** Stronger proof wins — and this is a defence: a legitimate holder can instantly void an attacker's pending reset |
| Two Path R completions | Both consume challenges; the first to commit wins, the second finds its challenge consumed and fails generically |
| Path R vs account deletion in progress | **Deletion wins.** Reset is refused |
| Pending reset vs deletion request | Deletion proceeds and cancels the pending reset |
| Device offline during either | Unaffected — §4, case M |

---

## 3. D10, split by path

The earlier phrasing — *"is a second factor required at reset?"* — conflated two
mechanisms with different security properties.

### 3.1 Path R — no additional factor needed

```
  recovery phrase  ──►  Ed25519 proof of possession  ──►  IMMEDIATE reset
```

**The phrase is already a 128-bit possession factor**, stronger than TOTP
(~20 bits per window) and not phishable in the usual sense. Requiring a second
factor on top would mean a woman holding the strongest credential in the system
is *more* obstructed than one holding only a mailbox.

**No delay window. No additional factor. Settled — not part of D10.**

### 3.2 Path E — the open question

```
  mailbox control  ──►  delay window  ──►  [ additional factor? ]  ──►  reset
```

| Option | Security | Cost |
|---|---|---|
| **E1** Mailbox + window only | Mailbox takeover yields **the entire Life Record** after the window. Cancellable only if she has a live session or reads the email | Nothing — always available |
| **E2** Mailbox + window + TOTP/passkey | Mailbox takeover alone is insufficient | She must have enrolled one, and can lose it. Losing password **and** factor **and** phrase = account lost |
| **E3** Mailbox + window + approval from any enrolled device | Strong when she has a signed-in device; **zero setup** | Useless when she is locked out of everything |
| **E4** No email-only path | Strongest | A woman who loses password **and** phrase loses her account entirely. **Brutal, and it falls hardest on the least technical user** |

### 3.3 Does the recovery phrase satisfy Path E's factor requirement?

**No — and it cannot, by construction.**

Path E exists *precisely for the case where she does not have the phrase*. If
she had it, she would use Path R. Accepting the phrase as Path E's second
factor would collapse the two paths and leave Path E with no independent
meaning.

**They are distinct recovery mechanisms, not tiers of one.**

### 3.4 D10 — **APPROVED: E3.** D9 — **APPROVED: 24 hours.**

```
  Path E initiated
        │
  any enrolled device holding a live session?
        │
        ├── YES ──► approval request pushed to every such device
        │             ├─ she APPROVES  → reset completes IMMEDIATELY
        │             ├─ she DECLINES  → reset cancelled at once,
        │             │                   all devices + email notified
        │             └─ no response   → see D12
        │
        └── NO  ───► 24-hour window · email + notifications · cancellable
                      completes at expiry
```

**Reading of D9 = 24 h**, stated so it can be corrected: 24 hours is the
**maximum** window, applying to the no-device path. **Device approval
short-circuits it** — approval from a signed-in device proves current control
more directly than waiting, so making her wait afterwards would add friction
without adding security.

### 3.5 D12 — what happens when a device exists but does not answer

Specifying E3 exposes a sub-decision that materially changes its security
property. **A device that never responds is indistinguishable from a device in
a drawer with a flat battery.**

| | **E3a — approval is a fast path** | **E3b — approval is a gate** |
|---|---|---|
| No response in 24 h | Reset **completes** | Reset **fails** |
| Security property | **Visibility, not a barrier** — a push notification is far more noticeable than an email, and Decline cancels instantly | A genuine second factor: mailbox alone is insufficient |
| Lockout risk | None | **A woman whose only signed-in device is lost, broken or flat cannot reset at all** — her remaining route is Path R, and under Model A she may not have the phrase |
| Honest description | E1 plus a high-visibility channel and an immediate-decline capability | E2, with the device as the factor |

**I am not choosing this.** E3a is what I had in mind when recommending E3, but
described plainly it is **not a hard second factor** — and that may be less than
was intended when D10 was approved. E3b is a real gate and a real lockout risk.

**Raised as D12.**

> **D12 is defined precisely, and the whole reset authorization protocol is
> specified, in `WLOS_RESET_AUTHORIZATION_V1.md`.** That document supersedes §3
> and §4 here wherever the two differ, and lists the differences explicitly in
> its §11.

---

## 4. Reset state machine — thirteen cases

`gen` = generation change · `wrap` = wrapper disposition · `sess` = sessions

| | Case | Credential accepted | gen | wrap | sess | Attacker reaches | She recovers |
|---|---|---|---|---|---|---|---|
| **A** | Normal password change | **current password** | none | `pw/{k}` replaced; recovery & device untouched | current session kept, others revoked | — | everything |
| **B** | Path R reset | **Ed25519 PoP** | none | `pw/{k}` replaced; recovery untouched | all revoked | — | **everything, including old journal** |
| **C** | Path E reset | mailbox + window *(+ D10 factor)* | **k → DORMANT, new ACTIVE k+1** | `pw/{k}` **deleted**, `device/*/{k}` **deleted**, `recovery/{k}` **retained** (Model A) | all revoked at completion | **Life Record** | account + Life Record; journal only with the old phrase |
| **D** | Attacker controls mailbox | Path E only | as C | as C | as C | **Life Record. Not the journal** | via cancel during the window, if she has a session or reads the mail |
| **E** | Attacker knows old password | login; **may change, may not reset** | none | — | he creates a session | **Life Record and, once signed in, the DEK → the journal** | password change; **rotation required** |
| **F** | Attacker controls a live session | session only | none | — | — | **Life Record.** Not the DEK (held client-side, not re-derivable from a session). **Cannot destroy history — §3 requires the password** | revoke the session |
| **G** | Attacker knows the recovery phrase | Path R PoP | none | as B | all revoked | **Everything — he passes PoP, resets, then unwraps.** ⚠ **Corrected:** true only of the **current** generation's phrase. A superseded phrase authorises generation recovery, not a reset, and needs an authenticated session in addition — `WLOS_RESET_AUTHORIZATION_V1.md` §3.3 | **Only by destroying the generation first.** This is D8's real cost |
| **H** | Phrase + copied ciphertext | none needed | — | — | — | **The old journal, offline, forever. No server action reaches it** | nothing — §5 |
| **I** | She spots an unauthorised reset in-window | cancel link or any live session | none | none | none | nothing | everything; **rotation advised** |
| **J** | Two Path E requests race | latest supersedes | per C, once | per C | at completion | — | cancel voids both |
| **K** | Path R races a pending Path E | **PoP wins; E cancelled** | none | as B | all revoked | — | **everything — this is the defence against D** |
| **L** | Path R races account deletion | **deletion wins**; reset refused | n/a | all deleted | all revoked | — | nothing — deletion is deliberate |
| **M** | Device offline during reset | n/a | learns on reconnect | server-side only | its session is dead | — | signs in with the new password; **keeps any cached `DEK(k)` until it discards it — §1 of prior revision** |

### 4.1 What the table makes plain

**Case G is D8's true cost.** An attacker with the phrase passes proof-of-possession, resets, and unwraps. Model A's retention of `wrap/recovery/{k}` is not what enables this — **the phrase plus the wrapper is**, and under Model B the same attacker simply uses Path R before she deletes anything.

**Case H is beyond every control.** Ciphertext plus phrase, both already copied, needs no server at all.

**Case E deserves emphasis:** a stolen password is worse than a stolen session, because signing in yields the DEK. Password compromise is the one case that **requires rotation**, not merely a password change.

---

## 5. Possession taxonomy — kept separate

**Server authentication is access control over one retrieval channel. It is not
cryptographic protection of ciphertext.**

| Possession | Grants | Does **not** grant |
|---|---|---|
| **API authorisation** (session) | Retrieval of server-held ciphertext and Life Record | Any key. No decryption |
| **Ciphertext** | Nothing alone | — |
| **Recovery phrase** | `KEK_recovery`; and PoP for Path R | Nothing without the matching wrapper |
| **Wrapper + phrase** | **The DEK** | — |
| **DEK** | **Plaintext of that generation** | Other generations |
| **Password** | `auth_secret` **and** `KEK_password` → session **and** DEK | Other generations' DEKs |
| **Authenticated session** | Life Record; ciphertext retrieval | **Not the DEK** — it is client-derived, never transmitted |

**Two consequences worth stating:**

- Ciphertext obtained outside the API — backup, export, copied device — is
  **unprotected by authentication**. Only the key hierarchy protects it.
- A session is strictly weaker than a password. This is why §3's destroy
  operation requires the password and never the session.

---

## 6. Re-audit

| Area | Result |
|---|---|
| PoP ↔ generation transitions | Consistent. Path R changes no generation |
| PoP ↔ *"recovery phrase never leaves"* | Consistent. Only a signature transmits |
| **PoP ↔ HKDF labels** | **Verified.** `recovery/sign` and `kek/recovery` are independent outputs; the signing key cannot yield the wrapping key |
| PoP ↔ rate limiting | Consistent. Single-use challenge, generic failures |
| Path R ↔ D10 | **Corrected.** Path R is settled; only Path E is open |
| Path E ↔ recovery phrase as a factor | **Resolved: it cannot be.** §3.3 |
| Session revocation timing | Consistent — at completion, per the prior fix |
| Destroy ↔ case G | Consistent. Destroying is the only pre-emptive defence, and §3 correctly requires the password |
| Model A ↔ case G | **Narrowed again.** Under Model B the same attacker uses Path R first. D8 changes *less* than it appears |
| Backups, exports ↔ §5 | Consistent and explicitly unprotected by authentication |
| Everything else | Unchanged and consistent |

### 6.1 Finding

**Case G shows D8 matters less than previously framed.** An attacker with the
phrase can complete Path R under either model. Model B only helps if she
deletes the wrapper **before** he acts — which is the "destroy earlier entries"
operation, available under Model A too.

**D8 should therefore be decided on the mislaid-phrase case**, where Model A
preserves her history and Model B destroys it, rather than on an attack Model B
does not actually prevent.

---

## 7. Carried forward unchanged

Key topology · BIP39 as encoding · registration · login · password change ·
reset with recovery key · recovery-key regeneration · second-device enrolment ·
generation states · envelope format · padding arithmetic · sync and conflict ·
memory boundary · Life Record boundary · threat model · rotation semantics ·
"the protocol decides, never the user".

---

## 8. Fitness tests — additions

| Test | Asserts |
|---|---|
| PoP required for Path R | No path grants an immediate reset without a verified Ed25519 signature |
| Challenge single-use | A consumed `challengeId` never verifies again |
| Context separation | A `recovery-reset` signature does not authenticate a session |
| Generic failure | All Path R failures return an identical body and status |
| Challenge for unknown accounts | Issued for any address, constant time |

---

# BLOCKED — product decisions only

## Technical blockers

**None.** With §2 specified, every cryptographic lifecycle question in the
protocol is resolved and internally consistent.

**The reset authorization protocol — D12, the device-approval proof, both reset
state machines, the threat model, the Model A consequence and the destroy
interaction — is specified in `WLOS_RESET_AUTHORIZATION_V1.md`.** Ten
corrections to this document are listed in its §11; the two that change a
security claim are case G (§4 above, marked) and the release of
`wrap/recovery/{k}` only after proof of possession.

## Decisions locked

| | Decision | Locked |
|---|---|---|
| **D8** | **Model A** — the old recovery wrapper is retained on reset without a recovery phrase. *"Reset without recovery key" does not mean all old credentials are invalidated.* "Destroy earlier entries" is the deliberate route to Model B | ✔ |
| **D9** | **24 hours** — maximum window, no-device path. Device approval short-circuits it (§3.4) | ✔ |
| **D10** | **E3** — device approval where a signed-in device exists, degrading to the 24-hour window where none does. Path R was already settled and is out of scope | ✔ |

## Product decisions remaining

| | Decision | Note |
|---|---|---|
| **D12** | **E3a or E3b** (§3.5) — is device approval a fast path or a gate? | **New, and it decides whether D10 is a real second factor.** E3a is visibility; E3b is a barrier with a lockout risk |
| **D11** | Delay on "destroy earlier entries" | Recommend 24 h for consistency with D9 |
| **D6** | Minimum supported Android device | Benchmark prerequisite |
| **D7** | p95 ceiling — 2 s proposed | Fix before measuring |

**Once D12, D11, D6 and D7 are answered and the measured Argon2id parameters
are written in, this becomes IMPLEMENTATION READY — CRYPTO PROTOCOL LOCKED.**

**No implementation. No migrations. No production code. Nothing committed.**
