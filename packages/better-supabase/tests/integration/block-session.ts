import { Pool, type PoolClient } from "pg";

import type { SqlClient } from "../../src/postgres/executor.ts";
import type { ModuleLayout } from "../../src/sql/registry.ts";

import { renderModules } from "../../src/sql/registry.ts";

export const dbUrl: string =
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

export interface TestUser {
  readonly id: string;
  readonly email: string;
}

/**
 * One connection in one transaction that is rolled back at the end, so a
 * test leaves nothing behind. `as` switches the JWT claims the functions see,
 * and `asRole` also switches the database role so RLS applies.
 */
export class BlockSession {
  readonly client: PoolClient;

  constructor(client: PoolClient) {
    this.client = client;
  }

  static async open(pool: Pool): Promise<BlockSession> {
    const client = await pool.connect();
    await client.query("begin");
    return new BlockSession(client);
  }

  async close(): Promise<void> {
    try {
      await this.client.query("rollback");
    } finally {
      this.client.release();
    }
  }

  async install(
    names: readonly string[],
    layout: ModuleLayout = {},
  ): Promise<void> {
    for (const file of renderModules(names, layout))
      if (file.kind !== "test") await this.client.query(file.contents);
  }

  async user(name: string, emailDomain = "example.test"): Promise<TestUser> {
    const id = crypto.randomUUID();
    const email = `${name}-${id.slice(0, 8)}@${emailDomain}`;
    await this.client.query(
      `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
       values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
      [id, email],
    );
    return { id, email };
  }

  /** An organization with `owner` as its owner and the other members' roles. */
  async organization(
    owner: TestUser,
    members: Readonly<Record<string, TestUser>> = {},
  ): Promise<string> {
    await this.as(owner);
    const slug = `org-${crypto.randomUUID().slice(0, 8)}`;
    const id = await this.value<string>(
      "better_supabase.create_organization($1)",
      [{ name: slug, slug }],
    );
    await this.service();
    for (const [role, user] of Object.entries(members)) {
      await this.client.query(
        "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, $3)",
        [id, user.id, role.replace(/\d+$/, "")],
      );
    }
    return id;
  }

  async as(user: TestUser | "anon", extra: object = {}): Promise<void> {
    await this.client.query("reset role");
    const claims =
      user === "anon"
        ? { role: "anon" }
        : {
            sub: user.id,
            role: "authenticated",
            email: user.email,
            ...extra,
          };
    await this.client.query(
      "select set_config('request.jwt.claims', $1, true)",
      [JSON.stringify(claims)],
    );
  }

  /** Runs as `authenticated` (or `anon`) so policies apply. */
  async asRole(user: TestUser | "anon", extra: object = {}): Promise<void> {
    await this.as(user, extra);
    await this.client.query(
      `set local role ${user === "anon" ? "anon" : "authenticated"}`,
    );
  }

  async service(): Promise<void> {
    await this.client.query("reset role");
    await this.client.query(
      "select set_config('request.jwt.claims', $1, true)",
      [JSON.stringify({ role: "service_role" })],
    );
  }

  async value<T>(sql: string, params: unknown[] = []): Promise<T> {
    const { rows } = await this.client.query<{ value: T }>(
      `select ${sql} as value`,
      params,
    );
    return rows[0]!.value;
  }

  async rows<T>(sql: string, params: unknown[] = []): Promise<T[]> {
    const { rows } = await this.client.query(sql, params);
    // SAFETY: the test names the row shape of its own query.
    return rows as T[];
  }

  /** The hint (or message) of the error `sql` raises, rolled back to a savepoint. */
  async hint(sql: string, params: unknown[] = []): Promise<string> {
    await this.client.query("savepoint attempt");
    try {
      await this.client.query(
        sql.startsWith("select") ||
          sql.startsWith("insert") ||
          sql.startsWith("update") ||
          sql.startsWith("delete")
          ? sql
          : `select ${sql}`,
        params,
      );
    } catch (error) {
      await this.client.query("rollback to savepoint attempt");
      const { hint, message } = error as { hint?: string; message: string };
      return hint ?? message;
    }
    await this.client.query("release savepoint attempt");
    return "no error";
  }

  /**
   * A `SqlClient` over this session's connection, for the TypeScript side.
   * Each statement runs in a savepoint, so an expected error leaves the
   * transaction usable.
   */
  get sql(): SqlClient {
    const client = this.client;
    return {
      async queryRaw<T>(text: string, params?: unknown[]): Promise<T[]> {
        await client.query("savepoint block_call");
        try {
          const { rows } = await client.query(text, params);
          await client.query("release savepoint block_call");
          // SAFETY: the caller names the row shape of its own query.
          return rows as T[];
        } catch (error) {
          await client.query("rollback to savepoint block_call");
          throw error;
        }
      },
    };
  }
}
