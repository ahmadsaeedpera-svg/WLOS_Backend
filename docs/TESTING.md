# Testing Strategy & Coverage

Test suite overview, coverage metrics, and testing requirements.

---

## Testing Pyramid

```
        ┌─────────────┐
        │  E2E Tests  │  Integration tests (real DB)
        │  (few)      │  Mobile device tests
        ├─────────────┤
        │ Integration │  Backend: 86 integration tests
        │ Tests       │  Mobile: 425 unit + widget tests
        ├─────────────┤
        │ Unit Tests  │  Domain logic, helpers, utilities
        │  (many)     │
        └─────────────┘
```

---

## Backend Testing (111 tests)

**Location:** `Maren-Backend/tests/Maren.Tests/`

### Integration Tests (Real Database)

All 111 tests run against a real SQL Server instance. No repository mocks.

**Test structure:**
```csharp
public class AuthIntegrationTests : IAsyncLifetime
{
    private DatabaseFixture _fixture;
    
    public async Task InitializeAsync()
    {
        _fixture = new DatabaseFixture();
        await _fixture.InitializeAsync();
    }
    
    [Fact]
    public async Task Register_CreatesUser_AndReturnsTokens()
    {
        // Arrange
        var command = new RegisterCommand(new RegisterRequest("test@example.com", "password", "Test User"));
        var handler = new RegisterCommandHandler(_fixture.Repository, _fixture.PasswordHasher, _fixture.TokenGenerator);
        
        // Act
        var result = await handler.Handle(command, CancellationToken.None);
        
        // Assert
        Assert.True(result.Succeeded);
        Assert.NotNull(result.Value.AccessToken);
    }
}
```

### SQL Assertion Suites

**cms_workflow_test.sql** — 17 assertions
- Content creation and versioning
- Approval workflow (cannot publish unapproved)
- Restore writes forward only
- Publish pointer atomicity
- Targeting filters (country, week, season)

**access_test.sql** — 19 assertions
- Privilege escalation prevention
- Permission enforcement
- Self-demotion prevention
- Role deletion guards
- Last administrator protection
- Audit append-only

### Test Coverage

| Area | Coverage | Status |
|---|---|---|
| Handlers | ~95% | Excellent |
| Repositories | 100% | (no logic, just mapping) |
| Validators | ~90% | Good |
| Domain | ~85% | Good |
| Controllers | ~60% | OK (mostly routing) |
| Overall | ~70% | Good for a platform |

---

## Mobile Testing (425 tests)

**Location:** `Maren-Frontend/mobile/test/` and `mobile/integration_test/`

### Unit Tests

Domain logic, model methods, utilities. No Flutter imports.

```dart
void main() {
  group('DueDateCalculation', () {
    test('LMP dating calculates correct EDD', () {
      final calc = DueDateCalculation.fromLmp(DateTime(2024, 1, 15));
      expect(calc.estimatedDueDate, DateTime(2024, 10, 21));
    });
  });
}
```

### Widget Tests

Screen behavior, state management, form validation. No device needed.

```dart
void main() {
  testWidgets('HospitalBagChecklist allows adding items', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    
    expect(find.byType(ChecklistItemTile), findsWidgets);
    
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpWidget(const MyApp());
    
    expect(find.byType(AddItemBottomSheet), findsOneWidget);
  });
}
```

### Integration Tests

Full journeys on a real device or emulator.

```bash
flutter test integration_test/onboarding_test.dart
# Requires device or emulator attached
```

### Guard Tests (5, Verified Failing)

Compliance enforcement. Each is verified to **fail** when violated.

**no_interpretation_test.dart** — No medical advice in constrained modules
- Contraction timer (no time-to-hospital alert)
- Kick counter (no threshold)
- Body log (no aggregation)
- Daily check-in (no assessment)
- Birth preferences (no advice)

**analytics_event_test.dart** — No health data in event properties
- Check event names don't disclose health status
- Check properties don't include dates, numbers, health indicators

**contraception_claim_test.dart** — No contraception-adjacent phrasing
- Scan for keywords (contraceptive, contraception, birth control)

**crash_scrubbing_test.dart** — Crash reports don't leak PII
- No dates, user IDs, emails, usernames
- No health data in stack traces

**inclusive_copy_test.dart** — No hardcoded gendered/parental terms
- Scan for "mother", "father", "pregnant", "he/she"
- Allow customizable terms only

**Test coverage:** ~72% excluding generated code (app_database.g.dart)

---

## Portal Testing

**Status:** Manual only (no test suite yet)

**Pre-merge verification:**
```bash
npm run build           # TypeScript strict, no errors
npm run preview         # Test locally against running API
# Manual testing in browser
```

**If adding tests:**
```bash
npm install vitest @testing-library/react  # (as example)
# Document in this section
```

---

## Before Committing

### Backend Checklist

```bash
# In Maren-Backend/
dotnet build                                                   # no warnings
dotnet test tests/Maren.Tests                                  # 111/111 passing
sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform \
  -i src/Maren.Database/tests/cms_workflow_test.sql           # TOTAL: 17  FAILED: 0
sqlcmd -S "(localdb)\MSSQLLocalDB" -I -d MarenPlatform \
  -i src/Maren.Database/tests/access_test.sql                 # TOTAL: 19  FAILED: 0
```

**Failure means:** Do not commit. Debug and fix.

### Mobile Checklist

```bash
# In Maren-Frontend/mobile/
flutter analyze                                                # must be clean
flutter test                                                   # 425/425 passing
flutter test integration_test                                  # needs device
```

**Before release:**
- [ ] Tested on Android 10 (not just emulator)
- [ ] Tested on Android 12 (not just emulator)
- [ ] Orientation change works
- [ ] Background/foreground lifecycle works
- [ ] Guard tests pass (5/5)

### Portal Checklist

```bash
# In Maren-Frontend/web-admin/
npm run build                                                   # tsc -b + vite
npm run preview                                                 # test locally
```

---

## Test Coverage Goals

| Component | Goal | Current |
|---|---|---|
| Backend handlers | 95% | ✅ ~95% |
| Backend domain | 90% | ✅ ~85% |
| Mobile domain | 95% | ✅ ~90% |
| Mobile widgets | 80% | ✅ ~80% |
| Portal components | TBD | ⛔ 0% |

---

## Known Test Issues

| Issue | Status | Impact |
|---|---|---|
| **Portal no tests yet** | Open | No automated verification |
| **Coverage excludes generated** | OK | Drift schema 1.7k lines @ 30% |
| **One device tested** | **Blocker** | Android 10/12 unknown regressions |
| **Frame timing slow** | Open | 1576ms first frame needs profiling |

---

## For More Information

- **Backend tests:** `Maren-Backend/tests/Maren.Tests/`
- **SQL assertions:** `Maren-Backend/src/Maren.Database/tests/`
- **Mobile tests:** `Maren-Frontend/mobile/test/`
- **Guard tests:** `Maren-Frontend/mobile/test/guards/`
- **Architecture:** `docs/ARCHITECTURE.md`
