SET local check_function_bodies = off;

DROP FUNCTION "api"."delete_care_rule"(uuid);

DROP FUNCTION "api"."list_care_rules"(uuid);

DROP FUNCTION "better_supabase"."delete_care_rule"(uuid);

DROP FUNCTION "better_supabase"."list_care_rules"(uuid);

ALTER TABLE "better_supabase"."care_rules"
  ADD COLUMN "archived_at" timestamp WITH time zone;

CREATE OR REPLACE FUNCTION api.archive_care_rule (
  rule_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."archive_care_rule"($1) $function$;

CREATE OR REPLACE FUNCTION api.list_care_rules (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."list_care_rules"($1, $2) $function$;

CREATE OR REPLACE FUNCTION api.purge_care_rule (
  rule_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."purge_care_rule"($1) $function$;

CREATE OR REPLACE FUNCTION api.restore_care_rule (
  rule_id uuid
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."restore_care_rule"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.archive_care_rule (
  rule_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_rules" x where x."id" = archive_care_rule.rule_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.read'), false))) then
    raise exception 'no such rule' using errcode = 'P0002', hint = 'DECISION_SUPPORT_RULE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.manage'), false))) then
    raise exception 'not allowed to change care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = true then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."care_rules" x set "archived_at" = now(), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('care_rule.archived', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity"), 'care-rules/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_rule.archived',
    category => 'configuration',
    target_type => 'care_rule',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care rule archived',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.evaluate_care_rules (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_alerts jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (evaluate_care_rules.tenant is not null and coalesce(better_supabase.can('tenant', evaluate_care_rules.tenant, 'clinical_decision_support.write'), false))) then
    raise exception 'not allowed to evaluate care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case evaluate_care_rules.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'warranty_claim' then exists (select 1 from "better_supabase"."warranty_claims" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'advisory' then exists (select 1 from "better_supabase"."advisories" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'advisory_product' then exists (select 1 from "better_supabase"."advisory_products" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'vulnerability' then exists (select 1 from "better_supabase"."vulnerabilities" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."id"::text = evaluate_care_rules.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      else false
    end and "better_supabase"."can_subject"(evaluate_care_rules.subject_type, evaluate_care_rules.subject_id, 'read'))) then
    raise exception 'evaluating needs a record of the organization' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_SUBJECT_INVALID';
  end if;
  with active as (
    select o."id" as order_id, o."medication_id" as medication_id, o."dose" as dose, o."dose_unit" as unit, mx."name" as name,
      coalesce(
        case when o."schedule" ? 'times' then jsonb_array_length(o."schedule" -> 'times') * o."dose"
          when o."schedule" ? 'everyHours' then 24 / nullif((o."schedule" ->> 'everyHours')::numeric, 0) * o."dose" end,
        case when o."as_needed" then o."max_per_day" end) as per_day
    from "better_supabase"."medication_orders" o join "better_supabase"."medications" mx on mx."id" = o."medication_id" and mx."tenant_id" = o."tenant_id"
    where o."tenant_id" = evaluate_care_rules.tenant and o."subject_type" = evaluate_care_rules.subject_type and o."subject_id" = evaluate_care_rules.subject_id
      and o."status" = 'active' and o."starts_on" <= (now() at time zone 'UTC')::date and (o."ends_on" is null or o."ends_on" >= (now() at time zone 'UTC')::date)
  ), raised(alert) as (
      select jsonb_build_object(
        'kind', 'dose_range', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', jsonb_build_array(d.order_id),
        'fingerprint', 'dose_range:' || r."id"::text || ':' || d.order_id::text || ':min',
        'message', coalesce(r."message", format('%s: a dose of %s %s is below the minimum of %s', d.name, d.dose, d.unit, r."min_dose")),
        'details', jsonb_build_object('medicationId', d.medication_id, 'limit', 'min', 'value', d.dose, 'unit', d.unit, 'bound', r."min_dose"))
      from active d join "better_supabase"."care_rules" r on r."medication_ids"[1] = d.medication_id
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."archived_at" is null and r."kind" = 'dose_range' and r."min_dose" is not null and d.dose < r."min_dose"
    union all 
      select jsonb_build_object(
        'kind', 'dose_range', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', jsonb_build_array(d.order_id),
        'fingerprint', 'dose_range:' || r."id"::text || ':' || d.order_id::text || ':max',
        'message', coalesce(r."message", format('%s: a dose of %s %s is above the maximum of %s', d.name, d.dose, d.unit, r."max_dose")),
        'details', jsonb_build_object('medicationId', d.medication_id, 'limit', 'max', 'value', d.dose, 'unit', d.unit, 'bound', r."max_dose"))
      from active d join "better_supabase"."care_rules" r on r."medication_ids"[1] = d.medication_id
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."archived_at" is null and r."kind" = 'dose_range' and r."max_dose" is not null and d.dose > r."max_dose"
    union all 
      select jsonb_build_object(
        'kind', 'dose_range', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', jsonb_build_array(d.order_id),
        'fingerprint', 'dose_range:' || r."id"::text || ':' || d.order_id::text || ':day',
        'message', coalesce(r."message", format('%s: %s %s a day is above the maximum of %s', d.name, d.per_day, d.unit, r."max_per_day")),
        'details', jsonb_build_object('medicationId', d.medication_id, 'limit', 'day', 'value', d.per_day, 'unit', d.unit, 'bound', r."max_per_day"))
      from active d join "better_supabase"."care_rules" r on r."medication_ids"[1] = d.medication_id
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."archived_at" is null and r."kind" = 'dose_range' and r."max_per_day" is not null and d.per_day > r."max_per_day"
    union all
      select jsonb_build_object(
        'kind', 'duplicate_therapy', 'severity', 'warning',
        'orderIds', to_jsonb(array_agg(d.order_id order by d.order_id)),
        'fingerprint', 'duplicate:' || d.medication_id::text,
        'message', format('%s is ordered more than once', min(d.name)),
        'details', jsonb_build_object('medicationId', d.medication_id))
      from active d group by d.medication_id having count(*) > 1
    union all
      select jsonb_build_object(
        'kind', 'duplicate_therapy', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', to_jsonb(array_agg(d.order_id order by d.order_id)),
        'fingerprint', 'therapy_group:' || r."id"::text,
        'message', coalesce(r."message", format('%s are in the same therapy group', string_agg(distinct d.name, ', '))),
        'details', jsonb_build_object('medicationIds', to_jsonb(array_agg(distinct d.medication_id))))
      from "better_supabase"."care_rules" r join active d on d.medication_id = any(r."medication_ids")
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."archived_at" is null and r."kind" = 'duplicate_therapy'
      group by r."id" having count(distinct d.medication_id) > 1
    union all
      select jsonb_build_object(
        'kind', 'interaction', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', (select to_jsonb(array_agg(d.order_id order by d.order_id)) from active d where d.medication_id = any(r."medication_ids")),
        'fingerprint', 'interaction:' || r."id"::text,
        'message', coalesce(r."message", format('%s interact', (select string_agg(distinct d.name, ' and ') from active d where d.medication_id = any(r."medication_ids")))),
        'details', jsonb_build_object('medicationIds', to_jsonb(r."medication_ids")))
      from "better_supabase"."care_rules" r
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."archived_at" is null and r."kind" = 'interaction'
        and (select count(distinct d.medication_id) from active d where d.medication_id = any(r."medication_ids")) = 2
  )
  select coalesce(jsonb_agg(raised.alert), '[]'::jsonb) into v_alerts from raised;
  return "better_supabase"."sync_care_alerts"(evaluate_care_rules.tenant, evaluate_care_rules.subject_type, evaluate_care_rules.subject_id, 'built-in', v_alerts);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_care_rules (
  tenant           uuid,
  include_archived boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_care_rules.tenant is not null and coalesce(better_supabase.can('tenant', list_care_rules.tenant, 'clinical_decision_support.read'), false))) then
    raise exception 'not allowed to read care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'kind', y."kind", 'medicationIds', to_jsonb(y."medication_ids"), 'minDose', y."min_dose", 'maxDose', y."max_dose", 'maxPerDay', y."max_per_day", 'severity', y."severity", 'message', y."message", 'active', y."active", 'createdAt', y."created_at", 'updatedAt', y."updated_at", 'archivedAt', y."archived_at") order by y."kind", y."created_at", y."id")
    from "better_supabase"."care_rules" y
    where y."tenant_id" = list_care_rules.tenant
      and (coalesce(list_care_rules.include_archived, false) or y."archived_at" is null)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purge_care_rule (
  rule_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_rules" x where x."id" = purge_care_rule.rule_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.read'), false))) then
    raise exception 'no such rule' using errcode = 'P0002', hint = 'DECISION_SUPPORT_RULE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.manage'), false))) then
    raise exception 'not allowed to purge care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  delete from "better_supabase"."care_rules" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('care_rule.purged', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity"), 'care-rules/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_rule.purged',
    category => 'configuration',
    target_type => 'care_rule',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care rule purged',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.restore_care_rule (
  rule_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_rules" x where x."id" = restore_care_rule.rule_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.read'), false))) then
    raise exception 'no such rule' using errcode = 'P0002', hint = 'DECISION_SUPPORT_RULE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.manage'), false))) then
    raise exception 'not allowed to change care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  if (v_row."archived_at" is not null) = false then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
  end if;
  update "better_supabase"."care_rules" x set "archived_at" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('care_rule.restored', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity"), 'care-rules/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_rule.restored',
    category => 'configuration',
    target_type => 'care_rule',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care rule restored',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_care_rule (
  tenant uuid,
  attrs  jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_attrs jsonb := coalesce(save_care_rule.attrs, '{}'::jsonb);
  v_row "better_supabase"."care_rules";
  v_id uuid;
  v_kind text;
  v_ids uuid[];
  v_min numeric;
  v_max numeric;
  v_day numeric;
  v_severity text;
  v_message text;
  v_active boolean;
  v_created boolean := false;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_care_rule.tenant is not null and coalesce(better_supabase.can('tenant', save_care_rule.tenant, 'clinical_decision_support.manage'), false))) then
    raise exception 'not allowed to change care rules' using errcode = '42501', hint = 'DECISION_SUPPORT_ALERT_FORBIDDEN';
  end if;
  begin
    v_id := nullif(v_attrs ->> 'id', '')::uuid;
    v_ids := coalesce((select array_agg(distinct e.value::uuid) from jsonb_array_elements_text(case when jsonb_typeof(v_attrs -> 'medicationIds') = 'array' then v_attrs -> 'medicationIds' else '[]'::jsonb end) e), '{}');
    v_min := nullif(v_attrs ->> 'minDose', '')::numeric;
    v_max := nullif(v_attrs ->> 'maxDose', '')::numeric;
    v_day := nullif(v_attrs ->> 'maxPerDay', '')::numeric;
    v_active := coalesce((v_attrs ->> 'active')::boolean, true);
  exception when invalid_text_representation or invalid_parameter_value then
    raise exception 'ids are uuids, doses are numbers and active is true or false' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end;
  v_kind := v_attrs ->> 'kind';
  v_severity := coalesce(nullif(v_attrs ->> 'severity', ''), 'warning');
  v_message := nullif(trim(v_attrs ->> 'message'), '');
  if v_kind is null or v_kind not in ('dose_range', 'duplicate_therapy', 'interaction') then
    raise exception 'kind is dose_range, duplicate_therapy or interaction' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_severity not in ('info', 'warning', 'critical') then
    raise exception 'severity is info, warning or critical' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_message is not null and length(v_message) > 1000 then
    raise exception 'a message is up to 1000 characters' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if (select count(*) from "better_supabase"."medications" mx where mx."tenant_id" = save_care_rule.tenant and mx."id" = any(v_ids)) <> cardinality(v_ids) then
    raise exception 'medicationIds names medications that are not in the organization''s catalog' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind = 'dose_range' and (cardinality(v_ids) <> 1 or (v_min is null and v_max is null and v_day is null)) then
    raise exception 'a dose range rule names one medication and at least one bound' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind = 'dose_range' and v_min is not null and v_max is not null and v_min > v_max then
    raise exception 'minDose is at most maxDose' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind <> 'dose_range' and (v_min is not null or v_max is not null or v_day is not null) then
    raise exception 'only a dose range rule has dose bounds' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind = 'interaction' and cardinality(v_ids) <> 2 then
    raise exception 'an interaction rule names two medications' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  if v_kind = 'duplicate_therapy' and cardinality(v_ids) < 2 then
    raise exception 'a duplicate therapy rule names at least two medications' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."care_rules" ("tenant_id", "kind", "medication_ids", "min_dose", "max_dose", "max_per_day", "severity", "message", "active")
      values (save_care_rule.tenant, v_kind, v_ids, v_min, v_max, v_day, v_severity, v_message, v_active)
      returning * into v_row;
      v_created := true;
    else
      perform 1 from "better_supabase"."care_rules" x where x."id" = v_id and x."tenant_id" = save_care_rule.tenant and x."archived_at" is not null;
      if found then
        raise exception 'the rule is archived; restore it first' using errcode = '55000', hint = 'DECISION_SUPPORT_RULE_ARCHIVED';
      end if;
      update "better_supabase"."care_rules" x set "kind" = v_kind, "medication_ids" = v_ids, "min_dose" = v_min, "max_dose" = v_max,
        "max_per_day" = v_day, "severity" = v_severity, "message" = v_message, "active" = v_active, "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_care_rule.tenant
      returning * into v_row;
      if not found then
        raise exception 'no such rule' using errcode = 'P0002', hint = 'DECISION_SUPPORT_RULE_NOT_FOUND';
      end if;
    end if;
  exception when check_violation then
    raise exception 'the rule''s medications and bounds do not fit its kind' using errcode = '22023', hint = 'DECISION_SUPPORT_ALERT_INVALID';
  end;
  if v_created then
    perform "better_supabase".emit_event('care_rule.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity"), 'care-rules/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_rule.created',
    category => 'configuration',
    target_type => 'care_rule',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care rule created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity")
  );
  else
    perform "better_supabase".emit_event('care_rule.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity"), 'care-rules/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_rule.updated',
    category => 'configuration',
    target_type => 'care_rule',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care rule changed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'archivedAt', v_row."archived_at");
end;
$function$;

REVOKE ALL ON FUNCTION "api"."archive_care_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."archive_care_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."list_care_rules"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."list_care_rules"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purge_care_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purge_care_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."restore_care_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."restore_care_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."archive_care_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."archive_care_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."list_care_rules"(uuid, boolean) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."list_care_rules"(uuid, boolean) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purge_care_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purge_care_rule"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."restore_care_rule"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."restore_care_rule"(uuid) TO "authenticated", "service_role";
