SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.permission_claims_bitset (
  user_id uuid,
  tenant  uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."permission_claims_bitset"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.permission_claims_bitset (
  user_id uuid,
  tenant  uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with catalog as (
    select coalesce(array_agg(c."key" order by c."key" collate "C"), '{}'::text[]) as keys
    from "better_supabase"."permissions" c
  )
  select case
    when permission_claims_bitset.tenant is null then '{}'::jsonb
    else jsonb_build_object(
      permission_claims_bitset.tenant::text,
      jsonb_build_object(
        'h', left(md5(array_to_string(catalog.keys, E'\n')), 8),
        'b', better_supabase.permission_bitset(
          catalog.keys,
          better_supabase.member_permissions(permission_claims_bitset.user_id, permission_claims_bitset.tenant)
        )
      )
    )
  end
  from catalog
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

  -- The permissions of the active organization only, as a catalog hash and a
  -- bitset (about 60 bytes for 413 keys), which `permissionsOf()` and
  -- `permissionsAuthorizer()` read over the generated `permissionKeys`. A
  -- hash the app doesn't know makes them read `my_permissions()` instead.
  if active_tenant ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    permission_keys := better_supabase.permission_claims_bitset((event ->> 'user_id')::uuid, active_tenant::uuid);
  end if;

  claims := jsonb_set(claims, '{permissions}', permission_keys);
  claims := claims - 'permissions_truncated';

  return jsonb_set(event, '{claims}', claims);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."permission_claims_bitset"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."permission_claims_bitset"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."permission_claims_bitset"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_claims_bitset"(uuid, uuid) TO "service_role", "supabase_auth_admin";
