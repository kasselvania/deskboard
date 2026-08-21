import { readFile } from "node:fs/promises";

import { boardSnapshotSchema } from "@deskboard/contracts";
import { afterEach, describe, expect, it } from "vitest";

import { buildApp } from "../src/app";

const openApps: ReturnType<typeof buildApp>[] = [];

function makeApp(options?: Parameters<typeof buildApp>[0]) {
  const app = buildApp(options);
  openApps.push(app);
  return app;
}

afterEach(async () => {
  await Promise.all(openApps.splice(0).map((app) => app.close()));
});

describe("Deskboard API", () => {
  it("serves the minimal health response", async () => {
    const response = await makeApp().inject({ method: "GET", url: "/health" });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({
      status: "ok",
      service: "deskboard-api",
    });
  });

  it("serves a runtime-validated default Board", async () => {
    const response = await makeApp().inject({
      method: "GET",
      url: "/v1/board",
    });

    expect(response.statusCode).toBe(200);
    expect(response.headers["content-type"]).toMatch(/^application\/json/);
    const board = boardSnapshotSchema.parse(response.json());
    expect(board.today.items.map((item) => item.title)).toEqual([
      "Return the library book",
      "Measure the workshop shelf",
      "Place recycling by the door",
    ]);
    expect(board.next.items.map((item) => item.title)).toEqual([
      "Fictional planning call",
      "Workshop maintenance window",
    ]);
  });

  it("returns a small safe error when fixture validation fails", async () => {
    const invalidFixture = JSON.parse(
      await readFile(
        new URL(
          "../../../fixtures/board/invalid/unsupported-version.json",
          import.meta.url,
        ),
        "utf8",
      ),
    ) as unknown;
    const response = await makeApp({
      loadBoard: async () => invalidFixture,
    }).inject({ method: "GET", url: "/v1/board" });

    expect(response.statusCode).toBe(500);
    expect(response.json()).toEqual({
      error: {
        code: "BOARD_UNAVAILABLE",
        message: "The Board is temporarily unavailable.",
      },
    });
    expect(response.body).not.toMatch(/Zod|fixtures|\/Users|stack/i);
  });

  it("does not expose undeclared routes, methods, or query parameters", async () => {
    const app = makeApp();
    const responses = await Promise.all([
      app.inject({ method: "GET", url: "/" }),
      app.inject({ method: "HEAD", url: "/health" }),
      app.inject({ method: "POST", url: "/v1/board" }),
      app.inject({ method: "GET", url: "/v1/board?fixture=stale" }),
    ]);

    expect(responses.map((response) => response.statusCode)).toEqual([
      404, 404, 404, 400,
    ]);
  });
});
