import type { BlocksConfig, SubjectsConfig } from "better-supabase/config";
import type { SqlClient } from "better-supabase/postgres";
import type { BlockSqlAccessProvider } from "better-supabase/sql";
import type { PoolClient, QueryResultRow } from "pg";

import { resolveConfig } from "better-supabase/config";
import { moduleLayout, renderBlocks } from "better-supabase/sql";
import { readdir, readFile } from "node:fs/promises";
import { DatabaseError, Pool } from "pg";

import config from "../better-supabase.config.ts";
import { centrakitProvider } from "./provider.ts";

const resolved = resolveConfig(config, process.cwd());

type Writable<T> = { -readonly [K in keyof T]: T[K] };

const provider = centrakitProvider();

// What `add` derives from config.authorization for the access module; the
// extra modules a test installs render against the same provider.
const accessProvider: Writable<BlockSqlAccessProvider> = {
  name: provider.name,
  scope: provider.tenantScope,
  scopes: provider.scopes.map((scope) => scope.name),
  idType: "uuid",
  functions: provider.functions,
};

if (provider.suspension) {
  accessProvider.suspension = provider.suspension;
}

if (provider.roleSources) {
  accessProvider.roleSources = provider.roleSources;
}

if (provider.operations) {
  accessProvider.operations = provider.operations;
}

// `pnpm env:local` writes it (the CLI picks the ports per checkout); without
// it the suites skip, like they do when the stack is down.
export const dbUrl: string | undefined = process.env["SUPABASE_DB_URL"];

export async function reachable(): Promise<boolean> {
  if (dbUrl === undefined) {
    return false;
  }

  const pool = new Pool({
    connectionString: dbUrl,
    max: 1,
    connectionTimeoutMillis: 1000,
  });

  try {
    await pool.query("select 1");

    return true;
  } catch {
    return false;
  } finally {
    await pool.end();
  }
}

export const USERS = {
  owner: crypto.randomUUID(),
  admin: crypto.randomUUID(),
  member: crypto.randomUUID(),
  support: crypto.randomUUID(),
} as const;

export type Who = keyof typeof USERS;

export const email = (who: Who): string =>
  `${who}-${USERS[who]}@centrakit.test`;

export const ROLES = {
  owner: "00000000-0000-4000-8000-00000000a001",
  admin: "00000000-0000-4000-8000-00000000a002",
  member: "00000000-0000-4000-8000-00000000a003",
  systemSupport: "00000000-0000-4000-8000-00000000a004",
} as const;

// Which permissions each role grants is the provider's, compiled into
// centrakit.authz_role_grants(); the seed only creates the roles.
const SEED = `insert into centrakit.roles (id, scope, key, name, system) values
  ('${ROLES.owner}', 'organization', 'owner', 'Owner', true),
  ('${ROLES.admin}', 'organization', 'admin', 'Admin', true),
  ('${ROLES.member}', 'organization', 'member', 'Member', true),
  ('${ROLES.systemSupport}', 'system', 'system-support', 'Support', true)`;

const SUPABASE = new URL("../supabase/", import.meta.url);

/** The files `upgrade` wrote in `dir`, in the order a reset applies them. */
async function generated(dir: string): Promise<string[]> {
  const url = new URL(`${dir}/`, SUPABASE);

  const names = (await readdir(url))
    .filter((name) => name.startsWith("900_better_supabase_"))
    // Module numbers run past 99, so 112 has to load after 19.
    .toSorted((a, b) => a.localeCompare(b, "en", { numeric: true }));

  return Promise.all(
    names.map((name) => readFile(new URL(name, url), "utf-8")),
  );
}

/** A connection inside one transaction, acting as a user per call. */
export class Session {
  readonly client: PoolClient;

  constructor(client: PoolClient) {
    this.client = client;
  }

  async as(who: Who | "service"): Promise<void> {
    const claims =
      who === "service"
        ? { role: "service_role" }
        : { sub: USERS[who], role: "authenticated", email: email(who) };

    await this.client.query(
      "select set_config('request.jwt.claims', $1, true)",
      [JSON.stringify(claims)],
    );
  }

  async value<T>(sql: string, params: readonly unknown[] = []): Promise<T> {
    const { rows } = await this.client.query<{ value: T }>(
      `select ${sql} as value`,
      [...params],
    );

    return rows[0]!.value;
  }

  async rows<T extends QueryResultRow>(
    sql: string,
    params: readonly unknown[] = [],
  ): Promise<T[]> {
    return (await this.client.query<T>(sql, [...params])).rows;
  }

  /** The hint of the error `sql` raises, rolled back to a savepoint. */
  async hint(sql: string, params: readonly unknown[] = []): Promise<string> {
    await this.client.query("savepoint attempt");

    try {
      await this.client.query(`select ${sql}`, [...params]);
    } catch (error) {
      await this.client.query("rollback to savepoint attempt");

      if (!(error instanceof DatabaseError)) {
        throw error;
      }

      return error.hint ?? error.message;
    }

    await this.client.query("release savepoint attempt");

    return "no error";
  }

  /** `SqlClient` for the block transports; each call runs in a savepoint. */
  get sql(): SqlClient {
    const client = this.client;

    return {
      async queryRaw<T>(text: string, params: readonly unknown[] = []) {
        await client.query("savepoint call");

        try {
          const { rows } = await client.query(text, [...params]);
          await client.query("release savepoint call");

          // SAFETY: callers name the row shape of the query they send.
          return rows as T[];
        } catch (error) {
          await client.query("rollback to savepoint call");
          throw error;
        }
      },
    };
  }
}

/** More modules and subjects to install next to CentraKit's own config. */
export interface Extra {
  readonly modules: readonly string[];
  readonly config?: BlocksConfig;
  readonly subjects?: SubjectsConfig;
}

/**
 * Runs `body` against CentraKit's tables with the block installed, then rolls
 * back.
 */
export async function withCentraKit(
  pool: Pool,
  body: (session: Session) => Promise<void>,
  extra?: Extra,
): Promise<void> {
  const client = await pool.connect();
  const session = new Session(client);

  try {
    await client.query("begin");
    // validation-recipes installs blocks on the same database; concurrent installs deadlock.
    await client.query(
      "select pg_advisory_xact_lock(hashtext('better-supabase:validation-install'))",
    );
    // The install creates triggers on auth.users, which needs its strongest
    // lock. Taking it before inserting users makes a concurrent sign-in wait
    // for this transaction instead of deadlocking with it.
    await client.query("lock table auth.users in access exclusive mode");
    // The stack holds the root fixture's blocks. Their triggers would outlive
    // this install on the tables both share and emit with the fixture's
    // config, so CentraKit starts from an empty schema.
    await client.query("drop schema if exists better_supabase cascade");

    for (const who of ["owner", "admin", "member", "support"] as const) {
      await client.query(
        `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at, raw_user_meta_data)
         values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now(), $3)`,
        [USERS[who], email(who), { first_name: who, last_name: "Tester" }],
      );
    }

    // The extensions come first; the data migration repeats the data files,
    // which load after the module files below.
    const migrations = new URL("migrations/", SUPABASE);

    const extensions = (await readdir(migrations))
      .filter((name) => name.endsWith("_extensions.sql"))
      .toSorted();

    for (const name of extensions) {
      await client.query(await readFile(new URL(name, migrations), "utf-8"));
    }

    await client.query(
      await readFile(new URL("schemas/000_centrakit.sql", SUPABASE), "utf-8"),
    );
    await client.query(SEED);
    await client.query(
      "insert into centrakit.user_roles (user_id, role_id) values ($1, $2)",
      [USERS.support, ROLES.systemSupport],
    );

    for (const file of [
      ...(await generated("schemas")),
      ...(await generated("better-supabase-data")),
    ]) {
      await client.query(file);
    }

    // An app runs this once when it adopts the profiles block; a user without
    // a profile counts as disabled.
    await client.query("select better_supabase.backfill_profiles()");

    if (extra !== undefined) {
      const base = moduleLayout(
        resolved,
        undefined,
        [],
        undefined,
        accessProvider,
        provider.permissions?.map((permission) => permission.key),
      );

      const layout: Writable<typeof base> = {
        ...base,
        modules: { ...base.modules, ...extra.config },
      };

      if (extra.subjects) {
        layout.subjects = extra.subjects;
      }

      for (const file of renderBlocks(extra.modules, layout)) {
        await client.query(file.contents);
      }
    }

    await client.query(
      await readFile(
        new URL("schemas/990_centrakit_policies.sql", SUPABASE),
        "utf-8",
      ),
    );
    await body(session);
  } finally {
    await client.query("rollback");
    client.release();
  }
}
