import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { liteStack } from "../../../src/testing/lite.ts";

const TENANT = "11111111-1111-4111-8111-111111111111";

const ROLES = `
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_auth_admin') then
    create role supabase_auth_admin;
  end if;
end;
$$;
`;

// The app's own runs table: renamed columns, an enum status, and no subject,
// mode or trigger node columns.
const APP = `
create type public.job_state as enum ('queued', 'running', 'waiting', 'completed', 'failed', 'cancelled');

create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  runner text not null,
  runner_ref text not null,
  workflow text not null,
  org_id uuid,
  started_by uuid,
  state public.job_state not null default 'queued',
  attributes jsonb not null default '{}'::jsonb,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  cancel_requested_at timestamptz,
  principal_kind text,
  principal_id text,
  notes text
);
`;

const OWN_TABLES = { "public.jobs": "app.sql" };

const BLOCKS: AnyBlocksConfig = {
  workflows: {
    tables: { runs: "public.jobs" },
    columns: {
      runs: {
        engine: "runner",
        externalId: "runner_ref",
        definition: "workflow",
        tenant: "org_id",
        actor: "started_by",
        status: "state",
        subjectType: null,
        subjectId: null,
        mode: null,
        triggerNode: null,
      },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

// An app runs table that keeps the module's column names, which are also the
// names of record_workflow_run's parameters.
const SAME_NAMES = `
create table public.jobs (
  id uuid primary key default gen_random_uuid(),
  engine text not null,
  external_id text not null,
  definition text not null,
  tenant_id uuid,
  actor_id uuid,
  status text not null default 'queued',
  attributes jsonb not null default '{}'::jsonb,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  cancel_requested_at timestamptz,
  principal_kind text,
  principal_id text
);
`;

const SAME_BLOCKS: AnyBlocksConfig = {
  workflows: {
    tables: { runs: "public.jobs" },
    columns: {
      runs: {
        subjectType: null,
        subjectId: null,
        mode: null,
        triggerNode: null,
      },
    },
  },
};

// The app's own schedules and start requests: the schedule key columns share
// create_workflow_schedule's parameter names, an enum request status, and no
// last run or subject columns.
const QUEUE = `
create type public.start_state as enum ('pending', 'started', 'superseded', 'dropped');

create table public.cron_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant uuid,
  name text not null,
  workflow text not null,
  input jsonb not null default '[]'::jsonb,
  cron text not null,
  timezone text not null default 'UTC',
  next_run_at timestamptz not null,
  locked_until timestamptz,
  paused boolean not null default false,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table public.start_queue (
  id uuid primary key default gen_random_uuid(),
  key text not null,
  workflow text not null,
  input jsonb not null default '[]'::jsonb,
  tenant_id uuid,
  actor_id uuid,
  concurrency integer,
  state public.start_state not null default 'pending',
  not_before timestamptz not null default now(),
  claimed_until timestamptz,
  run_id text,
  created_at timestamptz not null default now(),
  started_at timestamptz
);
`;

const QUEUE_TABLES = {
  "public.cron_jobs": "app.sql",
  "public.start_queue": "app.sql",
};

const QUEUE_BLOCKS: AnyBlocksConfig = {
  workflows: {
    tables: {
      schedules: "public.cron_jobs",
      startRequests: "public.start_queue",
    },
    columns: {
      schedules: { tenant: "tenant", lastRunAt: null },
      startRequests: { status: "state", subjectType: null, subjectId: null },
    },
  },
};

async function run(
  check: string,
  app = APP,
  blocks = BLOCKS,
  ownTables: Record<string, string> = OWN_TABLES,
): Promise<void> {
  const files = renderBlocks(["workflows"], { modules: blocks, ownTables });

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      app,
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

describe("workflows over the app's tables", BOOT, () => {
  it("records, updates and lists live runs in an enum status column", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_again uuid;
  v_list jsonb;
begin
  ${SERVICE}
  v_id := better_supabase.record_workflow_run('vercel', 'run-1', 'onboard', 'running', '${TENANT}', null, '{"bsb.trigger_node": "start"}'::jsonb);
  v_again := better_supabase.record_workflow_run('vercel', 'run-1', 'onboard', 'completed', '${TENANT}', completed_at => now());
  if v_again <> v_id or (select state from public.jobs where id = v_id) <> 'completed' then
    raise exception 'status is %', (select state from public.jobs where id = v_id);
  end if;
  v_list := better_supabase.workflow_runs_list('${TENANT}', status => 'completed');
  if jsonb_array_length(v_list) <> 1
    or v_list -> 0 ->> 'mode' <> 'live'
    or v_list -> 0 ->> 'triggerNode' <> 'start'
    or v_list -> 0 -> 'subjectType' <> 'null'::jsonb then
    raise exception 'listed %', v_list;
  end if;
  if jsonb_array_length(better_supabase.workflow_runs_list('${TENANT}', mode => 'test')) <> 0 then
    raise exception 'listed a test run';
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("updates a run when the app's columns share the parameters' names", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_again uuid;
begin
  ${SERVICE}
  v_id := better_supabase.record_workflow_run('vercel', 'run-1', 'onboard', 'running', '${TENANT}');
  v_again := better_supabase.record_workflow_run('vercel', 'run-1', 'onboard', 'failed', '${TENANT}', error => 'boom');
  if v_again <> v_id or (select status from public.jobs where id = v_id) <> 'failed' then
    raise exception 'the run was not updated';
  end if;
end;
$$;`,
        SAME_NAMES,
        SAME_BLOCKS,
      ),
    ).resolves.toBeUndefined();
  });

  it("records runs in a table without principal columns, reading the principal from attributes", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_list jsonb;
begin
  ${SERVICE}
  v_id := better_supabase.record_workflow_run('vercel', 'run-1', 'onboard', 'running', '${TENANT}', attributes => '{"bsb.principal_kind": "service_principal", "bsb.principal": "sp-1"}'::jsonb, principal_kind => 'user', principal_id => 'ignored');
  perform better_supabase.record_workflow_run('vercel', 'run-1', 'onboard', 'completed', '${TENANT}', completed_at => now());
  v_list := better_supabase.workflow_runs_list('${TENANT}');
  if jsonb_array_length(v_list) <> 1
    or v_list -> 0 ->> 'principalKind' <> 'service_principal'
    or v_list -> 0 ->> 'principalId' <> 'sp-1'
    or v_list -> 0 ->> 'status' <> 'completed' then
    raise exception 'listed %', v_list;
  end if;
end;
$$;`,
        SAME_NAMES.replace(
          "  principal_kind text,\n  principal_id text\n",
          "  notes text\n",
        ),
        {
          workflows: {
            tables: { runs: "public.jobs" },
            columns: {
              runs: {
                subjectType: null,
                subjectId: null,
                principalKind: null,
                principalId: null,
                mode: null,
                triggerNode: null,
              },
            },
          },
        },
      ),
    ).resolves.toBeUndefined();
  });

  it("refuses test runs and record links the app's table has no columns for", async () => {
    await expect(
      run(`do $$
declare
  v_hint text;
begin
  ${SERVICE}
  begin
    perform better_supabase.record_workflow_run('vercel', 'run-2', 'onboard', 'running', '${TENANT}', mode => 'test');
    raise exception 'recorded a test run';
  exception when invalid_parameter_value then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'WORKFLOW_MODE_UNSUPPORTED' then raise; end if;
  end;
  begin
    perform better_supabase.record_workflow_run('vercel', 'run-3', 'onboard', 'running', '${TENANT}', subject_type => 'deal', subject_id => 'd1');
    raise exception 'recorded a record link';
  exception when invalid_parameter_value then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'WORKFLOW_SUBJECT_UNSUPPORTED' then raise; end if;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("upserts schedules and admits starts in the app's tables", async () => {
    await expect(
      run(
        `do $$
declare
  v_first jsonb;
  v_again jsonb;
  v_claimed jsonb;
  v_request jsonb;
begin
  ${SERVICE}
  v_first := better_supabase.create_workflow_schedule('nightly', 'report', '0 2 * * *', now() - interval '1 minute', tenant => '${TENANT}');
  v_again := better_supabase.create_workflow_schedule('nightly', 'digest', '0 3 * * *', now() - interval '1 minute', tenant => '${TENANT}');
  if v_again ->> 'id' <> v_first ->> 'id' or (select count(*) from public.cron_jobs) <> 1 or v_again ->> 'workflow' <> 'digest' then
    raise exception 'upserted %', v_again;
  end if;
  v_claimed := better_supabase.claim_due_workflow_schedules();
  if jsonb_array_length(v_claimed) <> 1 or v_claimed -> 0 -> 'lastRunAt' <> 'null'::jsonb then
    raise exception 'claimed %', v_claimed;
  end if;
  if not better_supabase.advance_workflow_schedule((v_first ->> 'id')::uuid, (v_claimed -> 0 ->> 'fireAt')::timestamptz, now() + interval '1 day') then
    raise exception 'did not advance';
  end if;
  perform better_supabase.request_workflow_start('k', 'report', debounce => interval '0');
  v_request := better_supabase.request_workflow_start('k', 'report', debounce => interval '0');
  if (select count(*) from public.start_queue where state = 'superseded') <> 1 then
    raise exception 'did not supersede';
  end if;
  v_claimed := better_supabase.claim_workflow_start_requests();
  if jsonb_array_length(v_claimed) <> 1 or v_claimed -> 0 -> 'subjectType' <> 'null'::jsonb then
    raise exception 'claimed %', v_claimed;
  end if;
  if not better_supabase.mark_workflow_start_request((v_request ->> 'id')::uuid, 'run-9') then
    raise exception 'did not mark the request';
  end if;
  if (select state from public.start_queue where id = (v_request ->> 'id')::uuid) <> 'started' then
    raise exception 'did not mark the request started';
  end if;
end;
$$;`,
        QUEUE,
        QUEUE_BLOCKS,
        QUEUE_TABLES,
      ),
    ).resolves.toBeUndefined();
  });
});
