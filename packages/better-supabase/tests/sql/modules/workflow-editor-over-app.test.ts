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
create schema if not exists extensions;
`;

// The app's own definition, run, node run, grant and opt-out tables: renamed
// columns, enum statuses and grant kinds, and no scope, fork, subject, mode
// or trigger node columns.
const APP = `
create type public.job_state as enum ('queued', 'running', 'waiting', 'completed', 'failed', 'cancelled');
create type public.step_state as enum ('running', 'waiting', 'completed', 'failed', 'skipped');
create type public.grantee_kind as enum ('user', 'team', 'role');
create type public.grant_action as enum ('run', 'edit');

create table public.flows (
  id uuid primary key default gen_random_uuid(),
  org_id uuid,
  handle text not null,
  title text not null,
  description text,
  restricted boolean not null default false,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (org_id, handle)
);

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
  principal_id text
);

create table public.job_steps (
  job_id uuid not null references public.jobs (id) on delete cascade,
  step text not null,
  state public.step_state not null,
  attempts integer not null default 0,
  output jsonb,
  error text,
  started_at timestamptz,
  ended_at timestamptz,
  primary key (job_id, step)
);

create table public.flow_access (
  id uuid primary key default gen_random_uuid(),
  flow_id uuid not null references public.flows (id) on delete cascade,
  grantee_kind public.grantee_kind not null,
  grantee_id text not null,
  action public.grant_action not null,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table public.flow_opt_outs (
  org_id uuid not null,
  flow_id uuid not null references public.flows (id) on delete cascade,
  created_by uuid,
  created_at timestamptz not null default now(),
  primary key (org_id, flow_id)
);
`;

const OWN_TABLES = {
  "public.flows": "app.sql",
  "public.jobs": "app.sql",
  "public.job_steps": "app.sql",
  "public.flow_access": "app.sql",
  "public.flow_opt_outs": "app.sql",
};

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
  "workflow-editor": {
    tables: {
      definitions: "public.flows",
      nodeRuns: "public.job_steps",
      grants: "public.flow_access",
      optOuts: "public.flow_opt_outs",
    },
    columns: {
      definitions: {
        tenant: "org_id",
        slug: "handle",
        name: "title",
        subjectTypes: null,
        scope: null,
        forkedFrom: null,
        forkedFromVersion: null,
      },
      nodeRuns: { run: "job_id", node: "step", status: "state" },
      grants: {
        definition: "flow_id",
        principalKind: "grantee_kind",
        principalId: "grantee_id",
      },
      optOuts: { tenant: "org_id", definition: "flow_id" },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const GRAPH = `'{"nodes": [{"id": "start", "kind": "trigger"}], "edges": []}'::jsonb`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(check: string): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "workflows", "workflow-editor"],
    { modules: BLOCKS, ownTables: OWN_TABLES },
  );

  await using stack = await liteStack({
    driver: "pglite",
    migrations: [
      ROLES,
      APP,
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

describe("workflow-editor over the app's tables", BOOT, () => {
  it("saves, publishes, starts, records and lists a run, then opts out", async () => {
    await expect(
      run(`do $$
declare
  v_def jsonb;
  v_id uuid;
  v_draft jsonb;
  v_target jsonb;
  v_run uuid;
  v_list jsonb;
begin
  ${SERVICE}
  v_def := better_supabase.save_workflow_definition('${TENANT}', 'onboard', 'Onboard');
  v_id := (v_def ->> 'id')::uuid;
  if v_def ->> 'scope' <> 'tenant' or v_def -> 'subjectTypes' <> '[]'::jsonb or v_def -> 'forkedFrom' <> 'null'::jsonb then
    raise exception 'saved %', v_def;
  end if;
  v_draft := better_supabase.save_workflow_draft(v_id, ${GRAPH});
  perform better_supabase.publish_workflow_version((v_draft ->> 'id')::uuid, '{"engine": "test"}'::jsonb);
  v_target := better_supabase.workflow_start_target(v_id);
  if v_target is null then
    raise exception 'no start target';
  end if;
  perform better_supabase.set_workflow_definition_grant(v_id, 'user', '22222222-2222-4222-8222-222222222222', 'run');
  perform better_supabase.set_workflow_definition_grant(v_id, 'user', '22222222-2222-4222-8222-222222222222', 'run');
  if (select count(*) from public.flow_access where flow_id = v_id) <> 1 then
    raise exception 'grants %', (select count(*) from public.flow_access where flow_id = v_id);
  end if;
  perform better_supabase.set_workflow_definition_grant(v_id, 'user', '22222222-2222-4222-8222-222222222222', 'run', false);
  if exists (select 1 from public.flow_access where flow_id = v_id) then
    raise exception 'the grant was not revoked';
  end if;

  v_run := better_supabase.record_workflow_run('test', 'run-1', v_id::text, 'running', '${TENANT}');
  perform better_supabase.record_workflow_node_run('run-1', 'start', 'running', 1);
  perform better_supabase.record_workflow_node_run('run-1', 'start', 'completed', 1, '{"ok": true}'::jsonb);
  perform better_supabase.record_workflow_run('test', 'run-1', v_id::text, 'completed', '${TENANT}');
  if (select state from public.job_steps where job_id = v_run and step = 'start') <> 'completed'
    or (select state from public.jobs where id = v_run) <> 'completed' then
    raise exception 'statuses are wrong';
  end if;
  v_list := better_supabase.workflow_runs_list('${TENANT}', v_id::text);
  if jsonb_array_length(v_list) <> 1 or v_list -> 0 ->> 'status' <> 'completed' then
    raise exception 'listed %', v_list;
  end if;

  if not better_supabase.set_workflow_opt_out('${TENANT}', v_id) then
    raise exception 'did not opt out';
  end if;
  if not exists (select 1 from public.flow_opt_outs where org_id = '${TENANT}' and flow_id = v_id) then
    raise exception 'no opt-out row';
  end if;
  v_list := better_supabase.workflow_definitions_list('${TENANT}');
  if jsonb_array_length(v_list) <> 1 or (v_list -> 0 ->> 'optedOut')::boolean is not true or (v_list -> 0 ->> 'behind')::boolean then
    raise exception 'definitions %', v_list;
  end if;
end;
$$;`),
    ).resolves.toBeUndefined();
  });

  it("refuses system definitions, forks and test runs the app's tables have no columns for", async () => {
    await expect(
      run(`do $$
declare
  v_id uuid;
  v_hint text;
begin
  ${SERVICE}
  v_id := (better_supabase.save_workflow_definition('${TENANT}', 'onboard', 'Onboard') ->> 'id')::uuid;
  begin
    perform better_supabase.save_workflow_definition(null, 'shared', 'Shared', scope => 'system');
    raise exception 'saved a system definition';
  exception when invalid_parameter_value then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'WORKFLOW_SCOPE_UNSUPPORTED' then raise; end if;
  end;
  begin
    perform better_supabase.fork_workflow_definition(v_id, '${TENANT}', 'copy');
    raise exception 'forked a definition';
  exception when invalid_parameter_value then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'WORKFLOW_FORK_UNSUPPORTED' then raise; end if;
  end;
  begin
    perform better_supabase.start_test_run(v_id);
    raise exception 'started a test run';
  exception when invalid_parameter_value then
    get stacked diagnostics v_hint = pg_exception_hint;
    if v_hint <> 'WORKFLOW_TEST_UNSUPPORTED' then raise; end if;
  end;
end;
$$;`),
    ).resolves.toBeUndefined();
  });
});
