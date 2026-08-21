import {
  boardSnapshotSchema,
  type BoardSnapshot,
  type CommitmentItem,
  type TaskItem,
} from "@deskboard/contracts";

export type FixtureClock = () => Date;

const timeFormatter = new Intl.DateTimeFormat("en-US", {
  hour: "numeric",
  minute: "2-digit",
});
const weekdayFormatter = new Intl.DateTimeFormat("en-US", {
  weekday: "long",
});

function localCalendarDate(now: Date, dayOffset: number): string {
  const date = new Date(
    now.getFullYear(),
    now.getMonth(),
    now.getDate() + dayOffset,
    12,
  );
  const year = String(date.getFullYear()).padStart(4, "0");
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function localDateTimeOn(localDate: string, source: string): string {
  return `${localDate}${source.slice(10)}`;
}

function formattedTime(localDateTime: string): string {
  const hour = Number(localDateTime.slice(11, 13));
  const minute = Number(localDateTime.slice(14, 16));
  return timeFormatter.format(new Date(2000, 0, 1, hour, minute));
}

function weekdayFor(localDate: string): string {
  const [year, month, day] = localDate.split("-").map(Number);
  return weekdayFormatter.format(
    new Date(year ?? 0, (month ?? 1) - 1, day ?? 1, 12),
  );
}

function materializeTodayItem(item: TaskItem, today: string): TaskItem {
  if (!item.temporal) {
    return { ...item };
  }

  if (item.temporal.kind === "date") {
    return {
      ...item,
      whenLabel: "Today",
      temporal: { ...item.temporal, localDate: today },
    };
  }

  const localDateTime = localDateTimeOn(today, item.temporal.localDateTime);
  return {
    ...item,
    ...(item.whenLabel
      ? { whenLabel: `Before ${formattedTime(localDateTime)}` }
      : {}),
    temporal: { ...item.temporal, localDateTime },
  };
}

function materializeNextItem(
  item: CommitmentItem,
  tomorrow: string,
  followingDay: string,
  followingEnd: string,
): CommitmentItem {
  if (item.temporal.kind === "dateTime") {
    const localDateTime = localDateTimeOn(
      tomorrow,
      item.temporal.localDateTime,
    );
    return {
      ...item,
      whenLabel: `Tomorrow · ${formattedTime(localDateTime)}`,
      temporal: { ...item.temporal, localDateTime },
    };
  }

  return {
    ...item,
    whenLabel: `${weekdayFor(followingDay)} · all day`,
    temporal: {
      ...item.temporal,
      startDate: followingDay,
      endDate: followingEnd,
    },
  };
}

/** Materialize only the known default specimen; selection and ordering stay fixed. */
export function materializeDefaultBoard(
  template: BoardSnapshot,
  clock: FixtureClock,
): BoardSnapshot {
  const now = clock();
  const today = localCalendarDate(now, 0);
  const tomorrow = localCalendarDate(now, 1);
  const followingDay = localCalendarDate(now, 2);
  const followingEnd = localCalendarDate(now, 3);

  return boardSnapshotSchema.parse({
    ...template,
    generatedAt: now.toISOString(),
    freshness: {
      reminders: {
        ...template.freshness.reminders,
        updatedAt: new Date(now.getTime() - 60_000).toISOString(),
      },
      calendar: {
        ...template.freshness.calendar,
        updatedAt: new Date(now.getTime() - 120_000).toISOString(),
      },
    },
    today: {
      ...template.today,
      items: template.today.items.map((item) =>
        materializeTodayItem(item, today),
      ),
    },
    next: {
      ...template.next,
      items: template.next.items.map((item) =>
        materializeNextItem(item, tomorrow, followingDay, followingEnd),
      ),
    },
  });
}
