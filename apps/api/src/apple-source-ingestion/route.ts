import type { FastifyInstance, FastifyReply } from "fastify";

import {
  AppleSourceMirror,
  type AppleSourceMirrorApplyResult,
} from "../apple-source-mirror/index.js";
import { authorizationMatchesConfiguredToken } from "./auth.js";
import type { AppleSourceIngestionConfiguration } from "./config.js";
import { parseAppleSourceIngestionEnvelope } from "./envelope.js";

export const APPLE_SOURCE_INGESTION_BODY_LIMIT_BYTES = 1_048_576;
export const APPLE_SOURCE_INGESTION_ROUTE = "/v1/apple-source-snapshots";

export interface AppleSourceMirrorApplicationBoundary {
  apply(input: {
    snapshot: unknown;
    sourceRevision: number;
  }): AppleSourceMirrorApplyResult;
  close(): void;
}

export interface AppleSourceIngestionRegistrationOptions
  extends AppleSourceIngestionConfiguration {
  mirror?: AppleSourceMirrorApplicationBoundary;
}

const noQueryParameters = {
  type: "object",
  maxProperties: 0,
  additionalProperties: false,
} as const;

function sendError(reply: FastifyReply, statusCode: number, code: string) {
  return reply.status(statusCode).type("application/json; charset=utf-8").send({
    error: { code },
  });
}

function statusForApplyResult(result: AppleSourceMirrorApplyResult): number {
  switch (result.kind) {
    case "applied":
    case "unchangedDuplicate":
      return 200;
    case "rejectedStale":
    case "rejectedRevisionConflict":
      return 409;
    case "rejectedTruncated":
      return 422;
    case "rejectedInvalid":
      return 400;
  }
}

function sendApplyResult(
  reply: FastifyReply,
  result: AppleSourceMirrorApplyResult,
) {
  return reply
    .status(statusForApplyResult(result))
    .type("application/json; charset=utf-8")
    .send(result);
}

function isJsonContentType(value: string | undefined): boolean {
  if (!value) {
    return false;
  }
  return value.split(";", 1)[0]?.trim().toLowerCase() === "application/json";
}

export function registerAppleSourceIngestion(
  app: FastifyInstance,
  options: AppleSourceIngestionRegistrationOptions,
): void {
  const mirror =
    options.mirror ??
    new AppleSourceMirror({ databasePath: options.mirrorDatabasePath });
  let mirrorClosed = false;

  app.addHook("onClose", async () => {
    if (!mirrorClosed) {
      mirrorClosed = true;
      mirror.close();
    }
  });

  app.post(
    APPLE_SOURCE_INGESTION_ROUTE,
    {
      bodyLimit: APPLE_SOURCE_INGESTION_BODY_LIMIT_BYTES,
      schema: { querystring: noQueryParameters },
      onRequest: async (request, reply) => {
        if (
          !authorizationMatchesConfiguredToken(
            request.headers.authorization,
            options.bearerToken,
          )
        ) {
          return sendError(reply, 401, "APPLE_SOURCE_AUTHENTICATION_FAILED");
        }
        if (!isJsonContentType(request.headers["content-type"])) {
          return sendError(reply, 415, "APPLE_SOURCE_JSON_REQUIRED");
        }
      },
      errorHandler: async (error, _request, reply) => {
        if (error.code === "FST_ERR_CTP_BODY_TOO_LARGE") {
          return sendError(reply, 413, "APPLE_SOURCE_BODY_TOO_LARGE");
        }
        return sendApplyResult(reply, { kind: "rejectedInvalid" });
      },
    },
    async (request, reply) => {
      const envelope = parseAppleSourceIngestionEnvelope(request.body);
      if (!envelope) {
        return sendApplyResult(reply, { kind: "rejectedInvalid" });
      }
      if (envelope.snapshot.bridgeId !== options.expectedBridgeId) {
        return sendError(reply, 403, "APPLE_SOURCE_BRIDGE_MISMATCH");
      }

      try {
        return sendApplyResult(
          reply,
          mirror.apply({
            snapshot: envelope.snapshot,
            sourceRevision: envelope.sourceRevision,
          }),
        );
      } catch {
        return sendError(reply, 500, "APPLE_SOURCE_APPLICATION_FAILED");
      }
    },
  );
}
