SET local check_function_bodies = off;

DROP FUNCTION "better_supabase"."comment_count_rows"(uuid[]);

CREATE OR REPLACE FUNCTION api.can_subjects (
  subject_type text,
  subject_ids  text[],
  action       text
)
  RETURNS SETOF text
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."can_subjects"($1, $2, $3) $function$;

CREATE OR REPLACE FUNCTION api.usage_quotas_for (
  tenants uuid[],
  meters  text[]
)
  RETURNS TABLE (
    tenant      uuid,
    meter       text,
    quota_limit numeric,
    period      text
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$ select * from "better_supabase"."usage_quotas_for"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subjects (
  subject_type text,
  subject_ids  text[],
  action       text
)
  RETURNS SETOF text
  LANGUAGE plpgsql
  STABLE
  COST 1000
  SET search_path TO ''
  AS $function$
begin
  case can_subjects.subject_type
    when 'message' then
      return query
        select s."id"::text from "better_supabase"."messages" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end);
    when 'conversation' then
      return query
        select s."id"::text from "better_supabase"."conversations" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end);
    when 'channel' then
      return query
        select s."id"::text from "better_supabase"."channels" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'channels.manage'), false)
          else true
        end);
    when 'company' then
      return query
        select s."id"::text from "better_supabase"."companies" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end);
    when 'person' then
      return query
        select s."id"::text from "better_supabase"."people" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contacts.write'), false)
          else true
        end);
    when 'deal' then
      return query
        select s."id"::text from "better_supabase"."deals" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end);
    when 'course' then
      return query
        select s."id"::text from "better_supabase"."courses" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.manage'), false)
          else true
        end);
    when 'post' then
      return query
        select s."id"::text from "better_supabase"."posts" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.write'), false)
          else true
        end);
    when 'activity' then
      return query
        select s."id"::text from "better_supabase"."activities" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'activities.write'), false)
          else true
        end);
    when 'quote' then
      return query
        select s."id"::text from "better_supabase"."quotes" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.write'), false)
          else true
        end);
    when 'work_item' then
      return query
        select s."id"::text from "better_supabase"."work_items" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tasks.write'), false)
          else true
        end);
    when 'employee' then
      return query
        select s."id"::text from "better_supabase"."employees" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end);
    when 'ledger_account' then
      return query
        select s."id"::text from "better_supabase"."ledger_accounts" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.manage'), false)
          else true
        end);
    when 'invoice' then
      return query
        select s."id"::text from "better_supabase"."invoices" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.write'), false)
          else true
        end);
    when 'product' then
      return query
        select s."id"::text from "better_supabase"."products" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end);
    when 'product_variant' then
      return query
        select s."id"::text from "better_supabase"."product_variants" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end);
    when 'rfq' then
      return query
        select s."id"::text from "better_supabase"."rfqs" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'rfqs.write'), false)
          else true
        end);
    when 'till' then
      return query
        select s."id"::text from "better_supabase"."tills" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tills.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tills.write'), false)
          else true
        end);
    when 'order' then
      return query
        select s."id"::text from "better_supabase"."orders" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.manage'), false)
          else true
        end);
    when 'calendar_event' then
      return query
        select s."id"::text from "better_supabase"."calendar_events" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.write'), false)
          else true
        end);
    when 'booking' then
      return query
        select s."id"::text from "better_supabase"."bookings" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.manage'), false)
          else true
        end);
    when 'asset' then
      return query
        select s."id"::text from "better_supabase"."assets" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end);
    when 'asset_location' then
      return query
        select s."id"::text from "better_supabase"."asset_locations" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end);
    when 'lease' then
      return query
        select s."id"::text from "better_supabase"."leases" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.manage'), false)
          else true
        end);
    when 'expense_report' then
      return query
        select s."id"::text from "better_supabase"."expense_reports" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          else true
        end);
    when 'expense_line' then
      return query
        select s."id"::text from "better_supabase"."expense_lines" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.submit'), false)
          else true
        end);
    when 'donation_fund' then
      return query
        select s."id"::text from "better_supabase"."donation_funds" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.manage'), false)
          else true
        end);
    when 'warranty_claim' then
      return query
        select s."id"::text from "better_supabase"."warranty_claims" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'warranty.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'warranty.write'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'warranty.write'), false)
          else true
        end);
    when 'work_order' then
      return query
        select s."id"::text from "better_supabase"."work_orders" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.manage'), false)
          else true
        end);
    when 'shipment' then
      return query
        select s."id"::text from "better_supabase"."shipments" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.manage'), false)
          else true
        end);
    when 'contract' then
      return query
        select s."id"::text from "better_supabase"."contracts" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.write'), false)
          else true
        end);
    when 'control' then
      return query
        select s."id"::text from "better_supabase"."controls" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end);
    when 'compliance_policy' then
      return query
        select s."id"::text from "better_supabase"."compliance_policies" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'compliance.manage'), false)
          else true
        end);
    when 'qualification_type' then
      return query
        select s."id"::text from "better_supabase"."qualification_types" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'qualifications.manage'), false)
          else true
        end);
    when 'risk' then
      return query
        select s."id"::text from "better_supabase"."risks" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'risks.write'), false)
          else true
        end);
    when 'case' then
      return query
        select s."id"::text from "better_supabase"."cases" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'cases.write'), false)
          else true
        end);
    when 'inspection' then
      return query
        select s."id"::text from "better_supabase"."inspections" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end);
    when 'inspection_program' then
      return query
        select s."id"::text from "better_supabase"."inspection_programs" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.manage'), false)
          else true
        end);
    when 'inspection_finding' then
      return query
        select s."id"::text from "better_supabase"."inspection_findings" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'inspections.write'), false)
          else true
        end);
    when 'form' then
      return query
        select s."id"::text from "better_supabase"."forms" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.manage'), false)
          else true
        end);
    when 'meeting' then
      return query
        select s."id"::text from "better_supabase"."meetings" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end);
    when 'meeting_decision' then
      return query
        select s."id"::text from "better_supabase"."meeting_decisions" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'meetings.write'), false)
          else true
        end);
    when 'maintenance_plan' then
      return query
        select s."id"::text from "better_supabase"."maintenance_plans" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'maintenance.manage'), false)
          else true
        end);
    when 'dam_usage_right' then
      return query
        select s."id"::text from "better_supabase"."dam_usage_rights" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dam.write'), false)
          else true
        end);
    when 'lims_sample' then
      return query
        select s."id"::text from "better_supabase"."lims_samples" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'lims.write'), false)
          else true
        end);
    when 'tax_code' then
      return query
        select s."id"::text from "better_supabase"."tax_codes" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'tax.manage'), false)
          else true
        end);
    when 'production_order' then
      return query
        select s."id"::text from "better_supabase"."production_orders" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.write'), false)
          else true
        end);
    when 'work_center' then
      return query
        select s."id"::text from "better_supabase"."work_centers" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'manufacturing.manage'), false)
          else true
        end);
    when 'bank_account' then
      return query
        select s."id"::text from "better_supabase"."bank_accounts" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'banking.manage'), false)
          else true
        end);
    when 'care_plan' then
      return query
        select s."id"::text from "better_supabase"."care_plans" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'care_plans.write'), false)
          else true
        end);
    when 'incident' then
      return query
        select s."id"::text from "better_supabase"."incidents" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.write'), false)
          else true
        end);
    when 'advisory' then
      return query
        select s."id"::text from "better_supabase"."advisories" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.write'), false)
          else true
        end);
    when 'advisory_product' then
      return query
        select s."id"::text from "better_supabase"."advisory_products" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.write'), false)
          else true
        end);
    when 'vulnerability' then
      return query
        select s."id"::text from "better_supabase"."vulnerabilities" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'advisories.write'), false)
          else true
        end);
    when 'content_entry' then
      return query
        select s."id"::text from "better_supabase"."content_entries" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.write'), false)
          else true
        end);
    when 'document' then
      return query
        select s."id"::text from "better_supabase"."documents" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.write'), false)
          else true
        end);
    when 'customer' then
      return query
        select s."id"::text from "public"."customers" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          when 'write' then (coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false) or "better_supabase"."is_subject_member"('customer', s."id"::text))
          else true
        end);
    when 'drive_node' then
      return query
        select s."id"::text from "better_supabase"."drive_nodes" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then ((coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', s."id"::text))
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          when 'comment' then coalesce("better_supabase"."drive_can_comment"(s."id"), false)
          when 'fields' then coalesce("better_supabase"."drive_node_writable"(s."id"), false)
          else true
        end);
    when 'organization' then
      return query
        select s."id"::text from "public"."organizations" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and true;
    when 'application' then
      return query
        select s."id"::text from "better_supabase"."applications" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subjects.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end);
    when 'change_request' then
      return query
        select s."id"::text from "public"."change_requests" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and true;
    when 'project' then
      return query
        select s."id"::text from "public"."projects" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[]) and s."deleted_at" is null
          and true;
    when 'task' then
      return query
        select s."id"::text from "public"."tasks" s
        where s."id" = any ((can_subjects.subject_ids)::uuid[])
          and true;
    else
      return;
  end case;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_count_keys (
  tenant       uuid,
  subject_type text,
  subject_ids  text[],
  readable     text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_readable text[] := array(
    select "better_supabase"."can_subjects"(comment_count_keys.subject_type, comment_count_keys.readable, 'read')
  );
begin
  return (
    with c as materialized (
      select c."id" as id, c."subject_id" as subject_id
      from "better_supabase"."conversations" c
      where c."tenant_id" = comment_count_keys.tenant and c."kind" = 'subject'
        and c."subject_type" = comment_count_keys.subject_type
        and c."subject_id" = any (comment_count_keys.subject_ids)
        and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (case when c."kind" = 'inbox'
    then "better_supabase"."inbox_conversation_allowed"(c."id"::text)
    else ((coalesce(better_supabase.can('tenant', c."tenant_id", 'messages.read'), false)
    or (c."access" = 'subject' and c."subject_type" in ('drive_node')))
    and case c."access"
      when 'tenant' then true
      when 'members' then "better_supabase"."is_conversation_member"(c."id")
      when 'subject' then c."subject_id" = any (v_readable)
      else false
    end)
    or (c."kind" = 'subject' and ((c."tenant_id")::text, (c."subject_type")::text, (c."subject_id")::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g)) end))
    ),
    n as (
      select x."conversation_id" as id, count(*) as n
      from "better_supabase"."messages" x
      where x."conversation_id" = any (array(select c.id from c))
        and x."sent_at" is not null and x."archived_at" is null
  and (x."kind" = 'message' or "better_supabase"."inbox_note_readable"(x."conversation_id"))
      group by x."conversation_id"
    )
    select coalesce(jsonb_object_agg(c.subject_id, n.n), '{}'::jsonb)
    from c
    join n on n.id = c.id
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.comment_counts (
  tenant       uuid,
  subject_type text,
  subject_ids  text[]
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  return "better_supabase"."comment_count_keys"(
    comment_counts.tenant,
    comment_counts.subject_type,
    comment_counts.subject_ids,
    array(select "better_supabase"."can_subjects"(comment_counts.subject_type, comment_counts.subject_ids, 'read'))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_favorites (
  max_results integer DEFAULT 10,
  types       text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with s as materialized (
    select s.subject_type, s.subject_id, s.opened_at, s.starred_at, s.starred_at as at
    from "better_supabase"."search_user_state"() s
    where s.starred_at is not null
      and (search_favorites.types is null or s.subject_type = any (search_favorites.types))
  ),
  ok as (
    select t.subject_type, r.id
    from (select distinct s.subject_type from s) t
    cross join lateral "better_supabase"."can_subjects"(t.subject_type, array(select y.subject_id from s y where y.subject_type = t.subject_type), 'read') r(id)
  )
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from s
    join ok on ok.subject_type = s.subject_type and ok.id = s.subject_id
    order by s.at desc
    limit least(greatest(coalesce(search_favorites.max_results, 10), 1), 100)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_page (
  q         text    DEFAULT NULL::text,
  types     text[]  DEFAULT NULL::text[],
  tenant    uuid    DEFAULT NULL::uuid,
  filter    jsonb   DEFAULT NULL::jsonb,
  after     text    DEFAULT NULL::text,
  page_size integer DEFAULT 20
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
declare
  v_q text := btrim(coalesce(search_page.q, ''));
  v_mode text := 'b';
  v_norm text;
  v_hash text;
  v_web tsquery;
  v_prefix tsquery;
  v_size integer := least(greatest(coalesce(search_page.page_size, 20), 1), 100);
  v_filter jsonb := coalesce(search_page.filter, '{}'::jsonb);
  v_cur jsonb;
  v_items jsonb;
  v_more boolean;
  v_last jsonb;
  v_next text;
  v_batch integer := greatest((v_size + 1) * 2, 50);
  v_k text;
  v_i text;
  v_t text;
  v_rows jsonb;
  v_found jsonb;
  v_scanned integer;
  v_tail jsonb;
begin
  if length(v_q) > 256 then
    raise exception 'a search query is at most 256 characters' using errcode = '22023', hint = 'SEARCH_QUERY_TOO_LONG';
  end if;
  if jsonb_typeof(v_filter) is distinct from 'object' then
    raise exception 'filter must be a JSON object of facet values' using errcode = '22023', hint = 'SEARCH_FILTER_INVALID';
  end if;
  if v_q <> '' then
    v_mode := 's';
    v_norm := "better_supabase"."search_normalize"(v_q);
    v_hash := md5(v_norm);
    v_web := websearch_to_tsquery('simple', v_norm);
    select to_tsquery('simple', string_agg(quote_literal(w) || ':*', ' & '))
      into v_prefix
      from regexp_split_to_table(v_norm, '[^[:alnum:]]+') w
      where w <> '';
  end if;
  if search_page.after is not null then
    begin
      v_cur := convert_from(decode(rpad(translate(search_page.after, '-_', '+/'), length(search_page.after) + (4 - length(search_page.after) % 4) % 4, '='), 'base64'), 'UTF8')::jsonb;
    exception when others then
      v_cur := null;
    end;
    if v_cur is null or jsonb_typeof(v_cur) is distinct from 'object'
      or v_cur ->> 'm' is distinct from v_mode
      or (v_mode = 's' and v_cur ->> 'h' is distinct from v_hash) then
      raise exception 'this cursor does not belong to this query' using errcode = '22023', hint = 'SEARCH_CURSOR_INVALID';
    end if;
  end if;
  if v_mode = 'b' then
    -- Keyset batches of candidates, each checked in one can_subjects call per
    -- type, until the page and one more row are readable.
    v_k := v_cur ->> 'k';
    v_i := v_cur ->> 'i';
    v_t := v_cur ->> 't';
    v_rows := '[]'::jsonb;
    loop
      with cand as materialized (
        select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
          d."title" as title, d."url" as url, d."body" as body, d."facets" as facets, d."sort_key" as sort_key, null::numeric as score
        from "better_supabase"."search_documents" d
        where (search_page.types is null or d."subject_type" = any (search_page.types))
          and (search_page.tenant is null or d."tenant_id" = search_page.tenant)
          and d."facets" @> v_filter
          and (v_k is null or (d."sort_key", d."subject_id", d."subject_type") > (v_k, v_i, v_t))
        order by d."sort_key", d."subject_id", d."subject_type"
        limit v_batch
      ),
      ok as (
        select t.subject_type, r.id
      from (select distinct x.subject_type from cand x) t
      cross join lateral "better_supabase"."can_subjects"(t.subject_type, array(select y.subject_id from cand y where y.subject_type = t.subject_type), 'read') r(id)
      )
      select
        coalesce(jsonb_agg(to_jsonb(x) order by x.sort_key, x.subject_id, x.subject_type) filter (where ok.id is not null), '[]'::jsonb),
        count(*),
        (array_agg(jsonb_build_array(x.sort_key, x.subject_id, x.subject_type) order by x.sort_key desc, x.subject_id desc, x.subject_type desc))[1]
      into v_found, v_scanned, v_tail
      from cand x
      left join ok on ok.subject_type = x.subject_type and ok.id = x.subject_id;
      v_rows := v_rows || v_found;
      exit when v_scanned < v_batch or jsonb_array_length(v_rows) > v_size;
      v_k := v_tail ->> 0;
      v_i := v_tail ->> 1;
      v_t := v_tail ->> 2;
    end loop;
    with lim as (
      select r.* from jsonb_to_recordset(v_rows) as r(tenant uuid, subject_type text, subject_id text, title text, url text, body text, facets jsonb, sort_key text, score numeric)
      order by r.sort_key, r.subject_id, r.subject_type
      limit v_size + 1
    ),
    page as (
      select l.*, row_number() over (order by l.sort_key, l.subject_id, l.subject_type) as rn from lim l
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'organizationId', p.tenant,
        'subjectType', p.subject_type,
        'subjectId', p.subject_id,
        'title', p.title,
        'url', p.url,
        'snippet', null,
        'score', case when p.score is null then null else round(p.score, 6) end,
        'facets', p.facets
      ) order by p.rn) filter (where p.rn <= v_size), '[]'::jsonb),
      count(*) > v_size,
      (select jsonb_build_object('m', v_mode, 'h', v_hash, 'k', l.sort_key, 'i', l.subject_id, 't', l.subject_type, 's', l.score)
        from page l where l.rn = v_size)
    into v_items, v_more, v_last
    from page p;
  else
    with pool as materialized (
      select d."subject_type" as subject_type, d."subject_id" as subject_id,
        round((2 * coalesce(ts_rank_cd(d."tsv", v_web), 0)
          + coalesce(ts_rank_cd(d."tsv", v_prefix), 0)
          + extensions.similarity(d."title_search", v_norm))::numeric, 6) as score
      from "better_supabase"."search_documents" d
      where (search_page.types is null or d."subject_type" = any (search_page.types))
          and (search_page.tenant is null or d."tenant_id" = search_page.tenant)
          and d."facets" @> v_filter
        and (d."tsv" @@ v_web
          or (v_prefix is not null and d."tsv" @@ v_prefix)
          or d."title_search" operator(extensions.%) v_norm)
      order by score desc, d."subject_type", d."subject_id"
      limit 500
    ),
    ok as (
      select t.subject_type, r.id
      from (select distinct x.subject_type from pool x) t
      cross join lateral "better_supabase"."can_subjects"(t.subject_type, array(select y.subject_id from pool y where y.subject_type = t.subject_type), 'read') r(id)
    ),
    lim as (
      select d."tenant_id" as tenant, d."subject_type" as subject_type, d."subject_id" as subject_id,
          d."title" as title, d."url" as url, d."body" as body, d."facets" as facets, d."sort_key" as sort_key, h.score
      from pool h
      join "better_supabase"."search_documents" d on d."subject_type" = h.subject_type and d."subject_id" = h.subject_id
      where (v_cur is null
          or h.score < (v_cur ->> 's')::numeric
          or (h.score = (v_cur ->> 's')::numeric and (h.subject_type, h.subject_id) > (v_cur ->> 't', v_cur ->> 'i')))
        and exists (select 1 from ok where ok.subject_type = h.subject_type and ok.id = h.subject_id)
      order by h.score desc, h.subject_type, h.subject_id
      limit v_size + 1
    ),
    page as (
      select l.*, row_number() over (order by l.score desc, l.subject_type, l.subject_id) as rn from lim l
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'organizationId', p.tenant,
        'subjectType', p.subject_type,
        'subjectId', p.subject_id,
        'title', p.title,
        'url', p.url,
        'snippet', case when p.body is null then null
          else ts_headline('simple', p.body, coalesce(v_prefix, v_web), 'StartSel="", StopSel="", MaxWords=20, MinWords=8, MaxFragments=1')
        end,
        'score', case when p.score is null then null else round(p.score, 6) end,
        'facets', p.facets
      ) order by p.rn) filter (where p.rn <= v_size), '[]'::jsonb),
      count(*) > v_size,
      (select jsonb_build_object('m', v_mode, 'h', v_hash, 'k', l.sort_key, 'i', l.subject_id, 't', l.subject_type, 's', l.score)
        from page l where l.rn = v_size)
    into v_items, v_more, v_last
    from page p;
  end if;
  if v_more then
    v_next := translate(encode(convert_to(v_last::text, 'UTF8'), 'base64'), E'+/=\n', '-_');
  end if;
  return jsonb_build_object('items', v_items, 'nextCursor', v_next);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.search_recents (
  max_results integer DEFAULT 10,
  types       text[]  DEFAULT NULL::text[]
)
  RETURNS jsonb
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  with s as materialized (
    select s.subject_type, s.subject_id, s.opened_at, s.starred_at, s.opened_at as at
    from "better_supabase"."search_user_state"() s
    where s.opened_at is not null
      and (search_recents.types is null or s.subject_type = any (search_recents.types))
  ),
  ok as (
    select t.subject_type, r.id
    from (select distinct s.subject_type from s) t
    cross join lateral "better_supabase"."can_subjects"(t.subject_type, array(select y.subject_id from s y where y.subject_type = t.subject_type), 'read') r(id)
  )
  select coalesce(jsonb_agg(x.item order by x.at desc), '[]'::jsonb)
  from (
    select s.at, jsonb_build_object(
      'subjectType', s.subject_type,
      'subjectId', s.subject_id,
      'title', "better_supabase"."subject_title"(s.subject_type, s.subject_id),
      'url', "better_supabase"."subject_url"(s.subject_type, s.subject_id),
      'openedAt', s.opened_at,
      'starredAt', s.starred_at
    ) as item
    from s
    join ok on ok.subject_type = s.subject_type and ok.id = s.subject_id
    order by s.at desc
    limit least(greatest(coalesce(search_recents.max_results, 10), 1), 100)
  ) x
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_quota (
  tenant uuid,
  meter  text
)
  RETURNS TABLE (
    quota_limit numeric,
    period      text
  )
  LANGUAGE sql
  STABLE
  SET search_path TO ''
  AS $function$
  select q.quota_limit, q.period
  from "better_supabase"."usage_quotas_for"(array[usage_quota.tenant], array[usage_quota.meter]) q
$function$;

CREATE OR REPLACE FUNCTION better_supabase.usage_quotas_for (
  tenants uuid[],
  meters  text[]
)
  RETURNS TABLE (
    tenant      uuid,
    meter       text,
    quota_limit numeric,
    period      text
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  with t as materialized (
    select d.tenant, better_supabase.tenant_entitlements(d.tenant)::text[] as entitled, better_supabase.tenant_plans(d.tenant)::text[] as plans
    from (select distinct u.tenant from unnest(usage_quotas_for.tenants) u(tenant) where u.tenant is not null) d
  )
  select distinct on (t.tenant, q."meter") t.tenant, q."meter", q."limit", q."period"
  from t
  join "better_supabase"."usage_quotas" q on q."meter" = any (usage_quotas_for.meters)
    and (q."tenant_id" = t.tenant or (q."tenant_id" is null and (q."plan" = '*' or q."plan" = any (t.entitled) or q."plan" = any (t.plans))))
  order by t.tenant, q."meter", (q."tenant_id" is not null) desc, q."limit" desc nulls first
$function$;

REVOKE ALL ON FUNCTION "api"."can_subjects"(text, text[], text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."can_subjects"(text, text[], text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "api"."usage_quotas_for"(uuid[], text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."usage_quotas_for"(uuid[], text[]) TO "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."can_subjects"(text, text[], text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."can_subjects"(text, text[], text) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."comment_count_keys"(uuid, text, text[], text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."comment_count_keys"(uuid, text, text[], text[]) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."usage_quotas_for"(uuid[], text[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."usage_quotas_for"(uuid[], text[]) TO "service_role";
