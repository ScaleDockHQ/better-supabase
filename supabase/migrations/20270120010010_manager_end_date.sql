SET local check_function_bodies = off;

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
        and (case when q."subject_type" = 'support_request' then ("better_supabase"."support_request_approvable"(q."subject_id"::uuid))
          when q."subject_type" = 'ai_tool_approval' then ("better_supabase"."ai_tool_approval_approvable"(q."subject_id"))
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
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
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
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = q.bsb_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = q."tenant_id" and mm."user_id" = q.bsb_me
    )))))
    or exists (select 1 from "better_supabase"."approval_decisions" x where x."request_id" = q."id" and x."step" = q."step" and x."decision" = 'delegated' and x."delegate_to" = q.bsb_me)) end)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_fact (
  tenant    uuid,
  kind      text,
  value     text,
  requester uuid DEFAULT NULL::uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_me uuid := auth.uid();
  v_key text := 'approvals.f' || md5(format('%s|%s|%s|%s|%s', v_me, approval_fact.tenant, approval_fact.kind, approval_fact.value, approval_fact.requester));
  v_stamp text := statement_timestamp()::text || '/' || coalesce(better_supabase.memo_get('approvals.gen'), '0');
  v_hit text := better_supabase.memo_slot_get(v_key);
  v_result boolean;
begin
  if v_hit is not null and split_part(v_hit, '|', 1) = v_stamp then
    return split_part(v_hit, '|', 2) = 't';
  end if;
  v_result := coalesce(case approval_fact.kind
    when 'role' then exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = approval_fact.tenant and m."user_id" = v_me and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (approval_fact.value)::text or r."key" = (approval_fact.value)::text) order by (r."id"::text = (approval_fact.value)::text) desc limit 1)
    )
    when 'team' then exists (select 1 from "better_supabase"."team_members" tm where tm."team_id"::text = approval_fact.value and tm."user_id" = v_me)
    when 'manager' then (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = approval_fact.tenant and (case when approval_fact.value is not null then me."id"::text = approval_fact.value else me."user_id" = approval_fact.requester end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = v_me, false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = approval_fact.tenant and mm."user_id" = v_me
    ))
    else false
  end, false);
  perform better_supabase.memo_slot_set(v_key, v_stamp || '|' || case when v_result then 't' else 'f' end);
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_notify (
  request_id uuid,
  kind       text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_approvers jsonb;
  v_permission text;
  v_recipients uuid[] := '{}';
  v_claims text;
  v_note jsonb;
  v_hook regprocedure;
  v_extra jsonb;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_notify.request_id;
  if not found then
    return;
  end if;
  if approval_notify.kind in ('approved', 'rejected', 'expired') then
    v_recipients := array[v_req."requested_by"];
    v_permission := null;
  else
    v_approvers := v_req."policy" -> 'steps' -> v_req."step" -> case when approval_notify.kind = 'escalated' then 'escalateTo' else 'approvers' end;
    v_permission := v_approvers ->> 'permission';
    v_recipients := array(
      select x::uuid from jsonb_array_elements_text(coalesce(v_approvers -> 'users', '[]'::jsonb)) x
      union
      select m."user_id" from "public"."memberships" m
      where m."organization_id" = v_req."tenant_id" and m."role" = (select r."id" from "better_supabase"."roles" r where (r."id"::text = (v_approvers ->> 'role')::text or r."key" = (v_approvers ->> 'role')::text) order by (r."id"::text = (v_approvers ->> 'role')::text) desc limit 1)
      union
      select tm."user_id" from "better_supabase"."team_members" tm
      where tm."team_id"::text = v_approvers ->> 'team'
      union
      select (select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_req."tenant_id" and (case when (v_req."policy" ->> 'managerOf') is not null then me."id"::text = (v_req."policy" ->> 'managerOf') else me."user_id" = v_req."requested_by" end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) where coalesce((v_approvers ->> 'manager')::boolean, false)
      union
      select x."delegate_to" from "better_supabase"."approval_decisions" x
      where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
    );
    if approval_notify.kind = 'delegated' then
      v_recipients := array(
        select x."delegate_to" from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."decision" = 'delegated'
        order by x."created_at" desc limit 1
      );
      v_permission := null;
    end if;
    -- Approvers who already decided this step aren't asked again.
    v_recipients := array(
      select u from unnest(v_recipients) u
      where not exists (
        select 1 from "better_supabase"."approval_decisions" x
        where x."request_id" = v_req."id" and x."step" = v_req."step" and x."approver" = u
      )
    );
  end if;
  if cardinality(v_recipients) = 0 and v_permission is null then
    return;
  end if;
  v_note := jsonb_build_object(
      'type', 'approval.' || approval_notify.kind,
      'tenant', v_req."tenant_id",
      'actor', coalesce(auth.uid(), v_req."requested_by"),
      'subject_type', v_req."subject_type",
      'subject_id', v_req."subject_id",
      'summary', left(v_req."action" || coalesce(': ' || v_req."reason", ''), 140),
      'recipients', to_jsonb(v_recipients),
      'permission', v_permission,
      'exclude', case when coalesce((v_req."policy" ->> 'selfApproval')::boolean, false) or approval_notify.kind in ('approved', 'rejected', 'expired') then '[]'::jsonb else jsonb_build_array(v_req."requested_by") end,
      'include_actor', approval_notify.kind in ('approved', 'rejected', 'expired'),
      'key', 'approval.' || approval_notify.kind || ':' || v_req."id"::text || ':' || v_req."step"::text || ':' || extract(epoch from now())::bigint::text,
      'data', jsonb_build_object('requestId', v_req."id", 'action', v_req."action", 'step', v_req."step")
    );
  v_hook := to_regprocedure('"public"."approval_notification"(uuid, text, jsonb)');
  if v_hook is not null then
    execute format('select %s($1, $2, $3)', v_hook::oid::regproc) into v_extra
      using v_req."id", approval_notify.kind, v_note;
    if v_extra is null then
      return;
    end if;
    v_note := v_note || (v_extra - 'data') || jsonb_build_object('data', coalesce(v_note -> 'data', '{}'::jsonb) || coalesce(v_extra -> 'data', '{}'::jsonb));
  end if;
  if better_supabase.import_run() is null then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform "better_supabase"."notify"(v_note);
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.cancel_leave_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."leave_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_manager boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leave_requests" x where x."id" = cancel_leave_request.request_id for update;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  v_manager := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false);
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
    raise exception 'not allowed to cancel this leave request' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_row."cancelled_at" is not null then
    raise exception 'this leave request is already cancelled' using errcode = '55000', hint = 'LEAVE_REQUEST_CLOSED';
  end if;
  if not v_manager and v_row."approved_at" is not null and v_row."starts_on" <= current_date then
    raise exception 'leave that has started can only be cancelled by a manager' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
    where p."id" = v_row."approval_id" and p."status" = 'pending';
  if v_row."approved_at" is not null then
    perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id", 'cancelled')
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "cancelled_at" = now(), "cancelled_by" = auth.uid(), "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  perform "better_supabase".emit_event('leave_request.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_request.cancelled',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'cancelled leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and me."user_id" = v_row."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_leave_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."leave_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_row from "better_supabase"."leave_requests" x where x."id" = get_leave_request.request_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.read'), false))) then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and me."user_id" = v_row."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_leave_requests (
  tenant    uuid,
  user_id   uuid    DEFAULT NULL::uuid,
  status    text    DEFAULT NULL::text,
  starts    date    DEFAULT NULL::date,
  ends      date    DEFAULT NULL::date,
  everyone  boolean DEFAULT false,
  page_size integer DEFAULT 100
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_leave_requests.tenant, 'leave.read'), false);
  v_rows jsonb;
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', list_leave_requests.tenant, 'leave.request'), false)) then
    raise exception 'not allowed to list leave requests' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'userId', r."user_id", 'typeId', r."type_id", 'startsOn', r."starts_on", 'endsOn', r."ends_on", 'partial', r."partial", 'amount', r."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(r."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = r."tenant_id" and me."user_id" = r."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = r."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', r."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', r."tenant_id", 'leave.manage'), false)) then r."note" end, 'status', case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', r."approval_id", 'approvedAt', r."approved_at", 'cancelledAt', r."cancelled_at", 'createdAt', r."created_at", 'updatedAt', r."updated_at") as item, r."starts_on" as starts, r."created_at" as created
    from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
    where r."tenant_id" = list_leave_requests.tenant
      and (case
        when coalesce(list_leave_requests.everyone, false) then true
        when list_leave_requests.user_id is not null then r."user_id" = list_leave_requests.user_id
        else r."user_id" = auth.uid()
      end)
      and (list_leave_requests.status is null or case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end = list_leave_requests.status)
      and (list_leave_requests.starts is null or r."ends_on" >= list_leave_requests.starts)
      and (list_leave_requests.ends is null or r."starts_on" <= list_leave_requests.ends)
    order by r."starts_on", r."created_at"
    limit least(greatest(coalesce(list_leave_requests.page_size, 100), 1), 500)
  ) z;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.page_leave_requests (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_leave_requests.filters, '{}'::jsonb);
  v_reader boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', page_leave_requests.tenant, 'leave.read'), false);
  v_everyone boolean := coalesce(nullif(coalesce(v_filters #>> '{everyone,0}', v_filters ->> 'everyone'), '')::boolean, false);
  v_user_arg uuid := nullif(coalesce(v_filters #>> '{userId,0}', v_filters ->> 'userId'), '')::uuid;
  v_employee_arg uuid := nullif(coalesce(v_filters #>> '{employeeId,0}', v_filters ->> 'employeeId'), '')::uuid;
  v_from date := nullif(coalesce(v_filters #>> '{from,0}', v_filters ->> 'from'), '')::date;
  v_to date := nullif(coalesce(v_filters #>> '{to,0}', v_filters ->> 'to'), '')::date;
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500);
  v_offset integer := greatest(coalesce((v_filters ->> 'offset')::integer, 0), 0);
  v_after jsonb := v_filters -> 'after';
  v_paged boolean := coalesce((v_filters ->> 'paged')::boolean, false);
  v_total_cap integer := least(greatest(coalesce((v_filters ->> 'totalCap')::integer, 10000), 1), 100000);
  v_items jsonb;
  v_more boolean;
  v_next jsonb;
  v_total integer;
  v_sort text := nullif(v_filters ->> 'sort', '');
  v_dir text := nullif(v_filters ->> 'direction', '');
  v_facet text := nullif(v_filters ->> 'facet', '');
  v_count boolean := coalesce((v_filters ->> 'count')::boolean, false);
  v_result jsonb;
begin
  if not (v_reader or coalesce(better_supabase.can('tenant', page_leave_requests.tenant, 'leave.request'), false)) then
    raise exception 'not allowed to list leave requests' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if not v_reader and (v_everyone or (v_user_arg is not null and v_user_arg is distinct from auth.uid())) then
    raise exception 'not allowed to read another member''s leave' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_filters ? 'after' and v_filters ? 'offset' then
    raise exception 'after and offset are two ways to page; pass one' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_facet is not null then
    if v_facet not in ('status', 'typeId') then
      raise exception 'facet is one of status, typeId' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    with s as (
      select (case v_facet when 'status' then (x.leave_status)::text when 'typeId' then (x."type_id"::text)::text end) as v
      from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
      limit v_total_cap + 1
    )
    select jsonb_build_object('facet', v_facet, 'values', coalesce(jsonb_agg(jsonb_build_object('value', g.v, 'count', jsonb_build_object('value', g.n, 'exact', g.exact)) order by g.n desc, g.v), '[]'::jsonb))
    into v_result
    from (
      select s.v, count(*) as n, (select count(*) from s) <= v_total_cap as exact
      from s where s.v is not null group by s.v order by n desc, s.v limit 100
    ) g;
    return v_result;
  end if;
  if v_count then
    select count(*) into v_total from (
      select 1 from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
      limit v_total_cap + 1
    ) c;
    return jsonb_build_object('value', least(v_total, v_total_cap), 'exact', v_total <= v_total_cap);
  end if;
  if v_sort is not null and v_sort not in ('startsOn', 'endsOn', 'createdAt') then
    raise exception 'sort is one of startsOn, endsOn, createdAt' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_dir is not null and v_dir not in ('asc', 'desc') then
    raise exception 'direction is asc or desc' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_sort is null and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."starts_on", x."created_at", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."starts_on" asc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort is null and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."created_at" > (v_after ->> 1)::timestamptz) or (x."starts_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."starts_on" desc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'asc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."starts_on", x."created_at", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::timestamptz, (v_after ->> 2)::uuid))
      order by x."starts_on" asc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'startsOn' and coalesce(v_dir, 'asc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 3) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."starts_on")::text, (x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."starts_on" <= (v_after ->> 0)::date and ((x."starts_on" < (v_after ->> 0)::date) or (x."starts_on" = (v_after ->> 0)::date and x."created_at" > (v_after ->> 1)::timestamptz) or (x."starts_on" = (v_after ->> 0)::date and x."created_at" = (v_after ->> 1)::timestamptz and x."id" > (v_after ->> 2)::uuid))))
      order by x."starts_on" desc, x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."ends_on")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."ends_on", x."id") > ((v_after ->> 0)::date, (v_after ->> 1)::uuid))
      order by x."ends_on" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'endsOn' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."ends_on")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."ends_on" <= (v_after ->> 0)::date and ((x."ends_on" < (v_after ->> 0)::date) or (x."ends_on" = (v_after ->> 0)::date and x."id" > (v_after ->> 1)::uuid))))
      order by x."ends_on" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'asc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."created_at", x."id") > ((v_after ->> 0)::timestamptz, (v_after ->> 1)::uuid))
      order by x."created_at" asc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  elsif v_sort = 'createdAt' and coalesce(v_dir, 'desc') = 'desc' then
    if v_after is not null and (jsonb_typeof(v_after) <> 'array' or jsonb_array_length(v_after) <> 2) then
    raise exception 'after is the nextCursor of the previous page' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  select coalesce(jsonb_agg(p.j order by p.n) filter (where p.n <= v_limit), '[]'::jsonb),
    count(*) > v_limit,
    (array_agg(p.k order by p.n) filter (where p.n = v_limit))[1]
  into v_items, v_more, v_next
  from (
    select row_number() over () as n, jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', x.leave_status, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") as j, jsonb_build_array((x."created_at")::text, (x."id")::text) as k
    from (
      select * from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
        and (v_after is null or (x."created_at" <= (v_after ->> 0)::timestamptz and ((x."created_at" < (v_after ->> 0)::timestamptz) or (x."created_at" = (v_after ->> 0)::timestamptz and x."id" > (v_after ->> 1)::uuid))))
      order by x."created_at" desc, x."id" asc
      limit v_limit + 1 offset v_offset
    ) x
  ) p;
  end if;
  if not v_paged then
    return v_items;
  end if;
  if coalesce((v_filters ->> 'total')::boolean, false) then
    select count(*) into v_total from (
      select 1 from (select r.*, case when r."cancelled_at" is not null then 'cancelled' when r."approved_at" is not null then 'approved' when p."status" in ('rejected', 'expired') then 'rejected' when p."status" = 'cancelled' then 'cancelled' else 'pending' end as leave_status from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id") x
      where x."tenant_id" = page_leave_requests.tenant
        and (case when v_everyone then true when v_user_arg is not null then x."user_id" = v_user_arg else x."user_id" = auth.uid() end)
        and (not (v_filters -> 'status' is not null and jsonb_typeof(v_filters -> 'status') <> 'null' and not (jsonb_typeof(v_filters -> 'status') = 'array' and jsonb_array_length(v_filters -> 'status') = 0)) or (x.leave_status)::text = any((case when jsonb_typeof(v_filters -> 'status') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'status')) else array[v_filters ->> 'status'] end)::text[]))
        and (not (v_filters -> 'typeId' is not null and jsonb_typeof(v_filters -> 'typeId') <> 'null' and not (jsonb_typeof(v_filters -> 'typeId') = 'array' and jsonb_array_length(v_filters -> 'typeId') = 0)) or x."type_id"::text = any((case when jsonb_typeof(v_filters -> 'typeId') = 'array' then array(select jsonb_array_elements_text(v_filters -> 'typeId')) else array[v_filters ->> 'typeId'] end)::text[]))
        and (v_from is null or x."ends_on" >= v_from)
        and (v_to is null or x."starts_on" <= v_to)
        and (v_search is null or (x."note" ilike v_search and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false))) or exists (select 1 from "better_supabase"."leave_types" st where st."id"::text = x."type_id"::text and st."name" ilike v_search))
      limit v_total_cap + 1
    ) c;
  end if;
  return jsonb_build_object('items', v_items, 'hasMore', v_more, 'nextCursor', case when v_more then v_next end)
    || case when v_total is null then '{}'::jsonb
      else jsonb_build_object('total', least(v_total, v_total_cap), 'totalCapped', v_total > v_total_cap) end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_leave (
  tenant    uuid,
  type_id   uuid,
  starts_on date,
  ends_on   date,
  partial   text    DEFAULT 'full'::text,
  hours     numeric DEFAULT NULL::numeric,
  note      text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_type "better_supabase"."leave_types"%rowtype;
  v_partial text := coalesce(request_leave.partial, 'full');
  v_amount numeric;
  v_row "better_supabase"."leave_requests"%rowtype;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', request_leave.tenant, 'leave.request'), false) then
    raise exception 'not allowed to request leave here' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select * into v_type from "better_supabase"."leave_types" x
    where x."id" = request_leave.type_id and x."tenant_id" = request_leave.tenant and x."archived_at" is null;
  if not found then
    raise exception 'leave type not found' using errcode = 'P0002', hint = 'LEAVE_TYPE_NOT_FOUND';
  end if;
  if request_leave.starts_on is null or request_leave.ends_on is null or request_leave.ends_on < request_leave.starts_on then
    raise exception 'ends_on must be on or after starts_on' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_partial not in ('full', 'morning', 'afternoon', 'hours') then
    raise exception 'partial must be full, morning, afternoon or hours' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_type."unit" = 'hours' then
    if v_partial <> 'hours' and v_partial <> 'full' then
      raise exception 'an hours type takes partial hours' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if request_leave.hours is null or request_leave.hours <= 0 then
      raise exception 'an hours type needs hours greater than zero' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_partial := 'hours';
    v_amount := request_leave.hours;
  else
    if v_partial = 'hours' then
      raise exception 'a day type takes partial full, morning or afternoon' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if v_partial in ('morning', 'afternoon') and request_leave.starts_on <> request_leave.ends_on then
      raise exception 'a half day starts and ends on the same date' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_amount := "better_supabase"."leave_working_days"(request_leave.starts_on, request_leave.ends_on)
      * case when v_partial = 'full' then 1 else 0.5 end;
  end if;
  if v_amount <= 0 then
    raise exception 'the request covers no working days' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if not "better_supabase"."period_is_open"(request_leave.tenant, 'leave_year', request_leave.starts_on) then raise exception 'the leave year of this request is locked or closed' using errcode = '55000', hint = 'LEAVE_PERIOD_CLOSED'; end if;
  perform pg_advisory_xact_lock(hashtextextended('leave:' || request_leave.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
    where r."tenant_id" = request_leave.tenant and r."user_id" = v_me
      and r."cancelled_at" is null and (r."approved_at" is not null or p."status" = 'pending')
      and daterange(r."starts_on", r."ends_on", '[]') && daterange(request_leave.starts_on, request_leave.ends_on, '[]')
      and not (r."partial" = 'morning' and v_partial = 'afternoon')
      and not (r."partial" = 'afternoon' and v_partial = 'morning')
  ) then
    raise exception 'this overlaps another leave request' using errcode = '23P01', hint = 'LEAVE_OVERLAP';
  end if;
  if v_type."tracked" and "better_supabase"."leave_available"(request_leave.tenant, v_me, v_type."id", extract(year from request_leave.starts_on)::integer) < v_amount then
    raise exception 'this request is more than the available balance' using errcode = '23514', hint = 'LEAVE_BALANCE_EXCEEDED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_leave_request"(uuid, uuid, date, date, numeric)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date, $4::date, $5::numeric)', v_hook::oid::regproc)
        using request_leave.tenant, v_type."id", request_leave.starts_on, request_leave.ends_on, v_amount;
    end if;
  end;
  insert into "better_supabase"."leave_requests" ("tenant_id", "user_id", "type_id", "starts_on", "ends_on", "partial", "amount", "note")
  values (request_leave.tenant, v_me, v_type."id", request_leave.starts_on, request_leave.ends_on, v_partial, v_amount, nullif(trim(request_leave.note), ''))
  returning * into v_row;
  if not v_type."auto_approve" then
    v_request := "better_supabase"."open_approval"(
      request_leave.tenant, 'leave_request', v_row."id"::text, 'approve',
      '{"steps":[{"approvers":{"permission":"leave.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
      jsonb_build_object('userId', v_me, 'typeId', v_type."id", 'type', v_type."name", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_amount::text, 'unit', v_type."unit")
    );
    update "better_supabase"."leave_requests" x set "approval_id" = (v_request ->> 'id')::uuid
      where x."id" = v_row."id"
      returning * into v_row;
    select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  end if;
  perform "better_supabase".emit_event('leave_request.requested', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_request.requested',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'requested leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
  if v_type."auto_approve" then
    perform "better_supabase"."approve_leave_request"(v_row."id");
    select * into v_row from "better_supabase"."leave_requests" x where x."id" = v_row."id";
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_leave_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and me."user_id" = v_row."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.split_leave_request (
  request_id uuid,
  gap_starts date,
  gap_ends   date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."leave_requests"%rowtype;
  v_row "better_supabase"."leave_requests"%rowtype;
  v_type "better_supabase"."leave_types"%rowtype;
  v_partial text := 'full';
  v_amount numeric;
  v_approval "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_old from "better_supabase"."leave_requests" x where x."id" = split_leave_request.request_id for update;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_old."tenant_id", 'leave.manage'), false)) then
    raise exception 'approved leave is split by a manager' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if v_old."approved_at" is null or v_old."cancelled_at" is not null then
    raise exception 'only approved leave is split' using errcode = '55000', hint = 'LEAVE_REQUEST_CLOSED';
  end if;
  select * into v_type from "better_supabase"."leave_types" x where x."id" = v_old."type_id";
  if v_type."unit" = 'hours' then
    raise exception 'leave in hours isn''t split' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if split_leave_request.gap_starts is null or split_leave_request.gap_ends is null
    or split_leave_request.gap_ends < split_leave_request.gap_starts
    or split_leave_request.gap_starts <= v_old."starts_on" or split_leave_request.gap_ends >= v_old."ends_on" then
    raise exception 'the gap lies inside the leave with days on both sides; shorten leave with update_leave_request' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_partial not in ('full', 'morning', 'afternoon', 'hours') then
    raise exception 'partial must be full, morning, afternoon or hours' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_type."unit" = 'hours' then
    if v_partial <> 'hours' and v_partial <> 'full' then
      raise exception 'an hours type takes partial hours' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if null is null or null <= 0 then
      raise exception 'an hours type needs hours greater than zero' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_partial := 'hours';
    v_amount := null;
  else
    if v_partial = 'hours' then
      raise exception 'a day type takes partial full, morning or afternoon' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if v_partial in ('morning', 'afternoon') and (split_leave_request.gap_ends + 1) <> v_old."ends_on" then
      raise exception 'a half day starts and ends on the same date' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_amount := "better_supabase"."leave_working_days"((split_leave_request.gap_ends + 1), v_old."ends_on")
      * case when v_partial = 'full' then 1 else 0.5 end;
  end if;
  perform "better_supabase"."update_leave_request"(v_old."id", ends_on => split_leave_request.gap_starts - 1, partial => 'full');
  insert into "better_supabase"."leave_requests" ("tenant_id", "user_id", "type_id", "starts_on", "ends_on", "partial", "amount", "note", "approval_id", "approved_at")
  values (v_old."tenant_id", v_old."user_id", v_old."type_id", split_leave_request.gap_ends + 1, v_old."ends_on", v_partial, v_amount, v_old."note", v_old."approval_id", v_old."approved_at")
  returning * into v_row;
  perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
  from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  perform "better_supabase".emit_event('leave_request.split', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_request.split',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'split leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
  return jsonb_build_object(
    'request', (select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'userId', x."user_id", 'typeId', x."type_id", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'partial', x."partial", 'amount', x."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(x."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = x."tenant_id" and me."user_id" = x."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = x."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', x."tenant_id", 'leave.manage'), false)) then x."note" end, 'status', case when x."cancelled_at" is not null then 'cancelled' when x."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', x."approval_id", 'approvedAt', x."approved_at", 'cancelledAt', x."cancelled_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") from "better_supabase"."leave_requests" x where x."id" = v_old."id"),
    'split', jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and me."user_id" = v_row."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at")
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_leave_request (
  request_id uuid,
  starts_on  date    DEFAULT NULL::date,
  ends_on    date    DEFAULT NULL::date,
  partial    text    DEFAULT NULL::text,
  hours      numeric DEFAULT NULL::numeric,
  note       text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid;
  v_row "better_supabase"."leave_requests"%rowtype;
  v_old "better_supabase"."leave_requests"%rowtype;
  v_type "better_supabase"."leave_types"%rowtype;
  v_partial text;
  v_amount numeric;
  v_manager boolean;
  v_status text;
  v_starts date;
  v_ends date;
  v_approval "better_supabase"."approval_requests"%rowtype;
  v_request jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leave_requests" x where x."id" = update_leave_request.request_id for update;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
  v_old := v_row;
  v_manager := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false);
  if not (v_manager or coalesce(v_row."user_id" = auth.uid(), false)) then
    raise exception 'not allowed to change this leave request' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  v_status := case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end;
  if v_status not in ('pending', 'approved') then
    raise exception 'only a pending or approved leave request changes' using errcode = '55000', hint = 'LEAVE_REQUEST_CLOSED';
  end if;
  if v_status = 'approved' and not v_manager then
    raise exception 'approved leave is changed by a manager' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  select * into v_type from "better_supabase"."leave_types" x where x."id" = v_row."type_id";
  v_me := v_row."user_id";
  v_starts := coalesce(update_leave_request.starts_on, v_row."starts_on");
  v_ends := coalesce(update_leave_request.ends_on, v_row."ends_on");
  if v_ends < v_starts then
    raise exception 'ends_on must be on or after starts_on' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  v_partial := coalesce(update_leave_request.partial, (v_old."partial")::text);
  if v_partial not in ('full', 'morning', 'afternoon', 'hours') then
    raise exception 'partial must be full, morning, afternoon or hours' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if v_type."unit" = 'hours' then
    if v_partial <> 'hours' and v_partial <> 'full' then
      raise exception 'an hours type takes partial hours' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if coalesce(update_leave_request.hours, case when v_type."unit" = 'hours' then v_old."amount" end) is null or coalesce(update_leave_request.hours, case when v_type."unit" = 'hours' then v_old."amount" end) <= 0 then
      raise exception 'an hours type needs hours greater than zero' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_partial := 'hours';
    v_amount := coalesce(update_leave_request.hours, case when v_type."unit" = 'hours' then v_old."amount" end);
  else
    if v_partial = 'hours' then
      raise exception 'a day type takes partial full, morning or afternoon' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    if v_partial in ('morning', 'afternoon') and v_starts <> v_ends then
      raise exception 'a half day starts and ends on the same date' using errcode = '22023', hint = 'LEAVE_INVALID';
    end if;
    v_amount := "better_supabase"."leave_working_days"(v_starts, v_ends)
      * case when v_partial = 'full' then 1 else 0.5 end;
  end if;
  if v_amount <= 0 then
    raise exception 'the request covers no working days' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leave:' || v_row."tenant_id"::text || ':' || v_me::text, 0));
  if exists (
    select 1 from "better_supabase"."leave_requests" r
    left join "better_supabase"."approval_requests" p on p."id" = r."approval_id"
    where r."tenant_id" = v_row."tenant_id" and r."user_id" = v_me
      and r."cancelled_at" is null and r."id" <> v_row."id" and (r."approved_at" is not null or p."status" = 'pending')
      and daterange(r."starts_on", r."ends_on", '[]') && daterange(v_starts, v_ends, '[]')
      and not (r."partial" = 'morning' and v_partial = 'afternoon')
      and not (r."partial" = 'afternoon' and v_partial = 'morning')
  ) then
    raise exception 'this overlaps another leave request' using errcode = '23P01', hint = 'LEAVE_OVERLAP';
  end if;
  if v_type."tracked" and "better_supabase"."leave_available"(v_row."tenant_id", v_me, v_type."id", extract(year from v_starts)::integer)
    + (case when extract(year from v_old."starts_on") = extract(year from v_starts) then v_old."amount" else 0 end) < v_amount then
    raise exception 'this request is more than the available balance' using errcode = '23514', hint = 'LEAVE_BALANCE_EXCEEDED';
  end if;
  if v_status = 'approved' then
    perform "better_supabase"."leave_post"(v_old."tenant_id", v_old."user_id", v_old."type_id", 'taken', v_old."amount", extract(year from v_old."starts_on")::integer, v_old."id", 'changed')
    from "better_supabase"."leave_types" t where t."id" = v_old."type_id" and t."tracked";
  end if;
  update "better_supabase"."leave_requests" x set "starts_on" = v_starts, "ends_on" = v_ends, "partial" = v_partial, "amount" = v_amount, "note" = case when update_leave_request.note is null then x."note" else nullif(trim(update_leave_request.note), '') end, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  if v_status = 'approved' then
    perform "better_supabase"."leave_post"(v_row."tenant_id", v_row."user_id", v_row."type_id", 'taken', -v_row."amount", extract(year from v_row."starts_on")::integer, v_row."id")
    from "better_supabase"."leave_types" t where t."id" = v_row."type_id" and t."tracked";
  end if;
  if v_status = 'pending' then
    update "better_supabase"."approval_requests" p set "status" = 'cancelled', "decided_at" = now()
      where p."id" = v_row."approval_id" and p."status" = 'pending';
    if not v_type."auto_approve" then
      v_request := "better_supabase"."open_approval"(
        v_row."tenant_id", 'leave_request', v_row."id"::text, 'approve',
        '{"steps":[{"approvers":{"permission":"leave.approve"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb, v_row."note",
        jsonb_build_object('userId', v_me, 'typeId', v_type."id", 'type', v_type."name", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_amount::text, 'unit', v_type."unit")
      );
      update "better_supabase"."leave_requests" x set "approval_id" = (v_request ->> 'id')::uuid
        where x."id" = v_row."id"
        returning * into v_row;
      select * into v_approval from "better_supabase"."approval_requests" x where x."id" = v_row."approval_id";
    end if;
    if v_type."auto_approve" then
      perform "better_supabase"."approve_leave_request"(v_row."id");
      select * into v_row from "better_supabase"."leave_requests" x where x."id" = v_row."id";
    end if;
  end if;
  perform "better_supabase".emit_event('leave_request.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id"), 'leave-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/leave');
  perform better_supabase.audit_event(
    event_type => 'leave_request.updated',
    category => 'data',
    target_type => 'leave_request',
    record_id => v_row."id"::text,
    summary => 'changed leave' || ' from ' || v_row."starts_on"::text || ' to ' || v_row."ends_on"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'amount', v_row."amount"::text, 'approvalId', v_row."approval_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and me."user_id" = v_row."user_id"
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "public"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = auth.uid()
    )) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;
