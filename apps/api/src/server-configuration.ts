export const SERVER_ENVIRONMENT = {
  host: "DESKBOARD_API_HOST",
  port: "PORT",
} as const;

export const DEFAULT_SERVER_HOST = "127.0.0.1";
export const CONTAINER_SERVER_HOST = "0.0.0.0";
export const DEFAULT_SERVER_PORT = 3001;

export interface ServerListenConfiguration {
  host: typeof DEFAULT_SERVER_HOST | typeof CONTAINER_SERVER_HOST;
  port: number;
}

export class ServerConfigurationError extends Error {
  readonly code = "SERVER_CONFIGURATION_INVALID";

  constructor() {
    super("Deskboard server configuration is invalid.");
    this.name = "ServerConfigurationError";
  }
}

export function readServerListenConfiguration(
  environment: NodeJS.ProcessEnv,
): ServerListenConfiguration {
  const configuredHost = environment[SERVER_ENVIRONMENT.host];
  const host = configuredHost ?? DEFAULT_SERVER_HOST;
  if (host !== DEFAULT_SERVER_HOST && host !== CONTAINER_SERVER_HOST) {
    throw new ServerConfigurationError();
  }

  const configuredPort = environment[SERVER_ENVIRONMENT.port];
  const port =
    configuredPort === undefined ? DEFAULT_SERVER_PORT : Number(configuredPort);
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new ServerConfigurationError();
  }

  return { host, port };
}
