import {
  boardSnapshotSchema,
  type AppleBridgeSelectedSourceStatusV1,
  type AppleCalendarSourceRecordV1,
  type AppleReminderSourceRecordV1,
} from "@deskboard/contracts";
import { describe, expect, it } from "vitest";

import {
  MIRROR_BOARD_FRESHNESS_MILLISECONDS,
  composeMirrorBackedBoard,
} from "../src/mirror-backed-board/index";
import { AppleSourceMirror } from "../src/apple-source-mirror/index";
import {
  makeCalendarRecord,
  makeCalendarSnapshot,
  makeReminderSnapshot,
} from "./apple-source-mirror-fixtures";

const BRIDGE_ID = "synthetic-phase-3c-bridge";
const REMINDER_A = "synthetic-reminder-a";
const REMINDER_B = "synthetic-reminder-b";
const CALENDAR_A = "synthetic-calendar-a";
const NOW = new Date("2026-08-24T17:00:00.000Z");
const FRESH_CAPTURE = "2026-08-24T16:59:30.000Z";
const FRESH_ACK = "2026-08-24T16:59:00.000Z";
const SIDEWAYS = {
  label: "Sideways" as const,
  text: "Keep one synthetic edge quiet enough to notice.",
};

function selectedSource(
  entityType: "calendar" | "reminder",
  sourceContainerId: string,
  options: Partial<AppleBridgeSelectedSourceStatusV1> = {},
): AppleBridgeSelectedSourceStatusV1 {
  return {
    entityType,
    sourceContainerId,
    status: "applied",
    acknowledgedSourceRevision: 1,
    lastAttemptedAt: FRESH_ACK,
    lastAcknowledgedAt: FRESH_ACK,
    ...options,
  };
}

function applyStatus(
  mirror: AppleSourceMirror,
  options: {
    calendarPermission?: "granted" | "denied" | "notDetermined";
    reminderPermission?: "granted" | "denied" | "notDetermined";
    capturedAt?: string;
    selectedSources?: AppleBridgeSelectedSourceStatusV1[];
    statusRevision?: number;
  } = {},
) {
  const result = mirror.applyBridgeStatus({
    schemaVersion: 1,
    bridgeId: BRIDGE_ID,
    statusRevision: options.statusRevision ?? 1,
    capturedAt: options.capturedAt ?? FRESH_CAPTURE,
    permissions: {
      calendar: options.calendarPermission ?? "granted",
      reminders: options.reminderPermission ?? "granted",
    },
    selectedSources: options.selectedSources ?? [],
  });
  expect(result.kind).toBe("applied");
}

function compose(mirror: AppleSourceMirror, now = NOW) {
  return composeMirrorBackedBoard({
    source: mirror,
    expectedBridgeId: BRIDGE_ID,
    timeZone: "America/Los_Angeles",
    clock: () => now,
    sidewaysPrompt: SIDEWAYS,
  });
}

function applyReminders(
  mirror: AppleSourceMirror,
  records: AppleReminderSourceRecordV1[],
  sourceContainerId = REMINDER_A,
  revision = 1,
) {
  const snapshot = makeReminderSnapshot({
    bridgeId: BRIDGE_ID,
    sourceContainerId,
    capturedAt: FRESH_ACK,
    records,
  });
  expect(mirror.apply({ snapshot, sourceRevision: revision }).kind).toBe(
    "applied",
  );
}

function applyCalendar(
  mirror: AppleSourceMirror,
  records: AppleCalendarSourceRecordV1[],
  sourceContainerId = CALENDAR_A,
  revision = 1,
  windowStart = "2026-08-01T00:00:00Z",
  windowEnd = "2026-09-15T00:00:00Z",
) {
  const snapshot = makeCalendarSnapshot({
    bridgeId: BRIDGE_ID,
    sourceContainerId,
    capturedAt: FRESH_ACK,
    windowStart,
    windowEnd,
    records,
  });
  expect(mirror.apply({ snapshot, sourceRevision: revision }).kind).toBe(
    "applied",
  );
}

function reminder(
  localIdentifier: string,
  title: string | undefined,
  options: Partial<AppleReminderSourceRecordV1> = {},
): AppleReminderSourceRecordV1 {
  return {
    localIdentifier,
    ...(title === undefined ? {} : { title }),
    start: { kind: "absent" },
    due: { kind: "absent" },
    isCompleted: false,
    ...options,
  };
}

describe("mirror-backed Board freshness", () => {
  it("uses a fixed fifteen-minute interval and the oldest selected acknowledgement", () => {
    expect(MIRROR_BOARD_FRESHNESS_MILLISECONDS).toBe(15 * 60 * 1_000);
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyReminders(mirror, [
      reminder("a", "First", { due: { kind: "dateOnly", localDate: "2026-08-24" } }),
    ]);
    applyReminders(
      mirror,
      [reminder("b", "Second", { due: { kind: "dateOnly", localDate: "2026-08-24" } })],
      REMINDER_B,
    );
    applyStatus(mirror, {
      selectedSources: [
        selectedSource("reminder", REMINDER_A),
        selectedSource("reminder", REMINDER_B, {
          lastAttemptedAt: "2026-08-24T16:58:00.000Z",
          lastAcknowledgedAt: "2026-08-24T16:58:00.000Z",
        }),
      ],
    });

    const result = compose(mirror);

    expect(result.board.freshness.reminders).toEqual({
      status: "fresh",
      updatedAt: "2026-08-24T16:58:00.000Z",
    });
    expect(result.acceptanceSummary.selectedSourceCounts.reminders).toBe(2);
    expect(result.acceptanceSummary.sources).toEqual([
      { source: "Reminder source 1", health: "applied" },
      { source: "Reminder source 2", health: "applied" },
    ]);
    mirror.close();
  });

  it.each(["blockedTruncated", "retryPending"] as const)(
    "keeps last-good items visible but marks %s selected delivery stale",
    (status) => {
      const mirror = new AppleSourceMirror({ clock: () => NOW });
      applyReminders(mirror, [
        reminder("a", "Last good", {
          due: { kind: "dateOnly", localDate: "2026-08-24" },
        }),
      ]);
      applyStatus(mirror, {
        selectedSources: [
          selectedSource("reminder", REMINDER_A, {
            status,
            pendingSourceRevision: 2,
          }),
        ],
      });

      const result = compose(mirror);

      expect(result.board.freshness.reminders.status).toBe("stale");
      expect(result.board.today.items.map((item) => item.title)).toEqual([
        "Last good",
      ]);
      mirror.close();
    },
  );

  it("keeps Calendar permission failure independent from fresh Reminders", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyReminders(mirror, [
      reminder("a", "Independent task", {
        due: { kind: "dateOnly", localDate: "2026-08-24" },
      }),
    ]);
    applyCalendar(mirror, [
      makeCalendarRecord(
        "a",
        "2026-08-24T18:00:00Z",
        "2026-08-24T19:00:00Z",
        "Last good event",
      ),
    ]);
    applyStatus(mirror, {
      calendarPermission: "denied",
      selectedSources: [
        selectedSource("calendar", CALENDAR_A, {
          status: "permissionUnavailable",
        }),
        selectedSource("reminder", REMINDER_A),
      ],
    });

    const result = compose(mirror);

    expect(result.board.freshness.calendar.status).toBe("unavailable");
    expect(result.board.freshness.reminders.status).toBe("fresh");
    expect(result.board.next.items).toHaveLength(1);
    expect(result.board.today.items).toHaveLength(1);
    mirror.close();
  });

  it("marks a missing or revision-mismatched selected scope stale without deleting other facts", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyReminders(mirror, [
      reminder("a", "Present", {
        due: { kind: "dateOnly", localDate: "2026-08-24" },
      }),
    ]);
    applyStatus(mirror, {
      selectedSources: [
        selectedSource("reminder", REMINDER_A, {
          acknowledgedSourceRevision: 2,
        }),
        selectedSource("reminder", REMINDER_B),
      ],
    });

    const result = compose(mirror);

    expect(result.board.freshness.reminders.status).toBe("stale");
    expect(result.board.today.items.map((item) => item.title)).toEqual([
      "Present",
    ]);
    expect(result.board.freshness.reminders.updatedAt).toBe(FRESH_ACK);
    mirror.close();
  });

  it("excludes deselected sources immediately while retaining their mirror scopes", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyReminders(mirror, [
      reminder("a", "Selected", {
        due: { kind: "dateOnly", localDate: "2026-08-24" },
      }),
    ]);
    applyReminders(
      mirror,
      [reminder("b", "Deselected", { due: { kind: "dateOnly", localDate: "2026-08-24" } })],
      REMINDER_B,
    );
    applyStatus(mirror, {
      selectedSources: [selectedSource("reminder", REMINDER_A)],
    });

    const result = compose(mirror);

    expect(result.board.today.items.map((item) => item.title)).toEqual([
      "Selected",
    ]);
    expect(
      mirror.readSourceScopeSummary({
        bridgeId: BRIDGE_ID,
        entityType: "reminder",
        sourceContainerId: REMINDER_B,
      }),
    ).not.toBeNull();
    mirror.close();
  });

  it("is unavailable without status and does not infer selections from mirror rows", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyReminders(mirror, [
      reminder("a", "Stored but not selected", {
        due: { kind: "dateOnly", localDate: "2026-08-24" },
      }),
    ]);

    const result = compose(mirror);

    expect(result.board.freshness).toEqual({
      reminders: { status: "unavailable", updatedAt: null },
      calendar: { status: "unavailable", updatedAt: null },
    });
    expect(result.board.today.items).toEqual([]);
    mirror.close();
  });

  it("is unavailable when granted entities have no selected sources", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyStatus(mirror);

    const result = compose(mirror);

    expect(result.board.freshness).toEqual({
      reminders: { status: "unavailable", updatedAt: null },
      calendar: { status: "unavailable", updatedAt: null },
    });
    mirror.close();
  });

  it("marks selected acknowledgements older than the interval stale", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyReminders(mirror, [
      reminder("a", "Old acknowledgement", {
        due: { kind: "dateOnly", localDate: "2026-08-24" },
      }),
    ]);
    applyStatus(mirror, {
      capturedAt: "2026-08-24T16:40:00Z",
      selectedSources: [
        selectedSource("reminder", REMINDER_A, {
          lastAttemptedAt: "2026-08-24T16:40:00Z",
          lastAcknowledgedAt: "2026-08-24T16:40:00Z",
        }),
      ],
    });

    expect(compose(mirror).board.freshness.reminders.status).toBe("stale");
    mirror.close();
  });
});

describe("Reminder projection into Today", () => {
  it("orders timed due-today, date-only due-today, then start-only availability", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyReminders(mirror, [
      reminder("a", "Date only", {
        due: { kind: "dateOnly", localDate: "2026-08-24" },
      }),
      reminder("b", "Timed", {
        due: {
          kind: "timeZoneDateTime",
          localDateTime: "2026-08-24T15:00:00",
          timeZone: "America/Los_Angeles",
        },
      }),
      reminder("c", "Start only", {
        start: { kind: "dateOnly", localDate: "2026-08-24" },
      }),
    ]);
    applyStatus(mirror, {
      selectedSources: [selectedSource("reminder", REMINDER_A)],
    });

    const board = compose(mirror).board;

    expect(board.today.items.map(({ title, reason }) => ({ title, reason }))).toEqual([
      { title: "Timed", reason: "due at 3:00 PM" },
      { title: "Date only", reason: "due today" },
      { title: "Start only", reason: "available today" },
    ]);
    expect(board.today.items[0]?.temporal).toEqual({
      kind: "dateTime",
      localDateTime: "2026-08-24T15:00:00",
      timeZone: "America/Los_Angeles",
    });
    mirror.close();
  });

  it("orders overdue items most recently due and excludes future, undated, completed, and blank titles", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyReminders(mirror, [
      reminder("a", "Older", { due: { kind: "dateOnly", localDate: "2026-08-20" } }),
      reminder("b", "Yesterday", { due: { kind: "dateOnly", localDate: "2026-08-23" } }),
      reminder("c", "Future", { due: { kind: "dateOnly", localDate: "2026-08-25" } }),
      reminder("d", "Undated"),
      reminder("e", "Completed", {
        due: { kind: "dateOnly", localDate: "2026-08-24" },
        isCompleted: true,
        completionDate: "2026-08-24T16:00:00Z",
      }),
      reminder("f", "   ", { due: { kind: "dateOnly", localDate: "2026-08-24" } }),
      reminder("g", "Due takes precedence", {
        start: { kind: "dateOnly", localDate: "2026-08-24" },
        due: { kind: "dateOnly", localDate: "2026-08-25" },
      }),
      reminder("h", "Older timed", {
        due: {
          kind: "localDateTime",
          localDateTime: "2026-08-22T23:00:00",
        },
      }),
    ]);
    applyStatus(mirror, {
      selectedSources: [selectedSource("reminder", REMINDER_A)],
    });

    const items = compose(mirror).board.today.items;

    expect(items.map(({ title, reason }) => ({ title, reason }))).toEqual([
      { title: "Yesterday", reason: "overdue from yesterday" },
      { title: "Older timed", reason: "overdue 2 days" },
      { title: "Older", reason: "overdue 4 days" },
    ]);
    mirror.close();
  });

  it("applies the deterministic three-item cap and exposes only opaque client IDs", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyReminders(mirror, [
      reminder("raw-a", "Three", { due: { kind: "dateOnly", localDate: "2026-08-24" } }),
      reminder("raw-b", "One", { due: { kind: "localDateTime", localDateTime: "2026-08-24T08:00:00" } }),
      reminder("raw-c", "Four", { due: { kind: "dateOnly", localDate: "2026-08-23" } }),
      reminder("raw-d", "Two", { due: { kind: "localDateTime", localDateTime: "2026-08-24T09:00:00" } }),
    ]);
    applyStatus(mirror, {
      selectedSources: [selectedSource("reminder", REMINDER_A)],
    });

    const items = compose(mirror).board.today.items;

    expect(items.map((item) => item.title)).toEqual(["One", "Two", "Three"]);
    expect(items).toHaveLength(3);
    for (const item of items) {
      expect(item.id).toMatch(/^task-[0-9a-f]{32}$/);
      expect(item.id).not.toMatch(/raw|synthetic|bridge|reminder/i);
    }
    mirror.close();
  });
});

describe("Calendar projection into Next", () => {
  it("orders ongoing and future events and excludes canceled, blank, and ended ranges", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    const records: AppleCalendarSourceRecordV1[] = [
      makeCalendarRecord("e", "2026-08-24T15:00:00Z", "2026-08-24T17:00:00Z", "Ends now"),
      makeCalendarRecord("a", "2026-08-24T16:00:00Z", "2026-08-24T18:00:00Z", "Ongoing"),
      makeCalendarRecord("b", "2026-08-24T17:45:00Z", "2026-08-24T18:30:00Z", "Soon"),
      { ...makeCalendarRecord("c", "2026-08-24T19:00:00Z", "2026-08-24T20:00:00Z", "Canceled"), status: "canceled" },
      makeCalendarRecord("d", "2026-08-24T20:00:00Z", "2026-08-24T21:00:00Z", "   "),
    ];
    applyCalendar(mirror, records);
    applyStatus(mirror, {
      selectedSources: [selectedSource("calendar", CALENDAR_A)],
    });

    const items = compose(mirror).board.next.items;

    expect(items.map(({ title, reason }) => ({ title, reason }))).toEqual([
      { title: "Ongoing", reason: "happening now" },
      { title: "Soon", reason: "in 45 minutes" },
    ]);
    expect(items[0]?.whenLabel).toBe("Continues today");
    expect(items[1]?.whenLabel).toBe("Today · 10:45 AM");
    mirror.close();
  });

  it("preserves single and active multi-day all-day civil ranges", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    const records: AppleCalendarSourceRecordV1[] = [
      {
        localIdentifier: "a",
        title: "Multi-day",
        temporal: {
          kind: "allDayRange",
          startDate: "2026-08-23",
          endDate: "2026-08-26",
        },
        isDetached: false,
        status: "confirmed",
      },
      {
        localIdentifier: "b",
        title: "Tomorrow all day",
        temporal: {
          kind: "allDayRange",
          startDate: "2026-08-25",
          endDate: "2026-08-26",
        },
        isDetached: false,
        status: "confirmed",
      },
    ];
    applyCalendar(mirror, records);
    applyStatus(mirror, {
      selectedSources: [selectedSource("calendar", CALENDAR_A)],
    });

    const items = compose(mirror).board.next.items;

    expect(items.map(({ title, reason, whenLabel }) => ({ title, reason, whenLabel }))).toEqual([
      { title: "Multi-day", reason: "continues today", whenLabel: "Continues today" },
      { title: "Tomorrow all day", reason: "tomorrow", whenLabel: "Tomorrow · all day" },
    ]);
    expect(items.map((item) => item.temporal)).toEqual([
      { kind: "allDay", startDate: "2026-08-23", endDate: "2026-08-26" },
      { kind: "allDay", startDate: "2026-08-25", endDate: "2026-08-26" },
    ]);
    mirror.close();
  });

  it("projects exact instants through a Board-zone offset transition", () => {
    const now = new Date("2026-03-08T09:45:00Z");
    const mirror = new AppleSourceMirror({ clock: () => now });
    applyCalendar(
      mirror,
      [
        {
          localIdentifier: "a",
          title: "After transition",
          temporal: {
            kind: "timeZoneTimedRange",
            start: "2026-03-08T10:30:00Z",
            end: "2026-03-08T11:30:00Z",
            timeZone: "Etc/UTC",
          },
          isDetached: false,
          status: "confirmed",
        },
      ],
      CALENDAR_A,
      1,
      "2026-03-01T00:00:00Z",
      "2026-03-15T00:00:00Z",
    );
    applyStatus(mirror, {
      capturedAt: "2026-03-08T09:44:30Z",
      selectedSources: [
        selectedSource("calendar", CALENDAR_A, {
          lastAttemptedAt: "2026-03-08T09:44:00Z",
          lastAcknowledgedAt: "2026-03-08T09:44:00Z",
        }),
      ],
    });

    const item = compose(mirror, now).board.next.items[0];

    expect(item?.temporal).toEqual({
      kind: "dateTime",
      localDateTime: "2026-03-08T03:30:00",
      timeZone: "America/Los_Angeles",
    });
    expect(item?.reason).toBe("in 45 minutes");
    expect(item?.whenLabel).toBe("Today · 3:30 AM");
    mirror.close();
  });

  it("uses only rows in the latest accepted Calendar window", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyCalendar(
      mirror,
      [
        makeCalendarRecord(
          "a",
          "2026-09-10T18:00:00Z",
          "2026-09-10T19:00:00Z",
          "Retained outside latest window",
        ),
      ],
      CALENDAR_A,
      1,
      "2026-08-01T00:00:00Z",
      "2026-09-15T00:00:00Z",
    );
    applyCalendar(
      mirror,
      [],
      CALENDAR_A,
      2,
      "2026-08-01T00:00:00Z",
      "2026-09-01T00:00:00Z",
    );
    applyStatus(mirror, {
      selectedSources: [
        selectedSource("calendar", CALENDAR_A, {
          acknowledgedSourceRevision: 2,
        }),
      ],
    });

    const result = compose(mirror);

    expect(result.board.next.items).toEqual([]);
    expect(
      mirror.listRetainedCalendarRecordsOutsideLatestWindow({
        bridgeId: BRIDGE_ID,
        entityType: "calendar",
        sourceContainerId: CALENDAR_A,
      }),
    ).toHaveLength(1);
    mirror.close();
  });

  it("applies the deterministic two-item cap and opaque IDs", () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    applyCalendar(mirror, [
      makeCalendarRecord("raw-a", "2026-08-24T18:00:00Z", "2026-08-24T19:00:00Z", "First"),
      makeCalendarRecord("raw-b", "2026-08-24T19:00:00Z", "2026-08-24T20:00:00Z", "Second"),
      makeCalendarRecord("raw-c", "2026-08-24T20:00:00Z", "2026-08-24T21:00:00Z", "Third"),
    ]);
    applyStatus(mirror, {
      selectedSources: [selectedSource("calendar", CALENDAR_A)],
    });

    const result = compose(mirror);

    expect(result.board.next.items.map((item) => item.title)).toEqual([
      "First",
      "Second",
    ]);
    for (const item of result.board.next.items) {
      expect(item.id).toMatch(/^commitment-[0-9a-f]{32}$/);
      expect(item.id).not.toMatch(/raw|synthetic|bridge|calendar/i);
    }
    expect(boardSnapshotSchema.safeParse(result.board).success).toBe(true);
    expect(result.board.generatedAt).toBe(NOW.toISOString());
    expect(result.board.sidewaysPrompt).toEqual(SIDEWAYS);
    expect(result.board.boardVersion).toMatch(/^apple-mirror-[0-9a-f]{32}$/);
    const second = compose(mirror).board;
    expect(second.boardVersion).toBe(result.board.boardVersion);
    mirror.close();
  });
});
