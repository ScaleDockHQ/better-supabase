SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.archive_collection (
  collection uuid,
  archived   boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."subject_collections";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  
  select * into v_row from "better_supabase"."subject_collections" where "id" = archive_collection.collection for update;
  if not found or not (auth.role() = 'service_role' or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.read'), false) and (
      (v_row."scope" = 'user' and coalesce(v_row."owner_id" = auth.uid(), false))
      or (v_row."scope" = 'team' and v_row."team_id" in (select t::text from "better_supabase"."team_ids_of"((select auth.uid())) t))
      or v_row."scope" = 'tenant'))) then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role'
    or (v_row."scope" = 'user' and coalesce(v_row."owner_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.write'), false))
    or (v_row."scope" <> 'user' and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'collections.share'), false))) then
    raise exception 'not allowed to change this collection' using errcode = '42501', hint = 'COLLECTION_FORBIDDEN';
  end if;
  update "better_supabase"."subject_collections" x set
    "archived_at" = case when coalesce(archive_collection.archived, true) then coalesce(x."archived_at", now()) end,
    "updated_at" = now()
  where x."id" = v_row."id";
  if coalesce(archive_collection.archived, true) and v_row."archived_at" is null then
    perform "better_supabase".emit_event('collection.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'collectionId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'collections/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/collections');
  elsif not coalesce(archive_collection.archived, true) and v_row."archived_at" is not null then
    perform "better_supabase".emit_event('collection.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'collectionId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'collections/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/collections');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_conversation (
  conversation uuid,
  archived     boolean DEFAULT true
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_conv "better_supabase"."conversations";
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_conv from "better_supabase"."conversations" c where c."id" = archive_conversation.conversation;
  v_was := v_conv."archived_at";
  if not found or not "better_supabase"."can_conversation"(v_conv."id", 'read') then
    raise exception 'no such conversation you can read' using errcode = 'P0002', hint = 'MESSAGING_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    or "better_supabase"."can_conversation"(v_conv."id", 'moderate')
    or coalesce(v_conv."created_by" = auth.uid(), false)
    or exists (select 1 from "better_supabase"."conversation_members" k where k."conversation_id" = v_conv."id" and k."user_id" = auth.uid() and k."role" = 'owner')) then
    raise exception 'not allowed to archive this conversation' using errcode = '42501', hint = 'MESSAGING_FORBIDDEN';
  end if;
  update "better_supabase"."conversations" c
  set "archived_at" = case when archive_conversation.archived then coalesce(c."archived_at", now()) end, "updated_at" = now()
  where c."id" = v_conv."id"
  returning * into v_conv;
  if archive_conversation.archived then
    perform "better_supabase".emit_event('conversation.archived', jsonb_build_object('organizationId', v_conv."tenant_id"::text, 'conversationId', v_conv."id", 'kind', v_conv."kind", 'subjectType', 'conversation', 'subjectId', v_conv."id"::text), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id"::text)::text, null, 'better-supabase/messaging');
  elsif v_was is not null then
    perform "better_supabase".emit_event('conversation.restored', jsonb_build_object('organizationId', v_conv."tenant_id"::text, 'conversationId', v_conv."id", 'kind', v_conv."kind", 'subjectType', 'conversation', 'subjectId', v_conv."id"::text), 'conversations/' || v_conv."id"::text, (v_conv."tenant_id"::text)::text, null, 'better-supabase/messaging');
  end if;
  return archive_conversation.archived;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_deal (
  deal     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."deals";
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."archived_at" into v_was from "better_supabase"."deals" x where x."id" = archive_deal.deal;
  update "better_supabase"."deals" x set "archived_at" = case when archive_deal.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_deal.deal and ((auth.role() = 'service_role') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.write'), false) and (true or coalesce(x."owner_id" = auth.uid(), false)
      or coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.manage'), false)
      or exists (select 1 from "better_supabase"."deal_members" mm where mm."deal_id" = x."id" and mm."user_id" = auth.uid()))))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_deal.archived then
    perform "better_supabase".emit_event('deal.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name"), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
  elsif v_was is not null then
    perform "better_supabase".emit_event('deal.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'dealId', v_row."id", 'subjectType', 'deal', 'subjectId', v_row."id"::text, 'name', v_row."name"), 'deals/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/deals');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_maintenance_request (
  task     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."archived_at" into v_was from "better_supabase"."maintenance_requests" x where x."id" = archive_maintenance_request.task;
  update "better_supabase"."maintenance_requests" x set "archived_at" = case when archive_maintenance_request.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_maintenance_request.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_maintenance_request.archived then
    perform "better_supabase".emit_event('maintenance_request.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  elsif v_was is not null then
    perform "better_supabase".emit_event('maintenance_request.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_maintenance_requests (
  ids      uuid[],
  archived boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_ids uuid[] := '{}';
  v_was uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select coalesce(array_agg(x."id"), '{}') into v_was from "better_supabase"."maintenance_requests" x
  where x."id" = any (coalesce(archive_maintenance_requests.ids, '{}')) and x."archived_at" is not null;
  for v_row in
    with changed as (
      update "better_supabase"."maintenance_requests" x set "archived_at" = case when archive_maintenance_requests.archived then coalesce(x."archived_at", now()) end
      where x."id" = any (coalesce(archive_maintenance_requests.ids, '{}')) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.write'), false))
      returning x.*
    )
    select * from changed
  loop
    v_ids := array_append(v_ids, v_row."id");
    if archive_maintenance_requests.archived then
      perform "better_supabase".emit_event('maintenance_request.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
    elsif v_row."id" = any (v_was) then
      perform "better_supabase".emit_event('maintenance_request.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance_requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_maintenance_requests.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_work_item (
  task     uuid,
  archived boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_was timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."archived_at" into v_was from "better_supabase"."work_items" x where x."id" = archive_work_item.task;
  update "better_supabase"."work_items" x set "archived_at" = case when archive_work_item.archived then coalesce(x."archived_at", now()) end
  where x."id" = archive_work_item.task and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
  returning * into v_row;
  if v_row."id" is null then
    return false;
  end if;
  if archive_work_item.archived then
    perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  elsif v_was is not null then
    perform "better_supabase".emit_event('work_item.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end if;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_work_items (
  ids      uuid[],
  archived boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_ids uuid[] := '{}';
  v_was uuid[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select coalesce(array_agg(x."id"), '{}') into v_was from "better_supabase"."work_items" x
  where x."id" = any (coalesce(archive_work_items.ids, '{}')) and x."archived_at" is not null;
  for v_row in
    with changed as (
      update "better_supabase"."work_items" x set "archived_at" = case when archive_work_items.archived then coalesce(x."archived_at", now()) end
      where x."id" = any (coalesce(archive_work_items.ids, '{}')) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.write'), false))
      returning x.*
    )
    select * from changed
  loop
    v_ids := array_append(v_ids, v_row."id");
    if archive_work_items.archived then
      perform "better_supabase".emit_event('work_item.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    elsif v_row."id" = any (v_was) then
      perform "better_supabase".emit_event('work_item.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work_items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_work_items.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;
