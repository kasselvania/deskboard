# Coding Agent Instructions

This repository is intentionally small and staged. Coding agents are expected to complete the requested slice, prove it, document it, and stop.

Before changing code or configuration, read:

1. `README.md`
2. `MANIFESTO.md`
3. `ARCHITECTURE.md`
4. `ROADMAP.md`
5. `docs/apple-source-mapping-v0.1.md`
6. `docs/apple-eventkit-discovery.md`
7. `CONTRIBUTING.md`
8. `SECURITY.md`
9. the active GitHub issue and its review context

If a task conflicts with those documents, pause and explain the conflict instead of silently expanding or redesigning the project.

## Prime Directive

> Build the smallest complete slice that proves the stated product or architectural assumption, then stop.

A complete slice includes working behavior, tests, error states, documentation, and reproducible commands. It does not include speculative scaffolding for later phases.

## Current Phase

Phase 1 — Fixture-Backed Board — is accepted and merged.

Phase 2A — EventKit Discovery Evidence — is accepted and merged in PR #7. Its probe, empirical findings, caveats, and owner-approved sanitized specimens are evidence inputs. They are not the final production source contract.

The current implementation target is **Phase 2B — Apple Source Contract and Reconciliation Semantics** from issue #8.

The feature branch contains the draft v1 contract in `docs/apple-source-contract-v1.md`, strict TypeScript and Swift validators, and separately versioned shared fixtures. These are Phase 2B review artifacts, not an accepted production Bridge. Phase 2B remains active and Phase 3 remains blocked until the draft pull request passes implementation review and is merged.

The question for Phase 2B is:

> What is the smallest versioned Apple-source contract that a later one-way mirror can transport and reconcile without losing the distinctions established in Phase 2A?

This is a contract and reconciliation-design slice. It is not the production Bridge, transport, source mirror, deployment, or Board integration.

### Allowed Phase 2B shape

Phase 2B may add only what the contract slice requires, approximately:

```text
packages/contracts/                  runtime-validated Apple source schemas and derived TypeScript types
tools/apple-eventkit-probe/          minimal Swift contract models/conversion and pure validation tests
fixtures/apple-source-contract/      synthetic cross-language contract examples
docs/                                field-minimization, identity, and reconciliation decisions
```

Use the existing EventKit specimens as evidence. Do not rewrite them into the production contract by default. Contract fixtures should be separately named, versioned, synthetic, and minimal.

### Phase 2B permitted behavior

- define separate versioned Reminder and Calendar source-record variants;
- define explicit temporal unions that preserve absence, date-only, local date-time, timezone-qualified date-time, timed start/end, and exclusive all-day ranges;
- classify every observed field as required, optional with a present use, deferred, or excluded;
- define bridge-scoped provenance and conservative identity/reconciliation rules;
- define deterministic ordering, bounds, retained-set meaning, and explicit truncation semantics;
- add matching Swift Codable/validation models and TypeScript runtime schemas;
- validate the same synthetic JSON shapes in both languages;
- add negative fixtures for unsupported versions, malformed unions, impossible dates, and invalid ranges;
- document complete atomic source-scope snapshot semantics for Phase 3 without implementing them;
- perform a narrowly targeted manual observation with synthetic Apple objects only when it materially changes the contract decision.

### Phase 2B forbidden behavior

Do not add:

- HTTP, WebSockets, another Bridge-to-Core transport, or any network client;
- SQLite, Postgres, Redis, or another database;
- synchronization-generation persistence or source-mirror implementation;
- Tailscale, Docker, CasaOS, homelab deployment, a daemon, login item, or background scheduler;
- Calendar or Reminder writes of any kind;
- Reminder completion or metadata write-back;
- production metadata parsing, Open Loop history, Project state, sessions, timers, or attention ranking;
- AI classification, summaries, or agents;
- new Board actions, settings, navigation, source management, or a production EventKit data path;
- generic adapter frameworks, code-generation systems, or abstractions for future sources;
- private EventKit values in fixtures, tests, logs, issues, PRs, or completion reports.

Deferred means absent, not partially implemented.

## Product Guardrails

- Apple Calendar and Reminders remain authoritative for source facts.
- Deskboard replicates facts, not authority.
- Ordinary Reminders remain candidate Tasks by default.
- Selected Calendar events remain candidate Commitments by default.
- Recurrence is a source schedule fact, not automatic Open Loop classification.
- Date-only, local-time, timezone-qualified, and all-day values must remain distinct.
- The Board remains a curated field of attention, not a backlog.
- The source contract must not become a raw EventKit dump.
- A field enters version 1 only when preservation or a present Phase 3 use justifies its privacy and maintenance cost.
- Organizer and attendee identities remain excluded.
- Every committed example must be synthetic and safe to publish.

## Contract Guardrails

### Separate records, shared primitives

Define explicit Apple Reminder and Apple Calendar record variants. Shared primitives such as provenance, container identity, temporal values, recurrence structure, or truncation metadata may be reused when their semantics are truly identical.

Do not hide entity differences behind a generic payload or an unvalidated dictionary.

### Minimality and privacy

For each candidate field, document one of:

- required in source contract version 1;
- optional in version 1 with a current use;
- deferred extension;
- excluded for privacy or lack of need.

Notes, alarms, URLs, locations, availability, participant information, creation timestamps, and other exposed EventKit fields do not enter version 1 merely because they were observed.

### Identity and reconciliation

- Scope local identifiers to a specific Bridge and source container.
- Treat external identifiers as optional hints, not universal keys.
- Keep Calendar event identifier and occurrence date as separate provenance facts.
- Do not claim identifier durability that Phase 2A did not observe.
- Prefer a conservative remove-plus-add result over a false merge when identity changes cannot be resolved safely.
- Specify complete atomic source-scope snapshots for Phase 3 rather than assuming fragile incremental semantics.

### Determinism and bounds

- Apply deterministic ordering before any cap.
- Define what the retained subset means for Calendar and Reminders.
- Represent matched count and truncation honestly.
- Preserve exact instants for timezone-qualified Calendar ranges; reject ambiguous or nonexistent local Calendar times instead of choosing an occurrence.
- Require complete ordering coordinates to be unique; a collision invalidates the candidate and retains the previous good scope.
- Authorize absence only for a successful non-truncated snapshot inside its exact Bridge, entity, container, and Calendar-window scope.
- Expose absence authority only after strict runtime and semantic validation; a structural type or Codable decode alone is not authority.
- A failed, partial, malformed, or truncated replacement must retain the previous good scope and must not delete unseen records.
- Preserve the accepted Calendar discovery window unless evidence justifies a documented change.
- Do not silently discard records while claiming a complete scope.

## Engineering Guardrails

### Dependencies

Prefer the existing Zod contract package, Apple platform APIs, and the Swift/Foundation standard libraries. Add no dependency, project generator, code generator, or monorepo tool unless a current Phase 2B proof cannot reasonably be completed without it.

When adding a dependency, stop for approval and record the exact current requirement it satisfies.

### Cross-language agreement

Swift and TypeScript must independently validate the same committed contract fixtures. Agreement means compatible wire semantics, not duplicated source code or generated models.

The contract boundary must reject:

- unsupported schema versions;
- unknown or contradictory temporal shapes where strictness is intended;
- impossible dates and date-times;
- all-day ranges whose exclusive end is not after the start;
- inconsistent completion, occurrence, or truncation facts defined by the contract.

### Testing

The Phase 2B slice is not complete without:

- TypeScript runtime-schema tests for valid and invalid contract fixtures;
- Swift encode/decode and semantic-validation tests against the same fixtures;
- exact committed contract-fixture inventory checks;
- continued validation of the twelve approved Phase 2A EventKit specimens without reading private data;
- deterministic ordering, cap, and truncation tests;
- documentation proving field inclusion/exclusion and identity/reconciliation decisions;
- the existing native probe build and Swift test gate;
- the existing Node lint, typecheck, unit, browser, and production-build gate.

Tests must not require access to the user's real EventKit store.

### Privacy and Security

Never commit or report:

- real Calendar or Reminder records;
- source titles, list names, calendar names, notes, URLs, or locations;
- local or external EventKit identifiers;
- organizer, attendee, contact, account, or provider details;
- recovery, health, household, or work information;
- `.env` files, credentials, certificates, or provisioning profiles;
- Tailscale hostnames, keys, or tailnet identifiers;
- private exports, database files, production logs, or screenshots containing personal data.

`private-fixtures/` remains local and ignored. The Phase 2A probe's disabled app sandbox is not a production precedent; production Bridge sandbox and entitlement decisions remain deferred.

### Git Safety

- Work on a feature branch, not directly on `main`, unless the user explicitly directs otherwise.
- Begin from the accepted Phase 2A `main` branch.
- Do not force-push shared branches or rewrite existing history.
- Do not modify the twelve owner-approved Phase 2A specimen bytes without stopping for renewed owner review.
- Do not delete or replace product philosophy or architecture documents to make implementation easier.
- Keep commits coherent and use the conventions in `CONTRIBUTING.md`.
- Do not mix broad formatting, dependency upgrades, Phase 1 redesign, or Phase 3 scaffolding into the contract slice.

## Decision Policy

Agents may make ordinary implementation decisions inside Phase 2B, including schema file organization, names for current contract primitives, focused test structure, and synthetic negative examples.

Stop and ask before:

- changing the architecture or data-ownership model;
- adding a field without a present use or preservation rationale;
- claiming an EventKit identifier is durable beyond observed evidence;
- requesting or performing Apple write access;
- adding any network communication, database, cloud service, deployment, or authentication system;
- adding a generic adapter or code-generation framework;
- changing the Board contract or interaction model;
- weakening a proof test or exit criterion;
- modifying approved Phase 2A fixture bytes;
- exposing personal data outside the local environment;
- beginning Phase 3 or later work.

An unobserved source case remains `not tested`. Do not fabricate support.

## Completion Report

At the end of a Phase 2B task, report:

1. the exact versioned contract shape and files;
2. the field inclusion/exclusion matrix and rationale;
3. the identity and reconciliation policy;
4. deterministic ordering, bounds, and truncation semantics;
5. the same-fixture Swift and TypeScript proof results;
6. the exact native and Node validation commands and results;
7. any deliberate deviations;
8. files changed and dependencies added, if any;
9. what remains deferred to Phase 3;
10. branch, commits, push, pull-request, and working-tree state.

Never include real Calendar, Reminder, source, account, participant, location, note, or identifier values in the report.

Do not claim completion while tests are failing, the documented commands are unverified, private data is present, approved evidence has changed without review, or Phase 3 work has begun.
