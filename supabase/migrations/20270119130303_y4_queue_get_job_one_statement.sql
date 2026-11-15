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
  found jsonb;
begin
  if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || queue)) is not null then
    execute format($q$
      select jsonb_build_object(
        'queue', %L,
        'id', msg_id,
        'state', case when read_ct > 0 and vt > clock_timestamp() and not message ? 'last_error' then 'running' else 'waiting' end,
        'attempts', read_ct,
        'enqueuedAt', enqueued_at,
        'lastError', message ->> 'last_error',
        'maxAttempts', coalesce((message ->> 'max_attempts')::integer, 5))
      from pgmq.%I where msg_id = $1$q$, queue, 'q_' || queue)
      into found using job_id;
    if found is not null then
      return found;
    end if;
  end if;
  if pg_catalog.to_regclass(format('pgmq.%I', 'a_' || queue)) is not null then
    execute format($q$
      select jsonb_build_object(
        'queue', %L,
        'id', msg_id,
        'state', case when message ? 'dead' then 'dead' else 'done' end,
        'attempts', read_ct,
        'enqueuedAt', enqueued_at,
        'finishedAt', archived_at,
        'lastError', message ->> 'last_error',
        'maxAttempts', coalesce((message ->> 'max_attempts')::integer, 5))
      from pgmq.%I where msg_id = $1$q$, queue, 'a_' || queue)
      into found using job_id;
    if found is not null then
      return found;
    end if;
  end if;
  return null;
end;
$function$;
