# Coding Agent Instructions

Deskboard is intentionally staged. Coding agents must complete the requested slice, prove it, document it, and stop.

## Read before changing anything

1. `README.md`
2. `MANIFESTO.md`
3. `ARCHITECTURE.md`
4. `ROADMAP.md`
5. `docs/apple-eventkit-discovery.md`
6. `docs/apple-source-contract-v1.md`
7. `docs/apple-source-mirror.md`
8. `docs/apple-bridge-manual-delivery.md`
9. `docs/apple-bridge-status-v1.md`
10. `docs/mirror-backed-board.md`
11. `docs/private-homelab-deployment.md`
12. `CONTRIBUTING.md`
13. `SECURITY.md`
14. the active GitHub issue and every review comment

The active issue is authoritative for the current slice. Stop when a request conflicts with accepted contracts, source authority, privacy, or the active issue rather than silently broadening the project.

## Prime directive

> Build the smallest complete slice that proves the stated product or architectural assumption, then stop.

A complete slice includes behavior, tests, failure states, privacy evidence, documentation, and reproducible commands. It does not include speculative scaffolding for later work.

## Accepted phases

- Phase 1 fixture-backed Board — PR #3
- Phase 2A EventKit evidence — PR #7
- Phase 2B Apple source contract v1 — PR #11
- Phase 3A atomic Core mirror — PR #14
- Phase 3B signed authenticated manual Bridge — PR #18
- Phase 3C truthful mirror-backed Board — PR #21
- Phase 3D private homelab deployment and manual remote Board — PR #24

These are accepted infrastructure. Do not redesign them opportunistically.

## Current phase

The active target is **Phase 3E — Unattended Read-Only Bridge and Selected-Source Completeness**, defined by issue #25.

The question is:

> Can the accepted private read path remain normally current while the user is logged in, recover honestly from sleep/network/permission failures, and avoid a permanently stale selected Reminder scope without weakening source completeness?

The Phase 3D live result is accepted evidence:

- the private homelab deployment works;
- remote source/status delivery works;
- exact uncertain retry works;
- iPad and Steam Deck show the same recognizable, calm Board;
- Calendar becomes stale after 15 minutes without another manual sync;
- one selected Reminder source remains `blockedTruncated` under the finite production cap.

Phase 3E must address those last two operational facts without changing source meaning or hiding degraded state.

## Phase 3E order of work

Do not begin with a scheduler and ignore the permanently blocked source.

1. Complete the content-free selected-source completeness gate.
2. Stop for architecture review if one complete v1 snapshot cannot fit safely.
3. Only then implement owner-approved unattended read-only operation.
4. Prove login, scheduling, sleep/wake, outage, and device behavior.
5. Stop before backup/restore, longer soak, or Apple writes.

## Accepted source authority

### Apple source contract v1

Do not add, remove, rename, reinterpret, or silently filter a v1 field or scope.

- Apple Calendar and Apple Reminders own source facts.
- Reminder scope is one Bridge + one selected list + every accessible record in that list.
- Calendar scope is one Bridge + one selected Calendar + records overlapping the exact declared window.
- Only a strict, semantically valid, non-truncated snapshot authorizes absence.
- Complete empty snapshots are authoritative only inside their declared scopes.
- Ordering-coordinate collisions invalidate a candidate.
- Date-only, local-time, timezone-qualified, exact-instant, and all-day meanings remain distinct.
- Notes, URLs, locations, participants, account titles, recurrence grammar, and other excluded fields remain absent.

### Selected Reminder source completeness

The known capped source must produce one explicit outcome:

- a measured finite operational limit increase that preserves whole-list v1 authority and fits safely;
- deliberate owner deselection;
- or a stop for separate contract review.

Do not:

- filter completed or old records;
- filter future or undated records;
- split one v1 scope into unversioned pages;
- increase limits without measured count/size proof;
- call partial data complete;
- automatically deselect the source.

Content-free diagnostic output may contain only counts, current/proposed limits, encoded byte count, and fit yes/no.

## Accepted Core mirror

Do not weaken Phase 3A:

- revision scope is Bridge + entity + source container;
- same revision/same digest is idempotent;
- same revision/different digest is conflict;
- lower revision is stale;
- invalid or truncated candidates do not mutate or advance state;
- Reminder replacement is whole-scope;
- Calendar replacement is overlap-window only;
- destructive work and metadata commit atomically;
- out-of-window Calendar rows may remain stored but are not current candidates.

## Accepted Bridge delivery and outboxes

Do not duplicate or weaken Phase 3B/3C:

- the production Bridge remains signed, sandboxed, outbound-only, and read-only;
- bearer credential remains in Keychain and only in the Authorization header;
- Bridge identity, selections, permissions, revisions, history, origin, and pending bytes remain private;
- exact pending source and status envelopes are persisted before sending;
- uncertain delivery retries byte-equivalent bytes at the same revision;
- only `applied` and `unchangedDuplicate` acknowledge and clear pending state;
- source and status outboxes remain independent;
- no EventKit save or remove call may appear.

Every manual, scheduled, and wake-triggered run must use the existing coordinator semantics. Do not add another transport or synchronization implementation.

## Accepted private deployment

Do not weaken Phase 3D:

- SSH plus ordinary Docker Compose is the deployment control plane;
- Dockge observes the same stack files and is not an API dependency;
- Core has no host-published port;
- the private proxy binds only to numeric loopback;
- Tailscale Serve is the sole remote ingress;
- Funnel and public ingress remain absent;
- the private database remains in the persistent volume;
- secrets remain file-mounted and excluded from Git, logs, image layers, and proxy state;
- the deterministic bootstrap and strict `.ts.net` origin policy remain accepted;
- iPad and Steam Deck continue using the same `BoardSnapshot` v1.

Do not add another deployment path, VPN, TLS authority, account system, public cloud, or proxy.

## Allowed Phase 3E native shape

A narrow implementation may add:

- owner opt-in such as `Keep Board Current`;
- `SMAppService.mainApp` registration and status handling;
- a minimal menu-bar or background-capable native control surface when necessary;
- one injected scheduler boundary around `NSBackgroundActivityScheduler`;
- one coalescing trigger coordinator for manual, scheduled, and wake requests;
- local content-free background status;
- sleep/wake and connectivity observation sufficient to request one later sync opportunity;
- measured finite production-limit changes when the source-completeness gate permits them;
- tests and `docs/unattended-read-only-bridge.md`.

Do not create a root daemon or unmanaged LaunchAgent. Do not create a separate helper identity unless a concrete platform limitation is proved and reviewed.

## Startup and owner control

Unattended operation must be explicit, reversible, and understandable.

Requirements:

- owner turns it on;
- registration state is shown content-free;
- owner can turn it off;
- a disabled login item does not break manual Bridge launch;
- a normal System Settings link may be provided;
- startup preserves the existing bundle identity, sandbox, Keychain item, EventKit/TCC decisions, Bridge ID, selections, revisions, history, and pending bytes;
- no hidden installation in `~/Library/LaunchAgents`;
- no admin/root requirement.

## Scheduling guardrails

Use one energy-conscious repeating scheduler.

Requirements:

- document interval, tolerance, repeat behavior, quality of service, and deferral meaning;
- no overlapping synchronization;
- background and manual triggers coalesce;
- a wake trigger requests at most one additional run;
- no busy loop or exact wall-clock guarantee;
- scheduler deferral is allowed and must remain truthfully stale when needed;
- no aggressive transport retry loop;
- restored reachability is handled by a later scheduled, wake, or manual opportunity;
- quitting or disabling unattended operation stops future scheduling;
- `Sync Now` remains available.

Do not put scheduling metadata into Apple source contract v1 or Bridge status v1 without a separate reviewed need.

## Freshness and Board guardrails

Do not change Phase 3C Board semantics:

- latest accepted selected-source roster controls eligibility;
- blocked, retrying, missing, mismatched, unavailable, or old selected sources cannot appear fresh;
- last-good selected facts may remain visible with stale or unavailable freshness;
- no operational failure authorizes source deletion;
- `BoardSnapshot` v1 remains unchanged;
- at most three Today Tasks and two Next Commitments;
- no raw source provenance reaches clients;
- web client behavior remains unchanged.

Unattended scheduling may improve freshness. It must not redefine freshness to make the implementation appear successful.

## Privacy and evidence

Never commit, report, or transmit:

- real Calendar, Reminder, or Board content;
- source/list/calendar/account names;
- source, EventKit, Bridge, status, or record identifiers;
- source temporal values;
- tokens, Keychain values, origins, hostnames, tailnet data, private paths, or populated configuration;
- pending source or status bytes;
- production database rows, dumps, or backups;
- certificates, Team IDs, signer data, or designated-requirement text;
- screenshots, accessibility trees, OCR, DOM dumps, API bodies, or remote-debug output from real-data surfaces.

The owner may inspect the Board and Bridge privately. Agent-visible evidence uses only schema success, counts, masked ordinals, freshness/permission/result categories, revisions, safe intervals, and yes/no state-continuity conclusions.

## Required Phase 3E proof

At minimum:

### Source completeness

- content-free matched/retained/encoded-size diagnostic;
- explicit decision A, B, or C from issue #25;
- no silent filtering or contract drift;
- coherent converter, envelope, Core, proxy, and memory limits when changed;
- oversized input remains honestly truncated.

### Unit and synthetic

- login-item state mapping and owner opt-in/out;
- scheduler interval/tolerance/QoS/repeat/deferral;
- no overlapping sync;
- manual/background/wake coalescing;
- temporary network failure preserves exact pending bytes;
- app relaunch preserves scheduling state and accepted Bridge state;
- disabled login item leaves manual path intact;
- content-free failures;
- all accepted source/status outbox regressions;
- no Apple write call.

### Signed product

- owner-approved login registration;
- stable signing and state across a second build;
- real login/restart launch behavior;
- operation without leaving the full window open;
- owner disable and manual-launch behavior.

### Private deployment

Over at least 24 hours with one sleep/wake cycle and one temporary network outage:

- working sources normally stay within the documented freshness expectation while awake and connected;
- sleep/disconnection becomes stale honestly;
- recovery occurs without conflict or pending-byte loss;
- known capped source is complete or explicitly deselected;
- iPad and Steam Deck agree after recovery;
- Board remains recognizable and calm;
- ordinary scheduled runs need no owner action;
- manual `Sync Now` still works.

## Explicit non-goals

Do not add in Phase 3E:

- root daemon or unmanaged LaunchAgent;
- public ingress or Funnel;
- backup/restore automation;
- week-long recovery soak;
- database export through the web;
- web-client product changes;
- Board/source/status contract changes without review;
- source-management UI in the Board;
- notifications;
- automatic conflict reset;
- Apple writes or Reminder completion;
- Notes or metadata parsing;
- Home Assistant;
- Open Loops;
- Projects;
- sessions;
- timers;
- ranking;
- AI;
- a generic scheduler, job queue, service framework, telemetry platform, or new auth system.

Deferred means absent.

## Validation

Run every accepted Node, browser, probe, production Bridge, signed-product, deployment, source/status, mirror, and Board gate affected by the change.

Verify:

- Phase 2A evidence unchanged;
- Phase 2B source contract unchanged unless separate review authorizes a new version;
- Phase 3A replacement/rollback unchanged;
- Phase 3B authentication, permission, identity, revision, and exact source outbox unchanged;
- Phase 3C status/freshness/Board semantics unchanged;
- Phase 3D bootstrap/Tailscale/private-device path unchanged;
- no private artifact is tracked or reported;
- no backup/restore or Apple write path exists.

Do not modify GitHub Actions to disguise the account-level administrative non-start.

## Git safety

- begin from accepted current `main`;
- use a new Phase 3E feature branch;
- do not force-push or rewrite accepted history;
- do not change approved Phase 2A evidence bytes;
- do not reset Bridge identity, Keychain, TCC, selections, revisions, history, or pending state;
- keep commits coherent;
- open a draft PR containing `Closes #25`;
- leave the PR draft and unmerged for tech-lead review.

## Completion report

Report only content-free facts:

1. selected-source completeness diagnostic and decision;
2. final operational limits, when changed;
3. login-item architecture and owner controls;
4. scheduler and trigger-coalescing behavior;
5. sleep/wake/network/permission behavior;
6. exact outbox and state-continuity proof;
7. signed-product and login proof;
8. 24-hour iPad/Steam Deck private acceptance;
9. exact automated validation results;
10. accepted earlier-phase integrity;
11. files, commits, dependencies, and deviations;
12. work deferred to Phase 3F;
13. branch, push, draft PR, and clean-working-tree state.

Never include real source content, Board content, credentials, identifiers, private host information, database rows, pending bytes, screenshots, accessibility output, DOM output, signer data, or Team IDs.
