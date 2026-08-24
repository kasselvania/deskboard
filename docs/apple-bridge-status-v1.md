# Apple Bridge Status Snapshot v1

This document defines the Phase 3C operational status boundary. It is separate from the accepted Apple source contract: source snapshots carry source facts, while `AppleBridgeStatusSnapshotV1` carries only current selection, permission, and delivery-health facts needed to compose an honest Board.

The implementations are:

- TypeScript/Zod: `packages/contracts/src/apple-bridge-status.ts`;
- Swift/Foundation: `native/apple-bridge/DeskboardAppleBridge/AppleBridgeStatusContract.swift`;
- shared synthetic fixtures: `fixtures/apple-bridge-status/v1/`;
- Core storage and route: `apps/api/src/apple-bridge-status/`.

Apple source contract v1 is unchanged.

## Document shape

The strict top-level document contains:

| Field | Meaning |
|---|---|
| `schemaVersion` | Literal `1`. |
| `bridgeId` | Nonempty opaque Bridge identity. |
| `statusRevision` | Positive JavaScript-safe integer revision for this status stream. |
| `capturedAt` | Offset-bearing ISO 8601 capture instant. |
| `permissions.calendar` | Independent Calendar permission category. |
| `permissions.reminders` | Independent Reminders permission category. |
| `selectedSources` | Exact, ordered roster of currently selected source coordinates and their content-free delivery state. |

Permission categories are `notDetermined`, `denied`, `restricted`, `granted`, and `unavailable`.

Each selected-source entry contains:

- `entityType`: `calendar` or `reminder`;
- `sourceContainerId`: opaque coordinate component;
- `status`: one of the content-free states below;
- `acknowledgedSourceRevision`: nonnegative safe integer;
- optional `pendingSourceRevision`;
- optional `lastAttemptedAt`;
- optional `lastAcknowledgedAt`.

Content-free delivery states are:

```text
idle
applied
unchangedDuplicate
blockedTruncated
blockedInvalid
operatorActionStale
operatorActionConflict
retryPending
permissionUnavailable
sourceUnavailable
```

## Semantic invariants

- Every object has exact keys; unknown keys fail.
- Coordinates use Unicode-scalar order by `entityType`, then `sourceContainerId`, and are unique.
- A pending revision equals the acknowledged revision plus one.
- `blockedTruncated`, `operatorActionStale`, `operatorActionConflict`, and `retryPending` require pending source bytes.
- `idle`, successful, permission-unavailable, and source-unavailable states forbid pending source bytes.
- `blockedInvalid` permits either shape because conversion can fail before an envelope exists or Core can reject an already persisted candidate.
- A pending entry has `lastAttemptedAt`.
- A positive acknowledged revision has `lastAcknowledgedAt`; revision zero does not.
- Successful state has a positive acknowledged revision and an attempt instant.
- An idle source has no revision history.
- Entry timestamps cannot be later than `capturedAt`.

The roster authorizes Board selection only. Removing a coordinate from the roster does not authorize deletion of its source scope or records from the mirror.

## Excluded data

The document contains no source or record title, record count, temporal source value, token, pending-envelope bytes, account data, EventKit payload, signer, certificate, or Team ID. The opaque source coordinate is persisted inside trusted Core because it is required to join status to the mirror; it is never exposed through a read route or Board document.

## Exact fixture inventories

Swift and TypeScript enumerate the same five valid fixtures:

```text
empty-independent-permissions.json
selected-applied.json
selected-blocked-invalid.json
selected-retry-pending.json
selected-unavailable.json
```

They enumerate the same thirteen invalid fixtures:

```text
acknowledged-without-time.json
duplicate-coordinate.json
excluded-source-title.json
invalid-captured-at.json
pending-revision-gap.json
retry-without-pending.json
success-with-pending.json
unknown-delivery-key.json
unknown-permission.json
unknown-top-level-key.json
unordered-coordinate.json
unsupported-schema-version.json
zero-status-revision.json
```

The allowlists are locked in both test suites; adding or removing a fixture requires an explicit contract change.

## Crash-safe Bridge outbox

Bridge state version 1 now also stores:

- last acknowledged status revision, defaulting to zero for Phase 3B state files;
- at most one exact pending encoded status document;
- one content-free status-delivery result.

Before a new status send, the Bridge derives the next revision, builds and validates the whole document, deterministically encodes it, atomically saves those exact bytes, and sends the saved bytes. Timeout, response loss, termination, relaunch, malformed response, and transport uncertainty preserve the pending bytes and revision.

Only `applied` and `unchangedDuplicate` acknowledge and clear pending status. Invalid, stale, conflict, and transport outcomes keep the exact pending document. Status delivery never edits, clears, replaces, or reorders a pending source envelope.

`Sync Now` executes this sequence:

1. retry an exact pending status document;
2. stop without touching source pending state or EventKit if that status remains unresolved;
3. retry exact pending source envelopes in coordinate order;
4. read and deliver eligible new selected-source snapshots;
5. derive, validate, encode, and atomically persist one new final status document;
6. deliver that exact final document.

The early stop is necessary because only one pending status document is allowed; it prevents different status content from replacing uncertain bytes under the same revision.

## Authenticated Core boundary

`POST /v1/apple-bridge-status` is the only new route. It:

- reuses the Phase 3B fixed bearer token and expected opaque Bridge identity;
- authenticates in `onRequest` before body parsing;
- requires JSON;
- enforces a 262,144-byte body limit;
- binds the parsed Bridge ID to the authenticated identity;
- returns only fixed errors or content-free result documents;
- exposes no status read route.

Core canonicalizes parsed values, computes a SHA-256 digest, and stores the parsed document, accepted revision, digest, capture time, and receive time in migration 2 of the existing private mirror database. Metadata and document commit in one transaction. A newer revision applies; equal revision/equal digest is an unchanged duplicate; equal revision/different digest conflicts; a lower revision is stale. Invalid input does not mutate state. Persisted JSON is strictly parsed again and checked against its metadata and digest on every internal read.

In mirror-backed mode, source ingestion, status ingestion, and Board composition use one `AppleSourceMirror` instance and one close hook.
