import type { PoolClient } from "pg";

import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

/**
 * Claims across real connections. The harness in
 * `tasks-coordination.integration.test.ts` runs one rolled-back transaction, so
 * it can't show two workers racing. This file commits its own organization and
 * work items (the stack's `work_items` noun carries the same SQL as the tasks
 * block), runs each worker in a transaction of its own as the service role, and
 * deletes everything it made. Workers are told apart by profile name, because a
 * holder that claims again keeps its token (ADR 1112) and the service role has
 * no user id. Nothing here reads memberships, so suites that commit other
 * module renders into the shared stack can't change the outcome.
 */
describe.skipIf(!live)("concurrent task claims", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 12 });
  const orgs: string[] = [];

  afterAll(async () => {
    try {
      for (const org of orgs) {
        await pool.query(
          "delete from better_supabase.work_item_claims where tenant_id = $1",
          [org],
        );

        await pool.query(
          "delete from better_supabase.work_items where tenant_id = $1",
          [org],
        );

        await pool.query("delete from public.organizations where id = $1", [
          org,
        ]);
      }
    } finally {
      await pool.end();
    }
  });

  const asService = (client: PoolClient): Promise<unknown> =>
    client.query("select set_config('request.jwt.claims', $1, true)", [
      JSON.stringify({ role: "service_role" }),
    ]);

  /** An organization with `count` ready work items, committed. */
  const setup = async (
    count: number,
  ): Promise<{ org: string; tasks: string[] }> => {
    const org = crypto.randomUUID();

    await pool.query(
      "insert into public.organizations (id, name, slug) values ($1, 'Claims race', $2)",
      [org, `claims-${org.slice(0, 8)}`],
    );

    orgs.push(org);
    const client = await pool.connect();

    try {
      await client.query("begin");
      await asService(client);
      const team = crypto.randomUUID();
      const tasks: string[] = [];

      for (let index = 0; index < count; index += 1) {
        const {
          rows: [row],
        } = await client.query<{ task: { id: string } }>(
          "select better_supabase.create_work_item($1, $2, null) as task",
          [org, { title: `Task ${String(index)}`, teamId: team }],
        );

        tasks.push(row!.task.id);
      }

      await client.query("commit");

      return { org, tasks };
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  };

  const worker = (index: number) =>
    JSON.stringify({ kind: "agent", name: `worker-${String(index)}` });

  const claimNext = async (
    org: string,
    index: number,
  ): Promise<string | undefined> => {
    const client = await pool.connect();

    try {
      await client.query("begin");
      await asService(client);

      try {
        const {
          rows: [row],
        } = await client.query<{ claimed: { task: { id: string } } }>(
          "select better_supabase.claim_next_work_item($1, null, null, $2::jsonb) as claimed",
          [org, worker(index)],
        );

        await client.query("commit");

        return row?.claimed.task.id;
      } catch (error) {
        await client.query("rollback");

        if ((error as { hint?: string }).hint === "TASK_NOTHING_READY") {
          return undefined;
        }

        throw error;
      }
    } finally {
      client.release();
    }
  };

  it("hands each ready task to exactly one of many racing workers", async () => {
    const { org, tasks } = await setup(5);

    const results = await Promise.all(
      Array.from({ length: 8 }, (_, index) => claimNext(org, index)),
    );

    const won = results.filter((id): id is string => id !== undefined);

    expect(won).toHaveLength(5);
    expect(new Set(won).size).toBe(5);
    expect(new Set(won)).toEqual(new Set(tasks));

    const { rows } = await pool.query(
      "select 1 from better_supabase.work_item_claims where tenant_id = $1",
      [org],
    );

    expect(rows).toHaveLength(5);
  });

  it("skips a task another open transaction is claiming instead of waiting", async () => {
    const { org, tasks } = await setup(1);
    const holder = await pool.connect();

    try {
      await holder.query("begin");
      await asService(holder);

      const {
        rows: [row],
      } = await holder.query<{ claimed: { task: { id: string } } }>(
        "select better_supabase.claim_next_work_item($1, null, null, $2::jsonb) as claimed",
        [org, worker(0)],
      );

      expect(row?.claimed.task.id).toBe(tasks[0]);

      // The first claim is not committed and holds the row lock. The second
      // worker must return at once with nothing, not block on the lock.
      const outcome = await Promise.race([
        claimNext(org, 1).then((id) => ({ id })),
        new Promise<"blocked">((resolve) => {
          setTimeout(() => {
            resolve("blocked");
          }, 5000);
        }),
      ]);

      expect(outcome).toEqual({ id: undefined });
      await holder.query("commit");
    } catch (error) {
      await holder.query("rollback");
      throw error;
    } finally {
      holder.release();
    }
  });

  it("lets exactly one of two concurrent claims on the same task win", async () => {
    const { org, tasks } = await setup(1);

    const attempt = async (index: number): Promise<string> => {
      const client = await pool.connect();

      try {
        await client.query("begin");
        await asService(client);

        try {
          await client.query(
            "select better_supabase.claim_work_item($1, null, $2::jsonb)",
            [tasks[0], worker(index)],
          );

          await client.query("commit");

          return "won";
        } catch (error) {
          await client.query("rollback");

          return (error as { hint?: string }).hint ?? "error";
        }
      } finally {
        client.release();
      }
    };

    const results = await Promise.all([attempt(0), attempt(1)]);

    expect(results.toSorted()).toEqual(["TASK_CLAIMED", "won"]);

    const { rows } = await pool.query(
      "select 1 from better_supabase.work_item_claims where tenant_id = $1",
      [org],
    );

    expect(rows).toHaveLength(1);
  });
});
