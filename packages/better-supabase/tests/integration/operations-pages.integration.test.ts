import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const MISSING = "00000000-0000-4000-8000-00000000dead";

interface Page {
  readonly items: readonly unknown[];
  readonly hasMore: boolean;
}

describe.skipIf(!live)("operations list functions in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let tenant: string;

  const call = <T>(sql: string, params: unknown[] = []): Promise<T> =>
    session.value<T>(sql, params);

  const filters = (value: object): string => JSON.stringify(value);

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install([
      "organizations",
      "outbox",
      "numbering",
      "catalog",
      "inventory",
      "warehouse",
      "lims",
      "maintenance",
    ]);
    owner = await session.user("operations-owner");
    tenant = await session.organization(owner);
    await session.as(owner);
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it.each([
    ["page_lims_methods", "get_lims_method", "key"],
    ["page_maintenance_meters", "get_maintenance_meter", "name"],
    ["page_pick_waves", "get_pick_wave", "createdAt"],
    ["page_count_plans", "get_count_plan", "nextRunOn"],
  ])("%s pages, counts, searches and misses %s", async (page, get, sort) => {
    const empty = await call<Page>(`better_supabase.${page}($1, $2::jsonb)`, [
      tenant,
      filters({ paged: true, sort, search: "zz", limit: 5 }),
    ]);

    expect(empty).toMatchObject({ items: [], hasMore: false });
    expect(
      await call<{ value: number }>(`better_supabase.${page}($1, $2::jsonb)`, [
        tenant,
        filters({ count: true }),
      ]),
    ).toMatchObject({ value: 0, exact: true });
    expect(
      await call<unknown>(`better_supabase.${get}($1)`, [MISSING]),
    ).toBeNull();
  });

  it("refuses an undeclared sort", async () => {
    expect(
      await session.hint("better_supabase.page_pick_waves($1, $2::jsonb)", [
        tenant,
        filters({ paged: true, sort: "nope" }),
      ]),
    ).toBeTruthy();
  });

  it("keeps list_putaway_rules an array unless paged", async () => {
    expect(
      await call<unknown[]>(
        "better_supabase.list_putaway_rules($1, $2::jsonb)",
        [tenant, filters({})],
      ),
    ).toEqual([]);
    expect(
      await call<Page>("better_supabase.list_putaway_rules($1, $2::jsonb)", [
        tenant,
        filters({ paged: true, active: ["true"] }),
      ]),
    ).toMatchObject({ items: [], hasMore: false });
    expect(
      await call<unknown>("better_supabase.get_putaway_rule($1)", [MISSING]),
    ).toBeNull();
  });
});
