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

The first connected release will be strictly one-way:

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
- **SQLite** when persistent Deskboard-owned state is introduced;
- a small **Swift/SwiftUI macOS bridge using EventKit** for Apple Calendar and Reminders;
- **Tailscale** for private access to the Ubuntu homelab without a public cloud dependency.

The repository is developed in bounded vertical slices. The sequence and exit criteria are documented in [ROADMAP.md](ROADMAP.md), while ownership and synchronization boundaries are documented in [ARCHITECTURE.md](ARCHITECTURE.md).

## Current status

**Phase 1 — Fixture-Backed Board: accepted and merged.**

The repository contains the complete synthetic presentation spine: runtime-validated fixtures, a two-route Fastify API, a single-route React Board, validated display caching, responsive iPad and Steam Deck layouts, and automated contract, API, component, accessibility, and browser proof tests.

The Board has also been reached from the physical iPad over the local network. Phase 1 was accepted from the complete local Node 24 quality gate and device proof. The hosted GitHub Actions job did not execute repository steps because of the account billing/spending restriction; the workflow itself remains unchanged and should be rerun after that administrative issue is resolved.

**Phase 2A — EventKit Discovery Evidence: accepted and merged in PR [#7](https://github.com/kasselvania/deskboard/pull/7).**

Phase 2A established the read-only local probe, empirical field inventory, owner-approved sanitized evidence set, deterministic bounded Calendar reads, inspection-scope invalidation, and executable fixture evidence.

**Phase 2B — Apple Source Contract and Reconciliation Semantics: accepted and merged in PR [#11](https://github.com/kasselvania/deskboard/pull/11).**

Phase 2B defines the strict versioned Reminder and Calendar source snapshots, cross-language validation, exact Calendar instant semantics, deterministic collision handling, truncation and authority rules, and the minimum privacy-preserving field set in [docs/apple-source-contract-v1.md](docs/apple-source-contract-v1.md).

**Phase 3A — Atomic Core Apple Source Mirror: active under issue [#12](https://github.com/kasselvania/deskboard/issues/12).**

Phase 3A is intentionally limited to a SQLite-backed Core persistence boundary that proves transactional Reminder scope replacement, Calendar overlap-window replacement, revision/idempotency behavior, and rollback safety with synthetic source-contract fixtures. It does not add a network ingestion endpoint, production Bridge conversion, Board integration, deployment, or any Apple write path.

The active feature slice implements that internal mirror with ordered strict migrations, validation-before-mutation, normalized digests, explicit non-applied results, narrow reads, and close/reopen proof. Its exact behavior and later-phase boundary are documented in [docs/apple-source-mirror.md](docs/apple-source-mirror.md). Phase 3A remains active until its draft pull request is reviewed and merged.

**Later Phase 3 connected work: not begun.** No Bridge-to-Core transport, production EventKit conversion, homelab deployment, real-data Board composition, background scheduling, or Apple write action exists.

The discovery design is in [docs/apple-source-mapping-v0.1.md](docs/apple-source-mapping-v0.1.md), the accepted empirical findings are in [docs/apple-eventkit-discovery.md](docs/apple-eventkit-discovery.md), the accepted source contract is in [docs/apple-source-contract-v1.md](docs/apple-source-contract-v1.md), and the active Core mirror design is in [docs/apple-source-mirror.md](docs/apple-source-mirror.md).

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

### Validate the slice

```bash
npm run lint
npm run typecheck
npm run test
npm run test:browser
npm run build
npm run check
```

`npm run check` is the complete local and CI gate. Browser tests exercise WebKit at `1366 × 1024`, Chromium at `1280 × 800`, and a `768 × 1024` portrait sanity viewport. The iPad and Steam Deck runs write screenshot artifacts under `test-results/playwright/`; CI uploads that directory and the Playwright report even after a browser-test failure.

### Repository structure

```text
apps/api/                         Fastify API, fixture Board, and Core tests
apps/web/                         React/Vite Board and component tests
packages/contracts/               Board and Apple source runtime contracts
fixtures/board/                   Publish-safe Board fixtures
fixtures/eventkit/                Owner-approved sanitized discovery evidence
fixtures/apple-source-contract/   Strict cross-language source-contract fixtures
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
- [AGENTS.md](AGENTS.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)

The guiding implementation rule is simple:

> Build the smallest complete slice that proves a product assumption, then stop and evaluate it before expanding the system.
