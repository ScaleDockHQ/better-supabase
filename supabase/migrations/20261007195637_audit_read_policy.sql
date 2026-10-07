SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.audit_read_tenants()
  RETURNS SETOF uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."audit_read_tenants"() $function$;

CREATE OR REPLACE FUNCTION api.audit_reads_all()
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."audit_reads_all"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_read_tenants()
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return query select t::uuid from better_supabase.tenant_ids_with('audit.read') t;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.audit_reads_all()
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return better_supabase.is_platform('audit.read');
end;
$function$;

CREATE POLICY "bs_audit_read" ON "better_supabase"."audit_events"
  FOR SELECT
  TO "authenticated"
  USING (((organization_id IN ( SELECT better_supabase.audit_read_tenants() AS audit_read_tenants)) OR ( SELECT better_supabase.audit_reads_all() AS audit_reads_all)));

REVOKE ALL
  ON FUNCTION "api"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  FROM "authenticated";

GRANT EXECUTE
  ON FUNCTION "api"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  TO "authenticated";

REVOKE ALL ON FUNCTION "api"."audit_read_tenants"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."audit_read_tenants"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."audit_reads_all"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."audit_reads_all"() TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "api"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp WITH time zone)
  FROM "authenticated";

GRANT EXECUTE
  ON FUNCTION "api"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp WITH time zone)
  TO "authenticated";

REVOKE ALL
  ON FUNCTION "api"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer)
  FROM "authenticated";

GRANT EXECUTE
  ON FUNCTION "api"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer)
  TO "authenticated";

REVOKE ALL
  ON FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  FROM "authenticated";

GRANT EXECUTE
  ON FUNCTION "better_supabase"."audit_event"(text, text, text, text, text, text, uuid, jsonb, text, jsonb, uuid, text, text, text, text, text, inet, text, text, text, text)
  TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."audit_read_tenants"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."audit_read_tenants"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."audit_reads_all"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."audit_reads_all"() TO "authenticated", "service_role";

REVOKE ALL
  ON FUNCTION "better_supabase"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone)
  FROM "authenticated";

GRANT EXECUTE
  ON FUNCTION "better_supabase"."count_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone)
  TO "authenticated";

REVOKE ALL
  ON FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer)
  FROM "authenticated";

GRANT EXECUTE
  ON FUNCTION "better_supabase"."list_audit_events"(uuid[], text[], uuid[], text[], text[], text[], text[], text, text[], text[], text[], timestamp WITH time zone, timestamp
    WITH time zone, timestamp WITH time zone, text, integer, boolean, integer)
  TO "authenticated";

REVOKE ALL ON TABLE "better_supabase"."audit_events" FROM "authenticated";

GRANT SELECT ON TABLE "better_supabase"."audit_events" TO "authenticated";
