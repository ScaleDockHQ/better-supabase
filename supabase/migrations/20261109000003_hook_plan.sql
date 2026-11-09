SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.hook_plan (
  event jsonb
)
  RETURNS text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."hook_plan"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.hook_plan (
  event jsonb
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_user uuid := nullif(event ->> 'user_id', '')::uuid;
begin
  if coalesce(v_claims ->> 'client_id', '') <> '' then
    return 'slim';
  end if;

  if event ->> 'authentication_method' = 'token_refresh'
    and jsonb_typeof(v_claims -> 'authz_ver') = 'number'
    and jsonb_typeof(v_claims -> 'memberships') = 'array'
    and coalesce(v_claims ->> 'permissions_truncated', 'false') <> 'true'
    and coalesce(v_claims ->> 'team_ids_truncated', 'false') <> 'true'
    and (v_claims ->> 'authz_ver')::bigint = better_supabase.authz_version(v_user)
  then
    return 'reuse';
  end if;

  return 'full';
end;
$function$;

CREATE OR REPLACE FUNCTION rbac.custom_access_token_hook (
  event jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  claims jsonb := event -> 'claims';
  user_role rbac.app_role;
  active_tenant text := claims -> 'app_metadata' ->> 'tenant_id';
  permission_keys jsonb := '{}'::jsonb;
  plan text := better_supabase.hook_plan(event);
begin
  -- blocks['sessions'].options.hook: an OAuth client token carries none of
  -- the claims below, and a refresh whose authz_ver is still current keeps
  -- the claims it already has, so neither reads memberships or permissions.
  if plan in ('slim', 'reuse') then
    return event;
  end if;

  select ur.role into user_role
  from rbac.user_roles ur
  where ur.user_id = (event ->> 'user_id')::uuid;

  if user_role is not null then
    claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
  end if;

  -- The version SessionProvider and `subscribeAuthzVersions` watch
  -- (blocks['sessions'].options.authzVersions).
  claims := jsonb_set(claims, '{authz_ver}', to_jsonb(better_supabase.authz_version((event ->> 'user_id')::uuid)));

  -- Every organization the user belongs to, and each one's plan features
  -- (supabase/schemas/045_access_contract.sql and the entitlements module).
  claims := jsonb_set(claims, '{memberships}', better_supabase.membership_claims((event ->> 'user_id')::uuid));
  claims := jsonb_set(claims, '{features}', better_supabase.feature_claims((event ->> 'user_id')::uuid));

  -- The permission keys for the active organization only, which
  -- `permissionsOf()` and `permissionsAuthorizer()` read. Past the budget the
  -- token says so, and the app reads `my_permissions()` instead.
  if active_tenant ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    permission_keys := better_supabase.permission_claims((event ->> 'user_id')::uuid, active_tenant::uuid);
  end if;

  if permission_keys ? active_tenant then
    permission_keys := jsonb_build_object(active_tenant, to_jsonb(rbac.compact_permission_keys(
      array(select jsonb_array_elements_text(permission_keys -> active_tenant))
    )));
  end if;

  if octet_length(permission_keys::text) > 2048 then
    claims := jsonb_set(claims, '{permissions}', '{}'::jsonb);
    claims := jsonb_set(claims, '{permissions_truncated}', 'true'::jsonb);
  else
    claims := jsonb_set(claims, '{permissions}', permission_keys);
    claims := claims - 'permissions_truncated';
  end if;

  return jsonb_set(event, '{claims}', claims);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."hook_plan"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."hook_plan"(jsonb) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."hook_plan"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."hook_plan"(jsonb) TO "service_role", "supabase_auth_admin";
