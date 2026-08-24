# Deskboard Roadmap

Deskboard is developed as a sequence of bounded vertical slices. Every slice must prove one product or architectural assumption, include explicit tests, and stop before the next layer begins.

This roadmap is intentionally conservative. The project should earn complexity through evidence and real use.

## Delivery Rules

1. **One slice, one thesis.** Each slice has one dominant question.
2. **No speculative scaffolding.** Do not create empty services, adapters, transports, or abstractions for future work.
3. **Exit criteria are mandatory.** A slice is complete only when its proof conditions pass.
4. **Deferred means absent.** Later behavior must not appear partially implemented.
5. **The previous slice remains usable.** New work must not turn the Board into a development-only demo.
6. **Privacy comes before convenience.** No real personal data enters committed fixtures, logs, screenshots, tests, issues, or pull requests.
7. **Stop and use it.** After connected product slices, pause long enough to learn from actual desk use.

---

## Phase 0 — Product and Repository Contract

**Question:** Do we agree on what Deskboard is, what it is not, and how development will remain bounded?

**Status:** accepted and complete.

### Deliverables

- product README and Manifesto;
- architecture and data-ownership document;
- phased roadmap;
- coding-agent, contribution, privacy, and Git guardrails.

### Exit criteria

- a contributor can explain the first slice without inventing features;
- Apple Calendar and Reminders are explicitly authoritative;
- the initial Apple path is explicitly read-only;
- no application framework is scaffolded prematurely.

---

## Phase 1 — Fixture-Backed Board

**Question:** Can a deliberately constrained Board feel useful, calm, and appliance-like on the iPad Pro and Steam Deck before private integration exists?

**Status:** accepted and merged in PR #3.

### Scope

- React/Vite web client;
- Fastify API;
- shared runtime-validated Board contracts;
- synthetic Board fixtures;
- one `/board` route;
- `GET /health` and `GET /v1/board` only;
- loading, empty, stale, saved, and unreachable states;
- deterministic capacity limits and browser proofs.

### Boundaries

- no Apple integration;
- no database or authentication;
- no write actions;
- no deployment requirement;
- no AI, generic dashboard framework, settings, or navigation.

### Exit criteria

- complete Node quality gate passes;
- iPad landscape and Steam Deck layouts have no document-level vertical overflow;
- physical iPad access over the local network is proved;
- the Board remains small, calm, read-only, and fixture-backed.

---

## Phase 2A — EventKit Discovery Evidence

**Question:** What supported EventKit data is actually available from selected Calendar and Reminder sources, and which distinctions must later contract work preserve?

**Status:** accepted and merged in PR #7.

### Scope

- contained macOS Swift/SwiftUI discovery probe;
- separate Calendar and Reminder permission states;
- explicit empty-by-default source selection;
- bounded local reads;
- destructive sanitization and ignored private exports;
- empirical field inventory and honest `not tested` cases;
- owner-approved synthetic EventKit specimens;
- EventKit-derived Board fixture through the unchanged Phase 1 contract.

### Accepted evidence

- six Reminder specimens;
- six Calendar specimens;
- exact twelve-file allowlist and byte/hash hold;
- deterministic Calendar ordering before the discovery cap;
- stale-inspection invalidation;
- native and Node quality gates.

### Boundaries

- no EventKit write behavior;
- no frozen production contract;
- no network, database, daemon, deployment, or Board integration;
- no fabricated support for unobserved cases.

---

## Phase 2B — Apple Source Contract and Reconciliation Semantics

**Question:** What is the smallest versioned Apple-source contract that a one-way mirror can validate and reconcile without losing the distinctions established in Phase 2A?

**Status:** accepted and merged in PR #11.

**Contract:** [`docs/apple-source-contract-v1.md`](docs/apple-source-contract-v1.md).

### Accepted shape

- separate `AppleReminderSourceSnapshotV1` and `AppleCalendarSourceSnapshotV1` documents;
- one opaque Bridge and one selected source container per snapshot;
- explicit matched count and truncation state;
- exact Calendar window scope;
- strict TypeScript and Swift validation of the same fixtures;
- exact timezone-qualified Calendar instants;
- rejection of ambiguous or nonexistent local Calendar times;
- deterministic ordering with collision rejection;
- complete empty scopes as authoritative cases;
- absence authority exposed only after runtime and semantic validation;
- privacy-minimized field set.

### Accepted authority rule

> Unseen is absent only after a successful, strict, non-truncated snapshot covers the exact scope in which absence is claimed.

Truncated, malformed, failed, partial, collision-bearing, or otherwise invalid candidates authorize no deletion.

### Boundaries

- no transport or ingestion endpoint;
- no database or persistence implementation;
- no synchronization generations, deployment, Board integration, or Apple writes.

---

# Phase 3 — One-Way Apple Mirror

**Question:** Can real Calendar and Reminder changes travel reliably from Apple to both Deskboard clients without Deskboard modifying the source systems?

The original connected phase contained persistence, transport, native conversion, Board composition, deployment, freshness, and a real-use soak. It is therefore delivered as bounded sub-slices. Later sub-slices must preserve the accepted Phase 2B authority semantics rather than redesigning them opportunistically.

## Phase 3A — Atomic Core Apple Source Mirror

**Question:** Can Core persist and transactionally reconcile validated Apple source snapshots without deleting unseen facts?

**Status:** accepted and merged in PR #14.

The accepted implementation is documented in [`docs/apple-source-mirror.md`](docs/apple-source-mirror.md). It provides the isolated SQLite mirror, ordered strict migration, validation-before-mutation, transactional replacement service, source-scoped revisions and normalized digests, rollback proof, and close/reopen persistence. Phase 3A exposes no transport or Board path.

### Scope

- isolated SQLite-backed Apple source mirror inside Core;
- source-controlled migrations and foreign-key enforcement;
- strict validation before mutation;
- operational source revision and normalized digest outside source contract v1;
- transactional Reminder whole-scope replacement;
- transactional Calendar overlap-window replacement;
- retained out-of-window Calendar rows;
- explicit duplicate, stale, conflict, truncated, invalid, and applied results;
- rollback, reopen, and migration proofs;
- narrow internal read methods for tests and later slices;
- `docs/apple-source-mirror.md`.

### Core rules

- revision scope is Bridge + entity + source container;
- same revision and same digest is an idempotent duplicate;
- same revision and different digest is a conflict;
- lower revision is stale;
- invalid or truncated input does not mutate records, freshness, or accepted revision;
- complete Reminder snapshots replace the entire selected-list scope;
- Calendar snapshots replace only stored rows overlapping the accepted window;
- Calendar rows outside the window remain stored but are not current-window candidates;
- all destructive work and scope metadata commit in one transaction.

### Boundaries

- no HTTP or other ingestion endpoint;
- no Swift network client or production EventKit conversion;
- no Board composition or change to `GET /v1/board`;
- no authentication, deployment, scheduler, daemon, Docker, or Tailscale;
- no Apple writes or later semantic features;
- no generic persistence framework.

### Exit criteria

- authoritative snapshots apply atomically to exact scopes;
- complete empty scopes clear only their authoritative regions;
- truncated, invalid, stale, conflicting, and failed candidates preserve previous good state;
- duplicate delivery is idempotent;
- Calendar window shifts never delete unobserved out-of-window records;
- injected destructive failure rolls back completely;
- migrations and close/reopen persistence are proved;
- native and complete Node gates pass;
- Phase 1 Board remains fixture-backed and unchanged.

## Phase 3B — Authenticated Manual Bridge Delivery

**Question:** Can the Mac produce contract-v1 snapshots from selected EventKit sources and deliver them to Core safely on explicit demand?

**Status:** active under issue #15.

The review implementation is documented in [`docs/apple-bridge-manual-delivery.md`](docs/apple-bridge-manual-delivery.md). The real Phase 3B proof runs a dedicated sandboxed Bridge and Core on the same Mac over loopback. It deliberately settles production conversion, authentication, persistent Bridge identity, source-scoped revisions, and crash-safe retry before remote topology, deployment, background operation, or Board composition begins. Phase 3B remains active until review and merge.

### Scope

- dedicated sandboxed, hardened, read-only macOS Bridge separate from the Phase 2A probe;
- production EventKit-to-v1 conversion that reads only accepted contract fields;
- separate intentional Calendar and Reminder permissions and empty-by-default source selections;
- explicit content-free permission-request results that distinguish system errors from completed requests with no TCC decision;
- persistent opaque Bridge identity and source-scoped acknowledged revisions;
- one crash-safe pending delivery envelope per source coordinate;
- one strict authenticated Core ingestion route;
- bearer token stored in macOS Keychain and bound to the configured Bridge identity;
- loopback-only manual delivery through an explicit `Sync Now` action;
- strict body, source-record, and response limits;
- idempotent application through the accepted Phase 3A mirror;
- content-free status for applied, duplicate, stale, conflict, truncated, invalid, and transport-failed results;
- no background scheduler.

### Central retry rule

> Persist the exact envelope before sending. After timeout, crash, relaunch, or another uncertain response, resend that byte-equivalent envelope at the same revision.

The Bridge must not reread EventKit and reuse an uncertain revision for changed content. Only `applied` and `unchangedDuplicate` acknowledge the revision and clear pending state. All other results preserve pending state and fail closed.

### Boundaries

- Calendar and Reminders remain read-only;
- Core continues listening only on loopback for the real proof;
- no Board composition from the mirror;
- no daemon, login item, background scheduler, deployment, Tailscale, TLS termination, or public ingress;
- no write commands or general command bus;
- no source administration in the Board;
- no automatic stale/conflict recovery or silent Bridge identity reset.

### Exit criteria

- a sandboxed production Bridge converts controlled Calendar and Reminder sources into exact accepted v1 snapshots;
- one authenticated loopback route applies envelopes through the Phase 3A mirror;
- missing or wrong authentication fails before body application and leaks no private content;
- first delivery, acknowledgement, duplicate retry, timeout, relaunch, stale, conflict, invalid, and truncation behavior are proved;
- an uncertain response retries the exact persisted envelope and revision;
- credentials remain in injected Core configuration and macOS Keychain, excluded from Git and SQLite;
- entitlement inspection proves sandbox, outgoing client, Calendar access, no incoming service, and no EventKit writes;
- an Apple Development-signed installed Release product produces independent Calendar and Reminders decisions and retains them across a same-identity rebuild;
- a content-free manual local Calendar and Reminder delivery proof passes;
- `/health` and the fixture-backed Board remain unchanged;
- Phase 3C, deployment, background operation, and Apple writes remain absent.

## Phase 3C — Real Read-Only Board and Private Deployment

**Question:** Can the validated one-way mirror drive the real Board reliably on the iPad and Steam Deck in the private homelab?

**Status:** planned; blocked on accepted Phase 3B.

### Intended scope

- Core composition of Tasks and Commitments from the source mirror;
- deterministic reasons and existing Board capacity limits;
- source freshness and honest stale states;
- background Bridge scheduling only after manual delivery is reliable;
- Ubuntu/CasaOS deployment;
- private Tailscale access;
- backup and restore for the Core database;
- one-week read-only soak on both target devices.

### Boundaries

- Calendar and Reminders remain read-only;
- no client write actions;
- no source-management UI in the Board;
- no Notes, Home Assistant, Open Loops, Projects, sessions, timers, ranking, or AI;
- no public internet ingress requirement.

### Exit criteria

- Apple edits eventually change both Boards;
- a sleeping or disconnected Mac produces understandable staleness rather than silent incorrectness;
- failed or partial synchronization never deletes the last good scope;
- duplicate delivery remains idempotent;
- backup and restore are exercised;
- the path runs for at least one week without manual database repair;
- the Board remains simpler and calmer than opening the source applications for the default glance use case.

### Deliberate pause

Use the read-only Deskboard daily. Record which facts deserve space, which reasons help, which source fields are unnecessary, and what is repeatedly ignored. Do not add interactions merely because the plumbing permits them.

---

## Phase 4 — One Reminder Round Trip

**Question:** Can Deskboard acknowledge completion of one ordinary Reminder safely without becoming a Reminder-management application?

**Status:** blocked on a reliable read-only Phase 3 path and its deliberate pause.

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
- source-version conflict detection;
- EventKit completion and save;
- pending, success, conflict, and failed states;
- audit history;
- normal read synchronization as final confirmation.

### Boundaries

- no Reminder creation, title editing, due-date editing, or list movement;
- no Calendar writes;
- no optimistic permanent removal before source confirmation;
- no general command bus.

### Exit criteria

- completion from either client updates the real Reminder and both Boards;
- duplicate commands complete only once;
- source changes produce explicit conflicts rather than overwrites;
- a sleeping Mac leaves the command visibly pending;
- every attempt is auditable;
- no other Apple-editing control appears.

---

## Phase 5 — First Open Loop

**Question:** Does elapsed time since engagement invite a return without producing guilt or another recurring-task backlog?

### Scope

- one manually chosen loop;
- preferred minimum and maximum return gap;
- resting, available, calling, and paused states;
- elapsed-time explanation;
- one `I Did This` action;
- append-only engagement history;
- one Open Loop slot on the Board.

### Boundaries

- one loop first;
- no streaks, missed-instance debt, charts, AI ranking, or automatic cadence prescription;
- no completion of a persistent Reminder anchor.

### Exit criteria

- engagement resets elapsed time and derived state;
- pause is intentional and preserves history;
- both clients show the same state;
- the Board never labels the user failed, behind, or unproductive;
- the loop is used for at least two preferred windows and adds less maintenance than it removes.

---

## Phase 6 — One Session Timer

**Question:** Can a lightweight timer reduce the barrier to beginning without becoming surveillance or detailed time tracking?

### Scope

- one server-owned active session;
- start and stop from either client;
- duration and engagement record;
- small correction for an abandoned timer;
- one active session per user initially.

### Boundaries

- no Pomodoro framework, billing, timesheets, productivity score, automatic monitoring, overlapping timers, or elaborate reports.

### Exit criteria

- start on one client and stop on the other;
- the timer survives reload, lock, and reconnect;
- duplicate requests are idempotent;
- session completion updates associated engagement;
- durations feel informative rather than burdensome.

---

## Later Candidates — Not Scheduled

Possible future bounded slices include:

- three-slot active-project model and `last moved` history;
- next actions linked to Reminders;
- re-entry summaries;
- weather and one-line Home state;
- carefully scoped Sonos or household scenes;
- Home Assistant and ESP32 signals;
- audited agent and Shortcut commands;
- family-safe profiles;
- Android and E-Ink rendering profiles;
- server-rendered low-power display clients;
- weekly descriptive reflection.

These are candidates, not commitments. Each requires its own thesis, boundaries, and proof tests.

---

## Definition of Done for Every Slice

A slice is not complete until:

- its acceptance tests pass locally;
- hosted CI results are reported honestly, including administrative non-starts;
- documentation describes what exists rather than what was intended;
- no secrets or personal data are committed;
- new dependencies are justified by current requirements;
- failure and empty states are proved;
- the previous slice remains usable;
- deferred behavior remains absent;
- the repository can be cloned and validated from documented commands;
- the change is small enough for coherent review;
- the next slice has not been partially started.
