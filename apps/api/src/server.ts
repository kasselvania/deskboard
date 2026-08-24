import { buildApp } from "./app.js";
import { readAppleSourceIngestionConfiguration } from "./apple-source-ingestion/index.js";

const DEFAULT_PORT = 3001;

function readPort(value: string | undefined): number {
  if (value === undefined) {
    return DEFAULT_PORT;
  }

  const port = Number(value);
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error("PORT must be an integer between 1 and 65535.");
  }

  return port;
}

const appleSourceIngestion = readAppleSourceIngestionConfiguration(process.env);
const app = buildApp({
  logger: true,
  ...(appleSourceIngestion ? { appleSourceIngestion } : {}),
});

try {
  await app.listen({
    host: "127.0.0.1",
    port: readPort(process.env.PORT),
  });
} catch (error) {
  app.log.error(error, "Deskboard API could not start");
  process.exitCode = 1;
}
