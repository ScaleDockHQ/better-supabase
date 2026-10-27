-- better-supabase module: workflow-sdk
-- @bsb-block workflow-sdk@3 managed
-- @bsb-hash sha256:3e8d1a1aac909363ac14524fa6a3dd40bf5c424cad314de75c467766f926f0d8
-- The tables of the Workflow SDK World (@workflow/world-postgres 5.0.4) in the workflow schema, closed to the API roles; a trigger that copies each run into workflow_runs, a pg_net dispatcher for the delivery queue on a pg_cron schedule, start idempotency keys, a list of the hooks open runs wait on and a purge of ended runs.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- The Workflow SDK World's tables (@workflow/world-postgres 5.0.4).
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
  "seq_in_band" integer not null default 1,
  constraint "workflow_event_slots_pkey" PRIMARY KEY (run_id)
);

alter table workflow.workflow_event_slots
  add column if not exists "run_id" character varying not null,
  add column if not exists "seq_in_band" integer not null default 1;

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


-- One row per start idempotency key: startFor claims the key before it starts
-- a run, so two concurrent starts with one key start one run. run_id is null
-- while the start that claimed it is still running.
create table if not exists workflow.workflow_run_keys (
  key text primary key check (length(key) between 1 and 500),
  run_id character varying,
  claimed_at timestamptz not null default now()
);
create index if not exists workflow_run_keys_run_id_idx on workflow.workflow_run_keys (run_id);
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
-- the bsb.tenant and bsb.actor attributes that startFor sets. A run with an
-- actor keeps its tenant only when the actor holds workflow.run there; a
-- run without one, or one with bsb.principal_kind (a runAs start, whose
-- actor is the user who triggered it), was started by the server, which is
-- trusted. bsb.subject
-- (type/id), bsb.principal_kind, bsb.principal, bsb.mode and bsb.trigger_node
-- fill the run's subject, principal, mode and trigger node.
create or replace function "better_supabase"."workflow_sdk_mirror_run"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_actor uuid;
  v_subject text;
  v_subject_type text;
  v_subject_id text;
  v_principal_kind text;
  v_mode text;
begin
  begin
    v_tenant := (new.attributes ->> 'bsb.tenant')::uuid;
  exception when others then
    v_tenant := null;
  end;
  begin
    v_actor := (new.attributes ->> 'bsb.actor')::uuid;
  exception when others then
    v_actor := null;
  end;
  v_principal_kind := new.attributes ->> 'bsb.principal_kind';
  if v_principal_kind is not null and v_principal_kind not in ('user', 'service_principal', 'system', 'external') then
    v_principal_kind := null;
  end if;
  if v_tenant is not null and v_actor is not null and v_principal_kind is null
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflow.run'), false) then
    v_tenant := null;
  end if;
  v_subject := new.attributes ->> 'bsb.subject';
  if v_subject is not null and position('/' in v_subject) between 2 and 101
    and length(v_subject) - position('/' in v_subject) between 1 and 200 then
    v_subject_type := left(v_subject, position('/' in v_subject) - 1);
    v_subject_id := substr(v_subject, position('/' in v_subject) + 1);
  end if;
  v_mode := case when new.attributes ->> 'bsb.mode' = 'test' then 'test' else 'live' end;
  perform "better_supabase"."record_workflow_run"(
    'workflow-sdk',
    new.id,
    new.name,
    case new.status::text when 'pending' then 'queued' else new.status::text end,
    v_tenant,
    v_actor,
    coalesce(new.attributes, '{}'::jsonb) - 'bsb.tenant' - 'bsb.actor' - 'bsb.subject' - 'bsb.principal_kind' - 'bsb.principal' - 'bsb.mode' - 'bsb.trigger_node',
    case when new.status::text = 'failed' then coalesce(new.error_code, left(new.error, 4000)) end,
    new.started_at at time zone 'UTC',
    new.completed_at at time zone 'UTC',
    v_subject_type,
    v_subject_id,
    v_principal_kind,
    case when v_principal_kind is null then null else nullif(left(new.attributes ->> 'bsb.principal', 200), '') end,
    v_mode,
    nullif(left(new.attributes ->> 'bsb.trigger_node', 100), '')
  );
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_sdk_mirror_run"() from public, anon, authenticated;
drop trigger if exists "bsb_workflow_sdk_runs_mirror" on workflow.workflow_runs;
create trigger "bsb_workflow_sdk_runs_mirror" after insert or update of status, attributes, error on workflow.workflow_runs
  for each row execute function "better_supabase"."workflow_sdk_mirror_run"();

-- pg_net delivery: posts up to batch due messages to the flow route in the
-- Vault secret workflow_flow_url, signed with workflow_delivery_secret
-- (x-bsb-signature: t=<unix>,v1=hex(hmac_sha256(t.job.body))). The body is
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
        'x-bsb-job', v_job_header,
        'x-bsb-signature', 't=' || v_t || ',v1=' || encode(extensions.hmac(v_t || '.' || v_job_header || '.' || v_body::text, v_secret, 'sha256'), 'hex')
      ), 30000;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."dispatch_workflow_deliveries"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."dispatch_workflow_deliveries"(integer) to service_role;

-- Claims a start key: claimed is true when this caller may start the run,
-- either because the key is new or because the start that claimed it left no
-- run for stale_after. Otherwise run_id is the run of the earlier start (null
-- while that start is still running).
create or replace function "better_supabase"."workflow_claim_run_key"(run_key text, stale_after interval default '5 minutes')
returns table (claimed boolean, run_id text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
    insert into workflow.workflow_run_keys as k (key) values (run_key)
    on conflict (key) do update set claimed_at = now()
      where k.run_id is null and k.claimed_at < now() - coalesce(stale_after, interval '5 minutes')
    returning true, k.run_id::text;
  if not found then
    return query select false, k.run_id::text from workflow.workflow_run_keys k where k.key = run_key;
  end if;
end;
$$;

-- Records the run a claimed key started.
create or replace function "better_supabase"."workflow_set_run_key"(run_key text, run text)
returns void
language sql
security definer
set search_path = ''
as $$
  update workflow.workflow_run_keys set run_id = run, claimed_at = now() where key = run_key;
$$;

-- Frees a key whose start failed before it created a run.
create or replace function "better_supabase"."workflow_release_run_key"(run_key text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from workflow.workflow_run_keys where key = run_key and run_id is null;
$$;

-- Deletes up to batch terminal runs that ended more than older_than ago, with
-- their events, steps, waits, streams, snapshots and invocations; hooks whose
-- token is still reserved (token_retention_until) stay, so a token can't be
-- reused. The copies in workflow_runs follow purge_workflow_runs instead.
create or replace function "better_supabase"."workflow_purge_runs"(
  older_than interval default '30 days',
  statuses text[] default array['completed', 'failed', 'cancelled'],
  batch integer default 500
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_statuses text[] := coalesce(statuses, array['completed', 'failed', 'cancelled']);
  v_ids text[];
  v_count integer;
begin
  if exists (select 1 from unnest(v_statuses) s where s not in ('completed', 'failed', 'cancelled')) then
    raise exception 'workflow_purge_runs deletes only completed, failed or cancelled runs'
      using errcode = '22023', hint = 'WORKFLOW_PURGE_STATUS';
  end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select r.id from workflow.workflow_runs r
    where r.status::text = any (v_statuses)
      and coalesce(r.completed_at, r.updated_at) < (now() at time zone 'UTC') - coalesce(older_than, interval '30 days')
    order by coalesce(r.completed_at, r.updated_at)
    limit least(greatest(coalesce(batch, 500), 1), 10000)
    for update skip locked
  ) x;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  delete from workflow.workflow_events where run_id = any (v_ids);
  delete from workflow.workflow_event_slots where run_id = any (v_ids);
  delete from workflow.workflow_steps where run_id = any (v_ids);
  delete from workflow.workflow_waits where run_id = any (v_ids);
  delete from workflow.workflow_stream_chunks where run_id = any (v_ids);
  delete from workflow.workflow_snapshots where run_id = any (v_ids);
  delete from workflow.workflow_invocations where run_id = any (v_ids);
  delete from workflow.workflow_hooks
    where run_id = any (v_ids) and (token_retention_until is null or token_retention_until < now());
  delete from workflow.workflow_run_keys where run_id = any (v_ids);
  delete from workflow.workflow_runs where id = any (v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- The hooks of pending and running runs, newest first: what a run waits on.
-- The token is left out; the app that created a hook knows it.
create or replace function "better_supabase"."workflow_open_hooks"(
  tenant text default null,
  workflow_name text default null,
  max integer default 50
)
returns table (
  hook_id text,
  run_id text,
  workflow text,
  tenant_id text,
  actor_id text,
  metadata jsonb,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select h.hook_id::text, h.run_id::text, r.name::text,
    r.attributes ->> 'bsb.tenant', r.attributes ->> 'bsb.actor',
    h.metadata, h.created_at at time zone 'UTC'
  from workflow.workflow_hooks h
  join workflow.workflow_runs r on r.id = h.run_id
  where r.status::text in ('pending', 'running')
    and not coalesce(h.is_system, false)
    and (workflow_open_hooks.tenant is null or r.attributes ->> 'bsb.tenant' = workflow_open_hooks.tenant)
    and (workflow_open_hooks.workflow_name is null or r.name = workflow_open_hooks.workflow_name)
  order by h.created_at desc
  limit least(greatest(coalesce(workflow_open_hooks.max, 50), 1), 500);
$$;
revoke execute on function "better_supabase"."workflow_claim_run_key"(text, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_claim_run_key"(text, interval) to service_role;
revoke execute on function "better_supabase"."workflow_set_run_key"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_set_run_key"(text, text) to service_role;
revoke execute on function "better_supabase"."workflow_release_run_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_release_run_key"(text) to service_role;
revoke execute on function "better_supabase"."workflow_purge_runs"(interval, text[], integer) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_purge_runs"(interval, text[], integer) to service_role;
revoke execute on function "better_supabase"."workflow_open_hooks"(text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_open_hooks"(text, text, integer) to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
