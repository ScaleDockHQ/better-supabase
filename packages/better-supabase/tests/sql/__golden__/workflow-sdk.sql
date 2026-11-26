-- ==== alone: schema supabase/schemas/900_better_supabase_043_workflow_sdk.sql
-- better-supabase module: workflow-sdk
-- @bsb-block workflow-sdk@10 managed
-- @bsb-hash sha256:8bf2a0fd730c2e873939cb17821e2dde229b3638cd05cfbd720b25e816ea08d7
-- The tables of the Workflow SDK World (@workflow/world-postgres 5.5.0) in the workflow schema, closed to the API roles; a trigger that copies each run into workflow_runs, a pg_net dispatcher for the delivery queue on a pg_cron schedule, start idempotency keys, a list of the hooks open runs wait on, a purge of ended runs, the purge backstops of zero-retention runs and the eve projection tables with the jobs that copy eve sessions into the blocks.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The Workflow SDK World's tables (@workflow/world-postgres 5.5.0).
-- Only the service role reads them: the app reads runs from workflow_runs in
-- the workflows module.
create schema if not exists workflow;

create type workflow.status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');

create type workflow.step_status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');

create type workflow.wait_status as enum ('waiting', 'completed');

create table workflow.workflow_event_slots (
  "run_id" character varying not null,
  "seq_in_band" integer not null default 1,
  constraint "workflow_event_slots_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_events (
  "id" character varying not null,
  "type" character varying not null,
  "correlation_id" character varying,
  "created_at" timestamp with time zone not null default now(),
  "run_id" character varying not null,
  "payload" jsonb,
  "payload_cbor" bytea,
  "spec_version" integer,
  "resume_id" character varying,
  "resume_payload_digest" character varying,
  constraint "workflow_events_run_id_id_pk" PRIMARY KEY (run_id, id)
);

create index workflow_events_correlation_id_index ON workflow.workflow_events USING btree (correlation_id);

create unique index workflow_events_entity_creation_unique ON workflow.workflow_events USING btree (run_id, correlation_id, type) WHERE ((type)::text = ANY ((ARRAY['step_created'::character varying, 'hook_created'::character varying, 'wait_created'::character varying, 'attr_set'::character varying])::text[]));

create unique index workflow_events_hook_resume_unique ON workflow.workflow_events USING btree (run_id, resume_id) WHERE (((type)::text = 'hook_received'::text) AND (resume_id IS NOT NULL));

create table workflow.workflow_hooks (
  "run_id" character varying not null,
  "hook_id" character varying not null,
  "token" character varying not null,
  "owner_id" character varying not null,
  "project_id" character varying not null,
  "environment" character varying not null,
  "created_at" timestamp with time zone not null default now(),
  "metadata" jsonb,
  "metadata_cbor" bytea,
  "spec_version" integer,
  "is_webhook" boolean default true,
  "is_system" boolean default false,
  "resume_context" bytea,
  "token_retention_until" timestamp with time zone,
  "claimed_from" bytea,
  "claims_token" boolean not null default false,
  constraint "workflow_hooks_pkey" PRIMARY KEY (hook_id)
);

create index workflow_hooks_run_id_index ON workflow.workflow_hooks USING btree (run_id);

create unique index workflow_hooks_token_claim_unique ON workflow.workflow_hooks USING btree (token) WHERE claims_token;

create index workflow_hooks_token_index ON workflow.workflow_hooks USING btree (token);

create table workflow.workflow_invocations (
  "sequence" bigserial,
  "run_id" character varying not null,
  "request_id" character varying not null,
  "payload" bytea,
  "fingerprint" character varying,
  "result" bytea,
  "created_at" timestamp with time zone not null default now(),
  "responded_at" timestamp with time zone,
  "expired_at" timestamp with time zone,
  "result_version" integer not null default 0,
  constraint "workflow_invocations_pkey" PRIMARY KEY (run_id, request_id)
);

create index workflow_invocations_pending ON workflow.workflow_invocations USING btree (run_id, sequence) WHERE (responded_at IS NULL);

create table workflow.workflow_job_lock_holders (
  "worker_id" text not null,
  "renewed_at" timestamp with time zone not null default now(),
  constraint "workflow_job_lock_holders_pkey" PRIMARY KEY (worker_id)
);

create table workflow.workflow_rate_limits (
  "scope" character varying not null,
  "key" character varying not null,
  "tat_us" bigint,
  constraint "workflow_rate_limits_scope_key_pk" PRIMARY KEY (scope, key)
);

create table workflow.workflow_run_delivery_leases (
  "run_id" character varying not null,
  "owner_job_id" bigint not null,
  "wake" jsonb,
  "wake_resume" boolean not null default false,
  "deferred" jsonb not null default '[]'::jsonb,
  "claimed_at" timestamp with time zone not null default now(),
  constraint "workflow_run_delivery_leases_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_runs (
  "id" character varying not null,
  "output" jsonb,
  "deployment_id" character varying not null,
  "status" workflow.status not null,
  "name" character varying not null,
  "execution_context" jsonb,
  "input" jsonb,
  "error" text,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "completed_at" timestamp with time zone,
  "started_at" timestamp with time zone,
  "output_cbor" bytea,
  "execution_context_cbor" bytea,
  "input_cbor" bytea,
  "expired_at" timestamp with time zone,
  "spec_version" character varying,
  "error_cbor" bytea,
  "error_code" character varying,
  "attributes" jsonb not null default '{}'::jsonb,
  "encryption_public_key" character varying,
  "dynamic_workflow_code_cbor" bytea,
  "start_hook_cbor" bytea,
  "job_prefix" character varying,
  "wake_pending" boolean not null default false,
  constraint "workflow_runs_pkey" PRIMARY KEY (id)
);

create index workflow_runs_name_index ON workflow.workflow_runs USING btree (name);

create index workflow_runs_status_index ON workflow.workflow_runs USING btree (status);

create table workflow.workflow_snapshots (
  "run_id" character varying not null,
  "data" bytea not null,
  "events_cursor" character varying,
  "created_at" timestamp with time zone not null default now(),
  constraint "workflow_snapshots_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_start_hook_admissions (
  "run_id" character varying not null,
  "token" character varying not null,
  "decision" character varying not null,
  "conflicting_run_id" character varying,
  "created_at" timestamp with time zone not null default now(),
  constraint "workflow_start_hook_admissions_pkey" PRIMARY KEY (run_id)
);

create index workflow_start_hook_admissions_created_at_index ON workflow.workflow_start_hook_admissions USING btree (created_at);

create table workflow.workflow_steps (
  "run_id" character varying not null,
  "step_id" character varying not null,
  "step_name" character varying not null,
  "status" workflow.step_status not null,
  "input" jsonb,
  "output" jsonb,
  "error" text,
  "attempt" integer not null,
  "started_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "retry_after" timestamp with time zone,
  "input_cbor" bytea,
  "output_cbor" bytea,
  "error_cbor" bytea,
  "spec_version" integer,
  constraint "workflow_steps_pkey" PRIMARY KEY (step_id)
);

create index workflow_steps_run_id_index ON workflow.workflow_steps USING btree (run_id);

create index workflow_steps_status_index ON workflow.workflow_steps USING btree (status);

create table workflow.workflow_stream_chunks (
  "id" character varying not null,
  "stream_id" character varying not null,
  "data" bytea not null,
  "created_at" timestamp with time zone not null default now(),
  "eof" boolean not null,
  "run_id" character varying,
  constraint "workflow_stream_chunks_stream_id_id_pk" PRIMARY KEY (stream_id, id)
);

create index workflow_stream_chunks_run_id_index ON workflow.workflow_stream_chunks USING btree (run_id);

create table workflow.workflow_waits (
  "wait_id" character varying not null,
  "run_id" character varying not null,
  "status" workflow.wait_status not null,
  "resume_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "spec_version" integer,
  constraint "workflow_waits_pkey" PRIMARY KEY (wait_id)
);

create index workflow_waits_run_id_index ON workflow.workflow_waits USING btree (run_id);

-- One row per start idempotency key: startFor claims the key before it starts
-- a run, so two concurrent starts with one key start one run. run_id is null
-- while the start that claimed it is still running.
create table workflow.workflow_run_keys (
  key text primary key constraint bsb_workflow_run_keys_key_check check (length(key) >= 1 and length(key) <= 500),
  run_id character varying,
  claimed_at timestamptz not null default now()
);
create index workflow_run_keys_run_id_idx on workflow.workflow_run_keys (run_id);
-- The purge backstops of zero-retention runs. world-postgres adds one through
-- Graphile Worker's add_job in the transaction that finishes such a run; this
-- World runs no Graphile Worker, so it points GRAPHILE_WORKER_SCHEMA at
-- workflow, where add_job records the run here and workflow_purge_backstops
-- deletes its data once due if the purge after the commit did not.
create table workflow.workflow_purge_backstops (
  run_id character varying primary key,
  due_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index workflow_purge_backstops_due_at_idx on workflow.workflow_purge_backstops (due_at);
create or replace function workflow.add_job(
  identifier text,
  payload json default null,
  run_at timestamptz default null,
  max_attempts integer default null,
  job_key text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run text := payload ->> 'runId';
begin
  if identifier not like '%purge' or v_run is null then
    raise exception 'Only the purge backstops of @workflow/world-postgres go through workflow.add_job'
      using errcode = '0A000', hint = 'WORKFLOW_GRAPHILE_UNSUPPORTED', detail = 'task ' || coalesce(identifier, 'null');
  end if;
  insert into workflow.workflow_purge_backstops (run_id, due_at)
    values (v_run, coalesce(run_at, now()))
    on conflict (run_id) do nothing;
end;
$$;
revoke execute on function workflow.add_job(text, json, timestamptz, integer, text) from public, anon, authenticated;
grant execute on function workflow.add_job(text, json, timestamptz, integer, text) to service_role;
-- The eve projection (eve sessions copied into the blocks by syncSession).
-- session_id is the id of the session's first run. read_cursor is the next
-- line of the session stream to read. A session is behind while dirty_at is
-- later than synced_at; the lease keeps two sync jobs off one session.
create table workflow.eve_sessions (
  session_id text primary key constraint bsb_eve_sessions_session_id_check check (length(session_id) >= 1 and length(session_id) <= 200),
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint not null default 0 constraint bsb_eve_sessions_read_cursor_check check (read_cursor >= 0),
  status text not null default 'open' constraint bsb_eve_sessions_status_check check (status in ('open', 'ended', 'failed', 'cancelled', 'stranded')),
  dirty_at timestamptz,
  synced_at timestamptz,
  lease_id text,
  leased_at timestamptz,
  lease_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index eve_sessions_dirty_idx on workflow.eve_sessions (dirty_at) where dirty_at is not null;
create index eve_sessions_open_idx on workflow.eve_sessions (eve_version) where status = 'open';
create table workflow.eve_session_runs (
  run_id text primary key,
  session_id text not null references workflow.eve_sessions (session_id) on delete cascade,
  eve_version text,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index eve_session_runs_session_idx on workflow.eve_session_runs (session_id);
revoke all on schema workflow from public, anon, authenticated;
grant usage on schema workflow to service_role;
alter table workflow.eve_session_runs enable row level security;
revoke all on workflow.eve_session_runs from public, anon, authenticated;
grant all on workflow.eve_session_runs to service_role;
alter table workflow.eve_sessions enable row level security;
revoke all on workflow.eve_sessions from public, anon, authenticated;
grant all on workflow.eve_sessions to service_role;
alter table workflow.workflow_event_slots enable row level security;
revoke all on workflow.workflow_event_slots from public, anon, authenticated;
grant all on workflow.workflow_event_slots to service_role;
alter table workflow.workflow_events enable row level security;
revoke all on workflow.workflow_events from public, anon, authenticated;
grant all on workflow.workflow_events to service_role;
alter table workflow.workflow_hooks enable row level security;
revoke all on workflow.workflow_hooks from public, anon, authenticated;
grant all on workflow.workflow_hooks to service_role;
alter table workflow.workflow_invocations enable row level security;
revoke all on workflow.workflow_invocations from public, anon, authenticated;
grant all on workflow.workflow_invocations to service_role;
alter table workflow.workflow_job_lock_holders enable row level security;
revoke all on workflow.workflow_job_lock_holders from public, anon, authenticated;
grant all on workflow.workflow_job_lock_holders to service_role;
alter table workflow.workflow_purge_backstops enable row level security;
revoke all on workflow.workflow_purge_backstops from public, anon, authenticated;
grant all on workflow.workflow_purge_backstops to service_role;
alter table workflow.workflow_rate_limits enable row level security;
revoke all on workflow.workflow_rate_limits from public, anon, authenticated;
grant all on workflow.workflow_rate_limits to service_role;
alter table workflow.workflow_run_delivery_leases enable row level security;
revoke all on workflow.workflow_run_delivery_leases from public, anon, authenticated;
grant all on workflow.workflow_run_delivery_leases to service_role;
alter table workflow.workflow_run_keys enable row level security;
revoke all on workflow.workflow_run_keys from public, anon, authenticated;
grant all on workflow.workflow_run_keys to service_role;
alter table workflow.workflow_runs enable row level security;
revoke all on workflow.workflow_runs from public, anon, authenticated;
grant all on workflow.workflow_runs to service_role;
alter table workflow.workflow_snapshots enable row level security;
revoke all on workflow.workflow_snapshots from public, anon, authenticated;
grant all on workflow.workflow_snapshots to service_role;
alter table workflow.workflow_start_hook_admissions enable row level security;
revoke all on workflow.workflow_start_hook_admissions from public, anon, authenticated;
grant all on workflow.workflow_start_hook_admissions to service_role;
alter table workflow.workflow_steps enable row level security;
revoke all on workflow.workflow_steps from public, anon, authenticated;
grant all on workflow.workflow_steps to service_role;
alter table workflow.workflow_stream_chunks enable row level security;
revoke all on workflow.workflow_stream_chunks from public, anon, authenticated;
grant all on workflow.workflow_stream_chunks to service_role;
alter table workflow.workflow_waits enable row level security;
revoke all on workflow.workflow_waits from public, anon, authenticated;
grant all on workflow.workflow_waits to service_role;
grant usage, select on sequence workflow.workflow_invocations_sequence_seq to service_role;
create index workflow_runs_attributes_idx on workflow.workflow_runs using gin (attributes jsonb_path_ops);

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
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflows.run'), false) then
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
    new.started_at,
    new.completed_at,
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
  v_extra jsonb;
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
  -- Extra headers (a deployment protection bypass, for one) as a JSON object.
  select ds.decrypted_secret::jsonb into v_extra from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_headers';
  if v_extra is not null and pg_catalog.jsonb_typeof(v_extra) <> 'object' then
    raise exception 'The Vault secret workflow_delivery_headers must be a JSON object of header names and values' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from "better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := 'workflow_deliveries' || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, coalesce(v_extra, '{}'::jsonb) || jsonb_build_object(
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
-- With skip_unprojected, a run of an eve session stays until the session's
-- copy in the blocks is current (the session was synced after its last change
-- and is no longer open).

create or replace function "better_supabase"."workflow_purge_runs"(
  older_than interval default '30 days',
  statuses text[] default array['completed', 'failed', 'cancelled'],
  batch integer default 500,
  skip_unprojected boolean default false
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
      and coalesce(r.completed_at, r.updated_at) < now() - coalesce(older_than, interval '30 days')
      and not (coalesce(skip_unprojected, false) and exists (
        select 1 from workflow.eve_session_runs sr
        join workflow.eve_sessions es on es.session_id = sr.session_id
        where sr.run_id = r.id
          and (es.status = 'open' or es.synced_at is null or es.dirty_at > es.synced_at)
      ))
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
  delete from workflow.workflow_purge_backstops where run_id = any (v_ids);
  delete from workflow.eve_session_runs where run_id = any (v_ids);
  delete from workflow.workflow_runs where id = any (v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Runs up to batch due purge backstops: a run that ended with the $retention
-- attribute 0 and still has its data (expired_at is null) gets the purge
-- @workflow/world-postgres runs after the terminal write, in one transaction.
-- The run row is updated first, so late step and stream writes, which lock it
-- to read expired_at, wait for the purge. Returns how many runs it purged.
create or replace function "better_supabase"."workflow_purge_backstops"(batch integer default 100)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_due text[];
  v_ids text[];
begin
  with due as (
    delete from workflow.workflow_purge_backstops b
    where b.run_id in (
      select d.run_id from workflow.workflow_purge_backstops d
      where d.due_at <= now()
      order by d.due_at
      limit least(greatest(coalesce(batch, 100), 1), 1000)
      for update skip locked
    )
    returning b.run_id
  )
  select coalesce(array_agg(due.run_id), '{}') into v_due from due;
  if cardinality(v_due) = 0 then
    return 0;
  end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select r.id from workflow.workflow_runs r
    where r.id = any (v_due)
      and r.status::text in ('completed', 'failed', 'cancelled')
      and r.attributes ->> '$retention' = '0'
      and r.expired_at is null
    for update
  ) x;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  update workflow.workflow_runs set expired_at = now(),
    input_cbor = null, input = null, output_cbor = null, output = null,
    error_cbor = null, error = null, dynamic_workflow_code_cbor = null
    where id = any (v_ids);
  update workflow.workflow_steps set input_cbor = null, input = null,
    output_cbor = null, output = null, error_cbor = null, error = null
    where run_id = any (v_ids);
  update workflow.workflow_events set payload_cbor = null, payload = null, resume_payload_digest = null
    where run_id = any (v_ids);
  update workflow.workflow_hooks set metadata_cbor = null, metadata = null, resume_context = null
    where run_id = any (v_ids);
  update workflow.workflow_stream_chunks set data = ''::bytea where run_id = any (v_ids);
  update workflow.workflow_invocations set payload = null, result = null, fingerprint = null, expired_at = now()
    where run_id = any (v_ids);
  delete from workflow.workflow_snapshots where run_id = any (v_ids);
  return cardinality(v_ids);
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
  metadata_cbor bytea,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select h.hook_id::text, h.run_id::text, r.name::text,
    r.attributes ->> 'bsb.tenant', r.attributes ->> 'bsb.actor',
    h.metadata, h.metadata_cbor, h.created_at
  from workflow.workflow_hooks h
  join workflow.workflow_runs r on r.id = h.run_id
  where r.status::text in ('pending', 'running')
    and not coalesce(h.is_system, false)
    and (workflow_open_hooks.tenant is null or r.attributes ->> 'bsb.tenant' = workflow_open_hooks.tenant)
    and (workflow_open_hooks.workflow_name is null or r.name = workflow_open_hooks.workflow_name)
  order by h.created_at desc
  limit least(greatest(coalesce(workflow_open_hooks.max, 50), 1), 500);
$$;
-- Marks a session as behind and queues its sync job. The job is debounced: a
-- job that has not started yet absorbs later wake-ups of the same session.
create or replace function "better_supabase"."eve_session_wake"(sid text, delay_seconds integer default 2)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into workflow.eve_sessions as s (session_id, dirty_at) values (sid, now())
  on conflict (session_id) do update set dirty_at = now(), updated_at = now();
  perform "better_supabase"."enqueue_job"(queue => 'eve_session_sync', payload => jsonb_build_object('sessionId', sid), delay => greatest(coalesce(delay_seconds, 0), 0), dedupe_key => 'eve:' || sid, dedupe_running => false);
end;
$$;

-- Follows eve's runs: a run with an eve session type, or one that names its
-- session, belongs to that session. The newest run decides the status.
create or replace function "better_supabase"."workflow_sdk_track_eve_run"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
  v_status text;
begin
  if new.attributes ->> '$eve.type' is distinct from 'session' and nullif(new.attributes ->> '$eve.session', '') is null then
    return null;
  end if;
  v_session := coalesce(nullif(new.attributes ->> '$eve.session', ''), new.id);
  v_status := case new.status::text
    when 'completed' then 'ended'
    when 'failed' then 'failed'
    when 'cancelled' then 'cancelled'
    else 'open'
  end;
  insert into workflow.eve_sessions as s (session_id, eve_version, run_id, status)
  values (v_session, new.attributes ->> '$eve.version', new.id, v_status)
  on conflict (session_id) do update set
    eve_version = coalesce(new.attributes ->> '$eve.version', s.eve_version),
    run_id = new.id,
    status = case when s.status = 'stranded' then s.status else v_status end,
    updated_at = now()
  where s.run_id is null or s.run_id = new.id
    or new.created_at >= coalesce((select r.created_at from workflow.workflow_runs r where r.id = s.run_id), '-infinity'::timestamptz);
  insert into workflow.eve_session_runs as sr (run_id, session_id, eve_version, status)
  values (new.id, v_session, new.attributes ->> '$eve.version', new.status::text)
  on conflict (run_id) do update set status = new.status::text, updated_at = now();
  perform "better_supabase"."eve_session_wake"(v_session);
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_sdk_track_eve_run"() from public, anon, authenticated;
create trigger "bsb_workflow_sdk_eve_runs" after insert or update of status on workflow.workflow_runs
  for each row execute function "better_supabase"."workflow_sdk_track_eve_run"();

-- Wakes the session of a run that wrote an event. Other runs cost one lookup.
create or replace function "better_supabase"."workflow_sdk_wake_eve_session"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
begin
  select sr.session_id into v_session from workflow.eve_session_runs sr where sr.run_id = new.run_id;
  if v_session is not null then
    perform "better_supabase"."eve_session_wake"(v_session);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_sdk_wake_eve_session"() from public, anon, authenticated;
create trigger "bsb_workflow_sdk_eve_events" after insert on workflow.workflow_events
  for each row execute function "better_supabase"."workflow_sdk_wake_eve_session"();

-- Takes the lease on a session and returns its row, or no row while another
-- sync job holds the lease.
create or replace function "better_supabase"."eve_session_lease"(sid text, lease_seconds integer default 60)
returns table (
  session_id text,
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint,
  status text,
  lease_id text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_token text := gen_random_uuid()::text;
begin
  insert into workflow.eve_sessions (session_id) values (sid) on conflict (session_id) do nothing;
  return query
    update workflow.eve_sessions s set
      lease_id = v_token,
      leased_at = now(),
      lease_until = now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1)),
      updated_at = now()
    where s.session_id = sid and (s.lease_until is null or s.lease_until < now())
    returning s.session_id, s.tenant_id, s.principal_kind, s.principal_id, s.eve_version, s.chat_id,
      s.record_type, s.record_id, s.run_id, s.read_cursor, s.status, s.lease_id;
end;
$$;

-- Advances the cursor and stores what the job resolved, then frees the lease.
-- synced_at is the time the lease began, so a change after that stays behind.
create or replace function "better_supabase"."eve_session_commit"(
  sid text,
  token text,
  cursor_line bigint,
  tenant text default null,
  principal_kind text default null,
  principal_id text default null,
  chat text default null,
  record_type text default null,
  record_id text default null,
  session_status text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status is not null and session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_commit: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions s set
    read_cursor = greatest(s.read_cursor, coalesce(cursor_line, 0)),
    tenant_id = coalesce(tenant, s.tenant_id),
    principal_kind = coalesce(eve_session_commit.principal_kind, s.principal_kind),
    principal_id = coalesce(eve_session_commit.principal_id, s.principal_id),
    chat_id = coalesce(chat, s.chat_id),
    record_type = coalesce(eve_session_commit.record_type, s.record_type),
    record_id = coalesce(eve_session_commit.record_id, s.record_id),
    status = coalesce(session_status, s.status),
    synced_at = coalesce(s.leased_at, now()),
    lease_id = null,
    lease_until = null,
    updated_at = now()
  where s.session_id = sid and s.lease_id = token;
  return found;
end;
$$;

-- Frees a lease without advancing the cursor, so the next job starts at once.
create or replace function "better_supabase"."eve_session_release"(sid text, token text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update workflow.eve_sessions set lease_id = null, lease_until = null, updated_at = now()
  where session_id = sid and lease_id = token
  returning true;
$$;

-- The sessions whose copy is behind, oldest first: changed since the last sync,
-- or open and not synced for older_than.
create or replace function "better_supabase"."eve_sessions_behind"(older_than interval default '5 minutes', max integer default 100)
returns table (session_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id
  from workflow.eve_sessions s
  where (s.lease_until is null or s.lease_until < now())
    and (
      (s.dirty_at is not null and (s.synced_at is null or s.synced_at < s.dirty_at))
      or (s.status = 'open' and coalesce(s.synced_at, s.created_at) < now() - coalesce(older_than, interval '5 minutes'))
    )
  order by coalesce(s.synced_at, s.created_at)
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- The open sessions that a release other than not_version started, oldest first.
create or replace function "better_supabase"."eve_open_sessions"(not_version text default null, tenant text default null, max integer default 100)
returns table (
  session_id text,
  eve_version text,
  tenant_id text,
  principal_id text,
  chat_id text,
  run_id text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id, s.eve_version, s.tenant_id, s.principal_id, s.chat_id, s.run_id, s.created_at
  from workflow.eve_sessions s
  where s.status = 'open'
    and (not_version is null or s.eve_version is distinct from not_version)
    and (tenant is null or s.tenant_id = tenant)
  order by s.created_at
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- Sets a session's status (for instance stranded) and queues a sync.
create or replace function "better_supabase"."eve_session_mark"(sid text, session_status text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_mark: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions set status = session_status, updated_at = now() where session_id = sid;
  if not found then
    return false;
  end if;
  perform "better_supabase"."eve_session_wake"(sid, 0);
  return true;
end;
$$;
revoke execute on function "better_supabase"."workflow_claim_run_key"(text, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_claim_run_key"(text, interval) to service_role;
revoke execute on function "better_supabase"."workflow_set_run_key"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_set_run_key"(text, text) to service_role;
revoke execute on function "better_supabase"."workflow_release_run_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_release_run_key"(text) to service_role;
revoke execute on function "better_supabase"."workflow_purge_runs"(interval, text[], integer, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_purge_runs"(interval, text[], integer, boolean) to service_role;
revoke execute on function "better_supabase"."workflow_purge_backstops"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_purge_backstops"(integer) to service_role;
revoke execute on function "better_supabase"."workflow_open_hooks"(text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_open_hooks"(text, text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_wake"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_wake"(text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_lease"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_lease"(text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) to service_role;
revoke execute on function "better_supabase"."eve_session_release"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_release"(text, text) to service_role;
revoke execute on function "better_supabase"."eve_sessions_behind"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_sessions_behind"(interval, integer) to service_role;
revoke execute on function "better_supabase"."eve_open_sessions"(text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_open_sessions"(text, text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_mark"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_mark"(text, text) to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_043_workflow_sdk.sql
-- better-supabase module: workflow-sdk
-- @bsb-block-data workflow-sdk
-- @bsb-hash sha256:03d035c6cdd294e29651450c06bd849b42260fb91e90c111f01dfc427c4eff9c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

do $$
declare
  c record;
begin
  for c in select table_name, column_name from information_schema.columns
    where table_schema = 'workflow' and data_type = 'timestamp without time zone'
  loop
    execute format('alter table workflow.%I alter column %I type timestamptz using %I at time zone ''UTC''', c.table_name, c.column_name, c.column_name);
  end loop;
end
$$;

insert into better_supabase.blocks (name, version, mode)
values ('workflow-sdk', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_043_workflow_sdk.sql
-- better-supabase module: workflow-sdk
-- @bsb-block workflow-sdk@10 managed
-- @bsb-hash sha256:8bf2a0fd730c2e873939cb17821e2dde229b3638cd05cfbd720b25e816ea08d7
-- The tables of the Workflow SDK World (@workflow/world-postgres 5.5.0) in the workflow schema, closed to the API roles; a trigger that copies each run into workflow_runs, a pg_net dispatcher for the delivery queue on a pg_cron schedule, start idempotency keys, a list of the hooks open runs wait on, a purge of ended runs, the purge backstops of zero-retention runs and the eve projection tables with the jobs that copy eve sessions into the blocks.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The Workflow SDK World's tables (@workflow/world-postgres 5.5.0).
-- Only the service role reads them: the app reads runs from workflow_runs in
-- the workflows module.
create schema if not exists workflow;

create type workflow.status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');

create type workflow.step_status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');

create type workflow.wait_status as enum ('waiting', 'completed');

create table workflow.workflow_event_slots (
  "run_id" character varying not null,
  "seq_in_band" integer not null default 1,
  constraint "workflow_event_slots_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_events (
  "id" character varying not null,
  "type" character varying not null,
  "correlation_id" character varying,
  "created_at" timestamp with time zone not null default now(),
  "run_id" character varying not null,
  "payload" jsonb,
  "payload_cbor" bytea,
  "spec_version" integer,
  "resume_id" character varying,
  "resume_payload_digest" character varying,
  constraint "workflow_events_run_id_id_pk" PRIMARY KEY (run_id, id)
);

create index workflow_events_correlation_id_index ON workflow.workflow_events USING btree (correlation_id);

create unique index workflow_events_entity_creation_unique ON workflow.workflow_events USING btree (run_id, correlation_id, type) WHERE ((type)::text = ANY ((ARRAY['step_created'::character varying, 'hook_created'::character varying, 'wait_created'::character varying, 'attr_set'::character varying])::text[]));

create unique index workflow_events_hook_resume_unique ON workflow.workflow_events USING btree (run_id, resume_id) WHERE (((type)::text = 'hook_received'::text) AND (resume_id IS NOT NULL));

create table workflow.workflow_hooks (
  "run_id" character varying not null,
  "hook_id" character varying not null,
  "token" character varying not null,
  "owner_id" character varying not null,
  "project_id" character varying not null,
  "environment" character varying not null,
  "created_at" timestamp with time zone not null default now(),
  "metadata" jsonb,
  "metadata_cbor" bytea,
  "spec_version" integer,
  "is_webhook" boolean default true,
  "is_system" boolean default false,
  "resume_context" bytea,
  "token_retention_until" timestamp with time zone,
  "claimed_from" bytea,
  "claims_token" boolean not null default false,
  constraint "workflow_hooks_pkey" PRIMARY KEY (hook_id)
);

create index workflow_hooks_run_id_index ON workflow.workflow_hooks USING btree (run_id);

create unique index workflow_hooks_token_claim_unique ON workflow.workflow_hooks USING btree (token) WHERE claims_token;

create index workflow_hooks_token_index ON workflow.workflow_hooks USING btree (token);

create table workflow.workflow_invocations (
  "sequence" bigserial,
  "run_id" character varying not null,
  "request_id" character varying not null,
  "payload" bytea,
  "fingerprint" character varying,
  "result" bytea,
  "created_at" timestamp with time zone not null default now(),
  "responded_at" timestamp with time zone,
  "expired_at" timestamp with time zone,
  "result_version" integer not null default 0,
  constraint "workflow_invocations_pkey" PRIMARY KEY (run_id, request_id)
);

create index workflow_invocations_pending ON workflow.workflow_invocations USING btree (run_id, sequence) WHERE (responded_at IS NULL);

create table workflow.workflow_job_lock_holders (
  "worker_id" text not null,
  "renewed_at" timestamp with time zone not null default now(),
  constraint "workflow_job_lock_holders_pkey" PRIMARY KEY (worker_id)
);

create table workflow.workflow_rate_limits (
  "scope" character varying not null,
  "key" character varying not null,
  "tat_us" bigint,
  constraint "workflow_rate_limits_scope_key_pk" PRIMARY KEY (scope, key)
);

create table workflow.workflow_run_delivery_leases (
  "run_id" character varying not null,
  "owner_job_id" bigint not null,
  "wake" jsonb,
  "wake_resume" boolean not null default false,
  "deferred" jsonb not null default '[]'::jsonb,
  "claimed_at" timestamp with time zone not null default now(),
  constraint "workflow_run_delivery_leases_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_runs (
  "id" character varying not null,
  "output" jsonb,
  "deployment_id" character varying not null,
  "status" workflow.status not null,
  "name" character varying not null,
  "execution_context" jsonb,
  "input" jsonb,
  "error" text,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "completed_at" timestamp with time zone,
  "started_at" timestamp with time zone,
  "output_cbor" bytea,
  "execution_context_cbor" bytea,
  "input_cbor" bytea,
  "expired_at" timestamp with time zone,
  "spec_version" character varying,
  "error_cbor" bytea,
  "error_code" character varying,
  "attributes" jsonb not null default '{}'::jsonb,
  "encryption_public_key" character varying,
  "dynamic_workflow_code_cbor" bytea,
  "start_hook_cbor" bytea,
  "job_prefix" character varying,
  "wake_pending" boolean not null default false,
  constraint "workflow_runs_pkey" PRIMARY KEY (id)
);

create index workflow_runs_name_index ON workflow.workflow_runs USING btree (name);

create index workflow_runs_status_index ON workflow.workflow_runs USING btree (status);

create table workflow.workflow_snapshots (
  "run_id" character varying not null,
  "data" bytea not null,
  "events_cursor" character varying,
  "created_at" timestamp with time zone not null default now(),
  constraint "workflow_snapshots_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_start_hook_admissions (
  "run_id" character varying not null,
  "token" character varying not null,
  "decision" character varying not null,
  "conflicting_run_id" character varying,
  "created_at" timestamp with time zone not null default now(),
  constraint "workflow_start_hook_admissions_pkey" PRIMARY KEY (run_id)
);

create index workflow_start_hook_admissions_created_at_index ON workflow.workflow_start_hook_admissions USING btree (created_at);

create table workflow.workflow_steps (
  "run_id" character varying not null,
  "step_id" character varying not null,
  "step_name" character varying not null,
  "status" workflow.step_status not null,
  "input" jsonb,
  "output" jsonb,
  "error" text,
  "attempt" integer not null,
  "started_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "retry_after" timestamp with time zone,
  "input_cbor" bytea,
  "output_cbor" bytea,
  "error_cbor" bytea,
  "spec_version" integer,
  constraint "workflow_steps_pkey" PRIMARY KEY (step_id)
);

create index workflow_steps_run_id_index ON workflow.workflow_steps USING btree (run_id);

create index workflow_steps_status_index ON workflow.workflow_steps USING btree (status);

create table workflow.workflow_stream_chunks (
  "id" character varying not null,
  "stream_id" character varying not null,
  "data" bytea not null,
  "created_at" timestamp with time zone not null default now(),
  "eof" boolean not null,
  "run_id" character varying,
  constraint "workflow_stream_chunks_stream_id_id_pk" PRIMARY KEY (stream_id, id)
);

create index workflow_stream_chunks_run_id_index ON workflow.workflow_stream_chunks USING btree (run_id);

create table workflow.workflow_waits (
  "wait_id" character varying not null,
  "run_id" character varying not null,
  "status" workflow.wait_status not null,
  "resume_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "spec_version" integer,
  constraint "workflow_waits_pkey" PRIMARY KEY (wait_id)
);

create index workflow_waits_run_id_index ON workflow.workflow_waits USING btree (run_id);

-- One row per start idempotency key: startFor claims the key before it starts
-- a run, so two concurrent starts with one key start one run. run_id is null
-- while the start that claimed it is still running.
create table workflow.workflow_run_keys (
  key text primary key constraint bsb_workflow_run_keys_key_check check (length(key) >= 1 and length(key) <= 500),
  run_id character varying,
  claimed_at timestamptz not null default now()
);
create index workflow_run_keys_run_id_idx on workflow.workflow_run_keys (run_id);
-- The purge backstops of zero-retention runs. world-postgres adds one through
-- Graphile Worker's add_job in the transaction that finishes such a run; this
-- World runs no Graphile Worker, so it points GRAPHILE_WORKER_SCHEMA at
-- workflow, where add_job records the run here and workflow_purge_backstops
-- deletes its data once due if the purge after the commit did not.
create table workflow.workflow_purge_backstops (
  run_id character varying primary key,
  due_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index workflow_purge_backstops_due_at_idx on workflow.workflow_purge_backstops (due_at);
create or replace function workflow.add_job(
  identifier text,
  payload json default null,
  run_at timestamptz default null,
  max_attempts integer default null,
  job_key text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run text := payload ->> 'runId';
begin
  if identifier not like '%purge' or v_run is null then
    raise exception 'Only the purge backstops of @workflow/world-postgres go through workflow.add_job'
      using errcode = '0A000', hint = 'WORKFLOW_GRAPHILE_UNSUPPORTED', detail = 'task ' || coalesce(identifier, 'null');
  end if;
  insert into workflow.workflow_purge_backstops (run_id, due_at)
    values (v_run, coalesce(run_at, now()))
    on conflict (run_id) do nothing;
end;
$$;
revoke execute on function workflow.add_job(text, json, timestamptz, integer, text) from public, anon, authenticated;
grant execute on function workflow.add_job(text, json, timestamptz, integer, text) to service_role;
-- The eve projection (eve sessions copied into the blocks by syncSession).
-- session_id is the id of the session's first run. read_cursor is the next
-- line of the session stream to read. A session is behind while dirty_at is
-- later than synced_at; the lease keeps two sync jobs off one session.
create table workflow.eve_sessions (
  session_id text primary key constraint bsb_eve_sessions_session_id_check check (length(session_id) >= 1 and length(session_id) <= 200),
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint not null default 0 constraint bsb_eve_sessions_read_cursor_check check (read_cursor >= 0),
  status text not null default 'open' constraint bsb_eve_sessions_status_check check (status in ('open', 'ended', 'failed', 'cancelled', 'stranded')),
  dirty_at timestamptz,
  synced_at timestamptz,
  lease_id text,
  leased_at timestamptz,
  lease_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index eve_sessions_dirty_idx on workflow.eve_sessions (dirty_at) where dirty_at is not null;
create index eve_sessions_open_idx on workflow.eve_sessions (eve_version) where status = 'open';
create table workflow.eve_session_runs (
  run_id text primary key,
  session_id text not null references workflow.eve_sessions (session_id) on delete cascade,
  eve_version text,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index eve_session_runs_session_idx on workflow.eve_session_runs (session_id);
revoke all on schema workflow from public, anon, authenticated;
grant usage on schema workflow to service_role;
alter table workflow.eve_session_runs enable row level security;
revoke all on workflow.eve_session_runs from public, anon, authenticated;
grant all on workflow.eve_session_runs to service_role;
alter table workflow.eve_sessions enable row level security;
revoke all on workflow.eve_sessions from public, anon, authenticated;
grant all on workflow.eve_sessions to service_role;
alter table workflow.workflow_event_slots enable row level security;
revoke all on workflow.workflow_event_slots from public, anon, authenticated;
grant all on workflow.workflow_event_slots to service_role;
alter table workflow.workflow_events enable row level security;
revoke all on workflow.workflow_events from public, anon, authenticated;
grant all on workflow.workflow_events to service_role;
alter table workflow.workflow_hooks enable row level security;
revoke all on workflow.workflow_hooks from public, anon, authenticated;
grant all on workflow.workflow_hooks to service_role;
alter table workflow.workflow_invocations enable row level security;
revoke all on workflow.workflow_invocations from public, anon, authenticated;
grant all on workflow.workflow_invocations to service_role;
alter table workflow.workflow_job_lock_holders enable row level security;
revoke all on workflow.workflow_job_lock_holders from public, anon, authenticated;
grant all on workflow.workflow_job_lock_holders to service_role;
alter table workflow.workflow_purge_backstops enable row level security;
revoke all on workflow.workflow_purge_backstops from public, anon, authenticated;
grant all on workflow.workflow_purge_backstops to service_role;
alter table workflow.workflow_rate_limits enable row level security;
revoke all on workflow.workflow_rate_limits from public, anon, authenticated;
grant all on workflow.workflow_rate_limits to service_role;
alter table workflow.workflow_run_delivery_leases enable row level security;
revoke all on workflow.workflow_run_delivery_leases from public, anon, authenticated;
grant all on workflow.workflow_run_delivery_leases to service_role;
alter table workflow.workflow_run_keys enable row level security;
revoke all on workflow.workflow_run_keys from public, anon, authenticated;
grant all on workflow.workflow_run_keys to service_role;
alter table workflow.workflow_runs enable row level security;
revoke all on workflow.workflow_runs from public, anon, authenticated;
grant all on workflow.workflow_runs to service_role;
alter table workflow.workflow_snapshots enable row level security;
revoke all on workflow.workflow_snapshots from public, anon, authenticated;
grant all on workflow.workflow_snapshots to service_role;
alter table workflow.workflow_start_hook_admissions enable row level security;
revoke all on workflow.workflow_start_hook_admissions from public, anon, authenticated;
grant all on workflow.workflow_start_hook_admissions to service_role;
alter table workflow.workflow_steps enable row level security;
revoke all on workflow.workflow_steps from public, anon, authenticated;
grant all on workflow.workflow_steps to service_role;
alter table workflow.workflow_stream_chunks enable row level security;
revoke all on workflow.workflow_stream_chunks from public, anon, authenticated;
grant all on workflow.workflow_stream_chunks to service_role;
alter table workflow.workflow_waits enable row level security;
revoke all on workflow.workflow_waits from public, anon, authenticated;
grant all on workflow.workflow_waits to service_role;
grant usage, select on sequence workflow.workflow_invocations_sequence_seq to service_role;
create index workflow_runs_attributes_idx on workflow.workflow_runs using gin (attributes jsonb_path_ops);

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
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflows.run'), false) then
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
    new.started_at,
    new.completed_at,
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
  v_extra jsonb;
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
  -- Extra headers (a deployment protection bypass, for one) as a JSON object.
  select ds.decrypted_secret::jsonb into v_extra from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_headers';
  if v_extra is not null and pg_catalog.jsonb_typeof(v_extra) <> 'object' then
    raise exception 'The Vault secret workflow_delivery_headers must be a JSON object of header names and values' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from "better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := 'workflow_deliveries' || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, coalesce(v_extra, '{}'::jsonb) || jsonb_build_object(
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
-- With skip_unprojected, a run of an eve session stays until the session's
-- copy in the blocks is current (the session was synced after its last change
-- and is no longer open).

create or replace function "better_supabase"."workflow_purge_runs"(
  older_than interval default '30 days',
  statuses text[] default array['completed', 'failed', 'cancelled'],
  batch integer default 500,
  skip_unprojected boolean default false
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
      and coalesce(r.completed_at, r.updated_at) < now() - coalesce(older_than, interval '30 days')
      and not (coalesce(skip_unprojected, false) and exists (
        select 1 from workflow.eve_session_runs sr
        join workflow.eve_sessions es on es.session_id = sr.session_id
        where sr.run_id = r.id
          and (es.status = 'open' or es.synced_at is null or es.dirty_at > es.synced_at)
      ))
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
  delete from workflow.workflow_purge_backstops where run_id = any (v_ids);
  delete from workflow.eve_session_runs where run_id = any (v_ids);
  delete from workflow.workflow_runs where id = any (v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Runs up to batch due purge backstops: a run that ended with the $retention
-- attribute 0 and still has its data (expired_at is null) gets the purge
-- @workflow/world-postgres runs after the terminal write, in one transaction.
-- The run row is updated first, so late step and stream writes, which lock it
-- to read expired_at, wait for the purge. Returns how many runs it purged.
create or replace function "better_supabase"."workflow_purge_backstops"(batch integer default 100)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_due text[];
  v_ids text[];
begin
  with due as (
    delete from workflow.workflow_purge_backstops b
    where b.run_id in (
      select d.run_id from workflow.workflow_purge_backstops d
      where d.due_at <= now()
      order by d.due_at
      limit least(greatest(coalesce(batch, 100), 1), 1000)
      for update skip locked
    )
    returning b.run_id
  )
  select coalesce(array_agg(due.run_id), '{}') into v_due from due;
  if cardinality(v_due) = 0 then
    return 0;
  end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select r.id from workflow.workflow_runs r
    where r.id = any (v_due)
      and r.status::text in ('completed', 'failed', 'cancelled')
      and r.attributes ->> '$retention' = '0'
      and r.expired_at is null
    for update
  ) x;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  update workflow.workflow_runs set expired_at = now(),
    input_cbor = null, input = null, output_cbor = null, output = null,
    error_cbor = null, error = null, dynamic_workflow_code_cbor = null
    where id = any (v_ids);
  update workflow.workflow_steps set input_cbor = null, input = null,
    output_cbor = null, output = null, error_cbor = null, error = null
    where run_id = any (v_ids);
  update workflow.workflow_events set payload_cbor = null, payload = null, resume_payload_digest = null
    where run_id = any (v_ids);
  update workflow.workflow_hooks set metadata_cbor = null, metadata = null, resume_context = null
    where run_id = any (v_ids);
  update workflow.workflow_stream_chunks set data = ''::bytea where run_id = any (v_ids);
  update workflow.workflow_invocations set payload = null, result = null, fingerprint = null, expired_at = now()
    where run_id = any (v_ids);
  delete from workflow.workflow_snapshots where run_id = any (v_ids);
  return cardinality(v_ids);
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
  metadata_cbor bytea,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select h.hook_id::text, h.run_id::text, r.name::text,
    r.attributes ->> 'bsb.tenant', r.attributes ->> 'bsb.actor',
    h.metadata, h.metadata_cbor, h.created_at
  from workflow.workflow_hooks h
  join workflow.workflow_runs r on r.id = h.run_id
  where r.status::text in ('pending', 'running')
    and not coalesce(h.is_system, false)
    and (workflow_open_hooks.tenant is null or r.attributes ->> 'bsb.tenant' = workflow_open_hooks.tenant)
    and (workflow_open_hooks.workflow_name is null or r.name = workflow_open_hooks.workflow_name)
  order by h.created_at desc
  limit least(greatest(coalesce(workflow_open_hooks.max, 50), 1), 500);
$$;
-- Marks a session as behind and queues its sync job. The job is debounced: a
-- job that has not started yet absorbs later wake-ups of the same session.
create or replace function "better_supabase"."eve_session_wake"(sid text, delay_seconds integer default 2)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into workflow.eve_sessions as s (session_id, dirty_at) values (sid, now())
  on conflict (session_id) do update set dirty_at = now(), updated_at = now();
  perform "better_supabase"."enqueue_job"(queue => 'eve_session_sync', payload => jsonb_build_object('sessionId', sid), delay => greatest(coalesce(delay_seconds, 0), 0), dedupe_key => 'eve:' || sid, dedupe_running => false);
end;
$$;

-- Follows eve's runs: a run with an eve session type, or one that names its
-- session, belongs to that session. The newest run decides the status.
create or replace function "better_supabase"."workflow_sdk_track_eve_run"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
  v_status text;
begin
  if new.attributes ->> '$eve.type' is distinct from 'session' and nullif(new.attributes ->> '$eve.session', '') is null then
    return null;
  end if;
  v_session := coalesce(nullif(new.attributes ->> '$eve.session', ''), new.id);
  v_status := case new.status::text
    when 'completed' then 'ended'
    when 'failed' then 'failed'
    when 'cancelled' then 'cancelled'
    else 'open'
  end;
  insert into workflow.eve_sessions as s (session_id, eve_version, run_id, status)
  values (v_session, new.attributes ->> '$eve.version', new.id, v_status)
  on conflict (session_id) do update set
    eve_version = coalesce(new.attributes ->> '$eve.version', s.eve_version),
    run_id = new.id,
    status = case when s.status = 'stranded' then s.status else v_status end,
    updated_at = now()
  where s.run_id is null or s.run_id = new.id
    or new.created_at >= coalesce((select r.created_at from workflow.workflow_runs r where r.id = s.run_id), '-infinity'::timestamptz);
  insert into workflow.eve_session_runs as sr (run_id, session_id, eve_version, status)
  values (new.id, v_session, new.attributes ->> '$eve.version', new.status::text)
  on conflict (run_id) do update set status = new.status::text, updated_at = now();
  perform "better_supabase"."eve_session_wake"(v_session);
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_sdk_track_eve_run"() from public, anon, authenticated;
create trigger "bsb_workflow_sdk_eve_runs" after insert or update of status on workflow.workflow_runs
  for each row execute function "better_supabase"."workflow_sdk_track_eve_run"();

-- Wakes the session of a run that wrote an event. Other runs cost one lookup.
create or replace function "better_supabase"."workflow_sdk_wake_eve_session"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
begin
  select sr.session_id into v_session from workflow.eve_session_runs sr where sr.run_id = new.run_id;
  if v_session is not null then
    perform "better_supabase"."eve_session_wake"(v_session);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_sdk_wake_eve_session"() from public, anon, authenticated;
create trigger "bsb_workflow_sdk_eve_events" after insert on workflow.workflow_events
  for each row execute function "better_supabase"."workflow_sdk_wake_eve_session"();

-- Takes the lease on a session and returns its row, or no row while another
-- sync job holds the lease.
create or replace function "better_supabase"."eve_session_lease"(sid text, lease_seconds integer default 60)
returns table (
  session_id text,
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint,
  status text,
  lease_id text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_token text := gen_random_uuid()::text;
begin
  insert into workflow.eve_sessions (session_id) values (sid) on conflict (session_id) do nothing;
  return query
    update workflow.eve_sessions s set
      lease_id = v_token,
      leased_at = now(),
      lease_until = now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1)),
      updated_at = now()
    where s.session_id = sid and (s.lease_until is null or s.lease_until < now())
    returning s.session_id, s.tenant_id, s.principal_kind, s.principal_id, s.eve_version, s.chat_id,
      s.record_type, s.record_id, s.run_id, s.read_cursor, s.status, s.lease_id;
end;
$$;

-- Advances the cursor and stores what the job resolved, then frees the lease.
-- synced_at is the time the lease began, so a change after that stays behind.
create or replace function "better_supabase"."eve_session_commit"(
  sid text,
  token text,
  cursor_line bigint,
  tenant text default null,
  principal_kind text default null,
  principal_id text default null,
  chat text default null,
  record_type text default null,
  record_id text default null,
  session_status text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status is not null and session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_commit: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions s set
    read_cursor = greatest(s.read_cursor, coalesce(cursor_line, 0)),
    tenant_id = coalesce(tenant, s.tenant_id),
    principal_kind = coalesce(eve_session_commit.principal_kind, s.principal_kind),
    principal_id = coalesce(eve_session_commit.principal_id, s.principal_id),
    chat_id = coalesce(chat, s.chat_id),
    record_type = coalesce(eve_session_commit.record_type, s.record_type),
    record_id = coalesce(eve_session_commit.record_id, s.record_id),
    status = coalesce(session_status, s.status),
    synced_at = coalesce(s.leased_at, now()),
    lease_id = null,
    lease_until = null,
    updated_at = now()
  where s.session_id = sid and s.lease_id = token;
  return found;
end;
$$;

-- Frees a lease without advancing the cursor, so the next job starts at once.
create or replace function "better_supabase"."eve_session_release"(sid text, token text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update workflow.eve_sessions set lease_id = null, lease_until = null, updated_at = now()
  where session_id = sid and lease_id = token
  returning true;
$$;

-- The sessions whose copy is behind, oldest first: changed since the last sync,
-- or open and not synced for older_than.
create or replace function "better_supabase"."eve_sessions_behind"(older_than interval default '5 minutes', max integer default 100)
returns table (session_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id
  from workflow.eve_sessions s
  where (s.lease_until is null or s.lease_until < now())
    and (
      (s.dirty_at is not null and (s.synced_at is null or s.synced_at < s.dirty_at))
      or (s.status = 'open' and coalesce(s.synced_at, s.created_at) < now() - coalesce(older_than, interval '5 minutes'))
    )
  order by coalesce(s.synced_at, s.created_at)
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- The open sessions that a release other than not_version started, oldest first.
create or replace function "better_supabase"."eve_open_sessions"(not_version text default null, tenant text default null, max integer default 100)
returns table (
  session_id text,
  eve_version text,
  tenant_id text,
  principal_id text,
  chat_id text,
  run_id text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id, s.eve_version, s.tenant_id, s.principal_id, s.chat_id, s.run_id, s.created_at
  from workflow.eve_sessions s
  where s.status = 'open'
    and (not_version is null or s.eve_version is distinct from not_version)
    and (tenant is null or s.tenant_id = tenant)
  order by s.created_at
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- Sets a session's status (for instance stranded) and queues a sync.
create or replace function "better_supabase"."eve_session_mark"(sid text, session_status text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_mark: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions set status = session_status, updated_at = now() where session_id = sid;
  if not found then
    return false;
  end if;
  perform "better_supabase"."eve_session_wake"(sid, 0);
  return true;
end;
$$;
revoke execute on function "better_supabase"."workflow_claim_run_key"(text, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_claim_run_key"(text, interval) to service_role;
revoke execute on function "better_supabase"."workflow_set_run_key"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_set_run_key"(text, text) to service_role;
revoke execute on function "better_supabase"."workflow_release_run_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_release_run_key"(text) to service_role;
revoke execute on function "better_supabase"."workflow_purge_runs"(interval, text[], integer, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_purge_runs"(interval, text[], integer, boolean) to service_role;
revoke execute on function "better_supabase"."workflow_purge_backstops"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_purge_backstops"(integer) to service_role;
revoke execute on function "better_supabase"."workflow_open_hooks"(text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_open_hooks"(text, text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_wake"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_wake"(text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_lease"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_lease"(text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) to service_role;
revoke execute on function "better_supabase"."eve_session_release"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_release"(text, text) to service_role;
revoke execute on function "better_supabase"."eve_sessions_behind"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_sessions_behind"(interval, integer) to service_role;
revoke execute on function "better_supabase"."eve_open_sessions"(text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_open_sessions"(text, text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_mark"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_mark"(text, text) to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_043_workflow_sdk.sql
-- better-supabase module: workflow-sdk
-- @bsb-block-data workflow-sdk
-- @bsb-hash sha256:03d035c6cdd294e29651450c06bd849b42260fb91e90c111f01dfc427c4eff9c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

do $$
declare
  c record;
begin
  for c in select table_name, column_name from information_schema.columns
    where table_schema = 'workflow' and data_type = 'timestamp without time zone'
  loop
    execute format('alter table workflow.%I alter column %I type timestamptz using %I at time zone ''UTC''', c.table_name, c.column_name, c.column_name);
  end loop;
end
$$;

insert into better_supabase.blocks (name, version, mode)
values ('workflow-sdk', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_043_workflow_sdk.sql
-- better-supabase module: workflow-sdk
-- @bsb-block workflow-sdk@10 managed
-- @bsb-hash sha256:77ac4d0d3298dfbeca35b9ad27c072f12bdf21df50082b01c9696220fcda72b4
-- The tables of the Workflow SDK World (@workflow/world-postgres 5.5.0) in the workflow schema, closed to the API roles; a trigger that copies each run into workflow_runs, a pg_net dispatcher for the delivery queue on a pg_cron schedule, start idempotency keys, a list of the hooks open runs wait on, a purge of ended runs, the purge backstops of zero-retention runs and the eve projection tables with the jobs that copy eve sessions into the blocks.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges for role postgres in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges for role postgres in schema "app_private" revoke all on functions from public, anon, authenticated;
-- The Workflow SDK World's tables (@workflow/world-postgres 5.5.0).
-- Only the service role reads them: the app reads runs from workflow_runs in
-- the workflows module.
create schema if not exists workflow;

create type workflow.status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');

create type workflow.step_status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');

create type workflow.wait_status as enum ('waiting', 'completed');

create table workflow.workflow_event_slots (
  "run_id" character varying not null,
  "seq_in_band" integer not null default 1,
  constraint "workflow_event_slots_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_events (
  "id" character varying not null,
  "type" character varying not null,
  "correlation_id" character varying,
  "created_at" timestamp with time zone not null default now(),
  "run_id" character varying not null,
  "payload" jsonb,
  "payload_cbor" bytea,
  "spec_version" integer,
  "resume_id" character varying,
  "resume_payload_digest" character varying,
  constraint "workflow_events_run_id_id_pk" PRIMARY KEY (run_id, id)
);

create index workflow_events_correlation_id_index ON workflow.workflow_events USING btree (correlation_id);

create unique index workflow_events_entity_creation_unique ON workflow.workflow_events USING btree (run_id, correlation_id, type) WHERE ((type)::text = ANY ((ARRAY['step_created'::character varying, 'hook_created'::character varying, 'wait_created'::character varying, 'attr_set'::character varying])::text[]));

create unique index workflow_events_hook_resume_unique ON workflow.workflow_events USING btree (run_id, resume_id) WHERE (((type)::text = 'hook_received'::text) AND (resume_id IS NOT NULL));

create table workflow.workflow_hooks (
  "run_id" character varying not null,
  "hook_id" character varying not null,
  "token" character varying not null,
  "owner_id" character varying not null,
  "project_id" character varying not null,
  "environment" character varying not null,
  "created_at" timestamp with time zone not null default now(),
  "metadata" jsonb,
  "metadata_cbor" bytea,
  "spec_version" integer,
  "is_webhook" boolean default true,
  "is_system" boolean default false,
  "resume_context" bytea,
  "token_retention_until" timestamp with time zone,
  "claimed_from" bytea,
  "claims_token" boolean not null default false,
  constraint "workflow_hooks_pkey" PRIMARY KEY (hook_id)
);

create index workflow_hooks_run_id_index ON workflow.workflow_hooks USING btree (run_id);

create unique index workflow_hooks_token_claim_unique ON workflow.workflow_hooks USING btree (token) WHERE claims_token;

create index workflow_hooks_token_index ON workflow.workflow_hooks USING btree (token);

create table workflow.workflow_invocations (
  "sequence" bigserial,
  "run_id" character varying not null,
  "request_id" character varying not null,
  "payload" bytea,
  "fingerprint" character varying,
  "result" bytea,
  "created_at" timestamp with time zone not null default now(),
  "responded_at" timestamp with time zone,
  "expired_at" timestamp with time zone,
  "result_version" integer not null default 0,
  constraint "workflow_invocations_pkey" PRIMARY KEY (run_id, request_id)
);

create index workflow_invocations_pending ON workflow.workflow_invocations USING btree (run_id, sequence) WHERE (responded_at IS NULL);

create table workflow.workflow_job_lock_holders (
  "worker_id" text not null,
  "renewed_at" timestamp with time zone not null default now(),
  constraint "workflow_job_lock_holders_pkey" PRIMARY KEY (worker_id)
);

create table workflow.workflow_rate_limits (
  "scope" character varying not null,
  "key" character varying not null,
  "tat_us" bigint,
  constraint "workflow_rate_limits_scope_key_pk" PRIMARY KEY (scope, key)
);

create table workflow.workflow_run_delivery_leases (
  "run_id" character varying not null,
  "owner_job_id" bigint not null,
  "wake" jsonb,
  "wake_resume" boolean not null default false,
  "deferred" jsonb not null default '[]'::jsonb,
  "claimed_at" timestamp with time zone not null default now(),
  constraint "workflow_run_delivery_leases_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_runs (
  "id" character varying not null,
  "output" jsonb,
  "deployment_id" character varying not null,
  "status" workflow.status not null,
  "name" character varying not null,
  "execution_context" jsonb,
  "input" jsonb,
  "error" text,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "completed_at" timestamp with time zone,
  "started_at" timestamp with time zone,
  "output_cbor" bytea,
  "execution_context_cbor" bytea,
  "input_cbor" bytea,
  "expired_at" timestamp with time zone,
  "spec_version" character varying,
  "error_cbor" bytea,
  "error_code" character varying,
  "attributes" jsonb not null default '{}'::jsonb,
  "encryption_public_key" character varying,
  "dynamic_workflow_code_cbor" bytea,
  "start_hook_cbor" bytea,
  "job_prefix" character varying,
  "wake_pending" boolean not null default false,
  constraint "workflow_runs_pkey" PRIMARY KEY (id)
);

create index workflow_runs_name_index ON workflow.workflow_runs USING btree (name);

create index workflow_runs_status_index ON workflow.workflow_runs USING btree (status);

create table workflow.workflow_snapshots (
  "run_id" character varying not null,
  "data" bytea not null,
  "events_cursor" character varying,
  "created_at" timestamp with time zone not null default now(),
  constraint "workflow_snapshots_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_start_hook_admissions (
  "run_id" character varying not null,
  "token" character varying not null,
  "decision" character varying not null,
  "conflicting_run_id" character varying,
  "created_at" timestamp with time zone not null default now(),
  constraint "workflow_start_hook_admissions_pkey" PRIMARY KEY (run_id)
);

create index workflow_start_hook_admissions_created_at_index ON workflow.workflow_start_hook_admissions USING btree (created_at);

create table workflow.workflow_steps (
  "run_id" character varying not null,
  "step_id" character varying not null,
  "step_name" character varying not null,
  "status" workflow.step_status not null,
  "input" jsonb,
  "output" jsonb,
  "error" text,
  "attempt" integer not null,
  "started_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "retry_after" timestamp with time zone,
  "input_cbor" bytea,
  "output_cbor" bytea,
  "error_cbor" bytea,
  "spec_version" integer,
  constraint "workflow_steps_pkey" PRIMARY KEY (step_id)
);

create index workflow_steps_run_id_index ON workflow.workflow_steps USING btree (run_id);

create index workflow_steps_status_index ON workflow.workflow_steps USING btree (status);

create table workflow.workflow_stream_chunks (
  "id" character varying not null,
  "stream_id" character varying not null,
  "data" bytea not null,
  "created_at" timestamp with time zone not null default now(),
  "eof" boolean not null,
  "run_id" character varying,
  constraint "workflow_stream_chunks_stream_id_id_pk" PRIMARY KEY (stream_id, id)
);

create index workflow_stream_chunks_run_id_index ON workflow.workflow_stream_chunks USING btree (run_id);

create table workflow.workflow_waits (
  "wait_id" character varying not null,
  "run_id" character varying not null,
  "status" workflow.wait_status not null,
  "resume_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "spec_version" integer,
  constraint "workflow_waits_pkey" PRIMARY KEY (wait_id)
);

create index workflow_waits_run_id_index ON workflow.workflow_waits USING btree (run_id);

-- One row per start idempotency key: startFor claims the key before it starts
-- a run, so two concurrent starts with one key start one run. run_id is null
-- while the start that claimed it is still running.
create table workflow.workflow_run_keys (
  key text primary key constraint bsb_workflow_run_keys_key_check check (length(key) >= 1 and length(key) <= 500),
  run_id character varying,
  claimed_at timestamptz not null default now()
);
create index workflow_run_keys_run_id_idx on workflow.workflow_run_keys (run_id);
-- The purge backstops of zero-retention runs. world-postgres adds one through
-- Graphile Worker's add_job in the transaction that finishes such a run; this
-- World runs no Graphile Worker, so it points GRAPHILE_WORKER_SCHEMA at
-- workflow, where add_job records the run here and workflow_purge_backstops
-- deletes its data once due if the purge after the commit did not.
create table workflow.workflow_purge_backstops (
  run_id character varying primary key,
  due_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index workflow_purge_backstops_due_at_idx on workflow.workflow_purge_backstops (due_at);
create or replace function workflow.add_job(
  identifier text,
  payload json default null,
  run_at timestamptz default null,
  max_attempts integer default null,
  job_key text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run text := payload ->> 'runId';
begin
  if identifier not like '%purge' or v_run is null then
    raise exception 'Only the purge backstops of @workflow/world-postgres go through workflow.add_job'
      using errcode = '0A000', hint = 'WORKFLOW_GRAPHILE_UNSUPPORTED', detail = 'task ' || coalesce(identifier, 'null');
  end if;
  insert into workflow.workflow_purge_backstops (run_id, due_at)
    values (v_run, coalesce(run_at, now()))
    on conflict (run_id) do nothing;
end;
$$;
revoke execute on function workflow.add_job(text, json, timestamptz, integer, text) from public, anon, authenticated;
grant execute on function workflow.add_job(text, json, timestamptz, integer, text) to service_role;
-- The eve projection (eve sessions copied into the blocks by syncSession).
-- session_id is the id of the session's first run. read_cursor is the next
-- line of the session stream to read. A session is behind while dirty_at is
-- later than synced_at; the lease keeps two sync jobs off one session.
create table workflow.eve_sessions (
  session_id text primary key constraint bsb_eve_sessions_session_id_check check (length(session_id) >= 1 and length(session_id) <= 200),
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint not null default 0 constraint bsb_eve_sessions_read_cursor_check check (read_cursor >= 0),
  status text not null default 'open' constraint bsb_eve_sessions_status_check check (status in ('open', 'ended', 'failed', 'cancelled', 'stranded')),
  dirty_at timestamptz,
  synced_at timestamptz,
  lease_id text,
  leased_at timestamptz,
  lease_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index eve_sessions_dirty_idx on workflow.eve_sessions (dirty_at) where dirty_at is not null;
create index eve_sessions_open_idx on workflow.eve_sessions (eve_version) where status = 'open';
create table workflow.eve_session_runs (
  run_id text primary key,
  session_id text not null references workflow.eve_sessions (session_id) on delete cascade,
  eve_version text,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index eve_session_runs_session_idx on workflow.eve_session_runs (session_id);
revoke all on schema workflow from public, anon, authenticated;
grant usage on schema workflow to service_role;
alter table workflow.eve_session_runs enable row level security;
revoke all on workflow.eve_session_runs from public, anon, authenticated;
grant all on workflow.eve_session_runs to service_role;
alter table workflow.eve_sessions enable row level security;
revoke all on workflow.eve_sessions from public, anon, authenticated;
grant all on workflow.eve_sessions to service_role;
alter table workflow.workflow_event_slots enable row level security;
revoke all on workflow.workflow_event_slots from public, anon, authenticated;
grant all on workflow.workflow_event_slots to service_role;
alter table workflow.workflow_events enable row level security;
revoke all on workflow.workflow_events from public, anon, authenticated;
grant all on workflow.workflow_events to service_role;
alter table workflow.workflow_hooks enable row level security;
revoke all on workflow.workflow_hooks from public, anon, authenticated;
grant all on workflow.workflow_hooks to service_role;
alter table workflow.workflow_invocations enable row level security;
revoke all on workflow.workflow_invocations from public, anon, authenticated;
grant all on workflow.workflow_invocations to service_role;
alter table workflow.workflow_job_lock_holders enable row level security;
revoke all on workflow.workflow_job_lock_holders from public, anon, authenticated;
grant all on workflow.workflow_job_lock_holders to service_role;
alter table workflow.workflow_purge_backstops enable row level security;
revoke all on workflow.workflow_purge_backstops from public, anon, authenticated;
grant all on workflow.workflow_purge_backstops to service_role;
alter table workflow.workflow_rate_limits enable row level security;
revoke all on workflow.workflow_rate_limits from public, anon, authenticated;
grant all on workflow.workflow_rate_limits to service_role;
alter table workflow.workflow_run_delivery_leases enable row level security;
revoke all on workflow.workflow_run_delivery_leases from public, anon, authenticated;
grant all on workflow.workflow_run_delivery_leases to service_role;
alter table workflow.workflow_run_keys enable row level security;
revoke all on workflow.workflow_run_keys from public, anon, authenticated;
grant all on workflow.workflow_run_keys to service_role;
alter table workflow.workflow_runs enable row level security;
revoke all on workflow.workflow_runs from public, anon, authenticated;
grant all on workflow.workflow_runs to service_role;
alter table workflow.workflow_snapshots enable row level security;
revoke all on workflow.workflow_snapshots from public, anon, authenticated;
grant all on workflow.workflow_snapshots to service_role;
alter table workflow.workflow_start_hook_admissions enable row level security;
revoke all on workflow.workflow_start_hook_admissions from public, anon, authenticated;
grant all on workflow.workflow_start_hook_admissions to service_role;
alter table workflow.workflow_steps enable row level security;
revoke all on workflow.workflow_steps from public, anon, authenticated;
grant all on workflow.workflow_steps to service_role;
alter table workflow.workflow_stream_chunks enable row level security;
revoke all on workflow.workflow_stream_chunks from public, anon, authenticated;
grant all on workflow.workflow_stream_chunks to service_role;
alter table workflow.workflow_waits enable row level security;
revoke all on workflow.workflow_waits from public, anon, authenticated;
grant all on workflow.workflow_waits to service_role;
grant usage, select on sequence workflow.workflow_invocations_sequence_seq to service_role;
create index workflow_runs_attributes_idx on workflow.workflow_runs using gin (attributes jsonb_path_ops);

-- Copies each World run into workflow_runs: its tenant and actor come from
-- the bsb.tenant and bsb.actor attributes that startFor sets. A run with an
-- actor keeps its tenant only when the actor holds workflow.run there; a
-- run without one, or one with bsb.principal_kind (a runAs start, whose
-- actor is the user who triggered it), was started by the server, which is
-- trusted. bsb.subject
-- (type/id), bsb.principal_kind, bsb.principal, bsb.mode and bsb.trigger_node
-- fill the run's subject, principal, mode and trigger node.
create or replace function "app_private"."workflow_sdk_mirror_run"()
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
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflows.run'), false) then
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
    new.started_at,
    new.completed_at,
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
revoke execute on function "app_private"."workflow_sdk_mirror_run"() from public, anon, authenticated;
create trigger "bsb_workflow_sdk_runs_mirror" after insert or update of status, attributes, error on workflow.workflow_runs
  for each row execute function "app_private"."workflow_sdk_mirror_run"();

-- pg_net delivery: posts up to batch due messages to the flow route in the
-- Vault secret workflow_flow_url, signed with workflow_delivery_secret
-- (x-bsb-signature: t=<unix>,v1=hex(hmac_sha256(t.job.body))). The body is
-- the stored message; the route completes or fails the job, so a delivery
-- whose response is lost runs again after the lease.
create or replace function "app_private"."dispatch_workflow_deliveries"(batch integer default 20)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
  v_extra jsonb;
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
  -- Extra headers (a deployment protection bypass, for one) as a JSON object.
  select ds.decrypted_secret::jsonb into v_extra from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_headers';
  if v_extra is not null and pg_catalog.jsonb_typeof(v_extra) <> 'object' then
    raise exception 'The Vault secret workflow_delivery_headers must be a JSON object of header names and values' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from "better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := 'workflow_deliveries' || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, coalesce(v_extra, '{}'::jsonb) || jsonb_build_object(
        'content-type', 'application/json',
        'x-bsb-job', v_job_header,
        'x-bsb-signature', 't=' || v_t || ',v1=' || encode(extensions.hmac(v_t || '.' || v_job_header || '.' || v_body::text, v_secret, 'sha256'), 'hex')
      ), 30000;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."dispatch_workflow_deliveries"(integer) from public, anon, authenticated;
grant execute on function "app_private"."dispatch_workflow_deliveries"(integer) to service_role;

-- Claims a start key: claimed is true when this caller may start the run,
-- either because the key is new or because the start that claimed it left no
-- run for stale_after. Otherwise run_id is the run of the earlier start (null
-- while that start is still running).
create or replace function "app_private"."workflow_claim_run_key"(run_key text, stale_after interval default '5 minutes')
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
create or replace function "app_private"."workflow_set_run_key"(run_key text, run text)
returns void
language sql
security definer
set search_path = ''
as $$
  update workflow.workflow_run_keys set run_id = run, claimed_at = now() where key = run_key;
$$;

-- Frees a key whose start failed before it created a run.
create or replace function "app_private"."workflow_release_run_key"(run_key text)
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
-- With skip_unprojected, a run of an eve session stays until the session's
-- copy in the blocks is current (the session was synced after its last change
-- and is no longer open).

create or replace function "app_private"."workflow_purge_runs"(
  older_than interval default '30 days',
  statuses text[] default array['completed', 'failed', 'cancelled'],
  batch integer default 500,
  skip_unprojected boolean default false
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
      and coalesce(r.completed_at, r.updated_at) < now() - coalesce(older_than, interval '30 days')
      and not (coalesce(skip_unprojected, false) and exists (
        select 1 from workflow.eve_session_runs sr
        join workflow.eve_sessions es on es.session_id = sr.session_id
        where sr.run_id = r.id
          and (es.status = 'open' or es.synced_at is null or es.dirty_at > es.synced_at)
      ))
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
  delete from workflow.workflow_purge_backstops where run_id = any (v_ids);
  delete from workflow.eve_session_runs where run_id = any (v_ids);
  delete from workflow.workflow_runs where id = any (v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Runs up to batch due purge backstops: a run that ended with the $retention
-- attribute 0 and still has its data (expired_at is null) gets the purge
-- @workflow/world-postgres runs after the terminal write, in one transaction.
-- The run row is updated first, so late step and stream writes, which lock it
-- to read expired_at, wait for the purge. Returns how many runs it purged.
create or replace function "app_private"."workflow_purge_backstops"(batch integer default 100)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_due text[];
  v_ids text[];
begin
  with due as (
    delete from workflow.workflow_purge_backstops b
    where b.run_id in (
      select d.run_id from workflow.workflow_purge_backstops d
      where d.due_at <= now()
      order by d.due_at
      limit least(greatest(coalesce(batch, 100), 1), 1000)
      for update skip locked
    )
    returning b.run_id
  )
  select coalesce(array_agg(due.run_id), '{}') into v_due from due;
  if cardinality(v_due) = 0 then
    return 0;
  end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select r.id from workflow.workflow_runs r
    where r.id = any (v_due)
      and r.status::text in ('completed', 'failed', 'cancelled')
      and r.attributes ->> '$retention' = '0'
      and r.expired_at is null
    for update
  ) x;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  update workflow.workflow_runs set expired_at = now(),
    input_cbor = null, input = null, output_cbor = null, output = null,
    error_cbor = null, error = null, dynamic_workflow_code_cbor = null
    where id = any (v_ids);
  update workflow.workflow_steps set input_cbor = null, input = null,
    output_cbor = null, output = null, error_cbor = null, error = null
    where run_id = any (v_ids);
  update workflow.workflow_events set payload_cbor = null, payload = null, resume_payload_digest = null
    where run_id = any (v_ids);
  update workflow.workflow_hooks set metadata_cbor = null, metadata = null, resume_context = null
    where run_id = any (v_ids);
  update workflow.workflow_stream_chunks set data = ''::bytea where run_id = any (v_ids);
  update workflow.workflow_invocations set payload = null, result = null, fingerprint = null, expired_at = now()
    where run_id = any (v_ids);
  delete from workflow.workflow_snapshots where run_id = any (v_ids);
  return cardinality(v_ids);
end;
$$;

-- The hooks of pending and running runs, newest first: what a run waits on.
-- The token is left out; the app that created a hook knows it.
create or replace function "app_private"."workflow_open_hooks"(
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
  metadata_cbor bytea,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select h.hook_id::text, h.run_id::text, r.name::text,
    r.attributes ->> 'bsb.tenant', r.attributes ->> 'bsb.actor',
    h.metadata, h.metadata_cbor, h.created_at
  from workflow.workflow_hooks h
  join workflow.workflow_runs r on r.id = h.run_id
  where r.status::text in ('pending', 'running')
    and not coalesce(h.is_system, false)
    and (workflow_open_hooks.tenant is null or r.attributes ->> 'bsb.tenant' = workflow_open_hooks.tenant)
    and (workflow_open_hooks.workflow_name is null or r.name = workflow_open_hooks.workflow_name)
  order by h.created_at desc
  limit least(greatest(coalesce(workflow_open_hooks.max, 50), 1), 500);
$$;
-- Marks a session as behind and queues its sync job. The job is debounced: a
-- job that has not started yet absorbs later wake-ups of the same session.
create or replace function "app_private"."eve_session_wake"(sid text, delay_seconds integer default 2)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into workflow.eve_sessions as s (session_id, dirty_at) values (sid, now())
  on conflict (session_id) do update set dirty_at = now(), updated_at = now();
  perform "better_supabase"."enqueue_job"(queue => 'eve_session_sync', payload => jsonb_build_object('sessionId', sid), delay => greatest(coalesce(delay_seconds, 0), 0), dedupe_key => 'eve:' || sid, dedupe_running => false);
end;
$$;

-- Follows eve's runs: a run with an eve session type, or one that names its
-- session, belongs to that session. The newest run decides the status.
create or replace function "app_private"."workflow_sdk_track_eve_run"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
  v_status text;
begin
  if new.attributes ->> '$eve.type' is distinct from 'session' and nullif(new.attributes ->> '$eve.session', '') is null then
    return null;
  end if;
  v_session := coalesce(nullif(new.attributes ->> '$eve.session', ''), new.id);
  v_status := case new.status::text
    when 'completed' then 'ended'
    when 'failed' then 'failed'
    when 'cancelled' then 'cancelled'
    else 'open'
  end;
  insert into workflow.eve_sessions as s (session_id, eve_version, run_id, status)
  values (v_session, new.attributes ->> '$eve.version', new.id, v_status)
  on conflict (session_id) do update set
    eve_version = coalesce(new.attributes ->> '$eve.version', s.eve_version),
    run_id = new.id,
    status = case when s.status = 'stranded' then s.status else v_status end,
    updated_at = now()
  where s.run_id is null or s.run_id = new.id
    or new.created_at >= coalesce((select r.created_at from workflow.workflow_runs r where r.id = s.run_id), '-infinity'::timestamptz);
  insert into workflow.eve_session_runs as sr (run_id, session_id, eve_version, status)
  values (new.id, v_session, new.attributes ->> '$eve.version', new.status::text)
  on conflict (run_id) do update set status = new.status::text, updated_at = now();
  perform "app_private"."eve_session_wake"(v_session);
  return null;
end;
$$;
revoke execute on function "app_private"."workflow_sdk_track_eve_run"() from public, anon, authenticated;
create trigger "bsb_workflow_sdk_eve_runs" after insert or update of status on workflow.workflow_runs
  for each row execute function "app_private"."workflow_sdk_track_eve_run"();

-- Wakes the session of a run that wrote an event. Other runs cost one lookup.
create or replace function "app_private"."workflow_sdk_wake_eve_session"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
begin
  select sr.session_id into v_session from workflow.eve_session_runs sr where sr.run_id = new.run_id;
  if v_session is not null then
    perform "app_private"."eve_session_wake"(v_session);
  end if;
  return null;
end;
$$;
revoke execute on function "app_private"."workflow_sdk_wake_eve_session"() from public, anon, authenticated;
create trigger "bsb_workflow_sdk_eve_events" after insert on workflow.workflow_events
  for each row execute function "app_private"."workflow_sdk_wake_eve_session"();

-- Takes the lease on a session and returns its row, or no row while another
-- sync job holds the lease.
create or replace function "app_private"."eve_session_lease"(sid text, lease_seconds integer default 60)
returns table (
  session_id text,
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint,
  status text,
  lease_id text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_token text := gen_random_uuid()::text;
begin
  insert into workflow.eve_sessions (session_id) values (sid) on conflict (session_id) do nothing;
  return query
    update workflow.eve_sessions s set
      lease_id = v_token,
      leased_at = now(),
      lease_until = now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1)),
      updated_at = now()
    where s.session_id = sid and (s.lease_until is null or s.lease_until < now())
    returning s.session_id, s.tenant_id, s.principal_kind, s.principal_id, s.eve_version, s.chat_id,
      s.record_type, s.record_id, s.run_id, s.read_cursor, s.status, s.lease_id;
end;
$$;

-- Advances the cursor and stores what the job resolved, then frees the lease.
-- synced_at is the time the lease began, so a change after that stays behind.
create or replace function "app_private"."eve_session_commit"(
  sid text,
  token text,
  cursor_line bigint,
  tenant text default null,
  principal_kind text default null,
  principal_id text default null,
  chat text default null,
  record_type text default null,
  record_id text default null,
  session_status text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status is not null and session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_commit: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions s set
    read_cursor = greatest(s.read_cursor, coalesce(cursor_line, 0)),
    tenant_id = coalesce(tenant, s.tenant_id),
    principal_kind = coalesce(eve_session_commit.principal_kind, s.principal_kind),
    principal_id = coalesce(eve_session_commit.principal_id, s.principal_id),
    chat_id = coalesce(chat, s.chat_id),
    record_type = coalesce(eve_session_commit.record_type, s.record_type),
    record_id = coalesce(eve_session_commit.record_id, s.record_id),
    status = coalesce(session_status, s.status),
    synced_at = coalesce(s.leased_at, now()),
    lease_id = null,
    lease_until = null,
    updated_at = now()
  where s.session_id = sid and s.lease_id = token;
  return found;
end;
$$;

-- Frees a lease without advancing the cursor, so the next job starts at once.
create or replace function "app_private"."eve_session_release"(sid text, token text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update workflow.eve_sessions set lease_id = null, lease_until = null, updated_at = now()
  where session_id = sid and lease_id = token
  returning true;
$$;

-- The sessions whose copy is behind, oldest first: changed since the last sync,
-- or open and not synced for older_than.
create or replace function "app_private"."eve_sessions_behind"(older_than interval default '5 minutes', max integer default 100)
returns table (session_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id
  from workflow.eve_sessions s
  where (s.lease_until is null or s.lease_until < now())
    and (
      (s.dirty_at is not null and (s.synced_at is null or s.synced_at < s.dirty_at))
      or (s.status = 'open' and coalesce(s.synced_at, s.created_at) < now() - coalesce(older_than, interval '5 minutes'))
    )
  order by coalesce(s.synced_at, s.created_at)
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- The open sessions that a release other than not_version started, oldest first.
create or replace function "app_private"."eve_open_sessions"(not_version text default null, tenant text default null, max integer default 100)
returns table (
  session_id text,
  eve_version text,
  tenant_id text,
  principal_id text,
  chat_id text,
  run_id text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id, s.eve_version, s.tenant_id, s.principal_id, s.chat_id, s.run_id, s.created_at
  from workflow.eve_sessions s
  where s.status = 'open'
    and (not_version is null or s.eve_version is distinct from not_version)
    and (tenant is null or s.tenant_id = tenant)
  order by s.created_at
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- Sets a session's status (for instance stranded) and queues a sync.
create or replace function "app_private"."eve_session_mark"(sid text, session_status text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_mark: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions set status = session_status, updated_at = now() where session_id = sid;
  if not found then
    return false;
  end if;
  perform "app_private"."eve_session_wake"(sid, 0);
  return true;
end;
$$;
revoke execute on function "app_private"."workflow_claim_run_key"(text, interval) from public, anon, authenticated;
grant execute on function "app_private"."workflow_claim_run_key"(text, interval) to service_role;
revoke execute on function "app_private"."workflow_set_run_key"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."workflow_set_run_key"(text, text) to service_role;
revoke execute on function "app_private"."workflow_release_run_key"(text) from public, anon, authenticated;
grant execute on function "app_private"."workflow_release_run_key"(text) to service_role;
revoke execute on function "app_private"."workflow_purge_runs"(interval, text[], integer, boolean) from public, anon, authenticated;
grant execute on function "app_private"."workflow_purge_runs"(interval, text[], integer, boolean) to service_role;
revoke execute on function "app_private"."workflow_purge_backstops"(integer) from public, anon, authenticated;
grant execute on function "app_private"."workflow_purge_backstops"(integer) to service_role;
revoke execute on function "app_private"."workflow_open_hooks"(text, text, integer) from public, anon, authenticated;
grant execute on function "app_private"."workflow_open_hooks"(text, text, integer) to service_role;
revoke execute on function "app_private"."eve_session_wake"(text, integer) from public, anon, authenticated;
grant execute on function "app_private"."eve_session_wake"(text, integer) to service_role;
revoke execute on function "app_private"."eve_session_lease"(text, integer) from public, anon, authenticated;
grant execute on function "app_private"."eve_session_lease"(text, integer) to service_role;
revoke execute on function "app_private"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function "app_private"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) to service_role;
revoke execute on function "app_private"."eve_session_release"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."eve_session_release"(text, text) to service_role;
revoke execute on function "app_private"."eve_sessions_behind"(interval, integer) from public, anon, authenticated;
grant execute on function "app_private"."eve_sessions_behind"(interval, integer) to service_role;
revoke execute on function "app_private"."eve_open_sessions"(text, text, integer) from public, anon, authenticated;
grant execute on function "app_private"."eve_open_sessions"(text, text, integer) to service_role;
revoke execute on function "app_private"."eve_session_mark"(text, text) from public, anon, authenticated;
grant execute on function "app_private"."eve_session_mark"(text, text) to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_043_workflow_sdk.sql
-- better-supabase module: workflow-sdk
-- @bsb-block-data workflow-sdk
-- @bsb-hash sha256:03d035c6cdd294e29651450c06bd849b42260fb91e90c111f01dfc427c4eff9c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

do $$
declare
  c record;
begin
  for c in select table_name, column_name from information_schema.columns
    where table_schema = 'workflow' and data_type = 'timestamp without time zone'
  loop
    execute format('alter table workflow.%I alter column %I type timestamptz using %I at time zone ''UTC''', c.table_name, c.column_name, c.column_name);
  end loop;
end
$$;

insert into better_supabase.blocks (name, version, mode)
values ('workflow-sdk', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_043_workflow_sdk.sql
-- better-supabase module: workflow-sdk
-- @bsb-block workflow-sdk@10 managed
-- @bsb-hash sha256:d5bcf27a72b2c5bcb3b324b3b842e20751668a91a4369b0c3b1e75c81c736964
-- The tables of the Workflow SDK World (@workflow/world-postgres 5.5.0) in the workflow schema, closed to the API roles; a trigger that copies each run into workflow_runs, a pg_net dispatcher for the delivery queue on a pg_cron schedule, start idempotency keys, a list of the hooks open runs wait on, a purge of ended runs, the purge backstops of zero-retention runs and the eve projection tables with the jobs that copy eve sessions into the blocks.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The Workflow SDK World's tables (@workflow/world-postgres 5.5.0).
-- Only the service role reads them: the app reads runs from workflow_runs in
-- the workflows module.
create schema if not exists workflow;

create type workflow.status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');

create type workflow.step_status as enum ('pending', 'running', 'completed', 'failed', 'cancelled');

create type workflow.wait_status as enum ('waiting', 'completed');

create table workflow.workflow_event_slots (
  "run_id" character varying not null,
  "seq_in_band" integer not null default 1,
  constraint "workflow_event_slots_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_events (
  "id" character varying not null,
  "type" character varying not null,
  "correlation_id" character varying,
  "created_at" timestamp with time zone not null default now(),
  "run_id" character varying not null,
  "payload" jsonb,
  "payload_cbor" bytea,
  "spec_version" integer,
  "resume_id" character varying,
  "resume_payload_digest" character varying,
  constraint "workflow_events_run_id_id_pk" PRIMARY KEY (run_id, id)
);

create index workflow_events_correlation_id_index ON workflow.workflow_events USING btree (correlation_id);

create unique index workflow_events_entity_creation_unique ON workflow.workflow_events USING btree (run_id, correlation_id, type) WHERE ((type)::text = ANY ((ARRAY['step_created'::character varying, 'hook_created'::character varying, 'wait_created'::character varying, 'attr_set'::character varying])::text[]));

create unique index workflow_events_hook_resume_unique ON workflow.workflow_events USING btree (run_id, resume_id) WHERE (((type)::text = 'hook_received'::text) AND (resume_id IS NOT NULL));

create table workflow.workflow_hooks (
  "run_id" character varying not null,
  "hook_id" character varying not null,
  "token" character varying not null,
  "owner_id" character varying not null,
  "project_id" character varying not null,
  "environment" character varying not null,
  "created_at" timestamp with time zone not null default now(),
  "metadata" jsonb,
  "metadata_cbor" bytea,
  "spec_version" integer,
  "is_webhook" boolean default true,
  "is_system" boolean default false,
  "resume_context" bytea,
  "token_retention_until" timestamp with time zone,
  "claimed_from" bytea,
  "claims_token" boolean not null default false,
  constraint "workflow_hooks_pkey" PRIMARY KEY (hook_id)
);

create index workflow_hooks_run_id_index ON workflow.workflow_hooks USING btree (run_id);

create unique index workflow_hooks_token_claim_unique ON workflow.workflow_hooks USING btree (token) WHERE claims_token;

create index workflow_hooks_token_index ON workflow.workflow_hooks USING btree (token);

create table workflow.workflow_invocations (
  "sequence" bigserial,
  "run_id" character varying not null,
  "request_id" character varying not null,
  "payload" bytea,
  "fingerprint" character varying,
  "result" bytea,
  "created_at" timestamp with time zone not null default now(),
  "responded_at" timestamp with time zone,
  "expired_at" timestamp with time zone,
  "result_version" integer not null default 0,
  constraint "workflow_invocations_pkey" PRIMARY KEY (run_id, request_id)
);

create index workflow_invocations_pending ON workflow.workflow_invocations USING btree (run_id, sequence) WHERE (responded_at IS NULL);

create table workflow.workflow_job_lock_holders (
  "worker_id" text not null,
  "renewed_at" timestamp with time zone not null default now(),
  constraint "workflow_job_lock_holders_pkey" PRIMARY KEY (worker_id)
);

create table workflow.workflow_rate_limits (
  "scope" character varying not null,
  "key" character varying not null,
  "tat_us" bigint,
  constraint "workflow_rate_limits_scope_key_pk" PRIMARY KEY (scope, key)
);

create table workflow.workflow_run_delivery_leases (
  "run_id" character varying not null,
  "owner_job_id" bigint not null,
  "wake" jsonb,
  "wake_resume" boolean not null default false,
  "deferred" jsonb not null default '[]'::jsonb,
  "claimed_at" timestamp with time zone not null default now(),
  constraint "workflow_run_delivery_leases_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_runs (
  "id" character varying not null,
  "output" jsonb,
  "deployment_id" character varying not null,
  "status" workflow.status not null,
  "name" character varying not null,
  "execution_context" jsonb,
  "input" jsonb,
  "error" text,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "completed_at" timestamp with time zone,
  "started_at" timestamp with time zone,
  "output_cbor" bytea,
  "execution_context_cbor" bytea,
  "input_cbor" bytea,
  "expired_at" timestamp with time zone,
  "spec_version" character varying,
  "error_cbor" bytea,
  "error_code" character varying,
  "attributes" jsonb not null default '{}'::jsonb,
  "encryption_public_key" character varying,
  "dynamic_workflow_code_cbor" bytea,
  "start_hook_cbor" bytea,
  "job_prefix" character varying,
  "wake_pending" boolean not null default false,
  constraint "workflow_runs_pkey" PRIMARY KEY (id)
);

create index workflow_runs_name_index ON workflow.workflow_runs USING btree (name);

create index workflow_runs_status_index ON workflow.workflow_runs USING btree (status);

create table workflow.workflow_snapshots (
  "run_id" character varying not null,
  "data" bytea not null,
  "events_cursor" character varying,
  "created_at" timestamp with time zone not null default now(),
  constraint "workflow_snapshots_pkey" PRIMARY KEY (run_id)
);

create table workflow.workflow_start_hook_admissions (
  "run_id" character varying not null,
  "token" character varying not null,
  "decision" character varying not null,
  "conflicting_run_id" character varying,
  "created_at" timestamp with time zone not null default now(),
  constraint "workflow_start_hook_admissions_pkey" PRIMARY KEY (run_id)
);

create index workflow_start_hook_admissions_created_at_index ON workflow.workflow_start_hook_admissions USING btree (created_at);

create table workflow.workflow_steps (
  "run_id" character varying not null,
  "step_id" character varying not null,
  "step_name" character varying not null,
  "status" workflow.step_status not null,
  "input" jsonb,
  "output" jsonb,
  "error" text,
  "attempt" integer not null,
  "started_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "retry_after" timestamp with time zone,
  "input_cbor" bytea,
  "output_cbor" bytea,
  "error_cbor" bytea,
  "spec_version" integer,
  constraint "workflow_steps_pkey" PRIMARY KEY (step_id)
);

create index workflow_steps_run_id_index ON workflow.workflow_steps USING btree (run_id);

create index workflow_steps_status_index ON workflow.workflow_steps USING btree (status);

create table workflow.workflow_stream_chunks (
  "id" character varying not null,
  "stream_id" character varying not null,
  "data" bytea not null,
  "created_at" timestamp with time zone not null default now(),
  "eof" boolean not null,
  "run_id" character varying,
  constraint "workflow_stream_chunks_stream_id_id_pk" PRIMARY KEY (stream_id, id)
);

create index workflow_stream_chunks_run_id_index ON workflow.workflow_stream_chunks USING btree (run_id);

create table workflow.workflow_waits (
  "wait_id" character varying not null,
  "run_id" character varying not null,
  "status" workflow.wait_status not null,
  "resume_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone not null default now(),
  "updated_at" timestamp with time zone not null default now(),
  "spec_version" integer,
  constraint "workflow_waits_pkey" PRIMARY KEY (wait_id)
);

create index workflow_waits_run_id_index ON workflow.workflow_waits USING btree (run_id);

-- One row per start idempotency key: startFor claims the key before it starts
-- a run, so two concurrent starts with one key start one run. run_id is null
-- while the start that claimed it is still running.
create table workflow.workflow_run_keys (
  key text primary key constraint bsb_workflow_run_keys_key_check check (length(key) >= 1 and length(key) <= 500),
  run_id character varying,
  claimed_at timestamptz not null default now()
);
create index workflow_run_keys_run_id_idx on workflow.workflow_run_keys (run_id);
-- The purge backstops of zero-retention runs. world-postgres adds one through
-- Graphile Worker's add_job in the transaction that finishes such a run; this
-- World runs no Graphile Worker, so it points GRAPHILE_WORKER_SCHEMA at
-- workflow, where add_job records the run here and workflow_purge_backstops
-- deletes its data once due if the purge after the commit did not.
create table workflow.workflow_purge_backstops (
  run_id character varying primary key,
  due_at timestamptz not null,
  created_at timestamptz not null default now()
);
create index workflow_purge_backstops_due_at_idx on workflow.workflow_purge_backstops (due_at);
create or replace function workflow.add_job(
  identifier text,
  payload json default null,
  run_at timestamptz default null,
  max_attempts integer default null,
  job_key text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_run text := payload ->> 'runId';
begin
  if identifier not like '%purge' or v_run is null then
    raise exception 'Only the purge backstops of @workflow/world-postgres go through workflow.add_job'
      using errcode = '0A000', hint = 'WORKFLOW_GRAPHILE_UNSUPPORTED', detail = 'task ' || coalesce(identifier, 'null');
  end if;
  insert into workflow.workflow_purge_backstops (run_id, due_at)
    values (v_run, coalesce(run_at, now()))
    on conflict (run_id) do nothing;
end;
$$;
revoke execute on function workflow.add_job(text, json, timestamptz, integer, text) from public, anon, authenticated;
grant execute on function workflow.add_job(text, json, timestamptz, integer, text) to service_role;
-- The eve projection (eve sessions copied into the blocks by syncSession).
-- session_id is the id of the session's first run. read_cursor is the next
-- line of the session stream to read. A session is behind while dirty_at is
-- later than synced_at; the lease keeps two sync jobs off one session.
create table workflow.eve_sessions (
  session_id text primary key constraint bsb_eve_sessions_session_id_check check (length(session_id) >= 1 and length(session_id) <= 200),
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint not null default 0 constraint bsb_eve_sessions_read_cursor_check check (read_cursor >= 0),
  status text not null default 'open' constraint bsb_eve_sessions_status_check check (status in ('open', 'ended', 'failed', 'cancelled', 'stranded')),
  dirty_at timestamptz,
  synced_at timestamptz,
  lease_id text,
  leased_at timestamptz,
  lease_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index eve_sessions_dirty_idx on workflow.eve_sessions (dirty_at) where dirty_at is not null;
create index eve_sessions_open_idx on workflow.eve_sessions (eve_version) where status = 'open';
create table workflow.eve_session_runs (
  run_id text primary key,
  session_id text not null references workflow.eve_sessions (session_id) on delete cascade,
  eve_version text,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index eve_session_runs_session_idx on workflow.eve_session_runs (session_id);
revoke all on schema workflow from public, anon, authenticated;
grant usage on schema workflow to service_role;
alter table workflow.eve_session_runs enable row level security;
revoke all on workflow.eve_session_runs from public, anon, authenticated;
grant all on workflow.eve_session_runs to service_role;
alter table workflow.eve_sessions enable row level security;
revoke all on workflow.eve_sessions from public, anon, authenticated;
grant all on workflow.eve_sessions to service_role;
alter table workflow.workflow_event_slots enable row level security;
revoke all on workflow.workflow_event_slots from public, anon, authenticated;
grant all on workflow.workflow_event_slots to service_role;
alter table workflow.workflow_events enable row level security;
revoke all on workflow.workflow_events from public, anon, authenticated;
grant all on workflow.workflow_events to service_role;
alter table workflow.workflow_hooks enable row level security;
revoke all on workflow.workflow_hooks from public, anon, authenticated;
grant all on workflow.workflow_hooks to service_role;
alter table workflow.workflow_invocations enable row level security;
revoke all on workflow.workflow_invocations from public, anon, authenticated;
grant all on workflow.workflow_invocations to service_role;
alter table workflow.workflow_job_lock_holders enable row level security;
revoke all on workflow.workflow_job_lock_holders from public, anon, authenticated;
grant all on workflow.workflow_job_lock_holders to service_role;
alter table workflow.workflow_purge_backstops enable row level security;
revoke all on workflow.workflow_purge_backstops from public, anon, authenticated;
grant all on workflow.workflow_purge_backstops to service_role;
alter table workflow.workflow_rate_limits enable row level security;
revoke all on workflow.workflow_rate_limits from public, anon, authenticated;
grant all on workflow.workflow_rate_limits to service_role;
alter table workflow.workflow_run_delivery_leases enable row level security;
revoke all on workflow.workflow_run_delivery_leases from public, anon, authenticated;
grant all on workflow.workflow_run_delivery_leases to service_role;
alter table workflow.workflow_run_keys enable row level security;
revoke all on workflow.workflow_run_keys from public, anon, authenticated;
grant all on workflow.workflow_run_keys to service_role;
alter table workflow.workflow_runs enable row level security;
revoke all on workflow.workflow_runs from public, anon, authenticated;
grant all on workflow.workflow_runs to service_role;
alter table workflow.workflow_snapshots enable row level security;
revoke all on workflow.workflow_snapshots from public, anon, authenticated;
grant all on workflow.workflow_snapshots to service_role;
alter table workflow.workflow_start_hook_admissions enable row level security;
revoke all on workflow.workflow_start_hook_admissions from public, anon, authenticated;
grant all on workflow.workflow_start_hook_admissions to service_role;
alter table workflow.workflow_steps enable row level security;
revoke all on workflow.workflow_steps from public, anon, authenticated;
grant all on workflow.workflow_steps to service_role;
alter table workflow.workflow_stream_chunks enable row level security;
revoke all on workflow.workflow_stream_chunks from public, anon, authenticated;
grant all on workflow.workflow_stream_chunks to service_role;
alter table workflow.workflow_waits enable row level security;
revoke all on workflow.workflow_waits from public, anon, authenticated;
grant all on workflow.workflow_waits to service_role;
grant usage, select on sequence workflow.workflow_invocations_sequence_seq to service_role;
create index workflow_runs_attributes_idx on workflow.workflow_runs using gin (attributes jsonb_path_ops);

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
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflows.run'), false) then
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
    new.started_at,
    new.completed_at,
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
  v_extra jsonb;
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
  -- Extra headers (a deployment protection bypass, for one) as a JSON object.
  select ds.decrypted_secret::jsonb into v_extra from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_headers';
  if v_extra is not null and pg_catalog.jsonb_typeof(v_extra) <> 'object' then
    raise exception 'The Vault secret workflow_delivery_headers must be a JSON object of header names and values' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from "better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := 'workflow_deliveries' || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, coalesce(v_extra, '{}'::jsonb) || jsonb_build_object(
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
-- With skip_unprojected, a run of an eve session stays until the session's
-- copy in the blocks is current (the session was synced after its last change
-- and is no longer open).

create or replace function "better_supabase"."workflow_purge_runs"(
  older_than interval default '30 days',
  statuses text[] default array['completed', 'failed', 'cancelled'],
  batch integer default 500,
  skip_unprojected boolean default false
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
      and coalesce(r.completed_at, r.updated_at) < now() - coalesce(older_than, interval '30 days')
      and not (coalesce(skip_unprojected, false) and exists (
        select 1 from workflow.eve_session_runs sr
        join workflow.eve_sessions es on es.session_id = sr.session_id
        where sr.run_id = r.id
          and (es.status = 'open' or es.synced_at is null or es.dirty_at > es.synced_at)
      ))
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
  delete from workflow.workflow_purge_backstops where run_id = any (v_ids);
  delete from workflow.eve_session_runs where run_id = any (v_ids);
  delete from workflow.workflow_runs where id = any (v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- Runs up to batch due purge backstops: a run that ended with the $retention
-- attribute 0 and still has its data (expired_at is null) gets the purge
-- @workflow/world-postgres runs after the terminal write, in one transaction.
-- The run row is updated first, so late step and stream writes, which lock it
-- to read expired_at, wait for the purge. Returns how many runs it purged.
create or replace function "better_supabase"."workflow_purge_backstops"(batch integer default 100)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_due text[];
  v_ids text[];
begin
  with due as (
    delete from workflow.workflow_purge_backstops b
    where b.run_id in (
      select d.run_id from workflow.workflow_purge_backstops d
      where d.due_at <= now()
      order by d.due_at
      limit least(greatest(coalesce(batch, 100), 1), 1000)
      for update skip locked
    )
    returning b.run_id
  )
  select coalesce(array_agg(due.run_id), '{}') into v_due from due;
  if cardinality(v_due) = 0 then
    return 0;
  end if;
  select coalesce(array_agg(x.id), '{}') into v_ids from (
    select r.id from workflow.workflow_runs r
    where r.id = any (v_due)
      and r.status::text in ('completed', 'failed', 'cancelled')
      and r.attributes ->> '$retention' = '0'
      and r.expired_at is null
    for update
  ) x;
  if cardinality(v_ids) = 0 then
    return 0;
  end if;
  update workflow.workflow_runs set expired_at = now(),
    input_cbor = null, input = null, output_cbor = null, output = null,
    error_cbor = null, error = null, dynamic_workflow_code_cbor = null
    where id = any (v_ids);
  update workflow.workflow_steps set input_cbor = null, input = null,
    output_cbor = null, output = null, error_cbor = null, error = null
    where run_id = any (v_ids);
  update workflow.workflow_events set payload_cbor = null, payload = null, resume_payload_digest = null
    where run_id = any (v_ids);
  update workflow.workflow_hooks set metadata_cbor = null, metadata = null, resume_context = null
    where run_id = any (v_ids);
  update workflow.workflow_stream_chunks set data = ''::bytea where run_id = any (v_ids);
  update workflow.workflow_invocations set payload = null, result = null, fingerprint = null, expired_at = now()
    where run_id = any (v_ids);
  delete from workflow.workflow_snapshots where run_id = any (v_ids);
  return cardinality(v_ids);
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
  metadata_cbor bytea,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select h.hook_id::text, h.run_id::text, r.name::text,
    r.attributes ->> 'bsb.tenant', r.attributes ->> 'bsb.actor',
    h.metadata, h.metadata_cbor, h.created_at
  from workflow.workflow_hooks h
  join workflow.workflow_runs r on r.id = h.run_id
  where r.status::text in ('pending', 'running')
    and not coalesce(h.is_system, false)
    and (workflow_open_hooks.tenant is null or r.attributes ->> 'bsb.tenant' = workflow_open_hooks.tenant)
    and (workflow_open_hooks.workflow_name is null or r.name = workflow_open_hooks.workflow_name)
  order by h.created_at desc
  limit least(greatest(coalesce(workflow_open_hooks.max, 50), 1), 500);
$$;
-- Marks a session as behind and queues its sync job. The job is debounced: a
-- job that has not started yet absorbs later wake-ups of the same session.
create or replace function "better_supabase"."eve_session_wake"(sid text, delay_seconds integer default 2)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into workflow.eve_sessions as s (session_id, dirty_at) values (sid, now())
  on conflict (session_id) do update set dirty_at = now(), updated_at = now();
  perform "better_supabase"."enqueue_job"(queue => 'eve_session_sync', payload => jsonb_build_object('sessionId', sid), delay => greatest(coalesce(delay_seconds, 0), 0), dedupe_key => 'eve:' || sid, dedupe_running => false);
end;
$$;

-- Follows eve's runs: a run with an eve session type, or one that names its
-- session, belongs to that session. The newest run decides the status.
create or replace function "better_supabase"."workflow_sdk_track_eve_run"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
  v_status text;
begin
  if new.attributes ->> '$eve.type' is distinct from 'session' and nullif(new.attributes ->> '$eve.session', '') is null then
    return null;
  end if;
  v_session := coalesce(nullif(new.attributes ->> '$eve.session', ''), new.id);
  v_status := case new.status::text
    when 'completed' then 'ended'
    when 'failed' then 'failed'
    when 'cancelled' then 'cancelled'
    else 'open'
  end;
  insert into workflow.eve_sessions as s (session_id, eve_version, run_id, status)
  values (v_session, new.attributes ->> '$eve.version', new.id, v_status)
  on conflict (session_id) do update set
    eve_version = coalesce(new.attributes ->> '$eve.version', s.eve_version),
    run_id = new.id,
    status = case when s.status = 'stranded' then s.status else v_status end,
    updated_at = now()
  where s.run_id is null or s.run_id = new.id
    or new.created_at >= coalesce((select r.created_at from workflow.workflow_runs r where r.id = s.run_id), '-infinity'::timestamptz);
  insert into workflow.eve_session_runs as sr (run_id, session_id, eve_version, status)
  values (new.id, v_session, new.attributes ->> '$eve.version', new.status::text)
  on conflict (run_id) do update set status = new.status::text, updated_at = now();
  perform "better_supabase"."eve_session_wake"(v_session);
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_sdk_track_eve_run"() from public, anon, authenticated;
create trigger "bsb_workflow_sdk_eve_runs" after insert or update of status on workflow.workflow_runs
  for each row execute function "better_supabase"."workflow_sdk_track_eve_run"();

-- Wakes the session of a run that wrote an event. Other runs cost one lookup.
create or replace function "better_supabase"."workflow_sdk_wake_eve_session"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_session text;
begin
  select sr.session_id into v_session from workflow.eve_session_runs sr where sr.run_id = new.run_id;
  if v_session is not null then
    perform "better_supabase"."eve_session_wake"(v_session);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."workflow_sdk_wake_eve_session"() from public, anon, authenticated;
create trigger "bsb_workflow_sdk_eve_events" after insert on workflow.workflow_events
  for each row execute function "better_supabase"."workflow_sdk_wake_eve_session"();

-- Takes the lease on a session and returns its row, or no row while another
-- sync job holds the lease.
create or replace function "better_supabase"."eve_session_lease"(sid text, lease_seconds integer default 60)
returns table (
  session_id text,
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint,
  status text,
  lease_id text
)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_token text := gen_random_uuid()::text;
begin
  insert into workflow.eve_sessions (session_id) values (sid) on conflict (session_id) do nothing;
  return query
    update workflow.eve_sessions s set
      lease_id = v_token,
      leased_at = now(),
      lease_until = now() + make_interval(secs => greatest(coalesce(lease_seconds, 60), 1)),
      updated_at = now()
    where s.session_id = sid and (s.lease_until is null or s.lease_until < now())
    returning s.session_id, s.tenant_id, s.principal_kind, s.principal_id, s.eve_version, s.chat_id,
      s.record_type, s.record_id, s.run_id, s.read_cursor, s.status, s.lease_id;
end;
$$;

-- Advances the cursor and stores what the job resolved, then frees the lease.
-- synced_at is the time the lease began, so a change after that stays behind.
create or replace function "better_supabase"."eve_session_commit"(
  sid text,
  token text,
  cursor_line bigint,
  tenant text default null,
  principal_kind text default null,
  principal_id text default null,
  chat text default null,
  record_type text default null,
  record_id text default null,
  session_status text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status is not null and session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_commit: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions s set
    read_cursor = greatest(s.read_cursor, coalesce(cursor_line, 0)),
    tenant_id = coalesce(tenant, s.tenant_id),
    principal_kind = coalesce(eve_session_commit.principal_kind, s.principal_kind),
    principal_id = coalesce(eve_session_commit.principal_id, s.principal_id),
    chat_id = coalesce(chat, s.chat_id),
    record_type = coalesce(eve_session_commit.record_type, s.record_type),
    record_id = coalesce(eve_session_commit.record_id, s.record_id),
    status = coalesce(session_status, s.status),
    synced_at = coalesce(s.leased_at, now()),
    lease_id = null,
    lease_until = null,
    updated_at = now()
  where s.session_id = sid and s.lease_id = token;
  return found;
end;
$$;

-- Frees a lease without advancing the cursor, so the next job starts at once.
create or replace function "better_supabase"."eve_session_release"(sid text, token text)
returns boolean
language sql
security definer
set search_path = ''
as $$
  update workflow.eve_sessions set lease_id = null, lease_until = null, updated_at = now()
  where session_id = sid and lease_id = token
  returning true;
$$;

-- The sessions whose copy is behind, oldest first: changed since the last sync,
-- or open and not synced for older_than.
create or replace function "better_supabase"."eve_sessions_behind"(older_than interval default '5 minutes', max integer default 100)
returns table (session_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id
  from workflow.eve_sessions s
  where (s.lease_until is null or s.lease_until < now())
    and (
      (s.dirty_at is not null and (s.synced_at is null or s.synced_at < s.dirty_at))
      or (s.status = 'open' and coalesce(s.synced_at, s.created_at) < now() - coalesce(older_than, interval '5 minutes'))
    )
  order by coalesce(s.synced_at, s.created_at)
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- The open sessions that a release other than not_version started, oldest first.
create or replace function "better_supabase"."eve_open_sessions"(not_version text default null, tenant text default null, max integer default 100)
returns table (
  session_id text,
  eve_version text,
  tenant_id text,
  principal_id text,
  chat_id text,
  run_id text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.session_id, s.eve_version, s.tenant_id, s.principal_id, s.chat_id, s.run_id, s.created_at
  from workflow.eve_sessions s
  where s.status = 'open'
    and (not_version is null or s.eve_version is distinct from not_version)
    and (tenant is null or s.tenant_id = tenant)
  order by s.created_at
  limit least(greatest(coalesce(max, 100), 1), 1000);
$$;

-- Sets a session's status (for instance stranded) and queues a sync.
create or replace function "better_supabase"."eve_session_mark"(sid text, session_status text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if session_status not in ('open', 'ended', 'failed', 'cancelled', 'stranded') then
    raise exception 'eve_session_mark: unknown status %', session_status using errcode = '22023', hint = 'EVE_SESSION_STATUS';
  end if;
  update workflow.eve_sessions set status = session_status, updated_at = now() where session_id = sid;
  if not found then
    return false;
  end if;
  perform "better_supabase"."eve_session_wake"(sid, 0);
  return true;
end;
$$;
revoke execute on function "better_supabase"."workflow_claim_run_key"(text, interval) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_claim_run_key"(text, interval) to service_role;
revoke execute on function "better_supabase"."workflow_set_run_key"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_set_run_key"(text, text) to service_role;
revoke execute on function "better_supabase"."workflow_release_run_key"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_release_run_key"(text) to service_role;
revoke execute on function "better_supabase"."workflow_purge_runs"(interval, text[], integer, boolean) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_purge_runs"(interval, text[], integer, boolean) to service_role;
revoke execute on function "better_supabase"."workflow_purge_backstops"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_purge_backstops"(integer) to service_role;
revoke execute on function "better_supabase"."workflow_open_hooks"(text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."workflow_open_hooks"(text, text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_wake"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_wake"(text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_lease"(text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_lease"(text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) to service_role;
revoke execute on function "better_supabase"."eve_session_release"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_release"(text, text) to service_role;
revoke execute on function "better_supabase"."eve_sessions_behind"(interval, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_sessions_behind"(interval, integer) to service_role;
revoke execute on function "better_supabase"."eve_open_sessions"(text, text, integer) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_open_sessions"(text, text, integer) to service_role;
revoke execute on function "better_supabase"."eve_session_mark"(text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."eve_session_mark"(text, text) to service_role;

-- blocks.workflow-sdk.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."dispatch_workflow_deliveries"(batch integer default 20)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."dispatch_workflow_deliveries"($1) $$;
revoke execute on function "api"."dispatch_workflow_deliveries"(integer) from public, anon, authenticated;
grant execute on function "api"."dispatch_workflow_deliveries"(integer) to service_role;

create or replace function "api"."workflow_claim_run_key"(run_key text, stale_after interval default '5 minutes')
returns table (claimed boolean, run_id text)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."workflow_claim_run_key"($1, $2) $$;
revoke execute on function "api"."workflow_claim_run_key"(text, interval) from public, anon, authenticated;
grant execute on function "api"."workflow_claim_run_key"(text, interval) to service_role;

create or replace function "api"."workflow_set_run_key"(run_key text, run text)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_set_run_key"($1, $2) $$;
revoke execute on function "api"."workflow_set_run_key"(text, text) from public, anon, authenticated;
grant execute on function "api"."workflow_set_run_key"(text, text) to service_role;

create or replace function "api"."workflow_release_run_key"(run_key text)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_release_run_key"($1) $$;
revoke execute on function "api"."workflow_release_run_key"(text) from public, anon, authenticated;
grant execute on function "api"."workflow_release_run_key"(text) to service_role;

create or replace function "api"."workflow_purge_runs"(older_than interval default '30 days', statuses text[] default array['completed', 'failed', 'cancelled'], batch integer default 500, skip_unprojected boolean default false)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_purge_runs"($1, $2, $3, $4) $$;
revoke execute on function "api"."workflow_purge_runs"(interval, text[], integer, boolean) from public, anon, authenticated;
grant execute on function "api"."workflow_purge_runs"(interval, text[], integer, boolean) to service_role;

create or replace function "api"."workflow_purge_backstops"(batch integer default 100)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."workflow_purge_backstops"($1) $$;
revoke execute on function "api"."workflow_purge_backstops"(integer) from public, anon, authenticated;
grant execute on function "api"."workflow_purge_backstops"(integer) to service_role;

create or replace function "api"."workflow_open_hooks"(tenant text default null, workflow_name text default null, max integer default 50)
returns table (
  hook_id text,
  run_id text,
  workflow text,
  tenant_id text,
  actor_id text,
  metadata jsonb,
  metadata_cbor bytea,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."workflow_open_hooks"($1, $2, $3) $$;
revoke execute on function "api"."workflow_open_hooks"(text, text, integer) from public, anon, authenticated;
grant execute on function "api"."workflow_open_hooks"(text, text, integer) to service_role;

create or replace function "api"."eve_session_wake"(sid text, delay_seconds integer default 2)
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."eve_session_wake"($1, $2) $$;
revoke execute on function "api"."eve_session_wake"(text, integer) from public, anon, authenticated;
grant execute on function "api"."eve_session_wake"(text, integer) to service_role;

create or replace function "api"."eve_session_lease"(sid text, lease_seconds integer default 60)
returns table (
  session_id text,
  tenant_id text,
  principal_kind text,
  principal_id text,
  eve_version text,
  chat_id text,
  record_type text,
  record_id text,
  run_id text,
  read_cursor bigint,
  status text,
  lease_id text
)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."eve_session_lease"($1, $2) $$;
revoke execute on function "api"."eve_session_lease"(text, integer) from public, anon, authenticated;
grant execute on function "api"."eve_session_lease"(text, integer) to service_role;

create or replace function "api"."eve_session_commit"(sid text, token text, cursor_line bigint, tenant text default null, principal_kind text default null, principal_id text default null, chat text default null, record_type text default null, record_id text default null, session_status text default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."eve_session_commit"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function "api"."eve_session_commit"(text, text, bigint, text, text, text, text, text, text, text) to service_role;

create or replace function "api"."eve_session_release"(sid text, token text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."eve_session_release"($1, $2) $$;
revoke execute on function "api"."eve_session_release"(text, text) from public, anon, authenticated;
grant execute on function "api"."eve_session_release"(text, text) to service_role;

create or replace function "api"."eve_sessions_behind"(older_than interval default '5 minutes', max integer default 100)
returns table (session_id text)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."eve_sessions_behind"($1, $2) $$;
revoke execute on function "api"."eve_sessions_behind"(interval, integer) from public, anon, authenticated;
grant execute on function "api"."eve_sessions_behind"(interval, integer) to service_role;

create or replace function "api"."eve_open_sessions"(not_version text default null, tenant text default null, max integer default 100)
returns table (
  session_id text,
  eve_version text,
  tenant_id text,
  principal_id text,
  chat_id text,
  run_id text,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."eve_open_sessions"($1, $2, $3) $$;
revoke execute on function "api"."eve_open_sessions"(text, text, integer) from public, anon, authenticated;
grant execute on function "api"."eve_open_sessions"(text, text, integer) to service_role;

create or replace function "api"."eve_session_mark"(sid text, session_status text)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."eve_session_mark"($1, $2) $$;
revoke execute on function "api"."eve_session_mark"(text, text) from public, anon, authenticated;
grant execute on function "api"."eve_session_mark"(text, text) to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_043_workflow_sdk.sql
-- better-supabase module: workflow-sdk
-- @bsb-block-data workflow-sdk
-- @bsb-hash sha256:03d035c6cdd294e29651450c06bd849b42260fb91e90c111f01dfc427c4eff9c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

do $$
declare
  c record;
begin
  for c in select table_name, column_name from information_schema.columns
    where table_schema = 'workflow' and data_type = 'timestamp without time zone'
  loop
    execute format('alter table workflow.%I alter column %I type timestamptz using %I at time zone ''UTC''', c.table_name, c.column_name, c.column_name);
  end loop;
end
$$;

insert into better_supabase.blocks (name, version, mode)
values ('workflow-sdk', 10, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
