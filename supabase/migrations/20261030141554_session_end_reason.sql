SET local check_function_bodies = off;

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
      'end_reason', better_supabase.session_end_reason(),
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

CREATE OR REPLACE FUNCTION better_supabase.session_end_reason()
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if exists (
    select 1 from auth.users u
    where u.id = auth.uid() and u.banned_until is not null and u.banned_until > now()
  ) then
    return 'user_banned';
  end if;
  return 'session_not_found';
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."session_end_reason"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."session_end_reason"() TO "authenticated";
