import type { AppleCalendarSourceRecordV1 } from "@deskboard/contracts";

const localDateTimePattern =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$/;

interface LocalDateTimeParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

export interface InterpretedCalendarRange {
  startMs: number;
  endMs: number;
}

const formatterCache = new Map<string, Intl.DateTimeFormat>();

function parseLocalDateTime(value: string): LocalDateTimeParts | undefined {
  const match = localDateTimePattern.exec(value);
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

function dateTimeFormatter(timeZone: string): Intl.DateTimeFormat | undefined {
  const cached = formatterCache.get(timeZone);
  if (cached) {
    return cached;
  }

  try {
    const formatter = new Intl.DateTimeFormat(
      "en-US-u-ca-gregory-nu-latn",
      {
        timeZone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        second: "2-digit",
        hourCycle: "h23",
      },
    );
    formatterCache.set(timeZone, formatter);
    return formatter;
  } catch {
    return undefined;
  }
}

function representedParts(
  epochMilliseconds: number,
  timeZone: string,
): LocalDateTimeParts | undefined {
  const formatter = dateTimeFormatter(timeZone);
  if (!formatter) {
    return undefined;
  }

  const values = new Map(
    formatter
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

export function interpretLocalDateTimeInTimeZone(
  value: string,
  timeZone: string,
): number | undefined {
  const desired = parseLocalDateTime(value);
  if (!desired) {
    return undefined;
  }

  const desiredAsUtc = utcMilliseconds(desired);
  const candidates = new Set<number>();
  const hourMilliseconds = 60 * 60 * 1000;

  // This mirrors the accepted Phase 2B resolver: round-trip every offset
  // observed around the civil value, then accept exactly one resulting instant.
  for (let hour = -48; hour <= 48; hour += 6) {
    const sampleInstant = desiredAsUtc + hour * hourMilliseconds;
    const represented = representedParts(sampleInstant, timeZone);
    if (!represented) {
      continue;
    }

    const offset = utcMilliseconds(represented) - sampleInstant;
    const candidate = desiredAsUtc - offset;
    const verified = representedParts(candidate, timeZone);
    if (verified && sameParts(verified, desired)) {
      candidates.add(candidate);
    }
  }

  return candidates.size === 1 ? [...candidates][0] : undefined;
}

export function interpretAppleCalendarRecordRange(
  record: AppleCalendarSourceRecordV1,
  windowTimeZone: string,
): InterpretedCalendarRange | undefined {
  if (record.temporal.kind === "timeZoneTimedRange") {
    const startMs = Date.parse(record.temporal.start);
    const endMs = Date.parse(record.temporal.end);
    return Number.isFinite(startMs) && Number.isFinite(endMs) && endMs > startMs
      ? { startMs, endMs }
      : undefined;
  }

  const startValue =
    record.temporal.kind === "allDayRange"
      ? `${record.temporal.startDate}T00:00:00`
      : record.temporal.startLocalDateTime;
  const endValue =
    record.temporal.kind === "allDayRange"
      ? `${record.temporal.endDate}T00:00:00`
      : record.temporal.endLocalDateTime;
  const startMs = interpretLocalDateTimeInTimeZone(
    startValue,
    windowTimeZone,
  );
  const endMs = interpretLocalDateTimeInTimeZone(
    endValue,
    windowTimeZone,
  );

  return startMs !== undefined && endMs !== undefined && endMs > startMs
    ? { startMs, endMs }
    : undefined;
}
