// Minimal forward-only SQL migration runner.
//
//   node db/migrate.mjs
//
// Applies every .sql file in db/migrations (in filename order) that has not
// already been recorded in the schema_migrations table. Each file runs inside
// a transaction. Reads DATABASE_URL from the environment.

import { readdir, readFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const __dirname = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(__dirname, "migrations");

const connectionString = process.env.DATABASE_URL;
if (!connectionString) {
  console.error("ERROR: DATABASE_URL is not set.");
  process.exit(1);
}

const ssl =
  process.env.DATABASE_SSL === "disable"
    ? false
    : { rejectUnauthorized: false };

// Strip sslmode from the URL so it doesn't override the ssl option above.
// Recent pg versions treat sslmode=require as full cert verification, which
// fails against the RDS CA.
function stripSslmode(connStr) {
  try {
    const url = new URL(connStr);
    url.searchParams.delete("sslmode");
    return url.toString();
  } catch {
    return connStr;
  }
}

const client = new pg.Client({
  connectionString: stripSslmode(connectionString),
  ssl,
});

async function main() {
  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      filename   TEXT PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  const applied = new Set(
    (await client.query("SELECT filename FROM schema_migrations")).rows.map(
      (r) => r.filename
    )
  );

  const files = (await readdir(migrationsDir))
    .filter((f) => f.endsWith(".sql"))
    .sort();

  let count = 0;
  for (const file of files) {
    if (applied.has(file)) {
      console.log(`= skip   ${file}`);
      continue;
    }
    const sql = await readFile(join(migrationsDir, file), "utf8");
    console.log(`+ apply  ${file}`);
    try {
      await client.query("BEGIN");
      await client.query(sql);
      await client.query(
        "INSERT INTO schema_migrations (filename) VALUES ($1)",
        [file]
      );
      await client.query("COMMIT");
      count++;
    } catch (err) {
      await client.query("ROLLBACK");
      console.error(`\nFailed on ${file}:\n`, err.message);
      process.exit(1);
    }
  }

  console.log(`\nDone. ${count} migration(s) applied.`);
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => client.end());
