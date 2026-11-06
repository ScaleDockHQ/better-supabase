import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ACME = "33333333-3333-4333-8333-333333333333";
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
  pipeline_id uuid,
  stage_id uuid
);
insert into public.organizations values ('${TENANT}', null), ('${ACME}', 'acme');
`;

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const layout: BlockSqlLayout = {
  subjects: {
    ticket: {
      table: "public.tickets",
      idType: "uuid",
      tenant: "organization_id",
    },
  },
  modules: {
    pipelines: {
      options: { brand: { table: "public.organizations", column: "brand" } },
      on: {
        ticket: {
          categories: { todo: "open", done: "success" },
          stages: [
            { key: "todo", name: "To do", category: "todo", icon: "circle" },
            { key: "doing", name: "Doing", category: "todo" },
            { key: "done", name: "Done", category: "done" },
          ],
          brands: {
            acme: {
              stages: [
                { key: "inbox", name: "Inbox", category: "todo" },
                { key: "doing", name: "In flight", category: "todo" },
                { key: "done", name: "Shipped", category: "done" },
              ],
            },
          },
        },
      },
    },
  },
};

async function run(check: string): Promise<void> {
  const files = renderBlocks(["pipelines"], layout);

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
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("pipeline lanes in Postgres", { timeout: 120_000 }, () => {
  it("starts an organization of a brand with its own stages", async () => {
    await expect(
      run(`do $$
declare
  v_pipeline uuid;
begin
  ${SERVICE}
  v_pipeline := better_supabase.default_pipeline('${ACME}', 'ticket', null);
  if (select count(*) from better_supabase.pipeline_stages where pipeline_id = v_pipeline) <> 3 then
    raise exception 'brand stages %', (select jsonb_agg(key) from better_supabase.pipeline_stages);
  end if;
  v_pipeline := better_supabase.default_pipeline('${TENANT}', 'ticket', null);
  if (select count(*) from better_supabase.pipeline_stages where pipeline_id = v_pipeline and icon = 'circle') <> 1 then
    raise exception 'default stages or icon missing %', (select jsonb_agg(to_jsonb(s)) from better_supabase.pipeline_stages s where s.pipeline_id = v_pipeline);
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("moves records into the stage that replaces an archived one", async () => {
    await expect(
      run(`do $$
declare
  v_pipeline uuid;
  v_todo uuid;
  v_failed boolean := false;
begin
  ${SERVICE}
  insert into public.tickets (id, organization_id) values ('${TICKET}', '${TENANT}');
  select pipeline_id, stage_id into v_pipeline, v_todo from public.tickets where id = '${TICKET}';
  begin
    perform better_supabase.archive_pipeline_stage(v_todo);
  exception when others then
    v_failed := true;
  end;
  if not v_failed then raise exception 'an occupied stage was archived'; end if;
  perform better_supabase.archive_pipeline_stage(v_todo, (select id from better_supabase.pipeline_stages where pipeline_id = v_pipeline and key = 'doing'));
  if (select stage_id from public.tickets where id = '${TICKET}') <> (select id from better_supabase.pipeline_stages where pipeline_id = v_pipeline and key = 'doing') then
    raise exception 'record did not move';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
