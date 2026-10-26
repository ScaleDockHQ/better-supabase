import { describe, expect, it } from "vitest";

import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const TICKET = "44444444-4444-4444-8444-444444444444";
const DONE_TICKET = "55555555-5555-4555-8555-555555555555";

const SETUP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create table public.tickets (
  id uuid primary key,
  organization_id uuid not null,
  status text not null default 'todo',
  pipeline_id uuid,
  stage_id uuid
);
`;

const ticket = (follow: boolean) => ({
  categories: { todo: "open", doing: "open", done: "success" },
  status: {
    column: "status",
    values: { todo: "todo", doing: "doing", done: "done" },
    ...(follow ? { follow: true } : {}),
  },
  stages: [
    { key: "todo", name: "To do", category: "todo" },
    { key: "doing", name: "Doing", category: "doing" },
    { key: "done", name: "Done", category: "done" },
  ],
});

const layout = (follow: boolean): BlockSqlLayout => ({
  subjects: { ticket: { table: "public.tickets", idType: "uuid" } },
  modules: { pipelines: { on: { ticket: ticket(follow) } } },
});

const sqlOf = (follow: boolean): string =>
  renderBlocks(["pipelines"], layout(follow))
    .filter((file) => file.module === "pipelines")
    .map((file) => file.contents)
    .join("\n");

describe("pipelines status that follows direct writes", () => {
  it("adds the follow trigger only when the binding asks for it", () => {
    expect(sqlOf(false)).not.toContain("bsb_pipeline_follow_ticket");
    expect(sqlOf(true)).toContain(
      'create trigger bsb_pipeline_follow_ticket after update of "status" on "public"."tickets"',
    );
  });

  it(
    "moves a record to the stage its new status maps to",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(["pipelines"], layout(true));

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          SETUP,
          ...files
            .filter((file) => file.kind !== "data")
            .map((file) => file.contents),
        ],
        seed: [
          ...files
            .filter((file) => file.kind === "data")
            .map((file) => file.contents),
          `do $$
declare
  v_done uuid;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  insert into public.tickets (id, organization_id) values ('${TICKET}', '${TENANT}');
  if (select stage_id from public.tickets where id = '${TICKET}') is null then
    raise exception 'no first stage %', (select jsonb_agg(t) from public.tickets t);
  end if;
  update public.tickets set status = 'done' where id = '${TICKET}';
  select s.id into v_done from better_supabase.pipeline_stages s where s.key = 'done';
  if (select stage_id from public.tickets where id = '${TICKET}') is distinct from v_done then
    raise exception 'stage did not follow %', (select jsonb_agg(t) from public.tickets t);
  end if;
  update public.tickets set stage_id = (select s.id from better_supabase.pipeline_stages s where s.key = 'doing') where id = '${TICKET}';
  if (select status from public.tickets where id = '${TICKET}') <> 'doing' then
    raise exception 'status did not follow the stage %', (select jsonb_agg(t) from public.tickets t);
  end if;
  update public.tickets set status = 'parked' where id = '${TICKET}';
  if (select s.key from better_supabase.pipeline_stages s join public.tickets t on t.stage_id = s.id) <> 'doing' then
    raise exception 'an unmapped status moved the stage';
  end if;
  insert into public.tickets (id, organization_id, status) values ('${DONE_TICKET}', '${TENANT}', 'done');
  if (select s.key from better_supabase.pipeline_stages s join public.tickets t on t.stage_id = s.id where t.id = '${DONE_TICKET}') <> 'done'
    or (select status from public.tickets where id = '${DONE_TICKET}') <> 'done' then
    raise exception 'an inserted status did not pick its stage %', (select jsonb_agg(t) from public.tickets t);
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
