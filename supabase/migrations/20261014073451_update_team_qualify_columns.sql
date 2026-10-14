SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.update_team (
  team        uuid,
  name        text,
  description text
)
  RETURNS jsonb
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
  select "tenant_id" into v_tenant from "better_supabase"."teams" where "id" = update_team.team;
  if not found then
    raise exception 'team not found' using errcode = 'P0002', hint = 'TEAM_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'teams.manage'), false)) then
    raise exception 'not allowed to manage teams' using errcode = '42501', hint = 'TEAM_FORBIDDEN';
  end if;
  update "better_supabase"."teams" as t
  set "name" = coalesce(update_team.name, t."name"),
      "description" = coalesce(update_team.description, t."description"),
      "updated_at" = now()
  where t."id" = update_team.team;
  perform better_supabase.audit_event(
    event_type => 'team.updated',
    category => 'membership',
    target_type => 'team',
    record_id => (update_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', update_team.team, 'name', update_team.name)
  );
  return jsonb_build_object('id', update_team.team);
end;
$function$;
