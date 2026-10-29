SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.caller_authz_version()
  RETURNS bigint
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."caller_authz_version"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.bootstrap_islands (
  args jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if not (select better_supabase.session_active()) then
    return jsonb_build_object(
      'session_active', false,
      'authz_version', auth.jwt() -> 'authz_ver',
      'token_authz_version', auth.jwt() -> 'authz_ver',
      'tenant', args ->> 'tenant',
      'data', null
    );
  end if;
  return jsonb_build_object(
    'session_active', true,
    'authz_version', to_jsonb(better_supabase.caller_authz_version()),
    'token_authz_version', auth.jwt() -> 'authz_ver',
    'tenant', args ->> 'tenant',
    'data', to_jsonb(public.island_counts(args))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.caller_authz_version()
  RETURNS bigint
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if auth.uid() is null then
    return null;
  end if;
  return better_supabase.authz_version(auth.uid());
end;
$function$;

REVOKE ALL ON FUNCTION "api"."caller_authz_version"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."caller_authz_version"() TO "authenticated";

REVOKE ALL ON FUNCTION "better_supabase"."caller_authz_version"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."caller_authz_version"() TO "authenticated";
