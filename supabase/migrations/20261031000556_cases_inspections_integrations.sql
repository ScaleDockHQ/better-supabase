SET local check_function_bodies = off;

ALTER TABLE "better_supabase"."inspections"
  ADD COLUMN "overdue_notified_for" date;

CREATE OR REPLACE FUNCTION api.case_close_approved (
  case_id uuid
)
  RETURNS void
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."case_close_approved"($1) $function$;

CREATE OR REPLACE FUNCTION api.notify_overdue_inspections()
  RETURNS integer
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."notify_overdue_inspections"() $function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_finalize (
  request_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
  v_run jsonb;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = approval_finalize.request_id;
  v_run := v_req."policy" -> 'run';
  if v_req."subject_type" = 'ai_tool_approval' then
    perform "better_supabase"."apply_ai_tool_approval"(v_req."subject_id", true, (select x."comment" from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id" order by x."created_at" desc, x."id" desc limit 1));
  end if;
  if v_req."subject_type" = 'access_request' then
    perform "better_supabase"."grant_access_request"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'drive_node' then
    perform "better_supabase"."drive_document_decided"(v_req."id", true);
  end if;
  if v_req."subject_type" = 'timesheet' then
    perform "better_supabase"."approve_timesheet"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'expense_report' then
    perform "better_supabase"."approve_expense_report"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'content_entry' then
    perform "better_supabase"."content_entry_approved"((v_req."subject_id")::uuid);
  end if;
  if v_req."subject_type" = 'care_plan_action' then
    perform "better_supabase"."care_plan_action_approved"(v_req."subject_id"::uuid);
  end if;
  if v_req."subject_type" = 'case' then
    perform "better_supabase"."case_close_approved"(v_req."subject_id"::uuid);
  end if;
  perform "better_supabase".emit_event('approval.approved', jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step"), 'approval-requests/' || v_req."id"::text, (v_req."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval.approved',
    category => 'data',
    target_type => 'approval_request',
    record_id => v_req."id"::text,
    summary => 'approved' || ' ' || v_req."action" || ' on ' || v_req."subject_type" || ' ' || v_req."subject_id",
    tenant => (v_req."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_req."tenant_id"::text, 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'id', v_req."id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step")
  );
  perform "better_supabase"."approval_notify"(v_req."id", 'approved');
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.approval_policy (
  subject_type text,
  action       text
)
  RETURNS jsonb
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO ''
  AS $function$
  select coalesce(case approval_policy.subject_type || ':' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    when 'customer:discount' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'customer:refund' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'customer:export' then '{"steps":[{"approvers":{"manager":true},"required":1}],"selfApproval":false,"expiresIn":null,"run":null,"mode":"confirm"}'::jsonb
    when 'case:close' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'drive_node:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    when 'drive_node:release' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":2}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'eve_tool_call:add_note' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":false,"expiresIn":null,"run":null}'::jsonb
    when 'workflow_run:approve' then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":true,"expiresIn":null,"run":null}'::jsonb
    else null::jsonb
  end, case '*:' || approval_policy.action
    when '*:quote.send' then '{"steps":[],"selfApproval":false,"expiresIn":null,"run":null,"effects":["money-movement"]}'::jsonb
    else null::jsonb
  end)
$function$;

CREATE OR REPLACE FUNCTION better_supabase.bsb_case_guard()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_outcome text;
  v_blockers text[];
begin
  if new."stage_id" is not distinct from old."stage_id" then
    return new;
  end if;
  v_outcome := (select s."outcome" from "better_supabase"."pipeline_stages" s where s."id" = new."stage_id");
  if v_outcome = 'success' then
    if old."status" <> 'closed' then
      v_blockers := "better_supabase"."case_blockers_of"(new);
      if cardinality(v_blockers) > 0 then
        raise exception 'the case can''t close yet' using errcode = '55000', hint = v_blockers[1], detail = jsonb_build_object('blockers', to_jsonb(v_blockers))::text;
      end if;
      new."status" := 'closed';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
      perform "better_supabase"."version_insert"(new."tenant_id", 'case', new."id"::text,
        jsonb_build_object('id', new."id", 'organizationId', new."tenant_id", 'kindId', new."kind_id", 'number', new."number", 'title', new."title", 'description', new."description", 'severity', new."severity", 'source', new."source", 'reporterId', new."reporter_id", 'reporterContact', new."reporter_contact", 'ownerId', new."owner_id", 'occurredAt', new."occurred_at", 'detectedAt', new."detected_at", 'dueOn', new."due_on", 'pipelineId', new."pipeline_id", 'stageId', new."stage_id", 'stageEnteredAt', new."stage_entered_at", 'status', new."status", 'rootCause', new."root_cause", 'rootCauseSubmissionId', new."root_cause_submission_id", 'effective', new."effective", 'effectivenessDueOn', new."effectiveness_due_on", 'effectivenessNote', new."effectiveness_note", 'effectivenessSubmissionId', new."effectiveness_submission_id", 'closedAt', new."closed_at", 'closedBy', new."closed_by", 'closeNote', new."close_note", 'rank', new."rank", 'archivedAt', new."archived_at", 'createdBy', new."created_by", 'createdAt', new."created_at", 'updatedAt', new."updated_at"), null, 'Closed ' || new."number", 'manual', true, auth.uid());
    end if;
  elsif v_outcome = 'failure' then
    if old."status" <> 'canceled' then
      new."status" := 'canceled';
      new."closed_at" := now();
      new."closed_by" := auth.uid();
    end if;
  elsif old."status" <> 'open' then
    new."status" := 'open';
    new."closed_at" := null;
    new."closed_by" := null;
    new."close_note" := null;
  end if;
  new."updated_at" := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.case_blockers_of (
  target better_supabase.cases
)
  RETURNS text[]
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind "better_supabase"."case_kinds";
  v_blockers text[] := '{}';
  v_policy jsonb;
begin
  select * into v_kind from "better_supabase"."case_kinds" y where y."id" = case_blockers_of.target."kind_id";
  if v_kind."requires_root_cause" and coalesce(trim(case_blockers_of.target."root_cause"), '') = '' then
    v_blockers := v_blockers || 'CASE_ROOT_CAUSE_REQUIRED'::text;
  end if;
  if v_kind."requires_actions" and not exists (
    select 1 from "better_supabase"."case_actions" x where x."case_id" = case_blockers_of.target."id" and x."required"
  ) then
    v_blockers := v_blockers || 'CASE_ACTIONS_REQUIRED'::text;
  end if;
  if exists (
    select 1 from "better_supabase"."case_actions" x
    join "better_supabase"."work_items" i on i."id" = x."task_id"
    where x."case_id" = case_blockers_of.target."id" and x."required"
      and i."state" not in ('completed', 'canceled')
  ) then
    v_blockers := v_blockers || 'CASE_ACTIONS_OPEN'::text;
  end if;
  if v_kind."requires_effectiveness" and case_blockers_of.target."effective" is not true then
    v_blockers := v_blockers || 'CASE_EFFECTIVENESS_REQUIRED'::text;
  end if;
  if v_kind."requires_revisions" and exists (
    select 1 from "better_supabase"."relations" r
    join "better_supabase"."drive_nodes" n on n."id"::text = r."target_id"
    where r."kind" = 'affects'
      and r."source_type" = 'case'
      and r."source_id" = case_blockers_of.target."id"::text
      and r."target_type" = 'drive_node'
      and (n."effective_from" is null or n."effective_from" <= case_blockers_of.target."created_at")
  ) then
    v_blockers := v_blockers || 'CASE_DOCUMENTS_NOT_REVISED'::text;
  end if;
  v_policy := "better_supabase"."approval_effective_policy"(case_blockers_of.target."tenant_id", 'case', 'close',
    jsonb_build_object('caseId', case_blockers_of.target."id", 'kind', v_kind."key", 'severity', case_blockers_of.target."severity"));
  if (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0)
    and not exists (
      select 1 from "better_supabase"."approval_requests" r
      where r."subject_type" = 'case'
        and r."subject_id" = case_blockers_of.target."id"::text
        and r."action" = 'close'
        and r."status" = 'approved'
    ) then
    v_blockers := v_blockers || 'CASE_APPROVAL_REQUIRED'::text;
  end if;
  return v_blockers;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.case_close_approved (
  case_id uuid
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_variable
declare
  v_row "better_supabase"."cases";
  v_stage uuid;
begin
  select * into v_row from "better_supabase"."cases" x where x."id" = case_close_approved.case_id for update;
  if not found or v_row."status" <> 'open' or cardinality("better_supabase"."case_blockers_of"(v_row)) > 0 then
    return;
  end if;
  select s."id" into v_stage from "better_supabase"."pipeline_stages" s
  where s."pipeline_id" = v_row."pipeline_id" and s."outcome" = 'success' and s."archived_at" is null
  order by s."rank" collate "C"
  limit 1;
  if v_stage is not null then
    update "better_supabase"."cases" x set "stage_id" = v_stage where x."id" = v_row."id";
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_approval (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  select * into v_req from "better_supabase"."approval_requests" r where r."id" = get_approval.request_id;
  if not found then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_req."requested_by" = auth.uid(), false) or "better_supabase"."approval_eligible"(v_req."id")
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (not v_req."subject_type" in ('ai_tool_approval') and (v_req."subject_type" in ('access_request', 'timesheet', 'expense_report', 'content_entry', 'care_plan_action', 'case') or (case when v_req."subject_type" = 'drive_node' then coalesce(case when v_req."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((v_req."subject_id")::uuid, 'viewer') end, false) else case v_req."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'forms.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'manufacturing.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id" and (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    else false
  end end))))) then
    raise exception 'approval request not found' using errcode = 'P0002', hint = 'APPROVAL_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at") || jsonb_build_object(
    'canDecide', "better_supabase"."approval_eligible"(v_req."id"),
    'decisions', coalesce((
      select jsonb_agg(jsonb_build_object('id', x."id", 'step', x."step", 'approver', x."approver", 'decision', x."decision", 'delegateTo', x."delegate_to", 'comment', x."comment", 'createdAt', x."created_at") order by x."created_at", x."id")
      from "better_supabase"."approval_decisions" x where x."request_id" = v_req."id"
    ), '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inspection_assignment_notice()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_claims text;
begin
  if new."user_id" is not distinct from auth.uid() then
    return new;
  end if;
  select * into v_row from "better_supabase"."inspections" x where x."id" = new."inspection_id";
  if not found or v_row."status" not in ('planned', 'in_progress') then
    return new;
  end if;
  v_claims := current_setting('request.jwt.claims', true);
  perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
  perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'inspection.assigned',
      'tenant', v_row."tenant_id",
      'actor', auth.uid(),
      'subject_type', 'inspection',
      'subject_id', v_row."id"::text,
      'summary', v_row."number" || ' ' || v_row."title",
      'recipients', to_jsonb(array[new."user_id"]),
      'key', 'inspection.assigned:' || v_row."id"::text || ':' || new."user_id"::text,
      'data', jsonb_build_object('inspectionId', v_row."id", 'role', new."role")
    ));
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.inspection_calendar_mirror()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_calendar uuid;
begin
  select y."id" into v_calendar from "better_supabase"."calendars" y
  where y."tenant_id" = new."tenant_id" and y."name" = 'Audits'
  order by y."created_at"
  limit 1;
  if v_calendar is null then
    return new;
  end if;
  if new."planned_start" is null or new."status" not in ('planned', 'in_progress') then
    delete from "better_supabase"."calendar_events" x where x."calendar_id" = v_calendar and x."uid" = 'inspection-' || new."id"::text;
    return new;
  end if;
  insert into "better_supabase"."calendar_events" ("tenant_id", "calendar_id", "uid", "title", "starts_at", "ends_at", "all_day", "tz", "status", "subject_type", "subject_id")
  values (new."tenant_id", v_calendar, 'inspection-' || new."id"::text, new."number" || ' ' || new."title",
    (new."planned_start"::timestamp at time zone 'UTC'),
    (coalesce(new."planned_end", new."planned_start") + 1)::timestamp at time zone 'UTC', true, 'UTC', 'confirmed', 'inspection', new."id"::text)
  on conflict ("calendar_id", "uid", "original_start") do update set
    "title" = excluded."title", "starts_at" = excluded."starts_at",
    "ends_at" = excluded."ends_at", "updated_at" = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_approvals (
  tenant       uuid,
  status       text                     DEFAULT 'pending'::text,
  assigned     boolean                  DEFAULT false,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  page_size    integer                  DEFAULT 50,
  before       timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_rows jsonb;
  v_read boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_approvals.tenant, 'approvals.read'), false);
begin
  select coalesce(jsonb_agg(t.j order by t.at desc, t.id), '[]'::jsonb) into v_rows
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'action', x."action", 'status', x."status", 'step', x."step", 'steps', x."policy" -> 'steps', 'requestedBy', x."requested_by", 'reason', x."reason", 'payload', x."payload", 'expiresAt', x."expires_at", 'decidedAt', x."decided_at", 'mode', coalesce(x."policy" ->> 'mode', 'authorize'), 'fingerprint', x."fingerprint", 'consumedAt', x."consumed_at", 'createdAt', x."created_at") as j, x."created_at" as at, x."id" as id
    from "better_supabase"."approval_requests" x
    where x."tenant_id" = list_approvals.tenant
      and (list_approvals.status is null or x."status" = list_approvals.status)
      and (list_approvals.subject_type is null or x."subject_type" = list_approvals.subject_type)
      and (list_approvals.subject_id is null or x."subject_id" = list_approvals.subject_id)
      and (list_approvals.before is null or x."created_at" < list_approvals.before)
      and case
        when list_approvals.assigned then "better_supabase"."approval_eligible"(x."id")
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (not x."subject_type" in ('ai_tool_approval') and (x."subject_type" in ('access_request', 'timesheet', 'expense_report', 'content_entry', 'care_plan_action', 'case') or (case when x."subject_type" = 'drive_node' then coalesce(case when x."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((x."subject_id")::uuid, 'viewer') end, false) else case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contacts.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'activities.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'tasks.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'compliance.read'), false)
    when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'qualifications.read'), false)
    when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'risks.read'), false)
    when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'cases.read'), false)
    when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'inspections.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'manufacturing.read'), false)
    when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'care_plans.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end end))))) or "better_supabase"."approval_eligible"(x."id")
      end
    order by x."created_at" desc, x."id"
    limit least(greatest(coalesce(list_approvals.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.notify_overdue_inspections()
  RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."inspections"%rowtype;
  v_claims text;
  v_to uuid[];
  v_count integer := 0;
begin
  for v_row in
    select * from "better_supabase"."inspections" x
    where x."status" in ('planned', 'in_progress')
      and x."planned_end" < current_date
      and x."overdue_notified_for" is distinct from x."planned_end"
    for update skip locked
  loop
    select coalesce(array_agg(y."user_id"), '{}'::uuid[]) into v_to from "better_supabase"."inspection_members" y
    where y."inspection_id" = v_row."id" and y."role" = 'lead';
    if cardinality(v_to) = 0 then
      select coalesce(array_agg(y."user_id"), '{}'::uuid[]) into v_to from "better_supabase"."inspection_members" y
      where y."inspection_id" = v_row."id" and y."role" = 'auditor';
    end if;
    if cardinality(v_to) > 0 then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'inspection.overdue',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', 'inspection',
        'subject_id', v_row."id"::text,
        'summary', v_row."number" || ' ' || v_row."title",
        'recipients', to_jsonb(v_to),
        'key', 'inspection.overdue:' || v_row."id"::text || ':' || v_row."planned_end"::text,
        'data', jsonb_build_object('inspectionId', v_row."id", 'plannedEnd', v_row."planned_end")
      ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
    update "better_supabase"."inspections" x set "overdue_notified_for" = v_row."planned_end" where x."id" = v_row."id";
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_approval_policy (
  tenant uuid,
  policy jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_old "better_supabase"."approval_policies"%rowtype;
  v_row "better_supabase"."approval_policies"%rowtype;
  v_type text;
  v_action text;
  v_conditions jsonb;
  v_steps jsonb;
  v_step jsonb;
  v_fields jsonb;
  v_effect text;
  v_who jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_approval_policy.tenant, 'approvals.manage'), false)) then
    raise exception 'managing approval policies needs approvals.manage' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if jsonb_typeof(save_approval_policy.policy) is distinct from 'object' then
    raise exception 'policy must be an object' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if save_approval_policy.policy ? 'id' then
    select * into v_old from "better_supabase"."approval_policies" x
    where x."id" = (save_approval_policy.policy ->> 'id')::uuid and x."tenant_id" is not distinct from save_approval_policy.tenant
    for update;
    if not found then
      raise exception 'approval policy not found' using errcode = 'P0002', hint = 'APPROVAL_POLICY_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(save_approval_policy.policy ->> 'subjectType', v_old."subject_type");
  v_action := coalesce(save_approval_policy.policy ->> 'action', v_old."action");
  v_effect := case when save_approval_policy.policy ? 'effect' then nullif(save_approval_policy.policy ->> 'effect', '') else v_old."effect" end;
  if v_type is null or v_action is null or not (exists (
      select 1 from jsonb_array_elements('[{"subjectType":"*","action":"quote.send","effects":["money-movement"]},{"subjectType":"customer","action":"discount","effects":[]},{"subjectType":"customer","action":"refund","effects":[]},{"subjectType":"customer","action":"export","effects":[]},{"subjectType":"case","action":"close","effects":[]},{"subjectType":"drive_node","action":"approve","effects":[]},{"subjectType":"drive_node","action":"release","effects":[]},{"subjectType":"eve_tool_call","action":"add_note","effects":[]},{"subjectType":"workflow_run","action":"approve","effects":[]}]'::jsonb) f
      where (v_type = '*' or f.value ->> 'subjectType' in (v_type, '*'))
        and (v_action = '*' or f.value ->> 'action' in (v_action, '*'))
        and (v_effect is null or f.value -> 'effects' ? v_effect)
    )) then
    raise exception 'a tenant policy tightens an options.policies entry, and there is none for this subject type, action and effect' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  v_conditions := case when save_approval_policy.policy ? 'conditions' then nullif(save_approval_policy.policy -> 'conditions', 'null'::jsonb) else v_old."conditions" end;
  if v_conditions is not null then
    v_fields := "better_supabase"."rule_field_map"(v_type);
    if v_fields = '{}'::jsonb then
      raise exception 'no rule fields for this subject type; sync them first' using errcode = '22023', hint = 'APPROVAL_FIELDS_MISSING';
    end if;
    perform "better_supabase"."rule_check"(v_conditions, v_fields, 1);
  end if;
  v_steps := coalesce(save_approval_policy.policy -> 'steps', v_old."steps", '[]'::jsonb);
  if jsonb_typeof(v_steps) <> 'array' or jsonb_array_length(v_steps) > 20 then
    raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  for v_step in select * from jsonb_array_elements(v_steps) loop
    if jsonb_typeof(v_step) <> 'object' then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
    for v_who in select a.w from (values (v_step -> 'approvers', true), (v_step -> 'escalateTo', v_step ? 'escalateTo')) a(w, checked) where a.checked loop
      if jsonb_typeof(v_who) is distinct from 'object'
        or not (v_who ?| array['permission', 'role', 'team', 'users', 'manager'])
        or (v_who ? 'manager' and v_who -> 'manager' <> 'true'::jsonb)
        or (v_who ? 'users' and (jsonb_typeof(v_who -> 'users') <> 'array'
          or exists (select 1 from jsonb_array_elements(v_who -> 'users') u
            where jsonb_typeof(u) <> 'string' or u #>> '{}' !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'))) then
        raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
      end if;
    end loop;
    if (v_step ? 'required' and v_step -> 'required' <> '"all"'::jsonb and (jsonb_typeof(v_step -> 'required') <> 'number' or (v_step ->> 'required')::numeric < 1
        or (v_step ->> 'required')::numeric <> trunc((v_step ->> 'required')::numeric)))
      or (v_step -> 'required' = '"all"'::jsonb and (v_step -> 'approvers') - 'permission' <> '{}'::jsonb
        and ((v_step -> 'approvers') - 'users' <> '{}'::jsonb or jsonb_array_length(v_step -> 'approvers' -> 'users') = 0))
      or (jsonb_typeof(v_step -> 'required') = 'number' and (v_step -> 'approvers') - 'users' = '{}'::jsonb
        and (v_step ->> 'required')::numeric > jsonb_array_length(v_step -> 'approvers' -> 'users'))
      or ((v_step ? 'escalateAfter') <> (v_step ? 'escalateTo'))
      or (v_step ? 'escalateAfter' and (jsonb_typeof(v_step -> 'escalateAfter') <> 'string' or (v_step ->> 'escalateAfter')::interval <= interval '0')) then
      raise exception 'steps must be a list of { approvers: { permission, role, team, users, manager }, required, escalateAfter, escalateTo } objects' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
    end if;
  end loop;
  v_steps := (select coalesce(jsonb_agg(case when s -> 'required' = '"all"'::jsonb and (s -> 'approvers') ? 'users'
    then jsonb_set(s, '{required}', to_jsonb(jsonb_array_length(s -> 'approvers' -> 'users'))) || '{"all": true}'::jsonb else s - 'all' end order by o), '[]'::jsonb)
    from jsonb_array_elements(v_steps) with ordinality e(s, o));
  if coalesce(save_approval_policy.policy ->> 'mode', v_old."mode"::text, 'authorize') not in ('confirm', 'authorize') then
    raise exception 'mode must be confirm or authorize' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
  end if;
  if v_old."id" is null then
    insert into "better_supabase"."approval_policies" ("tenant_id", "subject_type", "action", "name", "conditions", "effect", "mode", "steps", "self_approval", "expires_in", "enabled", "created_by", "description")
    values (save_approval_policy.tenant, v_type, v_action, btrim(save_approval_policy.policy ->> 'name'), v_conditions, v_effect,
      coalesce(save_approval_policy.policy ->> 'mode', 'authorize'), v_steps,
      coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, false), (save_approval_policy.policy ->> 'expiresIn')::interval,
      coalesce((save_approval_policy.policy ->> 'enabled')::boolean, true), auth.uid(), case when coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', coalesce(save_approval_policy.policy -> 'fields', '{}'::jsonb) -> 'description')))."description" else better_supabase.column_default('"better_supabase"."approval_policies"', 'description', (null::"better_supabase"."approval_policies")."description") end)
    returning * into v_row;
  else
    update "better_supabase"."approval_policies" x set
      "subject_type" = v_type,
      "action" = v_action,
      "name" = coalesce(btrim(save_approval_policy.policy ->> 'name'), x."name"),
      "conditions" = v_conditions,
      "effect" = v_effect,
      "mode" = coalesce(save_approval_policy.policy ->> 'mode', x."mode"),
      "steps" = v_steps,
      "self_approval" = coalesce((save_approval_policy.policy ->> 'selfApproval')::boolean, x."self_approval"),
      "expires_in" = case when save_approval_policy.policy ? 'expiresIn' then (save_approval_policy.policy ->> 'expiresIn')::interval else x."expires_in" end,
      "enabled" = coalesce((save_approval_policy.policy ->> 'enabled')::boolean, x."enabled"),
      "updated_at" = now(), "description" = case when (save_approval_policy.policy -> 'fields') ? 'description' then (jsonb_populate_record(null::"better_supabase"."approval_policies", jsonb_build_object('description', (save_approval_policy.policy -> 'fields') -> 'description')))."description" else x."description" end
    where x."id" = v_old."id"
    returning * into v_row;
  end if;
  if v_old."id" is null then
    perform "better_supabase".emit_event('approval_policy.created', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.created',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'created approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  else
    perform "better_supabase".emit_event('approval_policy.updated', jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action"), 'approval-policies/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/approvals');
  perform better_supabase.audit_event(
    event_type => 'approval_policy.updated',
    category => 'configuration',
    target_type => 'approval_policy',
    record_id => v_row."id"::text,
    summary => 'updated approval policy ' || v_row."name",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id"::text, 'id', v_row."id", 'subjectType', v_row."subject_type", 'action', v_row."action")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'action', v_row."action", 'effect', v_row."effect", 'name', v_row."name", 'conditions', v_row."conditions", 'mode', v_row."mode", 'steps', v_row."steps", 'selfApproval', v_row."self_approval", 'expiresIn', v_row."expires_in"::text, 'enabled', v_row."enabled", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'fields', jsonb_build_object('description', v_row."description"));
exception
  when invalid_text_representation or invalid_datetime_format or not_null_violation or check_violation then
    raise exception 'policy has an invalid name, mode, expiry or flag' using errcode = '22023', hint = 'APPROVAL_POLICY_INVALID';
end;
$function$;

CREATE TRIGGER bsb_inspection_assignment
  AFTER INSERT ON better_supabase.inspection_members
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.inspection_assignment_notice();

CREATE TRIGGER bsb_inspection_calendar
  AFTER INSERT OR UPDATE OF planned_start, planned_end, title, status ON better_supabase.inspections
  FOR EACH ROW
  EXECUTE FUNCTION better_supabase.inspection_calendar_mirror();

REVOKE ALL ON FUNCTION "api"."case_close_approved"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."case_close_approved"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "api"."notify_overdue_inspections"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."notify_overdue_inspections"() TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."case_close_approved"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."case_close_approved"(uuid) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."inspection_assignment_notice"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."inspection_calendar_mirror"() FROM PUBLIC;

REVOKE ALL ON FUNCTION "better_supabase"."notify_overdue_inspections"() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."notify_overdue_inspections"() TO "service_role";
