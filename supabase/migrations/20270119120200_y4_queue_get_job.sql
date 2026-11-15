SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.get_job (
  queue  text,
  job_id bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  r record;
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || queue)) is not null then
    execute format('select read_ct, enqueued_at, vt, message from pgmq.%I where msg_id = $1', 'q_' || queue)
      into r using job_id;
    if r.read_ct is not null then
      return jsonb_build_object(
        'queue', queue,
        'id', job_id,
        'state', case when r.read_ct > 0 and r.vt > clock_timestamp() and not r.message ? 'last_error' then 'running' else 'waiting' end,
        'attempts', r.read_ct,
        'enqueuedAt', r.enqueued_at,
        'lastError', r.message ->> 'last_error',
        'maxAttempts', coalesce((r.message ->> 'max_attempts')::integer, 5)
      );
    end if;
  end if;
  if pg_catalog.to_regclass(format('pgmq.%I', 'a_' || queue)) is not null then
    execute format('select read_ct, enqueued_at, archived_at, message from pgmq.%I where msg_id = $1', 'a_' || queue)
      into r using job_id;
    if r.read_ct is not null then
      return jsonb_build_object(
        'queue', queue,
        'id', job_id,
        'state', case when r.message ? 'dead' then 'dead' else 'done' end,
        'attempts', r.read_ct,
        'enqueuedAt', r.enqueued_at,
        'finishedAt', r.archived_at,
        'lastError', r.message ->> 'last_error',
        'maxAttempts', coalesce((r.message ->> 'max_attempts')::integer, 5)
      );
    end if;
  end if;
  return null;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."get_job"(text, bigint) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_job"(text, bigint) TO "service_role";
