# Phase 3B Authenticated Manual Bridge Delivery

## Status and boundary

This document describes the Phase 3B review implementation for issue #15. Phase 3B remains active until technical review and merge.

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

Apple ingestion is enabled only when all three runtime values are present:

| Environment name | Meaning |
|---|---|
| `DESKBOARD_APPLE_BRIDGE_ID` | The one opaque Bridge identity Core accepts |
| `DESKBOARD_APPLE_BRIDGE_TOKEN` | One 256-bit bearer secret encoded as exactly 64 lowercase hexadecimal characters |
| `DESKBOARD_APPLE_MIRROR_DATABASE_PATH` | Private local path for the isolated Phase 3A SQLite mirror |

If all three values are absent, the ingestion route is absent and normal fixture-only development continues. If only part of the configuration is present, or the identity/token/path format is invalid, startup fails with the fixed `APPLE_SOURCE_INGESTION_CONFIGURATION_INVALID` error. The error contains no configured value.

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
| Retained records per selected source | 500 |
| Encoded pending envelope | 768 KiB |
| Core request body | 1 MiB |
| Core response body accepted by Bridge | 4 KiB |
| URLSession request/resource timeout | 15 seconds |

Ordering and collision checks run on the complete matched set before the record cap. `matchedCount` is always the complete match count. If the source-record cap or encoded-envelope cap omits any matched record, the snapshot is encoded with `truncated: true`. Core therefore rejects it without mutation; the Bridge reports it as blocked and never calls it synchronized.

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

The production app has no probe command mode, private export path, incoming service, scheduler, daemon, launch-at-login behavior, notification, or EventKit save/remove invocation. It stores private state only within its sandbox container and opens only outbound loopback HTTP connections.

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

The app provides one setup path: paste the same locally generated 64-character lowercase hexadecimal secret into the Bridge `SecureField`, then choose **Store Token in Keychain**. The field is cleared after either success or failure. The token is not accepted as a command-line argument and is never shown again.

Supply the same secret privately to the Core process through `DESKBOARD_APPLE_BRIDGE_TOKEN`. Do not place it in shell history, a URL, a query, the JSON body, a screenshot, a log, an issue, or a pull request.

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

1. Build and launch the production Bridge once so it creates an identity.
2. Configure Core with that identity, one newly generated high-entropy token, and a private local mirror path.
3. Store the same token through the Bridge `SecureField` into Keychain.
4. Request Calendar and Reminders permission separately.
5. Select at least one controlled source for each entity when available.
6. Choose **Sync Now** and record only masked source ordinals, counts, result kinds, permission categories, versions, and safe timing.
7. Retry the exact already-delivered envelope/revision and observe `unchangedDuplicate`.
8. Make one controlled Apple-side source change and deliver the next revision.
9. Deny one entity and verify the other remains usable without changing either selection.
10. Remove the private acceptance database when the proof is complete and no longer needed.

No manual-proof record belongs in Git unless it is fully content-free.

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
  build test
```

Build a clean non-test product and inspect its signature and entitlements:

```bash
xcodebuild \
  -project native/apple-bridge/DeskboardAppleBridge.xcodeproj \
  -scheme DeskboardAppleBridge \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /private/tmp/deskboard-phase3b-release-derived \
  build

codesign -d --verbose=4 \
  /private/tmp/deskboard-phase3b-release-derived/Build/Products/Release/DeskboardAppleBridge.app

codesign -d --entitlements :- \
  /private/tmp/deskboard-phase3b-release-derived/Build/Products/Release/DeskboardAppleBridge.app
```

Record only the `runtime` signature flag and the entitlement names/Boolean values listed above. Do not publish hashes, identities, paths containing private names, or unrelated signing metadata.

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
