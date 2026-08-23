import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import {
  appleCalendarSourceSnapshotV1Schema,
  appleReminderSourceSnapshotV1Schema,
  appleSourceSnapshotAuthorizesAbsence,
  appleSourceSnapshotV1Schema,
} from "../src/index";

const fixtureDirectory = fileURLToPath(
  new URL("../../../fixtures/apple-source-contract/v1/", import.meta.url),
);

const reminderValidFixtureNames = [
  "reminder-empty.json",
  "reminder-undated.json",
  "reminder-date-only.json",
  "reminder-local-date-time.json",
  "reminder-time-zone-date-time.json",
  "reminder-completed.json",
  "reminder-truncated.json",
] as const;

const calendarValidFixtureNames = [
  "calendar-empty.json",
  "calendar-local-timed.json",
  "calendar-time-zone-timed.json",
  "calendar-time-zone-offset-transition.json",
  "calendar-all-day-single-day.json",
  "calendar-recurring-occurrence.json",
  "calendar-subscribed-read-only.json",
  "calendar-truncated.json",
] as const;

const invalidFixtureNames = [
  "unsupported-schema-version.json",
  "unknown-top-level-key.json",
  "unknown-nested-key.json",
  "wrong-entity-discriminator.json",
  "contradictory-temporal-fields.json",
  "impossible-date.json",
  "impossible-clock-time.json",
  "offset-in-local-date-time.json",
  "ambiguous-local-date-time.json",
  "nonexistent-local-date-time.json",
  "timed-end-not-after-start.json",
  "all-day-end-not-after-start.json",
  "incomplete-reminder-with-completion-date.json",
  "matched-count-below-records-length.json",
  "non-truncated-count-inconsistency.json",
  "truncated-without-omission.json",
  "malformed-calendar-window.json",
  "unrecognized-time-zone.json",
  "excluded-participant-field.json",
  "calendar-record-outside-window.json",
  "reminder-record-order.json",
  "calendar-record-order.json",
  "duplicate-reminder-order-coordinate.json",
  "duplicate-calendar-order-coordinate.json",
] as const;

async function readFixture(
  collection: "valid" | "invalid",
  fixtureName: string,
): Promise<unknown> {
  const fixture = await readFile(
    new URL(`${collection}/${fixtureName}`, `file://${fixtureDirectory}/`),
    "utf8",
  );
  return JSON.parse(fixture) as unknown;
}

describe("Apple source contract v1", () => {
  it("locks the exact shared valid and invalid fixture inventories", async () => {
    const validFiles = (await readdir(`${fixtureDirectory}/valid`))
      .filter((path) => path.endsWith(".json"))
      .sort();
    const invalidFiles = (await readdir(`${fixtureDirectory}/invalid`))
      .filter((path) => path.endsWith(".json"))
      .sort();

    expect(validFiles).toEqual(
      [...reminderValidFixtureNames, ...calendarValidFixtureNames].sort(),
    );
    expect(invalidFiles).toEqual([...invalidFixtureNames].sort());
  });

  it("accepts every shared valid Reminder fixture as only the Reminder variant", async () => {
    for (const fixtureName of reminderValidFixtureNames) {
      const fixture = await readFixture("valid", fixtureName);
      expect(
        appleReminderSourceSnapshotV1Schema.safeParse(fixture).success,
        fixtureName,
      ).toBe(true);
      expect(
        appleCalendarSourceSnapshotV1Schema.safeParse(fixture).success,
        fixtureName,
      ).toBe(false);
      expect(appleSourceSnapshotV1Schema.safeParse(fixture).success).toBe(true);
    }
  });

  it("accepts every shared valid Calendar fixture as only the Calendar variant", async () => {
    for (const fixtureName of calendarValidFixtureNames) {
      const fixture = await readFixture("valid", fixtureName);
      expect(
        appleCalendarSourceSnapshotV1Schema.safeParse(fixture).success,
        fixtureName,
      ).toBe(true);
      expect(
        appleReminderSourceSnapshotV1Schema.safeParse(fixture).success,
        fixtureName,
      ).toBe(false);
      expect(appleSourceSnapshotV1Schema.safeParse(fixture).success).toBe(true);
    }
  });

  it("rejects every shared invalid fixture", async () => {
    for (const fixtureName of invalidFixtureNames) {
      expect(
        appleSourceSnapshotV1Schema.safeParse(
          await readFixture("invalid", fixtureName),
        ).success,
        fixtureName,
      ).toBe(false);
    }
  });

  it("rejects unknown keys at the top level, nested scope, temporal, and record levels", async () => {
    for (const fixtureName of [
      "unknown-top-level-key.json",
      "unknown-nested-key.json",
      "contradictory-temporal-fields.json",
      "excluded-participant-field.json",
    ]) {
      expect(
        appleSourceSnapshotV1Schema.safeParse(
          await readFixture("invalid", fixtureName),
        ).success,
        fixtureName,
      ).toBe(false);
    }
  });

  it("rejects impossible dates, clocks, offset-bearing locals, and invalid ranges", async () => {
    for (const fixtureName of [
      "impossible-date.json",
      "impossible-clock-time.json",
      "offset-in-local-date-time.json",
      "ambiguous-local-date-time.json",
      "nonexistent-local-date-time.json",
      "timed-end-not-after-start.json",
      "all-day-end-not-after-start.json",
      "malformed-calendar-window.json",
      "calendar-record-outside-window.json",
    ]) {
      expect(
        appleSourceSnapshotV1Schema.safeParse(
          await readFixture("invalid", fixtureName),
        ).success,
        fixtureName,
      ).toBe(false);
    }
  });

  it("enforces completion, count, truncation, and deterministic ordering invariants", async () => {
    for (const fixtureName of [
      "incomplete-reminder-with-completion-date.json",
      "matched-count-below-records-length.json",
      "non-truncated-count-inconsistency.json",
      "truncated-without-omission.json",
      "reminder-record-order.json",
      "calendar-record-order.json",
      "duplicate-reminder-order-coordinate.json",
      "duplicate-calendar-order-coordinate.json",
    ]) {
      expect(
        appleSourceSnapshotV1Schema.safeParse(
          await readFixture("invalid", fixtureName),
        ).success,
        fixtureName,
      ).toBe(false);
    }
  });

  it("authorizes absence only after strict runtime validation", async () => {
    const emptyReminder = await readFixture("valid", "reminder-empty.json");
    const emptyCalendar = await readFixture("valid", "calendar-empty.json");
    const truncatedReminder = await readFixture(
      "valid",
      "reminder-truncated.json",
    );
    const truncatedCalendar = await readFixture(
      "valid",
      "calendar-truncated.json",
    );

    expect(appleSourceSnapshotAuthorizesAbsence(emptyReminder)).toBe(true);
    expect(appleSourceSnapshotAuthorizesAbsence(emptyCalendar)).toBe(true);
    expect(appleSourceSnapshotAuthorizesAbsence(truncatedReminder)).toBe(false);
    expect(appleSourceSnapshotAuthorizesAbsence(truncatedCalendar)).toBe(false);
    expect(
      appleSourceSnapshotAuthorizesAbsence({ truncated: false }),
    ).toBe(false);
    expect(
      appleSourceSnapshotAuthorizesAbsence(
        await readFixture("invalid", "unsupported-schema-version.json"),
      ),
    ).toBe(false);
    expect(
      appleSourceSnapshotAuthorizesAbsence(
        await readFixture(
          "invalid",
          "non-truncated-count-inconsistency.json",
        ),
      ),
    ).toBe(false);
    expect(
      appleSourceSnapshotAuthorizesAbsence({
        ...(emptyReminder as Record<string, unknown>),
        unexpected: "strict validation must reject this cast-shaped value",
      }),
    ).toBe(false);
  });

  it("preserves exact timezone-qualified instants across an offset transition", async () => {
    const snapshot = appleCalendarSourceSnapshotV1Schema.parse(
      await readFixture(
        "valid",
        "calendar-time-zone-offset-transition.json",
      ),
    );
    const temporal = snapshot.records[0]?.temporal;

    expect(temporal?.kind).toBe("timeZoneTimedRange");
    if (temporal?.kind !== "timeZoneTimedRange") {
      throw new Error("Expected timezone-qualified Calendar range.");
    }
    expect(temporal.start).toBe("2026-11-01T01:30:00-07:00");
    expect(temporal.end).toBe("2026-11-01T01:30:00-08:00");
    expect(temporal).not.toHaveProperty("startLocalDateTime");
    expect(temporal).not.toHaveProperty("endLocalDateTime");
  });

  it("represents expanded recurring occurrences without recurrence grammar", async () => {
    const snapshot = appleCalendarSourceSnapshotV1Schema.parse(
      await readFixture("valid", "calendar-recurring-occurrence.json"),
    );
    const occurrence = snapshot.records[0];

    expect(occurrence?.occurrenceDate).toBeDefined();
    expect(occurrence).not.toHaveProperty("recurrences");
  });
});
