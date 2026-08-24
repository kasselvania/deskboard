import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

import { appleBridgeStatusSnapshotV1Schema } from "../src/index";

const fixtureDirectory = fileURLToPath(
  new URL("../../../fixtures/apple-bridge-status/v1/", import.meta.url),
);

const validFixtureNames = [
  "empty-independent-permissions.json",
  "selected-applied.json",
  "selected-blocked-invalid.json",
  "selected-retry-pending.json",
  "selected-unavailable.json",
] as const;

const invalidFixtureNames = [
  "acknowledged-without-time.json",
  "duplicate-coordinate.json",
  "excluded-source-title.json",
  "invalid-captured-at.json",
  "pending-revision-gap.json",
  "retry-without-pending.json",
  "success-with-pending.json",
  "unknown-delivery-key.json",
  "unknown-permission.json",
  "unknown-top-level-key.json",
  "unordered-coordinate.json",
  "unsupported-schema-version.json",
  "zero-status-revision.json",
] as const;

async function readFixture(
  collection: "valid" | "invalid",
  fixtureName: string,
): Promise<unknown> {
  return JSON.parse(
    await readFile(
      new URL(`${collection}/${fixtureName}`, `file://${fixtureDirectory}/`),
      "utf8",
    ),
  ) as unknown;
}

describe("Apple Bridge status snapshot v1", () => {
  it("locks the exact shared valid and invalid fixture inventories", async () => {
    const validFiles = (await readdir(`${fixtureDirectory}/valid`))
      .filter((path) => path.endsWith(".json"))
      .sort();
    const invalidFiles = (await readdir(`${fixtureDirectory}/invalid`))
      .filter((path) => path.endsWith(".json"))
      .sort();

    expect(validFiles).toEqual([...validFixtureNames].sort());
    expect(invalidFiles).toEqual([...invalidFixtureNames].sort());
  });

  it("accepts every shared valid fixture", async () => {
    for (const fixtureName of validFixtureNames) {
      expect(
        appleBridgeStatusSnapshotV1Schema.safeParse(
          await readFixture("valid", fixtureName),
        ).success,
        fixtureName,
      ).toBe(true);
    }
  });

  it("rejects every shared invalid fixture", async () => {
    for (const fixtureName of invalidFixtureNames) {
      expect(
        appleBridgeStatusSnapshotV1Schema.safeParse(
          await readFixture("invalid", fixtureName),
        ).success,
        fixtureName,
      ).toBe(false);
    }
  });
});
