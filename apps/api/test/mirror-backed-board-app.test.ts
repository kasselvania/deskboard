import { boardSnapshotSchema } from "@deskboard/contracts";
import { describe, expect, it, vi } from "vitest";

import { buildApp } from "../src/app";
import { MirrorBackedBoardConfigurationError } from "../src/board-configuration";
import { AppleSourceMirror } from "../src/apple-source-mirror/index";
import { makeReminderSnapshot } from "./apple-source-mirror-fixtures";

const BRIDGE_ID = "synthetic-shared-runtime-bridge";
const TOKEN = "a".repeat(64);
const NOW = new Date("2026-08-24T17:00:00Z");
const SOURCE_ID = "synthetic-shared-reminders";

function headers() {
  return {
    authorization: `Bearer ${TOKEN}`,
    "content-type": "application/json",
  };
}

describe("mirror-backed Board application wiring", () => {
  it("fails closed when mirror mode lacks the shared ingestion resource", () => {
    expect(() =>
      buildApp({
        board: {
          mode: "apple-mirror",
          timeZone: "America/Los_Angeles",
        },
      }),
    ).toThrow(MirrorBackedBoardConfigurationError);
  });

  it("serves the unchanged Board contract from the same resource used by both ingestion routes", async () => {
    const mirror = new AppleSourceMirror({ clock: () => NOW });
    const close = vi.spyOn(mirror, "close");
    const observeSummary = vi.fn();
    const app = buildApp({
      board: {
        mode: "apple-mirror",
        timeZone: "America/Los_Angeles",
      },
      appleSourceIngestion: {
        expectedBridgeId: BRIDGE_ID,
        bearerToken: TOKEN,
        mirrorDatabasePath: ":memory:",
        mirror,
      },
      clock: () => NOW,
      contentFreeBoardObserver: observeSummary,
    });
    const snapshot = makeReminderSnapshot({
      bridgeId: BRIDGE_ID,
      sourceContainerId: SOURCE_ID,
      capturedAt: "2026-08-24T16:59:00Z",
      records: [
        {
          localIdentifier: "synthetic-record",
          title: "Synthetic local task",
          start: { kind: "absent" },
          due: { kind: "dateOnly", localDate: "2026-08-24" },
          isCompleted: false,
        },
      ],
    });

    const sourceResponse = await app.inject({
      method: "POST",
      url: "/v1/apple-source-snapshots",
      headers: headers(),
      payload: { sourceRevision: 1, snapshot },
    });
    const statusResponse = await app.inject({
      method: "POST",
      url: "/v1/apple-bridge-status",
      headers: headers(),
      payload: {
        schemaVersion: 1,
        bridgeId: BRIDGE_ID,
        statusRevision: 1,
        capturedAt: "2026-08-24T16:59:30Z",
        permissions: { calendar: "denied", reminders: "granted" },
        selectedSources: [
          {
            entityType: "reminder",
            sourceContainerId: SOURCE_ID,
            status: "applied",
            acknowledgedSourceRevision: 1,
            lastAttemptedAt: "2026-08-24T16:59:00Z",
            lastAcknowledgedAt: "2026-08-24T16:59:00Z",
          },
        ],
      },
    });
    const healthResponse = await app.inject({ method: "GET", url: "/health" });
    const boardResponse = await app.inject({ method: "GET", url: "/v1/board" });
    const statusReadResponse = await app.inject({
      method: "GET",
      url: "/v1/apple-bridge-status",
    });
    await app.close();

    expect(sourceResponse.statusCode).toBe(200);
    expect(statusResponse.statusCode).toBe(200);
    expect(healthResponse.json()).toEqual({
      status: "ok",
      service: "deskboard-api",
    });
    expect(statusReadResponse.statusCode).toBe(404);
    const board = boardSnapshotSchema.parse(boardResponse.json());
    expect(board.schemaVersion).toBe(1);
    expect(board.today.items.map((item) => item.title)).toEqual([
      "Synthetic local task",
    ]);
    expect(board.freshness).toEqual({
      reminders: {
        status: "fresh",
        updatedAt: "2026-08-24T16:59:00Z",
      },
      calendar: { status: "unavailable", updatedAt: null },
    });
    expect(observeSummary).toHaveBeenCalledWith({
      schemaValid: true,
      todayItemCount: 1,
      nextItemCount: 0,
      calendarFreshness: "unavailable",
      remindersFreshness: "fresh",
      selectedSourceCounts: { calendar: 0, reminders: 1 },
      sources: [{ source: "Reminder source 1", health: "applied" }],
    });
    expect(JSON.stringify(observeSummary.mock.calls)).not.toMatch(
      /Synthetic local task|synthetic-record|synthetic-shared-reminders/,
    );
    expect(close).toHaveBeenCalledTimes(1);
  });
});
