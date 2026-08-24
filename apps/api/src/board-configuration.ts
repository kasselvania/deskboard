import { isRecognizedTimeZone } from "@deskboard/contracts";

import {
  AppleSourceIngestionConfigurationError,
  readAppleSourceIngestionConfiguration,
  type AppleSourceIngestionConfiguration,
} from "./apple-source-ingestion/index.js";

export const BOARD_ENVIRONMENT = {
  mode: "DESKBOARD_BOARD_MODE",
  timeZone: "DESKBOARD_BOARD_TIME_ZONE",
} as const;

export type BoardRuntimeConfiguration =
  | { mode: "fixture" }
  | { mode: "apple-mirror"; timeZone: string };

export interface DeskboardRuntimeConfiguration {
  board: BoardRuntimeConfiguration;
  appleSourceIngestion: AppleSourceIngestionConfiguration | undefined;
}

export class MirrorBackedBoardConfigurationError extends Error {
  readonly code = "MIRROR_BACKED_BOARD_CONFIGURATION_INVALID";

  constructor() {
    super("Mirror-backed Board configuration is invalid.");
    this.name = "MirrorBackedBoardConfigurationError";
  }
}

export function readDeskboardRuntimeConfiguration(
  environment: NodeJS.ProcessEnv,
): DeskboardRuntimeConfiguration {
  const mode = environment[BOARD_ENVIRONMENT.mode];
  const timeZone = environment[BOARD_ENVIRONMENT.timeZone];

  if (mode === undefined && timeZone === undefined) {
    return {
      board: { mode: "fixture" },
      appleSourceIngestion:
        readAppleSourceIngestionConfiguration(environment),
    };
  }

  if (mode === "fixture" && timeZone === undefined) {
    return {
      board: { mode: "fixture" },
      appleSourceIngestion:
        readAppleSourceIngestionConfiguration(environment),
    };
  }

  if (
    mode !== "apple-mirror" ||
    timeZone === undefined ||
    timeZone.length === 0 ||
    timeZone.length > 128 ||
    !isRecognizedTimeZone(timeZone)
  ) {
    throw new MirrorBackedBoardConfigurationError();
  }

  try {
    const appleSourceIngestion =
      readAppleSourceIngestionConfiguration(environment);
    if (!appleSourceIngestion) {
      throw new MirrorBackedBoardConfigurationError();
    }
    return {
      board: { mode: "apple-mirror", timeZone },
      appleSourceIngestion,
    };
  } catch (error) {
    if (
      error instanceof MirrorBackedBoardConfigurationError ||
      error instanceof AppleSourceIngestionConfigurationError
    ) {
      throw new MirrorBackedBoardConfigurationError();
    }
    throw error;
  }
}
