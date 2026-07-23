# Git Workflow & Branch Strategy

Branching strategy, merge policy, and release process for all three repositories.

---

## Repository Split (22 July 2026)

After 22 July, development is in three independent repositories with independent deployment:

| Repository | Team | Deploy | Cycle |
|---|---|---|---|
| [Maren-Backend](https://github.com/ahmadsaeedpera-svg/Maren-Backend) | Backend | Independent | Continuous |
| [Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend) — `mobile/` | Mobile | Google Play | 2-week review |
| [Maren-Frontend](https://github.com/ahmadsaeedpera-svg/Maren-Frontend) — `web-admin/` | Portal | Static host | Continuous |
| This archive | — | None | Read-only |

---

## Branch Strategy

### Main Branch (`main`)

**Always deployable.** No work-in-progress, no failed tests, no known blockers.

**Protection rules:**
- ✅ Require PR review (1 approval minimum)
- ✅ Dismiss stale PR approvals on new pushes
- ✅ Require status checks to pass (CI/CD)
- ✅ Require branches to be up to date

**Access:** Push only via PR merge

---

### Feature Branches

**Naming:** `feature/<feature-name>` or `fix/<issue>` or `docs/<item>`

**Pattern:**
```
git checkout -b feature/hospital-bag-checklist
# make changes
# commit with conventional commits
git push -u origin feature/hospital-bag-checklist
```

**Lifecycle:**
1. Create from `main`
2. Commit frequently (small, logical commits)
3. Push when ready for feedback
4. Open PR (not a draft until ready for review)
5. Address review feedback
6. Merge with merge commit (not squash)
7. Delete branch after merge

**Merge:** Never fast-forward. Merge commit preserves history and reasoning.

---

### Release Branches

**For production releases only.** Not used for routine deploys (those go directly from `main`).

**Pattern:** `release/v<major>.<minor>`

**Example:**
```bash
git checkout -b release/v1.0
# only commits: version bump, release notes, critical fixes
git tag v1.0 -m "Maren Platform v1.0"
```

---

### Hotfix Branches

**Critical bug fixes during a release candidate phase.**

**Pattern:** `hotfix/<issue>`

**Lifecycle:**
```bash
git checkout -b hotfix/password-reset-crash
git merge main  # start from main
# make fix
git push -u origin hotfix/password-reset-crash
# PR → merge to main
# Tag immediately after merge
```

---

## Commit Strategy

### Conventional Commits

Every commit follows [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation only
- `refactor:` Code reorganization (no behavior change)
- `test:` Test additions/updates
- `chore:` Dependency updates, tooling

**Scope:** Module or area (e.g., `content`, `permissions`, `mobile-app`)

**Examples:**
```
feat(auth): add security stamp for session revocation

Implement revocation within ~30 seconds by checking a security
stamp on every request. Old stamps remain valid until the token
expires (15 minutes), so concurrent requests don't cause logout.

Fixes #123
```

```
fix(content): SELECT * breaks procedure shape tests

A procedure returning {VersionId, Title, Body} but the DTO
expected only {Title, Body} caused runtime errors. Named all
columns explicitly.

Fixes #124
```

### Why This Matters

Commit messages are **design records.** `git log` explains why a feature is absent, what trade-offs were made, and what decisions are load-bearing.

**Do not squash-merge feature branches.** Individual commits stay visible and their messages stay meaningful.

---

## Pull Request Workflow

### Opening a PR

**Do not open a PR until:**
- All tests pass locally
- Code is formatted (`dotnet format` / `flutter format` / `npm run format`)
- No new warnings or errors

**PR description template:**

```markdown
## Summary
One-line description of what this PR does.

## Problem
Why this change is needed (issue link, customer feedback, technical debt).

## Solution
How it solves the problem.

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] Tested on device (mobile only)
- [ ] Manual testing (describe)

## Breaking Changes
If this is a breaking change to `Maren.Contracts` or an API contract:
- [ ] DTOs changed: list which
- [ ] Endpoints changed: list which
- [ ] **Coordinated with frontend team?** Yes / No

## Checklist
- [ ] Code follows style guide
- [ ] Self-reviewed for obvious issues
- [ ] Meaningful commit messages
- [ ] No console.log / println / print
- [ ] No hardcoded secrets
```

### Review Expectations

**Reviewer responsibilities:**
- Run the code locally if possible
- Check for security issues
- Verify architecture follows ADRs
- Confirm tests cover new behavior
- Read commit messages (not just diff)

**Reviewer will ask for changes if:**
- Tests do not pass
- Code introduces warnings
- Architecture violates ADRs
- Commits are squashed (if feature branch)
- No explanation for why (commit body is empty)

### Approval & Merge

**Approval:** One ✅ minimum

**Merge:** Use "Create a merge commit" (not squash or rebase)

```bash
# The UI will show this option when you click "Merge"
# This preserves individual commit messages in history
```

**After merge:**
```bash
git checkout main
git pull origin main
git branch -d <feature-branch>  # local cleanup
# GitHub will offer to delete the remote branch
```

---

## Deployment Workflow

### Backend (Maren-Backend)

**Continuous deployment from `main`:**

```bash
# Developer
git push origin feature/auth-improvements  # PR
git checkout main && git pull              # PR merged

# CI/CD (GitHub Actions or Azure Pipelines)
dotnet build
dotnet test tests/Maren.Tests
sqlcmd ... tests/cms_workflow_test.sql
sqlcmd ... tests/access_test.sql
# if all pass: build Docker image, push to registry
# deploy to staging → health checks → deploy to production
```

**Automatic:** Every merge to `main` triggers CI/CD.

**Manual rollback:** Tag the previous commit, re-deploy that image.

### Mobile (Maren-Frontend/mobile)

**Manual submission to Google Play:**

```bash
# Developer
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release

# Manual
# 1. Open Google Play Console
# 2. Upload AAB to Internal Testing
# 3. Test on devices
# 4. Promote to Closed Testing (optional)
# 5. Submit to production (Google reviews for ~7 days)
```

**Pre-release checklist:**
- [ ] All guard tests passing
- [ ] `flutter analyze` clean
- [ ] Tested on Android 10, 12
- [ ] Orientation change works
- [ ] Background/foreground lifecycle works
- [ ] Release blockers resolved
- [ ] Version number bumped (Android Gradle)
- [ ] Release notes updated (`docs/play-store/release-notes.md`)

### Portal (Maren-Frontend/web-admin)

**Continuous deployment to static host:**

```bash
# Developer
npm run build  # TypeScript strict, no errors
npm run preview  # test the build locally

git push origin feature/...  # PR
# PR merged to main

# CI/CD
npm install
npm run build
# if successful: sync `dist/` to static host (S3, Netlify, etc.)
```

**Automatic:** Every merge to `main` triggers build and deploy.

---

## Testing Before Merge

### Backend

```bash
dotnet build                                    # no warnings
dotnet test tests/Maren.Tests                   # 111/111 passing

# Plus SQL assertions
sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform -i src/Maren.Database/tests/cms_workflow_test.sql
# expect TOTAL: 17  FAILED: 0

sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform -i src/Maren.Database/tests/access_test.sql
# expect TOTAL: 19  FAILED: 0
```

**CI/CD will enforce this.** PR cannot merge if tests fail.

### Mobile

```bash
flutter analyze      # must be clean
flutter test         # 425/425 passing
flutter test integration_test  # needs device
```

**CI/CD enforces:** `flutter analyze` and `flutter test` before merge.

### Portal

```bash
npm run build        # TypeScript strict, no errors
# tsc -b runs first, fails the build if any errors
```

**CI/CD enforces:** `npm run build` passes before merge.

---

## Versioning

### Backend API

**URL versioning:** `/api/v1/auth/login`

**Major version bumps:** Only when breaking changes to DTOs.

**Current:** v1 (stable, no major changes planned)

### Mobile App

**Android Gradle `versionCode`:** Incremented every release

**`versionName`:** Semantic versioning (`1.0.0`, `1.0.1`, etc.)

**Update in:** `Maren-Frontend/mobile/android/app/build.gradle`

### Portal

No versioning. Static files serve current version.

---

## Reverting Changes

**If a merge breaks production:**

```bash
# Identify the commit
git log --oneline main | head -5

# Option 1: Revert commit (preferred)
git revert abc123def  # creates a new commit that undoes the change
git push origin main

# Option 2: Reset to prior commit (only if < 30 min old)
git reset --hard abc123def~1
git push --force-with-lease origin main
```

**Revert is preferred** because it creates a visible commit in history.

---

## Collaboration Across Repos

### Contract Changes (Backend → Frontend)

**If you change `Maren.Contracts`:**

1. Mark PR with 🔴 breaking change
2. State exactly what changed: "Added `VerificationEmailSent: bool` to `RegisterResponse`"
3. Wait for frontend team to acknowledge
4. Merge when ready
5. Frontend team updates their deserialization in a separate PR

**Timeline:** Ideally frontend updates within 1 week. API can remain backward-compatible if the field is optional.

### Coordinated Releases

**Usually not needed.** API v1 is stable and backward-compatible.

**If needed:**
1. Create `release/*` branches in both repos
2. Coordinate version numbers in PR descriptions
3. Merge both PRs ~same time
4. Tag both repos with matching version numbers

---

## For More Information

- **Conventional Commits:** https://www.conventionalcommits.org/
- **Backend CLAUDE.md:** Contributing section
- **Frontend CLAUDE.md:** Contributing section
- **Team responsibilities:** `docs/TEAM_RESPONSIBILITIES.md`
