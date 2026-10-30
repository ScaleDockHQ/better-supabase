SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.set_maintenance_request_assignees (
  work_item uuid,
  users     uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_maintenance_request_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = set_maintenance_request_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'maintenance_requests.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."maintenance_request_assignees" y where y."maintenance_request_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."maintenance_request_assignees" ("tenant_id", "maintenance_request_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'maintenance_request', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'maintenance_request.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'maintenance_request',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'maintenance_request.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('maintenanceRequestId', v_row."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('maintenance_request.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  end if;
  return cardinality(v_users);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_work_item_assignees (
  work_item uuid,
  users     uuid[]
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_users uuid[] := array(select distinct x from unnest(coalesce(set_work_item_assignees.users, '{}')) x where x is not null);
  v_added uuid[];
  v_new uuid[];
  v_claims text;
  v_user uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = set_work_item_assignees.work_item and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.write'), false));
  if v_row."id" is null then
    raise exception 'no such work item you can edit' using errcode = 'P0002', hint = 'WORK_ITEM_NOT_FOUND';
  end if;
  v_new := array(select x from unnest(v_users) x where x is distinct from auth.uid() and not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  v_added := array(select x from unnest(v_users) x where not exists (
    select 1 from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and y."user_id" = x));
  delete from "better_supabase"."work_item_assignees" y where y."work_item_id" = v_row."id" and not (y."user_id" = any (v_users));
  insert into "better_supabase"."work_item_assignees" ("tenant_id", "work_item_id", "user_id")
  select v_row."tenant_id", v_row."id", x from unnest(v_users) x
  on conflict do nothing;
  foreach v_user in array v_users loop
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
    values (v_row."tenant_id", v_user, 'work_item', v_row."id"::text, 'participating')
    on conflict do nothing;
  end loop;
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'work_item.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'work_item',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."title",
      'summary', v_row."title",
      'action_path', null,
      'recipients', to_jsonb(v_new),
      'watchers', false,
      'key', 'work_item.assigned:' || v_row."id"::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('workItemId', v_row."id")
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
  if cardinality(v_added) > 0 then
    perform "better_supabase".emit_event('work_item.assigned', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title", 'assigneeIds', to_jsonb(v_users), 'addedIds', to_jsonb(v_added)), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return cardinality(v_users);
end;
$function$;
