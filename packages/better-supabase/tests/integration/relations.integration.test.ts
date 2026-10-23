import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import { createRelations } from "../../src/blocks/relations/index.ts";
import { createUndo } from "../../src/blocks/undo/undo.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const OTHER_ORG = "00000000-0000-4000-8000-0000000000ff";

const layout: BlockSqlLayout = {
  modules: {
    relations: {
      schema: "rel_it",
      on: { task: { table: "rel_it.tasks", idType: "uuid", cascade: true } },
    },
  },
};

const task = (n: number): string =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

interface Linked {
  readonly id: string;
  readonly created: boolean;
  readonly sourceId: string;
  readonly targetId: string;
  readonly replaced: { targetId: string } | null;
  readonly previousData: Record<string, unknown> | null;
}

interface Edge {
  readonly kind: string;
  readonly direction: string;
  readonly subjectId: string;
  readonly data: Record<string, unknown>;
}

describe.skipIf(!live)("relations in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let db: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let org: string;

  const link = (
    kind: string,
    from: number,
    to: number,
    data: string | null = null,
  ): string =>
    `rel_it.link('${org}', '${kind}', 'task', '${task(from)}', 'task', '${task(to)}', ${data === null ? "null" : `'${data}'::jsonb`})`;

  beforeAll(async () => {
    db = await BlockSession.open(pool);
    await db.client.query(`create schema rel_it;
create table rel_it.tasks (
  id uuid primary key,
  organization_id uuid not null,
  estimate integer not null default 0
);
alter table rel_it.tasks enable row level security;
create policy tasks_read on rel_it.tasks for select to authenticated using (true);
grant usage on schema rel_it to authenticated;
grant select on rel_it.tasks to authenticated;`);
    await db.install(["organizations", "outbox", "relations"], layout);
    owner = await db.user("owner");
    member = await db.user("member");
    org = await db.organization(owner, { member });
    await db.client
      .query(`insert into rel_it.tasks (id, organization_id, estimate)
select ('00000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, '${org}', n
from generate_series(1, 9) n;
insert into rel_it.tasks (id, organization_id) values ('${task(99)}', '${OTHER_ORG}');`);
  });

  afterAll(async () => {
    await db.close();
    await pool.end();
  });

  it("needs relations.manage and readable subjects on both ends", async () => {
    await db.as(member);
    expect(await db.hint(link("blocks", 1, 2))).toBe("RELATION_FORBIDDEN");
    await db.as(owner);
    expect(await db.hint(link("blocks", 1, 99))).toBe(
      "RELATION_SUBJECT_FORBIDDEN",
    );
    expect(await db.hint(link("blocks", 1, 1))).toBe("RELATION_SELF");
    expect(await db.hint(link("owns", 1, 2))).toBe("RELATION_KIND_UNKNOWN");
  });

  it("stores an inverse name from the other end and reads it back by side", async () => {
    await db.as(owner);
    const made = await db.value<Linked>(link("blocked_by", 3, 4));
    expect(made).toMatchObject({
      created: true,
      sourceId: task(4),
      targetId: task(3),
    });
    await db.asRole(member);

    const of3 = await db.value<Edge[]>(
      `rel_it.relations_of('${org}', 'task', '${task(3)}', null)`,
    );

    expect(of3).toEqual([
      expect.objectContaining({
        kind: "blocked_by",
        direction: "in",
        subjectId: task(4),
      }),
    ]);

    const of4 = await db.value<Edge[]>(
      `rel_it.relations_of('${org}', 'task', '${task(4)}', 'blocks')`,
    );

    expect(of4.map((edge) => edge.subjectId)).toEqual([task(3)]);
  });

  it("refuses a link that closes a cycle", async () => {
    await db.as(owner);
    await db.value(link("blocks", 5, 6));
    await db.value(link("blocks", 6, 7));
    expect(await db.hint(link("blocks", 7, 5))).toBe("RELATION_CYCLE");
    expect(await db.hint(link("blocked_by", 5, 7))).toBe("RELATION_CYCLE");
    const again = await db.value<Linked>(link("blocks", 5, 6, '{"lag":2}'));
    expect(again).toMatchObject({ created: false, previousData: {} });
  });

  it("replaces a one-target link and returns the old target", async () => {
    await db.as(owner);
    await db.value(link("parent", 2, 1));
    const moved = await db.value<Linked>(link("parent", 2, 8));
    expect(moved.replaced).toMatchObject({ targetId: task(1) });
    expect(await db.hint(link("parent", 8, 2))).toBe("RELATION_CYCLE");
  });

  it("walks ancestors and descendants and rolls up a column", async () => {
    await db.as(owner);
    await db.value(link("parent", 9, 8));
    await db.value(link("children", 9, 6));
    await db.asRole(member);

    const up = await db.value<{ id: string; depth: number }[]>(
      `rel_it.ancestors('${org}', 'parent', 'task', '${task(6)}')`,
    );

    expect(up).toEqual([
      { type: "task", id: task(9), depth: 1 },
      { type: "task", id: task(8), depth: 2 },
    ]);

    const down = await db.value<{ id: string }[]>(
      `rel_it.descendants('${org}', 'parent', 'task', '${task(8)}')`,
    );

    expect(down.map((row) => row.id)).toEqual([task(2), task(9), task(6)]);
    expect(
      await db.value(
        `rel_it.relation_rollup('${org}', 'parent', 'task', '${task(8)}', 'task', 'estimate', 'sum')`,
      ),
    ).toBe(2 + 9 + 6);
    expect(
      await db.value(
        `rel_it.relation_rollup('${org}', 'parent', 'task', '${task(8)}', 'task', null, 'count')`,
      ),
    ).toBe(3);
    expect(
      await db.hint(
        `rel_it.relation_rollup('${org}', 'parent', 'task', '${task(8)}', 'task', 'estimate', 'median')`,
      ),
    ).toBe("RELATION_ROLLUP_INVALID");
    await db.service();
  });

  it("stores a symmetric link once and unlinks from either end", async () => {
    await db.as(owner);
    await db.value(link("relates", 4, 1));
    const again = await db.value<Linked>(link("relates", 1, 4));
    expect(again.created).toBe(false);

    const removed = await db.value<{ removed: boolean }>(
      `rel_it.unlink('${org}', 'relates', 'task', '${task(4)}', 'task', '${task(1)}')`,
    );

    expect(removed.removed).toBe(true);
  });

  it("undoes a replaced parent through the client", async () => {
    const transport = sqlTransport(db.sql);

    const relations = createRelations({
      transport,
      schema: "rel_it",
      tenant: org,
    });

    await db.as(owner);

    const moved = await relations
      .link(
        { type: "task", id: task(3) },
        { type: "task", id: task(1) },
        { kind: "parent" },
      )
      .orThrow();

    const again = await relations
      .link(
        { type: "task", id: task(3) },
        { type: "task", id: task(5) },
        { kind: "parent" },
      )
      .orThrow();

    expect(moved.created && again.replaced?.target.id).toBe(task(1));
    await createUndo({ transport, schema: "rel_it" })
      .apply(again.undo)
      .orThrow();

    const up = await relations
      .ancestors({ type: "task", id: task(3) }, "parent")
      .orThrow();

    expect(up.map((node) => node.id)).toEqual([task(1)]);
  });

  it("tracks conversions through created_from and reads the lineage", async () => {
    await db.as(owner);
    await db.value(link("created_from", 8, 7));
    await db.value(link("created_from", 9, 8));
    expect(
      await db.value<string | null>(
        `rel_it.converted_into('${org}', 'task', '${task(7)}', 'task')`,
      ),
    ).toBe(task(8));
    expect(
      await db.value<string | null>(
        `rel_it.converted_into('${org}', 'task', '${task(9)}', 'task')`,
      ),
    ).toBeNull();
    expect(await db.hint(link("created_from", 7, 9))).toBe("RELATION_CYCLE");

    const relations = createRelations({
      transport: sqlTransport(db.sql),
      schema: "rel_it",
      tenant: org,
    });

    const lineage = await relations
      .lineage({ type: "task", id: task(8) })
      .orThrow();

    expect(lineage.origins.map((node) => node.id)).toEqual([task(7)]);
    expect(lineage.conversions.map((node) => node.id)).toEqual([task(9)]);
    expect(
      await relations
        .convertedInto({ type: "task", id: task(8) }, "task")
        .orThrow(),
    ).toBe(task(9));
  });

  it("records events and deletes links with their subject", async () => {
    await db.service();

    const events = await db.rows<{ type: string }>(
      `select type from better_supabase.outbox_events where organization_id = $1 and type like 'subject.%'`,
      [org],
    );

    expect(new Set(events.map((row) => row.type))).toEqual(
      new Set(["subject.linked", "subject.unlinked"]),
    );
    await db.client.query(`delete from rel_it.tasks where id = $1`, [task(6)]);

    const left = await db.rows(
      `select 1 from rel_it.relations where source_id = $1 or target_id = $1`,
      [task(6)],
    );

    expect(left).toEqual([]);
  });
});
