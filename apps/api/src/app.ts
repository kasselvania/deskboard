import { readFile } from "node:fs/promises";

import {
  boardSnapshotSchema,
  type BoardSnapshot,
} from "@deskboard/contracts";
import Fastify, { type FastifyInstance } from "fastify";

import {
  materializeDefaultBoard,
  type FixtureClock,
} from "./materialize-default-board";
import {
  registerAppleSourceIngestion,
  type AppleSourceIngestionRegistrationOptions,
} from "./apple-source-ingestion/index.js";

const defaultFixtureUrl = new URL(
  "../../../fixtures/board/default.json",
  import.meta.url,
);

export type BoardLoader = () => Promise<unknown>;

export interface BuildAppOptions {
  appleSourceIngestion?: AppleSourceIngestionRegistrationOptions;
  clock?: FixtureClock;
  loadBoard?: BoardLoader;
  logger?: boolean;
}

const noQueryParameters = {
  schema: {
    querystring: {
      type: "object",
      maxProperties: 0,
      additionalProperties: false,
    },
  },
} as const;

const systemClock: FixtureClock = () => new Date();

export async function loadDefaultBoardFixture(
  clock: FixtureClock = systemClock,
): Promise<BoardSnapshot> {
  const fixture = await readFile(defaultFixtureUrl, "utf8");
  const template = boardSnapshotSchema.parse(JSON.parse(fixture) as unknown);
  return materializeDefaultBoard(template, clock);
}

export function buildApp(options: BuildAppOptions = {}): FastifyInstance {
  const app = Fastify({
    exposeHeadRoutes: false,
    logger: options.logger ?? false,
  });
  const clock = options.clock ?? systemClock;
  const loadBoard =
    options.loadBoard ?? (() => loadDefaultBoardFixture(clock));

  app.get("/health", noQueryParameters, async () => ({
    status: "ok",
    service: "deskboard-api",
  }));

  app.get("/v1/board", noQueryParameters, async (_request, reply) => {
    reply.header("Cache-Control", "no-store");

    try {
      const candidate = await loadBoard();
      const board: BoardSnapshot = boardSnapshotSchema.parse(candidate);
      return reply.type("application/json; charset=utf-8").send(board);
    } catch (error) {
      app.log.error({ error }, "Board fixture could not be served");
      return reply.status(500).send({
        error: {
          code: "BOARD_UNAVAILABLE",
          message: "The Board is temporarily unavailable.",
        },
      });
    }
  });

  if (options.appleSourceIngestion) {
    registerAppleSourceIngestion(app, options.appleSourceIngestion);
  }

  return app;
}
