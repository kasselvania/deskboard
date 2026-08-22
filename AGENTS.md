# Coding Agent Instructions

This repository is intentionally small and staged. Coding agents are expected to complete the requested slice, prove it, document it, and stop.

Before changing code or configuration, read:

1. `README.md`
2. `MANIFESTO.md`
3. `ARCHITECTURE.md`
4. `ROADMAP.md`
5. `docs/apple-source-mapping-v0.1.md`
6. `CONTRIBUTING.md`
7. `SECURITY.md`

If a task conflicts with those documents, pause and explain the conflict instead of silently expanding or redesigning the project.

## Prime Directive

> Build the smallest complete slice that proves the stated product or architectural assumption, then stop.

A complete slice includes working behavior, tests, error states, documentation, and reproducible commands. It does not include speculative scaffolding for later phases.

## Current Phase

Phase 1 — Fixture-Backed Board — is accepted and merged.

The current branch remains **Phase 2A — EventKit Discovery Evidence** acceptance cleanup for draft PR #7. The empirical probe and approved evidence set are implemented, but Phase 2A remains unaccepted until the pull request passes implementation review and is merged.

The question for Phase 2A is:

> What supported EventKit data is actually available from selected Apple Calendar and Reminder sources, and what is the smallest lossless representation Deskboard will need for the later one-way mirror?

This is an empirical, read-only discovery slice. It is not the production Bridge.

Issue #8 defines **Phase 2B — Apple Source Contract and Reconciliation Semantics** as the next bounded slice after Phase 2A merge. Agents must not begin Phase 2B or Phase 3 while PR #7 remains unaccepted.

### Allowed Phase 2A shape

Phase 2A may add only what the discovery spike and its acceptance corrections require, approximately:

```text
tools/apple-eventkit-probe/   minimal native macOS Swift/SwiftUI probe
fixtures/eventkit/            sanitized structural examples
docs/apple-eventkit-discovery.md
```

A focused synthetic Board fixture and test may be added only to prove that the existing Phase 1 presentation contract can render an EventKit-derived shape. The production Board data path must remain fixture-backed.

### Phase 2A permitted behavior

- request read access to Calendar and Reminders;
- enumerate and explicitly select source calendars and Reminder lists;
- read bounded Calendar and Reminder data locally;
- inspect EventKit field availability and temporal behavior;
- create private local inspection exports under an ignored path;
- generate aggressively sanitized synthetic examples;
- document verified, unavailable, and unresolved fields;
- test pure normalization and sanitization behavior;
- update architecture documentation after observations exist.

### Phase 2A forbidden behavior

Do not add:

- Calendar or Reminder writes of any kind;
- Reminder completion from Deskboard;
- a production Bridge-to-Core network path;
- HTTP clients, Tailscale, homelab deployment, or Docker;
- SQLite, Postgres, Redis, or another database;
- a background daemon, login item, or always-on agent;
- authentication or authorization;
- Open Loop history, Project state, sessions, timers, or attention ranking;
- AI classification, summaries, or agents;
- Notes, Contacts, Mail, Health, Home Assistant, weather, Sonos, media, ESP32, or camera integrations;
- new Board actions, settings, navigation, or source-management UI;
- generic adapter frameworks or placeholder packages for later phases.

Deferred means absent, not partially implemented.

## Product Guardrails

- Apple Calendar and Reminders remain authoritative for source facts.
- The probe observes source behavior; it does not administer source applications.
- Ordinary Reminders are candidate Tasks by default.
- Selected Calendar events are candidate Commitments by default.
- Recurrence is evidence, not automatic Open Loop classification.
- Date-only, local-time, timezone-qualified, and all-day values must remain distinct.
- Dynamic Deskboard state must not be written into Reminder notes.
- The existing Board remains a curated field of attention, not a backlog.
- The existing Phase 1 Board must remain usable throughout the spike.
- Every committed example must be synthetic and safe to publish.

## Engineering Guardrails

### Dependencies

Prefer Apple platform APIs and the standard library. Add no Swift package, project generator, or Node dependency unless a current discovery requirement cannot reasonably be met without it.

When adding a dependency, record the reason in the pull request description.

### Native project scope

Prefer a minimal macOS SwiftUI application contained under `tools/apple-eventkit-probe/`.

Do not introduce XcodeGen, Tuist, CocoaPods, a cross-platform framework, or a production application architecture for a disposable discovery spike.

Wrap EventKit-dependent reads behind the smallest practical boundary so pure temporal normalization and sanitization logic can be tested with synthetic inputs.

### Testing

The Phase 2A slice is not complete without:

- a reproducible native macOS build;
- Swift unit tests for pure normalization, selection persistence, and sanitization behavior;
- documented manual permission and source-selection checks;
- sanitized fixtures reviewed for private data;
- the existing Node lint, typecheck, unit, browser, and production-build gate;
- documentation that distinguishes verified facts from recommendations and unresolved questions.

Tests should prove behavior and boundaries, not implementation trivia. Tests must not require access to the user's real EventKit store.

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

Private inspection output must remain in an ignored local directory. Sanitization must replace private values, not rely on partial redaction.

### Git Safety

- Work on a feature branch, not directly on `main`, unless the user explicitly directs otherwise.
- Do not force-push shared branches.
- Do not rewrite existing history.
- Do not delete or replace project philosophy and architecture documents to make implementation easier.
- Keep commits coherent and use the commit conventions in `CONTRIBUTING.md`.
- Do not mix broad formatting, dependency upgrades, Phase 1 redesign, or later-phase work into the spike.

## Decision Policy

Agents may make ordinary implementation decisions inside Phase 2A, including small native file organization, naming, test structure, and local UI details required for permission and source selection.

Stop and ask before:

- changing the architecture or data-ownership model;
- requesting or performing Apple write access;
- adding any network communication, database, cloud service, or authentication system;
- freezing the final Bridge-to-Core schema before observations are documented;
- declaring Project anchors, metadata grammar, importance, or ranking behavior final;
- adding a new production route, endpoint, application, persistent service, or Board interaction;
- weakening a proof test or exit criterion;
- exposing personal data outside the local environment;
- beginning work from Phase 2B, Phase 3, or later while PR #7 remains unaccepted.

An unobserved source case remains `not tested`. Do not fabricate support.

## Completion Report

At the end of a coding task, report:

1. what was built;
2. the macOS, Xcode, and Swift versions used;
3. the exact commands used to validate it;
4. which automated and manual checks passed;
5. which EventKit behaviors were verified, unavailable, or not tested;
6. any deliberate deviations from the requested design;
7. the sanitized fixtures added;
8. the files changed;
9. what remains deferred;
10. the branch, commits, push, pull-request, and working-tree state.

Never include real Calendar, Reminder, source, account, participant, location, note, or identifier values in the report.

Do not claim completion while tests are failing, the documented run commands are unverified, private data is present, or later-phase work has been started.
