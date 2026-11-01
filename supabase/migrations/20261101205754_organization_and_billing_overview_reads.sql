SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.organization_overview (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."organization_overview"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.organization_overview (
  organization uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_org jsonb;
  v_seats integer;
begin
  select to_jsonb(o) into v_org
  from "better_supabase"."list_my_organizations"() o
  where o.id = organization_overview.organization;
  if v_org is null then
    raise exception 'Not a member of this organization' using errcode = '42501', hint = 'ORGANIZATION_FORBIDDEN';
  end if;
  
  return jsonb_build_object(
    'id', v_org ->> 'id',
    'name', v_org ->> 'name',
    'slug', v_org -> 'slug',
    'role', v_org ->> 'role',
    'seats', v_seats,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'userId', m.user_id, 'role', m.role,
        'roles', coalesce(to_jsonb(m) -> 'roles', jsonb_build_array(m.role)),
        'disabledAt', to_jsonb(m) -> 'disabled_at')
        order by m.user_id)
      from "better_supabase"."list_members"(organization_overview.organization) m
    ), '[]'::jsonb),
    'invitations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', i.id, 'email', i.email, 'role', i.role, 'expiresAt', to_jsonb(i) -> 'expires_at')
          order by i.email)
        from "better_supabase"."list_organization_invitations"(organization_overview.organization) i
      ), '[]'::jsonb)
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."organization_overview"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."organization_overview"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."organization_overview"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."organization_overview"(uuid) TO "authenticated", "service_role";
