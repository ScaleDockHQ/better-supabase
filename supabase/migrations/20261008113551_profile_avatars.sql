SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."app_organization_members"(uuid);

DROP FUNCTION "public"."my_profile"();

DROP FUNCTION "public"."organization_members"(uuid);

CREATE OR REPLACE FUNCTION better_supabase.app_organization_members (
  organization uuid
)
  RETURNS TABLE (
    user_id     uuid,
    role        text,
    full_name   text,
    email       text,
    avatar_url  text,
    avatar_path text,
    joined_at   timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.read') then
    raise exception 'Not allowed to list members' using errcode = '42501';
  end if;
  return query
  select m.user_id, m.role, p.full_name, coalesce(p.email, u.email::text), p.avatar_url, p.avatar_path, m.created_at
  from public.memberships m
  join auth.users u on u.id = m.user_id
  left join better_supabase.profiles p on p.id = m.user_id
  where m.organization_id = organization
  order by better_supabase.role_rank(m.role) desc, coalesce(p.full_name, u.email::text);
end;
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
    "avatar_path" = case when update_my_profile.attrs ? 'avatar_path' then update_my_profile.attrs ->> 'avatar_path' else p."avatar_path" end,
    "username" = case when update_my_profile.attrs ? 'username' then update_my_profile.attrs ->> 'username' else p."username" end,
    "onboarding" = case when update_my_profile.attrs ? 'onboarding' then update_my_profile.attrs -> 'onboarding' else p."onboarding" end,
    "updated_at" = now()
  where p."id" = (select auth.uid());
  get diagnostics updated = row_count;
  return updated > 0;
end;
$function$;

CREATE OR REPLACE FUNCTION public.my_profile()
  RETURNS TABLE (
    full_name   text,
    email       text,
    username    text,
    avatar_url  text,
    avatar_path text
  )
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return query
  select p.full_name, p.email, p.username, p.avatar_url, p.avatar_path
  from better_supabase.profiles p
  where p.id = (select auth.uid());
end;
$function$;

REVOKE ALL ON FUNCTION "public"."my_profile"() FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.organization_members (
  organization uuid
)
  RETURNS TABLE (
    user_id     uuid,
    role        text,
    full_name   text,
    email       text,
    avatar_url  text,
    avatar_path text,
    joined_at   timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select * from better_supabase.app_organization_members(organization)
$function$;

REVOKE ALL ON FUNCTION "public"."organization_members"(uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.set_my_avatar_path (
  avatar_path text
)
  RETURNS void
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
begin
  if set_my_avatar_path.avatar_path is not null
    and split_part(set_my_avatar_path.avatar_path, '/', 1) <> (select auth.uid())::text then
    raise exception 'The avatar must be in your own folder' using errcode = '42501', hint = 'AVATAR_PATH_FORBIDDEN';
  end if;
  update better_supabase.profiles p
  set avatar_path = set_my_avatar_path.avatar_path, updated_at = now()
  where p.id = (select auth.uid());
end;
$function$;

REVOKE ALL ON FUNCTION "public"."set_my_avatar_path"(text) FROM PUBLIC, "anon";

CREATE POLICY "bs_avatars_delete" ON "storage"."objects"
  FOR DELETE
  TO "authenticated"
  USING
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text)));

CREATE POLICY "bs_avatars_insert" ON "storage"."objects"
  FOR INSERT
  TO "authenticated"
  WITH
    CHECK
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text) AND (name ~ '^[^/]+/avatar-[^/]+\.[^/]+$'::text)));

CREATE POLICY "bs_avatars_select" ON "storage"."objects"
  FOR SELECT
  TO "authenticated"
  USING
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text)));

CREATE POLICY "bs_avatars_update" ON "storage"."objects"
  FOR UPDATE
  TO "authenticated"
  USING
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text)))
  WITH
    CHECK
    (((bucket_id = 'avatars'::text) AND ((name COLLATE "C") >= ((( SELECT auth.uid() AS uid))::text || '/'::text)) AND ((name COLLATE "C") < ((( SELECT auth.uid() AS uid))::text ||
    '0'::text)) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text) AND (name ~ '^[^/]+/avatar-[^/]+\.[^/]+$'::text)));

REVOKE ALL ON FUNCTION "better_supabase"."app_organization_members"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."app_organization_members"(uuid) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "public"."my_profile"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."my_profile"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_profile"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_profile"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."organization_members"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."organization_members"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_members"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_members"(uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."set_my_avatar_path"(text) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."set_my_avatar_path"(text) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_my_avatar_path"(text) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."set_my_avatar_path"(text) TO "service_role";
