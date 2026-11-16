import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { liteStack } from "../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/**
 * An app that keeps a block's status in its own enum type, as one it adopted:
 * the block's text checks go, and its triggers are recreated over the column.
 */
const enumStatus = (table: string, type: string, values: string): string => `
create type public.${type} as enum (${values});
do $$
declare
  v_table regclass := 'better_supabase.${table}';
  v_name text;
  v_triggers text[];
  v_trigger text;
begin
  for v_name in select conname from pg_constraint where conrelid = v_table and contype = 'c' and pg_get_constraintdef(oid) like '%status%' loop
    execute format('alter table %s drop constraint %I', v_table, v_name);
  end loop;
  select coalesce(array_agg(pg_get_triggerdef(oid)), '{}') into v_triggers from pg_trigger where tgrelid = v_table and not tgisinternal;
  for v_name in select tgname from pg_trigger where tgrelid = v_table and not tgisinternal loop
    execute format('drop trigger %I on %s', v_name, v_table);
  end loop;
  alter table better_supabase.${table} alter column status drop default;
  alter table better_supabase.${table} alter column status type public.${type} using status::public.${type};
  foreach v_trigger in array v_triggers loop
    execute v_trigger;
  end loop;
end;
$$;
`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  blocks: readonly string[],
  alter: string,
  check: string,
): Promise<void> {
  const files = renderBlocks(blocks, {});

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
      alter,
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

const filtered = (call: string): string => `do $$
begin
  ${SERVICE}
  perform ${call}('${TENANT}', '{"status": ["active"]}');
  perform ${call}('${TENANT}', '{"status": "active"}');
end;
$$;`;

describe("a status filter on an enum column", BOOT, () => {
  it("lists teams", async () => {
    await expect(
      run(
        ["teams"],
        enumStatus("teams", "team_status", "'active', 'archived'"),
        filtered("better_supabase.list_teams"),
      ),
    ).resolves.toBeUndefined();
  });

  it("pages employees", async () => {
    await expect(
      run(
        ["employees"],
        enumStatus(
          "employees",
          "employee_status",
          "'preboarding', 'active', 'on_leave', 'offboarded'",
        ),
        filtered("better_supabase.page_employees"),
      ),
    ).resolves.toBeUndefined();
  });

  it("pages invoices", async () => {
    await expect(
      run(
        ["invoices"],
        enumStatus(
          "invoices",
          "invoice_status",
          "'draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible'",
        ),
        filtered("better_supabase.page_invoices"),
      ),
    ).resolves.toBeUndefined();
  });
});
