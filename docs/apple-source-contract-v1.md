# Apple source contract v1 — Phase 2B

## Status

This document defines the Phase 2B Apple source contract and reconciliation semantics implemented on `feat/apple-source-contract-v1`. Phase 2B remains active until its draft pull request is reviewed and merged. Phase 3 has not begun.

The runtime implementations are:

- TypeScript/Zod: `packages/contracts/src/apple-source-contract.ts`;
- Swift/Foundation: `tools/apple-eventkit-probe/AppleEventKitProbe/AppleSourceContract.swift`;
- shared synthetic wire fixtures: `fixtures/apple-source-contract/v1/`.

The accepted Phase 2A probe models and twelve EventKit specimens remain evidence models and evidence files. They are not renamed, reused, or treated as the wire contract.

## 1. Purpose and non-goals

Version 1 answers one question:

> What is the smallest Apple-source document that a later one-way mirror can validate, order, and reconcile without losing the distinctions accepted in Phase 2A?

It defines two explicit documents:

- `AppleReminderSourceSnapshotV1`;
- `AppleCalendarSourceSnapshotV1`.

Each document represents one successful read from one selected Apple source container through one Deskboard Bridge. There is no generic adapter payload and no unvalidated payload dictionary.

Version 1 is not a production Bridge, transport envelope, database row, synchronization generation, source mirror, deployment, Board projection, metadata parser, or Apple write command. It adds no network path, persistence, authentication, background scheduling, source-management UI, or Board behavior.

## 2. Exact scope-document semantics

### Shared snapshot fields

| Field | Wire type | Meaning |
|---|---|---|
| `schemaVersion` | literal `1` | Version of this concrete Apple source document. |
| `entityType` | `reminder` or `calendar` | Selects the concrete snapshot variant. It is not repeated per record. |
| `bridgeId` | non-empty opaque string | Deskboard-issued identity of the supplying Bridge. It carries no hostname, account, owner, or hardware meaning. |
| `source` | strict variant-specific object | The single explicitly selected Apple source container. |
| `capturedAt` | offset-bearing ISO 8601 instant | Time at which the successful source read was captured. |
| `matchedCount` | non-negative integer | Exact count of source records that matched the declared scope before a safety cap. |
| `truncated` | boolean | Whether at least one matched record was omitted from `records`. |
| `records` | ordered array | Deterministic retained prefix after source matching and ordering. |

`records.length` is the retained count, so a second count field would be redundant. `absenceIsAuthoritative` is also deliberately not serialized. For a semantically valid snapshot it is derived as `!truncated`.

Every accepted snapshot is a successful read document. A failed, interrupted, partially enumerated, or malformed read is not represented by setting another status inside this contract; it produces no acceptable replacement snapshot. Phase 3 may record operational failure metadata outside this source document, but that metadata cannot change the source facts or authorize deletion.

### Reminder scope

`AppleReminderSourceSnapshotV1.source` contains:

| Field | Wire type | Meaning |
|---|---|---|
| `sourceContainerId` | non-empty opaque string | Selected Reminder list identifier, meaningful only with `bridgeId`. |
| `allowsContentModifications` | boolean | Observed container capability. It is not write authorization. |

The v1 Reminder scope means all accessible Reminder records matched from that one selected list. It has no hidden completion, temporal, recurrence, title, or attention filter. If Phase 3 needs a narrower Reminder query, that query must become an explicit versioned scope; it cannot silently reuse v1 and still claim authoritative absence.

### Calendar scope and window

`AppleCalendarSourceSnapshotV1.source` contains:

| Field | Wire type | Meaning |
|---|---|---|
| `sourceContainerId` | non-empty opaque string | Selected Calendar container identifier, meaningful only with `bridgeId`. |
| `allowsContentModifications` | boolean | Observed container capability. It is not write authorization. |
| `isSubscribed` | boolean | Distinguishes subscribed Calendar scope from other read-only scope. |

The Calendar snapshot additionally contains a strict `window`:

| Field | Wire type | Meaning |
|---|---|---|
| `start` | offset-bearing ISO 8601 instant | Inclusive query boundary. |
| `end` | offset-bearing ISO 8601 instant | Exclusive query boundary; it must be later than `start`. |
| `timeZone` | recognized time-zone identifier | Civil-time context for local timed and all-day values. |
| `boundarySemantics` | literal `overlapStartInclusiveEndExclusive` | A retained event must overlap `[start, end)`. |

Calendar scope is therefore:

```text
bridgeId
+ entityType = calendar
+ sourceContainerId
+ events overlapping [window.start, window.end)
```

An event overlaps when its normalized start is earlier than `window.end` and its normalized end is later than `window.start`. An event ending exactly at the window start does not match. An event starting exactly at the window end does not match. An event may begin before the window or end after it; overlap, not full containment, is the declared predicate.

The validator rejects a Calendar record that does not overlap its declared scope. `window.timeZone` interprets `localTimedRange` and `allDayRange`. A `timeZoneTimedRange` carries exact offset-bearing start/end instants; its own time-zone identifier is display context and is not used to reconstruct an instant from civil text.

## 3. Version 1 records

### `AppleReminderSourceRecordV1`

| Field | Required? | Meaning and current use |
|---|---:|---|
| `localIdentifier` | yes | Bridge-and-container-scoped EventKit provenance used for conservative same-scope reconciliation. |
| `externalIdentifier` | no | Optional hint that may assist reconciliation; never a universal key. |
| `title` | no | Source title for the first Task mirror. Absence remains absence; the Bridge invents no fallback. An empty source string, when supplied, remains a string fact. |
| `start` | yes | Explicit Reminder temporal union, including the `absent` variant. |
| `due` | yes | Explicit Reminder temporal union, including the `absent` variant. |
| `isCompleted` | yes | Current Apple completion state needed by the one-way Task mirror. |
| `completionDate` | no | Current completion instant when supplied. It is rejected on an incomplete Reminder and is not completion history. |

`start` and `due` are structurally present so absence is explicit rather than confused with a dropped key. Their variants are:

```text
absent
dateOnly(localDate)
localDateTime(localDateTime)
timeZoneDateTime(localDateTime, timeZone)
```

### `AppleCalendarSourceRecordV1`

| Field | Required? | Meaning and current use |
|---|---:|---|
| `localIdentifier` | yes | Bridge-and-container-scoped Calendar item provenance. |
| `eventIdentifier` | no | Separate Calendar event provenance fact. It is not folded into the local or external identifier. |
| `externalIdentifier` | no | Optional reconciliation hint; never a universal key. |
| `title` | no | Source title for the first Commitment mirror. Absence remains absence. |
| `temporal` | yes | Required timed or exclusive all-day range. |
| `occurrenceDate` | no | Separate offset-bearing provenance fact for an expanded recurring occurrence. |
| `isDetached` | yes | Prevents a detached occurrence from being silently treated as an ordinary generated occurrence during first-mirror reconciliation. Phase 2A did not observe `true`. |
| `status` | yes | Normalized `none`, `confirmed`, `tentative`, or `canceled` state so cancellation can be represented without relying on absence. |

Calendar temporal variants are:

```text
localTimedRange(startLocalDateTime, endLocalDateTime)
timeZoneTimedRange(start instant, end instant, timeZone)
allDayRange(startDate, exclusive endDate)
```

Timezone-qualified Calendar start/end values are exact offset-bearing instants copied from the EventKit `Date` meaning. Civil display values are derived from each instant plus `timeZone`; local civil strings are not serialized as substitutes for exact-time identity.

The contract supports `tentative` and `canceled` status, detached occurrences, local timed ranges, and multi-day all-day ranges. Phase 2A observed only `none`/`confirmed`, non-detached records, timezone-qualified timed records, and a single-day all-day source case. Contract support does not rewrite those empirical classifications.

## 4. Field inclusion and exclusion matrix

The classification labels in this table are exhaustive for v1:

- **required in v1**;
- **optional in v1 with a current use**;
- **deferred extension**;
- **excluded for privacy or lack of need**.

| Phase 2A evidence field or contract coordinate | Classification | Rationale |
|---|---|---|
| snapshot schema version | required in v1 | Rejects unsupported wire meaning. |
| snapshot entity type | required in v1 | Selects an explicit Reminder or Calendar document. |
| opaque Bridge identity | required in v1 | Scopes every Apple identifier without exposing a hardware name. |
| capture time | required in v1 | Defines when the successful facts were observed. |
| matched count | required in v1 | Proves whether retained records cover the declared scope. |
| truncation flag | required in v1 | Prevents an incomplete retained set from authorizing absence. |
| ordered retained records | required in v1 | Gives caps deterministic, non-attention meaning. |
| per-record `entityType` from probe models | excluded for privacy or lack of need | Redundant inside one entity-scoped snapshot. |
| selected container identifier | required in v1 | Defines the Bridge-scoped source boundary. |
| container mutability | required in v1 | Preserves observed source capability and prevents later code from guessing writability. It grants no write authority. |
| Calendar subscription state | required in v1 | Distinguishes subscribed read-only scope from other read-only scope. |
| Reminder subscription state | excluded for privacy or lack of need | No distinct Reminder v1 use was established. |
| normalized container/provider category (`calendarType`) | deferred extension | No first-mirror reconciliation or Board use requires it. |
| normalized account/provider category (`sourceType`) | deferred extension | No first-mirror use requires it. |
| source/account identifier | excluded for privacy or lack of need | Container identity is sufficient; account scope would add private provenance. |
| container title | excluded for privacy or lack of need | Source selection remains on the Bridge; Core does not need a private list/calendar name. |
| source/account title | excluded for privacy or lack of need | Private account naming has no v1 use. |
| local item identifier | required in v1 | Necessary scoped provenance; durability remains unresolved. |
| external identifier | optional in v1 with a current use | Conservative reconciliation hint when present. |
| Calendar event identifier | optional in v1 with a current use | Separate Calendar provenance hint. |
| record title | optional in v1 with a current use | Supplies Task or Commitment display content without fallback fabrication. |
| creation date | deferred extension | No current mirror decision depends on source age. |
| modification date | deferred extension | Phase 3 may revisit conflict diagnostics, but v1 snapshot replacement does not need it. |
| Reminder start | required in v1 | Preserves earliest relevance, including explicit absence. |
| Reminder due | required in v1 | Preserves date-only and timed due meaning, including explicit absence. |
| Reminder completion state | required in v1 | Required by the first Task mirror. |
| Reminder completion date | optional in v1 with a current use | Preserves current completed-record evidence without claiming history. |
| Reminder raw Apple priority | deferred extension | No concrete Phase 3 use exists; it is not attention ranking. |
| Reminder recurrence structure | deferred extension | It was not observed and must not be fabricated; v1 does not need it. |
| Calendar timed start and end | required in v1 | Required for window membership, ordering, and Commitment timing. Timezone-qualified values are exact offset-bearing instants; local/floating values remain civil strings under the declared window zone. |
| Calendar all-day state plus start/end | required in v1 | Represented once by the all-day temporal discriminator and exclusive dates. |
| probe window `daysBefore` / `daysAfter` | excluded for privacy or lack of need | Discovery-policy offsets are redundant with exact v1 window boundaries and must not freeze the probe cap/window policy. |
| separate probe `isAllDay` boolean | excluded for privacy or lack of need | Redundant with the strict temporal discriminator. |
| Calendar occurrence date | optional in v1 with a current use | Provenance for expanded recurrence occurrences without recurrence grammar. |
| Calendar detached state | required in v1 | Prevents false assumptions during occurrence reconciliation. True remains empirically not tested. |
| Calendar event status | required in v1 | Represents cancellation safely. Supported values exceed the statuses observed in Phase 2A. |
| Calendar availability | excluded for privacy or lack of need | No first Commitment mirror use exists. |
| Calendar recurrence structure and nested recurrence fields | deferred extension | Phase 3 receives expanded occurrences inside its bounded window. |
| Reminder or Calendar notes | excluded for privacy or lack of need | Private content and production metadata parsing are outside Phase 2B and Phase 3 source v1. |
| metadata-block observation | excluded for privacy or lack of need | Probe diagnostic only; no metadata grammar was empirically established. |
| alarm count or alarm structures | excluded for privacy or lack of need | Apple remains notification owner; the Board does not need alarm data. |
| URL | excluded for privacy or lack of need | Private reference content with no first-mirror use. |
| location | excluded for privacy or lack of need | Private context with no first-mirror use. |
| structured-location presence | excluded for privacy or lack of need | No current use; even a presence flag adds unsupported interpretation. |
| organizer presence or identity | excluded for privacy or lack of need | Participant provenance is private and unnecessary. |
| attendee count or identities | excluded for privacy or lack of need | Participant data is private and unnecessary. |
| EventKit normalization warnings | excluded for privacy or lack of need | Probe diagnostics are not source facts. Operational errors belong outside a successful snapshot. |
| synchronization generation | deferred extension | Phase 3 transport/persistence concern, intentionally absent from v1. |
| database identifier | excluded for privacy or lack of need | Storage implementation must not leak into the source contract. |
| content hash | deferred extension | Phase 3 may choose idempotency mechanics; no v1 source meaning exists. |
| transport, authentication, or deployment metadata | excluded for privacy or lack of need | Different trust boundary and later phase. |

## 5. Identity and provenance policy

`bridgeId` is an opaque Deskboard identifier. It is not a Mac hostname, device name, account name, user name, or provider identifier. Core must not parse meaning from it.

`sourceContainerId` is meaningful only inside its supplying Bridge. A local EventKit item identifier is meaningful only inside:

```text
bridgeId + entityType + sourceContainerId
```

Even inside that coordinate, Phase 2A did not prove long-term durability or uniqueness across every occurrence and provider. The coordinate is provenance, not a universal database primary key.

`externalIdentifier` is an optional hint. Calendar `eventIdentifier` and `occurrenceDate` remain separate optional facts. No one of these fields, and no undocumented combination of them, is declared universally durable.

Reconciliation must therefore be conservative:

1. Match only when the available scoped provenance establishes the intended record with sufficient confidence.
2. Never merge two records merely because an optional external or event identifier matches.
3. When an identity change cannot be resolved without ambiguity, represent it as removal from an authoritative old scope plus addition to the new scope.
4. If the old scope is not authoritative, retain the previous record rather than inventing a removal.

False merging is prohibited. Conservative remove-plus-add behavior may lose continuity, but it does not claim two Apple facts are one when the evidence cannot establish that.

The complete ordering coordinate is also a validation coordinate, not a durable primary key. If two retained records collide on that coordinate, the candidate snapshot is invalid. Core must retain the previous good scope; it must not merge, discard, or arbitrarily order the colliding records.

## 6. Temporal semantics

All calendar dates use the proleptic Gregorian calendar and must be real dates. Local date-times use exact `YYYY-MM-DDTHH:mm:ss` civil-time form and must contain real clock values. A `Z` or numeric offset in a local date-time is rejected rather than silently reclassified.

Offset-bearing instants are used where the source meaning is an instant: capture time, completion date, occurrence date, Calendar window boundaries, and timezone-qualified Calendar start/end.

Reminder date-only values remain dates. Calendar all-day values remain exclusive civil-date ranges. Neither is flattened to UTC.

Timezone-qualified Calendar ranges require exact start/end instants with end later than start. Ordering and Calendar-window overlap use those exact instants. The associated `timeZone` preserves civil display context; consumers derive display text from the instant rather than accepting an ambiguous local substitute.

Local/floating Calendar ranges remain civil values interpreted in `window.timeZone`. Both validators require each local start and end to resolve to exactly one instant. A nonexistent civil time resolves to none and fails. A repeated civil time resolves to more than one and fails. Neither language silently chooses the first or last repeated occurrence. After unique resolution, the exact end must be later than the exact start and the range must overlap the window.

All-day dates remain exclusive civil ranges interpreted in `window.timeZone`. Time-zone identifiers must be recognized by the validating platform.

The Phase 2A source pass did not observe a daylight-saving transition, ambiguous repeated civil time, or local/floating Calendar value. The exact-instant and local-rejection rules are contract-correctness decisions derived from the exact `Date` values EventKit already supplies; they are not new empirical evidence.

## 7. Deterministic ordering and retained-set meaning

Ordering is applied to the complete matched set before any safety cap. String comparisons use Unicode scalar order, not process locale.

Calendar order remains the accepted Phase 2A order:

1. exact start instant, or the uniquely interpreted local/all-day start;
2. exact end instant, or the uniquely interpreted local/all-day end;
3. source container identifier;
4. local Calendar item identifier;
5. event identifier, with absence before presence;
6. occurrence date as an exact instant, with absence before presence;
7. external identifier, with absence before presence.

Because each v1 snapshot contains one container, step 3 is constant inside that document but remains part of the provenance order across source coordinates.

Reminder order is a stable provenance order with no attention meaning:

1. source container identifier;
2. local Reminder item identifier;
3. external identifier, with absence before presence.

Reminder title, start, due, completion, and Apple priority do not affect retained order. The retained prefix is not “the most important Reminders.”

The complete Calendar and Reminder ordering coordinates must each be unique inside one snapshot. Equality is a provenance collision, not a stable tie. The validators reject the entire candidate rather than selecting from upstream order, merging records, or discarding one. Calendar occurrence date and external identifier are ordering-only tie-breakers; this use makes no durability or universal-identity claim.

The Phase 2A cap of 200 was a disposable probe safety limit. V1 does not serialize or mandate a production cap. Phase 3 may choose an operational cap, but it must sort first, report exact `matchedCount`, set `truncated`, and preserve the semantics here.

## 8. Count, truncation, completeness, and deletion

The runtime invariants are:

```text
matchedCount >= records.length

truncated = false  => matchedCount == records.length
truncated = true   => matchedCount > records.length
```

A valid non-truncated snapshot is authoritative for absence only inside its exact declared scope. It may say that a previously mirrored record in that same scope is no longer present.

The valid empty case is explicit: `matchedCount: 0`, `records: []`, and `truncated: false`. After strict and semantic validation, an empty Reminder or Calendar snapshot authorizes removal of every previously mirrored record inside only that exact scope.

A valid truncated snapshot is an incomplete retained prefix. It may update or add records that are present, but it must never authorize absence, removal, or deletion of an unseen record.

A malformed, failed, interrupted, partially decoded, or semantically invalid document is not a snapshot at all. It authorizes no replacement and no absence inference.

This rule is the central reconciliation invariant:

> Unseen is absent only after a successful, strict, non-truncated snapshot covers the exact scope in which absence is claimed.

## 9. Phase 3 atomic replacement rules

Phase 3 must implement these rules without changing their meaning:

1. Receive a complete candidate document before mutating the mirror.
2. Reject unsupported versions, unknown keys, malformed temporal values, invalid counts, invalid order, duplicate ordering coordinates, and out-of-window Calendar records.
3. Treat a failed or partial transfer as no candidate document.
4. For a valid truncated candidate, retain the previous good source scope and do not delete unseen records. Present records may be staged only under an explicitly designed non-destructive policy.
5. For a valid non-truncated candidate, atomically replace only the declared scope.
6. For Calendar, a shifted window may remove unseen records only inside the new declared window. Records outside it were not observed and cannot be called absent merely because the window moved.
7. Commit the replacement and its freshness/bookkeeping together or not at all.
8. If storage or composition fails, preserve the previous good scope.
9. Cancellation is carried as record status when supplied; it is not inferred from truncation or transport failure.

A provenance/order-coordinate collision invalidates the complete candidate and follows the same retain-previous-good-scope rule as any other semantic failure.

Synchronization generation IDs, idempotency receipts, database keys, retry state, transport envelopes, and failure/freshness storage are Phase 3 design and implementation. They must wrap or store this document without weakening its scope authority.

## 10. Strict validation strategy

TypeScript uses strict Zod objects at every promised object boundary and discriminated temporal unions. Semantic refinements validate dates, clocks, exact instants, zones, ranges, local-time uniqueness, completion, counts, truncation, ordering-coordinate uniqueness, and Calendar overlap. The public absence-authority helper accepts `unknown`, runs the strict union schema internally, and returns authority only after successful validation.

Swift uses three layers:

1. a narrowly scoped JSON object walk rejects `null` and any unknown key at the snapshot, scope, window, record, and temporal-variant levels;
2. `JSONDecoder`/`Codable` enforces concrete field types and enum values;
3. pure semantic validation enforces the same date, exact-instant, local-time uniqueness, range, count, completion, scope, truncation, and ordering-collision rules as Zod.

Codable success by itself is never treated as strict wire validation.

Swift returns a `ValidatedAppleSourceSnapshotV1` wrapper only after all three layers pass. Only that wrapper exposes `absenceIsAuthoritative`; raw Codable snapshot structs do not.

Both implementations enumerate the exact same 15 valid and 24 invalid fixture names. Swift additionally encodes every valid decoded model and passes the result back through the strict decoder. The valid inventory includes complete empty Reminder and Calendar scopes and an exact-instant range whose endpoints share a repeated civil clock reading on opposite sides of an offset transition. The invalid inventory includes ambiguous/nonexistent local times and duplicate complete ordering coordinates. The existing Phase 2A test separately preserves the exact twelve accepted EventKit evidence files and never reads `private-fixtures/`.

## 11. Privacy rationale

V1 exposes only selected-container identity and the minimum Task/Commitment facts needed for a one-way mirror. It carries no source title, account title, account identifier, hardware name, note, URL, location, alarm, participant detail, recurrence grammar, or probe diagnostic.

Container identifiers and item identifiers are still sensitive provenance even when opaque. They belong only inside the private Bridge-to-Core boundary planned for Phase 3. Committed examples use synthetic values and must never be replaced with private exports.

Mutability and subscription are capability facts, not permission to write. Apple Calendar and Reminders remain authoritative. Version 1 defines no Apple mutation.

## 12. Unresolved cases and versioning policy

The following remain unresolved or empirically not tested:

- identifier changes after edits, synchronization, relaunch, or cross-device propagation;
- duplicate external identifiers and duplicate provenance coordinates;
- moves between source containers;
- true detached Calendar exceptions;
- Calendar cancellation, tentative status, and decline behavior from selected sources;
- local/floating timed EventKit values from selected sources;
- source-observed daylight-saving transitions and repeated civil times; v1 preserves exact timezone-qualified instants and rejects ambiguous local values without claiming new empirical evidence;
- multi-day all-day values from selected sources;
- Reminder recurrence and repeated completion history;
- provider behavior beyond the selected CalDAV and subscribed cases;
- live source disappearance;
- the eventual Phase 3 operational cap.

Unobserved support remains contract capability, not empirical fact, only where v1 needs a safe semantic branch. No Reminder recurrence shape is fabricated.

V1 objects are strict. Adding a field, temporal variant, enum value, scope filter, or changed boundary meaning requires a new schema version and new shared fixtures. Consumers must reject unsupported versions rather than ignore new meaning. A future version may share genuinely identical primitives, but it must not turn Reminder and Calendar documents into a generic adapter payload.
