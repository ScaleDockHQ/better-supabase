SET local check_function_bodies = off;

DROP FUNCTION "api"."delegate_maintenance_request"(uuid, uuid, jsonb);

DROP FUNCTION "api"."delegate_work_item"(uuid, uuid, jsonb);

DROP FUNCTION "better_supabase"."delegate_maintenance_request"(uuid, uuid, jsonb);

DROP FUNCTION "better_supabase"."delegate_work_item"(uuid, uuid, jsonb);

CREATE OR REPLACE FUNCTION api.delegate_maintenance_request (
  task       uuid,
  to_user    uuid,
  profile    jsonb DEFAULT NULL::jsonb,
  to_profile text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delegate_maintenance_request"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION api.delegate_work_item (
  task       uuid,
  to_user    uuid,
  profile    jsonb DEFAULT NULL::jsonb,
  to_profile text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delegate_work_item"($1, $2, $3, $4) $function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_maintenance_request_close_hook()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_close"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using new."id", case new."close_reason"::text when 'completed' then 'completed' when 'failed' then 'failed' else 'canceled' end, coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note");
    end if;
  end;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_maintenance_request_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."maintenance_requests" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."maintenance_requests" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      new."close_note" := coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note");
      new."held_at" := null;
      new."hold_kind" := null;
      new."hold_return_stage_id" := null;
      delete from "better_supabase"."maintenance_request_claims" c where c."maintenance_request_id" = new."id";
      new."delegate_profile" := null;
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      perform "better_supabase".emit_event('maintenance_request.closed', jsonb_build_object('organizationId', new."tenant_id", 'maintenanceRequestId', new."id", 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason", 'note', coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note"), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/facilities');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      new."close_note" := null;
      perform "better_supabase".emit_event('maintenance_request.reopened', jsonb_build_object('organizationId', new."tenant_id", 'maintenanceRequestId', new."id", 'subjectType', 'maintenance_request', 'subjectId', new."id"::text, 'title', new."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/facilities');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_maintenance_request_reservation()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."maintenance_requests" x set "delegate_profile" = null
    where x."id" = old."maintenance_request_id" and x."delegate_profile" ->> 'userId' = old."user_id"::text;
  return old;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_work_item_close_hook()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_close"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using new."id", case new."close_reason"::text when 'completed' then 'completed' when 'failed' then 'failed' else 'canceled' end, coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note");
    end if;
  end;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_work_item_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."parent_id" is not null and (tg_op = 'INSERT' or new."parent_id" is distinct from old."parent_id") then
    if exists (
      with recursive up(id, depth) as (
        select new."parent_id", 1
        union all
        select x."parent_id", up.depth + 1 from "better_supabase"."work_items" x join up on x."id" = up.id
        where x."parent_id" is not null and up.depth < 100
      )
      select 1 from up where up.id = new."id"
    ) then
      raise exception 'an item can''t sit under itself' using errcode = '23514', hint = 'TASK_PARENT_CYCLE';
    end if;
    if not exists (select 1 from "better_supabase"."work_items" x where x."id" = new."parent_id" and x."tenant_id" = new."tenant_id") then
      raise exception 'the parent is in another organization' using errcode = '22023', hint = 'TASK_PARENT_INVALID';
    end if;
  end if;
  if tg_op = 'UPDATE' and old."locked" and not (auth.role() = 'service_role') and (new."start_at" is distinct from old."start_at" or new."end_at" is distinct from old."end_at" or new."due_at" is distinct from old."due_at") then
    raise exception 'the item is locked; its dates can''t change' using errcode = '55000', hint = 'TASK_LOCKED';
  end if;
  if tg_op = 'INSERT' then
    if new."state" in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
    end if;
    return new;
  end if;
  if new."state" is distinct from old."state" then
    if new."state" in ('completed', 'canceled') and old."state" not in ('completed', 'canceled') then
      new."closed_at" := now();
      new."close_reason" := coalesce(new."close_reason", case new."state" when 'completed' then 'completed' else 'not_planned' end);
      new."close_note" := coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note");
      new."held_at" := null;
      new."hold_kind" := null;
      new."hold_return_stage_id" := null;
      delete from "better_supabase"."work_item_claims" c where c."work_item_id" = new."id";
      new."delegate_profile" := null;
      if new."state" = 'completed' and new."progress" is not null then
        new."progress" := 100;
      end if;
      perform "better_supabase".emit_event('work_item.closed', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'state', new."state", 'closeReason', new."close_reason", 'note', coalesce(nullif(current_setting('bsb.close_note', true), ''), new."close_note"), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif not (new."state" in ('completed', 'canceled')) and old."state" in ('completed', 'canceled') then
      new."closed_at" := null;
      new."close_reason" := null;
      new."close_note" := null;
      perform "better_supabase".emit_event('work_item.reopened', jsonb_build_object('organizationId', new."tenant_id", 'workItemId', new."id", 'subjectType', 'work_item', 'subjectId', new."id"::text, 'title', new."title", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || new."id"::text, (new."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_work_item_reservation()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  update "better_supabase"."work_items" x set "delegate_profile" = null
    where x."id" = old."work_item_id" and x."delegate_profile" ->> 'userId' = old."user_id"::text;
  return old;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_maintenance_request (
  task    uuid,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_claim "better_supabase"."maintenance_request_claims";
  v_actor jsonb := "better_supabase"."maintenance_request_actor"(claim_maintenance_request.profile);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = claim_maintenance_request.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'a closed task can''t be claimed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  if coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) and not exists (select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = auth.uid()) then
    raise exception 'an agent session claims only tasks assigned to its user' using errcode = '42501', hint = 'TASK_NOT_ASSIGNED';
  end if;
  if not (v_row."delegate_profile" is null or (v_row."delegate_profile" ->> 'name' is not distinct from v_actor ->> 'name' and (v_row."delegate_profile" ->> 'userId') is not distinct from auth.uid()::text) or (not coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)))) then
    raise exception 'the task is reserved for another profile' using errcode = '42501', hint = 'TASK_RESERVED';
  end if;
  if v_row."held_at" is not null then
    raise exception 'the task is on hold' using errcode = '55000', hint = 'TASK_HELD';
  end if;
  insert into "better_supabase"."maintenance_request_claims" as c ("maintenance_request_id", "tenant_id", "holder_id", "profile", "expires_at")
  values (v_row."id", v_row."tenant_id", auth.uid(), v_actor, now() + make_interval(secs => least(900, greatest(1, coalesce(claim_maintenance_request.lease, 900)))))
  on conflict ("maintenance_request_id") do update set
    "token" = case when c."expires_at" > now() then c."token" else gen_random_uuid() end,
    "epoch" = case when c."expires_at" > now() then c."epoch" else c."epoch" + 1 end,
    "holder_id" = excluded."holder_id",
    "profile" = excluded."profile",
    "claimed_at" = case when c."expires_at" > now() then c."claimed_at" else now() end,
    "expires_at" = excluded."expires_at",
    "expired_at" = null
  where not c."expires_at" > now()
    or (c."holder_id" is not distinct from excluded."holder_id" and c."profile" ->> 'name' is not distinct from excluded."profile" ->> 'name')
  returning * into v_claim;
  if not found then
    raise exception 'another holder has a live claim on the task' using errcode = '55P03', hint = 'TASK_CLAIMED';
  end if;
  if v_row."delegate_profile" is not null and not (v_row."delegate_profile" ->> 'name' is not distinct from v_actor ->> 'name' and (v_row."delegate_profile" ->> 'userId') is not distinct from auth.uid()::text) then
    update "better_supabase"."maintenance_requests" x set "delegate_profile" = null where x."id" = v_row."id";
  end if;
  perform "better_supabase".emit_event('maintenance_request.claimed', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(claim_maintenance_request.profile) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(claim_maintenance_request.profile) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  return jsonb_build_object('task', (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id"), 'claim', jsonb_build_object('token', v_claim."token", 'epoch', v_claim."epoch", 'holderId', v_claim."holder_id", 'profile', v_claim."profile", 'claimedAt', v_claim."claimed_at", 'expiresAt', v_claim."expires_at"));
end;
$function$;

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
  select x."id" into v_id from "better_supabase"."maintenance_requests" x
  where x."tenant_id" = claim_next_maintenance_request.tenant and x."archived_at" is null and x."closed_at" is null
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
  select x."id" into v_id from "better_supabase"."work_items" x
  where x."tenant_id" = claim_next_work_item.tenant and x."archived_at" is null and x."closed_at" is null
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
  if v_id is null then
    raise exception 'no task is ready to claim' using errcode = 'P0002', hint = 'TASK_NOTHING_READY';
  end if;
  return "better_supabase"."claim_work_item"(v_id, claim_next_work_item.lease, claim_next_work_item.profile);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.claim_work_item (
  task    uuid,
  lease   integer DEFAULT NULL::integer,
  profile jsonb   DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_claim "better_supabase"."work_item_claims";
  v_actor jsonb := "better_supabase"."work_item_actor"(claim_work_item.profile);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = claim_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if v_row."closed_at" is not null then
    raise exception 'a closed task can''t be claimed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  if coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) and not exists (select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = auth.uid()) then
    raise exception 'an agent session claims only tasks assigned to its user' using errcode = '42501', hint = 'TASK_NOT_ASSIGNED';
  end if;
  if not (v_row."delegate_profile" is null or (v_row."delegate_profile" ->> 'name' is not distinct from v_actor ->> 'name' and (v_row."delegate_profile" ->> 'userId') is not distinct from auth.uid()::text) or (not coalesce(auth.jwt() -> 'act' ->> 'kind' = 'agent', false) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)))) then
    raise exception 'the task is reserved for another profile' using errcode = '42501', hint = 'TASK_RESERVED';
  end if;
  if v_row."held_at" is not null then
    raise exception 'the task is on hold' using errcode = '55000', hint = 'TASK_HELD';
  end if;
  insert into "better_supabase"."work_item_claims" as c ("work_item_id", "tenant_id", "holder_id", "profile", "expires_at")
  values (v_row."id", v_row."tenant_id", auth.uid(), v_actor, now() + make_interval(secs => least(900, greatest(1, coalesce(claim_work_item.lease, 900)))))
  on conflict ("work_item_id") do update set
    "token" = case when c."expires_at" > now() then c."token" else gen_random_uuid() end,
    "epoch" = case when c."expires_at" > now() then c."epoch" else c."epoch" + 1 end,
    "holder_id" = excluded."holder_id",
    "profile" = excluded."profile",
    "claimed_at" = case when c."expires_at" > now() then c."claimed_at" else now() end,
    "expires_at" = excluded."expires_at",
    "expired_at" = null
  where not c."expires_at" > now()
    or (c."holder_id" is not distinct from excluded."holder_id" and c."profile" ->> 'name' is not distinct from excluded."profile" ->> 'name')
  returning * into v_claim;
  if not found then
    raise exception 'another holder has a live claim on the task' using errcode = '55P03', hint = 'TASK_CLAIMED';
  end if;
  if v_row."delegate_profile" is not null and not (v_row."delegate_profile" ->> 'name' is not distinct from v_actor ->> 'name' and (v_row."delegate_profile" ->> 'userId') is not distinct from auth.uid()::text) then
    update "better_supabase"."work_items" x set "delegate_profile" = null where x."id" = v_row."id";
  end if;
  perform "better_supabase".emit_event('work_item.claimed', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'holderId', v_claim."holder_id", 'epoch', v_claim."epoch", 'expiresAt', v_claim."expires_at", 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(claim_work_item.profile) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(claim_work_item.profile) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  return jsonb_build_object('task', (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id"), 'claim', jsonb_build_object('token', v_claim."token", 'epoch', v_claim."epoch", 'holderId', v_claim."holder_id", 'profile', v_claim."profile", 'claimedAt', v_claim."claimed_at", 'expiresAt', v_claim."expires_at"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_maintenance_request (
  task    uuid,
  outcome text,
  note    text DEFAULT NULL::text,
  stage   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_stage uuid;
  v_note text := nullif(trim(close_maintenance_request.note), '');
  v_constraint text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if close_maintenance_request.outcome is null or close_maintenance_request.outcome not in ('completed', 'canceled', 'failed', 'open') then
    raise exception 'outcome is completed, canceled, failed or open' using errcode = '22023', hint = 'TASK_OUTCOME_INVALID';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = close_maintenance_request.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if close_maintenance_request.outcome = 'open' and v_row."closed_at" is null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
  end if;
  if close_maintenance_request.outcome <> 'open' and v_row."closed_at" is not null then
    raise exception 'the task is already closed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  v_stage := coalesce(close_maintenance_request.stage, case close_maintenance_request.outcome
    when 'completed' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'completed' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    when 'open' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'unstarted' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    else (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'canceled' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1) end);
  if v_stage is null then
    raise exception 'the task''s pipeline has no stage for this outcome; pass a stage' using errcode = '22023', hint = 'TASK_STAGE_REQUIRED';
  end if;
  perform set_config('bsb.close_note', coalesce(v_note, ''), true);
  perform set_config('bsb.close_by', coalesce(auth.uid()::text, ''), true);
  begin
    if close_maintenance_request.outcome = 'failed' then
      begin
        update "better_supabase"."maintenance_requests" x set "stage_id" = v_stage, "close_reason" = 'failed' where x."id" = v_row."id";
      exception when check_violation or invalid_text_representation then
        update "better_supabase"."maintenance_requests" x set "stage_id" = v_stage where x."id" = v_row."id";
      end;
    else
      update "better_supabase"."maintenance_requests" x set "stage_id" = v_stage where x."id" = v_row."id";
    end if;
  exception when check_violation or foreign_key_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint is null then
      raise;
    end if;
    raise exception 'the stage can''t be used for this task' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  perform set_config('bsb.close_note', '', true);
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_row."id";
  if close_maintenance_request.outcome = 'failed' then
    perform "better_supabase".emit_event('maintenance_request.failed', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'note', v_note, 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.close_work_item (
  task    uuid,
  outcome text,
  note    text DEFAULT NULL::text,
  stage   uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_stage uuid;
  v_note text := nullif(trim(close_work_item.note), '');
  v_constraint text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if close_work_item.outcome is null or close_work_item.outcome not in ('completed', 'canceled', 'failed', 'open') then
    raise exception 'outcome is completed, canceled, failed or open' using errcode = '22023', hint = 'TASK_OUTCOME_INVALID';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = close_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if close_work_item.outcome = 'open' and v_row."closed_at" is null then
    return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
  end if;
  if close_work_item.outcome <> 'open' and v_row."closed_at" is not null then
    raise exception 'the task is already closed' using errcode = '55000', hint = 'TASK_CLOSED';
  end if;
  v_stage := coalesce(close_work_item.stage, case close_work_item.outcome
    when 'completed' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'completed' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    when 'open' then (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'unstarted' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1)
    else (select s."id" from "better_supabase"."pipeline_stages" s where s."pipeline_id" = v_row."pipeline_id" and s."category"::text = 'canceled' and s."archived_at" is null order by s."rank" collate "C", s."id" limit 1) end);
  if v_stage is null then
    raise exception 'the task''s pipeline has no stage for this outcome; pass a stage' using errcode = '22023', hint = 'TASK_STAGE_REQUIRED';
  end if;
  perform set_config('bsb.close_note', coalesce(v_note, ''), true);
  perform set_config('bsb.close_by', coalesce(auth.uid()::text, ''), true);
  begin
    if close_work_item.outcome = 'failed' then
      begin
        update "better_supabase"."work_items" x set "stage_id" = v_stage, "close_reason" = 'failed' where x."id" = v_row."id";
      exception when check_violation or invalid_text_representation then
        update "better_supabase"."work_items" x set "stage_id" = v_stage where x."id" = v_row."id";
      end;
    else
      update "better_supabase"."work_items" x set "stage_id" = v_stage where x."id" = v_row."id";
    end if;
  exception when check_violation or foreign_key_violation then
    get stacked diagnostics v_constraint = constraint_name;
    if v_constraint is null then
      raise;
    end if;
    raise exception 'the stage can''t be used for this task' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  perform set_config('bsb.close_note', '', true);
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_row."id";
  if close_work_item.outcome = 'failed' then
    perform "better_supabase".emit_event('work_item.failed', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'note', v_note, 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delegate_maintenance_request (
  task       uuid,
  to_user    uuid,
  profile    jsonb DEFAULT NULL::jsonb,
  to_profile text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_actor jsonb := "better_supabase"."maintenance_request_actor"(delegate_maintenance_request.profile);
  v_name text := nullif(btrim(delegate_maintenance_request.to_profile), '');
  v_added boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = delegate_maintenance_request.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'facilities.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if delegate_maintenance_request.to_profile is not null and (v_name is null or length(v_name) > 120) then
    raise exception 'to_profile is a name of up to 120 characters' using errcode = '22023', hint = 'TASK_DELEGATE_INVALID';
  end if;
  if not coalesce(better_supabase.can_user(delegate_maintenance_request.to_user, 'tenant', v_row."tenant_id", 'facilities.read'), false) then
    raise exception 'the user can''t read tasks in this organization' using errcode = '22023', hint = 'TASK_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."maintenance_request_assignees" ("tenant_id", "maintenance_request_id", "user_id") values (v_row."tenant_id", v_row."id", delegate_maintenance_request.to_user)
  on conflict do nothing;
  v_added := found;
  delete from "better_supabase"."maintenance_request_claims" c where c."maintenance_request_id" = v_row."id" and c."holder_id" is distinct from delegate_maintenance_request.to_user;
  update "better_supabase"."maintenance_requests" x set "delegate_profile" = case when v_name is null then null else jsonb_build_object('name', v_name, 'userId', delegate_maintenance_request.to_user) end where x."id" = v_row."id";
  perform "better_supabase".emit_event('maintenance_request.delegated', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'delegateId', delegate_maintenance_request.to_user, 'toProfile', v_name, 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(delegate_maintenance_request.profile) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(delegate_maintenance_request.profile) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  if v_added then
    perform "better_supabase".emit_event('maintenance_request.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(array(select y."user_id" from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id")), 'addedIds', jsonb_build_array(delegate_maintenance_request.to_user), 'actorId', auth.uid(), 'actorKind', "better_supabase"."maintenance_request_actor"(null) ->> 'kind', 'actorName', "better_supabase"."maintenance_request_actor"(null) ->> 'name'), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delegate_work_item (
  task       uuid,
  to_user    uuid,
  profile    jsonb DEFAULT NULL::jsonb,
  to_profile text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_actor jsonb := "better_supabase"."work_item_actor"(delegate_work_item.profile);
  v_name text := nullif(btrim(delegate_work_item.to_profile), '');
  v_added boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = delegate_work_item.task and x."archived_at" is null for update;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tasks.write'), false)) then
    raise exception 'not allowed to change this work item' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if delegate_work_item.to_profile is not null and (v_name is null or length(v_name) > 120) then
    raise exception 'to_profile is a name of up to 120 characters' using errcode = '22023', hint = 'TASK_DELEGATE_INVALID';
  end if;
  if not coalesce(better_supabase.can_user(delegate_work_item.to_user, 'tenant', v_row."tenant_id", 'tasks.read'), false) then
    raise exception 'the user can''t read tasks in this organization' using errcode = '22023', hint = 'TASK_DELEGATE_INVALID';
  end if;
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id") values (v_row."tenant_id", v_row."id", delegate_work_item.to_user)
  on conflict do nothing;
  v_added := found;
  delete from "better_supabase"."work_item_claims" c where c."work_item_id" = v_row."id" and c."holder_id" is distinct from delegate_work_item.to_user;
  update "better_supabase"."work_items" x set "delegate_profile" = case when v_name is null then null else jsonb_build_object('name', v_name, 'userId', delegate_work_item.to_user) end where x."id" = v_row."id";
  perform "better_supabase".emit_event('work_item.delegated', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'delegateId', delegate_work_item.to_user, 'toProfile', v_name, 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(delegate_work_item.profile) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(delegate_work_item.profile) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  if v_added then
    perform "better_supabase".emit_event('work_item.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(array(select y."user_id" from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id")), 'addedIds', jsonb_build_array(delegate_work_item.to_user), 'actorId', auth.uid(), 'actorKind', "better_supabase"."work_item_actor"(null) ->> 'kind', 'actorName', "better_supabase"."work_item_actor"(null) ->> 'name'), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_row."id");
end;
$function$;

CREATE TRIGGER bsb_maintenance_request_reservation
  AFTER DELETE ON better_supabase.maintenance_request_assignees
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_maintenance_request_reservation();

CREATE TRIGGER bsb_maintenance_request_close_hook
  AFTER UPDATE ON better_supabase.maintenance_requests
  FOR EACH ROW
  WHEN (((old.closed_at IS NULL) AND (new.closed_at IS NOT NULL)))
  EXECUTE FUNCTION better_supabase.bsb_maintenance_request_close_hook();

CREATE TRIGGER bsb_work_item_reservation
  AFTER DELETE ON better_supabase.work_item_assignees
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.bsb_work_item_reservation();

CREATE TRIGGER bsb_work_item_close_hook
  AFTER UPDATE ON better_supabase.work_items
  FOR EACH ROW
  WHEN (((old.closed_at IS NULL) AND (new.closed_at IS NOT NULL)))
  EXECUTE FUNCTION better_supabase.bsb_work_item_close_hook();

REVOKE ALL ON FUNCTION "api"."delegate_maintenance_request"(uuid, uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delegate_maintenance_request"(uuid, uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delegate_work_item"(uuid, uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delegate_work_item"(uuid, uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."bsb_maintenance_request_close_hook"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_maintenance_request_reservation"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_work_item_close_hook"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."bsb_work_item_reservation"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."delegate_maintenance_request"(uuid, uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delegate_maintenance_request"(uuid, uuid, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delegate_work_item"(uuid, uuid, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delegate_work_item"(uuid, uuid, jsonb, text) TO "authenticated", "service_role";
