SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.outbox_stamp_xid()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if tg_op = 'INSERT' then
    new."xid" := pg_current_xact_id();
  else
    new."xid" := old."xid";
  end if;
  return new;
end;
$function$;

CREATE TRIGGER bsb_outbox_stamp_xid
  BEFORE INSERT OR UPDATE OF xid ON better_supabase.outbox_events
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.outbox_stamp_xid();

REVOKE ALL ON FUNCTION "better_supabase"."outbox_stamp_xid"() FROM PUBLIC;
