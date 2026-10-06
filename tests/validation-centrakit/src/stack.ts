import type { SqlClient } from "better-supabase/postgres";

import { renderBlocks } from "better-supabase/sql";
import { readFile } from "node:fs/promises";
import { DatabaseError, Pool, type PoolClient, type QueryResultRow } from "pg";

import config from "../better-supabase.config.ts";

export const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";

export async function reachable(): Promise<boolean> {
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

const ORGANIZATION_PERMISSIONS = [
  "organization.settings.manage",
  "organization.delete",
  "organization.members.invite",
  "organization.members.remove",
  "organization.members.manage",
  "organization.ownership.transfer",
  "organization.webhooks.manage",
  "organization.webhooks.view",
  "notifications.send",
  "notifications.read",
  "audit.view",
];

const GRANTS = {
  owner: ORGANIZATION_PERMISSIONS,
  admin: ORGANIZATION_PERMISSIONS.filter(
    (key) =>
      key !== "organization.delete" &&
      key !== "organization.ownership.transfer",
  ),
  member: ["notifications.send", "notifications.read"],
  systemSupport: ["system.users.manage"],
} satisfies Record<keyof typeof ROLES, readonly string[]>;

const SEED = [
  `insert into centrakit.roles (id, scope, key, name, system) values
    ('${ROLES.owner}', 'organization', 'owner', 'Owner', true),
    ('${ROLES.admin}', 'organization', 'admin', 'Admin', true),
    ('${ROLES.member}', 'organization', 'member', 'Member', true),
    ('${ROLES.systemSupport}', 'system', 'system-support', 'Support', true)`,
  `insert into centrakit.permissions (scope, key, name)
   select (case when key like 'system.%' then 'system' else 'organization' end)::centrakit.scope_type, key, key
   from unnest($1::text[]) key`,
  `insert into centrakit.role_permissions (role_id, permission_id)
   select g.role_id::uuid, p.id
   from jsonb_each($1::jsonb) as r(name, keys)
   cross join lateral jsonb_array_elements_text(r.keys) as k(key)
   join jsonb_each_text($2::jsonb) as g(name, role_id) on g.name = r.name
   join centrakit.permissions p on p.key = k.key`,
];

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
      if (!(error instanceof DatabaseError)) throw error;
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

/** Runs `body` against CentraKit's tables with the block installed, then rolls back. */
export async function withCentraKit(
  pool: Pool,
  body: (session: Session) => Promise<void>,
): Promise<void> {
  const client = await pool.connect();
  const session = new Session(client);
  try {
    await client.query("begin");
    for (const who of ["owner", "admin", "member", "support"] as const) {
      await client.query(
        `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at, raw_user_meta_data)
         values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now(), $3)`,
        [USERS[who], email(who), { first_name: who, last_name: "Tester" }],
      );
    }
    await client.query(
      await readFile(
        new URL("../supabase/schema.sql", import.meta.url),
        "utf8",
      ),
    );
    await client.query(SEED[0]!);
    await client.query(SEED[1]!, [
      [...ORGANIZATION_PERMISSIONS, "system.users.manage"],
    ]);
    await client.query(
      SEED[2]!,
      [GRANTS, ROLES].map((v) => JSON.stringify(v)),
    );
    await client.query(
      "insert into centrakit.user_roles (user_id, role_id) values ($1, $2)",
      [USERS.support, ROLES.systemSupport],
    );
    for (const file of renderBlocks(
      config.sql?.modules ?? [],
      config.blocks ? { blocks: config.blocks } : {},
    ))
      await client.query(file.contents);
    await client.query(
      await readFile(
        new URL("../supabase/policies.sql", import.meta.url),
        "utf8",
      ),
    );
    await body(session);
  } finally {
    await client.query("rollback");
    client.release();
  }
}
