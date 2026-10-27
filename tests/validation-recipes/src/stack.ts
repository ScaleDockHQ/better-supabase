import type { SqlClient } from "better-supabase/postgres";
import type { PoolClient, QueryResultRow } from "pg";

import { resolveConfig } from "better-supabase/config";
import { moduleLayout, renderBlocks } from "better-supabase/sql";
import { DatabaseError, Pool } from "pg";

import type { Recipe } from "./recipes.ts";

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

/** The module files `add` writes for the recipe, schema files first. */
export function moduleFiles(recipe: Recipe) {
  const config = resolveConfig(recipe.config, process.cwd());
  const files = renderBlocks(config.blockNames, moduleLayout(config));

  return [
    ...files.filter((file) => file.kind === "schema"),
    ...files.filter((file) => file.kind === "data"),
  ];
}

/** The recipe's tables, every module file and its after SQL, as one migration. */
export function migration(recipe: Recipe): string {
  return [
    recipe.tables,
    ...moduleFiles(recipe).map((file) => file.contents),
    recipe.after ?? "",
  ].join("\n\n");
}

export interface User {
  readonly id: string;
  /** Empty for an anonymous sign-in. */
  readonly email: string;
  readonly anonymous?: boolean;
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

  /** A user from an anonymous sign-in: no email, `is_anonymous` in the claims. */
  async anonymousUser(): Promise<User> {
    const id = crypto.randomUUID();
    await this.client.query(
      `insert into auth.users (id, aud, role, instance_id, is_anonymous)
       values ($1, 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000', true)`,
      [id],
    );

    return { id, email: "", anonymous: true };
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
        JSON.stringify(
          user.anonymous
            ? { sub: user.id, role: "authenticated", is_anonymous: true }
            : { sub: user.id, role: "authenticated", email: user.email },
        ),
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

      if (!(error instanceof DatabaseError)) {
        throw error;
      }

      return error.hint ?? error.message;
    }

    await this.client.query("release savepoint attempt");

    return "no error";
  }

  /**
   * `SqlClient` for the block transports; each call runs in a savepoint, one at
   * a time.
   */
  get sql(): SqlClient {
    return this.sqlClient(false);
  }

  /**
   * `SqlClient` for a block's `service` transport: each call runs as the
   * service role, then the caller's role and claims come back.
   */
  get serviceSql(): SqlClient {
    return this.sqlClient(true);
  }

  private sqlClient(asService: boolean): SqlClient {
    const client = this.client;

    const run = async <T>(
      text: string,
      params: readonly unknown[],
    ): Promise<T[]> => {
      await client.query("savepoint call");

      try {
        const caller = asService
          ? (
              await client.query<{ role: string; claims: string }>(
                "select current_user as role, coalesce(current_setting('request.jwt.claims', true), '') as claims",
              )
            ).rows[0]
          : undefined;

        if (caller) {
          await this.service();
        }

        const { rows } = await client.query(text, [...params]);

        if (caller) {
          await client.query(
            "select set_config('request.jwt.claims', $1, true)",
            [caller.claims],
          );

          if (caller.role === "authenticated") {
            await client.query("set local role authenticated");
          }
        }

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

/**
 * Applies the recipe's migration in one transaction, runs `body`, then rolls
 * back.
 */
export async function withRecipe(
  pool: Pool,
  recipe: Recipe,
  body: (session: Session) => Promise<void>,
): Promise<void> {
  const client = await pool.connect();

  try {
    await install(client, migration(recipe));
    await body(new Session(client));
  } finally {
    await client.query("rollback");
    client.release();
  }
}

/**
 * Other suites install modules on the same stack at the same time, and Postgres
 * resolves a deadlock between two installs by aborting one of them. The aborted
 * install starts over.
 */
async function install(client: PoolClient, sql: string): Promise<void> {
  for (let attempt = 1; ; attempt += 1) {
    await client.query("begin");

    try {
      // validation-centrakit installs blocks on the same database; concurrent installs deadlock.
      await client.query(
        "select pg_advisory_xact_lock(hashtext('better-supabase:validation-install'))",
      );
      // The fixture runs the catalog permissions model: its invitations hold role ids
      // and its team members reference public.memberships. A recipe re-adds those
      // constraints for its own model, which the seeded rows fail. The rollback after
      // each recipe brings the rows back.
      await client.query(`do $$ begin
        if to_regclass('better_supabase.team_members') is not null then delete from better_supabase.team_members; end if;
        if to_regclass('better_supabase.invitations') is not null then delete from better_supabase.invitations; end if;
      end $$`);
      await client.query(sql);

      return;
    } catch (error) {
      await client.query("rollback");

      if (!(error instanceof DatabaseError) || error.code !== "40P01") {
        throw error;
      }

      if (attempt === 5) {
        throw error;
      }
    }
  }
}
