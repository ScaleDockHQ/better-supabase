import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { PgliteConnection } from "../../../src/lite/runtime.ts";

import { getLite, migrateLite } from "../../../src/lite/runtime.ts";
import { renderBlocks } from "../../../src/sql/render.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const TENANT = "00000000-0000-4000-8000-000000000001";

const BLOCKS: AnyBlocksConfig = {
  imports: {
    options: {
      targets: {
        customer: { subjectType: "customer", write: "public.import_customer" },
      },
    },
  },
};

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create schema if not exists extensions;
create or replace function extensions.gen_random_bytes(n integer) returns bytea
language sql volatile as $$ select decode(md5(random()::text), 'hex') $$;
create or replace function extensions.digest(data text, type text) returns bytea
language sql immutable as $$ select sha256(convert_to(data, 'UTF8')) $$;
create schema if not exists realtime;
create or replace function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language sql as $$ select $$;
`;

const APP = `
create table public.customers (id uuid primary key default gen_random_uuid(), name text not null);
create function public.import_customer(run uuid, item jsonb, subject_id text) returns jsonb
language plpgsql as $$
declare v_id uuid;
begin
  if item -> 'data' ->> 'name' = 'bad' then
    raise exception 'bad customer' using hint = 'IMPORT_ITEM_INVALID';
  end if;
  insert into public.customers (name) values (item -> 'data' ->> 'name') returning id into v_id;
  return jsonb_build_object('subjectId', v_id::text);
end;
$$;
`;

const SERVICE = `
select set_config('request.jwt.claims', '{"role":"service_role"}', false);
select set_config('request.jwt.claim.role', 'service_role', false);
`;

describe("import runs", { timeout: 60_000 }, () => {
  let connection: PgliteConnection | undefined;

  const query = async <R>(text: string, params?: unknown[]): Promise<R[]> => {
    // SAFETY: PGlite's query takes parameters; the runtime type leaves them out.
    const driver = connection?.driver as unknown as {
      query(text: string, params?: unknown[]): Promise<{ rows: unknown[] }>;
    };

    // SAFETY: each caller names the row type its statement selects.
    return (await driver.query(text, params)).rows as R[];
  };

  const start = async (source: string, dryRun: boolean): Promise<string> => {
    const [row] = await query<{ id: string }>(
      `select better_supabase.start_import_run($1::uuid, $2, $3::jsonb) ->> 'id' as id`,
      [TENANT, source, JSON.stringify({ dryRun })],
    );

    await query(`select better_supabase.mark_import_running($1::uuid)`, [
      row?.id,
    ]);

    return row?.id ?? "";
  };

  const issues = async (run: string): Promise<number> =>
    Number(
      (
        await query<{ n: number }>(
          `select count(*)::int as n from better_supabase.import_run_issues where run_id = $1::uuid`,
          [run],
        )
      )[0]?.n,
    );

  beforeAll(async () => {
    const lite = await getLite();

    if (!lite) {
      throw new Error("@supabase/lite is a devDependency of these tests");
    }

    connection = await lite.createPgliteConnection();
    await new lite.App({
      connection,
      auth: {
        enabled: true,
        jwt_secret: "x".repeat(32),
        publishable_key: "sb_publishable_test",
        secret_key: "sb_secret_test",
      },
    }).init();

    const files = renderBlocks(
      ["memberships", "permissions", "queue", "imports"],
      { modules: BLOCKS, ownTables: ownTablesOf(BLOCKS, []) },
    );

    await migrateLite(connection, [
      ROLES,
      APP,
      ...files
        // PGlite has no pgmq; only enqueue_import_chunks calls the queue, at run time.
        .filter((file) => file.kind === "schema" && file.module !== "queue")
        .map((file) => file.contents),
    ]);

    for (const file of files.filter(
      (each) => each.kind === "data" && each.module !== "queue",
    )) {
      await connection.driver.exec(file.contents);
    }

    await connection.driver.exec(SERVICE);
  }, 120_000);

  afterAll(async () => {
    await connection?.close();
  });

  it("keeps the error rows of a dry run batch, and cancelling the run removes them", async () => {
    const run = await start("dry", true);
    await query(
      `select better_supabase.import_upsert_batch($1::uuid, 'customer', $2::jsonb)`,
      [
        run,
        JSON.stringify([
          { key: "a", data: { name: "Ann" } },
          { key: "b", data: { name: "bad" } },
        ]),
      ],
    );

    expect(await issues(run)).toBe(1);
    expect(
      (
        await query<{ n: number }>(
          `select count(*)::int as n from public.customers`,
        )
      )[0]?.n,
    ).toBe(0);

    await query(`select better_supabase.cancel_import_run($1::uuid)`, [run]);
    expect(await issues(run)).toBe(0);
  });

  it("writes new keys once and finds known ones from the prefetch", async () => {
    const run = await start("live", false);

    const items = JSON.stringify([
      { key: "k1", data: { name: "One" } },
      { key: "k2", data: { name: "Two" } },
      { key: "k1", data: { name: "One" } },
    ]);

    const [first] = await query<{
      result: { inserted: number; unchanged: number };
    }>(
      `select better_supabase.import_upsert_batch($1::uuid, 'customer', $2::jsonb) as result`,
      [run, items],
    );

    expect(first?.result.inserted).toBe(2);
    expect(first?.result.unchanged).toBe(1);

    const [second] = await query<{
      result: { inserted: number; unchanged: number };
    }>(
      `select better_supabase.import_upsert_batch($1::uuid, 'customer', $2::jsonb) as result`,
      [run, items],
    );

    expect(second?.result.inserted).toBe(0);
    expect(second?.result.unchanged).toBe(3);
  });
});
