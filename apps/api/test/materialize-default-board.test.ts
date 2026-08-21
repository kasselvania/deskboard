import { readFile } from "node:fs/promises";

import { boardSnapshotSchema } from "@deskboard/contracts";
import { describe, expect, it } from "vitest";

import { materializeDefaultBoard } from "../src/materialize-default-board";

const fixtureUrl = new URL(
  "../../../fixtures/board/default.json",
  import.meta.url,
);

async function readTemplate() {
  return boardSnapshotSchema.parse(
    JSON.parse(await readFile(fixtureUrl, "utf8")) as unknown,
  );
}

describe("default Board materialization", () => {
  it("makes a frozen August 21 specimen temporally coherent", async () => {
    const template = await readTemplate();
    const now = new Date(2026, 7, 21, 10, 5, 0);
    const board = materializeDefaultBoard(template, () => now);

    expect(boardSnapshotSchema.safeParse(board).success).toBe(true);
    expect(board.generatedAt).toBe(now.toISOString());
    expect(board.freshness.reminders.updatedAt).toBe(
      new Date(now.getTime() - 60_000).toISOString(),
    );
    expect(board.freshness.calendar.updatedAt).toBe(
      new Date(now.getTime() - 120_000).toISOString(),
    );
    expect(board.today.items[0]).toMatchObject({
      whenLabel: "Today",
      temporal: { kind: "date", localDate: "2026-08-21" },
    });
    expect(board.today.items[2]).toMatchObject({
      whenLabel: "Before 5:30 PM",
      temporal: {
        kind: "dateTime",
        localDateTime: "2026-08-21T17:30:00",
      },
    });
    expect(board.next.items[0]).toMatchObject({
      whenLabel: "Tomorrow · 9:30 AM",
      temporal: {
        kind: "dateTime",
        localDateTime: "2026-08-22T09:30:00",
      },
    });
    expect(board.next.items[1]).toMatchObject({
      whenLabel: "Sunday · all day",
      temporal: {
        kind: "allDay",
        startDate: "2026-08-23",
        endDate: "2026-08-24",
      },
    });
  });

  it("advances Today and Next semantics together by one local day", async () => {
    const template = await readTemplate();
    const august21 = materializeDefaultBoard(
      template,
      () => new Date(2026, 7, 21, 10, 5, 0),
    );
    const august22 = materializeDefaultBoard(
      template,
      () => new Date(2026, 7, 22, 10, 5, 0),
    );

    expect(august21.today.items[0]?.temporal).toMatchObject({
      localDate: "2026-08-21",
    });
    expect(august22.today.items[0]?.temporal).toMatchObject({
      localDate: "2026-08-22",
    });
    expect(august22.today.items[2]?.temporal).toMatchObject({
      localDateTime: "2026-08-22T17:30:00",
    });
    expect(august22.next.items[0]).toMatchObject({
      whenLabel: "Tomorrow · 9:30 AM",
      temporal: { localDateTime: "2026-08-23T09:30:00" },
    });
    expect(august22.next.items[1]).toMatchObject({
      whenLabel: "Monday · all day",
      temporal: {
        startDate: "2026-08-24",
        endDate: "2026-08-25",
      },
    });
  });

  it("is identical for the same clock and leaves the specimen untouched", async () => {
    const template = await readTemplate();
    const original = structuredClone(template);
    const frozen = new Date(2026, 7, 21, 10, 5, 0);
    const clock = () => frozen;

    expect(materializeDefaultBoard(template, clock)).toEqual(
      materializeDefaultBoard(template, clock),
    );
    expect(template).toEqual(original);
  });
});
