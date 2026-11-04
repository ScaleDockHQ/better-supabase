SET local check_function_bodies = off;

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
    created_at   timestamp with time zone,
    payload      jsonb
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
    'select j.jobname::text, j.schedule::text, ''UTC''::text, null::text, null::text, null::timestamptz, null::timestamptz, null::timestamptz, null::timestamptz, null::jsonb
     from %s j where $1 is null or starts_with(j.jobname, $1) order by j.jobname', v_jobs)
    using name_prefix;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.ready_job_queues (
  queues text[]
)
  RETURNS TABLE (
    queue text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_name text;
  v_ready boolean;
begin
  foreach v_name in array coalesce(queues, '{}') loop
    if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || v_name)) is not null then
      execute format('select exists (select 1 from pgmq.%I where vt <= clock_timestamp())', 'q_' || v_name)
        into v_ready;
      if v_ready then
        queue := v_name;
        return next;
      end if;
    end if;
  end loop;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."list_schedules"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_schedules"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."ready_job_queues"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."ready_job_queues"(text[]) TO "service_role";
