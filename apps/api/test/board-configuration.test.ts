import { describe, expect, it } from "vitest";

import {
  MirrorBackedBoardConfigurationError,
  readDeskboardRuntimeConfiguration,
} from "../src/board-configuration";

const INGESTION = {
  DESKBOARD_APPLE_BRIDGE_ID: "synthetic-bridge",
  DESKBOARD_APPLE_BRIDGE_TOKEN: "a".repeat(64),
  DESKBOARD_APPLE_MIRROR_DATABASE_PATH: "/tmp/synthetic.sqlite",
};

describe("Board runtime configuration", () => {
  it("keeps fixture mode as the zero-configuration default", () => {
    expect(readDeskboardRuntimeConfiguration({})).toEqual({
      board: { mode: "fixture" },
      appleSourceIngestion: undefined,
    });
  });

  it("requires explicit complete mirror mode and an IANA time zone", () => {
    expect(
      readDeskboardRuntimeConfiguration({
        ...INGESTION,
        DESKBOARD_BOARD_MODE: "apple-mirror",
        DESKBOARD_BOARD_TIME_ZONE: "America/Los_Angeles",
      }),
    ).toEqual({
      board: {
        mode: "apple-mirror",
        timeZone: "America/Los_Angeles",
      },
      appleSourceIngestion: {
        expectedBridgeId: "synthetic-bridge",
        bearerToken: "a".repeat(64),
        mirrorDatabasePath: "/tmp/synthetic.sqlite",
      },
    });
  });

  it("maps every partial or invalid mirror configuration to one fixed safe error", () => {
    const cases: NodeJS.ProcessEnv[] = [
      { DESKBOARD_BOARD_MODE: "apple-mirror" },
      { ...INGESTION, DESKBOARD_BOARD_MODE: "apple-mirror" },
      {
        ...INGESTION,
        DESKBOARD_BOARD_MODE: "apple-mirror",
        DESKBOARD_BOARD_TIME_ZONE: "Not/AZone",
      },
      { DESKBOARD_BOARD_TIME_ZONE: "Etc/UTC" },
      { ...INGESTION, DESKBOARD_BOARD_MODE: "other" },
      {
        DESKBOARD_BOARD_MODE: "apple-mirror",
        DESKBOARD_BOARD_TIME_ZONE: "Etc/UTC",
        DESKBOARD_APPLE_BRIDGE_ID: "synthetic-bridge",
      },
    ];

    for (const environment of cases) {
      expect(() => readDeskboardRuntimeConfiguration(environment)).toThrow(
        MirrorBackedBoardConfigurationError,
      );
      try {
        readDeskboardRuntimeConfiguration(environment);
      } catch (error) {
        expect(error).toMatchObject({
          code: "MIRROR_BACKED_BOARD_CONFIGURATION_INVALID",
          message: "Mirror-backed Board configuration is invalid.",
        });
      }
    }
  });

  it("allows configured ingestion while the Board remains explicitly fixture-backed", () => {
    expect(
      readDeskboardRuntimeConfiguration({
        ...INGESTION,
        DESKBOARD_BOARD_MODE: "fixture",
      }),
    ).toMatchObject({
      board: { mode: "fixture" },
      appleSourceIngestion: { expectedBridgeId: "synthetic-bridge" },
    });
  });
});
