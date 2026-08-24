import { buildApp } from "./app.js";
import { readDeskboardRuntimeConfiguration } from "./board-configuration.js";
import { readServerListenConfiguration } from "./server-configuration.js";

try {
  const listen = readServerListenConfiguration(process.env);
  const runtime = readDeskboardRuntimeConfiguration(process.env);
  const app = buildApp({
    logger: false,
    board: runtime.board,
    ...(runtime.appleSourceIngestion
      ? { appleSourceIngestion: runtime.appleSourceIngestion }
      : {}),
  });

  let isClosing = false;
  const close = async (): Promise<void> => {
    if (isClosing) {
      return;
    }
    isClosing = true;
    try {
      await app.close();
    } catch {
      process.stderr.write("Deskboard API could not close cleanly.\n");
      process.exitCode = 1;
    }
  };
  const requestClose = (): void => {
    void close();
  };
  process.once("SIGINT", requestClose);
  process.once("SIGTERM", requestClose);

  try {
    await app.listen(listen);
  } catch {
    await close();
    throw new Error("SERVER_START_FAILED");
  }
} catch {
  process.stderr.write("Deskboard API could not start.\n");
  process.exitCode = 1;
}
