SET local check_function_bodies = off;

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
  for v_job in select * from better_supabase.claim_jobs('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
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
declare
  v_jobs regclass := pg_catalog.to_regclass('cron.job');
begin
  if v_jobs is null or list_schedules.for_tenant is not null then
    return;
  end if;
  return query execute format(
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz
     from %s j where $1 is null or starts_with(j.jobname, $1) order by j.jobname', v_jobs)
    using name_prefix;
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
declare
  -- pg_cron is optional: its functions are looked up, not named, so
  -- plpgsql_check (supabase db lint) passes without the extension.
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
  v_id bigint;
begin
  if tenant is not null then
    raise exception 'pg_cron schedules have no tenant; set sql.modules.jobs.options.scheduler to "drain" to keep one per schedule';
  end if;
  if v_schedule is null then
    raise exception 'schedule_job needs pg_cron: create extension pg_cron with schema pg_catalog, or set sql.modules.jobs.options.scheduler to "drain"';
  end if;
  if timezone <> 'UTC' then
    raise exception 'pg_cron runs schedules in cron.timezone, not %; set sql.modules.jobs.options.scheduler to "drain" for per-schedule time zones', timezone;
  end if;
  perform better_supabase.ensure_job_queue(queue);
  execute format('select %s($1::text, $2::text, $3::text)', v_schedule::oid::regproc)
    into v_id
    using job_name, schedule, format('select better_supabase.enqueue_job(%L, %L::jsonb)', queue, payload::text);
  return v_id;
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
declare
  v_unschedule regprocedure := pg_catalog.to_regprocedure('cron.unschedule(text)');
  v_removed boolean;
begin
  if v_unschedule is null then
    return false;
  end if;
  execute format('select %s($1::text)', v_unschedule::oid::regproc)
    into v_removed
    using job_name;
  return v_removed;
end;
$function$;
