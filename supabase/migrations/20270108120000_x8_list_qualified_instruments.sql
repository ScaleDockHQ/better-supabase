SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.list_qualified_instruments (
  tenant  uuid,
  on_date date DEFAULT CURRENT_DATE
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_qualified_instruments"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_qualified_instruments (
  tenant  uuid,
  on_date date DEFAULT CURRENT_DATE
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_qualified_instruments.tenant is not null and coalesce(better_supabase.can('tenant', list_qualified_instruments.tenant, 'lims.read'), false))) then
    raise exception 'not allowed to read instruments' using errcode = '42501', hint = 'LIMS_FORBIDDEN';
  end if;
  return "better_supabase"."qualified_holders"(list_qualified_instruments.tenant, 'calibration', 'asset', coalesce(list_qualified_instruments.on_date, current_date));
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_qualified_instruments"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_qualified_instruments"(uuid, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_qualified_instruments"(uuid, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_qualified_instruments"(uuid, date) TO "authenticated", "service_role";
