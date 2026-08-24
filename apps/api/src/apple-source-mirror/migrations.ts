import type { DatabaseSync } from "node:sqlite";

interface AppleSourceMirrorMigration {
  version: number;
  name: string;
  sql: string;
}

export const APPLE_SOURCE_MIRROR_MIGRATIONS = [
  {
    version: 1,
    name: "initial_atomic_apple_source_mirror",
    sql: `
      CREATE TABLE apple_source_scopes (
        bridge_id TEXT NOT NULL CHECK (length(bridge_id) > 0),
        entity_type TEXT NOT NULL CHECK (entity_type IN ('reminder', 'calendar')),
        source_container_id TEXT NOT NULL CHECK (length(source_container_id) > 0),
        accepted_source_revision INTEGER NOT NULL CHECK (accepted_source_revision > 0),
        normalized_digest TEXT NOT NULL CHECK (
          length(normalized_digest) = 64
          AND normalized_digest NOT GLOB '*[^0-9a-f]*'
        ),
        source_captured_at TEXT NOT NULL CHECK (length(source_captured_at) > 0),
        core_received_at TEXT NOT NULL CHECK (length(core_received_at) > 0),
        matched_count INTEGER NOT NULL CHECK (matched_count >= 0),
        allows_content_modifications INTEGER NOT NULL
          CHECK (allows_content_modifications IN (0, 1)),
        calendar_is_subscribed INTEGER CHECK (calendar_is_subscribed IN (0, 1)),
        calendar_window_start TEXT,
        calendar_window_end TEXT,
        calendar_window_start_ms INTEGER,
        calendar_window_end_ms INTEGER,
        calendar_window_time_zone TEXT,
        calendar_window_boundary_semantics TEXT,
        PRIMARY KEY (bridge_id, entity_type, source_container_id),
        CHECK (
          (
            entity_type = 'reminder'
            AND calendar_is_subscribed IS NULL
            AND calendar_window_start IS NULL
            AND calendar_window_end IS NULL
            AND calendar_window_start_ms IS NULL
            AND calendar_window_end_ms IS NULL
            AND calendar_window_time_zone IS NULL
            AND calendar_window_boundary_semantics IS NULL
          )
          OR
          (
            entity_type = 'calendar'
            AND calendar_is_subscribed IS NOT NULL
            AND calendar_window_start IS NOT NULL
            AND calendar_window_end IS NOT NULL
            AND calendar_window_start_ms IS NOT NULL
            AND calendar_window_end_ms IS NOT NULL
            AND calendar_window_start_ms < calendar_window_end_ms
            AND calendar_window_time_zone IS NOT NULL
            AND length(calendar_window_time_zone) > 0
            AND calendar_window_boundary_semantics =
              'overlapStartInclusiveEndExclusive'
          )
        )
      ) STRICT;

      CREATE TABLE apple_reminder_records (
        bridge_id TEXT NOT NULL,
        entity_type TEXT NOT NULL DEFAULT 'reminder'
          CHECK (entity_type = 'reminder'),
        source_container_id TEXT NOT NULL,
        source_revision INTEGER NOT NULL CHECK (source_revision > 0),
        record_order INTEGER NOT NULL CHECK (record_order >= 0),
        local_identifier TEXT NOT NULL CHECK (length(local_identifier) > 0),
        record_json TEXT NOT NULL CHECK (json_valid(record_json)),
        PRIMARY KEY (
          bridge_id,
          entity_type,
          source_container_id,
          source_revision,
          record_order
        ),
        FOREIGN KEY (bridge_id, entity_type, source_container_id)
          REFERENCES apple_source_scopes (
            bridge_id,
            entity_type,
            source_container_id
          )
          ON DELETE CASCADE
      ) STRICT;

      CREATE TABLE apple_calendar_records (
        bridge_id TEXT NOT NULL,
        entity_type TEXT NOT NULL DEFAULT 'calendar'
          CHECK (entity_type = 'calendar'),
        source_container_id TEXT NOT NULL,
        source_revision INTEGER NOT NULL CHECK (source_revision > 0),
        record_order INTEGER NOT NULL CHECK (record_order >= 0),
        local_identifier TEXT NOT NULL CHECK (length(local_identifier) > 0),
        temporal_kind TEXT NOT NULL CHECK (
          temporal_kind IN ('localTimedRange', 'timeZoneTimedRange', 'allDayRange')
        ),
        interpretation_time_zone TEXT NOT NULL
          CHECK (length(interpretation_time_zone) > 0),
        range_start_ms INTEGER NOT NULL,
        range_end_ms INTEGER NOT NULL CHECK (range_end_ms > range_start_ms),
        record_json TEXT NOT NULL CHECK (json_valid(record_json)),
        PRIMARY KEY (
          bridge_id,
          entity_type,
          source_container_id,
          source_revision,
          record_order
        ),
        FOREIGN KEY (bridge_id, entity_type, source_container_id)
          REFERENCES apple_source_scopes (
            bridge_id,
            entity_type,
            source_container_id
          )
          ON DELETE CASCADE
      ) STRICT;

      CREATE INDEX apple_calendar_records_overlap
        ON apple_calendar_records (
          bridge_id,
          source_container_id,
          range_start_ms,
          range_end_ms
        );
    `,
  },
  {
    version: 2,
    name: "bridge_status_snapshot_v1",
    sql: `
      CREATE TABLE apple_bridge_status_snapshots (
        bridge_id TEXT PRIMARY KEY CHECK (length(bridge_id) > 0),
        accepted_status_revision INTEGER NOT NULL
          CHECK (accepted_status_revision > 0),
        normalized_digest TEXT NOT NULL CHECK (
          length(normalized_digest) = 64
          AND normalized_digest NOT GLOB '*[^0-9a-f]*'
        ),
        captured_at TEXT NOT NULL CHECK (length(captured_at) > 0),
        core_received_at TEXT NOT NULL CHECK (length(core_received_at) > 0),
        document_json TEXT NOT NULL CHECK (json_valid(document_json))
      ) STRICT;
    `,
  },
] as const satisfies readonly AppleSourceMirrorMigration[];

const migrationLedgerSql = `
  CREATE TABLE IF NOT EXISTS apple_source_mirror_migrations (
    version INTEGER PRIMARY KEY CHECK (version > 0),
    name TEXT NOT NULL UNIQUE CHECK (length(name) > 0)
  ) STRICT;
`;

export class AppleSourceMirrorMigrationError extends Error {
  readonly code = "APPLE_SOURCE_MIRROR_MIGRATION_FAILED";

  constructor() {
    super("Apple source mirror migration failed.");
    this.name = "AppleSourceMirrorMigrationError";
  }
}

function rollbackIfNeeded(database: DatabaseSync): void {
  if (!database.isTransaction) {
    return;
  }

  try {
    database.exec("ROLLBACK");
  } catch {
    // The fixed outer error remains the only surfaced migration detail.
  }
}

export function configureAppleSourceMirrorConnection(
  database: DatabaseSync,
): void {
  database.exec("PRAGMA foreign_keys = ON");
  const row = database.prepare("PRAGMA foreign_keys").get();
  if (row?.foreign_keys !== 1) {
    throw new AppleSourceMirrorMigrationError();
  }
}

export function applyAppleSourceMirrorMigrations(
  database: DatabaseSync,
): void {
  try {
    database.exec("BEGIN IMMEDIATE");
    database.exec(migrationLedgerSql);

    const rows = database
      .prepare(
        "SELECT version, name FROM apple_source_mirror_migrations ORDER BY version",
      )
      .all();
    const applied = new Map<number, string>();

    for (const row of rows) {
      if (
        typeof row.version !== "number" ||
        !Number.isSafeInteger(row.version) ||
        typeof row.name !== "string"
      ) {
        throw new AppleSourceMirrorMigrationError();
      }
      applied.set(row.version, row.name);
    }

    const knownVersions = new Set<number>(
      APPLE_SOURCE_MIRROR_MIGRATIONS.map((migration) => migration.version),
    );
    if ([...applied.keys()].some((version) => !knownVersions.has(version))) {
      throw new AppleSourceMirrorMigrationError();
    }

    const recordMigration = database.prepare(
      "INSERT INTO apple_source_mirror_migrations (version, name) VALUES (?, ?)",
    );
    for (const migration of APPLE_SOURCE_MIRROR_MIGRATIONS) {
      const appliedName = applied.get(migration.version);
      if (appliedName !== undefined) {
        if (appliedName !== migration.name) {
          throw new AppleSourceMirrorMigrationError();
        }
        continue;
      }

      database.exec(migration.sql);
      recordMigration.run(migration.version, migration.name);
    }

    database.exec("COMMIT");
  } catch {
    rollbackIfNeeded(database);
    throw new AppleSourceMirrorMigrationError();
  }
}
