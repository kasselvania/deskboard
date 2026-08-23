# Deskboard Roadmap

Deskboard will be developed as a sequence of bounded vertical slices. Every slice must prove one product or architectural assumption, include explicit tests, and end before the next layer of capability begins.

This roadmap is intentionally conservative. The project should earn complexity through real use.

## Delivery Rules

1. **One slice, one thesis.** Each phase must have a single dominant question it answers.
2. **No speculative scaffolding.** Do not create empty services, packages, adapters, or abstractions for future phases.
3. **Exit criteria are mandatory.** A phase is complete only when its proof conditions pass.
4. **Deferred means absent.** Features listed as deferred should not appear partially implemented behind an unfinished interface.
5. **The previous slice remains usable.** New work must not turn the Board into a development-only demo.
6. **Privacy comes before convenience.** No real personal data enters committed fixtures, logs, screenshots, or tests.
7. **Stop and use it.** After meaningful product slices, pause implementation long enough to learn from actual desk use.

---

## Phase 0 — Product and Repository Contract

**Question:** Do we agree on what Deskboard is, what it is not, and how development will remain bounded?

### Deliverables

- README with the product overview
- root-level manifesto
- architecture and data-ownership document
- phased roadmap
- coding-agent guardrails
- contribution and Git hygiene files

### Exit criteria

- a new contributor can explain the first slice without inventing features;
- the repository clearly states that the initial Apple path is read-only;
- the first implementation can begin without making another architecture decision;
- no framework or application scaffold has been committed prematurely.

**Status:** complete when the repository-foundation commit set is verified.

---

## Phase 1 — Fixture-Backed Board

**Question:** Can a deliberately constrained Board feel useful, calm, and appliance-like on the iPad Pro and Steam Deck before any private integration exists?

### Scope

Build a small monorepo containing:

- `apps/web`: React, TypeScript, and Vite;
- `apps/api`: Fastify and TypeScript;
- `packages/contracts`: runtime-validated shared contracts;
- synthetic fixtures for the Board;
- automated tests and GitHub Actions CI.

The application exposes only:

```text
GET /health
GET /v1/board
```

The Board contains only:

- date/time header;
- source-freshness presentation;
- **Today** with no more than three fixture reminders;
- **Next** with no more than two fixture Calendar commitments;
- one optional **Sideways Prompt**;
- calm loading, empty, stale, and error states.

### UI boundaries

- one route: `/board`;
- no application navigation;
- no settings page;
- no editable controls;
- no document-level vertical scrolling at the primary target viewports;
- no animation required to understand state;
- no hover-only behavior;
- no generic dashboard cards or charting library;
- no notification permission;
- no links out to source applications.

### Technical boundaries

- no Apple integration;
- no database;
- no authentication;
- no Docker requirement for local development;
- no Tailscale configuration;
- no service worker beyond what is needed for a minimal installable shell and cached static assets;
- no WebSockets or Server-Sent Events;
- no state-management library unless React state is demonstrably insufficient;
- no UI component framework;
- no AI.

### Proof tests

- contract schemas accept all committed fixtures and reject malformed examples;
- `GET /v1/board` returns a schema-valid response;
- ordering and capacity limits are deterministic;
- iPad landscape reference viewport renders without document-level vertical overflow;
- Steam Deck `1280 × 800` renders without document-level vertical overflow;
- content is legible and usable with touch, keyboard, and controller-emulated keyboard navigation;
- no essential distinction relies only on color;
- loading, empty, stale, and API-error states are covered;
- lint, typecheck, unit tests, API tests, browser tests, and production build pass in CI.

### Exit criteria

- the project starts with one documented command;
- both applications run locally without private credentials;
- the same fixture Board is visible on the iPad and Steam Deck over the local network;
- screenshots or test artifacts demonstrate both target layouts;
- there are no TODO implementations for deferred phases;
- README local-development instructions match reality;
- the implementation is small enough for a reviewer to understand in one sitting.

### Deliberate pause

Use the Board for several days with fixture content. Adjust typography, density, ordering, and whitespace before connecting Apple data.

---

## Phase 2A — EventKit Discovery Evidence

**Question:** What supported EventKit data is actually available from selected Calendar and Reminder sources, and what is the smallest lossless representation that later contract work should evaluate?

This is an empirical, read-only discovery slice, not the production Bridge or a frozen source contract.

**Status:** accepted and merged in PR [#7](https://github.com/kasselvania/deskboard/pull/7), with owner-approved sanitized fixtures and the complete local native and Node acceptance gates.

**Discovery evidence:** [`docs/apple-eventkit-discovery.md`](docs/apple-eventkit-discovery.md).

### Scope

- create a minimal macOS Swift/SwiftUI utility;
- request read access to Calendar and Reminders;
- show a source whitelist for selected calendars and Reminder lists;
- read a bounded local source scope and invalidate stale in-memory inspections;
- export sanitized, normalized examples to local development fixtures;
- document the verified field inventory, unavailable fields, and honestly untested cases;
- recommend a minimum source representation for Phase 2B to evaluate.

### Required evidence

- observed date-only, timed, undated, notes-bearing, priority, and completed Reminder shapes;
- observed timed, single-day all-day, timezone-qualified, recurring-occurrence, read-only-source, and location-bearing Calendar shapes;
- explicit `not tested` status for required cases not available through selected sources;
- an exact owner-approved committed specimen allowlist.

### Boundaries

- no EventKit save or remove calls and no Apple write behavior;
- no frozen production source contract;
- no homelab synchronization, network transport, database, or synchronization generations;
- no background daemon or login item;
- no attempt to expose unsupported Apple UI concepts;
- no real personal data committed to Git.

### Proof tests

- the utility handles the observed permission states without coupling Calendar and Reminders;
- source selection persists locally and successful enumeration reconciles disappeared identifiers;
- authorization or effective selection changes invalidate captured in-memory inspection data;
- Calendar events are deterministically ordered before the retained-record cap;
- the exact committed specimen allowlist is enumerated and decoded with the Swift models;
- exported candidates contain no private identifying information;
- normalized temporal structures preserve date-only, local-time, all-day, and timezone-qualified distinctions;
- malformed or unavailable fields fail safely.

### Exit criteria

- `ARCHITECTURE.md` contains an observed field map instead of assumptions;
- the fixture Board renders a sanitized EventKit-derived shape;
- every committed specimen is synthetic, approved, and executable as test evidence;
- unsupported and untested cases are explicit;
- the report makes a bounded recommendation without claiming a frozen contract;
- Phase 2B and Phase 3 implementation remain absent at acceptance.

## Phase 2B — Apple Source Contract and Reconciliation Semantics

**Question:** What is the smallest versioned Apple-source contract that a later one-way mirror can transport and reconcile without losing the distinctions established in Phase 2A?

**Status:** active under issue [#8](https://github.com/kasselvania/deskboard/issues/8). The feature branch implements the draft v1 contract documented in [`docs/apple-source-contract-v1.md`](docs/apple-source-contract-v1.md), but Phase 2B remains unaccepted until implementation review and merge. Phase 3 remains blocked.

### Scope

- define separate versioned Reminder and Calendar source-record variants;
- classify observed fields as required, optional with a present use, deferred, or excluded;
- document bridge-scoped identity and conservative remove-plus-add reconciliation;
- define deterministic Calendar and Reminder ordering before caps and explicit truncation semantics;
- preserve exact timezone-qualified Calendar instants and reject ambiguous or nonexistent local Calendar times;
- reject duplicate complete ordering coordinates rather than inheriting upstream order;
- validate the same synthetic contract fixtures in Swift and TypeScript;
- derive absence authority only for successful, non-truncated snapshots inside their exact declared scope;
- document complete atomic source-scope snapshot semantics for later Phase 3 implementation.

### Boundaries

- no HTTP, WebSockets, or another Bridge-to-Core transport;
- no SQLite or another database;
- no synchronization-generation or persistence implementation;
- no Tailscale, Docker, CasaOS, homelab deployment, daemon, login item, or background scheduling;
- no Calendar or Reminder writes, Reminder completion, or metadata parsing/write-back;
- no Open Loop, Project, session, timer, ranking, AI, or Board interaction behavior;
- no generic adapter framework or speculative future-source abstraction.

### Proof tests

- Swift and TypeScript independently validate the same versioned synthetic shapes;
- unsupported versions and malformed temporal values fail closed;
- strict Swift and TypeScript validation reject unknown keys at the same promised boundaries;
- ordering, collision, cap, and truncation semantics are deterministic;
- timezone-qualified Calendar transition ranges retain exact start/end instants;
- complete empty Reminder and Calendar scopes authorize absence only after runtime validation;
- identity limitations and source-scope reconciliation rules are explicit;
- all approved Phase 2A specimens remain validated without private data access.

### Exit criteria

- source contract v1 is minimal, versioned, and runtime validated in both languages;
- every included or excluded field has a current rationale;
- the later Phase 3 mirror can begin without inventing another source-contract decision;
- no Phase 3 implementation has begun.

---

## Phase 3 — One-Way Apple Mirror

**Question:** Can real Calendar and Reminder changes travel reliably from Apple to the two Deskboard clients without Deskboard modifying the source systems?

**Status:** not begun; blocked on accepted Phase 2B contract and reconciliation semantics.

### Scope

- macOS Bridge performs bounded read-only scans;
- Bridge posts versioned synchronization generations to Deskboard Core;
- Core validates and atomically stores normalized source records;
- SQLite is introduced for the source mirror and sync bookkeeping;
- Core composes the Board from real data;
- clients display freshness and stale-source states;
- deploy Core and Web to the Ubuntu/CasaOS homelab;
- expose the service privately through Tailscale.

### Initial source limits

- only whitelisted calendars and reminder lists;
- each v1 Reminder snapshot covers all accessible records from one selected list; Phase 3 must not add an undeclared completion or temporal filter and still claim authoritative absence;
- a bounded Calendar range, initially approximately seven days behind and forty-five days ahead;
- any production cap is applied after deterministic ordering and makes the snapshot explicitly truncated and non-authoritative for unseen records;
- no Notes ingestion;
- no Home Assistant data.

### Boundaries

- Calendar is read-only;
- Reminders is read-only;
- no commands from Core to Bridge;
- no client write actions;
- no background push notification system;
- no source-management UI in the Board.

### Proof tests

- editing a selected Reminder in Apple eventually changes both Boards;
- completing a Reminder in Apple removes or updates it on both Boards;
- creating, moving, or cancelling a selected Calendar event updates both Boards;
- a failed or partial synchronization does not delete the last good generation;
- a sleeping or disconnected Mac produces an honest stale-source state;
- duplicate sync delivery is idempotent;
- database backup and restore are documented and exercised;
- no Apple credentials leave the Mac.

### Exit criteria

- the one-way path runs for at least one week without manual database repair;
- the Board remains useful when the Bridge is temporarily offline;
- source freshness is understandable without being noisy;
- personal source selection is explicit and reviewable;
- the system is still simpler than opening the source applications for the default glance use case.

### Deliberate pause

Use this read-only Deskboard daily. Record which information deserves space, which reasons are useful, and what is repeatedly ignored. Do not add interactions merely because the plumbing permits them.

---

## Phase 4 — One Reminder Round Trip

**Question:** Can Deskboard safely acknowledge completion of one ordinary Reminder without becoming a Reminder-management application?

### Scope

Add exactly one Apple mutation:

```text
Complete ordinary Reminder
```

Required pieces:

- a small inline `Done` action on eligible Reminder rows;
- Core command queue;
- unique client mutation IDs;
- Bridge command polling over its existing outbound connection;
- source-version or content-hash conflict detection;
- EventKit completion and save;
- success, pending, conflict, and failed states;
- audit history;
- ordinary read synchronization as the final confirmation path.

### Boundaries

- no creating Reminders;
- no editing titles or notes;
- no changing due dates;
- no moving between lists;
- no Calendar writes;
- no optimistic permanent removal before confirmation;
- no general command bus for imagined future actions.

### Proof tests

- completing on the iPad completes the real Reminder and updates the Steam Deck;
- completing on the Steam Deck produces the same result;
- duplicate client requests complete only once;
- a changed source item produces an explicit conflict instead of an overwrite;
- a sleeping Mac leaves the command visibly pending and later completes it;
- Bridge failure leaves Apple data unchanged and reports a useful error;
- every attempt has an auditable actor, time, command, and result.

### Exit criteria

- the single write path is reliable enough that the Board does not become visibly incorrect after a real task is completed;
- no other Apple-editing controls have appeared;
- the interaction remains a tiny acknowledgment, not source administration.

---

## Phase 5 — First Open Loop

**Question:** Does elapsed time since engagement help invite a return without producing guilt or another recurring-task backlog?

### Scope

Introduce one manually chosen loop, preferably a session-oriented creative activity.

Add:

- a stable loop declaration;
- a preferred minimum and maximum gap;
- `resting`, `available`, `calling`, and `paused` derived states;
- elapsed-time explanation;
- one Deskboard-owned `I Did This` action;
- append-only activity history;
- one Open Loops slot on the Board.

A Reminder note metadata block may act as the portable declaration once its parser has been verified, but dynamic history stays in Core.

### Boundaries

- one loop first, not an import wizard;
- no streaks;
- no missed-occurrence debt;
- no AI ranking;
- no charts;
- no automatic cadence prescription;
- no completion of the persistent Reminder anchor.

### Proof tests

- engagement resets elapsed time and loop state;
- crossing the minimum gap makes the loop eligible without forcing display;
- crossing the preferred maximum changes the explanation to `calling` behavior;
- pausing removes the loop intentionally without deleting history;
- clients show the same derived state;
- the Board never labels the user as failed, behind, or unproductive.

### Exit criteria

- the loop is used in real life for at least two preferred windows;
- elapsed-time context is experienced as useful rather than punitive;
- the interaction adds less maintenance than it removes.

---

## Phase 6 — One Session Timer

**Question:** Can a lightweight timer reduce the mental barrier to beginning without turning Deskboard into surveillance or detailed time tracking?

### Scope

- start one server-owned active session;
- display it consistently on both clients;
- stop it from either client;
- record duration and engagement;
- allow a small correction for an accidentally running timer;
- enforce one active session per user initially.

### Boundaries

- no Pomodoro framework;
- no billing or timesheets;
- no productivity score;
- no automatic activity monitoring;
- no multiple overlapping timers;
- no elaborate reports.

### Proof tests

- start on iPad, inspect on Steam Deck, and stop on either device;
- the timer survives client reload, lock, and reconnect;
- duplicate start/stop requests are idempotent;
- session completion updates the associated loop’s engagement time;
- an abandoned timer can be corrected without corrupting history.

### Exit criteria

- the timer is useful for at least one creative activity and one project activity;
- recorded durations feel informative rather than burdensome;
- the Board remains quiet while a session is active.

---

## Later Candidates — Not Scheduled

These are possible directions, not commitments:

- three-slot active-project model and `last moved` history;
- next actions linked to Reminders;
- re-entry summaries;
- weather and one-line Home state;
- carefully scoped Sonos or household scenes;
- Home Assistant and ESP32 signals;
- agent and Shortcut commands through an audited API;
- family-safe profiles;
- Android wall mode;
- E-Ink paper profile;
- server-rendered Pi/Kindle frame client;
- weekly descriptive reflection.

Each candidate requires a new bounded slice with its own thesis, exclusions, and proof tests.

---

## Definition of Done for Every Slice

A slice is not complete until:

- its acceptance tests pass locally and in CI;
- documentation describes what exists, not what was intended;
- no secrets or personal fixture data are committed;
- new dependencies are justified by current requirements;
- error and empty states are implemented;
- the prior slice’s use case still works;
- deferred features remain absent;
- the repository can be cloned and run from documented commands;
- the change is small enough to review coherently;
- the next phase has not been partially started.
