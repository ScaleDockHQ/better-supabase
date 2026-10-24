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

async function run(check: string, app = APP, blocks = BLOCKS): Promise<void> {
  const files = renderBlocks(["workflows"], {
    modules: blocks,
    ownTables: OWN_TABLES,
  });

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
});
