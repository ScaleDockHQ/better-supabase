SET local check_function_bodies = off;

DROP POLICY "bs_realtime_tables_receive" ON "realtime"."messages";

CREATE OR REPLACE FUNCTION better_supabase.acting_member()
  RETURNS uuid
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  header text;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    return null;
  end if;
  header := nullif(current_setting('request.headers', true), '')::jsonb ->> 'x-bsb-actor';
  return case when header ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then header::uuid end;
exception when others then
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.broadcast_changes()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  base text := 'bsb:t:' || tg_table_schema || '.' || tg_table_name
    || case when tg_nargs > 1 and tg_argv[1] = 'user' then ':u' else '' end;
  payload jsonb := jsonb_build_object('schema', tg_table_schema, 'table', tg_table_name, 'operation', tg_op);
  source text;
  tenant text;
begin
  if tg_nargs = 0 or tg_argv[0] = '' then
    perform realtime.send(payload, 'change', base, true);
    return null;
  end if;
  source := case tg_op
    when 'INSERT' then format('select %1$I from new_rows', tg_argv[0])
    when 'DELETE' then format('select %1$I from old_rows', tg_argv[0])
    else format('select %1$I from new_rows union select %1$I from old_rows', tg_argv[0])
  end;
  for tenant in execute format('select distinct t.v::text from (%s) as t(v) where t.v is not null', source) loop
    perform realtime.send(payload, 'change', base || ':' || tenant, true);
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_in_pass (
  pass_id     uuid,
  nonce       text DEFAULT NULL::text,
  method      text DEFAULT 'qr'::text,
  gate        text DEFAULT NULL::text,
  resource_id uuid DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_pass "better_supabase"."passes"%rowtype;
  v_row "better_supabase"."pass_check_ins"%rowtype;
  v_reason text;
  v_resource uuid;
  v_capacity integer;
  v_booking "better_supabase"."bookings"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if check_in_pass.method is null or check_in_pass.method not in ('qr', 'nfc', 'manual') then
    raise exception 'method is qr, nfc or manual' using errcode = '22023', hint = 'PASS_METHOD_INVALID';
  end if;
  select * into v_pass from "better_supabase"."passes" x where x."id" = check_in_pass.pass_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_pass."tenant_id", 'passes.check_in'), false)) then
    raise exception 'pass not found' using errcode = 'P0002', hint = 'PASS_NOT_FOUND';
  end if;
  v_resource := coalesce(check_in_pass.resource_id, v_pass."resource_id");
  v_reason := case
    when check_in_pass.method <> 'manual' and check_in_pass.nonce is distinct from v_pass."nonce" then 'invalid'
    when v_pass."status" = 'revoked' then 'revoked'
    when now() < v_pass."valid_from" then 'not_yet_valid'
    when v_pass."valid_until" is not null and now() >= v_pass."valid_until" then 'expired'
    when v_pass."uses_allowed" is not null and v_pass."uses" >= v_pass."uses_allowed" then 'used_up'
    when check_in_pass.resource_id is not null and v_pass."resource_id" is not null
      and check_in_pass.resource_id <> v_pass."resource_id" then 'wrong_resource'
  end;
  if v_reason is null and v_pass."booking_id" is not null then
    select * into v_booking from "better_supabase"."bookings" bk where bk."id" = v_pass."booking_id";
    if not found or v_booking."status" = 'cancelled'
      or (v_booking."status" = 'hold' and v_booking."hold_expires_at" <= now()) then
      v_reason := 'booking_cancelled';
    elsif v_booking."status" = 'hold' then
      v_reason := 'booking_unconfirmed';
    elsif now() < lower(v_booking."during") - '1 hour'::interval
      or now() >= upper(v_booking."during") then
      v_reason := 'outside_window';
    end if;
  end if;
  if v_reason is null and v_pass."booking_id" is null and v_resource is not null then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:passes:' || v_resource::text, 0));
    select rs."capacity" into v_capacity from "better_supabase"."booking_resources" rs
      where rs."id" = v_resource and rs."tenant_id" = v_pass."tenant_id";
    if v_capacity is null then
      v_reason := 'wrong_resource';
    elsif ((select count(*) from "better_supabase"."bookings" bk
      where bk."resource_id" = v_resource and (bk."status" = 'confirmed' or (bk."status" = 'hold' and bk."hold_expires_at" > now())) and bk."during" @> now())
      + (select count(*) from "better_supabase"."pass_check_ins" y
      where y."resource_id" = v_resource and y."admitted" and y."booking_id" is null
        and y."created_at" > now() - '2 hours'::interval)) >= v_capacity then
      v_reason := 'full';
    end if;
  end if;
  insert into "better_supabase"."pass_check_ins" ("tenant_id", "pass_id", "resource_id", "booking_id", "gate", "method", "admitted", "reason", "checked_in_by")
  values (v_pass."tenant_id", v_pass."id", v_resource, v_pass."booking_id", check_in_pass.gate, check_in_pass.method, v_reason is null, v_reason, auth.uid())
  returning * into v_row;
  if v_reason is null then
    update "better_supabase"."passes" x set "uses" = x."uses" + 1, "updated_at" = now()
      where x."id" = v_pass."id"
      returning * into v_pass;
    perform "better_supabase".emit_event('pass.admitted', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  else
    perform "better_supabase".emit_event('pass.rejected', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."pass_id", 'checkInId', v_row."id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'reason', v_row."reason"), 'passes/' || v_row."pass_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/passes');
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'passId', v_row."pass_id", 'resourceId', v_row."resource_id", 'bookingId', v_row."booking_id", 'gate', v_row."gate", 'method', v_row."method", 'admitted', v_row."admitted", 'reason', v_row."reason", 'checkedInBy', v_row."checked_in_by", 'createdAt', v_row."created_at") || jsonb_build_object('pass', jsonb_build_object('id', v_pass."id", 'organizationId', v_pass."tenant_id"::text, 'kind', v_pass."kind", 'holderUserId', v_pass."holder_user_id", 'holderName', v_pass."holder_name", 'holderEmail', v_pass."holder_email", 'subjectType', v_pass."subject_type", 'subjectId', v_pass."subject_id", 'bookingId', v_pass."booking_id", 'resourceId', v_pass."resource_id", 'usesAllowed', v_pass."uses_allowed", 'uses', v_pass."uses", 'validFrom', v_pass."valid_from", 'validUntil', v_pass."valid_until", 'status', v_pass."status", 'issuedBy', v_pass."issued_by", 'createdAt', v_pass."created_at", 'updatedAt', v_pass."updated_at", 'revokedAt', v_pass."revoked_at"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.check_workflow_alerts (
  batch integer DEFAULT 100
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_pair record;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_run "better_supabase"."workflow_runs"%rowtype;
  v_fired integer := 0;
begin
  for v_pair in
    select x."id" as alert, y."id" as run from "better_supabase"."workflow_alerts" x
    join "better_supabase"."workflow_runs" y on y."attributes" ->> 'bsb.definition' = x."definition_id"::text
    where x."on_event" = 'slow'
      and y."mode" = 'live'
      and y."status" in ('queued', 'running', 'waiting')
      and y."created_at" < now() - x."threshold"
      and not exists (select 1 from "better_supabase"."workflow_alert_fires" z where z."alert_id" = x."id" and z."run_id" = y."id")
    limit greatest(coalesce(batch, 100), 1)
  loop
    select * into v_alert from "better_supabase"."workflow_alerts" x where x."id" = v_pair.alert;
    select * into v_run from "better_supabase"."workflow_runs" x where x."id" = v_pair.run;
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
        perform "better_supabase".emit_event('workflow_alert.triggered', jsonb_build_object('alertId', v_alert."id", 'organizationId', v_run."tenant_id"::text, 'definition', v_alert."definition_id", 'onEvent', v_alert."on_event", 'channel', v_alert."channel", 'runId', v_run."id", 'status', v_run."status", 'error', v_run."error"), 'workflow-runs/' || v_run."id", (v_run."tenant_id")::text, 'workflow_alert.triggered:' || v_alert."id" || ':' || v_run."id", 'better-supabase/workflow-builder');
      end if;
  end loop;
  return v_fired;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_work_order (
  tenant       uuid,
  title        text,
  description  text                     DEFAULT NULL::text,
  priority     text                     DEFAULT 'normal'::text,
  location_id  uuid                     DEFAULT NULL::uuid,
  asset_id     uuid                     DEFAULT NULL::uuid,
  booking_id   uuid                     DEFAULT NULL::uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  address      text                     DEFAULT NULL::text,
  technician   uuid                     DEFAULT NULL::uuid,
  starts_at    timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  ends_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_orders"%rowtype;
  v_starts timestamptz := create_work_order.starts_at;
  v_ends timestamptz := create_work_order.ends_at;
  v_during tstzrange;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', create_work_order.tenant, 'dispatch.manage'), false)) then
    raise exception 'not allowed to manage work orders' using errcode = '42501', hint = 'DISPATCH_FORBIDDEN';
  end if;
  if (create_work_order.subject_type is null) <> (create_work_order.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'DISPATCH_SUBJECT_INVALID';
  end if;
  if create_work_order.subject_type is not null
    and (case create_work_order.subject_type
      when 'message' then (select s."tenant_id"::text from "better_supabase"."messages" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'conversation' then (select s."tenant_id"::text from "better_supabase"."conversations" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'channel' then (select s."tenant_id"::text from "better_supabase"."channels" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'company' then (select s."tenant_id"::text from "better_supabase"."companies" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'person' then (select s."tenant_id"::text from "better_supabase"."people" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'deal' then (select s."tenant_id"::text from "better_supabase"."deals" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'course' then (select s."tenant_id"::text from "better_supabase"."courses" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'post' then (select s."tenant_id"::text from "better_supabase"."posts" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'engagement' then (select s."tenant_id"::text from "better_supabase"."engagements" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'work_item' then (select s."tenant_id"::text from "better_supabase"."work_items" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'employee' then (select s."tenant_id"::text from "better_supabase"."employees" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'ledger_account' then (select s."tenant_id"::text from "better_supabase"."ledger_accounts" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'product' then (select s."tenant_id"::text from "better_supabase"."products" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'product_variant' then (select s."tenant_id"::text from "better_supabase"."product_variants" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'calendar_event' then (select s."tenant_id"::text from "better_supabase"."calendar_events" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'asset' then (select s."tenant_id"::text from "better_supabase"."assets" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'asset_location' then (select s."tenant_id"::text from "better_supabase"."asset_locations" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'lease' then (select s."tenant_id"::text from "better_supabase"."lease_agreements" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'maintenance_request' then (select s."tenant_id"::text from "better_supabase"."maintenance_requests" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'expense_report' then (select s."tenant_id"::text from "better_supabase"."expense_reports" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'expense_line' then (select s."tenant_id"::text from "better_supabase"."expense_lines" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'donation_fund' then (select s."tenant_id"::text from "better_supabase"."donation_funds" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'work_order' then (select s."tenant_id"::text from "better_supabase"."work_orders" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'shipment' then (select s."tenant_id"::text from "better_supabase"."shipments" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'contract' then (select s."tenant_id"::text from "better_supabase"."contracts" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'control' then (select s."tenant_id"::text from "better_supabase"."controls" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'policy' then (select s."tenant_id"::text from "better_supabase"."policies" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'incident' then (select s."tenant_id"::text from "better_supabase"."incidents" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'document' then (select s."tenant_id"::text from "better_supabase"."documents" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'customer' then (select s."organization_id"::text from "public"."customers" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'drive_node' then (select s."tenant_id"::text from "better_supabase"."drive_nodes" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'application' then (select s."tenant_id"::text from "better_supabase"."applications" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'project' then (select s."organization_id"::text from "public"."projects" s where s."id" = (create_work_order.subject_id)::uuid)
      when 'task' then (select s."organization_id"::text from "public"."tasks" s where s."id" = (create_work_order.subject_id)::uuid)
      else null::text
    end) is distinct from create_work_order.tenant::text then
    raise exception 'the record does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_SUBJECT_NOT_FOUND';
  end if;
  if create_work_order.location_id is not null and not exists (
    select 1 from "better_supabase"."asset_locations" l
    where l."id" = create_work_order.location_id and l."tenant_id" = create_work_order.tenant
  ) then
    raise exception 'the location does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_LOCATION_NOT_FOUND';
  end if;
  if create_work_order.asset_id is not null and not exists (
    select 1 from "better_supabase"."assets" a
    where a."id" = create_work_order.asset_id and a."tenant_id" = create_work_order.tenant
  ) then
    raise exception 'the asset does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_ASSET_NOT_FOUND';
  end if;
  if create_work_order.booking_id is not null then
    select bk."during" into v_during from "better_supabase"."bookings" bk
      where bk."id" = create_work_order.booking_id and bk."tenant_id" = create_work_order.tenant;
    if not found then
      raise exception 'the booking does not exist in this organization' using errcode = 'P0002', hint = 'DISPATCH_BOOKING_NOT_FOUND';
    end if;
  end if;
  if create_work_order.booking_id is not null and v_starts is null then
    v_starts := lower(v_during);
    v_ends := upper(v_during);
  end if;
  if v_starts is not null then
    if create_work_order.technician is null then
      raise exception 'a scheduled work order needs a technician' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_REQUIRED';
    end if;
    v_ends := coalesce(v_ends, v_starts + '1 hour'::interval);
  if not coalesce(better_supabase.can_user(create_work_order.technician, 'tenant', create_work_order.tenant, 'dispatch.work'), false) then
    raise exception 'the technician is not a member who can do field work here' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_INVALID';
  end if;
  if v_ends <= v_starts then
    raise exception 'a slot ends after it starts' using errcode = '22023', hint = 'DISPATCH_SLOT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:dispatch:' || create_work_order.technician::text, 0));
  if exists (
    select 1 from "better_supabase"."work_orders" o
    where o."tenant_id" = create_work_order.tenant and o."technician_id" = create_work_order.technician
      and o."id" is distinct from null::uuid
      and o."status" in ('scheduled', 'en_route', 'on_site')
      and o."starts_at" < v_ends and o."ends_at" > v_starts
  ) then
    raise exception 'the technician already has a work order in that slot' using errcode = '23P01', hint = 'DISPATCH_SLOT_TAKEN';
  end if;
  elsif create_work_order.technician is not null
    and not coalesce(better_supabase.can_user(create_work_order.technician, 'tenant', create_work_order.tenant, 'dispatch.work'), false) then
    raise exception 'the technician is not a member who can do field work here' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_INVALID';
  end if;
  begin
    insert into "better_supabase"."work_orders" ("tenant_id", "title", "description", "priority", "status", "technician_id", "starts_at", "ends_at", "location_id", "asset_id", "booking_id", "subject_type", "subject_id", "address", "created_by")
    values (create_work_order.tenant, btrim(create_work_order.title), create_work_order.description, coalesce(create_work_order.priority, 'normal'),
      case when v_starts is null then 'unscheduled' else 'scheduled' end, create_work_order.technician, v_starts, v_ends,
      create_work_order.location_id, create_work_order.asset_id, create_work_order.booking_id,
      create_work_order.subject_type, create_work_order.subject_id, nullif(btrim(create_work_order.address), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation then
    raise exception 'a work order needs a title of 1 to 200 characters and a known priority' using errcode = '22023', hint = 'DISPATCH_INVALID';
  end;
  perform "better_supabase".emit_event('work_order.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'status', v_row."status", 'technicianId', v_row."technician_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.created',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'created work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'status', v_row."status", 'technicianId', v_row."technician_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id")
  );
  if v_row."status" = 'scheduled' then
    perform "better_supabase".emit_event('work_order.scheduled', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.scheduled',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'scheduled work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.dispatch_workflow_deliveries (
  batch integer DEFAULT 20
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_url text;
  v_secret text;
  v_job record;
  v_body jsonb;
  v_t text;
  v_job_header text;
  v_count integer := 0;
  -- pg_net is optional: http_post is looked up, not named, so plpgsql_check
  -- (supabase db lint) passes without the extension.
  v_post regprocedure := pg_catalog.to_regprocedure('net.http_post(text, jsonb, jsonb, jsonb, integer)');
begin
  if v_post is null then
    raise exception 'dispatch_workflow_deliveries needs pg_net: create extension pg_net, or deliver with the poll mode';
  end if;
  select ds.decrypted_secret into v_url from vault.decrypted_secrets ds where ds.name = 'workflow_flow_url';
  select ds.decrypted_secret into v_secret from vault.decrypted_secrets ds where ds.name = 'workflow_delivery_secret';
  if v_url is null or v_secret is null then
    raise exception 'Set the Vault secrets workflow_flow_url and workflow_delivery_secret before dispatching' using hint = 'WORKFLOW_DELIVERY_UNCONFIGURED';
  end if;
  for v_job in select * from "better_supabase"."claim_jobs"('workflow_deliveries', 60, greatest(coalesce(batch, 20), 1)) loop
    v_body := coalesce(v_job.message -> 'payload', '{}'::jsonb);
    v_t := floor(extract(epoch from now()))::bigint::text;
    v_job_header := 'workflow_deliveries' || ':' || v_job.id::text || ':' || v_job.attempts::text;
    execute format('select %s(url := $1, body := $2, headers := $3, timeout_milliseconds := $4)', v_post::oid::regproc)
      using v_url, v_body, jsonb_build_object(
        'content-type', 'application/json',
        'x-bsb-job', v_job_header,
        'x-bsb-signature', 't=' || v_t || ',v1=' || encode(extensions.hmac(v_t || '.' || v_job_header || '.' || v_body::text, v_secret, 'sha256'), 'hex')
      ), 30000;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_work_order (
  work_order_id uuid,
  technician    uuid,
  starts_at     timestamp with time zone,
  ends_at       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."work_orders"%rowtype;
  v_ends timestamptz := coalesce(schedule_work_order.ends_at, schedule_work_order.starts_at + '1 hour'::interval);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."work_orders" x where x."id" = schedule_work_order.work_order_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.manage'), false)) then
    raise exception 'work order not found' using errcode = 'P0002', hint = 'DISPATCH_NOT_FOUND';
  end if;
  if v_row."status" not in ('unscheduled', 'scheduled') then
    raise exception 'only a work order in the backlog or not started yet can be scheduled' using errcode = '55000', hint = 'DISPATCH_STATUS_INVALID';
  end if;
  if schedule_work_order.technician is null or schedule_work_order.starts_at is null then
    raise exception 'a scheduled work order needs a technician and a start' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_REQUIRED';
  end if;
  if not coalesce(better_supabase.can_user(schedule_work_order.technician, 'tenant', v_row."tenant_id", 'dispatch.work'), false) then
    raise exception 'the technician is not a member who can do field work here' using errcode = '22023', hint = 'DISPATCH_TECHNICIAN_INVALID';
  end if;
  if v_ends <= schedule_work_order.starts_at then
    raise exception 'a slot ends after it starts' using errcode = '22023', hint = 'DISPATCH_SLOT_INVALID';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb:dispatch:' || schedule_work_order.technician::text, 0));
  if exists (
    select 1 from "better_supabase"."work_orders" o
    where o."tenant_id" = v_row."tenant_id" and o."technician_id" = schedule_work_order.technician
      and o."id" is distinct from v_row."id"
      and o."status" in ('scheduled', 'en_route', 'on_site')
      and o."starts_at" < v_ends and o."ends_at" > schedule_work_order.starts_at
  ) then
    raise exception 'the technician already has a work order in that slot' using errcode = '23P01', hint = 'DISPATCH_SLOT_TAKEN';
  end if;
  if v_row."technician_id" is distinct from schedule_work_order.technician then
    delete from "better_supabase"."dispatch_route_stops" st where st."work_order_id" = v_row."id";
  end if;
  update "better_supabase"."work_orders" x set "status" = 'scheduled', "technician_id" = schedule_work_order.technician,
    "starts_at" = schedule_work_order.starts_at, "ends_at" = v_ends, "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  perform "better_supabase".emit_event('work_order.scheduled', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at"), 'work-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/dispatch');
  perform better_supabase.audit_event(
    event_type => 'work_order.scheduled',
    category => 'data',
    target_type => 'work_order',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'scheduled work order',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id"::text, 'title', v_row."title", 'description', v_row."description", 'priority', v_row."priority", 'status', v_row."status", 'technicianId', v_row."technician_id", 'startsAt', v_row."starts_at", 'endsAt', v_row."ends_at", 'day', (v_row."starts_at" at time zone 'UTC')::date, 'locationId', v_row."location_id", 'assetId', v_row."asset_id", 'bookingId', v_row."booking_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'address', v_row."address", 'enRouteAt', v_row."en_route_at", 'arrivedAt', v_row."arrived_at", 'completedAt', v_row."completed_at", 'cancelledAt', v_row."cancelled_at", 'cancelReason', v_row."cancel_reason", 'completionNote', v_row."completion_note", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_runs_alert()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_run "better_supabase"."workflow_runs"%rowtype := new;
  v_alert "better_supabase"."workflow_alerts"%rowtype;
  v_fired integer := 0;
begin
  if new."mode" = 'test' or new."status" <> 'failed' or (tg_op = 'UPDATE' and old."status" = 'failed') then
    return null;
  end if;
  for v_alert in
    select * from "better_supabase"."workflow_alerts" x
    where x."on_event" = 'failed' and x."definition_id"::text = new."attributes" ->> 'bsb.definition'
  loop
    insert into "better_supabase"."workflow_alert_fires" ("alert_id", "run_id") values (v_alert."id", v_run."id")
      on conflict do nothing;
      if found then
        v_fired := v_fired + 1;
        perform "better_supabase".emit_event('workflow_alert.triggered', jsonb_build_object('alertId', v_alert."id", 'organizationId', v_run."tenant_id"::text, 'definition', v_alert."definition_id", 'onEvent', v_alert."on_event", 'channel', v_alert."channel", 'runId', v_run."id", 'status', v_run."status", 'error', v_run."error"), 'workflow-runs/' || v_run."id", (v_run."tenant_id")::text, 'workflow_alert.triggered:' || v_alert."id" || ':' || v_run."id", 'better-supabase/workflow-builder');
      end if;
  end loop;
  return null;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.workflow_sdk_mirror_run()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
  v_actor uuid;
  v_subject text;
  v_subject_type text;
  v_subject_id text;
  v_principal_kind text;
  v_mode text;
begin
  begin
    v_tenant := (new.attributes ->> 'bsb.tenant')::uuid;
  exception when others then
    v_tenant := null;
  end;
  begin
    v_actor := (new.attributes ->> 'bsb.actor')::uuid;
  exception when others then
    v_actor := null;
  end;
  v_principal_kind := new.attributes ->> 'bsb.principal_kind';
  if v_principal_kind is not null and v_principal_kind not in ('user', 'service_principal', 'system', 'external') then
    v_principal_kind := null;
  end if;
  if v_tenant is not null and v_actor is not null and v_principal_kind is null
    and not coalesce(better_supabase.can_user(v_actor, 'tenant', v_tenant, 'workflow.run'), false) then
    v_tenant := null;
  end if;
  v_subject := new.attributes ->> 'bsb.subject';
  if v_subject is not null and position('/' in v_subject) between 2 and 101
    and length(v_subject) - position('/' in v_subject) between 1 and 200 then
    v_subject_type := left(v_subject, position('/' in v_subject) - 1);
    v_subject_id := substr(v_subject, position('/' in v_subject) + 1);
  end if;
  v_mode := case when new.attributes ->> 'bsb.mode' = 'test' then 'test' else 'live' end;
  perform "better_supabase"."record_workflow_run"(
    'workflow-sdk',
    new.id,
    new.name,
    case new.status::text when 'pending' then 'queued' else new.status::text end,
    v_tenant,
    v_actor,
    coalesce(new.attributes, '{}'::jsonb) - 'bsb.tenant' - 'bsb.actor' - 'bsb.subject' - 'bsb.principal_kind' - 'bsb.principal' - 'bsb.mode' - 'bsb.trigger_node',
    case when new.status::text = 'failed' then coalesce(new.error_code, left(new.error, 4000)) end,
    new.started_at at time zone 'UTC',
    new.completed_at at time zone 'UTC',
    v_subject_type,
    v_subject_id,
    v_principal_kind,
    case when v_principal_kind is null then null else nullif(left(new.attributes ->> 'bsb.principal', 200), '') end,
    v_mode,
    nullif(left(new.attributes ->> 'bsb.trigger_node', 100), '')
  );
  return null;
end;
$function$;

CREATE POLICY "bs_realtime_tables_receive" ON "realtime"."messages"
  FOR SELECT
  TO "authenticated"
  USING
    (((EXTENSION = 'broadcast'::text) AND (( SELECT realtime.topic() AS topic) ~~ 'bsb:t:%'::text) AND (NOT COALESCE(((( SELECT auth.jwt() AS jwt) ->>
    'is_anonymous'::text))::boolean,
    false)) AND
    ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = ''::text) OR ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 5) = ''::text) AND (split_part((
    SELECT realtime.topic() AS topic),
    ':'::text,
    4) = COALESCE((( SELECT auth.jwt() AS jwt) ->> 'tenant_id'::text), ((( SELECT auth.jwt() AS jwt) -> 'app_metadata'::text) ->> 'tenant_id'::text), ''::text))) OR
    ((split_part(( SELECT realtime.topic() AS topic), ':'::text, 4) = 'u'::text) AND (split_part(( SELECT realtime.topic() AS topic), ':'::text, 5) = (( SELECT auth.uid() AS
    uid))::text)))));
