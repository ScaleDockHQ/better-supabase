import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ACME = "33333333-3333-4333-8333-333333333333";
const ALICE = "22222222-2222-4222-8222-222222222222";
const TICKET = "44444444-4444-4444-8444-444444444444";

const SETUP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create table public.organizations (id uuid primary key, brand text);
create table public.tickets (
  id uuid primary key,
  organization_id uuid not null,
  priority smallint not null default 0
);
`;

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}');
insert into public.organizations values ('${TENANT}', null), ('${ACME}', 'acme');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const ITEMS = [
  { key: "none", label: "None", level: 0 },
  { key: "low", label: "Low", level: 1 },
  { key: "high", label: "High", level: 3 },
];

const layout: BlockSqlLayout = {
  subjects: {
    ticket: {
      table: "public.tickets",
      idType: "uuid",
      tenant: "organization_id",
    },
  },
  modules: {
    "option-sets": {
      options: { brand: { table: "public.organizations", column: "brand" } },
      on: {
        ticket: {
          priority: {
            levels: { min: 0, max: 4 },
            items: ITEMS,
            brands: {
              acme: [
                { key: "calm", label: "Calm", level: 0 },
                { key: "now", label: "Right now", level: 4, color: "red" },
              ],
            },
          },
        },
      },
    },
  },
};

const BOOT = { timeout: 120_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "subjects", "option-sets"],
    layout,
  );

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      SETUP,
      ...files
        .filter((file) => file.kind === "schema")
        .map((file) => file.contents),
    ],
    seed: [
      ...files
        .filter((file) => file.kind === "data")
        .map((file) => file.contents),
      ALLOW,
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("option sets in Postgres", BOOT, () => {
  it("seeds a default set, writes the level and replaces an archived item", async () => {
    await expect(
      run(`do $$
declare
  v_set jsonb;
  v_high uuid;
  v_low uuid;
  v_failed boolean := false;
begin
  ${SERVICE}
  v_set := better_supabase.ensure_option_set('${TENANT}', 'ticket', 'priority');
  if jsonb_array_length(v_set -> 'items') <> 3 then raise exception 'items %', v_set; end if;
  if better_supabase.ensure_option_set('${TENANT}', 'ticket', 'priority') ->> 'id' <> v_set ->> 'id' then
    raise exception 'ensure made a second set';
  end if;
  select (i ->> 'id')::uuid into v_high from jsonb_array_elements(v_set -> 'items') i where i ->> 'key' = 'high';
  select (i ->> 'id')::uuid into v_low from jsonb_array_elements(v_set -> 'items') i where i ->> 'key' = 'low';

  insert into public.tickets (id, organization_id, priority_option_id) values ('${TICKET}', '${TENANT}', v_high);
  if (select priority from public.tickets where id = '${TICKET}') <> 3 then
    raise exception 'level not written';
  end if;

  begin
    perform better_supabase.archive_option_set_item(v_high);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then raise exception 'an item in use was archived'; end if;

  perform better_supabase.archive_option_set_item(v_high, v_low);
  if (select priority from public.tickets where id = '${TICKET}') <> 1 then
    raise exception 'replacement level not written';
  end if;

end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("starts a tenant of a brand with that brand's items", async () => {
    await expect(
      run(`do $$
declare
  v_set jsonb;
begin
  ${SERVICE}
  v_set := better_supabase.ensure_option_set('${ACME}', 'ticket', 'priority');
  if jsonb_array_length(v_set -> 'items') <> 2
    or not exists (select 1 from jsonb_array_elements(v_set -> 'items') i where i ->> 'label' = 'Right now') then
    raise exception 'brand items %', v_set;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
