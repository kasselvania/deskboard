# Deskboard Architecture

## Status

This document describes the intended architecture and the boundaries for the first several implementation slices. It is a working design, not a promise that every listed component will be built immediately.

The current product phase is **read-only bulletin board**. Apple Calendar and Apple Reminders will eventually supply data to Deskboard, but Deskboard will not initially modify either source.

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

The implementation begins with only the lower half of this diagram: a fixture-backed API and Board. The macOS Bridge arrives only after the display contract is proven.

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

**Initial persistence:** none beyond fixtures. SQLite is introduced only when real source snapshots or Deskboard-owned state need persistence.

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

**Initial mode:** outbound-only and read-only.

**Responsibilities:**

- request explicit access to selected Calendar and Reminder sources;
- let the user whitelist which calendars and reminder lists are included;
- read a bounded range of Calendar events and selected reminders;
- preserve important temporal semantics such as all-day, date-only, local-time, and timezone-qualified values;
- normalize EventKit records into the Bridge contract;
- push complete, bounded synchronization snapshots to Deskboard Core;
- report sync status and errors without exposing iCloud credentials to the homelab.

**Non-responsibilities during the first connected phase:**

- completing reminders;
- rescheduling or deleting events;
- exposing an inbound service on the Mac;
- parsing every visible feature in Apple’s applications;
- continuously rewriting Reminder notes.

The Bridge will eventually become the only component permitted to perform approved Apple write-back. That capability is explicitly deferred until the one-way path is reliable.

### 4. Ubuntu Homelab and Tailscale

Deskboard Core is intended to run in a container on the existing Ubuntu/CasaOS host.

The initial network posture is private:

- the API binds to the local host or container network;
- Tailscale provides remote connectivity;
- HTTPS is terminated through Tailscale Serve or an equivalently private reverse proxy;
- no public internet ingress is required;
- no Apple credentials are stored on the server;
- secrets are supplied at runtime and excluded from Git.

The system should remain usable on the local network even if a public cloud service is unavailable.

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

A source record needs enough identity and provenance to be reconciled and debugged:

```text
adapter                 apple-eventkit
entity type             event | reminder
bridge identity         which Mac/bridge supplied it
local source ID         EventKit local identifier
external source ID      cross-device reconciliation hint
container ID            calendar or reminder list
source created time
source modified time
content hash
normalized payload
last-seen sync generation
```

A second mapping layer can associate a source record with a Deskboard concept.

This separation matters because:

- imported facts should remain inspectable;
- Apple fields may evolve independently of Deskboard semantics;
- a Reminder is not automatically an Open Loop;
- later metadata parsers can be revised without losing the original normalized record;
- synchronization errors can be diagnosed without guessing what EventKit returned.

## Initial Apple Field Map

The exact inventory will be verified through an EventKit spike. The first connected implementation should expect at least the following public concepts.

### Common fields

- local item identifier
- external item identifier when available
- source container/list
- title
- notes
- location
- URL/reference
- created and last-modified dates
- timezone information
- recurrence rules
- alarms

### Reminder-specific fields

- available/start date components
- due date components
- priority
- completion state
- completion date

### Calendar-event-specific fields

- start and end
- all-day state
- recurring occurrence identity
- status/cancellation state
- availability
- structured location
- organizer and attendees where available

Not every feature visible in the Apple Reminders UI is guaranteed to be exposed through the supported EventKit API. Tags, sections, subtasks, smart-list behavior, grocery categorization, and attachments must not become architectural dependencies until the Bridge spike proves their availability and behavior.

## Temporal Semantics

Dates must not be flattened carelessly.

Deskboard should distinguish at least:

```text
date-only              Friday, with no clock time
local date-time        Friday at 9:00 in the user’s local context
timezone-qualified     Friday at 9:00 America/Los_Angeles
all-day event          an event spanning a local calendar day
```

Illustrative normalized values:

```json
{
  "kind": "date",
  "localDate": "2026-08-22"
}
```

```json
{
  "kind": "dateTime",
  "localDateTime": "2026-08-22T09:00:00",
  "timeZone": "America/Los_Angeles"
}
```

A date-only Reminder must not move to the previous day because a client converted it to UTC.

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
EventKit change signal or scheduled refresh
      ↓
Bridge performs a bounded rescan
      ↓
Bridge posts a complete sync generation
      ↓
Core validates and atomically replaces that source scope
      ↓
Core composes a new Board version
      ↓
Clients fetch the updated Board
```

The first Bridge implementation should prefer understandable bounded snapshots over clever incremental synchronization.

A sync generation should be atomic for its declared scope. Items missing from a completed generation can be marked absent only after the generation succeeds; a partially failed upload must not delete previously known source data.

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
- Do not expose secrets, private notes, attendees, or source identifiers unless the Board needs them.
- Keep mutation endpoints absent until their phase begins.

Initial endpoints should be no broader than:

```text
GET /health
GET /v1/board
```

A development-only fixture selector may exist behind an environment flag, but it should not become a production API feature.

## Security and Privacy

- The repository must contain no real Calendar, Reminder, health, recovery, household, or contact data.
- Fixtures must be synthetic.
- `.env` files, credentials, Tailscale details, database files, and exported source snapshots are ignored by Git.
- The Bridge should whitelist source containers rather than ingesting every Calendar and Reminder list.
- The Core should log metadata and errors without logging entire private records by default.
- Future family-facing profiles should use explicit allowlists; private information is excluded by default.
- Future agent actions must pass through the same audited API as all other clients.
- No client or agent should receive direct database access.

## Repository Shape

The first coding slice should establish approximately this structure:

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
│   └── board/               Synthetic Board and source examples
│
├── .github/
│   └── workflows/           CI after implementation begins
│
├── ARCHITECTURE.md
├── MANIFESTO.md
├── ROADMAP.md
└── README.md
```

The macOS Bridge should be added only when its slice begins:

```text
apps/mac-bridge/
```

Do not scaffold empty packages for every future idea.

## Testing Strategy

### Contract tests

Prove that:

- fixture Board snapshots satisfy the runtime schema;
- invalid temporal values are rejected;
- API responses match the shared contract;
- the web client handles unsupported schema versions safely.

### Unit tests

Prove that:

- capacity limits are enforced;
- ordering is deterministic;
- reasons are generated correctly for fixture cases;
- date-only and timezone-qualified values remain distinct.

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

### Integration tests, later

The EventKit Bridge should export sanitized fixtures for representative cases:

- date-only Reminder;
- timed Reminder;
- completed Reminder;
- all-day event;
- timed event;
- recurring event occurrence;
- cancelled event;
- malformed Deskboard note metadata.

## Decision Boundaries

The following choices are intentional for the opening phases:

| Concern | Initial decision |
|---|---|
| Front end | React + TypeScript + Vite PWA |
| Server | Fastify + TypeScript |
| Monorepo | npm workspaces unless a concrete need suggests otherwise |
| Database | none in slice 1; SQLite when persistence becomes necessary |
| Cloud | none required |
| Private access | Tailscale |
| Live updates | ordinary polling |
| Apple integration | EventKit through outbound macOS Bridge |
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
