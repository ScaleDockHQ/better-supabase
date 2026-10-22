import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { createBulkActions } from "../../src/blocks/bulk-actions/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const layout: BlockSqlLayout = {
  subjects: {
    task: { table: "bulk_it.tasks", idType: "uuid", deletedAt: "deleted_at" },
  },
  modules: {
    trash: { schema: "bulk_it", options: { subjects: { task: {} } } },
    relations: {
      schema: "bulk_it",
      options: {
        subjects: { task: { table: "bulk_it.tasks", idType: "uuid" } },
      },
    },
    "bulk-actions": {
      schema: "bulk_it",
      options: {
        limit: 4,
        actions: { "tasks.archive": "bulk_it.archive_task" },
      },
    },
  },
};

const task = (n: number): string =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

const ids = (...numbers: number[]): string =>
  `array[${numbers.map((n) => `'${task(n)}'`).join(", ")}]::text[]`;

interface Applied {
  readonly total: number;
  readonly succeeded: number;
  readonly failed: number;
  readonly results: readonly {
    id: string;
    ok: boolean;
    error?: { code: string | null };
  }[];
}

describe.skipIf(!live)("bulk actions in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let db: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let stranger: TestUser;
  let org: string;

  const apply = (action: string, rows: string, args = "{}", atomic = false) =>
    `bulk_it.bulk_apply('${org}', 'task', ${rows}, '${action}', '${args}'::jsonb, ${String(atomic)})`;

  beforeAll(async () => {
    db = await BlockSession.open(pool);
    await db.client.query(`create schema bulk_it;
create table bulk_it.tasks (
  id uuid primary key,
  organization_id uuid not null,
  locked boolean not null default false,
  label text,
  archived_by uuid,
  deleted_at timestamptz
);
alter table bulk_it.tasks enable row level security;
create policy tasks_all on bulk_it.tasks for all to authenticated using (true) with check (true);
grant usage on schema bulk_it to authenticated;
grant select, update on bulk_it.tasks to authenticated;
create function bulk_it.archive_task(tenant uuid, subject_type text, subject_id text, args jsonb)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  update bulk_it.tasks set archived_by = auth.uid(), label = args ->> 'label'
  where id = subject_id::uuid and organization_id = tenant and not locked;
  if not found then
    raise exception 'task is locked' using hint = 'TASK_LOCKED';
  end if;
end;
$$;
grant execute on function bulk_it.archive_task(uuid, text, text, jsonb) to authenticated;`);
    await db.install(
      ["organizations", "outbox", "jobs", "relations", "trash", "bulk"],
      layout,
    );
    owner = await db.user("owner");
    member = await db.user("member");
    stranger = await db.user("stranger");
    org = await db.organization(owner, { member });
    await db.client
      .query(`insert into bulk_it.tasks (id, organization_id, locked)
select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, '${org}', n = 3
from generate_series(1, 9) n;`);
  });

  afterAll(async () => {
    await db.close();
    await pool.end();
  });

  it("needs bulk.run, a known action and at most the limit", async () => {
    await db.as(stranger);
    expect(await db.hint(apply("tasks.archive", ids(1)))).toBe(
      "BULK_FORBIDDEN",
    );
    await db.as(member);
    expect(await db.hint(apply("tasks.delete", ids(1)))).toBe(
      "BULK_ACTION_UNKNOWN",
    );
    expect(await db.hint(apply("tasks.archive", ids(1, 2, 4, 5, 6)))).toBe(
      "BULK_TOO_MANY",
    );
  });

  it("reports a result per row and keeps the rows that worked", async () => {
    await db.as(member);

    const result = await db.value<Applied>(
      apply("tasks.archive", ids(1, 2, 3), `{"label": "done"}`),
    );

    expect(result).toMatchObject({ total: 3, succeeded: 2, failed: 1 });
    expect(result.results.map((row) => [row.ok, row.error?.code])).toEqual([
      [true, undefined],
      [true, undefined],
      [false, "TASK_LOCKED"],
    ]);

    const rows = await db.rows<{
      label: string | null;
      archived_by: string | null;
    }>(
      `select label, archived_by from bulk_it.tasks where id in ('${task(1)}', '${task(3)}') order by id`,
    );

    expect(rows).toEqual([
      { label: "done", archived_by: member.id },
      { label: null, archived_by: null },
    ]);
  });

  it("rolls every row back when atomic", async () => {
    await db.as(member);
    expect(
      await db.hint(apply("tasks.archive", ids(4, 3), `{"label": "x"}`, true)),
    ).toBe("TASK_LOCKED");
    expect(
      await db.value<string | null>(
        `(select label from bulk_it.tasks where id = '${task(4)}')`,
      ),
    ).toBeNull();
  });

  it("runs a block's action through its own checks", async () => {
    await db.as(owner);

    const result = await db.value<Applied>(
      apply(
        "relations.link",
        ids(1, 2, 9),
        `{"kind": "parent", "targetType": "task", "targetId": "${task(9)}"}`,
      ),
    );

    expect(result.succeeded).toBe(2);
    expect(result.results[2]?.error?.code).toBe("RELATION_SELF");

    const children = await db.value<unknown[]>(
      `bulk_it.descendants('${org}', 'parent', 'task', '${task(9)}')`,
    );

    expect(children).toHaveLength(2);
  });

  it("trashes rows through the trash block", async () => {
    await db.as(owner);
    const result = await db.value<Applied>(apply("trash.trash", ids(7, 7)));
    expect(result.succeeded).toBe(1);
    expect(result.results[1]?.error?.code).toBe("TRASH_NOT_FOUND");
    expect(
      await db.value<boolean>(`bulk_it.is_trashed('task', '${task(7)}')`),
    ).toBe(true);
    await db.service();

    const items = await db.rows<{ id: string }>(
      `select id from bulk_it.trash_items where subject_id = '${task(7)}'`,
    );

    await db.value(`bulk_it.restore_trash('${items[0]?.id ?? ""}')`);
  });

  it("runs a background run in steps as the user who started it", async () => {
    await db.as(member);

    const started = await db.value<{
      id: string;
      total: number;
      topic: string;
    }>(
      `bulk_it.start_bulk('${org}', 'task', ${ids(5, 6, 3, 7, 8)}, 'tasks.archive', '{"label": "later"}'::jsonb)`,
    );

    expect(started).toMatchObject({ total: 5, topic: `bulk:${started.id}` });
    await db.asRole(member);
    expect(await db.hint(`bulk_it.bulk_step('${started.id}', 2)`)).not.toBe(
      "no error",
    );

    await db.service();

    const first = await db.value<{ done: boolean; position: number }>(
      `bulk_it.bulk_step('${started.id}', 2)`,
    );

    expect(first).toMatchObject({ done: false, position: 2 });
    expect(await db.value<string>("current_user::text")).toBe("postgres");

    const transport = sqlTransport(db.sql);
    const bulk = createBulkActions({ transport, schema: "bulk_it" });
    const finished = await bulk.drain(started.id, { size: 2 }).orThrow();
    expect(finished).toMatchObject({
      status: "completed",
      total: 5,
      succeeded: 4,
      failed: 1,
    });

    const archivedBy = await db.rows<{ archived_by: string }>(
      `select distinct archived_by from bulk_it.tasks where label = 'later'`,
    );

    expect(archivedBy).toEqual([{ archived_by: member.id }]);

    const events = await db.rows<{ payload: Record<string, unknown> }>(
      `select payload from better_supabase.outbox_events where type = 'bulk_run.completed' and organization_id = '${org}'`,
    );

    expect(events.map((event) => event.payload)).toEqual([
      expect.objectContaining({ kind: "tasks.archive", count: 5, failed: 1 }),
    ]);

    await db.asRole(member);
    const run = await bulk.get(started.id).orThrow();
    expect(run?.results.filter((row) => !row.ok).map((row) => row.id)).toEqual([
      task(3),
    ]);
    await db.asRole(owner);
    expect(await bulk.get(started.id).orThrow()).toBeNull();
  });
});
