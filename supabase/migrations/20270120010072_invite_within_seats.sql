SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.invite_within_seats (
  tenant        uuid,
  invitee_email text,
  invitee_role  text,
  valid_for     interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."invite_within_seats"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.invite_within_seats (
  tenant        uuid,
  invitee_email text,
  invitee_role  text,
  valid_for     interval DEFAULT '7 days'::interval
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  used integer;
  cap jsonb;
begin
  if not service and not coalesce(better_supabase.member_can(auth.uid(), tenant, 'members.invite'), false) then
    raise exception 'Not allowed to invite members' using errcode = '42501', hint = 'INVITATION_FORBIDDEN';
  end if;
  cap := better_supabase.tenant_entitlement_value(tenant, 'seats');
  select count(*) into used from "public"."memberships" m where m."organization_id" = tenant;
  if cap is not null and jsonb_typeof(cap) = 'number' and used >= (cap #>> '{}')::numeric then
    raise exception 'The plan has no seat left' using errcode = '22023', hint = 'INVITATION_NO_SEAT';
  end if;
  return "better_supabase"."invite_member"(tenant, invitee_email, invitee_role, valid_for);
end;
$function$;

REVOKE ALL ON FUNCTION "api"."invite_within_seats"(uuid, text, text, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."invite_within_seats"(uuid, text, text, interval) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."invite_within_seats"(uuid, text, text, interval) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."invite_within_seats"(uuid, text, text, interval) TO "authenticated", "service_role";
