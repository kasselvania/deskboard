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

### Accepted result

- product README and Manifesto;
- architecture and data-ownership document;
- phased roadmap;
- coding-agent, contribution, privacy, and Git guardrails;
- explicit read-only Apple starting posture.

---

## Phase 1 — Fixture-Backed Board

**Question:** Can a deliberately constrained Board feel useful, calm, and appliance-like on the iPad Pro and Steam Deck before private integration exists?

**Status:** accepted and merged in PR #3.

### Accepted result

- React/Vite web client and Fastify API;
- shared runtime-validated Board contract;
- synthetic Board fixtures;
- one `/board` route;
- `GET /health` and `GET /v1/board`;
- calm loading, empty, stale, saved, and unreachable states;
- deterministic three-Task/two-Commitment capacity limits;
- physical iPad and Steam Deck viewport proof.

### Boundary retained

The production Board remains contract-driven. Later source work must not turn it into a raw backlog, source browser, or general dashboard.

---

## Phase 2A — EventKit Discovery Evidence

**Question:** What supported EventKit data is actually available from selected Calendar and Reminder sources, and which distinctions must later contract work preserve?

**Status:** accepted and merged in PR #7.

### Accepted result

- contained macOS discovery probe;
- separate Calendar and Reminders permission states;
- explicit empty-by-default source selection;
- bounded deterministic reads;
- destructive sanitization and ignored private exports;
- empirical field inventory and honest `not tested` cases;
- exact twelve-file owner-approved EventKit evidence hold;
- no EventKit write behavior.

---

## Phase 2B — Apple Source Contract and Reconciliation Semantics

**Question:** What is the smallest versioned Apple-source contract that a one-way mirror can validate and reconcile without losing the distinctions established in Phase 2A?

**Status:** accepted and merged in PR #11.

**Contract:** [`docs/apple-source-contract-v1.md`](docs/apple-source-contract-v1.md).

### Accepted result

- separate strict `AppleReminderSourceSnapshotV1` and `AppleCalendarSourceSnapshotV1` documents;
- one opaque Bridge and one selected source container per snapshot;
- exact matched count and explicit truncation;
- exact Calendar window scope;
- cross-language Swift and TypeScript validation of the same fixtures;
- exact timezone-qualified Calendar instants;
- rejection of ambiguous/nonexistent local Calendar times;
- deterministic ordering with collision rejection;
- complete empty scopes as authoritative cases;
- privacy-minimized v1 field set.

### Accepted authority rule

> Unseen is absent only after a successful, strict, non-truncated snapshot covers the exact scope in which absence is claimed.

Truncated, malformed, failed, partial, collision-bearing, or otherwise invalid candidates authorize no deletion.

---

# Phase 3 — One-Way Apple Mirror

**Question:** Can real Calendar and Reminder changes travel reliably from Apple to the Board without Deskboard modifying the source systems?

The original connected phase combined persistence, transport, conversion, composition, deployment, freshness, and real-use proof. It is therefore delivered as bounded sub-slices. Each later slice must preserve the accepted source authority and retry semantics rather than redesigning them opportunistically.

## Phase 3A — Atomic Core Apple Source Mirror

**Question:** Can Core persist and transactionally reconcile validated Apple source snapshots without deleting unseen facts?

**Status:** accepted and merged in PR #14.

**Design:** [`docs/apple-source-mirror.md`](docs/apple-source-mirror.md).

### Accepted result

- isolated SQLite-backed source mirror;
- source-controlled strict migrations and foreign-key enforcement;
- validation before mutation;
- source-scoped operational revisions and normalized digests;
- atomic Reminder whole-list replacement;
- atomic Calendar overlap-window replacement;
- retained out-of-window Calendar rows;
- duplicate, stale, conflict, truncated, invalid, and applied results;
- destructive rollback, migration, and close/reopen proofs;
- no transport or Board path.

---

## Phase 3B — Authenticated Manual Bridge Delivery

**Question:** Can the Mac produce contract-v1 snapshots from selected EventKit sources and deliver them safely to Core on explicit demand?

**Status:** accepted and merged in PR #18.

**Design and setup:** [`docs/apple-bridge-manual-delivery.md`](docs/apple-bridge-manual-delivery.md).

### Accepted result

- dedicated signed, sandboxed, Hardened Runtime, read-only macOS Bridge;
- strict production EventKit-to-v1 conversion using only admitted fields;
- separate intentional Calendar and Reminders permissions and selections;
- content-free before/result/after permission outcomes;
- persistent opaque Bridge identity and per-source acknowledged revisions;
- one exact crash-safe pending envelope per source coordinate;
- Keychain bearer credential;
- numeric-loopback-only HTTP client;
- one authenticated Core ingestion route;
- direct application through the Phase 3A mirror;
- exact uncertain-response retry across termination and relaunch;
- stable Apple Development identity and TCC decisions across rebuilds;
- content-free local Calendar and Reminder delivery proof.

### Accepted retry rule

> Persist the exact envelope before sending. After timeout, crash, relaunch, or another uncertain response, resend that byte-equivalent envelope at the same revision.

Only `applied` and `unchangedDuplicate` acknowledge the revision and clear pending state. Truncated, invalid, stale, conflict, and transport-failed outcomes preserve pending state and fail closed.

### Boundary retained

The Board remains fixture-backed. There is no remote topology, background process, homelab deployment, Board composition, or Apple write path.

---

## Phase 3C — Truthful Local Mirror-Backed Board

**Question:** Can Core compose the existing calm Board from the Apple mirror on the same Mac while accurately representing selected, stale, truncated, retrying, missing, and unavailable sources?

**Status:** active under issue [#19](https://github.com/kasselvania/deskboard/issues/19).

This is the first real-data Board slice. It remains same-Mac, loopback-only, manually synchronized, and read-only. Issue #19 is the detailed implementation and proof contract.

### Required scope

- a strict, separately versioned, content-free Bridge status snapshot;
- exact selected-source roster and independent permission categories;
- content-free per-source delivery health and acknowledged/pending revisions;
- crash-safe status-envelope delivery using the existing authentication boundary;
- one additional authenticated loopback status-ingestion route;
- Core persistence and idempotency for accepted Bridge status;
- explicit mirror-backed Board mode, while fixture mode remains the default;
- required configured IANA Board time zone;
- truthful `fresh`, `stale`, and `unavailable` derivation;
- selected incomplete due/start Reminder candidates for `Today`;
- selected ongoing/upcoming non-cancelled Calendar candidates for `Next`;
- existing maximum of three Tasks and two Commitments;
- concise deterministic reasons;
- opaque client IDs that expose no source provenance;
- unchanged `BoardSnapshot` v1 and unchanged web client unless a compatibility failure proves a tiny correction necessary.

### Central honesty rule

The source mirror alone is not enough to infer current selection or health. A previously mirrored row may belong to a source that is now deselected, blocked, missing, denied, or retry-pending.

> Compose only from the latest accepted selected-source roster, preserve last-good facts without calling them fresh, and never convert missing operational evidence into source deletion.

### Product rules

- undated and future Reminders remain mirrored but do not enter `Today` in this slice;
- completed and blank-title Reminders are excluded;
- canceled and blank-title Calendar records are excluded;
- no Apple priority, AI score, project inference, recurrence inference, note parsing, or backlog import;
- reasons remain calm and explainable;
- the Sideways prompt remains fixture behavior and is not connected to Apple data.

### Privacy proof rule

The owner may inspect the real Board privately. Agents must not receive real Board text, source names, source identifiers, EventKit identifiers, accessibility trees, screenshots, DOM dumps, request bodies, database rows, or pending envelopes. Agent-visible proof uses only schema success, masked ordinals, item counts, permission/freshness categories, and content-free status kinds.

### Exit criteria

- Core has a strict accepted view of current Bridge selection and health;
- status delivery is crash-safe and source delivery remains unchanged;
- `/v1/board` can be explicitly switched to same-Mac mirror-backed composition;
- the unchanged Board contract displays at most three real Task candidates and two real Commitment candidates;
- deselected, truncated, missing, unavailable, and stale sources are represented honestly;
- fixture mode remains the default;
- the owner privately confirms the real Board is recognizable and calm;
- no private real-data proof enters agent-visible tooling or Git;
- deployment, scheduling, backup, and Apple writes remain absent.

---

## Phase 3D — Private Deployment, Background Read Path, and Soak

**Question:** Can the accepted real-data Board run reliably on the iPad and Steam Deck through the private homelab without weakening source authority or freshness honesty?

**Status:** planned; blocked on accepted Phase 3C.

### Intended scope

- Ubuntu/CasaOS deployment of Core and Web;
- private Tailscale topology and TLS termination;
- background Bridge scheduling only after manual delivery is accepted;
- source freshness presentation on both clients;
- database backup and restore;
- one-week read-only soak on both target devices.

### Boundaries

- Calendar and Reminders remain read-only;
- no client write actions or source-management UI;
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

**Status:** blocked on an accepted and deliberately used read-only Phase 3 path.

### Scope

Add exactly one Apple mutation:

```text
Complete ordinary Reminder
```

Required pieces:

- a small inline `Done` action on eligible Reminder rows;
- Core command queue;
- unique client mutation IDs;
- Bridge command polling through the accepted private connection;
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
