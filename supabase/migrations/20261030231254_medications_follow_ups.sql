SET local check_function_bodies = off;

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_administrations";

DROP POLICY "medication_administrations_read" ON "better_supabase"."medication_administrations";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_orders";

DROP POLICY "medication_orders_read" ON "better_supabase"."medication_orders";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."medications";

DROP POLICY "medications_read" ON "better_supabase"."medications";

DROP FUNCTION "api"."record_medication_administration"(uuid, text, numeric, text, uuid, text);

DROP FUNCTION "better_supabase"."record_medication_administration"(uuid, text, numeric, text, uuid, text);

ALTER TABLE "better_supabase"."medication_administrations"
  ADD COLUMN "signature_id" uuid;

ALTER TABLE "better_supabase"."medication_orders"
  ADD COLUMN "signature_id" uuid;

CREATE OR REPLACE FUNCTION api.approve_medication_order (
  order_id     uuid,
  signature_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."approve_medication_order"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.record_medication_administration (
  administration_id uuid,
  status            text,
  dose              numeric DEFAULT NULL::numeric,
  reason            text    DEFAULT NULL::text,
  checked_by        uuid    DEFAULT NULL::uuid,
  note              text    DEFAULT NULL::text,
  signature_id      uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."record_medication_administration"($1, $2, $3, $4, $5, $6, $7) $function$;

CREATE OR REPLACE FUNCTION better_supabase.approve_medication_order (
  order_id     uuid,
  signature_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = approve_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if approve_medication_order.signature_id is null then
    raise exception 'approving an order needs a signature' using errcode = '22023', hint = 'MEDICATION_SIGNATURE_INVALID';
  end if;
  if approve_medication_order.signature_id is not null and not exists (
    select 1 from "better_supabase"."signatures" sg
    join "better_supabase"."signature_requests" sr on sr."id" = sg."request_id"
    where sg."id" = approve_medication_order.signature_id
      and sg."signer" = (select auth.uid())
      and sr."status" = 'completed'
      and sr."tenant_id" = v_row."tenant_id"
      and sr."subject_type" = 'medication_order'
      and sr."subject_id" = v_row."id"::text
  ) then
    raise exception 'the signature isn''t your completed signature on this record' using errcode = '22023', hint = 'MEDICATION_SIGNATURE_INVALID';
  end if;
  update "better_supabase"."medication_orders" x set "signature_id" = approve_medication_order.signature_id, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  perform "better_supabase".emit_event('medication_order.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.updated',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication order approved',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'signatureId', v_row."signature_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.import_medication_orders (
  tenant uuid,
  items  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_medication "better_supabase"."medications"%rowtype;
  v_item jsonb;
  v_external text;
  v_created jsonb := '[]'::jsonb;
  v_skipped integer := 0;
  v_name text;
  v_med_unit text;
  v_system text;
  v_code text;
  v_form text;
  v_strength text;
  v_high_risk boolean;
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;
begin
  if import_medication_orders.items is null or jsonb_typeof(import_medication_orders.items) <> 'array' then
    raise exception 'items is an array' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  for v_item in select value from jsonb_array_elements(import_medication_orders.items) loop
    if jsonb_typeof(v_item) <> 'object' then
      raise exception 'each item is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    v_external := nullif(trim(v_item ->> 'externalId'), '');
    if v_external is null then
      raise exception 'each imported order needs an externalId' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if exists (select 1 from "better_supabase"."medication_orders" x where x."tenant_id" = import_medication_orders.tenant and x."external_id" = v_external) then
      v_skipped := v_skipped + 1;
      continue;
    end if;
    if not (case (v_item ->> 'subjectType')
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."organization_id"::text = import_medication_orders.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."tenant_id"::text = import_medication_orders.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."organization_id"::text = import_medication_orders.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."organization_id"::text = import_medication_orders.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ((v_item ->> 'subjectId'))::uuid and s."organization_id"::text = import_medication_orders.tenant::text)
      else false
    end and "better_supabase"."can_subject"((v_item ->> 'subjectType'), (v_item ->> 'subjectId'), 'read')) then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if jsonb_typeof(v_item -> 'medication') = 'object' then
      v_name := nullif(trim((v_item -> 'medication') ->> 'name'), '');
  v_med_unit := nullif(trim((v_item -> 'medication') ->> 'unit'), '');
  v_system := coalesce(nullif(trim((v_item -> 'medication') ->> 'codeSystem'), ''), 'custom');
  v_code := nullif(trim((v_item -> 'medication') ->> 'code'), '');
  v_form := nullif(trim((v_item -> 'medication') ->> 'form'), '');
  v_strength := nullif(trim((v_item -> 'medication') ->> 'strength'), '');
  v_high_risk := coalesce(((v_item -> 'medication') ->> 'highRisk')::boolean, false);
  if v_name is null or length(v_name) > 300 then
    raise exception 'a medication needs a name of at most 300 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_med_unit is null or length(v_med_unit) > 50 then
    raise exception 'a medication needs a unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system is null or v_system not in ('gtin', 'hpk', 'atc', 'rxnorm', 'custom') then
    raise exception 'code_system is gtin, hpk, atc, rxnorm or custom' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_code is not null and length(v_code) > 100 then
    raise exception 'a code is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if v_system <> 'custom' and v_code is null then
    raise exception 'a medication from a catalog needs its code' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  if coalesce(length(v_form), 0) > 100 or coalesce(length(v_strength), 0) > 100 then
    raise exception 'form and strength are at most 100 characters' using errcode = '22023', hint = 'MEDICATION_INVALID';
  end if;
  select * into v_medication from "better_supabase"."medications" x
  where x."tenant_id" = import_medication_orders.tenant and x."code_system" = v_system and x."code" = v_code
  for update;
  if found then
    update "better_supabase"."medications" x set
    "name" = v_name,
    "code_system" = v_system,
    "code" = v_code,
    "form" = v_form,
    "strength" = v_strength,
    "unit" = v_med_unit,
    "high_risk" = v_high_risk,
    "updated_at" = now()
    where x."id" = v_medication."id"
    returning x.* into v_medication;
  else
    insert into "better_supabase"."medications" ("tenant_id", "name", "code_system", "code", "form", "strength", "unit", "high_risk")
    values (import_medication_orders.tenant, v_name, v_system, v_code, v_form, v_strength, v_med_unit, v_high_risk)
    returning * into v_medication;
  end if;
    else
      select * into v_medication from "better_supabase"."medications" x
      where x."id" = (v_item ->> 'medicationId')::uuid and x."tenant_id" = import_medication_orders.tenant;
      if not found then
        raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
      end if;
    end if;
    v_dose := case when v_item ? 'dose' then ((v_item -> 'dose') #>> '{}')::numeric else null end;
  v_unit := case when v_item ? 'doseUnit' then nullif(trim((v_item -> 'doseUnit') #>> '{}'), '') else v_medication."unit" end;
  v_route := case when v_item ? 'route' then nullif(trim((v_item -> 'route') #>> '{}'), '') else null end;
  v_schedule := case when v_item ? 'schedule' then nullif((v_item -> 'schedule'), 'null'::jsonb) else null end;
  v_as_needed := coalesce(case when v_item ? 'asNeeded' then ((v_item -> 'asNeeded') #>> '{}')::boolean else null end, false);
  v_as_needed_reason := case when v_item ? 'asNeededReason' then nullif(trim((v_item -> 'asNeededReason') #>> '{}'), '') else null end;
  v_max := case when v_item ? 'maxPerDay' then ((v_item -> 'maxPerDay') #>> '{}')::numeric else null end;
  v_starts := case when v_item ? 'startsOn' then ((v_item -> 'startsOn') #>> '{}')::date else (now() at time zone 'UTC')::date end;
  v_ends := case when v_item ? 'endsOn' then ((v_item -> 'endsOn') #>> '{}')::date else null end;
  v_prescriber := case when v_item ? 'prescriber' then nullif(trim((v_item -> 'prescriber') #>> '{}'), '') else null end;
  v_double := coalesce(case when v_item ? 'requiresDoubleCheck' then ((v_item -> 'requiresDoubleCheck') #>> '{}')::boolean else null end, false);
    if v_dose is null or v_dose <= 0 then
    raise exception 'an order needs a dose above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_unit is null or length(v_unit) > 50 then
    raise exception 'an order needs a dose unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_route is not null and length(v_route) > 100 then
    raise exception 'route is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if not v_as_needed and v_schedule is null then
    raise exception 'an order needs a schedule unless it is given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_schedule is not null then
    if jsonb_typeof(v_schedule) <> 'object' or not (v_schedule ? 'times' or v_schedule ? 'everyHours') then
      raise exception 'a schedule is an object with times or everyHours' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'times' and (jsonb_typeof(v_schedule -> 'times') <> 'array' or jsonb_array_length(v_schedule -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      raise exception 'schedule times are HH:MM strings' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'everyHours' and (jsonb_typeof(v_schedule -> 'everyHours') <> 'number' or (v_schedule ->> 'everyHours') !~ '^[0-9]+$' or (v_schedule ->> 'everyHours')::integer not between 1 and 24) then
      raise exception 'schedule everyHours is a whole number of hours from 1 to 24' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'startTime' and (jsonb_typeof(v_schedule -> 'startTime') <> 'string' or (v_schedule ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      raise exception 'schedule startTime is an HH:MM string' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'weekdays' and (jsonb_typeof(v_schedule -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      raise exception 'schedule weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
  end if;
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    raise exception 'asNeededReason is at most 500 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_max is not null and v_max <= 0 then
    raise exception 'maxPerDay is above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an order needs a start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an order ends on or after its start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_prescriber is not null and length(v_prescriber) > 300 then
    raise exception 'prescriber is at most 300 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
    
    insert into "better_supabase"."medication_orders" ("tenant_id", "subject_type", "subject_id", "medication_id", "dose", "dose_unit", "route", "schedule", "as_needed", "as_needed_reason", "max_per_day", "starts_on", "ends_on", "prescriber", "source", "external_id", "requires_double_check", "created_by")
    values (import_medication_orders.tenant, v_item ->> 'subjectType', v_item ->> 'subjectId', v_medication."id", v_dose, v_unit, v_route, v_schedule, v_as_needed, v_as_needed_reason, v_max, v_starts, v_ends, v_prescriber, coalesce(nullif(v_item ->> 'source', ''), 'import'), v_external, v_double, (select auth.uid()))
    returning * into v_row;
    perform "better_supabase".emit_event('medication_order.created', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.created',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication prescribed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
    v_created := v_created || jsonb_build_array(jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'signatureId', v_row."signature_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at"));
  end loop;
  return jsonb_build_object('created', v_created, 'skipped', v_skipped);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.medication_chart (
  subject_type text,
  subject_id   text,
  since        timestamp with time zone DEFAULT NULL::timestamp WITH time zone,
  until        timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with bounds as (
    select
      coalesce(medication_chart.since, (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')) as since,
      coalesce(medication_chart.until, ((date_trunc('day', now() at time zone 'UTC') + interval '1 day') at time zone 'UTC')) as until
  )
  select jsonb_build_object(
    'since', b.since,
    'until', b.until,
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'medicationId', x."medication_id", 'dose', x."dose", 'doseUnit', x."dose_unit", 'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed", 'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'prescriber', x."prescriber", 'source', x."source", 'externalId', x."external_id", 'requiresDoubleCheck', x."requires_double_check", 'status', x."status", 'stoppedReason', x."stopped_reason", 'signatureId', x."signature_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('medication', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'name', y."name", 'codeSystem', y."code_system", 'code', y."code", 'form', y."form", 'strength', y."strength", 'unit', y."unit", 'highRisk', y."high_risk", 'archivedAt', y."archived_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on", x."id")
      from "better_supabase"."medication_orders" x
      join "better_supabase"."medications" y on y."tenant_id" = x."tenant_id" and y."id" = x."medication_id"
      where x."subject_type" = medication_chart.subject_type
        and x."subject_id" = medication_chart.subject_id
        and x."starts_on" <= (b.until at time zone 'UTC')::date
        and (x."ends_on" is null or x."ends_on" >= (b.since at time zone 'UTC')::date)
    ), '[]'::jsonb),
    'administrations', coalesce((
      select jsonb_agg(jsonb_build_object('id', z."id", 'organizationId', z."tenant_id", 'orderId', z."order_id", 'scheduledAt', z."scheduled_at", 'administeredAt', z."administered_at", 'status', z."status", 'dose', z."dose", 'performerId', z."performer_id", 'checkedBy', z."checked_by", 'reason', z."reason", 'note', z."note", 'signatureId', z."signature_id") order by coalesce(z."scheduled_at", z."administered_at"), z."id")
      from "better_supabase"."medication_administrations" z
      join "better_supabase"."medication_orders" x on x."tenant_id" = z."tenant_id" and x."id" = z."order_id"
      where x."subject_type" = medication_chart.subject_type
        and x."subject_id" = medication_chart.subject_id
        and coalesce(z."scheduled_at", z."administered_at") >= b.since
        and coalesce(z."scheduled_at", z."administered_at") < b.until
    ), '[]'::jsonb)
  )
  from bounds b
$function$;

CREATE OR REPLACE FUNCTION better_supabase.medication_orders_of (
  subject_type    text,
  subject_id      text,
  include_stopped boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'medicationId', x."medication_id", 'dose', x."dose", 'doseUnit', x."dose_unit", 'route', x."route", 'schedule', x."schedule", 'asNeeded', x."as_needed", 'asNeededReason', x."as_needed_reason", 'maxPerDay', x."max_per_day", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'prescriber', x."prescriber", 'source', x."source", 'externalId', x."external_id", 'requiresDoubleCheck', x."requires_double_check", 'status', x."status", 'stoppedReason', x."stopped_reason", 'signatureId', x."signature_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('medication', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'name', y."name", 'codeSystem', y."code_system", 'code', y."code", 'form', y."form", 'strength', y."strength", 'unit', y."unit", 'highRisk', y."high_risk", 'archivedAt', y."archived_at", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."medication_orders" x
  join "better_supabase"."medications" y on y."tenant_id" = x."tenant_id" and y."id" = x."medication_id"
  where x."subject_type" = medication_orders_of.subject_type
    and x."subject_id" = medication_orders_of.subject_id
    and (coalesce(medication_orders_of.include_stopped, false) or x."status" <> 'stopped')
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pause_medication_order (
  order_id uuid,
  paused   boolean DEFAULT true
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_status text := case when coalesce(pause_medication_order.paused, true) then 'paused' else 'active' end;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = pause_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_row."status" = 'stopped' then
    raise exception 'the medication order is stopped' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if v_row."status" = v_status then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'signatureId', v_row."signature_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."medication_orders" x set "status" = v_status, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  if v_status = 'paused' then
    delete from "better_supabase"."medication_administrations" x where x."order_id" = v_row."id" and x."status" = 'planned' and x."scheduled_at" > now();
    perform "better_supabase".emit_event('medication_order.paused', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.paused',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication order paused',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  else
    perform "better_supabase".emit_event('medication_order.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.updated',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication order resumed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'signatureId', v_row."signature_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.prescribe_medication (
  tenant        uuid,
  subject_type  text,
  subject_id    text,
  medication_id uuid,
  attrs         jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_medication "better_supabase"."medications"%rowtype;
  v_attrs jsonb := coalesce(prescribe_medication.attrs, '{}'::jsonb);
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', prescribe_medication.tenant, 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if not (case prescribe_medication.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (prescribe_medication.subject_id)::uuid and s."organization_id"::text = prescribe_medication.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (prescribe_medication.subject_id)::uuid and s."tenant_id"::text = prescribe_medication.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (prescribe_medication.subject_id)::uuid and s."organization_id"::text = prescribe_medication.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (prescribe_medication.subject_id)::uuid and s."organization_id"::text = prescribe_medication.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (prescribe_medication.subject_id)::uuid and s."organization_id"::text = prescribe_medication.tenant::text)
      else false
    end and "better_supabase"."can_subject"(prescribe_medication.subject_type, prescribe_medication.subject_id, 'read')) then
    raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  select * into v_medication from "better_supabase"."medications" x
  where x."id" = prescribe_medication.medication_id and x."tenant_id" = prescribe_medication.tenant and x."archived_at" is null;
  if not found then
    raise exception 'medication not found' using errcode = 'P0002', hint = 'MEDICATION_NOT_FOUND';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  v_dose := case when v_attrs ? 'dose' then ((v_attrs -> 'dose') #>> '{}')::numeric else null end;
  v_unit := case when v_attrs ? 'doseUnit' then nullif(trim((v_attrs -> 'doseUnit') #>> '{}'), '') else v_medication."unit" end;
  v_route := case when v_attrs ? 'route' then nullif(trim((v_attrs -> 'route') #>> '{}'), '') else null end;
  v_schedule := case when v_attrs ? 'schedule' then nullif((v_attrs -> 'schedule'), 'null'::jsonb) else null end;
  v_as_needed := coalesce(case when v_attrs ? 'asNeeded' then ((v_attrs -> 'asNeeded') #>> '{}')::boolean else null end, false);
  v_as_needed_reason := case when v_attrs ? 'asNeededReason' then nullif(trim((v_attrs -> 'asNeededReason') #>> '{}'), '') else null end;
  v_max := case when v_attrs ? 'maxPerDay' then ((v_attrs -> 'maxPerDay') #>> '{}')::numeric else null end;
  v_starts := case when v_attrs ? 'startsOn' then ((v_attrs -> 'startsOn') #>> '{}')::date else (now() at time zone 'UTC')::date end;
  v_ends := case when v_attrs ? 'endsOn' then ((v_attrs -> 'endsOn') #>> '{}')::date else null end;
  v_prescriber := case when v_attrs ? 'prescriber' then nullif(trim((v_attrs -> 'prescriber') #>> '{}'), '') else null end;
  v_double := coalesce(case when v_attrs ? 'requiresDoubleCheck' then ((v_attrs -> 'requiresDoubleCheck') #>> '{}')::boolean else null end, false);
  if v_dose is null or v_dose <= 0 then
    raise exception 'an order needs a dose above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_unit is null or length(v_unit) > 50 then
    raise exception 'an order needs a dose unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_route is not null and length(v_route) > 100 then
    raise exception 'route is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if not v_as_needed and v_schedule is null then
    raise exception 'an order needs a schedule unless it is given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_schedule is not null then
    if jsonb_typeof(v_schedule) <> 'object' or not (v_schedule ? 'times' or v_schedule ? 'everyHours') then
      raise exception 'a schedule is an object with times or everyHours' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'times' and (jsonb_typeof(v_schedule -> 'times') <> 'array' or jsonb_array_length(v_schedule -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      raise exception 'schedule times are HH:MM strings' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'everyHours' and (jsonb_typeof(v_schedule -> 'everyHours') <> 'number' or (v_schedule ->> 'everyHours') !~ '^[0-9]+$' or (v_schedule ->> 'everyHours')::integer not between 1 and 24) then
      raise exception 'schedule everyHours is a whole number of hours from 1 to 24' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'startTime' and (jsonb_typeof(v_schedule -> 'startTime') <> 'string' or (v_schedule ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      raise exception 'schedule startTime is an HH:MM string' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'weekdays' and (jsonb_typeof(v_schedule -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      raise exception 'schedule weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
  end if;
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    raise exception 'asNeededReason is at most 500 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_max is not null and v_max <= 0 then
    raise exception 'maxPerDay is above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an order needs a start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an order ends on or after its start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_prescriber is not null and length(v_prescriber) > 300 then
    raise exception 'prescriber is at most 300 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_order_prescribe"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using prescribe_medication.tenant, prescribe_medication.subject_type, prescribe_medication.subject_id, prescribe_medication.medication_id;
    end if;
  end;
  insert into "better_supabase"."medication_orders" ("tenant_id", "subject_type", "subject_id", "medication_id", "dose", "dose_unit", "route", "schedule", "as_needed", "as_needed_reason", "max_per_day", "starts_on", "ends_on", "prescriber", "source", "external_id", "requires_double_check", "created_by")
    values (prescribe_medication.tenant, prescribe_medication.subject_type, prescribe_medication.subject_id, v_medication."id", v_dose, v_unit, v_route, v_schedule, v_as_needed, v_as_needed_reason, v_max, v_starts, v_ends, v_prescriber, 'prescriber', null, v_double, (select auth.uid()))
    returning * into v_row;
  perform "better_supabase".emit_event('medication_order.created', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.created',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication prescribed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_order_prescribe"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'signatureId', v_row."signature_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_as_needed_administration (
  order_id   uuid,
  dose       numeric DEFAULT NULL::numeric,
  reason     text    DEFAULT NULL::text,
  checked_by uuid    DEFAULT NULL::uuid,
  note       text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_administrations"%rowtype;
  v_order "better_supabase"."medication_orders"%rowtype;
  v_reason text := nullif(trim(record_as_needed_administration.reason), '');
  v_dose numeric;
  v_given numeric;
  v_today date := (now() at time zone 'UTC')::date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."id" = record_as_needed_administration.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_order."tenant_id", 'medications.administer'), false) and coalesce("better_supabase"."can_subject"(v_order."subject_type", v_order."subject_id", 'read'), false))) then
    raise exception 'not allowed to administer medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if not v_order."as_needed" then
    raise exception 'the order isn''t given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_order."status" <> 'active' or v_order."starts_on" > v_today or v_order."ends_on" < v_today then
    raise exception 'the medication order isn''t active' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if v_reason is null then
    raise exception 'an as-needed dose needs the reason it was given' using errcode = '22023', hint = 'MEDICATION_REASON_REQUIRED';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  v_dose := coalesce(record_as_needed_administration.dose, v_order."dose");
  if v_dose <= 0 then
    raise exception 'a dose is above zero' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_order."max_per_day" is not null then
    select coalesce(sum(x."dose"), 0) into v_given from "better_supabase"."medication_administrations" x
    where x."order_id" = v_order."id" and x."status" = 'given' and x."administered_at" > now() - interval '24 hours';
    if v_given + v_dose > v_order."max_per_day" then
      raise exception 'this dose goes over the most the order allows in 24 hours' using errcode = '22023', hint = 'MEDICATION_MAX_DOSE_EXCEEDED';
    end if;
  end if;
  if (coalesce((select y."high_risk" from "better_supabase"."medications" y where y."tenant_id" = v_order."tenant_id" and y."id" = v_order."medication_id"), false) or v_order."requires_double_check") then
    if record_as_needed_administration.checked_by is null then
      raise exception 'this dose needs a second member to check it' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
    if record_as_needed_administration.checked_by = (select auth.uid()) then
      raise exception 'the second check is by another member' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_SELF';
    end if;
    if not coalesce(coalesce(better_supabase.can_user(record_as_needed_administration.checked_by, 'tenant', v_order."tenant_id", 'medications.administer'), false), false) then
      raise exception 'the member who checks may administer medication in this organization' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_administration_record"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_order."id", 'given';
    end if;
  end;
  insert into "better_supabase"."medication_administrations" ("tenant_id", "order_id", "administered_at", "status", "dose", "performer_id", "checked_by", "reason", "note")
  values (v_order."tenant_id", v_order."id", now(), 'given', v_dose, (select auth.uid()), record_as_needed_administration.checked_by, v_reason, nullif(trim(record_as_needed_administration.note), ''))
  returning * into v_row;
  perform "better_supabase".emit_event('medication_administration.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at"), 'medication-orders/' || v_row."order_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_administration.recorded',
    category => 'data',
    target_type => 'medication_administration',
    record_id => v_row."id"::text,
    summary => 'Medication dose recorded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_administration_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at", 'status', v_row."status", 'dose', v_row."dose", 'performerId', v_row."performer_id", 'checkedBy', v_row."checked_by", 'reason', v_row."reason", 'note', v_row."note", 'signatureId', v_row."signature_id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.record_medication_administration (
  administration_id uuid,
  status            text,
  dose              numeric DEFAULT NULL::numeric,
  reason            text    DEFAULT NULL::text,
  checked_by        uuid    DEFAULT NULL::uuid,
  note              text    DEFAULT NULL::text,
  signature_id      uuid    DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_administrations"%rowtype;
  v_order "better_supabase"."medication_orders"%rowtype;
  v_status text := lower(trim(record_medication_administration.status));
  v_reason text := nullif(trim(record_medication_administration.reason), '');
  v_dose numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_administrations" x where x."id" = record_medication_administration.administration_id for update;
  if not found then
    raise exception 'medication dose not found' using errcode = 'P0002', hint = 'MEDICATION_ADMINISTRATION_NOT_FOUND';
  end if;
  select * into v_order from "better_supabase"."medication_orders" x where x."id" = v_row."order_id";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_order."tenant_id", 'medications.administer'), false) and coalesce("better_supabase"."can_subject"(v_order."subject_type", v_order."subject_id", 'read'), false))) then
    raise exception 'not allowed to administer medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_status is null or v_status not in ('given', 'refused', 'skipped') then
    raise exception 'a dose is recorded as given, refused or skipped' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_row."status" not in ('planned', 'missed') then
    raise exception 'the dose is already recorded' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_order."status" <> 'active' then
    raise exception 'the medication order isn''t active' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if v_status in ('refused', 'skipped') and v_reason is null then
    raise exception 'a refused or skipped dose needs a reason' using errcode = '22023', hint = 'MEDICATION_REASON_REQUIRED';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
  end if;
  if v_status = 'given' then
    v_dose := coalesce(record_medication_administration.dose, v_row."dose", v_order."dose");
    if v_dose <= 0 then
      raise exception 'a dose is above zero' using errcode = '22023', hint = 'MEDICATION_ADMINISTRATION_INVALID';
    end if;
    if (coalesce((select y."high_risk" from "better_supabase"."medications" y where y."tenant_id" = v_order."tenant_id" and y."id" = v_order."medication_id"), false) or v_order."requires_double_check") then
    if record_medication_administration.checked_by is null then
      raise exception 'this dose needs a second member to check it' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
    if record_medication_administration.checked_by = (select auth.uid()) then
      raise exception 'the second check is by another member' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_SELF';
    end if;
    if not coalesce(coalesce(better_supabase.can_user(record_medication_administration.checked_by, 'tenant', v_order."tenant_id", 'medications.administer'), false), false) then
      raise exception 'the member who checks may administer medication in this organization' using errcode = '22023', hint = 'MEDICATION_DOUBLE_CHECK_REQUIRED';
    end if;
  end if;
  end if;
  if record_medication_administration.signature_id is not null and not exists (
    select 1 from "better_supabase"."signatures" sg
    join "better_supabase"."signature_requests" sr on sr."id" = sg."request_id"
    where sg."id" = record_medication_administration.signature_id
      and sg."signer" = (select auth.uid())
      and sr."status" = 'completed'
      and sr."tenant_id" = v_order."tenant_id"
      and sr."subject_type" = 'medication_administration'
      and sr."subject_id" = v_row."id"::text
  ) then
    raise exception 'the signature isn''t your completed signature on this record' using errcode = '22023', hint = 'MEDICATION_SIGNATURE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_administration_record"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_order."id", v_status;
    end if;
  end;
  update "better_supabase"."medication_administrations" x set
    "status" = v_status,
    "administered_at" = now(),
    "dose" = case when v_status = 'given' then v_dose else x."dose" end,
    "performer_id" = (select auth.uid()),
    "checked_by" = case when v_status = 'given' then record_medication_administration.checked_by end,
    "reason" = v_reason, "note" = nullif(trim(record_medication_administration.note), ''),
    "signature_id" = record_medication_administration.signature_id
  where x."id" = v_row."id"
  returning x.* into v_row;
  perform "better_supabase".emit_event('medication_administration.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at"), 'medication-orders/' || v_row."order_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_administration.recorded',
    category => 'data',
    target_type => 'medication_administration',
    record_id => v_row."id"::text,
    summary => 'Medication dose recorded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."order_id", 'medicationAdministrationId', v_row."id", 'subjectType', v_order."subject_type", 'subjectId', v_order."subject_id", 'status', v_row."status", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_administration_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'orderId', v_row."order_id", 'scheduledAt', v_row."scheduled_at", 'administeredAt', v_row."administered_at", 'status', v_row."status", 'dose', v_row."dose", 'performerId', v_row."performer_id", 'checkedBy', v_row."checked_by", 'reason', v_row."reason", 'note', v_row."note", 'signatureId', v_row."signature_id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.stop_medication_order (
  order_id uuid,
  reason   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_reason text := nullif(trim(stop_medication_order.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = stop_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_reason is null then
    raise exception 'stopping an order needs a reason' using errcode = '22023', hint = 'MEDICATION_REASON_REQUIRED';
  end if;
  if length(v_reason) > 1000 then
    raise exception 'a reason is at most 1000 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_row."status" = 'stopped' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'signatureId', v_row."signature_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_medication_order_stop"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."medication_orders" x set "status" = 'stopped', "stopped_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  delete from "better_supabase"."medication_administrations" x where x."order_id" = v_row."id" and x."status" = 'planned' and x."scheduled_at" > now();
  perform "better_supabase".emit_event('medication_order.stopped', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'reason', v_reason), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.stopped',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication order stopped',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'reason', v_reason)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_medication_order_stop"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'signatureId', v_row."signature_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_medication_order (
  order_id uuid,
  attrs    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."medication_orders"%rowtype;
  v_attrs jsonb := coalesce(update_medication_order.attrs, '{}'::jsonb);
  v_dose numeric;
  v_unit text;
  v_route text;
  v_schedule jsonb;
  v_as_needed boolean;
  v_as_needed_reason text;
  v_max numeric;
  v_starts date;
  v_ends date;
  v_prescriber text;
  v_double boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."medication_orders" x where x."id" = update_medication_order.order_id for update;
  if not found then
    raise exception 'medication order not found' using errcode = 'P0002', hint = 'MEDICATION_ORDER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'medications.prescribe'), false)) then
    raise exception 'not allowed to prescribe medication' using errcode = '42501', hint = 'MEDICATION_FORBIDDEN';
  end if;
  if v_row."status" = 'stopped' then
    raise exception 'the medication order is stopped' using errcode = '22023', hint = 'MEDICATION_ORDER_INACTIVE';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  v_dose := case when v_attrs ? 'dose' then ((v_attrs -> 'dose') #>> '{}')::numeric else v_row."dose" end;
  v_unit := case when v_attrs ? 'doseUnit' then nullif(trim((v_attrs -> 'doseUnit') #>> '{}'), '') else v_row."dose_unit" end;
  v_route := case when v_attrs ? 'route' then nullif(trim((v_attrs -> 'route') #>> '{}'), '') else v_row."route" end;
  v_schedule := case when v_attrs ? 'schedule' then nullif((v_attrs -> 'schedule'), 'null'::jsonb) else v_row."schedule" end;
  v_as_needed := coalesce(case when v_attrs ? 'asNeeded' then ((v_attrs -> 'asNeeded') #>> '{}')::boolean else v_row."as_needed" end, false);
  v_as_needed_reason := case when v_attrs ? 'asNeededReason' then nullif(trim((v_attrs -> 'asNeededReason') #>> '{}'), '') else v_row."as_needed_reason" end;
  v_max := case when v_attrs ? 'maxPerDay' then ((v_attrs -> 'maxPerDay') #>> '{}')::numeric else v_row."max_per_day" end;
  v_starts := case when v_attrs ? 'startsOn' then ((v_attrs -> 'startsOn') #>> '{}')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then ((v_attrs -> 'endsOn') #>> '{}')::date else v_row."ends_on" end;
  v_prescriber := case when v_attrs ? 'prescriber' then nullif(trim((v_attrs -> 'prescriber') #>> '{}'), '') else v_row."prescriber" end;
  v_double := coalesce(case when v_attrs ? 'requiresDoubleCheck' then ((v_attrs -> 'requiresDoubleCheck') #>> '{}')::boolean else v_row."requires_double_check" end, false);
  if v_dose is null or v_dose <= 0 then
    raise exception 'an order needs a dose above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_unit is null or length(v_unit) > 50 then
    raise exception 'an order needs a dose unit of at most 50 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_route is not null and length(v_route) > 100 then
    raise exception 'route is at most 100 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if not v_as_needed and v_schedule is null then
    raise exception 'an order needs a schedule unless it is given as needed' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_schedule is not null then
    if jsonb_typeof(v_schedule) <> 'object' or not (v_schedule ? 'times' or v_schedule ? 'everyHours') then
      raise exception 'a schedule is an object with times or everyHours' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'times' and (jsonb_typeof(v_schedule -> 'times') <> 'array' or jsonb_array_length(v_schedule -> 'times') = 0 or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'times') t
      where jsonb_typeof(t) <> 'string' or (t #>> '{}') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
    )) then
      raise exception 'schedule times are HH:MM strings' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'everyHours' and (jsonb_typeof(v_schedule -> 'everyHours') <> 'number' or (v_schedule ->> 'everyHours') !~ '^[0-9]+$' or (v_schedule ->> 'everyHours')::integer not between 1 and 24) then
      raise exception 'schedule everyHours is a whole number of hours from 1 to 24' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'startTime' and (jsonb_typeof(v_schedule -> 'startTime') <> 'string' or (v_schedule ->> 'startTime') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') then
      raise exception 'schedule startTime is an HH:MM string' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
    if v_schedule ? 'weekdays' and (jsonb_typeof(v_schedule -> 'weekdays') <> 'array' or exists (
      select 1 from jsonb_array_elements(v_schedule -> 'weekdays') d
      where jsonb_typeof(d) <> 'number' or (d #>> '{}') !~ '^[1-7]$'
    )) then
      raise exception 'schedule weekdays are 1 (Monday) to 7 (Sunday)' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
    end if;
  end if;
  if v_as_needed_reason is not null and length(v_as_needed_reason) > 500 then
    raise exception 'asNeededReason is at most 500 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_max is not null and v_max <= 0 then
    raise exception 'maxPerDay is above zero' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an order needs a start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an order ends on or after its start date' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  if v_prescriber is not null and length(v_prescriber) > 300 then
    raise exception 'prescriber is at most 300 characters' using errcode = '22023', hint = 'MEDICATION_ORDER_INVALID';
  end if;
  
  update "better_supabase"."medication_orders" x set
    "dose" = v_dose,
    "dose_unit" = v_unit,
    "route" = v_route,
    "schedule" = v_schedule,
    "as_needed" = v_as_needed,
    "as_needed_reason" = v_as_needed_reason,
    "max_per_day" = v_max,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "prescriber" = v_prescriber,
    "requires_double_check" = v_double,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  delete from "better_supabase"."medication_administrations" x where x."order_id" = v_row."id" and x."status" = 'planned' and x."scheduled_at" > now();
  perform "better_supabase".emit_event('medication_order.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'medication-orders/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/medications');
  perform better_supabase.audit_event(
    event_type => 'medication_order.updated',
    category => 'data',
    target_type => 'medication_order',
    record_id => v_row."id"::text,
    summary => 'Medication order changed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'medicationOrderId', v_row."id", 'medicationId', v_row."medication_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'medicationId', v_row."medication_id", 'dose', v_row."dose", 'doseUnit', v_row."dose_unit", 'route', v_row."route", 'schedule', v_row."schedule", 'asNeeded', v_row."as_needed", 'asNeededReason', v_row."as_needed_reason", 'maxPerDay', v_row."max_per_day", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'prescriber', v_row."prescriber", 'source', v_row."source", 'externalId', v_row."external_id", 'requiresDoubleCheck', v_row."requires_double_check", 'status', v_row."status", 'stoppedReason', v_row."stopped_reason", 'signatureId', v_row."signature_id", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_administrations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND (EXISTS ( SELECT 1
   FROM better_supabase.medication_orders x
  WHERE ((x.id = medication_administrations.order_id) AND COALESCE(better_supabase.can_subject(x.subject_type, x.subject_id, 'read'::text), false))))) OR (EXISTS ( SELECT 1
   FROM better_supabase.medication_orders x
  WHERE ((x.id = medication_administrations.order_id) AND (((x.tenant_id)::text, x.subject_type, x.subject_id) IN ( SELECT g.tenant,
            g.subject_type,
            g.subject_id
           FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))))))));

CREATE POLICY "medication_administrations_read" ON "better_supabase"."medication_administrations"
  FOR SELECT
  TO "authenticated"
  USING ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND (EXISTS ( SELECT 1
   FROM better_supabase.medication_orders x
  WHERE ((x.id = medication_administrations.order_id) AND COALESCE(better_supabase.can_subject(x.subject_type, x.subject_id, 'read'::text), false))))) OR (EXISTS ( SELECT 1
   FROM better_supabase.medication_orders x
  WHERE ((x.id = medication_administrations.order_id) AND (((x.tenant_id)::text, x.subject_type, x.subject_id) IN ( SELECT g.tenant,
            g.subject_type,
            g.subject_id
           FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))))))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_orders"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)) OR
    (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))))));

CREATE POLICY "medication_orders_read" ON "better_supabase"."medication_orders"
  FOR SELECT
  TO "authenticated"
  USING
    ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.can_subject(subject_type, subject_id,
    'read'::text), false)) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."medications"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.medication_orders x
  WHERE ((x.tenant_id = medications.tenant_id) AND (x.medication_id = medications.id) AND (((x.tenant_id)::text, x.subject_type, x.subject_id) IN ( SELECT g.tenant,
            g.subject_type,
            g.subject_id
           FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))))))));

CREATE POLICY "medications_read" ON "better_supabase"."medications"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) OR (EXISTS ( SELECT 1
   FROM better_supabase.medication_orders x
  WHERE ((x.tenant_id = medications.tenant_id) AND (x.medication_id = medications.id) AND (((x.tenant_id)::text, x.subject_type, x.subject_id) IN ( SELECT g.tenant,
            g.subject_type,
            g.subject_id
           FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))))))));

REVOKE ALL ON FUNCTION "api"."approve_medication_order"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."approve_medication_order"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."record_medication_administration"(uuid, text, numeric, text, uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."record_medication_administration"(uuid, text, numeric, text, uuid, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."approve_medication_order"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."approve_medication_order"(uuid, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."record_medication_administration"(uuid, text, numeric, text, uuid, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."record_medication_administration"(uuid, text, numeric, text, uuid, text, uuid) TO "authenticated", "service_role";
