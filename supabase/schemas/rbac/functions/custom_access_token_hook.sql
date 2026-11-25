create or replace function rbac.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
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
$$;

grant execute on function rbac.custom_access_token_hook(jsonb) to supabase_auth_admin;

revoke execute on function rbac.custom_access_token_hook(jsonb) from authenticated, anon, public;
