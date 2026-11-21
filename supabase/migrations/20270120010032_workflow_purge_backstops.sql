SET local check_function_bodies = off;

CREATE TABLE "workflow"."workflow_purge_backstops" (
  "run_id"     character varying        NOT NULL,
  "due_at"     timestamp with time zone NOT NULL,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "workflow_purge_backstops_pkey" PRIMARY KEY (run_id)
);

ALTER TABLE "workflow"."workflow_purge_backstops"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION better_supabase.workflow_purge_backstops (
  batch integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_purge_runs (
  older_than       interval DEFAULT '30 days'::interval,
  statuses         text[]   DEFAULT ARRAY['completed'::text,
  'failed'::text,
  'cancelled'::text],
  batch            integer  DEFAULT 500,
  skip_unprojected boolean  DEFAULT false
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
$function$;

CREATE OR REPLACE FUNCTION workflow.add_job (
  identifier   text,
  payload      json                     DEFAULT NULL::json,
  run_at       timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  max_attempts integer                  DEFAULT NULL::integer,
  job_key      text                     DEFAULT NULL::text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
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
$function$;

CREATE INDEX workflow_purge_backstops_due_at_idx ON workflow.workflow_purge_backstops USING btree (due_at);

REVOKE ALL ON FUNCTION "better_supabase"."workflow_purge_backstops"(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."workflow_purge_backstops"(integer) TO "service_role";

REVOKE ALL ON FUNCTION "workflow"."add_job"(text, json, timestamp WITH time zone, integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "workflow"."add_job"(text, json, timestamp WITH time zone, integer, text) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "workflow"."workflow_purge_backstops" TO "service_role";
