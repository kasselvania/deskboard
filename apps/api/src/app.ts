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
  MirrorBackedBoardConfigurationError,
  type BoardRuntimeConfiguration,
} from "./board-configuration.js";
import {
  registerAppleSourceIngestion,
  type AppleSourceIngestionRegistrationOptions,
} from "./apple-source-ingestion/index.js";
import { AppleSourceMirror } from "./apple-source-mirror/index.js";
import {
  composeMirrorBackedBoard,
  type ContentFreeBoardAcceptanceSummary,
  type MirrorBackedBoardSource,
} from "./mirror-backed-board/index.js";

const defaultFixtureUrl = new URL(
  "../../../fixtures/board/default.json",
  import.meta.url,
);

export type BoardLoader = () => Promise<unknown>;

export interface BuildAppOptions {
  appleSourceIngestion?: AppleSourceIngestionRegistrationOptions;
  board?: BoardRuntimeConfiguration;
  clock?: FixtureClock;
  contentFreeBoardObserver?: (
    summary: ContentFreeBoardAcceptanceSummary,
  ) => void;
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

async function loadDefaultBoardTemplate(): Promise<BoardSnapshot> {
  const fixture = await readFile(defaultFixtureUrl, "utf8");
  return boardSnapshotSchema.parse(JSON.parse(fixture) as unknown);
}

function isMirrorBackedBoardSource(
  value: unknown,
): value is MirrorBackedBoardSource {
  if (!value || typeof value !== "object") {
    return false;
  }
  const candidate = value as Record<string, unknown>;
  return (
    typeof candidate.readBridgeStatus === "function" &&
    typeof candidate.readSourceScopeSummary === "function" &&
    typeof candidate.listReminderRecords === "function" &&
    typeof candidate.listCalendarRecordsInLatestWindow === "function"
  );
}

export function buildApp(options: BuildAppOptions = {}): FastifyInstance {
  const app = Fastify({
    exposeHeadRoutes: false,
    logger: options.logger ?? false,
  });
  const clock = options.clock ?? systemClock;
  const boardConfiguration = options.board ?? { mode: "fixture" };
  let appleSourceIngestion = options.appleSourceIngestion;
  let configuredBoardLoader: BoardLoader;
  if (boardConfiguration.mode === "apple-mirror") {
    if (!appleSourceIngestion) {
      throw new MirrorBackedBoardConfigurationError();
    }
    const sharedMirror =
      appleSourceIngestion.mirror ??
      new AppleSourceMirror({
        databasePath: appleSourceIngestion.mirrorDatabasePath,
        clock,
      });
    if (!isMirrorBackedBoardSource(sharedMirror)) {
      throw new MirrorBackedBoardConfigurationError();
    }
    appleSourceIngestion = {
      ...appleSourceIngestion,
      mirror: sharedMirror,
    };
    const expectedBridgeId = appleSourceIngestion.expectedBridgeId;
    configuredBoardLoader = async () => {
      const template = await loadDefaultBoardTemplate();
      const result = composeMirrorBackedBoard({
        source: sharedMirror,
        expectedBridgeId,
        timeZone: boardConfiguration.timeZone,
        clock,
        ...(template.sidewaysPrompt
          ? { sidewaysPrompt: template.sidewaysPrompt }
          : {}),
      });
      options.contentFreeBoardObserver?.(result.acceptanceSummary);
      return result.board;
    };
  } else {
    configuredBoardLoader = () => loadDefaultBoardFixture(clock);
  }
  const loadBoard = options.loadBoard ?? configuredBoardLoader;

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
      app.log.error({ error }, "Board could not be served");
      return reply.status(500).send({
        error: {
          code: "BOARD_UNAVAILABLE",
          message: "The Board is temporarily unavailable.",
        },
      });
    }
  });

  if (appleSourceIngestion) {
    registerAppleSourceIngestion(app, appleSourceIngestion);
  }

  return app;
}
