SET local check_function_bodies = off;

DROP POLICY "bsb_tenant_scope" ON "better_supabase"."drive_nodes";

DROP POLICY "drive_nodes_read" ON "better_supabase"."drive_nodes";

CREATE OR REPLACE FUNCTION api.drive_readable_ids()
  RETURNS SETOF uuid
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."drive_readable_ids"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_readable_ids()
  RETURNS SETOF uuid
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select x."id" from "better_supabase"."drive_nodes" x
  where coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or (auth.uid() is not null
      and x."tenant_id" in (select better_supabase.tenant_ids_with('drive.read'))
      and (x."tenant_id" in (select better_supabase.tenant_ids_with('drive.manage'))))
  union
  select s.node_id from "better_supabase"."drive_grants" dg
  cross join lateral "better_supabase"."drive_subtree"(dg."node_id") s
  join "better_supabase"."drive_nodes" x on x."id" = s.node_id
  where auth.uid() is not null and (dg."expires_at" is null or dg."expires_at" > now())
    and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], dg."role"), 0) >= coalesce(array_position(array['viewer', 'editor', 'owner']::text[], 'viewer'), 0)
    and coalesce(array_position(array['viewer', 'editor', 'owner']::text[], 'viewer'), 0) > 0
    and x."tenant_id" in (select better_supabase.tenant_ids_with('drive.read'))
    and ((dg."principal_type" = 'user' and dg."principal_id" = auth.uid()::text)
      or (dg."principal_type" = 'team' and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = dg."principal_id"::text and tm."user_id" = auth.uid()))
      or (dg."principal_type" = 'role' and exists (select 1 from "public"."memberships" mr where mr."organization_id" = x."tenant_id" and mr."user_id" = auth.uid() and mr."role"::text = dg."principal_id")))
$function$;

CREATE POLICY "bsb_tenant_scope" ON "better_supabase"."drive_nodes"
  AS RESTRICTIVE
  FOR ALL
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((deleted_at IS NULL) AND (id IN ( SELECT
    better_supabase.drive_readable_ids() AS drive_readable_ids)))))
  WITH CHECK ((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)));

CREATE POLICY "drive_nodes_read" ON "better_supabase"."drive_nodes"
  FOR SELECT
  TO "authenticated"
  USING (((deleted_at IS NULL) AND (id IN ( SELECT better_supabase.drive_readable_ids() AS drive_readable_ids))));

REVOKE ALL ON FUNCTION "api"."drive_readable_ids"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_readable_ids"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_readable_ids"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_readable_ids"() TO "authenticated", "service_role";
