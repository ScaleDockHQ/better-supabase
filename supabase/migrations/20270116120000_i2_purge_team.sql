SET local check_function_bodies = off;

drop function if exists "api"."delete_team"(uuid);
drop function if exists "better_supabase"."delete_team"(uuid);

create or replace function "better_supabase"."purge_team"(team uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
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
  perform "better_supabase".emit_event('team.purged', jsonb_build_object('organizationId', v_tenant, 'id', purge_team.team), 'teams/' || (purge_team.team)::text, (v_tenant)::text, null, 'better-supabase/teams');
  perform better_supabase.audit_event(
    event_type => 'team.purged',
    category => 'membership',
    target_type => 'team',
    record_id => (purge_team.team)::text,
    tenant => (v_tenant)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'id', purge_team.team)
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."purge_team"(uuid) from public, anon;
grant execute on function "better_supabase"."purge_team"(uuid) to authenticated, service_role;

create or replace function "api"."purge_team"(team uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purge_team"($1) $$;
revoke execute on function "api"."purge_team"(uuid) from public, anon;
grant execute on function "api"."purge_team"(uuid) to authenticated, service_role;
