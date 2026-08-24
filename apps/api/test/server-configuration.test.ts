import { describe, expect, it } from "vitest";

import {
  ServerConfigurationError,
  readServerListenConfiguration,
} from "../src/server-configuration";

describe("server listen configuration", () => {
  it("keeps numeric loopback and the accepted port as local defaults", () => {
    expect(readServerListenConfiguration({})).toEqual({
      host: "127.0.0.1",
      port: 3001,
    });
  });

  it("allows only the explicit private-container bind correction", () => {
    expect(
      readServerListenConfiguration({
        DESKBOARD_API_HOST: "0.0.0.0",
        PORT: "4310",
      }),
    ).toEqual({ host: "0.0.0.0", port: 4310 });

    expect(
      readServerListenConfiguration({
        DESKBOARD_API_HOST: "127.0.0.1",
      }),
    ).toEqual({ host: "127.0.0.1", port: 3001 });
  });

  it("rejects every other host and malformed port with one safe error", () => {
    const cases: NodeJS.ProcessEnv[] = [
      { DESKBOARD_API_HOST: "" },
      { DESKBOARD_API_HOST: "localhost" },
      { DESKBOARD_API_HOST: "192.0.2.10" },
      { DESKBOARD_API_HOST: "::" },
      { DESKBOARD_API_HOST: "127.0.0.2" },
      { PORT: "0" },
      { PORT: "65536" },
      { PORT: "3001.5" },
      { PORT: "not-a-port" },
    ];

    for (const environment of cases) {
      expect(() => readServerListenConfiguration(environment)).toThrow(
        ServerConfigurationError,
      );
      try {
        readServerListenConfiguration(environment);
      } catch (error) {
        expect(error).toMatchObject({
          code: "SERVER_CONFIGURATION_INVALID",
          message: "Deskboard server configuration is invalid.",
        });
        expect(String(error)).not.toMatch(/localhost|192\.0\.2|not-a-port/);
      }
    }
  });
});
