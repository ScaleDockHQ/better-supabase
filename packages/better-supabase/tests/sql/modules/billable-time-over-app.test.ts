import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const TASK = "66666666-6666-4666-8666-666666666666";
const OTHER_TASK = "77777777-7777-4777-8777-777777777777";

// The app's work log: one foreign key per record type, and a start with a
// duration instead of an end.
const SETUP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create table public.tasks (id uuid primary key, organization_id uuid not null);
create table public.work_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid not null,
  task_id uuid references public.tasks (id) on delete cascade,
  started_at timestamptz not null,
  duration_seconds integer,
  timer_started_at timestamptz,
  billable boolean not null default false,
  rate bigint,
  rate_currency text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.timesheets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid not null,
  week date not null,
  note text,
  submitted_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  status text not null default 'open',
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  unique (tenant_id, user_id, week)
);
`;

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$ select true $$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  values ('${TENANT}', '${ALICE}', 'member') on conflict do nothing;
insert into public.tasks (id, organization_id) values ('${TASK}', '${TENANT}'), ('${OTHER_TASK}', '${TENANT}');
`;

const BLOCKS: AnyBlocksConfig = {
  "time-tracking": {
    tables: { entries: "public.work_logs", timesheets: "public.timesheets" },
    columns: {
      entries: {
        subjectType: null,
        subjectId: null,
        endedAt: null,
        seconds: "duration_seconds",
        runningSince: "timer_started_at",
      },
      timesheets: { approval: null },
    },
    on: { task: { column: "task_id" } },
    options: { approvals: false },
  },
};

const render = () =>
  renderBlocks(["billable-time"], {
    modules: BLOCKS,
    subjects: { task: { table: "public.tasks", idType: "uuid" } },
    ownTables: {
      "public.work_logs": "app.sql",
      "public.timesheets": "app.sql",
    },
  }).map((file) => ({
    ...file,
    contents: file.contents
      .replace(
        "create extension if not exists btree_gist with schema extensions;",
        "",
      )
      .replace(
        'create extension if not exists "btree_gist" with schema "extensions";',
        "",
      ),
  }));

describe("billable time over per-record columns and duration entries", () => {
  it("reads the record from its column and the end from the duration", () => {
    const sql = render()
      .filter((file) => file.module === "billable-time")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).not.toContain("bsb_unmapped");
    expect(sql).toContain(`when x."task_id" is not null then 'task'`);
    expect(sql).toContain(
      `old."duration_seconds" is distinct from new."duration_seconds"`,
    );
    expect(sql).toContain(
      `old."timer_started_at" is distinct from new."timer_started_at"`,
    );
  });

  it(
    "rates finished entries by their record and leaves a running timer out",
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
          ALLOW,
          `do $$
declare
  v_time jsonb;
begin
  insert into public.work_logs (tenant_id, user_id, task_id, started_at, duration_seconds, billable)
  values ('${TENANT}', '${ALICE}', '${TASK}', '2026-03-02T09:00:00Z', 3600, true),
    ('${TENANT}', '${ALICE}', '${OTHER_TASK}', '2026-03-02T11:00:00Z', 1800, true);
  insert into public.work_logs (tenant_id, user_id, task_id, started_at, timer_started_at, billable)
  values ('${TENANT}', '${ALICE}', '${TASK}', '2026-03-03T09:00:00Z', '2026-03-03T09:00:00Z', true);
  perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform better_supabase.set_time_rate('${TENANT}', 12000, 'EUR', null, 'task', '${TASK}', '2026-01-01');
  v_time := better_supabase.unbilled_time('${TENANT}', jsonb_build_object('subject', jsonb_build_object('type', 'task', 'id', '${TASK}')));
  if jsonb_array_length(v_time -> 'lines') <> 1
    or (v_time -> 'lines' -> 0 ->> 'quantity')::numeric <> 1
    or v_time -> 'lines' -> 0 ->> 'subjectType' <> 'task'
    or v_time -> 'lines' -> 0 ->> 'subjectId' <> '${TASK}' then
    raise exception 'unbilled %', v_time;
  end if;
  v_time := better_supabase.unbilled_time('${TENANT}');
  if jsonb_array_length(v_time -> 'lines') <> 1 or jsonb_array_length(v_time -> 'unrated') <> 1 then
    raise exception 'all %', v_time;
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );
});
