# Deskboard

**Remember. Return. Begin.**

Deskboard is a quiet, local-first attention surface for the things that matter but are easy to lose inside conventional calendars, task managers, notifications, and general-purpose computers.

It is not intended to replace Apple Calendar, Apple Reminders, Notes, Home Assistant, or other durable systems. Those remain the sources of truth. Deskboard begins as a read-only interpretation layer that gathers a deliberately small amount of information, adds context such as elapsed time and project relationships, and presents it as a calm, persistent board.

## What we are building

The first version is a single-view, touch-friendly web application designed for two existing devices:

- an iPad Pro used as the primary desk display;
- a Steam Deck used as a secondary 16:10 test and interaction surface.

The initial board emphasizes:

- a small selection of reminders that matter today;
- the next meaningful calendar commitments;
- generous whitespace and clear reasons for why an item is visible;
- an optional daily sideways prompt, inspired by Oblique Strategies;
- a display that feels like an appliance rather than a general-purpose website.

The first connected release is strictly one-way:

```text
Apple Calendar + Apple Reminders
              ↓
       macOS EventKit bridge
              ↓
        Deskboard Core
              ↓
      iPad + Steam Deck
```

Only after this read path is reliable will Deskboard add carefully bounded interactions such as completing a Reminder, recording engagement with an Open Loop, or starting and stopping a lightweight session timer.

## Product direction

Deskboard is built around a few durable ideas:

- **Attention is scarce.** The system may know a great deal, but the board should show very little.
- **Existing tools keep ownership.** Calendar events remain Calendar events; concrete tasks remain Reminders.
- **Elapsed time is context, not judgment.** Time since an activity or project last moved can help invite a return without manufacturing guilt.
- **The board is not a backlog.** It is a curated field of attention.
- **Returning counts.** A five-minute re-entry into a neglected project or creative practice is meaningful.
- **Hardware is replaceable.** The same system should eventually support ordinary browsers, Android devices, E-Ink displays, and low-power custom clients.

Read the full philosophy in [MANIFESTO.md](MANIFESTO.md).

## Planned technical shape

The current intended architecture is intentionally modest:

- **React + TypeScript + Vite** for the responsive PWA;
- **Fastify + TypeScript** for the Deskboard Core API;
- **SQLite** for the accepted Apple source mirror and later Deskboard-owned state;
- a small **Swift/SwiftUI macOS bridge using EventKit** for Apple Calendar and Reminders;
- **Tailscale** later, for private access to the Ubuntu homelab without a public cloud dependency.

The repository is developed in bounded vertical slices. The sequence and exit criteria are documented in [ROADMAP.md](ROADMAP.md), while ownership and synchronization boundaries are documented in [ARCHITECTURE.md](ARCHITECTURE.md).

## Current status

**Phase 1 — Fixture-Backed Board: accepted and merged.**

The repository contains the complete synthetic presentation spine: runtime-validated fixtures, a two-route Fastify API, a single-route React Board, validated display caching, responsive iPad and Steam Deck layouts, and automated contract, API, component, accessibility, and browser proof tests.

The Board has also been reached from the physical iPad over the local network. Phase 1 was accepted from the complete local Node 24 quality gate and device proof. The hosted GitHub Actions job does not currently execute repository steps because of the account billing/spending restriction; the workflow remains unchanged and should be rerun after that administrative issue is resolved.

**Phase 2A — EventKit Discovery Evidence: accepted and merged in PR [#7](https://github.com/kasselvania/deskboard/pull/7).**

Phase 2A established the read-only local probe, empirical field inventory, owner-approved sanitized evidence set, deterministic bounded Calendar reads, inspection-scope invalidation, and executable fixture evidence.

**Phase 2B — Apple Source Contract and Reconciliation Semantics: accepted and merged in PR [#11](https://github.com/kasselvania/deskboard/pull/11).**

Phase 2B defines the strict versioned Reminder and Calendar source snapshots, cross-language validation, exact Calendar instant semantics, deterministic collision handling, truncation and authority rules, and the minimum privacy-preserving field set in [docs/apple-source-contract-v1.md](docs/apple-source-contract-v1.md).

**Phase 3A — Atomic Core Apple Source Mirror: accepted and merged in PR [#14](https://github.com/kasselvania/deskboard/pull/14).**

Phase 3A provides the isolated SQLite-backed Core mirror, ordered strict migrations, validation-before-mutation, source-scoped revisions and normalized digests, transactional Reminder and Calendar replacement, out-of-window Calendar retention, idempotency, rollback proof, and close/reopen persistence. Its accepted behavior is documented in [docs/apple-source-mirror.md](docs/apple-source-mirror.md).

**Phase 3B — Authenticated Manual Bridge Delivery: accepted and merged in PR [#18](https://github.com/kasselvania/deskboard/pull/18).**

Phase 3B provides one signed, sandboxed, read-only macOS Bridge; strict EventKit-to-v1 conversion; independent Calendar and Reminders permissions; crash-safe source-scoped revisions and exact pending-envelope retries; Keychain credentials; numeric-loopback-only delivery; and one authenticated Core ingestion route. The installed Apple Development-signed product proved stable permissions across rebuilds and manual loopback delivery without adding a background process, remote topology, Board integration, or Apple writes. Its accepted setup and reliability boundary are documented in [docs/apple-bridge-manual-delivery.md](docs/apple-bridge-manual-delivery.md).

**Phase 3C — Truthful Local Mirror-Backed Board: active under issue [#19](https://github.com/kasselvania/deskboard/issues/19).**

Phase 3C is intentionally limited to the same Mac and explicit manual synchronization. It adds a strict content-free Bridge status boundary so Core knows which sources are selected, blocked, retrying, missing, or unavailable; then it composes the unchanged Board contract from selected last-good mirror facts with honest freshness. Fixture mode remains the default. Homelab deployment, Tailscale, background scheduling, backup/restore, Board source management, and every Apple write path remain blocked.

**Remote deployment and background operation: not begun.** No private remote topology, automatic Bridge schedule, production homelab deployment, or Apple write action exists.

The discovery design is in [docs/apple-source-mapping-v0.1.md](docs/apple-source-mapping-v0.1.md), the accepted empirical findings are in [docs/apple-eventkit-discovery.md](docs/apple-eventkit-discovery.md), the accepted source contract is in [docs/apple-source-contract-v1.md](docs/apple-source-contract-v1.md), the accepted Core mirror is documented in [docs/apple-source-mirror.md](docs/apple-source-mirror.md), and the accepted manual-delivery path is documented in [docs/apple-bridge-manual-delivery.md](docs/apple-bridge-manual-delivery.md).

## Phase 1 development

### Prerequisites

- Node.js 24 LTS (the repository pins the major in `.nvmrc` and `package.json`)
- npm, included with Node.js

Install exactly the committed dependency graph:

```bash
nvm use
npm ci
npx playwright install chromium webkit
```

### Run the fixture Board

Start the API and web development server together:

```bash
npm run dev
```

Open [http://localhost:5173/board](http://localhost:5173/board). Vite proxies `/health` and `/v1/board` to the API on `127.0.0.1:3001`; the API also accepts a `PORT` environment variable when it is run independently.

The committed JSON fixtures remain deterministic contract specimens. For normal development, the API materializes the default specimen against the current clock so its generated time, source freshness, Today date, and following commitments stay coherent.

The web development server listens on the local network. Another trusted device on the same network can open:

```text
http://<development-machine-LAN-address>:5173/board
```

This is a fixture-only development server. It is not configured or intended for public exposure.

### Validate the repository

```bash
npm run lint
npm run typecheck
npm run test
npm run test:browser
npm run build
npm run check
```

`npm run check` is the complete local and CI Node gate. Browser tests exercise WebKit at `1366 × 1024`, Chromium at `1280 × 800`, and a `768 × 1024` portrait sanity viewport. The iPad and Steam Deck runs write screenshot artifacts under `test-results/playwright/`; CI uploads that directory and the Playwright report even after a browser-test failure.

Native validation commands for the accepted EventKit probe and production Bridge are documented in their respective READMEs and Apple integration documents.

### Repository structure

```text
apps/api/                         Fastify API, fixture Board, Apple mirror, and optional ingestion
apps/web/                         React/Vite Board and component tests
packages/contracts/               Board and Apple runtime contracts
fixtures/board/                   Publish-safe Board fixtures
fixtures/eventkit/                Owner-approved sanitized discovery evidence
fixtures/apple-source-contract/   Strict cross-language source-contract fixtures
native/apple-bridge/              Signed sandboxed production Bridge and synthetic tests
tools/apple-eventkit-probe/       Contained native EventKit discovery probe
tests/browser/                    Playwright viewport proofs
.github/workflows/                The complete CI quality gate
```

## Scope discipline

Deskboard should earn complexity through use. Before contributing or directing a coding agent, read:

- [MANIFESTO.md](MANIFESTO.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ROADMAP.md](ROADMAP.md)
- [docs/apple-source-mapping-v0.1.md](docs/apple-source-mapping-v0.1.md)
- [docs/apple-eventkit-discovery.md](docs/apple-eventkit-discovery.md)
- [docs/apple-source-contract-v1.md](docs/apple-source-contract-v1.md)
- [docs/apple-source-mirror.md](docs/apple-source-mirror.md)
- [docs/apple-bridge-manual-delivery.md](docs/apple-bridge-manual-delivery.md)
- [AGENTS.md](AGENTS.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)
- the active GitHub issue and its review context

The guiding implementation rule is simple:

> Build the smallest complete slice that proves a product assumption, then stop and evaluate it before expanding the system.
