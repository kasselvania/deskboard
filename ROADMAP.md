# Deskboard Roadmap

Deskboard is developed as bounded vertical slices. Every slice proves one product or architectural assumption, includes explicit failure and privacy evidence, and stops before the next layer begins.

## Delivery rules

1. **One slice, one thesis.**
2. **Deferred means absent.** No speculative services, transports, schedulers, write paths, or abstractions.
3. **Source authority is preserved.** Apple owns Calendar and Reminder facts.
4. **Failure is represented honestly.** Missing, partial, stale, blocked, or unavailable information is never converted into deletion or freshness.
5. **Privacy precedes convenience.** Real source content, credentials, databases, screenshots, accessibility trees, DOM dumps, and payloads do not enter Git or agent-visible evidence.
6. **The previous slice remains usable.**
7. **Connected product slices require real use.** Stop long enough to learn from the Board before adding interactions.

---

## Phase 0 — Product and Repository Contract

**Status:** accepted and complete.

Established the Manifesto, architecture, roadmap, contribution rules, privacy policy, read-only Apple posture, and bounded-agent workflow.

---

## Phase 1 — Fixture-Backed Board

**Status:** accepted and merged in PR #3.

Proved the calm, non-scrolling `BoardSnapshot` v1 experience on iPad and Steam Deck with a fixture-backed Fastify API, React/Vite PWA, runtime contracts, loading/empty/stale/saved/unreachable states, deterministic capacity limits, accessibility checks, and browser proof.

Accepted limits remain:

- at most three Today Tasks;
- at most two Next Commitments;
- one optional Sideways prompt;
- no source management, settings, navigation, write action, or general dashboard behavior.

---

## Phase 2A — EventKit Discovery Evidence

**Status:** accepted and merged in PR #7.

Established separate Calendar and Reminders permissions, empty-by-default source selection, bounded deterministic reads, destructive sanitization, ignored private exports, an empirical field inventory, honest `not tested` cases, and the exact owner-approved twelve-fixture evidence hold.

No EventKit write behavior was introduced.

---

## Phase 2B — Apple Source Contract and Reconciliation Semantics

**Status:** accepted and merged in PR #11.

**Design:** [docs/apple-source-contract-v1.md](docs/apple-source-contract-v1.md)

Accepted separate strict Reminder and Calendar snapshot documents, cross-language validation, exact Calendar instants, civil date preservation, collision rejection, explicit truncation, complete empty scopes, and the minimum privacy-preserving field set.

> Unseen is absent only after a successful, strict, non-truncated snapshot covers the exact scope in which absence is claimed.

---

# Phase 3 — One-Way Apple Read Path

## Phase 3A — Atomic Core Apple Source Mirror

**Status:** accepted and merged in PR #14.

**Design:** [docs/apple-source-mirror.md](docs/apple-source-mirror.md)

Added the strict SQLite mirror, source-scoped operational revisions and digests, atomic Reminder whole-scope replacement, Calendar overlap-window replacement, out-of-window retention, duplicate/stale/conflict/truncation handling, rollback proof, migrations, and close/reopen persistence.

No transport or Board path existed in this slice.

---

## Phase 3B — Authenticated Manual Bridge Delivery

**Status:** accepted and merged in PR #18.

**Design:** [docs/apple-bridge-manual-delivery.md](docs/apple-bridge-manual-delivery.md)

Added the signed, sandboxed, read-only macOS Bridge; strict EventKit-to-v1 conversion; independent permissions and selections; Keychain bearer credential; one authenticated loopback source-ingestion route; source-scoped revisions; and exact pending-envelope retry across timeout, termination, and relaunch.

> Persist the exact envelope before sending. After an uncertain response, resend those byte-equivalent bytes at the same revision.

Only `applied` and `unchangedDuplicate` acknowledge and clear pending delivery.

---

## Phase 3C — Truthful Local Mirror-Backed Board

**Status:** accepted and merged in PR #21.

**Designs:**

- [docs/apple-bridge-status-v1.md](docs/apple-bridge-status-v1.md)
- [docs/mirror-backed-board.md](docs/mirror-backed-board.md)

Accepted:

- a separately versioned content-free Bridge status contract;
- the exact selected-source roster and independent permission categories;
- crash-safe status-envelope retry independent of source pending state;
- one authenticated loopback status route and transactional status persistence;
- explicit mirror-backed Board mode with a required IANA Board time zone;
- truthful `fresh`, `stale`, and `unavailable` derivation;
- deterministic Reminder-to-Today and Calendar-to-Next composition;
- opaque client IDs and semantic Board versions;
- unchanged `BoardSnapshot` v1, unchanged web client, and fixture mode as the default.

The owner privately confirmed that the real local Board was recognizable and calm. Agent-visible evidence remained content-free.

Central honesty rule:

> Compose only from the latest accepted selected-source roster, preserve last-good facts without calling them fresh, and never convert missing operational evidence into source deletion.

---

## Phase 3D — Private Homelab Deployment and Manual Remote Board

**Status:** active under issue [#22](https://github.com/kasselvania/deskboard/issues/22).

**Question:** Can the accepted manual real-data Board run privately from the Ubuntu/CasaOS homelab and serve the iPad and Steam Deck through one Tailscale HTTPS origin without changing source authority, retry identity, freshness honesty, or the Board contract?

### Scope

- reproducible container deployment of Core and the production web build;
- persistent private SQLite mirror/status volume;
- API kept off the host network;
- one loopback-bound web/private-proxy service;
- Tailscale Serve as the sole private HTTPS ingress;
- no Funnel or public ingress;
- a narrowly expanded Bridge origin policy for approved `.ts.net` HTTPS origins;
- explicit manual remote **Sync Now** only;
- iPad and Steam Deck private-device acceptance;
- restart/recreate persistence and unreachable/retry proof;
- publish-safe deployment documentation and content-free evidence.

### Boundaries

- no background Bridge schedule, daemon, launch item, menu-bar process, watcher, or notification;
- no backup/restore automation yet;
- no source-management UI;
- no Board, Apple source, or Bridge status contract change;
- no Apple writes;
- no public internet ingress;
- no new semantic feature.

### Exit criteria

- Core and Web run reproducibly on the private homelab;
- only the private Tailscale HTTPS origin provides remote ingress;
- the signed Bridge manually delivers source and status envelopes without changing identity or retry semantics;
- iPad and Steam Deck display the same truthful Board;
- restart/recreate preserves database and Board state;
- unreachable transport preserves exact pending bytes and last-good Core data;
- the owner confirms the deployed Board remains recognizable and calm;
- background operation, backup/restore automation, and Apple writes remain absent.

---

## Phase 3E — Background Read Path, Backup/Restore, and Soak

**Status:** planned; blocked on accepted Phase 3D.

**Question:** Can the accepted private deployment operate unattended and recoverably without making the read path noisy or unreliable?

Intended scope:

- narrowly bounded background Bridge scheduling after manual remote delivery is stable;
- explicit startup/restart behavior;
- source freshness during sleeping, disconnected, or unavailable Mac states;
- database backup and exercised restore;
- one-week read-only soak on iPad and Steam Deck;
- operational documentation based on observed failures.

No Apple write action belongs in Phase 3E.

A deliberate product pause follows: use Deskboard daily and record which facts deserve space, which reasons help, and what is repeatedly ignored.

---

## Phase 4 — One Reminder Round Trip

**Status:** blocked on an accepted, used, and reliable read-only Phase 3 path.

Add exactly one Apple mutation: complete an eligible ordinary Reminder with authenticated, idempotent, conflict-aware, auditable behavior and normal read synchronization as final confirmation.

No Reminder creation/editing/list movement and no Calendar writes.

---

## Phase 5 — First Open Loop

Test one manually chosen persistent practice with elapsed time, a preferred return window, one Board slot, and one `I Did This` action.

No streaks, missed-instance debt, productivity score, automatic cadence prescription, or AI ranking.

---

## Phase 6 — One Session Timer

Test one server-owned active session that can start on one client and stop on the other, survives reconnect, and creates a lightweight engagement record.

No billing, timesheets, surveillance, Pomodoro framework, or elaborate reporting.

---

## Later candidates — not scheduled

Possible bounded slices include active-project state, re-entry summaries, weather, carefully scoped home signals, audited Shortcuts or agents, Android/E-Ink profiles, and descriptive reflection. These are candidates, not commitments.

---

## Definition of done for every slice

A slice is not complete until:

- its local acceptance gates pass;
- hosted CI is reported honestly, including administrative non-starts;
- documentation describes implemented behavior;
- failure, empty, stale, and privacy states are proved;
- no secret or personal artifact is committed;
- new dependencies are justified by current requirements;
- the previous slice remains usable;
- deferred behavior remains absent;
- the repository can be cloned and validated from documented commands;
- the change is reviewable as one coherent thesis;
- the next slice has not been partially started.
