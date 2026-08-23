import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

import {
  appleReminderSourceRecordV1Schema,
  appleSourceSnapshotV1Schema,
} from "@deskboard/contracts";
import { afterEach, describe, expect, it } from "vitest";

import {
  AppleSourceMirror,
  AppleSourceMirrorReadError,
  type AppleSourceScopeCoordinate,
} from "../src/apple-source-mirror/index";
import {
  invalidContractFixtureNames,
  readContractFixture,
  validContractFixtureNames,
} from "./apple-source-mirror-fixtures";

const fixtureRoot = new URL(
  "../../../fixtures/apple-source-contract/v1/",
  import.meta.url,
);
const openMirrors: AppleSourceMirror[] = [];
const temporaryDirectories: string[] = [];

function openMirror(
  options?: ConstructorParameters<typeof AppleSourceMirror>[0],
): AppleSourceMirror {
  const mirror = new AppleSourceMirror(options);
  openMirrors.push(mirror);
  return mirror;
}

afterEach(async () => {
  for (const mirror of openMirrors.splice(0)) {
    mirror.close();
  }
  await Promise.all(
    temporaryDirectories.splice(0).map((directory) =>
      rm(directory, { recursive: true, force: true }),
    ),
  );
});

function possibleCoordinate(value: unknown): AppleSourceScopeCoordinate | null {
  if (typeof value !== "object" || value === null) {
    return null;
  }
  const candidate = value as Record<string, unknown>;
  const source = candidate.source;
  if (typeof source !== "object" || source === null) {
    return null;
  }
  const sourceContainerId = (source as Record<string, unknown>)
    .sourceContainerId;
  if (
    typeof candidate.bridgeId !== "string" ||
    (candidate.entityType !== "reminder" &&
      candidate.entityType !== "calendar") ||
    typeof sourceContainerId !== "string"
  ) {
    return null;
  }
  return {
    bridgeId: candidate.bridgeId,
    entityType: candidate.entityType,
    sourceContainerId,
  };
}

describe("Apple source mirror contract boundary", () => {
  it("enumerates and accepts every shared valid Phase 2B fixture", async () => {
    const validFiles = (await readdir(new URL("valid/", fixtureRoot)))
      .filter((path) => path.endsWith(".json"))
      .sort();
    expect(validFiles).toEqual([...validContractFixtureNames].sort());

    for (const fixtureName of validContractFixtureNames) {
      const fixture = await readContractFixture("valid", fixtureName);
      const parsed = appleSourceSnapshotV1Schema.parse(fixture);
      const mirror = openMirror();
      const result = mirror.apply({ snapshot: fixture, sourceRevision: 1 });

      if (parsed.truncated) {
        expect(result, fixtureName).toEqual({
          kind: "rejectedTruncated",
          entityType: parsed.entityType,
          sourceRevision: 1,
        });
      } else {
        expect(result, fixtureName).toEqual({
          kind: "applied",
          entityType: parsed.entityType,
          sourceRevision: 1,
        });
      }
      mirror.close();
    }
  });

  it("rejects every shared invalid fixture before creating its scope", async () => {
    const invalidFiles = (await readdir(new URL("invalid/", fixtureRoot)))
      .filter((path) => path.endsWith(".json"))
      .sort();
    expect(invalidFiles).toEqual([...invalidContractFixtureNames].sort());

    for (const fixtureName of invalidContractFixtureNames) {
      const fixture = await readContractFixture("invalid", fixtureName);
      const mirror = openMirror();

      expect(
        mirror.apply({ snapshot: fixture, sourceRevision: 1 }),
        fixtureName,
      ).toEqual({ kind: "rejectedInvalid" });

      const coordinate = possibleCoordinate(fixture);
      if (coordinate?.entityType === "reminder") {
        expect(
          mirror.readSourceScopeSummary({
            ...coordinate,
            entityType: "reminder",
          }),
          fixtureName,
        ).toBeNull();
      } else if (coordinate?.entityType === "calendar") {
        expect(
          mirror.readSourceScopeSummary({
            ...coordinate,
            entityType: "calendar",
          }),
          fixtureName,
        ).toBeNull();
      }
      mirror.close();
    }
  });

  it("rejects non-positive and unsafe operational revisions before mutation", async () => {
    const snapshot = await readContractFixture("valid", "reminder-undated.json");
    const mirror = openMirror();

    for (const sourceRevision of [0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1]) {
      expect(mirror.apply({ snapshot, sourceRevision })).toEqual({
        kind: "rejectedInvalid",
      });
    }
  });

  it("stores only parsed records and never the raw candidate document", async () => {
    const directory = await mkdtemp(join(tmpdir(), "deskboard-mirror-contract-"));
    temporaryDirectories.push(directory);
    const databasePath = join(directory, "mirror.sqlite");
    const fixture = appleSourceSnapshotV1Schema.parse(
      await readContractFixture("valid", "reminder-undated.json"),
    );
    if (fixture.entityType !== "reminder") {
      throw new Error("Expected the synthetic Reminder fixture.");
    }

    const rawOnlyMarker = "synthetic-raw-request-only-marker";
    const invalidCandidate = {
      ...structuredClone(fixture),
      rawRequestMarker: rawOnlyMarker,
    };
    const mirror = openMirror({ databasePath });
    expect(
      mirror.apply({ snapshot: invalidCandidate, sourceRevision: 1 }),
    ).toEqual({ kind: "rejectedInvalid" });
    expect(mirror.apply({ snapshot: fixture, sourceRevision: 1 }).kind).toBe(
      "applied",
    );
    mirror.close();

    const database = new DatabaseSync(databasePath, { readOnly: true });
    try {
      const scopeColumns = database
        .prepare("PRAGMA table_info(apple_source_scopes)")
        .all()
        .map((row) => row.name);
      expect(scopeColumns).not.toContain("snapshot_json");
      expect(scopeColumns).not.toContain("request_json");
      expect(scopeColumns).not.toContain("raw_body");

      const persistedState = [
        ...database.prepare("SELECT * FROM apple_source_scopes").all(),
        ...database.prepare("SELECT * FROM apple_reminder_records").all(),
      ];
      expect(JSON.stringify(persistedState)).not.toContain(rawOnlyMarker);

      const row = database
        .prepare("SELECT record_json FROM apple_reminder_records")
        .get();
      expect(typeof row?.record_json).toBe("string");
      const parsedRecord = appleReminderSourceRecordV1Schema.parse(
        JSON.parse(String(row?.record_json)) as unknown,
      );
      expect(parsedRecord).toEqual(fixture.records[0]);
    } finally {
      database.close();
    }
  });

  it("strictly revalidates canonical record JSON on read", async () => {
    const directory = await mkdtemp(join(tmpdir(), "deskboard-mirror-read-"));
    temporaryDirectories.push(directory);
    const databasePath = join(directory, "mirror.sqlite");
    const fixture = appleSourceSnapshotV1Schema.parse(
      await readContractFixture("valid", "reminder-undated.json"),
    );
    if (fixture.entityType !== "reminder") {
      throw new Error("Expected the synthetic Reminder fixture.");
    }

    const firstConnection = openMirror({ databasePath });
    expect(
      firstConnection.apply({ snapshot: fixture, sourceRevision: 1 }).kind,
    ).toBe("applied");
    firstConnection.close();

    const rawConnection = new DatabaseSync(databasePath);
    try {
      rawConnection
        .prepare(
          `
            UPDATE apple_reminder_records
            SET record_json = json_set(record_json, '$.unexpected', 1)
          `,
        )
        .run();
    } finally {
      rawConnection.close();
    }

    const secondConnection = openMirror({ databasePath });
    expect(() =>
      secondConnection.listReminderRecords({
        bridgeId: fixture.bridgeId,
        entityType: "reminder",
        sourceContainerId: fixture.source.sourceContainerId,
      }),
    ).toThrow(AppleSourceMirrorReadError);
  });
});
