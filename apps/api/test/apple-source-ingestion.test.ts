import { describe, expect, it, vi } from "vitest";

import { buildApp } from "../src/app";
import {
  APPLE_SOURCE_INGESTION_BODY_LIMIT_BYTES,
  AppleSourceIngestionConfigurationError,
  authorizationMatchesConfiguredToken,
  readAppleSourceIngestionConfiguration,
  type AppleSourceMirrorApplicationBoundary,
} from "../src/apple-source-ingestion/index";
import {
  AppleSourceMirror,
  type AppleSourceMirrorApplyResult,
} from "../src/apple-source-mirror/index";
import { makeReminderSnapshot } from "./apple-source-mirror-fixtures";

const EXPECTED_BRIDGE_ID = "synthetic-phase-3b-bridge";
const CONFIGURED_TOKEN = "a".repeat(64);
const WRONG_TOKEN = "b".repeat(64);

function authorization(token = CONFIGURED_TOKEN) {
  return { authorization: `Bearer ${token}`, "content-type": "application/json" };
}

function ingestionOptions(mirror?: AppleSourceMirrorApplicationBoundary) {
  return {
    expectedBridgeId: EXPECTED_BRIDGE_ID,
    bearerToken: CONFIGURED_TOKEN,
    mirrorDatabasePath: ":memory:",
    ...(mirror ? { mirror } : {}),
  };
}

function validEnvelope(sourceRevision = 1) {
  return {
    sourceRevision,
    snapshot: makeReminderSnapshot({ bridgeId: EXPECTED_BRIDGE_ID }),
  };
}

class StubMirror implements AppleSourceMirrorApplicationBoundary {
  readonly apply = vi.fn<
    (input: {
      snapshot: unknown;
      sourceRevision: number;
    }) => AppleSourceMirrorApplyResult
  >();
  readonly close = vi.fn<() => void>();

  constructor(result: AppleSourceMirrorApplyResult) {
    this.apply.mockReturnValue(result);
  }
}

describe("Apple source ingestion configuration", () => {
  it("keeps fixture-only development enabled when every ingestion value is absent", () => {
    expect(readAppleSourceIngestionConfiguration({})).toBeUndefined();
  });

  it("accepts only complete fixed-format configuration", () => {
    expect(
      readAppleSourceIngestionConfiguration({
        DESKBOARD_APPLE_BRIDGE_ID: EXPECTED_BRIDGE_ID,
        DESKBOARD_APPLE_BRIDGE_TOKEN: CONFIGURED_TOKEN,
        DESKBOARD_APPLE_MIRROR_DATABASE_PATH: "/tmp/synthetic-mirror.sqlite",
      }),
    ).toEqual({
      expectedBridgeId: EXPECTED_BRIDGE_ID,
      bearerToken: CONFIGURED_TOKEN,
      mirrorDatabasePath: "/tmp/synthetic-mirror.sqlite",
    });
  });

  it("accepts the same strict token through one absolute token file", () => {
    const readTokenFile = vi.fn(() => CONFIGURED_TOKEN);
    expect(
      readAppleSourceIngestionConfiguration(
        {
          DESKBOARD_APPLE_BRIDGE_ID: EXPECTED_BRIDGE_ID,
          DESKBOARD_APPLE_BRIDGE_TOKEN_FILE: "/run/secrets/apple_bridge_token",
          DESKBOARD_APPLE_MIRROR_DATABASE_PATH: "/tmp/synthetic-mirror.sqlite",
        },
        readTokenFile,
      ),
    ).toEqual({
      expectedBridgeId: EXPECTED_BRIDGE_ID,
      bearerToken: CONFIGURED_TOKEN,
      mirrorDatabasePath: "/tmp/synthetic-mirror.sqlite",
    });
    expect(readTokenFile).toHaveBeenCalledWith(
      "/run/secrets/apple_bridge_token",
    );
  });

  it("rejects token environment and token file configuration together", () => {
    const readTokenFile = vi.fn(() => CONFIGURED_TOKEN);
    expect(() =>
      readAppleSourceIngestionConfiguration(
        {
          DESKBOARD_APPLE_BRIDGE_ID: EXPECTED_BRIDGE_ID,
          DESKBOARD_APPLE_BRIDGE_TOKEN: CONFIGURED_TOKEN,
          DESKBOARD_APPLE_BRIDGE_TOKEN_FILE: "/run/secrets/apple_bridge_token",
          DESKBOARD_APPLE_MIRROR_DATABASE_PATH: "/tmp/synthetic-mirror.sqlite",
        },
        readTokenFile,
      ),
    ).toThrow(AppleSourceIngestionConfigurationError);
    expect(readTokenFile).not.toHaveBeenCalled();
  });

  it("fails closed when the token file is relative, unreadable, or malformed", () => {
    const cases: Array<[string, () => string]> = [
      ["relative-token", () => CONFIGURED_TOKEN],
      ["/run/secrets/missing", () => {
        throw new Error("synthetic read failure");
      }],
      ["/run/secrets/invalid", () => `${CONFIGURED_TOKEN}\n`],
    ];

    for (const [tokenFile, readTokenFile] of cases) {
      expect(() =>
        readAppleSourceIngestionConfiguration(
          {
            DESKBOARD_APPLE_BRIDGE_ID: EXPECTED_BRIDGE_ID,
            DESKBOARD_APPLE_BRIDGE_TOKEN_FILE: tokenFile,
            DESKBOARD_APPLE_MIRROR_DATABASE_PATH: "/tmp/synthetic-mirror.sqlite",
          },
          readTokenFile,
        ),
      ).toThrow(AppleSourceIngestionConfigurationError);
    }
  });

  it("fails partial or malformed configuration with one content-free error", () => {
    for (const environment of [
      { DESKBOARD_APPLE_BRIDGE_ID: EXPECTED_BRIDGE_ID },
      {
        DESKBOARD_APPLE_BRIDGE_ID: EXPECTED_BRIDGE_ID,
        DESKBOARD_APPLE_BRIDGE_TOKEN: "short",
        DESKBOARD_APPLE_MIRROR_DATABASE_PATH: "/tmp/synthetic.sqlite",
      },
      {
        DESKBOARD_APPLE_BRIDGE_ID: EXPECTED_BRIDGE_ID,
        DESKBOARD_APPLE_BRIDGE_TOKEN_FILE: "/run/secrets/token",
      },
    ]) {
      expect(() => readAppleSourceIngestionConfiguration(environment)).toThrow(
        AppleSourceIngestionConfigurationError,
      );
      try {
        readAppleSourceIngestionConfiguration(environment);
      } catch (error) {
        expect(error).toMatchObject({
          code: "APPLE_SOURCE_INGESTION_CONFIGURATION_INVALID",
          message: "Apple source ingestion configuration is invalid.",
        });
        expect(String(error)).not.toContain(CONFIGURED_TOKEN);
      }
    }
  });
});

describe("fixed-format bearer authentication", () => {
  it("compares exactly two 32-byte secret values through the injected constant-time boundary", () => {
    const compare = vi.fn(
      (presented: Uint8Array, expected: Uint8Array) =>
        presented.byteLength === expected.byteLength,
    );

    expect(
      authorizationMatchesConfiguredToken(
        `Bearer ${CONFIGURED_TOKEN}`,
        CONFIGURED_TOKEN,
        compare,
      ),
    ).toBe(true);
    expect(compare).toHaveBeenCalledTimes(1);
    const [presented, expected] = compare.mock.calls[0] ?? [];
    expect(presented).toHaveLength(32);
    expect(expected).toHaveLength(32);
  });

  it("rejects malformed material without invoking the fixed-length comparator", () => {
    const compare = vi.fn(
      (presented: Uint8Array, expected: Uint8Array) =>
        presented.byteLength === expected.byteLength,
    );

    for (const value of [
      undefined,
      `bearer ${CONFIGURED_TOKEN}`,
      "Bearer short",
      [`Bearer ${CONFIGURED_TOKEN}`],
    ]) {
      expect(
        authorizationMatchesConfiguredToken(value, CONFIGURED_TOKEN, compare),
      ).toBe(false);
    }
    expect(compare).not.toHaveBeenCalled();
  });

  it("uses the production constant-time comparison for correct and wrong tokens", () => {
    expect(
      authorizationMatchesConfiguredToken(
        `Bearer ${CONFIGURED_TOKEN}`,
        CONFIGURED_TOKEN,
      ),
    ).toBe(true);
    expect(
      authorizationMatchesConfiguredToken(
        `Bearer ${WRONG_TOKEN}`,
        CONFIGURED_TOKEN,
      ),
    ).toBe(false);
  });
});

describe("POST /v1/apple-source-snapshots", () => {
  it("is absent when ingestion is not configured", async () => {
    const app = buildApp();
    const response = await app.inject({
      method: "POST",
      url: "/v1/apple-source-snapshots",
      headers: authorization(),
      payload: validEnvelope(),
    });
    await app.close();

    expect(response.statusCode).toBe(404);
  });

  it("authenticates before parsing or mirror application", async () => {
    const mirror = new StubMirror({ kind: "rejectedInvalid" });
    const app = buildApp({ appleSourceIngestion: ingestionOptions(mirror) });

    for (const headers of [
      { "content-type": "application/json" },
      { ...authorization(), authorization: "Basic synthetic" },
      authorization(WRONG_TOKEN),
    ]) {
      const response = await app.inject({
        method: "POST",
        url: "/v1/apple-source-snapshots",
        headers,
        payload: '{"sourceRevision":',
      });
      expect(response.statusCode).toBe(401);
      expect(response.json()).toEqual({
        error: { code: "APPLE_SOURCE_AUTHENTICATION_FAILED" },
      });
      expect(response.body).not.toContain(CONFIGURED_TOKEN);
      expect(response.body).not.toContain(WRONG_TOKEN);
    }

    expect(mirror.apply).not.toHaveBeenCalled();
    await app.close();
  });

  it("requires JSON only after successful authentication", async () => {
    const mirror = new StubMirror({ kind: "rejectedInvalid" });
    const app = buildApp({ appleSourceIngestion: ingestionOptions(mirror) });
    const response = await app.inject({
      method: "POST",
      url: "/v1/apple-source-snapshots",
      headers: { authorization: `Bearer ${CONFIGURED_TOKEN}` },
      payload: "synthetic",
    });
    await app.close();

    expect(response.statusCode).toBe(415);
    expect(response.json()).toEqual({
      error: { code: "APPLE_SOURCE_JSON_REQUIRED" },
    });
    expect(mirror.apply).not.toHaveBeenCalled();
  });

  it("rejects an authenticated Bridge-ID mismatch before application", async () => {
    const mirror = new StubMirror({ kind: "rejectedInvalid" });
    const app = buildApp({ appleSourceIngestion: ingestionOptions(mirror) });
    const response = await app.inject({
      method: "POST",
      url: "/v1/apple-source-snapshots",
      headers: authorization(),
      payload: {
        sourceRevision: 1,
        snapshot: makeReminderSnapshot({ bridgeId: "synthetic-other-bridge" }),
      },
    });
    await app.close();

    expect(response.statusCode).toBe(403);
    expect(response.json()).toEqual({
      error: { code: "APPLE_SOURCE_BRIDGE_MISMATCH" },
    });
    expect(mirror.apply).not.toHaveBeenCalled();
  });

  it("rejects unknown envelope and nested snapshot keys without application", async () => {
    const mirror = new StubMirror({ kind: "rejectedInvalid" });
    const app = buildApp({ appleSourceIngestion: ingestionOptions(mirror) });
    const envelope = validEnvelope();
    const candidates = [
      { ...envelope, unexpected: true },
      {
        ...envelope,
        snapshot: { ...envelope.snapshot, unexpected: true },
      },
    ];

    for (const payload of candidates) {
      const response = await app.inject({
        method: "POST",
        url: "/v1/apple-source-snapshots",
        headers: authorization(),
        payload,
      });
      expect(response.statusCode).toBe(400);
      expect(response.json()).toEqual({ kind: "rejectedInvalid" });
    }
    expect(mirror.apply).not.toHaveBeenCalled();
    await app.close();
  });

  it("requires a positive JavaScript-safe integer source revision", async () => {
    const mirror = new StubMirror({ kind: "rejectedInvalid" });
    const app = buildApp({ appleSourceIngestion: ingestionOptions(mirror) });

    for (const sourceRevision of [
      0,
      -1,
      1.5,
      Number.MAX_SAFE_INTEGER + 1,
      "1",
    ]) {
      const response = await app.inject({
        method: "POST",
        url: "/v1/apple-source-snapshots",
        headers: authorization(),
        payload: { ...validEnvelope(), sourceRevision },
      });
      expect(response.statusCode).toBe(400);
      expect(response.json()).toEqual({ kind: "rejectedInvalid" });
    }

    expect(mirror.apply).not.toHaveBeenCalled();
    await app.close();
  });

  it("enforces the explicit route body limit with a content-free response", async () => {
    const mirror = new StubMirror({ kind: "rejectedInvalid" });
    const app = buildApp({ appleSourceIngestion: ingestionOptions(mirror) });
    const response = await app.inject({
      method: "POST",
      url: "/v1/apple-source-snapshots",
      headers: authorization(),
      payload: JSON.stringify({
        sourceRevision: 1,
        snapshot: "x".repeat(APPLE_SOURCE_INGESTION_BODY_LIMIT_BYTES),
      }),
    });
    await app.close();

    expect(response.statusCode).toBe(413);
    expect(response.json()).toEqual({
      error: { code: "APPLE_SOURCE_BODY_TOO_LARGE" },
    });
    expect(mirror.apply).not.toHaveBeenCalled();
  });

  it.each([
    [{ kind: "applied", entityType: "reminder", sourceRevision: 1 }, 200],
    [
      { kind: "unchangedDuplicate", entityType: "reminder", sourceRevision: 1 },
      200,
    ],
    [{ kind: "rejectedStale", entityType: "reminder", sourceRevision: 1 }, 409],
    [
      {
        kind: "rejectedRevisionConflict",
        entityType: "reminder",
        sourceRevision: 1,
      },
      409,
    ],
    [
      { kind: "rejectedTruncated", entityType: "reminder", sourceRevision: 1 },
      422,
    ],
    [{ kind: "rejectedInvalid" }, 400],
  ] as const)("maps %s without adding private fields", async (result, statusCode) => {
    const mirror = new StubMirror(result);
    const app = buildApp({ appleSourceIngestion: ingestionOptions(mirror) });
    const response = await app.inject({
      method: "POST",
      url: "/v1/apple-source-snapshots",
      headers: authorization(),
      payload: validEnvelope(),
    });
    await app.close();

    expect(response.statusCode).toBe(statusCode);
    expect(response.json()).toEqual(result);
    expect(response.body).not.toMatch(/container|identifier|title|digest|token/i);
  });

  it("preserves mirror idempotency through authenticated Fastify delivery", async () => {
    const mirror = new AppleSourceMirror();
    const close = vi.spyOn(mirror, "close");
    const app = buildApp({ appleSourceIngestion: ingestionOptions(mirror) });
    const request = {
      method: "POST" as const,
      url: "/v1/apple-source-snapshots",
      headers: authorization(),
      payload: validEnvelope(),
    };

    const first = await app.inject(request);
    const duplicate = await app.inject(request);
    await app.close();

    expect(first.statusCode).toBe(200);
    expect(first.json()).toEqual({
      kind: "applied",
      entityType: "reminder",
      sourceRevision: 1,
    });
    expect(duplicate.statusCode).toBe(200);
    expect(duplicate.json()).toEqual({
      kind: "unchangedDuplicate",
      entityType: "reminder",
      sourceRevision: 1,
    });
    expect(close).toHaveBeenCalledTimes(1);
  });

  it("keeps health and the fixture Board unchanged while ingestion is enabled", async () => {
    const mirror = new StubMirror({ kind: "rejectedInvalid" });
    const frozen = new Date(2026, 7, 21, 10, 5, 0);
    const app = buildApp({
      appleSourceIngestion: ingestionOptions(mirror),
      clock: () => frozen,
    });

    const health = await app.inject({ method: "GET", url: "/health" });
    const board = await app.inject({ method: "GET", url: "/v1/board" });
    await app.close();

    expect(health.statusCode).toBe(200);
    expect(health.json()).toEqual({
      status: "ok",
      service: "deskboard-api",
    });
    expect(board.statusCode).toBe(200);
    expect(board.headers["cache-control"]).toBe("no-store");
    expect(board.json()).toMatchObject({
      schemaVersion: 1,
      boardVersion: "fixture-default-001",
      generatedAt: frozen.toISOString(),
    });
  });
});
