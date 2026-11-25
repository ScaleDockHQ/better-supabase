SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.book_with_reminder (
  service        uuid,
  resource       uuid,
  starts_at      timestamp with time zone,
  customer       jsonb,
  offset_minutes integer
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."book_with_reminder"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION better_supabase.book_with_reminder (
  service        uuid,
  resource       uuid,
  starts_at      timestamp with time zone,
  customer       jsonb,
  offset_minutes integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_booking jsonb;
  v_reminder jsonb;
begin
  select s."tenant_id" into v_tenant from "better_supabase"."booking_services" s where s."id" = book_with_reminder.service;
  v_booking := "better_supabase"."hold_booking"(book_with_reminder.service, book_with_reminder.resource, book_with_reminder.starts_at, book_with_reminder.customer, true);
  v_reminder := "better_supabase"."save_reminder"(
    tenant => v_tenant,
    subject_type => 'booking',
    subject_id => v_booking ->> 'id',
    offset_minutes => book_with_reminder.offset_minutes
  );
  return jsonb_build_object('booking', v_booking, 'reminder', v_reminder);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."book_with_reminder"(uuid, uuid, timestamp WITH time zone, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."book_with_reminder"(uuid, uuid, timestamp WITH time zone, jsonb, integer) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."book_with_reminder"(uuid, uuid, timestamp WITH time zone, jsonb, integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."book_with_reminder"(uuid, uuid, timestamp WITH time zone, jsonb, integer) TO "authenticated", "service_role";
