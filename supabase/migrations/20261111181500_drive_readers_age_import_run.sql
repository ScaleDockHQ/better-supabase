SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.evaluate_segment (
  segment uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."segments";
  v_fields jsonb;
  v_now timestamptz := now();
  v_ids text[];
  v_entered text[];
  v_left text[];
  v_id text;
begin
  select * into v_row from "better_supabase"."segments" x where x."id" = evaluate_segment.segment for update;
  if v_row."id" is null then
    return null;
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_row."subject_type");
  if v_row."subject_type" = 'message' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."messages" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'conversation' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."conversations" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'channel' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."channels" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'company' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."companies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'person' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."people" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'deal' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."deals" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'course' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."courses" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'post' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."posts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'activity' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."activities" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'quote' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."quotes" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_item' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_items" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'employee' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."employees" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'invoice' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."invoices" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'ledger_account' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."ledger_accounts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."products" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'product_variant' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."product_variants" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'rfq' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."rfqs" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'till' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."tills" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'calendar_event' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."calendar_events" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'booking' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."bookings" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."assets" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'asset_location' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."asset_locations" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'lease' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."leases" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_report' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_reports" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'expense_line' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."expense_lines" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'donation_fund' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."donation_funds" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'shipment' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."shipments" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'contract' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."contracts" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'control' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."controls" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'compliance_policy' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."compliance_policies" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'qualification_type' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."qualification_types" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'risk' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."risks" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'case' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."cases" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'inspection' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."inspections" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'inspection_program' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."inspection_programs" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'inspection_finding' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."inspection_findings" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'form' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."forms" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'meeting' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."meetings" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'meeting_decision' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."meeting_decisions" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'maintenance_plan' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."maintenance_plans" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'dam_usage_right' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."dam_usage_rights" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'lims_sample' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."lims_samples" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'tax_code' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."tax_codes" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'production_order' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."production_orders" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'work_center' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."work_centers" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'bank_account' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."bank_accounts" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'care_plan' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."care_plans" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'incident' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."incidents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'content_entry' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."content_entries" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'document' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."documents" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'customer' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."customers" s
      where s."organization_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'drive_node' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."drive_nodes" s
      where s."tenant_id" = v_row."tenant_id" and s."archived_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'organization' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."organizations" s
      where s."id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'application' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "better_supabase"."applications" s
      where s."tenant_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'change_request' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."change_requests" s
      where s."organization_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'project' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."projects" s
      where s."organization_id" = v_row."tenant_id" and s."deleted_at" is null
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  elsif v_row."subject_type" = 'task' then
    select coalesce(array_agg(x.id order by x.id), '{}') into v_ids from (
      select s."id"::text as id from "public"."tasks" s
      where s."organization_id" = v_row."tenant_id"
        and "better_supabase"."rule_matches"(v_row."conditions", to_jsonb(s), v_fields, 'UTC', v_now)
      limit 10001
    ) x;
  else
    raise exception 'The segment''s subject type is not registered in config.recordTypes' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  if cardinality(v_ids) > 10000 then
    raise exception 'A segment holds at most 10000 records; narrow its conditions' using errcode = '54000', hint = 'SEGMENT_TOO_LARGE';
  end if;
  with gone as (
    delete from "better_supabase"."segment_members" y
    where y."segment_id" = v_row."id" and not (y."subject_id" = any (v_ids))
    returning y."subject_id" as id
  ), added as (
    insert into "better_supabase"."segment_members" ("segment_id", "tenant_id", "subject_id", "entered_at")
    select v_row."id", v_row."tenant_id", z, v_now from unnest(v_ids) z
    on conflict do nothing
    returning "subject_id" as id
  )
  select coalesce((select array_agg(g.id order by g.id) from gone g), '{}'),
    coalesce((select array_agg(a.id order by a.id) from added a), '{}')
  into v_left, v_entered;
  foreach v_id in array v_entered loop
    perform "better_supabase".emit_event('segment.entered', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.entered:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  foreach v_id in array v_left loop
    perform "better_supabase".emit_event('segment.left', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_id), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, 'segment.left:' || v_row."id"::text || ':' || v_id || ':' || extract(epoch from v_now)::text, 'better-supabase/segments');
  end loop;
  update "better_supabase"."segments" x set "member_count" = cardinality(v_ids), "refreshed_at" = v_now
  where x."id" = v_row."id";
  return jsonb_build_object('entered', cardinality(v_entered), 'left', cardinality(v_left), 'memberCount', cardinality(v_ids));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.move (
  subject_type text,
  subject_id   text,
  previous_id  text,
  next_id      text,
  to_group     text
)
  RETURNS text
  LANGUAGE plpgsql
  SET search_path TO ''
  AS $function$
declare
  v_tenant text;
  v_group text;
  v_other_tenant text;
  v_other_group text;
  v_previous text;
  v_next text;
  v_key text;
begin
  if not "better_supabase"."can_subject"(move.subject_type, move.subject_id, 'write') then
    raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
  end if;
  case move.subject_type
    when 'deal' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."deals" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."deals" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."deals" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."deals" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."deals", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    when 'work_item' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."work_items" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."work_items" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."work_items" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."work_items" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."work_items", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    when 'case' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."cases" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."cases" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."cases" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."cases" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."cases", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    when 'application' then
      select s."tenant_id"::text, s."stage_id"::text
        into v_tenant, v_group
        from "better_supabase"."applications" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_previous, v_other_tenant, v_other_group
          from "better_supabase"."applications" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."tenant_id"::text, s."stage_id"::text
          into v_next, v_other_tenant, v_other_group
          from "better_supabase"."applications" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "better_supabase"."applications" s set "rank" = v_key, "stage_id" = (jsonb_populate_record(null::"better_supabase"."applications", jsonb_build_object('stage_id', v_group)))."stage_id"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    when 'task' then
      select s."organization_id"::text, s."status"::text
        into v_tenant, v_group
        from "public"."tasks" s where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'row not found' using errcode = 'P0002', hint = 'RANK_NOT_FOUND';
      end if;
      v_group := coalesce(move.to_group, v_group);
      if move.previous_id is not null then
        select s."rank", s."organization_id"::text, s."status"::text
          into v_previous, v_other_tenant, v_other_group
          from "public"."tasks" s where s."id" = (move.previous_id)::uuid;
        if not found then
          raise exception 'the previous row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the previous row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if move.next_id is not null then
        select s."rank", s."organization_id"::text, s."status"::text
          into v_next, v_other_tenant, v_other_group
          from "public"."tasks" s where s."id" = (move.next_id)::uuid;
        if not found then
          raise exception 'the next row was not found' using errcode = 'P0002', hint = 'RANK_NEIGHBOR_NOT_FOUND';
        end if;
        if v_other_tenant is distinct from v_tenant or v_other_group is distinct from v_group then
          raise exception 'the next row is in another tenant or group' using errcode = '22023', hint = 'RANK_NEIGHBOR_MISMATCH';
        end if;
      end if;
      if v_previous is not null and v_next is not null and v_previous collate "C" >= v_next collate "C" then
        raise exception 'the neighbours share a rank key; rebalance the group first' using errcode = '22023', hint = 'RANK_CONFLICT';
      end if;
      v_key := "better_supabase"."rank_between"(v_previous, v_next);
      update "public"."tasks" s set "rank" = v_key, "status" = (jsonb_populate_record(null::"public"."tasks", jsonb_build_object('status', v_group)))."status"
        where s."id" = (move.subject_id)::uuid;
      if not found then
        raise exception 'not allowed to move this row' using errcode = '42501', hint = 'RANK_FORBIDDEN';
      end if;
    else
      raise exception 'this subject type has no rank column in config.recordTypes' using errcode = '22023', hint = 'RANK_SUBJECT_UNKNOWN';
  end case;
  if length(v_key) > 24 then
    perform "better_supabase"."enqueue_job"(queue => 'rank.rebalance', payload => jsonb_build_object('subjectType', move.subject_type, 'tenant', v_tenant, 'group', v_group), dedupe_key => 'rank:' || move.subject_type || ':' || coalesce(v_tenant, '') || ':' || coalesce(v_group, ''), dedupe_running => false);
  end if;
  return v_key;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.rebalance_ranks (
  subject_type text,
  tenant       text,
  rank_group   text
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_count integer := 0;
begin
  case rebalance_ranks.subject_type
    when 'deal' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."deals" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."deals" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    when 'work_item' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."work_items" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."work_items" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    when 'case' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."cases" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."cases" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    when 'application' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."stage_id" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."stage_id") as total
        from "better_supabase"."applications" s
        where s."tenant_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."stage_id"::text = rebalance_ranks.rank_group)
      )
      update "better_supabase"."applications" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    when 'task' then
      with ordered as (
        select s."id" as row_id,
          row_number() over (partition by s."status" order by s."rank" collate "C", s."id") as nth,
          count(*) over (partition by s."status") as total
        from "public"."tasks" s
        where s."organization_id"::text = rebalance_ranks.tenant
          and (rebalance_ranks.rank_group is null or s."status"::text = rebalance_ranks.rank_group)
      )
      update "public"."tasks" t set "rank" = "better_supabase"."rank_key"(o.nth, o.total)
      from ordered o
      where t."id" = o.row_id;
      get diagnostics v_count = row_count;
    else
      raise exception 'this subject type has no rank column in config.recordTypes' using errcode = '22023', hint = 'RANK_SUBJECT_UNKNOWN';
  end case;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_subject_export (
  subject_type text,
  subject_id   text,
  format       text DEFAULT 'ndjson'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."data_exports";
  v_tenant uuid;
  v_record jsonb;
  v_name text;
  v_reveal text;
  v_reveal_schema text;
  v_proc text;
  v_arg text;
  v_sealed text[];
  v_plain jsonb;
  v_rows jsonb;
  v_fields jsonb;
  v_parts jsonb := '{}'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'Sign in to export data' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  if request_subject_export.format is null or request_subject_export.format not in ('ndjson', 'csv') then
    raise exception 'format must be ndjson or csv' using errcode = '22023', hint = 'DATA_EXPORT_FORMAT';
  end if;
  case request_subject_export.subject_type
    when 'message' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."messages" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.messages';
      v_reveal := 'messages_reveal';
      v_reveal_schema := 'better_supabase';
    when 'conversation' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."conversations" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.conversations';
      v_reveal := 'conversations_reveal';
      v_reveal_schema := 'better_supabase';
    when 'channel' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."channels" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.channels';
      v_reveal := 'channels_reveal';
      v_reveal_schema := 'better_supabase';
    when 'company' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."companies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.companies';
      v_reveal := 'companies_reveal';
      v_reveal_schema := 'better_supabase';
    when 'person' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."people" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.people';
      v_reveal := 'people_reveal';
      v_reveal_schema := 'better_supabase';
    when 'deal' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."deals" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.deals';
      v_reveal := 'deals_reveal';
      v_reveal_schema := 'better_supabase';
    when 'course' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."courses" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.courses';
      v_reveal := 'courses_reveal';
      v_reveal_schema := 'better_supabase';
    when 'post' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."posts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.posts';
      v_reveal := 'posts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'activity' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."activities" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.activities';
      v_reveal := 'activities_reveal';
      v_reveal_schema := 'better_supabase';
    when 'quote' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."quotes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.quotes';
      v_reveal := 'quotes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_item' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_items" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_items';
      v_reveal := 'work_items_reveal';
      v_reveal_schema := 'better_supabase';
    when 'employee' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."employees" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.employees';
      v_reveal := 'employees_reveal';
      v_reveal_schema := 'better_supabase';
    when 'invoice' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."invoices" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.invoices';
      v_reveal := 'invoices_reveal';
      v_reveal_schema := 'better_supabase';
    when 'ledger_account' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."ledger_accounts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.ledger_accounts';
      v_reveal := 'ledger_accounts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'product' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."products" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.products';
      v_reveal := 'products_reveal';
      v_reveal_schema := 'better_supabase';
    when 'product_variant' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."product_variants" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.product_variants';
      v_reveal := 'product_variants_reveal';
      v_reveal_schema := 'better_supabase';
    when 'rfq' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."rfqs" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.rfqs';
      v_reveal := 'rfqs_reveal';
      v_reveal_schema := 'better_supabase';
    when 'till' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."tills" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.tills';
      v_reveal := 'tills_reveal';
      v_reveal_schema := 'better_supabase';
    when 'order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.orders';
      v_reveal := 'orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'calendar_event' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."calendar_events" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.calendar_events';
      v_reveal := 'calendar_events_reveal';
      v_reveal_schema := 'better_supabase';
    when 'booking' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."bookings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.bookings';
      v_reveal := 'bookings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'asset' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."assets" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.assets';
      v_reveal := 'assets_reveal';
      v_reveal_schema := 'better_supabase';
    when 'asset_location' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."asset_locations" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.asset_locations';
      v_reveal := 'asset_locations_reveal';
      v_reveal_schema := 'better_supabase';
    when 'lease' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."leases" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.leases';
      v_reveal := 'leases_reveal';
      v_reveal_schema := 'better_supabase';
    when 'expense_report' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."expense_reports" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.expense_reports';
      v_reveal := 'expense_reports_reveal';
      v_reveal_schema := 'better_supabase';
    when 'expense_line' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."expense_lines" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.expense_lines';
      v_reveal := 'expense_lines_reveal';
      v_reveal_schema := 'better_supabase';
    when 'donation_fund' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."donation_funds" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.donation_funds';
      v_reveal := 'donation_funds_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_orders';
      v_reveal := 'work_orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'shipment' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."shipments" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.shipments';
      v_reveal := 'shipments_reveal';
      v_reveal_schema := 'better_supabase';
    when 'contract' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."contracts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.contracts';
      v_reveal := 'contracts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'control' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."controls" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.controls';
      v_reveal := 'controls_reveal';
      v_reveal_schema := 'better_supabase';
    when 'compliance_policy' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."compliance_policies" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.compliance_policies';
      v_reveal := 'compliance_policies_reveal';
      v_reveal_schema := 'better_supabase';
    when 'qualification_type' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."qualification_types" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.qualification_types';
      v_reveal := 'qualification_types_reveal';
      v_reveal_schema := 'better_supabase';
    when 'risk' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."risks" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.risks';
      v_reveal := 'risks_reveal';
      v_reveal_schema := 'better_supabase';
    when 'case' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."cases" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.cases';
      v_reveal := 'cases_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspections" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspections';
      v_reveal := 'inspections_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection_program' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspection_programs" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspection_programs';
      v_reveal := 'inspection_programs_reveal';
      v_reveal_schema := 'better_supabase';
    when 'inspection_finding' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."inspection_findings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.inspection_findings';
      v_reveal := 'inspection_findings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'form' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."forms" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.forms';
      v_reveal := 'forms_reveal';
      v_reveal_schema := 'better_supabase';
    when 'meeting' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."meetings" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.meetings';
      v_reveal := 'meetings_reveal';
      v_reveal_schema := 'better_supabase';
    when 'meeting_decision' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."meeting_decisions" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.meeting_decisions';
      v_reveal := 'meeting_decisions_reveal';
      v_reveal_schema := 'better_supabase';
    when 'maintenance_plan' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."maintenance_plans" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.maintenance_plans';
      v_reveal := 'maintenance_plans_reveal';
      v_reveal_schema := 'better_supabase';
    when 'dam_usage_right' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."dam_usage_rights" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.dam_usage_rights';
      v_reveal := 'dam_usage_rights_reveal';
      v_reveal_schema := 'better_supabase';
    when 'lims_sample' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."lims_samples" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.lims_samples';
      v_reveal := 'lims_samples_reveal';
      v_reveal_schema := 'better_supabase';
    when 'tax_code' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."tax_codes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.tax_codes';
      v_reveal := 'tax_codes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'production_order' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."production_orders" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.production_orders';
      v_reveal := 'production_orders_reveal';
      v_reveal_schema := 'better_supabase';
    when 'work_center' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."work_centers" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.work_centers';
      v_reveal := 'work_centers_reveal';
      v_reveal_schema := 'better_supabase';
    when 'bank_account' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."bank_accounts" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.bank_accounts';
      v_reveal := 'bank_accounts_reveal';
      v_reveal_schema := 'better_supabase';
    when 'care_plan' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."care_plans" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.care_plans';
      v_reveal := 'care_plans_reveal';
      v_reveal_schema := 'better_supabase';
    when 'incident' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."incidents" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.incidents';
      v_reveal := 'incidents_reveal';
      v_reveal_schema := 'better_supabase';
    when 'content_entry' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."content_entries" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.content_entries';
      v_reveal := 'content_entries_reveal';
      v_reveal_schema := 'better_supabase';
    when 'document' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."documents" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.documents';
      v_reveal := 'documents_reveal';
      v_reveal_schema := 'better_supabase';
    when 'customer' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."customers" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.customers';
      v_reveal := 'customers_reveal';
      v_reveal_schema := 'public';
    when 'drive_node' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."drive_nodes" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.drive_nodes';
      v_reveal := 'drive_nodes_reveal';
      v_reveal_schema := 'better_supabase';
    when 'organization' then
      select to_jsonb(s.*), s."id" into v_record, v_tenant
      from "public"."organizations" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.organizations';
      v_reveal := 'organizations_reveal';
      v_reveal_schema := 'public';
    when 'application' then
      select to_jsonb(s.*), s."tenant_id" into v_record, v_tenant
      from "better_supabase"."applications" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'better_supabase.applications';
      v_reveal := 'applications_reveal';
      v_reveal_schema := 'better_supabase';
    when 'change_request' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."change_requests" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.change_requests';
      v_reveal := 'change_requests_reveal';
      v_reveal_schema := 'public';
    when 'project' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."projects" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.projects';
      v_reveal := 'projects_reveal';
      v_reveal_schema := 'public';
    when 'task' then
      select to_jsonb(s.*), s."organization_id" into v_record, v_tenant
      from "public"."tasks" s where s."id" = (request_subject_export.subject_id)::uuid;
      v_name := 'public.tasks';
      v_reveal := 'tasks_reveal';
      v_reveal_schema := 'public';
    else
      raise exception 'subject_type is not a record type in config.recordTypes' using errcode = '22023', hint = 'DATA_EXPORT_SUBJECT';
  end case;
  if v_record is null or not ((v_tenant is not null and coalesce(better_supabase.can('tenant', v_tenant, 'data_lifecycle.export'), false))) then
    raise exception 'You may not export this record' using errcode = '42501', hint = 'DATA_EXPORT_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."data_exports" x
  where x."subject" = 'record' and x."subject_type" = request_subject_export.subject_type
    and x."subject_id" = request_subject_export.subject_id and x."requested_by" = auth.uid()
    and x."status" in ('pending', 'running');
  if v_row."id" is not null then
    return to_jsonb(v_row);
  end if;
  -- Only the owner's reveal function, so one another role created never runs
  -- with this function's rights.
  select pg_catalog.format('%I.%I', n.nspname, p.proname), pg_catalog.format_type(p.proargtypes[0], null),
    array(select a.name from unnest(p.proargnames, p.proargmodes::text[]) with ordinality a(name, mode, n)
      where a.mode = 't' order by a.n offset 1)
  into v_proc, v_arg, v_sealed
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = v_reveal_schema and p.proname = v_reveal and p.pronargs = 1
    and p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)
  limit 1;
  -- The stored ciphertext never leaves: a caller the reveal returns no row
  -- for gets the record without its encrypted columns.
  if v_proc is not null then
    execute format('select to_jsonb(r.*) from %s(array[$1]::%s) r', v_proc, v_arg) into v_plain
    using request_subject_export.subject_id;
    v_record := (v_record - coalesce(v_sealed, '{}'::text[])) || coalesce(v_plain, '{}'::jsonb);
  end if;
  v_parts := jsonb_build_object(v_name, jsonb_build_array(v_record));
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."notification_events" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.notification_events', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."notification_subscriptions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.notification_subscriptions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."guest_grants" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.guest_grants', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."attachments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.attachments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."enrollments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.enrollments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."workflow_runs" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.workflow_runs', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."workflow_start_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.workflow_start_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."knowledge_documents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.knowledge_documents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."memories" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.memories', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."taggings" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.taggings', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."status_history" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.status_history', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."status_stages" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.status_stages', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."subject_lifecycles" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.subject_lifecycles', v_rows);
  end if;
  if v_tenant is not null then
    v_fields := coalesce("better_supabase"."read_field_values"(v_tenant, request_subject_export.subject_type, request_subject_export.subject_id), '[]'::jsonb);
    select coalesce(jsonb_agg(((to_jsonb(t.*)) || jsonb_build_object('value_text', f.value ->> 'text')) order by t.ctid), '[]'::jsonb) into v_rows
    from "better_supabase"."field_values" t
    join jsonb_array_elements(v_fields) f on f.value ->> 'id' = t."id"::text
    where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
    if jsonb_array_length(v_rows) > 0 then
      v_parts := v_parts || jsonb_build_object('better_supabase.field_values', v_rows);
    end if;
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*) - array['token_hash', 'password_hash']::text[]) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."share_links" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.share_links', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."recurrence_rules" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.recurrence_rules', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reminders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reminders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."import_records" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.import_records', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."subject_members" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.subject_members', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."calendar_events" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.calendar_events', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."versions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.versions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."trash_items" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.trash_items', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reactions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reactions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."reaction_scores" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.reaction_scores', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."approval_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.approval_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."access_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.access_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."documents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.documents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."form_submissions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.form_submissions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."signature_requests" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.signature_requests', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."time_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.time_entries', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."template_applications" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.template_applications', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."pipeline_stage_history" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.pipeline_stage_history', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."activity_subjects" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.activity_subjects', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."sla_clocks" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.sla_clocks', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."moderation_items" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.moderation_items', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."moderation_notices" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.moderation_notices', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."automation_evaluations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.automation_evaluations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."scores" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.scores', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."passes" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.passes', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."time_rates" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.time_rates', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."work_orders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.work_orders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."shipments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.shipments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."conversations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.conversations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."message_record_mentions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.message_record_mentions', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."channels" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.channels', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."timeline_entries" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.timeline_entries', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."mail_thread_subjects" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.mail_thread_subjects', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.assignments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."field_changes" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.field_changes', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgement_assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgement_assignments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgements" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgements', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."acknowledgement_notices" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.acknowledgement_notices', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."consents" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.consents', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."consent_signals" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.consent_signals', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."consent_receipts" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.consent_receipts', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."observations" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.observations', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."medication_orders" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.medication_orders', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."care_plans" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.care_plans', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."funding_awards" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.funding_awards', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."care_alerts" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.care_alerts', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."deadlines" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.deadlines', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."commission_assignments" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.commission_assignments', v_rows);
  end if;
  select coalesce(jsonb_agg((to_jsonb(t.*)) order by t.ctid), '[]'::jsonb) into v_rows
  from "better_supabase"."prescriptions" t where t."subject_type"::text = request_subject_export.subject_type and t."subject_id"::text = request_subject_export.subject_id and (v_tenant is null or t."tenant_id"::text = v_tenant::text);
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object('better_supabase.prescriptions', v_rows);
  end if;
  insert into "better_supabase"."data_exports" ("subject", "tenant_id", "subject_type", "subject_id", "format")
  values ('record', v_tenant, request_subject_export.subject_type, request_subject_export.subject_id, request_subject_export.format)
  returning * into v_row;
  insert into "better_supabase"."data_export_contents" ("export_id", "parts") values (v_row."id", v_parts);
  perform "better_supabase".emit_event('data_export.requested', jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id"), 'data-exports/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/data-lifecycle');
  perform better_supabase.audit_event(
    event_type => 'data_export.requested',
    category => 'data',
    target_type => 'data_export',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('exportId', v_row."id", 'subject', v_row."subject", 'organizationId', v_row."tenant_id"::text, 'userId', v_row."user_id", 'requestedBy', v_row."requested_by", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id")
  );
  return to_jsonb(v_row);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_segment (
  tenant  uuid,
  segment jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
  v_old "better_supabase"."segments";
  v_row "better_supabase"."segments";
  v_type text;
  v_name text;
  v_description text;
  v_conditions jsonb;
  v_fields jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not coalesce(better_supabase.can('tenant', save_segment.tenant, 'segments.write'), false) then
    raise exception 'You need segments.edit to save a segment' using errcode = '42501', hint = 'SEGMENT_FORBIDDEN';
  end if;
  if jsonb_typeof(segment) is distinct from 'object' then
    raise exception 'segment must be an object' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_id := nullif(segment ->> 'id', '')::uuid;
  if v_id is not null then
    select * into v_old from "better_supabase"."segments" x
    where x."id" = v_id and x."tenant_id" = save_segment.tenant for update;
    if v_old."id" is null then
      raise exception 'No segment in this organization has this id' using errcode = 'P0002', hint = 'SEGMENT_NOT_FOUND';
    end if;
    if segment ? 'subjectType' and segment ->> 'subjectType' is distinct from v_old."subject_type" then
      raise exception 'A segment''s subject type can''t change' using errcode = '22023', hint = 'SEGMENT_INVALID';
    end if;
  end if;
  v_type := coalesce(v_old."subject_type", segment ->> 'subjectType');
  if v_type is null or v_type not in ('message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'activity', 'quote', 'work_item', 'employee', 'invoice', 'ledger_account', 'product', 'product_variant', 'rfq', 'till', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'qualification_type', 'risk', 'case', 'inspection', 'inspection_program', 'inspection_finding', 'form', 'meeting', 'meeting_decision', 'maintenance_plan', 'dam_usage_right', 'lims_sample', 'tax_code', 'production_order', 'work_center', 'bank_account', 'care_plan', 'incident', 'content_entry', 'document', 'customer', 'drive_node', 'organization', 'application', 'change_request', 'project', 'task') then
    raise exception 'subjectType must be a type in config.recordTypes' using errcode = '22023', hint = 'SEGMENT_SUBJECT_UNKNOWN';
  end if;
  v_name := coalesce(nullif(trim(segment ->> 'name'), ''), v_old."name");
  if v_name is null or length(v_name) > 200 then
    raise exception 'A segment needs a name of at most 200 characters' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_description := case when segment ? 'description' then nullif(trim(segment ->> 'description'), '') else v_old."description" end;
  v_conditions := coalesce(segment -> 'conditions', v_old."conditions");
  if jsonb_typeof(v_conditions) is distinct from 'object' then
    raise exception 'A segment needs conditions, a filter tree' using errcode = '22023', hint = 'SEGMENT_INVALID';
  end if;
  v_fields := "better_supabase"."rule_field_map"(v_type);
  if v_fields = '{}'::jsonb then
    raise exception 'No rule fields for this subject type; sync them first' using errcode = '22023', hint = 'SEGMENT_FIELDS_MISSING';
  end if;
  perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  if v_old."id" is null then
    insert into "better_supabase"."segments" ("tenant_id", "name", "description", "subject_type", "conditions", "created_by")
    values (save_segment.tenant, v_name, v_description, v_type, v_conditions, auth.uid())
    returning * into v_row;
  elsif v_old."name" = v_name and v_old."description" is not distinct from v_description
    and v_old."conditions" = v_conditions then
    return jsonb_build_object('id', v_old."id", 'organizationId', v_old."tenant_id", 'name', v_old."name", 'description', v_old."description", 'subjectType', v_old."subject_type", 'conditions', v_old."conditions", 'memberCount', v_old."member_count", 'refreshedAt', v_old."refreshed_at", 'createdBy', v_old."created_by", 'createdAt', v_old."created_at", 'updatedAt', v_old."updated_at");
  else
    update "better_supabase"."segments" x set
      "name" = v_name,
      "description" = v_description,
      "conditions" = v_conditions,
      "refreshed_at" = case when x."conditions" = v_conditions then x."refreshed_at" end,
      "updated_at" = now()
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('segment.created', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.created',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  else
    perform "better_supabase".emit_event('segment.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name"), 'segments/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/segments');
  perform better_supabase.audit_event(
    event_type => 'segment.updated',
    category => 'data',
    target_type => 'segment',
    record_id => v_row."id"::text,
    target_label => v_row."name",
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'segmentId', v_row."id", 'subjectType', v_row."subject_type", 'name', v_row."name")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'name', v_row."name", 'description', v_row."description", 'subjectType', v_row."subject_type", 'conditions', v_row."conditions", 'memberCount', v_row."member_count", 'refreshedAt', v_row."refreshed_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
exception when unique_violation then
  raise exception 'Another segment in this organization has this name' using errcode = '23505', hint = 'SEGMENT_NAME_TAKEN';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_refresh (
  subject_type text,
  subject_id   text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_title text;
  v_body text;
  v_url text;
  v_found boolean := false;
  v_hash text;
begin
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  case search_refresh.subject_type
    when 'message' then
      select s."tenant_id", s."body"::text, null, null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."messages" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'channel' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."topic"::text, s."purpose"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."channels" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'company' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."domain"::text), ''), '/crm/contacts/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."companies" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'person' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."title"::text), ''), '/crm/contacts/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."people" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'deal' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."note"::text), ''), '/crm/deals'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."deals" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'course' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."courses" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'post' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."posts" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'activity' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."body"::text, s."outcome"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."activities" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'work_item' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."identifier"::text, s."body"::text), ''), '/work'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."work_items" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'employee' then
      select s."tenant_id", s."name"::text, nullif(concat_ws(E'\n', s."email"::text, s."job_title"::text), ''), '/people'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."employees" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."slug"::text), ''), '/shop'
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."products" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'product_variant' then
      select s."tenant_id", s."sku"::text, nullif(concat_ws(E'\n', s."title"::text, s."barcode"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."product_variants" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'calendar_event' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."description"::text, s."location"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."calendar_events" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'risk' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."cause"::text, s."consequence"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."risks" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'case' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."description"::text, s."root_cause"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."cases" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'inspection' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."number"::text, s."scope"::text, s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."inspections" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'meeting' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."location"::text, s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."meetings" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'production_order' then
      select s."tenant_id", s."number"::text, nullif(concat_ws(E'\n', s."note"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."production_orders" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'content_entry' then
      select s."tenant_id", s."title"::text, nullif(concat_ws(E'\n', s."summary"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."content_entries" s
        where s."id" = (search_refresh.subject_id)::uuid;
      v_found := found;
    when 'customer' then
      select s."organization_id", s."name"::text, null, '/customers/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."customers" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'drive_node' then
      select s."tenant_id", f."name"::text, nullif(concat_ws(E'\n', f."content"::text), ''), null
        into v_tenant, v_title, v_body, v_url
        from "better_supabase"."drive_nodes" s
        join "better_supabase"."drive_node_search" f on f."id" = s."id"
        where s."id" = (search_refresh.subject_id)::uuid
        and f."id" = (search_refresh.subject_id)::uuid
        and s."archived_at" is null;
      v_found := found;
    when 'project' then
      select s."organization_id", s."name"::text, null, '/projects/' || s."id"::text
        into v_tenant, v_title, v_body, v_url
        from "public"."projects" s
        where s."id" = (search_refresh.subject_id)::uuid
        and s."deleted_at" is null;
      v_found := found;
    else
      raise exception 'this subject type has no search entry in config.recordTypes' using errcode = '22023', hint = 'SEARCH_SUBJECT_UNKNOWN';
  end case;
  if not v_found then
    delete from "better_supabase"."search_documents"
    where "subject_type" = search_refresh.subject_type and "subject_id" = search_refresh.subject_id;
    return false;
  end if;
  v_hash := md5(coalesce(v_title, '') || E'\x1f' || coalesce(v_body, ''));
  insert into "better_supabase"."search_documents" ("tenant_id", "subject_type", "subject_id", "title", "title_search", "body", "url", "tsv", "content_hash", "updated_at")
  values (
    v_tenant, search_refresh.subject_type, search_refresh.subject_id, v_title, "better_supabase"."search_normalize"(v_title), v_body, v_url,
    setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_title)), 'A')
      || setweight(to_tsvector('simple', "better_supabase"."search_normalize"(v_body)), 'B'),
    v_hash, now()
  )
  on conflict ("subject_type", "subject_id") do update set
    "tenant_id" = excluded."tenant_id",
    "title" = excluded."title",
    "title_search" = excluded."title_search",
    "body" = excluded."body",
    "url" = excluded."url",
    "tsv" = excluded."tsv",
    "content_hash" = excluded."content_hash",
    "updated_at" = now()
  where ("better_supabase"."search_documents"."tenant_id", "better_supabase"."search_documents"."title", "better_supabase"."search_documents"."body", "better_supabase"."search_documents"."url")
    is distinct from (excluded."tenant_id", excluded."title", excluded."body", excluded."url");
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_search_document_index"(text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::text, $2::text)', v_hook::oid::regproc)
        using search_refresh.subject_type, search_refresh.subject_id;
    end if;
  end;
  return true;
end;
$function$;
