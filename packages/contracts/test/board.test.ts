import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import {
  BOARD_TEXT_LIMITS,
  boardSnapshotSchema,
  isCalendarDate,
  type BoardSnapshot,
} from "../src/index";

const fixtureDirectory = fileURLToPath(
  new URL("../../../fixtures/board/", import.meta.url),
);

async function readFixture(relativePath: string): Promise<unknown> {
  const fixture = await readFile(
    new URL(relativePath, `file://${fixtureDirectory}/`),
    "utf8",
  );
  return JSON.parse(fixture) as unknown;
}

describe("BoardSnapshot contract", () => {
  for (const fixtureName of ["default.json", "empty.json", "stale.json"]) {
    it(`accepts ${fixtureName}`, async () => {
      const result = boardSnapshotSchema.safeParse(await readFixture(fixtureName));
      expect(result.success).toBe(true);
    });
  }

  it("rejects every committed malformed fixture", async () => {
    const invalidFixtureNames = await readdir(`${fixtureDirectory}/invalid`);
    expect(invalidFixtureNames).toHaveLength(6);

    for (const fixtureName of invalidFixtureNames) {
      const result = boardSnapshotSchema.safeParse(
        await readFixture(`invalid/${fixtureName}`),
      );
      expect(result.success, fixtureName).toBe(false);
    }
  });

  it("fails unsupported schema versions explicitly", async () => {
    const result = boardSnapshotSchema.safeParse(
      await readFixture("invalid/unsupported-version.json"),
    );

    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.error.issues[0]?.message).toContain(
        "Unsupported schemaVersion 2",
      );
    }
  });

  it("rejects impossible calendar dates while accepting leap days", async () => {
    expect(isCalendarDate("2028-02-29")).toBe(true);
    expect(isCalendarDate("2026-02-29")).toBe(false);
    expect(isCalendarDate("2026-02-30")).toBe(false);

    const result = boardSnapshotSchema.safeParse(
      await readFixture("invalid/invalid-date.json"),
    );
    expect(result.success).toBe(false);
  });

  it("does not accept a date-only value for a timed commitment", async () => {
    const result = boardSnapshotSchema.safeParse(
      await readFixture("invalid/timed-as-date.json"),
    );
    expect(result.success).toBe(false);
  });

  it("enforces the Today and Next capacities", async () => {
    const todayResult = boardSnapshotSchema.safeParse(
      await readFixture("invalid/too-many-today.json"),
    );
    const nextResult = boardSnapshotSchema.safeParse(
      await readFixture("invalid/too-many-next.json"),
    );

    expect(todayResult.success).toBe(false);
    expect(nextResult.success).toBe(false);
  });

  it("validates generatedAt and freshness timestamps as ISO instants", async () => {
    const candidate = (await readFixture("empty.json")) as Record<
      string,
      unknown
    >;
    candidate.generatedAt = "2026-02-30T17:05:00Z";

    expect(boardSnapshotSchema.safeParse(candidate).success).toBe(false);
  });

  it("rejects text beyond each field-specific display limit", async () => {
    const validBoard = boardSnapshotSchema.parse(
      await readFixture("default.json"),
    );
    const cases: Array<{
      field: string;
      limit: number;
      change: (board: BoardSnapshot, value: string) => void;
    }> = [
      {
        field: "id",
        limit: BOARD_TEXT_LIMITS.id,
        change: (board, value) => {
          board.today.items[0]!.id = value;
        },
      },
      {
        field: "boardVersion",
        limit: BOARD_TEXT_LIMITS.boardVersion,
        change: (board, value) => {
          board.boardVersion = value;
        },
      },
      {
        field: "title",
        limit: BOARD_TEXT_LIMITS.title,
        change: (board, value) => {
          board.today.items[0]!.title = value;
        },
      },
      {
        field: "reason",
        limit: BOARD_TEXT_LIMITS.reason,
        change: (board, value) => {
          board.today.items[0]!.reason = value;
        },
      },
      {
        field: "whenLabel",
        limit: BOARD_TEXT_LIMITS.whenLabel,
        change: (board, value) => {
          board.next.items[0]!.whenLabel = value;
        },
      },
      {
        field: "Sideways Prompt",
        limit: BOARD_TEXT_LIMITS.sidewaysPrompt,
        change: (board, value) => {
          board.sidewaysPrompt!.text = value;
        },
      },
      {
        field: "timeZone",
        limit: BOARD_TEXT_LIMITS.timeZone,
        change: (board, value) => {
          const temporal = board.next.items[0]!.temporal;
          if (temporal.kind === "dateTime") {
            temporal.timeZone = value;
          }
        },
      },
    ];

    for (const testCase of cases) {
      const candidate = structuredClone(validBoard);
      testCase.change(candidate, "x".repeat(testCase.limit + 1));

      expect(
        boardSnapshotSchema.safeParse(candidate).success,
        testCase.field,
      ).toBe(false);
    }
  });
});
