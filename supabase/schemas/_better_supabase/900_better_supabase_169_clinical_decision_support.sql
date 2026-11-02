-- better-supabase module: clinical-decision-support
-- @bsb-block clinical-decision-support@1 managed
-- @bsb-hash sha256:3f02fa0a5d0353ce59e4fb3648546112e0a9326893bb23f7dd68b87e686c165d
-- Tenant rules for dose range, duplicate therapy and interactions over a record's medication orders, alerts that members acknowledge or override with a reason, and a decision context for external engines whose alerts are stored the same way.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;
-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."care_rules";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_rules";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_rules";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_rules";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_rules";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."care_alerts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_alerts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_alerts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_alerts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_alerts";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Clinical decision support: tenant rules for dose range, duplicate therapy
-- and interactions over a record's medication orders, alerts that members
-- acknowledge or override with a reason, and a context function for external
-- engines whose alerts are stored the same way.

-- A tenant rule of the built-in set. A dose_range rule bounds the dose of one
-- medication (per dose, or per day with max_per_day), an interaction rule names
-- two medications that must not be active together and a duplicate_therapy rule
-- names the medications of one therapy group.
create table if not exists "better_supabase"."care_rules" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null check ("kind" in ('dose_range', 'duplicate_therapy', 'interaction')),
  "medication_ids" uuid[] not null default '{}',
  "min_dose" numeric check ("min_dose" is null or "min_dose" >= 0),
  "max_dose" numeric check ("max_dose" is null or "max_dose" > 0),
  "max_per_day" numeric check ("max_per_day" is null or "max_per_day" > 0),
  "severity" text not null default 'warning' check ("severity" in ('info', 'warning', 'critical')),
  "message" text check ("message" is null or length("message") <= 1000),
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check (
    ("kind" = 'dose_range' and cardinality("medication_ids") = 1 and ("min_dose" is not null or "max_dose" is not null or "max_per_day" is not null))
    or ("kind" = 'interaction' and cardinality("medication_ids") = 2)
    or ("kind" = 'duplicate_therapy' and cardinality("medication_ids") >= 2)
  )
);
create index if not exists "care_rules_tenant_idx" on "better_supabase"."care_rules" ("tenant_id", "kind");
alter table "better_supabase"."care_rules" enable row level security;
revoke all on "better_supabase"."care_rules" from public, anon, authenticated;
grant select on "better_supabase"."care_rules" to authenticated;
grant all on "better_supabase"."care_rules" to service_role;
drop policy if exists care_rules_read on "better_supabase"."care_rules";
create policy care_rules_read on "better_supabase"."care_rules"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('clinical_decision_support.read')));

-- An alert about a record, from the built-in rules or an external engine
-- (source). The fingerprint identifies the finding, so evaluating again updates
-- the alert instead of raising it twice and keeps a member's decision. order_ids
-- are the medication orders involved.
create table if not exists "better_supabase"."care_alerts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "kind" text not null check ("kind" in ('dose_range', 'duplicate_therapy', 'interaction', 'allergy', 'other')),
  "severity" text not null check ("severity" in ('info', 'warning', 'critical')),
  "source" text not null check (length("source") between 1 and 100),
  "rule_id" uuid,
  "order_ids" uuid[] not null default '{}',
  "message" text not null check (length("message") between 1 and 1000),
  "details" jsonb,
  "fingerprint" text not null check (length("fingerprint") between 1 and 200),
  "status" text not null default 'open' check ("status" in ('open', 'acknowledged', 'overridden', 'resolved')),
  "decided_by" uuid,
  "decided_at" timestamptz,
  "decision_reason" text check ("decision_reason" is null or length("decision_reason") <= 1000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("status" not in ('acknowledged', 'overridden') or "decided_at" is not null)
);
create unique index if not exists "care_alerts_live_key" on "better_supabase"."care_alerts" ("tenant_id", "subject_type", "subject_id", "fingerprint") where "status" <> 'resolved';
create index if not exists "care_alerts_subject_idx" on "better_supabase"."care_alerts" ("tenant_id", "subject_type", "subject_id", "status");
alter table "better_supabase"."care_alerts" enable row level security;
revoke all on "better_supabase"."care_alerts" from public, anon, authenticated;
grant select on "better_supabase"."care_alerts" to authenticated;
grant all on "better_supabase"."care_alerts" to service_role;
drop policy if exists care_alerts_read on "better_supabase"."care_alerts";
create policy care_alerts_read on "better_supabase"."care_alerts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('clinical_decision_support.read')));

-- The alerts an engine raised for a record, stored and diffed by fingerprint:
-- a new fingerprint raises an alert, a known one updates it and keeps the
-- decision, and an open or decided alert of this source that the engine no
-- longer returns is resolved. Not callable through the API.
create or replace function "better_supabase"."sync_care_alerts"(tenant uuid, subject_type text, subject_id text, source text, alerts jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_item jsonb;
  v_row "better_supabase"."care_alerts";
  v_seen text[] := '{}';
  v_kind text;
  v_severity text;
  v_message text;
  v_fingerprint text;
  v_rule uuid;
  v_orders uuid[];
  v_details jsonb;
begin
  if jsonb_typeof(sync_care_alerts.alerts) is distinct from 'array' then
    raise exception 'alerts is an array' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  for v_item in select e.value from jsonb_array_elements(sync_care_alerts.alerts) e loop
    v_kind := coalesce(nullif(v_item ->> 'kind', ''), 'other');
    v_severity := coalesce(nullif(v_item ->> 'severity', ''), 'warning');
    v_message := nullif(trim(v_item ->> 'message'), '');
    if v_kind not in ('dose_range', 'duplicate_therapy', 'interaction', 'allergy', 'other') then
      raise exception 'kind is dose_range, duplicate_therapy, interaction, allergy or other' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
    end if;
    if v_severity not in ('info', 'warning', 'critical') then
      raise exception 'severity is info, warning or critical' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
    end if;
    if v_message is null or length(v_message) > 1000 then
      raise exception 'an alert needs a message of up to 1000 characters' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
    end if;
    v_fingerprint := coalesce(nullif(trim(v_item ->> 'fingerprint'), ''), md5(v_kind || '|' || v_message));
    if length(v_fingerprint) > 200 then
      raise exception 'a fingerprint is up to 200 characters' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
    end if;
    v_details := case when jsonb_typeof(v_item -> 'details') = 'object' then v_item -> 'details' else null end;
    begin
      v_rule := nullif(v_item ->> 'ruleId', '')::uuid;
      v_orders := coalesce((select array_agg(e.value::uuid) from jsonb_array_elements_text(case when jsonb_typeof(v_item -> 'orderIds') = 'array' then v_item -> 'orderIds' else '[]'::jsonb end) e), '{}');
    exception when invalid_text_representation then
      raise exception 'ruleId and orderIds are uuids' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
    end;
    select * into v_row from "better_supabase"."care_alerts" x
    where x."tenant_id" = sync_care_alerts.tenant and x."subject_type" = sync_care_alerts.subject_type and x."subject_id" = sync_care_alerts.subject_id
      and x."fingerprint" = v_fingerprint and x."status" <> 'resolved'
    for update;
    if found then
      update "better_supabase"."care_alerts" x set "kind" = v_kind, "severity" = v_severity, "message" = v_message, "rule_id" = v_rule,
        "order_ids" = v_orders, "details" = v_details, "updated_at" = now()
      where x."id" = v_row."id";
    else
      insert into "better_supabase"."care_alerts" ("tenant_id", "subject_type", "subject_id", "kind", "severity", "source", "rule_id", "order_ids", "message", "details", "fingerprint")
      values (sync_care_alerts.tenant, sync_care_alerts.subject_type, sync_care_alerts.subject_id, v_kind, v_severity, sync_care_alerts.source, v_rule, v_orders, v_message, v_details, v_fingerprint)
      returning * into v_row;
      perform "better_supabase".emit_event('care_alert.raised', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status"), 'care-alerts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_alert.raised',
    category => 'data',
    target_type => 'care_alert',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care alert raised',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status")
  );
    end if;
    v_seen := array_append(v_seen, v_fingerprint);
  end loop;
  for v_row in
    update "better_supabase"."care_alerts" x set "status" = 'resolved', "updated_at" = now()
    where x."tenant_id" = sync_care_alerts.tenant and x."subject_type" = sync_care_alerts.subject_type and x."subject_id" = sync_care_alerts.subject_id
      and x."source" = sync_care_alerts.source and x."status" <> 'resolved' and not (x."fingerprint" = any(v_seen))
    returning x.*
  loop
    perform "better_supabase".emit_event('care_alert.resolved', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status"), 'care-alerts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_alert.resolved',
    category => 'data',
    target_type => 'care_alert',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care alert resolved',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status")
  );
  end loop;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'subjectType', y."subject_type", 'subjectId', y."subject_id", 'kind', y."kind", 'severity', y."severity", 'source', y."source", 'ruleId', y."rule_id", 'orderIds', to_jsonb(y."order_ids"), 'message', y."message", 'details', y."details", 'fingerprint', y."fingerprint", 'status', y."status", 'decidedBy', y."decided_by", 'decidedAt', y."decided_at", 'decisionReason', y."decision_reason", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by case y."severity" when 'critical' then 0 when 'warning' then 1 else 2 end, y."created_at", y."id")
    from "better_supabase"."care_alerts" y
    where y."tenant_id" = sync_care_alerts.tenant and y."subject_type" = sync_care_alerts.subject_type and y."subject_id" = sync_care_alerts.subject_id and y."status" <> 'resolved'
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."sync_care_alerts"(uuid, text, text, text, jsonb) from public, anon, authenticated, service_role;

-- Runs the built-in rule set over a record's active medication orders: dose
-- range (a dose or a daily total outside a rule's bounds), duplicate therapy
-- (one medication ordered twice, or two medications of a therapy group) and
-- interaction (both medications of a pair are active). Returns the record's
-- open alerts. Needs clinical_decision_support.write.
create or replace function "better_supabase"."evaluate_care_rules"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_alerts jsonb;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (evaluate_care_rules.tenant is not null and coalesce(better_supabase.can('tenant', evaluate_care_rules.tenant, 'clinical_decision_support.write'), false))) then
    raise exception 'not allowed to evaluate care rules' using errcode = '42501', hint = 'CARE_ALERT_FORBIDDEN';
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
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
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
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."tenant_id"::text = evaluate_care_rules.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (evaluate_care_rules.subject_id)::uuid and s."organization_id"::text = evaluate_care_rules.tenant::text)
      else false
    end and "better_supabase"."can_subject"(evaluate_care_rules.subject_type, evaluate_care_rules.subject_id, 'read'))) then
    raise exception 'evaluating needs a record of the organization' using errcode = '22023', hint = 'CARE_ALERT_SUBJECT_INVALID';
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
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'dose_range' and r."min_dose" is not null and d.dose < r."min_dose"
    union all 
      select jsonb_build_object(
        'kind', 'dose_range', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', jsonb_build_array(d.order_id),
        'fingerprint', 'dose_range:' || r."id"::text || ':' || d.order_id::text || ':max',
        'message', coalesce(r."message", format('%s: a dose of %s %s is above the maximum of %s', d.name, d.dose, d.unit, r."max_dose")),
        'details', jsonb_build_object('medicationId', d.medication_id, 'limit', 'max', 'value', d.dose, 'unit', d.unit, 'bound', r."max_dose"))
      from active d join "better_supabase"."care_rules" r on r."medication_ids"[1] = d.medication_id
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'dose_range' and r."max_dose" is not null and d.dose > r."max_dose"
    union all 
      select jsonb_build_object(
        'kind', 'dose_range', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', jsonb_build_array(d.order_id),
        'fingerprint', 'dose_range:' || r."id"::text || ':' || d.order_id::text || ':day',
        'message', coalesce(r."message", format('%s: %s %s a day is above the maximum of %s', d.name, d.per_day, d.unit, r."max_per_day")),
        'details', jsonb_build_object('medicationId', d.medication_id, 'limit', 'day', 'value', d.per_day, 'unit', d.unit, 'bound', r."max_per_day"))
      from active d join "better_supabase"."care_rules" r on r."medication_ids"[1] = d.medication_id
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'dose_range' and r."max_per_day" is not null and d.per_day > r."max_per_day"
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
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'duplicate_therapy'
      group by r."id" having count(distinct d.medication_id) > 1
    union all
      select jsonb_build_object(
        'kind', 'interaction', 'severity', r."severity", 'ruleId', r."id",
        'orderIds', (select to_jsonb(array_agg(d.order_id order by d.order_id)) from active d where d.medication_id = any(r."medication_ids")),
        'fingerprint', 'interaction:' || r."id"::text,
        'message', coalesce(r."message", format('%s interact', (select string_agg(distinct d.name, ' and ') from active d where d.medication_id = any(r."medication_ids")))),
        'details', jsonb_build_object('medicationIds', to_jsonb(r."medication_ids")))
      from "better_supabase"."care_rules" r
      where r."tenant_id" = evaluate_care_rules.tenant and r."active" and r."kind" = 'interaction'
        and (select count(distinct d.medication_id) from active d where d.medication_id = any(r."medication_ids")) = 2
  )
  select coalesce(jsonb_agg(raised.alert), '[]'::jsonb) into v_alerts from raised;
  return "better_supabase"."sync_care_alerts"(evaluate_care_rules.tenant, evaluate_care_rules.subject_type, evaluate_care_rules.subject_id, 'built-in', v_alerts);
end;
$$;
revoke execute on function "better_supabase"."evaluate_care_rules"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."evaluate_care_rules"(uuid, text, text) to authenticated, service_role;

-- Stores the alerts an external engine returned for a record, keyed by its
-- source name. Alerts of that source the engine no longer returns are resolved.
-- The built-in source name is reserved. Needs clinical_decision_support.write.
create or replace function "better_supabase"."record_care_alerts"(tenant uuid, subject_type text, subject_id text, source text, alerts jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (record_care_alerts.tenant is not null and coalesce(better_supabase.can('tenant', record_care_alerts.tenant, 'clinical_decision_support.write'), false))) then
    raise exception 'not allowed to record care alerts' using errcode = '42501', hint = 'CARE_ALERT_FORBIDDEN';
  end if;
  if coalesce(trim(record_care_alerts.source), '') = '' or length(record_care_alerts.source) > 100 or record_care_alerts.source = 'built-in' then
    raise exception 'source names the engine, up to 100 characters, and is not the built-in source' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case record_care_alerts.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (record_care_alerts.subject_id)::uuid and s."organization_id"::text = record_care_alerts.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (record_care_alerts.subject_id)::uuid and s."tenant_id"::text = record_care_alerts.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (record_care_alerts.subject_id)::uuid and s."organization_id"::text = record_care_alerts.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (record_care_alerts.subject_id)::uuid and s."organization_id"::text = record_care_alerts.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (record_care_alerts.subject_id)::uuid and s."organization_id"::text = record_care_alerts.tenant::text)
      else false
    end and "better_supabase"."can_subject"(record_care_alerts.subject_type, record_care_alerts.subject_id, 'read'))) then
    raise exception 'recording needs a record of the organization' using errcode = '22023', hint = 'CARE_ALERT_SUBJECT_INVALID';
  end if;
  return "better_supabase"."sync_care_alerts"(record_care_alerts.tenant, record_care_alerts.subject_type, record_care_alerts.subject_id, trim(record_care_alerts.source), record_care_alerts.alerts);
end;
$$;
revoke execute on function "better_supabase"."record_care_alerts"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."record_care_alerts"(uuid, text, text, text, jsonb) to authenticated, service_role;

-- What an external engine needs to decide: the record's active medication
-- orders, the latest observation of each kind, granted consents and the
-- active care plan. Blocks that aren't installed contribute nothing. Needs
-- clinical_decision_support.read.
create or replace function "better_supabase"."care_decision_context"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (care_decision_context.tenant is not null and coalesce(better_supabase.can('tenant', care_decision_context.tenant, 'clinical_decision_support.read'), false))) then
    raise exception 'not allowed to read the decision context' using errcode = '42501', hint = 'CARE_ALERT_FORBIDDEN';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case care_decision_context.subject_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'rfq' then exists (select 1 from "better_supabase"."rfqs" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'till' then exists (select 1 from "better_supabase"."tills" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'maintenance_plan' then exists (select 1 from "better_supabase"."maintenance_plans" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'dam_usage_right' then exists (select 1 from "better_supabase"."dam_usage_rights" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'lims_sample' then exists (select 1 from "better_supabase"."lims_samples" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'tax_code' then exists (select 1 from "better_supabase"."tax_codes" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (care_decision_context.subject_id)::uuid and s."tenant_id"::text = care_decision_context.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (care_decision_context.subject_id)::uuid and s."organization_id"::text = care_decision_context.tenant::text)
      else false
    end and "better_supabase"."can_subject"(care_decision_context.subject_type, care_decision_context.subject_id, 'read'))) then
    raise exception 'the context needs a record of the organization' using errcode = '22023', hint = 'CARE_ALERT_SUBJECT_INVALID';
  end if;
  return jsonb_build_object(
    'organizationId', care_decision_context.tenant,
    'subjectType', care_decision_context.subject_type,
    'subjectId', care_decision_context.subject_id,
    'medications', coalesce((select jsonb_agg(jsonb_build_object('orderId', o."id", 'medicationId', o."medication_id", 'name', mx."name", 'codeSystem', mx."code_system", 'code', mx."code", 'dose', o."dose", 'doseUnit', o."dose_unit", 'asNeeded', o."as_needed", 'maxPerDay', o."max_per_day", 'schedule', o."schedule", 'startsOn', o."starts_on", 'endsOn', o."ends_on") order by mx."name", o."id")
      from "better_supabase"."medication_orders" o join "better_supabase"."medications" mx on mx."id" = o."medication_id" and mx."tenant_id" = o."tenant_id"
    where o."tenant_id" = care_decision_context.tenant and o."subject_type" = care_decision_context.subject_type and o."subject_id" = care_decision_context.subject_id
      and o."status" = 'active' and o."starts_on" <= (now() at time zone 'UTC')::date and (o."ends_on" is null or o."ends_on" >= (now() at time zone 'UTC')::date)), '[]'::jsonb),
    'observations', coalesce((select jsonb_agg(jsonb_build_object('key', q."key", 'code', q."code", 'codeSystem', q."code_system", 'unit', q."unit", 'valueNumber', q."value_number", 'valueText', q."value_text", 'valueCode', q."value_code", 'flag', q."flag", 'observedAt', q."observed_at") order by q."key")
      from (select distinct on (od."id") od."key", od."code", od."code_system", od."unit", ox."value_number", ox."value_text", ox."value_code", ox."flag", ox."observed_at"
        from "better_supabase"."observations" ox join "better_supabase"."observation_definitions" od on od."id" = ox."definition_id"
        where ox."tenant_id" = care_decision_context.tenant and ox."subject_type" = care_decision_context.subject_type and ox."subject_id" = care_decision_context.subject_id and ox."status" <> 'entered_in_error'
        order by od."id", ox."observed_at" desc) q), '[]'::jsonb),
    'consents', coalesce((select jsonb_agg(jsonb_build_object('purpose', pu."key", 'status', cx."status", 'scope', cx."scope", 'grantedAt', cx."granted_at", 'validUntil', cx."valid_until") order by pu."key")
      from "better_supabase"."consents" cx join "better_supabase"."consent_purposes" pu on pu."id" = cx."purpose_id"
      where cx."tenant_id" = care_decision_context.tenant and cx."subject_type" = care_decision_context.subject_type and cx."subject_id" = care_decision_context.subject_id and cx."status" = 'granted'), '[]'::jsonb),
    'carePlan', (select jsonb_build_object('id', px."id", 'title', px."title", 'version', px."version", 'reviewOn', px."review_on")
      from "better_supabase"."care_plans" px
      where px."tenant_id" = care_decision_context.tenant and px."subject_type" = care_decision_context.subject_type and px."subject_id" = care_decision_context.subject_id and px."status" = 'active'
      order by px."version" desc limit 1));
end;
$$;
revoke execute on function "better_supabase"."care_decision_context"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."care_decision_context"(uuid, text, text) to authenticated, service_role;

-- A record's alerts, serious ones first. filters is { subjectType, subjectId,
-- status, kind, limit, offset }; without a status the resolved ones are left out.
create or replace function "better_supabase"."list_care_alerts"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_care_alerts.filters, '{}'::jsonb);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_care_alerts.tenant is not null and coalesce(better_supabase.can('tenant', list_care_alerts.tenant, 'clinical_decision_support.read'), false))) then
    raise exception 'not allowed to read care alerts' using errcode = '42501', hint = 'CARE_ALERT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'kind', q."kind", 'severity', q."severity", 'source', q."source", 'ruleId', q."rule_id", 'orderIds', to_jsonb(q."order_ids"), 'message', q."message", 'details', q."details", 'fingerprint', q."fingerprint", 'status', q."status", 'decidedBy', q."decided_by", 'decidedAt', q."decided_at", 'decisionReason', q."decision_reason", 'createdAt', q."created_at", 'updatedAt', q."updated_at") order by case q."severity" when 'critical' then 0 when 'warning' then 1 else 2 end, q."created_at" desc, q."id")
    from (
      select y.* from "better_supabase"."care_alerts" y
      where y."tenant_id" = list_care_alerts.tenant
        and (v_filters ->> 'subjectType' is null or y."subject_type" = v_filters ->> 'subjectType')
        and (v_filters ->> 'subjectId' is null or y."subject_id" = v_filters ->> 'subjectId')
        and (v_filters ->> 'kind' is null or y."kind" = v_filters ->> 'kind')
        and ((v_filters ->> 'status' is null and y."status" <> 'resolved') or y."status" = v_filters ->> 'status')
      order by y."created_at" desc, y."id"
      limit least(greatest(coalesce((v_filters ->> 'limit')::int, 50), 1), 200) offset greatest(coalesce((v_filters ->> 'offset')::int, 0), 0)
    ) q
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_care_alerts"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_care_alerts"(uuid, jsonb) to authenticated, service_role;

-- Saves a rule of the built-in set. attrs is { id, kind, medicationIds,
-- minDose, maxDose, maxPerDay, severity, message, active }: a dose_range rule
-- names one medication and at least one bound, an interaction rule names two,
-- and a duplicate_therapy rule names the medications of one therapy group.
-- Without an id it adds a rule. Needs clinical_decision_support.manage.
create or replace function "better_supabase"."save_care_rule"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception 'not allowed to change care rules' using errcode = '42501', hint = 'CARE_ALERT_FORBIDDEN';
  end if;
  begin
    v_id := nullif(v_attrs ->> 'id', '')::uuid;
    v_ids := coalesce((select array_agg(distinct e.value::uuid) from jsonb_array_elements_text(case when jsonb_typeof(v_attrs -> 'medicationIds') = 'array' then v_attrs -> 'medicationIds' else '[]'::jsonb end) e), '{}');
    v_min := nullif(v_attrs ->> 'minDose', '')::numeric;
    v_max := nullif(v_attrs ->> 'maxDose', '')::numeric;
    v_day := nullif(v_attrs ->> 'maxPerDay', '')::numeric;
    v_active := coalesce((v_attrs ->> 'active')::boolean, true);
  exception when invalid_text_representation or invalid_parameter_value then
    raise exception 'ids are uuids, doses are numbers and active is true or false' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end;
  v_kind := v_attrs ->> 'kind';
  v_severity := coalesce(nullif(v_attrs ->> 'severity', ''), 'warning');
  v_message := nullif(trim(v_attrs ->> 'message'), '');
  if v_kind is null or v_kind not in ('dose_range', 'duplicate_therapy', 'interaction') then
    raise exception 'kind is dose_range, duplicate_therapy or interaction' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if v_severity not in ('info', 'warning', 'critical') then
    raise exception 'severity is info, warning or critical' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if v_message is not null and length(v_message) > 1000 then
    raise exception 'a message is up to 1000 characters' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if (select count(*) from "better_supabase"."medications" mx where mx."tenant_id" = save_care_rule.tenant and mx."id" = any(v_ids)) <> cardinality(v_ids) then
    raise exception 'medicationIds names medications that are not in the organization''s catalog' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if v_kind = 'dose_range' and (cardinality(v_ids) <> 1 or (v_min is null and v_max is null and v_day is null)) then
    raise exception 'a dose range rule names one medication and at least one bound' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if v_kind = 'dose_range' and v_min is not null and v_max is not null and v_min > v_max then
    raise exception 'minDose is at most maxDose' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if v_kind <> 'dose_range' and (v_min is not null or v_max is not null or v_day is not null) then
    raise exception 'only a dose range rule has dose bounds' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if v_kind = 'interaction' and cardinality(v_ids) <> 2 then
    raise exception 'an interaction rule names two medications' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if v_kind = 'duplicate_therapy' and cardinality(v_ids) < 2 then
    raise exception 'a duplicate therapy rule names at least two medications' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."care_rules" ("tenant_id", "kind", "medication_ids", "min_dose", "max_dose", "max_per_day", "severity", "message", "active")
      values (save_care_rule.tenant, v_kind, v_ids, v_min, v_max, v_day, v_severity, v_message, v_active)
      returning * into v_row;
      v_created := true;
    else
      update "better_supabase"."care_rules" x set "kind" = v_kind, "medication_ids" = v_ids, "min_dose" = v_min, "max_dose" = v_max,
        "max_per_day" = v_day, "severity" = v_severity, "message" = v_message, "active" = v_active, "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_care_rule.tenant
      returning * into v_row;
      if not found then
        raise exception 'no such rule' using errcode = 'P0002', hint = 'CARE_RULE_NOT_FOUND';
      end if;
    end if;
  exception when check_violation then
    raise exception 'the rule''s medications and bounds do not fit its kind' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
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
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_care_rule"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_care_rule"(uuid, jsonb) to authenticated, service_role;

-- Deletes a rule. Alerts it raised stay until the next evaluation resolves
-- them. Needs clinical_decision_support.manage.
create or replace function "better_supabase"."delete_care_rule"(rule_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_rules";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_rules" x where x."id" = delete_care_rule.rule_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.read'), false))) then
    raise exception 'no such rule' using errcode = 'P0002', hint = 'CARE_RULE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.manage'), false))) then
    raise exception 'not allowed to change care rules' using errcode = '42501', hint = 'CARE_ALERT_FORBIDDEN';
  end if;
  delete from "better_supabase"."care_rules" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('care_rule.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity"), 'care-rules/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_rule.deleted',
    category => 'configuration',
    target_type => 'care_rule',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care rule deleted',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'kind', v_row."kind", 'severity', v_row."severity")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'kind', v_row."kind", 'medicationIds', to_jsonb(v_row."medication_ids"), 'minDose', v_row."min_dose", 'maxDose', v_row."max_dose", 'maxPerDay', v_row."max_per_day", 'severity', v_row."severity", 'message', v_row."message", 'active', v_row."active", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."delete_care_rule"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_care_rule"(uuid) to authenticated, service_role;

-- The organization's rules, by kind. Needs clinical_decision_support.read.
create or replace function "better_supabase"."list_care_rules"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_care_rules.tenant is not null and coalesce(better_supabase.can('tenant', list_care_rules.tenant, 'clinical_decision_support.read'), false))) then
    raise exception 'not allowed to read care rules' using errcode = '42501', hint = 'CARE_ALERT_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'kind', y."kind", 'medicationIds', to_jsonb(y."medication_ids"), 'minDose', y."min_dose", 'maxDose', y."max_dose", 'maxPerDay', y."max_per_day", 'severity', y."severity", 'message', y."message", 'active', y."active", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."kind", y."created_at", y."id")
    from "better_supabase"."care_rules" y
    where y."tenant_id" = list_care_rules.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_care_rules"(uuid) from public, anon;
grant execute on function "better_supabase"."list_care_rules"(uuid) to authenticated, service_role;

-- Acknowledges or overrides an open alert. Overriding, and any decision on a
-- critical alert, needs a reason. The decision is audited and stays on the
-- alert while the engine keeps raising it. Needs clinical_decision_support.write.
create or replace function "better_supabase"."decide_care_alert"(alert_id uuid, decision text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."care_alerts";
  v_reason text := nullif(trim(decide_care_alert.reason), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."care_alerts" x where x."id" = decide_care_alert.alert_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.read'), false))) then
    raise exception 'no such alert' using errcode = 'P0002', hint = 'CARE_ALERT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'clinical_decision_support.write'), false))) then
    raise exception 'not allowed to decide on care alerts' using errcode = '42501', hint = 'CARE_ALERT_FORBIDDEN';
  end if;
  if decide_care_alert.decision is null or decide_care_alert.decision not in ('acknowledged', 'overridden') then
    raise exception 'decision is acknowledged or overridden' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if v_row."status" = 'resolved' or (v_row."status" = 'overridden') or (v_row."status" = 'acknowledged' and decide_care_alert.decision = 'acknowledged') then
    raise exception 'this alert has already been decided or resolved' using errcode = '55000', hint = 'CARE_ALERT_STATUS';
  end if;
  if v_reason is null and (decide_care_alert.decision = 'overridden' or v_row."severity" = 'critical') then
    raise exception 'overriding an alert, or deciding on a critical one, needs a reason' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  if v_reason is not null and length(v_reason) > 1000 then
    raise exception 'a reason is up to 1000 characters' using errcode = '22023', hint = 'CARE_ALERT_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_care_alert_decide"(uuid, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text)', v_hook::oid::regproc)
        using v_row."id", decide_care_alert.decision;
    end if;
  end;
  update "better_supabase"."care_alerts" x set "status" = decide_care_alert.decision, "decided_by" = auth.uid(), "decided_at" = now(),
    "decision_reason" = v_reason, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('care_alert.decided', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status"), 'care-alerts/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/clinical-decision-support');
  perform better_supabase.audit_event(
    event_type => 'care_alert.decided',
    category => 'data',
    target_type => 'care_alert',
    record_id => v_row."id"::text,
    target_label => v_row."kind",
    summary => 'care alert decided',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'status', v_row."status")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_care_alert_decide"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'kind', v_row."kind", 'severity', v_row."severity", 'source', v_row."source", 'ruleId', v_row."rule_id", 'orderIds', to_jsonb(v_row."order_ids"), 'message', v_row."message", 'details', v_row."details", 'fingerprint', v_row."fingerprint", 'status', v_row."status", 'decidedBy', v_row."decided_by", 'decidedAt', v_row."decided_at", 'decisionReason', v_row."decision_reason", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."decide_care_alert"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."decide_care_alert"(uuid, text, text) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_organization_ids(text[])') is null then
    create function better_supabase.member_organization_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."care_rules";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_rules";
create policy bsb_tenant_scope_select on "better_supabase"."care_rules" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('clinical_decision_support.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_rules";
create policy bsb_tenant_scope_insert on "better_supabase"."care_rules" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_rules";
create policy bsb_tenant_scope_update on "better_supabase"."care_rules" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_rules";
create policy bsb_tenant_scope_delete on "better_supabase"."care_rules" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."care_alerts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."care_alerts";
create policy bsb_tenant_scope_select on "better_supabase"."care_alerts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('clinical_decision_support.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."care_alerts";
create policy bsb_tenant_scope_insert on "better_supabase"."care_alerts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."care_alerts";
create policy bsb_tenant_scope_update on "better_supabase"."care_alerts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."care_alerts";
create policy bsb_tenant_scope_delete on "better_supabase"."care_alerts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
do $$
begin
  perform better_supabase.audit('better_supabase.care_alerts', target_type => 'care_alert', event_prefix => 'care_alert', deferred => true);
  perform better_supabase.audit('better_supabase.care_rules', target_type => 'care_rule', event_prefix => 'care_rule', deferred => true);
end;
$$;

-- blocks.clinical-decision-support.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."actor_may_write"()
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."actor_may_write"() $$;
revoke execute on function "api"."actor_may_write"() from public;
grant execute on function "api"."actor_may_write"() to anon, authenticated, service_role;

create or replace function "api"."raise_actor_readonly"()
returns void
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."raise_actor_readonly"() $$;
revoke execute on function "api"."raise_actor_readonly"() from public;
grant execute on function "api"."raise_actor_readonly"() to anon, authenticated, service_role;

create or replace function "api"."evaluate_care_rules"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."evaluate_care_rules"($1, $2, $3) $$;
revoke execute on function "api"."evaluate_care_rules"(uuid, text, text) from public, anon;
grant execute on function "api"."evaluate_care_rules"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."record_care_alerts"(tenant uuid, subject_type text, subject_id text, source text, alerts jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_care_alerts"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."record_care_alerts"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "api"."record_care_alerts"(uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."care_decision_context"(tenant uuid, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."care_decision_context"($1, $2, $3) $$;
revoke execute on function "api"."care_decision_context"(uuid, text, text) from public, anon;
grant execute on function "api"."care_decision_context"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."list_care_alerts"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_care_alerts"($1, $2) $$;
revoke execute on function "api"."list_care_alerts"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_care_alerts"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."save_care_rule"(tenant uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_care_rule"($1, $2) $$;
revoke execute on function "api"."save_care_rule"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_care_rule"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_care_rule"(rule_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_care_rule"($1) $$;
revoke execute on function "api"."delete_care_rule"(uuid) from public, anon;
grant execute on function "api"."delete_care_rule"(uuid) to authenticated, service_role;

create or replace function "api"."list_care_rules"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_care_rules"($1) $$;
revoke execute on function "api"."list_care_rules"(uuid) from public, anon;
grant execute on function "api"."list_care_rules"(uuid) to authenticated, service_role;

create or replace function "api"."decide_care_alert"(alert_id uuid, decision text, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_care_alert"($1, $2, $3) $$;
revoke execute on function "api"."decide_care_alert"(uuid, text, text) from public, anon;
grant execute on function "api"."decide_care_alert"(uuid, text, text) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;
