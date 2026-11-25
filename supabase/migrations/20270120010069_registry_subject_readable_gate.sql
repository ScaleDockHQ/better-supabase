SET local check_function_bodies = off;

DROP POLICY "bsb_consents_read" ON "better_supabase"."consents";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."consents";

DROP POLICY "bsb_field_changes_read" ON "better_supabase"."field_changes";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."field_changes";

DROP POLICY "bsb_funding_awards_read" ON "better_supabase"."funding_awards";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_awards";

DROP POLICY "bsb_funding_deliveries_read" ON "better_supabase"."funding_deliveries";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_deliveries";

DROP POLICY "bsb_medication_orders_read" ON "better_supabase"."medication_orders";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_orders";

DROP POLICY "bsb_observations_read" ON "better_supabase"."observations";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."observations";

DROP POLICY "bsb_pipeline_stage_history_read" ON "better_supabase"."pipeline_stage_history";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."pipeline_stage_history";

DROP POLICY "bsb_sla_clocks_read" ON "better_supabase"."sla_clocks";

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."sla_clocks";

CREATE OR REPLACE FUNCTION better_supabase.consents_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case consents_subject_readable.subject_type
    when 'message' then return coalesce(exists (select 1 from "better_supabase"."messages" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'conversation' then return coalesce(exists (select 1 from "better_supabase"."conversations" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'channel' then return coalesce(exists (select 1 from "better_supabase"."channels" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'company' then return coalesce(exists (select 1 from "better_supabase"."companies" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'person' then return coalesce(exists (select 1 from "better_supabase"."people" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'deal' then return coalesce(exists (select 1 from "better_supabase"."deals" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'course' then return coalesce(exists (select 1 from "better_supabase"."courses" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'post' then return coalesce(exists (select 1 from "better_supabase"."posts" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'activity' then return coalesce(exists (select 1 from "better_supabase"."activities" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'quote' then return coalesce(exists (select 1 from "better_supabase"."quotes" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'work_item' then return coalesce(exists (select 1 from "better_supabase"."work_items" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'employee' then return coalesce(exists (select 1 from "better_supabase"."employees" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'ledger_account' then return coalesce(exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'invoice' then return coalesce(exists (select 1 from "better_supabase"."invoices" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'product' then return coalesce(exists (select 1 from "better_supabase"."products" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'product_variant' then return coalesce(exists (select 1 from "better_supabase"."product_variants" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'order' then return coalesce(exists (select 1 from "better_supabase"."orders" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'calendar_event' then return coalesce(exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'booking' then return coalesce(exists (select 1 from "better_supabase"."bookings" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'asset' then return coalesce(exists (select 1 from "better_supabase"."assets" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'asset_location' then return coalesce(exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'lease' then return coalesce(exists (select 1 from "better_supabase"."leases" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'expense_report' then return coalesce(exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'expense_line' then return coalesce(exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'donation_fund' then return coalesce(exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'work_order' then return coalesce(exists (select 1 from "better_supabase"."work_orders" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'shipment' then return coalesce(exists (select 1 from "better_supabase"."shipments" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'contract' then return coalesce(exists (select 1 from "better_supabase"."contracts" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'control' then return coalesce(exists (select 1 from "better_supabase"."controls" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'compliance_policy' then return coalesce(exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'qualification_type' then return coalesce(exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'risk' then return coalesce(exists (select 1 from "better_supabase"."risks" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'case' then return coalesce(exists (select 1 from "better_supabase"."cases" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'form' then return coalesce(exists (select 1 from "better_supabase"."forms" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'tax_code' then return coalesce(exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'incident' then return coalesce(exists (select 1 from "better_supabase"."incidents" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'content_entry' then return coalesce(exists (select 1 from "better_supabase"."content_entries" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'document' then return coalesce(exists (select 1 from "better_supabase"."documents" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'customer' then return coalesce(exists (select 1 from "public"."customers" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."organization_id" = consents_subject_readable.tenant) and (consents_subject_readable.tenant in (select better_supabase.tenant_ids_with('customers.read')) or "better_supabase"."is_subject_member"('customer', consents_subject_readable.subject_id)), false);
    when 'drive_node' then return coalesce(exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant and ((consents_subject_readable.tenant in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', consents_subject_readable.subject_id))), false);
    when 'organization' then return coalesce(exists (select 1 from "public"."organizations" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."id" = consents_subject_readable.tenant), false);
    when 'application' then return coalesce(exists (select 1 from "better_supabase"."applications" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."tenant_id" = consents_subject_readable.tenant), false);
    when 'change_request' then return coalesce(exists (select 1 from "public"."change_requests" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."organization_id" = consents_subject_readable.tenant), false);
    when 'project' then return coalesce(exists (select 1 from "public"."projects" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."organization_id" = consents_subject_readable.tenant), false);
    when 'task' then return coalesce(exists (select 1 from "public"."tasks" s where s."id" = (consents_subject_readable.subject_id)::uuid and s."organization_id" = consents_subject_readable.tenant), false);
    else return coalesce(coalesce("better_supabase"."can_subject"(consents_subject_readable.subject_type, consents_subject_readable.subject_id, 'read'), false), false);
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.field_history_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case field_history_subject_readable.subject_type
    when 'message' then return coalesce(exists (select 1 from "better_supabase"."messages" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'conversation' then return coalesce(exists (select 1 from "better_supabase"."conversations" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'channel' then return coalesce(exists (select 1 from "better_supabase"."channels" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'company' then return coalesce(exists (select 1 from "better_supabase"."companies" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'person' then return coalesce(exists (select 1 from "better_supabase"."people" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'deal' then return coalesce(exists (select 1 from "better_supabase"."deals" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'course' then return coalesce(exists (select 1 from "better_supabase"."courses" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'activity' then return coalesce(exists (select 1 from "better_supabase"."activities" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'quote' then return coalesce(exists (select 1 from "better_supabase"."quotes" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'work_item' then return coalesce(exists (select 1 from "better_supabase"."work_items" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'employee' then return coalesce(exists (select 1 from "better_supabase"."employees" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'ledger_account' then return coalesce(exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'invoice' then return coalesce(exists (select 1 from "better_supabase"."invoices" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'product' then return coalesce(exists (select 1 from "better_supabase"."products" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'product_variant' then return coalesce(exists (select 1 from "better_supabase"."product_variants" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'order' then return coalesce(exists (select 1 from "better_supabase"."orders" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'calendar_event' then return coalesce(exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'booking' then return coalesce(exists (select 1 from "better_supabase"."bookings" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'asset' then return coalesce(exists (select 1 from "better_supabase"."assets" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'asset_location' then return coalesce(exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'lease' then return coalesce(exists (select 1 from "better_supabase"."leases" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'expense_report' then return coalesce(exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'expense_line' then return coalesce(exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'donation_fund' then return coalesce(exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'work_order' then return coalesce(exists (select 1 from "better_supabase"."work_orders" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'shipment' then return coalesce(exists (select 1 from "better_supabase"."shipments" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'contract' then return coalesce(exists (select 1 from "better_supabase"."contracts" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'control' then return coalesce(exists (select 1 from "better_supabase"."controls" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'compliance_policy' then return coalesce(exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'case' then return coalesce(exists (select 1 from "better_supabase"."cases" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'form' then return coalesce(exists (select 1 from "better_supabase"."forms" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'incident' then return coalesce(exists (select 1 from "better_supabase"."incidents" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'document' then return coalesce(exists (select 1 from "better_supabase"."documents" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'customer' then return coalesce(exists (select 1 from "public"."customers" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."organization_id" = field_history_subject_readable.tenant) and (field_history_subject_readable.tenant in (select better_supabase.tenant_ids_with('customers.read')) or "better_supabase"."is_subject_member"('customer', field_history_subject_readable.subject_id)), false);
    when 'drive_node' then return coalesce(exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant and ((field_history_subject_readable.tenant in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', field_history_subject_readable.subject_id))), false);
    when 'organization' then return coalesce(exists (select 1 from "public"."organizations" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."id" = field_history_subject_readable.tenant), false);
    when 'application' then return coalesce(exists (select 1 from "better_supabase"."applications" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."tenant_id" = field_history_subject_readable.tenant), false);
    when 'change_request' then return coalesce(exists (select 1 from "public"."change_requests" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."organization_id" = field_history_subject_readable.tenant), false);
    when 'project' then return coalesce(exists (select 1 from "public"."projects" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."organization_id" = field_history_subject_readable.tenant), false);
    when 'task' then return coalesce(exists (select 1 from "public"."tasks" s where s."id" = (field_history_subject_readable.subject_id)::uuid and s."organization_id" = field_history_subject_readable.tenant), false);
    else return coalesce(coalesce("better_supabase"."can_subject"(field_history_subject_readable.subject_type, field_history_subject_readable.subject_id, 'read'), false), false);
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.funding_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case funding_subject_readable.subject_type
    when 'message' then return coalesce(exists (select 1 from "better_supabase"."messages" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'conversation' then return coalesce(exists (select 1 from "better_supabase"."conversations" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'channel' then return coalesce(exists (select 1 from "better_supabase"."channels" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'company' then return coalesce(exists (select 1 from "better_supabase"."companies" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'person' then return coalesce(exists (select 1 from "better_supabase"."people" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'deal' then return coalesce(exists (select 1 from "better_supabase"."deals" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'course' then return coalesce(exists (select 1 from "better_supabase"."courses" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'post' then return coalesce(exists (select 1 from "better_supabase"."posts" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'activity' then return coalesce(exists (select 1 from "better_supabase"."activities" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'quote' then return coalesce(exists (select 1 from "better_supabase"."quotes" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'work_item' then return coalesce(exists (select 1 from "better_supabase"."work_items" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'employee' then return coalesce(exists (select 1 from "better_supabase"."employees" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'ledger_account' then return coalesce(exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'invoice' then return coalesce(exists (select 1 from "better_supabase"."invoices" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'product' then return coalesce(exists (select 1 from "better_supabase"."products" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'product_variant' then return coalesce(exists (select 1 from "better_supabase"."product_variants" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'order' then return coalesce(exists (select 1 from "better_supabase"."orders" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'calendar_event' then return coalesce(exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'booking' then return coalesce(exists (select 1 from "better_supabase"."bookings" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'asset' then return coalesce(exists (select 1 from "better_supabase"."assets" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'asset_location' then return coalesce(exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'lease' then return coalesce(exists (select 1 from "better_supabase"."leases" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'expense_report' then return coalesce(exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'expense_line' then return coalesce(exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'donation_fund' then return coalesce(exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'work_order' then return coalesce(exists (select 1 from "better_supabase"."work_orders" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'shipment' then return coalesce(exists (select 1 from "better_supabase"."shipments" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'contract' then return coalesce(exists (select 1 from "better_supabase"."contracts" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'control' then return coalesce(exists (select 1 from "better_supabase"."controls" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'compliance_policy' then return coalesce(exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'qualification_type' then return coalesce(exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'risk' then return coalesce(exists (select 1 from "better_supabase"."risks" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'case' then return coalesce(exists (select 1 from "better_supabase"."cases" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'inspection' then return coalesce(exists (select 1 from "better_supabase"."inspections" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'inspection_program' then return coalesce(exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'inspection_finding' then return coalesce(exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'form' then return coalesce(exists (select 1 from "better_supabase"."forms" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'meeting' then return coalesce(exists (select 1 from "better_supabase"."meetings" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'meeting_decision' then return coalesce(exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'tax_code' then return coalesce(exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'production_order' then return coalesce(exists (select 1 from "better_supabase"."production_orders" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'work_center' then return coalesce(exists (select 1 from "better_supabase"."work_centers" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'bank_account' then return coalesce(exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'care_plan' then return coalesce(exists (select 1 from "better_supabase"."care_plans" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'incident' then return coalesce(exists (select 1 from "better_supabase"."incidents" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'content_entry' then return coalesce(exists (select 1 from "better_supabase"."content_entries" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'document' then return coalesce(exists (select 1 from "better_supabase"."documents" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'customer' then return coalesce(exists (select 1 from "public"."customers" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."organization_id" = funding_subject_readable.tenant) and (funding_subject_readable.tenant in (select better_supabase.tenant_ids_with('customers.read')) or "better_supabase"."is_subject_member"('customer', funding_subject_readable.subject_id)), false);
    when 'drive_node' then return coalesce(exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant and ((funding_subject_readable.tenant in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', funding_subject_readable.subject_id))), false);
    when 'organization' then return coalesce(exists (select 1 from "public"."organizations" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."id" = funding_subject_readable.tenant), false);
    when 'application' then return coalesce(exists (select 1 from "better_supabase"."applications" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."tenant_id" = funding_subject_readable.tenant), false);
    when 'change_request' then return coalesce(exists (select 1 from "public"."change_requests" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."organization_id" = funding_subject_readable.tenant), false);
    when 'project' then return coalesce(exists (select 1 from "public"."projects" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."organization_id" = funding_subject_readable.tenant), false);
    when 'task' then return coalesce(exists (select 1 from "public"."tasks" s where s."id" = (funding_subject_readable.subject_id)::uuid and s."organization_id" = funding_subject_readable.tenant), false);
    else return coalesce(coalesce("better_supabase"."can_subject"(funding_subject_readable.subject_type, funding_subject_readable.subject_id, 'read'), false), false);
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.medications_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case medications_subject_readable.subject_type
    when 'message' then return coalesce(exists (select 1 from "better_supabase"."messages" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'conversation' then return coalesce(exists (select 1 from "better_supabase"."conversations" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'channel' then return coalesce(exists (select 1 from "better_supabase"."channels" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'company' then return coalesce(exists (select 1 from "better_supabase"."companies" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'person' then return coalesce(exists (select 1 from "better_supabase"."people" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'deal' then return coalesce(exists (select 1 from "better_supabase"."deals" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'course' then return coalesce(exists (select 1 from "better_supabase"."courses" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'post' then return coalesce(exists (select 1 from "better_supabase"."posts" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'activity' then return coalesce(exists (select 1 from "better_supabase"."activities" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'quote' then return coalesce(exists (select 1 from "better_supabase"."quotes" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'work_item' then return coalesce(exists (select 1 from "better_supabase"."work_items" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'employee' then return coalesce(exists (select 1 from "better_supabase"."employees" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'ledger_account' then return coalesce(exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'invoice' then return coalesce(exists (select 1 from "better_supabase"."invoices" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'product' then return coalesce(exists (select 1 from "better_supabase"."products" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'product_variant' then return coalesce(exists (select 1 from "better_supabase"."product_variants" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'order' then return coalesce(exists (select 1 from "better_supabase"."orders" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'calendar_event' then return coalesce(exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'booking' then return coalesce(exists (select 1 from "better_supabase"."bookings" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'asset' then return coalesce(exists (select 1 from "better_supabase"."assets" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'asset_location' then return coalesce(exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'lease' then return coalesce(exists (select 1 from "better_supabase"."leases" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'expense_report' then return coalesce(exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'expense_line' then return coalesce(exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'donation_fund' then return coalesce(exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'work_order' then return coalesce(exists (select 1 from "better_supabase"."work_orders" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'shipment' then return coalesce(exists (select 1 from "better_supabase"."shipments" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'contract' then return coalesce(exists (select 1 from "better_supabase"."contracts" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'control' then return coalesce(exists (select 1 from "better_supabase"."controls" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'compliance_policy' then return coalesce(exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'qualification_type' then return coalesce(exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'risk' then return coalesce(exists (select 1 from "better_supabase"."risks" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'case' then return coalesce(exists (select 1 from "better_supabase"."cases" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'form' then return coalesce(exists (select 1 from "better_supabase"."forms" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'tax_code' then return coalesce(exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'incident' then return coalesce(exists (select 1 from "better_supabase"."incidents" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'content_entry' then return coalesce(exists (select 1 from "better_supabase"."content_entries" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'document' then return coalesce(exists (select 1 from "better_supabase"."documents" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'customer' then return coalesce(exists (select 1 from "public"."customers" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."organization_id" = medications_subject_readable.tenant) and (medications_subject_readable.tenant in (select better_supabase.tenant_ids_with('customers.read')) or "better_supabase"."is_subject_member"('customer', medications_subject_readable.subject_id)), false);
    when 'drive_node' then return coalesce(exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant and ((medications_subject_readable.tenant in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', medications_subject_readable.subject_id))), false);
    when 'organization' then return coalesce(exists (select 1 from "public"."organizations" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."id" = medications_subject_readable.tenant), false);
    when 'application' then return coalesce(exists (select 1 from "better_supabase"."applications" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."tenant_id" = medications_subject_readable.tenant), false);
    when 'change_request' then return coalesce(exists (select 1 from "public"."change_requests" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."organization_id" = medications_subject_readable.tenant), false);
    when 'project' then return coalesce(exists (select 1 from "public"."projects" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."organization_id" = medications_subject_readable.tenant), false);
    when 'task' then return coalesce(exists (select 1 from "public"."tasks" s where s."id" = (medications_subject_readable.subject_id)::uuid and s."organization_id" = medications_subject_readable.tenant), false);
    else return coalesce(coalesce("better_supabase"."can_subject"(medications_subject_readable.subject_type, medications_subject_readable.subject_id, 'read'), false), false);
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.observations_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case observations_subject_readable.subject_type
    when 'message' then return coalesce(exists (select 1 from "better_supabase"."messages" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'conversation' then return coalesce(exists (select 1 from "better_supabase"."conversations" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'channel' then return coalesce(exists (select 1 from "better_supabase"."channels" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'company' then return coalesce(exists (select 1 from "better_supabase"."companies" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'person' then return coalesce(exists (select 1 from "better_supabase"."people" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'deal' then return coalesce(exists (select 1 from "better_supabase"."deals" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'course' then return coalesce(exists (select 1 from "better_supabase"."courses" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'post' then return coalesce(exists (select 1 from "better_supabase"."posts" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'activity' then return coalesce(exists (select 1 from "better_supabase"."activities" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'quote' then return coalesce(exists (select 1 from "better_supabase"."quotes" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'work_item' then return coalesce(exists (select 1 from "better_supabase"."work_items" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'employee' then return coalesce(exists (select 1 from "better_supabase"."employees" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'ledger_account' then return coalesce(exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'invoice' then return coalesce(exists (select 1 from "better_supabase"."invoices" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'product' then return coalesce(exists (select 1 from "better_supabase"."products" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'product_variant' then return coalesce(exists (select 1 from "better_supabase"."product_variants" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'order' then return coalesce(exists (select 1 from "better_supabase"."orders" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'calendar_event' then return coalesce(exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'booking' then return coalesce(exists (select 1 from "better_supabase"."bookings" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'asset' then return coalesce(exists (select 1 from "better_supabase"."assets" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'asset_location' then return coalesce(exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'lease' then return coalesce(exists (select 1 from "better_supabase"."leases" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'expense_report' then return coalesce(exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'expense_line' then return coalesce(exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'donation_fund' then return coalesce(exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'work_order' then return coalesce(exists (select 1 from "better_supabase"."work_orders" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'shipment' then return coalesce(exists (select 1 from "better_supabase"."shipments" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'contract' then return coalesce(exists (select 1 from "better_supabase"."contracts" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'control' then return coalesce(exists (select 1 from "better_supabase"."controls" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'compliance_policy' then return coalesce(exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'qualification_type' then return coalesce(exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'risk' then return coalesce(exists (select 1 from "better_supabase"."risks" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'case' then return coalesce(exists (select 1 from "better_supabase"."cases" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'form' then return coalesce(exists (select 1 from "better_supabase"."forms" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'tax_code' then return coalesce(exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'incident' then return coalesce(exists (select 1 from "better_supabase"."incidents" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'content_entry' then return coalesce(exists (select 1 from "better_supabase"."content_entries" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'document' then return coalesce(exists (select 1 from "better_supabase"."documents" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'customer' then return coalesce(exists (select 1 from "public"."customers" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."organization_id" = observations_subject_readable.tenant) and (observations_subject_readable.tenant in (select better_supabase.tenant_ids_with('customers.read')) or "better_supabase"."is_subject_member"('customer', observations_subject_readable.subject_id)), false);
    when 'drive_node' then return coalesce(exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant and ((observations_subject_readable.tenant in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', observations_subject_readable.subject_id))), false);
    when 'organization' then return coalesce(exists (select 1 from "public"."organizations" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."id" = observations_subject_readable.tenant), false);
    when 'application' then return coalesce(exists (select 1 from "better_supabase"."applications" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."tenant_id" = observations_subject_readable.tenant), false);
    when 'change_request' then return coalesce(exists (select 1 from "public"."change_requests" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."organization_id" = observations_subject_readable.tenant), false);
    when 'project' then return coalesce(exists (select 1 from "public"."projects" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."organization_id" = observations_subject_readable.tenant), false);
    when 'task' then return coalesce(exists (select 1 from "public"."tasks" s where s."id" = (observations_subject_readable.subject_id)::uuid and s."organization_id" = observations_subject_readable.tenant), false);
    else return coalesce(coalesce("better_supabase"."can_subject"(observations_subject_readable.subject_type, observations_subject_readable.subject_id, 'read'), false), false);
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pipeline_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case pipeline_subject_readable.subject_type
    when 'deal' then return coalesce(exists (select 1 from "better_supabase"."deals" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'work_item' then return coalesce(exists (select 1 from "better_supabase"."work_items" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'ledger_account' then return coalesce(exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'product' then return coalesce(exists (select 1 from "better_supabase"."products" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'product_variant' then return coalesce(exists (select 1 from "better_supabase"."product_variants" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'order' then return coalesce(exists (select 1 from "better_supabase"."orders" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'calendar_event' then return coalesce(exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'booking' then return coalesce(exists (select 1 from "better_supabase"."bookings" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'case' then return coalesce(exists (select 1 from "better_supabase"."cases" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'form' then return coalesce(exists (select 1 from "better_supabase"."forms" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'document' then return coalesce(exists (select 1 from "better_supabase"."documents" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'customer' then return coalesce(exists (select 1 from "public"."customers" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."organization_id" = pipeline_subject_readable.tenant) and (pipeline_subject_readable.tenant in (select better_supabase.tenant_ids_with('customers.read')) or "better_supabase"."is_subject_member"('customer', pipeline_subject_readable.subject_id)), false);
    when 'drive_node' then return coalesce(exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant and ((pipeline_subject_readable.tenant in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', pipeline_subject_readable.subject_id))), false);
    when 'organization' then return coalesce(exists (select 1 from "public"."organizations" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."id" = pipeline_subject_readable.tenant), false);
    when 'application' then return coalesce(exists (select 1 from "better_supabase"."applications" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."tenant_id" = pipeline_subject_readable.tenant), false);
    when 'change_request' then return coalesce(exists (select 1 from "public"."change_requests" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."organization_id" = pipeline_subject_readable.tenant), false);
    when 'project' then return coalesce(exists (select 1 from "public"."projects" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."organization_id" = pipeline_subject_readable.tenant), false);
    when 'task' then return coalesce(exists (select 1 from "public"."tasks" s where s."id" = (pipeline_subject_readable.subject_id)::uuid and s."organization_id" = pipeline_subject_readable.tenant), false);
    else return coalesce(coalesce("better_supabase"."can_subject"(pipeline_subject_readable.subject_type, pipeline_subject_readable.subject_id, 'read'), false), false);
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.sla_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case sla_subject_readable.subject_type
    when 'company' then return coalesce(exists (select 1 from "better_supabase"."companies" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'person' then return coalesce(exists (select 1 from "better_supabase"."people" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'deal' then return coalesce(exists (select 1 from "better_supabase"."deals" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'activity' then return coalesce(exists (select 1 from "better_supabase"."activities" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'quote' then return coalesce(exists (select 1 from "better_supabase"."quotes" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'work_item' then return coalesce(exists (select 1 from "better_supabase"."work_items" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'ledger_account' then return coalesce(exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'invoice' then return coalesce(exists (select 1 from "better_supabase"."invoices" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'product' then return coalesce(exists (select 1 from "better_supabase"."products" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'product_variant' then return coalesce(exists (select 1 from "better_supabase"."product_variants" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'order' then return coalesce(exists (select 1 from "better_supabase"."orders" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'calendar_event' then return coalesce(exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'booking' then return coalesce(exists (select 1 from "better_supabase"."bookings" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'case' then return coalesce(exists (select 1 from "better_supabase"."cases" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'form' then return coalesce(exists (select 1 from "better_supabase"."forms" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'document' then return coalesce(exists (select 1 from "better_supabase"."documents" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'customer' then return coalesce(exists (select 1 from "public"."customers" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."organization_id" = sla_subject_readable.tenant) and (sla_subject_readable.tenant in (select better_supabase.tenant_ids_with('customers.read')) or "better_supabase"."is_subject_member"('customer', sla_subject_readable.subject_id)), false);
    when 'drive_node' then return coalesce(exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant and ((sla_subject_readable.tenant in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', sla_subject_readable.subject_id))), false);
    when 'organization' then return coalesce(exists (select 1 from "public"."organizations" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."id" = sla_subject_readable.tenant), false);
    when 'application' then return coalesce(exists (select 1 from "better_supabase"."applications" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."tenant_id" = sla_subject_readable.tenant), false);
    when 'change_request' then return coalesce(exists (select 1 from "public"."change_requests" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."organization_id" = sla_subject_readable.tenant), false);
    when 'project' then return coalesce(exists (select 1 from "public"."projects" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."organization_id" = sla_subject_readable.tenant), false);
    when 'task' then return coalesce(exists (select 1 from "public"."tasks" s where s."id" = (sla_subject_readable.subject_id)::uuid and s."organization_id" = sla_subject_readable.tenant), false);
    else return coalesce(coalesce("better_supabase"."can_subject"(sla_subject_readable.subject_type, sla_subject_readable.subject_id, 'read'), false), false);
  end case;
end;
$function$;

CREATE POLICY "bsb_consents_read" ON "better_supabase"."consents"
  FOR SELECT
  TO "authenticated"
  USING ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('consents.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id) AND (((consents.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR better_supabase.is_subject_member('drive_node'::text, consents.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.id = consents.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text, 'post'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'qualification_type'::text,
      'risk'::text,
      'case'::text,
      'form'::text,
      'tax_code'::text, 'incident'::text, 'content_entry'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('posts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['post'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('qualifications.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['qualification_type'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('risks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['risk'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tax.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['tax_code'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('content.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['content_entry'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.consents_subject_readable(subject_type, subject_id, tenant_id))
END) OR (grantor_id = ( SELECT auth.uid() AS uid))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."consents"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('consents.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (consents.subject_id)::uuid) AND (s.tenant_id = consents.tenant_id) AND (((consents.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS
        tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR better_supabase.is_subject_member('drive_node'::text, consents.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.id = consents.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (consents.subject_id)::uuid) AND (s.organization_id = consents.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text, 'post'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'qualification_type'::text,
      'risk'::text,
      'case'::text,
      'form'::text,
      'tax_code'::text, 'incident'::text, 'content_entry'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('posts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['post'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('qualifications.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['qualification_type'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('risks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['risk'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tax.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['tax_code'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('content.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['content_entry'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.consents_subject_readable(subject_type, subject_id, tenant_id))
END) OR (grantor_id = ( SELECT auth.uid() AS uid)))));

CREATE POLICY "bsb_field_changes_read" ON "better_supabase"."field_changes"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('field_history.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id) AND (((field_changes.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, field_changes.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.id = field_changes.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'case'::text, 'form'::text, 'incident'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.field_history_subject_readable(subject_type, subject_id, tenant_id))
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."field_changes"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('field_history.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (field_changes.subject_id)::uuid) AND (s.tenant_id = field_changes.tenant_id) AND (((field_changes.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, field_changes.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.id = field_changes.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (field_changes.subject_id)::uuid) AND (s.organization_id = field_changes.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'case'::text, 'form'::text, 'incident'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.field_history_subject_readable(subject_type, subject_id, tenant_id))
END)));

CREATE POLICY "bsb_funding_awards_read" ON "better_supabase"."funding_awards"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id) AND (((funding_awards.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, funding_awards.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.id = funding_awards.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text, 'post'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'qualification_type'::text,
      'risk'::text,
      'case'::text,
      'inspection'::text,
      'inspection_program'::text,
      'inspection_finding'::text,
      'form'::text,
      'meeting'::text,
      'meeting_decision'::text,
      'tax_code'::text,
      'production_order'::text,
      'work_center'::text,
      'bank_account'::text,
      'care_plan'::text, 'incident'::text, 'content_entry'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('posts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['post'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('qualifications.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['qualification_type'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('risks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['risk'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('inspections.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['inspection'::text, 'inspection_program'::text, 'inspection_finding'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('meetings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['meeting'::text, 'meeting_decision'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tax.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['tax_code'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('manufacturing.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['production_order'::text, 'work_center'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('banking.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['bank_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('care_plans.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['care_plan'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('content.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['content_entry'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.funding_subject_readable(subject_type, subject_id, tenant_id))
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_awards"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text)
    AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id) AND (((funding_awards.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, funding_awards.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.id = funding_awards.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text, 'post'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'qualification_type'::text,
      'risk'::text,
      'case'::text,
      'inspection'::text,
      'inspection_program'::text,
      'inspection_finding'::text,
      'form'::text,
      'meeting'::text,
      'meeting_decision'::text,
      'tax_code'::text,
      'production_order'::text,
      'work_center'::text,
      'bank_account'::text,
      'care_plan'::text, 'incident'::text, 'content_entry'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('posts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['post'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('qualifications.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['qualification_type'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('risks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['risk'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('inspections.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['inspection'::text, 'inspection_program'::text, 'inspection_finding'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('meetings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['meeting'::text, 'meeting_decision'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tax.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['tax_code'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('manufacturing.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['production_order'::text, 'work_center'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('banking.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['bank_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('care_plans.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['care_plan'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('content.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['content_entry'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.funding_subject_readable(subject_type, subject_id, tenant_id))
END)));

CREATE POLICY "bsb_funding_deliveries_read" ON "better_supabase"."funding_deliveries"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text) AS tenant_ids_with)) AND (EXISTS ( SELECT 1
   FROM better_supabase.funding_awards x
  WHERE
    ((x.tenant_id = funding_deliveries.tenant_id) AND (x.id = funding_deliveries.award_id) AND COALESCE(better_supabase.can_subject(x.subject_type, x.subject_id, 'read'::text),
    false))))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."funding_deliveries"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text)
    AS tenant_ids_with)) AND (EXISTS ( SELECT 1
   FROM better_supabase.funding_awards x
  WHERE
    ((x.tenant_id = funding_deliveries.tenant_id) AND (x.id = funding_deliveries.award_id) AND COALESCE(better_supabase.can_subject(x.subject_type, x.subject_id, 'read'::text),
    false)))))));

CREATE POLICY "bsb_medication_orders_read" ON "better_supabase"."medication_orders"
  FOR SELECT
  TO "authenticated"
  USING ((((tenant_id IN ( SELECT better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id) AND (((medication_orders.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, medication_orders.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.id = medication_orders.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text, 'post'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'qualification_type'::text,
      'risk'::text,
      'case'::text,
      'form'::text,
      'tax_code'::text, 'incident'::text, 'content_entry'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('posts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['post'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('qualifications.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['qualification_type'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('risks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['risk'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tax.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['tax_code'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('content.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['content_entry'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.medications_subject_readable(subject_type, subject_id, tenant_id))
END) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id)))));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."medication_orders"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR (((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('medications.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (medication_orders.subject_id)::uuid) AND (s.tenant_id = medication_orders.tenant_id) AND (((medication_orders.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, medication_orders.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.id = medication_orders.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (medication_orders.subject_id)::uuid) AND (s.organization_id = medication_orders.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text, 'post'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'qualification_type'::text,
      'risk'::text,
      'case'::text,
      'form'::text,
      'tax_code'::text, 'incident'::text, 'content_entry'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('posts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['post'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('qualifications.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['qualification_type'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('risks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['risk'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tax.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['tax_code'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('content.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['content_entry'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.medications_subject_readable(subject_type, subject_id, tenant_id))
END) OR (((tenant_id)::text, subject_type, subject_id) IN ( SELECT g.tenant,
    g.subject_type,
    g.subject_id
   FROM better_supabase.portal_subjects('read'::text) g(tenant, subject_type, subject_id))))));

CREATE POLICY "bsb_observations_read" ON "better_supabase"."observations"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('observations.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id) AND (((observations.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, observations.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.id = observations.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text, 'post'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'qualification_type'::text,
      'risk'::text,
      'case'::text,
      'form'::text,
      'tax_code'::text, 'incident'::text, 'content_entry'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('posts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['post'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('qualifications.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['qualification_type'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('risks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['risk'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tax.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['tax_code'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('content.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['content_entry'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.observations_subject_readable(subject_type, subject_id, tenant_id))
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."observations"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('observations.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (observations.subject_id)::uuid) AND (s.tenant_id = observations.tenant_id) AND (((observations.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, observations.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.id = observations.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (observations.subject_id)::uuid) AND (s.organization_id = observations.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['message'::text, 'conversation'::text, 'channel'::text, 'company'::text, 'person'::text, 'deal'::text, 'course'::text, 'post'::text,
      'activity'::text,
      'quote'::text,
      'work_item'::text,
      'employee'::text,
      'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text,
      'asset'::text,
      'asset_location'::text,
      'lease'::text,
      'expense_report'::text,
      'expense_line'::text,
      'donation_fund'::text,
      'work_order'::text,
      'shipment'::text,
      'contract'::text,
      'control'::text,
      'compliance_policy'::text,
      'qualification_type'::text,
      'risk'::text,
      'case'::text,
      'form'::text,
      'tax_code'::text, 'incident'::text, 'content_entry'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('messages.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['message'::text, 'conversation'::text, 'channel'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('courses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['course'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('posts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['post'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('employees.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['employee'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('assets.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['asset'::text, 'asset_location'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('leases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['lease'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('expenses.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['expense_report'::text, 'expense_line'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('donations.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['donation_fund'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('dispatch.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('shipments.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['shipment'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contracts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['contract'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('compliance.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['control'::text, 'compliance_policy'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('qualifications.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['qualification_type'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('risks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['risk'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tax.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['tax_code'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('incidents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['incident'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('content.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['content_entry'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.observations_subject_readable(subject_type, subject_id, tenant_id))
END)));

CREATE POLICY "bsb_pipeline_stage_history_read" ON "better_supabase"."pipeline_stage_history"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('pipelines.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id) AND (((pipeline_stage_history.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, pipeline_stage_history.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.id = pipeline_stage_history.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['deal'::text, 'work_item'::text, 'ledger_account'::text, 'product'::text, 'product_variant'::text, 'order'::text,
      'calendar_event'::text,
      'booking'::text, 'case'::text, 'form'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.pipeline_subject_readable(subject_type, subject_id, tenant_id))
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."pipeline_stage_history"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('pipelines.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.tenant_id = pipeline_stage_history.tenant_id) AND (((pipeline_stage_history.tenant_id IN ( SELECT
        better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR
        better_supabase.is_subject_member('drive_node'::text, pipeline_stage_history.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.id = pipeline_stage_history.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (pipeline_stage_history.subject_id)::uuid) AND (s.organization_id = pipeline_stage_history.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['deal'::text, 'work_item'::text, 'ledger_account'::text, 'product'::text, 'product_variant'::text, 'order'::text,
      'calendar_event'::text,
      'booking'::text, 'case'::text, 'form'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.pipeline_subject_readable(subject_type, subject_id, tenant_id))
END)));

CREATE POLICY "bsb_sla_clocks_read" ON "better_supabase"."sla_clocks"
  FOR SELECT
  TO "authenticated"
  USING (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('sla.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id) AND (((sla_clocks.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text)
        AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR better_supabase.is_subject_member('drive_node'::text, sla_clocks.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.id = sla_clocks.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['company'::text, 'person'::text, 'deal'::text, 'activity'::text, 'quote'::text, 'work_item'::text, 'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text, 'case'::text, 'form'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.sla_subject_readable(subject_type, subject_id, tenant_id))
END));

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."sla_clocks"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('sla.read'::text) AS
    tenant_ids_with)) AND
CASE subject_type
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM public.customers s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id)))) AND
        ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE
        ((s.id = (sla_clocks.subject_id)::uuid) AND (s.tenant_id = sla_clocks.tenant_id) AND (((sla_clocks.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text)
        AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR better_supabase.is_subject_member('drive_node'::text, sla_clocks.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM public.organizations s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.id = sla_clocks.tenant_id))))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM public.change_requests s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM public.projects s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM public.tasks s
      WHERE ((s.id = (sla_clocks.subject_id)::uuid) AND (s.organization_id = sla_clocks.tenant_id))))
    ELSE
      (((COALESCE((subject_type = ANY (ARRAY['company'::text, 'person'::text, 'deal'::text, 'activity'::text, 'quote'::text, 'work_item'::text, 'ledger_account'::text,
      'invoice'::text,
      'product'::text,
      'product_variant'::text,
      'order'::text,
      'calendar_event'::text,
      'booking'::text, 'case'::text, 'form'::text, 'document'::text, 'application'::text])), false) = false) OR ((tenant_id, subject_type) IN ( SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('contacts.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['company'::text, 'person'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('deals.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['deal'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('activities.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['activity'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('quotes.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['quote'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('tasks.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['work_item'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('ledger.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['ledger_account'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('invoices.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['invoice'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('catalog.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['product'::text, 'product_variant'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('orders.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['order'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('calendar.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['calendar_event'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('bookings.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['booking'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('cases.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['case'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('forms.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['form'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('documents.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['document'::text]) g(TYPE))
    UNION ALL
     SELECT t.tenant,
        g.type
       FROM (better_supabase.tenant_ids_with('hiring.read'::text) t(tenant)
         CROSS JOIN unnest(ARRAY['application'::text]) g(TYPE))))) AND better_supabase.sla_subject_readable(subject_type, subject_id, tenant_id))
END)));

REVOKE ALL ON FUNCTION "better_supabase"."consents_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."consents_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."field_history_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."field_history_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."funding_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."funding_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."medications_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."medications_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."observations_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."observations_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."pipeline_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."pipeline_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."sla_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."sla_subject_readable"(text, text, uuid) TO "authenticated", "service_role";

