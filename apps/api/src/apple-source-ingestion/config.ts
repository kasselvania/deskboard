import { readFileSync } from "node:fs";
import { isAbsolute } from "node:path";

export const APPLE_SOURCE_INGESTION_ENVIRONMENT = {
  bridgeId: "DESKBOARD_APPLE_BRIDGE_ID",
  bearerToken: "DESKBOARD_APPLE_BRIDGE_TOKEN",
  bearerTokenFile: "DESKBOARD_APPLE_BRIDGE_TOKEN_FILE",
  mirrorDatabasePath: "DESKBOARD_APPLE_MIRROR_DATABASE_PATH",
} as const;

export const APPLE_SOURCE_BEARER_TOKEN_PATTERN = /^[0-9a-f]{64}$/;

export interface AppleSourceIngestionConfiguration {
  expectedBridgeId: string;
  bearerToken: string;
  mirrorDatabasePath: string;
}

export class AppleSourceIngestionConfigurationError extends Error {
  readonly code = "APPLE_SOURCE_INGESTION_CONFIGURATION_INVALID";

  constructor() {
    super("Apple source ingestion configuration is invalid.");
    this.name = "AppleSourceIngestionConfigurationError";
  }
}

export type AppleSourceTokenFileReader = (path: string) => string;

const readTokenFile: AppleSourceTokenFileReader = (path) =>
  readFileSync(path, "utf8");

export function readAppleSourceIngestionConfiguration(
  environment: NodeJS.ProcessEnv,
  tokenFileReader: AppleSourceTokenFileReader = readTokenFile,
): AppleSourceIngestionConfiguration | undefined {
  const bridgeId = environment[APPLE_SOURCE_INGESTION_ENVIRONMENT.bridgeId];
  const environmentBearerToken =
    environment[APPLE_SOURCE_INGESTION_ENVIRONMENT.bearerToken];
  const bearerTokenFile =
    environment[APPLE_SOURCE_INGESTION_ENVIRONMENT.bearerTokenFile];
  const mirrorDatabasePath =
    environment[APPLE_SOURCE_INGESTION_ENVIRONMENT.mirrorDatabasePath];
  const values = [
    bridgeId,
    environmentBearerToken,
    bearerTokenFile,
    mirrorDatabasePath,
  ];

  if (values.every((value) => value === undefined)) {
    return undefined;
  }
  if (
    bridgeId === undefined ||
    (environmentBearerToken === undefined) === (bearerTokenFile === undefined) ||
    mirrorDatabasePath === undefined
  ) {
    throw new AppleSourceIngestionConfigurationError();
  }
  if (
    bearerTokenFile !== undefined &&
    (bearerTokenFile.length === 0 ||
      bearerTokenFile.length > 4096 ||
      !isAbsolute(bearerTokenFile))
  ) {
    throw new AppleSourceIngestionConfigurationError();
  }

  let bearerToken: string;
  try {
    bearerToken =
      environmentBearerToken ?? tokenFileReader(bearerTokenFile as string);
  } catch {
    throw new AppleSourceIngestionConfigurationError();
  }
  if (
    bridgeId.length === 0 ||
    bridgeId.length > 512 ||
    !APPLE_SOURCE_BEARER_TOKEN_PATTERN.test(bearerToken) ||
    mirrorDatabasePath.length === 0
  ) {
    throw new AppleSourceIngestionConfigurationError();
  }

  return {
    expectedBridgeId: bridgeId,
    bearerToken,
    mirrorDatabasePath,
  };
}
