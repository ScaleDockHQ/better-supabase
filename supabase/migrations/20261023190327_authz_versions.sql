SET local check_function_bodies = off;

CREATE TABLE "rbac"."user_authz_versions" (
  "user_id"    uuid                     NOT NULL,
  "version"    bigint                   NOT NULL DEFAULT 1,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "user_authz_versions_pkey" PRIMARY KEY (user_id)
);

ALTER TABLE "rbac"."user_authz_versions"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION rbac.broadcast_authz_version()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  perform realtime.send(
    jsonb_build_object('user_id', new.user_id, 'version', new.version),
    'changed',
    'authz-versions',
    true
  );

  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION rbac.bump_authz_version()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  changed uuid := coalesce(new.user_id, old.user_id);
begin
  insert into rbac.user_authz_versions as v (user_id)
  values (changed)
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now();

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
$function$;

ALTER TABLE "rbac"."user_authz_versions"
  ADD CONSTRAINT "user_authz_versions_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

CREATE TRIGGER user_authz_versions_broadcast
  AFTER INSERT OR UPDATE ON rbac.user_authz_versions
  FOR EACH ROW
  EXECUTE FUNCTION rbac.broadcast_authz_version();

CREATE TRIGGER user_roles_bump_authz_version
  AFTER INSERT OR DELETE OR UPDATE ON rbac.user_roles
  FOR EACH ROW
  EXECUTE FUNCTION rbac.bump_authz_version();

CREATE POLICY "Auth admin reads authorization versions" ON "rbac"."user_authz_versions"
  FOR SELECT
  TO "supabase_auth_admin"
  USING (true);

REVOKE ALL ON FUNCTION "rbac"."broadcast_authz_version"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "rbac"."bump_authz_version"() FROM PUBLIC;

GRANT SELECT ON TABLE "rbac"."user_authz_versions" TO "supabase_auth_admin";
