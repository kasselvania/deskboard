# Deskboard: Project Philosophy and Shape

**Working tagline:** *Remember. Return. Begin.*

## 1. Working Definition

**Deskboard is a quiet, local-first attention layer that turns the trusted systems already used in daily life into a small, intentional view of what deserves attention now.**

It does not replace Apple Reminders, Calendar, Notes, Home Assistant, or other permanent tools. Those systems remain the durable record.

Deskboard adds what they generally do not:

- elapsed time
- context
- relationships between tasks and projects
- awareness of neglected activities
- a record of engagement
- a gentle path back into something
- protection from notification overload
- a deliberately limited field of attention

Its purpose is not to display everything. Its purpose is to make it easier to remember, return, and begin.

---

## 2. The Problem Deskboard Is Solving

The problem is not a lack of applications.

There are already excellent applications for reminders, calendars, notes, home controls, media, health, projects, and communication. The problem is that using them often requires remembering where the information lives, opening a distracting device, navigating into the correct application, and sorting the important item from everything else competing for attention.

For someone with ADHD, that sequence contains several opportunities to lose the original intention.

A reminder may exist but never re-enter awareness at the right moment. A project may remain important but disappear because it has no deadline. A creative activity may be deeply valued but continually lose to louder obligations. A recurring household task may become either invisible or an endlessly overdue checkbox.

Deskboard should address these gaps without becoming another demanding system that must itself be maintained.

The central question is:

> **Given everything the system knows, what small amount of information would genuinely help right now?**

---

## 3. The Three Parts of the System

### The Bridge

The Bridge connects Deskboard to durable source systems:

- Apple Reminders
- Apple Calendar
- selected references from Apple Notes
- Shortcuts or agent commands
- weather
- Home Assistant
- future sensors and household services

The Bridge reads from those systems and writes back to them when appropriate.

### The Personal Dossier

The Personal Dossier is the local interpretation layer.

It stores the information that does not naturally belong in Calendar or Reminders:

- loop definitions
- preferred recurrence windows
- last engagement
- session history
- project state
- project relationships
- active-work limits
- snoozes and pauses
- display history
- lightweight contextual metadata

The Dossier should remain small, transparent, and portable.

### The Board

The Board is the visible interface.

It presents a tightly curated selection from the Dossier and source systems. It may run on an iPad, Steam Deck, Android tablet, hacked Switch, BOOX device, Kindle, Raspberry Pi display, or ordinary browser.

The technology may be web-based. The product behavior should not feel like the open web.

---

## 4. Project Immutables

These principles should be treated as the project’s constitution. Features may change; these should change only after deliberate reconsideration.

### 4.1 Attention is the scarce resource

Deskboard is not trying to gather more information. It is trying to protect attention.

The backend may know about hundreds of things. The default display should show only a handful.

### 4.2 Existing tools remain the source of truth

Appointments remain Calendar events.

Concrete tasks remain Reminders.

Long-form thinking remains in Notes or another chosen writing system.

Home devices remain managed by the appropriate home platform.

Deskboard augments these tools instead of creating a new silo that must be continually reconciled.

### 4.3 Elapsed time is context, not a verdict

“Six days since you played music” is useful information.

“You failed your six-day streak” is not.

Deskboard should expose time honestly without turning it into moral judgment.

### 4.4 Returning counts

Beginning again is meaningful progress.

A project that was untouched for three weeks is not ruined. A five-minute return can update its state and restore momentum.

Deskboard should make re-entry easier rather than making absence feel expensive.

### 4.5 Joy, recovery, and identity are legitimate

The system must not optimize only for work, chores, and externally imposed obligations.

Meditation, meetings, music, reading, creative play, relationships, rest, and exploration deserve representation because they are part of a meaningful life—not because they produce output.

At least one available space on the Board should be capable of surfacing something nourishing rather than merely urgent.

### 4.6 The Board is not a backlog

The default display must never become a complete list of everything unfinished.

A backlog may exist elsewhere. Deskboard presents a field of attention.

### 4.7 Every surfaced item should be explainable

Deskboard should be able to say why something is visible:

- due today
- appointment in two hours
- six days since last engagement
- active project untouched for nine days
- waiting item now unblocked
- back door unlocked after bedtime

There should be no mysterious AI score that the user is expected to trust.

### 4.8 Interaction should be tiny

Most actions should take one tap or one sentence:

- Done
- Start
- Stop
- I worked on this
- Not today
- Park
- Resume
- Set next action

The system should not require a project-management session before a project can be worked on.

### 4.9 The Board should never scold

No broken streak celebrations.

No red walls of overdue items.

No accumulating debt for recurring activities.

No language such as “failed,” “behind,” or “unproductive.”

Actual hard commitments may be labeled overdue. Open loops should use gentler states such as **available**, **calling**, or **paused**.

### 4.10 Local-first and privacy-conscious

The system should keep personal context on trusted local hardware whenever practical.

Only the information necessary for a given display or integration should be exposed. Family-facing screens should not automatically inherit private work, recovery, health, or calendar details.

Changes made through agents or integrations should be recorded in an audit history.

### 4.11 Hardware is replaceable

Deskboard must not be “the iPad app,” “the BOOX app,” or “the Pi display.”

The information model and core behavior should be independent of the display.

Each device is a rendering profile, not a separate product.

---

## 5. What Deskboard Is Not

Deskboard is not:

- a replacement for Apple Reminders
- a full project-management suite
- another notification center
- a general-purpose Home Assistant dashboard
- an app launcher
- an analytics platform for personal productivity
- a gamified habit tracker
- a system that requires everything in life to be categorized
- an opaque AI life coach
- a permanent record of every minute
- a wall of widgets
- a reason to duplicate information already stored elsewhere

The system should know more than it displays and require less interaction than it enables.

---

## 6. The Core Information Model

| Concept | Meaning | Typical source |
|---|---|---|
| **Commitment** | Something tied to a real time, date, or external obligation | Calendar or dated Reminder |
| **Task** | A concrete action that can be completed | Reminders |
| **Open Loop** | Something worth returning to within a flexible interval | Reminder anchor plus Dossier metadata |
| **Project** | A larger effort with a state, next action, and history of movement | Dossier plus linked Reminders/Notes |
| **Session** | Evidence that time or attention was spent on a loop or project | Deskboard |
| **Signal** | Background information that matters primarily when abnormal | Home, weather, sensors, homelab |
| **Sideways Prompt** | A non-demanding creative interruption or perspective shift | User-provided prompt source |

### 6.1 Commitments

Commitments are rigid because reality is rigid.

Examples include appointments, meetings, deadlines, reservations, and scheduled obligations. Calendar and native Reminder alerts should continue handling hard notifications.

Deskboard supplements those systems by keeping the next few meaningful commitments persistently visible.

It should not become the only alarm for something important.

### 6.2 Tasks

Tasks are discrete actions:

- call the dentist
- put out the trash
- order ESP32 boards
- submit an estimate
- buy cleaning supplies

Completing one from Deskboard should eventually complete the actual Apple Reminder.

### 6.3 Open Loops

An Open Loop represents something that matters repeatedly but does not fit a strict recurring due date.

Examples include:

- meditate
- attend a support or community meeting
- clean the desk
- vacuum the office
- scrub the toilets
- play with music equipment
- read
- contact a friend
- review finances
- spend time on a creative practice

A recurring task says:

> This was due Tuesday and is now late.

An Open Loop says:

> This matters to you, and it has been a while since you returned to it.

That difference is foundational.

### 6.4 Projects

A Project is not a giant checkbox.

A Project should have:

- a stable name
- a state
- one next action
- a `last moved` time
- optional linked reminders
- optional reference material
- optional sessions
- a concise note about where things were left

Project states should remain simple:

- **Active**
- **Waiting**
- **Parked**
- **Complete**

The number of Active projects should be intentionally limited. Three is a strong initial default.

Progress should initially be represented through evidence rather than fake percentages:

- touched today
- one session this week
- next action defined
- waiting for delivery
- nine days since movement
- prototype assembled

### 6.5 Sessions

A Session records engagement.

It is not intended to become billing-grade time tracking.

A session needs only:

- what was engaged with
- when it began
- when it ended
- calculated duration
- optional short note

Examples:

> Play music — 34 minutes  
> Deskboard — 51 minutes  
> Meditation — 12 minutes  
> Clean office — 23 minutes

A session updates the associated loop or project’s `last touched` value.

The timer is evidence of engagement, not surveillance.

### 6.6 Signals

Signals should remain quiet unless they become meaningful.

Normal state:

> 71° inside · air good · doors locked · home normal

Exceptional state:

> Back door unlocked since 11:18 PM

Potential signals include:

- indoor temperature
- outdoor temperature
- air quality
- thermostat state
- door-lock state
- camera availability
- backup health
- network availability
- future ESP32 sensors
- future blind-controller state

Deskboard should summarize these systems, not reproduce every control and sensor.

### 6.7 The Sideways Prompt

A small, optional region may display one Oblique Strategy or another short prompt supplied by the user or an authorized source.

This prompt is deliberately unrelated to the task system.

It should:

- rotate no more than once per day unless manually changed
- occupy otherwise-unused space
- disappear when higher-value information needs the room
- never become a task
- never be scored
- never be tracked
- never generate a notification

Its purpose is simply to create a small interruption in habitual thinking.

---

## 7. Open Loop Semantics

Each loop has a preferred window rather than a hard due date.

For example:

```text
Play music
Preferred window: every 2–5 days
Last engaged: 6 days ago
```

The two ends of the window mean different things:

- **Minimum gap:** do not begin resurfacing this too soon.
- **Preferred maximum:** after this point, gradually give it more prominence.

### Loop States

**Resting**  
The minimum gap has not elapsed. The loop remains hidden.

**Available**  
The loop is within its preferred window. It may appear if there is room.

**Calling**  
The preferred maximum has passed. It becomes a stronger candidate for the Board.

**Paused**  
The user has intentionally removed it from consideration.

There is no accumulating debt. Completing an activity does not create missed instances for every prior day.

### Loop Modes

A minimal first version needs only three modes.

#### Completion

Used for discrete maintenance activities.

Examples:

- vacuum office
- scrub toilets
- clean desk

Primary action: **Done**

#### Session

Used when spending time is the meaningful outcome.

Examples:

- play music
- program
- read
- meditate
- work on a project

Primary action: **Start**

Secondary action: **I did this**

#### Attendance

Used for an event or practice where showing up is the meaningful outcome.

Examples:

- meeting
- class
- community event
- support activity

Primary action: **Attended**

These distinctions are enough to cover much of daily life without building a complicated habit engine.

---

## 8. Metadata in Apple Reminders

Apple Reminders can act as the durable, human-readable anchor for tasks, loops, and selected project relationships.

A dedicated list such as **Deskboard Loops** can contain persistent Reminder records. Unlike ordinary tasks, these anchor reminders remain incomplete. Recording a loop occurrence updates Deskboard’s history rather than completing the anchor.

The Notes field can contain ordinary human notes along with a namespaced metadata block.

### Proposed Metadata Format

```text
[deskboard:v1]
key: play-music
kind: loop
mode: session
window: 2d..5d
domain: creative
[/deskboard]
```

The format should be:

- readable by a person
- easy for an agent or Shortcut to create
- strictly parseable
- versioned
- tolerant of unknown future fields
- safe to mix with normal prose

### Stable Initial Fields

| Field | Purpose |
|---|---|
| `key` | Stable human-readable identifier |
| `kind` | `task`, `loop`, or `project` |
| `mode` | `completion`, `session`, or `attendance` |
| `window` | Preferred minimum and maximum gap |
| `domain` | Broad area such as `recovery`, `home`, `creative`, `work`, or `relationships` |
| `project` | Optional relationship to a project key |
| `role` | Optional task role such as `next` or `waiting` |

### Examples

#### Creative practice

```text
[deskboard:v1]
key: play-music
kind: loop
mode: session
window: 2d..5d
domain: creative
[/deskboard]
```

#### Household maintenance

```text
[deskboard:v1]
key: vacuum-office
kind: loop
mode: completion
window: 7d..14d
domain: home
[/deskboard]
```

#### Recovery or community activity

```text
[deskboard:v1]
key: meeting
kind: loop
mode: attendance
window: 3d..7d
domain: recovery
[/deskboard]
```

The exact window is always chosen by the user. Deskboard should not prescribe a recovery, health, or personal-practice schedule.

#### Project-linked task

```text
[deskboard:v1]
kind: task
project: deskboard
role: next
[/deskboard]
```

### What Does Not Belong in Reminder Notes

Dynamic information should remain in the local Dossier database:

- last completion
- last engagement
- session history
- total time
- active timer
- snoozed-until time
- display history
- project last moved
- ranking state

This keeps the metadata block stable and avoids constantly rewriting Apple data.

---

## 9. Domain Balance

A purely urgency-driven system will eventually fill itself with work and chores.

Deskboard should recognize broad life domains such as:

- recovery and care
- home maintenance
- work and administration
- creative practice
- relationships
- learning
- rest and recreation

This does not require a complex life-balance score.

A simple initial rule is enough:

> When an available or calling creative, recovery, or relationship loop exists, reserve the possibility of showing one alongside obligations.

This prevents “play music” from losing forever to “clean bathroom” merely because chores are easier to quantify.

---

## 10. The Interaction Grammar

Deskboard should use a very small vocabulary.

### Done

Records a completion.

For an ordinary task, this eventually completes the source Reminder.

For a loop anchor, it records an occurrence while leaving the anchor intact.

### Start

Begins one active session.

The active session should remain quietly visible at the top of the Board.

### Stop

Ends the active session and records its duration.

The user may correct the duration afterward if needed.

### I Did This

Records engagement without requiring the timer.

Useful when the activity happened away from Deskboard or was remembered afterward.

### Touched

Records meaningful project movement without claiming completion.

Examples include:

- researched a component
- discussed the idea
- made a design decision
- ordered a part
- wrote notes
- reopened the project and determined the next action

### Park

Intentionally removes a project or loop from active consideration.

Parking is not abandonment. It is a decision about current attention.

### Resume

Returns a parked item to active consideration.

### Not Today

Temporarily removes an item from the current Board without changing its underlying importance.

There should be no penalty for using it.

### Set Next Action

Assigns one concrete entry point to a project.

A project without a next action may be shown as:

> Deskboard has no next action.

That is more useful than showing an ambiguous project title.

---

## 11. The Default Desk Display

The first screen should fit without scrolling.

A possible shape:

```text
THURSDAY · AUGUST 20                           10:42

NOW
────────────────────────────────────────────────────
Deskboard
Build the Reminders metadata parser                28m


TODAY
────────────────────────────────────────────────────
○ Call the dentist
○ Put out the trash
○ Order ESP32 boards


OPEN LOOPS
────────────────────────────────────────────────────
Meeting                         5 days since last
Play music                      6 days since last
Clean desk                      4 days since last


IN MOTION                                             3 / 3
────────────────────────────────────────────────────
Deskboard                       touched today
Password migration             3 days since movement
Smart blinds                    11 days since movement


NEXT
────────────────────────────────────────────────────
Tomorrow · 9:00 AM              Project call


HOME
────────────────────────────────────────────────────
71° inside · air good · doors locked · home normal


SIDEWAYS PROMPT
────────────────────────────────────────────────────
[One short prompt from the selected source]
```

### Display Limits

A strong initial constraint would be:

- one current focus
- three Today items
- three Open Loops
- three Active Projects
- two upcoming commitments
- one Home summary
- one optional prompt

If there is more information than this, the system must rank it rather than expanding the screen.

White space is part of the interface.

---

## 12. Attention Selection Rules

The first ranking system should be deterministic and understandable.

### Priority Order

1. **Immediate exceptions**  
   A serious home condition, missed hard commitment, or appointment requiring action.

2. **Current focus**  
   The selected project, task, or running session.

3. **Today commitments**  
   Dated Reminders and Calendar events that genuinely matter today.

4. **Calling loops**  
   Loops beyond their preferred maximum.

5. **Active-project staleness**  
   Active projects with no recent movement or no next action.

6. **Available loops**  
   Activities within their preferred window, particularly nourishing or recovery-oriented ones.

7. **Normal signals and prompt content**  
   These occupy remaining space only.

### Explainability

Every surfaced item should carry a concise reason:

- `due today`
- `in 90 minutes`
- `6 days since last`
- `11 days without movement`
- `waiting item unblocked`
- `door unlocked`

The reason is part of the product, not debug information.

### No AI Ranking in the Initial Version

An agent may help interpret commands, but the Board should initially use explicit rules.

Learning and suggestions can come later, after enough real use exists to determine what would actually help.

---

## 13. Agent and Chat Interaction

A conversational interface can become a convenient input method, but it should not become the owner of the data.

The desired flow is:

```text
User statement
      ↓
Structured intent
      ↓
Deskboard command gateway
      ↓
Correct source system or Dossier record
      ↓
Audit history
```

Examples:

> “I played with the synth for 35 minutes.”

Creates a 35-minute session against `play-music`.

> “Mark vacuuming as done.”

Records an occurrence against `vacuum-office`.

> “Park the smart-blinds project.”

Changes the project state in the Dossier.

> “Remind me tomorrow to order the motor driver.”

Creates an Apple Reminder through the Bridge.

> “Move my appointment to Friday.”

Proposes or performs an Apple Calendar update through the Bridge.

The agent should route information to the system that owns it:

- dates and appointments → Calendar
- concrete tasks → Reminders
- sessions and loop history → Dossier
- long-form thoughts → Notes
- home commands → narrowly scoped home adapter

High-impact actions, particularly calendar deletion, security controls, locks, or destructive home administration, should require explicit confirmation.

---

## 14. Device Philosophy

### iPad Pro: First Desk Client

The iPad is the practical first display because it already exists and has a large, readable touch screen.

Its Deskboard mode should be intentionally appliance-like:

- added to the Home Screen
- full-screen presentation
- no external browsing
- no notification permission
- no animations
- no infinite scrolling
- large static regions
- one or two levels of navigation
- optional Guided Access during testing

The iPad’s ability to do everything else does not undermine Deskboard. Constraining it is part of the experiment.

### Steam Deck: Secondary Client and Test Surface

The Steam Deck does not need to remain on all day.

It can validate:

- responsive layout
- desktop-sized rendering
- keyboard and controller navigation
- Linux browser behavior
- temporary focus mode
- session control from another device

It may serve as a secondary control surface rather than a permanent ambient display.

### Future Android Devices

A hacked Switch or inexpensive Android tablet can later become:

- a portable household panel
- a kitchen display
- a wall controller
- a family-safe client
- a second Deskboard station

### Future E-Ink Devices

BOOX, Kindle, or Raspberry Pi clients should use a dedicated paper profile:

- no animation
- limited refresh
- high contrast
- no continuous clock updates
- no unnecessary imagery
- static page layout
- event-driven changes
- server-rendered frames where appropriate

The same core system should support all of these without duplicating the information model.

---

## 15. Technical Shape

```text
                         APPLE SYSTEMS
                ┌───────────────────────────┐
                │ Reminders · Calendar     │
                │ Notes references         │
                └─────────────┬─────────────┘
                              │
                        macOS Bridge
                              │
                              ▼
┌──────────────┐      ┌─────────────────────┐
│ Agent / Chat │─────▶│   Deskboard Core    │
└──────────────┘      │                     │
                      │ Personal Dossier    │
┌──────────────┐      │ Session history     │
│  Shortcuts   │─────▶│ Loop rules          │
└──────────────┘      │ Project state       │
                      │ Attention selector  │
┌──────────────┐      └──────────┬──────────┘
│ Home / ESP32 │────────────────▶│
└──────────────┘                 │
                                 ▼
                         Deskboard API
                                 │
              ┌──────────────────┼──────────────────┐
              ▼                  ▼                  ▼
            iPad             Steam Deck          Android
          desk mode          desktop mode         wall mode
                                                     │
                                      ┌──────────────┴─────────────┐
                                      ▼                            ▼
                                  BOOX/Kindle                   Pi E-Ink
                                  paper mode                    frame mode
```

### Initial Components

**macOS Bridge**  
Reads Calendar and Reminders, performs approved writeback, and exposes normalized information.

**Deskboard Core**  
Stores the Dossier, sessions, loops, projects, and ranking rules.

**Deskboard Client**  
A responsive PWA used first on the iPad and Steam Deck.

**Command Gateway**  
Accepts structured commands from Shortcuts, an agent, or the Board.

### Initial Hosting Shape

The first version can run entirely on the Mac:

- easiest access to Apple data
- lowest infrastructure overhead
- no premature deployment work

The intended connected architecture moves Deskboard Core to the Ubuntu homelab while the Apple Bridge remains a small Mac companion that connects to it over the private network.

---

## 16. Initial Scope

The first useful version should be deliberately small.

### Version 0.1: Prove the Feeling

Use manually entered or fixture data.

Include:

- a single, non-scrolling Board
- a small Today section
- the next Calendar commitments
- one Sideways Prompt
- responsive iPad and Steam Deck layouts
- explicit reasons for why each item is shown

No Apple synchronization is required to test whether the display model is useful.

### Version 0.2: Bridge Apple Read-Only

Add:

- read Apple Reminders
- read upcoming Calendar events
- normalize and cache source records
- parse Deskboard metadata from Reminder notes without acting on it
- show data freshness and bridge health

### Version 0.3: Prove One Round Trip

Add only:

- complete an ordinary Reminder from Deskboard
- a queued command path through the macOS Bridge
- idempotency, conflict detection, and audit history

Calendar remains read-only.

### Version 0.4: Introduce One Open Loop

Add:

- one manually designated Reminder anchor
- preferred loop window
- elapsed-time display
- `I Did This`
- resting, available, calling, and paused states

### Version 0.5: Add a Session

Add:

- Start
- Stop
- one server-side active timer
- duration history
- cross-device state

### Version 1.0: Expand Carefully

Only after the earlier behavior has proved useful, consider:

- projects and next actions
- active-work limits
- home summaries
- agent commands
- Android and E-Ink rendering profiles
- family-safe views
- ESP32 sensor inputs

---

## 17. Explicitly Deferred Ideas

These may become valuable, but they should not enter the first build:

- AI-generated priority scores
- full Notes indexing
- automatic interpretation of every document
- complex tags and nested taxonomies
- productivity charts
- streaks
- badges or points
- social comparison
- full Home Assistant administration
- camera feeds on the default screen
- automatic project percentages
- dozens of home controls
- elaborate time reports
- commercial multi-user architecture
- native applications for every platform

The project should earn complexity through use.

---

## 18. Long-Term Possibilities

Once the core behavior has proven useful, Deskboard could gradually develop richer assistance.

### Re-entry Summaries

For a neglected project:

> Last time you ordered the motor and identified the GPIO library. Next unresolved question: how to detect the blind’s end position.

This would directly reduce the mental cost of returning.

### Learned Duration

Without becoming a productivity tracker, session history could offer realistic expectations:

> Cleaning the desk usually takes 12–18 minutes.

> Your recent music sessions are usually around 35 minutes.

This can weaken the mental wall created by not knowing how large an activity will feel.

### Available-Time Suggestions

When the user has fifteen minutes:

> Clean desk usually fits here.

> The next Deskboard action usually takes around twenty minutes.

The system should explain why it suggested something and always allow dismissal.

### Weekly Reflection

A quiet review could show:

- what received attention
- what repeatedly resurfaced
- which projects moved
- what remained parked
- what nourishing activities happened
- which loop windows may need adjustment

This should be descriptive, not judgmental.

### Home and ESP32 Ecosystem

Future projects can become Deskboard peripherals:

- solar-powered indoor air-quality monitors
- smart blind openers
- outdoor camera integration
- room-level temperature sensors
- environmental alerts
- physical Deskboard buttons
- occupancy-aware displays

### Family Mode

A separate household profile could show:

- shared calendar
- groceries
- household reminders
- weather
- locks
- thermostat
- media requests
- family notes
- safe home scenes

Private loops, recovery information, and work projects should remain excluded by default.

---

## 19. The Emotional Contract

Deskboard should communicate the following through its behavior:

> You are allowed to forget.

> You are allowed to park something.

> You are allowed to return after a long absence.

> Time away is information, not a moral failure.

> Five minutes of engagement still counts.

> Creative activity is not a reward that must be earned after every chore is complete.

> A project does not need a fake percentage to be real.

> The system will show you a manageable amount and keep the rest safe.

> You do not have to maintain the entire system before it can help you today.

This emotional contract is not decoration. It is a functional requirement.

---

## 20. Success Criteria for the First Real Trial

After two weeks of daily use, the prototype should be considered promising if:

- the Board remains on the desk voluntarily
- it takes less than two minutes per day to maintain
- most interactions require one tap or one sentence
- it catches at least one task or appointment that might otherwise have been forgotten
- it helps revive at least one neglected creative, recovery, or personal activity
- it makes the next action on an active project easier to identify
- the display remains calm rather than becoming another backlog
- the iPad and Steam Deck show the same underlying state
- it remains useful even when some integrations are unavailable
- the user wants to keep looking at it after the novelty period

The first trial is not measuring productivity.

It is measuring whether Deskboard makes daily life feel more visible, recoverable, and intentional.

---

## 21. First Build Commitment

The first implementation slice should contain only:

- one full-screen Board
- fixture-backed Reminder and Calendar data
- a small typed Board contract
- Today and Next sections
- one rotating Sideways Prompt
- source-freshness presentation
- responsive layouts for the iPad Pro and Steam Deck
- accessibility, unit, and browser-level proof tests

Everything else waits until this version has been used and reviewed.

The project begins not by connecting every system, but by proving one central idea:

> **A small, quiet, persistent field of attention can be more useful than another powerful application.**
