SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."approval_eligible_ids"(uuid);

CREATE OR REPLACE FUNCTION api.archive_maintenance_requests (
  ids      uuid[],
  archived boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_maintenance_requests"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.archive_work_items (
  ids      uuid[],
  archived boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_work_items"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.delete_maintenance_requests (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_maintenance_requests"($1) $function$;

CREATE OR REPLACE FUNCTION api.delete_work_items (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."delete_work_items"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_eligible_ids (
  tenant uuid DEFAULT NULL::uuid
)
  RETURNS SETOF uuid
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return query
  with base as (
    select r.*, (select auth.uid()) as bsb_me from "better_supabase"."approval_requests" r
    where r."status" = 'pending' and (select auth.uid()) is not null
      and (approval_eligible_ids.tenant is null or r."tenant_id" = approval_eligible_ids.tenant)
  ),
  q as (
    select b.*, b."policy" -> 'steps' -> b."step" as bsb_step from base b
  ),
  needs as materialized (
    select distinct q."tenant_id" as t, s.ap ->> 'permission' as p
    from q, lateral (values ((q.bsb_step -> 'approvers'), (case when coalesce((q.bsb_step ->> 'escalated')::boolean, false) then (q.bsb_step -> 'escalateTo') end))) as s(ap)
    where s.ap ->> 'permission' is not null
  ),
  granted as materialized (
    select n.t, n.p from needs n
    where coalesce(better_supabase.can('tenant', n.t, n.p), false)
  )
  select q."id" from q
  where not exists (select 1 from "better_supabase"."approval_decisions" x where x."request_id" = q."id" and x."step" = q."step" and x."approver" = q.bsb_me)
    and ((q.bsb_me = q."requested_by" and q."policy" ->> 'mode' = 'confirm')
      or ((q.bsb_me is distinct from q."requested_by" or coalesce((q."policy" ->> 'selfApproval')::boolean, false))
        and (case when q."subject_type" = 'ai_tool_approval' then ("better_supabase"."ai_tool_approval_approvable"(q."subject_id"))
          else (((coalesce((q.bsb_step -> 'approvers') -> 'users', '[]'::jsonb) ? q.bsb_me::text)
    or ((q.bsb_step -> 'approvers') ->> 'permission' is not null and exists (select 1 from granted g where g.t is not distinct from q."tenant_id" and g.p = (q.bsb_step -> 'approvers') ->> 'permission'))
    or ((q.bsb_step -> 'approvers') ->> 'role' is not null and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me and mm."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = ((q.bsb_step -> 'approvers') ->> 'role')::text or r."key" = ((q.bsb_step -> 'approvers') ->> 'role')::text) order by (r."id"::text = ((q.bsb_step -> 'approvers') ->> 'role')::text) desc limit 1)
    ))
    or ((q.bsb_step -> 'approvers') ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = (q.bsb_step -> 'approvers') ->> 'team' and tm."user_id" = q.bsb_me))
    or (coalesce(((q.bsb_step -> 'approvers') ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = q."tenant_id" and (case when (q."policy" ->> 'managerOf') is not null then me."id"::text = (q."policy" ->> 'managerOf') else me."user_id" = q."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) = q.bsb_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me
    ))))
    or (coalesce((q.bsb_step ->> 'escalated')::boolean, false) and ((coalesce((q.bsb_step -> 'escalateTo') -> 'users', '[]'::jsonb) ? q.bsb_me::text)
    or ((q.bsb_step -> 'escalateTo') ->> 'permission' is not null and exists (select 1 from granted g where g.t is not distinct from q."tenant_id" and g.p = (q.bsb_step -> 'escalateTo') ->> 'permission'))
    or ((q.bsb_step -> 'escalateTo') ->> 'role' is not null and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me and mm."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = ((q.bsb_step -> 'escalateTo') ->> 'role')::text or r."key" = ((q.bsb_step -> 'escalateTo') ->> 'role')::text) order by (r."id"::text = ((q.bsb_step -> 'escalateTo') ->> 'role')::text) desc limit 1)
    ))
    or ((q.bsb_step -> 'escalateTo') ->> 'team' is not null and exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = (q.bsb_step -> 'escalateTo') ->> 'team' and tm."user_id" = q.bsb_me))
    or (coalesce(((q.bsb_step -> 'escalateTo') ->> 'manager')::boolean, false) and (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = q."tenant_id" and (case when (q."policy" ->> 'managerOf') is not null then me."id"::text = (q."policy" ->> 'managerOf') else me."user_id" = q."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded'
      limit 1) = q.bsb_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me
    )))))
    or exists (select 1 from "better_supabase"."approval_decisions" x where x."request_id" = q."id" and x."step" = q."step" and x."decision" = 'delegated' and x."delegate_to" = q.bsb_me)) end)));
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
      perform "better_supabase".emit_event('maintenance_request.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_maintenance_requests.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
      perform "better_supabase".emit_event('task.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
    end if;
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(archive_work_items.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_maintenance_requests (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."maintenance_requests";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    with removed as (
      delete from "better_supabase"."maintenance_requests" x
      where x."id" = any (coalesce(delete_maintenance_requests.ids, '{}'))
        and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'facilities.manage'), false))
      returning x.*
    )
    select * from removed
  loop
    v_ids := array_append(v_ids, v_row."id");
    perform "better_supabase".emit_event('maintenance_request.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/facilities');
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(delete_maintenance_requests.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.delete_work_items (
  ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."work_items";
  v_ids uuid[] := '{}';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    with removed as (
      delete from "better_supabase"."work_items" x
      where x."id" = any (coalesce(delete_work_items.ids, '{}'))
        and ((auth.role() = 'service_role') or x."created_by" = auth.uid() or coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.manage'), false))
      returning x.*
    )
    select * from removed
  loop
    v_ids := array_append(v_ids, v_row."id");
    perform "better_supabase".emit_event('task.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  end loop;
  return jsonb_build_object(
    'ids', to_jsonb(v_ids),
    'skipped', to_jsonb(array(select distinct i from unnest(coalesce(delete_work_items.ids, '{}')) i where i is not null and not (i = any (v_ids)))));
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_maintenance_requests"(uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_maintenance_requests"(uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."archive_work_items"(uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_work_items"(uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_maintenance_requests"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_maintenance_requests"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."delete_work_items"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."delete_work_items"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approval_eligible_ids"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."approval_eligible_ids"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_maintenance_requests"(uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_maintenance_requests"(uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_work_items"(uuid[], boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_work_items"(uuid[], boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_maintenance_requests"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_maintenance_requests"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."delete_work_items"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."delete_work_items"(uuid[]) TO "authenticated", "service_role";
