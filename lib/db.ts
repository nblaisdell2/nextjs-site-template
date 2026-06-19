import fs from "node:fs";
import { Pool, type QueryResultRow } from "pg";

/**
 * A single shared connection pool for the whole app, created lazily on first
 * use. Lazy creation matters: Next.js imports route modules at build time to
 * collect metadata, and we must not require DATABASE_URL just to import this
 * file — only when a query actually runs.
 *
 * In development, Next.js hot-reloads modules, which would otherwise create a
 * new Pool on every reload and exhaust connections, so we stash it on the
 * Node global to survive reloads.
 *
 * Connection config comes entirely from DATABASE_URL, which in production is
 * injected by App Runner from Secrets Manager (see infra/secrets.tf).
 */

declare global {
  // eslint-disable-next-line no-var
  var _pgPool: Pool | undefined;
}

/**
 * Remove the `sslmode` query param from a connection string. Recent versions
 * of pg's connection-string parser treat sslmode=require as full cert
 * verification, which fails against the RDS CA. We control TLS via the `ssl`
 * option below instead, so we strip sslmode to avoid the conflict.
 */
function stripSslmode(connectionString: string): string {
  try {
    const url = new URL(connectionString);
    url.searchParams.delete("sslmode");
    return url.toString();
  } catch {
    return connectionString;
  }
}

// Path to the RDS CA bundle baked into the image (see Dockerfile). Overridable.
const CA_PATH =
  process.env.DATABASE_CA_PATH ?? "/app/certs/rds-global-bundle.pem";

/**
 * Decide TLS behaviour:
 *  - DATABASE_SSL=disable  -> no TLS (local non-TLS Postgres)
 *  - RDS CA bundle present -> full verification (verify-full): encrypted AND
 *    the server cert is checked against Amazon's CA. This is the production path.
 *  - otherwise             -> encrypted but unverified (e.g. local dev without
 *    the bundle). Never silently downgrades in the container, which ships the CA.
 */
function buildSsl(): false | { ca: string; rejectUnauthorized: true } | { rejectUnauthorized: false } {
  if (process.env.DATABASE_SSL === "disable") return false;
  if (fs.existsSync(CA_PATH)) {
    return { ca: fs.readFileSync(CA_PATH, "utf8"), rejectUnauthorized: true };
  }
  return { rejectUnauthorized: false };
}

function createPool(): Pool {
  const raw = process.env.DATABASE_URL;
  if (!raw) {
    throw new Error(
      "DATABASE_URL is not set. Locally, copy .env.example to .env. " +
        "In AWS it is injected by ECS from Secrets Manager."
    );
  }

  return new Pool({
    connectionString: stripSslmode(raw),
    ssl: buildSsl(),
    max: Number(process.env.DATABASE_POOL_MAX ?? 5),
    idleTimeoutMillis: 30_000,
    connectionTimeoutMillis: 10_000,
  });
}

/** Returns the shared pool, creating it on first call. */
export function getPool(): Pool {
  if (!global._pgPool) {
    global._pgPool = createPool();
  }
  return global._pgPool;
}

/** Typed query helper. */
export async function query<T extends QueryResultRow = QueryResultRow>(
  text: string,
  params?: unknown[]
): Promise<T[]> {
  const res = await getPool().query<T>(text, params as never[]);
  return res.rows;
}
