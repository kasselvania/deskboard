import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

import { afterEach, describe, expect, it } from "vitest";

import {
  AppleSourceMirror,
  AppleSourceMirrorApplyError,
  type AppleReminderSourceScopeCoordinate,
} from "../src/apple-source-mirror/index";
import {
  APPLE_SOURCE_MIRROR_MIGRATIONS,
  applyAppleSourceMirrorMigrations,
  configureAppleSourceMirrorConnection,
} from "../src/apple-source-mirror/migrations";
import {
  calendarCoordinate,
  makeCalendarRecord,
  makeCalendarSnapshot,
  makeReminderRecord,
  makeReminderSnapshot,
  reminderCoordinate,
} from "./apple-source-mirror-fixtures";

const openMirrors: AppleSourceMirror[] = [];
const temporaryDirectories: string[] = [];

function openMirror(
  options?: ConstructorParameters<typeof AppleSourceMirror>[0],
): AppleSourceMirror {
  const mirror = new AppleSourceMirror(options);
  openMirrors.push(mirror);
  return mirror;
}

afterEach(async () => {
  for (const mirror of openMirrors.splice(0)) {
    mirror.close();
  }
  await Promise.all(
    temporaryDirectories.splice(0).map((directory) =>
      rm(directory, { recursive: true, force: true }),
    ),
  );
});

function reminderState(
  mirror: AppleSourceMirror,
  coordinate: AppleReminderSourceScopeCoordinate,
) {
  return {
    summary: mirror.readSourceScopeSummary(coordinate),
    records: mirror.listReminderRecords(coordinate),
  };
}

describe("atomic Apple source mirror", () => {
  it("replaces complete Reminder scopes and isolates other Bridges and lists", () => {
    const first = makeReminderSnapshot({
      records: [
        makeReminderRecord("synthetic-reminder-a", "Synthetic first A"),
        makeReminderRecord("synthetic-reminder-b", "Synthetic first B"),
      ],
    });
    const otherBridge = makeReminderSnapshot({
      bridgeId: "synthetic-bridge-b",
      records: [
        makeReminderRecord("synthetic-reminder-c", "Synthetic other Bridge"),
      ],
    });
    const otherList = makeReminderSnapshot({
      sourceContainerId: "synthetic-reminder-container-b",
      records: [
        makeReminderRecord("synthetic-reminder-d", "Synthetic other list"),
      ],
    });
    const mirror = openMirror({
      clock: () => new Date("2026-08-23T02:00:00Z"),
    });

    expect(mirror.apply({ snapshot: first, sourceRevision: 1 }).kind).toBe(
      "applied",
    );
    expect(
      mirror.apply({ snapshot: otherBridge, sourceRevision: 1 }).kind,
    ).toBe("applied");
    expect(mirror.apply({ snapshot: otherList, sourceRevision: 1 }).kind).toBe(
      "applied",
    );
    expect(mirror.listReminderRecords(reminderCoordinate(first))).toEqual(
      first.records,
    );

    const replacement = makeReminderSnapshot({
      capturedAt: "2026-08-23T03:00:00Z",
      records: [
        makeReminderRecord("synthetic-reminder-e", "Synthetic replacement"),
      ],
    });
    expect(
      mirror.apply({ snapshot: replacement, sourceRevision: 2 }),
    ).toEqual({
      kind: "applied",
      entityType: "reminder",
      sourceRevision: 2,
    });
    expect(mirror.listReminderRecords(reminderCoordinate(first))).toEqual(
      replacement.records,
    );
    expect(
      mirror.listReminderRecords(reminderCoordinate(otherBridge)),
    ).toEqual(otherBridge.records);
    expect(mirror.listReminderRecords(reminderCoordinate(otherList))).toEqual(
      otherList.records,
    );

    const empty = makeReminderSnapshot({
      capturedAt: "2026-08-23T04:00:00Z",
    });
    expect(mirror.apply({ snapshot: empty, sourceRevision: 3 }).kind).toBe(
      "applied",
    );
    expect(mirror.listReminderRecords(reminderCoordinate(first))).toEqual([]);
    expect(
      mirror.readSourceScopeSummary(reminderCoordinate(first)),
    ).toMatchObject({
      acceptedSourceRevision: 3,
      matchedCount: 0,
    });
    expect(
      mirror.listReminderRecords(reminderCoordinate(otherBridge)),
    ).toEqual(otherBridge.records);
    expect(mirror.listReminderRecords(reminderCoordinate(otherList))).toEqual(
      otherList.records,
    );
  });

  it("replaces only Calendar overlap and retains rows outside the latest window", () => {
    const outsideLaterWindow = makeCalendarRecord(
      "synthetic-calendar-a",
      "2026-08-04T23:00:00Z",
      "2026-08-05T00:00:00Z",
      "Synthetic retained event",
    );
    const absentInsideLaterWindow = makeCalendarRecord(
      "synthetic-calendar-b",
      "2026-08-06T10:00:00Z",
      "2026-08-06T11:00:00Z",
      "Synthetic replaced event",
    );
    const first = makeCalendarSnapshot({
      windowStart: "2026-08-01T00:00:00Z",
      windowEnd: "2026-08-11T00:00:00Z",
      records: [outsideLaterWindow, absentInsideLaterWindow],
    });
    const mirror = openMirror({
      clock: () => new Date("2026-08-23T02:00:00Z"),
    });

    expect(mirror.apply({ snapshot: first, sourceRevision: 1 }).kind).toBe(
      "applied",
    );
    expect(
      mirror.listCalendarRecordsInLatestWindow(calendarCoordinate(first)),
    ).toEqual(first.records);

    const newWindowRecord = makeCalendarRecord(
      "synthetic-calendar-c",
      "2026-08-12T10:00:00Z",
      "2026-08-12T11:00:00Z",
      "Synthetic new-window event",
    );
    const shifted = makeCalendarSnapshot({
      windowStart: "2026-08-05T00:00:00Z",
      windowEnd: "2026-08-15T00:00:00Z",
      capturedAt: "2026-08-23T03:00:00Z",
      records: [newWindowRecord],
    });
    expect(mirror.apply({ snapshot: shifted, sourceRevision: 2 }).kind).toBe(
      "applied",
    );
    expect(
      mirror.listCalendarRecordsInLatestWindow(calendarCoordinate(first)),
    ).toEqual([newWindowRecord]);
    expect(
      mirror.listRetainedCalendarRecordsOutsideLatestWindow(
        calendarCoordinate(first),
      ),
    ).toEqual([outsideLaterWindow]);

    const emptyOverlap = makeCalendarSnapshot({
      windowStart: "2026-08-10T00:00:00Z",
      windowEnd: "2026-08-14T00:00:00Z",
      capturedAt: "2026-08-23T04:00:00Z",
    });
    const beforeTruncated = {
      summary: mirror.readSourceScopeSummary(calendarCoordinate(first)),
      current: mirror.listCalendarRecordsInLatestWindow(
        calendarCoordinate(first),
      ),
      retainedOutside: mirror.listRetainedCalendarRecordsOutsideLatestWindow(
        calendarCoordinate(first),
      ),
    };
    expect(
      mirror.apply({
        snapshot: {
          ...structuredClone(emptyOverlap),
          matchedCount: 1,
          truncated: true,
        },
        sourceRevision: 3,
      }),
    ).toMatchObject({ kind: "rejectedTruncated" });
    expect({
      summary: mirror.readSourceScopeSummary(calendarCoordinate(first)),
      current: mirror.listCalendarRecordsInLatestWindow(
        calendarCoordinate(first),
      ),
      retainedOutside: mirror.listRetainedCalendarRecordsOutsideLatestWindow(
        calendarCoordinate(first),
      ),
    }).toEqual(beforeTruncated);

    expect(
      mirror.apply({ snapshot: emptyOverlap, sourceRevision: 3 }).kind,
    ).toBe("applied");
    expect(
      mirror.listCalendarRecordsInLatestWindow(calendarCoordinate(first)),
    ).toEqual([]);
    expect(
      mirror.listRetainedCalendarRecordsOutsideLatestWindow(
        calendarCoordinate(first),
      ),
    ).toEqual([outsideLaterWindow]);

    const refreshedEarlierRegion = makeCalendarRecord(
      "synthetic-calendar-d",
      "2026-08-02T12:00:00Z",
      "2026-08-02T13:00:00Z",
      "Synthetic refreshed earlier event",
    );
    const refreshedLaterRegion = makeCalendarRecord(
      "synthetic-calendar-e",
      "2026-08-12T12:00:00Z",
      "2026-08-12T13:00:00Z",
      "Synthetic refreshed later event",
    );
    const expanded = makeCalendarSnapshot({
      windowStart: "2026-08-01T00:00:00Z",
      windowEnd: "2026-08-15T00:00:00Z",
      capturedAt: "2026-08-23T05:00:00Z",
      records: [refreshedEarlierRegion, refreshedLaterRegion],
    });
    expect(mirror.apply({ snapshot: expanded, sourceRevision: 4 }).kind).toBe(
      "applied",
    );
    expect(
      mirror.listCalendarRecordsInLatestWindow(calendarCoordinate(first)),
    ).toEqual(expanded.records);
    expect(
      mirror.listRetainedCalendarRecordsOutsideLatestWindow(
        calendarCoordinate(first),
      ),
    ).toEqual([]);
    expect(
      mirror.readSourceScopeSummary(calendarCoordinate(first)),
    ).toMatchObject({
      acceptedSourceRevision: 4,
      window: {
        start: expanded.window.start,
        end: expanded.window.end,
      },
    });
  });

  it("distinguishes duplicate, conflict, stale, truncated, invalid, and newer delivery", () => {
    let receiptInstant = "2026-08-23T02:00:00Z";
    const first = makeReminderSnapshot({
      records: [
        makeReminderRecord("synthetic-sequence-a", "Synthetic sequence first"),
      ],
    });
    const coordinate = reminderCoordinate(first);
    const mirror = openMirror({
      clock: () => new Date(receiptInstant),
    });

    const applied = mirror.apply({ snapshot: first, sourceRevision: 7 });
    expect(applied).toEqual({
      kind: "applied",
      entityType: "reminder",
      sourceRevision: 7,
    });
    expect(Object.keys(applied).sort()).toEqual([
      "entityType",
      "kind",
      "sourceRevision",
    ]);
    expect(JSON.stringify(applied)).not.toContain(first.records[0]?.title);
    expect(JSON.stringify(applied)).not.toContain(
      first.records[0]?.localIdentifier,
    );
    const accepted = reminderState(mirror, coordinate);

    const reorderedInput = {
      records: structuredClone(first.records),
      truncated: first.truncated,
      matchedCount: first.matchedCount,
      capturedAt: first.capturedAt,
      source: {
        allowsContentModifications: first.source.allowsContentModifications,
        sourceContainerId: first.source.sourceContainerId,
      },
      bridgeId: first.bridgeId,
      entityType: first.entityType,
      schemaVersion: first.schemaVersion,
    };
    receiptInstant = "2026-08-23T03:00:00.000Z";
    expect(
      mirror.apply({ snapshot: reorderedInput, sourceRevision: 7 }),
    ).toMatchObject({ kind: "unchangedDuplicate" });
    expect(reminderState(mirror, coordinate)).toEqual(accepted);

    const changed = makeReminderSnapshot({
      capturedAt: "2026-08-23T04:00:00Z",
      records: [
        makeReminderRecord("synthetic-sequence-b", "Synthetic changed record"),
      ],
    });
    expect(mirror.apply({ snapshot: changed, sourceRevision: 7 })).toMatchObject(
      { kind: "rejectedRevisionConflict" },
    );
    expect(reminderState(mirror, coordinate)).toEqual(accepted);

    expect(mirror.apply({ snapshot: changed, sourceRevision: 6 })).toMatchObject(
      { kind: "rejectedStale" },
    );
    expect(reminderState(mirror, coordinate)).toEqual(accepted);

    const truncated = {
      ...structuredClone(first),
      capturedAt: "2026-08-23T05:00:00Z",
      matchedCount: 2,
      truncated: true,
    };
    expect(
      mirror.apply({ snapshot: truncated, sourceRevision: 8 }),
    ).toMatchObject({ kind: "rejectedTruncated" });
    expect(reminderState(mirror, coordinate)).toEqual(accepted);

    const collision = {
      ...structuredClone(first),
      capturedAt: "2026-08-23T06:00:00Z",
      matchedCount: 2,
      records: [
        first.records[0],
        { ...first.records[0], title: "Synthetic colliding record" },
      ],
    };
    expect(mirror.apply({ snapshot: collision, sourceRevision: 8 })).toEqual({
      kind: "rejectedInvalid",
    });
    expect(reminderState(mirror, coordinate)).toEqual(accepted);

    expect(
      mirror.apply({
        snapshot: { ...structuredClone(first), unexpected: true },
        sourceRevision: 8,
      }),
    ).toEqual({ kind: "rejectedInvalid" });
    expect(reminderState(mirror, coordinate)).toEqual(accepted);

    expect(mirror.apply({ snapshot: changed, sourceRevision: 8 })).toMatchObject(
      { kind: "applied" },
    );
    expect(reminderState(mirror, coordinate).records).toEqual(changed.records);
    expect(mirror.readSourceScopeSummary(coordinate)).toMatchObject({
      acceptedSourceRevision: 8,
      sourceCapturedAt: changed.capturedAt,
      coreReceivedAt: receiptInstant,
    });
  });

  it("rolls metadata and records back after injected failure following deletion", () => {
    let shouldFail = false;
    const first = makeReminderSnapshot({
      records: [
        makeReminderRecord("synthetic-rollback-a", "Synthetic rollback first"),
        makeReminderRecord("synthetic-rollback-b", "Synthetic rollback second"),
      ],
    });
    const replacement = makeReminderSnapshot({
      capturedAt: "2026-08-23T03:00:00Z",
      records: [
        makeReminderRecord(
          "synthetic-rollback-c",
          "Synthetic rollback replacement",
        ),
      ],
    });
    const mirror = openMirror({
      clock: () => new Date("2026-08-23T02:00:00Z"),
      testOnlyAfterDestructiveSql: () => {
        if (shouldFail) {
          throw new Error(
            "Synthetic source content must not escape the transaction boundary.",
          );
        }
      },
    });
    const coordinate = reminderCoordinate(first);
    expect(mirror.apply({ snapshot: first, sourceRevision: 1 }).kind).toBe(
      "applied",
    );
    const beforeFailure = reminderState(mirror, coordinate);

    shouldFail = true;
    let capturedError: unknown;
    try {
      mirror.apply({ snapshot: replacement, sourceRevision: 2 });
    } catch (error) {
      capturedError = error;
    }
    expect(capturedError).toBeInstanceOf(AppleSourceMirrorApplyError);
    expect(capturedError).toMatchObject({
      code: "APPLE_SOURCE_MIRROR_APPLY_FAILED",
      message: "Apple source mirror apply failed.",
    });
    expect(String(capturedError)).not.toContain(replacement.records[0]?.title);
    expect(String(capturedError)).not.toContain(
      replacement.records[0]?.localIdentifier,
    );
    expect(reminderState(mirror, coordinate)).toEqual(beforeFailure);

    shouldFail = false;
    expect(
      mirror.apply({ snapshot: replacement, sourceRevision: 2 }).kind,
    ).toBe("applied");
  });

  it("applies ordered strict migrations repeatedly with foreign keys enabled", () => {
    const database = new DatabaseSync(":memory:");
    try {
      configureAppleSourceMirrorConnection(database);
      applyAppleSourceMirrorMigrations(database);
      applyAppleSourceMirrorMigrations(database);

      expect(database.prepare("PRAGMA foreign_keys").get()).toMatchObject({
        foreign_keys: 1,
      });
      expect(
        database
          .prepare(
            "SELECT version, name FROM apple_source_mirror_migrations ORDER BY version",
          )
          .all(),
      ).toEqual(
        APPLE_SOURCE_MIRROR_MIGRATIONS.map(({ version, name }) => ({
          version,
          name,
        })),
      );

      const strictTables = database
        .prepare(
          `
            SELECT name, strict
            FROM pragma_table_list
            WHERE name LIKE 'apple_%'
            ORDER BY name
          `,
        )
        .all();
      expect(strictTables).toEqual([
        { name: "apple_calendar_records", strict: 1 },
        { name: "apple_reminder_records", strict: 1 },
        { name: "apple_source_mirror_migrations", strict: 1 },
        { name: "apple_source_scopes", strict: 1 },
      ]);
    } finally {
      database.close();
    }
    expect(database.isOpen).toBe(false);
  });

  it("closes, reopens, reruns migrations, and preserves accepted state", async () => {
    const directory = await mkdtemp(join(tmpdir(), "deskboard-mirror-reopen-"));
    temporaryDirectories.push(directory);
    const databasePath = join(directory, "mirror.sqlite");
    const snapshot = makeReminderSnapshot({
      records: [
        makeReminderRecord("synthetic-reopen-a", "Synthetic reopen record"),
      ],
    });
    const coordinate = reminderCoordinate(snapshot);

    const firstConnection = openMirror({
      databasePath,
      clock: () => new Date("2026-08-23T02:00:00Z"),
    });
    expect(
      firstConnection.apply({ snapshot, sourceRevision: 1 }).kind,
    ).toBe("applied");
    const acceptedState = reminderState(firstConnection, coordinate);
    firstConnection.close();
    expect(() => firstConnection.close()).not.toThrow();

    const secondConnection = openMirror({ databasePath });
    expect(reminderState(secondConnection, coordinate)).toEqual(acceptedState);
    secondConnection.close();

    const thirdConnection = openMirror({ databasePath });
    expect(reminderState(thirdConnection, coordinate)).toEqual(acceptedState);
    thirdConnection.close();
  });
});
