import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";

import {
  appleBridgeStatusSnapshotV1Schema,
  type AppleBridgeStatusSnapshotV1,
} from "@deskboard/contracts";
import { afterEach, describe, expect, it, vi } from "vitest";

import { buildApp } from "../src/app";
import {
  APPLE_BRIDGE_STATUS_BODY_LIMIT_BYTES,
  APPLE_BRIDGE_STATUS_ROUTE,
} from "../src/apple-bridge-status/index";
import { AppleSourceMirror } from "../src/apple-source-mirror/index";
import { AppleBridgeStatusReadError } from "../src/apple-bridge-status/index";

const openMirrors: AppleSourceMirror[] = [];
const temporaryDirectories: string[] = [];
const CONFIGURED_TOKEN = "c".repeat(64);

function openMirror(
  options: ConstructorParameters<typeof AppleSourceMirror>[0] = {},
): AppleSourceMirror {
  const mirror = new AppleSourceMirror({
    clock: () => new Date("2026-08-24T18:01:00Z"),
    ...options,
  });
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

async function validStatusFixture(
  name = "selected-applied.json",
): Promise<AppleBridgeStatusSnapshotV1> {
  return appleBridgeStatusSnapshotV1Schema.parse(
    JSON.parse(
      await readFile(
        new URL(
          `../../../fixtures/apple-bridge-status/v1/valid/${name}`,
          import.meta.url,
        ),
        "utf8",
      ),
    ) as unknown,
  );
}

describe("Apple Bridge status storage", () => {
  it("applies newer status and rejects duplicate, stale, and conflicting revisions", async () => {
    const mirror = openMirror();
    const revisionThree = await validStatusFixture();

    expect(mirror.applyBridgeStatus(revisionThree)).toEqual({
      kind: "applied",
      statusRevision: 3,
    });
    expect(mirror.applyBridgeStatus(revisionThree)).toEqual({
      kind: "unchangedDuplicate",
      statusRevision: 3,
    });
    expect(
      mirror.applyBridgeStatus({ ...revisionThree, statusRevision: 2 }),
    ).toEqual({ kind: "rejectedStale", statusRevision: 2 });
    expect(
      mirror.applyBridgeStatus({
        ...revisionThree,
        capturedAt: "2026-08-24T18:00:01Z",
      }),
    ).toEqual({
      kind: "rejectedRevisionConflict",
      statusRevision: 3,
    });
    expect(mirror.readBridgeStatus(revisionThree.bridgeId)).toEqual(
      revisionThree,
    );
  });

  it("rejects invalid candidates without changing the accepted status", async () => {
    const mirror = openMirror();
    const accepted = await validStatusFixture();
    expect(mirror.applyBridgeStatus(accepted).kind).toBe("applied");

    expect(
      mirror.applyBridgeStatus({ ...accepted, sourceTitle: "excluded" }),
    ).toEqual({ kind: "rejectedInvalid" });
    expect(mirror.readBridgeStatus(accepted.bridgeId)).toEqual(accepted);
  });

  it("persists only parsed status JSON and strictly revalidates it on read", async () => {
    const directory = await mkdtemp(join(tmpdir(), "deskboard-status-"));
    temporaryDirectories.push(directory);
    const databasePath = join(directory, "status.sqlite");
    const accepted = await validStatusFixture();
    const rawOnlyMarker = "synthetic-raw-status-request-marker";

    const first = openMirror({ databasePath });
    expect(
      first.applyBridgeStatus({ ...accepted, rawOnlyMarker }),
    ).toEqual({ kind: "rejectedInvalid" });
    expect(first.applyBridgeStatus(accepted).kind).toBe("applied");
    first.close();

    const raw = new DatabaseSync(databasePath);
    try {
      const persisted = raw
        .prepare("SELECT * FROM apple_bridge_status_snapshots")
        .all();
      expect(JSON.stringify(persisted)).not.toContain(rawOnlyMarker);
      raw
        .prepare(
          `
            UPDATE apple_bridge_status_snapshots
            SET document_json = json_set(document_json, '$.unexpected', 1)
          `,
        )
        .run();
    } finally {
      raw.close();
    }

    const reopened = openMirror({ databasePath });
    expect(() => reopened.readBridgeStatus(accepted.bridgeId)).toThrow(
      AppleBridgeStatusReadError,
    );
  });
});

describe("POST /v1/apple-bridge-status", () => {
  function configuration(mirror?: AppleSourceMirror) {
    return {
      expectedBridgeId: "synthetic-bridge-applied",
      bearerToken: CONFIGURED_TOKEN,
      mirrorDatabasePath: ":memory:",
      ...(mirror ? { mirror } : {}),
    };
  }

  function headers() {
    return {
      authorization: `Bearer ${CONFIGURED_TOKEN}`,
      "content-type": "application/json",
    };
  }

  it("is absent without ingestion configuration and exposes no read route", async () => {
    const app = buildApp();
    const post = await app.inject({
      method: "POST",
      url: APPLE_BRIDGE_STATUS_ROUTE,
      headers: headers(),
      payload: await validStatusFixture(),
    });
    const get = await app.inject({
      method: "GET",
      url: APPLE_BRIDGE_STATUS_ROUTE,
    });
    await app.close();

    expect(post.statusCode).toBe(404);
    expect(get.statusCode).toBe(404);
  });

  it("authenticates before parsing or status application", async () => {
    const mirror = openMirror();
    const apply = vi.spyOn(mirror, "applyBridgeStatus");
    const app = buildApp({
      appleSourceIngestion: configuration(mirror),
    });

    const response = await app.inject({
      method: "POST",
      url: APPLE_BRIDGE_STATUS_ROUTE,
      headers: { "content-type": "application/json" },
      payload: '{"schemaVersion":',
    });

    expect(response.statusCode).toBe(401);
    expect(response.json()).toEqual({
      error: { code: "APPLE_BRIDGE_STATUS_AUTHENTICATION_FAILED" },
    });
    expect(apply).not.toHaveBeenCalled();
    await app.close();
  });

  it("binds the authenticated Bridge and applies idempotently", async () => {
    const mirror = openMirror();
    const close = vi.spyOn(mirror, "close");
    const app = buildApp({
      appleSourceIngestion: configuration(mirror),
    });
    const snapshot = await validStatusFixture();
    const request = {
      method: "POST" as const,
      url: APPLE_BRIDGE_STATUS_ROUTE,
      headers: headers(),
      payload: snapshot,
    };

    const first = await app.inject(request);
    const duplicate = await app.inject(request);
    const mismatch = await app.inject({
      ...request,
      payload: { ...snapshot, bridgeId: "synthetic-other-bridge" },
    });
    await app.close();

    expect(first.statusCode).toBe(200);
    expect(first.json()).toEqual({ kind: "applied", statusRevision: 3 });
    expect(duplicate.statusCode).toBe(200);
    expect(duplicate.json()).toEqual({
      kind: "unchangedDuplicate",
      statusRevision: 3,
    });
    expect(mismatch.statusCode).toBe(403);
    expect(mismatch.json()).toEqual({
      error: { code: "APPLE_BRIDGE_STATUS_BRIDGE_MISMATCH" },
    });
    expect(close).toHaveBeenCalledTimes(1);
  });

  it("requires JSON, strict status, and the finite body limit", async () => {
    const app = buildApp({ appleSourceIngestion: configuration() });
    const nonJson = await app.inject({
      method: "POST",
      url: APPLE_BRIDGE_STATUS_ROUTE,
      headers: { authorization: `Bearer ${CONFIGURED_TOKEN}` },
      payload: "synthetic",
    });
    const invalid = await app.inject({
      method: "POST",
      url: APPLE_BRIDGE_STATUS_ROUTE,
      headers: headers(),
      payload: { ...(await validStatusFixture()), sourceTitle: "excluded" },
    });
    const oversized = await app.inject({
      method: "POST",
      url: APPLE_BRIDGE_STATUS_ROUTE,
      headers: headers(),
      payload: JSON.stringify({ value: "x".repeat(APPLE_BRIDGE_STATUS_BODY_LIMIT_BYTES) }),
    });
    await app.close();

    expect(nonJson.statusCode).toBe(415);
    expect(nonJson.json()).toEqual({
      error: { code: "APPLE_BRIDGE_STATUS_JSON_REQUIRED" },
    });
    expect(invalid.statusCode).toBe(400);
    expect(invalid.json()).toEqual({ kind: "rejectedInvalid" });
    expect(oversized.statusCode).toBe(413);
    expect(oversized.json()).toEqual({
      error: { code: "APPLE_BRIDGE_STATUS_BODY_TOO_LARGE" },
    });
  });
});
