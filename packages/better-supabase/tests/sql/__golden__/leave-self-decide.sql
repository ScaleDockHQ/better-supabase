create or replace function "better_supabase"."decide_leave_request"(request_id uuid, approved boolean, note text default null, decided_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."leave_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."leave_requests" x where x."id" = decide_leave_request.request_id for update;
  if not found then
    raise exception 'leave request not found' using errcode = 'P0002', hint = 'LEAVE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or (coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and (case when v_row."employee_id"::text is not null then me."id"::text = v_row."employee_id"::text else me."user_id" = (select lo."user_id" from "better_supabase"."employees" lo where lo."id" = v_row."employee_id") end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = auth.uid(), false) and exists (
      select 1 from "better_supabase"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = auth.uid() and mm."disabled_at" is null
    )) or coalesce("public"."chain_decides"(decide_leave_request.request_id), false)) and (select lo."user_id" from "better_supabase"."employees" lo where lo."id" = v_row."employee_id") is distinct from auth.uid()) or (coalesce((select lo."user_id" from "better_supabase"."employees" lo where lo."id" = v_row."employee_id") = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) and not exists (
      select 1 from "better_supabase"."memberships" om
      where om."organization_id" = v_row."tenant_id" and om."user_id" is distinct from (select lo."user_id" from "better_supabase"."employees" lo where lo."id" = v_row."employee_id") and om."disabled_at" is null
        and ((coalesce((select mgr."user_id" from "better_supabase"."employees" me
      join "better_supabase"."employees" mgr on mgr."id" = me."manager_id"
      where me."tenant_id" = v_row."tenant_id" and (case when v_row."employee_id"::text is not null then me."id"::text = v_row."employee_id"::text else me."user_id" = (select lo."user_id" from "better_supabase"."employees" lo where lo."id" = v_row."employee_id") end)
        and mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
      limit 1) = om."user_id", false) and exists (
      select 1 from "better_supabase"."memberships" mm
      where mm."organization_id" = v_row."tenant_id" and mm."user_id" = om."user_id" and mm."disabled_at" is null
    )) or om."user_id" in (
          with recursive up(id) as (
            select me."manager_id" from "better_supabase"."employees" me
            where me."tenant_id" = v_row."tenant_id" and (case when v_row."employee_id"::text is not null then me."id"::text = v_row."employee_id"::text else me."user_id" = (select lo."user_id" from "better_supabase"."employees" lo where lo."id" = v_row."employee_id") end)
            union
            select boss."manager_id" from up join "better_supabase"."employees" boss on boss."id" = up.id
          )
          select mgr."user_id" from up join "better_supabase"."employees" mgr on mgr."id" = up.id
          where mgr."user_id" is not null and mgr."status" <> 'offboarded' and (mgr."end_date" is null or mgr."end_date" >= current_date)
        ) or coalesce(better_supabase.can_user(om."user_id", 'tenant', v_row."tenant_id", 'leave.approve'), false))
    ))) or (decide_leave_request.decided_by is not null and (not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') and decide_leave_request.decided_by is distinct from auth.uid() or decide_leave_request.decided_by = (select lo."user_id" from "better_supabase"."employees" lo where lo."id" = v_row."employee_id"))) then
    raise exception 'not allowed to decide this leave request; only the service role decides for another user, never for the requester' using errcode = '42501', hint = 'LEAVE_FORBIDDEN';
  end if;
  if not (v_row."cancelled_at" is null and v_row."approved_at" is null and v_row."rejected_at" is null) then
    raise exception 'this leave request was already decided or cancelled' using errcode = 'PT409', hint = 'LEAVE_REQUEST_CLOSED';
  end if;
  if decide_leave_request.approved is null then
    raise exception 'approved must be true or false' using errcode = '22023', hint = 'LEAVE_INVALID';
  end if;
  if decide_leave_request.approved then
    perform "better_supabase"."approve_leave_request"(v_row."id");
    update "better_supabase"."leave_requests" x set "updated_at" = now(), "decided_by" = coalesce(decide_leave_request.decided_by, auth.uid()), "decision_note" = nullif(trim(decide_leave_request.note), '')
      where x."id" = v_row."id"
      returning * into v_row;
  else
    update "better_supabase"."leave_requests" x set "rejected_at" = now(), "updated_at" = now(), "decided_by" = coalesce(decide_leave_request.decided_by, auth.uid()), "decision_note" = nullif(trim(decide_leave_request.note), '')
      where x."id" = v_row."id"
      returning * into v_row;
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'employeeId', v_row."employee_id", 'typeId', v_row."type_id", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'partial', v_row."partial", 'amount', v_row."amount"::text, 'note', case when (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce("better_supabase"."leave_is_mine"(v_row."tenant_id", v_row."employee_id"), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_row."rejected_at" is not null then 'rejected' else 'pending' end, 'approvalId', null, 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;