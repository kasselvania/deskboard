import { createHash } from "node:crypto";
import type { DatabaseSync } from "node:sqlite";

import {
  appleBridgeStatusSnapshotV1Schema,
  isIsoInstant,
  type AppleBridgeStatusSnapshotV1,
} from "@deskboard/contracts";

export type AppleBridgeStatusApplyResult =
  | { kind: "applied"; statusRevision: number }
  | { kind: "unchangedDuplicate"; statusRevision: number }
  | { kind: "rejectedStale"; statusRevision: number }
  | { kind: "rejectedRevisionConflict"; statusRevision: number }
  | { kind: "rejectedInvalid" };

export class AppleBridgeStatusApplyError extends Error {
  readonly code = "APPLE_BRIDGE_STATUS_APPLY_FAILED";

  constructor() {
    super("Apple Bridge status apply failed.");
    this.name = "AppleBridgeStatusApplyError";
  }
}

export class AppleBridgeStatusReadError extends Error {
  readonly code = "APPLE_BRIDGE_STATUS_READ_FAILED";

  constructor() {
    super("Apple Bridge status read failed.");
    this.name = "AppleBridgeStatusReadError";
  }
}

function canonicalJson(value: unknown): string {
  if (value === null || typeof value === "boolean" || typeof value === "string") {
    return JSON.stringify(value);
  }
  if (typeof value === "number" && Number.isFinite(value)) {
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => canonicalJson(entry)).join(",")}]`;
  }
  if (typeof value === "object") {
    const object = value as Record<string, unknown>;
    return `{${Object.keys(object)
      .filter((key) => object[key] !== undefined)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(object[key])}`)
      .join(",")}}`;
  }
  throw new AppleBridgeStatusApplyError();
}

function digest(snapshot: AppleBridgeStatusSnapshotV1): string {
  return createHash("sha256").update(canonicalJson(snapshot)).digest("hex");
}

function rollbackIfNeeded(database: DatabaseSync): void {
  if (!database.isTransaction) {
    return;
  }
  try {
    database.exec("ROLLBACK");
  } catch {
    // Preserve the fixed safe outer error.
  }
}

function requireString(row: Record<string, unknown>, key: string): string {
  const value = row[key];
  if (typeof value !== "string") {
    throw new AppleBridgeStatusReadError();
  }
  return value;
}

function requireSafeInteger(
  row: Record<string, unknown>,
  key: string,
): number {
  const value = row[key];
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw new AppleBridgeStatusReadError();
  }
  return value;
}

export class AppleBridgeStatusStore {
  readonly #database: DatabaseSync;
  readonly #clock: () => Date;

  constructor(database: DatabaseSync, clock: () => Date) {
    this.#database = database;
    this.#clock = clock;
  }

  apply(input: unknown): AppleBridgeStatusApplyResult {
    let parsed: ReturnType<typeof appleBridgeStatusSnapshotV1Schema.safeParse>;
    try {
      parsed = appleBridgeStatusSnapshotV1Schema.safeParse(input);
    } catch {
      return { kind: "rejectedInvalid" };
    }
    if (!parsed.success) {
      return { kind: "rejectedInvalid" };
    }

    const snapshot = parsed.data;
    const normalizedDigest = digest(snapshot);
    try {
      this.#database.exec("BEGIN IMMEDIATE");
      const current = this.#database
        .prepare(
          `
            SELECT accepted_status_revision, normalized_digest
            FROM apple_bridge_status_snapshots
            WHERE bridge_id = ?
          `,
        )
        .get(snapshot.bridgeId);

      if (current) {
        const acceptedRevision = requireSafeInteger(
          current,
          "accepted_status_revision",
        );
        const acceptedDigest = requireString(current, "normalized_digest");
        if (snapshot.statusRevision < acceptedRevision) {
          this.#database.exec("ROLLBACK");
          return {
            kind: "rejectedStale",
            statusRevision: snapshot.statusRevision,
          };
        }
        if (snapshot.statusRevision === acceptedRevision) {
          this.#database.exec("ROLLBACK");
          return {
            kind:
              normalizedDigest === acceptedDigest
                ? "unchangedDuplicate"
                : "rejectedRevisionConflict",
            statusRevision: snapshot.statusRevision,
          };
        }
      }

      const receivedAt = this.#clock().toISOString();
      this.#database
        .prepare(
          `
            INSERT INTO apple_bridge_status_snapshots (
              bridge_id,
              accepted_status_revision,
              normalized_digest,
              captured_at,
              core_received_at,
              document_json
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT (bridge_id) DO UPDATE SET
              accepted_status_revision = excluded.accepted_status_revision,
              normalized_digest = excluded.normalized_digest,
              captured_at = excluded.captured_at,
              core_received_at = excluded.core_received_at,
              document_json = excluded.document_json
          `,
        )
        .run(
          snapshot.bridgeId,
          snapshot.statusRevision,
          normalizedDigest,
          snapshot.capturedAt,
          receivedAt,
          canonicalJson(snapshot),
        );
      this.#database.exec("COMMIT");
      return { kind: "applied", statusRevision: snapshot.statusRevision };
    } catch {
      rollbackIfNeeded(this.#database);
      throw new AppleBridgeStatusApplyError();
    }
  }

  read(bridgeId: string): AppleBridgeStatusSnapshotV1 | null {
    if (bridgeId.length === 0) {
      throw new AppleBridgeStatusReadError();
    }
    try {
      const row = this.#database
        .prepare(
          `
            SELECT
              accepted_status_revision,
              normalized_digest,
              captured_at,
              core_received_at,
              document_json
            FROM apple_bridge_status_snapshots
            WHERE bridge_id = ?
          `,
        )
        .get(bridgeId);
      if (!row) {
        return null;
      }

      const acceptedRevision = requireSafeInteger(
        row,
        "accepted_status_revision",
      );
      const normalizedDigest = requireString(row, "normalized_digest");
      const capturedAt = requireString(row, "captured_at");
      const coreReceivedAt = requireString(row, "core_received_at");
      const snapshot = appleBridgeStatusSnapshotV1Schema.parse(
        JSON.parse(requireString(row, "document_json")) as unknown,
      );
      if (
        snapshot.bridgeId !== bridgeId ||
        snapshot.statusRevision !== acceptedRevision ||
        snapshot.capturedAt !== capturedAt ||
        digest(snapshot) !== normalizedDigest ||
        !isIsoInstant(coreReceivedAt)
      ) {
        throw new AppleBridgeStatusReadError();
      }
      return snapshot;
    } catch {
      throw new AppleBridgeStatusReadError();
    }
  }
}
