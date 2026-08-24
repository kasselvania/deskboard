# Security and Privacy Policy

Deskboard is local-first software intended to process personal Calendar, Reminder, project, household, and activity information. Privacy boundaries are part of the product design, not a deployment afterthought.

## Supported code

Until versioned releases exist, only the current `main` branch is considered supported.

## Reporting a security issue

Do not open a public issue containing credentials, private source data, exploit details, or identifying information.

Report sensitive findings through a GitHub private security advisory when available, or contact the repository owner through an established private channel. Include:

- the affected component and revision;
- steps to reproduce;
- expected and observed behavior;
- likely impact;
- any suggested mitigation;
- only the minimum sanitized evidence needed to demonstrate the issue.

Do not include real Calendar events, Reminders, contacts, addresses, health or recovery information, household state, Tailscale identifiers, tokens, or private database contents.

## Repository rules

The repository must not contain:

- `.env` files or production secrets;
- access tokens, private keys, certificates, or provisioning profiles;
- real EventKit exports;
- real Calendar, Reminder, Notes, household, contact, or activity data;
- real Board screenshots, accessibility trees, DOM dumps, or API payloads;
- Tailscale hostnames, keys, or tailnet identifiers;
- production SQLite databases or backups;
- pending source or Bridge-status envelopes;
- logs or screenshots containing personal information.

Committed fixtures must be synthetic and safe to publish.

## Intended trust boundaries

The architecture follows these boundaries:

- Apple Calendar owns Calendar records.
- Apple Reminders owns ordinary Reminder records.
- The macOS Bridge receives Apple permissions and sends only normalized, explicitly selected data outward.
- Deskboard Core stores the read-only source mirror and later Deskboard-owned metadata.
- Display clients receive only the fields required to render their Board.
- Clients and agents do not receive direct database access.
- Apple credentials do not leave the Mac.
- Public internet ingress is not required for the initial deployment.

Any change to these boundaries requires an explicit architecture and privacy review.

## Accepted Phase 3B manual-delivery controls

The accepted Phase 3B path is same-Mac and manual only:

- Core remains bound to loopback and exposes exactly one optional source-ingestion route.
- The route is absent without complete configuration and authenticates one fixed-format bearer token before parsing a body.
- One configured opaque Bridge identity must match the identity inside every accepted snapshot.
- The production Bridge accepts only numeric loopback HTTP origins and has no incoming-network entitlement.
- The Bridge is Apple Development-signed, sandboxed, uses Hardened Runtime, reads only explicitly selected EventKit sources, and contains no EventKit write call.
- Calendar and Reminders requests expose only normalized before/after authorization categories, the returned grant Boolean when present, and fixed content-free outcomes.
- The repository commits no development team, signer, Team ID, certificate, or provisioning profile. Ad hoc signing is only an explicit automated-test override; custom certificate authorities and signing workflows are unsupported.
- The bearer token is stored in macOS Keychain and appears only in the Authorization header.
- Bridge identity, source selections, revisions, and exact pending source envelopes live only in the private sandbox container.
- Pending envelopes are treated as private source data and are never logged, exported, attached, or committed.
- Core and Bridge responses and status use content-free result kinds rather than source values.
- A signer transition never silently reuses inaccessible private state. Any intentional state reset requires owner awareness, a new opaque Bridge ID, and Core reconfiguration before revision 1 begins under the new identity.

## Implemented Phase 3C real-data Board controls

The active Phase 3C branch composes a local real-data Board only after Core has a strict content-free view of current Bridge selection and source health. Acceptance still requires the private owner gate and review.

- A selected-source roster and content-free delivery status are operational facts, separate from source records.
- One additional authenticated loopback status route reuses the Phase 3B token and Bridge binding; it has a finite body limit and no read counterpart.
- The Bridge persists and retries exact pending status bytes independently of pending source bytes.
- Core stores parsed status, revision, and digest transactionally in the existing private mirror database.
- In mirror mode, source ingestion, status ingestion, and Board composition share one Core-owned resource and one close lifecycle.
- A deselected source disappears from Board consideration but its mirror rows are not deleted merely because it is absent from the roster.
- A blocked, truncated, retrying, missing, permission-denied, or stale source must not be silently ignored to make an entity appear fresh.
- Last-good selected-source facts may remain displayable with stale or unavailable freshness; operational failure never fabricates source deletion.
- The web client receives only the accepted Board contract. It receives no Bridge ID, source-container ID, EventKit ID, mirror row, status document, token, or pending envelope.
- Board item IDs and versions must not reveal raw source provenance.
- Fixture mode remains the default; mirror-backed mode requires complete explicit local configuration and a valid IANA Board time zone.

### Agent-visible evidence boundary

The owner may privately inspect real source-selection and Board surfaces. Agents and shared tooling may receive only purpose-built content-free evidence such as schema success, item counts, freshness categories, permission categories, revisions, result kinds, and masked ordinals.

Do not use or transmit any of the following for real-data acceptance:

- screenshots;
- accessibility trees;
- OCR output;
- DOM dumps;
- API request or response bodies;
- source titles or Board titles;
- mirror rows;
- pending envelopes;
- EventKit or source identifiers.

The private accessibility-inspection incident during Phase 3B did not enter Git or public artifacts, but it establishes this hard process rule for every later real-data slice.

Remote transport security, Tailscale, TLS termination, deployment, background delivery, backup/restore, Board source management, and Apple writes remain absent until later reviewed slices.

## Dependency and implementation hygiene

- Add dependencies only for current requirements.
- Commit lockfiles and review dependency changes.
- Validate all network and persistence boundaries at runtime.
- Log errors without logging full private records by default.
- Prefer least-privilege source selection and explicit allowlists.
- Treat cached client data as sensitive even when it is not authoritative.
- Future write actions must be authenticated, idempotent, auditable, and narrowly scoped.
