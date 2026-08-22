# Deskboard Apple Source Mapping v0.1

## Status

This is the **Phase 2A discovery design**. It defines the questions, ownership boundaries, and candidate interpretations that the EventKit discovery spike tested.

The observed Phase 2A inventory, caveats, omitted cases, and recommended minimum representation are recorded in [`apple-eventkit-discovery.md`](apple-eventkit-discovery.md). That report is the evidence authority; this v0.1 document remains the discovery-question design and is not retroactively converted into a final schema. The recommendation is evidence for Phase 2B issue [#8](https://github.com/kasselvania/deskboard/issues/8), not a frozen production contract.

It is not:

- a verified EventKit field inventory;
- the final Deskboard data model;
- a production Bridge contract;
- an attention-ranking specification;
- permission to begin homelab synchronization or Apple write-back.

The scope is limited to two durable Apple sources:

1. Apple Reminders;
2. Apple Calendar.

Related project documents:

- [`MANIFESTO.md`](../MANIFESTO.md)
- [`ARCHITECTURE.md`](../ARCHITECTURE.md)
- [`ROADMAP.md`](../ROADMAP.md)

---

## 1. Purpose

Phase 1 proved that Deskboard can present a small, calm, persistent field of attention. Phase 2A determines how real Apple objects can supply evidence for later contract work without turning Deskboard into a second Calendar, Reminder manager, or project-management system.

The central question is:

> What does Apple already know as a durable fact, what meaning is missing, and what is the minimum additional declaration Deskboard needs in order to interpret that fact?

The intended sequence is:

```text
Apple source object
        ↓
normalized source fact
        ↓
optional Deskboard declaration
        ↓
Deskboard-derived state
        ↓
display-ready Board item
```

Each layer has a different owner. The layers must not be collapsed during the discovery spike.

---

## 2. Governing Rules

### 2.1 Apple owns source facts

Apple Calendar remains authoritative for Calendar events.

Apple Reminders remains authoritative for ordinary reminders.

Examples of source facts include:

- title;
- notes;
- source list or calendar;
- start and due dates;
- event start and end;
- completion state;
- recurrence;
- alarms;
- source identifiers.

Deskboard may mirror these facts, but it does not silently replace them with a second editable copy.

### 2.2 Deskboard owns interpretation

Deskboard may eventually own information Apple does not naturally represent, including:

- whether an object is a Task, Open Loop, Project, or Commitment;
- a loop's preferred return window;
- the way engagement is recorded;
- project relationships and next-action roles;
- last engagement and project movement;
- attention state and the explanation for visibility.

### 2.3 A source container is not semantic truth

A Reminder list or Calendar calendar is a source container. It is useful for:

- permission and source selection;
- privacy boundaries;
- inclusion and exclusion;
- optional default mappings.

It is not automatically a Deskboard domain.

A list named `Personal`, for example, may contain administration, creative practice, relationships, health, and household maintenance. Deskboard must not assume these have the same meaning merely because Apple stores them together.

### 2.4 Recurrence is evidence, not classification

A recurring Reminder might represent:

- a strict recurring task;
- an Open Loop;
- routine maintenance;
- a scheduled obligation.

A recurring Calendar event might represent:

- a meeting;
- a class;
- an attendance-oriented practice;
- an informational calendar entry.

Recurrence alone must not promote an object into an Open Loop.

### 2.5 Importance and attention are different

**Importance** asks:

> How much does this matter if it is ignored?

**Attention** asks:

> Does this deserve space on the Board now?

A passport renewal may be important but not yet deserve attention. A low-stakes household task may deserve attention because its timing or context makes it relevant today.

The discovery spike must preserve potential inputs to attention. It must not invent a final score.

### 2.6 Every interpretation must remain explainable

Deskboard should eventually surface reasons such as:

- `due today`;
- `starts in 90 minutes`;
- `available since Monday`;
- `six days since last engagement`;
- `next action for an active project`.

Opaque numerical rankings are outside this discovery phase.

---

## 3. The Three Data Layers

### 3.1 Layer A: normalized Apple source fact

This layer records what the supported Apple API actually returned, with enough provenance to inspect and reconcile it later.

Candidate common fields include:

```text
adapter
entity type
bridge identity
local source identifier
external source identifier, when available
source container identifier
source container title
source created time
source modified time
normalized payload
```

The EventKit spike must verify which of these fields are available and how stable they are.

### 3.2 Layer B: portable Deskboard declaration

This layer expresses a small amount of user intent that Apple does not represent directly.

The Manifesto proposes a namespaced block in Reminder notes:

```text
[deskboard:v1]
key: play-music
kind: loop
mode: session
window: 2d..5d
domain: creative
[/deskboard]
```

This remains a **candidate boundary** until the discovery spike verifies:

- notes are available through the supported API;
- ordinary prose can be preserved safely;
- the block can be parsed without rewriting unrelated notes;
- metadata remains usable across Apple devices and source providers;
- persistent anchor reminders do not create unacceptable clutter in Reminders.

Portable declarations should contain stable human intent, not frequently changing state.

### 3.3 Layer C: Deskboard-derived state

This layer belongs to Deskboard Core after persistence exists.

Examples include:

- last engagement;
- completion or attendance history recorded by Deskboard;
- active timer state;
- project `last moved` time;
- paused-until state;
- calculated loop state;
- attention reasons;
- Board selection history.

These values do not belong in Reminder notes and should not be written back repeatedly to Apple.

---

## 4. Initial Interpretation Rules

These are candidate rules for the semantic layer. The discovery spike must preserve enough information to support them, but it must not implement the complete lifecycle yet.

### 4.1 Ordinary Reminder → Task

An unmarked Reminder defaults to a **Task**.

A Task is:

> A finite action for which completion is meaningful.

Examples:

- call the dentist;
- submit an estimate;
- return a library book;
- order a component.

Expected ownership:

| Concern | Owner |
|---|---|
| title, notes, dates, completion | Apple Reminders |
| Board eligibility and reason | Deskboard |
| eventual completion write-back | Apple Reminders through the Bridge, in a later phase |

An ordinary Reminder should not require Deskboard metadata merely to appear as a Task.

### 4.2 Marked Reminder → Open Loop anchor

A Reminder explicitly declared with `kind: loop` is a candidate **Open Loop anchor**.

An Open Loop is:

> Something worth returning to within a flexible interval, where engagement matters more than final completion.

Examples:

- play music;
- meditate;
- read;
- attend a community or support meeting;
- clean a workspace;
- maintain a creative practice.

An Open Loop anchor is not completed each time the activity occurs. Deskboard records an occurrence or session and derives the next state from elapsed time.

Candidate lifecycle:

```text
resting → available → calling → engaged → resting
```

The EventKit spike must not infer loops from recurrence alone.

### 4.3 Marked Reminder → Project anchor

A Reminder explicitly declared with `kind: project` is a candidate **Project anchor**.

A Project is:

> A desired outcome that requires multiple actions and continuity over time.

Examples:

- build smart blinds;
- create an indoor air-quality monitor;
- complete a password-vault migration.

Whether a Project anchor should ultimately live as a persistent Apple Reminder remains unresolved. The spike should verify the mechanics of note metadata, source lists, and stable identity, but it must not assume that an indefinitely incomplete Reminder is the final project representation.

Project state, movement history, and active/parked/waiting status remain Deskboard-owned concepts.

### 4.4 Reminder linked to Project → Task with relationship

A project action remains a Task. It is not a fourth primary kind.

Candidate declaration:

```text
[deskboard:v1]
kind: task
project: smart-blinds
role: next
[/deskboard]
```

This means:

- Apple owns the Task and its completion;
- Deskboard associates it with a Project;
- `role: next` is a semantic relationship, not an Apple priority;
- completing the Task does not automatically complete the Project.

### 4.5 Calendar Event → Commitment

A selected Calendar event defaults to a **Commitment**.

A Commitment is:

> Something tied to a real date, time, or external obligation.

Examples:

- appointment;
- meeting;
- reservation;
- class;
- all-day event.

The first mapping should be intentionally conservative. Calendar events do not need extra Deskboard metadata merely to appear as Commitments.

Cancelled, declined, all-day, recurring, and read-only events must be observed during the spike before filtering rules are finalized.

---

## 5. Reminder Field Inventory to Verify

This table records the expected semantic use of Reminder fields. Availability and exact behavior are hypotheses until verified against EventKit.

| Source concept | Preserve? | Candidate Deskboard use | Discovery questions |
|---|---:|---|---|
| local identifier | yes | source lookup and reconciliation | Is it stable across launches and edits on the same Mac? |
| external identifier | when available | cross-device reconciliation hint | When is it absent, duplicated, or changed? |
| title | yes | display title | Are there provider-specific limits or unusual values? |
| notes | yes, privately | human context and candidate metadata block | Is the full text readable? Can prose and metadata coexist safely? |
| Reminder list/container | yes | source whitelist; optional default mapping | How are list identity, mutability, and account source represented? |
| start/availability components | yes | earliest relevance; suppress premature attention | How are date-only, timed, floating, and timezone values represented? |
| due components | yes | hard temporal pressure and display reason | How are date-only and timed due values distinguished? |
| priority | yes | weak source importance hint | What values are returned, and how consistently are they used? |
| completion state | yes | current source state | How do recurring and completed instances behave? |
| completion date | yes when available | source history hint | Does EventKit expose useful history for recurring completions, or only current-item state? |
| recurrence rules | yes | preserve schedule facts | How are recurring occurrences represented and identified? |
| alarms | initially preserve only if needed | source diagnostics; not a second notification system | Is alarm information needed for Board meaning? |
| creation date | yes when available | age and diagnostics | Is it populated consistently across providers? |
| modification date | yes when available | reconciliation and recent source activity | What changes update it? |
| URL/reference | verify | optional reference context | Is it useful and safe to mirror? |
| location | verify | possible context, not initial display | Is it exposed for Reminders in selected sources? |
| tags, sections, subtasks, attachments | do not depend on | none until verified | Are these available through supported APIs at all? |

### Reminder-specific cautions

- A due date is not a semantic classification.
- A recurrence rule is not an Open Loop declaration.
- A list is not automatically a domain.
- An Apple priority is not a Deskboard attention score.
- A completion date must not be mistaken for a complete behavioral history until recurrence behavior is observed.

---

## 6. Calendar Field Inventory to Verify

| Source concept | Preserve? | Candidate Deskboard use | Discovery questions |
|---|---:|---|---|
| local identifier | yes | occurrence lookup and reconciliation | How stable is it for recurring occurrences? |
| external identifier | when available | cross-device reconciliation hint | Can separate occurrences or duplicates share it? |
| title | yes | display title | Are empty or provider-generated titles possible? |
| source calendar/container | yes | source whitelist and privacy boundary | How are subscribed and read-only calendars represented? |
| start and end | yes | ordering, active/upcoming state, duration | How are timezone changes and floating events represented? |
| all-day state | yes | distinct date-only presentation | Is the end date exclusive, and how are multi-day events represented? |
| occurrence identity/date | yes when available | distinguish recurring instances | Which identifier combination is safe for an occurrence? |
| recurrence rules | yes | preserve source schedule | How much recurrence detail is needed outside the Bridge? |
| status/cancellation | yes | exclude or label invalid commitments | Which source providers expose cancelled or tentative states? |
| availability | verify | weak context only | Is it meaningful for a personal attention surface? |
| location/structured location | verify | possible travel or preparation context | Which fields are reliably populated? |
| organizer and attendees | do not expose initially | none in the first Board | What minimum data is needed for diagnostics without mirroring private participant details? |
| notes and URL | verify | optional context/reference | Should they remain Bridge-only in the first mirror? |
| alarms | initially ignore for presentation | none; Apple remains notification owner | Is any alarm data needed for interpretation? |

### Calendar-specific cautions

- All-day events must not receive the same urgency treatment as timed appointments by default.
- A recurring event is still a Commitment unless explicitly associated with another Deskboard concept later.
- Participant data is private and unnecessary for the initial Board.
- Calendar remains the only alarm and scheduling authority.

---

## 7. Candidate Portable Metadata Matrix

The following fields already appear in the Manifesto's proposed Reminder-note block. Phase 2A was intended to verify their practicality before later contract work; the empirical report records that no qualifying source block was observed, so no parser contract is frozen.

| Field | Applies to | Purpose | Required initially? |
|---|---|---|---:|
| `key` | loop or project anchor | stable Deskboard-readable identity | candidate; verify need and collision behavior |
| `kind` | Reminder | `task`, `loop`, or `project` interpretation | only required when overriding the default Task interpretation |
| `mode` | Open Loop | how engagement is recorded | required for a Loop once loop behavior is implemented |
| `window` | Open Loop | preferred minimum and maximum return gap | required for a Loop once loop behavior is implemented |
| `domain` | any interpreted item | broad life area used for balance and filtering | optional |
| `project` | Task or Loop | relationship to a Project key | optional |
| `role` | project-linked item | candidate role such as `next` or `waiting` | optional and not yet finalized |

### Fields deliberately excluded from the first declaration

Do not add manually maintained fields for:

- current attention score;
- last engagement;
- last moved;
- total time;
- display order;
- streaks;
- missed occurrences;
- AI-generated priority;
- mutable lifecycle state.

These are derived or historical values and belong in Deskboard Core.

### Importance is not frozen as metadata

The first discovery phase should preserve Apple priority as a source fact but should **not** add a new required Deskboard `importance` field yet.

The need for a separate, slowly changing importance declaration should be evaluated after real Reminder and Calendar data is visible on the Board. Adding another field before observing the source data would increase maintenance without proving value.

---

## 8. Engagement Modes

The Manifesto defines three candidate modes for Open Loops. This is the initial meaning of “multi-modal” within the semantic model: different activities produce different kinds of evidence.

### 8.1 Completion mode

Use when a discrete occurrence is meaningful even though the broader practice repeats.

Examples:

- vacuum office;
- scrub toilets;
- clean desk.

Primary future action:

```text
Done
```

Deskboard records an occurrence. It does not create missed-instance debt.

### 8.2 Session mode

Use when time spent engaging is the meaningful evidence.

Examples:

- play music;
- read;
- meditate;
- work on a creative practice.

Primary future actions:

```text
Start
Stop
I Did This
```

### 8.3 Attendance mode

Use when showing up is the meaningful evidence.

Examples:

- class;
- community meeting;
- support meeting.

Primary future action:

```text
Attended
```

### Mode rules for Phase 2A

- Mode is user intent, not something inferred from recurrence.
- Mode applies to Open Loops, not ordinary Tasks or Calendar Commitments.
- The EventKit discovery spike records metadata text if present but does not implement engagement history.

---

## 9. Lists, Calendars, Domains, and Privacy

### 9.1 Source selection comes first

The Bridge must whitelist Reminder lists and Calendar calendars. Unselected sources remain outside Deskboard.

This is both a privacy boundary and a product boundary.

### 9.2 Domain is an optional interpretation

A Deskboard domain describes the area of life an item belongs to, such as:

- recovery and care;
- home maintenance;
- work and administration;
- creative practice;
- relationships;
- learning;
- rest and recreation.

A source container may supply a default domain only through explicit configuration. Deskboard should not silently derive a domain from a list or calendar name.

### 9.3 Domain does not determine urgency

Domains may eventually support balance and diversity on the Board. They should not become a hidden priority hierarchy where work always outranks creativity or maintenance always outranks recovery.

---

## 10. Inputs to Future Attention Selection

Phase 2A preserves the facts needed for later attention selection without finalizing a scoring system.

Candidate inputs include:

### Hard temporal inputs

- overdue Task;
- Task due today or soon;
- Calendar Commitment beginning soon;
- current all-day Commitment;
- Reminder start date has arrived.

### Open Loop inputs

- time since last Deskboard-recorded engagement;
- preferred minimum gap;
- preferred maximum gap;
- paused state.

### Project inputs

- active, waiting, or parked state;
- designated next action;
- time since meaningful movement;
- unblocked waiting item.

### Source hints

- Apple priority;
- selected list or calendar;
- recent source modification;
- recurrence rule.

### Balance inputs

- domain diversity;
- limited Board capacity;
- user-selected current focus.

The later selection policy should return a human-readable reason, not only a number.

---

## 11. Temporal Semantics to Preserve

The Bridge must not flatten all dates into UTC instants.

At minimum, the discovery output must distinguish:

```text
date-only
local date-time without a source timezone
timezone-qualified date-time
all-day event or range
```

Candidate meanings:

- Reminder start date: earliest relevance;
- Reminder due date: expected completion constraint;
- Calendar start/end: commitment timing;
- all-day event: date context, not automatically immediate urgency.

The spike must document how EventKit represents each shape and where timezone information is absent.

---

## 12. Required Discovery Examples

The EventKit spike should observe real local examples, then commit only sanitized equivalents.

### Reminder examples

- ordinary incomplete Reminder without metadata;
- date-only Reminder;
- timed Reminder;
- Reminder with ordinary prose in notes;
- Reminder with a candidate `[deskboard:v1]` block;
- recurring Reminder;
- completed Reminder;
- Reminder from a read-only or unusual source, when available;
- Reminder with priority;
- Reminder without due or start dates.

### Calendar examples

- timed event;
- all-day event;
- multi-day all-day event;
- timezone-qualified event;
- recurring event occurrence;
- cancelled or declined event, when available;
- read-only or subscribed calendar event;
- event with location;
- event spanning a daylight-saving transition, when practical.

Sanitized fixtures must replace titles, notes, identifiers, locations, attendee data, and account details with synthetic values.

---

## 13. Questions the EventKit Spike Must Answer

### Identity and reconciliation

1. Which local and external identifiers are available for each entity?
2. Which identifiers change after edits, synchronization, or recurring-instance expansion?
3. How should a recurring event occurrence be identified?
4. Can duplicate items share an external identifier?

### Reminders

1. How are date-only and timed start/due components represented?
2. Are notes fully available across selected sources?
3. How do recurrence and completion interact?
4. Is any useful history of repeated completions observable?
5. Which visible Reminders features are absent from EventKit?
6. How are priority values encoded?
7. How are list mutability and account source represented?
8. Does a persistent Loop or Project anchor create an acceptable experience in the native Reminders app?

### Calendar

1. How are all-day and multi-day event boundaries represented?
2. How are recurring occurrences and exceptions represented?
3. Which status and cancellation values occur in practice?
4. How are floating and timezone-qualified events distinguished?
5. Which location fields are useful and consistently populated?
6. How should read-only, subscribed, birthday, and holiday calendars be filtered?

### Metadata block

1. Can the block be parsed while preserving prose before and after it?
2. How should malformed or duplicate blocks fail?
3. Should unknown fields be preserved for forward compatibility?
4. Is a stable `key` necessary, or can Deskboard identity be stored only in Core?
5. Should Project anchors live in Reminders at all?

---

## 14. Decisions Frozen for the Spike

The following decisions are sufficiently established to guide implementation:

- the spike is read-only;
- only Calendar and Reminders are in scope;
- source containers are explicitly selected;
- Apple source objects are normalized before semantic mapping;
- date-only, local-time, timezone-qualified, and all-day values remain distinct;
- ordinary Reminders default to Tasks;
- Calendar events default to Commitments;
- recurrence does not automatically create an Open Loop;
- dynamic Deskboard state is not written into Apple notes;
- committed examples contain only synthetic data;
- no production Bridge-to-Core synchronization is built in this phase.

---

## 15. Decisions Deliberately Not Frozen

The discovery spike must provide evidence before the project decides:

- the final Bridge-to-Core schema;
- whether Project anchors should live in Reminders;
- whether a dedicated `Deskboard Loops` list is the best native organization;
- the final note-block grammar and parser behavior;
- whether Deskboard needs a separate importance declaration;
- how attention inputs are weighted;
- how much completion history Apple can provide;
- which Calendar sources and event types should be excluded by default;
- whether the Phase 3 mirror should initially support loop/project metadata or only Tasks and Commitments.

---

## 16. Phase 2A Evidence and Phase 2B Handoff

Phase 2A implemented the minimal EventKit discovery utility and produced:

1. a controlled source-selection interface;
2. read-only access to Calendar and Reminders;
3. a bounded local inspection/export path;
4. documented permission behavior;
5. an owner-approved allowlist of sanitized fixtures for observed cases;
6. an updated, verified field inventory with unavailable and `not tested` cases;
7. a recommendation for the smallest representation Phase 2B should evaluate.

Issue [#8](https://github.com/kasselvania/deskboard/issues/8) owns Phase 2B contract minimization, deterministic snapshot semantics, and reconciliation policy after Phase 2A is accepted and merged. Phase 2A evidence does not freeze that contract.

Phase 2A stops before:

- homelab deployment;
- network synchronization;
- SQLite;
- Apple write-back;
- Open Loop history;
- Project lifecycle implementation;
- attention ranking;
- changes to the current Board interaction model.

The purpose of Phase 2A is to replace assumptions with observed source behavior. It is not to implement the entire semantic layer, Phase 2B, or the Phase 3 mirror.
