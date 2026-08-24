# Deskboard Architecture

## Status

This document describes the intended architecture and the boundaries for the first several implementation slices. It is a working design, not a promise that every listed component will be built immediately.

The current implementation phase is **authenticated manual read-only Bridge delivery**. The strict Apple source contract and atomic Core mirror are accepted. The active Phase 3B review implementation connects them manually over loopback on the same Mac and is documented in [`docs/apple-bridge-manual-delivery.md`](docs/apple-bridge-manual-delivery.md). The Board remains fixture-backed, remote deployment is deferred, and Deskboard does not modify Calendar or Reminders.

## Architectural Thesis

Deskboard is a distributed system with **one authoritative owner for every piece of information**. It is not a distributed database in which every device can independently edit the same record.

- Apple Calendar owns Calendar events.
- Apple Reminders owns ordinary reminders.
- Deskboard Core will eventually own loop history, sessions, project state, and attention-selection state.
- Display clients own only disposable local caches and ephemeral UI state.
- The macOS Bridge transports and normalizes Apple data; it does not become another source of truth.

The operating rule is:

> **Replicate facts, not authority.**

## Initial System Shape

```text
                         APPLE / ICLOUD
               ┌───────────────────────────┐
               │ Calendar                  │
               │ Reminders                 │
               └─────────────┬─────────────┘
                             │ EventKit
                             ▼
                ┌──────────────────────────┐
                │ Deskboard Bridge         │
                │ macOS / SwiftUI          │
                │                          │
                │ • select sources         │
                │ • normalize records      │
                │ • push snapshots         │
                │ • report freshness       │
                └─────────────┬────────────┘
                              │ outbound HTTPS
                              │ over Tailscale
                              ▼
┌──────────────────────────────────────────────────────────┐
│                   DESKBOARD CORE                         │
│                    Ubuntu / CasaOS                       │
│                                                          │
│  source mirror        board composition       API       │
│  metadata parser      attention rules         storage   │
│                                                          │
│                      GET /v1/board                       │
└────────────────────────────┬─────────────────────────────┘
                             │
                    private HTTPS/Tailscale
                             │
            ┌────────────────┼─────────────────┐
            ▼                ▼                 ▼
        iPad PWA        Steam Deck         Future clients
        desk profile    desk profile       Android/E-Ink
```

The diagram is the intended private homelab topology, not the current deployment. Phase 3B proves the Bridge and Core boundary with both processes on the same Mac over loopback. Phase 3C owns Tailscale, remote deployment, Board composition from mirrored facts, and background operation.

## Components

### 1. Deskboard Web

**Technology:** React, TypeScript, and Vite, delivered as an installable Progressive Web App.

**Responsibilities:**

- render one calm, non-scrolling Board;
- adapt the same semantic layout to iPad and Steam Deck dimensions;
- render the server-selected explanation for every visible item;
- cache the most recently successful Board snapshot for display-only offline use;
- expose no source-management interface in the first phase.

**Non-responsibilities:**

- deciding which reminders deserve attention;
- interpreting Apple recurrence rules;
- owning source records;
- directly calling Apple services;
- becoming a general-purpose task manager;
- implementing separate navigation for Calendar, Reminders, or projects.

The first route is simply:

```text
/board
```

The web technology is a delivery mechanism. The experience should feel like a dedicated appliance rather than an open browser.

### 2. Deskboard Core

**Initial technology:** TypeScript and Fastify.

**Initial persistence:** Phase 3A introduced an isolated SQLite Apple source mirror. The fixture-backed Board and every other Core concern remain unchanged and non-persistent.

**Responsibilities:**

- expose the versioned Deskboard API;
- validate all contracts at runtime;
- hold normalized source snapshots once the Bridge exists;
- compose a display-ready Board snapshot;
- make attention decisions centrally so every client sees the same Board;
- eventually own Deskboard-native state such as sessions and loop history.

The client should receive a display-ready document instead of reproducing selection logic.

Illustrative shape:

```json
{
  "schemaVersion": 1,
  "boardVersion": "fixture-001",
  "generatedAt": "2026-08-21T17:00:00Z",
  "freshness": {
    "calendar": {
      "status": "fixture",
      "updatedAt": "2026-08-21T16:58:00Z"
    },
    "reminders": {
      "status": "fixture",
      "updatedAt": "2026-08-21T16:58:00Z"
    }
  },
  "today": {
    "label": "Today",
    "items": [
      {
        "id": "task-library-book",
        "kind": "task",
        "title": "Return the library book",
        "reason": "due today",
        "temporal": {
          "kind": "date",
          "localDate": "2026-08-21"
        }
      }
    ]
  },
  "next": {
    "label": "Next",
    "items": [
      {
        "id": "commitment-planning-call",
        "kind": "commitment",
        "title": "Fictional planning call",
        "reason": "first commitment tomorrow",
        "whenLabel": "Tomorrow · 9:30 AM",
        "temporal": {
          "kind": "dateTime",
          "localDateTime": "2026-08-22T09:30:00",
          "timeZone": "America/Los_Angeles"
        }
      }
    ]
  },
  "sidewaysPrompt": {
    "label": "Sideways",
    "text": "Ask what the room would notice if the plan became quieter."
  }
}
```

The exact contract will be established and tested in the first implementation slice.

### 3. macOS Bridge

**Technology:** Swift/SwiftUI using EventKit.

**Initial production mode:** outbound-only, read-only, sandboxed, and explicitly invoked.

**Responsibilities:**

- request explicit access to selected Calendar and Reminder sources;
- let the user whitelist which calendars and reminder lists are included;
- read a bounded range of Calendar events and selected reminders;
- preserve important temporal semantics such as all-day, date-only, local-time, and timezone-qualified values;
- normalize EventKit records directly into the accepted v1 contract;
- persist an opaque Bridge identity and source-scoped revision state;
- persist the exact pending delivery envelope before sending;
- retry the same envelope and revision after an uncertain response;
- authenticate outbound delivery without exposing Apple credentials;
- report content-free per-source status.

**Non-responsibilities during the first connected phase:**

- completing reminders;
- rescheduling or deleting events;
- exposing an inbound service on the Mac;
- background scheduling or launch-at-login behavior;
- collecting fields excluded from source contract v1;
- parsing every visible feature in Apple’s applications;
- continuously rewriting Reminder notes.

The Bridge will eventually become the only component permitted to perform approved Apple write-back. That capability is explicitly deferred until the one-way path is reliable.

### 4. Ubuntu Homelab and Tailscale

Deskboard Core is intended to run in a container on the existing Ubuntu/CasaOS host during Phase 3C, after manual loopback delivery is accepted.

The intended network posture is private:

- the API binds to the local host or container network;
- Tailscale provides remote connectivity;
- HTTPS is terminated through Tailscale Serve or an equivalently private reverse proxy;
- no public internet ingress is required;
- no Apple credentials are stored on the server;
- secrets are supplied at runtime and excluded from Git.

Phase 3B does not instantiate this topology. It keeps Bridge and Core on the same Mac over loopback.

## Data Ownership

| Information | Authoritative owner | Other copies |
|---|---|---|
| Calendar event | Apple Calendar | Normalized read-only mirror in Core |
| Ordinary reminder | Apple Reminders | Normalized read-only mirror in Core |
| Reminder completion | Apple Reminders | Deferred command/audit state in Core after write-back exists |
| Loop declaration | Initially Reminder note metadata or explicit Core configuration | Parsed mirror in Core |
| Loop engagement history | Deskboard Core | Derived summaries in Board snapshots |
| Session history | Deskboard Core | Display cache on clients |
| Project state | Deskboard Core | Optional links from source records |
| Attention selection | Deskboard Core | Current Board snapshot on clients |
| UI expansion/focus | Current client | Disposable |
| Cached Board | Current client | Disposable, never authoritative |

## Source Normalization

Apple objects should be stored first as normalized source records, not immediately collapsed into Deskboard tasks or projects.

Phase 2B defines the first source boundary in [`docs/apple-source-contract-v1.md`](docs/apple-source-contract-v1.md). It has two concrete, strict documents:

```text
AppleReminderSourceSnapshotV1
AppleCalendarSourceSnapshotV1
```

Each snapshot covers one opaque Bridge identity, one selected source container, one entity type, one capture time, and one deterministically ordered retained record set. Calendar additionally declares an offset-bearing `[start, end)` overlap window and the civil time zone used to interpret local and all-day values. Timezone-qualified Calendar records carry exact offset-bearing start/end instants plus a display time zone; civil display values are derived rather than used to reconstruct identity.

The v1 document carries exact matched count and truncation state. Only a runtime-validated non-truncated snapshot may assert absence inside its declared scope. A complete empty snapshot is authoritative for removing the old contents of that exact scope. A truncated, partial, failed, malformed, collision-bearing, or otherwise semantically invalid result cannot authorize deletion of unseen records. `records.length` supplies the retained count, and absence authority is derived rather than duplicated on the wire.

The ordering coordinate is total only when it is unique. Equal complete coordinates invalidate the candidate and preserve the previous good scope; Core must not choose from upstream order, merge, or discard colliding records.

The contract deliberately excludes source/account titles, notes, URLs, locations, participants, alarms, creation/modification times, complete recurrence grammar, normalization diagnostics, content hashes, synchronization generations, database identifiers, and transport/deployment metadata. Phase 3 operational data must remain outside the source-fact document.

A second mapping layer can later associate a validated source record with a Deskboard concept.

This separation matters because:

- imported facts should remain inspectable;
- Apple fields may evolve independently of Deskboard semantics;
- a Reminder is not automatically an Open Loop;
- later metadata parsers can be revised without losing the original normalized record;
- synchronization errors can be diagnosed without guessing what EventKit returned.

### Phase 3A atomic source mirror

The accepted Phase 3A implementation is specified in [`docs/apple-source-mirror.md`](docs/apple-source-mirror.md). It accepts an unknown candidate plus a positive operational source revision, validates the candidate through the accepted Phase 2B union, and derives a deterministic SHA-256 digest only from the normalized parsed document. Revision and digest remain Core delivery metadata; the accepted v1 source contract is unchanged.

Core stores one strict scope row per Bridge, entity, and selected container, with separate strict Reminder and Calendar record tables. Scope metadata and records commit in one SQLite transaction. Complete Reminder snapshots replace their entire exact scope. Complete Calendar snapshots replace only stored rows whose interpreted exact ranges overlap the declared `[start, end)` window; unobserved out-of-window rows remain stored and are excluded from the normal current-window read. Complete empty snapshots clear only those authoritative regions.

Invalid, truncated, stale, conflicting, or failed candidates do not change records, accepted revision, digest, timestamps, counts, or Calendar window. An equal revision with an equal digest is an idempotent no-op. Phase 3A performs no identity-history merge through EventKit provenance hints.

### Phase 3B authenticated manual delivery

The active Phase 3B implementation adds exactly one loopback-only ingestion boundary and one dedicated production Bridge, as specified in [`docs/apple-bridge-manual-delivery.md`](docs/apple-bridge-manual-delivery.md). Core authenticates a strict operational envelope before application, binds one configured bearer token to one opaque Bridge identity, and delegates all source replacement to the accepted Phase 3A mirror.

The Bridge stores its token in macOS Keychain and its identity, selections, acknowledged revisions, pending envelopes, and content-free status in the sandbox container. It persists the exact pending envelope before sending. A timeout, crash, relaunch, malformed response, or otherwise uncertain outcome retries that byte-equivalent envelope at the same revision; the Bridge does not reread EventKit and reuse the revision for changed content.

Only `applied` and `unchangedDuplicate` acknowledge a revision and clear pending state. Truncated, invalid, stale, conflict, and transport-failed outcomes preserve pending state and fail closed. Remote topology, background scheduling, Board composition, and Apple writes remain absent.

## Initial Apple Field Map

Phase 2A observations are recorded in [`docs/apple-eventkit-discovery.md`](docs/apple-eventkit-discovery.md). The inventory below remains empirical evidence and retains its original classifications. The Phase 2B inclusion/exclusion decision is separate in [`docs/apple-source-contract-v1.md`](docs/apple-source-contract-v1.md).

### Verified through selected sources

| Entity | Observed fields |
|---|---|
| both | local identifier presence, external identifier presence, selected container identity/category/mutability, title presence, creation/modification presence, alarm count |
| Reminder | absent/date-only/timezone-qualified start or due values, incomplete/completed state, completion date presence, notes presence, raw priority values `0` and `1` |
| Calendar | timed start **and** end, timezone-qualified time, exclusive all-day range, occurrence date, event identifier, recurrence structure, `none`/`confirmed` status, `busy`/`free`/`notSupported` availability, read-only/subscribed source state, location and structured-location presence |

### Available with caveats

- local and external identifiers are provenance fields; stability, duplication, and cross-device behavior remain unresolved;
- Calendar recurrence was observed, but detached exceptions were not;
- Reminder completion date is current-record evidence, not repeated completion history;
- Calendar status and availability were observed only for the categories listed above;
- participant properties remain privacy-reduced to organizer presence and attendee count, and no nonzero case was observed;
- Reminder notes were observed, but no candidate metadata block was present;
- creation and modification timestamps were present, but mutation behavior was not tested because the probe is read-only.

### Unavailable through the installed supported Reminder API

- tags;
- sections;
- subtasks;
- attachments.

Smart-list behavior and grocery categorization are also not source-contract fields.

### Not tested through selected sources

- Reminder recurrence, URL, and location;
- floating/local timed values without timezone identity;
- Calendar cancellation/decline, detached exceptions, and multi-day all-day ranges;
- participant presence and Calendar URL;
- identifier changes after Apple edits or synchronization.

## Temporal Semantics

The Apple source contract preserves these explicit variants:

```text
Reminder: absent | dateOnly | localDateTime | timeZoneDateTime
Calendar: localTimedRange | timeZoneTimedRange | allDayRange
```

All values use real Gregorian dates and real clocks. A local date-time cannot carry an offset. Timezone-qualified Calendar ranges use exact offset-bearing start/end instants and retain a time zone only for civil display context. Local/floating Calendar boundaries must each resolve to exactly one instant in the window zone; repeated and nonexistent civil times fail instead of choosing an occurrence. Timed and exclusive all-day ends must be later than their starts. Date-only Reminders and all-day Calendar ranges remain civil values; they are not flattened to UTC.

## Synchronization

### Phase A: Fixture path

```text
Versioned fixture
      ↓
Deskboard Core
      ↓
GET /v1/board
      ↓
iPad and Steam Deck
```

This proves the contract and display before introducing private data or Apple-specific behavior.

### Phase B: Apple read path

```text
Apple data changes
      ↓
iCloud reaches Mac
      ↓
Bridge performs an explicit bounded read
      ↓
Bridge persists a pending source envelope
      ↓
Bridge sends the authenticated envelope over loopback
      ↓
Core validates and atomically applies that source scope
      ↓
Phase 3C later composes a new Board version
```

The first Bridge implementation uses understandable bounded snapshots rather than clever incremental synchronization. Operational revisions and pending-delivery state wrap the accepted source contract without changing its source meaning.

Atomic replacement is allowed only after the complete document passes strict and semantic validation. Items missing from a non-truncated snapshot may be marked absent only inside that exact Bridge, entity, container, and Calendar-window scope. A truncated or failed replacement must retain unseen source data. An uncertain transport response must retry the same persisted envelope and revision rather than create a different candidate under the same revision.

### Phase C: One write path, later

After the read path is stable, the first and only Apple write action will be completing an ordinary Reminder.

```text
Deskboard action
      ↓
Core queues command
      ↓
Bridge pulls command
      ↓
Bridge verifies current Apple item
      ↓
Bridge completes Reminder through EventKit
      ↓
Normal read synchronization confirms the result
```

Calendar remains read-only during this phase.

## Board Composition

The Board is not a projection of every available source record. It is a constrained composition.

The first Board has only:

- a header and source-freshness state;
- a small Today section based on fixture reminders;
- a small Next section based on fixture Calendar events;
- a Sideways Prompt;
- optional empty states.

Initial capacity limits should be explicit and testable, for example:

- no more than three Today items;
- no more than two Next commitments;
- exactly zero vertical scrolling at target viewports;
- one prompt only when room exists.

Every visible item should include a human-readable reason chosen by the Core, such as:

- `due today`
- `overdue from yesterday`
- `in 90 minutes`
- `all day`

The first ranking logic should be deterministic. No AI or opaque score belongs in Board composition.

## Client Update and Offline Behavior

The initial client update mechanism is intentionally simple:

- fetch on load;
- poll every 30–60 seconds while visible;
- pause or reduce polling when the document is hidden;
- retain the most recent valid Board snapshot in local storage or IndexedDB;
- display cached content immediately on launch;
- make staleness visible when the Core cannot be reached.

WebSockets, Server-Sent Events, background push, and offline mutations are deferred until polling is shown to be inadequate.

## API Principles

- Prefix versioned endpoints with `/v1`.
- Validate requests and responses at runtime.
- Share generated or source-controlled TypeScript contracts between API and web client.
- Treat Board snapshots as immutable documents identified by version.
- Use ISO 8601 for instants and explicit structures for date-only values.
- Return structured errors with stable codes.
- Do not expose raw EventKit payloads to display clients.
- Do not expose secrets, private notes, attendees, or source identifiers to display clients.
- Keep mutation endpoints absent until their phase begins.

The display API remains:

```text
GET /health
GET /v1/board
```

Phase 3B adds exactly one authenticated internal ingestion route, available only when explicitly configured while the API remains bound to loopback:

```text
POST /v1/apple-source-snapshots
```

The ingestion route is not a web-client API and exposes no mirror read method.

## Security and Privacy

- The repository must contain no real Calendar, Reminder, health, recovery, household, or contact data.
- Fixtures must be synthetic.
- `.env` files, credentials, Tailscale details, database files, pending envelopes, and exported source snapshots are ignored by Git.
- The Bridge whitelists source containers rather than ingesting every Calendar and Reminder list.
- The production Bridge is sandboxed, read-only, and has no inbound network service.
- The Bridge bearer token lives in macOS Keychain and appears only in the Authorization header.
- Core authenticates before applying the ingestion body and binds the token to one opaque Bridge identity.
- Core and Bridge logs use content-free operational status rather than private records.
- Future family-facing profiles should use explicit allowlists; private information is excluded by default.
- Future agent actions must pass through the same audited API as all other clients.
- No client or agent should receive direct database access.

## Repository Shape

The first coding slice established the TypeScript monorepo. Connected native code is added only in its active slice.

```text
deskboard/
├── apps/
│   ├── web/                 React + TypeScript + Vite
│   └── api/                 Fastify + TypeScript
│
├── packages/
│   └── contracts/           Runtime schemas and shared types
│
├── fixtures/
│   ├── board/               Synthetic Board examples
│   ├── eventkit/            Approved sanitized discovery evidence
│   └── apple-source-contract/ Strict cross-language source fixtures
│
├── native/
│   └── apple-bridge/        Dedicated production macOS Bridge and tests
├── tools/
│   └── apple-eventkit-probe/ Contained discovery probe
├── .github/
│   └── workflows/           Complete quality gate
│
├── ARCHITECTURE.md
├── MANIFESTO.md
├── ROADMAP.md
└── README.md
```

Do not scaffold empty packages for future ideas.

## Testing Strategy

### Contract tests

Prove that:

- fixture Board snapshots satisfy the runtime schema;
- invalid temporal values are rejected;
- API responses match the shared contract;
- the web client handles unsupported schema versions safely.

### Apple source contract tests

Phase 2B independently proves in TypeScript and Swift that:

- the exact same versioned synthetic fixture allowlist is used;
- every valid Reminder and Calendar snapshot passes;
- every invalid snapshot fails;
- unknown keys fail at every strict object boundary;
- dates, clocks, ranges, completion, counts, truncation, order, and Calendar scope are semantic invariants;
- timezone-qualified Calendar ranges preserve exact instants, while ambiguous/nonexistent local ranges fail;
- complete ordering-coordinate collisions fail rather than inherit upstream order;
- complete empty Reminder and Calendar scopes authorize absence only after strict runtime validation;
- truncated snapshots never authorize absence;
- the accepted Phase 2A specimen allowlist continues to decode without accessing private fixtures.

### Atomic mirror tests

Phase 3A proves:

- valid authoritative snapshots apply atomically;
- invalid, truncated, stale, conflicting, and failed candidates preserve previous good state;
- duplicate delivery is idempotent;
- Reminder scopes replace completely;
- Calendar overlap windows preserve unobserved out-of-window rows;
- destructive failure rolls metadata and records back;
- migrations and close/reopen persistence are repeatable.

### Manual Bridge delivery tests

Phase 3B must prove:

- one strict authenticated route applies through the accepted mirror;
- authentication and Bridge-ID binding fail before private application;
- converter output includes only accepted v1 fields;
- exact temporal, ordering, count, collision, and truncation semantics are preserved;
- source selections remain separate and empty by default;
- Bridge identity, revisions, credentials, and pending delivery survive relaunch;
- timeout or crash retries the exact persisted envelope and revision;
- applied and duplicate results acknowledge once, while other results fail closed;
- the production target is sandboxed with outbound-only network behavior and no EventKit writes;
- the manual local proof reports only masked counts and result kinds.

### Component/accessibility tests

Prove that:

- sections have meaningful headings;
- all visible content is keyboard reachable where interaction exists;
- no information relies only on color;
- reduced-motion preferences are respected;
- loading, empty, stale, and error states are understandable.

### Browser proof tests

At minimum, capture or assert the Board at representative viewports:

- iPad landscape: `1366 × 1024` CSS-pixel reference viewport;
- Steam Deck: `1280 × 800`;
- a narrower portrait sanity check.

The proof should assert that the target Board has no document-level vertical overflow at the two primary viewports.

## Decision Boundaries

The following choices are intentional for the opening phases:

| Concern | Initial decision |
|---|---|
| Front end | React + TypeScript + Vite PWA |
| Server | Fastify + TypeScript |
| Monorepo | npm workspaces unless a concrete need suggests otherwise |
| Database | none for the Phase 1 Board; isolated SQLite Apple source mirror from Phase 3A |
| Phase 3B topology | same-Mac loopback only |
| Later private access | Tailscale in Phase 3C |
| Live updates | ordinary polling after Board integration |
| Apple integration | sandboxed outbound EventKit Bridge |
| Calendar writes | deferred |
| Reminder writes | deferred until one explicit completion slice |
| AI | absent from selection logic |
| Home Assistant | deferred |
| Native mobile clients | deferred |

## Change Rule

A proposed architectural dependency should answer all three questions:

1. Which current slice requirement does it satisfy?
2. Why is the existing simpler mechanism insufficient?
3. What maintenance burden does it add?

If the first answer is “a future feature,” the dependency does not belong in the current slice.
