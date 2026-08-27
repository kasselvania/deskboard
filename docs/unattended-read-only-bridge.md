# Unattended read-only Bridge

Phase 3E adds owner-approved unattended operation to the accepted signed Bridge without changing Apple source contract v1, Bridge status v1, `BoardSnapshot` v1, the private deployment topology, or any Apple source fact. The implementation is in review under issue #25. Its synthetic and initial signed-product gates are complete; the private 24-hour acceptance and controlled login/restart cycle remain required before Phase 3E can be accepted.

## Selected Reminder completeness

The content-free Gate 1 diagnostic produced outcome **A: measured finite operational limit increase**.

| Measurement | Result |
|---|---:|
| Complete matched records | 945 |
| Prior Reminder retained-record cap | 500 |
| Complete encoded candidate | 280,671 bytes |
| Current Reminder retained-record cap | 1,000 |
| Current Calendar retained-record cap | 500 |
| Encoded pending-envelope limit | 786,432 bytes |
| Core source request limit | 1,048,576 bytes |
| Private proxy source request limit | 1,048,576 bytes |
| Bounded-memory fit | yes |
| Envelope fit | yes |
| Core fit | yes |
| Private-proxy fit | yes |

Only the Reminder retained-record cap changed, from 500 to 1,000. The Calendar retained-record cap remains 500. The 4,096-record diagnostic admission bound, 512 KiB admitted-string bound, 8 MiB diagnostic encoding bound, 768 KiB pending-envelope bound, 1 MiB Core/proxy source-body bounds, and source contract remain unchanged. Ordering and collision validation still run across the complete matched set before truncation. Encoded-envelope trimming remains the final independent bound after entity-specific record capping. Any source exceeding a finite production boundary remains `truncated: true`, non-authoritative, and rejected by Core without mirror mutation.

## Releasing the previously blocked revision

The accepted prior `blockedTruncated` envelope could not be discarded or superseded. Phase 3E therefore implements the tech-lead-approved, owner-invoked replacement transition.

The action is eligible only when the selected Reminder source, permission, source availability, Bridge/entity/container coordinate, strict pending envelope, blocked state, and `acknowledgedRevision + 1` relationship still agree. It then:

1. reads the same whole-list v1 scope under the 1,000-record cap;
2. builds and validates a strict, collision-free, non-truncated candidate before mutation;
3. encodes it at the existing pending source revision;
4. re-reads state and refuses any concurrent prerequisite change;
5. atomically replaces the pending encoded bytes without a persisted nil interval;
6. changes only that delivery result to `retryPending`;
7. delegates transport to the existing manual delivery implementation.

A still-truncated candidate is a no-op. Any read, conversion, validation, encoding, state-comparison, or save failure preserves the complete preexisting Bridge state. No scheduled, wake, login, or ordinary Sync Now path can invoke this recovery action.

The private owner gate completed with these permitted facts:

```text
Replacement persisted: yes
Complete snapshot applied: yes
Source remains blockedTruncated: no
Reminder freshness: fresh
No private content shared: yes
```

## Owner-approved startup

The production Bridge remains one signed, sandboxed application. `SMAppService.mainApp` registers that same application under **Open at Login**. There is no helper identity, root daemon, managed or unmanaged LaunchAgent, admin requirement, or App Background Activity helper.

The Release product declares its application and team identifiers through symbolic Xcode build settings. No signing value is committed or reported. Those signing identifiers let macOS construct the main-app login record; the functional entitlement allowlist remains App Sandbox, outbound network client, and Calendar/EventKit access. The bundle identity and designated requirement remain stable.

The owner controls startup through **Keep Board Current** in the menu-bar app or Bridge settings:

- turning it on registers the signed main application;
- `enabled`, `requires approval`, `not registered`, and `not found` map to fixed content-free categories;
- a previously approved relaunch retries a missing `notRegistered` or `notFound` registration once;
- an explicit retry control is available when a missing registration remains;
- disabling in the app unregisters the main app and stops future scheduling;
- disabling in System Settings stops unattended scheduling without disabling manual launch or Sync Now;
- quitting invalidates the scheduler and wake observer without erasing prior owner approval;
- no full settings window must remain open.

Deskboard appears in System Settings under **Open at Login**, not as a separate entry under **App Background Activity**.

## Scheduling and coalescing

One injected boundary wraps `NSBackgroundActivityScheduler`.

| Setting | Value |
|---|---:|
| Repeating interval | 600 seconds |
| Tolerance | 120 seconds |
| Repeats | yes |
| Quality of service | background |
| Wake threshold | 600 seconds since the last requested run |
| Deferral | accepted and reported as `deferred` |

The interval is compatible with the unchanged 15-minute Board freshness rule, but it is not a wall-clock promise. macOS may defer activity. A deferred or missed opportunity never fabricates freshness.

Manual, scheduled, and wake requests enter one main-actor coalescer and invoke the accepted `ManualSyncCoordinator`. One run may be active. Any number of requests arriving during it produce at most one later run; their completion handlers share that coalesced result. A wake event requests at most one opportunity when the previous request is at least 600 seconds old.

The coordinator still performs the accepted sequence:

```text
pending status -> exact pending source envelopes -> new reads -> final status
```

Pending source and status bytes remain persisted before transport. Transport uncertainty leaves the same encoded bytes at the same revision. Only `applied` or `unchangedDuplicate` acknowledges and clears pending state. There is no timer-driven transport retry loop and no parallel delivery implementation.

## Sleep, wake, network, permission, and state

- Sleep performs no synchronization and cannot advance freshness.
- Wake requests one coalesced opportunity only after the wake threshold.
- Temporary network failure preserves exact pending bytes; reconnect is handled by the next scheduled, wake, or manual opportunity.
- Calendar and Reminders remain independent.
- Permission or source unavailability remains content-free and does not deselect or delete source state.
- Unavailable Keychain or invalid persisted state fails content-free.
- Stale and revision-conflict results remain operator-action states.
- App replacement and relaunch preserve Bridge identity, selections, revisions, origin, history, pending source/status bytes, Keychain/TCC scope, and owner approval.
- No notification or automatic destructive recovery is added.

## Local content-free status

The native surface exposes only:

- Keep Board Current owner setting;
- effective unattended enabled/disabled state;
- login-item category;
- last background attempt;
- last fixed content-free result;
- whether one request is queued behind an active run.

No scheduler metadata enters Apple source contract v1, Bridge status v1, or `BoardSnapshot` v1.

## Signed-product checkpoint

The installed Release product has passed these content-free checks:

- two successive Release products built and installed;
- Apple Development identity category preserved;
- strict signature valid;
- designated requirement stable;
- Bridge state and owner scheduling state exact across both installs and relaunches;
- owner approval preserved;
- macOS Open at Login record present and enabled;
- operation with no full window open;
- first eligible scheduled run completed;
- no Deskboard shell LaunchAgent remains.

The controlled logout/login or restart launch, System Settings disablement, and manual-launch fallback remain required before the signed-product gate is complete.

## Private 24-hour acceptance

After code review, leave the signed menu-bar app running for at least 24 hours while recording only fixed categories and yes/no conclusions. The run must include one sleep/wake cycle and one temporary network outage, then prove:

- ordinary scheduled runs require no owner action;
- working sources normally remain inside the existing freshness expectation while awake and connected;
- sleep and disconnection become honestly stale;
- wake or a later connected opportunity recovers without conflict or byte loss;
- the previously capped Reminder source remains complete;
- iPad and Steam Deck agree after recovery;
- the Board remains recognizable and calm;
- manual Sync Now still works.

Do not capture screenshots, accessibility output, DOM/API bodies, mirror rows, pending bytes, source values, host values, signing values, or private Board content.

## Deferred work

Phase 3E adds no backup/restore, week-long soak, public ingress, notifications, source-management UI, new contract, web-client change, Apple write, Reminder completion, automatic conflict reset, or generic scheduler framework. Backup/restore and the longer read-only soak remain Phase 3F.
