SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.clone_maintenance_request (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."maintenance_requests"%rowtype;
  v_id uuid;
  v_created jsonb;
  v_child uuid;
  v_copy jsonb;
  v_users uuid[];
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."maintenance_requests" x where x."id" = clone_maintenance_request.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_tenant := coalesce(nullif(coalesce(clone_maintenance_request.overrides, '{}'::jsonb) ->> 'tenantId', '')::uuid, v_src."tenant_id");
  if v_tenant is distinct from v_src."tenant_id" and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'facilities.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_maintenance_request.source, clone_maintenance_request.overrides;
    end if;
  end;
  select coalesce(array_agg(ra."user_id"), '{}') into v_users from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = v_src."id";
  v_created := "better_supabase"."create_maintenance_request"(v_tenant, jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title",
    'body', v_src."body",
    'parentId', v_src."parent_id",
    'teamId', v_src."team_id",
    'dueAt', v_src."due_at",
    'priority', v_src."priority",
    'templateId', null,
    'sourceTemplateId', null
  )) || (coalesce(clone_maintenance_request.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), v_users);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."maintenance_request_checklist_items" ("tenant_id", "maintenance_request_id", "title", "done", "rank")
  select v_tenant, v_id, c."title", false, c."rank"
  from "better_supabase"."maintenance_request_checklist_items" c where c."maintenance_request_id" = clone_maintenance_request.source;
  insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
  select v_tenant, g."tag_id", g."subject_type", v_id::text
  from "better_supabase"."taggings" g
  where g."subject_type" = 'maintenance_request' and g."subject_id" = clone_maintenance_request.source::text;
  for v_child in select c."id" from "better_supabase"."maintenance_requests" c where c."parent_id" = clone_maintenance_request.source loop
    v_copy := "better_supabase"."clone_maintenance_request"(v_child, coalesce(clone_maintenance_request.overrides, '{}'::jsonb) - 'templateId' - 'parentId');
    update "better_supabase"."maintenance_requests" x set "parent_id" = v_id where x."id" = (v_copy ->> 'id')::uuid;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_request_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."maintenance_request_claim"(x."id")) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.clone_work_item (
  source    uuid,
  overrides jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_src "better_supabase"."work_items"%rowtype;
  v_id uuid;
  v_created jsonb;
  v_child uuid;
  v_copy jsonb;
  v_users uuid[];
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."work_items" x where x."id" = clone_work_item.source;
  if not found then
    raise exception 'no such work item' using errcode = 'P0002', hint = 'TASK_NOT_FOUND';
  end if;
  v_tenant := coalesce(nullif(coalesce(clone_work_item.overrides, '{}'::jsonb) ->> 'tenantId', '')::uuid, v_src."tenant_id");
  if v_tenant is distinct from v_src."tenant_id" and not ((auth.role() = 'service_role') or false) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_clone"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using clone_work_item.source, clone_work_item.overrides;
    end if;
  end;
  select coalesce(array_agg(ra."user_id"), '{}') into v_users from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = v_src."id";
  v_created := "better_supabase"."create_work_item"(v_tenant, jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title",
    'body', v_src."body",
    'parentId', v_src."parent_id",
    'teamId', v_src."team_id",
    'dueAt', v_src."due_at",
    'priority', v_src."priority",
    'templateId', null,
    'sourceTemplateId', null
  )) || (coalesce(clone_work_item.overrides, '{}'::jsonb) - 'templateId') || jsonb_strip_nulls(jsonb_build_object('templateId', null, 'sourceTemplateId', null)), v_users);
  v_id := (v_created ->> 'id')::uuid;
  insert into "better_supabase"."work_item_checklist_items" ("tenant_id", "work_item_id", "title", "done", "rank")
  select v_tenant, v_id, c."title", false, c."rank"
  from "better_supabase"."work_item_checklist_items" c where c."work_item_id" = clone_work_item.source;
  insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
  select v_tenant, g."tag_id", g."subject_type", v_id::text
  from "better_supabase"."taggings" g
  where g."subject_type" = 'work_item' and g."subject_id" = clone_work_item.source::text;
  for v_child in select c."id" from "better_supabase"."work_items" c where c."parent_id" = clone_work_item.source loop
    v_copy := "better_supabase"."clone_work_item"(v_child, coalesce(clone_work_item.overrides, '{}'::jsonb) - 'templateId' - 'parentId');
    update "better_supabase"."work_items" x set "parent_id" = v_id where x."id" = (v_copy ->> 'id')::uuid;
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_clone"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) || jsonb_build_object('claim', "better_supabase"."work_item_claim"(x."id")) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$function$;
