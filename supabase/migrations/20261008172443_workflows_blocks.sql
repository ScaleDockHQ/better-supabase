SET local check_function_bodies = off;

CREATE SCHEMA "workflow";

CREATE SEQUENCE "workflow"."workflow_invocations_sequence_seq" AS bigint INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START WITH 1 CACHE 1 NO CYCLE;

CREATE TABLE "better_supabase"."workflow_runs" (
  "id"                  uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "engine"              text                     NOT NULL,
  "external_id"         text                     NOT NULL,
  "definition"          text                     NOT NULL,
  "tenant_id"           uuid,
  "actor_id"            uuid,
  "status"              text                     NOT NULL DEFAULT 'queued'::text,
  "attributes"          jsonb                    NOT NULL DEFAULT '{}'::jsonb,
  "error"               text,
  "created_at"          timestamp with time zone NOT NULL DEFAULT now(),
  "updated_at"          timestamp with time zone NOT NULL DEFAULT now(),
  "started_at"          timestamp with time zone,
  "completed_at"        timestamp with time zone,
  "cancel_requested_at" timestamp with time zone,
  CONSTRAINT "workflow_runs_definition_check" CHECK (((length(definition) >= 1) AND (length(definition) <= 200))),
  CONSTRAINT "workflow_runs_engine_check" CHECK (((length(engine) >= 1) AND (length(engine) <= 100))),
  CONSTRAINT "workflow_runs_engine_external_key" UNIQUE (engine, external_id),
  CONSTRAINT "workflow_runs_external_id_check" CHECK (((length(external_id) >= 1) AND (length(external_id) <= 200))),
  CONSTRAINT "workflow_runs_pkey" PRIMARY KEY (id),
  CONSTRAINT "workflow_runs_status_check" CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'waiting'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])))
);

ALTER TABLE "better_supabase"."workflow_runs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_schedules" (
  "id"           uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "tenant_id"    uuid,
  "name"         text                     NOT NULL,
  "workflow"     text                     NOT NULL,
  "input"        jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "cron"         text                     NOT NULL,
  "timezone"     text                     NOT NULL DEFAULT 'UTC'::text,
  "next_run_at"  timestamp with time zone NOT NULL,
  "last_run_at"  timestamp with time zone,
  "locked_until" timestamp with time zone,
  "paused"       boolean                  NOT NULL DEFAULT false,
  "created_by"   uuid,
  "created_at"   timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_schedules_cron_check" CHECK (((length(cron) >= 1) AND (length(cron) <= 200))),
  CONSTRAINT "workflow_schedules_name_check" CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT "workflow_schedules_pkey" PRIMARY KEY (id),
  CONSTRAINT "workflow_schedules_tenant_name_key" UNIQUE NULLS NOT DISTINCT (tenant_id, name),
  CONSTRAINT "workflow_schedules_workflow_check" CHECK (((length(workflow) >= 1) AND (length(workflow) <= 200)))
);

ALTER TABLE "better_supabase"."workflow_schedules"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_semaphores" (
  "key"         text                     NOT NULL,
  "holder"      text                     NOT NULL,
  "acquired_at" timestamp with time zone NOT NULL DEFAULT now(),
  "expires_at"  timestamp with time zone NOT NULL,
  CONSTRAINT "workflow_semaphores_holder_check" CHECK (((length(holder) >= 1) AND (length(holder) <= 200))),
  CONSTRAINT "workflow_semaphores_key_check" CHECK (((length(key) >= 1) AND (length(key) <= 200))),
  CONSTRAINT "workflow_semaphores_pkey" PRIMARY KEY (key, holder)
);

ALTER TABLE "better_supabase"."workflow_semaphores"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "better_supabase"."workflow_start_requests" (
  "id"            uuid                     NOT NULL DEFAULT gen_random_uuid(),
  "key"           text                     NOT NULL,
  "workflow"      text                     NOT NULL,
  "input"         jsonb                    NOT NULL DEFAULT '[]'::jsonb,
  "tenant_id"     uuid,
  "actor_id"      uuid,
  "concurrency"   integer,
  "status"        text                     NOT NULL DEFAULT 'pending'::text,
  "not_before"    timestamp with time zone NOT NULL DEFAULT now(),
  "claimed_until" timestamp with time zone,
  "run_id"        text,
  "created_at"    timestamp with time zone NOT NULL DEFAULT now(),
  "started_at"    timestamp with time zone,
  CONSTRAINT "workflow_start_requests_concurrency_check" CHECK ((concurrency > 0)),
  CONSTRAINT "workflow_start_requests_key_check" CHECK (((length(key) >= 1) AND (length(key) <= 200))),
  CONSTRAINT "workflow_start_requests_pkey" PRIMARY KEY (id),
  CONSTRAINT "workflow_start_requests_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'started'::text, 'superseded'::text, 'dropped'::text]))),
  CONSTRAINT "workflow_start_requests_workflow_check" CHECK (((length(workflow) >= 1) AND (length(workflow) <= 200)))
);

ALTER TABLE "better_supabase"."workflow_start_requests"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_event_slots" (
  "run_id" character varying NOT NULL,
  CONSTRAINT "workflow_event_slots_pkey" PRIMARY KEY (run_id)
);

ALTER TABLE "workflow"."workflow_event_slots"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_events" (
  "id"                    character varying           NOT NULL,
  "type"                  character varying           NOT NULL,
  "correlation_id"        character varying,
  "created_at"            timestamp without time zone NOT NULL DEFAULT now(),
  "run_id"                character varying           NOT NULL,
  "payload"               jsonb,
  "payload_cbor"          bytea,
  "spec_version"          integer,
  "resume_id"             character varying,
  "resume_payload_digest" character varying,
  CONSTRAINT "workflow_events_run_id_id_pk" PRIMARY KEY (run_id, id)
);

ALTER TABLE "workflow"."workflow_events"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_hooks" (
  "run_id"                character varying           NOT NULL,
  "hook_id"               character varying           NOT NULL,
  "token"                 character varying           NOT NULL,
  "owner_id"              character varying           NOT NULL,
  "project_id"            character varying           NOT NULL,
  "environment"           character varying           NOT NULL,
  "created_at"            timestamp without time zone NOT NULL DEFAULT now(),
  "metadata"              jsonb,
  "metadata_cbor"         bytea,
  "spec_version"          integer,
  "is_webhook"            boolean                     DEFAULT true,
  "is_system"             boolean                     DEFAULT false,
  "resume_context"        bytea,
  "token_retention_until" timestamp with time zone,
  "claimed_from"          bytea,
  CONSTRAINT "workflow_hooks_pkey" PRIMARY KEY (hook_id)
);

ALTER TABLE "workflow"."workflow_hooks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_invocations" (
  "sequence"       bigint                      NOT NULL DEFAULT nextval('workflow.workflow_invocations_sequence_seq'::regclass),
  "run_id"         character varying           NOT NULL,
  "request_id"     character varying           NOT NULL,
  "payload"        bytea,
  "fingerprint"    character varying,
  "result"         bytea,
  "created_at"     timestamp without time zone NOT NULL DEFAULT now(),
  "responded_at"   timestamp without time zone,
  "expired_at"     timestamp without time zone,
  "result_version" integer                     NOT NULL DEFAULT 0,
  CONSTRAINT "workflow_invocations_pkey" PRIMARY KEY (run_id, request_id)
);

ALTER TABLE "workflow"."workflow_invocations"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_runs" (
  "id"                         character varying           NOT NULL,
  "output"                     jsonb,
  "deployment_id"              character varying           NOT NULL,
  "name"                       character varying           NOT NULL,
  "execution_context"          jsonb,
  "input"                      jsonb,
  "error"                      text,
  "created_at"                 timestamp without time zone NOT NULL DEFAULT now(),
  "updated_at"                 timestamp without time zone NOT NULL DEFAULT now(),
  "completed_at"               timestamp without time zone,
  "started_at"                 timestamp without time zone,
  "output_cbor"                bytea,
  "execution_context_cbor"     bytea,
  "input_cbor"                 bytea,
  "expired_at"                 timestamp without time zone,
  "spec_version"               character varying,
  "error_cbor"                 bytea,
  "error_code"                 character varying,
  "attributes"                 jsonb                       NOT NULL DEFAULT '{}'::jsonb,
  "encryption_public_key"      character varying,
  "dynamic_workflow_code_cbor" bytea,
  CONSTRAINT "workflow_runs_pkey" PRIMARY KEY (id)
);

ALTER TABLE "workflow"."workflow_runs"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_snapshots" (
  "run_id"        character varying           NOT NULL,
  "data"          bytea                       NOT NULL,
  "events_cursor" character varying,
  "created_at"    timestamp without time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_snapshots_pkey" PRIMARY KEY (run_id)
);

ALTER TABLE "workflow"."workflow_snapshots"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_steps" (
  "run_id"       character varying           NOT NULL,
  "step_id"      character varying           NOT NULL,
  "step_name"    character varying           NOT NULL,
  "input"        jsonb,
  "output"       jsonb,
  "error"        text,
  "attempt"      integer                     NOT NULL,
  "started_at"   timestamp without time zone,
  "completed_at" timestamp without time zone,
  "created_at"   timestamp without time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp without time zone NOT NULL DEFAULT now(),
  "retry_after"  timestamp without time zone,
  "input_cbor"   bytea,
  "output_cbor"  bytea,
  "error_cbor"   bytea,
  "spec_version" integer,
  CONSTRAINT "workflow_steps_pkey" PRIMARY KEY (step_id)
);

ALTER TABLE "workflow"."workflow_steps"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_stream_chunks" (
  "id"         character varying           NOT NULL,
  "stream_id"  character varying           NOT NULL,
  "data"       bytea                       NOT NULL,
  "created_at" timestamp without time zone NOT NULL DEFAULT now(),
  "eof"        boolean                     NOT NULL,
  "run_id"     character varying,
  CONSTRAINT "workflow_stream_chunks_stream_id_id_pk" PRIMARY KEY (stream_id, id)
);

ALTER TABLE "workflow"."workflow_stream_chunks"
  ENABLE ROW LEVEL SECURITY;

CREATE TABLE "workflow"."workflow_waits" (
  "wait_id"      character varying           NOT NULL,
  "run_id"       character varying           NOT NULL,
  "resume_at"    timestamp without time zone,
  "completed_at" timestamp without time zone,
  "created_at"   timestamp without time zone NOT NULL DEFAULT now(),
  "updated_at"   timestamp without time zone NOT NULL DEFAULT now(),
  "spec_version" integer,
  CONSTRAINT "workflow_waits_pkey" PRIMARY KEY (wait_id)
);

ALTER TABLE "workflow"."workflow_waits"
  ENABLE ROW LEVEL SECURITY;

ALTER SEQUENCE "workflow"."workflow_invocations_sequence_seq" OWNED BY "workflow"."workflow_invocations"."sequence";

CREATE TYPE "workflow"."status" AS ENUM (
  'pending',
  'running',
  'completed',
  'failed',
  'cancelled'
);

ALTER TABLE "workflow"."workflow_runs"
  ADD COLUMN "status" workflow.status NOT NULL;

CREATE TYPE "workflow"."step_status" AS ENUM (
  'pending',
  'running',
  'completed',
  'failed',
  'cancelled'
);

ALTER TABLE "workflow"."workflow_steps"
  ADD COLUMN "status" workflow.step_status NOT NULL;

CREATE TYPE "workflow"."wait_status" AS ENUM (
  'waiting',
  'completed'
);

ALTER TABLE "workflow"."workflow_waits"
  ADD COLUMN "status" workflow.wait_status NOT NULL;

CREATE OR REPLACE FUNCTION api.acquire_workflow_semaphore (
  key    text,
  holder text,
  max    integer,
  ttl    interval DEFAULT '00:05:00'::interval
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."acquire_workflow_semaphore"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.advance_workflow_schedule (
  schedule uuid,
  fired    timestamp with time zone,
  next_run timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."advance_workflow_schedule"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.claim_due_workflow_schedules (
  lease integer DEFAULT 60,
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_due_workflow_schedules"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.claim_workflow_start_requests (
  lease integer DEFAULT 60,
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."claim_workflow_start_requests"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.create_workflow_schedule (
  name     text,
  workflow text,
  cron     text,
  next_run timestamp with time zone,
  payload  jsonb                    DEFAULT '{}'::jsonb,
  timezone text                     DEFAULT 'UTC'::text,
  tenant   uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."create_workflow_schedule"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION api.mark_workflow_start_request (
  request uuid,
  run     text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."mark_workflow_start_request"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.pause_workflow_schedule (
  schedule uuid,
  paused   boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."pause_workflow_schedule"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_workflow_runs (
  older_than interval DEFAULT '30 days'::interval,
  batch      integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_workflow_runs"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.record_workflow_run (
  engine       text,
  external_id  text,
  definition   text,
  status       text,
  tenant       uuid                     DEFAULT NULL::uuid,
  actor        uuid                     DEFAULT NULL::uuid,
  attributes   jsonb                    DEFAULT '{}'::jsonb,
  error        text                     DEFAULT NULL::text,
  started_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  completed_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_workflow_run"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $function$;

CREATE OR REPLACE FUNCTION api.release_workflow_semaphore (
  key    text,
  holder text
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."release_workflow_semaphore"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.remove_workflow_schedule (
  schedule uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."remove_workflow_schedule"($1) $function$;

CREATE OR REPLACE FUNCTION api.request_workflow_cancel (
  run text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."request_workflow_cancel"($1) $function$;

CREATE OR REPLACE FUNCTION api.request_workflow_start (
  key         text,
  workflow    text,
  payload     jsonb    DEFAULT '{}'::jsonb,
  tenant      uuid     DEFAULT NULL::uuid,
  actor       uuid     DEFAULT NULL::uuid,
  concurrency integer  DEFAULT NULL::integer,
  debounce    interval DEFAULT NULL::interval,
  singleton   boolean  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."request_workflow_start"($1, $2, $3, $4, $5, $6, $7, $8) $function$;

CREATE OR REPLACE FUNCTION api.workflow_admission_active (
  key text
)
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_admission_active"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_run_get (
  run text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_run_get"($1) $function$;

CREATE OR REPLACE FUNCTION api.workflow_runs_list (
  tenant     uuid                     DEFAULT NULL::uuid,
  definition text                     DEFAULT NULL::text,
  status     text                     DEFAULT NULL::text,
  max        integer                  DEFAULT 50,
  before     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_runs_list"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.workflow_schedules_list (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."workflow_schedules_list"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.acquire_workflow_semaphore (
  key    text,
  holder text,
  max    integer,
  ttl    interval DEFAULT '00:05:00'::interval
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_held integer;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_semaphore'), pg_catalog.hashtext(key));
  delete from "better_supabase"."workflow_semaphores" x where x."key" = key and x."expires_at" < now();
  update "better_supabase"."workflow_semaphores" x set "expires_at" = now() + coalesce(ttl, interval '5 minutes')
  where x."key" = key and x."holder" = holder;
  if found then
    return true;
  end if;
  select count(*) into v_held from "better_supabase"."workflow_semaphores" x where x."key" = key;
  if v_held >= greatest(coalesce(max, 1), 1) then
    return false;
  end if;
  insert into "better_supabase"."workflow_semaphores" ("key", "holder", "expires_at")
  values (key, holder, now() + coalesce(ttl, interval '5 minutes'));
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.advance_schedule (
  job_name text,
  ran      timestamp with time zone,
  next_run timestamp with time zone
)
  RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select false;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.advance_workflow_schedule (
  schedule uuid,
  fired    timestamp with time zone,
  next_run timestamp with time zone
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  update "better_supabase"."workflow_schedules" x set "last_run_at" = fired, "next_run_at" = next_run, "locked_until" = null
  where x."id" = schedule and x."next_run_at" = fired;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_due_schedules (
  lease integer DEFAULT 60,
  batch integer DEFAULT 100
)
  RETURNS TABLE (
    job_name    text,
    schedule    text,
    timezone    text,
    queue       text,
    payload     jsonb,
    next_run    timestamp with time zone,
    first_after timestamp with time zone
  )
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select null::text, null::text, null::text, null::text, null::jsonb, null::timestamptz, null::timestamptz where false;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_due_workflow_schedules (
  lease integer DEFAULT 60,
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$
  with due as (
    select "id" from "better_supabase"."workflow_schedules"
    where not "paused"
      and "next_run_at" <= now()
      and ("locked_until" is null or "locked_until" < now())
    order by "next_run_at"
    limit greatest(coalesce(batch, 50), 1)
    for update skip locked
  ),
  leased as (
    update "better_supabase"."workflow_schedules" x set "locked_until" = now() + make_interval(secs => greatest(coalesce(lease, 60), 1))
    from due where x."id" = due."id"
    returning x.*
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', leased."id",
    'tenant', leased."tenant_id",
    'name', leased."name",
    'workflow', leased."workflow",
    'input', leased."input",
    'cron', leased."cron",
    'timezone', leased."timezone",
    'nextRunAt', leased."next_run_at",
    'lastRunAt', leased."last_run_at",
    'paused', leased."paused",
    'createdBy', leased."created_by",
    'createdAt', leased."created_at"
  ) || jsonb_build_object('fireAt', leased."next_run_at") order by leased."next_run_at"), '[]'::jsonb)
  from leased;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_jobs (
  queue text,
  lease integer DEFAULT 300,
  batch integer DEFAULT 1
)
  RETURNS TABLE (
    id            bigint,
    attempts      integer,
    enqueued_at   timestamp with time zone,
    visible_until timestamp with time zone,
    message       jsonb
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  r record;
begin
  perform better_supabase.ensure_job_queue(queue);
  for r in select * from pgmq.read(queue, lease, batch) loop
    if r.read_ct > coalesce((r.message ->> 'max_attempts')::integer, 5) then
      execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', ''The lease ran out on the last attempt'', ''dead'', true) where msg_id = $1', 'q_' || queue)
        using r.msg_id;
      perform pgmq.archive(queue, r.msg_id);
    else
      id := r.msg_id;
      attempts := r.read_ct;
      enqueued_at := r.enqueued_at;
      visible_until := r.vt;
      message := r.message;
      return next;
    end if;
  end loop;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_workflow_start_requests (
  lease integer DEFAULT 60,
  batch integer DEFAULT 50
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."workflow_start_requests"%rowtype;
  v_out jsonb := '[]'::jsonb;
  v_taken integer := 0;
begin
  for v_row in
    select * from "better_supabase"."workflow_start_requests"
    where "status" = 'pending'
      and "not_before" <= now()
      and ("claimed_until" is null or "claimed_until" < now())
    order by "created_at"
    for update skip locked
  loop
    exit when v_taken >= greatest(coalesce(batch, 50), 1);
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(v_row."key"));
    if v_row."concurrency" is null
      or "better_supabase"."workflow_admission_active"(v_row."key") < v_row."concurrency" then
      update "better_supabase"."workflow_start_requests" set "claimed_until" = now() + make_interval(secs => greatest(coalesce(lease, 60), 1))
      where "id" = v_row."id";
      v_out := v_out || jsonb_build_array(jsonb_build_object(
        'id', v_row."id",
        'key', v_row."key",
        'workflow', v_row."workflow",
        'input', v_row."input",
        'tenant', v_row."tenant_id",
        'actor', v_row."actor_id"
      ));
      v_taken := v_taken + 1;
    end if;
  end loop;
  return v_out;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.complete_job (
  queue   text,
  job_id  bigint,
  attempt integer
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  hit bigint;
begin
  execute format('select msg_id from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into hit using job_id, attempt;
  if hit is null then
    return false;
  end if;
  return pgmq.archive(queue, job_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_workflow_schedule (
  name     text,
  workflow text,
  cron     text,
  next_run timestamp with time zone,
  payload  jsonb                    DEFAULT '{}'::jsonb,
  timezone text                     DEFAULT 'UTC'::text,
  tenant   uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."workflow_schedules"%rowtype;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (tenant is not null and coalesce(better_supabase.can('tenant', tenant, 'workflow.admin'), false))) then
    raise exception 'You may not schedule workflows here' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  insert into "better_supabase"."workflow_schedules" as x ("tenant_id", "name", "workflow", "input", "cron", "timezone", "next_run_at", "created_by")
  values (tenant, name, workflow, coalesce(payload -> 'input', '[]'::jsonb), cron, coalesce(timezone, 'UTC'), next_run, (select auth.uid()))
  on conflict on constraint workflow_schedules_tenant_name_key do update set
    "workflow" = excluded."workflow",
    "input" = excluded."input",
    "cron" = excluded."cron",
    "timezone" = excluded."timezone",
    "next_run_at" = excluded."next_run_at",
    "locked_until" = null
  returning * into v_row;
  return jsonb_build_object(
    'id', v_row."id",
    'tenant', v_row."tenant_id",
    'name', v_row."name",
    'workflow', v_row."workflow",
    'input', v_row."input",
    'cron', v_row."cron",
    'timezone', v_row."timezone",
    'nextRunAt', v_row."next_run_at",
    'lastRunAt', v_row."last_run_at",
    'paused', v_row."paused",
    'createdBy', v_row."created_by",
    'createdAt', v_row."created_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dispatch_workflow_deliveries (
  batch integer DEFAULT 20
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_url text;
  v_secret text;
  v_job record;
  v_body jsonb;
  v_t text;
  v_job_header text;
  v_count integer := 0;
begin
  if pg_catalog.to_regnamespace('net') is null then
    raise exception 'dispatch_workflow_deliveries needs pg_net: create extension pg_net, or deliver with the poll mode';
  end if;
  select ds.decrypted_secret into v_url from vault.decrypted_secrets ds where ds.name = 'workflow_flow_url';
  select ds.decrypted_secret into v_secret from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_secret';
  if v_url is null or v_secret is null then
    raise exception 'Set the Vault secrets workflow_flow_url and workflow_delivery_secret before dispatching' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from better_supabase.claim_jobs('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := 'workflow_deliveries' || ':' || v_job.id::text || ':' || v_job.attempts::text;
    perform net.http_post(
      url := v_url,
      body := v_body,
      headers := jsonb_build_object(
        'content-type', 'application/json',
        'x-bs-job', v_job_header,
        'x-bs-signature', 't=' || v_t || ',v1=' || encode(extensions.hmac(v_t || '.' || v_job_header || '.' || v_body::text, v_secret, 'sha256'), 'hex')
      ),
      timeout_milliseconds := 30000
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.enqueue_job (
  queue          text,
  payload        jsonb   DEFAULT '{}'::jsonb,
  delay          integer DEFAULT 0,
  max_attempts   integer DEFAULT 5,
  dedupe_key     text    DEFAULT NULL::text,
  dedupe_running boolean DEFAULT true
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing bigint;
begin
  perform better_supabase.ensure_job_queue(queue);
  if dedupe_key is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(queue), pg_catalog.hashtext(dedupe_key));
    execute format('select msg_id from pgmq.%I where message ? ''dedupe_key'' and message ->> ''dedupe_key'' = $1 and ($2 or read_ct = 0) limit 1', 'q_' || queue)
      into existing using dedupe_key, dedupe_running;
    if existing is not null then
      return existing;
    end if;
  end if;
  return (
    select pgmq.send(
      queue,
      jsonb_build_object('payload', payload, 'max_attempts', max_attempts)
        || case when dedupe_key is null then '{}'::jsonb else jsonb_build_object('dedupe_key', dedupe_key) end,
      greatest(delay, 0)
    )
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ensure_job_queue (
  queue text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || queue)) is null then
    perform pgmq.create(queue);
    perform better_supabase.index_job_queue(queue);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.extend_job_lease (
  queue   text,
  job_id  bigint,
  attempt integer,
  lease   integer
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  hit bigint;
begin
  execute format('select msg_id from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into hit using job_id, attempt;
  if hit is null then
    return false;
  end if;
  perform pgmq.set_vt(queue, job_id, lease);
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.fail_job (
  queue    text,
  job_id   bigint,
  attempt  integer,
  error    text,
  retry_in integer DEFAULT NULL::integer
)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  msg jsonb;
begin
  execute format('select message from pgmq.%I where msg_id = $1 and read_ct = $2 for update', 'q_' || queue)
    into msg using job_id, attempt;
  if msg is null then
    return null;
  end if;
  if attempt >= coalesce((msg ->> 'max_attempts')::integer, 5) then
    execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', $2::text, ''dead'', true) where msg_id = $1', 'q_' || queue)
      using job_id, left(error, 4000);
    perform pgmq.archive(queue, job_id);
    return 'dead';
  end if;
  execute format('update pgmq.%I set message = message || jsonb_build_object(''last_error'', $2::text), vt = clock_timestamp() + make_interval(secs => $3) where msg_id = $1', 'q_' || queue)
    using job_id, left(error, 4000), coalesce(retry_in, 1 + floor(random() * least(3600, 10 * power(2, attempt - 1)))::integer);
  return 'queued';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.index_job_queue (
  queue text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  execute format(
    'create index if not exists %I on pgmq.%I ((message ->> ''dedupe_key'')) where message ? ''dedupe_key''',
    'q_' || queue || '_dedupe_idx',
    'q_' || queue
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.job_queue_stats (
  queue text
)
  RETURNS TABLE (
    ready              bigint,
    in_flight          bigint,
    delayed            bigint,
    dead               bigint,
    oldest_age_seconds double precision
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || queue)) is null then
    return query select 0::bigint, 0::bigint, 0::bigint, 0::bigint, null::double precision;
    return;
  end if;
  return query execute format(
    'select count(*) filter (where q.vt <= clock_timestamp()),
       count(*) filter (where q.vt > clock_timestamp() and q.read_ct > 0),
       count(*) filter (where q.vt > clock_timestamp() and q.read_ct = 0),
       (select count(*) from pgmq.%2$I a where a.message ? ''dead''),
       extract(epoch from clock_timestamp() - min(q.enqueued_at))::double precision
     from pgmq.%1$I q',
    'q_' || queue, 'a_' || queue
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_dead_jobs (
  queue     text,
  max_rows  integer DEFAULT 100,
  before_id bigint  DEFAULT NULL::bigint
)
  RETURNS TABLE (
    id          bigint,
    attempts    integer,
    enqueued_at timestamp with time zone,
    died_at     timestamp with time zone,
    message     jsonb
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'a_' || queue)) is null then
    return;
  end if;
  return query execute format(
    'select a.msg_id, a.read_ct, a.enqueued_at, a.archived_at, a.message from pgmq.%I a
     where a.message ? ''dead'' and ($2 is null or a.msg_id < $2)
     order by a.msg_id desc limit least(greatest($1, 1), 1000)',
    'a_' || queue
  ) using max_rows, before_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_schedules (
  name_prefix text DEFAULT NULL::text,
  for_tenant  text DEFAULT NULL::text
)
  RETURNS TABLE (
    job_name     text,
    schedule     text,
    timezone     text,
    queue        text,
    tenant       text,
    next_run     timestamp with time zone,
    last_run     timestamp with time zone,
    locked_until timestamp with time zone,
    created_at   timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regnamespace('cron') is null or list_schedules.for_tenant is not null then
    return;
  end if;
  return query execute
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz
     from cron.job j where $1 is null or starts_with(j.jobname, $1) order by j.jobname'
    using name_prefix;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.mark_workflow_start_request (
  request uuid,
  run     text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  update "better_supabase"."workflow_start_requests" x set "status" = 'started', "run_id" = run, "started_at" = now(), "claimed_until" = null
  where x."id" = request and x."status" = 'pending';
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pause_workflow_schedule (
  schedule uuid,
  paused   boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  update "better_supabase"."workflow_schedules" x set "paused" = coalesce(paused, true)
  where x."id" = schedule
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_job_archive (
  queue           text,
  older_than      interval DEFAULT '7 days'::interval,
  batch           integer  DEFAULT 10000,
  dead_older_than interval DEFAULT '30 days'::interval
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  purged integer;
begin
  execute format(
    'with purged as (delete from pgmq.%1$I where msg_id in (select a.msg_id from pgmq.%1$I a where a.archived_at < now() - case when a.message ? ''dead'' then $3 else $1 end order by a.msg_id limit $2) returning 1) select count(*)::integer from purged',
    'a_' || queue
  ) into purged using older_than, batch, dead_older_than;
  return purged;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_workflow_runs (
  older_than interval DEFAULT '30 days'::interval,
  batch      integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_runs integer;
begin
  with doomed as (
    select "id" from "better_supabase"."workflow_runs"
    where "status" in ('completed', 'failed', 'cancelled')
      and coalesce("completed_at", "updated_at") < now() - coalesce(older_than, interval '30 days')
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from "better_supabase"."workflow_runs" x using doomed where x."id" = doomed."id";
  get diagnostics v_runs = row_count;
  with doomed as (
    select "id" from "better_supabase"."workflow_start_requests"
    where "status" <> 'pending'
      and "created_at" < now() - coalesce(older_than, interval '30 days')
    limit greatest(coalesce(batch, 1000), 1)
  )
  delete from "better_supabase"."workflow_start_requests" x using doomed where x."id" = doomed."id";
  delete from "better_supabase"."workflow_semaphores" where "expires_at" < now();
  return v_runs;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_workflow_run (
  engine       text,
  external_id  text,
  definition   text,
  status       text,
  tenant       uuid                     DEFAULT NULL::uuid,
  actor        uuid                     DEFAULT NULL::uuid,
  attributes   jsonb                    DEFAULT '{}'::jsonb,
  error        text                     DEFAULT NULL::text,
  started_at   timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  completed_at timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS uuid
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  insert into "better_supabase"."workflow_runs" as x ("engine", "external_id", "definition", "status", "tenant_id", "actor_id", "attributes", "error", "started_at", "completed_at")
  values (engine, external_id, definition, status, tenant, actor, coalesce(attributes, '{}'::jsonb), left(error, 4000), started_at, completed_at)
  on conflict on constraint workflow_runs_engine_external_key do update set
    "definition" = excluded."definition",
    "status" = excluded."status",
    "tenant_id" = coalesce(x."tenant_id", excluded."tenant_id"),
    "actor_id" = coalesce(x."actor_id", excluded."actor_id"),
    "attributes" = x."attributes" || excluded."attributes",
    "error" = coalesce(excluded."error", x."error"),
    "started_at" = coalesce(x."started_at", excluded."started_at"),
    "completed_at" = coalesce(excluded."completed_at", x."completed_at"),
    "updated_at" = now()
  returning x."id" into v_id;
  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.release_workflow_semaphore (
  key    text,
  holder text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  delete from "better_supabase"."workflow_semaphores" x where x."key" = key and x."holder" = holder;
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.remove_workflow_schedule (
  schedule uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  delete from "better_supabase"."workflow_schedules" x
  where x."id" = schedule
    and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (x."tenant_id" is not null and coalesce(better_supabase.can('tenant', x."tenant_id", 'workflow.admin'), false)));
  return found;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.replay_dead_job (
  queue  text,
  job_id bigint
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  msg jsonb;
begin
  perform better_supabase.ensure_job_queue(queue);
  execute format('delete from pgmq.%I where msg_id = $1 and message ? ''dead'' returning message', 'a_' || queue)
    into msg using job_id;
  if msg is null then
    return null;
  end if;
  return better_supabase.enqueue_job(
    queue,
    coalesce(msg -> 'payload', '{}'),
    0,
    coalesce((msg ->> 'max_attempts')::integer, 5),
    msg ->> 'dedupe_key'
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_workflow_cancel (
  run text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."workflow_runs"%rowtype;
begin
  select * into v_run from "better_supabase"."workflow_runs" x
  where (x."id"::text = request_workflow_cancel.run or x."external_id" = request_workflow_cancel.run)
  order by x."id"::text = request_workflow_cancel.run desc
  limit 1
  for update;
  if not found then
    return null;
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or v_run."actor_id" = (select auth.uid())
    or (v_run."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_run."tenant_id", 'workflow.admin'), false))) then
    raise exception 'You may not cancel this run' using errcode = '42501', hint = 'WORKFLOW_FORBIDDEN';
  end if;
  if v_run."status" in ('completed', 'failed', 'cancelled') then
    return jsonb_build_object(
    'id', v_run."id",
    'engine', v_run."engine",
    'externalId', v_run."external_id",
    'definition', v_run."definition",
    'tenant', v_run."tenant_id",
    'actor', v_run."actor_id",
    'status', v_run."status",
    'attributes', v_run."attributes",
    'error', v_run."error",
    'createdAt', v_run."created_at",
    'updatedAt', v_run."updated_at",
    'startedAt', v_run."started_at",
    'completedAt', v_run."completed_at",
    'cancelRequestedAt', v_run."cancel_requested_at"
  );
  end if;
  update "better_supabase"."workflow_runs" set "cancel_requested_at" = coalesce("cancel_requested_at", now()), "updated_at" = now()
  where "id" = v_run."id"
  returning * into v_run;
  return jsonb_build_object(
    'id', v_run."id",
    'engine', v_run."engine",
    'externalId', v_run."external_id",
    'definition', v_run."definition",
    'tenant', v_run."tenant_id",
    'actor', v_run."actor_id",
    'status', v_run."status",
    'attributes', v_run."attributes",
    'error', v_run."error",
    'createdAt', v_run."created_at",
    'updatedAt', v_run."updated_at",
    'startedAt', v_run."started_at",
    'completedAt', v_run."completed_at",
    'cancelRequestedAt', v_run."cancel_requested_at"
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_workflow_start (
  key         text,
  workflow    text,
  payload     jsonb    DEFAULT '{}'::jsonb,
  tenant      uuid     DEFAULT NULL::uuid,
  actor       uuid     DEFAULT NULL::uuid,
  concurrency integer  DEFAULT NULL::integer,
  debounce    interval DEFAULT NULL::interval,
  singleton   boolean  DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_id uuid;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('workflow_admission'), pg_catalog.hashtext(key));
  if coalesce(singleton, false) and (
    "better_supabase"."workflow_admission_active"(key) > 0
    or exists (select 1 from "better_supabase"."workflow_start_requests" x where x."key" = key and x."status" = 'pending')
  ) then
    return jsonb_build_object('id', null, 'status', 'dropped');
  end if;
  if debounce is not null then
    update "better_supabase"."workflow_start_requests" x set "status" = 'superseded'
    where x."key" = key and x."status" = 'pending'
      and (x."claimed_until" is null or x."claimed_until" < now());
  end if;
  insert into "better_supabase"."workflow_start_requests" ("key", "workflow", "input", "tenant_id", "actor_id", "concurrency", "not_before")
  values (key, workflow, coalesce(payload -> 'input', '[]'::jsonb), tenant, actor, case when coalesce(singleton, false) then 1 else concurrency end, now() + coalesce(debounce, interval '0'))
  returning "id" into v_id;
  return jsonb_build_object('id', v_id, 'status', 'pending');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.retry_dead_jobs (
  queue text,
  ids   bigint[] DEFAULT NULL::bigint[],
  batch integer  DEFAULT 1000
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  dead_id bigint;
  retried integer := 0;
begin
  for dead_id in
    select d.id from better_supabase.list_dead_jobs(queue, batch) d where ids is null
    union all
    select unnest(ids) where ids is not null
  loop
    if better_supabase.replay_dead_job(queue, dead_id) is not null then
      retried := retried + 1;
    end if;
  end loop;
  return retried;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_job (
  job_name text,
  schedule text,
  queue    text,
  payload  jsonb                    DEFAULT '{}'::jsonb,
  timezone text                     DEFAULT 'UTC'::text,
  next_run timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  tenant   text                     DEFAULT NULL::text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tenant is not null then
    raise exception 'pg_cron schedules have no tenant; set sql.modules.jobs.options.scheduler to "drain" to keep one per schedule';
  end if;
  if pg_catalog.to_regnamespace('cron') is null then
    raise exception 'schedule_job needs pg_cron: create extension pg_cron with schema pg_catalog, or set sql.modules.jobs.options.scheduler to "drain"';
  end if;
  if timezone <> 'UTC' then
    raise exception 'pg_cron runs schedules in cron.timezone, not %; set sql.modules.jobs.options.scheduler to "drain" for per-schedule time zones', timezone;
  end if;
  perform better_supabase.ensure_job_queue(queue);
  return cron.schedule(job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unschedule_job (
  job_name text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if pg_catalog.to_regnamespace('cron') is null then
    return false;
  end if;
  return cron.unschedule(job_name);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unschedule_tenant (
  tenant text
)
  RETURNS integer
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select 0;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_admission_active (
  key text
)
  RETURNS integer
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select count(*)::integer from "better_supabase"."workflow_start_requests" x
  where x."key" = workflow_admission_active.key
    and (
      (x."status" = 'pending' and x."claimed_until" >= now())
      or (x."status" = 'started' and not exists (
        select 1 from "better_supabase"."workflow_runs" y
        where y."external_id" = x."run_id" and y."status" in ('completed', 'failed', 'cancelled')
      ) and x."started_at" > now() - interval '1 day')
    );
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_run_get (
  run text
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select jsonb_build_object(
    'id', x."id",
    'engine', x."engine",
    'externalId', x."external_id",
    'definition', x."definition",
    'tenant', x."tenant_id",
    'actor', x."actor_id",
    'status', x."status",
    'attributes', x."attributes",
    'error', x."error",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at",
    'startedAt', x."started_at",
    'completedAt', x."completed_at",
    'cancelRequestedAt', x."cancel_requested_at"
  )
  from "better_supabase"."workflow_runs" x
  where x."id"::text = workflow_run_get.run or x."external_id" = workflow_run_get.run
  order by x."id"::text = workflow_run_get.run desc
  limit 1;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_runs_changed()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'UPDATE' and old."status" = new."status" then
    return null;
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('id', new."id", 'status', new."status"), 'status', 'workflow-run:' || new."id"::text, true);
    if new."tenant_id" is not null then
      perform realtime.send(jsonb_build_object('id', new."id", 'status', new."status"), 'status', 'workflow-runs:' || new."tenant_id"::text, true);
    end if;
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_runs_list (
  tenant     uuid                     DEFAULT NULL::uuid,
  definition text                     DEFAULT NULL::text,
  status     text                     DEFAULT NULL::text,
  max        integer                  DEFAULT 50,
  before     timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'engine', x."engine",
    'externalId', x."external_id",
    'definition', x."definition",
    'tenant', x."tenant_id",
    'actor', x."actor_id",
    'status', x."status",
    'attributes', x."attributes",
    'error', x."error",
    'createdAt', x."created_at",
    'updatedAt', x."updated_at",
    'startedAt', x."started_at",
    'completedAt', x."completed_at",
    'cancelRequestedAt', x."cancel_requested_at"
  ) order by x."created_at" desc), '[]'::jsonb)
  from (
    select * from "better_supabase"."workflow_runs" y
    where (workflow_runs_list.tenant is null or y."tenant_id" = workflow_runs_list.tenant)
      and (workflow_runs_list.definition is null or y."definition" = workflow_runs_list.definition)
      and (workflow_runs_list.status is null or y."status" = workflow_runs_list.status)
      and (workflow_runs_list.before is null or y."created_at" < workflow_runs_list.before)
    order by y."created_at" desc
    limit least(greatest(coalesce(workflow_runs_list.max, 50), 1), 500)
  ) x;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_schedules_list (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', x."id",
    'tenant', x."tenant_id",
    'name', x."name",
    'workflow', x."workflow",
    'input', x."input",
    'cron', x."cron",
    'timezone', x."timezone",
    'nextRunAt', x."next_run_at",
    'lastRunAt', x."last_run_at",
    'paused', x."paused",
    'createdBy', x."created_by",
    'createdAt', x."created_at"
  ) order by x."name"), '[]'::jsonb)
  from "better_supabase"."workflow_schedules" x
  where workflow_schedules_list.tenant is null or x."tenant_id" = workflow_schedules_list.tenant;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_sdk_mirror_run()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;

ALTER TABLE "better_supabase"."workflow_runs"
  ADD CONSTRAINT "workflow_runs_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."workflow_schedules"
  ADD CONSTRAINT "workflow_schedules_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE "better_supabase"."workflow_start_requests"
  ADD CONSTRAINT "workflow_start_requests_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX workflow_runs_actor_idx ON better_supabase.workflow_runs USING btree (actor_id, created_at DESC);

CREATE INDEX workflow_runs_status_idx ON better_supabase.workflow_runs USING btree (status, completed_at);

CREATE INDEX workflow_runs_tenant_idx ON better_supabase.workflow_runs USING btree (tenant_id, created_at DESC);

CREATE INDEX workflow_schedules_created_by_idx ON better_supabase.workflow_schedules USING btree (created_by);

CREATE INDEX workflow_schedules_due_idx ON better_supabase.workflow_schedules USING btree (next_run_at)
  WHERE (NOT paused);

CREATE INDEX workflow_start_requests_actor_idx ON better_supabase.workflow_start_requests USING btree (actor_id);

CREATE INDEX workflow_start_requests_due_idx ON better_supabase.workflow_start_requests USING btree (not_before)
  WHERE (status = 'pending'::text);

CREATE INDEX workflow_start_requests_key_idx ON better_supabase.workflow_start_requests USING btree (key, status);

CREATE INDEX workflow_events_correlation_id_index ON workflow.workflow_events USING btree (correlation_id);

CREATE UNIQUE INDEX workflow_events_entity_creation_unique ON workflow.workflow_events USING btree (run_id, correlation_id, TYPE)
  WHERE
    ((TYPE)::text = ANY (ARRAY[('step_created'::character varying)::text, ('hook_created'::character varying)::text, ('wait_created'::character varying)::text,
    ('attr_set'::character varying)::text]));

CREATE UNIQUE INDEX workflow_events_hook_resume_unique ON workflow.workflow_events USING btree (run_id, resume_id)
  WHERE (((TYPE)::text = 'hook_received'::text) AND (resume_id IS NOT NULL));

CREATE INDEX workflow_hooks_run_id_index ON workflow.workflow_hooks USING btree (run_id);

CREATE INDEX workflow_hooks_token_index ON workflow.workflow_hooks USING btree (token);

CREATE INDEX workflow_invocations_pending ON workflow.workflow_invocations USING btree (run_id, SEQUENCE)
  WHERE (responded_at IS NULL);

CREATE INDEX workflow_runs_attributes_idx ON workflow.workflow_runs USING gin (attributes jsonb_path_ops);

CREATE INDEX workflow_runs_name_index ON workflow.workflow_runs USING btree (name);

CREATE INDEX workflow_runs_status_index ON workflow.workflow_runs USING btree (status);

CREATE INDEX workflow_steps_run_id_index ON workflow.workflow_steps USING btree (run_id);

CREATE INDEX workflow_steps_status_index ON workflow.workflow_steps USING btree (status);

CREATE INDEX workflow_stream_chunks_run_id_index ON workflow.workflow_stream_chunks USING btree (run_id);

CREATE INDEX workflow_waits_run_id_index ON workflow.workflow_waits USING btree (run_id);

CREATE TRIGGER bs_workflow_runs_status
  AFTER INSERT OR UPDATE OF status ON better_supabase.workflow_runs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.workflow_runs_changed();

CREATE TRIGGER bs_workflow_sdk_runs_mirror
  AFTER INSERT OR UPDATE OF status, attributes, error ON workflow.workflow_runs
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.workflow_sdk_mirror_run();

CREATE POLICY "workflow_runs_read" ON "better_supabase"."workflow_runs"
  FOR SELECT
  TO "authenticated"
  USING (((actor_id = ( SELECT auth.uid() AS uid)) OR (tenant_id IN ( SELECT better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with))));

CREATE POLICY "workflow_schedules_read" ON "better_supabase"."workflow_schedules"
  FOR SELECT
  TO "authenticated"
  USING ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('workflow.read'::text) AS tenant_ids_with)));

CREATE POLICY "bs_workflow_runs_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (((( SELECT realtime.topic() AS topic) ~~ 'workflow-run:%'::text) AND (EXISTS ( SELECT 1
   FROM better_supabase.workflow_runs x
  WHERE ((x.id)::text = substr(( SELECT realtime.topic() AS topic), 14))))) OR
    ((( SELECT realtime.topic() AS topic) ~~ 'workflow-runs:%'::text) AND (substr(( SELECT realtime.topic() AS topic), 15) IN ( SELECT (t.t)::text AS t
   FROM better_supabase.tenant_ids_with('workflow.read'::text) t(t)))))));

REVOKE ALL ON FUNCTION "api"."acquire_workflow_semaphore"(text, text, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."acquire_workflow_semaphore"(text, text, integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "api"."advance_workflow_schedule"(uuid, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."advance_workflow_schedule"(uuid, timestamp WITH time zone, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."claim_due_workflow_schedules"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_due_workflow_schedules"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."claim_workflow_start_requests"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."claim_workflow_start_requests"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."create_workflow_schedule"(text, text, text, timestamp WITH time zone, jsonb, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."create_workflow_schedule"(text, text, text, timestamp WITH time zone, jsonb, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."mark_workflow_start_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."mark_workflow_start_request"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."pause_workflow_schedule"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."pause_workflow_schedule"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_workflow_runs"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_workflow_runs"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "api"."release_workflow_semaphore"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."release_workflow_semaphore"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."remove_workflow_schedule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."remove_workflow_schedule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."request_workflow_cancel"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."request_workflow_cancel"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_admission_active"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_admission_active"(text) TO "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_run_get"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_run_get"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."workflow_schedules_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."workflow_schedules_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."acquire_workflow_semaphore"(text, text, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."acquire_workflow_semaphore"(text, text, integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."advance_schedule"(text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."advance_schedule"(text, timestamp WITH time zone, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."advance_workflow_schedule"(uuid, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."advance_workflow_schedule"(uuid, timestamp WITH time zone, timestamp WITH time zone) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_due_schedules"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_due_schedules"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_due_workflow_schedules"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_due_workflow_schedules"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_jobs"(text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_jobs"(text, integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."claim_workflow_start_requests"(integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."claim_workflow_start_requests"(integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."complete_job"(text, bigint, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."complete_job"(text, bigint, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."create_workflow_schedule"(text, text, text, timestamp WITH time zone, jsonb, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."create_workflow_schedule"(text, text, text, timestamp WITH time zone, jsonb, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."dispatch_workflow_deliveries"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."dispatch_workflow_deliveries"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."enqueue_job"(text, jsonb, integer, integer, text, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."enqueue_job"(text, jsonb, integer, integer, text, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ensure_job_queue"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ensure_job_queue"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."extend_job_lease"(text, bigint, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."extend_job_lease"(text, bigint, integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."fail_job"(text, bigint, integer, text, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."fail_job"(text, bigint, integer, text, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."index_job_queue"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."index_job_queue"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."job_queue_stats"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."job_queue_stats"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_dead_jobs"(text, integer, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_dead_jobs"(text, integer, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_schedules"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_schedules"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."mark_workflow_start_request"(uuid, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."mark_workflow_start_request"(uuid, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pause_workflow_schedule"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pause_workflow_schedule"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_job_archive"(text, interval, integer, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_job_archive"(text, interval, integer, interval) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_workflow_runs"(interval, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_workflow_runs"(interval, integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE
  ON FUNCTION "better_supabase"."record_workflow_run"(text, text, text, text, uuid, uuid, jsonb, text, timestamp WITH time zone, timestamp WITH time zone)
  TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."release_workflow_semaphore"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."release_workflow_semaphore"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."remove_workflow_schedule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."remove_workflow_schedule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."replay_dead_job"(text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."replay_dead_job"(text, bigint) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."request_workflow_cancel"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."request_workflow_cancel"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."request_workflow_start"(text, text, jsonb, uuid, uuid, integer, interval, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."retry_dead_jobs"(text, bigint[], integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."retry_dead_jobs"(text, bigint[], integer) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."schedule_job"(text, text, text, jsonb, text, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."schedule_job"(text, text, text, jsonb, text, timestamp WITH time zone, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unschedule_job"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unschedule_job"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."unschedule_tenant"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."unschedule_tenant"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_admission_active"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_admission_active"(text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_run_get"(text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_run_get"(text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_runs_changed"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_runs_list"(uuid, text, text, integer, timestamp WITH time zone) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_schedules_list"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_schedules_list"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."workflow_sdk_mirror_run"() FROM PUBLIC;

GRANT USAGE ON SCHEMA "workflow" TO "service_role";

GRANT SELECT, USAGE ON SEQUENCE "workflow"."workflow_invocations_sequence_seq" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_runs" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_runs" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."workflow_schedules" TO "authenticated";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_schedules" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_semaphores" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."workflow_start_requests" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_event_slots" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_events" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_hooks" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_invocations" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_runs" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_snapshots" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_steps" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_stream_chunks" TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_waits" TO "service_role";
