SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."delete_team"(uuid);

CREATE OR REPLACE FUNCTION better_supabase.purge_team (
  team uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = purge_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  delete from "better_supabase"."teams" where "id" = purge_team.team;
  null;
  return true;
end;
$function$;

REVOKE ALL ON FUNCTION "better_supabase"."purge_team"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_team"(uuid) TO "authenticated", "service_role";
