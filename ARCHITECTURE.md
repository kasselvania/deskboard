# Deskboard Architecture

## Status

The accepted product is a **read-only Apple attention surface**.

Phases 1 through 3C are accepted. Deskboard can now:

- read explicitly selected Calendar and Reminder sources through a signed, sandboxed macOS Bridge;
- convert only privacy-minimized fields into strict versioned source documents;
- deliver source and content-free status envelopes manually and idempotently;
- persist them atomically in Core;
- compose the unchanged calm `BoardSnapshot` v1 from the latest selected-source roster;
- represent fresh, stale, and unavailable source states honestly.

The active Phase 3D slice deploys this **existing manual path** to the private Ubuntu/CasaOS homelab and serves the iPad and Steam Deck through one Tailscale HTTPS origin. Background scheduling, backup/restore automation, source administration, public ingress, and every Apple write remain deferred.

## Architectural thesis

Deskboard has one authoritative owner for every kind of information. It is not a distributed database in which every client edits the same record.

- Apple Calendar owns Calendar events.
- Apple Reminders owns ordinary reminders.
- Deskboard Core owns the read-only mirror, operational Bridge status, Board composition, and future Deskboard-native state.
- Display clients own only disposable cache and ephemeral UI state.
- The macOS Bridge transports and normalizes Apple facts; it is not another source of truth.

The operating rule is:

> **Replicate facts, not authority.**

## Accepted system shape

```text
                         APPLE / ICLOUD
               ┌───────────────────────────┐
               │ Calendar                  │
               │ Reminders                 │
               └─────────────┬─────────────┘
                             │ EventKit
                             ▼
                ┌──────────────────────────┐
                │ Deskboard Apple Bridge   │
                │ signed / sandboxed macOS │
                │ read-only / outbound     │
                │                          │
                │ • explicit source roster │
                │ • source-v1 conversion   │
                │ • source/status outboxes │
                │ • explicit Sync Now      │
                └─────────────┬────────────┘
                              │ authenticated delivery
                              ▼
┌──────────────────────────────────────────────────────────┐
│                      DESKBOARD CORE                      │
│                                                          │
│ strict source mirror     content-free Bridge status      │
│ atomic SQLite state      truthful Board composition      │
│                                                          │
│ GET  /health                                            │
│ GET  /v1/board                                          │
│ POST /v1/apple-source-snapshots                         │
│ POST /v1/apple-bridge-status                            │
└────────────────────────────┬─────────────────────────────┘
                             │ BoardSnapshot v1
                 ┌───────────┴───────────┐
                 ▼                       ▼
             iPad PWA               Steam Deck
```

Phase 3D instantiates Core and Web on the homelab without changing the logical boundaries:

```text
Bridge --manual HTTPS/Tailscale--> Tailscale Serve
                                      │ loopback
                                      ▼
                              private web/proxy
                                      │ container network
                                      ├── production PWA
                                      └── Core API + SQLite volume
```

## Components

### Deskboard Web

**Technology:** React, TypeScript, and Vite, delivered as an installable PWA.

Responsibilities:

- render one calm, non-scrolling Board;
- support the accepted iPad and Steam Deck layouts;
- show Core-selected reasons and source freshness;
- cache the most recent valid Board for display-only fallback;
- poll the existing Board endpoint;
- expose no Apple source-management interface.

Non-responsibilities:

- ranking source records independently;
- reading Apple services;
- interpreting EventKit recurrence;
- owning source facts;
- exposing mirror or Bridge status internals;
- becoming a task manager or dashboard framework.

The product route remains:

```text
/board
```

### Deskboard Core

**Technology:** TypeScript, Fastify, and Node 24 built-in SQLite.

Responsibilities:

- validate every external and internal contract at runtime;
- authenticate Bridge delivery;
- hold the normalized Apple source mirror;
- hold the latest accepted content-free Bridge selection/status document;
- preserve operational revisions, digests, timestamps, and transactional boundaries;
- compose a display-ready Board centrally;
- expose only the accepted health, Board, source-ingestion, and status-ingestion routes;
- eventually own Deskboard-native state such as sessions and Open Loop history.

Core does not expose raw mirror rows, source records, status documents, roster coordinates, or direct database access to clients.

### macOS Bridge

**Technology:** Swift/SwiftUI using EventKit and Apple Security APIs.

Accepted mode:

- Apple Development-signed;
- App Sandbox enabled;
- Hardened Runtime enabled;
- outbound network client only;
- Calendar and Reminders read-only behavior;
- explicit source selection;
- explicit **Sync Now**.

Responsibilities:

- request Calendar and Reminders access independently;
- preserve source selections and permission outcomes independently;
- read only fields admitted by Apple source contract v1;
- build one source document per selected source scope;
- preserve exact Calendar and Reminder temporal meaning;
- persist exact source and status envelopes before sending;
- retry byte-equivalent pending envelopes after uncertain delivery;
- store the bearer token in Keychain;
- preserve one opaque Bridge identity and source/status revisions;
- report content-free local status.

Non-responsibilities in the accepted read path:

- EventKit save or remove calls;
- Reminder completion;
- inbound network service;
- Apple account credential export;
- notes, locations, participants, URLs, alarms, or recurrence-grammar collection;
- automatic scheduling during Phase 3D;
- source administration through the Board.

### Private homelab boundary

Phase 3D uses the existing Ubuntu/CasaOS and Tailscale environment.

The accepted target posture is:

- production Core and Web containers;
- one private persistent SQLite volume;
- API reachable only on the private container network;
- one host-facing web/private-proxy port bound to host loopback;
- Tailscale Serve as the sole remote HTTPS ingress;
- no Tailscale Funnel and no public internet ingress;
- all private configuration supplied at runtime and excluded from Git;
- manual Bridge delivery only.

Background operation and backup/restore move to Phase 3E after the remote manual path is accepted.

## Data ownership

| Information | Authoritative owner | Other copies |
|---|---|---|
| Calendar event | Apple Calendar | Strict read-only mirror in Core |
| Ordinary Reminder | Apple Reminders | Strict read-only mirror in Core |
| Source selection | Bridge local state | Latest content-free roster in Core |
| Source delivery health | Bridge operational state | Latest strict status document in Core |
| Board composition | Deskboard Core | Immutable Board snapshot and disposable client cache |
| Bridge bearer token | macOS Keychain / Core runtime secret | Authorization header only |
| Bridge ID and revisions | Bridge operational state | Auth/reconciliation metadata in Core |
| Future Reminder completion | Apple Reminders | Deferred command/audit state in Core |
| Future Open Loop/session/project state | Deskboard Core | Derived Board summaries |
| UI focus/expansion | Current client | Disposable |

## Source contracts and authority

Phase 2B defines two strict source documents:

```text
AppleReminderSourceSnapshotV1
AppleCalendarSourceSnapshotV1
```

Each document covers:

- one opaque Bridge identity;
- one selected source container;
- one entity type;
- one capture instant;
- one deterministically ordered retained record set;
- exact matched count and truncation state.

Calendar additionally declares its exact overlap window and civil interpretation time zone.

Authority rule:

> A source fact may be called absent only after a strict, semantically valid, non-truncated document successfully covers the exact scope in which absence is claimed.

A truncated, malformed, partial, failed, collision-bearing, or invalid candidate authorizes no deletion.

The source documents deliberately exclude account/source titles, notes, URLs, locations, participants, alarms, complete recurrence grammar, content hashes, synchronization revisions, database identifiers, and deployment metadata.

## Atomic mirror

Core stores one source scope per:

```text
bridgeId + entityType + sourceContainerId
```

Operational `sourceRevision` and normalized digest sit outside source contract v1.

Revision behavior:

- greater revision may apply;
- equal revision/equal digest is an unchanged duplicate;
- equal revision/different digest is conflict;
- lower revision is stale;
- invalid and truncated candidates make no change.

Reminder replacement covers the complete selected list scope.

Calendar replacement deletes and replaces only stored rows overlapping the accepted `[window.start, window.end)` scope. Unobserved out-of-window rows remain stored and are excluded from normal current-window reads.

Records, metadata, revisions, digests, freshness, deletions, and insertions commit together.

## Bridge status contract

The mirror cannot prove current source selection or health. Phase 3C therefore adds a separate strict content-free document:

```text
AppleBridgeStatusSnapshotV1
```

It contains only:

- Bridge ID;
- status revision and capture instant;
- independent Calendar and Reminders permission categories;
- the exact selected source-coordinate roster;
- content-free per-source delivery status;
- acknowledged and optional pending revisions;
- safe attempt and acknowledgement instants.

It contains no source title, record title, source temporal data, token, pending envelope bytes, account data, or EventKit payload.

The roster is authoritative for Board selection, not source deletion. Deselection removes a source from Board composition while retaining its mirror rows.

Status delivery has its own exact crash-safe outbox. It never rewrites or discards pending source envelopes.

## Board composition

Fixture mode remains the zero-configuration default. Mirror mode requires:

- complete ingestion configuration;
- explicit `apple-mirror` mode;
- explicit valid IANA Board time zone.

Both modes return unchanged `BoardSnapshot` v1.

### Freshness

An entity is `fresh` only when:

- permission is granted;
- at least one source is selected;
- every selected source has a successful nonpending status;
- every selected source has an accepted mirror scope at the acknowledged revision;
- status and acknowledgements are within the fixed freshness interval.

An entity is `stale` when selected sources exist but any one is blocked, retrying, missing, revision-mismatched, source-unavailable, or old.

An entity is `unavailable` when permission is not granted or no source is selected.

Last-good selected facts may remain visible while stale or unavailable. Operational failure never authorizes source deletion.

### Today

The first mirror-backed Today composition includes only selected, incomplete, nonblank Reminders whose due value—or start value when due is absent—is today or overdue in the configured Board time zone.

It excludes future, undated, completed, and blank-title Reminders.

Ordering favors:

1. timed due-today values;
2. date-only due-today values;
3. start-only available-today values;
4. recent overdue values;
5. accepted provenance only as deterministic tie-breaking.

The existing three-item cap remains.

### Next

The first mirror-backed Next composition includes only selected, noncancelled, nonblank Calendar records in the accepted latest window whose end is after `now`.

Ordering uses interpreted start, interpreted end, and accepted provenance order. Exact instants are projected into the configured Board time zone; all-day values remain civil date ranges.

The existing two-item cap remains.

### Client privacy

Board IDs are domain-separated opaque hashes over scoped provenance. Raw Bridge, source-container, EventKit, local, event, occurrence, and external identifiers never reach clients.

`boardVersion` hashes semantic Board content and freshness, not raw source coordinates or `generatedAt`.

## Synchronization

The accepted manual sequence is:

```text
1. retry exact pending status, if any
2. stop if that status remains unresolved
3. retry exact pending source envelopes
4. read and deliver eligible new source snapshots
5. persist exact final content-free status
6. deliver that exact status
7. Core composes Board from accepted source + status state
```

Only successful application or an unchanged duplicate acknowledges a revision and clears its pending bytes.

Phase 3D changes the approved network destination, not this sequence.

## API principles

Accepted routes:

```text
GET  /health
GET  /v1/board
POST /v1/apple-source-snapshots
POST /v1/apple-bridge-status
```

Principles:

- versioned runtime validation;
- fixed content-free errors;
- no raw EventKit payloads for clients;
- no source/status read API;
- no direct database access;
- Board responses use `Cache-Control: no-store`;
- Bridge routes authenticate before body parsing;
- one bearer token is bound to one expected Bridge identity;
- no mutation endpoint until its dedicated phase.

## Phase 3D network boundary

The Bridge keeps accepted numeric-loopback HTTP origins for local operation.

The only additional production origin class permitted in Phase 3D is a strict Tailscale HTTPS origin:

- `https` scheme;
- exact `.ts.net` host;
- no user info, query, fragment, or preconfigured path;
- normal system TLS validation;
- redirects rejected;
- no raw LAN/tailnet IP, arbitrary HTTPS host, public hostname, or remote plain HTTP.

The Bridge appends only the two accepted ingestion paths.

Changing destination does not change Bridge identity, Keychain credential, selections, TCC grants, revisions, or pending envelope bytes.

## Security and privacy

- Real source data and Board content never enter committed fixtures.
- `.env` files, tokens, certificates, provisioning profiles, databases, backups, Tailscale details, and pending envelopes are ignored and prohibited from Git.
- Agent-visible real-data proof is content-free.
- No real Board screenshot, accessibility tree, OCR, DOM dump, API body, mirror row, or pending envelope may be transmitted to an agent.
- The owner may inspect the real Board privately.
- Deployment and proxy logs must not contain request headers, bodies, Board responses, source coordinates, or credentials.
- Tailscale Serve is private ingress; Funnel is forbidden.
- Apple writes remain absent.

## Decision boundaries

| Concern | Accepted decision |
|---|---|
| Web | React + TypeScript + Vite PWA |
| Core | Fastify + TypeScript |
| Persistence | Node 24 SQLite source mirror plus content-free Bridge status |
| Apple integration | Signed sandboxed EventKit Bridge |
| Source delivery | Strict snapshots with exact pending-envelope retry |
| Board contract | `BoardSnapshot` v1 |
| Board mode | Fixture default; explicit mirror mode |
| Phase 3D access | Private Tailscale HTTPS only |
| Phase 3D sync | Explicit manual Sync Now |
| Public ingress | None |
| Calendar writes | Deferred |
| Reminder writes | Deferred until one explicit completion slice |
| AI selection | Absent |
| Background scheduling | Deferred to Phase 3E |
| Backup/restore | Deferred to Phase 3E |

A proposed architectural dependency must answer:

1. Which current issue requirement does it satisfy?
2. Why is the accepted simpler mechanism insufficient?
3. What maintenance and privacy burden does it add?

If the first answer is a future feature, it does not belong in the current slice.
