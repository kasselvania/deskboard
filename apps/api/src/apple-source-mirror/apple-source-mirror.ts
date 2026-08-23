import { createHash } from "node:crypto";
import { DatabaseSync } from "node:sqlite";

import {
  appleCalendarSourceRecordV1Schema,
  appleReminderSourceRecordV1Schema,
  appleSourceSnapshotV1Schema,
  isIsoInstant,
  isRecognizedTimeZone,
  type AppleCalendarSourceRecordV1,
  type AppleCalendarSourceSnapshotV1,
  type AppleReminderSourceRecordV1,
  type AppleReminderSourceSnapshotV1,
  type AppleSourceSnapshotV1,
} from "@deskboard/contracts";

import { interpretAppleCalendarRecordRange } from "./calendar-range.js";
import {
  AppleSourceMirrorMigrationError,
  applyAppleSourceMirrorMigrations,
  configureAppleSourceMirrorConnection,
} from "./migrations.js";

export type AppleSourceEntityType = "reminder" | "calendar";

export interface AppleSourceScopeCoordinate {
  bridgeId: string;
  entityType: AppleSourceEntityType;
  sourceContainerId: string;
}

export interface AppleReminderSourceScopeCoordinate
  extends AppleSourceScopeCoordinate {
  entityType: "reminder";
}

export interface AppleCalendarSourceScopeCoordinate
  extends AppleSourceScopeCoordinate {
  entityType: "calendar";
}

interface AppleSourceScopeSummaryBase extends AppleSourceScopeCoordinate {
  acceptedSourceRevision: number;
  normalizedDigest: string;
  sourceCapturedAt: string;
  coreReceivedAt: string;
  matchedCount: number;
  allowsContentModifications: boolean;
}

export interface AppleReminderSourceScopeSummary
  extends AppleSourceScopeSummaryBase {
  entityType: "reminder";
}

export interface AppleCalendarSourceScopeSummary
  extends AppleSourceScopeSummaryBase {
  entityType: "calendar";
  isSubscribed: boolean;
  window: {
    start: string;
    end: string;
    timeZone: string;
    boundarySemantics: "overlapStartInclusiveEndExclusive";
  };
}

export type AppleSourceScopeSummary =
  | AppleReminderSourceScopeSummary
  | AppleCalendarSourceScopeSummary;

type ParsedApplyResult = {
  entityType: AppleSourceEntityType;
  sourceRevision: number;
};

export type AppleSourceMirrorApplyResult =
  | ({ kind: "applied" } & ParsedApplyResult)
  | ({ kind: "unchangedDuplicate" } & ParsedApplyResult)
  | ({ kind: "rejectedStale" } & ParsedApplyResult)
  | ({ kind: "rejectedRevisionConflict" } & ParsedApplyResult)
  | ({ kind: "rejectedTruncated" } & ParsedApplyResult)
  | { kind: "rejectedInvalid" };

export interface AppleSourceMirrorOptions {
  databasePath?: string | URL;
  clock?: () => Date;
  /** Narrow failure injection for transaction rollback tests only. */
  testOnlyAfterDestructiveSql?: () => void;
}

export class AppleSourceMirrorApplyError extends Error {
  readonly code = "APPLE_SOURCE_MIRROR_APPLY_FAILED";

  constructor() {
    super("Apple source mirror apply failed.");
    this.name = "AppleSourceMirrorApplyError";
  }
}

export class AppleSourceMirrorReadError extends Error {
  readonly code = "APPLE_SOURCE_MIRROR_READ_FAILED";

  constructor() {
    super("Apple source mirror read failed.");
    this.name = "AppleSourceMirrorReadError";
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
      .map(
        (key) => `${JSON.stringify(key)}:${canonicalJson(object[key])}`,
      )
      .join(",")}}`;
  }

  throw new AppleSourceMirrorApplyError();
}

function normalizedSnapshotDigest(snapshot: AppleSourceSnapshotV1): string {
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

function isValidCoordinate(coordinate: AppleSourceScopeCoordinate): boolean {
  return (
    (coordinate.entityType === "reminder" ||
      coordinate.entityType === "calendar") &&
    coordinate.bridgeId.length > 0 &&
    coordinate.sourceContainerId.length > 0
  );
}

function requireString(
  row: Record<string, unknown>,
  key: string,
): string {
  const value = row[key];
  if (typeof value !== "string") {
    throw new AppleSourceMirrorReadError();
  }
  return value;
}

function requireSafeInteger(
  row: Record<string, unknown>,
  key: string,
): number {
  const value = row[key];
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw new AppleSourceMirrorReadError();
  }
  return value;
}

function requireBooleanInteger(
  row: Record<string, unknown>,
  key: string,
): boolean {
  const value = requireSafeInteger(row, key);
  if (value !== 0 && value !== 1) {
    throw new AppleSourceMirrorReadError();
  }
  return value === 1;
}

function parseReminderRecordRow(
  row: Record<string, unknown>,
): AppleReminderSourceRecordV1 {
  try {
    const recordJson = requireString(row, "record_json");
    const record = appleReminderSourceRecordV1Schema.parse(
      JSON.parse(recordJson) as unknown,
    );
    if (record.localIdentifier !== requireString(row, "local_identifier")) {
      throw new AppleSourceMirrorReadError();
    }
    return record;
  } catch {
    throw new AppleSourceMirrorReadError();
  }
}

function parseCalendarRecordRow(
  row: Record<string, unknown>,
): AppleCalendarSourceRecordV1 {
  try {
    const recordJson = requireString(row, "record_json");
    const record = appleCalendarSourceRecordV1Schema.parse(
      JSON.parse(recordJson) as unknown,
    );
    const interpretationTimeZone = requireString(
      row,
      "interpretation_time_zone",
    );
    const range = interpretAppleCalendarRecordRange(
      record,
      interpretationTimeZone,
    );
    if (
      record.localIdentifier !== requireString(row, "local_identifier") ||
      record.temporal.kind !== requireString(row, "temporal_kind") ||
      !range ||
      range.startMs !== requireSafeInteger(row, "range_start_ms") ||
      range.endMs !== requireSafeInteger(row, "range_end_ms")
    ) {
      throw new AppleSourceMirrorReadError();
    }
    return record;
  } catch {
    throw new AppleSourceMirrorReadError();
  }
}

export class AppleSourceMirror {
  readonly #database: DatabaseSync;
  readonly #clock: () => Date;
  readonly #testOnlyAfterDestructiveSql: (() => void) | undefined;

  constructor(options: AppleSourceMirrorOptions = {}) {
    let database: DatabaseSync;
    try {
      database = new DatabaseSync(options.databasePath ?? ":memory:");
    } catch {
      throw new AppleSourceMirrorMigrationError();
    }

    try {
      configureAppleSourceMirrorConnection(database);
      applyAppleSourceMirrorMigrations(database);
      database.enableDefensive(true);
    } catch {
      if (database.isOpen) {
        database.close();
      }
      throw new AppleSourceMirrorMigrationError();
    }

    this.#database = database;
    this.#clock = options.clock ?? (() => new Date());
    this.#testOnlyAfterDestructiveSql =
      options.testOnlyAfterDestructiveSql;
  }

  close(): void {
    if (this.#database.isOpen) {
      this.#database.close();
    }
  }

  apply(input: {
    snapshot: unknown;
    sourceRevision: number;
  }): AppleSourceMirrorApplyResult {
    if (
      !Number.isSafeInteger(input.sourceRevision) ||
      input.sourceRevision <= 0
    ) {
      return { kind: "rejectedInvalid" };
    }

    let parsed: ReturnType<typeof appleSourceSnapshotV1Schema.safeParse>;
    try {
      parsed = appleSourceSnapshotV1Schema.safeParse(input.snapshot);
    } catch {
      return { kind: "rejectedInvalid" };
    }
    if (!parsed.success) {
      return { kind: "rejectedInvalid" };
    }

    const snapshot = parsed.data;
    if (snapshot.truncated) {
      return {
        kind: "rejectedTruncated",
        entityType: snapshot.entityType,
        sourceRevision: input.sourceRevision,
      };
    }

    const digest = normalizedSnapshotDigest(snapshot);
    return this.#applyAuthoritativeSnapshot(
      snapshot,
      input.sourceRevision,
      digest,
    );
  }

  readSourceScopeSummary(
    coordinate: AppleReminderSourceScopeCoordinate,
  ): AppleReminderSourceScopeSummary | null;
  readSourceScopeSummary(
    coordinate: AppleCalendarSourceScopeCoordinate,
  ): AppleCalendarSourceScopeSummary | null;
  readSourceScopeSummary(
    coordinate: AppleSourceScopeCoordinate,
  ): AppleSourceScopeSummary | null {
    if (!isValidCoordinate(coordinate)) {
      throw new AppleSourceMirrorReadError();
    }

    try {
      const row = this.#database
        .prepare(
          `
            SELECT
              accepted_source_revision,
              normalized_digest,
              source_captured_at,
              core_received_at,
              matched_count,
              allows_content_modifications,
              calendar_is_subscribed,
              calendar_window_start,
              calendar_window_end,
              calendar_window_start_ms,
              calendar_window_end_ms,
              calendar_window_time_zone,
              calendar_window_boundary_semantics
            FROM apple_source_scopes
            WHERE bridge_id = ?
              AND entity_type = ?
              AND source_container_id = ?
          `,
        )
        .get(
          coordinate.bridgeId,
          coordinate.entityType,
          coordinate.sourceContainerId,
        );
      if (!row) {
        return null;
      }

      const acceptedSourceRevision = requireSafeInteger(
        row,
        "accepted_source_revision",
      );
      const normalizedDigest = requireString(row, "normalized_digest");
      const sourceCapturedAt = requireString(row, "source_captured_at");
      const coreReceivedAt = requireString(row, "core_received_at");
      const matchedCount = requireSafeInteger(row, "matched_count");
      const allowsContentModifications = requireBooleanInteger(
        row,
        "allows_content_modifications",
      );
      if (
        acceptedSourceRevision <= 0 ||
        matchedCount < 0 ||
        !/^[0-9a-f]{64}$/.test(normalizedDigest) ||
        !isIsoInstant(sourceCapturedAt) ||
        !isIsoInstant(coreReceivedAt)
      ) {
        throw new AppleSourceMirrorReadError();
      }

      const base = {
        ...coordinate,
        acceptedSourceRevision,
        normalizedDigest,
        sourceCapturedAt,
        coreReceivedAt,
        matchedCount,
        allowsContentModifications,
      };
      if (coordinate.entityType === "reminder") {
        return { ...base, entityType: "reminder" };
      }

      const start = requireString(row, "calendar_window_start");
      const end = requireString(row, "calendar_window_end");
      const startMs = requireSafeInteger(row, "calendar_window_start_ms");
      const endMs = requireSafeInteger(row, "calendar_window_end_ms");
      const timeZone = requireString(row, "calendar_window_time_zone");
      const boundarySemantics = requireString(
        row,
        "calendar_window_boundary_semantics",
      );
      if (
        !isIsoInstant(start) ||
        !isIsoInstant(end) ||
        Date.parse(start) !== startMs ||
        Date.parse(end) !== endMs ||
        endMs <= startMs ||
        !isRecognizedTimeZone(timeZone) ||
        boundarySemantics !== "overlapStartInclusiveEndExclusive"
      ) {
        throw new AppleSourceMirrorReadError();
      }

      return {
        ...base,
        entityType: "calendar",
        isSubscribed: requireBooleanInteger(row, "calendar_is_subscribed"),
        window: {
          start,
          end,
          timeZone,
          boundarySemantics,
        },
      };
    } catch {
      throw new AppleSourceMirrorReadError();
    }
  }

  listReminderRecords(
    coordinate: AppleReminderSourceScopeCoordinate,
  ): AppleReminderSourceRecordV1[] {
    const summary = this.readSourceScopeSummary(coordinate);
    if (!summary) {
      return [];
    }

    try {
      return this.#database
        .prepare(
          `
            SELECT local_identifier, record_json
            FROM apple_reminder_records
            WHERE bridge_id = ?
              AND entity_type = 'reminder'
              AND source_container_id = ?
              AND source_revision = ?
            ORDER BY record_order
          `,
        )
        .all(
          coordinate.bridgeId,
          coordinate.sourceContainerId,
          summary.acceptedSourceRevision,
        )
        .map((row) => parseReminderRecordRow(row));
    } catch {
      throw new AppleSourceMirrorReadError();
    }
  }

  listCalendarRecordsInLatestWindow(
    coordinate: AppleCalendarSourceScopeCoordinate,
  ): AppleCalendarSourceRecordV1[] {
    const summary = this.readSourceScopeSummary(coordinate);
    if (!summary) {
      return [];
    }

    try {
      const windowStartMs = Date.parse(summary.window.start);
      const windowEndMs = Date.parse(summary.window.end);
      return this.#database
        .prepare(
          `
            SELECT
              local_identifier,
              temporal_kind,
              interpretation_time_zone,
              range_start_ms,
              range_end_ms,
              record_json
            FROM apple_calendar_records
            WHERE bridge_id = ?
              AND entity_type = 'calendar'
              AND source_container_id = ?
              AND source_revision = ?
              AND range_start_ms < ?
              AND range_end_ms > ?
            ORDER BY record_order
          `,
        )
        .all(
          coordinate.bridgeId,
          coordinate.sourceContainerId,
          summary.acceptedSourceRevision,
          windowEndMs,
          windowStartMs,
        )
        .map((row) => parseCalendarRecordRow(row));
    } catch {
      throw new AppleSourceMirrorReadError();
    }
  }

  listRetainedCalendarRecordsOutsideLatestWindow(
    coordinate: AppleCalendarSourceScopeCoordinate,
  ): AppleCalendarSourceRecordV1[] {
    const summary = this.readSourceScopeSummary(coordinate);
    if (!summary) {
      return [];
    }

    try {
      const windowStartMs = Date.parse(summary.window.start);
      const windowEndMs = Date.parse(summary.window.end);
      return this.#database
        .prepare(
          `
            SELECT
              local_identifier,
              temporal_kind,
              interpretation_time_zone,
              range_start_ms,
              range_end_ms,
              record_json
            FROM apple_calendar_records
            WHERE bridge_id = ?
              AND entity_type = 'calendar'
              AND source_container_id = ?
              AND NOT (range_start_ms < ? AND range_end_ms > ?)
            ORDER BY range_start_ms, range_end_ms, source_revision, record_order
          `,
        )
        .all(
          coordinate.bridgeId,
          coordinate.sourceContainerId,
          windowEndMs,
          windowStartMs,
        )
        .map((row) => parseCalendarRecordRow(row));
    } catch {
      throw new AppleSourceMirrorReadError();
    }
  }

  #applyAuthoritativeSnapshot(
    snapshot: AppleSourceSnapshotV1,
    sourceRevision: number,
    digest: string,
  ): AppleSourceMirrorApplyResult {
    try {
      this.#database.exec("BEGIN IMMEDIATE");
      const current = this.#database
        .prepare(
          `
            SELECT accepted_source_revision, normalized_digest
            FROM apple_source_scopes
            WHERE bridge_id = ?
              AND entity_type = ?
              AND source_container_id = ?
          `,
        )
        .get(
          snapshot.bridgeId,
          snapshot.entityType,
          snapshot.source.sourceContainerId,
        );

      if (current) {
        const acceptedRevision = requireSafeInteger(
          current,
          "accepted_source_revision",
        );
        const acceptedDigest = requireString(current, "normalized_digest");
        if (sourceRevision < acceptedRevision) {
          this.#database.exec("ROLLBACK");
          return {
            kind: "rejectedStale",
            entityType: snapshot.entityType,
            sourceRevision,
          };
        }
        if (sourceRevision === acceptedRevision) {
          this.#database.exec("ROLLBACK");
          return {
            kind:
              digest === acceptedDigest
                ? "unchangedDuplicate"
                : "rejectedRevisionConflict",
            entityType: snapshot.entityType,
            sourceRevision,
          };
        }
      }

      const receivedAt = this.#clock().toISOString();
      this.#upsertScope(snapshot, sourceRevision, digest, receivedAt);
      if (snapshot.entityType === "reminder") {
        this.#replaceReminderRecords(snapshot, sourceRevision);
      } else {
        this.#replaceCalendarRecords(snapshot, sourceRevision);
      }
      this.#database.exec("COMMIT");

      return {
        kind: "applied",
        entityType: snapshot.entityType,
        sourceRevision,
      };
    } catch {
      rollbackIfNeeded(this.#database);
      throw new AppleSourceMirrorApplyError();
    }
  }

  #upsertScope(
    snapshot: AppleSourceSnapshotV1,
    sourceRevision: number,
    digest: string,
    receivedAt: string,
  ): void {
    const isCalendar = snapshot.entityType === "calendar";
    const window = isCalendar ? snapshot.window : undefined;
    this.#database
      .prepare(
        `
          INSERT INTO apple_source_scopes (
            bridge_id,
            entity_type,
            source_container_id,
            accepted_source_revision,
            normalized_digest,
            source_captured_at,
            core_received_at,
            matched_count,
            allows_content_modifications,
            calendar_is_subscribed,
            calendar_window_start,
            calendar_window_end,
            calendar_window_start_ms,
            calendar_window_end_ms,
            calendar_window_time_zone,
            calendar_window_boundary_semantics
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT (bridge_id, entity_type, source_container_id)
          DO UPDATE SET
            accepted_source_revision = excluded.accepted_source_revision,
            normalized_digest = excluded.normalized_digest,
            source_captured_at = excluded.source_captured_at,
            core_received_at = excluded.core_received_at,
            matched_count = excluded.matched_count,
            allows_content_modifications = excluded.allows_content_modifications,
            calendar_is_subscribed = excluded.calendar_is_subscribed,
            calendar_window_start = excluded.calendar_window_start,
            calendar_window_end = excluded.calendar_window_end,
            calendar_window_start_ms = excluded.calendar_window_start_ms,
            calendar_window_end_ms = excluded.calendar_window_end_ms,
            calendar_window_time_zone = excluded.calendar_window_time_zone,
            calendar_window_boundary_semantics =
              excluded.calendar_window_boundary_semantics
        `,
      )
      .run(
        snapshot.bridgeId,
        snapshot.entityType,
        snapshot.source.sourceContainerId,
        sourceRevision,
        digest,
        snapshot.capturedAt,
        receivedAt,
        snapshot.matchedCount,
        snapshot.source.allowsContentModifications ? 1 : 0,
        isCalendar && snapshot.source.isSubscribed ? 1 : isCalendar ? 0 : null,
        window?.start ?? null,
        window?.end ?? null,
        window ? Date.parse(window.start) : null,
        window ? Date.parse(window.end) : null,
        window?.timeZone ?? null,
        window?.boundarySemantics ?? null,
      );
  }

  #replaceReminderRecords(
    snapshot: AppleReminderSourceSnapshotV1,
    sourceRevision: number,
  ): void {
    this.#database
      .prepare(
        `
          DELETE FROM apple_reminder_records
          WHERE bridge_id = ?
            AND entity_type = 'reminder'
            AND source_container_id = ?
        `,
      )
      .run(snapshot.bridgeId, snapshot.source.sourceContainerId);
    this.#testOnlyAfterDestructiveSql?.();

    const insert = this.#database.prepare(
      `
        INSERT INTO apple_reminder_records (
          bridge_id,
          entity_type,
          source_container_id,
          source_revision,
          record_order,
          local_identifier,
          record_json
        ) VALUES (?, 'reminder', ?, ?, ?, ?, ?)
      `,
    );
    for (const [recordOrder, record] of snapshot.records.entries()) {
      insert.run(
        snapshot.bridgeId,
        snapshot.source.sourceContainerId,
        sourceRevision,
        recordOrder,
        record.localIdentifier,
        canonicalJson(record),
      );
    }
  }

  #replaceCalendarRecords(
    snapshot: AppleCalendarSourceSnapshotV1,
    sourceRevision: number,
  ): void {
    const windowStartMs = Date.parse(snapshot.window.start);
    const windowEndMs = Date.parse(snapshot.window.end);
    this.#database
      .prepare(
        `
          DELETE FROM apple_calendar_records
          WHERE bridge_id = ?
            AND entity_type = 'calendar'
            AND source_container_id = ?
            AND range_start_ms < ?
            AND range_end_ms > ?
        `,
      )
      .run(
        snapshot.bridgeId,
        snapshot.source.sourceContainerId,
        windowEndMs,
        windowStartMs,
      );
    this.#testOnlyAfterDestructiveSql?.();

    const insert = this.#database.prepare(
      `
        INSERT INTO apple_calendar_records (
          bridge_id,
          entity_type,
          source_container_id,
          source_revision,
          record_order,
          local_identifier,
          temporal_kind,
          interpretation_time_zone,
          range_start_ms,
          range_end_ms,
          record_json
        ) VALUES (?, 'calendar', ?, ?, ?, ?, ?, ?, ?, ?, ?)
      `,
    );
    for (const [recordOrder, record] of snapshot.records.entries()) {
      const range = interpretAppleCalendarRecordRange(
        record,
        snapshot.window.timeZone,
      );
      if (!range) {
        throw new AppleSourceMirrorApplyError();
      }
      insert.run(
        snapshot.bridgeId,
        snapshot.source.sourceContainerId,
        sourceRevision,
        recordOrder,
        record.localIdentifier,
        record.temporal.kind,
        snapshot.window.timeZone,
        range.startMs,
        range.endMs,
        canonicalJson(record),
      );
    }
  }
}
