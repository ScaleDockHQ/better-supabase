SET local check_function_bodies = off;

DROP POLICY "bsb_tenant_scope_select" ON "better_supabase"."deadlines";

DROP POLICY "deadlines_read" ON "better_supabase"."deadlines";

CREATE OR REPLACE FUNCTION better_supabase.compute_deadlines (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  jurisdiction text,
  kind         text,
  facts        jsonb DEFAULT '{}'::jsonb,
  as_of        date  DEFAULT CURRENT_DATE,
  group_key    text  DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_version jsonb;
  v_results jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (compute_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', compute_deadlines.tenant, 'deadlines.write'), false))) then
    raise exception 'not allowed to compute deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if compute_deadlines.subject_type is null or compute_deadlines.subject_type !~ '^[a-z][a-z0-9_]{0,62}$'
    or compute_deadlines.subject_id is null or length(compute_deadlines.subject_id) not between 1 and 200
    or compute_deadlines.facts is null or jsonb_typeof(compute_deadlines.facts) <> 'object'
    or compute_deadlines.as_of is null then
    raise exception 'a deadline needs a subject type, a subject id, facts as an object and a date' using errcode = '22023', hint = 'DEADLINE_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."deadline_subject_readable"(compute_deadlines.subject_type, compute_deadlines.subject_id, compute_deadlines.tenant)) then
    raise exception 'not allowed to compute deadlines for this subject' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  v_version := "better_supabase"."rule_version_at"(compute_deadlines.jurisdiction, compute_deadlines.kind, compute_deadlines.as_of);
  if v_version is null then
    raise exception 'no approved rule set version applies' using errcode = 'P0002', hint = 'DEADLINE_RULES_NOT_FOUND';
  end if;
  if compute_deadlines.group_key is not null and not exists (
    select 1 from jsonb_array_elements(v_version -> 'groups') g(value) where g.value ->> 'key' = compute_deadlines.group_key
  ) then
    raise exception 'the rule set has no group with this key' using errcode = 'P0002', hint = 'DEADLINE_RULE_NOT_FOUND';
  end if;
  v_results := "better_supabase"."evaluate_deadlines"(
    jsonb_build_object('rules', v_version -> 'rules', 'groups', v_version -> 'groups', 'counting', v_version -> 'counting'),
    compute_deadlines.facts, compute_deadlines.as_of, compute_deadlines.group_key);
  return "better_supabase"."deadline_store"(compute_deadlines.tenant, compute_deadlines.subject_type, compute_deadlines.subject_id,
    compute_deadlines.jurisdiction, compute_deadlines.kind, (v_version ->> 'id')::uuid, compute_deadlines.facts, compute_deadlines.as_of,
    v_results, case when compute_deadlines.group_key is null
      then array(
        select g.value ->> 'key' from jsonb_array_elements(v_version -> 'groups') g(value)
        union
        select x."group_key" from "better_supabase"."deadlines" x
        where x."tenant_id" = compute_deadlines.tenant and x."subject_type" = compute_deadlines.subject_type
          and x."subject_id" = compute_deadlines.subject_id and x."jurisdiction" = compute_deadlines.jurisdiction
          and x."kind" = compute_deadlines.kind)
      else array[compute_deadlines.group_key] end) -> 'rows';
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.deadline_subject_readable (
  subject_type text,
  subject_id   text,
  tenant       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return coalesce(case deadline_subject_readable.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'catalog.read'), false)
    when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'rfqs.read'), false)
    when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'tills.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'forms.read'), false)
    when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'meetings.read'), false)
    when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'meetings.read'), false)
    when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'maintenance.read'), false)
    when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'dam.read'), false)
    when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'lims.read'), false)
    when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'tax.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'manufacturing.read'), false)
    when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'banking.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."organization_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant and (coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."tenant_id" = deadline_subject_readable.tenant) and coalesce(better_supabase.can('tenant', deadline_subject_readable.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."organization_id" = deadline_subject_readable.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."organization_id" = deadline_subject_readable.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (deadline_subject_readable.subject_id)::uuid and s."organization_id" = deadline_subject_readable.tenant)
    else false
  end, false);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_deadlines (
  tenant  uuid,
  filters jsonb DEFAULT '{}'::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_deadlines.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', list_deadlines.tenant, 'deadlines.read'), false))) then
    raise exception 'not allowed to read deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'subjectType', y."subject_type", 'subjectId', y."subject_id", 'jurisdiction', y."jurisdiction", 'kind', y."kind", 'groupKey', y."group_key", 'ruleKey', y."rule_key", 'period', y."period", 'ruleVersionId', y."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = y."rule_version_id"), 'facts', y."facts", 'result', y."result", 'dueOn', y."due_on", 'provisional', y."provisional", 'missing', to_jsonb(y."missing"), 'exception', y."exception", 'review', y."review", 'basis', y."basis", 'deadline', y."deadline", 'citation', y."citation", 'asOf', y."as_of", 'state', y."state", 'satisfiedAt', y."satisfied_at", 'satisfiedBy', y."satisfied_by", 'satisfiedAction', y."satisfied_action", 'computedAt', y."computed_at", 'createdAt', y."created_at") order by y."due_on" nulls last, y."created_at")
    from (
      select * from "better_supabase"."deadlines" z
      where z."tenant_id" = list_deadlines.tenant
        and (not v_filters ? 'subjectType' or z."subject_type" = v_filters ->> 'subjectType')
        and (not v_filters ? 'subjectId' or z."subject_id" = v_filters ->> 'subjectId')
        and (not v_filters ? 'groupKey' or z."group_key" = v_filters ->> 'groupKey')
        and (not v_filters ? 'period' or z."period" = v_filters ->> 'period')
        and (not v_filters ? 'state' or z."state" = v_filters ->> 'state')
        and (not v_filters ? 'result' or z."result" = v_filters ->> 'result')
        and (not v_filters ? 'provisional' or z."provisional" = (v_filters ->> 'provisional')::boolean)
        and (not v_filters ? 'dueBefore' or z."due_on" < (v_filters ->> 'dueBefore')::date)
      order by z."due_on" nulls last, z."created_at"
      limit least(greatest(coalesce((v_filters ->> 'limit')::integer, 100), 1), 500)
    ) y
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.recompute_deadlines (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  facts        jsonb DEFAULT '{}'::jsonb
)
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (recompute_deadlines.tenant is not null and coalesce(better_supabase.can('tenant', recompute_deadlines.tenant, 'deadlines.write'), false))) then
    raise exception 'not allowed to compute deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."deadline_subject_readable"(recompute_deadlines.subject_type, recompute_deadlines.subject_id, recompute_deadlines.tenant)) then
    raise exception 'not allowed to compute deadlines for this subject' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  return "better_supabase"."deadline_recompute"(recompute_deadlines.tenant::text, recompute_deadlines.subject_type, recompute_deadlines.subject_id, recompute_deadlines.facts);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.satisfy_deadline (
  deadline_id uuid,
  action      text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."deadlines";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."deadlines" x where x."id" = satisfy_deadline.deadline_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deadlines.read'), false)))
    or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or "better_supabase"."deadline_subject_readable"(v_row."subject_type", v_row."subject_id", v_row."tenant_id")) then
    raise exception 'no such deadline' using errcode = 'P0002', hint = 'DEADLINE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deadlines.write'), false))) then
    raise exception 'not allowed to satisfy deadlines' using errcode = '42501', hint = 'DEADLINE_FORBIDDEN';
  end if;
  if v_row."state" = 'satisfied' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'groupKey', v_row."group_key", 'ruleKey', v_row."rule_key", 'period', v_row."period", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'provisional', v_row."provisional", 'missing', to_jsonb(v_row."missing"), 'exception', v_row."exception", 'review', v_row."review", 'basis', v_row."basis", 'deadline', v_row."deadline", 'citation', v_row."citation", 'asOf', v_row."as_of", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
  end if;
  update "better_supabase"."deadlines" x set "state" = 'satisfied', "satisfied_at" = now(), "satisfied_by" = auth.uid(),
    "satisfied_action" = nullif(btrim(satisfy_deadline.action), '')
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('deadline.satisfied', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'groupKey', v_row."group_key", 'ruleKey', v_row."rule_key", 'period', v_row."period", 'result', v_row."result", 'dueOn', v_row."due_on", 'provisional', v_row."provisional"), 'deadlines/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/deadlines');
  perform better_supabase.audit_event(
    event_type => 'deadline.satisfied',
    category => 'data',
    target_type => 'deadline',
    record_id => v_row."id"::text,
    target_label => v_row."group_key" || coalesce(' ' || v_row."period", '') || ' ' || v_row."subject_type" || '/' || v_row."subject_id",
    summary => 'deadline satisfied',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'groupKey', v_row."group_key", 'ruleKey', v_row."rule_key", 'period', v_row."period", 'result', v_row."result", 'dueOn', v_row."due_on", 'provisional', v_row."provisional")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'jurisdiction', v_row."jurisdiction", 'kind', v_row."kind", 'groupKey', v_row."group_key", 'ruleKey', v_row."rule_key", 'period', v_row."period", 'ruleVersionId', v_row."rule_version_id", 'ruleVersion', (select x."version" from "better_supabase"."deadline_rule_versions" x where x."id" = v_row."rule_version_id"), 'facts', v_row."facts", 'result', v_row."result", 'dueOn', v_row."due_on", 'provisional', v_row."provisional", 'missing', to_jsonb(v_row."missing"), 'exception', v_row."exception", 'review', v_row."review", 'basis', v_row."basis", 'deadline', v_row."deadline", 'citation', v_row."citation", 'asOf', v_row."as_of", 'state', v_row."state", 'satisfiedAt', v_row."satisfied_at", 'satisfiedBy', v_row."satisfied_by", 'satisfiedAction', v_row."satisfied_action", 'computedAt', v_row."computed_at", 'createdAt', v_row."created_at");
end;
$function$;

CREATE POLICY "bsb_tenant_scope_select" ON "better_supabase"."deadlines"
  AS RESTRICTIVE
  FOR SELECT
  TO PUBLIC
  USING
    (((tenant_id IN ( SELECT better_supabase.member_organization_ids() AS member_organization_ids)) OR ((tenant_id IN ( SELECT
    better_supabase.tenant_ids_with('deadlines.read'::text) AS tenant_ids_with)) AND better_supabase.deadline_subject_readable(subject_type, subject_id, tenant_id))));

CREATE POLICY "deadlines_read" ON "better_supabase"."deadlines"
  FOR SELECT
  TO "authenticated"
  USING
    (((tenant_id IN ( SELECT better_supabase.tenant_ids_with('deadlines.read'::text) AS tenant_ids_with)) AND better_supabase.deadline_subject_readable(subject_type, subject_id,
    tenant_id)));

REVOKE ALL ON FUNCTION "better_supabase"."deadline_subject_readable"(text, text, uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."deadline_subject_readable"(text, text, uuid) TO "authenticated", "service_role";
