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

**Status:** accepted and merged in PR #24.

**Design and operation:** [docs/private-homelab-deployment.md](docs/private-homelab-deployment.md)

Accepted:

- pinned non-root production images built from the committed lockfile;
- one internal-only Core API and one route-allowlisted private web proxy;
- numeric-loopback host publication for the proxy only;
- Tailscale Serve as the sole private HTTPS ingress with no Funnel;
- one persistent SQLite volume;
- one tracked-byte SSH bootstrap and Dockge-compatible root Compose stack;
- API-only file-mounted bearer secret and signed-Bridge provisioning inbox;
- strict private `.ts.net` Bridge-origin policy;
- container restart/recreate persistence and host-reboot restart policy;
- real private remote source/status delivery;
- exact uncertain-response retry through proxy outage and Bridge relaunch;
- private iPad and Steam Deck agreement, refresh, layout, and calmness proof.

The owner confirmed that both devices displayed the same recognizable Board without document-level overflow. Final device-time freshness was truthfully stale: Calendar had exceeded the manual 15-minute interval, and one selected Reminder source remained capped and blocked.

Phase 3D deliberately retains:

- explicit manual `Sync Now` as the only Bridge trigger;
- no supported authenticated same-Mac rollback after bearer rotation;
- no backup/restore automation;
- no Apple write behavior.

---

## Phase 3E — Unattended Read-Only Bridge and Selected-Source Completeness

**Status:** review implementation active under issue [#25](https://github.com/kasselvania/deskboard/issues/25); private 24-hour acceptance remains open.

**Question:** Can the accepted private read path remain normally current while the user is logged in, recover honestly from sleep/network/permission failures, and avoid a permanently stale selected Reminder scope without weakening completeness?

### Scope

- content-free measurement and an explicit bounded decision for the known capped Reminder source;
- owner-approved signed Bridge startup at login;
- one energy-conscious repeating scheduler through the existing Bridge process;
- manual/background/wake triggers coalesced through the accepted exact outbox path;
- no overlapping sync or revision reuse;
- truthful behavior during sleep, wake, network loss, permission loss, scheduler deferral, and login-item disablement;
- content-free local controls and troubleshooting;
- at least 24 hours of private deployed proof including sleep/wake and temporary network loss;
- iPad and Steam Deck agreement after recovery.

### Required source-completeness decision

The selected capped Reminder source must result in exactly one of:

1. a measured finite operational cap/envelope increase that preserves whole-list v1 authority and fits safely;
2. deliberate owner deselection when the source is not needed;
3. a stop for separate source-contract review when complete v1 delivery cannot fit safely.

Do not silently filter records, page an unversioned scope, or call partial data complete.

### Implemented checkpoint

- outcome A measured 945 records and a 280,671-byte complete candidate;
- retained-record cap increased from 500 to 1,000; envelope, Core, and proxy limits stayed unchanged;
- the owner-invoked same-revision replacement applied privately and cleared `blockedTruncated`;
- the signed main application registers through `SMAppService.mainApp` under **Open at Login**;
- one 600-second scheduler with 120-second tolerance and background QoS delegates to the accepted coordinator;
- manual, scheduled, and wake requests coalesce without overlap;
- two successive signed Release installations preserved exact private state, and one no-window scheduled run completed content-free.

Controlled login/restart, owner disablement through System Settings, and the 24-hour sleep/wake/outage/iPad/Steam Deck acceptance remain gates, not completed claims.

### Boundaries

- no root daemon or unmanaged LaunchAgent installation;
- no backup/restore automation;
- no week-long recovery soak yet;
- no Board, source, or status contract change without separate review;
- no notifications, source-management UI, public ingress, or Apple writes;
- no new semantic feature.

---

## Phase 3F — Backup/Restore and Read-Only Soak

**Status:** planned; blocked on accepted Phase 3E.

**Question:** Can the unattended private read path recover its Core state and remain trustworthy through a longer real-use period?

Intended scope:

- source-controlled database backup using the accepted Node/SQLite runtime boundary;
- owner-only retention and secret-safe storage policy;
- exercised restore into a clean deployment;
- proof that source/status revisions, Board behavior, and bootstrap remain coherent after restore;
- one-week read-only soak on iPad and Steam Deck;
- operational documentation based on observed failures;
- a deliberate product review of what deserves space, which reasons help, and what is repeatedly ignored.

No Apple write action belongs in Phase 3F.

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
