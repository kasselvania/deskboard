# Atomic Apple Source Mirror

## Purpose and boundary

Phase 3A adds one isolated Core persistence boundary for the accepted
`AppleReminderSourceSnapshotV1` and `AppleCalendarSourceSnapshotV1` documents.
It proves that Core can validate, sequence, store, and atomically replace Apple
source facts without deleting facts the candidate did not authoritatively
observe.

The boundary is an internal synchronous service. It has no HTTP route, Bridge
transport, EventKit conversion, Board composition, scheduler, deployment
configuration, or Apple write path. The Phase 1 Board remains fixture-backed.

The apply input is:

```ts
{
  snapshot: unknown;
  sourceRevision: number;
}
```

`snapshot` is accepted only after the strict Phase 2B runtime union validates
it. `sourceRevision` must be a positive safe integer. It is Core/Bridge delivery
metadata and is not added to either v1 source document.

## SQLite schema and migrations

The mirror uses the Node 24 built-in `node:sqlite` `DatabaseSync` API. It adds
no database package, ORM, migration framework, workspace, or dependency.

Migrations are immutable, ordered source entries in
`apps/api/src/apple-source-mirror/migrations.ts`. A strict
`apple_source_mirror_migrations` ledger records each positive version and its
stable name. The runner uses `BEGIN IMMEDIATE`, rejects unknown or renamed
ledger entries, applies each missing migration once, and can run repeatedly on
an existing database. Every mirror connection enables and verifies SQLite
foreign-key enforcement before migrations run. The owner closes each
connection deterministically; close is idempotent.

Version 1 creates these strict tables:

| Table | Purpose and principal constraints |
|---|---|
| `apple_source_scopes` | One row per `(bridge_id, entity_type, source_container_id)`. The primary key is the revision scope. Positive accepted revision, lowercase 64-character SHA-256 digest, nonnegative matched count, Boolean integers, and entity-specific Calendar nullability are checked. A Calendar row must carry a valid ordered window and the exact `overlapStartInclusiveEndExclusive` boundary literal; a Reminder row must carry no Calendar metadata. |
| `apple_reminder_records` | Validated Reminder records for an accepted whole-scope replacement. Rows reference their exact source scope and carry positive source revision, nonnegative retained order, local provenance, and canonical record JSON. |
| `apple_calendar_records` | Validated Calendar occurrence records, including the accepted source revision and order, temporal kind, interpretation zone, canonical record JSON, and interpreted start/end epoch milliseconds with `end > start`. Rows reference their exact source scope. |

Calendar overlap columns have a scope/range index. Reminder and Calendar facts
remain in separate tables; there is no generic payload table. Persisted JSON is
created only from accepted parsed records. Every record JSON value is parsed
and strictly revalidated with its Phase 2B record schema on read, then checked
against its indexed provenance and Calendar range columns. The original
unvalidated candidate document is never persisted or hashed.

Local database files, SQLite journals and WAL/SHM sidecars, dumps, and backups
remain ignored. Phase 3A adds no backup or restore automation.

## Revision and normalized digest

The operational revision coordinate is exactly:

```text
bridgeId + entityType + sourceContainerId
```

The Bridge ID remains opaque. If a future Bridge loses its revision history or
is reset, it must use a new opaque `bridgeId`; Core does not guess that two
revision sequences are continuous.

After strict validation, Core canonicalizes the parsed source document by
sorting object keys recursively while preserving array order and JSON scalar
values. It hashes those normalized bytes with SHA-256. Optional absent values
remain absent. Because Phase 2B already enforces deterministic retained-record
ordering, the digest represents the complete accepted document without using
the original request bytes.

Within one revision coordinate:

- a greater revision may apply;
- an equal revision with the same digest is `unchangedDuplicate`;
- an equal revision with a different digest is
  `rejectedRevisionConflict`;
- a lower revision is `rejectedStale`;
- a truncated or invalid candidate is non-applied and never advances the
  revision.

Duplicate, stale, conflict, truncated, and invalid outcomes do not alter the
accepted digest, capture time, Core receipt time, matched count, Calendar
window, or stored records.

## Validation before mutation

The public apply method accepts `unknown` and runs the accepted strict Phase 2B
union before opening a database transaction. Unsupported versions, unknown
keys, malformed or contradictory temporal shapes, impossible dates, invalid
ranges, out-of-window Calendar records, invalid ordering, and provenance-order
collisions return `rejectedInvalid` without mutation.

A truncated snapshot is valid source-contract data but is not authoritative
for absence. It returns `rejectedTruncated` before any database mutation or
revision lookup. A later complete candidate may therefore use the same higher
revision.

The complete result union is:

```text
applied
unchangedDuplicate
rejectedStale
rejectedRevisionConflict
rejectedTruncated
rejectedInvalid
```

Parsed outcomes contain only their result kind, entity type, and operational
revision. Invalid outcomes contain only their kind. Errors use fixed codes and
messages. Results and errors contain no titles, temporal payloads, record
identifiers, or complete snapshots, and the service emits no logs.

## One transaction per accepted apply

An authoritative candidate runs under one `BEGIN IMMEDIATE` transaction:

1. read the currently accepted revision and digest for the exact scope;
2. reject stale, duplicate, or conflicting delivery without mutation;
3. write the new scope metadata, revision, digest, capture time, receipt time,
   count, and Calendar window when present;
4. perform the entity-specific destructive replacement;
5. insert every validated retained record;
6. commit all metadata and records together.

Any SQL, conversion, clock, or test-hook failure rolls the transaction back and
surfaces only a fixed safe apply error. A narrowly named test-only hook runs
after destructive SQL. Its proof captures a previous good scope, forces a
failure after deletion, and observes that both metadata and records survive
unchanged before a later successful apply. This is not a general fault-
injection framework.

## Reminder replacement

A complete Reminder snapshot authoritatively covers exactly:

```text
bridgeId + reminder + sourceContainerId
```

Core deletes every Reminder row in that coordinate and inserts the validated
ordered candidate set in the same transaction. It does not infer identity
history, merge through EventKit hints, or affect another Bridge or list. A
complete empty snapshot commits the new scope metadata and clears all records
in that exact scope.

## Calendar overlap-window replacement

A complete Calendar snapshot authoritatively covers only records overlapping
its declared exact-instant window `[window.start, window.end)`. A stored range
overlaps when:

```text
stored.start < window.end AND stored.end > window.start
```

Core deletes only overlapping rows from the same Bridge and container, inserts
the complete validated candidate, and updates the latest accepted window in
one transaction. Rows wholly outside that window remain stored because the
candidate did not observe them. The normal read method returns only rows from
the latest accepted revision overlapping the latest accepted window; retained
out-of-window rows are available only through the narrow diagnostic/test read.

A complete empty Calendar snapshot deletes only the stored overlap region. A
later expanded window deletes and refreshes its entire larger overlap region,
including regions retained through an earlier shifted or smaller window.

Timezone-qualified event ranges use their exact offset-bearing instants.
Local/floating and exclusive all-day boundaries are interpreted in the
candidate window time zone with the accepted Phase 2B exactly-one-instant rule;
ambiguous and nonexistent civil boundaries already fail contract validation.
The interpretation zone is retained with each Calendar row so old retained
ranges can be revalidated even after the latest window zone changes.

No replacement infers continuity or merges records through
`externalIdentifier`, `eventIdentifier`, or `occurrenceDate`.

## Narrow reads and proof inventory

Phase 3A exposes only these internal reads:

- one exact source-scope summary;
- Reminder records for one exact Reminder coordinate;
- Calendar records inside the latest accepted window;
- retained Calendar records outside the latest accepted window for proof and
  diagnosis.

Tests send all 15 valid and all 24 invalid accepted Phase 2B fixtures through
the apply boundary using exact allowlists. They also prove whole-list Reminder
replacement and isolation, Calendar shifted/empty/expanded window behavior,
duplicate/stale/conflict/truncation safety, collision and invalid no-mutation,
rollback after destructive SQL, strict migrations with foreign keys, repeated
migration runs, deterministic close/reopen persistence, safe result/error
surfaces, and absence of raw request storage. All additional records and paths
are synthetic, and no test reads EventKit or `private-fixtures/`.

## Deferred work

Phase 3B remains responsible for authenticated manual Bridge delivery,
production EventKit-to-contract conversion, and the first transport boundary.
Phase 3C remains responsible for private deployment, Core composition from
mirrored facts, freshness presentation, and real-device read-only proof.

Also absent are synchronization generations, HTTP or WebSocket endpoints,
generic persistence/adapters, background work, monitoring, backup/restore,
Board changes, metadata parsing, higher-level Deskboard concepts, and every
Apple write path.
