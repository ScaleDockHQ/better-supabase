import { Pool, type PoolClient } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { ModuleLayout } from "../../src/sql/module-types.ts";

import { rankBetween } from "../../src/core/rank-keys.ts";
import { rankAfter } from "../../src/sql/rank-sql.ts";
import { renderModules } from "../../src/sql/render.ts";
import { upgradePlan } from "../../src/sql/upgrade.ts";
import VECTORS from "../core/fixtures/rank-vectors.json" with { type: "json" };
import { dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const ACME = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-0000000000ff";

const layout: ModuleLayout = {
  subjects: {
    deal: {
      table: "rank_it.deals",
      rank: { column: "rank", group: "stage" },
    },
    ticket: {
      table: "rank_it.tickets",
      rank: { column: "rank", group: "stage_id" },
    },
    bug: {
      table: "rank_it.bugs",
      rank: { column: "rank", group: "lane" },
    },
  },
  modules: {
    "state-machine": {
      options: {
        machines: {
          deal_stage: {
            table: "rank_it.deals",
            column: "stage",
            initial: "lead",
            tenant: "organization_id",
            transitions: { lead: ["won"], won: [] },
          },
        },
      },
    },
    tags: { schema: "rank_it" },
    "custom-fields": { schema: "rank_it" },
  },
};

const TABLE = `create schema rank_it;
create table rank_it.deals (
  id text primary key,
  organization_id uuid not null,
  stage text not null default 'lead',
  rank text collate "C" not null
);
alter table rank_it.deals enable row level security;
create policy deals_acme on rank_it.deals for all to authenticated
  using (organization_id = '${ACME}') with check (organization_id = '${ACME}');
grant usage on schema rank_it to authenticated;
grant select, update on rank_it.deals to authenticated;
create table rank_it.tickets (
  id text primary key,
  organization_id uuid not null,
  stage_id uuid not null,
  rank text collate "C" not null
);
create type rank_it.lane as enum ('triage', 'doing', 'done');
create table rank_it.bugs (
  id text primary key,
  organization_id uuid not null,
  lane rank_it.lane not null default 'triage',
  rank text collate "C" not null
);`;

interface PgError {
  readonly hint?: string;
  readonly message: string;
}

describe.skipIf(!live)("rank keys in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let client: PoolClient;

  const one = async <T>(sql: string, values: unknown[] = []): Promise<T> => {
    const { rows } = await client.query<{ value: T }>(sql, values);

    return rows[0]!.value;
  };

  const failure = async (
    sql: string,
    values: unknown[] = [],
  ): Promise<PgError> => {
    await client.query("savepoint attempt");

    try {
      await client.query(sql, values);
    } catch (cause) {
      await client.query("rollback to savepoint attempt");

      return cause as PgError;
    }

    throw new Error(`expected ${sql} to fail`);
  };

  const deals = async (): Promise<{ id: string; stage: string }[]> =>
    (
      await client.query<{ id: string; stage: string }>(
        `select id, stage from rank_it.deals where organization_id = '${ACME}' order by stage, rank collate "C"`,
      )
    ).rows;

  const move = (
    id: string,
    previous: string | null,
    next: string | null,
    group: string | null = null,
  ): Promise<string> =>
    one<string>(
      "select better_supabase.move('deal', $1, $2, $3, $4) as value",
      [id, previous, next, group],
    );

  beforeAll(async () => {
    client = await pool.connect();
    await client.query("begin");
    await client.query(TABLE);

    for (const file of renderModules(
      ["rank", "state-machine", "tags", "custom-fields"],
      layout,
    )) {
      if (file.kind !== "test") {
        await client.query(file.contents);
      }
    }

    await client.query(
      `insert into rank_it.deals (id, organization_id, rank)
       select 'd' || n, '${ACME}', better_supabase.rank_key(n, 4) from generate_series(1, 4) n`,
    );
    await client.query(
      `insert into rank_it.deals (id, organization_id, rank) values ('x1', '${OTHER}', 'V')`,
    );
  });

  afterAll(async () => {
    await client.query("rollback");
    client.release();
    await pool.end();
  });

  it.each(VECTORS.between)(
    "rank_between($previous, $next) is $key",
    async ({ previous, next, key }) => {
      expect(
        await one("select better_supabase.rank_between($1, $2) as value", [
          previous,
          next,
        ]),
      ).toBe(key);
    },
  );

  it.each(VECTORS.invalid)(
    "rank_between($previous, $next) raises",
    async ({ previous, next }) => {
      const error = await failure(
        "select better_supabase.rank_between($1, $2)",
        [previous, next],
      );

      expect(error.hint).toMatch(/^RANK_KEY_(INVALID|ORDER)$/);
    },
  );

  it.each(VECTORS.keys)(
    "rank_key matches rankKeys($count)",
    async ({ count, keys }) => {
      expect(
        await one(
          "select array_agg(better_supabase.rank_key(n, $1) order by n) as value from generate_series(1, $1) n",
          [count],
        ),
      ).toEqual(keys);
    },
  );

  it("appends after a key the way rankBetween(last, null) does", async () => {
    const lasts = [
      ...VECTORS.between.flatMap(({ key }) => [key]),
      "z",
      "zzz",
      "z1",
      "Zz",
      "0001",
    ];

    for (const last of lasts) {
      expect(
        await one(`select ${rankAfter("$1::text")} as value`, [last]),
      ).toBe(rankBetween(last, null));
    }

    expect(await one(`select ${rankAfter("$1::text")} as value`, [null])).toBe(
      "V",
    );
  });

  it("moves a deal between two others in its group", async () => {
    const key = await move("d4", "d1", "d2");
    expect(key > "F" && key < "U").toBe(true);
    expect((await deals()).map((deal) => deal.id)).toEqual([
      "d1",
      "d4",
      "d2",
      "d3",
    ]);
  });

  it("changes the group through the state-machine trigger", async () => {
    await move("d3", null, null, "won");
    expect(await deals()).toContainEqual({ id: "d3", stage: "won" });

    const back = await failure(
      "select better_supabase.move('deal', 'd3', null, null, 'lead')",
    );

    expect(back.message).toMatch(/transition|not allowed/i);
  });

  it("moves into a uuid or enum group column", async () => {
    const [from, to] = [
      "00000000-0000-4000-8000-0000000000a1",
      "00000000-0000-4000-8000-0000000000a2",
    ];

    await client.query(
      `insert into rank_it.tickets values ('t1', '${ACME}', $1, 'V'), ('t2', '${ACME}', $2, 'V')`,
      [from, to],
    );
    await client.query(
      `insert into rank_it.bugs (id, organization_id, rank) values ('b1', '${ACME}', 'V')`,
    );
    await one(
      "select better_supabase.move('ticket', 't1', 't2', null, $1) as value",
      [to],
    );
    expect(
      await one(
        "select stage_id::text as value from rank_it.tickets where id = 't1'",
      ),
    ).toBe(to);
    await one(
      "select better_supabase.move('bug', 'b1', null, null, 'done') as value",
    );
    expect(
      await one("select lane::text as value from rank_it.bugs where id = 'b1'"),
    ).toBe("done");

    const bad = await failure(
      "select better_supabase.move('bug', 'b1', null, null, 'nope')",
    );

    expect(bad.message).toMatch(/invalid input value for enum/);
  });

  it("rejects a neighbour from another group", async () => {
    const error = await failure(
      "select better_supabase.move('deal', 'd1', 'd3', null, null)",
    );

    expect(error.hint).toBe("RANK_NEIGHBOR_MISMATCH");
  });

  it("runs as the caller, so policies hide other tenants' rows", async () => {
    await client.query("set local role authenticated");

    try {
      const hidden = await failure(
        "select better_supabase.move('deal', 'x1', null, null, null)",
      );

      expect(hidden.hint).toBe("RANK_FORBIDDEN");
      expect(typeof (await move("d2", null, "d1"))).toBe("string");
    } finally {
      await client.query("reset role");
    }
  });

  it("rebalances long keys to short ones in the same order", async () => {
    for (let step = 0; step < 40; step += 1) {
      await move("d2", "d1", "d4");
    }

    await move("d2", "d4", null);
    const before = (await deals()).map((deal) => deal.id);
    expect(
      await one(
        "select better_supabase.rebalance_ranks('deal', $1, 'lead') as value",
        [ACME],
      ),
    ).toBe(3);
    expect((await deals()).map((deal) => deal.id)).toEqual(before);
    expect(
      await one(
        `select max(length(rank)) as value from rank_it.deals where stage = 'lead'`,
      ),
    ).toBe(1);
  });

  it("appends tags and field definitions, and validates set keys", async () => {
    await client.query(
      `select set_config('request.jwt.claims', '{"role":"service_role"}', true)`,
    );

    const first = await one<{ rank: string }>(
      `select rank_it.create_tag($1, 'deal', 'Hot', null, null) as value`,
      [ACME],
    );

    const second = await one<{ rank: string; id: string }>(
      `select rank_it.create_tag($1, 'deal', 'Cold', null, null) as value`,
      [ACME],
    );

    expect([first.rank, second.rank]).toEqual(["V", "k"]);

    const invalid = await failure("select rank_it.rank_tag($1, 'V0')", [
      second.id,
    ]);

    expect(invalid.hint).toBe("TAG_RANK_INVALID");
    expect(
      await one("select rank_it.rank_tag($1, 'F') as value", [second.id]),
    ).toBe(true);
    await client.query(
      `select rank_it.save_field_definition($1, 'deal', 'tier', 'Tier', 'text', false)`,
      [ACME],
    );
    await client.query(
      `select rank_it.save_field_definition($1, 'deal', 'size', 'Size', 'number', false)`,
      [ACME],
    );
    expect(
      await one(
        `select array_agg(key order by rank collate "C") as value from rank_it.field_definitions where tenant_id = $1`,
        [ACME],
      ),
    ).toEqual(["tier", "size"]);
  });

  it("backfills rank keys in position order on upgrade", async () => {
    await client.query(`create schema rank_up;
create table rank_up.tags (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  kind text not null,
  name text not null,
  slug text not null,
  color text,
  description text,
  position integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into rank_up.tags (tenant_id, kind, name, slug, position) values
  ('${ACME}', 'deal', 'b', 'b', 2), ('${ACME}', 'deal', 'a', 'a', 1),
  ('${ACME}', 'deal', 'c', 'c', 2), ('${ACME}', 'note', 'z', 'z', 0);`);

    const [plan] = upgradePlan([{ module: "tags", version: 1 }], {
      modules: { tags: { schema: "rank_up" } },
    });

    for (const step of plan!.steps) {
      await client.query(step.sql);
    }

    const { rows } = await client.query<{ name: string; rank: string }>(
      `select name, rank from rank_up.tags order by kind, rank collate "C"`,
    );

    expect(rows).toEqual([
      { name: "a", rank: "0001V" },
      { name: "b", rank: "0002V" },
      { name: "c", rank: "0003V" },
      { name: "z", rank: "0001V" },
    ]);
  });
});
