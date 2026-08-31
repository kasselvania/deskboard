# Phase 3B Authenticated Manual Bridge Delivery

## Status and boundary

This document describes the Phase 3B review implementation for issue #15. Phase 3B remains active until technical review and merge.

Manual TCC acceptance requires an Apple Development-signed Release product launched from the stable installed path `~/Applications/DeskboardAppleBridge.app`. The project commits neither a development team nor a certificate identity and does not force ad hoc signing on the production application target. Ad hoc signing is acceptable only as an explicit command-line override for automated structural builds and synthetic tests; it is not permission, reinstall, relaunch, or update evidence.

The slice proves one explicitly invoked, read-only macOS Bridge delivering accepted Apple source snapshots to Deskboard Core on the same Mac. The Board remains fixture-backed. Remote topology, deployment, background operation, Board composition from the mirror, stale/conflict recovery, and every Apple write path are deferred.

The production Bridge is separate from the Phase 2A discovery probe. It reuses only the accepted pure Swift source-contract implementation. It does not reuse the probe application, disabled sandbox, private export, or command mode.

## Same-Mac topology

```text
selected Calendar and Reminder sources
                  │
                  │ read-only EventKit
                  ▼
      sandboxed Deskboard Apple Bridge
        │                         │
        │ exact pending envelope  │ bearer token
        │ in sandbox state        │ in Keychain
        └────────────┬────────────┘
                     │ explicit Sync Now
                     │ HTTP to numeric loopback only
                     ▼
       POST /v1/apple-source-snapshots
                     │
                     │ accepted Phase 3A apply boundary
                     ▼
          isolated Core SQLite mirror
```

Core continues to bind to `127.0.0.1`. The Bridge accepts only an explicit numeric HTTP loopback origin with a port: an IPv4 address in `127.0.0.0/8` or exact IPv6 loopback `[::1]`. It rejects hostnames, DNS-dependent names, non-loopback IPs, HTTPS, user information, query strings, fragments, missing ports, and paths other than the route it appends itself.

This slice deliberately does not choose TLS termination, Tailscale addressing, remote host identity, reverse proxy behavior, or homelab deployment. Those coupled decisions belong to Phase 3C.

## Core ingestion configuration

Apple ingestion is enabled only when the Bridge identity and mirror path are present with exactly one accepted token source:

| Environment name | Meaning |
|---|---|
| `DESKBOARD_APPLE_BRIDGE_ID` | The one opaque Bridge identity Core accepts |
| `DESKBOARD_APPLE_BRIDGE_TOKEN` | One 256-bit bearer secret encoded as exactly 64 lowercase hexadecimal characters |
| `DESKBOARD_APPLE_BRIDGE_TOKEN_FILE` | Phase 3D alternative absolute file containing exactly the same token format; mutually exclusive with `DESKBOARD_APPLE_BRIDGE_TOKEN` |
| `DESKBOARD_APPLE_MIRROR_DATABASE_PATH` | Private local path for the isolated Phase 3A SQLite mirror |

If all four settings are absent, the ingestion route is absent and normal fixture-only development continues. If only part of the configuration is present, if both token settings are present, or if the identity/token/path format is invalid, startup fails with the fixed `APPLE_SOURCE_INGESTION_CONFIGURATION_INVALID` error. The error contains no configured value.

Do not commit a populated environment file. Supply the values only to the local Core process. The mirror path must be private, outside tracked repository content, and must not identify a real source in its name.

After setting the three values in the local process environment, Core can be run with:

```bash
npm run dev --workspace @deskboard/api
```

The existing `/health` and fixture-backed `/v1/board` routes are unchanged.

## Authentication and Bridge binding

The only ingestion route is:

```text
POST /v1/apple-source-snapshots
```

It requires `Content-Type: application/json` and:

```text
Authorization: Bearer <configured secret>
```

The Fastify route authenticates in an `onRequest` hook, before JSON body parsing. Fixed-format secret material is decoded to two 32-byte values and compared with Node's constant-time `timingSafeEqual`. Missing, malformed, and wrong headers receive the same content-free authentication result.

The accepted snapshot's `bridgeId` must equal the identity bound to the authenticated token. A valid token for a different Bridge does not authorize application.

The strict operational request has exactly two keys:

```json
{
  "sourceRevision": 1,
  "snapshot": {
    "schemaVersion": 1,
    "entityType": "reminder"
  }
}
```

The abbreviated snapshot above illustrates the envelope only; it is not a valid source snapshot. The real `snapshot` must pass the unchanged strict Phase 2B Reminder-or-Calendar union, and `sourceRevision` must be a positive JavaScript-safe integer. Unknown envelope or snapshot keys fail.

The route delegates directly to `AppleSourceMirror.apply`. It does not reproduce revision, digest, replacement, transaction, or rollback logic. When configured, Core owns one mirror and closes it exactly once from one Fastify `onClose` hook.

## Finite operational limits

| Boundary | Limit |
|---|---:|
| Calendar window | 7 calendar days behind and 45 calendar days ahead of capture |
| Retained Reminder records per selected source | 1,000 |
| Retained Calendar records per selected source | 500 |
| Encoded pending envelope | 768 KiB |
| Core request body | 1 MiB |
| Core response body accepted by Bridge | 4 KiB |
| URLSession request/resource timeout | 15 seconds |

Ordering and collision checks run on the complete matched set before the entity-specific record cap. `matchedCount` is always the complete match count. Phase 3E changed only the measured Reminder cap from 500 to 1,000; the Calendar cap remains 500. If the applicable source-record cap or encoded-envelope cap omits any matched record, the snapshot is encoded with `truncated: true`. Core therefore rejects it without mutation; the Bridge reports it as blocked and never calls it synchronized.

The 768 KiB envelope ceiling remains below the 1 MiB Core route limit, leaving finite transport headroom. The bearer token is an HTTP header and is never part of the encoded or persisted envelope.

## Apply-result and HTTP mapping

Core returns only the result kind and, when already present in the safe mirror result, entity type and source revision.

| Mirror result | HTTP | Bridge transition |
|---|---:|---|
| `applied` | 200 | acknowledge once; clear pending |
| `unchangedDuplicate` | 200 | acknowledge once; clear pending |
| `rejectedStale` | 409 | preserve pending; operator action required |
| `rejectedRevisionConflict` | 409 | preserve pending; operator action required |
| `rejectedTruncated` | 422 | preserve pending; blocked |
| `rejectedInvalid` | 400 | preserve pending; blocked |

Route-boundary failures use fixed content-free codes:

| Condition | HTTP | Code |
|---|---:|---|
| Missing, malformed, or wrong bearer header | 401 | `APPLE_SOURCE_AUTHENTICATION_FAILED` |
| Authenticated Bridge-ID mismatch | 403 | `APPLE_SOURCE_BRIDGE_MISMATCH` |
| Non-JSON content type | 415 | `APPLE_SOURCE_JSON_REQUIRED` |
| Body exceeds 1 MiB | 413 | `APPLE_SOURCE_BODY_TOO_LARGE` |
| Unexpected mirror exception | 500 | `APPLE_SOURCE_APPLICATION_FAILED` |

An unrecognized status, malformed JSON, non-JSON response, oversized response, mismatched entity/revision, redirect, timeout, reset connection, or response loss is an uncertain delivery. The Bridge preserves the pending bytes and reports retry-pending status.

Responses never include container identifiers, record identifiers, titles, temporal values, digests, snapshots, database values, or token information.

## Production Bridge target

The dedicated project is:

```text
native/apple-bridge/DeskboardAppleBridge.xcodeproj
```

Its shared scheme is `DeskboardAppleBridge`. The application target is a SwiftUI macOS app; the test target uses only synthetic source-shaped inputs and injected state, credential, and transport boundaries.

The production target declares:

| Setting or entitlement | Value |
|---|---|
| App Sandbox | enabled |
| Hardened Runtime | enabled |
| `com.apple.security.app-sandbox` | `true` |
| `com.apple.security.network.client` | `true` |
| `com.apple.security.personal-information.calendars` | `true` |
| incoming-network entitlement | absent |
| arbitrary user-selected/downloads file entitlement | absent |
| Keychain sharing | absent |

The generated application property list includes `NSCalendarsFullAccessUsageDescription` and `NSRemindersFullAccessUsageDescription`. Calendar and Reminders access is requested independently and remains independently usable.

The production application target uses automatic signing without a committed `DEVELOPMENT_TEAM`, signer, Team ID, certificate, or provisioning profile. Phase 3B supports no self-signed certificate, local certificate authority, custom signing script, Developer ID distribution, or notarization workflow. A local Apple Development identity from an enrolled Xcode team or Personal Team is required only for the manual TCC acceptance build. A machine without that identity may run the synthetic test gate through an explicit ad hoc command-line override, but must stop before claiming manual permission acceptance.

The production app has no probe command mode, private export path, incoming service, scheduler, daemon, launch-at-login behavior, notification, or EventKit save/remove invocation. It stores private state only within its sandbox container and opens only outbound loopback HTTP connections.

## Explicit permission-request results

Every intentional Calendar or Reminders request returns one content-free `BridgePermissionRequestResult` to the view model. It records:

- the requested entity category;
- authorization category before the system request;
- the Boolean returned by the EventKit full-access request when it completed;
- authorization category after the request;
- one normalized outcome: `granted`, `denied`, `restricted`, `unavailable`, `systemRequestError`, or `noSystemDecision`.

A thrown EventKit request is `systemRequestError`; it is not collapsed into the current authorization category. A completed request that leaves authorization `notDetermined` is `noSystemDecision`. Calendar and Reminders retain separate last-request results in `BridgeViewModel`, and requesting one never changes the other's recorded result.

The UI displays only fixed operator messages. In particular, a completed request with no decision says that the entity access request did not produce a system decision and directs the owner to verify signing and installation. Arbitrary localized errors, source names, identifiers, and EventKit content are not displayed or logged.

## Source selection and read-only conversion

Calendar and Reminder selections are separate and default empty. Only explicitly selected source identifiers are read. Permission loss preserves the saved selections and does not broaden them. A selected source that disappears is reported unavailable; its selection and last acknowledged state are retained for operator action.

The local selection interface may display source names to the owner. Persisted and delivered source documents use source identifiers but never copy source, list, calendar, account, or provider titles.

### Reminder conversion

For each selected Reminder list, the Bridge uses an unfiltered `predicateForReminders` read covering every accessible Reminder in that list. It preserves only:

- bridge-scoped local identifier;
- optional external identifier and optional title;
- distinct absent, date-only, local date-time, and timezone-qualified start/due values;
- completion state and optional completion instant;
- selected container identity and mutability.

It applies no completion, due-date, title, recency, priority, or recurrence filter.

### Calendar conversion

For each selected Calendar, the Bridge reads events overlapping the exact declared capture window. It preserves only:

- accepted local, event, and optional external identifiers;
- optional title;
- exact offset-bearing start/end instants plus the time zone for timezone-qualified events;
- local/floating timed ranges only when both civil values exist exactly once in the window time zone;
- exclusive all-day civil-date ranges;
- optional occurrence date, detached state, normalized status, and source capability fields.

Local Calendar times that are nonexistent or ambiguous fail the complete source candidate. Calendar records are sorted by the accepted interpreted-range and provenance coordinate before capping. A complete equal coordinate invalidates the candidate.

### Excluded collection

The production reader does not access or copy notes, URLs, locations, structured locations, participants, organizers, attendees, alarms, account titles, recurrence grammar, creation/modification timestamps, or excluded diagnostic fields. Tests scan the EventKit reader for these accesses and for save/remove calls.

## Credential setup

The production credential boundary is a generic-password item in the user's macOS Keychain. It uses Apple Security APIs directly, requires no package, does not enable Keychain sharing, and stores the item as available only while the device is unlocked and only on that device.

For accepted Phase 3B local setup, the app interface provides one manual path: paste the same locally generated 64-character lowercase hexadecimal secret into the Bridge `SecureField`, then choose **Store Token in Keychain**. The field is cleared after either success or failure. Phase 3D adds only the fixed owner-only provisioning inbox described in the private deployment guide; the signed Bridge process consumes that request without accepting a token as a command-line argument, notice, or receipt value.

Supply the same secret privately to Core through exactly one of `DESKBOARD_APPLE_BRIDGE_TOKEN` or `DESKBOARD_APPLE_BRIDGE_TOKEN_FILE`. Phase 3D uses the file form so Compose grants the secret only to the API service. Do not place it in shell history, a process argument, URL, query, JSON body, screenshot, log, issue, or pull request.

## Private Bridge state

The production state file resolves inside the app sandbox container at:

```text
~/Library/Containers/com.kasselvania.deskboard.AppleBridge/Data/Library/Application Support/DeskboardAppleBridge/bridge-state-v1.json
```

The containing directory is created with owner-only permissions and the state file is written atomically with owner-only file permissions. The file contains:

- one opaque random Bridge ID;
- separate selected Calendar and Reminder source-ID sets;
- the configured numeric loopback origin;
- acknowledged revision per entity/source coordinate;
- at most one exact pending envelope per coordinate;
- content-free status and attempt/acknowledgement times.

The bearer token is not in this file. Pending envelopes do contain private normalized source facts. Do not print, export, inspect in shared tooling, attach, screenshot, back up to a public location, or commit this file.

If the state file is intentionally reset or lost, the next creation generates a new Bridge ID and empty selections/revisions. Core must then be reconfigured for that new identity. Corrupt state fails closed; the app does not silently reset identity or restart revision 1 under an old identity.

Changing from an ad hoc build to Apple Development signing may change access to the existing sandbox container or Keychain item. Before any reset, inspect only content-free pending and status counts. Do not copy, reinterpret, print, or publicly move the old state. If the signed installed product cannot safely use it, stop for owner awareness and perform an intentional state and credential reset. That reset must create a new opaque Bridge ID, require Core reconfiguration for the new identity, and start revisions under that new identity. Revision 1 must never restart under the old Bridge ID.

## Crash-safe pending lifecycle

For a source without pending work, **Sync Now** performs this sequence:

1. verify that the entity permission is still granted and the selected source still exists;
2. read the complete selected EventKit scope;
3. convert and validate the accepted v1 source snapshot;
4. derive `nextRevision = acknowledgedRevision + 1` for that entity/source coordinate;
5. deterministically encode the strict operational envelope;
6. atomically persist those exact encoded bytes as pending;
7. send the persisted bytes.

At the beginning of every later **Sync Now**, all persisted pending coordinates are attempted before any new EventKit read. A coordinate retried during that action is not reread, even if Core acknowledges it. This prevents a newer Apple state from being placed under the uncertain revision.

Only `applied` and `unchangedDuplicate` atomically advance the acknowledged revision and clear pending. Truncated and invalid results remain blocked with pending intact. Stale and conflict results require operator action, retain pending, and do not invent a recovery revision or reset identity. Every transport or response uncertainty remains retry-pending with the exact bytes intact.

Recovery from stale or conflicting Core state is intentionally absent from Phase 3B.

## Manual interface

The production app has one delivery action: **Sync Now**. Its local interface shows:

- Calendar and Reminders permission independently;
- locally named selectable sources for a granted entity;
- selected Calendar and Reminder-list counts;
- in-progress state;
- content-free per-source result and revision;
- last attempted and last acknowledged times;
- whether an exact persisted pending envelope will be retried.

Per-source operational rows use masked entity ordinals rather than source identifiers. The app does not log source content.

## Private local acceptance procedure

Run this only on the owner's Mac. Do not capture or publish the source-selection UI, pending state, mirror rows, token, or source values.

1. Inspect `security find-identity -p codesigning` privately and discover the local Xcode team without printing either value. The actual Apple-Development-signed Release build below is the signing source of truth: a `-v` summary that reports zero valid identities does not by itself block the attempt. If the build fails, diagnose its exact Xcode/codesign error rather than returning the identity summary. Do not create signing credentials automatically or invent another signing posture.
2. Inspect the previous Bridge only for content-free pending and status counts. If its state or Keychain item is unavailable to the signed product, stop for owner awareness before the intentional new-identity reset described above.
3. Supply the local team only in the shell environment and build a Release product with Apple Development signing, automatic provisioning, the committed entitlements, and Hardened Runtime. Never commit or publish the team or signer.
4. Quit every running Bridge copy. Stage and strictly verify the exact signed product before replacing `~/Applications/DeskboardAppleBridge.app`. Move the prior bundle out of `~/Applications` before moving the staged product into that canonical path; never overlay one application bundle onto another or retain a renamed copy with the same bundle identity. Launch no DerivedData copy concurrently.
5. Verify the installed product's strict signature, Apple Development authority, stable designated requirement, `runtime` flag, bundle identifier, and entitlement allowlist. Record only the content-free conclusions.
6. Quit the installed app and run `tccutil reset Calendar com.kasselvania.deskboard.AppleBridge`. Launch only the installed app, intentionally request Calendar access, and record only before category, normalized outcome, returned Boolean, after category, and whether the prompt appeared. Acceptance requires `granted` or `denied`; `notDetermined` without a prompt fails.
7. Repeat independently with `tccutil reset Reminders com.kasselvania.deskboard.AppleBridge`. Prove each reset/request leaves the other entity's decision unchanged. Do not reset another app or service.
8. Build a second Release product from the same branch with the same Apple Development identity. Compare designated requirements locally, replace the installed bundle with the second signed product, and prove both permission decisions remain associated without a rebuild-only prompt. Report only three yes/no conclusions: requirement stable, Calendar decision persisted, Reminders decision persisted.
9. Configure Core with the accepted or intentionally reset Bridge identity, one newly generated high-entropy token, and a private local mirror path. Store the same token through the Bridge `SecureField` into Keychain.
10. Select at least one controlled source for each granted entity when available. Choose **Sync Now** and record only masked source ordinals, counts, result kinds, permission categories, versions, and safe timing.
11. Retry the exact already-delivered envelope/revision and observe `unchangedDuplicate`. Make one controlled Apple-side source change and deliver the next revision. Deny one entity and prove the other remains usable without changing either selection.
12. Remove the private acceptance database when the proof is complete and no longer needed.

If a correctly Apple-Development-signed installed product still completes a request as `noSystemDecision`, stop without opening a PR. Retain only content-free before/result/after diagnostics, collect local TCC/EventKit material only as needed for Feedback Assistant, file Apple feedback, and report only its number and the normalized result. Do not disable SIP, edit the TCC database, insert grants, broaden entitlements, or reset unrelated applications or services.

No manual-proof record belongs in Git unless it is fully content-free.

## Content-free local acceptance record

The owner-Mac acceptance run on 2026-08-24 completed against the installed second Release product. This record deliberately omits signer, team, certificate, designated-requirement text, source values, identifiers, temporal payloads, token material, pending bytes, and database rows.

- Identity category: one Xcode Personal Team Apple Development identity was available. The first real Release build with automatic signing and provisioning updates succeeded; no certificate-chain repair or custom trust action was needed.
- Installed product: strict signature valid; Apple Development authority present; expected bundle identifier present; stable non-ad-hoc designated requirement present; Hardened Runtime present.
- Entitlements: App Sandbox `true`; outgoing network client `true`; Calendar/EventKit `true`; incoming network absent; arbitrary file access absent.
- Calendar permission: before `notDetermined`; system prompt appeared; returned grant Boolean `true`; normalized result `granted`; after `granted`. The Reminders state was unchanged by this request.
- Reminders permission: before `notDetermined`; system prompt appeared; returned grant Boolean `true`; normalized result `granted`; after `granted`. The Calendar state was unchanged by this request.
- Same-identity rebuild: designated requirement stable `yes`; Calendar decision persisted `yes`; Reminders decision persisted `yes`; rebuild-only prompt `no`.
- Signer transition: the signed product loaded the existing sandbox state and Keychain credential through their production boundaries. No state reset, Bridge-ID change, credential migration, or revision restart was required.
- Signed delivery: two Calendar scopes and two non-truncated Reminder scopes were accepted into the isolated mirror, containing 18 and 61 records respectively. A fifth selected Reminder scope remained honestly `blockedTruncated` with its revision-1 pending envelope preserved.
- Uncertain response: Core committed Calendar revision 4, its response was deliberately withheld, and the installed Bridge was terminated. Relaunch showed the exact persisted revision still pending. The next **Sync Now** returned `unchangedDuplicate` for revision 4, which proves the resent revision had the same accepted digest; the pending delivery then cleared.
- Controlled source change: one synthetic owner-controlled Calendar change was made through Calendar, not through the Bridge. Both selected Calendar scopes and both usable Reminder scopes then returned `applied` at revision 5.
- Permission isolation: Calendar was changed to `denied` while Reminders remained `granted`. Calendar scopes reported `permissionUnavailable`; both usable Reminder scopes returned `applied` at revision 6; the truncated Reminder stayed blocked and pending.
- Validation: Node 24.19.0 passed lint, typecheck, 73 unit/integration tests, all production builds, and five browser tests with one intentional skip. The production Bridge passed 30 tests. The accepted Phase 2A probe passed 35 tests. Both signed Release builds and the final installed-product verification passed.

Phase 3B remains a review implementation until its draft pull request is reviewed and merged. This local acceptance record does not activate Phase 3C.

## Content-free troubleshooting

| Visible state | Meaning | Phase 3B action |
|---|---|---|
| `retryPending` | Core may or may not have committed | Retry **Sync Now**; exact bytes are preserved |
| `blockedTruncated` | A finite cap omitted matches | Do not claim synchronized; keep pending |
| `blockedInvalid` | Conversion or Core validation failed | Inspect code/configuration without exposing payload |
| `operatorActionStale` | Core has a later accepted revision | Stop; recovery is not implemented |
| `operatorActionConflict` | Same revision has different Core content | Stop; recovery is not implemented |
| `permissionUnavailable` | One entity permission is not granted | The other entity may still sync independently |
| `sourceUnavailable` | A selected source disappeared | Preserve the selection/state; do not substitute another source |
| `noSystemDecision` | EventKit completed but TCC remained `notDetermined` | Verify Apple Development signing and stable installation; retry only after correcting them |
| `systemRequestError` | EventKit threw while requesting permission | Preserve the other entity and use only normalized local diagnosis |

Never troubleshoot by printing request bodies, pending envelopes, source identifiers, titles, times, database rows, or Keychain values.

## Reproducible validation

Run the locked Node gate from the repository root:

```bash
source /Users/peterkassel/.nvm/nvm.sh
nvm use
export PATH="/Users/peterkassel/.nvm/versions/node/v24.19.0/bin:$PATH"
rehash
node --version
npm ci
npm run check
git diff --check
git diff --check main...HEAD
```

Run the accepted probe gate without accessing the user's EventKit store:

```bash
xcodebuild \
  -project tools/apple-eventkit-probe/AppleEventKitProbe.xcodeproj \
  -scheme AppleEventKitProbe \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/deskboard-phase3b-probe-derived \
  build test
```

Run the production Bridge gate:

```bash
xcodebuild \
  -project native/apple-bridge/DeskboardAppleBridge.xcodeproj \
  -scheme DeskboardAppleBridge \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/deskboard-phase3b-bridge-derived \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build test
```

The three trailing settings are the explicit no-identity override for automated structural tests. They are not manual TCC evidence.

Before the manual proof, inspect the Apple Development identity privately, provide its team without committing it, and attempt the signed product. Treat this `xcodebuild` result, not the standalone identity-validity count, as the diagnostic boundary:

```bash
security find-identity -v -p codesigning
export DESKBOARD_APPLE_DEVELOPMENT_TEAM="<local team id>"

xcodebuild \
  -project native/apple-bridge/DeskboardAppleBridge.xcodeproj \
  -scheme DeskboardAppleBridge \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/deskboard-phase3b-signed-release \
  DEVELOPMENT_TEAM="$DESKBOARD_APPLE_DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  -allowProvisioningUpdates \
  build

DESKBOARD_INSTALL_STAGE="$(mktemp -d /private/tmp/deskboard-install.XXXXXX)"

ditto \
  /private/tmp/deskboard-phase3b-signed-release/Build/Products/Release/DeskboardAppleBridge.app \
  "$DESKBOARD_INSTALL_STAGE/DeskboardAppleBridge.app"

codesign --verify --deep --strict --verbose=4 \
  "$DESKBOARD_INSTALL_STAGE/DeskboardAppleBridge.app"

mv \
  "$HOME/Applications/DeskboardAppleBridge.app" \
  "$DESKBOARD_INSTALL_STAGE/previous-DeskboardAppleBridge.app"

mv \
  "$DESKBOARD_INSTALL_STAGE/DeskboardAppleBridge.app" \
  "$HOME/Applications/DeskboardAppleBridge.app"

codesign --verify --deep --strict --verbose=4 \
  "$HOME/Applications/DeskboardAppleBridge.app"

codesign --display --verbose=4 \
  "$HOME/Applications/DeskboardAppleBridge.app"

codesign --display --requirements - \
  "$HOME/Applications/DeskboardAppleBridge.app"

codesign --display --entitlements :- \
  "$HOME/Applications/DeskboardAppleBridge.app"
```

Repeat the signed Release build from the same branch and compare its designated requirement locally before replacing the installed bundle. Record only signature validity, Apple Development authority presence, designated-requirement stability, the `runtime` flag, expected bundle identity, required entitlement names/Boolean values, forbidden entitlement absence, and permission-decision persistence. Do not publish the requirement string, signer, Team ID, certificate hash, provisioning profile, or unrelated signing metadata.

Finally verify repository integrity:

```bash
git status --short
git ls-files private-fixtures
git diff --name-only main...HEAD -- fixtures/eventkit
git diff --name-only main...HEAD -- fixtures/apple-source-contract
git diff --check main...HEAD
```

The Phase 2A evidence bytes, Phase 2B contract and fixtures, and Phase 3A mirror semantics must remain unchanged. No private fixture, secret, pending state, database, dump, or new dependency may be tracked.

## Deferred to Phase 3C

Phase 3B intentionally leaves absent:

- LAN, Tailscale, public, or arbitrary remote delivery;
- TLS termination, reverse proxy, Docker, CasaOS, or homelab deployment;
- background scheduling, daemon, watcher, login item, menu-bar agent, or notification;
- Board composition from mirrored Apple facts or any mirror-read/status API;
- source management in the Board or any web-client change;
- automatic stale/conflict recovery;
- every Calendar or Reminder write, including Reminder completion;
- command queues, metadata parsing, generic buses/frameworks, Notes, Home Assistant, Open Loops, Projects, sessions, timers, ranking, and AI.

Deferred means absent, not partially implemented.
