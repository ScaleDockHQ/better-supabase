SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."profiles"
  ADD COLUMN "avatar_path" text;

CREATE OR REPLACE FUNCTION api.list_members (
  organization uuid
)
  RETURNS TABLE (
    user_id uuid,
    role    text
  )
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."list_members"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_my_organizations()
  RETURNS TABLE (
    id   uuid,
    name text,
    slug text,
    role text
  )
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."list_my_organizations"() $function$;

CREATE OR REPLACE FUNCTION api.list_organization_invitations (
  organization uuid
)
  RETURNS TABLE (
    id         uuid,
    email      text,
    role       text,
    expires_at timestamp with time zone
  )
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."list_organization_invitations"($1) $function$;

CREATE OR REPLACE FUNCTION api.my_profile()
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."my_profile"() $function$;

CREATE OR REPLACE FUNCTION api.update_my_profile (
  attrs jsonb
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."update_my_profile"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.list_members (
  organization uuid
)
  RETURNS TABLE (
    user_id uuid,
    role    text
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'members.read'), false) then
    raise exception 'Not allowed to list members' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select m."user_id", m."role"::text
  from "public"."memberships" m
  where m."organization_id" = organization
  order by m."user_id";
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_my_organizations()
  RETURNS TABLE (
    id   uuid,
    name text,
    slug text,
    role text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select o."id", o."name", o."slug", m."role"::text
  from "public"."memberships" m
  join "public"."organizations" o on o."id" = m."organization_id"
  where m."user_id" = (select auth.uid())
    and not better_supabase.tenant_disabled(o."id")
  order by o."name"
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_organization_invitations (
  organization uuid
)
  RETURNS TABLE (
    id         uuid,
    email      text,
    role       text,
    expires_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not coalesce(better_supabase.member_can((select auth.uid()), organization, 'members.invite'), false) then
    raise exception 'Not allowed to list invitations' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  return query
  select i."id", i."email", i."role"::text, i."expires_at"
  from "better_supabase"."invitations" i
  where i."organization_id" = organization and i."accepted_at" is null and i."declined_at" is null and i."revoked_at" is null and i."expires_at" >= now()
  order by i."expires_at" desc;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_profile()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select to_jsonb(p) from "better_supabase"."profiles" p where p."id" = (select auth.uid())
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_my_profile (
  attrs jsonb
)
  RETURNS boolean
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  updated integer;
begin
  update "better_supabase"."profiles" p
  set "full_name" = case when update_my_profile.attrs ? 'full_name' then update_my_profile.attrs ->> 'full_name' else p."full_name" end,
    "first_name" = case when update_my_profile.attrs ? 'first_name' then update_my_profile.attrs ->> 'first_name' else p."first_name" end,
    "last_name" = case when update_my_profile.attrs ? 'last_name' then update_my_profile.attrs ->> 'last_name' else p."last_name" end,
    "avatar_url" = case when update_my_profile.attrs ? 'avatar_url' then update_my_profile.attrs ->> 'avatar_url' else p."avatar_url" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs ->> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = (select auth.uid());
  get diagnostics updated = row_count;
  return updated > 0;
end;
$function$;

REVOKE ALL ON FUNCTION "api"."list_members"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_members"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_my_organizations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_my_organizations"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_organization_invitations"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_organization_invitations"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."my_profile"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."my_profile"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."update_my_profile"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."update_my_profile"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_members"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_members"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_my_organizations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_my_organizations"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_organization_invitations"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_organization_invitations"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."my_profile"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."my_profile"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."update_my_profile"(jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."update_my_profile"(jsonb) TO "authenticated", "service_role";

REVOKE ALL ("avatar_path") ON TABLE "better_supabase"."profiles" FROM "authenticated";

GRANT UPDATE ("avatar_path") ON TABLE "better_supabase"."profiles" TO "authenticated";
