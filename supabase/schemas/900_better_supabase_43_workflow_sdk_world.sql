-- better-supabase module: workflow-sdk-world (0.5.1)
-- @bs-module workflow-sdk-world@1 managed
-- The tables of the Workflow SDK World (@workflow/world-postgres 5.0.2) in the workflow schema, closed to the API roles; a trigger that copies each run into workflow_runs, and a pg_net dispatcher for the delivery queue on a pg_cron schedule.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The Workflow SDK World's tables (@workflow/world-postgres 5.0.2).
-- Only the service role reads them: the app reads runs from workflow_runs in
-- the workflows module.
create schema if not exists workflow;

do $$ begin
  create type workflow.status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type workflow.step_status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type workflow.wait_status as enum ('waiting', 'completed');
exception when duplicate_object then null;
end $$;

create table if not exists workflow.workflow_event_slots (
  "run_id" character varying not null,
  constraint "workflow_event_slots_pkey" PRIMARY KEY (run_id)
);

alter table workflow.workflow_event_slots
  add column if not exists "run_id" character varying not null;

create table if not exists workflow.workflow_events (
  "id" character varying not null,
  "type" character varying not null,
  "correlation_id" character varying,
  "created_at" timestamp without time zone not null default now(),
  "run_id" character varying not null,
  "payload" jsonb,
  "payload_cbor" bytea,
  "spec_version" integer,
  "resume_id" character varying,
  "resume_payload_digest" character varying,
  constraint "workflow_events_run_id_id_pk" PRIMARY KEY (run_id, id)
);

alter table workflow.workflow_events
  add column if not exists "id" character varying not null,
  add column if not exists "type" character varying not null,
  add column if not exists "correlation_id" character varying,
  add column if not exists "created_at" timestamp without time zone not null default now(),
  add column if not exists "run_id" character varying not null,
  add column if not exists "payload" jsonb,
  add column if not exists "payload_cbor" bytea,
  add column if not exists "spec_version" integer,
  add column if not exists "resume_id" character varying,
  add column if not exists "resume_payload_digest" character varying;

create index if not exists workflow_events_correlation_id_index ON workflow.workflow_events USING btree (correlation_id);

create unique index if not exists workflow_events_entity_creation_unique ON workflow.workflow_events USING btree (run_id, correlation_id, type) WHERE ((type)::text = ANY ((ARRAY['step_created'::character varying, 'hook_created'::character varying, 'wait_created'::character varying, 'attr_set'::character varying])::text[]));

create unique index if not exists workflow_events_hook_resume_unique ON workflow.workflow_events USING btree (run_id, resume_id) WHERE (((type)::text = 'hook_received'::text) AND (resume_id IS NOT NULL));

create table if not exists workflow.workflow_hooks (
  "run_id" character varying not null,
  "hook_id" character varying not null,
  "token" character varying not null,
  "owner_id" character varying not null,
  "project_id" character varying not null,
  "environment" character varying not null,
  "created_at" timestamp without time zone not null default now(),
  "metadata" jsonb,
  "metadata_cbor" bytea,
  "spec_version" integer,
  "is_webhook" boolean default true,
  "is_system" boolean default false,
  "resume_context" bytea,
  "token_retention_until" timestamp with time zone,
  "claimed_from" bytea,
  constraint "workflow_hooks_pkey" PRIMARY KEY (hook_id)
);

alter table workflow.workflow_hooks
  add column if not exists "run_id" character varying not null,
  add column if not exists "hook_id" character varying not null,
  add column if not exists "token" character varying not null,
  add column if not exists "owner_id" character varying not null,
  add column if not exists "project_id" character varying not null,
  add column if not exists "environment" character varying not null,
  add column if not exists "created_at" timestamp without time zone not null default now(),
  add column if not exists "metadata" jsonb,
  add column if not exists "metadata_cbor" bytea,
  add column if not exists "spec_version" integer,
  add column if not exists "is_webhook" boolean default true,
  add column if not exists "is_system" boolean default false,
  add column if not exists "resume_context" bytea,
  add column if not exists "token_retention_until" timestamp with time zone,
  add column if not exists "claimed_from" bytea;

create index if not exists workflow_hooks_run_id_index ON workflow.workflow_hooks USING btree (run_id);

create index if not exists workflow_hooks_token_index ON workflow.workflow_hooks USING btree (token);

create table if not exists workflow.workflow_invocations (
  "sequence" bigserial,
  "run_id" character varying not null,
  "request_id" character varying not null,
  "payload" bytea,
  "fingerprint" character varying,
  "result" bytea,
  "created_at" timestamp without time zone not null default now(),
  "responded_at" timestamp without time zone,
  "expired_at" timestamp without time zone,
  "result_version" integer not null default 0,
  constraint "workflow_invocations_pkey" PRIMARY KEY (run_id, request_id)
);

alter table workflow.workflow_invocations
  add column if not exists "sequence" bigserial,
  add column if not exists "run_id" character varying not null,
  add column if not exists "request_id" character varying not null,
  add column if not exists "payload" bytea,
  add column if not exists "fingerprint" character varying,
  add column if not exists "result" bytea,
  add column if not exists "created_at" timestamp without time zone not null default now(),
  add column if not exists "responded_at" timestamp without time zone,
  add column if not exists "expired_at" timestamp without time zone,
  add column if not exists "result_version" integer not null default 0;

create index if not exists workflow_invocations_pending ON workflow.workflow_invocations USING btree (run_id, sequence) WHERE (responded_at IS NULL);

create table if not exists workflow.workflow_runs (
  "id" character varying not null,
  "output" jsonb,
  "deployment_id" character varying not null,
  "status" workflow.status not null,
  "name" character varying not null,
  "execution_context" jsonb,
  "input" jsonb,
  "error" text,
  "created_at" timestamp without time zone not null default now(),
  "updated_at" timestamp without time zone not null default now(),
  "completed_at" timestamp without time zone,
  "started_at" timestamp without time zone,
  "output_cbor" bytea,
  "execution_context_cbor" bytea,
  "input_cbor" bytea,
  "expired_at" timestamp without time zone,
  "spec_version" character varying,
  "error_cbor" bytea,
  "error_code" character varying,
  "attributes" jsonb not null default '{}'::jsonb,
  "encryption_public_key" character varying,
  "dynamic_workflow_code_cbor" bytea,
  constraint "workflow_runs_pkey" PRIMARY KEY (id)
);

alter table workflow.workflow_runs
  add column if not exists "id" character varying not null,
  add column if not exists "output" jsonb,
  add column if not exists "deployment_id" character varying not null,
  add column if not exists "status" workflow.status not null,
  add column if not exists "name" character varying not null,
  add column if not exists "execution_context" jsonb,
  add column if not exists "input" jsonb,
  add column if not exists "error" text,
  add column if not exists "created_at" timestamp without time zone not null default now(),
  add column if not exists "updated_at" timestamp without time zone not null default now(),
  add column if not exists "completed_at" timestamp without time zone,
  add column if not exists "started_at" timestamp without time zone,
  add column if not exists "output_cbor" bytea,
  add column if not exists "execution_context_cbor" bytea,
  add column if not exists "input_cbor" bytea,
  add column if not exists "expired_at" timestamp without time zone,
  add column if not exists "spec_version" character varying,
  add column if not exists "error_cbor" bytea,
  add column if not exists "error_code" character varying,
  add column if not exists "attributes" jsonb not null default '{}'::jsonb,
  add column if not exists "encryption_public_key" character varying,
  add column if not exists "dynamic_workflow_code_cbor" bytea;

create index if not exists workflow_runs_name_index ON workflow.workflow_runs USING btree (name);

create index if not exists workflow_runs_status_index ON workflow.workflow_runs USING btree (status);

create table if not exists workflow.workflow_snapshots (
  "run_id" character varying not null,
  "data" bytea not null,
  "events_cursor" character varying,
  "created_at" timestamp without time zone not null default now(),
  constraint "workflow_snapshots_pkey" PRIMARY KEY (run_id)
);

alter table workflow.workflow_snapshots
  add column if not exists "run_id" character varying not null,
  add column if not exists "data" bytea not null,
  add column if not exists "events_cursor" character varying,
  add column if not exists "created_at" timestamp without time zone not null default now();

create table if not exists workflow.workflow_steps (
  "run_id" character varying not null,
  "step_id" character varying not null,
  "step_name" character varying not null,
  "status" workflow.step_status not null,
  "input" jsonb,
  "output" jsonb,
  "error" text,
  "attempt" integer not null,
  "started_at" timestamp without time zone,
  "completed_at" timestamp without time zone,
  "created_at" timestamp without time zone not null default now(),
  "updated_at" timestamp without time zone not null default now(),
  "retry_after" timestamp without time zone,
  "input_cbor" bytea,
  "output_cbor" bytea,
  "error_cbor" bytea,
  "spec_version" integer,
  constraint "workflow_steps_pkey" PRIMARY KEY (step_id)
);

alter table workflow.workflow_steps
  add column if not exists "run_id" character varying not null,
  add column if not exists "step_id" character varying not null,
  add column if not exists "step_name" character varying not null,
  add column if not exists "status" workflow.step_status not null,
  add column if not exists "input" jsonb,
  add column if not exists "output" jsonb,
  add column if not exists "error" text,
  add column if not exists "attempt" integer not null,
  add column if not exists "started_at" timestamp without time zone,
  add column if not exists "completed_at" timestamp without time zone,
  add column if not exists "created_at" timestamp without time zone not null default now(),
  add column if not exists "updated_at" timestamp without time zone not null default now(),
  add column if not exists "retry_after" timestamp without time zone,
  add column if not exists "input_cbor" bytea,
  add column if not exists "output_cbor" bytea,
  add column if not exists "error_cbor" bytea,
  add column if not exists "spec_version" integer;

create index if not exists workflow_steps_run_id_index ON workflow.workflow_steps USING btree (run_id);

create index if not exists workflow_steps_status_index ON workflow.workflow_steps USING btree (status);

create table if not exists workflow.workflow_stream_chunks (
  "id" character varying not null,
  "stream_id" character varying not null,
  "data" bytea not null,
  "created_at" timestamp without time zone not null default now(),
  "eof" boolean not null,
  "run_id" character varying,
  constraint "workflow_stream_chunks_stream_id_id_pk" PRIMARY KEY (stream_id, id)
);

alter table workflow.workflow_stream_chunks
  add column if not exists "id" character varying not null,
  add column if not exists "stream_id" character varying not null,
  add column if not exists "data" bytea not null,
  add column if not exists "created_at" timestamp without time zone not null default now(),
  add column if not exists "eof" boolean not null,
  add column if not exists "run_id" character varying;

create index if not exists workflow_stream_chunks_run_id_index ON workflow.workflow_stream_chunks USING btree (run_id);

create table if not exists workflow.workflow_waits (
  "wait_id" character varying not null,
  "run_id" character varying not null,
  "status" workflow.wait_status not null,
  "resume_at" timestamp without time zone,
  "completed_at" timestamp without time zone,
  "created_at" timestamp without time zone not null default now(),
  "updated_at" timestamp without time zone not null default now(),
  "spec_version" integer,
  constraint "workflow_waits_pkey" PRIMARY KEY (wait_id)
);

alter table workflow.workflow_waits
  add column if not exists "wait_id" character varying not null,
  add column if not exists "run_id" character varying not null,
  add column if not exists "status" workflow.wait_status not null,
  add column if not exists "resume_at" timestamp without time zone,
  add column if not exists "completed_at" timestamp without time zone,
  add column if not exists "created_at" timestamp without time zone not null default now(),
  add column if not exists "updated_at" timestamp without time zone not null default now(),
  add column if not exists "spec_version" integer;

create index if not exists workflow_waits_run_id_index ON workflow.workflow_waits USING btree (run_id);

revoke all on schema workflow from public, anon, authenticated;
grant usage on schema workflow to service_role;
do $$
declare
  t record;
begin
  for t in select c.relname from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'workflow' and c.relkind = 'r'
  loop
    execute format('alter table workflow.%I enable row level security', t.relname);
    execute format('revoke all on workflow.%I from public, anon, authenticated', t.relname);
    execute format('grant all on workflow.%I to service_role', t.relname);
  end loop;
end;
$$;
grant usage, select on all sequences in schema workflow to service_role;
create index if not exists workflow_runs_attributes_idx on workflow.workflow_runs using gin (attributes jsonb_path_ops);

-- Copies each World run into workflow_runs: its tenant and actor come from
-- the bs.tenant and bs.actor attributes that startFor sets. A run with an
-- actor keeps its tenant only when the actor holds workflow.run there; a
-- run without one was started by the server, which is trusted.
create or replace function "better_supabase"."workflow_sdk_mirror_run"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_actor uuid;
begin
  begin
    v_tenant := (new.attributes ->> 'bs.tenant')::uuid;
  exception when others then
    v_tenant := null;
  end;
  begin
    v_actor := (new.attributes ->> 'bs.actor')::uuid;
  exception when others then
    v_actor := null;
  end;
  if v_tenant is not null and v_actor is not null
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflow.run'), false) then
    v_tenant := null;
  end if;
  perform "better_supabase"."record_workflow_run"(
    'workflow-sdk',
    new.id,
    new.name,
    case new.status::text when 'pending' then 'queued' else new.status::text end,
    v_tenant,
    v_actor,
    coalesce(new.attributes, '{}'::jsonb) - 'bs.tenant' - 'bs.actor',
    case when new.status::text = 'failed' then coalesce(new.error_code, left(new.error, 4000)) end,
    new.started_at at time zone 'UTC',
    new.completed_at at time zone 'UTC'
  );
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_sdk_mirror_run"() from public, anon, authenticated;
drop trigger if exists "bs_workflow_sdk_runs_mirror" on workflow.workflow_runs;
create trigger "bs_workflow_sdk_runs_mirror" after insert or update of status, attributes, error on workflow.workflow_runs
  for each row execute function "better_supabase"."workflow_sdk_mirror_run"();

-- pg_net delivery: posts up to batch due messages to the flow route in the
-- Vault secret workflow_flow_url, signed with workflow_delivery_secret
-- (x-bs-signature: t=<unix>,v1=hex(hmac_sha256(t.job.body))). The body is
-- the stored message; the route completes or fails the job, so a delivery
-- whose response is lost runs again after the lease.
create or replace function "better_supabase"."dispatch_workflow_deliveries"(batch integer default 20)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_job record;
  v_body jsonb;
  v_t text;
  v_job_header text;
  v_count integer := 0;
  -- pg_net is optional: http_post is looked up, not named, so plpgsql_check
  -- (supabase db lint) passes without the extension.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
begin
  if v_post is null then
    raise exception 'dispatch_workflow_deliveries needs pg_net: create extension pg_net, or deliver with the poll mode';
  end if;
  select ds.decrypted_secret into v_url from vault.decrypted_secrets ds where ds.name = 'workflow_flow_url';
  select ds.decrypted_secret into v_secret from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_secret';
  if v_url is null or v_secret is null then
    raise exception 'Set the Vault secrets workflow_flow_url and workflow_delivery_secret before dispatching' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from "better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := 'workflow_deliveries' || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, jsonb_build_object(
        'content-type', 'application/json',
        'x-bs-job', v_job_header,
        'x-bs-signature', 't=' || v_t || ',v1=' || encode(extensions.hmac(v_t || '.' || v_job_header || '.' || v_body::text, v_secret, 'sha256'), 'hex')
      ), 30000;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."dispatch_workflow_deliveries"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."dispatch_workflow_deliveries"(integer) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
