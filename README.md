# Deskboard

**Remember. Return. Begin.**

Deskboard is a quiet, local-first attention surface for the things that matter but are easy to lose inside conventional calendars, task managers, notifications, and general-purpose computers.

It is not intended to replace Apple Calendar, Apple Reminders, Notes, Home Assistant, or other durable systems. Those remain the sources of truth. Deskboard will begin as a read-only interpretation layer that gathers a deliberately small amount of information, adds context such as elapsed time and project relationships, and presents it as a calm, persistent board.

## What we are building

The first version is a single-view, touch-friendly web application designed for two existing devices:

- an iPad Pro used as the primary desk display;
- a Steam Deck used as a secondary 16:10 test and interaction surface.

The initial board will emphasize:

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

The repository will be developed in bounded vertical slices. The sequence and exit criteria are documented in [ROADMAP.md](ROADMAP.md), while ownership and synchronization boundaries are documented in [ARCHITECTURE.md](ARCHITECTURE.md).

## Current status

**Phase 0: repository and product contract.**

No production application exists yet. The first implementation slice will establish a fixture-backed board, a small typed API contract, responsive layouts for iPad and Steam Deck, automated tests, and continuous integration. It will not connect to Apple, store personal data, or provide write actions.

## Scope discipline

Deskboard should earn complexity through use. Before contributing or directing a coding agent, read:

- [MANIFESTO.md](MANIFESTO.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [ROADMAP.md](ROADMAP.md)
- [AGENTS.md](AGENTS.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SECURITY.md](SECURITY.md)

The guiding implementation rule is simple:

> Build the smallest complete slice that proves a product assumption, then stop and evaluate it before expanding the system.
