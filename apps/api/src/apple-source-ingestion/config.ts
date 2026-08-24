export const APPLE_SOURCE_INGESTION_ENVIRONMENT = {
  bridgeId: "DESKBOARD_APPLE_BRIDGE_ID",
  bearerToken: "DESKBOARD_APPLE_BRIDGE_TOKEN",
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

export function readAppleSourceIngestionConfiguration(
  environment: NodeJS.ProcessEnv,
): AppleSourceIngestionConfiguration | undefined {
  const bridgeId = environment[APPLE_SOURCE_INGESTION_ENVIRONMENT.bridgeId];
  const bearerToken =
    environment[APPLE_SOURCE_INGESTION_ENVIRONMENT.bearerToken];
  const mirrorDatabasePath =
    environment[APPLE_SOURCE_INGESTION_ENVIRONMENT.mirrorDatabasePath];
  const values = [bridgeId, bearerToken, mirrorDatabasePath];

  if (values.every((value) => value === undefined)) {
    return undefined;
  }
  if (
    bridgeId === undefined ||
    bearerToken === undefined ||
    mirrorDatabasePath === undefined
  ) {
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
