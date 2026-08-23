import { z } from "zod";

import {
  isCalendarDate,
  isIsoInstant,
  isLocalDateTime,
} from "./temporal-validation.js";

const CONTRACT_LOCAL_DATE_TIME_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/;

const opaqueIdentifierSchema = z.string().min(1);
const calendarDateSchema = z.string().refine(isCalendarDate, {
  message: "Expected a real Gregorian date in YYYY-MM-DD form.",
});
const localDateTimeSchema = z
  .string()
  .regex(
    CONTRACT_LOCAL_DATE_TIME_PATTERN,
    "Expected YYYY-MM-DDTHH:mm:ss without an offset.",
  )
  .refine(isLocalDateTime, {
    message: "Expected a real Gregorian local date-time.",
  });
const isoInstantSchema = z.string().refine(isIsoInstant, {
  message: "Expected a valid ISO 8601 instant with a UTC offset.",
});

export function isRecognizedTimeZone(value: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}

const timeZoneSchema = z.string().min(1).refine(isRecognizedTimeZone, {
  message: "Expected a recognized time-zone identifier.",
});

export const appleReminderAbsentTemporalSchema = z
  .object({
    kind: z.literal("absent"),
  })
  .strict();

export const appleReminderDateOnlyTemporalSchema = z
  .object({
    kind: z.literal("dateOnly"),
    localDate: calendarDateSchema,
  })
  .strict();

export const appleReminderLocalDateTimeTemporalSchema = z
  .object({
    kind: z.literal("localDateTime"),
    localDateTime: localDateTimeSchema,
  })
  .strict();

export const appleReminderTimeZoneDateTimeTemporalSchema = z
  .object({
    kind: z.literal("timeZoneDateTime"),
    localDateTime: localDateTimeSchema,
    timeZone: timeZoneSchema,
  })
  .strict();

export const appleReminderTemporalSchema = z.discriminatedUnion("kind", [
  appleReminderAbsentTemporalSchema,
  appleReminderDateOnlyTemporalSchema,
  appleReminderLocalDateTimeTemporalSchema,
  appleReminderTimeZoneDateTimeTemporalSchema,
]);

function compareFixedLocalDateTimes(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

function compareCalendarDates(left: string, right: string): number {
  return left < right ? -1 : left > right ? 1 : 0;
}

export const appleCalendarLocalTimedRangeSchema = z
  .object({
    kind: z.literal("localTimedRange"),
    startLocalDateTime: localDateTimeSchema,
    endLocalDateTime: localDateTimeSchema,
  })
  .strict()
  .superRefine((value, context) => {
    if (
      compareFixedLocalDateTimes(
        value.startLocalDateTime,
        value.endLocalDateTime,
      ) >= 0
    ) {
      context.addIssue({
        code: "custom",
        path: ["endLocalDateTime"],
        message: "Timed range end must be later than its start.",
      });
    }
  });

export const appleCalendarTimeZoneTimedRangeSchema = z
  .object({
    kind: z.literal("timeZoneTimedRange"),
    start: isoInstantSchema,
    end: isoInstantSchema,
    timeZone: timeZoneSchema,
  })
  .strict()
  .superRefine((value, context) => {
    if (Date.parse(value.end) <= Date.parse(value.start)) {
      context.addIssue({
        code: "custom",
        path: ["end"],
        message: "Timezone-qualified end instant must be later than its start.",
      });
    }
  });

export const appleCalendarAllDayRangeSchema = z
  .object({
    kind: z.literal("allDayRange"),
    startDate: calendarDateSchema,
    endDate: calendarDateSchema,
  })
  .strict()
  .superRefine((value, context) => {
    if (compareCalendarDates(value.startDate, value.endDate) >= 0) {
      context.addIssue({
        code: "custom",
        path: ["endDate"],
        message: "Exclusive all-day end must be later than its start.",
      });
    }
  });

export const appleCalendarTemporalSchema = z.discriminatedUnion("kind", [
  appleCalendarLocalTimedRangeSchema,
  appleCalendarTimeZoneTimedRangeSchema,
  appleCalendarAllDayRangeSchema,
]);

export const appleReminderSourceRecordV1Schema = z
  .object({
    localIdentifier: opaqueIdentifierSchema,
    externalIdentifier: opaqueIdentifierSchema.optional(),
    title: z.string().optional(),
    start: appleReminderTemporalSchema,
    due: appleReminderTemporalSchema,
    isCompleted: z.boolean(),
    completionDate: isoInstantSchema.optional(),
  })
  .strict()
  .superRefine((value, context) => {
    if (!value.isCompleted && value.completionDate !== undefined) {
      context.addIssue({
        code: "custom",
        path: ["completionDate"],
        message: "An incomplete Reminder cannot have a completion date.",
      });
    }
  });

export const appleCalendarSourceRecordV1Schema = z
  .object({
    localIdentifier: opaqueIdentifierSchema,
    eventIdentifier: opaqueIdentifierSchema.optional(),
    externalIdentifier: opaqueIdentifierSchema.optional(),
    title: z.string().optional(),
    temporal: appleCalendarTemporalSchema,
    occurrenceDate: isoInstantSchema.optional(),
    isDetached: z.boolean(),
    status: z.enum(["none", "confirmed", "tentative", "canceled"]),
  })
  .strict();

export const appleReminderSourceScopeV1Schema = z
  .object({
    sourceContainerId: opaqueIdentifierSchema,
    allowsContentModifications: z.boolean(),
  })
  .strict();

export const appleCalendarSourceScopeV1Schema = z
  .object({
    sourceContainerId: opaqueIdentifierSchema,
    allowsContentModifications: z.boolean(),
    isSubscribed: z.boolean(),
  })
  .strict();

export const appleCalendarWindowV1Schema = z
  .object({
    start: isoInstantSchema,
    end: isoInstantSchema,
    timeZone: timeZoneSchema,
    boundarySemantics: z.literal("overlapStartInclusiveEndExclusive"),
  })
  .strict()
  .superRefine((value, context) => {
    if (Date.parse(value.end) <= Date.parse(value.start)) {
      context.addIssue({
        code: "custom",
        path: ["end"],
        message: "Calendar scope end must be later than its start.",
      });
    }
  });

interface CountedSnapshot {
  matchedCount: number;
  truncated: boolean;
  records: readonly unknown[];
}

function validateCountAndTruncation(
  value: CountedSnapshot,
  context: z.RefinementCtx,
): void {
  const retainedCount = value.records.length;

  if (value.matchedCount < retainedCount) {
    context.addIssue({
      code: "custom",
      path: ["matchedCount"],
      message: "matchedCount cannot be less than records.length.",
    });
  }

  if (!value.truncated && value.matchedCount !== retainedCount) {
    context.addIssue({
      code: "custom",
      path: ["matchedCount"],
      message:
        "A non-truncated snapshot must retain every matched source record.",
    });
  }

  if (value.truncated && value.matchedCount <= retainedCount) {
    context.addIssue({
      code: "custom",
      path: ["truncated"],
      message: "A truncated snapshot must omit at least one matched record.",
    });
  }
}

function compareUnicodeScalars(left: string, right: string): number {
  const leftScalars = Array.from(left, (value) => value.codePointAt(0) ?? 0);
  const rightScalars = Array.from(right, (value) => value.codePointAt(0) ?? 0);
  const sharedLength = Math.min(leftScalars.length, rightScalars.length);

  for (let index = 0; index < sharedLength; index += 1) {
    const leftValue = leftScalars[index] ?? 0;
    const rightValue = rightScalars[index] ?? 0;
    if (leftValue !== rightValue) {
      return leftValue < rightValue ? -1 : 1;
    }
  }

  return leftScalars.length < rightScalars.length
    ? -1
    : leftScalars.length > rightScalars.length
      ? 1
      : 0;
}

function compareOptionalIdentifiers(
  left: string | undefined,
  right: string | undefined,
): number {
  if (left === undefined) {
    return right === undefined ? 0 : -1;
  }
  if (right === undefined) {
    return 1;
  }
  return compareUnicodeScalars(left, right);
}

function compareOptionalInstants(
  left: string | undefined,
  right: string | undefined,
): number {
  if (left === undefined) {
    return right === undefined ? 0 : -1;
  }
  if (right === undefined) {
    return 1;
  }
  const leftInstant = Date.parse(left);
  const rightInstant = Date.parse(right);
  return leftInstant < rightInstant ? -1 : leftInstant > rightInstant ? 1 : 0;
}

export type AppleReminderSourceRecordV1 = z.infer<
  typeof appleReminderSourceRecordV1Schema
>;
export type AppleCalendarSourceRecordV1 = z.infer<
  typeof appleCalendarSourceRecordV1Schema
>;

export function compareAppleReminderSourceRecordsV1(
  left: AppleReminderSourceRecordV1,
  right: AppleReminderSourceRecordV1,
  leftSourceContainerId: string,
  rightSourceContainerId: string,
): number {
  const sourceComparison = compareUnicodeScalars(
    leftSourceContainerId,
    rightSourceContainerId,
  );
  if (sourceComparison !== 0) {
    return sourceComparison;
  }

  const localComparison = compareUnicodeScalars(
    left.localIdentifier,
    right.localIdentifier,
  );
  return localComparison !== 0
    ? localComparison
    : compareOptionalIdentifiers(
        left.externalIdentifier,
        right.externalIdentifier,
      );
}

interface LocalDateTimeParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

function parseLocalDateTime(value: string): LocalDateTimeParts | undefined {
  const match = CONTRACT_LOCAL_DATE_TIME_PATTERN.exec(value);
  if (!match) {
    return undefined;
  }

  return {
    year: Number(match[1]),
    month: Number(match[2]),
    day: Number(match[3]),
    hour: Number(match[4]),
    minute: Number(match[5]),
    second: Number(match[6]),
  };
}

function utcMilliseconds(parts: LocalDateTimeParts): number {
  const value = new Date(0);
  value.setUTCFullYear(parts.year, parts.month - 1, parts.day);
  value.setUTCHours(parts.hour, parts.minute, parts.second, 0);
  return value.getTime();
}

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function dateTimeFormatter(timeZone: string): Intl.DateTimeFormat {
  const cached = formatterCache.get(timeZone);
  if (cached) {
    return cached;
  }

  const formatter = new Intl.DateTimeFormat("en-US-u-ca-gregory-nu-latn", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  formatterCache.set(timeZone, formatter);
  return formatter;
}

function representedParts(
  epochMilliseconds: number,
  timeZone: string,
): LocalDateTimeParts | undefined {
  const values = new Map(
    dateTimeFormatter(timeZone)
      .formatToParts(new Date(epochMilliseconds))
      .map((part) => [part.type, part.value]),
  );
  const parts = {
    year: Number(values.get("year")),
    month: Number(values.get("month")),
    day: Number(values.get("day")),
    hour: Number(values.get("hour")),
    minute: Number(values.get("minute")),
    second: Number(values.get("second")),
  };

  return Object.values(parts).every(Number.isFinite) ? parts : undefined;
}

function sameParts(
  left: LocalDateTimeParts,
  right: LocalDateTimeParts,
): boolean {
  return (
    left.year === right.year &&
    left.month === right.month &&
    left.day === right.day &&
    left.hour === right.hour &&
    left.minute === right.minute &&
    left.second === right.second
  );
}

function localDateTimeCandidateEpochMilliseconds(
  value: string,
  timeZone: string,
): number[] {
  const desired = parseLocalDateTime(value);
  if (!desired || !isRecognizedTimeZone(timeZone)) {
    return [];
  }

  const desiredAsUTC = utcMilliseconds(desired);
  const candidates = new Set<number>();
  const hourMilliseconds = 60 * 60 * 1000;

  // Offset samples on both sides of the civil value expose both sides of an
  // ordinary time-zone transition. Every sampled offset is used to construct
  // and round-trip an exact candidate; zero or multiple candidates are
  // rejected by the caller instead of silently selecting one.
  for (let hour = -48; hour <= 48; hour += 6) {
    const sampleInstant = desiredAsUTC + hour * hourMilliseconds;
    const represented = representedParts(sampleInstant, timeZone);
    if (!represented) {
      continue;
    }
    const offset = utcMilliseconds(represented) - sampleInstant;
    const candidate = desiredAsUTC - offset;
    const verified = representedParts(candidate, timeZone);
    if (verified && sameParts(verified, desired)) {
      candidates.add(candidate);
    }
  }

  return [...candidates].sort((left, right) => left - right);
}

function unambiguousLocalDateTimeToEpochMilliseconds(
  value: string,
  timeZone: string,
): number | undefined {
  const candidates = localDateTimeCandidateEpochMilliseconds(value, timeZone);
  return candidates.length === 1 ? candidates[0] : undefined;
}

function dateOnlyToLocalMidnight(value: string): string {
  return `${value}T00:00:00`;
}

interface CalendarSortBounds {
  start: number;
  end: number;
}

function calendarSortBounds(
  record: AppleCalendarSourceRecordV1,
  windowTimeZone: string,
): CalendarSortBounds | undefined {
  const temporal = record.temporal;
  if (temporal.kind === "timeZoneTimedRange") {
    return {
      start: Date.parse(temporal.start),
      end: Date.parse(temporal.end),
    };
  }

  const startValue =
    temporal.kind === "allDayRange"
      ? dateOnlyToLocalMidnight(temporal.startDate)
      : temporal.startLocalDateTime;
  const endValue =
    temporal.kind === "allDayRange"
      ? dateOnlyToLocalMidnight(temporal.endDate)
      : temporal.endLocalDateTime;
  const start = unambiguousLocalDateTimeToEpochMilliseconds(
    startValue,
    windowTimeZone,
  );
  const end = unambiguousLocalDateTimeToEpochMilliseconds(
    endValue,
    windowTimeZone,
  );

  return start === undefined || end === undefined ? undefined : { start, end };
}

export function compareAppleCalendarSourceRecordsV1(
  left: AppleCalendarSourceRecordV1,
  right: AppleCalendarSourceRecordV1,
  leftSourceContainerId: string,
  rightSourceContainerId: string,
  windowTimeZone: string,
): number | undefined {
  const leftBounds = calendarSortBounds(left, windowTimeZone);
  const rightBounds = calendarSortBounds(right, windowTimeZone);
  if (!leftBounds || !rightBounds) {
    return undefined;
  }

  if (leftBounds.start !== rightBounds.start) {
    return leftBounds.start < rightBounds.start ? -1 : 1;
  }
  if (leftBounds.end !== rightBounds.end) {
    return leftBounds.end < rightBounds.end ? -1 : 1;
  }

  const sourceComparison = compareUnicodeScalars(
    leftSourceContainerId,
    rightSourceContainerId,
  );
  if (sourceComparison !== 0) {
    return sourceComparison;
  }

  const localComparison = compareUnicodeScalars(
    left.localIdentifier,
    right.localIdentifier,
  );
  if (localComparison !== 0) {
    return localComparison;
  }

  const eventComparison = compareOptionalIdentifiers(
    left.eventIdentifier,
    right.eventIdentifier,
  );
  if (eventComparison !== 0) {
    return eventComparison;
  }

  const occurrenceComparison = compareOptionalInstants(
    left.occurrenceDate,
    right.occurrenceDate,
  );
  return occurrenceComparison !== 0
    ? occurrenceComparison
    : compareOptionalIdentifiers(
        left.externalIdentifier,
        right.externalIdentifier,
      );
}

export const appleReminderSourceSnapshotV1Schema = z
  .object({
    schemaVersion: z.literal(1),
    entityType: z.literal("reminder"),
    bridgeId: opaqueIdentifierSchema,
    source: appleReminderSourceScopeV1Schema,
    capturedAt: isoInstantSchema,
    matchedCount: z.number().int().nonnegative(),
    truncated: z.boolean(),
    records: z.array(appleReminderSourceRecordV1Schema),
  })
  .strict()
  .superRefine((value, context) => {
    validateCountAndTruncation(value, context);

    for (let index = 1; index < value.records.length; index += 1) {
      const previous = value.records[index - 1];
      const current = value.records[index];
      if (previous && current) {
        const comparison = compareAppleReminderSourceRecordsV1(
          previous,
          current,
          value.source.sourceContainerId,
          value.source.sourceContainerId,
        );
        if (comparison > 0) {
          context.addIssue({
            code: "custom",
            path: ["records", index],
            message:
              "Reminder records are not in deterministic provenance order.",
          });
        } else if (comparison === 0) {
          context.addIssue({
            code: "custom",
            path: ["records", index],
            message: "Reminder provenance ordering coordinate collides.",
          });
        }
      }
    }
  });

export const appleCalendarSourceSnapshotV1Schema = z
  .object({
    schemaVersion: z.literal(1),
    entityType: z.literal("calendar"),
    bridgeId: opaqueIdentifierSchema,
    source: appleCalendarSourceScopeV1Schema,
    capturedAt: isoInstantSchema,
    window: appleCalendarWindowV1Schema,
    matchedCount: z.number().int().nonnegative(),
    truncated: z.boolean(),
    records: z.array(appleCalendarSourceRecordV1Schema),
  })
  .strict()
  .superRefine((value, context) => {
    validateCountAndTruncation(value, context);

    const windowStart = Date.parse(value.window.start);
    const windowEnd = Date.parse(value.window.end);
    for (const [index, record] of value.records.entries()) {
      const bounds = calendarSortBounds(record, value.window.timeZone);
      if (!bounds) {
        context.addIssue({
          code: "custom",
          path: ["records", index, "temporal"],
          message:
            "Calendar temporal values cannot be interpreted in the declared scope time zone.",
        });
        continue;
      }
      if (bounds.end <= bounds.start) {
        context.addIssue({
          code: "custom",
          path: ["records", index, "temporal"],
          message: "Calendar temporal end must be later than its start.",
        });
        continue;
      }
      if (!(bounds.start < windowEnd && bounds.end > windowStart)) {
        context.addIssue({
          code: "custom",
          path: ["records", index, "temporal"],
          message:
            "Calendar record does not overlap the declared start-inclusive, end-exclusive window.",
        });
      }
    }

    for (let index = 1; index < value.records.length; index += 1) {
      const previous = value.records[index - 1];
      const current = value.records[index];
      if (!previous || !current) {
        continue;
      }
      const comparison = compareAppleCalendarSourceRecordsV1(
        previous,
        current,
        value.source.sourceContainerId,
        value.source.sourceContainerId,
        value.window.timeZone,
      );
      if (comparison !== undefined) {
        if (comparison > 0) {
          context.addIssue({
            code: "custom",
            path: ["records", index],
            message: "Calendar records are not in deterministic source order.",
          });
        } else if (comparison === 0) {
          context.addIssue({
            code: "custom",
            path: ["records", index],
            message: "Calendar provenance ordering coordinate collides.",
          });
        }
      }
    }
  });

export const appleSourceSnapshotV1Schema = z.union([
  appleReminderSourceSnapshotV1Schema,
  appleCalendarSourceSnapshotV1Schema,
]);

export type AppleReminderTemporal = z.infer<
  typeof appleReminderTemporalSchema
>;
export type AppleCalendarTemporal = z.infer<
  typeof appleCalendarTemporalSchema
>;
export type AppleReminderSourceScopeV1 = z.infer<
  typeof appleReminderSourceScopeV1Schema
>;
export type AppleCalendarSourceScopeV1 = z.infer<
  typeof appleCalendarSourceScopeV1Schema
>;
export type AppleCalendarWindowV1 = z.infer<
  typeof appleCalendarWindowV1Schema
>;
export type AppleReminderSourceSnapshotV1 = z.infer<
  typeof appleReminderSourceSnapshotV1Schema
>;
export type AppleCalendarSourceSnapshotV1 = z.infer<
  typeof appleCalendarSourceSnapshotV1Schema
>;
export type AppleSourceSnapshotV1 = z.infer<
  typeof appleSourceSnapshotV1Schema
>;

export function appleSourceSnapshotAuthorizesAbsence(
  input: unknown,
): boolean {
  const result = appleSourceSnapshotV1Schema.safeParse(input);
  return result.success && !result.data.truncated;
}

export function parseAppleReminderSourceSnapshotV1(
  input: unknown,
): AppleReminderSourceSnapshotV1 {
  return appleReminderSourceSnapshotV1Schema.parse(input);
}

export function parseAppleCalendarSourceSnapshotV1(
  input: unknown,
): AppleCalendarSourceSnapshotV1 {
  return appleCalendarSourceSnapshotV1Schema.parse(input);
}
