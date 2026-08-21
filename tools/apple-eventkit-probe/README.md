# Apple EventKit Discovery Probe

This directory contains Deskboard's Phase 2 native discovery utility. It is a local, read-only inspector for Apple Calendar and Apple Reminders. It is not the production Bridge and has no Deskboard Core or network path.

## Environment

The project was created and compiled with:

- macOS 26.4.1 (25E253)
- Xcode 26.4.1 (17E202)
- Apple Swift 6.3.1 compiler in Swift 5 language mode
- macOS 26.4 SDK
- macOS 14.0 deployment target

The deployment target is the first macOS release that provides EventKit's current full-access request APIs.

## Privacy and read-only boundary

The probe:

- requests Calendar and Reminders permission separately and only after an explicit button press;
- enumerates containers only for a granted entity type;
- defaults to no selected calendars or Reminder lists;
- persists only the two sets of selected container identifiers in `UserDefaults`;
- reads Calendar events from 7 days before through 45 days after the current time;
- retains at most 200 inspected records per entity;
- never calls an EventKit save or remove API;
- imports no networking framework and contains no HTTP client;
- shows field structure instead of record content, with source titles masked by default.

macOS 14 and later name the required APIs `requestFullAccessToEvents` and `requestFullAccessToReminders`. The resulting system permission is broad, but this app contains no Apple write behavior. The generated app `Info.plist` includes:

- `NSCalendarsFullAccessUsageDescription`
- `NSRemindersFullAccessUsageDescription`

Calendar and Reminders remain independently usable: denying one does not disable the other. After denial, the corresponding permission row links to Privacy & Security settings. Authorization is refreshed when the app becomes active again; the app does not automatically re-request access.

## Build and test

From the repository root:

```bash
xcodebuild \
  -project tools/apple-eventkit-probe/AppleEventKitProbe.xcodeproj \
  -scheme AppleEventKitProbe \
  -destination 'platform=macOS' \
  build test
```

For an isolated build directory:

```bash
xcodebuild \
  -project tools/apple-eventkit-probe/AppleEventKitProbe.xcodeproj \
  -scheme AppleEventKitProbe \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/deskboard-eventkit-derived \
  build test
```

The tests use synthetic values and do not request or read the user's EventKit store.

## Run the probe

Open `AppleEventKitProbe.xcodeproj`, select the shared `AppleEventKitProbe` scheme, and run the macOS target. The shared scheme uses the repository root as its working directory so exports resolve beneath the ignored `private-fixtures/` directory.

The intended flow is:

1. request Calendar and/or Reminders access intentionally;
2. select individual source containers (none are selected automatically);
3. inspect the bounded result;
4. review structural presence information on screen;
5. optionally confirm a private local export;
6. generate destructively sanitized candidates;
7. inspect every candidate by hand before copying any representative specimen into `fixtures/eventkit/`.

If a selected source disappears, the next successful source enumeration removes its identifier from the saved selection. Loss of permission does not erase selections merely because containers cannot be enumerated.

## Exports

Exports resolve to:

```text
private-fixtures/eventkit-probe/
```

That path is ignored by the repository's existing `.gitignore` rule for `private-fixtures/`.

`private-inspection-latest.json` may contain real titles, notes, identifiers, URLs, locations, and container names. The app shows a warning and requires confirmation immediately before writing it. Never print, screenshot, commit, share, upload, or quote that file.

Sanitized candidates are written beneath:

```text
private-fixtures/eventkit-probe/sanitized-candidates/
```

The sanitizer replaces identifiers, titles, notes, source and container names, URLs, locations, recurrence calendar identifiers, timestamps, and temporal values with deterministic synthetic values. It preserves only structural distinctions such as field presence, temporal kind, recurrence structure, completion, source mutability, status, availability, and participant counts. Candidate generation does not automatically modify committed fixtures.

When launching the built executable outside Xcode, set `DESKBOARD_REPOSITORY_ROOT` to the repository root so the same ignored destination is used.
