# Coding Agent Instructions

This repository is intentionally small and staged. Coding agents are expected to complete the requested slice, prove it, document it, and stop.

Before changing code or configuration, read:

1. `README.md`
2. `MANIFESTO.md`
3. `ARCHITECTURE.md`
4. `ROADMAP.md`
5. `docs/apple-source-mapping-v0.1.md`
6. `docs/apple-eventkit-discovery.md`
7. `docs/apple-source-contract-v1.md`
8. `docs/apple-source-mirror.md`
9. `docs/apple-bridge-manual-delivery.md`
10. `CONTRIBUTING.md`
11. `SECURITY.md`
12. the active GitHub issue and all review context

If a task conflicts with those documents, pause and explain the conflict instead of silently expanding or redesigning the project. For active implementation details, the current GitHub issue is authoritative over older status wording in long-lived architecture prose.

## Prime Directive

> Build the smallest complete slice that proves the stated product or architectural assumption, then stop.

A complete slice includes working behavior, tests, error states, documentation, and reproducible commands. It does not include speculative scaffolding for later phases.

## Current Phase

Phase 1 — Fixture-Backed Board — is accepted and merged.

Phase 2A — EventKit Discovery Evidence — is accepted and merged in PR #7. Its probe, empirical findings, caveats, and twelve owner-approved sanitized specimens remain evidence inputs.

Phase 2B — Apple Source Contract and Reconciliation Semantics — is accepted and merged in PR #11. `AppleReminderSourceSnapshotV1` and `AppleCalendarSourceSnapshotV1` are strict accepted boundaries.

Phase 3A — Atomic Core Apple Source Mirror — is accepted and merged in PR #14. Its migrations, transactional scope replacement, revision/digest behavior, truncation rules, and rollback semantics are accepted infrastructure.

Phase 3B — Authenticated Manual Bridge Delivery — is accepted and merged in PR #18. Its signed sandboxed Bridge, EventKit converter, one authenticated source-ingestion route, Keychain credential boundary, source-scoped revisions, exact pending-envelope retry, independent permissions, and manual loopback proof are accepted infrastructure.

The current implementation target is **Phase 3C — Truthful Local Mirror-Backed Board** from issue #19.

The question for Phase 3C is:

> Can Core compose the existing calm Board from the Apple mirror on the same Mac while accurately representing selected, stale, truncated, retrying, missing, and unavailable sources?

This is a same-Mac, manually synchronized, read-only Board-composition slice. It is not deployment, background operation, source administration, or an Apple write path.

The active feature branch implements the bounded status, outbox, Core route/storage, and mirror-backed composer. The content-free private owner gate is complete. Phase 3C remains active until review is complete; this branch is not an accepted basis for Phase 3D.

## Allowed Phase 3C Shape

Phase 3C may add only what issue #19 requires, approximately:

```text
packages/contracts/                         strict content-free Bridge status contract
fixtures/apple-bridge-status/               synthetic cross-language status fixtures
apps/api/src/apple-bridge-status/            storage, apply service, authenticated route
apps/api/src/mirror-backed-board/            mirror/status-backed Board composer
apps/api/test/                               status and Board integration proofs
native/apple-bridge/                         status conversion and crash-safe status delivery
docs/apple-bridge-status-v1.md               operational status semantics
docs/mirror-backed-board.md                  composition and freshness rules
```

The production web client and `BoardSnapshot` v1 contract should remain unchanged. Fixture mode remains the default.

### Phase 3C permitted behavior

- define one strict, separately versioned, content-free Bridge status snapshot;
- represent independent Calendar and Reminders permission categories;
- represent the exact selected source-coordinate roster;
- represent content-free per-source delivery health, acknowledged revision, optional pending revision, and safe timestamps;
- validate the same synthetic status fixtures in Swift and TypeScript;
- persist and retry one exact pending status envelope independently of source pending envelopes;
- add exactly one authenticated loopback status-ingestion route using the accepted Phase 3B token and Bridge binding;
- store accepted status revision/digest/document transactionally;
- enable an explicitly configured mirror-backed Board mode;
- require an explicit IANA Board time zone;
- derive honest entity freshness from status plus matching mirror scopes;
- compose selected Reminder candidates into `Today`;
- compose selected Calendar candidates into `Next`;
- preserve existing capacity limits and calm reasons;
- derive opaque client IDs with the Node standard library;
- retain last-good facts without calling them fresh;
- update documentation after behavior exists.

### Phase 3C forbidden behavior

Do not add:

- LAN or public listening;
- Tailscale, TLS termination, reverse proxy, Docker, CasaOS, or homelab deployment;
- background Bridge scheduling, daemon, launch item, menu-bar agent, watcher, or notification;
- backup or restore automation;
- changes to Apple source contract v1;
- changes to Phase 3A source-replacement authority;
- Apple Calendar or Reminder writes;
- Reminder completion;
- source-management UI in the Board;
- raw mirror, status, source, or roster read routes;
- web-client changes unless a failing accepted contract/state proves one narrow compatibility correction;
- Notes, metadata parsing, Home Assistant, Open Loops, Projects, sessions, timers, ranking, or AI;
- automatic stale/conflict recovery;
- generic adapters, buses, schedulers, repositories, auth systems, or persistence frameworks;
- real personal data in agent-visible tools or repository artifacts.

Deferred means absent, not partially implemented.

## Product Guardrails

- Apple Calendar and Reminders remain authoritative for source facts.
- Deskboard replicates facts, not authority.
- Calendar and Reminders remain read-only.
- The Board remains a curated field of attention, not a backlog.
- Ordinary incomplete Reminders may become candidate Tasks; Calendar records may become candidate Commitments.
- Recurrence remains a source scheduling fact, not an Open Loop classification.
- Date-only, local-time, timezone-qualified, and all-day meanings remain distinct.
- Source health changes freshness and eligibility; it must never fabricate deletion.
- One blocked selected source must not be silently ignored so the entity can appear fresh.
- Reasons must be deterministic, concise, and nonjudgmental.
- Apple priority, AI scores, shame language, and opaque attention ranking remain absent.

## Accepted Boundaries

### Source contract

Do not add, remove, rename, or reinterpret a v1 source-contract field.

- Reminder scope is one Bridge + one selected Reminder list + every accessible record in that list.
- Calendar scope is one Bridge + one selected Calendar + records overlapping the exact declared window.
- Only a strict, semantically valid, non-truncated snapshot authorizes absence.
- Complete empty snapshots are authoritative only inside their exact source scopes.
- Ordering-coordinate collisions invalidate the source candidate.

### Core mirror

Do not duplicate or weaken Phase 3A behavior.

- source revision scope is Bridge + entity + container;
- same revision/same digest is idempotent;
- same revision/different digest is conflict;
- lower revision is stale;
- truncated or invalid source input does not mutate or advance the accepted source scope;
- Reminder replacement is whole-scope;
- Calendar replacement is overlap-window only;
- accepted destructive work commits atomically;
- out-of-window Calendar rows may remain stored but are not current-window candidates.

### Manual Bridge delivery

Do not duplicate or weaken Phase 3B behavior.

- the production Bridge remains sandboxed, signed, outbound-only, and read-only;
- source selections remain separate and explicit;
- the bearer token remains in Keychain and only in the Authorization header;
- Core remains loopback-only in this slice;
- exact source pending envelopes survive uncertain delivery;
- only `applied` and `unchangedDuplicate` acknowledge a source revision;
- source status/result surfaces remain content-free;
- no EventKit save or remove call may appear.

## Bridge Status Contract Guardrails

The source mirror cannot prove current source selection or health. Phase 3C therefore adds one operational status document rather than inferring state from old rows.

### Required meaning

A status snapshot must carry only:

- literal schema version;
- opaque Bridge ID;
- positive safe-integer status revision;
- capture instant;
- Calendar permission category;
- Reminders permission category;
- exact selected source-coordinate roster;
- one content-free status per selected coordinate;
- nonnegative acknowledged source revision;
- optional pending source revision;
- optional last-attempted and last-acknowledged instants.

Do not include:

- source titles;
- record titles;
- record counts;
- source temporal values;
- pending source envelope bytes;
- token material;
- account or signer data;
- EventKit payloads.

### Status semantics

- coordinates must be strictly ordered and unique;
- pending revision, when present, equals acknowledged revision plus one;
- status/pending combinations must be coherent;
- selected roster is authoritative only for Board selection, not source-record absence;
- deselection removes a source from Board consideration but does not delete its mirror rows;
- status contract changes require a new version and new shared fixtures.

### Crash-safe status delivery

Before sending new status content:

1. derive the next status revision;
2. build and strictly validate the complete status envelope;
3. atomically persist the exact encoded envelope;
4. send those persisted bytes.

After timeout, crash, relaunch, malformed response, or uncertain delivery, resend the byte-equivalent status envelope at the same status revision.

Only applied/idempotent duplicate acknowledgement clears pending status. Invalid, stale, conflict, or transport failure preserves it. Status delivery must not mutate, discard, or reorder pending source envelopes.

## Core Status Route and Storage Guardrails

Add exactly one additional route, for example:

```text
POST /v1/apple-bridge-status
```

Requirements:

- reuse the existing Phase 3B bearer token and expected Bridge ID;
- authenticate before body parsing;
- loopback server topology unchanged;
- strict finite body limit;
- strict document and positive safe-integer revision;
- authenticated Bridge-ID binding;
- canonical digest and status idempotency outside the status document;
- newer applies, equal/equal duplicates, equal/different conflicts, lower stale;
- invalid input does not mutate;
- metadata and document commit in one transaction;
- persisted JSON comes only from parsed values and is strictly revalidated on read;
- no status read route for the web client;
- no second authentication system or token.

A source-controlled status migration may extend the private Core database, but it must not alter accepted source tables or replacement semantics.

## Mirror-Backed Board Configuration

Fixture mode remains the default.

Mirror-backed mode must require complete explicit configuration, including:

- a mode selector;
- one valid IANA Board time zone;
- the same private Core resources used for ingestion/status/composition.

Do not infer Board time-zone meaning from the server process, because a later homelab process may run in UTC.

Partial or invalid configuration fails startup with a fixed content-free error. Do not commit the owner’s time zone or local environment values.

`GET /v1/board` continues returning the accepted `BoardSnapshot` v1. Do not expose source coordinates, mirror rows, status documents, or roster details to the web client.

## Freshness and Selection Guardrails

Compose only from coordinates in the latest accepted selected roster.

### Fresh

An entity is fresh only when:

- permission is granted;
- at least one source is selected;
- every selected source has a nonblocked acknowledged status;
- every selected source has a matching accepted mirror scope at that acknowledged revision;
- Bridge status and relevant acknowledgements are within the fixed documented freshness interval.

### Stale

An entity is stale when selected sources exist and last-good facts may remain usable, but any selected source is blocked, retry-pending, missing, revision-mismatched, or older than the freshness interval.

### Unavailable

An entity is unavailable when permission is not granted or no source is selected.

Stale or unavailable entities may retain last-good selected-source items when available, but freshness must remain honest. Never convert operational failure into source deletion.

Use the oldest relevant successful selected-source acknowledgement for `updatedAt`. Use `null` when no selected source has accepted data.

## Reminder → Today Guardrails

Version-one eligibility:

- selected source coordinates only;
- incomplete Reminder only;
- nonempty source title only;
- due temporal is preferred;
- start temporal may supply eligibility only when due is absent;
- effective Board-local date is today or earlier;
- future and undated Reminders remain mirrored but do not enter `Today`;
- Apple priority is not used;
- no recurrence, project, metadata, or AI inference.

Document and test one deterministic order that favors actionable today work over old backlog. Baseline:

1. timed values due today, earliest first;
2. date-only values due today;
3. overdue values, most recently due first;
4. scoped provenance only as deterministic tie-breaking.

Apply the existing three-item cap after ordering.

Reasons may include:

- `due today`;
- `due at 3:00 PM`;
- `overdue from yesterday`;
- `overdue 3 days`;
- `available today` when start supplied eligibility.

Do not expose raw provenance in client IDs. Derive stable opaque IDs from scoped provenance using the Node standard library.

## Calendar → Next Guardrails

Version-one eligibility:

- selected Calendar coordinates only;
- accepted rows overlapping the latest accepted source window;
- canceled records excluded;
- ongoing and future ranges whose end is after `now`;
- nonempty source title only;
- no participant, location, URL, availability, note, or recurrence-grammar use.

Sort by interpreted start, interpreted end, then accepted provenance order. Apply the existing two-item cap after ordering.

Render against the configured Board time zone. All-day values remain civil date ranges. Timed Board values may be display projections because exact instants remain in the source mirror.

Reasons/labels may include:

- `happening now`;
- `in 45 minutes`;
- `later today`;
- `tomorrow`;
- `all day`;
- `continues today`.

## Board Contract Guardrails

Keep `BoardSnapshot` v1 unchanged.

- at most three Today items;
- at most two Next items;
- existing Sideways prompt behavior unchanged;
- generated time comes from the injected clock;
- stable Board version derives from semantic Board content and freshness, not raw private identifiers;
- final output is validated through `boardSnapshotSchema` before serving;
- existing loading, empty, stale, unavailable, saved, and unreachable client behavior remains valid;
- no source-management UI or new route appears.

## Privacy and Evidence

Never commit, report, or transmit to an agent:

- real Board titles or text;
- real Calendar or Reminder records;
- source/list/calendar/account names;
- EventKit, source, or record identifiers;
- source temporal payloads;
- bearer tokens or Keychain values;
- pending source or status envelopes;
- production databases or rows;
- accessibility trees;
- DOM dumps;
- API request/response bodies containing real source data;
- screenshots of a real-data Board or source-selection surface;
- certificates, provisioning profiles, Team IDs, or signer details.

The owner may inspect the real Board privately. Agent-visible acceptance proof must use purpose-built content-free surfaces and report only:

- schema success/failure;
- entity item counts;
- freshness categories;
- permission categories;
- result kinds;
- revisions;
- masked source ordinals;
- safe timestamps.

The Phase 3B accessibility-inspection incident did not enter Git, but it establishes a hard process rule: do not use screenshot, accessibility, OCR, DOM, or general UI inspection on real-data surfaces as agent evidence.

## Engineering Guardrails

### Dependencies

Prefer existing Zod, Fastify, Node 24 standard library, Apple frameworks, and current project tooling. Stop before adding a package, Swift package, time-zone library, ORM, generic scheduler, UI framework, or persistence abstraction.

### Resource lifecycle

In mirror-backed mode, ingestion, status storage, and Board composition must share Core-owned resources safely and close them deterministically. Do not open duplicate writable mirror/status subsystems merely to avoid a small lifecycle refactor.

### Logging and errors

Use fixed content-free errors and safe operational metadata. Never log source titles, identifiers, temporal values, Board content, request bodies, status documents, or pending envelopes.

### Testing

Phase 3C is not complete without all proofs in issue #19, including:

- exact shared valid/invalid status fixture inventories in Swift and TypeScript;
- strict status key and semantic rejection;
- exact roster ordering and uniqueness;
- status revision/digest duplicate, stale, and conflict behavior;
- exact pending-status retry across timeout/relaunch;
- source pending envelopes unchanged by status delivery;
- truthful fresh/stale/unavailable derivation;
- deselected source exclusion without mirror deletion;
- truncated/retry/missing selected-source stale behavior;
- Reminder eligibility, ordering, reasons, and three-item cap;
- Calendar eligibility, ordering, reasons, time-zone projection, and two-item cap;
- opaque client IDs;
- final Board runtime validation;
- fixture mode, `/health`, existing source ingestion, mirror, Bridge, probe, and web tests remain green.

Tests use synthetic fixtures only. Private manual acceptance is owner-visible and agent-content-free.

## Git Safety

- Begin from current accepted `main`.
- Work on a new Phase 3C feature branch.
- Do not force-push or rewrite shared history.
- Do not modify the twelve approved Phase 2A specimen bytes.
- Do not change Phase 2B source-contract files or fixture inventories.
- Do not weaken Phase 3A mirror semantics.
- Do not weaken Phase 3B authentication, source pending delivery, signing, sandbox, or permission behavior.
- Do not change the Board contract or web client without a proved compatibility need.
- Keep commits coherent and follow `CONTRIBUTING.md`.
- Do not mix deployment, background scheduling, backup, Apple writes, dependency upgrades, or unrelated formatting into Phase 3C.

## Decision Policy

Agents may make ordinary decisions inside Phase 3C about narrow file names, status field names consistent with issue #19, migration numbering, fixed freshness duration, deterministic reason wording, and focused synthetic test organization.

Stop and ask before:

- changing source authority, identity, revision, retry, or replacement semantics;
- changing `BoardSnapshot` v1;
- adding a dependency or generic framework;
- exposing a raw read/status route;
- allowing non-loopback transport;
- adding deployment or background behavior;
- adding an Apple write;
- adding undated/future Reminder behavior beyond issue #19;
- adding AI or opaque ranking;
- deleting last-good data because status is missing;
- exposing real data outside the local owner-only interface;
- weakening privacy, fixture, freshness, or acceptance proofs;
- beginning Phase 3D or later work.

## Completion Report

At the end of Phase 3C, report:

1. strict Bridge status document shape and fixture inventories;
2. status revision, digest, storage, and exact retry behavior;
3. authenticated status route and lifecycle integration;
4. explicit mirror-backed configuration and Board time zone;
5. selection roster and fresh/stale/unavailable semantics;
6. Reminder eligibility, order, reasons, and capacity;
7. Calendar eligibility, order, reasons, and capacity;
8. opaque client-ID and Board-version behavior;
9. exact Node, Bridge, probe, browser, and build results;
10. accepted Phase 2A/2B/3A/3B integrity;
11. content-free private local acceptance result;
12. files changed, dependencies, and deliberate deviations;
13. everything deferred to Phase 3D;
14. branch, commits, push, draft PR, and clean-working-tree state.

Never include real Board, Calendar, Reminder, source, account, participant, location, note, identifier, token, pending-envelope, database, accessibility, DOM, screenshot, signer, or Team ID values in the report.

Do not claim completion while required gates are failing, source/status honesty is ambiguous, private data has entered agent-visible tooling, fixture mode is broken, accepted boundaries changed, or later-phase work has begun.
