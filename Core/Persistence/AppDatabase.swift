import Foundation
import GRDB

/// Owns the GRDB database connection and its migrations.
/// Repositories are the only other layer allowed to touch GRDB (spec §8).
public final class AppDatabase {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// In-memory database, used by tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    /// On-disk database at the given path.
    public static func onDisk(path: String) throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        return try AppDatabase(DatabaseQueue(path: path, configuration: configuration))
    }

    /// Forward-only migrations. Never edit a shipped migration; append a new one.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        // Schema v1, verbatim from Docs/kamome-poc-spec.md §3.
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE trip (
                  id TEXT PRIMARY KEY,            -- UUID
                  title TEXT NOT NULL,
                  started_at REAL NOT NULL,       -- unix epoch
                  ended_at REAL,
                  status TEXT NOT NULL,           -- recording | paused | completed
                  origin_plan_id TEXT,            -- non-null if this trip executed a Plan (enables diff)
                  stats_json TEXT                 -- denormalized: distance_m, drive_s, walk_s, top_speed…
                );

                CREATE TABLE segment (
                  id TEXT PRIMARY KEY,
                  trip_id TEXT NOT NULL REFERENCES trip(id),
                  mode TEXT NOT NULL,             -- drive | scooter | walk | cycle | transit | unknown
                  started_at REAL NOT NULL,
                  ended_at REAL,
                  matched_polyline TEXT           -- Google-encoded polyline AFTER map matching (Phase 3)
                );

                CREATE TABLE trackpoint (
                  id INTEGER PRIMARY KEY AUTOINCREMENT,
                  segment_id TEXT NOT NULL REFERENCES segment(id),
                  ts REAL NOT NULL,
                  lat REAL NOT NULL, lon REAL NOT NULL,
                  h_acc REAL, speed REAL, course REAL, altitude REAL
                );
                CREATE INDEX idx_trackpoint_segment_ts ON trackpoint(segment_id, ts);

                CREATE TABLE stop (
                  id TEXT PRIMARY KEY,
                  trip_id TEXT NOT NULL REFERENCES trip(id),
                  lat REAL NOT NULL, lon REAL NOT NULL,
                  arrived_at REAL NOT NULL, departed_at REAL,
                  name TEXT,                      -- reverse-geocoded, user-editable
                  note TEXT,
                  kind TEXT                       -- auto | manual
                );

                CREATE TABLE photo_ref (
                  id TEXT PRIMARY KEY,
                  trip_id TEXT NOT NULL REFERENCES trip(id),
                  stop_id TEXT REFERENCES stop(id),   -- null = attached to route point
                  ph_asset_id TEXT NOT NULL,          -- PhotoKit local identifier; NEVER copy image bytes
                  taken_at REAL, lat REAL, lon REAL,
                  is_highlight INTEGER NOT NULL DEFAULT 0
                );

                CREATE TABLE plan (
                  id TEXT PRIMARY KEY,
                  title TEXT NOT NULL,
                  forked_from TEXT,               -- plan id or share URL of ancestor
                  created_at REAL NOT NULL,
                  updated_at REAL NOT NULL,
                  meta_json TEXT                  -- days, notes, vehicle, season…
                );

                CREATE TABLE plan_stop (
                  id TEXT PRIMARY KEY,
                  plan_id TEXT NOT NULL REFERENCES plan(id),
                  order_idx INTEGER NOT NULL,
                  lat REAL NOT NULL, lon REAL NOT NULL,
                  name TEXT NOT NULL,
                  planned_dwell_min INTEGER,
                  day_idx INTEGER,                -- which trip day
                  note TEXT
                );
                """)
        }

        return migrator
    }
}
