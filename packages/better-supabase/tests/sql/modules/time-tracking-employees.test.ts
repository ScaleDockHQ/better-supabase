import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";
const ALICE = "22222222-2222-4222-8222-222222222222";
const BOB = "33333333-3333-4333-8333-333333333333";
const ALICE_EMPLOYEE = "44444444-4444-4444-8444-444444444444";
const CREW = "55555555-5555-4555-8555-555555555555";
const TASK = "66666666-6666-4666-8666-666666666666";
const CUSTOMER = "77777777-7777-4777-8777-777777777777";

const SETUP = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
create type public.sheet_state as enum ('draft', 'submitted', 'approved', 'returned');
create table public.tasks (id uuid primary key, tenant_id uuid not null);
create table public.customers (id uuid primary key, tenant_id uuid not null);
create table public.work_entries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  user_id uuid,
  employee_id uuid not null,
  task_id uuid references public.tasks (id) on delete cascade,
  customer_id uuid references public.customers (id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz,
  billable boolean not null default false,
  rate bigint,
  rate_currency text,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(task_id, customer_id) <= 1)
);
create table public.week_sheets (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  employee_id uuid not null,
  week date not null,
  note text,
  submitted_at timestamptz,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  state public.sheet_state not null default 'draft',
  decided_by uuid,
  decided_at timestamptz,
  decision_note text,
  unique (tenant_id, employee_id, week)
);
`;

const ALLOW = `
create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean language sql stable as $$
  select case
    when permission in ('time_tracking.approve', 'time_tracking.manage', 'time_tracking.read')
      then coalesce(current_setting('request.jwt.claim.sub', true), '') = '${BOB}'
    else true
  end
$$;
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid language sql stable as $$ select '${TENANT}'::uuid $$;
insert into auth.users (id) values ('${ALICE}'), ('${BOB}') on conflict do nothing;
insert into better_supabase.memberships (organization_id, user_id, role)
  select '${TENANT}', u, 'member' from unnest(array['${ALICE}', '${BOB}']::uuid[]) u
  on conflict do nothing;
insert into better_supabase.employees (id, tenant_id, user_id, name)
  values ('${ALICE_EMPLOYEE}', '${TENANT}', '${ALICE}', 'Alice'), ('${CREW}', '${TENANT}', null, 'Crew member');
insert into public.tasks (id, tenant_id) values ('${TASK}', '${TENANT}');
insert into public.customers (id, tenant_id) values ('${CUSTOMER}', '${TENANT}');
`;

const as = (
  user: string,
) => `perform set_config('request.jwt.claims', '{"sub":"${user}","role":"authenticated"}', true);
  perform set_config('request.jwt.claim.sub', '${user}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);`;

const BLOCKS: AnyBlocksConfig = {
  "time-tracking": {
    tables: {
      entries: "public.work_entries",
      timesheets: "public.week_sheets",
    },
    columns: {
      entries: { subjectType: null, subjectId: null },
      timesheets: { approval: null, user: null, status: "state" },
    },
    values: { timesheets: { status: { open: "draft", rejected: "returned" } } },
    on: {
      task: {
        table: "public.tasks",
        idType: "uuid",
        tenant: "tenant_id",
        column: "task_id",
      },
      customer: {
        table: "public.customers",
        idType: "uuid",
        tenant: "tenant_id",
        column: "customer_id",
      },
    },
    options: { approvals: false, owner: "employee" },
  },
};

const OWN_TABLES = {
  "public.work_entries": "app.sql",
  "public.week_sheets": "app.sql",
};

const render = (modules: AnyBlocksConfig = BLOCKS) =>
  renderBlocks(["time-tracking", "employees"], {
    modules,
    ownTables: OWN_TABLES,
  });

const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
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
      check,
    ],
  });

  expect(stack.url).not.toBe("");
}

describe("time tracking per employee with a column per record type", () => {
  it("refuses the employee owner without the status mode", () => {
    expect(() =>
      render({
        "time-tracking": {
          ...BLOCKS["time-tracking"],
          options: { owner: "employee" },
        },
      }),
    ).toThrow(/approvals: false/u);
  });

  it("refuses null subject columns unless every record type has a column", () => {
    expect(() =>
      render({
        "time-tracking": {
          ...BLOCKS["time-tracking"],
          on: {
            task: {
              table: "public.tasks",
              idType: "uuid",
              tenant: "tenant_id",
              column: "task_id",
            },
            customer: {
              table: "public.customers",
              idType: "uuid",
              tenant: "tenant_id",
            },
          },
        },
      }),
    ).toThrow(/subjectType and subjectId can be null only together/u);
  });

  it("refuses a null timesheet user without the employee owner", () => {
    expect(() =>
      render({
        "time-tracking": {
          ...BLOCKS["time-tracking"],
          options: { approvals: false },
        },
      }),
    ).toThrow(/timesheets.user can be null only/u);
  });

  it("renders employee-owned managed tables with foreign keys to employees", () => {
    const sql = renderBlocks(["time-tracking", "employees"], {
      modules: {
        "time-tracking": {
          columns: { timesheets: { user: null } },
          options: { approvals: false, owner: "employee" },
        },
      },
    })
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('"employee_id" uuid not null');
    expect(sql).toContain('unique ("tenant_id", "employee_id", "week")');
    expect(sql).toContain("time_is_my_employee");
    expect(sql).toContain("time_entries_employee_fkey");
    expect(sql).toContain("timesheets_employee_fkey");
    expect(sql).not.toContain("bsb_time_entries_employee_sync");
  });

  it("refuses an unknown owner, a missing employees block and record columns on managed tables", () => {
    expect(() =>
      renderBlocks(["time-tracking"], {
        modules: { "time-tracking": { options: { owner: "team" } } },
      }),
    ).toThrow(/owner must be/u);
    expect(() =>
      renderBlocks(["time-tracking"], {
        modules: {
          "time-tracking": { options: { approvals: false, owner: "employee" } },
        },
      }),
    ).toThrow(/needs the employees block/u);
    expect(() =>
      renderBlocks(["time-tracking"], {
        modules: {
          "time-tracking": {
            on: {
              task: {
                table: "public.tasks",
                idType: "uuid",
                column: "task_id",
              },
            },
          },
        },
      }),
    ).toThrow(/column of your own entries table/u);
    expect(() =>
      render({
        "time-tracking": {
          ...BLOCKS["time-tracking"],
          columns: {
            entries: { subjectType: null, subjectId: null, employee: null },
            timesheets: { approval: null, user: null, status: "state" },
          },
        },
      }),
    ).toThrow(/can't be null/u);
  });

  it(
    "tracks on typed record columns and keeps timesheets for an employee without an account",
    BOOT,
    async () => {
      await expect(
        run(`do $$
declare
  v_entry jsonb;
  v_sheet jsonb;
  v_list jsonb;
  v_hint text;
begin
  ${as(ALICE)}
  v_entry := better_supabase.start_timer('${TENANT}', 'task', '${TASK}');
  if v_entry ->> 'subjectType' <> 'task' or v_entry ->> 'subjectId' <> '${TASK}'
    or v_entry ->> 'employeeId' <> '${ALICE_EMPLOYEE}' then
    raise exception 'timer %', v_entry;
  end if;
  if (select task_id from public.work_entries where id = (v_entry ->> 'id')::uuid) <> '${TASK}'::uuid then
    raise exception 'task_id not set';
  end if;
  perform better_supabase.stop_timer('${TENANT}');
  v_entry := better_supabase.update_time_entry((v_entry ->> 'id')::uuid, jsonb_build_object('subjectType', 'customer', 'subjectId', '${CUSTOMER}'));
  if (select task_id from public.work_entries where id = (v_entry ->> 'id')::uuid) is not null
    or (select customer_id from public.work_entries where id = (v_entry ->> 'id')::uuid) <> '${CUSTOMER}'::uuid
    or v_entry ->> 'subjectType' <> 'customer' then
    raise exception 'moved %', v_entry;
  end if;
  v_list := better_supabase.list_time_entries('${TENANT}', subject_type => 'customer', subject_id => '${CUSTOMER}');
  if jsonb_array_length(v_list) <> 1 then
    raise exception 'list %', v_list;
  end if;
  begin
    perform better_supabase.log_time('${TENANT}', '2026-03-02T09:00:00Z', '2026-03-02T10:00:00Z', employee_id => '${CREW}');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TIME_FORBIDDEN' then
    raise exception 'logged for another employee without manage: %', v_hint;
  end if;
  ${as(BOB)}
  begin
    perform better_supabase.start_timer('${TENANT}');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TIME_EMPLOYEE_MISSING' then
    raise exception 'timer without an employee record: %', v_hint;
  end if;
  v_entry := better_supabase.log_time('${TENANT}', '2026-03-02T09:00:00Z', '2026-03-02T10:00:00Z', 'task', '${TASK}', employee_id => '${CREW}');
  if v_entry ->> 'employeeId' <> '${CREW}' or v_entry ->> 'userId' is not null then
    raise exception 'crew entry %', v_entry;
  end if;
  v_sheet := better_supabase.submit_timesheet('${TENANT}', '2026-03-02', null, '${CREW}');
  if v_sheet ->> 'status' <> 'submitted' or v_sheet ->> 'employeeId' <> '${CREW}'
    or (select state::text from public.week_sheets where employee_id = '${CREW}') <> 'submitted' then
    raise exception 'submit %', v_sheet;
  end if;
  begin
    perform better_supabase.log_time('${TENANT}', '2026-03-03T09:00:00Z', '2026-03-03T10:00:00Z', employee_id => '${CREW}');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TIME_PERIOD_LOCKED' then
    raise exception 'a submitted week is locked: %', v_hint;
  end if;
  v_sheet := better_supabase.get_timesheet('${TENANT}', '2026-03-02', employee_id => '${CREW}');
  if jsonb_array_length(v_sheet -> 'entries') <> 1 or (v_sheet -> 'totals' ->> 'seconds')::bigint <> 3600 then
    raise exception 'week %', v_sheet;
  end if;
  v_sheet := better_supabase.reject_timesheet((v_sheet ->> 'id')::uuid, 'wrong task');
  if (select state::text from public.week_sheets where employee_id = '${CREW}') <> 'returned' then
    raise exception 'reject %', v_sheet;
  end if;
  v_list := better_supabase.list_timesheets('${TENANT}', employee_id => '${CREW}');
  if jsonb_array_length(v_list) <> 1 or v_list -> 0 ->> 'status' <> 'rejected' then
    raise exception 'timesheets %', v_list;
  end if;
  ${as(ALICE)}
  begin
    perform better_supabase.get_timesheet('${TENANT}', '2026-03-02', employee_id => '${CREW}');
    v_hint := 'none';
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  if v_hint <> 'TIME_FORBIDDEN' then
    raise exception 'read another employee''s week: %', v_hint;
  end if;
end;
$$;`),
      ).resolves.toBeUndefined();
    },
  );
});
