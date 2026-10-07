SET local check_function_bodies = off;

REVOKE ALL ON TABLE "public"."memberships" FROM "anon";

DROP FUNCTION "public"."my_organizations"();

DROP FUNCTION "public"."organization_invitations"(uuid);

DROP FUNCTION "public"."organization_members"(uuid);

CREATE OR REPLACE FUNCTION better_supabase.app_my_organizations()
  RETURNS TABLE (
    id           uuid,
    name         text,
    slug         text,
    role         text,
    plan         text,
    last_used_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  select o.id, o.name, o.slug, m.role, s.plan_key, m.last_used_at
  from public.memberships m
  join public.organizations o on o.id = m.organization_id
  left join public.subscriptions s on s.organization_id = o.id
  where m.user_id = (select auth.uid())
  order by o.name;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.app_organization_invitations (
  organization uuid
)
  RETURNS TABLE (
    id         uuid,
    email      text,
    role       text,
    invited_by text,
    created_at timestamp with time zone,
    expires_at timestamp with time zone
  )
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.invite') then
    raise exception 'Not allowed to list invitations' using errcode = '42501';
  end if;
  return query
  select i.id, i.email, i.role, coalesce(p.full_name, p.email), i.created_at, i.expires_at
  from better_supabase.invitations i
  left join better_supabase.profiles p on p.id = i.invited_by
  where i.organization_id = organization
    and i.accepted_at is null and i.declined_at is null and i.revoked_at is null
    and i.expires_at >= now()
  order by i.created_at desc;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.app_organization_members (
  organization uuid
)
  RETURNS TABLE (
    user_id    uuid,
    role       text,
    full_name  text,
    email      text,
    avatar_url text,
    joined_at  timestamp with time zone
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
  select m.user_id, m.role, p.full_name, coalesce(p.email, u.email::text), p.avatar_url, m.created_at
  from public.memberships m
  join auth.users u on u.id = m.user_id
  left join better_supabase.profiles p on p.id = m.user_id
  where m.organization_id = organization
  order by better_supabase.role_rank(m.role) desc, coalesce(p.full_name, u.email::text);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.my_profile()
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select to_jsonb(p) from "better_supabase"."profiles" p where p."id" = (select auth.uid())
$function$;

CREATE OR REPLACE FUNCTION public.my_organizations()
  RETURNS TABLE (
    id           uuid,
    name         text,
    slug         text,
    role         text,
    plan         text,
    last_used_at timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select * from better_supabase.app_my_organizations()
$function$;

REVOKE ALL ON FUNCTION "public"."my_organizations"() FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.organization_invitations (
  organization uuid
)
  RETURNS TABLE (
    id         uuid,
    email      text,
    role       text,
    invited_by text,
    created_at timestamp with time zone,
    expires_at timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select * from better_supabase.app_organization_invitations(organization)
$function$;

REVOKE ALL ON FUNCTION "public"."organization_invitations"(uuid) FROM PUBLIC, "anon";

CREATE OR REPLACE FUNCTION public.organization_members (
  organization uuid
)
  RETURNS TABLE (
    user_id    uuid,
    role       text,
    full_name  text,
    email      text,
    avatar_url text,
    joined_at  timestamp with time zone
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select * from better_supabase.app_organization_members(organization)
$function$;

REVOKE ALL ON FUNCTION "public"."organization_members"(uuid) FROM PUBLIC, "anon";

REVOKE ALL ON FUNCTION "better_supabase"."app_my_organizations"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."app_my_organizations"() TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."app_organization_invitations"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."app_organization_invitations"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."app_organization_members"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."app_organization_members"(uuid) TO "authenticated", "service_role";

GRANT EXECUTE ON FUNCTION "public"."my_organizations"() TO "authenticated";

REVOKE ALL ON FUNCTION "public"."my_organizations"() FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_organizations"() TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."my_organizations"() TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."organization_invitations"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."organization_invitations"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_invitations"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_invitations"(uuid) TO "service_role";

GRANT EXECUTE ON FUNCTION "public"."organization_members"(uuid) TO "authenticated";

REVOKE ALL ON FUNCTION "public"."organization_members"(uuid) FROM "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_members"(uuid) TO "postgres";

GRANT EXECUTE ON FUNCTION "public"."organization_members"(uuid) TO "service_role";

REVOKE ALL ON TABLE "public"."memberships" FROM "authenticated";

GRANT SELECT ON TABLE "public"."memberships" TO "authenticated";
