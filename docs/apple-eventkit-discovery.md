# Apple EventKit Discovery

## Status

**Phase 2 discovery is not complete.**

The read-only probe, its synthetic unit tests, and its privacy boundaries compile and pass. The local EventKit permission and source-observation pass has not been performed because interactive approval on the Mac was unavailable during this run. Runtime source fields therefore remain `not tested`; no runtime-derived EventKit specimen or Board fixture is committed, and the architecture field map has not been promoted from hypothesis to verified fact.

This document distinguishes three evidence classes:

- **verified** — directly established by a completed local build, automated test, or runtime observation named here;
- **available with caveats** — observed through a selected source but subject to a documented limitation;
- **unavailable** — absent from the supported installed EventKit SDK surface or directly observed as unavailable;
- **not tested** — no qualifying local source observation has been completed.

Compiler availability alone is not treated as a runtime source observation.

## Environment

| Item | Value | Evidence status |
|---|---|---|
| macOS | 26.4.1 (25E253) | verified with `sw_vers` |
| Xcode | 26.4.1 (17E202) | verified with `xcodebuild -version` |
| Swift compiler | Apple Swift 6.3.1 | verified with `xcrun swift -version` |
| Swift language mode | Swift 5 | verified in Xcode project settings |
| macOS SDK | 26.4 | verified with `xcodebuild -showsdks` |
| deployment target | macOS 14.0 | verified in Xcode project settings and built product |
| source-provider categories tested | none yet | not tested |

## Probe boundary verified by build and tests

The contained project is `tools/apple-eventkit-probe/AppleEventKitProbe.xcodeproj` with one macOS SwiftUI application and one pure unit-test target. The build contains no Swift package dependency, project generator, database, HTTP client, daemon, login item, Apple write action, or Deskboard Core path.

The installed SDK and compiled app establish the following implementation facts:

- Calendar and Reminders use separate `EKEventStore.authorizationStatus(for:)` checks;
- Calendar requests use `requestFullAccessToEvents(completion:)`;
- Reminder requests use `requestFullAccessToReminders(completion:)`;
- the built `Info.plist` contains `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription`;
- no permission is requested during app initialization;
- denied access has a user-initiated link to the relevant Privacy & Security pane;
- authorization is refreshed when the app becomes active again;
- source selections use separate `UserDefaults` keys and default to empty;
- a successful source enumeration intersects saved selections with currently available identifiers;
- Calendar reads use only selected calendars and a 7-day-back/45-day-forward predicate;
- Reminder reads use only selected lists;
- at most 200 records of either entity are transformed, displayed, or exported;
- organizer and attendee values are reduced to presence and count; identities are never copied into the probe model;
- private and sanitized exports occur only after explicit user actions;
- the private destination is covered by the existing `private-fixtures/` ignore rule;
- the sanitizer deterministically replaces every modeled private text, identifier, name, URL, location, instant, and temporal value exercised by tests.

The `requestFullAccess` API name reflects Apple's permission model. It does not imply write behavior in this probe. No EventKit save or remove API is called.

## Permissions

### APIs used

| Entity | API | Compile/build status | Runtime behavior |
|---|---|---|---|
| Calendar | `requestFullAccessToEvents(completion:)` | verified | not tested |
| Reminders | `requestFullAccessToReminders(completion:)` | verified | not tested |
| both | `authorizationStatus(for:)` | verified | not tested |

### Runtime permission matrix

| Case | Status | Notes |
|---|---|---|
| first launch, both not determined | not tested | requires local interaction |
| Calendar granted, Reminders denied | not tested | requires local interaction |
| Reminders granted, Calendar denied | not tested | requires local interaction |
| both granted | not tested | requires local interaction |
| denied access later granted in System Settings | not tested | requires local interaction |
| restricted/unavailable state | not tested | may require a managed or otherwise restricted environment |

No claim is made yet about prompt timing, System Settings propagation, or provider behavior after a permission transition.

## Verified field inventory

The tables below cover every source concept listed in `docs/apple-source-mapping-v0.1.md`. `SDK surface present` means the installed SDK exposes a corresponding supported property and the probe compiles against it; it does not upgrade the field's observation status.

### Reminder fields

| Source field | Status | Current evidence or gap |
|---|---|---|
| local identifier | not tested | `calendarItemIdentifier` is in the SDK and probe model; no source instance observed |
| external identifier | not tested | `calendarItemExternalIdentifier` is in the SDK and probe model; no source instance observed |
| title | not tested | modeled privately and destructively sanitized; no source instance observed |
| notes | not tested | modeled privately with delimiter-presence observation; no source instance observed |
| Reminder list/container | not tested | calendar/list identifier, type, source category, subscription, and mutability are modeled; no source enumerated |
| start/availability components | not tested | pure tests verify date-only, local-time, and timezone-qualified normalization from synthetic `DateComponents` |
| due components | not tested | pure tests verify the same normalizer; no source instance observed |
| priority | not tested | `priority` is in the SDK and probe model; no returned value observed |
| completion state | not tested | `isCompleted` is in the SDK and probe model; no source instance observed |
| completion date | not tested | `completionDate` is in the SDK and probe model; repeated completion history is not claimed |
| recurrence rules | not tested | recurrence structure is modeled; no Reminder recurrence returned by a source |
| alarms | not tested | only alarm count is modeled; no source instance observed |
| creation date | not tested | modeled as an optional instant; no source instance observed |
| modification date | not tested | modeled as an optional instant; no source instance observed |
| URL/reference | not tested | modeled privately and replaced by `example.invalid`; no source instance observed |
| location | not tested | modeled privately and replaced; no source instance observed |
| tags | unavailable | no supported EventKit Reminder property exists in the installed SDK surface |
| sections | unavailable | no supported EventKit Reminder property exists in the installed SDK surface |
| subtasks | unavailable | no supported EventKit Reminder property exists in the installed SDK surface |
| attachments | unavailable | no supported EventKit Reminder property exists in the installed SDK surface |

### Calendar fields

| Source field | Status | Current evidence or gap |
|---|---|---|
| local identifier | not tested | both calendar-item and event identifiers are modeled; no source instance observed |
| external identifier | not tested | modeled as an optional reconciliation hint; no source instance observed |
| title | not tested | modeled privately and destructively sanitized; no source instance observed |
| source calendar/container | not tested | identifier, type, source category, subscription, and mutability are modeled; no source enumerated |
| start and end | not tested | pure tests verify temporal normalization only |
| all-day state | not tested | pure tests verify an exclusive multi-day range without UTC flattening |
| occurrence identity/date | not tested | event identifier, external identifier, occurrence date, and detached state are modeled; no recurring occurrence observed |
| recurrence rules | not tested | relevant recurrence structure is modeled; no source instance observed |
| status/cancellation | not tested | all `EKEventStatus` categories are mapped; no provider value observed |
| availability | not tested | all `EKEventAvailability` categories are mapped; no provider value observed |
| location/structured location | not tested | private location and structured-location presence are modeled; no source instance observed |
| organizer and attendees | not tested | only organizer presence and attendee count are modeled; participant details are intentionally omitted |
| notes | not tested | modeled privately and destructively sanitized; no source instance observed |
| URL | not tested | modeled privately and replaced by `example.invalid`; no source instance observed |
| alarms | not tested | only alarm count is modeled; no source instance observed |

## Identity

No edit, relaunch, synchronization, or recurring-occurrence identity test has been performed against a selected source.

The installed EventKit headers document caveats that the later runtime pass must verify rather than assume:

- `calendarItemIdentifier` and calendar identifiers are not sync-proof;
- `eventIdentifier` can change when an event moves calendars or after synchronization;
- `calendarItemExternalIdentifier` can be shared across recurring occurrences and can have provider/device caveats;
- EventKit recommends occurrence date as an additional recurring-occurrence discriminator;
- external identifiers can be duplicated when equivalent items exist in multiple containers.

These are SDK-documented constraints, not local observations.

## Temporal behavior

Pure tests verify that the diagnostic representation can preserve:

- a date-only Reminder as `dateOnly`;
- a timed Reminder without a source timezone as `localDateTime`;
- a timed Reminder with a source timezone as `timeZoneDateTime` plus the timezone identifier;
- an all-day event as an exclusive `allDayRange`;
- a multi-day all-day duration without converting its dates to UTC;
- an absent temporal field as absent;
- malformed components as a normalization warning rather than an invented value.

Actual Reminder and Calendar source representations, floating-time behavior, daylight-saving transitions, and provider-specific timezone behavior remain not tested.

## Reminder behavior

Notes, priority, completion, recurrence, list/container behavior, completed recurrence history, and visible Reminders features require runtime observation. The probe does not claim repeated completion history exists.

The metadata detector answers only structural questions. It records exact opening/closing delimiter presence, whether exactly one ordered pair exists, whether prose exists before and after, whether delimiters are duplicated, and whether another `[deskboard:…]` version appears. It does not parse fields, accept a grammar, rewrite notes, or infer a Task/Open Loop/Project lifecycle.

## Calendar behavior

Status and cancellation, locations, read-only/subscribed sources, recurrence exceptions, all-day boundaries, and occurrence identity require runtime observation. Organizer and attendee details are intentionally excluded from private and sanitized representations; only structural presence/count is retained.

## Sanitization evidence

The sanitizer unit test begins with a fully populated synthetic private-shaped Reminder and event. It proves that encoded sanitized output contains none of the input identifiers, titles, notes, source/container names, URLs, locations, recurrence calendar identifiers, timestamps, temporal dates, or timezone identifiers.

Replacement output is deterministic and visibly synthetic, including:

- `Synthetic Reminder A`;
- `Synthetic Event A`;
- `Synthetic Reminder List A`;
- `Synthetic Calendar A`;
- `synthetic-reminder-001`;
- `synthetic-event-001`;
- `Example Location`;
- `example.invalid` URLs.

No runtime-derived candidate has been generated or reviewed yet.

## Recommendations

### Verified

- Keep Calendar and Reminder records separate in the diagnostic layer.
- Keep source selection separate per entity and default both sets to empty.
- Preserve date-only, local date-time, timezone-qualified date-time, and all-day range as explicit variants.
- Preserve absence rather than inventing field values.
- Treat local and external identifiers as provenance fields, not guaranteed durable primary keys.
- Keep participant identities out of the source contract unless a later Board requirement proves they are necessary.
- Keep note-block handling observational until real prose/provider behavior is reviewed.

### Recommended pending runtime evidence

The smallest candidate Bridge-to-Core source representation would contain:

- entity type;
- bridge-scoped local identifier plus optional external identifier;
- selected container identity and mutability;
- optional source-created/source-modified instants;
- private title/notes only when required by mapping;
- explicit Reminder start/due temporal shapes, completion, priority, recurrence, and field-presence flags;
- explicit event temporal shape, all-day state, occurrence discriminator, status, availability, recurrence, and location presence;
- a content digest and sync-generation envelope only in Phase 3, not in this probe.

This is a provisional recommendation from the compiled surface and pure normalization tests. It is not stable enough to freeze until source observations establish optionality, provider caveats, and identity behavior.

### Unresolved

- actual provider categories present on this Mac;
- permission transitions and mixed granted/denied behavior;
- field optionality across selected providers;
- source mutability and subscribed/read-only behavior;
- Reminder date components as returned in practice;
- repeated completion history availability;
- recurring Reminder identity;
- recurring event occurrence and exception identity;
- cancellation/decline behavior;
- timezone and daylight-saving behavior;
- note prose around a candidate metadata block;
- which representative sanitized fixtures can be justified;
- the final Bridge-to-Core contract.

## Validation to complete on the Mac

The owner or a coding agent with interactive access must perform and record, without capturing private values:

1. first launch with permissions undetermined;
2. Calendar granted and Reminders denied;
3. Reminders granted and Calendar denied;
4. both granted;
5. previously denied access granted later through System Settings;
6. source selection persisted across relaunch;
7. selected source removed or made unavailable;
8. bounded private inspection export;
9. sanitized candidate generation and human review;
10. verification that the running probe opens no network socket;
11. source cases listed in Issue #6, marking unavailable cases `not tested` rather than fabricating them.

Only after that pass should representative files be committed under `fixtures/eventkit/`, the static EventKit-derived Board fixture/test be added, and the verified findings be reflected into `ARCHITECTURE.md`, `ROADMAP.md`, and the source-mapping document.
