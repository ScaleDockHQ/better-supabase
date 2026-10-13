import type { SqlClient } from "better-supabase/postgres";

import { resolveConfig } from "better-supabase/config";
import { moduleLayout, renderModules } from "better-supabase/sql";
import { DatabaseError, Pool, type PoolClient, type QueryResultRow } from "pg";

import type { Recipe } from "./recipes.ts";

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

/** The module files `sql add` writes for the recipe, schema files first. */
export function moduleFiles(recipe: Recipe) {
  const config = resolveConfig(recipe.config, process.cwd());
  const files = renderModules(config.sql.moduleNames, moduleLayout(config));
  return [
    ...files.filter((file) => file.kind === "schema"),
    ...files.filter((file) => file.kind === "data"),
  ];
}

/** The recipe's tables and every module file, as one migration. */
export function migration(recipe: Recipe): string {
  return [
    recipe.tables,
    ...moduleFiles(recipe).map((file) => file.contents),
  ].join("\n\n");
}

export interface User {
  readonly id: string;
  readonly email: string;
}

/** A connection inside one transaction, acting as a user per call. */
export class Session {
  readonly client: PoolClient;
  private queue: Promise<unknown> = Promise.resolve();

  constructor(client: PoolClient) {
    this.client = client;
  }

  async user(name: string): Promise<User> {
    const id = crypto.randomUUID();
    const email = `${name}-${id.slice(0, 8)}@recipes.test`;
    await this.client.query(
      `insert into auth.users (id, email, aud, role, instance_id, email_confirmed_at)
       values ($1, $2, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', now())`,
      [id, email],
    );
    return { id, email };
  }

  /** An organization owned by `owner`, with `members` as members. */
  async organization(
    owner: User,
    members: readonly User[] = [],
  ): Promise<string> {
    await this.as(owner);
    const slug = `org-${crypto.randomUUID().slice(0, 8)}`;
    const id = await this.value<string>(
      "better_supabase.create_organization($1)",
      [{ name: slug, slug }],
    );
    await this.service();
    for (const member of members) {
      await this.client.query(
        "insert into better_supabase.memberships (organization_id, user_id, role) values ($1, $2, 'member')",
        [id, member.id],
      );
    }
    return id;
  }

  /** Acts as `user` under the `authenticated` role, so policies apply. */
  async as(user: User): Promise<void> {
    await this.client.query("reset role");
    await this.client.query(
      "select set_config('request.jwt.claims', $1, true)",
      [
        JSON.stringify({
          sub: user.id,
          role: "authenticated",
          email: user.email,
        }),
      ],
    );
    await this.client.query("set local role authenticated");
  }

  async service(): Promise<void> {
    await this.client.query("reset role");
    await this.client.query(
      "select set_config('request.jwt.claims', $1, true)",
      [JSON.stringify({ role: "service_role" })],
    );
  }

  /** Watches a subject: the user gets every notification sent about it. */
  async watch(
    user: User,
    organizationId: string,
    subjectType: string,
    subjectId: string,
  ): Promise<void> {
    await this.client.query("reset role");
    await this.client.query(
      `insert into better_supabase.notification_subscriptions
         (organization_id, user_id, subject_type, subject_id, level)
       values ($1, $2, $3, $4, 'all')`,
      [organizationId, user.id, subjectType, subjectId],
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

  /** `SqlClient` for the block transports; each call runs in a savepoint, one at a time. */
  get sql(): SqlClient {
    const client = this.client;
    const run = async <T>(
      text: string,
      params: readonly unknown[],
    ): Promise<T[]> => {
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
    };
    return {
      queryRaw: <T>(text: string, params: readonly unknown[] = []) => {
        const result = this.queue.then(() => run<T>(text, params));
        this.queue = result.catch(() => undefined);
        return result;
      },
    };
  }
}

/** Applies the recipe's migration in one transaction, runs `body`, then rolls back. */
export async function withRecipe(
  pool: Pool,
  recipe: Recipe,
  body: (session: Session) => Promise<void>,
): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query("begin");
    // validation-centrakit installs its schema on the same database; concurrent DDL deadlocks.
    await client.query(
      "select pg_advisory_xact_lock(hashtext('better-supabase:validation-ddl'))",
    );
    await client.query(migration(recipe));
    await body(new Session(client));
  } finally {
    await client.query("rollback");
    client.release();
  }
}
