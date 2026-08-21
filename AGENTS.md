# Coding Agent Instructions

This repository is intentionally small and staged. Coding agents are expected to complete the requested slice, prove it, document it, and stop.

Before changing code or configuration, read:

1. `README.md`
2. `MANIFESTO.md`
3. `ARCHITECTURE.md`
4. `ROADMAP.md`
5. `CONTRIBUTING.md`

If a task conflicts with those documents, pause and explain the conflict instead of silently expanding or redesigning the project.

## Prime Directive

> Build the smallest complete slice that proves the stated product or architectural assumption, then stop.

A complete slice includes working behavior, tests, error states, documentation, and reproducible commands. It does not include speculative scaffolding for later phases.

## Current Phase

The current implementation target is **Phase 1 — Fixture-Backed Board** from `ROADMAP.md`.

Until that phase is explicitly accepted, do not add:

- Apple Calendar or Reminders integration;
- Swift or EventKit code;
- SQLite, Postgres, Redis, or another database;
- authentication or authorization;
- Docker as a requirement for local development;
- Tailscale configuration;
- Home Assistant, weather, Sonos, media, ESP32, or camera integrations;
- write actions of any kind;
- WebSockets, Server-Sent Events, or push notifications;
- AI ranking, summaries, or agent features;
- a settings screen, app navigation, project browser, or generic dashboard framework;
- placeholder packages or empty adapters for future phases.

Deferred means absent, not partially implemented.

## Required First-Slice Shape

The first implementation should contain only what the roadmap requires:

```text
apps/web/          React + TypeScript + Vite
apps/api/          Fastify + TypeScript
packages/contracts runtime schemas and shared types
fixtures/board/    synthetic fixture data
```

Use npm workspaces unless a current requirement demonstrates that another monorepo tool is necessary.

The initial API surface is limited to:

```text
GET /health
GET /v1/board
```

The initial user-facing route is limited to:

```text
/board
```

## Product Guardrails

- The Board is a curated field of attention, not a backlog.
- The first Board is read-only.
- The server composes a display-ready Board; the client does not independently rank source items.
- The Board should fit the target viewport without document-level vertical scrolling.
- White space is a feature.
- Every visible item needs a concise, human-readable reason for being present.
- No essential meaning may depend only on color.
- Do not add animation unless it communicates state that cannot be communicated more simply.
- Do not use a generic admin/dashboard template, charting library, or large UI component framework.
- Do not add outbound links or notification permissions.
- Fixtures must be synthetic and safe to publish.

## Engineering Guardrails

### Dependencies

Add a dependency only when it directly supports a requirement in the current slice. Prefer platform capabilities and small libraries over frameworks layered on frameworks.

When adding a dependency, record the reason in the pull request description.

### Contracts

- Define runtime-validated contracts in `packages/contracts`.
- Derive or share TypeScript types from the same source when practical.
- Validate API responses against the contract in tests.
- Model date-only values separately from instants and timed values.
- Reject unsupported schema versions safely.

### Testing

The requested slice is not complete without:

- linting;
- type checking;
- unit tests;
- API contract tests;
- component/accessibility tests;
- browser proof tests at the iPad and Steam Deck reference viewports;
- a production build;
- CI that runs the same commands.

Tests should prove behavior and boundaries, not implementation trivia.

### Privacy and Security

Never commit:

- real Calendar or Reminder records;
- names, addresses, contacts, meeting details, recovery information, or household information;
- `.env` files or secrets;
- Tailscale hostnames, keys, or tailnet identifiers;
- exported personal snapshots;
- database files;
- production logs.

Use obviously synthetic fixtures.

### Git Safety

- Work on a feature branch, not directly on `main`, unless the user explicitly directs otherwise.
- Do not force-push shared branches.
- Do not rewrite existing history.
- Do not delete or replace project philosophy and architecture documents to make an implementation easier.
- Keep commits coherent and use the commit conventions in `CONTRIBUTING.md`.
- Do not mix broad formatting or dependency upgrades into a feature change.

## Decision Policy

Agents may make ordinary implementation decisions inside the current slice, including file organization, small library selection, and test structure.

Stop and ask before:

- changing the architecture or data-ownership model;
- adding a database, cloud service, authentication system, or runtime dependency not required by the slice;
- changing the product vocabulary or Board capacity limits;
- adding a new route, endpoint, application, package, integration, or persistent store;
- weakening a proof test or exit criterion;
- exposing personal data outside the local environment;
- beginning work from a later roadmap phase.

## Completion Report

At the end of a coding task, report:

1. what was built;
2. the exact commands used to validate it;
3. which tests passed;
4. any deliberate deviations from the requested design;
5. the files changed;
6. what remains deferred;
7. the branch and commit state.

Do not claim completion while tests are failing, the documented run commands are unverified, or deferred work has been started.
