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
- Tailscale hostnames, keys, or tailnet identifiers;
- production SQLite databases or backups;
- logs or screenshots containing personal information.

Committed fixtures must be synthetic and safe to publish.

## Intended trust boundaries

The planned architecture follows these boundaries:

- Apple Calendar owns Calendar records.
- Apple Reminders owns ordinary Reminder records.
- The macOS Bridge receives Apple permissions and sends only normalized, selected data outward.
- The Ubuntu Deskboard Core stores the local mirror and future Deskboard-owned metadata.
- Display clients receive only the fields required to render their Board.
- Clients and agents do not receive direct database access.
- Apple credentials do not leave the Mac.
- Public internet ingress is not required for the initial deployment.

Any change to these boundaries requires an explicit architecture and privacy review.

## Phase 3B manual-delivery controls

The active Phase 3B implementation is same-Mac and manual only:

- Core remains bound to loopback and exposes exactly one optional ingestion route.
- The route is absent without complete configuration and authenticates one fixed-format bearer token before parsing a body.
- One configured opaque Bridge identity must match the identity inside every accepted snapshot.
- The production Bridge accepts only numeric loopback HTTP origins and has no incoming-network entitlement.
- The Bridge is sandboxed, uses Hardened Runtime, reads only explicitly selected EventKit sources, and contains no EventKit write call.
- The bearer token is stored in macOS Keychain and appears only in the Authorization header.
- Bridge identity, source selections, revisions, and exact pending envelopes live only in the private sandbox container.
- Pending envelopes are treated as private source data and are never logged, exported, attached, or committed.
- Core and Bridge responses and status use content-free result kinds rather than source values.

Remote transport security, Tailscale, TLS termination, deployment, background delivery, Board composition, and Apple writes remain absent until later reviewed slices.

## Dependency and implementation hygiene

- Add dependencies only for current requirements.
- Commit lockfiles and review dependency changes.
- Validate all network and persistence boundaries at runtime.
- Log errors without logging full private records by default.
- Prefer least-privilege source selection and explicit allowlists.
- Treat cached client data as sensitive even when it is not authoritative.
- Future write actions must be authenticated, idempotent, auditable, and narrowly scoped.
