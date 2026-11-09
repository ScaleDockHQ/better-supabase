SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.bump_authz_versions (
  p_users uuid[]
)
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  insert into better_supabase.user_authz_versions as v (user_id)
  select distinct u from unnest(p_users) u
  where u is not null and exists (select 1 from auth.users x where x.id = u)
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now()
$function$;
