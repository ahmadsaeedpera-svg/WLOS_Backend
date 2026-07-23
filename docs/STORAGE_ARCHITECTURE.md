# Storage architecture

Sprint 1A. Local persistence behind the existing repository interfaces.

## What changed

Before this sprint, every repository was `InMemory*` and `core/db` was empty.
Closing the app discarded everything — due date, onboarding answers, checklist
ticks, birth preferences. The architecture was right and the storage under it
did not exist.

Now: Drift over SQLite, one file at
`getApplicationSupportDirectory()/maren.sqlite`.

**No domain contract changed.** `OnboardingRepository`, `ChecklistRepository`
and `PreferenceRepository` have identical signatures. The `InMemory*`
implementations remain and are still used by every widget and unit test — the
Drift implementations are siblings, not replacements.

## Why Drift rather than raw sqflite

One reason: **it can verify a migration rather than hope for one.**

Data loss on update, migration or reinstall is the second most severe complaint
in this category and the highest-anger, lowest-forgiveness failure mode in the
research — people report losing a decade of tracking, whole pregnancy histories
gone during an app migration, postpartum logs erased by an unexpected logout.

Almost all of that happens at a schema change. Drift gives schema versioning, a
`MigrationStrategy` with explicit steps, and tooling that can migrate a real
v(N) database to v(N+1) and assert the data survived. sqflite gives you a
version integer and good intentions.

The cost is `build_runner` codegen. Worth it here.

## Schema

Ten tables. Relational rather than one JSON blob per feature, which would have
been less code.

The reason is `core/sync`: it already models per-record revisions, tombstones
and per-type conflict strategies, and none of that works against a blob — two
devices editing different checklist items would conflict on the whole document
rather than on the items. Rows now means the sync layer has something to sync
when it lands.

| Table | Holds |
|---|---|
| `address_term_rows` | Singleton. How the app addresses the user, partner, baby. |
| `pregnancy_rows` | One row per pregnancy. Ended ones are never deleted. |
| `checklist_meta_rows` | Singleton. Locale + seed version. |
| `checklist_check_rows` | One row per ticked item. |
| `checklist_hidden_rows` | Defaults the user removed. |
| `checklist_user_item_rows` | Items the user typed. |
| `preference_meta_rows` | Singleton. Locale. |
| `preference_selection_rows` | Free text per section. |
| `preference_choice_rows` | One row per chosen option. |
| `app_flag_rows` | Small flags no domain repository owns. |

### Three decisions inside the schema

**Sets are rows, not comma-joined strings.** Checked items, hidden defaults and
chosen options are stored one row per member, so a partial write cannot corrupt
the whole collection and a future migration can touch one member without
rewriting all of them.

**Enums are stored by name, not ordinal.** Reordering `DatingMethod` or
`PregnancyStatus` in a later release would silently reinterpret every existing
row if we stored indices. An unknown name falls back to a safe default rather
than refusing to load — refusing would lock someone out of their own history
after a downgrade, which is the failure this layer exists to prevent.

**Singletons are enforced by a table-level CHECK, not by convention.** A second
row is a write-time error instead of a bug where the app reads whichever row
came back first.

Note the constraint is declared on the table rather than the column: a
column-level `check(id.equals(0))` reads naturally and recurses, because
evaluating it calls the very getter being defined. The analyzer caught that as
`recursive_getters`; it would have been an infinite loop at runtime.

## Migration policy

`schemaVersion` is **2**.

**v1 → v2** (branch `feature/hospital-bag-checklist`): `checklist_user_item_rows`
gains `phase` and `sort_order`. Both have defaults, so existing rows acquire
values without a rewrite — nothing dropped, nothing recreated.

`sort_order` exists because SQLite row order is unspecified without an
`ORDER BY` and does change; without it a user's list silently reshuffles.

The migration test builds a **real v1 table**, inserts real rows, sets
`user_version` to 1 and reopens at v2. A migration that recreated the table
would pass a schema check and still lose everything someone recorded.

`onUpgrade` still **throws for any version beyond the defined steps**:

```dart
throw UnsupportedError(
  'No migration defined from schema v$from to v$to. Add the migration step '
  'and its test before bumping schemaVersion.',
);
```

**The rule for anyone changing `schemaVersion`:** write the migration step, add
a migration test that starts from real data at the old version, and only then
bump the number — all in the same commit. A migration without a test is how
this category loses people's pregnancies.

`PRAGMA integrity_check` runs on open in debug and profile builds. Left on in
profile deliberately: corruption shows up under real device conditions, and
profile is where those get exercised.

## SharedPreferences — deliberately not used

The sprint plan called for SharedPreferences for tiny settings. It is not here,
and that is a considered deviation.

Every setting the app currently has — onboarding completion, content locale — is
read by a **domain repository**. Splitting one contract across two stores is how
"saved in one place, read from another" bugs start. Those live in
`app_flag_rows` and `*_meta_rows`.

There is a second reason: on Android, SharedPreferences is a plaintext XML file
that participates in auto-backup by default.

SharedPreferences earns its place when there is a genuinely UI-only setting such
as theme mode. Adding the dependency before then would be ceremony.

## ⚠️ Android backup is disabled — a real trade-off

`android:allowBackup="false"`, `android:fullBackupContent="false"`, plus
`data_extraction_rules.xml` excluding both cloud backup and device-to-device
transfer.

**Why:** Android backs app data up to the user's Google Drive by default. Here
that means pregnancy dates, symptom logs and birth preferences leaving the
device without the user ever being asked. That sits badly next to everything
else in this codebase — opaque analytics event names, a package name that avoids
"pregnancy", scrubbed crash reports. Backing the whole health record up by
default would undo all of it.

Device-to-device transfer is excluded too, even though it is local, because the
app cannot tell whose device is on the other end.

**The cost, stated plainly:** someone changing phones loses their history unless
they export first. That cuts directly against the anti-data-loss thesis running
through this codebase.

**The resolution: export is the sanctioned migration path and must ship before
launch.** It is already planned for both the checklist (plain text) and birth
preferences (PDF); the pregnancy record and logs need one too.

If this trade is judged wrong, the honest alternative is backup enabled **plus a
clear disclosure at onboarding** — not backup enabled silently. Reversing it is
a two-line manifest change; the decision is the hard part, not the code.

## Encryption at rest — not implemented, on purpose

The database is plaintext inside app-private storage, protected by the Android
sandbox and full-disk encryption.

SQLCipher would add at-rest encryption, roughly 3 MB, and a key-management
problem with no obvious place to put the key on a device with no user account —
a key stored beside the data it protects is decoration.

Recorded as a decision, not an oversight. Revisit if the threat model grows to
include a rooted device or a shared phone.

## Verification

`flutter analyze` clean. **157 tests passing**, up from 143.

14 new tests in `test/persistence_test.dart`, and the important thing about them
is that they use a **real file on disk, closed and reopened** rather than an
in-memory database. An in-memory test proves the SQL is valid; it cannot prove
anything survives the process ending, which is exactly the failure being fixed.
A storage suite that never restarts is theatre.

Verified across a close-and-reopen cycle:

- Address terms, including a custom self term and partner term
- The pregnancy record, including an ending, with `babyCount` preserved through
  a recorded loss
- Onboarding completion — otherwise a returning user sees onboarding every
  launch
- Checklist ticks, hidden defaults and user-added items
- Birth preference selections and free text, including free text with no
  option chosen
- **An emptied checklist is not mistaken for a first run** — someone who hid
  every default must not have them silently re-seeded
- Both locales of birth preferences coexisting

Plus integrity: singleton tables reject a second row, repeated saves overwrite
rather than accumulate, enums round-trip by name, an unknown enum falls back
rather than refusing to load, and the most recently started pregnancy is
returned while ended ones are retained.

## Verified on a physical device

**POCO 25078PC3EG, Android 16 (API 36), arm64-v8a, HyperOS 3.0.**

Debug APK built (823s cold, **9.6s warm**), installed, launched, driven, force-
stopped and relaunched. What that proved, which no test could:

- ✅ **`path_provider` resolved a real application-support directory.**
  `maren.sqlite` exists at 73,728 bytes in app-private storage. Every test uses
  an explicit path, so this code path had never once executed.
- ✅ **`sqlite3_flutter_libs` bundled and loaded the arm64 native library.**
  Implied by the schema being created at all — without it the app would have
  crashed on first open.
- ✅ **All ten tables created on device**, `PRAGMA integrity_check` = `ok`,
  verified by pulling the database and opening it off-device.
- ✅ **Data survived a real process death.** Onboarding answers were written
  (`self_term`, `partner_term`), the app was force-stopped, and on relaunch it
  went **straight to the calculator rather than onboarding** — the
  `onboarding_complete` flag genuinely persisted.
- ✅ No crash, no `FATAL`, no `AndroidRuntime` exception on launch.
- ✅ Dark theme and the required medical disclaimer render correctly.
- ✅ The main-thread watchdog fired its first real signal:
  `[vitals] slow frame 1576ms (build 1543ms, raster 31ms)` on first frame.
  Expected for a debug build doing JIT plus profile installation — but it needs
  re-measuring in profile mode, because that number would be an ANR risk if it
  held in release.

### Pulling the database — a trap worth recording

`adb shell run-as … cat` **corrupts binary files**. The first pull came back
73,740 bytes against 73,728 on device — exactly the line-ending inflation — and
SQLite reported `database disk image is malformed`.

Use `adb exec-out` for raw bytes. The database was fine all along; the transfer
was not.

## Two defects found by running, not by testing

**1. The first option rendered as pre-selected.** The "no preference" presets
store an empty string, and an empty stored value matched the first option — so
on the partner question the app opened having apparently decided the user was
doing this alone. That is exactly the presumption the address-terms feature
exists to avoid. The stored value was correct all along; the screen was
answering for them.

Fixed: an unanswered question now shows nothing selected, while choosing "just
say you" or "I'm doing this on my own" remains a real answer that does select.
Two regression tests added, and the fix was re-verified on device with cleared
app data.

**2. A literal NUL byte in source.** The "something else" sentinel had picked up
a NUL where a space was intended. It worked — a NUL is certainly unique — but a
NUL in source can make git treat the file as binary and upsets tooling. Replaced
with a named `_customSentinel` constant.

Neither would have been caught by the 157 tests that were passing. This is the
argument for the Release Readiness Sprint in one paragraph.

## Still not verified

- Release APK and AAB builds
- Android 10 and 12 (only API 36 tested)
- Orientation change and background/foreground lifecycle
- Backup exclusion against real device behaviour
- Profile-mode frame timings — the 1576ms first frame needs re-measuring
- Minor: the last preset sits under the fixed Continue button on smaller
  screens. The list scrolls, so it is reachable, but it needs bottom padding
