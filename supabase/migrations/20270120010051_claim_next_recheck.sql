SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.claim_next_maintenance_request (
  tenant  uuid,
  filter  jsonb   DEFAULT NULL::jsonb,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_lost uuid[] := '{}';
  v_name text := "better_supabase"."maintenance_request_actor"(claim_next_maintenance_request.profile) ->> 'name';
  v_writer boolean := (auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', claim_next_maintenance_request.tenant, 'facilities.write'), false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;

  if (coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) or auth.uid() is not null) then
    if claim_next_maintenance_request.filter ->> 'assigneeId' is not null and (claim_next_maintenance_request.filter ->> 'assigneeId')::uuid is distinct from auth.uid() then
      raise exception 'this session picks only its own tasks' using errcode = '42501', hint = 'TASK_FILTER_FORBIDDEN';
    end if;
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', claim_next_maintenance_request.tenant, 'facilities.write'), false)) then
    raise exception 'not allowed to claim work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  -- A claim committed after this statement's snapshot is invisible to it, so
  -- a row picked here can already be taken. Check again and pick another.
  loop
    select x."id" into v_id from "better_supabase"."maintenance_requests" x
    where x."id" <> all (v_lost) and x."tenant_id" = claim_next_maintenance_request.tenant and x."archived_at" is null and x."closed_at" is null
      and x."held_at" is null
      and (not (coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) or auth.uid() is not null) or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and y."user_id" = auth.uid()))
      and (x."delegate_profile" is null or (x."delegate_profile" ->> 'name' is not distinct from v_name and (x."delegate_profile" ->> 'userId') is not distinct from auth.uid()::text) or (not coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) and v_writer))
      and not exists (select 1 from "better_supabase"."maintenance_request_claims" c where c."maintenance_request_id" = x."id" and c."expires_at" > now())
      and (claim_next_maintenance_request.filter ->> 'teamId' is null or x."team_id" = (claim_next_maintenance_request.filter ->> 'teamId')::uuid)
      and (claim_next_maintenance_request.filter ->> 'projectId' is null or x."project_id" = (claim_next_maintenance_request.filter ->> 'projectId')::uuid)
      and (claim_next_maintenance_request.filter ->> 'parentId' is null or x."parent_id" = (claim_next_maintenance_request.filter ->> 'parentId')::uuid)
      and (claim_next_maintenance_request.filter ->> 'stageId' is null or x."stage_id" = (claim_next_maintenance_request.filter ->> 'stageId')::uuid)
      and (claim_next_maintenance_request.filter ->> 'delegateProfile' is null or x."delegate_profile" ->> 'name' = claim_next_maintenance_request.filter ->> 'delegateProfile')
      and (claim_next_maintenance_request.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and y."user_id" = (claim_next_maintenance_request.filter ->> 'assigneeId')::uuid))
    order by (case when exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = x."id" and y."user_id" = auth.uid()) then 0 else 1 end), x."number"
    limit 1
    for update of x skip locked;
    exit when v_id is null or not exists (select 1 from "better_supabase"."maintenance_request_claims" c where c."maintenance_request_id" = v_id and c."expires_at" > now());
    v_lost := v_lost || v_id;
  end loop;
  if v_id is null then
    raise exception 'no task is ready to claim' using errcode = 'P0002', hint = 'TASK_NOTHING_READY';
  end if;
  return "better_supabase"."claim_maintenance_request"(v_id, claim_next_maintenance_request.lease, claim_next_maintenance_request.profile);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_next_work_item (
  tenant  uuid,
  filter  jsonb   DEFAULT NULL::jsonb,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_lost uuid[] := '{}';
  v_name text := "better_supabase"."work_item_actor"(claim_next_work_item.profile) ->> 'name';
  v_writer boolean := (auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', claim_next_work_item.tenant, 'tasks.write'), false);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;

  if (coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) or auth.uid() is not null) then
    if claim_next_work_item.filter ->> 'assigneeId' is not null and (claim_next_work_item.filter ->> 'assigneeId')::uuid is distinct from auth.uid() then
      raise exception 'this session picks only its own tasks' using errcode = '42501', hint = 'TASK_FILTER_FORBIDDEN';
    end if;
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', claim_next_work_item.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to claim work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  -- A claim committed after this statement's snapshot is invisible to it, so
  -- a row picked here can already be taken. Check again and pick another.
  loop
    select x."id" into v_id from "better_supabase"."work_items" x
    where x."id" <> all (v_lost) and x."tenant_id" = claim_next_work_item.tenant and x."archived_at" is null and x."closed_at" is null
      and x."held_at" is null
      and (not (coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) or auth.uid() is not null) or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = auth.uid()))
      and (x."delegate_profile" is null or (x."delegate_profile" ->> 'name' is not distinct from v_name and (x."delegate_profile" ->> 'userId') is not distinct from auth.uid()::text) or (not coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) and v_writer))
      and not exists (select 1 from "better_supabase"."work_item_claims" c where c."work_item_id" = x."id" and c."expires_at" > now())
      and (claim_next_work_item.filter ->> 'teamId' is null or x."team_id" = (claim_next_work_item.filter ->> 'teamId')::uuid)
      and (claim_next_work_item.filter ->> 'projectId' is null or x."project_id" = (claim_next_work_item.filter ->> 'projectId')::uuid)
      and (claim_next_work_item.filter ->> 'parentId' is null or x."parent_id" = (claim_next_work_item.filter ->> 'parentId')::uuid)
      and (claim_next_work_item.filter ->> 'stageId' is null or x."stage_id" = (claim_next_work_item.filter ->> 'stageId')::uuid)
      and (claim_next_work_item.filter ->> 'delegateProfile' is null or x."delegate_profile" ->> 'name' = claim_next_work_item.filter ->> 'delegateProfile')
      and (claim_next_work_item.filter ->> 'assigneeId' is null or exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = (claim_next_work_item.filter ->> 'assigneeId')::uuid))
    order by (case when exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = x."id" and y."user_id" = auth.uid()) then 0 else 1 end), x."number"
    limit 1
    for update of x skip locked;
    exit when v_id is null or not exists (select 1 from "better_supabase"."work_item_claims" c where c."work_item_id" = v_id and c."expires_at" > now());
    v_lost := v_lost || v_id;
  end loop;
  if v_id is null then
    raise exception 'no task is ready to claim' using errcode = 'P0002', hint = 'TASK_NOTHING_READY';
  end if;
  return "better_supabase"."claim_work_item"(v_id, claim_next_work_item.lease, claim_next_work_item.profile);
end;
$function$;
