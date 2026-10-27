SET local check_function_bodies = off;

ALTER TABLE "workflow"."workflow_events"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_events"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_events"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_hooks"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_hooks"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_hooks"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "expired_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "expired_at" TYPE timestamp WITH time zone USING "expired_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "responded_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_invocations"
  ALTER COLUMN "responded_at" TYPE timestamp WITH time zone USING "responded_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "completed_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "completed_at" TYPE timestamp WITH time zone USING "completed_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "expired_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "expired_at" TYPE timestamp WITH time zone USING "expired_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "started_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "started_at" TYPE timestamp WITH time zone USING "started_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "updated_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "updated_at" TYPE timestamp WITH time zone USING "updated_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_runs"
  ALTER COLUMN "updated_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_snapshots"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_snapshots"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_snapshots"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "completed_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "completed_at" TYPE timestamp WITH time zone USING "completed_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "retry_after" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "retry_after" TYPE timestamp WITH time zone USING "retry_after"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "started_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "started_at" TYPE timestamp WITH time zone USING "started_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "updated_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "updated_at" TYPE timestamp WITH time zone USING "updated_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_steps"
  ALTER COLUMN "updated_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_stream_chunks"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_stream_chunks"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_stream_chunks"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "completed_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "completed_at" TYPE timestamp WITH time zone USING "completed_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "created_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "created_at" TYPE timestamp WITH time zone USING "created_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "created_at" SET DEFAULT now();

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "resume_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "resume_at" TYPE timestamp WITH time zone USING "resume_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "updated_at" DROP DEFAULT;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "updated_at" TYPE timestamp WITH time zone USING "updated_at"::timestamp WITH time zone;

ALTER TABLE "workflow"."workflow_waits"
  ALTER COLUMN "updated_at" SET DEFAULT now();

CREATE OR REPLACE FUNCTION better_supabase.workflow_open_hooks (
  tenant        text    DEFAULT NULL::text,
  workflow_name text    DEFAULT NULL::text,
  max           integer DEFAULT 50
)
  RETURNS TABLE (
    hook_id    text,
    run_id     text,
    workflow   text,
    tenant_id  text,
    actor_id   text,
    metadata   jsonb,
    created_at timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select h.hook_id::text, h.run_id::text, r.name::text,
    r.attributes ->> 'bsb.tenant', r.attributes ->> 'bsb.actor',
    h.metadata, h.created_at
  from workflow.workflow_hooks h
  join workflow.workflow_runs r on r.id = h.run_id
  where r.status::text in ('pending', 'running')
    and not coalesce(h.is_system, false)
    and (workflow_open_hooks.tenant is null or r.attributes ->> 'bsb.tenant' = workflow_open_hooks.tenant)
    and (workflow_open_hooks.workflow_name is null or r.name = workflow_open_hooks.workflow_name)
  order by h.created_at desc
  limit least(greatest(coalesce(workflow_open_hooks.max, 50), 1), 500);
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_purge_runs (
  older_than interval DEFAULT '30 days'::interval,
  statuses   text[]   DEFAULT ARRAY['completed'::text,
  'failed'::text,
  'cancelled'::text],
  batch      integer  DEFAULT 500
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
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
$function$;
