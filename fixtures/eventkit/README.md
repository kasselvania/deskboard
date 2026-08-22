# EventKit sanitized specimens

This directory is reserved for individually reviewed, synthetic specimens generated from structural behavior actually observed through the Phase 2A EventKit probe.

Rules:

- never copy a private inspection export here;
- do not commit a bulk export;
- replace titles, notes, identifiers, container and source names, URLs, locations, timestamps, and temporal values;
- preserve only the structural fact being demonstrated;
- omit a target case when it has not been observed;
- record the observation basis in `docs/apple-eventkit-discovery.md`.

Candidate files are generated under the ignored `private-fixtures/eventkit-probe/sanitized-candidates/` directory. A human must review each candidate before a representative specimen is committed from `events/` or `reminders/`.

The proposed specimens cover observed Reminder shapes for incomplete/undated, date-only, timed, notes, priority, and completion, plus Calendar shapes for timed start/end, all-day, timezone-qualified, recurrence, read-only source, and location presence.

The following target cases were not observed and are deliberately absent:

- Reminder recurrence;
- a Reminder containing a `[deskboard:v1]` block;
- a multi-day all-day event;
- a cancelled event.

See `docs/apple-eventkit-discovery.md` for the evidence status and caveats. On 2026-08-21, the owner approved the exact twelve-file fixture set for commit after reviewing every literal value through the ignored local review packet. The unobserved multi-day all-day case remains `not tested` and has no fixture.

Phase 2B does not change or repurpose these evidence files. Its separately versioned synthetic wire fixtures live under `fixtures/apple-source-contract/v1/` and are documented in `fixtures/apple-source-contract/README.md`.

The accepted Phase 2A hold remains:

- 12 JSON files;
- 11,969 combined bytes;
- SHA-256 `d7f138203445751910fe7e995814ac9d8bf1f92d74bc632b8a43fee31598b776` over the raw bytes concatenated in the documented allowlist order.
