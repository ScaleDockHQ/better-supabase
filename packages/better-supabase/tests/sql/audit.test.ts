import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { liteStack } from "../../src/testing/lite.ts";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  name text,
  api_key text,
  updated_at timestamptz not null default now()
);
create table public.keyless (organization_id uuid, name text);
`;

const ORG = "11111111-1111-4111-8111-111111111111";

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["audit"], { modules: { audit: {} } });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      ...files
        .filter((file) => file.kind !== "data")
        .map((file) => file.contents),
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

const COUNT = (where: string, expected: number): string => `
do $$
declare n integer;
begin
  select count(*) into n from better_supabase.audit_events where ${where};
  if n <> ${expected} then
    raise exception 'expected ${expected} entries where ${where.replaceAll("'", "''")}, got %', n;
  end if;
end;
$$;`;

describe("audit(statement => true)", BOOT, () => {
  it("writes one entry per row from one insert per statement", async () => {
    await expect(
      run(`select better_supabase.audit('public.customers', ignore => '{updated_at}', redact => '{api_key}', statement => true);
insert into public.customers (organization_id, name, api_key)
  select '${ORG}', 'c' || i, 'secret' from generate_series(1, 3) i;
${COUNT(`op = 'insert' and organization_id = '${ORG}' and event_type = 'customers.created'`, 3)}
update public.customers set name = upper(name), api_key = 'other';
${COUNT("op = 'update' and changed = '{api_key,name}' and new_record ->> 'api_key' = '[redacted]'", 3)}
update public.customers set updated_at = now() + interval '1 day';
${COUNT("op = 'update'", 3)}
update public.customers set id = gen_random_uuid() where name = 'C1';
${COUNT("op = 'delete'", 1)}
${COUNT("op = 'insert'", 4)}
delete from public.customers;
${COUNT("op = 'delete'", 4)}
do $$
begin
  if jsonb_typeof(better_supabase.audit_settings('public.customers') -> 'ignore') <> 'array' then
    raise exception 'settings';
  end if;
  perform better_supabase.unaudit('public.customers'::regclass);
  if exists (select 1 from pg_trigger where tgrelid = 'public.customers'::regclass and not tgisinternal) then
    raise exception 'unaudit left triggers';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses tables and options it can't audit by statement", async () => {
    await expect(
      run(`do $$
begin
  begin
    perform better_supabase.audit('public.keyless', statement => true);
    raise exception 'audited a table without a primary key';
  exception when others then
    if sqlerrm not like '%needs a primary key%' then raise; end if;
  end;
  begin
    perform better_supabase.audit('public.customers', statement => true, deferred => true);
    raise exception 'combined deferred';
  exception when others then
    if sqlerrm not like '%does not combine%' then raise; end if;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
