import { createHash } from "node:crypto";

import {
  BOARD_TEXT_LIMITS,
  boardSnapshotSchema,
  type AppleBridgeSourceDeliveryStatus,
  type AppleBridgeStatusSnapshotV1,
  type AppleCalendarSourceRecordV1,
  type AppleReminderSourceRecordV1,
  type AppleReminderTemporal,
  type BoardSnapshot,
  type CommitmentItem,
  type SourceFreshness,
  type TaskItem,
} from "@deskboard/contracts";

import {
  interpretAppleCalendarRecordRange,
  interpretLocalDateTimeInTimeZone,
} from "../apple-source-mirror/calendar-range.js";
import type {
  AppleCalendarSourceScopeCoordinate,
  AppleReminderSourceScopeCoordinate,
  AppleSourceScopeSummary,
} from "../apple-source-mirror/index.js";

export const MIRROR_BOARD_FRESHNESS_MILLISECONDS = 15 * 60 * 1_000;

export interface MirrorBackedBoardSource {
  readBridgeStatus(bridgeId: string): AppleBridgeStatusSnapshotV1 | null;
  readSourceScopeSummary(
    coordinate:
      | AppleReminderSourceScopeCoordinate
      | AppleCalendarSourceScopeCoordinate,
  ): AppleSourceScopeSummary | null;
  listReminderRecords(
    coordinate: AppleReminderSourceScopeCoordinate,
  ): AppleReminderSourceRecordV1[];
  listCalendarRecordsInLatestWindow(
    coordinate: AppleCalendarSourceScopeCoordinate,
  ): AppleCalendarSourceRecordV1[];
}

export interface ContentFreeBoardAcceptanceSummary {
  schemaValid: true;
  todayItemCount: number;
  nextItemCount: number;
  calendarFreshness: SourceFreshness["status"];
  remindersFreshness: SourceFreshness["status"];
  selectedSourceCounts: {
    calendar: number;
    reminders: number;
  };
  sources: Array<{
    source: string;
    health: AppleBridgeSourceDeliveryStatus;
  }>;
}

export interface MirrorBackedBoardResult {
  board: BoardSnapshot;
  acceptanceSummary: ContentFreeBoardAcceptanceSummary;
}

export interface MirrorBackedBoardOptions {
  source: MirrorBackedBoardSource;
  expectedBridgeId: string;
  timeZone: string;
  clock?: () => Date;
  sidewaysPrompt?: BoardSnapshot["sidewaysPrompt"];
}

export class MirrorBackedBoardCompositionError extends Error {
  readonly code = "MIRROR_BACKED_BOARD_COMPOSITION_FAILED";

  constructor() {
    super("Mirror-backed Board composition failed.");
    this.name = "MirrorBackedBoardCompositionError";
  }
}

interface SelectedSourceRead {
  status: AppleBridgeStatusSnapshotV1["selectedSources"][number];
  summary: AppleSourceScopeSummary | null;
  sourceOrder: number;
}

interface ReminderCandidate {
  category: number;
  effectiveDay: number;
  withinDayOrder: number;
  dueBeforeStart: number;
  sourceOrder: number;
  recordOrder: number;
  item: TaskItem;
}

interface CalendarCandidate {
  startMs: number;
  endMs: number;
  sourceOrder: number;
  recordOrder: number;
  item: CommitmentItem;
}

const successfulDeliveryStates = new Set<AppleBridgeSourceDeliveryStatus>([
  "applied",
  "unchangedDuplicate",
]);

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function formatter(
  timeZone: string,
  options: Intl.DateTimeFormatOptions,
  cacheKey: string,
): Intl.DateTimeFormat {
  const key = `${timeZone}:${cacheKey}`;
  const cached = formatterCache.get(key);
  if (cached) {
    return cached;
  }
  const created = new Intl.DateTimeFormat("en-US-u-ca-gregory-nu-latn", {
    timeZone,
    ...options,
  });
  formatterCache.set(key, created);
  return created;
}

function partsFor(date: Date, timeZone: string): Map<string, string> {
  return new Map(
    formatter(
      timeZone,
      {
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hourCycle: "h23",
      },
      "parts",
    )
      .formatToParts(date)
      .map((part) => [part.type, part.value]),
  );
}

function boardLocalDate(date: Date, timeZone: string): string {
  const parts = partsFor(date, timeZone);
  return `${parts.get("year")}-${parts.get("month")}-${parts.get("day")}`;
}

function boardLocalDateTime(date: Date, timeZone: string): string {
  const parts = partsFor(date, timeZone);
  return `${parts.get("year")}-${parts.get("month")}-${parts.get("day")}T${parts.get("hour")}:${parts.get("minute")}:${parts.get("second")}`;
}

function displayTime(date: Date, timeZone: string): string {
  return formatter(
    timeZone,
    { hour: "numeric", minute: "2-digit" },
    "display-time",
  ).format(date);
}

function weekdayForCivilDate(value: string): string {
  const [year, month, day] = value.split("-").map(Number);
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "Etc/UTC",
    weekday: "long",
  }).format(new Date(Date.UTC(year ?? 0, (month ?? 1) - 1, day ?? 1, 12)));
}

function civilDayNumber(value: string): number {
  const [year, month, day] = value.split("-").map(Number);
  return Math.floor(
    Date.UTC(year ?? 0, (month ?? 1) - 1, day ?? 1) / 86_400_000,
  );
}

function truncateTitle(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  if (!trimmed) {
    return undefined;
  }
  if (trimmed.length <= BOARD_TEXT_LIMITS.title) {
    return trimmed;
  }
  let retained = "";
  for (const scalar of trimmed) {
    if ((retained + scalar).length > BOARD_TEXT_LIMITS.title - 1) {
      break;
    }
    retained += scalar;
  }
  return `${retained}…`;
}

function opaqueId(kind: "task" | "commitment", provenance: string): string {
  const digest = createHash("sha256")
    .update(`deskboard-board-v1\0${kind}\0${provenance}`)
    .digest("hex")
    .slice(0, 32);
  return `${kind}-${digest}`;
}

function canonicalJson(value: unknown): string {
  if (value === null || typeof value === "boolean" || typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(",")}]`;
  }
  if (typeof value === "object") {
    const object = value as Record<string, unknown>;
    return `{${Object.keys(object)
      .filter((key) => object[key] !== undefined)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(object[key])}`)
      .join(",")}}`;
  }
  throw new MirrorBackedBoardCompositionError();
}

function isWithinFreshness(value: string | undefined, nowMs: number): boolean {
  if (value === undefined) {
    return false;
  }
  const age = nowMs - Date.parse(value);
  return age >= 0 && age <= MIRROR_BOARD_FRESHNESS_MILLISECONDS;
}

function selectedReads(
  source: MirrorBackedBoardSource,
  snapshot: AppleBridgeStatusSnapshotV1,
): SelectedSourceRead[] {
  return snapshot.selectedSources.map((status, sourceOrder) => {
    const coordinate = {
      bridgeId: snapshot.bridgeId,
      entityType: status.entityType,
      sourceContainerId: status.sourceContainerId,
    } as
      | AppleReminderSourceScopeCoordinate
      | AppleCalendarSourceScopeCoordinate;
    return {
      status,
      summary: source.readSourceScopeSummary(coordinate),
      sourceOrder,
    };
  });
}

function freshnessForEntity(
  entityType: "calendar" | "reminder",
  snapshot: AppleBridgeStatusSnapshotV1 | null,
  reads: SelectedSourceRead[],
  nowMs: number,
): SourceFreshness {
  if (!snapshot) {
    return { status: "unavailable", updatedAt: null };
  }
  const selected = reads.filter(
    (entry) => entry.status.entityType === entityType,
  );
  const permission =
    entityType === "calendar"
      ? snapshot.permissions.calendar
      : snapshot.permissions.reminders;
  const acknowledgedInstants = selected
    .filter((entry) => entry.summary !== null)
    .map((entry) => entry.status.lastAcknowledgedAt)
    .filter((value): value is string => value !== undefined)
    .sort((left, right) => Date.parse(left) - Date.parse(right));
  const updatedAt = acknowledgedInstants[0] ?? null;

  if (permission !== "granted" || selected.length === 0) {
    return { status: "unavailable", updatedAt };
  }

  const allCurrent =
    isWithinFreshness(snapshot.capturedAt, nowMs) &&
    selected.every(
      ({ status, summary }) =>
        successfulDeliveryStates.has(status.status) &&
        status.pendingSourceRevision === undefined &&
        status.acknowledgedSourceRevision > 0 &&
        isWithinFreshness(status.lastAcknowledgedAt, nowMs) &&
        summary !== null &&
        summary.acceptedSourceRevision === status.acknowledgedSourceRevision,
    );
  return { status: allCurrent ? "fresh" : "stale", updatedAt };
}

function reminderInstant(
  temporal: AppleReminderTemporal,
  boardTimeZone: string,
): number | undefined {
  if (temporal.kind === "localDateTime") {
    return interpretLocalDateTimeInTimeZone(
      temporal.localDateTime,
      boardTimeZone,
    );
  }
  if (temporal.kind === "timeZoneDateTime") {
    return interpretLocalDateTimeInTimeZone(
      temporal.localDateTime,
      temporal.timeZone,
    );
  }
  return undefined;
}

function reminderCandidate(
  record: AppleReminderSourceRecordV1,
  provenance: string,
  sourceOrder: number,
  recordOrder: number,
  today: string,
  timeZone: string,
): ReminderCandidate | undefined {
  const title = truncateTitle(record.title);
  if (!title || record.isCompleted) {
    return undefined;
  }
  const usesDue = record.due.kind !== "absent";
  const temporal = usesDue ? record.due : record.start;
  if (temporal.kind === "absent") {
    return undefined;
  }

  let effectiveDate: string;
  let effectiveDay: number;
  let withinDayOrder: number;
  let projectedTemporal: TaskItem["temporal"];
  let whenLabel: string | undefined;
  const timed = temporal.kind !== "dateOnly";
  if (temporal.kind === "dateOnly") {
    effectiveDate = temporal.localDate;
    effectiveDay = civilDayNumber(effectiveDate);
    withinDayOrder = 0;
    projectedTemporal = { kind: "date", localDate: effectiveDate };
    whenLabel = effectiveDate === today ? "Today" : undefined;
  } else {
    const instant = reminderInstant(temporal, timeZone);
    if (instant === undefined) {
      throw new MirrorBackedBoardCompositionError();
    }
    const date = new Date(instant);
    effectiveDate = boardLocalDate(date, timeZone);
    effectiveDay = civilDayNumber(effectiveDate);
    const localDateTime = boardLocalDateTime(date, timeZone);
    withinDayOrder =
      Number(localDateTime.slice(11, 13)) * 3_600 +
      Number(localDateTime.slice(14, 16)) * 60 +
      Number(localDateTime.slice(17, 19));
    projectedTemporal = {
      kind: "dateTime",
      localDateTime,
      timeZone,
    };
    whenLabel = displayTime(date, timeZone);
  }

  const dayDifference = civilDayNumber(today) - civilDayNumber(effectiveDate);
  if (dayDifference < 0) {
    return undefined;
  }
  const category =
    dayDifference > 0
      ? 3
      : usesDue
        ? timed
          ? 0
          : 1
        : 2;
  let reason: string;
  if (dayDifference === 0) {
    reason = usesDue
      ? timed
        ? `due at ${whenLabel}`
        : "due today"
      : "available today";
  } else if (usesDue) {
    reason =
      dayDifference === 1
        ? "overdue from yesterday"
        : `overdue ${dayDifference} days`;
  } else {
    reason =
      dayDifference === 1
        ? "available since yesterday"
        : `available ${dayDifference} days`;
  }

  return {
    category,
    effectiveDay,
    withinDayOrder,
    dueBeforeStart: usesDue ? 0 : 1,
    sourceOrder,
    recordOrder,
    item: {
      id: opaqueId("task", provenance),
      kind: "task",
      title,
      reason,
      ...(whenLabel ? { whenLabel } : {}),
      temporal: projectedTemporal,
    },
  };
}

function compareReminderCandidates(
  left: ReminderCandidate,
  right: ReminderCandidate,
): number {
  if (left.category !== right.category) {
    return left.category - right.category;
  }
  if (left.effectiveDay !== right.effectiveDay) {
    return left.category === 3
      ? right.effectiveDay - left.effectiveDay
      : left.effectiveDay - right.effectiveDay;
  }
  if (left.withinDayOrder !== right.withinDayOrder) {
    return left.category === 3
      ? right.withinDayOrder - left.withinDayOrder
      : left.withinDayOrder - right.withinDayOrder;
  }
  if (left.dueBeforeStart !== right.dueBeforeStart) {
    return left.dueBeforeStart - right.dueBeforeStart;
  }
  return left.sourceOrder !== right.sourceOrder
    ? left.sourceOrder - right.sourceOrder
    : left.recordOrder - right.recordOrder;
}

function calendarCandidate(
  record: AppleCalendarSourceRecordV1,
  interpretationTimeZone: string,
  provenance: string,
  sourceOrder: number,
  recordOrder: number,
  now: Date,
  today: string,
  timeZone: string,
): CalendarCandidate | undefined {
  const title = truncateTitle(record.title);
  if (!title || record.status === "canceled") {
    return undefined;
  }
  const range = interpretAppleCalendarRecordRange(
    record,
    interpretationTimeZone,
  );
  if (!range) {
    throw new MirrorBackedBoardCompositionError();
  }
  if (range.endMs <= now.getTime()) {
    return undefined;
  }

  let reason: string;
  let whenLabel: string;
  let temporal: CommitmentItem["temporal"];
  if (record.temporal.kind === "allDayRange") {
    const startDate = record.temporal.startDate;
    const endDate = record.temporal.endDate;
    const tomorrow = civilDayNumber(startDate) - civilDayNumber(today);
    if (startDate <= today && today < endDate) {
      const continuing = startDate < today;
      reason = continuing ? "continues today" : "all day";
      whenLabel = continuing ? "Continues today" : "All day";
    } else if (tomorrow === 1) {
      reason = "tomorrow";
      whenLabel = "Tomorrow · all day";
    } else {
      reason = "upcoming";
      whenLabel = `${weekdayForCivilDate(startDate)} · all day`;
    }
    temporal = { kind: "allDay", startDate, endDate };
  } else {
    const start = new Date(range.startMs);
    const startDate = boardLocalDate(start, timeZone);
    const dayOffset = civilDayNumber(startDate) - civilDayNumber(today);
    if (range.startMs <= now.getTime()) {
      reason = "happening now";
      whenLabel = "Continues today";
    } else if (dayOffset === 0) {
      const minutes = Math.max(
        1,
        Math.round((range.startMs - now.getTime()) / 60_000),
      );
      reason = minutes <= 90 ? `in ${minutes} minutes` : "later today";
      whenLabel = `Today · ${displayTime(start, timeZone)}`;
    } else if (dayOffset === 1) {
      reason = "tomorrow";
      whenLabel = `Tomorrow · ${displayTime(start, timeZone)}`;
    } else {
      reason = "upcoming";
      whenLabel = `${weekdayForCivilDate(startDate)} · ${displayTime(start, timeZone)}`;
    }
    temporal = {
      kind: "dateTime",
      localDateTime: boardLocalDateTime(start, timeZone),
      timeZone,
    };
  }

  return {
    startMs: range.startMs,
    endMs: range.endMs,
    sourceOrder,
    recordOrder,
    item: {
      id: opaqueId("commitment", provenance),
      kind: "commitment",
      title,
      reason,
      whenLabel,
      temporal,
    },
  };
}

function compareCalendarCandidates(
  left: CalendarCandidate,
  right: CalendarCandidate,
): number {
  if (left.startMs !== right.startMs) {
    return left.startMs - right.startMs;
  }
  if (left.endMs !== right.endMs) {
    return left.endMs - right.endMs;
  }
  return left.sourceOrder !== right.sourceOrder
    ? left.sourceOrder - right.sourceOrder
    : left.recordOrder - right.recordOrder;
}

function reminderItems(
  source: MirrorBackedBoardSource,
  snapshot: AppleBridgeStatusSnapshotV1,
  reads: SelectedSourceRead[],
  now: Date,
  timeZone: string,
): TaskItem[] {
  const today = boardLocalDate(now, timeZone);
  const candidates: ReminderCandidate[] = [];
  for (const read of reads) {
    if (read.status.entityType !== "reminder" || !read.summary) {
      continue;
    }
    const coordinate: AppleReminderSourceScopeCoordinate = {
      bridgeId: snapshot.bridgeId,
      entityType: "reminder",
      sourceContainerId: read.status.sourceContainerId,
    };
    for (const [recordOrder, record] of source
      .listReminderRecords(coordinate)
      .entries()) {
      const candidate = reminderCandidate(
        record,
        [
          snapshot.bridgeId,
          "reminder",
          read.status.sourceContainerId,
          record.localIdentifier,
          record.externalIdentifier ?? "",
        ].join("\0"),
        read.sourceOrder,
        recordOrder,
        today,
        timeZone,
      );
      if (candidate) {
        candidates.push(candidate);
      }
    }
  }
  return candidates
    .sort(compareReminderCandidates)
    .slice(0, 3)
    .map((candidate) => candidate.item);
}

function calendarItems(
  source: MirrorBackedBoardSource,
  snapshot: AppleBridgeStatusSnapshotV1,
  reads: SelectedSourceRead[],
  now: Date,
  timeZone: string,
): CommitmentItem[] {
  const today = boardLocalDate(now, timeZone);
  const candidates: CalendarCandidate[] = [];
  for (const read of reads) {
    if (
      read.status.entityType !== "calendar" ||
      !read.summary ||
      read.summary.entityType !== "calendar"
    ) {
      continue;
    }
    const coordinate: AppleCalendarSourceScopeCoordinate = {
      bridgeId: snapshot.bridgeId,
      entityType: "calendar",
      sourceContainerId: read.status.sourceContainerId,
    };
    for (const [recordOrder, record] of source
      .listCalendarRecordsInLatestWindow(coordinate)
      .entries()) {
      const candidate = calendarCandidate(
        record,
        read.summary.window.timeZone,
        [
          snapshot.bridgeId,
          "calendar",
          read.status.sourceContainerId,
          record.localIdentifier,
          record.eventIdentifier ?? "",
          record.occurrenceDate ?? "",
          record.externalIdentifier ?? "",
        ].join("\0"),
        read.sourceOrder,
        recordOrder,
        now,
        today,
        timeZone,
      );
      if (candidate) {
        candidates.push(candidate);
      }
    }
  }
  return candidates
    .sort(compareCalendarCandidates)
    .slice(0, 2)
    .map((candidate) => candidate.item);
}

export function composeMirrorBackedBoard(
  options: MirrorBackedBoardOptions,
): MirrorBackedBoardResult {
  try {
    const now = (options.clock ?? (() => new Date()))();
    const snapshot = options.source.readBridgeStatus(
      options.expectedBridgeId,
    );
    const reads = snapshot ? selectedReads(options.source, snapshot) : [];
    const remindersFreshness = freshnessForEntity(
      "reminder",
      snapshot,
      reads,
      now.getTime(),
    );
    const calendarFreshness = freshnessForEntity(
      "calendar",
      snapshot,
      reads,
      now.getTime(),
    );
    const todayItems = snapshot
      ? reminderItems(
          options.source,
          snapshot,
          reads,
          now,
          options.timeZone,
        )
      : [];
    const nextItems = snapshot
      ? calendarItems(
          options.source,
          snapshot,
          reads,
          now,
          options.timeZone,
        )
      : [];
    const semanticBoard = {
      schemaVersion: 1 as const,
      freshness: {
        reminders: remindersFreshness,
        calendar: calendarFreshness,
      },
      today: { label: "Today" as const, items: todayItems },
      next: { label: "Next" as const, items: nextItems },
      ...(options.sidewaysPrompt
        ? { sidewaysPrompt: options.sidewaysPrompt }
        : {}),
    };
    const boardVersion = `apple-mirror-${createHash("sha256")
      .update(canonicalJson(semanticBoard))
      .digest("hex")
      .slice(0, 32)}`;
    const board = boardSnapshotSchema.parse({
      ...semanticBoard,
      boardVersion,
      generatedAt: now.toISOString(),
    });

    const ordinals = new Map<"calendar" | "reminder", number>();
    const sources =
      snapshot?.selectedSources.map((sourceStatus) => {
        const ordinal = (ordinals.get(sourceStatus.entityType) ?? 0) + 1;
        ordinals.set(sourceStatus.entityType, ordinal);
        return {
          source: `${sourceStatus.entityType === "calendar" ? "Calendar" : "Reminder"} source ${ordinal}`,
          health: sourceStatus.status,
        };
      }) ?? [];
    const acceptanceSummary: ContentFreeBoardAcceptanceSummary = {
      schemaValid: true,
      todayItemCount: board.today.items.length,
      nextItemCount: board.next.items.length,
      calendarFreshness: board.freshness.calendar.status,
      remindersFreshness: board.freshness.reminders.status,
      selectedSourceCounts: {
        calendar:
          snapshot?.selectedSources.filter(
            (sourceStatus) => sourceStatus.entityType === "calendar",
          ).length ?? 0,
        reminders:
          snapshot?.selectedSources.filter(
            (sourceStatus) => sourceStatus.entityType === "reminder",
          ).length ?? 0,
      },
      sources,
    };
    return { board, acceptanceSummary };
  } catch (error) {
    if (error instanceof MirrorBackedBoardCompositionError) {
      throw error;
    }
    throw new MirrorBackedBoardCompositionError();
  }
}
