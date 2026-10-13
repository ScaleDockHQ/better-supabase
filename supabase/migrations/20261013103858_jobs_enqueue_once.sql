SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.enqueue_job_once (
  queue        text,
  payload      jsonb,
  dedupe_key   text,
  delay        integer DEFAULT 0,
  max_attempts integer DEFAULT 5
)
  RETURNS TABLE (
    id        bigint,
    duplicate boolean
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  existing bigint;
begin
  if dedupe_key is null then
    raise exception 'enqueue_job_once needs a dedupe_key' using errcode = '22004';
  end if;
  perform better_supabase.ensure_job_queue(queue);
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(queue), pg_catalog.hashtext(dedupe_key));
  execute format('select msg_id from pgmq.%I where message ? ''dedupe_key'' and message ->> ''dedupe_key'' = $1 union all select msg_id from pgmq.%I where message ? ''dedupe_key'' and message ->> ''dedupe_key'' = $1 limit 1', 'q_' || queue, 'a_' || queue)
    into existing using dedupe_key;
  if existing is not null then
    id := existing;
    duplicate := true;
  else
    id := better_supabase.enqueue_job(queue, payload, delay, max_attempts, dedupe_key);
    duplicate := false;
  end if;
  return next;
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
  execute format(
    'create index if not exists %I on pgmq.%I ((message ->> ''dedupe_key'')) where message ? ''dedupe_key''',
    'a_' || queue || '_dedupe_idx',
    'a_' || queue
  );
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."enqueue_job_once"(text, jsonb, text, integer, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."enqueue_job_once"(text, jsonb, text, integer, integer) TO "service_role";
