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

// The app's versions, triggers, webhook tokens, credentials, step library,
// alerts and alert fires: enum statuses, kinds and events, a version status
// without a default, credential key columns named like the function's
// parameters, no step description and no primary key on the alert fires.
const BUILDER = `
create type public.version_state as enum ('draft', 'published', 'archived');
create type public.version_owner as enum ('user', 'organization');
create type public.hook_kind as enum ('manual', 'webhook', 'schedule', 'form', 'chat');
create type public.alert_event as enum ('failed', 'slow');

create table public.flow_versions (
  id uuid primary key default gen_random_uuid(),
  flow_id uuid not null references public.flows (id) on delete cascade,
  version integer not null,
  graph jsonb not null,
  compiled jsonb,
  state public.version_state not null,
  owner_kind public.version_owner,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table public.flow_hooks (
  id uuid primary key default gen_random_uuid(),
  flow_id uuid not null references public.flows (id) on delete cascade,
  kind public.hook_kind not null,
  config jsonb not null default '{}'::jsonb,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.hook_tokens (
  token_hash bytea primary key,
  trigger_id uuid not null references public.flow_hooks (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.flow_secrets (
  id uuid primary key default gen_random_uuid(),
  tenant uuid,
  kind text not null,
  name text not null,
  ref jsonb not null,
  scopes text[] not null default '{}',
  created_by uuid,
  created_at timestamptz not null default now()
);

create table public.step_catalog (
  name text primary key,
  title text not null,
  input_schema jsonb not null default '{}'::jsonb,
  output_schema jsonb not null default '{}'::jsonb,
  credential_kind text,
  operation text,
  updated_at timestamptz not null default now()
);

create table public.flow_alerts (
  id uuid primary key default gen_random_uuid(),
  flow_id uuid not null references public.flows (id) on delete cascade,
  on_event public.alert_event not null,
  threshold interval,
  channel jsonb not null default '{}'::jsonb,
  created_by uuid,
  created_at timestamptz not null default now()
);

create table public.flow_alert_fires (
  alert_id uuid not null references public.flow_alerts (id) on delete cascade,
  run_id uuid not null references public.jobs (id) on delete cascade,
  fired_at timestamptz not null default now()
);
`;

const BUILDER_TABLES = {
  ...OWN_TABLES,
  "public.flow_versions": "app.sql",
  "public.flow_hooks": "app.sql",
  "public.hook_tokens": "app.sql",
  "public.flow_secrets": "app.sql",
  "public.step_catalog": "app.sql",
  "public.flow_alerts": "app.sql",
  "public.flow_alert_fires": "app.sql",
};

const EDITOR = BLOCKS["workflow-editor"];

const BUILDER_BLOCKS: AnyBlocksConfig = {
  ...BLOCKS,
  "workflow-editor": {
    ...EDITOR,
    tables: {
      ...EDITOR?.tables,
      versions: "public.flow_versions",
      triggers: "public.flow_hooks",
      webhookTokens: "public.hook_tokens",
      credentials: "public.flow_secrets",
      steps: "public.step_catalog",
      alerts: "public.flow_alerts",
      alertFires: "public.flow_alert_fires",
    },
    columns: {
      ...EDITOR?.columns,
      versions: { definition: "flow_id", status: "state" },
      triggers: { definition: "flow_id" },
      credentials: { tenant: "tenant", ref: "ref" },
      steps: { description: null },
      alerts: { definition: "flow_id" },
    },
  },
};

const SERVICE = `perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform set_config('request.jwt.claim.role', 'service_role', true);`;

const GRAPH = `'{"nodes": [{"id": "start", "kind": "trigger"}], "edges": []}'::jsonb`;

/** Lite migrates and seeds PGlite in process; booting takes a second or more. */
const BOOT = { timeout: 60_000 };

async function run(
  check: string,
  app = APP,
  modules = BLOCKS,
  ownTables: Readonly<Record<string, string>> = OWN_TABLES,
): Promise<void> {
  const files = renderBlocks(
    ["memberships", "permissions", "workflows", "workflow-editor"],
    { modules, ownTables },
  );

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

  it("publishes versions, keeps triggers, credentials, steps and alerts in the app's tables", async () => {
    await expect(
      run(
        `do $$
declare
  v_id uuid;
  v_first uuid;
  v_second uuid;
  v_trigger uuid;
  v_token text;
  v_alert uuid;
  v_job uuid;
  v_fired integer;
begin
  ${SERVICE}
  v_id := (better_supabase.save_workflow_definition('${TENANT}', 'onboard', 'Onboard') ->> 'id')::uuid;
  v_first := (better_supabase.save_workflow_draft(v_id, ${GRAPH}) ->> 'id')::uuid;
  perform better_supabase.publish_workflow_version(v_first, '{"engine": "test"}'::jsonb);
  v_second := (better_supabase.save_workflow_draft(v_id, ${GRAPH}) ->> 'id')::uuid;
  perform better_supabase.publish_workflow_version(v_second, '{"engine": "test"}'::jsonb);
  if (select state from public.flow_versions where id = v_first) <> 'archived'
    or (select state from public.flow_versions where id = v_second) <> 'published'
    or (select owner_kind from public.flow_versions where id = v_second) <> 'organization' then
    raise exception 'versions %', (select jsonb_agg(to_jsonb(x)) from public.flow_versions x);
  end if;

  v_trigger := (better_supabase.save_workflow_trigger(v_id, 'manual') ->> 'id')::uuid;
  perform better_supabase.save_workflow_trigger(v_id, 'webhook', trigger => v_trigger);
  v_token := better_supabase.rotate_workflow_webhook_token(v_trigger);
  if (select kind from public.flow_hooks where id = v_trigger) <> 'webhook'
    or better_supabase.workflow_webhook_target(v_token) is null then
    raise exception 'the webhook trigger does not resolve';
  end if;

  perform better_supabase.save_workflow_credential('${TENANT}', 'api', 'main', '{"provider": "vault", "tenant": "${TENANT}"}'::jsonb);
  perform better_supabase.save_workflow_credential('${TENANT}', 'api', 'main', '{"provider": "vault", "tenant": "${TENANT}", "v": 2}'::jsonb);
  perform better_supabase.save_workflow_credential(null, 'api', 'shared', '{"provider": "vault"}'::jsonb);
  perform better_supabase.save_workflow_credential(null, 'api', 'shared', '{"provider": "vault"}'::jsonb);
  if (select count(*) from public.flow_secrets) <> 2
    or (select ref ->> 'v' from public.flow_secrets where name = 'main') <> '2' then
    raise exception 'credentials %', (select jsonb_agg(to_jsonb(x)) from public.flow_secrets x);
  end if;

  perform better_supabase.sync_workflow_steps('{"send": {"title": "Send", "description": "Sends"}}'::jsonb);
  if better_supabase.sync_workflow_steps('{"send": {"title": "Send it"}}'::jsonb) <> 1 then
    raise exception 'the step library is not one step';
  end if;
  if (select title from public.step_catalog where name = 'send') <> 'Send it' then
    raise exception 'steps %', (select jsonb_agg(to_jsonb(x)) from public.step_catalog x);
  end if;

  v_alert := (better_supabase.save_workflow_alert(v_id, 'slow', threshold => interval '1 minute') ->> 'id')::uuid;
  perform better_supabase.save_workflow_alert(v_id, 'failed');
  if (select on_event from public.flow_alerts where id = v_alert) <> 'slow' then
    raise exception 'the alert event is wrong';
  end if;
  insert into public.jobs (runner, runner_ref, workflow, org_id, state, attributes, created_at)
  values ('test', 'slow-1', v_id::text, '${TENANT}', 'running', jsonb_build_object('bsb.definition', v_id::text), now() - interval '1 hour')
  returning id into v_job;
  v_fired := better_supabase.check_workflow_alerts();
  if v_fired <> 1 or better_supabase.check_workflow_alerts() <> 0 then
    raise exception 'slow alerts fired %', v_fired;
  end if;
  update public.jobs set state = 'failed' where id = v_job;
  if (select count(*) from public.flow_alert_fires where run_id = v_job) <> 2 then
    raise exception 'fires %', (select count(*) from public.flow_alert_fires where run_id = v_job);
  end if;
end;
$$;`,
        `${APP}${BUILDER}`,
        BUILDER_BLOCKS,
        BUILDER_TABLES,
      ),
    ).resolves.toBeUndefined();
  });
});
