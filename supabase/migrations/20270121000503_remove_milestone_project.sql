-- remove_milestone reads the project key it puts on the delete event.
create or replace function "better_supabase"."remove_milestone"(milestone uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."milestones";
  v_project "better_supabase"."work_projects";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  delete from "better_supabase"."milestones" x
  where x."id" = remove_milestone.milestone and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  select * into v_project from "better_supabase"."work_projects" p
  where p."id" = v_row."work_project_id";
  perform "better_supabase".emit_event('work_project_milestone.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workProjectId', v_row."work_project_id", 'milestoneId', v_row."id", 'subjectType', 'project_milestone', 'subjectId', v_row."id"::text, 'key', v_project."key", 'name', v_row."name", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'milestones/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_milestone"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_milestone"(uuid) to authenticated, service_role;
