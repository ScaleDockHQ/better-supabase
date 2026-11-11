SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.get_approvals (
  request_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."get_approvals"($1) $function$;

CREATE OR REPLACE FUNCTION api.purchase_invoice_approval_statuses (
  invoice_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select "better_supabase"."purchase_invoice_approval_statuses"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.get_approvals (
  request_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', r."id", 'organizationId', r."tenant_id", 'subjectType', r."subject_type", 'subjectId', r."subject_id", 'action', r."action", 'status', r."status", 'step', r."step", 'steps', r."policy" -> 'steps', 'requestedBy', r."requested_by", 'reason', r."reason", 'payload', r."payload", 'expiresAt', r."expires_at", 'decidedAt', r."decided_at", 'mode', coalesce(r."policy" ->> 'mode', 'authorize'), 'fingerprint', r."fingerprint", 'consumedAt', r."consumed_at", 'createdAt', r."created_at") || jsonb_build_object(
      'canDecide', "better_supabase"."approval_eligible"(r."id"),
      'decisions', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'step', x."step", 'approver', x."approver", 'decision', x."decision", 'delegateTo', x."delegate_to", 'comment', x."comment", 'createdAt', x."created_at") order by x."created_at", x."id")
        from "better_supabase"."approval_decisions" x where x."request_id" = r."id"
      ), '[]'::jsonb),
      'items', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'key', x."key", 'label', x."label", 'payload', x."payload", 'permission', x."permission", 'dependsOn', to_jsonb(x."depends_on"), 'status', x."status", 'createdType', x."created_type", 'createdId', x."created_id", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'createdAt', x."created_at") order by x."created_at", x."key")
      from "better_supabase"."approval_items" x where x."request_id" = r."id"
    ), '[]'::jsonb)
    ) order by array_position(get_approvals.request_ids, r."id")), '[]'::jsonb)
    from "better_supabase"."approval_requests" r
    where r."id" = any (get_approvals.request_ids)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(r."requested_by" = auth.uid(), false) or "better_supabase"."approval_eligible"(r."id")
        or (coalesce(better_supabase.can('tenant', r."tenant_id", 'approvals.read'), false) and (not r."subject_type" in ('ai_tool_approval') and (r."subject_type" in ('access_request', 'purchase_requisition', 'timesheet', 'expense_report', 'content_entry', 'care_plan_action', 'case', 'appraisal') or (case when r."subject_type" = 'drive_node' then coalesce(case when r."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((r."subject_id")::uuid, 'viewer') end, false) else case r."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (r."subject_id")::uuid and s."organization_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id" and (coalesce(better_supabase.can('tenant', r."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = (r."subject_id")::uuid and s."id" = r."tenant_id")
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (r."subject_id")::uuid and s."tenant_id" = r."tenant_id") and coalesce(better_supabase.can('tenant', r."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (r."subject_id")::uuid and s."organization_id" = r."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (r."subject_id")::uuid and s."organization_id" = r."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (r."subject_id")::uuid and s."organization_id" = r."tenant_id")
    else false
  end end)))))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.purchase_invoice_approval_statuses (
  invoice_ids uuid[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  return (
    select coalesce(jsonb_object_agg(x."id", "better_supabase"."invoice_approval_state"(x."id")), '{}'::jsonb)
    from "better_supabase"."invoices" x
    where x."id" = any (purchase_invoice_approval_statuses.invoice_ids) and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false))
  );
end;
$function$;

REVOKE ALL ON FUNCTION "api"."get_approvals"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."get_approvals"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."purchase_invoice_approval_statuses"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."purchase_invoice_approval_statuses"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."get_approvals"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."get_approvals"(uuid[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."purchase_invoice_approval_statuses"(uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."purchase_invoice_approval_statuses"(uuid[]) TO "authenticated", "service_role";
