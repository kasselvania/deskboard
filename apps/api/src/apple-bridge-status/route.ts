import type { FastifyInstance, FastifyReply } from "fastify";

import { appleBridgeStatusSnapshotV1Schema } from "@deskboard/contracts";

import { authorizationMatchesConfiguredToken } from "../apple-source-ingestion/auth.js";
import type { AppleBridgeStatusApplyResult } from "./store.js";

export const APPLE_BRIDGE_STATUS_BODY_LIMIT_BYTES = 262_144;
export const APPLE_BRIDGE_STATUS_ROUTE = "/v1/apple-bridge-status";

export interface AppleBridgeStatusApplicationBoundary {
  applyBridgeStatus(input: unknown): AppleBridgeStatusApplyResult;
}

export interface AppleBridgeStatusRegistrationOptions {
  expectedBridgeId: string;
  bearerToken: string;
  application: AppleBridgeStatusApplicationBoundary;
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

function statusForApplyResult(result: AppleBridgeStatusApplyResult): number {
  switch (result.kind) {
    case "applied":
    case "unchangedDuplicate":
      return 200;
    case "rejectedStale":
    case "rejectedRevisionConflict":
      return 409;
    case "rejectedInvalid":
      return 400;
  }
}

function sendApplyResult(
  reply: FastifyReply,
  result: AppleBridgeStatusApplyResult,
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

export function registerAppleBridgeStatus(
  app: FastifyInstance,
  options: AppleBridgeStatusRegistrationOptions,
): void {
  app.post(
    APPLE_BRIDGE_STATUS_ROUTE,
    {
      bodyLimit: APPLE_BRIDGE_STATUS_BODY_LIMIT_BYTES,
      schema: { querystring: noQueryParameters },
      onRequest: async (request, reply) => {
        if (
          !authorizationMatchesConfiguredToken(
            request.headers.authorization,
            options.bearerToken,
          )
        ) {
          return sendError(
            reply,
            401,
            "APPLE_BRIDGE_STATUS_AUTHENTICATION_FAILED",
          );
        }
        if (!isJsonContentType(request.headers["content-type"])) {
          return sendError(reply, 415, "APPLE_BRIDGE_STATUS_JSON_REQUIRED");
        }
      },
      errorHandler: async (error, _request, reply) => {
        if (error.code === "FST_ERR_CTP_BODY_TOO_LARGE") {
          return sendError(reply, 413, "APPLE_BRIDGE_STATUS_BODY_TOO_LARGE");
        }
        return sendApplyResult(reply, { kind: "rejectedInvalid" });
      },
    },
    async (request, reply) => {
      const parsed = appleBridgeStatusSnapshotV1Schema.safeParse(request.body);
      if (!parsed.success) {
        return sendApplyResult(reply, { kind: "rejectedInvalid" });
      }
      if (parsed.data.bridgeId !== options.expectedBridgeId) {
        return sendError(reply, 403, "APPLE_BRIDGE_STATUS_BRIDGE_MISMATCH");
      }

      try {
        return sendApplyResult(
          reply,
          options.application.applyBridgeStatus(parsed.data),
        );
      } catch {
        return sendError(reply, 500, "APPLE_BRIDGE_STATUS_APPLICATION_FAILED");
      }
    },
  );
}
