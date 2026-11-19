SET local check_function_bodies = off;

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
    -- Two first enqueues can both see no queue; the slower create then fails.
    begin
      perform pgmq.create(queue);
    exception when unique_violation or duplicate_table or duplicate_object then
      if pg_catalog.to_regclass(format('pgmq.%I', 'q_' || queue)) is null then
        raise;
      end if;
    end;
    perform better_supabase.index_job_queue(queue);
  end if;
end;
$function$;
