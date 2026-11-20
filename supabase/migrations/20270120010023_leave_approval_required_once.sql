SET local check_function_bodies = off;

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
  v_at_once boolean;
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
  v_at_once := coalesce(v_type."auto_approve", false);
  if not v_at_once then
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
  if v_at_once then
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
  v_at_once boolean;
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
    raise exception 'only a pending or approved leave request changes' using errcode = 'PT409', hint = 'LEAVE_REQUEST_CLOSED';
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
    v_at_once := coalesce(v_type."auto_approve", false);
    if not v_at_once then
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
    if v_at_once then
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
