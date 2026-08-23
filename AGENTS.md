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
8. `CONTRIBUTING.md`
9. `SECURITY.md`
10. the active GitHub issue and its review context

If a task conflicts with those documents, pause and explain the conflict instead of silently expanding or redesigning the project.

## Prime Directive

> Build the smallest complete slice that proves the stated product or architectural assumption, then stop.

A complete slice includes working behavior, tests, error states, documentation, and reproducible commands. It does not include speculative scaffolding for later phases.

## Current Phase

Phase 1 — Fixture-Backed Board — is accepted and merged.

Phase 2A — EventKit Discovery Evidence — is accepted and merged in PR #7. Its probe, empirical findings, caveats, and twelve owner-approved sanitized specimens remain evidence inputs.

Phase 2B — Apple Source Contract and Reconciliation Semantics — is accepted and merged in PR #11. The strict v1 Reminder and Calendar snapshots, temporal semantics, ordering/collision rules, truncation authority, and privacy-minimized field set are now the source boundary for connected work.

The current implementation target is **Phase 3A — Atomic Core Apple Source Mirror** from issue #12.

The question for Phase 3A is:

> Can Deskboard Core persist and transactionally reconcile validated Apple source snapshots without deleting unseen facts when a candidate is truncated, stale, duplicated, conflicting, invalid, or scoped to a shifted Calendar window?

This is a Core persistence slice. It is not the Bridge transport, production EventKit conversion, Board integration, homelab deployment, scheduling, or an Apple write path.

### Allowed Phase 3A shape

Phase 3A may add only what the isolated source-mirror proof requires, approximately:

```text
apps/api/src/apple-source-mirror/   SQLite migrations, repository, and apply service
apps/api/test/                      focused persistence and transaction proofs
docs/apple-source-mirror.md         accepted mirror and reconciliation semantics
```

Use the accepted Phase 2B source contract and synthetic fixtures as the input boundary. The production Board must remain fixture-backed.

### Phase 3A permitted behavior

- use the pinned Node 24 built-in `node:sqlite` module for an isolated Core mirror;
- add source-controlled deterministic migrations and enable SQLite foreign keys;
- validate `unknown` input through the accepted strict Apple source contract before mutation;
- accept positive, source-scoped operational revisions outside the source contract;
- derive a deterministic normalized request digest with the Node standard library;
- atomically replace complete Reminder source scopes;
- atomically replace only the overlapping region of complete Calendar windows;
- preserve retained Calendar rows outside the latest accepted window without surfacing them as current-window records;
- reject truncated, invalid, stale, conflicting, or collision-bearing candidates without mutation;
- prove duplicate idempotency, rollback, close/reopen persistence, and migration repeatability;
- expose only narrow internal read methods needed to prove the mirror;
- use in-memory or isolated temporary SQLite databases and synthetic fixtures in tests;
- update architecture and status documentation after the behavior exists.

### Phase 3A forbidden behavior

Do not add:

- an HTTP, WebSocket, or other ingestion endpoint;
- a Swift network client or production EventKit-to-contract converter;
- authentication, tokens, Tailscale, Docker, CasaOS, or deployment configuration;
- a daemon, login item, timer, watcher, or background synchronization schedule;
- Board composition from the mirror;
- changes to `GET /v1/board`, the web client, Board contracts, actions, settings, navigation, or source-management UI;
- Calendar or Reminder writes, Reminder completion, or metadata write-back;
- Open Loop history, Project state, sessions, timers, attention ranking, or AI behavior;
- backup/restore automation or operational monitoring;
- a generic persistence framework or speculative adapter abstraction for future sources;
- private EventKit values in fixtures, tests, logs, errors, issues, PRs, or completion reports.

Deferred means absent, not partially implemented.

## Product Guardrails

- Apple Calendar and Reminders remain authoritative for source facts.
- Deskboard replicates facts, not authority.
- Ordinary Reminders remain candidate Tasks by default.
- Selected Calendar events remain candidate Commitments by default.
- Recurrence is a source schedule fact, not automatic Open Loop classification.
- Date-only, local-time, timezone-qualified, and all-day values remain distinct.
- The Board remains a curated field of attention, not a backlog.
- The Core mirror stores validated source facts; it does not invent semantic interpretation.
- The source contract must not be widened merely to simplify storage.
- Every committed example remains synthetic and safe to publish.

## Accepted Source-Contract Guardrails

### Contract immutability

`AppleReminderSourceSnapshotV1` and `AppleCalendarSourceSnapshotV1` are accepted boundaries. Do not add, remove, rename, or reinterpret a v1 field during Phase 3A. Stop for architecture review before proposing a new schema version.

### Scope authority

- A Reminder snapshot covers one Bridge, one Reminder list, and every accessible Reminder in that declared scope.
- A Calendar snapshot covers one Bridge, one Calendar container, and events overlapping its exact `[window.start, window.end)` scope.
- Only a strictly and semantically validated, non-truncated snapshot may authorize absence.
- A complete empty snapshot is authoritative only inside its exact declared scope.
- A truncated, malformed, failed, partial, collision-bearing, or semantically invalid candidate authorizes no deletion.
- Calendar rows outside a newly accepted window were not observed and must not be called absent.

### Identity

- Local identifiers are scoped to Bridge + entity + source container.
- External identifiers, Calendar event identifiers, and occurrence dates remain optional provenance hints.
- Do not false-merge records.
- Phase 3A performs scoped replacement, not historical continuity matching.
- Equal complete ordering coordinates invalidate the candidate and preserve the previous good scope.

## Mirror and Sequencing Guardrails

### Operational revision

`sourceRevision` is positive operational metadata supplied by a later transport layer and scoped to:

```text
bridgeId + entityType + sourceContainerId
```

It does not enter source contract v1.

Required behavior:

- greater revision: candidate may apply;
- same revision and same normalized digest: duplicate success with no state change;
- same revision and different digest: conflict with no state change;
- lower revision: stale with no state change;
- invalid or truncated candidate: no state change and no revision advancement.

A future Bridge state reset must use a new opaque `bridgeId`; do not silently restart revisions for an existing identity.

### Transactions

- Validate before beginning destructive mutation.
- Apply scope metadata and source records in one SQLite transaction.
- Commit everything or nothing.
- An injected failure after deletion must roll back deletions, inserts, metadata, revision, and freshness.
- Never persist the original unvalidated request body.
- Persisted JSON, if used, must come from accepted parsed values and be strictly revalidated when read.

### Reminder replacement

A complete Reminder snapshot atomically replaces the whole Bridge/entity/container scope. A complete empty snapshot clears only that exact scope. Another Bridge or list is unaffected.

### Calendar replacement

A complete Calendar snapshot removes previously mirrored rows in the same Bridge/container whose interpreted ranges overlap the new window, inserts the accepted records, and updates accepted scope metadata atomically.

Rows outside the new window remain stored because they were not observed. Current-window reads must not surface retained out-of-window rows. An empty Calendar snapshot clears only its overlap region.

### Truncation

Phase 3A deliberately does not partially apply a truncated snapshot. It returns an explicit non-applied result, preserves records and scope metadata, and does not advance revision or freshness.

## Engineering Guardrails

### Dependencies

Prefer the pinned Node 24 built-in `node:sqlite` module and the existing standard-library and workspace dependencies. Stop for approval before adding a SQLite package, changing the Node major, adding an ORM, or adding a migration framework.

Do not add a generic repository framework. Implement the smallest Apple source-mirror boundary required by issue #12.

### Database hygiene

- Keep database files, journals, dumps, and backups ignored.
- Tests use `:memory:` or isolated temporary files.
- Enable foreign-key enforcement for every connection.
- Use strict tables and explicit constraints where practical.
- Migrations are source-controlled, ordered, repeatable, and tested against an existing database.
- Close resources deterministically in tests and production code.

### Logging and errors

Logs, return values, and thrown errors may include only safe operational metadata such as entity type, opaque coordinate, revision, and result code. Never log titles, temporal payloads, identifiers from individual records, notes, locations, URLs, or full snapshot JSON.

### Testing

Phase 3A is not complete without:

- acceptance of every shared valid Phase 2B fixture at the mirror boundary;
- rejection of every shared invalid fixture before mutation;
- exact preservation of the Phase 2A evidence allowlist and bytes;
- Reminder first-apply, replacement, empty-scope, and scope-isolation tests;
- Calendar overlapping-window, shifted-window, empty-window, out-of-window retention, and expanding-window tests;
- duplicate, stale, conflict, newer-revision, and truncated no-mutation tests;
- transaction rollback after destructive statements;
- provenance-collision no-mutation proof;
- database close/reopen persistence;
- repeatable migration proof;
- the complete existing Node quality gate;
- the accepted native probe build and Swift test gate.

Tests must not access the user’s EventKit store or `private-fixtures/`.

## Privacy and Security

Never commit or report:

- real Calendar or Reminder records;
- source titles, list names, calendar names, notes, URLs, or locations;
- real EventKit identifiers;
- organizer, attendee, contact, account, or provider details;
- recovery, health, household, or work information;
- `.env` files, credentials, certificates, provisioning profiles, or tokens;
- Tailscale hostnames, keys, or tailnet identifiers;
- private exports, production databases, dumps, backups, logs, or screenshots containing personal data.

`private-fixtures/` remains local and ignored. The Phase 2A probe’s disabled app sandbox is not a production Bridge precedent.

## Git Safety

- Begin from current accepted `main`.
- Work on a feature branch, not directly on `main`.
- Do not force-push shared branches or rewrite existing history.
- Do not modify the twelve owner-approved Phase 2A specimen JSON bytes.
- Do not weaken the accepted Phase 2B source contract or fixture proofs.
- Do not delete or replace the Manifesto or architecture documents to simplify implementation.
- Keep commits coherent and follow `CONTRIBUTING.md`.
- Do not mix dependency upgrades, Board redesign, transport scaffolding, or deployment work into Phase 3A.

## Decision Policy

Agents may make ordinary implementation decisions inside Phase 3A, including SQLite table names, migration file organization, narrow internal interfaces, and focused synthetic test structure.

Stop and ask before:

- changing the source contract or data-ownership model;
- adding any dependency, ORM, migration framework, or changing Node versions;
- adding a network route, client, authentication, transport envelope, database API, or deployment system;
- exposing the mirror to the Board or changing the Board contract;
- applying truncated snapshots partially;
- changing operational revision scope or reset semantics;
- persisting unvalidated input;
- weakening transaction, rollback, idempotency, privacy, or exit proofs;
- modifying approved Phase 2A evidence bytes;
- exposing personal data outside the trusted local environment;
- beginning later Phase 3 work.

## Completion Report

At the end of a Phase 3A task, report:

1. SQLite and migration shape;
2. operational revision and normalized digest semantics;
3. Reminder replacement behavior;
4. Calendar overlap-window replacement and out-of-window retention;
5. apply-result variants;
6. validation-before-mutation and rollback proofs;
7. migration and reopen proofs;
8. exact Node and native validation commands and results;
9. Phase 2A evidence and Phase 2B fixture integrity;
10. dependencies added, if any;
11. files changed and deliberate deviations;
12. what remains deferred to later Phase 3 slices;
13. branch, commits, push, draft PR, and clean-working-tree state.

Never include real Calendar, Reminder, source, account, participant, location, note, or record-identifier values in the report.

Do not claim completion while tests are failing, the documented commands are unverified, private data is present, accepted evidence or contract guarantees have changed, or later Phase 3 work has begun.
