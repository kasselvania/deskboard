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
9. `docs/apple-bridge-manual-delivery.md` when present on the active Phase 3B branch
10. `CONTRIBUTING.md`
11. `SECURITY.md`
12. the active GitHub issue and its review context

If a task conflicts with those documents, pause and explain the conflict instead of silently expanding or redesigning the project.

## Prime Directive

> Build the smallest complete slice that proves the stated product or architectural assumption, then stop.

A complete slice includes working behavior, tests, error states, documentation, and reproducible commands. It does not include speculative scaffolding for later phases.

## Current Phase

Phase 1 — Fixture-Backed Board — is accepted and merged.

Phase 2A — EventKit Discovery Evidence — is accepted and merged in PR #7. Its probe, empirical findings, caveats, and twelve owner-approved sanitized specimens remain evidence inputs.

Phase 2B — Apple Source Contract and Reconciliation Semantics — is accepted and merged in PR #11. `AppleReminderSourceSnapshotV1` and `AppleCalendarSourceSnapshotV1` are strict accepted boundaries.

Phase 3A — Atomic Core Apple Source Mirror — is accepted and merged in PR #14. Its SQLite migrations, revision/digest behavior, exact scope replacement, truncation rules, and transaction semantics are accepted infrastructure.

The current implementation target is **Phase 3B — Authenticated Manual Bridge Delivery** from issue #15.

The feature branch contains the dedicated production Bridge, authenticated Core ingestion boundary, crash-safe pending-delivery state, and synthetic proof suite documented in `docs/apple-bridge-manual-delivery.md`. These are Phase 3B review artifacts, not an accepted basis for Phase 3C. Phase 3B remains active until review and merge.

The question for Phase 3B is:

> Can an explicitly invoked, read-only Mac Bridge produce accepted source snapshots and deliver each scope to the atomic Core mirror without leaking credentials or private content, losing retry identity, or reusing one revision for changed content after an uncertain response?

This is a manual loopback transport slice. It is not homelab deployment, background synchronization, Board integration, or an Apple write path.

### Allowed Phase 3B shape

Phase 3B may add only what issue #15 requires, approximately:

```text
apps/api/src/apple-source-ingestion/    one authenticated loopback ingestion route
apps/api/test/                           route/auth/mirror integration proofs
native/apple-bridge/                     dedicated sandboxed manual macOS Bridge
native/apple-bridge-tests/               pure converter/state/transport tests
docs/apple-bridge-manual-delivery.md     trust, retry, setup, and proof record
```

The exact native directory is an implementation choice. Do not convert the Phase 2A probe into the production Bridge or inherit its disabled sandbox and private-export behavior.

### Phase 3B permitted behavior

- create one sandboxed, hardened macOS Bridge target with outgoing network access and EventKit/Calendar entitlement;
- retain separate intentional Calendar and Reminders permissions and source selections;
- convert selected EventKit records directly into the accepted v1 fields;
- create one strict operational envelope containing `sourceRevision` and one v1 snapshot;
- add one authenticated Core ingestion route that applies through the accepted Phase 3A mirror;
- keep Core and Bridge traffic on loopback for real manual proof;
- use one high-entropy bearer token bound to one opaque Bridge identity;
- store the Bridge token in macOS Keychain and inject fakes in tests;
- persist Bridge identity, per-source acknowledged revisions, pending envelopes, and content-free status in the sandbox container;
- atomically persist an exact pending envelope before sending it;
- retry the same pending envelope and revision after uncertain delivery;
- provide one explicit `Sync Now` action and local content-free per-source status;
- define explicit finite Calendar/Reminder record and HTTP body limits;
- document and prove auth, retry, truncation, stale/conflict, timeout, permission, and cleanup behavior.

### Phase 3B forbidden behavior

Do not add:

- LAN or public API listening;
- Tailscale, TLS termination, reverse proxy, Docker, CasaOS, or homelab deployment;
- background scheduling, daemon, launch-at-login, menu-bar agent, watcher, or notification;
- Board composition from the source mirror;
- changes to `GET /v1/board`, Board contracts, web client, navigation, settings, or source-management UI;
- more than one ingestion route;
- a Core read/status route for the Board;
- Calendar or Reminder writes, Reminder completion, or metadata write-back;
- automatic conflict/stale recovery or silent Bridge identity reset;
- multi-user accounts, OAuth, sessions, token service, certificate authority, or general authentication framework;
- generic adapter, outbox, transport, credential, or persistence frameworks for imagined future sources;
- Notes, Home Assistant, Open Loops, Projects, sessions, timers, ranking, AI, or later-phase features;
- private source values, credentials, pending envelopes, databases, or screenshots in GitHub.

Deferred means absent, not partially implemented.

## Product Guardrails

- Apple Calendar and Reminders remain authoritative for source facts.
- Deskboard replicates facts, not authority.
- Calendar and Reminders remain read-only.
- Ordinary Reminders remain candidate Tasks; Calendar events remain candidate Commitments.
- Recurrence remains a source schedule fact, not an Open Loop classification.
- Date-only, local-time, timezone-qualified, and all-day meanings remain distinct.
- The Board remains fixture-backed and a curated field of attention, not a backlog.
- The production Bridge reads and emits only accepted v1 fields; it must not collect excluded private fields for convenience.
- Every committed fixture and automated example remains synthetic and publish-safe.

## Accepted Boundaries

### Source contract

Do not add, remove, rename, or reinterpret a v1 source-contract field. Stop for architecture review before proposing another version.

- Reminder scope is one Bridge + one selected Reminder list + all accessible records in that list.
- Calendar scope is one Bridge + one selected Calendar + records overlapping the exact declared window.
- Only a strict, semantically valid, non-truncated snapshot authorizes absence.
- Complete empty snapshots are authoritative only inside their exact scopes.
- Provenance/order collisions invalidate the candidate.

### Core mirror

Do not duplicate or weaken Phase 3A behavior in the route.

- source revision scope is Bridge + entity + container;
- same revision/same digest is idempotent;
- same revision/different digest is conflict;
- lower revision is stale;
- truncated or invalid input does not mutate or advance the accepted scope;
- Reminder replacement is whole-scope;
- Calendar replacement is overlap-window only;
- all accepted destructive work commits atomically.

## Trust and Topology Guardrails

### Loopback only

During Phase 3B, real source payloads travel only between processes on the same Mac through an explicit loopback origin. The API server must remain bound to `127.0.0.1` or `::1`.

The Bridge must reject non-loopback delivery URLs. Phase 3C owns Tailscale and private remote deployment.

### One authenticated Bridge

Core supports one configured opaque Bridge ID and one bearer token in this slice.

- token only in the `Authorization: Bearer` header;
- no token in query, URL, JSON, SQLite, logs, screenshots, or completion report;
- route-level authentication runs before body parsing;
- compare secret material in constant time;
- accepted snapshot Bridge ID must match the authenticated Bridge ID;
- route is absent or startup fails safely when required ingestion configuration is incomplete;
- all errors and results remain content-free.

### Body and source limits

Set explicit finite body and per-source record limits. Ordering happens before caps and `matchedCount` remains exact.

A truncated source is not synchronized. Do not silently filter, split a v1 scope, or narrow Reminder scope by completion/date without a new contract version.

## Bridge State and Retry Guardrails

### Persistent identity

Generate and persist one opaque random Bridge ID in the sandbox container. Persist separate Calendar and Reminder source selections, acknowledged revisions, and pending state.

If state is deliberately reset or lost, generate a new Bridge ID. Do not restart revision 1 under an old identity.

### Crash-safe pending envelope

Before a new send:

1. derive the next source-scoped revision;
2. build and validate the complete envelope;
3. atomically persist the exact envelope;
4. send the persisted envelope.

After timeout, crash, process restart, or uncertain response, resend the exact persisted envelope at the same revision. Do not reread EventKit and reuse that revision for changed content.

Only `applied` and `unchangedDuplicate` acknowledge the revision and clear pending state.

`rejectedTruncated`, `rejectedInvalid`, `rejectedStale`, `rejectedRevisionConflict`, transport failure, malformed response, and timeout do not advance revision. Preserve pending state and fail closed.

Pending envelopes contain private source facts. Keep them only in the sandbox container. Never print, export, attach, screenshot, or commit them.

## Native Security Guardrails

The production Bridge target must prove:

- App Sandbox enabled;
- Hardened Runtime enabled;
- outgoing network-client entitlement;
- required EventKit/Calendar entitlement and full-access usage descriptions;
- no incoming-network entitlement;
- no arbitrary file access;
- no private export or probe command mode;
- no EventKit save/remove call;
- token access through a Keychain-backed credential boundary;
- synthetic tests use in-memory credential and state fakes.

The local UI may show source titles on the owner’s Mac. Automated logs, screenshots, PRs, and reports must use masked labels, counts, and result kinds only.

## Engineering Guardrails

### Dependencies

Prefer Apple frameworks, Node standard library, existing Fastify/Zod workspaces, and existing project tooling. Stop before adding a package, Swift package, project generator, auth library, Keychain wrapper, networking framework, or generic storage abstraction.

### Core route

Use the existing `AppleSourceMirror`. Keep one strict route, one operational envelope, explicit response mapping, and an `onClose` hook for owned mirror resources.

Do not expose mirror read methods over HTTP.

### Production converter

Read only fields admitted by v1. Preserve exact Calendar instants, civil all-day dates, Reminder date-only values, accepted ordering, collision rejection, exact match count, and truncation.

Do not read or copy notes, locations, URLs, participants, alarms, account titles, recurrence grammar, or other excluded probe fields.

### Logging and errors

Never log request bodies, bearer tokens, source/container identifiers, record identifiers, titles, temporal payloads, pending envelopes, or complete snapshots.

Use fixed error/result codes and safe operational status only.

## Required Testing

Phase 3B is not complete without all proofs in issue #15, including:

- auth before parsing/application;
- strict envelope, Bridge-ID binding, body limit, and content-free results;
- every Phase 3A result mapped through the route;
- duplicate delivery idempotency through Fastify;
- `/health` and fixture Board unchanged;
- production converter from synthetic EventKit-shaped inputs;
- exact v1 field minimization and temporal semantics;
- separate empty-by-default source selections;
- first revision, acknowledgement, exact retry, relaunch, timeout, conflict, stale, invalid, and truncation state proofs;
- Keychain boundary with injected synthetic test credential;
- loopback URL enforcement and strict response parsing;
- built entitlement inspection and absence of EventKit writes;
- complete existing Node and native gates;
- content-free manual local Calendar and Reminder proof.

Tests must not require the user’s real EventKit store unless explicitly marked as a private manual acceptance step. No private values may enter test output or Git.

## Privacy and Security

Never commit or report:

- real Calendar or Reminder titles, records, notes, locations, URLs, or temporal payloads;
- real source/list/calendar/account names;
- real EventKit or source identifiers;
- participant, contact, provider, work, recovery, household, or health information;
- bearer tokens, Keychain values, `.env` files, pending envelopes, production databases, logs, screenshots, certificates, or provisioning profiles;
- Tailscale hostnames, keys, or tailnet identifiers.

`private-fixtures/` remains local and ignored. Production Bridge state belongs only inside its sandbox container and Keychain.

## Git Safety

- Begin from current accepted `main`.
- Work on a feature branch, not directly on `main`.
- Do not force-push or rewrite shared history.
- Do not modify the twelve approved Phase 2A specimen bytes.
- Do not change Phase 2B contract fixtures or semantics without stopping for review.
- Do not weaken Phase 3A transaction, revision, digest, or replacement behavior.
- Keep commits coherent and follow `CONTRIBUTING.md`.
- Do not mix deployment, Board, background scheduling, write paths, dependency upgrades, or unrelated formatting into Phase 3B.

## Decision Policy

Agents may make ordinary decisions inside Phase 3B about narrow file names, SwiftUI layout, local state-file structure, exact finite caps, HTTP status mapping, and focused test organization.

Stop and ask before:

- changing the source contract, authority model, revision scope, or mirror semantics;
- adding a dependency or general framework;
- allowing non-loopback delivery;
- changing authentication from the one-Bridge bearer-token boundary;
- adding another route or remote read API;
- discarding or rewriting pending data after uncertain delivery;
- automatically recovering stale/conflict state;
- weakening sandbox, Keychain, privacy, body-limit, content-free error, or retry proofs;
- exposing private data outside the trusted local environment;
- beginning Phase 3C or any Apple write work.

## Completion Report

At the end of a Phase 3B task, report:

1. production Bridge target and security entitlements;
2. EventKit-to-v1 conversion and excluded-field proof;
3. Core route, auth, body limit, and Bridge-ID binding;
4. Bridge identity and per-source revision persistence;
5. crash-safe pending-envelope behavior;
6. result/status mapping and failure behavior;
7. converter, route, credential, retry, and entitlement tests;
8. content-free manual local proof;
9. exact Node and native validation commands and results;
10. Phase 2A, Phase 2B, and Phase 3A integrity;
11. files changed, dependencies added, and deliberate deviations;
12. everything deferred to Phase 3C;
13. branch, commits, push, draft PR, and clean-working-tree state.

Never include real Calendar, Reminder, source, account, participant, location, note, token, pending-envelope, or record-identifier values in the report.

Do not claim completion while tests are failing, required commands are unverified, private data is present, pending retry semantics are unsafe, the production target is not sandboxed, or later-phase work has begun.
