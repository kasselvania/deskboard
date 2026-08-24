# Truthful Local Mirror-Backed Board

Phase 3C adds an explicitly enabled, same-Mac, manually synchronized, read-only Board projection over the accepted Apple mirror and the latest accepted Bridge status. Fixture mode remains the zero-configuration default. `BoardSnapshot` v1 and the web client are unchanged.

This slice has no remote deployment, Tailscale, background process, scheduler, backup/restore, source-management UI, or Apple write path.

## Runtime configuration and lifecycle

Mirror mode requires all existing Phase 3B ingestion values plus:

```text
DESKBOARD_BOARD_MODE=apple-mirror
DESKBOARD_BOARD_TIME_ZONE=<IANA time zone>
```

The owner's actual values remain outside Git. Missing, partial, or invalid mirror-mode configuration fails startup with the single content-free `MIRROR_BACKED_BOARD_CONFIGURATION_INVALID` error. Setting no Board variables selects fixture mode. Explicit `DESKBOARD_BOARD_MODE=fixture` is also accepted only without a Board time zone.

The configured Board time zone, not the server process time zone, controls timed Reminder eligibility and every timed display projection. The API remains bound to numeric loopback through `server.ts`.

In mirror mode, `buildApp` constructs or receives one `AppleSourceMirror`, passes that same instance to source ingestion, status ingestion, and Board composition, and closes it once through the ingestion hook. No raw mirror, status, roster, or source route exists.

## Selection and freshness

Only coordinates in the latest accepted status roster are considered. Mirror rows for a deselected coordinate remain stored but disappear from the next Board immediately. A missing status document is `unavailable`; Core does not infer selection or permission from old mirror rows.

The fixed freshness duration is **15 minutes**.

An entity is `fresh` only when:

- its permission is `granted`;
- at least one source is selected;
- the status capture is no more than 15 minutes old and is not in the future;
- every selected source is `applied` or `unchangedDuplicate` with no pending revision;
- every selected source has a positive acknowledged revision and a last-acknowledged instant no more than 15 minutes old and not in the future;
- every selected source has a Core scope at exactly that acknowledged revision.

An entity with selected sources is `stale` when any required condition fails, including blocked, retry-pending, source-unavailable, missing, mismatched, or old status. An entity is `unavailable` when permission is not granted or no source is selected. Calendar and Reminders are evaluated independently.

Selected last-good rows may still contribute items while stale or permission-unavailable. Operational failure never authorizes source deletion. `updatedAt` is the oldest reported successful acknowledgement among selected coordinates that still have accepted Core data; it is `null` when no selected coordinate has accepted data.

## Reminder to Today

Core considers only records from selected Reminder scopes. A candidate must have a nonblank title, be incomplete, and have a due value or, only when due is absent, a start value. Its effective Board-local date must be today or earlier. Future, undated, completed, and blank-title Reminders stay mirrored but are omitted.

Date-only values stay civil dates. A local timed value is interpreted in the configured Board zone. A timezone-qualified Reminder is interpreted in its declared zone and projected into the Board zone. A valid source value that cannot be mapped to one unambiguous instant fails Board composition with a fixed content-free error rather than inventing an occurrence.

Candidates are ordered by:

1. timed values effective today, earliest first;
2. date-only due values effective today;
3. start-only availability effective today;
4. overdue values, most recently due or available first;
5. accepted source and record order only as a final tie-breaker.

The existing three-item cap applies after ordering. Reasons include `due at 3:00 PM`, `due today`, `available today`, `overdue from yesterday`, and `overdue N days`. Apple priority, notes, recurrence, metadata, project inference, and AI are not read or scored.

## Calendar to Next

Core considers only records from selected Calendar scopes and only the accepted rows in each latest accepted Calendar window. Retained out-of-window rows remain stored but are not candidates. A candidate must have a nonblank title, not be canceled, and have an interpreted end strictly after the injected `now`.

Candidates sort by interpreted start, interpreted end, then accepted source/record order. The existing two-item cap applies afterward. Timed exact instants are projected into the configured Board zone, including across offset transitions. All-day ranges remain their original exclusive civil dates.

Reasons and labels are deterministic:

- ongoing timed: `happening now` / `Continues today`;
- near timed start: `in N minutes`;
- later same-day timed: `later today`;
- next-day values: `tomorrow`;
- active all-day: `all day` or `continues today`;
- later values: `upcoming` with a weekday label.

Notes, locations, URLs, availability, participants, attendee or organizer facts, and recurrence grammar do not reach the composer.

## Board document, IDs, and versions

The complete result is parsed through `boardSnapshotSchema` before serving. `generatedAt` uses the injected clock. The default fixture's existing Sideways prompt is copied unchanged and is not connected to Apple data.

Client IDs are SHA-256-derived, domain-separated opaque values over scoped provenance and are emitted as a 32-hex-character suffix. Raw Bridge, container, EventKit, local, event, occurrence, and external identifiers never reach the Board.

`boardVersion` is a SHA-256-derived `apple-mirror-...` value over the served semantic sections and freshness, excluding `generatedAt`. It therefore stays stable while semantic content and freshness are unchanged. The hashed input contains only the already projected Board document; it does not contain raw source coordinates. Source titles are trimmed for eligibility and, when longer than the unchanged Board v1 limit, projected to that limit with an ellipsis while the full source fact remains untouched in the mirror.

## Content-free owner acceptance

Build first, stop any separately running API process, then run the acceptance command with the normal private mirror-mode environment:

```bash
npm run build
npm run acceptance:board --workspace @deskboard/api
```

The command constructs one in-process API with the same shared Core resource, invokes Board composition without listening on a socket, closes the resource once, discards the private Board body, and prints only:

- schema valid yes/no;
- Today and Next counts;
- Calendar and Reminders freshness;
- selected Calendar and Reminder counts;
- masked source ordinals with content-free health states.

On failure it emits the same shape with `schemaValid: false`, zero counts, unavailable freshness, and no source entries. It never prints titles, coordinates, identifiers, times, database rows, status documents, or pending envelopes.

The owner inspects the actual Board privately and responds to the agent only with:

```text
Board recognizable: yes/no
Board calm: yes/no
Today item count: <number>
Next item count: <number>
Calendar freshness: <category>
Reminders freshness: <category>
No private content shared with agent: yes/no
```

Do not provide a screenshot, accessibility tree, OCR, DOM dump, API body, mirror row, pending envelope, source-selection view, or source value.
