# WLOS Connection & Consent

**Status:** decision paper. Nothing built. Contains one recommendation I would
argue for strongly, and one I would ask you to overrule explicitly if you
disagree.

**Covers:** guardian access (the original question), and the connection model
it turns out to be a special case of.

---

## Part 1 — The guardian decision

### The question

A minor's account. Child-protection law in most regimes gives a guardian rights
to review and delete their child's data. WLOS's promise is a private space
where she can write honestly.

> A fifteen-year-old writing about something difficult **at home**, and a
> guardian with a legal right to read it.

### The decision I recommend

**Metadata only. Never content. Stated plainly to both of them, before she
writes anything.**

| Guardian can see | Guardian cannot see |
|---|---|
| The account exists | Her journal |
| It is active | Her memories |
| Storage used | Her check-ins |
| That data exists in categories | Her goals, events, people |
| **That a safety escalation occurred** | Anything she wrote |

And she is told, in the product, in the first minute:

> *"Your guardian can see that your account exists and that you use it. They
> cannot read anything you write. If we ever have to tell them something
> serious, we will tell you first."*

### Why not the alternatives

| Posture | Why not |
|---|---|
| Guardian sees content | Destroys the product for the girl who needs it most. A diary her father can read is not a diary. |
| Guardian sees nothing at all | Hardest to square with consent regimes; may be unlawful in several markets |
| Journal disabled for minors | Honest, but removes the surface with the most value |

### The rule that makes it real

**A private space she wrongly believes is private is worse than no private
space at all.**

If we cannot promise it in a given market, we must say so in that market —
not quietly degrade the promise and keep the copy.

### Still required before any Younger-world UI

Legal sign-off per market · the safety-escalation duty model (clinical and
legal) · age assurance · resolution of the retention-versus-hard-deletion
conflict.

---

## Part 2 — The same question, larger

The connection vision — mother and daughter, father and daughter, sisters,
partners, parents and children — is the same question with the safety rails
removed. A guardian's access is at least *bounded by law*. A partner's is
bounded by nothing but what we build.

So the guardian answer and the connection answer must come from one principle,
or they will contradict each other within a release.

---

## Part 3 — The line between care and control

**The feature is identical. Only the direction of initiative differs.**

```
   CARE                              CONTROL
   ────                              ───────
   She chooses to tell               He can check
   A moment she sent                 A feed he can read
   She can stop, invisibly           Stopping is visible to him
   He learns how to show up          He learns where she is weak
```

### The four tests

Any connection feature must pass all four. A feature failing one is not a
smaller version of care — it is a control surface with a warm name.

**1. Does she push, or can they pull?**
Care is something she sent. Control is something they can check. If the other
person can *ask the system* how she is, it has stopped being hers.

**2. Can she stop, and can they tell?**
This is the load-bearing one. **If turning sharing off is visible to the other
person, the off switch does not exist.** *"Why did you turn it off?"* is the
whole mechanism of coercion. Sharing must be able to go quiet in a way that
looks like nothing happened.

**3. Does it tell them about her, or teach them to show up?**
*"She has been low for four days"* is a status report about a person.
*"A call would mean more than a message this week"* is an instruction to the
one who wants to help. The second is the product; the first is surveillance
with good intentions.

**4. Can she leave a connection without a conversation?**
Removing someone must not require confronting them. A connection that must be
argued out of is a connection she cannot safely leave.

---

## Part 4 — Risk is not the same across relationships

The same feature has very different consequences depending on who is at the
other end.

| Connection | Risk | Why |
|---|---|---|
| Adult ↔ adult friend, sister | **Low** | Symmetrical, both can leave |
| Adult daughter ↔ adult mother | **Low–moderate** | Usually loving; occasionally enmeshed |
| **Adult ↔ intimate partner** | **Highest** | The single most common context for coercive control |
| Parent → minor child | **High** | Child cannot freely decline |
| Adult daughter ↔ father | **Context-dependent, can be very high** | In some family and cultural contexts, monitoring of an adult daughter is normal and not chosen |

**The partner case deserves naming plainly.** A feature that shares a woman's
emotional state with her partner, and prompts him to act on it, is
functionally the same mechanism as intimate-partner monitoring. It is
wonderful with a loving partner. With a controlling one it is a tool, and the
population most exposed to that harm is exactly the population WLOS is for.

### The consent problem it creates

For a woman in a controlling relationship, **the existence of the feature is
itself the coercion.** She does not get to decline. *"If you have nothing to
hide, turn it on."* Consent given under that pressure is not consent, and no
consent screen we write can fix it.

This is why test 2 — invisible off — matters more than any permission UI.

---

## Part 5 — What I recommend building

Almost all of the vision, and it is genuinely good.

### She shares moments, not a feed

```
  She writes / checks in
          │
  WLOS:  "Would you like to let someone know?"      ← a prompt, never a send
          │
    she chooses  ──►  WHO  ──►  WHAT  ──►  send
          │
  He receives:  a moment she sent, with guidance on how to respond
```

**WLOS may prompt her. WLOS may never report on her.**

### The recipient side is the best idea here

This is the part I would build first, because it is pure upside:

> *"She has had a heavy week. She usually wants company rather than advice.
> Her exams finish Thursday."*
>
> *"Her mum's anniversary is Sunday. She found it hard last year."*
>
> *"She mentioned wanting to start swimming again."*

A father who does not know what to say. A boyfriend who wants to help and
guesses wrong. A son who forgets to call. **WLOS making people better at loving
her is the product** — and none of it requires him to see her state.

Crucially: **she decides what he is told, and she can see exactly what he
sees.** There is no view of her that she cannot herself see.

### Reciprocal care, pointed at her

> *"You have not spoken to your mum in three weeks."*
> *"Amira's parents' evening is Thursday — you said you wanted to ask about
> the reading group."*
> *"Your sister's birthday is Sunday. Last year you sent flowers."*

Helping her show up for the people she loves. No sharing required at all.

### Remembering what matters to other people

*"Amira is allergic to sesame."* *"Mum takes her tablets at eight."* *"He hates
surprises."* Memory, already in the model, pointed outward. Quietly one of the
most valuable things WLOS could do.

### Gifts, words, and the good day

Suggestions grounded in what **she** recorded about them — not inferred from
their behaviour, because they are not users and have consented to nothing.

---

## Part 6 — What I recommend refusing

Stated as recommendations, not refusals. You can overrule any of these and I
will build them — but I would want that decision to be explicit and recorded,
because each one converts WLOS from a care product into a monitoring one.

| | Why |
|---|---|
| **Continuous state visibility** — a dashboard of how she is | Fails test 1. This is the monitoring feature. |
| **Anything the other person can query** | Fails test 1. |
| **Sharing that cannot be stopped invisibly** | Fails test 2. Without this, no other safeguard holds. |
| **Location** | Not in the model, and should not enter through connection. |
| **Emotion inference from text, voice or photographs** | Already forbidden by the constitution. She *states* her state; WLOS does not read it. |
| **Judging the people around her** — *"bad vibes", "wrong people"* | Inference about third parties who are not users and have not consented. Also weaponisable: an app that labels her friends as bad influences is an app a controlling partner will use to isolate her. **This is the one I would argue hardest against.** |
| **Minor's emotional state to a parent** | Removes the only private space a teenager has. |

### On the protection instinct

The wish behind *"warn her about the wrong people"* is right and worth serving.
The safe form of it is **not** WLOS judging her relationships. It is:

- Telling her **what she herself has recorded**: *"You have written about
  feeling small after seeing him four times this month. You noticed it, not
  me."* — her own words, reflected, never a verdict.
- Making **resources findable** without her having to search for them.
- Making **leaving easy** — a connection she can drop without a conversation.
- Never making her legible to someone who might use it.

An app that says *"this person is bad for you"* is an app that can be made to
say *"your sister is bad for you."*

---

## Part 7 — What I need decided

1. **Guardian access: metadata only?** My recommendation. Overruling it means
   deciding what a minor's journal is worth.
2. **Partner connections: same model as family, or a higher bar?**
   My recommendation: **same feature set, and connection-type is recorded so
   safety work can be targeted** — never a reduced feature set that signals
   distrust to a healthy couple.
3. **Invisible off — accepted as non-negotiable?** Everything else rests on it.
4. **"Bad vibes" detection: build, or replace with her own words reflected
   back?** My strong recommendation is the second.
5. **Does the recipient get a WLOS account?** Large consequence: a boyfriend
   receiving guidance is a user with data. My proposal: **yes, a minimal
   account**, because a non-user receiving a stream of information about her is
   worse.
6. **Which connection ships first?** My recommendation: **adult ↔ adult,
   mutual, both consenting, no minors and no partners** — prove the care model
   where the risk is lowest, then extend deliberately.

---

## Part 8 — The sentence I would build the whole thing around

> **WLOS should make her better at loving people — not make her legible to
> them.**

The elder-sister model you described is exactly right, and it is worth being
precise about what an elder sister actually does. She does not monitor you. She
notices, she asks, and she shows up. She keeps your secrets, including from
your parents. And she never tells your boyfriend how you are — she tells *you*
what she thinks, and leaves it with you.
