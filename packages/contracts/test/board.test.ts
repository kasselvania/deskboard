import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { boardSnapshotSchema, isCalendarDate } from "../src/index";

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
});
