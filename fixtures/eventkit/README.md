# EventKit sanitized specimens

This directory is reserved for individually reviewed, synthetic specimens generated from structural behavior actually observed through the Phase 2 EventKit probe.

Rules:

- never copy a private inspection export here;
- do not commit a bulk export;
- replace titles, notes, identifiers, container and source names, URLs, locations, timestamps, and temporal values;
- preserve only the structural fact being demonstrated;
- omit a target case when it has not been observed;
- record the observation basis in `docs/apple-eventkit-discovery.md`.

Candidate files are generated under the ignored `private-fixtures/eventkit-probe/sanitized-candidates/` directory. A human must review each candidate before a representative specimen is copied into `events/` or `reminders/`.

No runtime-derived specimens are committed yet because the local Calendar and Reminders permission/inspection pass has not been performed. This is an explicit discovery gap, not evidence that the fields are unavailable.
