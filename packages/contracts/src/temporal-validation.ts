const CALENDAR_DATE_PATTERN = /^(\d{4})-(\d{2})-(\d{2})$/;
const LOCAL_DATE_TIME_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?$/;
const ISO_INSTANT_PATTERN =
  /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-]\d{2}:\d{2})$/;

function isLeapYear(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

export function isCalendarDate(value: string): boolean {
  const match = CALENDAR_DATE_PATTERN.exec(value);

  if (!match) {
    return false;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);

  if (year < 1 || month < 1 || month > 12 || day < 1) {
    return false;
  }

  const daysInMonth = [
    31,
    isLeapYear(year) ? 29 : 28,
    31,
    30,
    31,
    30,
    31,
    31,
    30,
    31,
    30,
    31,
  ];

  return day <= (daysInMonth[month - 1] ?? 0);
}

function isClockTime(hour: string, minute: string, second: string): boolean {
  return Number(hour) <= 23 && Number(minute) <= 59 && Number(second) <= 59;
}

export function isLocalDateTime(value: string): boolean {
  const match = LOCAL_DATE_TIME_PATTERN.exec(value);

  if (!match) {
    return false;
  }

  return (
    isCalendarDate(`${match[1]}-${match[2]}-${match[3]}`) &&
    isClockTime(match[4] ?? "", match[5] ?? "", match[6] ?? "")
  );
}

export function isIsoInstant(value: string): boolean {
  const match = ISO_INSTANT_PATTERN.exec(value);

  if (!match) {
    return false;
  }

  const offset = match[7] ?? "";
  if (offset !== "Z") {
    const [offsetHour, offsetMinute] = offset.slice(1).split(":");
    if (Number(offsetHour) > 23 || Number(offsetMinute) > 59) {
      return false;
    }
  }

  return (
    isCalendarDate(`${match[1]}-${match[2]}-${match[3]}`) &&
    isClockTime(match[4] ?? "", match[5] ?? "", match[6] ?? "") &&
    !Number.isNaN(Date.parse(value))
  );
}
