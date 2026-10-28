SET local check_function_bodies = off;

DROP TRIGGER "memberships_bump_authz_version" ON "public"."memberships";

DROP TRIGGER "user_roles_bump_authz_version" ON "rbac"."user_roles";

ALTER TABLE "rbac"."user_authz_versions"
  DROP CONSTRAINT "user_authz_versions_user_id_fkey";

DROP FUNCTION "rbac"."bump_authz_version"();

DROP TABLE "rbac"."user_authz_versions";

DROP FUNCTION "rbac"."broadcast_authz_version"();

CREATE TABLE "better_supabase"."user_authz_versions" (
  "user_id"    uuid                     NOT NULL,
  "version"    bigint                   NOT NULL DEFAULT 1,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "user_authz_versions_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "better_supabase"."user_authz_versions"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION api.authz_version (
  p_user uuid
)
  RETURNS bigint
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."authz_version"($1) $function$;

CREATE OR REPLACE FUNCTION api.bump_authz_versions (
  p_users uuid[]
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."bump_authz_versions"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.authz_version (
  p_user uuid
)
  RETURNS bigint
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select coalesce(
    (select v.version from better_supabase.user_authz_versions v where v.user_id = p_user),
    0
  )
$function$;

CREATE OR REPLACE FUNCTION better_supabase.broadcast_authz_version()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('user_id', new.user_id, 'version', new.version), 'changed', 'better_supabase:authz', true);
  end if;
  if to_regprocedure('realtime.send(jsonb, text, text, boolean)') is not null then
    perform realtime.send(jsonb_build_object('user_id', new.user_id, 'version', new.version), 'changed', 'authz:' || new.user_id::text, true);
  end if;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bump_authz_version()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  col text := coalesce(tg_argv[0], 'user_id');
begin
  perform better_supabase.bump_authz_versions(array[
    (to_jsonb(new) ->> col)::uuid,
    (to_jsonb(old) ->> col)::uuid
  ]);
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bump_authz_versions (
  p_users uuid[]
)
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  insert into better_supabase.user_authz_versions as v (user_id)
  select distinct u from unnest(p_users) u where u is not null
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now()
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
  perform better_supabase.bump_authz_versions(array(
    select m.user_id
    from public.memberships m
    where m.organization_id = changed_organization
      and m.role = changed_role
  ));

  return null;
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
$function$;

ALTER TABLE "better_supabase"."user_authz_versions"
  ADD CONSTRAINT "user_authz_versions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE TRIGGER bsb_authz_versions_broadcast
  AFTER INSERT OR UPDATE ON better_supabase.user_authz_versions
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.broadcast_authz_version();

CREATE TRIGGER memberships_bump_authz_version
  AFTER INSERT OR DELETE OR UPDATE OF ROLE ON public.memberships
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bump_authz_version();

CREATE TRIGGER user_roles_bump_authz_version
  AFTER INSERT OR DELETE OR UPDATE ON rbac.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bump_authz_version();

CREATE POLICY "bsb_authz_versions_auth_admin" ON "better_supabase"."user_authz_versions"
  FOR SELECT
  TO "supabase_auth_admin"
  USING (true);

CREATE POLICY "bsb_authz_versions_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) = ('authz:'::text || (( SELECT auth.uid() AS uid))::text))));

REVOKE ALL ON FUNCTION "api"."authz_version"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."authz_version"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."bump_authz_versions"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."bump_authz_versions"(uuid[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."authz_version"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."authz_version"(uuid) TO "service_role", "supabase_auth_admin";

REVOKE ALL ON FUNCTION "better_supabase"."broadcast_authz_version"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bump_authz_version"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bump_authz_versions"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."bump_authz_versions"(uuid[]) TO "service_role";

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "better_supabase"."user_authz_versions" TO "service_role";

GRANT SELECT ON TABLE "better_supabase"."user_authz_versions" TO "supabase_auth_admin";
