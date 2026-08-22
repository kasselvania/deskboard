# Apple EventKit Discovery — Phase 2A

## Status

The empirical Phase 2A evidence pass is complete for the source cases listed as verified below. On 2026-08-21, the owner approved the twelve sanitized fixtures at the fixture/evidence review gate. Phase 2A was accepted and merged in PR [#7](https://github.com/kasselvania/deskboard/pull/7) on 2026-08-22. This report records the accepted empirical evidence; it does not freeze a production Bridge contract or begin Phase 3.

The source-shape recommendation in this report is evidence for active Phase 2B issue [#8](https://github.com/kasselvania/deskboard/issues/8). The draft Phase 2B decision is documented separately in [`apple-source-contract-v1.md`](apple-source-contract-v1.md); it deliberately minimizes the probe models rather than renaming them as production types. This empirical report and all `verified`, `available with caveats`, `unavailable`, and `not tested` classifications remain unchanged.

This report uses four evidence labels:

- **verified** — directly observed through the built probe or proved by a named pure test;
- **available with caveats** — observed, but optionality, durability, provider behavior, or semantics remain unresolved;
- **unavailable** — absent from the supported installed EventKit SDK surface;
- **not tested** — no qualifying selected-source observation was obtained.

Compiler availability alone is not runtime evidence. No private value is reproduced in this report.

## Environment

| Item | Value | Evidence |
|---|---|---|
| macOS | 26.4.1 (25E253) | `sw_vers` |
| Xcode | 26.4.1 (17E202) | `xcodebuild -version` |
| Swift compiler | Apple Swift 6.3.1 | `xcrun swift -version` |
| Swift language mode | Swift 5 | project build settings |
| macOS SDK | 26.4 | `xcodebuild -showsdks` |
| deployment target | macOS 14.0 | project build settings and built product |
| selected Calendar provider categories | modifiable CalDAV, read-only CalDAV, read-only subscribed | verified without source names |
| selected Reminder provider categories | modifiable CalDAV | verified without source names |
| enumerated but not read | birthdays Calendar category | verified enumeration only |

## Probe and privacy boundary

The contained project is `tools/apple-eventkit-probe/AppleEventKitProbe.xcodeproj`. It has one macOS SwiftUI app, a narrow command mode in the same executable, and one native unit-test target. It adds no Swift package, project generator, database, HTTP client, daemon, login item, Apple write call, or Deskboard Core path.

The project sets `ENABLE_APP_SANDBOX = NO` so this contained local probe can use its explicit repository-root export path under ignored `private-fixtures/`. This is a probe/export convenience, not an approved security posture or implementation precedent for the production macOS Bridge. The production Bridge's sandbox, entitlement, and export-boundary decisions remain deferred to a separate security and architecture review.

The command mode exists because macOS accessibility inspection of the development build was unreliable. It emits only:

- permission states;
- masked source ordinals and structural categories;
- selected ordinal counts;
- sanitized field-presence summaries;
- fixed relative export paths.

It never emits source titles, identifiers, event or Reminder titles, notes, URLs, locations, account names, or participant details. Pure tests encode private-shaped inputs and verify that neither sanitized candidates nor safe reports retain those values.

A confirmed private export containing one Reminder and one Calendar record was written to `private-fixtures/eventkit-probe/private-inspection-latest.json`. Only file existence, record counts, and `git check-ignore` behavior were inspected. The file contents were never opened or printed. The repository's `private-fixtures/` rule ignores it.

With the tested app running and no sources selected, `lsof -nP -a -p <pid> -i` returned no network socket. The app was then closed.

## Permissions

### APIs and configuration

| Entity | API | Status |
|---|---|---|
| Calendar | `EKEventStore.authorizationStatus(for: .event)` | verified |
| Calendar | `requestFullAccessToEvents(completion:)` | verified |
| Reminders | `EKEventStore.authorizationStatus(for: .reminder)` | verified |
| Reminders | `requestFullAccessToReminders(completion:)` | verified |

The built `Info.plist` includes `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription`. On macOS 14 and later, modern EventKit requires **Full Access** authorization for an app to read Calendar events and Reminders through these APIs. `Full Access` is Apple's authorization-tier name, not a description of this probe's behavior: the probe exposes no write action and contains no EventKit save or remove call, so its use of the authorized stores remains read-only.

### Observed behavior

| Case | Status | Observation |
|---|---|---|
| first launch, permissions not determined | verified | owner observed separate intentional request controls; the probe did not request automatically |
| Calendar granted, Reminders denied | verified | owner observed the mixed state and the Calendar side remained usable |
| Reminders granted, Calendar denied | not tested | the safe command observed Reminders granted with Calendar `notDetermined`, not denied |
| both granted | verified | safe command returned `granted` for both entities |
| denied access later granted in System Settings | available with caveats | owner changed the setting and a later safe command reported Reminders granted; exact transition timing was not instrumented |
| app activation/process relaunch refresh | verified | safe status and source commands reflected the current authorization state across separate launches |
| restricted or unavailable environment | not tested | no managed or restricted environment was available |

Denied and unavailable states do not disable the other entity. The app shows a System Settings route after denial and never automatically repeats a permission request.

## Source selection and bounded reads

The safe inventory found Calendar containers in CalDAV, subscribed, and birthdays categories and Reminder lists in CalDAV. No names or identifiers were printed.

The following behavior is verified:

- Calendar and Reminder selections defaulted to empty;
- Calendar and Reminder selections used separate preference keys;
- explicit masked ordinals persisted across separate process launches;
- only selected identifiers were passed to EventKit predicates;
- Calendar reads used a 7-day-back, 45-day-forward window;
- Calendar results are ordered by start, end, container identifier, Calendar item identifier, and finally event identifier before the cap is applied;
- Reminder reads used only selected lists;
- retained records were capped at 200 per entity;
- a 200-record Reminder result reported truncation rather than silently claiming completeness;
- authorization or effective source-selection changes invalidate the captured in-memory inspection before it can be exported;
- losing permission clears available-source presentation and inspection data without erasing saved source identifiers;
- both selections were cleared after discovery;
- pure tests reconciled a disappeared identifier without affecting the other entity.

Removing a real source was not safe or necessary, so live disappearance behavior remains **not tested**. Only the injected-preference reconciliation behavior is verified.

## Verified field inventory

### Reminder fields

| Source field | Status | Evidence and caveat |
|---|---|---|
| local identifier | available with caveats | present on observed records; edit, sync, and long-term stability not tested |
| external identifier | available with caveats | present on committed specimens; duplication and cross-device stability not tested |
| title | verified | present on observed records and replaced with deterministic synthetic titles |
| notes | available with caveats | presence and absence observed; private text was never inspected, and metadata coexistence was not observed |
| Reminder list/container | verified | CalDAV category, mutability, selection identity, and source category observed |
| start/availability components | verified | absent and timezone-qualified start components observed |
| due components | verified | absent, date-only, and timezone-qualified date-time due values observed |
| priority | available with caveats | raw values `0` and `1` observed; semantic consistency was not tested |
| completion state | verified | incomplete and completed records observed |
| completion date | available with caveats | present on completed specimens; no repeated completion history is exposed or claimed |
| recurrence rules | not tested | no selected Reminder returned a recurrence rule |
| alarms | verified | zero and nonzero alarm counts observed |
| creation date | available with caveats | present on specimens; provider consistency not tested |
| modification date | available with caveats | present on specimens; mutation behavior not tested because the probe is read-only |
| URL/reference | not tested | no selected specimen with a URL was retained |
| location | not tested | no selected Reminder location was retained |
| tags | unavailable | no supported EventKit Reminder property in the installed SDK |
| sections | unavailable | no supported EventKit Reminder property in the installed SDK |
| subtasks | unavailable | no supported EventKit Reminder property in the installed SDK |
| attachments | unavailable | no supported EventKit Reminder property in the installed SDK |

### Calendar fields

| Source field | Status | Evidence and caveat |
|---|---|---|
| local identifier | available with caveats | calendar-item and event identifiers were present; durability not tested |
| external identifier | available with caveats | present on specimens; recurring sharing and cross-device behavior not tested |
| title | verified | present on observed events and replaced deterministically |
| source calendar/container | verified | modifiable CalDAV, read-only CalDAV, and read-only subscribed sources observed |
| start and end | verified | timed events retain distinct start and end local date-times; one-hour and long-running durations were observed |
| all-day state | verified | single-day all-day events used an exclusive end date |
| multi-day all-day range | not tested | no selected source returned one; the pure normalizer test proves representation only |
| occurrence identity/date | available with caveats | local ID, event ID, external ID, and occurrence date were present; uniqueness and durability not tested |
| recurrence rules | available with caveats | recurring occurrences and detailed yearly structure observed; exception identity not observed |
| status/cancellation | available with caveats | `none` and `confirmed` observed; `canceled` and declined behavior not observed |
| availability | available with caveats | `busy`, `free`, and `notSupported` observed; selection semantics are unresolved |
| location/structured location | verified | absent and present values observed; private values were replaced with `Example Location` |
| organizer and attendees | not tested | only false/zero structural results were observed; identities are intentionally never copied |
| notes | verified | presence and absence observed; values were destructively replaced |
| URL | not tested | no retained selected specimen contained a URL |
| alarms | verified | zero and nonzero alarm counts observed |

## Identity findings

Observed Calendar records exposed `calendarItemIdentifier`, `eventIdentifier`, `calendarItemExternalIdentifier`, and `occurrenceDate`. Observed Reminder records exposed `calendarItemIdentifier` and `calendarItemExternalIdentifier`.

A recurring Calendar occurrence exposed all four Calendar identity fields plus recurrence structure. This proves field availability, not a stable compound key. The probe performed no Apple edits and never printed raw identifiers, so it did not test:

- identifier changes after edits or synchronization;
- external-ID duplication;
- uniqueness across recurring occurrences;
- detached exception identity;
- cross-device reconciliation.

Recommendation: carry bridge-scoped local identity, optional external identity, and Calendar occurrence date as separate provenance fields. Do not treat any one observed identifier as a universal durable primary key.

## Temporal findings

### Reminders

- date-only due values returned date components without clock fields and normalized to `dateOnly`;
- timed start/due values returned timezone-bearing components and normalized to `timeZoneDateTime`;
- absent start/due values remained absent;
- floating/local timed Reminder components were not observed;
- no value was flattened to UTC.

### Calendar

- timed events exposed both start and end and a timezone-qualified local representation;
- observed timed durations included one hour and a longer multi-day timed span;
- single-day all-day events normalized to an exclusive `[startDate, endDate)` range;
- no multi-day all-day event was observed;
- recurring all-day and timed occurrences were observed;
- no detached recurrence exception or daylight-saving transition case was observed.

Pure tests additionally prove rejection of malformed Reminder components and preservation of a synthetic multi-day all-day boundary. Those tests do not convert an unobserved source case into runtime evidence.

## Reminder behavior

Selected CalDAV lists produced incomplete and completed Reminders, date-only and timed due values, notes presence, raw priority values `0` and `1`, alarm counts, identifiers, and container mutability.

Completion is current-record evidence only. EventKit exposed `isCompleted` and an optional `completionDate`; no repeated completion-history collection was observed. No selected Reminder returned recurrence, so recurrence/completion interaction remains unresolved.

The 200-record cap was reached on two selected lists. Truncation was reported explicitly. The probe did not infer that records beyond the cap shared the retained sample's shapes.

Tags, sections, subtasks, and attachments remain unavailable through the installed supported EventKit Reminder surface. Smart-list and other Reminders-UI behavior are not part of the source contract.

## Calendar behavior

Selected sources produced:

- modifiable and read-only CalDAV events;
- read-only subscribed events;
- timed and all-day events;
- recurring occurrences;
- `none` and `confirmed` status values;
- `busy`, `free`, and `notSupported` availability values;
- location and structured-location presence;
- alarm presence.

No selected event was cancelled, detached, or a multi-day all-day range. No participant presence was observed, and participant identities were intentionally excluded from every representation.

## Metadata-block observations

No selected Reminder contained a `[deskboard:v1]` delimiter pair. Therefore:

- prose-before/prose-after coexistence is **not tested** against a source record;
- no `reminder-with-deskboard-block.json` fixture is committed;
- no production parser grammar, unknown-field rule, or write-back behavior is frozen.

Pure tests verify only delimiter detection: one ordered pair, surrounding-prose flags, malformed missing delimiters, duplicate delimiters, and unsupported versions. The detector never parses fields or rewrites notes.

## Sanitized fixtures

The following candidates were generated from observed source shapes, reviewed in full through the local fixture packet, and approved by the owner for commit:

### Reminders

- `reminder-undated.json` — incomplete, no temporal value;
- `reminder-date-only.json` — incomplete, date-only due value;
- `reminder-timed.json` — timezone-qualified due value;
- `reminder-with-notes.json` — notes present;
- `reminder-priority.json` — nonzero source priority;
- `reminder-completed.json` — completed with completion date.

### Calendar

- `event-timed.json` — explicit timed start and end;
- `event-all-day.json` — exclusive single-day all-day range;
- `event-timezone.json` — timezone-qualified long-running event;
- `event-recurring-occurrence.json` — recurrence and occurrence identity;
- `event-read-only-source.json` — read-only CalDAV source;
- `event-with-location.json` — location and structured-location presence.

Omitted because unobserved:

- `reminder-with-deskboard-block.json`;
- `reminder-recurring.json`;
- `event-multi-day.json`;
- `event-cancelled.json`.

No bulk export is committed.

The approved fixture set contains 12 files totaling 11,969 bytes. Its combined SHA-256 is `d7f138203445751910fe7e995814ac9d8bf1f92d74bc632b8a43fee31598b776`, calculated over the raw fixture bytes concatenated in the documented allowlist order. Immediately after approval, every per-file byte count and SHA-256 matched the ignored local review manifest. The review generator did not access the private EventKit export.

A native test enumerates JSON files only in the two committed specimen directories, compares them with this exact twelve-path allowlist, and decodes each file as its concrete `ReminderProbeRecord` or `EventProbeRecord` type. The test has no path or operation that accesses `private-fixtures/`.

## Existing Board proof

`fixtures/board/eventkit-derived.json` uses the unchanged Phase 1 contract to render:

- one incomplete undated Reminder-derived Task;
- one incomplete date-only Reminder-derived Task;
- one timed Calendar Commitment;
- one all-day Calendar Commitment.

The focused component test renders all four synthetic items and confirms that the Board exposes no button or link. No production fixture selector, route, endpoint, Apple adapter, action, setting, or navigation was added.

## Phase 2A Recommendations for Phase 2B

These recommendations summarize the observed evidence. Phase 2B must minimize and validate the versioned source contract; the structures below are not frozen production types.

### Verified constraints

- Keep Calendar and Reminder source records separate.
- Keep Calendar and Reminder source selections separate and default them to empty.
- Preserve absence instead of inventing values.
- Preserve Reminder `dateOnly`, `localDateTime`, and `timeZoneDateTime` variants.
- Preserve Calendar timed start **and** end, timezone identity when present, and exclusive all-day ranges.
- Treat recurrence as a source schedule fact, not an Open Loop classification.
- Keep organizer and attendee identities out of the initial source contract.
- Treat local and external identifiers as provenance with unresolved durability.

### Smallest recommended Bridge-to-Core source representation

The later one-way mirror should carry two versioned record variants, not a generic adapter envelope.

A Reminder source record needs:

- bridge-scoped local identifier and optional external identifier;
- selected list identity, provider category, and mutability;
- optional title, notes, creation time, and modification time;
- optional start and due values using explicit temporal variants;
- completion state and optional completion date;
- raw source priority;
- optional recurrence structure;
- alarm count plus URL/location presence only if later Board mapping needs them.

A Calendar source record needs:

- bridge-scoped local identifier, optional event identifier, and optional external identifier;
- selected calendar identity, provider category, subscription state, and mutability;
- optional title, notes, creation time, and modification time;
- timed start/end or exclusive all-day start/end, with timezone identity when present;
- optional occurrence date and detached flag;
- status, availability, optional recurrence structure, alarm count, and location presence.

Content digests, synchronization generations, Core persistence, and transport belong to Phase 3. They are absent from this probe and from the bounded Phase 2B contract slice.

### Phase 2B draft resolution

The draft v1 contract adopts only the fields with a first-mirror use:

- one opaque Bridge ID and one selected container ID per snapshot;
- container mutability and Calendar subscription state, without source/account titles or provider identifiers;
- bridge-and-container-scoped local identity plus optional external identity;
- optional Calendar event identity and occurrence date as separate provenance facts;
- optional record title;
- explicit Reminder start/due temporal variants, completion state, and optional completion date;
- required Calendar temporal range, detached state, and normalized status;
- exact matched count, deterministic retained order, and explicit truncation;
- an exact start-inclusive/end-exclusive Calendar overlap window.

Notes, priority, recurrence grammar, alarms, URLs, locations, availability, participant fields, creation/modification timestamps, metadata-block observations, and normalization warnings do not enter v1. A valid non-truncated source snapshot may assert absence only inside its declared Bridge, entity, container, and Calendar-window scope. Truncated or failed replacement cannot authorize deletion. See [`apple-source-contract-v1.md`](apple-source-contract-v1.md) for the exhaustive matrix and Phase 3 atomic replacement rules.

Contract support for local timed values, multi-day all-day ranges, detached events, and tentative/canceled status is not new empirical evidence. Those Phase 2A cases remain `not tested` where recorded above.

### Unresolved

- exact Calendar-denied/Reminders-granted behavior;
- restricted/unavailable authorization behavior;
- live source disappearance behavior;
- identifier stability after Apple edits, synchronization, and relaunch;
- duplicate external identifiers;
- floating/local timed values from selected sources;
- multi-day all-day and daylight-saving boundaries from selected sources;
- Reminder recurrence and repeated completion history;
- recurrence exceptions and detached Calendar identity;
- cancellation and declined behavior;
- Reminder URL/location behavior;
- participant presence behavior;
- metadata-block coexistence with real prose;
- provider consistency beyond selected CalDAV and subscribed sources;
- final Phase 3 transport envelope and persistence key.

## Manual validation record

| Check | Result |
|---|---|
| first launch, not determined | owner observed |
| Calendar granted / Reminders denied | owner observed |
| Reminders granted / Calendar denied | not tested; Calendar `notDetermined` was observed instead |
| both granted | passed by safe status command |
| denial changed later in System Settings | passed with timing caveat |
| source selection across relaunch | passed across separate command launches |
| selected source removed/unavailable | pure reconciliation test passed; live removal not tested |
| private inspection export | passed; one record per entity, contents never opened |
| sanitized candidate generation | passed; stale candidate JSON cleanup tested |
| no network traffic | passed; running process had no network socket |

## Reproducible commands

### Automated validation record

On 2026-08-21, the documented native command built successfully and all 27 Swift tests passed. That count includes five deterministic Calendar ordering/cap tests, two inspection-scope invalidation tests, and one exact committed-fixture allowlist/decoding test. Under Node 24.19.0, `npm ci` and `npm run check` passed: lint, all workspace typechecks, 31 unit tests, all production builds, and Playwright with 5 passed and 1 intentional portrait skip. `git diff --check` passed.

Native build and test:

```bash
xcodebuild \
  -project tools/apple-eventkit-probe/AppleEventKitProbe.xcodeproj \
  -scheme AppleEventKitProbe \
  -destination 'platform=macOS' \
  build test
```

Isolated derived data used during discovery:

```bash
xcodebuild \
  -project tools/apple-eventkit-probe/AppleEventKitProbe.xcodeproj \
  -scheme AppleEventKitProbe \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/deskboard-eventkit-command-derived-2 \
  build test
```

Repository gate:

```bash
source /Users/peterkassel/.nvm/nvm.sh
nvm use
npm ci
npm run check
git diff --check
```

The private command and generated export are intentionally not included in CI. Native unit tests use synthetic data only and never require the user's EventKit store.
