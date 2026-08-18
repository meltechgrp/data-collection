/**
 * Applies pending Prisma migrations using better-sqlite3 directly.
 *
 * The Prisma CLI is not shipped in the runtime image: it pulls in ~170MB of
 * dependencies (Studio, pglite, effect) that a running container never needs.
 * This script reads the same `prisma/migrations` directory and writes the same
 * `_prisma_migrations` bookkeeping table, so `prisma migrate status` and local
 * `prisma migrate dev` stay in sync with what the container has applied.
 */
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const Database = require("better-sqlite3");

const root = process.env.APP_ROOT || process.cwd();
const url = process.env.DATABASE_URL || "file:./data/dev.db";

if (!url.startsWith("file:")) {
  console.error(`Unsupported DATABASE_URL for SQLite: ${url}`);
  process.exit(1);
}

const dbPath = path.resolve(root, url.slice("file:".length));
fs.mkdirSync(path.dirname(dbPath), { recursive: true });

const db = new Database(dbPath);
db.pragma("journal_mode = WAL");

// Matches the table Prisma creates, so both tools read the same history.
db.exec(`CREATE TABLE IF NOT EXISTS _prisma_migrations (
  id TEXT PRIMARY KEY NOT NULL,
  checksum TEXT NOT NULL,
  finished_at DATETIME,
  migration_name TEXT NOT NULL,
  logs TEXT,
  rolled_back_at DATETIME,
  started_at DATETIME NOT NULL DEFAULT current_timestamp,
  applied_steps_count INTEGER UNSIGNED NOT NULL DEFAULT 0
)`);

const migrationsDir = path.resolve(root, "prisma/migrations");
if (!fs.existsSync(migrationsDir)) {
  console.log("No migrations directory found; nothing to apply.");
  process.exit(0);
}

const applied = new Set(
  db
    .prepare("SELECT migration_name FROM _prisma_migrations WHERE finished_at IS NOT NULL")
    .all()
    .map((row) => row.migration_name),
);

const pending = fs
  .readdirSync(migrationsDir)
  .filter((name) => fs.existsSync(path.join(migrationsDir, name, "migration.sql")))
  .sort()
  .filter((name) => !applied.has(name));

if (pending.length === 0) {
  console.log("No pending migrations.");
  process.exit(0);
}

const record = db.prepare(
  "INSERT INTO _prisma_migrations (id, checksum, finished_at, migration_name, applied_steps_count) VALUES (?, ?, current_timestamp, ?, 1)",
);

for (const name of pending) {
  const sql = fs.readFileSync(path.join(migrationsDir, name, "migration.sql"), "utf8");
  const checksum = crypto.createHash("sha256").update(sql).digest("hex");

  db.exec("BEGIN");
  try {
    db.exec(sql);
    record.run(crypto.randomUUID(), checksum, name);
    db.exec("COMMIT");
    console.log(`Applied migration: ${name}`);
  } catch (error) {
    db.exec("ROLLBACK");
    console.error(`Failed to apply migration ${name}:`, error.message);
    process.exit(1);
  }
}

console.log(`Applied ${pending.length} migration(s).`);
