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
11. `CONTRIBUTING.md`
12. `SECURITY.md`
13. the active GitHub issue and all review comments

The active issue is authoritative for the current implementation slice. If the request conflicts with accepted contracts or guardrails, stop and explain the conflict rather than silently expanding the project.

## Prime directive

> Build the smallest complete slice that proves the stated product or architectural assumption, then stop.

A complete slice includes behavior, tests, failure states, privacy evidence, documentation, and reproducible commands. It does not include speculative scaffolding for later work.

## Accepted phases

- Phase 1 fixture Board — PR #3
- Phase 2A EventKit evidence — PR #7
- Phase 2B Apple source contract v1 — PR #11
- Phase 3A atomic Core mirror — PR #14
- Phase 3B signed authenticated manual Bridge — PR #18
- Phase 3C truthful local mirror-backed Board — PR #21

These are accepted infrastructure. Do not redesign them opportunistically.

## Current phase

The active target is **Phase 3D — Private Homelab Deployment and Manual Remote Board**, defined by issue #22.

The question is:

> Can the accepted manual real-data Board run privately from the Ubuntu/CasaOS homelab and serve the iPad and Steam Deck through one Tailscale HTTPS origin without changing source authority, retry identity, status honesty, or the Board contract?

Phase 3D is a deployment and manual remote-use slice. It is not background operation, backup/restore automation, source administration, or an Apple write path.

The active implementation includes the source-controlled Compose/proxy shape, explicit API container bind, strict Bridge `.ts.net` origin policy, synthetic persistence/migration proof, and private runbook. Do not describe Phase 3D as accepted until homelab, uncertain-retry, and both device gates are complete and reviewed.

## Allowed Phase 3D shape

Approximately:

```text
deploy/                              container and private-proxy configuration
docs/private-homelab-deployment.md   private topology and operations
native/apple-bridge/                 narrow private-origin policy update
apps/api/                            only deployment compatibility corrections
apps/web/                            existing production build, no new product feature
```

Ordinary implementation choices inside this boundary are allowed. Do not add a generic platform, scheduler, deployment framework, or account system.

## Accepted source authority

### Apple source contract

`AppleReminderSourceSnapshotV1` and `AppleCalendarSourceSnapshotV1` remain unchanged.

- Apple Calendar and Reminders own source facts.
- A Reminder snapshot is authoritative only for its exact Bridge/list scope.
- A Calendar snapshot is authoritative only for its exact Bridge/container/window overlap scope.
- Only strict, semantically valid, non-truncated snapshots authorize absence.
- Complete empty snapshots are authoritative only inside their declared scopes.
- Ordering-coordinate collisions invalidate a candidate.
- Date-only, local-time, timezone-qualified, and all-day meanings remain distinct.

### Core mirror

Phase 3A behavior is immutable in this slice:

- revision scope is Bridge + entity + source container;
- same revision/same digest is idempotent;
- same revision/different digest is conflict;
- lower revision is stale;
- invalid and truncated candidates do not mutate or advance state;
- Reminder replacement is whole-scope;
- Calendar replacement is overlap-window only;
- destructive work and scope metadata commit atomically;
- retained out-of-window Calendar rows are not current-window candidates.

### Bridge status and Board honesty

Phase 3C behavior is immutable in this slice:

- the latest accepted selected-source roster controls Board eligibility;
- deselection never deletes mirror rows;
- status and source pending envelopes remain independent and crash-safe;
- blocked, retrying, missing, mismatched, unavailable, or old selected sources cannot appear fresh;
- last-good selected facts may remain visible with stale or unavailable freshness;
- fixture mode remains the default outside complete mirror configuration;
- `BoardSnapshot` v1 and the web client remain unchanged;
- the Board exposes no raw source provenance.

## Phase 3D topology

The accepted Phase 3D target is:

```text
signed macOS Bridge
        │ explicit Sync Now
        │ authenticated HTTPS over Tailscale
        ▼
Tailscale Serve on the homelab host
        │ loopback proxy target
        ▼
private web/proxy container
        │ private container network
        ├── static production PWA
        └── Deskboard Core API
                │
                ▼
        private persistent SQLite volume
```

Rules:

- Tailscale Serve is the sole remote ingress.
- No Funnel or public ingress.
- The host-facing deployment port binds only to loopback.
- The API container port is not published to the host.
- The API may listen on the private container network.
- Apple credentials never leave the Mac.
- The bearer token remains the accepted one-Bridge authentication boundary.
- No second auth system, account service, TLS authority, VPN, or public cloud dependency.

## Container and deployment guardrails

Phase 3D may add a small reproducible Compose-based deployment.

Requirements:

- use a Node 24 runtime compatible with the lockfile and `node:sqlite`;
- install from `package-lock.json` with `npm ci`;
- build the existing API and web workspaces;
- run production builds, not Vite development servers;
- run non-root where practical;
- persist the mirror/status SQLite database in one private host volume;
- include content-free health checks;
- close gracefully and preserve the database;
- use explicit runtime configuration for Bridge ID, token, database path, Board mode, and Board time zone;
- keep secrets out of image layers, build arguments, compose YAML, committed environment files, logs, browser responses, and image metadata;
- provide only a publish-safe `.env.example` with placeholders;
- do not commit CasaOS exports containing private values.

A small API plus static web/private-proxy deployment is acceptable. Do not add Kubernetes, an ORM, a generic migration service, or a deployment platform abstraction.

## Private proxy rules

The deployed boundary may proxy only the accepted routes:

```text
GET  /health
GET  /v1/board
POST /v1/apple-source-snapshots
POST /v1/apple-bridge-status
```

Requirements:

- `/board` works directly and after refresh;
- `GET /v1/board` retains `Cache-Control: no-store`;
- hashed static assets may use bounded immutable caching;
- request-body limits are compatible with accepted Core limits;
- no request or response body logging;
- no token logging;
- no raw mirror, source, roster, or status read route;
- no directory listing or arbitrary file serving;
- fixed content-free errors only.

## Tailscale guardrails

Use the existing Tailscale installation on the homelab host.

- Discover the installed CLI’s current supported `tailscale serve` behavior locally.
- Do not commit the real hostname, tailnet name, device name, certificate, IP, or Serve state.
- Use placeholders in documentation.
- Do not enable Funnel.
- Prove the service is unreachable outside the tailnet and reachable from authenticated tailnet devices.
- Do not create a second certificate authority or manually manage TLS certificates.

## Bridge destination policy

Preserve numeric-loopback HTTP origins for accepted local development and tests.

Phase 3D may add one narrow remote origin class:

- `https` only;
- exact origin, no user info, query, fragment, or preconfigured path;
- default HTTPS port unless a demonstrated Tailscale requirement says otherwise;
- hostname must be a valid `.ts.net` name;
- normal system TLS validation;
- redirects rejected;
- raw LAN IPs, raw tailnet IPs, arbitrary public hosts, ordinary DNS hosts, and remote plain HTTP rejected.

The Bridge continues to append only:

```text
/v1/apple-source-snapshots
/v1/apple-bridge-status
```

Changing the destination must not change Bridge ID, Keychain credential, selections, TCC grants, source revisions, status revisions, or exact pending envelope bytes.

Do not add certificate pinning, custom trust roots, proxy credentials, OAuth, or a general destination framework.

## Manual synchronization only

Phase 3D retains one explicit **Sync Now** action.

Do not add:

- a timer;
- daemon;
- launch item;
- menu-bar agent;
- watcher;
- notification;
- background task;
- automatic retry loop beyond the existing explicit next attempt.

Required remote proof:

- existing identity and revision streams continue at the private origin;
- source and status deliveries apply or duplicate idempotently;
- one controlled source change produces a newer accepted revision;
- unreachable transport preserves exact pending source/status bytes;
- restored reachability retries byte-equivalent bytes without rereading under the uncertain revision;
- source freshness and Board honesty remain unchanged.

## Device acceptance

The iPad and Steam Deck must privately load the same deployed Board.

Agent-visible evidence is limited to:

- device class;
- private origin reachable yes/no;
- Board schema valid yes/no;
- Board version agreement yes/no;
- vertical overflow yes/no;
- Calendar and Reminders freshness categories;
- recognizable yes/no;
- calm yes/no;
- no private content shared yes/no.

Do not request or inspect real Board screenshots, accessibility trees, OCR, DOM dumps, API bodies, remote-debug output, source-selection UI, mirror rows, or pending envelopes.

The owner may inspect the real Board privately.

## Privacy and security

Never commit, report, or transmit:

- real Calendar or Reminder content;
- real Board titles or text;
- source/list/calendar/account names;
- EventKit, source, record, Bridge, or status identifiers;
- source temporal values;
- bearer tokens, Keychain values, `.env` files, or certificates;
- Tailscale hostname, tailnet, device name, keys, IPs, or Serve configuration;
- production databases, dumps, journals, backups, or host paths;
- pending source or status envelopes;
- screenshots, accessibility trees, OCR, DOM dumps, request bodies, or response bodies containing real data.

Fixtures and automated deployment tests use synthetic values only.

Logs must remain content-free. Do not enable proxy or application logging that records request headers, query strings, bodies, Board responses, source coordinates, or tokens.

## Explicit non-goals

Do not add in Phase 3D:

- public ingress or Funnel;
- arbitrary LAN/public Bridge destinations;
- background scheduling or automatic delivery;
- backup/restore automation;
- source-management UI;
- Board contract changes;
- web-client product changes;
- Apple source or Bridge status contract changes without architecture review;
- Apple writes or Reminder completion;
- automatic stale/conflict recovery;
- Notes or metadata parsing;
- Home Assistant;
- Open Loops;
- Projects;
- sessions;
- timers;
- ranking;
- AI;
- Kubernetes or a generic deployment/auth/persistence framework.

## Testing requirements

Phase 3D is not complete without:

- every accepted Node, browser, Bridge, probe, source/status, mirror, and Board test remaining green;
- clean production image builds from the lockfile;
- container health proof;
- API not host-published;
- web/private proxy bound only to host loopback;
- direct `/board` and refresh behavior;
- proxy limits compatible with both ingestion routes;
- synthetic source/status idempotency through the proxy;
- database persistence through restart/recreate;
- migration proof against a synthetic existing Phase 3C database;
- no secret in image history or configuration;
- no database in an image layer;
- graceful shutdown/reopen;
- strict Bridge origin-policy tests;
- signed Bridge build and entitlement proof;
- content-free manual remote sync and device acceptance.

Do not alter GitHub Actions to hide the account-level administrative non-start.

## Git safety

- Begin from current accepted `main`.
- Work on a new Phase 3D feature branch.
- Do not force-push or rewrite accepted history.
- Do not modify approved Phase 2A evidence bytes.
- Do not change accepted Phase 2B, 3A, 3B, or 3C contracts and semantics without stopping for review.
- Do not commit secrets, databases, hostnames, or local deployment state.
- Keep commits coherent and follow `CONTRIBUTING.md`.
- Open a draft PR linked with `Closes #22` and stop for review.

## Decision policy

Agents may choose narrow file names, container layout, private proxy configuration, internal container ports, health-check structure, and test organization within issue #22.

Stop before:

- changing source authority or contract versions;
- changing Board eligibility, capacity, freshness, or client behavior;
- adding a dependency not required by issue #22;
- exposing the API directly;
- enabling public ingress;
- accepting arbitrary remote Bridge origins;
- adding background operation or backup automation;
- resetting Bridge identity, Keychain, TCC, revisions, or pending state;
- exposing private data;
- beginning Phase 3E or Apple write work.

## Completion report

Report only content-free facts:

1. container and proxy topology;
2. runtime configuration and secret-injection boundary;
3. persistent database and migration/restart behavior;
4. Tailscale Serve boundary without real host/tailnet values;
5. Bridge origin policy and identity/revision preservation;
6. remote source/status retry proof;
7. iPad and Steam Deck acceptance summary;
8. exact automated and native validation results;
9. accepted earlier-phase integrity;
10. files, commits, dependencies, and deliberate deviations;
11. everything deferred to Phase 3E;
12. branch, push, draft PR, and clean-working-tree state.

Never include real source content, Board content, credentials, identifiers, private host information, database rows, pending bytes, screenshots, accessibility output, DOM output, signer data, or Team IDs.
