create or replace function rbac.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  claims jsonb := event -> 'claims';
  user_role rbac.app_role;
  authz_version bigint;
begin
  select ur.role into user_role
  from rbac.user_roles ur
  where ur.user_id = (event ->> 'user_id')::uuid;

  if user_role is not null then
    claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
  end if;

  -- The version `subscribeAuthzVersions` evicts on (user_authz_versions.sql).
  select v.version into authz_version
  from rbac.user_authz_versions v
  where v.user_id = (event ->> 'user_id')::uuid;

  claims := jsonb_set(claims, '{authz_ver}', to_jsonb(coalesce(authz_version, 0)));

  -- Every organization the user belongs to, and each one's plan features
  -- (supabase/schemas/045_access_contract.sql and the entitlements module).
  claims := jsonb_set(claims, '{memberships}', better_supabase.membership_claims((event ->> 'user_id')::uuid));
  claims := jsonb_set(claims, '{features}', better_supabase.feature_claims((event ->> 'user_id')::uuid));

  return jsonb_set(event, '{claims}', claims);
end;
$$;

grant execute on function rbac.custom_access_token_hook(jsonb) to supabase_auth_admin;

revoke execute on function rbac.custom_access_token_hook(jsonb) from authenticated, anon, public;
