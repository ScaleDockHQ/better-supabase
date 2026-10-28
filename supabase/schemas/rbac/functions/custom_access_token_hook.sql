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
begin
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
$$;

grant execute on function rbac.custom_access_token_hook(jsonb) to supabase_auth_admin;

revoke execute on function rbac.custom_access_token_hook(jsonb) from authenticated, anon, public;
