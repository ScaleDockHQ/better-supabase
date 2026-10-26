import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";

// The app's own tables, so the run needs no btree_gist exclusion (PGlite has
// no btree_gist): an enum status whose labels differ from the block's.
const SETUP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create type public.sheet_status as enum ('draft', 'submitted', 'approved', 'returned');
create table public.profiles (id uuid primary key, timezone text);
create table public.time_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid not null,
  subject_type text,
  subject_id text,
  started_at timestamptz not null,
  ended_at timestamptz,
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
  status public.sheet_status not null default 'draft',
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  unique (tenant_id, user_id, week)
);
`;

// Alice tracks; Bob approves.
const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select permission <> 'time_tracking.approve'
    or coalesce(current_setting('request.jwt.claim.sub', true), '') = '${BOB}'
$$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${ALICE}', '${BOB}']::uuid[]) u
  on conflict do nothing;
insert into public.profiles (id, timezone) values ('${ALICE}', 'Pacific/Auckland');
`;

const as = (
  user: string,
) => `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BLOCKS: AnyBlocksConfig = {
  "time-tracking": {
    tables: { entries: "public.time_entries", timesheets: "public.timesheets" },
    columns: { timesheets: { approval: null } },
    values: { timesheets: { status: { open: "draft", rejected: "returned" } } },
    options: {
      approvals: false,
      timeZone: "UTC",
      userTimeZone: { column: "public.profiles.timezone" },
    },
  },
};

const render = (modules: AnyBlocksConfig = BLOCKS) =>
  renderBlocks(["time-tracking"], {
    modules,
    ownTables: {
      "public.time_entries": "app.sql",
      "public.timesheets": "app.sql",
    },
  });

describe("time tracking without approvals", () => {
  it("drops approvals from the dependencies and writes the status functions", () => {
    const files = render();
    const modules = new Set(files.map((file) => file.module));

    const sql = files
      .filter((file) => file.module === "time-tracking")
      .map((file) => file.contents)
      .join("\n");

    expect(modules.has("approvals")).toBe(false);
    expect(sql).toContain("reject_timesheet");
    expect(sql).toContain('"time_week"(at timestamptz, user_id uuid)');
    expect(sql).not.toContain("open_approval");
  });

  it("refuses the status mode without a status column", () => {
    expect(() =>
      render({
        "time-tracking": {
          ...BLOCKS["time-tracking"],
          columns: { timesheets: { approval: null, status: null } },
          values: {},
        },
      }),
    ).toThrow(/can't be null/u);
  });

  it(
    "submits, rejects, resubmits and approves a week in the user's own time zone",
    { timeout: 60_000 },
    async () => {
      const files = render().map((file) => ({
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
  v_sheet jsonb;
  v_hint text;
begin
  ${as(ALICE)}
  -- Monday 00:30 in Auckland is still Sunday in UTC.
  perform better_supabase.log_time('${TENANT}', '2026-03-01T11:30:00Z', '2026-03-01T12:30:00Z');
  if better_supabase.time_week('2026-03-01T11:30:00Z', '${ALICE}'::uuid) <> '2026-03-02' then
    raise exception 'week in the user''s zone';
  end if;
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2026-03-02');
  if v_sheet ->> 'status' <> 'submitted' then
    raise exception 'submit %', v_sheet;
  end if;
  begin
    perform better_supabase.log_time('${TENANT}', '2026-03-03T09:00:00Z', '2026-03-03T10:00:00Z');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TIME_PERIOD_LOCKED' then
    raise exception 'a submitted week is locked: %', v_hint;
  end if;
  begin
    perform better_supabase.approve_timesheet((v_sheet ->> 'id')::uuid);
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TIME_FORBIDDEN' then
    raise exception 'approved without the permission: %', v_hint;
  end if;
  ${as(BOB)}
  v_sheet := better_supabase.reject_timesheet((v_sheet ->> 'id')::uuid, 'missing Friday');
  if v_sheet ->> 'status' <> 'rejected' or (select status::text from public.timesheets) <> 'returned'
    or v_sheet ->> 'decisionNote' <> 'missing Friday' then
    raise exception 'reject %', v_sheet;
  end if;
  ${as(ALICE)}
  perform better_supabase.log_time('${TENANT}', '2026-03-06T09:00:00Z', '2026-03-06T10:00:00Z');
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2026-03-02');
  ${as(BOB)}
  v_sheet := better_supabase.approve_timesheet((v_sheet ->> 'id')::uuid);
  if v_sheet ->> 'status' <> 'approved' or v_sheet ->> 'approvedAt' is null then
    raise exception 'approve %', v_sheet;
  end if;
  if jsonb_array_length(better_supabase.list_timesheets('${TENANT}', null, 'approved')) <> 1 then
    raise exception 'list by status';
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it(
    "keeps entries as a start, a duration and a running mark",
    { timeout: 60_000 },
    async () => {
      const files = renderBlocks(["time-tracking"], {
        modules: {
          "time-tracking": {
            tables: {
              entries: "public.work_logs",
              timesheets: "public.timesheets",
            },
            columns: {
              entries: {
                endedAt: null,
                seconds: "duration_seconds",
                runningSince: "timer_started_at",
              },
              timesheets: { approval: null },
            },
            values: {
              timesheets: { status: { open: "draft", rejected: "returned" } },
            },
            options: { approvals: false },
          },
        },
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

      await using stack = await liteStack({
        driver: "pglite",
        migrations: [
          SETUP,
          `create table public.work_logs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid not null,
  subject_type text,
  subject_id text,
  started_at timestamptz not null,
  duration_seconds integer,
  timer_started_at timestamptz,
  billable boolean not null default false,
  rate bigint,
  rate_currency text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);`,
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
  v_entry jsonb;
  v_hint text;
begin
  ${as(ALICE)}
  v_entry := better_supabase.start_timer('${TENANT}');
  if v_entry ->> 'endedAt' is not null or (select timer_started_at from public.work_logs) is null then
    raise exception 'start %', v_entry;
  end if;
  if better_supabase.running_timer('${TENANT}') ->> 'id' <> v_entry ->> 'id' then
    raise exception 'running';
  end if;
  v_entry := better_supabase.stop_timer('${TENANT}');
  if v_entry ->> 'endedAt' is null or (select timer_started_at from public.work_logs) is not null
    or (select duration_seconds from public.work_logs) is null then
    raise exception 'stop %', v_entry;
  end if;
  v_entry := better_supabase.log_time('${TENANT}', '2026-03-02T09:00:00Z', '2026-03-02T10:30:00Z');
  if (v_entry ->> 'seconds')::int <> 5400 or v_entry ->> 'endedAt' is null then
    raise exception 'log %', v_entry;
  end if;
  begin
    perform better_supabase.log_time('${TENANT}', '2026-03-02T10:00:00Z', '2026-03-02T11:00:00Z');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TIME_ENTRY_OVERLAP' then
    raise exception 'overlap %', v_hint;
  end if;
  v_entry := better_supabase.update_time_entry((v_entry ->> 'id')::uuid, '{"endedAt": "2026-03-02T09:45:00Z"}');
  if (select duration_seconds from public.work_logs where id = (v_entry ->> 'id')::uuid) <> 2700 then
    raise exception 'update %', v_entry;
  end if;
  if (better_supabase.get_timesheet('${TENANT}', '2026-03-02') -> 'totals' ->> 'seconds')::int <> 2700 then
    raise exception 'totals %', better_supabase.get_timesheet('${TENANT}', '2026-03-02');
  end if;
end;
$$;`,
        ],
      });

      expect(stack.url).not.toBe("");
    },
  );

  it("refuses a null ended_at over the block's own table", () => {
    expect(() =>
      renderBlocks(["time-tracking"], {
        modules: {
          "time-tracking": { columns: { entries: { endedAt: null } } },
        },
      }),
    ).toThrow(/endedAt can be null only over your own entries table/u);
  });
});
