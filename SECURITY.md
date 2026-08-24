# Security and Privacy Policy

Deskboard is local-first software that processes personal Calendar, Reminder, project, household, and activity information. Privacy boundaries are part of the architecture, not a deployment afterthought.

## Supported code

Until versioned releases exist, only the current `main` branch is considered supported.

## Reporting a security issue

Do not open a public issue containing credentials, private source data, exploit details, host information, or identifying information.

Use a GitHub private security advisory when available or an established private channel. Include only:

- affected component and revision;
- sanitized reproduction steps;
- expected and observed behavior;
- likely impact;
- suggested mitigation;
- the minimum evidence required.

## Repository prohibitions

The repository must not contain:

- populated `.env` files or production secrets;
- access tokens, private keys, certificates, provisioning profiles, or Team IDs;
- real EventKit exports or source records;
- real Calendar, Reminder, Notes, household, contact, health, recovery, or work data;
- real Board screenshots, accessibility trees, OCR, DOM dumps, API payloads, or remote-debug output;
- real Bridge, source, record, account, or status identifiers;
- Tailscale hostnames, tailnet names, device names, IPs, keys, certificates, or Serve state;
- production SQLite databases, journals, dumps, backups, or host volume paths;
- pending source or Bridge-status envelopes;
- CasaOS exports containing private values;
- logs or screenshots containing personal or operational secrets.

Committed fixtures and automated deployment examples must be synthetic and publish-safe.

## Trust boundaries

- Apple Calendar owns Calendar records.
- Apple Reminders owns ordinary Reminder records.
- The signed macOS Bridge receives Apple permissions and sends only normalized, explicitly selected facts plus content-free operational status.
- Deskboard Core stores the strict read-only mirror, Bridge status, and composed Board state.
- Display clients receive only `BoardSnapshot` v1 fields.
- Clients and agents do not receive direct database, mirror, roster, or status access.
- Apple credentials do not leave the Mac.
- The bearer token appears only in Keychain/Core runtime configuration and the Authorization header.
- Public internet ingress is not required or accepted.

Any change to these boundaries requires explicit architecture and privacy review.

## Accepted Bridge and ingestion controls

- The production Bridge is Apple Development-signed, sandboxed, Hardened Runtime-enabled, outbound-only, and behaviorally read-only.
- Calendar and Reminders permissions and selections remain independent.
- The Bridge reads only fields admitted by Apple source contract v1.
- There is no EventKit save or remove call.
- Source and status envelopes are strictly validated and persisted exactly before delivery.
- An uncertain response retries byte-equivalent bytes at the same revision.
- Only `applied` and `unchangedDuplicate` acknowledge and clear pending state.
- The source and status outboxes are independent.
- The bearer credential is stored in macOS Keychain.
- Core authenticates before body parsing and binds the token to one expected opaque Bridge identity.
- Request limits, response parsing, and errors are finite and content-free.
- No source or status read route exists.

## Accepted mirror and Board controls

- Core mutates source scopes only after strict validation and inside one transaction.
- Truncated, invalid, stale, conflicting, or failed candidates preserve the previous good state.
- Calendar replacement is authoritative only in the accepted overlap window.
- The latest accepted Bridge status roster controls Board selection.
- Deselection removes a source from composition without deleting its mirror rows.
- Blocked, retrying, missing, revision-mismatched, unavailable, or old selected sources cannot appear fresh.
- Last-good selected facts may remain visible with stale or unavailable freshness.
- `BoardSnapshot` v1 exposes no Bridge ID, source-container ID, EventKit ID, mirror row, status document, token, or pending envelope.
- Board item IDs and versions are opaque and do not reveal raw provenance.
- Fixture mode remains the default; mirror mode requires explicit complete configuration and a valid IANA Board time zone.

## Phase 3D private deployment controls

Phase 3D deploys the already accepted manual read path. It does not add automatic synchronization or write behavior.

### Container boundary

- Build only from the committed lockfile and production source.
- Do not place secrets or databases in image layers or build arguments.
- Run containers as non-root where practical.
- Persist the private SQLite mirror/status database in one protected host volume.
- Do not publish the API container port to the host.
- Publish only the web/private-proxy service, bound to host loopback.
- Use content-free health checks.
- Proxy only the accepted health, Board, source-ingestion, and status-ingestion routes.
- Disable request/response-body logging, directory listing, and arbitrary file serving.
- Board responses remain `no-store`; static hashed assets may use bounded immutable caching.

### Tailscale boundary

- Tailscale Serve is the sole private HTTPS ingress.
- Tailscale Funnel and public ingress are forbidden.
- Real hostname, tailnet, device name, keys, IPs, certificates, and Serve state remain local and unreported.
- Do not introduce another VPN, certificate authority, reverse-proxy account system, or public cloud dependency.
- Prove the service is unreachable outside the tailnet and reachable from authenticated tailnet devices.

### Bridge destination boundary

The Bridge retains numeric-loopback HTTP for local development and may additionally accept only a strict private Tailscale origin:

- HTTPS scheme;
- exact `.ts.net` host;
- no credentials, query, fragment, or preconfigured path;
- normal system TLS validation;
- no redirects;
- no raw LAN IP, raw tailnet IP, arbitrary public host, ordinary remote hostname, or remote plain HTTP.

Changing destination must not change Bridge ID, Keychain credential, source/status revisions, selections, TCC grants, or exact pending bytes.

### Manual operation only

Phase 3D retains explicit **Sync Now**. It must not add a scheduler, daemon, launch item, watcher, menu-bar agent, notification, or background task.

Background operation and backup/restore automation are deferred to Phase 3E.

## Agent-visible evidence boundary

The owner may privately inspect real source-selection, deployment, and Board surfaces.

Agents and shared tooling may receive only purpose-built content-free evidence:

- schema success/failure;
- item counts;
- freshness and permission categories;
- applied/duplicate/stale/conflict/truncated result kinds;
- masked source ordinals;
- device reachability and Board-version agreement;
- vertical-overflow yes/no;
- recognizable/calm yes/no.

Do not use or transmit for real-data acceptance:

- screenshots;
- accessibility trees;
- OCR;
- DOM dumps;
- API request or response bodies;
- source or Board titles;
- source identifiers;
- mirror rows;
- status documents;
- pending envelopes;
- browser remote-debug content;
- real Tailscale or host information.

The prior private accessibility-inspection incident did not enter Git, but it establishes this hard process rule for every later real-data slice.

## Logging and diagnostics

Logs and errors may contain fixed result codes and minimum safe operational metadata only.

Never log:

- Authorization headers or tokens;
- source or status request bodies;
- Board response bodies;
- source coordinates or record identifiers;
- titles, temporal values, notes, locations, URLs, or participants;
- database rows;
- pending envelopes;
- private host, tailnet, or volume information.

Sensitive local diagnostics used for a private Apple or deployment investigation must be deleted when no longer needed and must not be attached to public issues or PRs.

## Dependency and implementation hygiene

- Add dependencies only for current issue requirements.
- Commit and review lockfiles.
- Validate every network, contract, and persistence boundary at runtime.
- Prefer explicit allowlists and least privilege.
- Treat cached Board data as sensitive even when non-authoritative.
- Do not add generic auth, deployment, persistence, scheduler, adapter, or command frameworks for imagined future work.
- Future write actions must be authenticated, idempotent, conflict-aware, auditable, and separately reviewed.

## Deferred security work

Phase 3D does not include:

- public ingress;
- background synchronization;
- backup/restore automation;
- source administration;
- automatic conflict recovery;
- Apple Calendar or Reminder writes.

These remain absent until their own bounded, reviewed phases.
