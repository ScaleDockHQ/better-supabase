import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const TASK = "66666666-6666-4666-8666-666666666666";
const OTHER_TASK = "77777777-7777-4777-8777-777777777777";

// The app's work log: one foreign key per record type, a start with a
// duration instead of an end, and a currency that is always set.
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
  rate_currency text not null default 'EUR',
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
    options: { approvals: false, overlap: "allow", timers: "many" },
  },
};

const AS_ALICE = `perform set_config('request.jwt.claims', '{"sub":"${ALICE}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${ALICE}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const render = (blocks: AnyBlocksConfig = BLOCKS) =>
  renderBlocks(["time-tracking"], {
    modules: blocks,
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

describe("time tracking over a weekly grid's work log", () => {
  it(
    "logs overlapping time, runs several timers, resumes one and keeps a currency without a rate",
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
  v_first uuid;
  v_second uuid;
  v_entry jsonb;
begin
  ${AS_ALICE}
  perform better_supabase.log_time('${TENANT}', '2026-03-02T08:00:00Z', '2026-03-02T09:00:00Z', 'task', '${TASK}', false, null, 'EUR');
  perform better_supabase.log_time('${TENANT}', '2026-03-02T08:00:00Z', '2026-03-02T10:00:00Z', 'task', '${OTHER_TASK}', false, null, 'EUR');
  if (select count(*) from public.work_logs where started_at = '2026-03-02T08:00:00Z') <> 2 then
    raise exception 'overlapping entries were not both logged';
  end if;
  begin
    perform better_supabase.log_time('${TENANT}', '2026-03-03T08:00:00Z', '2026-03-03T09:00:00Z', 'task', '${TASK}', false, 100, null);
    raise exception 'a rate without a currency was accepted';
  exception when others then
    if sqlerrm = 'a rate without a currency was accepted' then
      raise;
    end if;
  end;
  v_first := (better_supabase.start_timer('${TENANT}', 'task', '${TASK}', false, null, 'EUR') ->> 'id')::uuid;
  v_second := (better_supabase.start_timer('${TENANT}', 'task', '${OTHER_TASK}', false, null, 'EUR') ->> 'id')::uuid;
  if jsonb_array_length(better_supabase.running_timers('${TENANT}')) <> 2 then
    raise exception 'running %', better_supabase.running_timers('${TENANT}');
  end if;
  perform better_supabase.stop_timer('${TENANT}', v_first);
  if (select timer_started_at from public.work_logs where id = v_second) is null
    or (select timer_started_at from public.work_logs where id = v_first) is not null then
    raise exception 'stopped the wrong timer';
  end if;
  update public.work_logs set duration_seconds = 600 where id = v_first;
  v_entry := better_supabase.resume_timer(v_first);
  if (select timer_started_at from public.work_logs where id = v_first) is null then
    raise exception 'not resumed %', v_entry;
  end if;
  update public.work_logs set timer_started_at = now() - interval '300 seconds' where id = v_first;
  perform better_supabase.stop_timer('${TENANT}', v_first);
  if (select duration_seconds from public.work_logs where id = v_first) not between 900 and 905
 then
    raise exception 'resumed segment %', (select duration_seconds from public.work_logs where id = v_first);
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it("refuses overlaps by default and several timers that would overlap", () => {
    const refuse = render({
      "time-tracking": {
        ...BLOCKS["time-tracking"],
        options: { approvals: false },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(refuse).toContain("TIME_ENTRY_OVERLAP");
    expect(() =>
      render({
        "time-tracking": {
          ...BLOCKS["time-tracking"],
          options: { approvals: false, timers: "many" },
        },
      }),
    ).toThrow(/overlap/);
  });
});
