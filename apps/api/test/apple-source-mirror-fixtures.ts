import { readFile } from "node:fs/promises";

import {
  appleCalendarSourceSnapshotV1Schema,
  appleReminderSourceSnapshotV1Schema,
  type AppleCalendarSourceRecordV1,
  type AppleCalendarSourceSnapshotV1,
  type AppleReminderSourceRecordV1,
  type AppleReminderSourceSnapshotV1,
} from "@deskboard/contracts";

import type {
  AppleCalendarSourceScopeCoordinate,
  AppleReminderSourceScopeCoordinate,
} from "../src/apple-source-mirror/index";

const contractFixtureRoot = new URL(
  "../../../fixtures/apple-source-contract/v1/",
  import.meta.url,
);

export const validContractFixtureNames = [
  "reminder-empty.json",
  "reminder-undated.json",
  "reminder-date-only.json",
  "reminder-local-date-time.json",
  "reminder-time-zone-date-time.json",
  "reminder-completed.json",
  "reminder-truncated.json",
  "calendar-empty.json",
  "calendar-local-timed.json",
  "calendar-time-zone-timed.json",
  "calendar-time-zone-offset-transition.json",
  "calendar-all-day-single-day.json",
  "calendar-recurring-occurrence.json",
  "calendar-subscribed-read-only.json",
  "calendar-truncated.json",
] as const;

export const invalidContractFixtureNames = [
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

export async function readContractFixture(
  collection: "valid" | "invalid",
  fixtureName: string,
): Promise<unknown> {
  return JSON.parse(
    await readFile(new URL(`${collection}/${fixtureName}`, contractFixtureRoot), "utf8"),
  ) as unknown;
}

export function makeReminderRecord(
  localIdentifier: string,
  title: string,
): AppleReminderSourceRecordV1 {
  return {
    localIdentifier,
    title,
    start: { kind: "absent" },
    due: { kind: "absent" },
    isCompleted: false,
  };
}

export function makeReminderSnapshot(options: {
  bridgeId?: string;
  sourceContainerId?: string;
  capturedAt?: string;
  records?: AppleReminderSourceRecordV1[];
} = {}): AppleReminderSourceSnapshotV1 {
  const records = options.records ?? [];
  return appleReminderSourceSnapshotV1Schema.parse({
    schemaVersion: 1,
    entityType: "reminder",
    bridgeId: options.bridgeId ?? "synthetic-bridge-a",
    source: {
      sourceContainerId:
        options.sourceContainerId ?? "synthetic-reminder-container-a",
      allowsContentModifications: true,
    },
    capturedAt: options.capturedAt ?? "2026-08-23T01:00:00Z",
    matchedCount: records.length,
    truncated: false,
    records,
  });
}

export function makeCalendarRecord(
  localIdentifier: string,
  start: string,
  end: string,
  title: string,
): AppleCalendarSourceRecordV1 {
  return {
    localIdentifier,
    title,
    temporal: {
      kind: "timeZoneTimedRange",
      start,
      end,
      timeZone: "Etc/UTC",
    },
    isDetached: false,
    status: "confirmed",
  };
}

export function makeCalendarSnapshot(options: {
  windowStart: string;
  windowEnd: string;
  bridgeId?: string;
  sourceContainerId?: string;
  capturedAt?: string;
  records?: AppleCalendarSourceRecordV1[];
}): AppleCalendarSourceSnapshotV1 {
  const records = options.records ?? [];
  return appleCalendarSourceSnapshotV1Schema.parse({
    schemaVersion: 1,
    entityType: "calendar",
    bridgeId: options.bridgeId ?? "synthetic-bridge-a",
    source: {
      sourceContainerId:
        options.sourceContainerId ?? "synthetic-calendar-container-a",
      allowsContentModifications: true,
      isSubscribed: false,
    },
    capturedAt: options.capturedAt ?? "2026-08-23T01:00:00Z",
    window: {
      start: options.windowStart,
      end: options.windowEnd,
      timeZone: "Etc/UTC",
      boundarySemantics: "overlapStartInclusiveEndExclusive",
    },
    matchedCount: records.length,
    truncated: false,
    records,
  });
}

export function reminderCoordinate(
  snapshot: AppleReminderSourceSnapshotV1,
): AppleReminderSourceScopeCoordinate {
  return {
    bridgeId: snapshot.bridgeId,
    entityType: "reminder",
    sourceContainerId: snapshot.source.sourceContainerId,
  };
}

export function calendarCoordinate(
  snapshot: AppleCalendarSourceSnapshotV1,
): AppleCalendarSourceScopeCoordinate {
  return {
    bridgeId: snapshot.bridgeId,
    entityType: "calendar",
    sourceContainerId: snapshot.source.sourceContainerId,
  };
}
