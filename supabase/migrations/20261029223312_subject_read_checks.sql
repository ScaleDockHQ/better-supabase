SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION api.drive_node_readable (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."drive_node_readable"($1) $function$;

CREATE OR REPLACE FUNCTION better_supabase.attachment_subject_readable (
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
  return attachment_subject_readable.subject_type is null or (((attachment_subject_readable.tenant)::text, (attachment_subject_readable.subject_type)::text, (attachment_subject_readable.subject_id)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or case attachment_subject_readable.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."organization_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant and (coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."tenant_id" = attachment_subject_readable.tenant) and coalesce(better_supabase.can('tenant', attachment_subject_readable.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."organization_id" = attachment_subject_readable.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."organization_id" = attachment_subject_readable.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (attachment_subject_readable.subject_id)::uuid and s."organization_id" = attachment_subject_readable.tenant)
    else false
  end);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject (
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SET search_path TO ''
  AS $function$
begin
  case can_subject.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.send'), false)
          else true
        end)
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'channels.manage'), false)
          else true
        end)
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'parties.write'), false)
          else true
        end)
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'deals.write'), false)
          else true
        end)
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'courses.manage'), false)
          else true
        end)
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'posts.write'), false)
          else true
        end)
      );
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'engagements.write'), false)
          else true
        end)
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'quotes.write'), false)
          else true
        end)
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'work_items.write'), false)
          else true
        end)
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'employees.write'), false)
          else true
        end)
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'invoices.write'), false)
          else true
        end)
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'ledger.manage'), false)
          else true
        end)
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'catalog.manage'), false)
          else true
        end)
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'orders.manage'), false)
          else true
        end)
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'calendar.write'), false)
          else true
        end)
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'bookings.manage'), false)
          else true
        end)
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'assets.manage'), false)
          else true
        end)
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."lease_agreements" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'leases.manage'), false)
          else true
        end)
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          else true
        end)
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can('tenant', s."tenant_id", 'expenses.submit'), false)
          else true
        end)
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'donations.manage'), false)
          else true
        end)
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'dispatch.manage'), false)
          else true
        end)
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'shipments.manage'), false)
          else true
        end)
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'contracts.write'), false)
          else true
        end)
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.manage'), false)
          else true
        end)
      );
    when 'policy' then
      return exists (
        select 1 from "better_supabase"."policies" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'controls.manage'), false)
          else true
        end)
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'incidents.write'), false)
          else true
        end)
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'content.write'), false)
          else true
        end)
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'forms.manage'), false)
          else true
        end)
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'documents.write'), false)
          else true
        end)
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject.subject_id)::uuid and s."archived_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."organization_id", 'customers.write'), false)
          else true
        end)
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then (coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false))
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'drive.manage'), false)
          when 'fields' then coalesce("better_supabase"."drive_node_writable"(s."id"), false)
          else true
        end)
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject.subject_id)::uuid
          and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case can_subject.action
          when 'read' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can('tenant', s."tenant_id", 'hiring.write'), false)
          else true
        end)
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject.subject_id)::uuid and s."deleted_at" is null
          and true
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject.subject_id)::uuid
          and true
      );
    else
      return false;
  end case;
  return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.can_subject_for (
  member       uuid,
  subject_type text,
  subject_id   text,
  action       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  case can_subject_for.subject_type
    when 'message' then
      return exists (
        select 1 from "better_supabase"."messages" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'conversation' then
      return exists (
        select 1 from "better_supabase"."conversations" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.send'), false)
          else false
        end
      );
    when 'channel' then
      return exists (
        select 1 from "better_supabase"."channels" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'messages.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'channels.manage'), false)
          else false
        end
      );
    when 'company' then
      return exists (
        select 1 from "better_supabase"."companies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'person' then
      return exists (
        select 1 from "better_supabase"."people" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'parties.write'), false)
          else false
        end
      );
    when 'deal' then
      return exists (
        select 1 from "better_supabase"."deals" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'deals.write'), false)
          else false
        end
      );
    when 'course' then
      return exists (
        select 1 from "better_supabase"."courses" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'courses.manage'), false)
          else false
        end
      );
    when 'post' then
      return exists (
        select 1 from "better_supabase"."posts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'posts.write'), false)
          else false
        end
      );
    when 'engagement' then
      return exists (
        select 1 from "better_supabase"."engagements" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'engagements.write'), false)
          else false
        end
      );
    when 'quote' then
      return exists (
        select 1 from "better_supabase"."quotes" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'quotes.write'), false)
          else false
        end
      );
    when 'work_item' then
      return exists (
        select 1 from "better_supabase"."work_items" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'work_items.write'), false)
          else false
        end
      );
    when 'employee' then
      return exists (
        select 1 from "better_supabase"."employees" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'employees.write'), false)
          else false
        end
      );
    when 'invoice' then
      return exists (
        select 1 from "better_supabase"."invoices" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'invoices.write'), false)
          else false
        end
      );
    when 'ledger_account' then
      return exists (
        select 1 from "better_supabase"."ledger_accounts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'ledger.manage'), false)
          else false
        end
      );
    when 'product' then
      return exists (
        select 1 from "better_supabase"."products" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'product_variant' then
      return exists (
        select 1 from "better_supabase"."product_variants" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'catalog.manage'), false)
          else false
        end
      );
    when 'order' then
      return exists (
        select 1 from "better_supabase"."orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'orders.manage'), false)
          else false
        end
      );
    when 'calendar_event' then
      return exists (
        select 1 from "better_supabase"."calendar_events" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'calendar.write'), false)
          else false
        end
      );
    when 'booking' then
      return exists (
        select 1 from "better_supabase"."bookings" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'bookings.manage'), false)
          else false
        end
      );
    when 'asset' then
      return exists (
        select 1 from "better_supabase"."assets" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'asset_location' then
      return exists (
        select 1 from "better_supabase"."asset_locations" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'assets.manage'), false)
          else false
        end
      );
    when 'lease' then
      return exists (
        select 1 from "better_supabase"."lease_agreements" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'leases.manage'), false)
          else false
        end
      );
    when 'expense_report' then
      return exists (
        select 1 from "better_supabase"."expense_reports" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          else false
        end
      );
    when 'expense_line' then
      return exists (
        select 1 from "better_supabase"."expense_lines" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.manage'), false)
          when 'upload' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'expenses.submit'), false)
          else false
        end
      );
    when 'donation_fund' then
      return exists (
        select 1 from "better_supabase"."donation_funds" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'donations.manage'), false)
          else false
        end
      );
    when 'work_order' then
      return exists (
        select 1 from "better_supabase"."work_orders" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'dispatch.manage'), false)
          else false
        end
      );
    when 'shipment' then
      return exists (
        select 1 from "better_supabase"."shipments" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'shipments.manage'), false)
          else false
        end
      );
    when 'contract' then
      return exists (
        select 1 from "better_supabase"."contracts" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'contracts.write'), false)
          else false
        end
      );
    when 'control' then
      return exists (
        select 1 from "better_supabase"."controls" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.manage'), false)
          else false
        end
      );
    when 'policy' then
      return exists (
        select 1 from "better_supabase"."policies" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'controls.manage'), false)
          else false
        end
      );
    when 'incident' then
      return exists (
        select 1 from "better_supabase"."incidents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'incidents.write'), false)
          else false
        end
      );
    when 'content_entry' then
      return exists (
        select 1 from "better_supabase"."content_entries" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'content.write'), false)
          else false
        end
      );
    when 'form' then
      return exists (
        select 1 from "better_supabase"."forms" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'forms.manage'), false)
          else false
        end
      );
    when 'document' then
      return exists (
        select 1 from "better_supabase"."documents" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'documents.write'), false)
          else false
        end
      );
    when 'customer' then
      return exists (
        select 1 from "public"."customers" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."archived_at" is null
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."organization_id", 'customers.write'), false)
          else false
        end
      );
    when 'drive_node' then
      return exists (
        select 1 from "better_supabase"."drive_nodes" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and case can_subject_for.action
          when 'read' then false
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'drive.manage'), false)
          when 'fields' then false
          else false
        end
      );
    when 'application' then
      return exists (
        select 1 from "better_supabase"."applications" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and case can_subject_for.action
          when 'read' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.read'), false)
          when 'write' then coalesce(better_supabase.can_user(can_subject_for.member, 'tenant', s."tenant_id", 'hiring.write'), false)
          else false
        end
      );
    when 'change_request' then
      return exists (
        select 1 from "public"."change_requests" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    when 'project' then
      return exists (
        select 1 from "public"."projects" s
        where s."id" = (can_subject_for.subject_id)::uuid and s."deleted_at" is null
          and false
      );
    when 'task' then
      return exists (
        select 1 from "public"."tasks" s
        where s."id" = (can_subject_for.subject_id)::uuid
          and false
      );
    else
      return false;
  end case;
  return false;
exception
  when feature_not_supported then
    return false;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.create_signature_request (
  tenant              uuid,
  subject_type        text,
  subject_id          text,
  signers             uuid[],
  version_id          uuid   DEFAULT NULL::uuid,
  sign_order          text   DEFAULT 'parallel'::text,
  approval_request_id uuid   DEFAULT NULL::uuid,
  message             text   DEFAULT NULL::text,
  meaning             text   DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_version uuid := create_signature_request.version_id;
  v_hash text;
  v_row "better_supabase"."signature_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'signatures.request'), false) and case create_signature_request.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant and (coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (create_signature_request.subject_id)::uuid and s."tenant_id" = create_signature_request.tenant) and coalesce(better_supabase.can('tenant', create_signature_request.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (create_signature_request.subject_id)::uuid and s."organization_id" = create_signature_request.tenant)
    else false
  end)) then
    raise exception 'not allowed to request signatures on this record' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  if create_signature_request.meaning is not null and create_signature_request.meaning not in ('authored', 'reviewed', 'approved', 'released', 'acknowledged') then
    raise exception 'meaning must be one of authored, reviewed, approved, released, acknowledged' using errcode = '22023', hint = 'SIGNATURE_REQUEST_MEANING_UNKNOWN';
  end if;
  if create_signature_request.sign_order not in ('parallel', 'sequential') then
    raise exception 'sign_order must be parallel or sequential' using errcode = '22023', hint = 'SIGNATURE_ORDER_INVALID';
  end if;
  if coalesce(cardinality(create_signature_request.signers), 0) not between 1 and 20
    or array_position(create_signature_request.signers, null) is not null
    or (select count(distinct x) from unnest(create_signature_request.signers) x) <> cardinality(create_signature_request.signers) then
    raise exception 'name between 1 and 20 different signers' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if exists (
    select 1 from unnest(create_signature_request.signers) x
    where not exists (
      select 1 from "public"."memberships" m
      where m."organization_id" = create_signature_request.tenant and m."user_id" = x
    )
  ) then
    raise exception 'every signer must be a member of the organization' using errcode = '22023', hint = 'SIGNATURE_SIGNERS_INVALID';
  end if;
  if create_signature_request.approval_request_id is not null and not exists (
    select 1 from "better_supabase"."approval_requests" a
    where a."id" = create_signature_request.approval_request_id
      and a."tenant_id" = create_signature_request.tenant
      and a."subject_type" = create_signature_request.subject_type
      and a."subject_id" = create_signature_request.subject_id
  ) then
    raise exception 'the approval request isn''t for this record' using errcode = '22023', hint = 'SIGNATURE_APPROVAL_NOT_FOUND';
  end if;
  if v_version is null then
    v_version := ("better_supabase"."snapshot_version"(create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id) ->> 'id')::uuid;
  end if;
  select x."content_hash" into v_hash
    from "better_supabase"."versions" x
    where x."id" = v_version
      and x."tenant_id" = create_signature_request.tenant
      and x."subject_type" = create_signature_request.subject_type
      and x."subject_id" = create_signature_request.subject_id;
  if v_hash is null then
    raise exception 'the version isn''t a version of this record' using errcode = '22023', hint = 'SIGNATURE_VERSION_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_signature_request"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version;
    end if;
  end;
  update "better_supabase"."versions" x set "frozen" = true where x."id" = v_version and not x."frozen";
  insert into "better_supabase"."signature_requests" ("tenant_id", "subject_type", "subject_id", "version_id", "content_hash", "signers", "sign_order", "approval_request_id", "message", "meaning", "requested_by")
  values (create_signature_request.tenant, create_signature_request.subject_type, create_signature_request.subject_id, v_version, v_hash, create_signature_request.signers, create_signature_request.sign_order, create_signature_request.approval_request_id, nullif(trim(create_signature_request.message), ''), create_signature_request.meaning, auth.uid())
  returning * into v_row;
  perform "better_supabase".emit_event('signature.requested', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id"), 'signature-requests/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/signatures');
  perform better_supabase.audit_event(
    event_type => 'signature.requested',
    category => 'data',
    target_type => 'signature_request',
    record_id => v_row."id"::text,
    summary => 'requested signatures on ' || v_row."subject_type" || ' ' || v_row."subject_id",
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'versionId', v_row."version_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_signature_request"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'versionId', v_row."version_id", 'contentHash', v_row."content_hash", 'signers', to_jsonb(v_row."signers"), 'order', v_row."sign_order", 'status', v_row."status", 'approvalRequestId', v_row."approval_request_id", 'message', v_row."message", 'meaning', v_row."meaning", 'requestedBy', v_row."requested_by", 'createdAt', v_row."created_at", 'completedAt', v_row."completed_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.decide_document_suggestion (
  suggestion_id uuid,
  decision      text,
  note          text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_suggestion from "better_supabase"."document_suggestions" x where x."id" = decide_document_suggestion.suggestion_id for update;
  if found then
    select * into v_doc from "better_supabase"."documents" d where d."id" = v_suggestion."document_id";
  end if;
  if v_suggestion."id" is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end) or coalesce(v_suggestion."created_by" = auth.uid(), false)) then
    raise exception 'suggestion not found' using errcode = 'P0002', hint = 'DOCUMENT_SUGGESTION_NOT_FOUND';
  end if;
  if decide_document_suggestion.decision is null or decide_document_suggestion.decision not in ('accepted', 'rejected', 'withdrawn') then
    raise exception 'decide with accepted, rejected or withdrawn' using errcode = '22023', hint = 'DOCUMENT_SUGGESTION_INVALID';
  end if;
  if decide_document_suggestion.decision = 'withdrawn' then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_suggestion."created_by" = auth.uid(), false)) then
      raise exception 'only the author can withdraw a suggestion' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'channels.manage'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.manage'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'quote' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'invoice' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'booking' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.manage'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'content_entry' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.write'), false)
    when 'form' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.manage'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to decide suggestions on this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  if v_suggestion."status" <> 'open' then
    raise exception 'the suggestion was already decided' using errcode = '55000', hint = 'DOCUMENT_SUGGESTION_CLOSED';
  end if;
  if decide_document_suggestion.decision = 'accepted' then
    insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_suggestion."payload", v_suggestion."created_by")
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    perform "better_supabase"."enqueue_job"(queue => 'documents.compact', payload => jsonb_build_object('documentId', v_doc."id"), dedupe_key => 'documents.compact:' || v_doc."id"::text, dedupe_running => false);
  end if;
  end if;
  update "better_supabase"."document_suggestions" x
    set "status" = decide_document_suggestion.decision, "decided_by" = auth.uid(), "decided_at" = now(), "note" = nullif(trim(decide_document_suggestion.note), '')
    where x."id" = v_suggestion."id"
    returning * into v_suggestion;
  if v_suggestion."status" = 'accepted' then
    perform "better_supabase".emit_event('document.suggestion_accepted', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  perform better_supabase.audit_event(
    event_type => 'document.suggestion_accepted',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status")
  );
  elsif v_suggestion."status" = 'rejected' then
    perform "better_supabase".emit_event('document.suggestion_rejected', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  perform better_supabase.audit_event(
    event_type => 'document.suggestion_rejected',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status")
  );
  end if;
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', '')) || jsonb_build_object('seq', v_seq);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.document_access (
  document_id uuid,
  write       boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = document_access.document_id;
  if not found then
    return false;
  end if;
  if coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then
    return true;
  end if;
  if document_access.write then
    return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'channels.manage'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.manage'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'quote' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'invoice' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'booking' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.manage'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'content_entry' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.write'), false)
    when 'form' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.manage'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end);
  end if;
  return (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.drive_node_readable (
  node uuid
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
  select "better_supabase"."drive_can"(drive_node_readable.node, 'viewer')
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
    or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'approvals.read'), false) and (not v_req."subject_type" in ('ai_tool_approval') and (v_req."subject_type" in ('access_request', 'timesheet', 'expense_report', 'content_entry') or (case when v_req."subject_type" = 'drive_node' then coalesce(case when v_req."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((v_req."subject_id")::uuid, 'viewer') end, false) else case v_req."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'work_items.read'), false)
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
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'forms.read'), false)
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

CREATE OR REPLACE FUNCTION better_supabase.get_document_version (
  document_id uuid,
  version_id  uuid
)
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_state text;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = get_document_version.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select x."content" ->> 'state' into v_state from "better_supabase"."versions" x
  where x."id" = get_document_version.version_id
    and x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text;
  if v_state is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'DOCUMENT_VERSION_NOT_FOUND';
  end if;
  return v_state;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.get_signature_request (
  request_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_req "better_supabase"."signature_requests"%rowtype;
  v_items jsonb;
begin
  select * into v_req from "better_supabase"."signature_requests" x where x."id" = get_signature_request.request_id;
  if not found then
    raise exception 'signature request not found' using errcode = 'P0002', hint = 'SIGNATURE_REQUEST_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(auth.uid() = any (v_req."signers"), false) or (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'signatures.read'), false) and case v_req."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'work_items.read'), false)
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
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id" and (coalesce(better_supabase.can('tenant', v_req."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_req."subject_id")::uuid and s."tenant_id" = v_req."tenant_id") and coalesce(better_supabase.can('tenant', v_req."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_req."subject_id")::uuid and s."organization_id" = v_req."tenant_id")
    else false
  end)) then
    raise exception 'not allowed to read this request' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', g."id", 'requestId', g."request_id", 'signer', g."signer", 'method', g."method", 'typedName', g."typed_name", 'imageAttachmentId', g."image_attachment_id", 'signedHash', g."signed_hash", 'ip', g."ip", 'userAgent', g."user_agent", 'signedAt', g."signed_at") order by g."signed_at"), '[]'::jsonb) into v_items
    from "better_supabase"."signatures" g where g."request_id" = v_req."id";
  return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'versionId', v_req."version_id", 'contentHash', v_req."content_hash", 'signers', to_jsonb(v_req."signers"), 'order', v_req."sign_order", 'status', v_req."status", 'approvalRequestId', v_req."approval_request_id", 'message', v_req."message", 'meaning', v_req."meaning", 'requestedBy', v_req."requested_by", 'createdAt', v_req."created_at", 'completedAt', v_req."completed_at") || jsonb_build_object('signatures', v_items, 'verification', "better_supabase"."signature_verification"(v_req."id"));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.link (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text,
  data        jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_id uuid;
  v_created boolean := false;
  v_previous jsonb;
  v_replaced jsonb;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', link.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to link records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;
  if link.data is not null and jsonb_typeof(link.data) <> 'object' then
    raise exception 'data must be an object' using errcode = '22023', hint = 'RELATION_INVALID';
  end if;
  if link.source_type = link.target_type and link.source_id = link.target_id then
    raise exception 'a record can''t link to itself' using errcode = '22023', hint = 'RELATION_SELF';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from'), ('represents', 'represents', false, false, false, false, 'represented_by'), ('represented_by', 'represents', true, false, false, false, 'represents')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = link.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := link.target_type; v_source_id := link.target_id;
    v_target_type := link.source_type; v_target_id := link.source_id;
  else
    v_source_type := link.source_type; v_source_id := link.source_id;
    v_target_type := link.target_type; v_target_id := link.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if v_kind = 'represents' and not (v_source_type in ('person')) then
    raise exception 'this kind of link doesn''t accept these record types' using errcode = '22023', hint = 'RELATION_TYPE_NOT_ALLOWED';
  end if;
  if not (case link.source_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant and (coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.source_id)::uuid and s."organization_id" = link.tenant)
    else false
  end)
     or not (case link.target_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant and (coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (link.target_id)::uuid and s."organization_id" = link.tenant)
    else false
  end) then
    raise exception 'not allowed to link these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_relation_link"(uuid, text, text, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text, $5::text, $6::text)', v_hook::oid::regproc)
        using link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id;
    end if;
  end;
  if v_acyclic or v_single then
    perform pg_advisory_xact_lock(hashtext(link.tenant::text || ':relation:' || v_kind));
  end if;
  select "id", "data" into v_id, v_previous from "better_supabase"."relations"
    where "tenant_id" = link.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id;
  if v_id is null then
    if v_kind = 'represents' and not coalesce((jsonb_typeof(coalesce(link.data, '{}'::jsonb)) = 'object'
      and (coalesce(link.data, '{}'::jsonb) ->> 'role') in ('legal_representative', 'guardian', 'mentor', 'curator', 'parent', 'contact_person', 'emergency_contact', 'other')
      and (coalesce(link.data, '{}'::jsonb) ->> 'authority') in ('inform', 'act')
      and (coalesce(link.data, '{}'::jsonb) -> 'valid_from' is null or (jsonb_typeof(coalesce(link.data, '{}'::jsonb) -> 'valid_from') = 'string' and pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_from', 'date')))
      and (coalesce(link.data, '{}'::jsonb) -> 'valid_until' is null or (jsonb_typeof(coalesce(link.data, '{}'::jsonb) -> 'valid_until') = 'string' and pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_until', 'date')))
      and case when pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_from', 'date') and pg_input_is_valid(coalesce(link.data, '{}'::jsonb) ->> 'valid_until', 'date')
        then (coalesce(link.data, '{}'::jsonb) ->> 'valid_from')::date <= (coalesce(link.data, '{}'::jsonb) ->> 'valid_until')::date else true end), false) then
      raise exception 'this kind of link doesn''t accept this data' using errcode = '22023', hint = 'RELATION_DATA_INVALID';
    end if;
    if v_acyclic and exists (
      with recursive reach(t, i, depth) as (
        select v_target_type, v_target_id, 0
        union
        select r."target_type", r."target_id", reach.depth + 1
        from "better_supabase"."relations" r join reach
          on r."source_type" = reach.t and r."source_id" = reach.i
        where r."tenant_id" = link.tenant and r."kind" = v_kind and reach.depth < 1000
      )
      select 1 from reach where t = v_source_type and i = v_source_id
    ) then
      raise exception 'this link would create a cycle' using errcode = '23514', hint = 'RELATION_CYCLE';
    end if;
    if v_single then
      delete from "better_supabase"."relations"
        where "tenant_id" = link.tenant and "kind" = v_kind
          and "source_type" = v_source_type and "source_id" = v_source_id
        returning * into v_old;
      if v_old."id" is not null then
        v_replaced := jsonb_build_object('targetType', v_old."target_type", 'targetId', v_old."target_id", 'data', v_old."data");
        perform "better_supabase".emit_event('subject.unlinked', jsonb_build_object('organizationId', link.tenant, 'id', v_old."id", 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_old."target_type", 'targetId', v_old."target_id"), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
      end if;
    end if;
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "data", "created_by")
    values (link.tenant, v_kind, v_source_type, v_source_id, v_target_type, v_target_id, coalesce(link.data, '{}'::jsonb), auth.uid())
    returning "id" into v_id;
    v_created := true;
    perform "better_supabase".emit_event('subject.linked', jsonb_build_object('organizationId', link.tenant, 'id', v_id, 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id), 'subjects/' || v_source_type || '/' || v_source_id, (link.tenant)::text, null, 'better-supabase/relations');
  elsif link.data is not null then
    if v_kind = 'represents' and not coalesce((jsonb_typeof(link.data) = 'object'
      and (link.data ->> 'role') in ('legal_representative', 'guardian', 'mentor', 'curator', 'parent', 'contact_person', 'emergency_contact', 'other')
      and (link.data ->> 'authority') in ('inform', 'act')
      and (link.data -> 'valid_from' is null or (jsonb_typeof(link.data -> 'valid_from') = 'string' and pg_input_is_valid(link.data ->> 'valid_from', 'date')))
      and (link.data -> 'valid_until' is null or (jsonb_typeof(link.data -> 'valid_until') = 'string' and pg_input_is_valid(link.data ->> 'valid_until', 'date')))
      and case when pg_input_is_valid(link.data ->> 'valid_from', 'date') and pg_input_is_valid(link.data ->> 'valid_until', 'date')
        then (link.data ->> 'valid_from')::date <= (link.data ->> 'valid_until')::date else true end), false) then
      raise exception 'this kind of link doesn''t accept this data' using errcode = '22023', hint = 'RELATION_DATA_INVALID';
    end if;
    update "better_supabase"."relations" set "data" = link.data where "id" = v_id;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_relation_link"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object(
    'id', v_id, 'kind', v_kind, 'created', v_created,
    'sourceType', v_source_type, 'sourceId', v_source_id,
    'targetType', v_target_type, 'targetId', v_target_id,
    'previousData', case when v_created then null else v_previous end,
    'replaced', v_replaced);
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
        else x."requested_by" = auth.uid() or (v_read and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (not x."subject_type" in ('ai_tool_approval') and (x."subject_type" in ('access_request', 'timesheet', 'expense_report', 'content_entry') or (case when x."subject_type" = 'drive_node' then coalesce(case when x."subject_id" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((x."subject_id")::uuid, 'viewer') end, false) else case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
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
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
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

CREATE OR REPLACE FUNCTION better_supabase.list_document_suggestions (
  document_id uuid,
  status      text DEFAULT 'open'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_suggestions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'documentId', x."document_id", 'summary', x."summary", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'decidedBy', x."decided_by", 'decidedAt', x."decided_at", 'note', x."note", 'update', replace(encode(x."payload", 'base64'), E'\n', '')) order by x."created_at", x."id"), '[]'::jsonb)
    from "better_supabase"."document_suggestions" x
    where x."document_id" = v_doc."id"
      and (coalesce(list_document_suggestions.status, 'all') = 'all' or x."status"::text = list_document_suggestions.status)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_document_versions (
  document_id uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = list_document_versions.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'number', x."number", 'label', x."label", 'source', x."source", 'frozen', x."frozen", 'createdBy', x."created_by", 'createdAt', x."created_at") order by x."number" desc), '[]'::jsonb)
    from "better_supabase"."versions" x
    where x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_signature_requests (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
  subject_id   text                     DEFAULT NULL::text,
  status       text                     DEFAULT NULL::text,
  mine         boolean                  DEFAULT false,
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
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or list_signature_requests.mine or coalesce(better_supabase.can('tenant', list_signature_requests.tenant, 'signatures.read'), false)) then
    raise exception 'not allowed to list signature requests' using errcode = '42501', hint = 'SIGNATURE_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', q."id", 'organizationId', q."tenant_id", 'subjectType', q."subject_type", 'subjectId', q."subject_id", 'versionId', q."version_id", 'contentHash', q."content_hash", 'signers', to_jsonb(q."signers"), 'order', q."sign_order", 'status', q."status", 'approvalRequestId', q."approval_request_id", 'message', q."message", 'meaning', q."meaning", 'requestedBy', q."requested_by", 'createdAt', q."created_at", 'completedAt', q."completed_at") order by q."created_at" desc), '[]'::jsonb) into v_rows
  from (
    select * from "better_supabase"."signature_requests" x
    where x."tenant_id" = list_signature_requests.tenant
      and (list_signature_requests.subject_type is null or x."subject_type" = list_signature_requests.subject_type)
      and (list_signature_requests.subject_id is null or x."subject_id" = list_signature_requests.subject_id)
      and (list_signature_requests.status is null or x."status" = list_signature_requests.status)
      and (list_signature_requests.before is null or x."created_at" < list_signature_requests.before)
      and (not list_signature_requests.mine or auth.uid() = any (x."signers"))
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or auth.uid() = any (x."signers") or (coalesce(better_supabase.can('tenant', x."tenant_id", 'signatures.read'), false) and case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
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
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end))
    order by x."created_at" desc
    limit least(greatest(coalesce(list_signature_requests.page_size, 50), 1), 200)
  ) q;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.list_trash (
  tenant       uuid,
  subject_type text                     DEFAULT NULL::text,
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
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', list_trash.tenant, 'trash.read'), false)) then
    raise exception 'not allowed to read this organization''s trash' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', t."id", 'subjectType', t."subject_type", 'subjectId', t."subject_id", 'title', t."title", 'batchId', t."batch_id", 'count', t.n, 'trashedBy', t."trashed_by", 'trashedAt', t."trashed_at", 'purgeAfter', t."purge_after") order by t."trashed_at" desc, t."id"), '[]'::jsonb)
    into v_rows
  from (
    select x.*, (select count(*) from "better_supabase"."trash_items" b where b."batch_id" = x."batch_id")::integer as n
    from "better_supabase"."trash_items" x
    where x."tenant_id" = list_trash.tenant
      and x."depth" = 0
      and (list_trash.subject_type is null or x."subject_type" = list_trash.subject_type)
      and (list_trash.before is null or x."trashed_at" < list_trash.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case x."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'work_items.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id") and coalesce(better_supabase.can('tenant', x."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (x."subject_id")::uuid and s."tenant_id" = x."tenant_id" and (coalesce(better_supabase.can('tenant', x."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (x."subject_id")::uuid and s."organization_id" = x."tenant_id")
    else false
  end)
    order by x."trashed_at" desc, x."id"
    limit least(greatest(coalesce(list_trash.page_size, 50), 1), 200)
  ) t;
  return v_rows;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.log_time (
  tenant        uuid,
  started_at    timestamp with time zone,
  ended_at      timestamp with time zone,
  subject_type  text                     DEFAULT NULL::text,
  subject_id    text                     DEFAULT NULL::text,
  billable      boolean                  DEFAULT false,
  rate          bigint                   DEFAULT NULL::bigint,
  rate_currency text                     DEFAULT NULL::text,
  note          text                     DEFAULT NULL::text,
  user_id       uuid                     DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_user uuid := coalesce(log_time.user_id, auth.uid());
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_user is null then
    raise exception 'sign in to track time' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_user = v_me then
    if not coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.track'), false) then
      raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', log_time.tenant, 'time_tracking.manage'), false)) then
    raise exception 'not allowed to log time for another member' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  elsif not exists (select 1 from "public"."memberships" m where m."organization_id" = log_time.tenant and m."user_id" = v_user) then
    raise exception 'that user isn''t a member of this organization' using errcode = '22023', hint = 'TIME_USER_INVALID';
  end if;
  if log_time.started_at is null or log_time.ended_at is null or log_time.ended_at <= log_time.started_at then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if (log_time.subject_type is null) <> (log_time.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if log_time.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case log_time.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant and (coalesce(better_supabase.can('tenant', log_time.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (log_time.subject_id)::uuid and s."tenant_id" = log_time.tenant) and coalesce(better_supabase.can('tenant', log_time.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (log_time.subject_id)::uuid and s."organization_id" = log_time.tenant)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if log_time.rate is not null and log_time.rate_currency is null then
    raise exception 'a rate needs rate_currency' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if log_time.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || log_time.tenant::text || ':' || v_user::text, 0));
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := log_time.tenant;
  v_row."user_id" := v_user;
  v_row."subject_type" := log_time.subject_type;
  v_row."subject_id" := log_time.subject_id;
  v_row."started_at" := log_time.started_at;
  v_row."ended_at" := log_time.ended_at;
  v_row."billable" := coalesce(log_time.billable, false);
  v_row."rate" := log_time.rate;
  v_row."rate_currency" := log_time.rate_currency;
  v_row."note" := log_time.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "ended_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."ended_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.name_document_version (
  document_id uuid,
  version_id  uuid,
  label       text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_frozen boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = name_document_version.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'channels.manage'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.manage'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'quote' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'invoice' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'booking' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.manage'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'content_entry' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.write'), false)
    when 'form' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.manage'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to name versions of this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  select x."frozen" into v_frozen from "better_supabase"."versions" x
  where x."id" = name_document_version.version_id
    and x."subject_type" = 'document' and x."subject_id" = v_doc."id"::text
  for update;
  if v_frozen is null then
    raise exception 'version not found' using errcode = 'P0002', hint = 'DOCUMENT_VERSION_NOT_FOUND';
  end if;
  if v_frozen then
    raise exception 'a frozen version keeps its name' using errcode = '55000', hint = 'DOCUMENT_VERSION_FROZEN';
  end if;
  update "better_supabase"."versions" x set "label" = nullif(trim(name_document_version.label), '')
  where x."id" = name_document_version.version_id;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.open_document (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  name         text DEFAULT 'body'::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
  v_write boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d
  where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
  if found and v_doc."tenant_id" <> open_document.tenant then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not found then
    v_doc."tenant_id" := open_document.tenant;
    v_doc."subject_type" := open_document.subject_type;
    v_doc."subject_id" := open_document.subject_id;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'channels.manage'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.manage'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'quote' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'invoice' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'booking' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.manage'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'content_entry' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.write'), false)
    when 'form' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.manage'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
      if (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end) then
        raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
      end if;
      raise exception 'not allowed to open this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_document_create"(uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::text)', v_hook::oid::regproc)
        using open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name;
    end if;
  end;
    insert into "better_supabase"."documents" ("tenant_id", "subject_type", "subject_id", "name", "created_by")
    values (open_document.tenant, open_document.subject_type, open_document.subject_id, open_document.name, auth.uid())
    on conflict ("subject_type", "subject_id", "name") do nothing
    returning * into v_doc;
    if found then
      perform "better_supabase".emit_event('document.created', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  perform better_supabase.audit_event(
    event_type => 'document.created',
    category => 'data',
    target_type => 'document',
    record_id => v_doc."id"::text,
    tenant => (v_doc."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name")
  );
      declare
    v_hook regprocedure := to_regprocedure('"public"."after_document_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_doc."id";
    end if;
  end;
    else
      select * into v_doc from "better_supabase"."documents" d
      where d."subject_type" = open_document.subject_type and d."subject_id" = open_document.subject_id and d."name" = open_document.name;
    end if;
  elsif not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  v_write := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'channels.manage'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.manage'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'quote' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'invoice' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'booking' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.manage'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'content_entry' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.write'), false)
    when 'form' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.manage'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end);
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  return jsonb_build_object('id', v_doc."id", 'organizationId', v_doc."tenant_id", 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'name', v_doc."name", 'topic', 'documents:' || v_doc."id"::text, 'createdAt', v_doc."created_at", 'updatedAt', v_doc."updated_at") || jsonb_build_object(
    'canWrite', v_write,
    'canSuggest', v_write or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)),
    'snapshot', case when v_snapshot."document_id" is null then null else replace(encode(v_snapshot."state", 'base64'), E'\n', '') end,
    'snapshotSeq', coalesce(v_snapshot."seq", 0),
    'updates', "better_supabase"."document_updates_after"(v_doc."id", coalesce(v_snapshot."seq", 0))
  );
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.pull_document_updates (
  document_id uuid,
  after_seq   bigint
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_snapshot "better_supabase"."document_snapshots"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = pull_document_updates.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  select * into v_snapshot from "better_supabase"."document_snapshots" x where x."document_id" = v_doc."id";
  if v_snapshot."document_id" is not null and pull_document_updates.after_seq < v_snapshot."seq" then
    return jsonb_build_object(
      'snapshot', replace(encode(v_snapshot."state", 'base64'), E'\n', ''),
      'snapshotSeq', v_snapshot."seq",
      'updates', "better_supabase"."document_updates_after"(v_doc."id", v_snapshot."seq")
    );
  end if;
  return jsonb_build_object('updates', "better_supabase"."document_updates_after"(v_doc."id", pull_document_updates.after_seq));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.push_document_update (
  document_id uuid,
  payload     text
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_bytes bytea;
  v_seq bigint;
  v_since bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = push_document_update.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'channels.manage'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.manage'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'quote' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'invoice' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'booking' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.manage'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'content_entry' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.write'), false)
    when 'form' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.manage'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(push_document_update.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_updates" ("document_id", "tenant_id", "payload", "actor")
  values (v_doc."id", v_doc."tenant_id", v_bytes, auth.uid())
  returning "seq" into v_seq;
  update "better_supabase"."documents" d set "updated_at" = now() where d."id" = v_doc."id";
  select count(*) into v_since from "better_supabase"."document_updates" x
  where x."document_id" = v_doc."id"
    and x."seq" > coalesce((select y."seq" from "better_supabase"."document_snapshots" y where y."document_id" = v_doc."id"), 0);
  if v_since = 200 then
    perform "better_supabase"."enqueue_job"(queue => 'documents.compact', payload => jsonb_build_object('documentId', v_doc."id"), dedupe_key => 'documents.compact:' || v_doc."id"::text, dedupe_running => false);
  end if;
  return v_seq;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.reaction_subject_visible (
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
  return case reaction_subject_visible.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."deleted_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."archived_at" is null) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant and s."deleted_at" is null and (coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."tenant_id" = reaction_subject_visible.tenant) and coalesce(better_supabase.can('tenant', reaction_subject_visible.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant and s."deleted_at" is null)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (reaction_subject_visible.subject_id)::uuid and s."organization_id" = reaction_subject_visible.tenant)
    else false
  end;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.read_field_values (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_values jsonb;
  v_key text;
  v_read jsonb;
begin
  v_key := "better_supabase"."field_key"('tenant:' || read_field_values.tenant::text, false);
  select coalesce(jsonb_agg(jsonb_build_object('id', v."id", 'text', case when coalesce(d."encrypted", false) then "better_supabase"."field_open"(v_key, v."value_text") else v."value_text" end)), '[]'::jsonb),
    jsonb_agg(v."id") filter (where coalesce(d."encrypted", false) or coalesce(d."sensitive", false))
  into v_values, v_read
  from "better_supabase"."field_values" v
  left join "better_supabase"."field_definitions" d on d."id" = v."definition_id"
  where v."tenant_id" = read_field_values.tenant
    and v."subject_type" = read_field_values.subject_type
    and v."subject_id" = read_field_values.subject_id
    and (auth.role() = 'service_role' or (case when read_field_values.subject_type in ('drive_node') then case read_field_values.subject_type
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (read_field_values.subject_id)::uuid and s."tenant_id" = read_field_values.tenant and (coalesce(better_supabase.can('tenant', read_field_values.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    else false
  end else coalesce(better_supabase.can('tenant', read_field_values.tenant, 'custom_fields.read'), false) end))
    and (not coalesce(d."sensitive", false)
        or coalesce(better_supabase.can('tenant', v."tenant_id", coalesce(d."permission", 'custom_fields.sensitive.read')), false));
  if v_read is not null then
    perform better_supabase.audit_event(
    event_type => 'field_value.viewed',
    category => 'read',
    target_type => 'field_value',
    record_id => read_field_values.subject_id,
    summary => 'Read ' || jsonb_array_length(v_read)::text || ' protected field value(s) of ' || read_field_values.subject_type,
    tenant => (read_field_values.tenant)::uuid,
    metadata => jsonb_build_object('organizationId', read_field_values.tenant, 'subjectType', read_field_values.subject_type, 'subjectId', read_field_values.subject_id, 'ids', v_read)
  );
  end if;
  return v_values;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.request_approval (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  action       text,
  reason       text  DEFAULT NULL::text,
  payload      jsonb DEFAULT '{}'::jsonb,
  fingerprint  text  DEFAULT NULL::text,
  policy       jsonb DEFAULT NULL::jsonb,
  requested_by uuid  DEFAULT NULL::uuid
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_policy jsonb := "better_supabase"."approval_effective_policy"(request_approval.tenant, request_approval.subject_type, request_approval.action, coalesce(request_approval.payload, '{}'::jsonb));
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_result jsonb;
  v_req "better_supabase"."approval_requests"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if request_approval.policy is not null and not v_service then
    raise exception 'only the service role files a request under its own policy' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if request_approval.requested_by is not null and not v_service and request_approval.requested_by is distinct from auth.uid() then
    raise exception 'only the service role files a request for another user' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if request_approval.policy is not null then
    v_policy := "better_supabase"."approval_policy_tighten"(v_policy, request_approval.policy);
  end if;
  if v_policy is null then
    raise exception 'no approval policy for this subject type and action' using errcode = '22023', hint = 'APPROVAL_POLICY_UNKNOWN';
  end if;
  if not (v_service or (coalesce(better_supabase.can('tenant', request_approval.tenant, 'approvals.request'), false) and (case when request_approval.subject_type = 'drive_node' then coalesce(case when request_approval.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((request_approval.subject_id)::uuid, 'editor') end, false) else case request_approval.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant and (coalesce(better_supabase.can('tenant', request_approval.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (request_approval.subject_id)::uuid and s."tenant_id" = request_approval.tenant) and coalesce(better_supabase.can('tenant', request_approval.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (request_approval.subject_id)::uuid and s."organization_id" = request_approval.tenant)
    else false
  end end))) then
    raise exception 'not allowed to request approval for this record' using errcode = '42501', hint = 'APPROVAL_FORBIDDEN';
  end if;
  if not (coalesce(v_policy ->> 'mode', 'authorize') = 'confirm' or jsonb_array_length(coalesce(v_policy -> 'steps', '[]'::jsonb)) > 0) then
    raise exception 'no approval is required for this request' using errcode = '22023', hint = 'APPROVAL_NOT_REQUIRED';
  end if;
  if request_approval.fingerprint is not null and request_approval.fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'fingerprint must be a lowercase hex SHA-256' using errcode = '22023', hint = 'APPROVAL_FINGERPRINT_INVALID';
  end if;
  v_result := "better_supabase"."open_approval"(request_approval.tenant, request_approval.subject_type, request_approval.subject_id, request_approval.action, v_policy, request_approval.reason, request_approval.payload, coalesce(request_approval.requested_by, auth.uid()));
  if request_approval.fingerprint is not null then
    update "better_supabase"."approval_requests" x set "fingerprint" = request_approval.fingerprint
    where x."id" = (v_result ->> 'id')::uuid and x."status" = 'pending';
  end if;
  select * into v_req from "better_supabase"."approval_requests" x where x."id" = (v_result ->> 'id')::uuid;
  if found then
    return jsonb_build_object('id', v_req."id", 'organizationId', v_req."tenant_id", 'subjectType', v_req."subject_type", 'subjectId', v_req."subject_id", 'action', v_req."action", 'status', v_req."status", 'step', v_req."step", 'steps', v_req."policy" -> 'steps', 'requestedBy', v_req."requested_by", 'reason', v_req."reason", 'payload', v_req."payload", 'expiresAt', v_req."expires_at", 'decidedAt', v_req."decided_at", 'mode', coalesce(v_req."policy" ->> 'mode', 'authorize'), 'fingerprint', v_req."fingerprint", 'consumedAt', v_req."consumed_at", 'createdAt', v_req."created_at");
  end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_document_version (
  document_id uuid,
  state       text,
  label       text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
begin
  select * into v_doc from "better_supabase"."documents" d where d."id" = save_document_version.document_id;
  if not found then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'channels.manage'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.manage'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'quote' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'invoice' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'booking' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.manage'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'content_entry' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.write'), false)
    when 'form' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.manage'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end)) then
    raise exception 'not allowed to edit this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  return "better_supabase"."version_insert"(v_doc."tenant_id", 'document', v_doc."id"::text,
    jsonb_build_object('state', save_document_version.state, 'name', v_doc."name"),
    null, nullif(trim(save_document_version.label), ''), 'manual', false, auth.uid());
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.save_reminder (
  tenant         uuid,
  subject_type   text,
  subject_id     text,
  offset_minutes integer,
  remind_at      timestamp with time zone DEFAULT NULL::timestamp WITH time zone
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_reminder.tenant, 'reminders.manage'), false)) then
    raise exception 'not allowed to manage reminders' using errcode = '42501', hint = 'REMINDER_FORBIDDEN';
  end if;
  if not (auth.role() = 'service_role')
    and save_reminder.subject_type in ('message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'post', 'engagement', 'quote', 'work_item', 'employee', 'invoice', 'ledger_account', 'product', 'product_variant', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'policy', 'incident', 'content_entry', 'form', 'document', 'customer', 'drive_node', 'application', 'change_request', 'project', 'task')
    and not (case save_reminder.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (save_reminder.subject_id)::uuid and s."organization_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant and (coalesce(better_supabase.can('tenant', save_reminder.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (save_reminder.subject_id)::uuid and s."tenant_id" = save_reminder.tenant) and coalesce(better_supabase.can('tenant', save_reminder.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (save_reminder.subject_id)::uuid and s."organization_id" = save_reminder.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (save_reminder.subject_id)::uuid and s."organization_id" = save_reminder.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (save_reminder.subject_id)::uuid and s."organization_id" = save_reminder.tenant)
    else false
  end) then
    raise exception 'the record was not found in this organization' using errcode = 'P0002', hint = 'REMINDER_SUBJECT_NOT_FOUND';
  end if;
  insert into "better_supabase"."reminders" ("tenant_id", "subject_type", "subject_id", "user_id", "offset_minutes", "remind_at")
  values (save_reminder.tenant, save_reminder.subject_type, save_reminder.subject_id, auth.uid(), coalesce(save_reminder.offset_minutes, 0), save_reminder.remind_at)
  returning "id" into v_id;
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.set_field_value (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  definition   uuid,
  value        text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', set_field_value.tenant, 'custom_fields.manage'), false)) then
    raise exception 'not allowed to set custom fields' using errcode = '42501', hint = 'FIELD_FORBIDDEN';
  end if;
  if not (case set_field_value.subject_type
    when 'drive_node' then coalesce("better_supabase"."can_subject"(set_field_value.subject_type, set_field_value.subject_id, 'fields'), false)
    else true
  end) then
    raise exception 'not allowed to set fields on this record' using errcode = '42501', hint = 'FIELD_SUBJECT_FORBIDDEN';
  end if;
  if exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and not (case d."type" when 'bsn' then "better_supabase"."bsb_valid_bsn"(set_field_value.value) when 'iban' then "better_supabase"."bsb_valid_iban"(set_field_value.value) when 'phone_e164' then set_field_value.value ~* '^\+[1-9][0-9]{1,14}$' else true end)) then
    raise exception 'the value doesn''t match the field''s format' using errcode = '22023', hint = 'FIELD_VALUE_INVALID';
  end if;
  insert into "better_supabase"."field_values" ("tenant_id", "definition_id", "subject_type", "subject_id", "value_text")
  values (set_field_value.tenant, set_field_value.definition, set_field_value.subject_type, set_field_value.subject_id, case when exists (select 1 from "better_supabase"."field_definitions" d where d."id" = set_field_value.definition and d."encrypted") then "better_supabase"."field_encrypt"('tenant:' || set_field_value.tenant::text, set_field_value.value) else set_field_value.value end)
  returning "id" into v_id;
  perform "better_supabase".emit_event('field_value.set', jsonb_build_object('organizationId', set_field_value.tenant, 'id', v_id, 'subjectType', set_field_value.subject_type, 'subjectId', set_field_value.subject_id), 'field-values/' || v_id::text, (set_field_value.tenant)::text, null, 'better-supabase/custom-fields');
  return jsonb_build_object('id', v_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.start_timer (
  tenant        uuid,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  billable      boolean DEFAULT false,
  rate          bigint  DEFAULT NULL::bigint,
  rate_currency text    DEFAULT NULL::text,
  note          text    DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_at timestamptz := clock_timestamp();
  v_row "better_supabase"."time_entries"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_me is null or not coalesce(better_supabase.can('tenant', start_timer.tenant, 'time_tracking.track'), false) then
    raise exception 'not allowed to track time here' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if (start_timer.subject_type is null) <> (start_timer.subject_id is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if start_timer.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case start_timer.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant and (coalesce(better_supabase.can('tenant', start_timer.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (start_timer.subject_id)::uuid and s."tenant_id" = start_timer.tenant) and coalesce(better_supabase.can('tenant', start_timer.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (start_timer.subject_id)::uuid and s."organization_id" = start_timer.tenant)
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if start_timer.rate is not null and start_timer.rate_currency is null then
    raise exception 'a rate needs rate_currency' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if start_timer.rate_currency !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('time_entry:' || start_timer.tenant::text || ':' || v_me::text, 0));
  update "better_supabase"."time_entries" x set "ended_at" = v_at, "updated_at" = v_at
    where x."tenant_id" = start_timer.tenant and x."user_id" = v_me and x."ended_at" is null
    returning * into v_row;
  if found then
    perform "better_supabase".emit_event('time_entry.recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  end if;
  v_row := null;
  v_row."id" := gen_random_uuid();
  v_row."tenant_id" := start_timer.tenant;
  v_row."user_id" := v_me;
  v_row."subject_type" := start_timer.subject_type;
  v_row."subject_id" := start_timer.subject_id;
  v_row."started_at" := v_at;
  v_row."billable" := coalesce(start_timer.billable, false);
  v_row."rate" := start_timer.rate;
  v_row."rate_currency" := start_timer.rate_currency;
  v_row."note" := start_timer.note;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  insert into "better_supabase"."time_entries" ("id", "tenant_id", "user_id", "subject_type", "subject_id", "started_at", "billable", "rate", "rate_currency", "note")
  values (v_row."id", v_row."tenant_id", v_row."user_id", v_row."subject_type", v_row."subject_id", v_row."started_at", v_row."billable", v_row."rate", v_row."rate_currency", v_row."note")
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.started', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at"), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.subject_tags (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_ids uuid[];
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.read'), false) or coalesce(better_supabase.can('tenant', subject_tags.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to read tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not ((case when subject_tags.subject_type = 'drive_node' then coalesce(case when subject_tags.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((subject_tags.subject_id)::uuid, 'viewer') end, false) else case subject_tags.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant and (coalesce(better_supabase.can('tenant', subject_tags.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (subject_tags.subject_id)::uuid and s."tenant_id" = subject_tags.tenant) and coalesce(better_supabase.can('tenant', subject_tags.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (subject_tags.subject_id)::uuid and s."organization_id" = subject_tags.tenant)
    else false
  end end)) then
    raise exception 'not allowed to read this record''s tags' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select array_agg(g."tag_id") into v_ids from "better_supabase"."taggings" g
      where g."tenant_id" = subject_tags.tenant
        and g."subject_type" = subject_tags.subject_type
        and g."subject_id" = subject_tags.subject_id;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', t."id", 'kind', t."kind", 'name', t."name", 'slug', t."slug", 'color', t."color", 'description', t."description", 'rank', t."rank") order by t."rank" collate "C", t."name", t."id")
    from "better_supabase"."tags" t
    where t."tenant_id" = subject_tags.tenant
      and t."id" = any (v_ids)
  ), '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.submit_form (
  form_id       uuid,
  answers       jsonb,
  subject_type  text    DEFAULT NULL::text,
  subject_id    text    DEFAULT NULL::text,
  submission_id uuid    DEFAULT NULL::uuid,
  draft         boolean DEFAULT false
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."forms" x where x."id" = submit_form.form_id;
  if not found then
    raise exception 'form not found' using errcode = 'P0002', hint = 'FORM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (auth.uid() is not null and coalesce(better_supabase.can('tenant', v_tenant, 'forms.submit'), false))) then
    raise exception 'not allowed to submit this form' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  if (submit_form.subject_type is null) <> (submit_form.subject_id is null) then
    raise exception 'pass both subject_type and subject_id, or neither' using errcode = '22023', hint = 'FORM_SUBJECT_INVALID';
  end if;
  if submit_form.subject_type is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case submit_form.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant and (coalesce(better_supabase.can('tenant', v_tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (submit_form.subject_id)::uuid and s."tenant_id" = v_tenant) and coalesce(better_supabase.can('tenant', v_tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (submit_form.subject_id)::uuid and s."organization_id" = v_tenant)
    else false
  end) then
    raise exception 'not allowed to link this record' using errcode = '42501', hint = 'FORM_FORBIDDEN';
  end if;
  return "better_supabase"."form_submission_save"(submit_form.form_id, submit_form.answers, submit_form.subject_type, submit_form.subject_id, auth.uid(),
    case when coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') then 'service' else 'member' end, coalesce(submit_form.draft, false), submit_form.submission_id);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.suggest_document_change (
  document_id uuid,
  payload     text,
  summary     text DEFAULT NULL::text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_doc "better_supabase"."documents"%rowtype;
  v_suggestion "better_supabase"."document_suggestions"%rowtype;
  v_bytes bytea;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_doc from "better_supabase"."documents" d where d."id" = suggest_document_change.document_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end)) then
    raise exception 'document not found' using errcode = 'P0002', hint = 'DOCUMENT_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end and case v_doc."subject_type"
    when 'message' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.send'), false)
    when 'channel' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'channels.manage'), false)
    when 'company' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'person' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.write'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.write'), false)
    when 'course' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.manage'), false)
    when 'post' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.write'), false)
    when 'engagement' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.write'), false)
    when 'quote' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.write'), false)
    when 'employee' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.write'), false)
    when 'invoice' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.write'), false)
    when 'ledger_account' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.manage'), false)
    when 'product' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'product_variant' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.manage'), false)
    when 'order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.manage'), false)
    when 'calendar_event' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.write'), false)
    when 'booking' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.manage'), false)
    when 'asset' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'asset_location' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.manage'), false)
    when 'lease' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.manage'), false)
    when 'expense_report' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'expense_line' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.manage'), false)
    when 'donation_fund' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.manage'), false)
    when 'work_order' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.manage'), false)
    when 'shipment' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.manage'), false)
    when 'contract' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.write'), false)
    when 'control' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'policy' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.manage'), false)
    when 'incident' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.write'), false)
    when 'content_entry' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.write'), false)
    when 'form' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.manage'), false)
    when 'document' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.manage'), false)
    when 'application' then coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.write'), false)
    else true
  end) or ((coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false) and case v_doc."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id" and (coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_doc."subject_id")::uuid and s."tenant_id" = v_doc."tenant_id") and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_doc."subject_id")::uuid and s."organization_id" = v_doc."tenant_id")
    else false
  end) and coalesce(better_supabase.can('tenant', v_doc."tenant_id", 'documents.suggest'), false)))) then
    raise exception 'not allowed to suggest changes to this document' using errcode = '42501', hint = 'DOCUMENT_FORBIDDEN';
  end if;
  begin
    v_bytes := decode(suggest_document_change.payload, 'base64');
  exception when others then
    raise exception 'the update must be base64' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end;
  if v_bytes is null or length(v_bytes) = 0 then
    raise exception 'the update is empty' using errcode = '22023', hint = 'DOCUMENT_UPDATE_INVALID';
  end if;
  if length(v_bytes) > 1048576 then
    raise exception 'an update can be at most 1048576 bytes' using errcode = '54000', hint = 'DOCUMENT_UPDATE_TOO_LARGE';
  end if;
  insert into "better_supabase"."document_suggestions" ("document_id", "tenant_id", "payload", "summary", "status", "created_by")
  values (v_doc."id", v_doc."tenant_id", v_bytes, nullif(trim(suggest_document_change.summary), ''), 'open', auth.uid())
  returning * into v_suggestion;
  perform "better_supabase".emit_event('document.suggested', jsonb_build_object('organizationId', v_doc."tenant_id"::text, 'subjectType', v_doc."subject_type", 'subjectId', v_doc."subject_id", 'id', v_doc."id", 'name', v_doc."name", 'suggestionId', v_suggestion."id", 'authorId', v_suggestion."created_by", 'status', v_suggestion."status"), 'documents/' || v_doc."id"::text, (v_doc."tenant_id")::text, null, 'better-supabase/documents');
  return jsonb_build_object('id', v_suggestion."id", 'documentId', v_suggestion."document_id", 'summary', v_suggestion."summary", 'status', v_suggestion."status", 'createdBy', v_suggestion."created_by", 'createdAt', v_suggestion."created_at", 'decidedBy', v_suggestion."decided_by", 'decidedAt', v_suggestion."decided_at", 'note', v_suggestion."note", 'update', replace(encode(v_suggestion."payload", 'base64'), E'\n', ''));
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.tag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_kind text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', tag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not ((case when tag.subject_type = 'drive_node' then coalesce(case when tag.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((tag.subject_id)::uuid, 'editor') end, false) else case tag.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant and (coalesce(better_supabase.can('tenant', tag.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (tag.subject_id)::uuid and s."tenant_id" = tag.tenant) and coalesce(better_supabase.can('tenant', tag.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (tag.subject_id)::uuid and s."organization_id" = tag.tenant)
    else false
  end end)) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  select "kind" into v_kind from "better_supabase"."tags" where "id" = tag.tag_id and "tenant_id" = tag.tenant;
  if v_kind is null then
    raise exception 'tag not found' using errcode = 'P0002', hint = 'TAG_NOT_FOUND';
  end if;
  if not (case tag.subject_type
    when 'message' then true
    when 'conversation' then true
    when 'channel' then true
    when 'company' then true
    when 'person' then true
    when 'deal' then true
    when 'course' then true
    when 'post' then true
    when 'engagement' then true
    when 'quote' then true
    when 'work_item' then true
    when 'employee' then true
    when 'invoice' then true
    when 'ledger_account' then true
    when 'product' then true
    when 'product_variant' then true
    when 'order' then true
    when 'calendar_event' then true
    when 'booking' then true
    when 'asset' then true
    when 'asset_location' then true
    when 'lease' then true
    when 'expense_report' then true
    when 'expense_line' then true
    when 'donation_fund' then true
    when 'work_order' then true
    when 'shipment' then true
    when 'contract' then true
    when 'control' then true
    when 'policy' then true
    when 'incident' then true
    when 'content_entry' then true
    when 'form' then true
    when 'document' then true
    when 'customer' then true
    when 'drive_node' then true
    when 'application' then true
    when 'change_request' then true
    when 'project' then true
    when 'task' then true
    else true
  end) then
    raise exception 'tag kind is not allowed on this subject' using errcode = '22023', hint = 'TAG_KIND_MISMATCH';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_tag_apply"(uuid, text, text, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::uuid)', v_hook::oid::regproc)
        using tag.tenant, tag.subject_type, tag.subject_id, tag.tag_id;
    end if;
  end;
  case tag.subject_type
    when '' then null;
    else
      insert into "better_supabase"."taggings" ("tenant_id", "tag_id", "subject_type", "subject_id")
      values (tag.tenant, tag.tag_id, tag.subject_type, tag.subject_id)
      on conflict do nothing;
  end case;
  perform "better_supabase".emit_event('subject.tagged', jsonb_build_object('organizationId', tag.tenant, 'subjectType', tag.subject_type, 'subjectId', tag.subject_id, 'id', tag.tag_id), 'subjects/' || tag.subject_type || '/' || tag.subject_id, (tag.tenant)::text, null, 'better-supabase/tags');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_tag_apply"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using tag.tag_id, tag.subject_type, tag.subject_id;
    end if;
  end;
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.trash (
  tenant       uuid,
  subject_type text,
  subject_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_batch uuid := gen_random_uuid();
  v_count integer;
  v_id uuid;
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', trash.tenant, 'trash.create'), false) and case trash.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'messages.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'deals.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'work_items.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (trash.subject_id)::uuid and s."organization_id" = trash.tenant) and coalesce(better_supabase.can('tenant', trash.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (trash.subject_id)::uuid and s."tenant_id" = trash.tenant and (coalesce(better_supabase.can('tenant', trash.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (trash.subject_id)::uuid and s."organization_id" = trash.tenant)
    else false
  end and case trash.subject_type
    when 'message' then coalesce(better_supabase.can('tenant', trash.tenant, 'messages.send'), false)
    when 'conversation' then coalesce(better_supabase.can('tenant', trash.tenant, 'messages.send'), false)
    when 'deal' then coalesce(better_supabase.can('tenant', trash.tenant, 'deals.write'), false)
    when 'work_item' then coalesce(better_supabase.can('tenant', trash.tenant, 'work_items.write'), false)
    when 'customer' then coalesce(better_supabase.can('tenant', trash.tenant, 'customers.write'), false)
    when 'drive_node' then coalesce(better_supabase.can('tenant', trash.tenant, 'drive.manage'), false)
    else true
  end)) then
    raise exception 'not allowed to trash this record' using errcode = '42501', hint = 'TRASH_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_trash"(uuid, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text)', v_hook::oid::regproc)
        using trash.tenant, trash.subject_type, trash.subject_id;
    end if;
  end;
  v_count := "better_supabase"."trash_cascade"(trash.tenant, trash.subject_type, trash.subject_id, v_batch, 0, auth.uid());
  if v_count = 0 then
    raise exception 'no live record to trash' using errcode = 'P0002', hint = 'TRASH_NOT_FOUND';
  end if;
  select i."id" into v_id from "better_supabase"."trash_items" i
    where i."subject_type" = trash.subject_type and i."subject_id" = trash.subject_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_trash"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_id, v_batch;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'batchId', v_batch, 'count', v_count);
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.unlink (
  tenant      uuid,
  kind        text,
  source_type text,
  source_id   text,
  target_type text,
  target_id   text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_kind text;
  v_inverted boolean;
  v_acyclic boolean;
  v_single boolean;
  v_symmetric boolean;
  v_source_type text;
  v_source_id text;
  v_target_type text;
  v_target_id text;
  v_old "better_supabase"."relations";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', unlink.tenant, 'relations.manage'), false)) then
    raise exception 'not allowed to unlink records' using errcode = '42501', hint = 'RELATION_FORBIDDEN';
  end if;

  select k.canonical, k.inverted, k.acyclic, k.single, k.both_ways
    into v_kind, v_inverted, v_acyclic, v_single, v_symmetric
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from'), ('represents', 'represents', false, false, false, false, 'represented_by'), ('represented_by', 'represents', true, false, false, false, 'represents')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = unlink.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  if v_inverted then
    v_source_type := unlink.target_type; v_source_id := unlink.target_id;
    v_target_type := unlink.source_type; v_target_id := unlink.source_id;
  else
    v_source_type := unlink.source_type; v_source_id := unlink.source_id;
    v_target_type := unlink.target_type; v_target_id := unlink.target_id;
  end if;
  if v_symmetric and (v_source_type, v_source_id) > (v_target_type, v_target_id) then
    select v_target_type, v_target_id, v_source_type, v_source_id
      into v_source_type, v_source_id, v_target_type, v_target_id;
  end if;
  if not (case unlink.source_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant and (coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (unlink.source_id)::uuid and s."organization_id" = unlink.tenant)
    else false
  end)
     or not (case unlink.target_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant and (coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (unlink.target_id)::uuid and s."organization_id" = unlink.tenant)
    else false
  end) then
    raise exception 'not allowed to unlink these records' using errcode = '42501', hint = 'RELATION_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."relations"
    where "tenant_id" = unlink.tenant and "kind" = v_kind
      and "source_type" = v_source_type and "source_id" = v_source_id
      and "target_type" = v_target_type and "target_id" = v_target_id
    returning * into v_old;
  if v_old."id" is null then
    return jsonb_build_object('removed', false, 'data', null);
  end if;
  perform "better_supabase".emit_event('subject.unlinked', jsonb_build_object('organizationId', unlink.tenant, 'id', v_old."id", 'kind', v_kind, 'subjectType', v_source_type, 'subjectId', v_source_id, 'targetType', v_target_type, 'targetId', v_target_id), 'subjects/' || v_source_type || '/' || v_source_id, (unlink.tenant)::text, null, 'better-supabase/relations');
  return jsonb_build_object('removed', true, 'data', v_old."data");
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.untag (
  tenant       uuid,
  subject_type text,
  subject_id   text,
  tag_id       uuid
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', untag.tenant, 'tags.manage'), false)) then
    raise exception 'not allowed to apply tags' using errcode = '42501', hint = 'TAG_FORBIDDEN';
  end if;
  if not ((case when untag.subject_type = 'drive_node' then coalesce(case when untag.subject_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then "better_supabase"."drive_can"((untag.subject_id)::uuid, 'editor') end, false) else case untag.subject_type
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant and (coalesce(better_supabase.can('tenant', untag.tenant, 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (untag.subject_id)::uuid and s."tenant_id" = untag.tenant) and coalesce(better_supabase.can('tenant', untag.tenant, 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant)
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant)
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (untag.subject_id)::uuid and s."organization_id" = untag.tenant)
    else false
  end end)) then
    raise exception 'not allowed to tag this record' using errcode = '42501', hint = 'TAG_SUBJECT_FORBIDDEN';
  end if;
  delete from "better_supabase"."taggings" g
      where g."tenant_id" = untag.tenant
        and g."tag_id" = untag.tag_id
        and g."subject_type" = untag.subject_type
        and g."subject_id" = untag.subject_id;
  perform "better_supabase".emit_event('subject.untagged', jsonb_build_object('organizationId', untag.tenant, 'subjectType', untag.subject_type, 'subjectId', untag.subject_id, 'id', untag.tag_id), 'subjects/' || untag.subject_type || '/' || untag.subject_id, (untag.tenant)::text, null, 'better-supabase/tags');
  return true;
end;
$function$;

CREATE OR REPLACE FUNCTION better_supabase.update_time_entry (
  entry_id uuid,
  patch    jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
#variable_conflict use_column
declare
  v_row "better_supabase"."time_entries"%rowtype;
  v_patch jsonb := coalesce(update_time_entry.patch, '{}'::jsonb);
  v_previous_started_at timestamptz;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."time_entries" x where x."id" = update_time_entry.entry_id for update;
  if not found then
    raise exception 'time entry not found' using errcode = 'P0002', hint = 'TIME_ENTRY_NOT_FOUND';
  end if;
  v_previous_started_at := v_row."started_at";
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(v_row."user_id" = auth.uid(), false) and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.track'), false)) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'time_tracking.manage'), false)) then
    raise exception 'not allowed to change this entry' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  if v_patch ? 'startedAt' then
    v_row."started_at" := (v_patch ->> 'startedAt')::timestamptz;
  end if;
  if v_patch ? 'endedAt' then
    if v_patch ->> 'endedAt' is null then
      raise exception 'a finished entry can''t be restarted; start a timer instead' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
    end if;
    v_row."ended_at" := (v_patch ->> 'endedAt')::timestamptz;
  end if;
  if v_row."started_at" is null or (v_row."ended_at" is not null and v_row."ended_at" <= v_row."started_at") then
    raise exception 'ended_at must be after started_at' using errcode = '22023', hint = 'TIME_ENTRY_INVALID';
  end if;
  if v_patch ? 'subjectType' or v_patch ? 'subjectId' then
    v_row."subject_type" := v_patch ->> 'subjectType';
    v_row."subject_id" := v_patch ->> 'subjectId';
    if (v_row."subject_type" is null) <> (v_row."subject_id" is null) then
    raise exception 'name both subject_type and subject_id, or neither' using errcode = '22023', hint = 'TIME_SUBJECT_INVALID';
  end if;
  if v_row."subject_type" is not null and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or case v_row."subject_type"
    when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'messages.read'), false)
    when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'parties.read'), false)
    when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'deals.read'), false)
    when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'courses.read'), false)
    when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'posts.read'), false)
    when 'engagement' then exists (select 1 from "better_supabase"."engagements" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'engagements.read'), false)
    when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'quotes.read'), false)
    when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'work_items.read'), false)
    when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'employees.read'), false)
    when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.read'), false)
    when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ledger.read'), false)
    when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'catalog.read'), false)
    when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'orders.read'), false)
    when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'calendar.read'), false)
    when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'bookings.read'), false)
    when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'assets.read'), false)
    when 'lease' then exists (select 1 from "better_supabase"."lease_agreements" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'leases.read'), false)
    when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'expenses.read'), false)
    when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'donations.read'), false)
    when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'dispatch.read'), false)
    when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'shipments.read'), false)
    when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'contracts.read'), false)
    when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.read'), false)
    when 'policy' then exists (select 1 from "better_supabase"."policies" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'controls.read'), false)
    when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'incidents.read'), false)
    when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'content.read'), false)
    when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'forms.read'), false)
    when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'documents.read'), false)
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'customers.read'), false)
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id" and (coalesce(better_supabase.can('tenant', v_row."tenant_id", 'drive.read'), false) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)))
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_row."subject_id")::uuid and s."tenant_id" = v_row."tenant_id") and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'hiring.read'), false)
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_row."subject_id")::uuid and s."organization_id" = v_row."tenant_id")
    else false
  end) then
    raise exception 'not allowed to track time on this record' using errcode = '42501', hint = 'TIME_FORBIDDEN';
  end if;
  end if;
  if v_patch ? 'billable' then
    v_row."billable" := coalesce((v_patch ->> 'billable')::boolean, false);
  end if;
  if v_patch ? 'rate' or v_patch ? 'rateCurrency' then
    v_row."rate" := (v_patch ->> 'rate')::bigint;
    v_row."rate_currency" := v_patch ->> 'rateCurrency';
    if v_row."rate" is not null and v_row."rate_currency" is null then
    raise exception 'a rate needs rate_currency' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  if v_row."rate_currency" !~ '^[A-Z]{3}$' then
    raise exception 'rate_currency must be a three-letter currency code' using errcode = '22023', hint = 'TIME_RATE_INVALID';
  end if;
  end if;
  if v_patch ? 'note' then
    v_row."note" := v_patch ->> 'note';
  end if;
  if exists (
    select 1 from "better_supabase"."time_entries" x
    where x."tenant_id" = v_row."tenant_id" and x."user_id" = v_row."user_id" and x."id" <> v_row."id"
      and tstzrange(x."started_at", coalesce(x."ended_at", 'infinity'::timestamptz)) && tstzrange(v_row."started_at", coalesce(v_row."ended_at", 'infinity'::timestamptz))
  ) then
    raise exception 'this time overlaps another entry' using errcode = '23P01', hint = 'TIME_ENTRY_OVERLAP';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_time_entry_save"(uuid, uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::uuid)', v_hook::oid::regproc)
        using v_row."id", v_row."tenant_id", v_row."user_id";
    end if;
  end;
  update "better_supabase"."time_entries" x
  set "started_at" = v_row."started_at",
      "ended_at" = v_row."ended_at",
      "subject_type" = v_row."subject_type",
      "subject_id" = v_row."subject_id",
      "billable" = v_row."billable",
      "rate" = v_row."rate",
      "rate_currency" = v_row."rate_currency",
      "note" = v_row."note",
      "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('time_entry.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'id', v_row."id", 'userId', v_row."user_id", 'startedAt', v_row."started_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'previousStartedAt', v_previous_started_at), 'time-entries/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/time-tracking');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_time_entry_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'userId', v_row."user_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'startedAt', v_row."started_at", 'endedAt', v_row."ended_at", 'seconds', case when v_row."ended_at" is null then null else extract(epoch from v_row."ended_at" - v_row."started_at")::bigint end, 'billable', v_row."billable", 'rate', v_row."rate"::text, 'rateCurrency', v_row."rate_currency", 'note', v_row."note", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$function$;

REVOKE ALL ON FUNCTION "api"."drive_node_readable"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."drive_node_readable"(uuid) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."drive_node_readable"(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."drive_node_readable"(uuid) TO "authenticated", "service_role";
