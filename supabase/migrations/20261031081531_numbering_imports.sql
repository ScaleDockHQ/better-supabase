SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."number_sequences"
  DROP CONSTRAINT "number_sequences_pkey";

DROP FUNCTION "api"."credit_invoice"(uuid, jsonb, text);

DROP FUNCTION "api"."issue_invoice"(uuid, date, date, jsonb);

DROP FUNCTION "better_supabase"."credit_invoice"(uuid, jsonb, text);

DROP FUNCTION "better_supabase"."issue_invoice"(uuid, date, date, jsonb);

DROP FUNCTION "better_supabase"."next_number"(uuid, text, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."preview_number"(uuid, text, timestamp WITH time zone);

DROP FUNCTION "better_supabase"."sync_number_sequences"(uuid, text);

ALTER TABLE "better_supabase"."number_sequences"
  ADD COLUMN "scope" text NOT NULL DEFAULT ''::text;

CREATE OR REPLACE FUNCTION api.credit_invoice (
  invoice      uuid,
  lines        jsonb,
  note         text,
  fixed_number text  DEFAULT NULL::text,
  issued_on    date  DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."credit_invoice"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION api.issue_invoice (
  invoice      uuid,
  issued_on    date,
  due_on       date  DEFAULT NULL::date,
  actor        jsonb DEFAULT NULL::jsonb,
  fixed_number text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."issue_invoice"($1, $2, $3, $4, $5) $function$;

CREATE OR REPLACE FUNCTION better_supabase.create_deal (
  tenant   uuid,
  attrs    jsonb,
  contacts jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_deal uuid;
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."deals";
  v_company_type text := coalesce(create_deal.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_deal.attrs -> 'company' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_deal.tenant, 'deals.write'), false)) then
    raise exception 'not allowed to change deals' using errcode = '42501', hint = 'DEAL_FORBIDDEN';
  end if;
  if nullif(trim(create_deal.attrs ->> 'name'), '') is null or (create_deal.attrs ->> 'closeOn') is null then
    raise exception 'a deal needs a name and a close date' using errcode = '23502', hint = 'DEAL_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_deal.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_deal.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'DEAL_COMPANY_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_deal_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_deal.tenant, create_deal.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'deal' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_deal.tenant::text || ':deal', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."deals" x where x."tenant_id" = create_deal.tenant;
  v_identifier := 'DEAL-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."deals" ("tenant_id", "number", "identifier", "name", "company_type", "company_id", "owner_user_id", "motion", "priority", "product", "seats", "amount", "existing_amount", "currency", "value_period", "pipeline_id", "stage_id", "probability", "forecast_category", "expected_close_on", "next_step", "next_at", "next_kind", "flags", "source", "note", "created_by")
    values (create_deal.tenant,
      v_seq,
      v_identifier,
      trim(create_deal.attrs ->> 'name'),
      case when v_company_id is null then null else v_company_type end,
      v_company_id,
      coalesce((create_deal.attrs ->> 'ownerId')::uuid, auth.uid()),
      create_deal.attrs ->> 'motion',
      create_deal.attrs ->> 'priority',
      create_deal.attrs ->> 'product',
      (create_deal.attrs ->> 'seats')::integer,
      coalesce((create_deal.attrs ->> 'amount')::bigint, 0),
      coalesce((create_deal.attrs ->> 'existingAmount')::bigint, 0),
      upper(coalesce(create_deal.attrs ->> 'currency', 'EUR')),
      coalesce(create_deal.attrs ->> 'valuePeriod', 'one_time'),
      (create_deal.attrs ->> 'pipelineId')::uuid,
      (create_deal.attrs ->> 'stageId')::uuid,
      (create_deal.attrs ->> 'probability')::smallint,
      create_deal.attrs ->> 'forecast',
      (create_deal.attrs ->> 'closeOn')::date,
      create_deal.attrs ->> 'nextStep',
      (create_deal.attrs ->> 'nextAt')::timestamptz,
      create_deal.attrs ->> 'nextKind',
      coalesce(array(select jsonb_array_elements_text(case jsonb_typeof(create_deal.attrs -> 'flags') when 'array' then create_deal.attrs -> 'flags' else '[]' end)), '{}'),
      create_deal.attrs ->> 'source',
      create_deal.attrs ->> 'note',
      auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a deal field has an invalid value' using errcode = '22023', hint = 'DEAL_ATTRS_INVALID';
  end;
  v_deal := v_row."id";
  if v_row."motion" is not null and not (v_row."motion" = any ('{new_logo,expansion,renewal}'::text[])) then
    raise exception 'unknown motion' using errcode = '22023', hint = 'DEAL_MOTION_INVALID';
  end if;
  if v_row."priority" is not null and not (v_row."priority" = any ('{hot,warm,cold}'::text[])) then
    raise exception 'unknown priority' using errcode = '22023', hint = 'DEAL_PRIORITY_INVALID';
  end if;
  if create_deal.contacts is not null then
    perform "better_supabase"."set_deal_contacts"(v_deal, create_deal.contacts);
  end if;
  perform "better_supabase".emit_event('deal.created', jsonb_build_object('organizationId', create_deal.tenant, 'dealId', v_deal, 'subjectType', 'deal', 'subjectId', v_deal::text, 'name', v_row."name"), 'deals/' || v_deal::text, (create_deal.tenant::text)::text, null, 'better-supabase/deals');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_deal_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_deal;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'amount', x."amount"::text, 'existing_amount', x."existing_amount"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object(
      'contacts', coalesce((select jsonb_agg(jsonb_build_object('type', ck."contact_type", 'id', ck."contact_id", 'role', ck."role", 'primary', ck."is_primary") order by ck."is_primary" desc, ck."contact_id") from "better_supabase"."deal_contacts" ck where ck."deal_id" = x."id"), '[]'::jsonb),
      'members', coalesce((select jsonb_agg(jsonb_build_object('userId', cm."user_id", 'role', cm."role") order by cm."user_id") from "better_supabase"."deal_members" cm where cm."deal_id" = x."id"), '[]'::jsonb)) from "better_supabase"."deals" x where x."id" = v_deal);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_maintenance_request (
  tenant    uuid,
  attrs     jsonb,
  assignees uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."maintenance_requests";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_maintenance_request.tenant, 'maintenance.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_maintenance_request.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_maintenance_request_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_maintenance_request.tenant, create_maintenance_request.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'maintenance_request' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'maintenance_request' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_maintenance_request.tenant::text || ':maintenance_request', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."maintenance_requests" x where x."tenant_id" = create_maintenance_request.tenant;
  v_identifier := 'MR' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."maintenance_requests" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by", "unit_id", "lease_id")
    values (create_maintenance_request.tenant, v_seq, v_identifier, trim(create_maintenance_request.attrs ->> 'title'), create_maintenance_request.attrs ->> 'body',
      (create_maintenance_request.attrs ->> 'parentId')::uuid, (create_maintenance_request.attrs ->> 'teamId')::uuid, (create_maintenance_request.attrs ->> 'projectId')::uuid,
      (create_maintenance_request.attrs ->> 'iterationId')::uuid, coalesce((create_maintenance_request.attrs ->> 'priority')::smallint, 0),
      (create_maintenance_request.attrs ->> 'estimate')::numeric, (create_maintenance_request.attrs ->> 'progress')::smallint,
      (create_maintenance_request.attrs ->> 'startAt')::timestamptz, (create_maintenance_request.attrs ->> 'endAt')::timestamptz, (create_maintenance_request.attrs ->> 'dueAt')::timestamptz,
      (create_maintenance_request.attrs ->> 'pipelineId')::uuid, (create_maintenance_request.attrs ->> 'stageId')::uuid, auth.uid(), case when (create_maintenance_request.attrs -> 'fields') ? 'unit_id' then (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('unit_id', (create_maintenance_request.attrs -> 'fields') -> 'unit_id')))."unit_id" else better_supabase.column_default('"better_supabase"."maintenance_requests"', 'unit_id', (null::"better_supabase"."maintenance_requests")."unit_id") end, case when (create_maintenance_request.attrs -> 'fields') ? 'lease_id' then (jsonb_populate_record(null::"better_supabase"."maintenance_requests", jsonb_build_object('lease_id', (create_maintenance_request.attrs -> 'fields') -> 'lease_id')))."lease_id" else better_supabase.column_default('"better_supabase"."maintenance_requests"', 'lease_id', (null::"better_supabase"."maintenance_requests")."lease_id") end)
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  update "better_supabase"."maintenance_requests" x set "unit_id" = case when (create_maintenance_request.attrs -> 'fields') ? 'unit_id' then r."unit_id" else x."unit_id" end, "lease_id" = case when (create_maintenance_request.attrs -> 'fields') ? 'lease_id' then r."lease_id" else x."lease_id" end
  from jsonb_populate_record(null::"better_supabase"."maintenance_requests", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((create_maintenance_request.attrs -> 'fields')) e where e.key in ('unit_id', 'lease_id'))) r
  where x."id" = v_id;
  if cardinality(coalesce(create_maintenance_request.assignees, '{}')) > 0 then
    perform "better_supabase"."set_maintenance_request_assignees"(v_id, create_maintenance_request.assignees);
  end if;
  select * into v_row from "better_supabase"."maintenance_requests" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_maintenance_request.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_maintenance_request.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'maintenance_request', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_maintenance_request.attrs -> 'attachments'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'maintenance_request' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_maintenance_request.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('maintenance_request.created', jsonb_build_object('organizationId', v_row."tenant_id", 'maintenanceRequestId', v_row."id", 'subjectType', 'maintenance_request', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'maintenance-requests/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/maintenance');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_maintenance_request_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."maintenance_request_assignees" ra where ra."maintenance_request_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."maintenance_request_checklist_items" rk where rk."maintenance_request_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'maintenance_request' and rr."subject_id" = x."id"::text)) from "better_supabase"."maintenance_requests" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_production_order (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."production_orders";
  v_variant uuid;
  v_quantity numeric;
  v_location uuid;
  v_bom uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_production_order.tenant is not null and coalesce(better_supabase.can('tenant', create_production_order.tenant, 'manufacturing.write'), false))) then
    raise exception 'not allowed to create production orders' using errcode = '42501', hint = 'MANUFACTURING_FORBIDDEN';
  end if;
  if jsonb_typeof(create_production_order.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  v_variant := nullif(create_production_order.input ->> 'variantId', '')::uuid;
  v_quantity := nullif(create_production_order.input ->> 'quantity', '')::numeric;
  if v_variant is null or not exists (select 1 from "better_supabase"."product_variants" cv where cv."id" = v_variant and cv."tenant_id" = create_production_order.tenant) then
    raise exception 'the variant isn''t a variant of this organization' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  if v_quantity is null or v_quantity <= 0 then
    raise exception 'the quantity must be more than zero' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  v_location := nullif(create_production_order.input ->> 'locationId', '')::uuid;
  if v_location is null then
    select y."id" into v_location from "better_supabase"."inventory_locations" y
    where y."tenant_id" = create_production_order.tenant and y."active"
    order by y."code"
    limit 1;
  end if;
  if v_location is null or not exists (select 1 from "better_supabase"."inventory_locations" y where y."id" = v_location
    and y."tenant_id" = create_production_order.tenant and y."active") then
    raise exception 'the location isn''t an active location of this organization' using errcode = '22023', hint = 'PRODUCTION_ORDER_INVALID';
  end if;
  select x."id" into v_bom from "better_supabase"."boms" x
  where x."variant_id" = v_variant and x."status" = 'active'
    and (nullif(create_production_order.input ->> 'bomId', '') is null or x."id" = (create_production_order.input ->> 'bomId')::uuid);
  if v_bom is null then
    raise exception 'the variant has no active bill of materials' using errcode = '55000', hint = 'BOM_NOT_ACTIVE';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'production_order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'production_order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(create_production_order.tenant, 'production_order', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(create_production_order.tenant, 'production_order', now(), '');
  v_number := better_supabase.format_assigned_number('MO-{yyyy}-{n:4}', v_seq, now());
  end if;
  insert into "better_supabase"."production_orders" ("tenant_id", "number", "sequence", "variant_id", "bom_id", "quantity", "location_id", "due_on", "note", "created_by")
  values (create_production_order.tenant, v_number, v_seq, v_variant, v_bom, v_quantity, v_location,
    nullif(create_production_order.input ->> 'dueOn', '')::date, nullif(trim(create_production_order.input ->> 'note'), ''), auth.uid())
  returning * into v_row;
  return (jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'variantId', v_row."variant_id", 'bomId', v_row."bom_id", 'quantity', v_row."quantity"::text, 'locationId', v_row."location_id", 'dueOn', v_row."due_on", 'status', v_row."status", 'producedQuantity', v_row."produced_quantity"::text, 'scrapQuantity', v_row."scrap_quantity"::text, 'outputLotId', v_row."output_lot_id", 'materialCost', v_row."material_cost"::text, 'laborCost', v_row."labor_cost"::text, 'currency', v_row."currency", 'note', v_row."note", 'releasedAt', v_row."released_at", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'canceledAt', v_row."canceled_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'operations', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'orderId', y."order_id", 'operationId', y."operation_id", 'sequence', y."sequence", 'workCenterId', y."work_center_id", 'title', y."title", 'plannedMinutes', y."planned_minutes"::text, 'status', y."status", 'startedAt', y."started_at", 'finishedAt', y."finished_at", 'operatorId', y."operator_id", 'minutes', y."minutes"::text, 'inspectionId', y."inspection_id") order by y."sequence")
      from "better_supabase"."production_order_operations" y where y."order_id" = v_row."id"), '[]'::jsonb),
    'components', coalesce((select jsonb_agg(jsonb_build_object('componentId', y."id", 'variantId', y."variant_id",
        'quantity', "better_supabase"."production_quantity"(y."variant_id", y."quantity" * v_row."quantity" / x."quantity" * (1 + y."scrap_bps" / 10000.0))::text,
        'allocated', coalesce(al."allocated", 0)::text, 'backordered', coalesce(al."backordered", 0)::text,
        'consumed', coalesce((select sum(z."quantity") from "better_supabase"."production_consumptions" z
          where z."order_id" = v_row."id" and z."variant_id" = y."variant_id"), 0)::text)
      order by y."position", y."id")
      from "better_supabase"."boms" x join "better_supabase"."bom_components" y on y."bom_id" = x."id"
      left join "better_supabase"."stock_allocations" al on al."tenant_id" = v_row."tenant_id"
        and al."document_type" = 'production_order' and al."document_id" = v_row."id"::text
        and al."line_id" = y."id"::text and al."status" = 'open'
      where x."id" = v_row."bom_id"), '[]'::jsonb),
    'consumptions', coalesce((select jsonb_agg(jsonb_build_object('id', z."id", 'variantId', z."variant_id", 'lotId', z."lot_id",
        'serial', z."serial", 'quantity', z."quantity"::text, 'cost', z."cost"::text, 'currency', z."currency",
        'movementId', z."movement_id", 'createdAt', z."created_at") order by z."created_at", z."id")
      from "better_supabase"."production_consumptions" z where z."order_id" = v_row."id"), '[]'::jsonb)));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_quote (
  tenant uuid,
  attrs  jsonb,
  lines  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_quote.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_quote.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "prices_include_tax", "discount_bps", "discount_amount", "deposit_bps", "deposit_amount", "deposit_required", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id',
      coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce((create_quote.attrs ->> 'discountBps')::integer, 0), coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0), (create_quote.attrs ->> 'depositBps')::integer, (create_quote.attrs ->> 'depositAmount')::bigint, coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'quote', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'quote' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('quote.created', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_risk (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."risks";
  v_title text := trim(create_risk.input ->> 'title');
  v_category text := create_risk.input ->> 'category';
  v_matrix uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_risk.tenant is not null and coalesce(better_supabase.can('tenant', create_risk.tenant, 'risks.write'), false))) then
    raise exception 'not allowed to write risks' using errcode = '42501', hint = 'RISK_FORBIDDEN';
  end if;
  if jsonb_typeof(create_risk.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'a risk needs a title of 1 to 300 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if v_category is null or not (v_category = any (array['quality', 'safety', 'environment', 'security', 'compliance', 'operational', 'financial', 'strategic']::text[])) then
    raise exception 'the category is not one of options.categories' using errcode = '22023', hint = 'RISK_CATEGORY_UNKNOWN';
  end if;
  if length(create_risk.input ->> 'description') > 10000 then
    raise exception 'description is at most 10000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if length(create_risk.input ->> 'cause') > 4000 then
    raise exception 'cause is at most 4000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if length(create_risk.input ->> 'consequence') > 4000 then
    raise exception 'consequence is at most 4000 characters' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if create_risk.input ? 'reviewIntervalMonths' and create_risk.input ->> 'reviewIntervalMonths' is not null
    and ((create_risk.input ->> 'reviewIntervalMonths') !~ '^[0-9]{1,3}$' or (create_risk.input ->> 'reviewIntervalMonths')::integer not between 1 and 120) then
    raise exception 'reviewIntervalMonths is a whole number from 1 to 120' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  if create_risk.input ? 'fields' and jsonb_typeof(create_risk.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'RISK_INVALID';
  end if;
  v_matrix := coalesce(nullif(create_risk.input ->> 'matrixId', '')::uuid, "better_supabase"."ensure_risk_matrix"(create_risk.tenant));
  if not exists (
    select 1 from "better_supabase"."risk_matrices" x where x."id" = v_matrix and x."tenant_id" = create_risk.tenant
  ) then
    raise exception 'no such risk matrix in this organization' using errcode = 'P0002', hint = 'RISK_MATRIX_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_risk_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_risk.tenant, create_risk.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'risk' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'risk' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(create_risk.tenant, 'risk', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(create_risk.tenant, 'risk', now(), '');
  v_number := better_supabase.format_assigned_number('RSK-{n:4}', v_seq, now());
  end if;
  insert into "better_supabase"."risks" ("tenant_id", "number", "sequence", "matrix_id", "title", "category", "description", "cause", "consequence", "owner_id", "review_interval_months", "created_by")
  values (create_risk.tenant, v_number, v_seq, v_matrix, v_title, v_category, nullif(trim(create_risk.input ->> 'description'), ''), nullif(trim(create_risk.input ->> 'cause'), ''), nullif(trim(create_risk.input ->> 'consequence'), ''), nullif(create_risk.input ->> 'ownerId', '')::uuid, (create_risk.input ->> 'reviewIntervalMonths')::integer, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('risk.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status"), 'risks/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/risks');
  perform better_supabase.audit_event(
    event_type => 'risk.created',
    category => 'data',
    target_type => 'risk',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'risk created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_risk_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'matrixId', v_row."matrix_id", 'title', v_row."title", 'description', v_row."description", 'category', v_row."category", 'cause', v_row."cause", 'consequence', v_row."consequence", 'ownerId', v_row."owner_id", 'status', v_row."status", 'treatment', v_row."treatment", 'reviewIntervalMonths', v_row."review_interval_months", 'nextReviewOn', v_row."next_review_on", 'reviewedAt', v_row."reviewed_at", 'inherent', case when v_row."inherent_score" is null then null else jsonb_build_object('likelihood', v_row."inherent_likelihood", 'impact', v_row."inherent_impact", 'score', v_row."inherent_score", 'band', v_row."inherent_band") end, 'residual', case when v_row."residual_score" is null then null else jsonb_build_object('likelihood', v_row."residual_likelihood", 'impact', v_row."residual_impact", 'score', v_row."residual_score", 'band', v_row."residual_band") end, 'currentAssessmentId', v_row."current_assessment_id", 'closedAt', v_row."closed_at", 'archivedAt', v_row."archived_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_work_item (
  tenant    uuid,
  attrs     jsonb,
  assignees uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_seq bigint;
  v_identifier text;
  v_id uuid;
  v_row "better_supabase"."work_items";
  v_linked integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_work_item.tenant, 'tasks.write'), false)) then
    raise exception 'not allowed to change work items' using errcode = '42501', hint = 'TASK_FORBIDDEN';
  end if;
  if nullif(trim(create_work_item.attrs ->> 'title'), '') is null then
    raise exception 'a title is required' using errcode = '23502', hint = 'TASK_TITLE_REQUIRED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_work_item_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_work_item.tenant, create_work_item.attrs;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'work_item' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_work_item.tenant::text || ':work_item', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."work_items" x where x."tenant_id" = create_work_item.tenant;
  v_identifier := 'TASK-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."work_items" ("tenant_id", "number", "identifier", "title", "body", "parent_id", "team_id", "project_id", "iteration_id",
      "priority", "estimate", "progress", "start_at", "end_at", "due_at", "pipeline_id", "stage_id", "created_by")
    values (create_work_item.tenant, v_seq, v_identifier, trim(create_work_item.attrs ->> 'title'), create_work_item.attrs ->> 'body',
      (create_work_item.attrs ->> 'parentId')::uuid, (create_work_item.attrs ->> 'teamId')::uuid, (create_work_item.attrs ->> 'projectId')::uuid,
      (create_work_item.attrs ->> 'iterationId')::uuid, coalesce((create_work_item.attrs ->> 'priority')::smallint, 0),
      (create_work_item.attrs ->> 'estimate')::numeric, (create_work_item.attrs ->> 'progress')::smallint,
      (create_work_item.attrs ->> 'startAt')::timestamptz, (create_work_item.attrs ->> 'endAt')::timestamptz, (create_work_item.attrs ->> 'dueAt')::timestamptz,
      (create_work_item.attrs ->> 'pipelineId')::uuid, (create_work_item.attrs ->> 'stageId')::uuid, auth.uid())
    returning "id" into v_id;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range or foreign_key_violation then
    raise exception 'a work item field has an invalid value' using errcode = '22023', hint = 'TASK_ATTRS_INVALID';
  end;
  if cardinality(coalesce(create_work_item.assignees, '{}')) > 0 then
    perform "better_supabase"."set_work_item_assignees"(v_id, create_work_item.assignees);
  end if;
  select * into v_row from "better_supabase"."work_items" x where x."id" = v_id;
  if jsonb_typeof(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) <> 'array' then
      raise exception 'attachments must be a list of attachment ids' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
    end if;
    if jsonb_array_length(coalesce((create_work_item.attrs -> 'attachments'), '[]'::jsonb)) > 0 then
      update "better_supabase"."attachments" f set "subject_type" = 'work_item', "subject_id" = v_row."id"::text
      where f."id" = any (array(select jsonb_array_elements_text((create_work_item.attrs -> 'attachments'))::uuid))
        and f."organization_id" = v_row."tenant_id"
        and (f."subject_type" is null or (f."subject_type" = 'work_item' and f."subject_id" = v_row."id"::text))
        and ((auth.role() = 'service_role') or f."uploaded_by" = auth.uid());
      get diagnostics v_linked = row_count;
      if v_linked <> (select count(distinct x) from jsonb_array_elements_text((create_work_item.attrs -> 'attachments')) x) then
        raise exception 'attach only your own files in this organization that aren''t on another subject' using errcode = '22023', hint = 'TASK_ATTACHMENTS_INVALID';
      end if;
    end if;
  perform "better_supabase".emit_event('task.created', jsonb_build_object('organizationId', v_row."tenant_id", 'workItemId', v_row."id", 'subjectType', 'work_item', 'subjectId', v_row."id"::text, 'title', v_row."title"), 'work-items/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/tasks');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_work_item_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text) || jsonb_build_object('assignees', coalesce((select jsonb_agg(ra."user_id" order by ra."created_at", ra."user_id") from "better_supabase"."work_item_assignees" ra where ra."work_item_id" = x."id"), '[]'::jsonb)) || jsonb_build_object('checklist', (select jsonb_build_object('total', count(*), 'done', count(*) filter (where rk."done")) from "better_supabase"."work_item_checklist_items" rk where rk."work_item_id" = x."id"), 'recurrence', (select jsonb_build_object('rrule', rr."rrule", 'tzid', rr."tzid", 'dtstart', rr."dtstart") from "better_supabase"."recurrence_rules" rr where rr."tenant_id" = x."tenant_id" and rr."subject_type" = 'work_item' and rr."subject_id" = x."id"::text)) from "better_supabase"."work_items" x where x."id" = v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.credit_invoice (
  invoice      uuid,
  lines        jsonb,
  note         text,
  fixed_number text  DEFAULT NULL::text,
  issued_on    date  DEFAULT NULL::date
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_original "better_supabase"."invoices";
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if credit_invoice.fixed_number is not null and better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  select * into v_original from "better_supabase"."invoices" x where x."id" = credit_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false));
  if v_original."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_original."kind" <> 'invoice' or v_original."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice is credited' using errcode = '55000', hint = 'INVOICE_NOT_CREDITABLE';
  end if;
  insert into "better_supabase"."invoices" ("tenant_id", "kind", "original_id", "title", "company_type", "company_id", "contact_type", "contact_id", legal_entity_id,
    "currency", "terms_days", "note", "prices_include_tax", "direction", "supplier_reference", "purchase_order_id", "dimensions", "created_by")
  values (v_original."tenant_id", 'credit_note', v_original."id", 'Credit for ' || coalesce(v_original."identifier", v_original."title"),
    v_original."company_type", v_original."company_id", v_original."contact_type", v_original."contact_id", v_original.legal_entity_id,
    v_original."currency", 0, nullif(trim(credit_invoice.note), ''), v_original."prices_include_tax", v_original."direction", v_original."supplier_reference", v_original."purchase_order_id", v_original."dimensions", auth.uid())
  returning * into v_row;
  if credit_invoice.lines is null then
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select x."tenant_id", v_row."id", x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."position"
    from "better_supabase"."invoice_lines" x where x."parent_id" = v_original."id";
  else
    perform "better_supabase"."set_invoice_lines"(v_row."id", credit_invoice.lines);
  end if;
  perform "better_supabase".emit_event('invoice.created', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if credit_invoice.fixed_number is not null then
    perform "better_supabase"."issue_invoice"(v_row."id", coalesce(credit_invoice.issued_on, current_date), null, null, credit_invoice.fixed_number);
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_document_save (
  node                   uuid,
  document_type          text,
  owner_id               uuid    DEFAULT NULL::uuid,
  review_interval_months integer DEFAULT NULL::integer
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_node "better_supabase"."drive_nodes"%rowtype;
  v_seq bigint;
  v_number text;
  v_entity text;
  v_format text;
begin
  perform better_supabase.raise_actor_readonly() where not better_supabase.actor_may_write();
  select * into v_node from "better_supabase"."drive_nodes" x where x."id" = drive_document_save.node and x."deleted_at" is null for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'viewer')) then
    raise exception 'drive item not found' using errcode = 'P0002', hint = 'DRIVE_NOT_FOUND';
  end if;
  if v_node."kind" <> 'file' then
    raise exception 'only a file can be a controlled document' using errcode = '22023', hint = 'DRIVE_NOT_A_FILE';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."drive_can"(v_node."id", 'editor')) then
    raise exception 'not allowed to control this document' using errcode = '42501', hint = 'DRIVE_FORBIDDEN';
  end if;
  if (v_node."locked_until" > now() and v_node."locked_by" is distinct from auth.uid() and not coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
    raise exception 'this item is checked out by someone else' using errcode = '55P03', hint = 'DRIVE_LOCKED', detail = jsonb_build_object('lockedBy', v_node."locked_by", 'lockedUntil', v_node."locked_until")::text;
  end if;
  if drive_document_save.document_type is null or not (drive_document_save.document_type = any (array['sop', 'policy', 'form']::text[])) then
    raise exception 'that document type is not in options.control.types' using errcode = '22023', hint = 'DRIVE_DOCUMENT_TYPE_UNKNOWN';
  end if;
  if v_node."document_status" = 'obsolete' then
    raise exception 'an obsolete document can''t change' using errcode = '22023', hint = 'DRIVE_DOCUMENT_STATUS_INVALID';
  end if;
  if drive_document_save.owner_id is not null and not exists (
    select 1 from "public"."memberships" mu
    where mu."organization_id" = v_node."tenant_id" and mu."user_id" = drive_document_save.owner_id
  ) then
    raise exception 'the owner must be a member of the organization' using errcode = '22023', hint = 'DRIVE_DOCUMENT_OWNER_INVALID';
  end if;
  v_number := v_node."document_number";
  if v_number is null then
    case drive_document_save.document_type
      when 'sop' then
        v_entity := 'drive_document_sop';
        v_format := 'SOP-{n:4}';
      else
        v_entity := 'drive_document';
        v_format := 'DOC-{n:5}';
    end case;
    if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = v_entity then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_node."tenant_id", v_entity, v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_node."tenant_id", v_entity, now());
    v_number := better_supabase.format_assigned_number(v_format, v_seq, now());
  end if;
  end if;
  update "better_supabase"."drive_nodes" x set "document_number" = v_number,
    "document_type" = drive_document_save.document_type,
    "document_owner_id" = coalesce(drive_document_save.owner_id, x."document_owner_id", auth.uid()),
    "review_interval_months" = coalesce(drive_document_save.review_interval_months, x."review_interval_months"), "updated_at" = now()
  where x."id" = v_node."id"
  returning * into v_node;
  if v_node."document_status" is null then
    perform "better_supabase"."transition"('drive_node', v_node."id"::text, 'draft', null);
    select * into v_node from "better_supabase"."drive_nodes" x where x."id" = v_node."id";
  end if;
  perform "better_supabase".emit_event('drive_node.document_saved', jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id"), 'drive-nodes/' || v_node."id"::text, (v_node."tenant_id")::text, null, 'better-supabase/drive-files');
  perform better_supabase.audit_event(
    event_type => 'drive_node.document_saved',
    category => 'data',
    target_type => 'drive_node',
    record_id => v_node."id"::text,
    target_label => v_node."name",
    summary => 'document saved',
    tenant => (v_node."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_node."tenant_id"::text, 'subjectType', 'drive_node', 'subjectId', v_node."id"::text, 'documentNumber', v_node."document_number", 'documentType', v_node."document_type", 'ownerId', v_node."document_owner_id")
  );
  return ("better_supabase"."drive_node_json"(v_node) || jsonb_build_object('role', "better_supabase"."drive_role"((v_node)."id"), 'readOnly', (coalesce((v_node)."source"::text, 'internal') not in ('internal', 'request') or false), 'held', "better_supabase"."drive_node_held"((v_node)."id"), 'downloadable', "better_supabase"."drive_can_download"((v_node)."id")));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_gift_receipt (
  gift_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."donations"%rowtype;
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."donations" x where x."id" = issue_gift_receipt.gift_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.manage'), false)) then
    raise exception 'no such gift you can read' using errcode = 'P0002', hint = 'DONATION_NOT_FOUND';
  end if;
  if v_row."status" <> 'posted' then
    raise exception 'only a posted gift gets a receipt' using errcode = '55000', hint = 'DONATION_STATUS_INVALID';
  end if;
  if v_row."receipt_id" is not null then
    select * into v_receipt from "better_supabase"."donation_receipts" x where x."id" = v_row."receipt_id";
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_row."tenant_id", 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_row."tenant_id", 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (v_row."tenant_id", v_row."donor_type", v_row."donor_id", v_seq, v_number, 'gift', extract(year from v_row."received_on")::integer,
    v_row."amount", v_row."currency")
  returning * into v_receipt;
  update "better_supabase"."donations" x set "receipt_id" = v_receipt."id", "updated_at" = now() where x."id" = v_row."id";
  perform "better_supabase".emit_event('donation_receipt.issued', jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency"), 'donation-receipts/' || v_receipt."id"::text, (v_receipt."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation_receipt.issued',
    category => 'billing',
    target_type => 'donation_receipt',
    record_id => v_receipt."id"::text,
    target_label => v_receipt."number",
    summary => 'issued a gift receipt',
    tenant => (v_receipt."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency")
  );
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_invoice (
  invoice      uuid,
  issued_on    date,
  due_on       date  DEFAULT NULL::date,
  actor        jsonb DEFAULT NULL::jsonb,
  fixed_number text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."invoices";
  v_original "better_supabase"."invoices";
  v_seq bigint;
  v_identifier text;
  v_issued_on date := coalesce(issue_invoice.issued_on, current_date);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'the invoice was already issued' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  if not exists (select 1 from "better_supabase"."invoice_lines" x where x."parent_id" = v_row."id") then
    raise exception 'an invoice needs a line before it is issued' using errcode = '23514', hint = 'INVOICE_EMPTY';
  end if;
  if issue_invoice.due_on < v_issued_on then
    raise exception 'an invoice falls due on or after its issue date' using errcode = '22023', hint = 'INVOICE_DUE_INVALID';
  end if;
  if issue_invoice.actor is not null then
    if jsonb_typeof(issue_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(issue_invoice.actor ->> 'ip', '')::inet, nullif(issue_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(issue_invoice.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  if v_row."kind" = 'credit_note' then
    select * into v_original from "better_supabase"."invoices" x where x."id" = v_row."original_id" for update;
    if v_row."total" > v_original."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_original."id"), 0) - v_original."credited_total" then
      raise exception 'a credit note can''t exceed the invoice''s total less its earlier credits' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
    end if;
    if v_row."direction" = 'purchase' then
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_credit_note' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'BCN-' || v_seq::text;
  end if;
    else
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':credit_note' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'CN-' || v_seq::text;
  end if;
    end if;
  else
    if v_row."direction" = 'purchase' then
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_bill' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_bill' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_bill' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'BILL-' || v_seq::text;
  end if;
    else
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'invoice' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'invoice' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':invoice' || ':' || "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id), 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id" and "better_supabase"."number_scope"(x."tenant_id", x.legal_entity_id) = "better_supabase"."number_scope"(v_row."tenant_id", v_row.legal_entity_id);
  v_identifier := 'INV-' || v_seq::text;
  end if;
    end if;
  end if;
  if v_row."kind" = 'invoice' and not v_row."direction" = 'purchase' and coalesce(v_row."company_id"::text, v_row."contact_id"::text) is not null then
    declare
      v_limit bigint;
    begin
      select s.credit_limit into v_limit from (select p."credit_limit", p."credit_currency" from "better_supabase"."companies" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null union all select p."credit_limit", p."credit_currency" from "better_supabase"."people" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null) s(credit_limit, credit_currency)
      where s.credit_limit is not null and coalesce(s.credit_currency, v_row."currency") = v_row."currency"
      order by s.credit_limit limit 1;
      if v_limit is not null and (select coalesce(sum((o."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = o."id"), 0) - o."credited_total" - o."paid_total")), 0) from "better_supabase"."invoices" o
        where o."tenant_id" = v_row."tenant_id" and o."id" <> v_row."id" and o."currency" = v_row."currency"
          and coalesce(o."company_id"::text, o."contact_id"::text) = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and not o."direction" = 'purchase'
          and o."kind" = 'invoice' and o."status" in ('issued', 'partially_paid')) + v_row."total" > v_limit and not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'orders.override_credit'), false)) then
        raise exception 'this invoice takes the customer over their credit limit' using errcode = '55000', hint = 'INVOICE_CREDIT_LIMIT_EXCEEDED';
      end if;
    end;
  end if;
  update "better_supabase"."invoices" x set "status" = 'issued', "number" = v_seq, "identifier" = v_identifier,
    "issued_on" = v_issued_on,
    "due_on" = coalesce(issue_invoice.due_on, v_issued_on + x."terms_days"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.issued', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'dueOn', v_row."due_on"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."kind" = 'credit_note' then
    update "better_supabase"."invoices" x set "credited_total" = x."credited_total" + v_row."total", "updated_at" = now()
    where x."id" = v_original."id"
    returning * into v_original;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_original."id"
  returning * into v_original;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_original."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_original;
    perform "better_supabase".emit_event('invoice.credited', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'creditNoteId', v_row."id", 'amount', v_row."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    if v_original."status" = 'paid' then
      perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'total', v_original."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    end if;
  end if;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice', v_row."id"::text);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.issue_yearly_receipt (
  tenant     uuid,
  donor_type text,
  donor_id   text,
  year       integer,
  currency   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_receipt "better_supabase"."donation_receipts"%rowtype;
  v_amount bigint;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', issue_yearly_receipt.tenant, 'donations.manage'), false)) then
    raise exception 'not allowed to manage donations' using errcode = '42501', hint = 'DONATIONS_FORBIDDEN';
  end if;
  if issue_yearly_receipt.year is null or issue_yearly_receipt.currency is null then
    raise exception 'a yearly receipt needs a year and a currency' using errcode = '22023', hint = 'DONATION_RECEIPT_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('donations.yearly:' || issue_yearly_receipt.tenant::text || ':' || issue_yearly_receipt.donor_type
    || ':' || issue_yearly_receipt.donor_id || ':' || issue_yearly_receipt.year::text || ':' || issue_yearly_receipt.currency, 0));
  select * into v_receipt from "better_supabase"."donation_receipts" x
    where x."tenant_id" = issue_yearly_receipt.tenant and x."donor_type" = issue_yearly_receipt.donor_type
      and x."donor_id" = issue_yearly_receipt.donor_id and x."year" = issue_yearly_receipt.year
      and x."currency" = issue_yearly_receipt.currency and x."kind" = 'yearly' and x."voided_at" is null;
  if found then
    return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
  end if;
  select coalesce(sum(g."amount"), 0) into v_amount from "better_supabase"."donations" g
    where g."tenant_id" = issue_yearly_receipt.tenant and g."donor_type" = issue_yearly_receipt.donor_type
      and g."donor_id" = issue_yearly_receipt.donor_id and g."currency" = issue_yearly_receipt.currency
      and g."status" = 'posted' and extract(year from g."received_on")::integer = issue_yearly_receipt.year;
  if v_amount <= 0 then
    raise exception 'the donor has no posted gifts in this year and currency' using errcode = '22023', hint = 'DONATION_RECEIPT_EMPTY';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'donation_receipt' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(issue_yearly_receipt.tenant, 'donation_receipt', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(issue_yearly_receipt.tenant, 'donation_receipt', now(), '');
  v_number := better_supabase.format_assigned_number('R-{n}', v_seq, now());
  end if;
  insert into "better_supabase"."donation_receipts" ("tenant_id", "donor_type", "donor_id", "sequence", "number", "kind", "year", "amount", "currency")
  values (issue_yearly_receipt.tenant, issue_yearly_receipt.donor_type, issue_yearly_receipt.donor_id, v_seq, v_number, 'yearly',
    issue_yearly_receipt.year, v_amount, issue_yearly_receipt.currency)
  returning * into v_receipt;
  perform "better_supabase".emit_event('donation_receipt.issued', jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency"), 'donation-receipts/' || v_receipt."id"::text, (v_receipt."tenant_id")::text, null, 'better-supabase/donations');
  perform better_supabase.audit_event(
    event_type => 'donation_receipt.issued',
    category => 'billing',
    target_type => 'donation_receipt',
    record_id => v_receipt."id"::text,
    target_label => v_receipt."number",
    summary => 'issued a yearly receipt',
    tenant => (v_receipt."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_receipt."tenant_id", 'id', v_receipt."id", 'number', v_receipt."number", 'kind', v_receipt."kind", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency")
  );
  return jsonb_build_object('id', v_receipt."id", 'organizationId', v_receipt."tenant_id", 'donorType', v_receipt."donor_type", 'donorId', v_receipt."donor_id", 'sequence', v_receipt."sequence"::text, 'number', v_receipt."number", 'kind', v_receipt."kind", 'year', v_receipt."year", 'amount', v_receipt."amount"::text, 'currency', v_receipt."currency", 'issuedAt', v_receipt."issued_at", 'voidedAt', v_receipt."voided_at", 'voidReason', v_receipt."void_reason");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.next_number (
  tenant   uuid,
  p_entity text,
  at       timestamp with time zone DEFAULT now(),
  p_scope  text                     DEFAULT ''::text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_period text;
  v_n bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  v_period := case p_entity
    when 'drive_document' then ''
    when 'drive_document_sop' then ''
    when 'donation_receipt' then ''
    when 'risk' then ''
    when 'case' then to_char(next_number.at at time zone 'utc', 'YYYY')
    when 'inspection' then to_char(next_number.at at time zone 'utc', 'YYYY')
    when 'production_order' then to_char(next_number.at at time zone 'utc', 'YYYY')
    else null
  end;
  if v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_number_assign"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_period;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(next_number.tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (next_number.tenant, p_entity, coalesce(p_scope, ''), v_period, 1)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = "better_supabase"."number_sequences"."last_number" + 1, "updated_at" = now()
  returning "last_number" into v_n;
  perform "better_supabase".emit_event('number.assigned', jsonb_build_object('organizationId', next_number.tenant, 'entity', p_entity, 'period', v_period, 'number', v_n), 'number-sequences/' || p_entity, (next_number.tenant)::text, null, 'better-supabase/numbering');
  perform better_supabase.audit_event(
    event_type => 'number.assigned',
    category => 'data',
    target_type => 'number_sequence',
    record_id => p_entity,
    summary => 'assigned ' || v_n::text,
    tenant => (next_number.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', next_number.tenant, 'entity', p_entity, 'period', v_period, 'number', v_n)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_number_assign"(uuid, text, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint)', v_hook::oid::regproc)
        using next_number.tenant, p_entity, v_n;
    end if;
  end;
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.number_scope (
  p_tenant       uuid,
  p_legal_entity uuid
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if p_legal_entity is null then
    return '';
  end if;
  if exists (
    select 1 from "better_supabase"."legal_entities" e
    where e."tenant_id" = p_tenant
      and e."id" = p_legal_entity
      and e."is_default"
  ) then
    return '';
  end if;
  return p_legal_entity::text;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_case_as (
  kind_id  uuid,
  input    jsonb,
  reporter uuid  DEFAULT NULL::uuid
)
  RETURNS better_supabase.cases
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_kind "better_supabase"."case_kinds";
  v_row "better_supabase"."cases";
  v_input jsonb := coalesce(open_case_as.input, '{}'::jsonb);
  v_title text := trim(v_input ->> 'title');
  v_seq bigint;
  v_identifier text;
  v_last text;
  v_rank text;
begin
  select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  if not found then
    raise exception 'no such case kind in this organization' using errcode = 'P0002', hint = 'CASE_KIND_NOT_FOUND';
  end if;
  if v_kind."archived_at" is not null then
    raise exception 'the case kind is archived' using errcode = '55000', hint = 'CASE_KIND_ARCHIVED';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 200 then
    raise exception 'a case needs a title of 1 to 200 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if length(v_input ->> 'description') > 20000 then
    raise exception 'description is at most 20000 characters' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'reporterContact' and jsonb_typeof(v_input -> 'reporterContact') not in ('object', 'null') then
    raise exception 'reporterContact must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  if v_input ? 'severity' and v_input ->> 'severity' is not null and not ((v_input ->> 'severity') = any (array['low', 'medium', 'high', 'critical']::text[])) then
    raise exception 'the severity is not one of options.severities' using errcode = '22023', hint = 'CASE_SEVERITY_UNKNOWN';
  end if;
  if v_input ? 'source' and not (coalesce(v_input ->> 'source', '') = any (array['internal', 'customer', 'supplier', 'inspection', 'regulator', 'employee', 'anonymous']::text[])) then
    raise exception 'the source is not one of options.sources' using errcode = '22023', hint = 'CASE_SOURCE_UNKNOWN';
  end if;
  if v_input ? 'fields' and jsonb_typeof(v_input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'CASE_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_case_open"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using v_kind."tenant_id", v_input || jsonb_build_object('kind', v_kind."key");
    end if;
  end;
  if v_kind."pipeline_id" is null then
    perform "better_supabase"."ensure_case_kinds"(v_kind."tenant_id");
    select * into v_kind from "better_supabase"."case_kinds" x where x."id" = open_case_as.kind_id;
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'case' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'case' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(v_kind."tenant_id", 'case', v_identifier, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(v_kind."tenant_id", 'case', now(), '');
  v_identifier := better_supabase.format_assigned_number('{yyyy}-{n:4}', v_seq, now());
  end if;
  select max(x."rank") into v_last from "better_supabase"."cases" x
  where x."tenant_id" = v_kind."tenant_id" and x."pipeline_id" = v_kind."pipeline_id";
  v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  insert into "better_supabase"."cases" ("tenant_id", "kind_id", "number", "sequence", "title", "severity", "source", "reporter_id", "owner_id", "occurred_at", "due_on", "pipeline_id", "rank", "description", "reporter_contact", "created_by")
  values (v_kind."tenant_id", v_kind."id", v_kind."prefix" || '-' || v_identifier, v_seq, v_title,
    v_input ->> 'severity', coalesce(v_input ->> 'source', 'internal'), open_case_as.reporter,
    nullif(v_input ->> 'ownerId', '')::uuid, nullif(v_input ->> 'occurredAt', '')::timestamptz, nullif(v_input ->> 'dueOn', '')::date,
    v_kind."pipeline_id", v_rank, nullif(trim(v_input ->> 'description'), ''), nullif(v_input -> 'reporterContact', 'null'::jsonb), auth.uid())
  returning * into v_row;
  if v_input ->> 'originType' is not null and v_input ->> 'originId' is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'case', v_row."id"::text, v_input ->> 'originType', v_input ->> 'originId', auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'case' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('case.created', jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', v_kind."key", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status"), 'cases/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/cases');
  perform better_supabase.audit_event(
    event_type => 'case.created',
    category => 'data',
    target_type => 'case',
    record_id => v_row."id"::text,
    target_label => v_row."number" || ' ' || v_row."title",
    summary => 'case opened',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'caseId', v_row."id", 'kind', v_kind."key", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_case_open"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return v_row;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.order_from_document (
  p_tenant   uuid,
  p_attrs    jsonb,
  p_lines    jsonb,
  p_location uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_order record;
  v_line record;
  v_allocation jsonb;
  v_seq bigint;
  v_number text;
  v_id uuid;
  v_claims text;
begin
  if p_attrs -> 'origin' is not null then
    select x."id" into v_id from "better_supabase"."orders" x
    where x."tenant_id" = p_tenant and x."origin_type" = p_attrs #>> '{origin,type}' and x."origin_id" = p_attrs #>> '{origin,id}'
      and x."status" <> 'cancelled'
    limit 1;
    if v_id is not null then
      return "better_supabase"."order_json"(v_id) || jsonb_build_object('created', false);
    end if;
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':commerce:order', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."orders" x where x."tenant_id" = p_tenant;
  v_number := v_seq::text;
  end if;
  insert into "better_supabase"."orders" ("tenant_id", "number", "sequence", "customer_id", "email", "status", "currency",
    "subtotal", "discount_total", "shipping_total", "tax_total", "total", "tax_inclusive",
    "shipping_address", "billing_address", "origin_type", "origin_id")
  values (p_tenant, v_number, v_seq, nullif(p_attrs ->> 'customerId', '')::uuid, p_attrs ->> 'email', 'confirmed', p_attrs ->> 'currency',
    (p_attrs ->> 'subtotal')::bigint, (p_attrs ->> 'discountTotal')::bigint, (p_attrs ->> 'shippingTotal')::bigint,
    (p_attrs ->> 'taxTotal')::bigint, (p_attrs ->> 'total')::bigint, coalesce((p_attrs ->> 'taxInclusive')::boolean, false),
    p_attrs -> 'shippingAddress', p_attrs -> 'billingAddress', p_attrs #>> '{origin,type}', p_attrs #>> '{origin,id}')
  returning "id" into v_id;
  insert into "better_supabase"."order_lines" ("tenant_id", "order_id", "position", "variant_id", "product_id", "sku", "title",
    "quantity", "unit_amount", "subtotal", "discount", "tax", "total", "requires_shipping")
  select p_tenant, v_id, e.n, nullif(e.l ->> 'variantId', '')::uuid, nullif(e.l ->> 'productId', '')::uuid, e.l ->> 'sku', e.l ->> 'title',
    (e.l ->> 'quantity')::integer, (e.l ->> 'unitAmount')::bigint, (e.l ->> 'subtotal')::bigint, (e.l ->> 'discount')::bigint,
    (e.l ->> 'tax')::bigint, (e.l ->> 'total')::bigint, (e.l ->> 'requiresShipping')::boolean
  from jsonb_array_elements(p_lines) with ordinality as e(l, n);
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_id;
  for v_line in
    select x."id" as id, x."variant_id" as variant, x."quantity" as quantity, cv."allow_backorder" as backorder
    from "better_supabase"."order_lines" x join "better_supabase"."product_variants" cv on cv."id" = x."variant_id"
    where x."order_id" = v_order.id and cv."track_inventory"
    order by x."position"
  loop
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_allocation := "better_supabase"."allocate_stock"(v_order.tenant, v_line.variant, p_location, v_line.quantity::numeric, 'order', v_order.id::text, v_line.id::text, v_line.backorder);
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    update "better_supabase"."order_lines" x set "location_id" = (v_allocation ->> 'locationId')::uuid,
      "backordered" = (v_allocation ->> 'backordered')::numeric > 0
    where x."id" = v_line.id;
  end loop;
  perform "better_supabase".emit_event('order.placed', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer, 'currency', v_order.currency, 'subtotal', (p_attrs ->> 'subtotal'), 'discountTotal', (p_attrs ->> 'discountTotal'), 'shippingTotal', (p_attrs ->> 'shippingTotal'), 'taxTotal', (p_attrs ->> 'taxTotal'), 'total', v_order.total::text, 'units', (select coalesce(sum(l."quantity"), 0)::text from "better_supabase"."order_lines" l where l."order_id" = v_order.id)), 'orders/' || v_order.id::text, (v_order.tenant)::text, null, 'better-supabase/orders');
  return "better_supabase"."order_json"(v_id) || jsonb_build_object('created', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.place_order (
  cart           uuid,
  tax            jsonb  DEFAULT NULL::jsonb,
  expected_total bigint DEFAULT NULL::bigint,
  location       uuid   DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_cart record;
  v_order record;
  v_line record;
  v_priced jsonb;
  v_tax bigint := 0;
  v_line_tax bigint;
  v_invalid boolean;
  v_inclusive boolean := false;
  v_total bigint;
  v_seq bigint;
  v_number text;
  v_id uuid;
  v_location uuid;
  v_reservation jsonb;
  v_claims text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status, x."currency" as currency,
    x."email" as email, x."shipping_address" as shipping_address, x."billing_address" as billing_address
  into v_cart from "better_supabase"."carts" x where x."id" = place_order.cart for update;
  if not found then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status = 'converted' then
    select x."id" into v_id from "better_supabase"."orders" x where x."cart_id" = place_order.cart;
    if v_id is not null then
      return "better_supabase"."order_json"(v_id) || jsonb_build_object('created', false);
    end if;
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_order_place"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using place_order.cart;
    end if;
  end;
  v_priced := "better_supabase"."cart_totals"(place_order.cart);
  if jsonb_array_length(v_priced -> 'lines') = 0 then
    raise exception 'the cart has no lines to order' using errcode = '55000', hint = 'ORDERS_CART_EMPTY';
  end if;
  if jsonb_array_length(v_priced -> 'problems') > 0 then
    raise exception 'the cart can''t be ordered: %', v_priced -> 'problems' using errcode = '55000', hint = 'ORDERS_CART_INVALID';
  end if;
  if place_order.expected_total is not null and (v_priced ->> 'total')::bigint <> place_order.expected_total then
    raise exception 'the cart''s total changed; price it and quote tax again' using errcode = '40001', hint = 'ORDERS_PRICE_CHANGED';
  end if;
  if place_order.tax is not null then
    if jsonb_typeof(place_order.tax) <> 'object' or (case when (place_order.tax ->> 'totalTax') ~ '^[0-9]{1,18}$' then (place_order.tax ->> 'totalTax')::bigint end) is null
      or coalesce(place_order.tax ->> 'currency', v_cart.currency) <> v_cart.currency then
      raise exception 'tax is a quote in the cart''s currency with a totalTax of zero or more' using errcode = '22023', hint = 'ORDERS_TAX_INVALID';
    end if;
    v_tax := (case when (place_order.tax ->> 'totalTax') ~ '^[0-9]{1,18}$' then (place_order.tax ->> 'totalTax')::bigint end);
    v_inclusive := coalesce((place_order.tax ->> 'inclusive')::boolean, false);
    select coalesce(sum((case when (e ->> 'tax') ~ '^[0-9]{1,18}$' then (e ->> 'tax')::bigint end)), 0), coalesce(bool_or((case when (e ->> 'tax') ~ '^[0-9]{1,18}$' then (e ->> 'tax')::bigint end) is null), false)
    into v_line_tax, v_invalid
    from jsonb_array_elements(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) e;
    if v_invalid or (jsonb_array_length(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) > 0 and v_line_tax <> v_tax) then
      raise exception 'the tax lines don''t add up to totalTax' using errcode = '22023', hint = 'ORDERS_TAX_INVALID';
    end if;
  end if;
  v_total := (v_priced ->> 'total')::bigint + case when v_inclusive then 0 else v_tax end;
  declare
    v_limit bigint;
  begin
    select s.credit_limit into v_limit from (select p."credit_limit", p."credit_currency" from "better_supabase"."companies" p where p."id"::text = (select p."id"::text from "better_supabase"."people" p where p."user_id" = v_cart.owner and p."tenant_id" = v_cart.tenant and p."merged_into" is null order by p."created_at" limit 1) and p."tenant_id" = v_cart.tenant and p."merged_into" is null union all select p."credit_limit", p."credit_currency" from "better_supabase"."people" p where p."id"::text = (select p."id"::text from "better_supabase"."people" p where p."user_id" = v_cart.owner and p."tenant_id" = v_cart.tenant and p."merged_into" is null order by p."created_at" limit 1) and p."tenant_id" = v_cart.tenant and p."merged_into" is null) s(credit_limit, credit_currency)
    where s.credit_limit is not null and coalesce(s.credit_currency, v_cart.currency) = v_cart.currency
    order by s.credit_limit limit 1;
    if v_limit is not null and (select coalesce(sum(greatest(x."total" - x."paid_total", 0)), 0) from "better_supabase"."orders" x
      where x."customer_id" = v_cart.owner and x."tenant_id" = v_cart.tenant and x."currency" = v_cart.currency
        and x."status" not in ('cancelled', 'refunded')) + v_total > v_limit and not (coalesce(better_supabase.can_user(v_cart.owner, 'tenant', v_cart.tenant, 'orders.override_credit'), false)) then
      raise exception 'the order takes the customer over their credit limit' using errcode = '55000', hint = 'ORDER_CREDIT_LIMIT_EXCEEDED';
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'order' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_cart.tenant::text || ':commerce:order', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."orders" x where x."tenant_id" = v_cart.tenant;
  v_number := v_seq::text;
  end if;
  insert into "better_supabase"."orders" ("tenant_id", "number", "sequence", "cart_id", "customer_id", "email", "currency",
    "subtotal", "discount_total", "shipping_total", "tax_total", "total", "tax_inclusive",
    "shipping_address", "billing_address", "shipping", "promotions", "tax")
  values (v_cart.tenant, v_number, v_seq, place_order.cart, v_cart.owner, v_cart.email, v_cart.currency,
    (v_priced ->> 'subtotal')::bigint, (v_priced ->> 'discountTotal')::bigint, (v_priced ->> 'shippingTotal')::bigint,
    v_tax, v_total, v_inclusive, v_cart.shipping_address, v_cart.billing_address, v_priced -> 'shipping',
    v_priced -> 'promotions', place_order.tax)
  returning "id" into v_id;
  insert into "better_supabase"."order_lines" ("tenant_id", "order_id", "position", "variant_id", "product_id", "sku", "title",
    "quantity", "unit_amount", "subtotal", "discount", "tax", "total", "requires_shipping")
  select v_cart.tenant, v_id, e.n, (e.l ->> 'variantId')::uuid, (e.l ->> 'productId')::uuid, e.l ->> 'sku', e.l ->> 'title',
    (e.l ->> 'quantity')::integer, (e.l ->> 'unitAmount')::bigint, (e.l ->> 'subtotal')::bigint, (e.l ->> 'discount')::bigint,
    coalesce((select (case when (t ->> 'tax') ~ '^[0-9]{1,18}$' then (t ->> 'tax')::bigint end) from jsonb_array_elements(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) t
      where t ->> 'lineId' = e.l ->> 'id' limit 1), 0),
    (e.l ->> 'total')::bigint, (e.l ->> 'requiresShipping')::boolean
  from jsonb_array_elements(v_priced -> 'lines') with ordinality as e(l, n);
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_id;
  for v_line in
    select x."id" as id, x."variant_id" as variant, x."quantity" as quantity,
      cv."track_inventory" as tracked, cv."allow_backorder" as backorder
    from "better_supabase"."order_lines" x join "better_supabase"."product_variants" cv on cv."id" = x."variant_id"
    where x."order_id" = v_order.id
    order by x."position"
  loop
    continue when not v_line.tracked;
    select loc."id" into v_location
    from "better_supabase"."inventory_locations" loc
    left join "better_supabase"."stock_levels" s on s."location_id" = loc."id" and s."variant_id" = v_line.variant
    where loc."tenant_id" = v_cart.tenant and loc."active" and (place_order.location is null or loc."id" = place_order.location)
    order by (coalesce(s."available", 0) >= v_line.quantity) desc, coalesce(s."available", 0) desc, loc."code"
    limit 1;
    if v_location is null then
      if not v_line.backorder then
        raise exception 'a line is out of stock' using errcode = '23514', hint = 'ORDERS_OUT_OF_STOCK';
      end if;
      update "better_supabase"."order_lines" x set "backordered" = true where x."id" = v_line.id;
      continue;
    end if;
    v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  v_reservation := "better_supabase"."reserve_stock"(v_line.variant, v_location, v_line.quantity, 'order', v_order.id::text, now() + interval '30 minutes');
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    update "better_supabase"."order_lines" x set "location_id" = v_location, "reservation_id" = (v_reservation ->> 'id')::uuid,
      "backordered" = (v_reservation ->> 'available')::numeric < 0
    where x."id" = v_line.id;
  end loop;
  perform "better_supabase"."redeem_promotions"(v_order.id, v_priced -> 'promotions');
  update "better_supabase"."carts" x set "status" = 'converted', "converted_at" = now(), "updated_at" = now()
  where x."id" = place_order.cart;
  perform "better_supabase".emit_event('order.placed', jsonb_build_object('organizationId', v_order.tenant, 'subjectType', 'order', 'subjectId', v_order.id::text, 'id', v_order.id, 'number', v_order.number, 'customerId', v_order.customer, 'currency', v_order.currency, 'subtotal', v_priced ->> 'subtotal', 'discountTotal', v_priced ->> 'discountTotal', 'shippingTotal', v_priced ->> 'shippingTotal', 'taxTotal', v_tax::text, 'total', v_order.total::text, 'units', (select coalesce(sum(l."quantity"), 0)::text from "better_supabase"."order_lines" l where l."order_id" = v_order.id)), 'orders/' || v_order.id::text, (v_order.tenant)::text, null, 'better-supabase/orders');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_order_place"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_order.id;
    end if;
  end;
  return "better_supabase"."order_json"(v_order.id) || jsonb_build_object('created', true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.preview_number (
  p_tenant uuid,
  p_entity text,
  p_at     timestamp with time zone DEFAULT now(),
  p_scope  text                     DEFAULT ''::text
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_format text;
  v_period text;
  v_last bigint;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'numbering.assign'), false)) then
    raise exception 'not allowed to number documents in this tenant' using errcode = '42501', hint = 'NUMBER_FORBIDDEN';
  end if;
  v_format := "better_supabase"."number_format"(p_tenant, p_entity);
  v_period := case p_entity
    when 'drive_document' then ''
    when 'drive_document_sop' then ''
    when 'donation_receipt' then ''
    when 'risk' then ''
    when 'case' then to_char(p_at at time zone 'utc', 'YYYY')
    when 'inspection' then to_char(p_at at time zone 'utc', 'YYYY')
    when 'production_order' then to_char(p_at at time zone 'utc', 'YYYY')
    else null
  end;
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  select s."last_number" into v_last
  from "better_supabase"."number_sequences" s
  where s."tenant_id" = p_tenant
    and s."entity" = p_entity
    and s."scope" = coalesce(p_scope, '')
    and s."period" = v_period;
  return better_supabase.format_assigned_number(v_format, coalesce(v_last, 0) + 1, p_at);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.register_fixed_number (
  p_tenant uuid,
  p_entity text,
  p_number text,
  p_at     timestamp with time zone DEFAULT now(),
  p_scope  text                     DEFAULT ''::text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_format text;
  v_period text;
  v_parts text[];
  v_n bigint;
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_number), '') is null or length(p_number) > 200 then
    raise exception 'a fixed number is 1 to 200 characters' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  v_format := "better_supabase"."number_format"(p_tenant, p_entity);
  v_period := case p_entity
    when 'drive_document' then ''
    when 'drive_document_sop' then ''
    when 'donation_receipt' then ''
    when 'risk' then ''
    when 'case' then to_char(p_at at time zone 'utc', 'YYYY')
    when 'inspection' then to_char(p_at at time zone 'utc', 'YYYY')
    when 'production_order' then to_char(p_at at time zone 'utc', 'YYYY')
    else null
  end;
  if v_format is null or v_period is null then
    raise exception 'unknown number sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;
  v_parts := regexp_match(p_number, better_supabase.number_format_pattern(v_format));
  if v_parts is null or v_parts[1] is null or length(v_parts[1]) > 18 then
    return case
      when p_number ~ '[0-9]{1,18}$' then substring(p_number from '([0-9]{1,18})$')::bigint
      else 0
    end;
  end if;
  v_n := v_parts[1]::bigint;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_tenant::text || ':' || p_entity || ':' || coalesce(p_scope, '') || ':' || v_period, 0));
  insert into "better_supabase"."number_sequences" ("tenant_id", "entity", "scope", "period", "last_number")
  values (p_tenant, p_entity, coalesce(p_scope, ''), v_period, v_n)
  on conflict ("tenant_id", "entity", "scope", "period")
  do update set "last_number" = greatest("better_supabase"."number_sequences"."last_number", excluded."last_number"), "updated_at" = now();
  return v_n;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.schedule_inspection (
  tenant uuid,
  input  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."inspections";
  v_tenant uuid := schedule_inspection.tenant;
  v_kind text;
  v_title text;
  v_program uuid;
  v_start date;
  v_end date;
  v_form uuid;
  v_auditee_type text;
  v_auditee_id text;
  v_lead uuid;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (schedule_inspection.tenant is not null and coalesce(better_supabase.can('tenant', schedule_inspection.tenant, 'inspections.manage'), false))) then
    raise exception 'not allowed to schedule inspections' using errcode = '42501', hint = 'INSPECTION_FORBIDDEN';
  end if;
  if jsonb_typeof(schedule_inspection.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  v_kind := schedule_inspection.input ->> 'kind';
  v_title := trim(schedule_inspection.input ->> 'title');
  v_program := nullif(schedule_inspection.input ->> 'programId', '')::uuid;
  v_start := nullif(schedule_inspection.input ->> 'plannedStart', '')::date;
  v_end := nullif(schedule_inspection.input ->> 'plannedEnd', '')::date;
  v_form := nullif(schedule_inspection.input ->> 'checklistFormId', '')::uuid;
  v_auditee_type := nullif(schedule_inspection.input -> 'auditee' ->> 'type', '');
  v_auditee_id := nullif(schedule_inspection.input -> 'auditee' ->> 'id', '');
  if v_kind is null or not (v_kind = any (array['internal_audit', 'external_audit', 'supplier_audit', 'certification_audit', 'inspection']::text[])) then
    raise exception 'the kind is not one of options.kinds' using errcode = '22023', hint = 'INSPECTION_KIND_UNKNOWN';
  end if;
  if coalesce(length(v_title), 0) not between 1 and 300 then
    raise exception 'an inspection needs a title of 1 to 300 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_end < v_start then
    raise exception 'plannedEnd is on or after plannedStart' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if (v_auditee_type is null) <> (v_auditee_id is null) then
    raise exception 'auditee needs a type and an id' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'scope') > 10000 then
    raise exception 'scope is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if length(schedule_inspection.input ->> 'criteria') > 10000 then
    raise exception 'criteria is at most 10000 characters' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if schedule_inspection.input ? 'fields' and jsonb_typeof(schedule_inspection.input -> 'fields') not in ('object', 'null') then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  if v_program is not null and not exists (
    select 1 from "better_supabase"."inspection_programs" y where y."id" = v_program and y."tenant_id" = v_tenant and y."status" <> 'closed'
  ) then
    raise exception 'no such audit programme in this organization' using errcode = 'P0002', hint = 'INSPECTION_PROGRAM_NOT_FOUND';
  end if;
  if v_form is not null and not exists (
    select 1 from "better_supabase"."forms" y where y."id" = v_form and y."tenant_id"::text = v_tenant::text
  ) then
    raise exception 'the checklist form is not a form of this organization' using errcode = '22023', hint = 'INSPECTION_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_inspection_schedule"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using schedule_inspection.tenant, schedule_inspection.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'inspection' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    v_seq := "better_supabase"."register_fixed_number"(schedule_inspection.tenant, 'inspection', v_number, now(), '');
    perform set_config('better_supabase.fixed_number', '', true);
  else
    v_seq := "better_supabase"."next_number"(schedule_inspection.tenant, 'inspection', now(), '');
  v_number := better_supabase.format_assigned_number('AUD-{yyyy}-{n:3}', v_seq, now());
  end if;
  insert into "better_supabase"."inspections" ("tenant_id", "program_id", "number", "sequence", "kind", "title", "scope", "criteria", "auditee_type", "auditee_id", "planned_start", "planned_end", "checklist_form_id", "created_by")
  values (schedule_inspection.tenant, v_program, v_number, v_seq, v_kind, v_title, nullif(trim(schedule_inspection.input ->> 'scope'), ''), nullif(trim(schedule_inspection.input ->> 'criteria'), ''), v_auditee_type, v_auditee_id, v_start, v_end, v_form, auth.uid())
  returning * into v_row;
  v_lead := "better_supabase"."inspection_set_team"(v_row."id", v_row."tenant_id",
    "better_supabase"."inspection_team_with_lead"(schedule_inspection.input -> 'members', nullif(schedule_inspection.input ->> 'leadId', '')::uuid));
  update "better_supabase"."inspections" x set "lead_id" = v_lead where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('inspection.scheduled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status"), 'inspections/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/inspections');
  perform better_supabase.audit_event(
    event_type => 'inspection.scheduled',
    category => 'data',
    target_type => 'inspection',
    record_id => v_row."id"::text,
    target_label => v_row."title",
    summary => 'inspection scheduled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_inspection_schedule"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'programId', v_row."program_id", 'number', v_row."number", 'kind', v_row."kind", 'title', v_row."title", 'scope', v_row."scope", 'criteria', v_row."criteria", 'auditee', case when v_row."auditee_type" is null then null else jsonb_build_object('type', v_row."auditee_type", 'id', v_row."auditee_id") end, 'leadId', v_row."lead_id", 'plannedStart', v_row."planned_start", 'plannedEnd', v_row."planned_end", 'startedAt', v_row."started_at", 'completedAt', v_row."completed_at", 'closedAt', v_row."closed_at", 'status', v_row."status", 'checklistFormId', v_row."checklist_form_id", 'checklistSubmissionId', v_row."checklist_submission_id", 'summary', v_row."summary", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_fixed_number (
  p_entity text,
  p_number text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
  end if;
  if nullif(btrim(p_entity), '') is null or nullif(btrim(p_number), '') is null then
    raise exception 'name the entity and its number' using errcode = '22023', hint = 'NUMBER_FIXED_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', p_entity || chr(31) || p_number, true);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sync_number_sequences (
  p_tenant uuid DEFAULT NULL::uuid,
  p_entity text DEFAULT NULL::text,
  p_scope  text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows integer := 0;
  v_count integer;
  v_bad jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if p_entity is not null and not (false) then
    raise exception 'no numbered table for this sequence' using errcode = '22023', hint = 'NUMBER_ENTITY_UNKNOWN';
  end if;

  if better_supabase.import_run() is not null and jsonb_array_length(v_bad) > 0 then
    update "better_supabase"."import_runs" r
    set "errors" = r."errors" || (
      select jsonb_agg(jsonb_build_object('entity', b ->> 'entity', 'key', b ->> 'number', 'code', 'NUMBER_FORMAT_MISMATCH', 'severity', 'warning', 'message', 'the number does not match the current format of ' || (b ->> 'entity')))
      from jsonb_array_elements(v_bad) b
    )
    where r."id" = better_supabase.import_run();
  end if;
  return jsonb_build_object('synced', v_rows, 'mismatched', v_bad);
end;
$function$;

ALTER TABLE "better_supabase"."number_sequences"
  ADD CONSTRAINT "number_sequences_pkey" PRIMARY KEY (tenant_id, entity, scope, period);

REVOKE ALL ON FUNCTION "api"."credit_invoice"(uuid, jsonb, text, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."credit_invoice"(uuid, jsonb, text, text, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."issue_invoice"(uuid, date, date, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."issue_invoice"(uuid, date, date, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."credit_invoice"(uuid, jsonb, text, text, date) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."credit_invoice"(uuid, jsonb, text, text, date) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."issue_invoice"(uuid, date, date, jsonb, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."issue_invoice"(uuid, date, date, jsonb, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."next_number"(uuid, text, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."next_number"(uuid, text, timestamp WITH time zone, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."number_scope"(uuid, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."number_scope"(uuid, uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."preview_number"(uuid, text, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."preview_number"(uuid, text, timestamp WITH time zone, text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."register_fixed_number"(uuid, text, text, timestamp WITH time zone, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."register_fixed_number"(uuid, text, text, timestamp WITH time zone, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."set_fixed_number"(text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."set_fixed_number"(text, text) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sync_number_sequences"(uuid, text, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sync_number_sequences"(uuid, text, text) TO "service_role";
