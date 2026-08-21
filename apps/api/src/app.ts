import { readFile } from "node:fs/promises";

import {
  boardSnapshotSchema,
  type BoardSnapshot,
} from "@deskboard/contracts";
import Fastify, { type FastifyInstance } from "fastify";

const defaultFixtureUrl = new URL(
  "../../../fixtures/board/default.json",
  import.meta.url,
);

export type BoardLoader = () => Promise<unknown>;

export interface BuildAppOptions {
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

export async function loadDefaultBoardFixture(): Promise<unknown> {
  const fixture = await readFile(defaultFixtureUrl, "utf8");
  return JSON.parse(fixture) as unknown;
}

export function buildApp(options: BuildAppOptions = {}): FastifyInstance {
  const app = Fastify({
    exposeHeadRoutes: false,
    logger: options.logger ?? false,
  });
  const loadBoard = options.loadBoard ?? loadDefaultBoardFixture;

  app.get("/health", noQueryParameters, async () => ({
    status: "ok",
    service: "deskboard-api",
  }));

  app.get("/v1/board", noQueryParameters, async (_request, reply) => {
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

  return app;
}
