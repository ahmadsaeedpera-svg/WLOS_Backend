## What changed

<!-- One or two sentences. What does this do that the codebase could not do before? -->

## Why

<!-- The reasoning, not the mechanics. A reviewer can read the diff; they cannot
     read why you chose this approach over the alternative. -->

## How it was verified

<!-- Say what you actually ran and what it returned. "Tests pass" is not
     verification; "111/111, plus locked an account and confirmed the token was
     refused in 5s" is. -->

---

## Vertical slice completeness

A capability is not done because a screen shows it. Tick what this change
actually delivers, or write N/A.

- [ ] SQL schema (numbered script, idempotent, re-runnable)
- [ ] Stored procedures — result columns **named**, never `SELECT *`
- [ ] Domain invariants
- [ ] Contracts / DTOs
- [ ] Application layer (CQRS handler + validator)
- [ ] Repository
- [ ] API endpoint
- [ ] Permission declared in `PlatformPermissions` **and** seeded
- [ ] Audit trail with before/after state
- [ ] Feature flag seeded (if the capability should be switchable)
- [ ] Tests
- [ ] Documentation updated

## Security

- [ ] Permission gate declared via `IRequirePermission` — **no role checks in code**
- [ ] No procedure outside the login path references password material
- [ ] Every input validated before the handler runs
- [ ] Page sizes bounded
- [ ] No raw SQL exception message reaches a client
- [ ] Request bodies are not logged
- [ ] No secret added to a committed file
- [ ] If this grants or checks access, the privilege-escalation rule still holds
      (you cannot grant a permission you do not hold)

## Data safety

- [ ] Client-facing reads serve **approved snapshots**, not live tables
- [ ] Nothing here writes to `Audit.AuditLog` via UPDATE or DELETE
- [ ] Migration is idempotent and safe to re-run against a populated database
- [ ] Breaking change to `Maren.Contracts`? If so, say so here and link the
      matching [Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend) PR

## Verification run

```
dotnet build                                    # no new warnings
dotnet test tests/Maren.Tests                   # expect 111/111
sqlcmd ... -i src/Maren.Database/tests/cms_workflow_test.sql   # TOTAL: 17  FAILED: 0
sqlcmd ... -i src/Maren.Database/tests/access_test.sql         # TOTAL: 19  FAILED: 0
```

Paste the actual output:

```
```
