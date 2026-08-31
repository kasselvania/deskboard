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
private Tailscale HTTPS origin
              ↓
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
- **Phase 3D — Private Homelab Deployment and Manual Remote Board:** accepted and merged in PR [#24](https://github.com/kasselvania/deskboard/pull/24).
- **Phase 3E — Unattended Read-Only Bridge and Selected-Source Completeness:** active under issue [#25](https://github.com/kasselvania/deskboard/issues/25).

Phase 3D proved the complete manual private path. One tracked-byte SSH bootstrap installs the Dockge-compatible Compose stack, keeps Core off the host network, exposes only a numeric-loopback proxy through private Tailscale Serve, rotates and provisions one bearer credential without exposing it, and preserves Bridge identity, selections, permissions, revisions, history, and exact pending envelopes. Real remote delivery, uncertain byte-equivalent retry, and private iPad/Steam Deck use all passed. Both devices displayed the same recognizable, calm Board without document-level overflow.

Phase 3E now has a review implementation. Its content-free diagnostic measured 945 whole-list Reminder records and a 280,671-byte complete envelope, authorizing outcome A: only the Reminder retained-record cap increased from 500 to 1,000. The Calendar cap remains 500, while the 768 KiB envelope and 1 MiB Core/proxy limits remain unchanged. The owner-invoked same-revision replacement released the accepted truncated pending envelope and applied the complete source without contract drift.

The signed menu-bar Bridge now uses `SMAppService.mainApp` for explicit **Keep Board Current** startup and one `NSBackgroundActivityScheduler` boundary for scheduled work. Manual, scheduled, and wake triggers coalesce through the accepted coordinator and exact outboxes. Initial signed registration and a scheduled run passed without a full window. Controlled login/restart proof and the private 24-hour sleep/wake/outage/device acceptance remain open, so Phase 3E is not yet accepted. Backup/restore and a longer read-only soak remain Phase 3F. Every Apple write remains deferred.

The hosted GitHub Actions job currently does not execute repository steps because of an account billing/spending restriction. The workflow remains unchanged; local locked Node, native, signed-product, browser, deployment, and private acceptance gates are the current code evidence.

## Contracts and design documents

- [ARCHITECTURE.md](ARCHITECTURE.md) — ownership, topology, and component boundaries
- [ROADMAP.md](ROADMAP.md) — accepted and active slices
- [docs/apple-eventkit-discovery.md](docs/apple-eventkit-discovery.md) — empirical EventKit findings
- [docs/apple-source-contract-v1.md](docs/apple-source-contract-v1.md) — strict Calendar and Reminder source documents
- [docs/apple-source-mirror.md](docs/apple-source-mirror.md) — atomic Core persistence and replacement semantics
- [docs/apple-bridge-manual-delivery.md](docs/apple-bridge-manual-delivery.md) — signed Bridge, authentication, and exact retry
- [docs/apple-bridge-status-v1.md](docs/apple-bridge-status-v1.md) — content-free selection and source-health status
- [docs/mirror-backed-board.md](docs/mirror-backed-board.md) — real Board eligibility, freshness, reasons, and privacy proof
- [docs/private-homelab-deployment.md](docs/private-homelab-deployment.md) — accepted private topology, bootstrap, and operation
- [docs/unattended-read-only-bridge.md](docs/unattended-read-only-bridge.md) — Phase 3E source completeness, startup, scheduling, and acceptance
- issue [#25](https://github.com/kasselvania/deskboard/issues/25) — active Phase 3E implementation and proof contract

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

Native validation and private operational procedures are documented in the Apple integration and deployment documents. Never use real Board screenshots, accessibility output, DOM dumps, API payloads, mirror rows, or pending envelopes as agent-visible proof.

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
deploy/                            Private production containers, bootstrap, proxy, and proof
tools/apple-eventkit-probe/       Contained EventKit discovery probe
tests/browser/                    iPad, Steam Deck, and portrait proofs
.github/workflows/                Complete quality gate
```

## Contribution rule

Before changing code, read [AGENTS.md](AGENTS.md), [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the active GitHub issue.

> Build the smallest complete slice that proves the current assumption, then stop and evaluate it before expanding the system.
