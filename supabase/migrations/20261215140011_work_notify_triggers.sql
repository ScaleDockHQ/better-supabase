SET local check_function_bodies = off;

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
    'create or replace trigger bsb_notify_work after insert on pgmq.%I referencing new table as new_rows for each statement execute function better_supabase.job_queue_notify(%L)',
    'q_' || queue,
    queue
  );
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

CREATE OR REPLACE FUNCTION better_supabase.job_queue_notify()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if exists (select 1 from new_rows) then
    perform pg_catalog.pg_notify('better_supabase_work', pg_catalog.json_build_object('kind', 'queue', 'queue', tg_argv[0])::text);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.outbox_notify()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if exists (select 1 from new_rows) then
    perform pg_catalog.pg_notify('better_supabase_work', '{"kind":"outbox"}');
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.webhook_inbox_notify()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if exists (select 1 from new_rows) then
    perform pg_catalog.pg_notify('better_supabase_work', '{"kind":"inbox"}');
  end if;
  return null;
end;
$function$;

CREATE TRIGGER bsb_notify_work
  AFTER INSERT ON better_supabase.outbox_events REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.outbox_notify();

CREATE TRIGGER bsb_notify_work
  AFTER INSERT ON better_supabase.webhook_inbox REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION better_supabase.webhook_inbox_notify();

REVOKE ALL ON FUNCTION "better_supabase"."job_queue_notify"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."outbox_notify"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."webhook_inbox_notify"() FROM PUBLIC;
