import type { PoolClient } from "pg";

import { Pool } from "pg";

import type { SqlClient } from "../../src/postgres/executor.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";

import { renderBlocks } from "../sql/app-columns.ts";
import { stackDbUrl } from "./stack-env.ts";

export const dbUrl: string = stackDbUrl();

/**
 * Fires the deferred constraint triggers (the audit row triggers) queued so
 * far, then defers them again. Postgres refuses DDL on a table that still has
 * trigger events pending. Leaving them immediate would break the tests that
 * assert on commit-time checks, such as the last-owner guard.
 */
export async function flushDeferred(client: {
  query: (sql: string) => Promise<unknown>;
}): Promise<void> {
  await client.query("set constraints all immediate");
  await client.query("set constraints all deferred");
}

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
 * One connection in one transaction that is rolled back at the end, so a test
 * leaves nothing behind. `as` switches the JWT claims the functions see, and
 * `asRole` also switches the database role so RLS applies.
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
    layout: BlockSqlLayout = {},
  ): Promise<void> {
    // The seed's team members belong to the fixture's `public.memberships`,
    // which a render over another memberships table can't reference. The
    // fixture keeps the tasks block on the work_item noun, so its pipeline
    // triggers on work_items would check a render's tasks against work_item
    // pipelines; a render that keeps that noun creates them again.
    await this.client.query(`do $$
      begin
        if to_regclass('better_supabase.team_members') is not null then
          delete from better_supabase.team_members;
        end if;
        if to_regclass('better_supabase.invitations') is not null then
          delete from better_supabase.invitations;
        end if;
        if to_regclass('better_supabase.work_items') is not null then
          drop trigger if exists bsb_pipeline_work_item on better_supabase.work_items;
          drop trigger if exists bsb_pipeline_status_work_item on better_supabase.work_items;
        end if;
      end
    $$`);

    // `create table if not exists` keeps a tasks table an earlier render left
    // with its projects key on another projects table.
    if (names.includes("tasks")) {
      const projects =
        layout.modules?.["tasks"]?.tables?.["projects"] ?? "projects";

      const { rowCount } = await this.client.query(
        `select 1 from pg_constraint
        where conrelid = to_regclass('better_supabase.tasks')
          and conname = 'tasks_project_id_fkey'
          and confrelid is distinct from to_regclass($1)`,
        [projects.includes(".") ? projects : `better_supabase.${projects}`],
      );

      if (rowCount) {
        await this.client.query(
          `drop table if exists better_supabase.task_checklist_items,
            better_supabase.task_assignees, better_supabase.tasks cascade`,
        );
      }
    }

    // The fixture's postmortem actions reference its work_items table, and
    // `create table if not exists` would keep that key for a render on tasks.
    if (names.includes("incidents") && names.includes("tasks")) {
      await this.client.query(`do $$
        begin
          if to_regclass('better_supabase.incident_postmortem_actions') is not null
            and not exists (
              select 1 from pg_constraint
              where conrelid = to_regclass('better_supabase.incident_postmortem_actions')
                and conname = 'incident_postmortem_actions_task_id_fkey'
                and confrelid = to_regclass('better_supabase.tasks')
            ) then
            drop table better_supabase.incident_postmortem_actions cascade;
          end if;
        end
      $$`);
    }

    // The fixture's note actions reference its work_items table, and
    // `create table if not exists` would keep that key for a render on tasks.
    if (names.includes("activities") && names.includes("tasks")) {
      await this.client.query(`do $$
        begin
          if to_regclass('better_supabase.activity_note_actions') is not null
            and not exists (
              select 1 from pg_constraint
              where conrelid = to_regclass('better_supabase.activity_note_actions')
                and conname = 'activity_note_actions_task_id_fkey'
                and confrelid = to_regclass('better_supabase.tasks')
            ) then
            drop table better_supabase.activity_note_actions cascade;
          end if;
        end
      $$`);
    }

    await flushDeferred(this.client);

    // The fixture keys field values per legal entity; a render without legal
    // entities upserts on the four-column key it creates on a new table.
    await this.client.query(`do $$
      begin
        if to_regclass('better_supabase.bsb_field_values_entity_key_idx') is not null then
          drop index better_supabase.bsb_field_values_entity_key_idx;
          create unique index bsb_field_values_entity_key_idx on better_supabase.field_values (tenant_id, subject_type, subject_id, definition_id);
        end if;
      end
    $$`);

    // The stack already holds the declarative schemas, so the render reruns.
    // The fixture keeps the audit read policy, which depends on the functions
    // a render without it would drop.
    const rerun: BlockSqlLayout = {
      ...layout,
      rerunnable: true,
      modules: {
        ...layout.modules,
        audit: {
          ...layout.modules?.["audit"],
          options: { readPolicy: true, ...layout.modules?.["audit"]?.options },
        },
      },
    };

    for (const file of renderBlocks(names, rerun)) {
      if (file.kind !== "test") {
        // The stack keeps tables between installs, so a column an app file adds
        // may exist already.
        await this.client.query(
          file.contents.replaceAll(
            /^(alter table \S+ add column )"/gm,
            '$1if not exists "',
          ),
        );
      }
    }
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
        : { sub: user.id, role: "authenticated", email: user.email, ...extra };

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

  /**
   * Empties tables that supabase/seed.sql fills, for a test that reads all of
   * their rows. The rollback in `close` restores them.
   */
  async clear(tables: readonly string[]): Promise<void> {
    await this.client.query("reset role");

    for (const table of tables) {
      await this.client.query(`delete from ${table}`);
    }
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
    if (/\b(alter|create|drop)\s+(unique\s+)?(table|index)\b/i.test(sql)) {
      await flushDeferred(this.client);
    }

    const { rows } = await this.client.query(sql, params);

    // SAFETY: the test names the row shape of its own query.
    return rows as T[];
  }

  /**
   * The hint (or message) of the error `sql` raises, rolled back to a
   * savepoint.
   */
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

  private queue: Promise<unknown> = Promise.resolve();

  /**
   * A `SqlClient` over this session's connection, for the TypeScript side. Each
   * statement runs in a savepoint, so an expected error leaves the transaction
   * usable.
   */
  get sql(): SqlClient {
    const raw = this.savepointed();

    return {
      queryRaw: <T>(text: string, params?: unknown[]): Promise<T[]> => {
        const run = () => raw.queryRaw<T>(text, params);
        const result = this.queue.then(run, run);
        this.queue = result.catch(() => undefined);

        return result;
      },
    };
  }

  private savepointed(): SqlClient {
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
