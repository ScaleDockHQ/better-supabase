import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

// An app's tasks table: its own enum states, of which on_hold has no block
// state, and an enum priority.
const SETUP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create type public.task_status as enum ('todo', 'in_progress', 'on_hold', 'done');
create type public.task_priority as enum ('low', 'medium', 'high', 'urgent');
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  number bigint not null default 1,
  title text not null,
  status public.task_status not null default 'todo',
  priority public.task_priority not null default 'medium',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
`;

const BLOCKS: AnyBlocksConfig = {
  tasks: {
    tables: {
      items: "public.tasks",
      checklist: null,
      projects: null,
      iterations: null,
    },
    columns: {
      items: {
        tenant: "organization_id",
        state: "status",
        project: null,
        iteration: null,
        estimate: null,
        progress: null,
        recursFrom: null,
      },
    },
    values: {
      items: {
        state: {
          triage: null,
          backlog: "todo",
          unstarted: "todo",
          started: ["in_progress", "on_hold"],
          completed: "done",
          canceled: null,
        },
        priority: {
          "0": "medium",
          "1": "urgent",
          "2": "high",
          "3": "medium",
          "4": "low",
        },
      },
    },
  },
};

const render = () =>
  renderBlocks(["tasks"], {
    modules: BLOCKS,
    ownTables: { "public.tasks": "app.sql" },
  });

describe("tasks over an app table with its own states", () => {
  it("leaves the checklist out when the app maps it to null", () => {
    const sql = render()
      .filter((file) => file.module === "tasks")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("work_item_checklist_items");
    expect(sql).not.toContain("save_task_checklist_item");
    expect(sql).toContain("'checklist', null");
  });

  it(
    "creates, closes and reopens work items through the value map",
    { timeout: 60_000 },
    async () => {
      const files = render();

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
          `create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
do $$
declare
  v_item jsonb;
  v_id uuid;
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  v_item := better_supabase.create_task('${TENANT}', '{"title": "Fix the gate", "priority": "1"}', '{}');
  v_id := (v_item ->> 'id')::uuid;
  if (select priority::text from public.tasks where id = v_id) <> 'urgent' then
    raise exception 'priority %', (select jsonb_agg(t) from public.tasks t);
  end if;
  update public.tasks set status = 'done' where id = v_id;
  if (select closed_at from public.tasks where id = v_id) is null then
    raise exception 'closing state did not stamp closed_at';
  end if;
  update public.tasks set status = 'on_hold' where id = v_id;
  if (select closed_at from public.tasks where id = v_id) is not null then
    raise exception 'reopening did not clear closed_at';
  end if;
  if better_supabase.get_task(v_id) ->> 'status' <> 'started' then
    raise exception 'read label %', better_supabase.get_task(v_id);
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
