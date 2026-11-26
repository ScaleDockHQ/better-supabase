-- better-supabase module: field-history
-- @bsb-block field-history@1 managed
-- @bsb-hash sha256:a25596f01e58833902097eb84820afaac80d502a50f72c4eebd2261af773dff5
-- The old and new value of chosen columns of any registered record on every update, who changed it and when, read per record and field.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Field history: the old and new value of the watched columns of a record on
-- every update, who made it and when.
create table "better_supabase"."field_changes" (
  "id" bigint generated always as identity primary key,
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "field" text not null,
  "old_value" jsonb,
  "new_value" jsonb,
  "changed_by" uuid references auth.users (id) on delete set null,
  "changed_at" timestamptz not null default now()
);
create index field_changes_subject_idx on "better_supabase"."field_changes" ("subject_type", "subject_id", "id" desc);
create index field_changes_tenant_idx on "better_supabase"."field_changes" ("tenant_id", "changed_at");
create index field_changes_changed_by_idx on "better_supabase"."field_changes" ("changed_by") where "changed_by" is not null;
alter table "better_supabase"."field_changes" enable row level security;
revoke all on "better_supabase"."field_changes" from public, anon, authenticated;
grant select on "better_supabase"."field_changes" to authenticated;
grant all on "better_supabase"."field_changes" to service_role;
-- Whether the caller may read the subject a row of field-history names, apart from
-- the permission of the types in the gate (ADR 1232): the subject row has to be
-- visible to them (its own policies apply), with the record grants and team
-- check of the types that have them. plpgsql, so a statement plans only the
-- branch of the type it reads and a table a later module creates binds late.
create or replace function "better_supabase"."field_history_subject_readable"(subject_type text, subject_id text, tenant uuid)
returns boolean
language plpgsql
stable
security invoker
cost 1000
set search_path = ''
as $$
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
$$;
revoke execute on function "better_supabase"."field_history_subject_readable"(text, text, uuid) from public, anon;
grant execute on function "better_supabase"."field_history_subject_readable"(text, text, uuid) to authenticated, service_role;
create policy bsb_field_changes_read on "better_supabase"."field_changes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and case "better_supabase"."field_changes"."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."organization_id" = "better_supabase"."field_changes"."tenant_id") and ("better_supabase"."field_changes"."tenant_id" in (select better_supabase.tenant_ids_with('customers.read')) or "better_supabase"."is_subject_member"('customer', "better_supabase"."field_changes"."subject_id"))
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."tenant_id" = "better_supabase"."field_changes"."tenant_id" and (("better_supabase"."field_changes"."tenant_id" in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', "better_supabase"."field_changes"."subject_id")))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."id" = "better_supabase"."field_changes"."tenant_id")
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."organization_id" = "better_supabase"."field_changes"."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."organization_id" = "better_supabase"."field_changes"."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."organization_id" = "better_supabase"."field_changes"."tenant_id")
    else (coalesce("better_supabase"."field_changes"."subject_type" = any(array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'activity', 'quote', 'work_item', 'employee', 'ledger_account', 'invoice', 'product', 'product_variant', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'case', 'form', 'incident', 'document', 'application']), false) = false or ("better_supabase"."field_changes"."tenant_id", "better_supabase"."field_changes"."subject_type") in (select t.tenant, g.type from better_supabase.tenant_ids_with('messages.read') as t(tenant) cross join unnest(array['message', 'conversation', 'channel']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('contacts.read') as t(tenant) cross join unnest(array['company', 'person']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('deals.read') as t(tenant) cross join unnest(array['deal']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('courses.read') as t(tenant) cross join unnest(array['course']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('activities.read') as t(tenant) cross join unnest(array['activity']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('quotes.read') as t(tenant) cross join unnest(array['quote']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('tasks.read') as t(tenant) cross join unnest(array['work_item']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('employees.read') as t(tenant) cross join unnest(array['employee']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('ledger.read') as t(tenant) cross join unnest(array['ledger_account']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('invoices.read') as t(tenant) cross join unnest(array['invoice']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('catalog.read') as t(tenant) cross join unnest(array['product', 'product_variant']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('orders.read') as t(tenant) cross join unnest(array['order']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('calendar.read') as t(tenant) cross join unnest(array['calendar_event']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('bookings.read') as t(tenant) cross join unnest(array['booking']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('assets.read') as t(tenant) cross join unnest(array['asset', 'asset_location']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('leases.read') as t(tenant) cross join unnest(array['lease']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('expenses.read') as t(tenant) cross join unnest(array['expense_report', 'expense_line']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('donations.read') as t(tenant) cross join unnest(array['donation_fund']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('dispatch.read') as t(tenant) cross join unnest(array['work_order']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('shipments.read') as t(tenant) cross join unnest(array['shipment']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('contracts.read') as t(tenant) cross join unnest(array['contract']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('compliance.read') as t(tenant) cross join unnest(array['control', 'compliance_policy']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('cases.read') as t(tenant) cross join unnest(array['case']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('forms.read') as t(tenant) cross join unnest(array['form']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('incidents.read') as t(tenant) cross join unnest(array['incident']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('documents.read') as t(tenant) cross join unnest(array['document']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('hiring.read') as t(tenant) cross join unnest(array['application']) as g(type))) and "better_supabase"."field_history_subject_readable"("better_supabase"."field_changes"."subject_type", "better_supabase"."field_changes"."subject_id", "better_supabase"."field_changes"."tenant_id")
  end);

-- Keeps the old and new value of each watched column of a work_item on update.
create or replace function better_supabase.bsb_field_history_work_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'work_item', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('title', to_jsonb(old."title"), to_jsonb(new."title")),
      ('body', to_jsonb(old."body"), to_jsonb(new."body"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_field_history_work_item() from public, anon, authenticated;
create trigger bsb_field_history_work_item after update of "title", "body" on "better_supabase"."work_items"
for each row execute function better_supabase.bsb_field_history_work_item();

-- Keeps the old and new value of each watched column of a deal on update.
create or replace function better_supabase.bsb_field_history_deal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'deal', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('amount', to_jsonb(old."amount"), to_jsonb(new."amount")),
      ('stage_id', to_jsonb(old."stage_id"), to_jsonb(new."stage_id")),
      ('owner_id', to_jsonb(old."owner_id"), to_jsonb(new."owner_id")),
      ('expected_close_on', to_jsonb(old."expected_close_on"), to_jsonb(new."expected_close_on"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_field_history_deal() from public, anon, authenticated;
create trigger bsb_field_history_deal after update of "amount", "stage_id", "owner_id", "expected_close_on" on "better_supabase"."deals"
for each row execute function better_supabase.bsb_field_history_deal();

-- Keeps the old and new value of each watched column of a company on update.
create or replace function better_supabase.bsb_field_history_company()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into "better_supabase"."field_changes" ("tenant_id", "subject_type", "subject_id", "field", "old_value", "new_value", "changed_by")
  select new."tenant_id", 'company', new."id"::text, x.field, x.old_value, x.new_value, auth.uid()
  from (values
      ('owner_id', to_jsonb(old."owner_id"), to_jsonb(new."owner_id")),
      ('lifecycle', to_jsonb(old."lifecycle"), to_jsonb(new."lifecycle"))
  ) as x (field, old_value, new_value)
  where x.old_value is distinct from x.new_value;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_field_history_company() from public, anon, authenticated;
create trigger bsb_field_history_company after update of "owner_id", "lifecycle" on "better_supabase"."companies"
for each row execute function better_supabase.bsb_field_history_company();

-- A record's changes, newest first, optionally of one field. before is the id
-- of the last change of the previous page. Needs history.read and read access
-- to the record.
create or replace function "better_supabase"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', z."id"::text,
    'organizationId', z."tenant_id",
    'subjectType', z."subject_type",
    'subjectId', z."subject_id",
    'field', z."field",
    'before', z."old_value",
    'after', z."new_value",
    'changedBy', z."changed_by",
    'changedAt', z."changed_at"
  ) order by z."id" desc), '[]'::jsonb)
  from (
    select x.* from "better_supabase"."field_changes" x
    where x."subject_type" = field_history.subject_type
      and x."subject_id" = field_history.subject_id
      and (field_history.field is null or x."field" = field_history.field)
      and (field_history.before is null or x."id" < field_history.before)
      and (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (coalesce(better_supabase.can('tenant', x."tenant_id", 'field_history.read'), false) and coalesce("better_supabase"."can_subject"(field_history.subject_type, field_history.subject_id, 'read'), false)))
    order by x."id" desc
    limit least(greatest(coalesce(field_history.max_count, 50), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "better_supabase"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."field_changes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('field_history.read')) and case "better_supabase"."field_changes"."subject_type"
    when 'customer' then exists (select 1 from "public"."customers" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."organization_id" = "better_supabase"."field_changes"."tenant_id") and ("better_supabase"."field_changes"."tenant_id" in (select better_supabase.tenant_ids_with('customers.read')) or "better_supabase"."is_subject_member"('customer', "better_supabase"."field_changes"."subject_id"))
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."tenant_id" = "better_supabase"."field_changes"."tenant_id" and (("better_supabase"."field_changes"."tenant_id" in (select better_supabase.tenant_ids_with('drive.read')) and coalesce("better_supabase"."drive_node_readable"(s."id"), false)) or "better_supabase"."is_subject_member"('drive_node', "better_supabase"."field_changes"."subject_id")))
    when 'organization' then exists (select 1 from "public"."organizations" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."id" = "better_supabase"."field_changes"."tenant_id")
    when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."organization_id" = "better_supabase"."field_changes"."tenant_id")
    when 'project' then exists (select 1 from "public"."projects" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."organization_id" = "better_supabase"."field_changes"."tenant_id")
    when 'task' then exists (select 1 from "public"."tasks" s where s."id" = ("better_supabase"."field_changes"."subject_id")::uuid and s."organization_id" = "better_supabase"."field_changes"."tenant_id")
    else (coalesce("better_supabase"."field_changes"."subject_type" = any(array['message', 'conversation', 'channel', 'company', 'person', 'deal', 'course', 'activity', 'quote', 'work_item', 'employee', 'ledger_account', 'invoice', 'product', 'product_variant', 'order', 'calendar_event', 'booking', 'asset', 'asset_location', 'lease', 'expense_report', 'expense_line', 'donation_fund', 'work_order', 'shipment', 'contract', 'control', 'compliance_policy', 'case', 'form', 'incident', 'document', 'application']), false) = false or ("better_supabase"."field_changes"."tenant_id", "better_supabase"."field_changes"."subject_type") in (select t.tenant, g.type from better_supabase.tenant_ids_with('messages.read') as t(tenant) cross join unnest(array['message', 'conversation', 'channel']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('contacts.read') as t(tenant) cross join unnest(array['company', 'person']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('deals.read') as t(tenant) cross join unnest(array['deal']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('courses.read') as t(tenant) cross join unnest(array['course']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('activities.read') as t(tenant) cross join unnest(array['activity']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('quotes.read') as t(tenant) cross join unnest(array['quote']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('tasks.read') as t(tenant) cross join unnest(array['work_item']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('employees.read') as t(tenant) cross join unnest(array['employee']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('ledger.read') as t(tenant) cross join unnest(array['ledger_account']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('invoices.read') as t(tenant) cross join unnest(array['invoice']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('catalog.read') as t(tenant) cross join unnest(array['product', 'product_variant']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('orders.read') as t(tenant) cross join unnest(array['order']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('calendar.read') as t(tenant) cross join unnest(array['calendar_event']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('bookings.read') as t(tenant) cross join unnest(array['booking']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('assets.read') as t(tenant) cross join unnest(array['asset', 'asset_location']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('leases.read') as t(tenant) cross join unnest(array['lease']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('expenses.read') as t(tenant) cross join unnest(array['expense_report', 'expense_line']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('donations.read') as t(tenant) cross join unnest(array['donation_fund']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('dispatch.read') as t(tenant) cross join unnest(array['work_order']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('shipments.read') as t(tenant) cross join unnest(array['shipment']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('contracts.read') as t(tenant) cross join unnest(array['contract']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('compliance.read') as t(tenant) cross join unnest(array['control', 'compliance_policy']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('cases.read') as t(tenant) cross join unnest(array['case']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('forms.read') as t(tenant) cross join unnest(array['form']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('incidents.read') as t(tenant) cross join unnest(array['incident']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('documents.read') as t(tenant) cross join unnest(array['document']) as g(type) union all select t.tenant, g.type from better_supabase.tenant_ids_with('hiring.read') as t(tenant) cross join unnest(array['application']) as g(type))) and "better_supabase"."field_history_subject_readable"("better_supabase"."field_changes"."subject_type", "better_supabase"."field_changes"."subject_id", "better_supabase"."field_changes"."tenant_id")
  end)
  );
create policy bsb_tenant_scope_insert on "better_supabase"."field_changes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."field_changes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."field_changes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.field-history.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.


create or replace function "api"."field_history"(subject_type text, subject_id text, field text default null, before bigint default null, max_count integer default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."field_history"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."field_history"(text, text, text, bigint, integer) from public, anon;
grant execute on function "api"."field_history"(text, text, text, bigint, integer) to authenticated, service_role;
