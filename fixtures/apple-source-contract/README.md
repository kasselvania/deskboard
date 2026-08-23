# Apple source contract fixtures

This tree contains the synthetic, separately versioned wire fixtures for Phase 2B. They are contract examples, not EventKit observations and not production source data. The accepted Phase 2A evidence remains separately held under `fixtures/eventkit/`.

Both the TypeScript and Swift tests enumerate the exact JSON allowlists below. Every valid file must pass both validators, every invalid file must fail both validators, and an unexpected JSON file fails the inventory test.

## Version 1 valid allowlist

Reminder snapshots:

- `v1/valid/reminder-empty.json`
- `v1/valid/reminder-undated.json`
- `v1/valid/reminder-date-only.json`
- `v1/valid/reminder-local-date-time.json`
- `v1/valid/reminder-time-zone-date-time.json`
- `v1/valid/reminder-completed.json`
- `v1/valid/reminder-truncated.json`

Calendar snapshots:

- `v1/valid/calendar-empty.json`
- `v1/valid/calendar-local-timed.json`
- `v1/valid/calendar-time-zone-timed.json`
- `v1/valid/calendar-time-zone-offset-transition.json`
- `v1/valid/calendar-all-day-single-day.json`
- `v1/valid/calendar-recurring-occurrence.json`
- `v1/valid/calendar-subscribed-read-only.json`
- `v1/valid/calendar-truncated.json`

The 15-file valid inventory includes complete empty Reminder and Calendar scopes. Each empty snapshot has zero matches, no retained records, is non-truncated, and authorizes absence after strict validation. The offset-transition fixture preserves the same repeated civil clock reading on two different offsets as distinct exact Calendar start/end instants, without serialized local substitutes. The recurring-occurrence fixture carries occurrence provenance but no recurrence grammar. The truncated fixtures are valid incomplete retained sets and are deliberately not authoritative for absence. The subscribed fixture proves scope capability facts without a source or account title.

## Version 1 invalid allowlist

- `v1/invalid/unsupported-schema-version.json`
- `v1/invalid/unknown-top-level-key.json`
- `v1/invalid/unknown-nested-key.json`
- `v1/invalid/wrong-entity-discriminator.json`
- `v1/invalid/contradictory-temporal-fields.json`
- `v1/invalid/impossible-date.json`
- `v1/invalid/impossible-clock-time.json`
- `v1/invalid/offset-in-local-date-time.json`
- `v1/invalid/ambiguous-local-date-time.json`
- `v1/invalid/nonexistent-local-date-time.json`
- `v1/invalid/timed-end-not-after-start.json`
- `v1/invalid/all-day-end-not-after-start.json`
- `v1/invalid/incomplete-reminder-with-completion-date.json`
- `v1/invalid/matched-count-below-records-length.json`
- `v1/invalid/non-truncated-count-inconsistency.json`
- `v1/invalid/truncated-without-omission.json`
- `v1/invalid/malformed-calendar-window.json`
- `v1/invalid/unrecognized-time-zone.json`
- `v1/invalid/excluded-participant-field.json`
- `v1/invalid/calendar-record-outside-window.json`
- `v1/invalid/reminder-record-order.json`
- `v1/invalid/calendar-record-order.json`
- `v1/invalid/duplicate-reminder-order-coordinate.json`
- `v1/invalid/duplicate-calendar-order-coordinate.json`

The 24-file invalid inventory proves, among the other strict and semantic failures, that ambiguous/nonexistent local Calendar times and duplicate complete Reminder/Calendar ordering coordinates are rejected. The excluded-participant specimen proves that privacy-excluded Calendar participant data is rejected as an unknown record key. No fixture contains a source title, account title, hardware name, note, URL, location, participant identity, transport field, database field, or synchronization-generation field.
