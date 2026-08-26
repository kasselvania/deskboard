# Deskboard

**Remember. Return. Begin.**

Deskboard is a quiet, local-first attention surface for things that matter but are easy to lose inside conventional calendars, task managers, notifications, and general-purpose computers.

It does not replace Apple Calendar or Apple Reminders. Those remain authoritative. Deskboard reads an explicitly selected, privacy-minimized subset, preserves source meaning, and composes a small persistent Board for an iPad Pro and Steam Deck.

## Product direction

Deskboard is built around a few durable ideas:

- **Attention is scarce.** The system may know a great deal, but the Board should show very little.
- **Existing tools keep ownership.** Calendar events remain Calendar events; ordinary tasks remain Reminders.
- **The Board is not a backlog.** It is a curated field of attention.
- **Freshness must be honest.** Missing, truncated, stale, or unavailable sources must never be silently presented as complete.
- **Privacy is architectural.** Real source data, credentials, databases, screenshots, accessibility trees, DOM dumps, and payloads do not enter Git or agent-visible evidence.
- **Complexity must be earned.** Every phase proves one bounded assumption and stops.

Read the full philosophy in [MANIFESTO.md](MANIFESTO.md).

## Accepted system shape

```text
Apple Calendar + Apple Reminders
              ↓ EventKit
signed, sandboxed macOS Bridge
              ↓ authenticated source + status envelopes
Deskboard Core / SQLite mirror
              ↓ BoardSnapshot v1
        iPad + Steam Deck
```

The read path is strictly one-way. Calendar and Reminders remain read-only.

## Current status

- **Phase 1 — Fixture-Backed Board:** accepted and merged in PR #3.
- **Phase 2A — EventKit Discovery Evidence:** accepted and merged in PR [#7](https://github.com/kasselvania/deskboard/pull/7).
- **Phase 2B — Apple Source Contract v1:** accepted and merged in PR [#11](https://github.com/kasselvania/deskboard/pull/11).
- **Phase 3A — Atomic Core Apple Source Mirror:** accepted and merged in PR [#14](https://github.com/kasselvania/deskboard/pull/14).
- **Phase 3B — Authenticated Manual Bridge Delivery:** accepted and merged in PR [#18](https://github.com/kasselvania/deskboard/pull/18).
- **Phase 3C — Truthful Local Mirror-Backed Board:** accepted and merged in PR [#21](https://github.com/kasselvania/deskboard/pull/21).
- **Phase 3D — Private Homelab Deployment and Manual Remote Board:** active under issue [#22](https://github.com/kasselvania/deskboard/issues/22).

Phase 3C established the first real-data Board without changing `BoardSnapshot` v1 or the web client. Core composes only from the latest accepted selected-source roster, keeps last-good facts without calling them fresh, and preserves the existing maximum of three Tasks and two Commitments. The owner privately confirmed the local Board was recognizable and calm using content-free evidence only.

The active Phase 3D implementation packages that accepted path as pinned production containers: a non-host-published Core API, one loopback-bound static web/private proxy, and one persistent SQLite volume. One deterministic SSH bootstrap installs the root Compose stack, configures private Tailscale Serve, rotates Core's file-mounted token, and asks the signed Bridge to import the same token plus a strict `.ts.net` origin without changing its operational state. Explicit **Sync Now** remains the only delivery trigger. Homelab, private remote-sync, and device acceptance are still required before Phase 3D can be accepted. Background scheduling, launch-at-login behavior, backup/restore automation, public ingress, source administration, and every Apple write remain deferred.

The hosted GitHub Actions job currently does not execute repository steps because of an account billing/spending restriction. The workflow remains unchanged; local locked Node, native, signed-product, browser, and private acceptance gates are the current code evidence.

## Contracts and design documents

- [ARCHITECTURE.md](ARCHITECTURE.md) — ownership, topology, and component boundaries
- [ROADMAP.md](ROADMAP.md) — accepted and active slices
- [docs/apple-eventkit-discovery.md](docs/apple-eventkit-discovery.md) — empirical EventKit findings
- [docs/apple-source-contract-v1.md](docs/apple-source-contract-v1.md) — strict Calendar and Reminder source documents
- [docs/apple-source-mirror.md](docs/apple-source-mirror.md) — atomic Core persistence and replacement semantics
- [docs/apple-bridge-manual-delivery.md](docs/apple-bridge-manual-delivery.md) — signed Bridge, authentication, and exact retry
- [docs/apple-bridge-status-v1.md](docs/apple-bridge-status-v1.md) — content-free selection and source-health status
- [docs/mirror-backed-board.md](docs/mirror-backed-board.md) — real Board eligibility, freshness, reasons, and privacy proof
- [docs/private-homelab-deployment.md](docs/private-homelab-deployment.md) — Phase 3D private topology, operation, and owner-only acceptance
- issue [#22](https://github.com/kasselvania/deskboard/issues/22) — active Phase 3D deployment contract

## Development prerequisites

- Node.js 24 LTS; the repository pins the major in `.nvmrc` and `package.json`
- npm from the selected Node installation
- Xcode for native Bridge and probe work
- Playwright browser engines for the full browser proof

Install the committed dependency graph:

```bash
nvm use
npm ci
npx playwright install chromium webkit
```

Run the default fixture-backed development Board:

```bash
npm run dev
```

Open:

```text
http://localhost:5173/board
```

The Vite development server proxies `/health` and `/v1/board` to the API on `127.0.0.1:3001`. Fixture mode remains the zero-configuration default.

Run the complete Node gate:

```bash
npm run check
```

Native validation and private manual procedures are documented in the Apple integration documents. Never use real Board screenshots, accessibility output, DOM dumps, API payloads, mirror rows, or pending envelopes as agent-visible proof.

## Repository structure

```text
apps/api/                         Fastify API, mirror, status, Board composition
apps/web/                         React/Vite Board
packages/contracts/               Board, Apple source, and Bridge status contracts
fixtures/board/                   Publish-safe Board fixtures
fixtures/eventkit/                Approved sanitized discovery evidence
fixtures/apple-source-contract/   Strict cross-language source fixtures
fixtures/apple-bridge-status/     Strict cross-language operational fixtures
native/apple-bridge/              Signed sandboxed production Bridge
deploy/                            Private production containers, proxy, and synthetic proof
tools/apple-eventkit-probe/       Contained EventKit discovery probe
tests/browser/                    iPad, Steam Deck, and portrait proofs
.github/workflows/                Complete quality gate
```

## Contribution rule

Before changing code, read [AGENTS.md](AGENTS.md), [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the active GitHub issue.

> Build the smallest complete slice that proves the current assumption, then stop and evaluate it before expanding the system.
