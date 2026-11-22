SET local check_function_bodies = off;

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
    raise exception 'this leave request is already cancelled' using errcode = 'PT409', hint = 'LEAVE_REQUEST_CLOSED';
  end if;
  if v_row."approved_at" is null and v_row."rejected_at" is not null then
    raise exception 'this leave request was rejected' using errcode = 'PT409', hint = 'LEAVE_REQUEST_CLOSED';
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
    )) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.approve'), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leave.manage'), false)) then v_row."note" end, 'status', case when v_row."cancelled_at" is not null then 'cancelled' when v_row."approved_at" is not null then 'approved' when v_row."rejected_at" is not null then 'rejected' when v_approval."status" in ('rejected', 'expired') then 'rejected' when v_approval."status" = 'cancelled' then 'cancelled' else 'pending' end, 'approvalId', v_row."approval_id", 'approvedAt', v_row."approved_at", 'cancelledAt', v_row."cancelled_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.outbox_register (
  consumer   text,
  types      text[]  DEFAULT NULL::text[],
  from_start boolean DEFAULT false
)
  RETURNS bigint
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  insert into "better_supabase"."outbox_consumers" ("name", "cursor_xid", "cursor_position", "types")
  select consumer, least(coalesce(latest.xid, '0'), pg_snapshot_xmax(pg_current_snapshot())), coalesce(latest.position, 0), types
  from (select 1) one
  left join lateral (
    select e."xid" as xid, e."position" as position from "better_supabase"."outbox_events" e
    where not from_start
    order by e."xid" desc, e."position" desc
    limit 1
  ) latest on true
  on conflict ("name") do update set "types" = excluded."types", "updated_at" = now()
  returning "cursor_position"
$function$;
