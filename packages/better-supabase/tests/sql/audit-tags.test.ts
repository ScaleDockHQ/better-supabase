import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../src/sql/render.ts";
import { liteStack } from "../../src/testing/lite.ts";

const TABLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create table public.facts (
  id bigint generated always as identity primary key,
  organization_id uuid not null,
  body text not null,
  chain_seq bigint,
  prev_hash bytea,
  row_hash bytea
);
`;

const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(["audit"], { modules: { audit: {} } });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      TABLES,
      ...files
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [check],
  });

  expect(stack.url).not.toBe("");
}

const ORG = "11111111-1111-4111-8111-111111111111";

describe("append-only, function-writes and chain helpers", () => {
  it(
    "refuses update, delete and truncate on an append-only table",
    BOOT,
    async () => {
      await run(`
select better_supabase.append_only('public.facts');
insert into public.facts (organization_id, body) values ('${ORG}', 'a');
do $$
begin
  begin
    update public.facts set body = 'b';
    raise exception 'update was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from public.facts;
    raise exception 'delete was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    truncate public.facts;
    raise exception 'truncate was allowed';
  exception when insufficient_privilege then null;
  end;
end;
$$;`);
    },
  );

  it(
    "chains rows per tenant and verify_chain finds an edit and a removed row",
    BOOT,
    async () => {
      await run(`
select better_supabase.chain('public.facts');
insert into public.facts (organization_id, body) values ('${ORG}', 'a'), ('${ORG}', 'b'), ('${ORG}', 'c');
do $$
declare
  v jsonb;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v := better_supabase.verify_chain('public.facts', 'organization_id', '${ORG}');
  if (v ->> 'valid')::boolean is not true or (v ->> 'checked')::int <> 3 then
    raise exception 'expected a valid chain of 3, got %', v;
  end if;
  update public.facts set body = 'x' where body = 'b';
  v := better_supabase.verify_chain('public.facts', 'organization_id', '${ORG}');
  if v ->> 'reason' <> 'hash' then
    raise exception 'expected hash, got %', v;
  end if;
  update public.facts set body = 'b' where body = 'x';
  delete from public.facts where body = 'b';
  v := better_supabase.verify_chain('public.facts', 'organization_id', '${ORG}');
  if v ->> 'reason' <> 'gap' then
    raise exception 'expected gap, got %', v;
  end if;
end;
$$;`);
    },
  );

  it("takes the write privileges away with function-writes", BOOT, async () => {
    await run(`
select better_supabase.function_writes('public.facts');
do $$
begin
  if has_table_privilege('authenticated', 'public.facts', 'insert') then
    raise exception 'authenticated can still insert';
  end if;
end;
$$;`);
  });
});
