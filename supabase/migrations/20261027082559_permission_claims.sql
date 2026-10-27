SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.permission_claims (
  user_id uuid,
  tenant  uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."permission_claims"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.permission_claims (
  user_id uuid,
  tenant  uuid
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select case
    when permission_claims.tenant is null then '{}'::jsonb
    else coalesce(jsonb_strip_nulls(jsonb_build_object(permission_claims.tenant::text, to_jsonb(better_supabase.member_permissions(permission_claims.user_id, permission_claims.tenant)))), '{}'::jsonb)
  end
$function$;

CREATE OR REPLACE FUNCTION rbac.bump_override_authz_versions()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  changed_organization uuid := coalesce(new.organization_id, old.organization_id);
  changed_role uuid := coalesce(new.role_id, old.role_id);
begin
  insert into rbac.user_authz_versions as v (user_id)
  select m.user_id
  from public.memberships m
  where m.organization_id = changed_organization
    and m.role = changed_role
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now();

  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION rbac.compact_permission_keys (
  granted text[]
)
  RETURNS text[]
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(array_agg(k order by k), '{}'::text[])
  from (
    select c.resource || '.*' as k
    from (
      select split_part(p.key, '.', 1) as resource,
        bool_and(p.key = any(granted)) as every
      from better_supabase.permissions p
      group by 1
    ) c
    where c.every
    union all
    select g
    from unnest(granted) g
    where exists (
      select 1 from better_supabase.permissions p
      where split_part(p.key, '.', 1) = split_part(g, '.', 1)
        and not p.key = any(granted)
    )
    or not exists (
      select 1 from better_supabase.permissions p
      where split_part(p.key, '.', 1) = split_part(g, '.', 1)
    )
  ) keys
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
  authz_version bigint;
  active_tenant text := claims -> 'app_metadata' ->> 'tenant_id';
  permission_keys jsonb := '{}'::jsonb;
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

CREATE TRIGGER permission_overrides_bump_authz_versions
  AFTER INSERT OR DELETE OR UPDATE ON better_supabase.permission_overrides
  FOR EACH ROW
  EXECUTE FUNCTION rbac.bump_override_authz_versions();

CREATE TRIGGER memberships_bump_authz_version
  AFTER INSERT OR DELETE OR UPDATE OF ROLE ON public.memberships
  FOR EACH ROW
  EXECUTE FUNCTION rbac.bump_authz_version();

REVOKE ALL ON FUNCTION "api"."permission_claims"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."permission_claims"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."permission_claims"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."permission_claims"(uuid, uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "rbac"."bump_override_authz_versions"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "rbac"."compact_permission_keys"(text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "rbac"."compact_permission_keys"(text[]) TO "supabase_auth_admin";
