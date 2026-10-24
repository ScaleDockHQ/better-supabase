-- better-supabase module: relations
-- @bsb-block relations@1 managed
-- @bsb-hash sha256:a957bb172d5c7ecb169f91e34da2df6a9ca2286b3c7a3ff31b57c7b518dc6333
-- Typed links between subjects (blocks, parent, relates, or your own kinds), with inverse names, cycle checks, one-target kinds, walks and rollups.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."relations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."relations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null,
  "source_type" text not null,
  "source_id" text not null,
  "target_type" text not null,
  "target_id" text not null,
  "data" jsonb not null default '{}'::jsonb check (jsonb_typeof("data") = 'object' and pg_column_size("data") <= 8192),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id"),
  check (not ("source_type" = "target_type" and "source_id" = "target_id"))
);
create index if not exists relations_target_idx on "better_supabase"."relations" ("tenant_id", "target_type", "target_id", "kind");
alter table "better_supabase"."relations" enable row level security;
revoke all on "better_supabase"."relations" from anon, authenticated;
grant select on "better_supabase"."relations" to authenticated;
grant all on "better_supabase"."relations" to service_role;

drop policy if exists relations_read on "better_supabase"."relations";
create policy relations_read on "better_supabase"."relations" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('relations.read')));

-- Links two subjects. An inverse name (blocked_by) stores the link from the
-- other end. Acyclic kinds take an advisory lock per tenant and kind, then
-- refuse a link whose target already reaches its source.
drop function if exists "better_supabase"."link"(uuid, text, text, text, text, text, jsonb, jsonb);
create or replace function "better_supabase"."link"(tenant uuid, kind text, source_type text, source_id text, target_type text, target_id text, data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = link.kind;
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
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.source_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
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
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (link.target_id)::uuid and s."tenant_id" = link.tenant) and coalesce(better_supabase.can('tenant', link.tenant, 'hiring.read'), false)
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
$$;
revoke execute on function "better_supabase"."link"(uuid, text, text, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."link"(uuid, text, text, text, text, text, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."unlink"(tenant uuid, kind text, source_type text, source_id text, target_type text, target_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = unlink.kind;
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
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.source_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
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
    when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'drive.read'), false)
    when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (unlink.target_id)::uuid and s."tenant_id" = unlink.tenant) and coalesce(better_supabase.can('tenant', unlink.tenant, 'hiring.read'), false)
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
$$;
revoke execute on function "better_supabase"."unlink"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."unlink"(uuid, text, text, text, text, text) to authenticated, service_role;

-- A subject's links in both directions, each named from the subject's side.
create or replace function "better_supabase"."relations_of"(tenant uuid, subject_type text, subject_id text, kind text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e.id, 'kind', n.seen, 'direction', e.direction,
    'type', e.other_type, 'subjectId', e.other_id,
    'data', e.data, 'createdAt', e.created_at
  ) order by n.seen, e.created_at, e.id), '[]'::jsonb)
  from (
    select r."id" as id, r."kind" as canonical, 'out' as direction,
      r."target_type" as other_type, r."target_id" as other_id, r."data" as data, r."created_at" as created_at
    from "better_supabase"."relations" r
    where r."tenant_id" = relations_of.tenant and r."source_type" = relations_of.subject_type and r."source_id" = relations_of.subject_id
    union all
    select r."id", r."kind", 'in', r."source_type", r."source_id", r."data", r."created_at"
    from "better_supabase"."relations" r
    where r."tenant_id" = relations_of.tenant and r."target_type" = relations_of.subject_type and r."target_id" = relations_of.subject_id
  ) e
  cross join lateral (
    select case when e.direction = 'in' and not k.both_ways then k.opposite else k.canonical end as seen
    from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite)
    where k.name = e.canonical
  ) n
  where relations_of.kind is null or n.seen = relations_of.kind
$$;
revoke execute on function "better_supabase"."relations_of"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."relations_of"(uuid, text, text, text) to authenticated, service_role;

-- Every link of one kind in a tenant, for a Gantt chart or a tree.
create or replace function "better_supabase"."relations_by_kind"(tenant uuid, kind text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'kind', r."kind",
    'sourceType', r."source_type", 'sourceId', r."source_id",
    'targetType', r."target_type", 'targetId', r."target_id",
    'data', r."data"
  ) order by r."created_at", r."id"), '[]'::jsonb)
  from (
    select * from "better_supabase"."relations" r
    where r."tenant_id" = relations_by_kind.tenant
      and r."kind" = (select k.canonical from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = relations_by_kind.kind)
    order by r."created_at", r."id"
    limit 10000
  ) r
$$;
revoke execute on function "better_supabase"."relations_by_kind"(uuid, text) from public, anon;
grant execute on function "better_supabase"."relations_by_kind"(uuid, text) to authenticated, service_role;

-- Every record a subject reaches through links of one kind, with its depth.
-- up follows source to target (a parent's parents); down follows target to source.
create or replace function "better_supabase"."relation_walk"(tenant uuid, kind text, subject_type text, subject_id text, up boolean, max_depth integer)
returns table (type text, id text, depth integer)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_kind text;
  v_inverted boolean;
  v_up boolean;
begin
  select k.canonical, k.inverted into v_kind, v_inverted from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = relation_walk.kind;
  if v_kind is null then
    raise exception 'unknown relation kind' using errcode = '22023', hint = 'RELATION_KIND_UNKNOWN';
  end if;
  v_up := relation_walk.up <> v_inverted;
  return query
  with recursive walk(t, i, d) as (
    select relation_walk.subject_type, relation_walk.subject_id, 0
    union
    select case when v_up then r."target_type" else r."source_type" end,
      case when v_up then r."target_id" else r."source_id" end,
      walk.d + 1
    from "better_supabase"."relations" r join walk on (
      case when v_up then r."source_type" = walk.t and r."source_id" = walk.i
      else r."target_type" = walk.t and r."target_id" = walk.i end)
    where r."tenant_id" = relation_walk.tenant and r."kind" = v_kind
      and walk.d < least(coalesce(relation_walk.max_depth, 100), 100)
  )
  select w.t, w.i, min(w.d)::integer from walk w where w.d > 0
  group by w.t, w.i
  order by min(w.d), w.t, w.i;
end;
$$;
revoke execute on function "better_supabase"."relation_walk"(uuid, text, text, text, boolean, integer) from public, anon;
grant execute on function "better_supabase"."relation_walk"(uuid, text, text, text, boolean, integer) to authenticated, service_role;

create or replace function "better_supabase"."ancestors"(tenant uuid, kind text, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('type', w.type, 'id', w.id, 'depth', w.depth) order by w.depth, w.type, w.id), '[]'::jsonb)
  from "better_supabase"."relation_walk"(ancestors.tenant, ancestors.kind, ancestors.subject_type, ancestors.subject_id, true, null) w
$$;
revoke execute on function "better_supabase"."ancestors"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."ancestors"(uuid, text, text, text) to authenticated, service_role;

create or replace function "better_supabase"."descendants"(tenant uuid, kind text, subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('type', w.type, 'id', w.id, 'depth', w.depth) order by w.depth, w.type, w.id), '[]'::jsonb)
  from "better_supabase"."relation_walk"(descendants.tenant, descendants.kind, descendants.subject_type, descendants.subject_id, false, null) w
$$;
revoke execute on function "better_supabase"."descendants"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."descendants"(uuid, text, text, text) to authenticated, service_role;

-- The record of into_type an origin was already converted into: the source
-- of a created_from link whose target is the origin. Conversions call it
-- first, so converting the same deal twice returns the first quote.
create or replace function "better_supabase"."converted_into"(tenant uuid, origin_type text, origin_id text, into_type text)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select r."source_id"
  from "better_supabase"."relations" r
  where r."tenant_id" = converted_into.tenant
    and r."kind" = (select k.canonical from (values ('blocks', 'blocks', false, true, false, false, 'blocked_by'), ('blocked_by', 'blocks', true, true, false, false, 'blocks'), ('parent', 'parent', false, true, true, false, 'children'), ('children', 'parent', true, true, true, false, 'parent'), ('relates', 'relates', false, false, false, true, 'relates'), ('created_from', 'created_from', false, true, true, false, 'converted_to'), ('converted_to', 'created_from', true, true, true, false, 'created_from')) as k(name, canonical, inverted, acyclic, single, both_ways, opposite) where k.name = 'created_from')
    and r."target_type" = converted_into.origin_type and r."target_id" = converted_into.origin_id
    and r."source_type" = converted_into.into_type
  order by r."created_at", r."id"
  limit 1
$$;
revoke execute on function "better_supabase"."converted_into"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."converted_into"(uuid, text, text, text) to authenticated, service_role;

-- Aggregates a column over a subject's descendants of one type, such as the
-- sum of estimates under an epic. Runs as the caller, so the subject table's
-- policies decide which rows count. agg is count, sum, avg, min or max.
create or replace function "better_supabase"."relation_rollup"(tenant uuid, kind text, subject_type text, subject_id text, of_type text, column_name text, agg text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_table text;
  v_id_col text;
  v_tenant_col text;
  v_ids text[];
  v_result jsonb;
begin
  if relation_rollup.agg is null or relation_rollup.agg not in ('count', 'sum', 'avg', 'min', 'max') then
    raise exception 'agg must be count, sum, avg, min or max' using errcode = '22023', hint = 'RELATION_ROLLUP_INVALID';
  end if;
  if relation_rollup.agg <> 'count' and relation_rollup.column_name is null then
    raise exception 'this aggregate needs a column' using errcode = '22023', hint = 'RELATION_ROLLUP_INVALID';
  end if;
  case relation_rollup.of_type
    when 'message' then v_table := '"better_supabase"."messages"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'conversation' then v_table := '"better_supabase"."conversations"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'channel' then v_table := '"better_supabase"."channels"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'company' then v_table := '"better_supabase"."companies"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'person' then v_table := '"better_supabase"."people"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'deal' then v_table := '"better_supabase"."deals"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'course' then v_table := '"better_supabase"."courses"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'post' then v_table := '"better_supabase"."posts"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'engagement' then v_table := '"better_supabase"."engagements"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'quote' then v_table := '"better_supabase"."quotes"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'work_item' then v_table := '"better_supabase"."work_items"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'employee' then v_table := '"better_supabase"."employees"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'invoice' then v_table := '"better_supabase"."invoices"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'ledger_account' then v_table := '"better_supabase"."ledger_accounts"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'product' then v_table := '"better_supabase"."products"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'product_variant' then v_table := '"better_supabase"."product_variants"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'order' then v_table := '"better_supabase"."orders"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'calendar_event' then v_table := '"better_supabase"."calendar_events"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'booking' then v_table := '"better_supabase"."bookings"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'asset' then v_table := '"better_supabase"."assets"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'asset_location' then v_table := '"better_supabase"."asset_locations"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'lease' then v_table := '"better_supabase"."lease_agreements"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'expense_report' then v_table := '"better_supabase"."expense_reports"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'expense_line' then v_table := '"better_supabase"."expense_lines"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'donation_fund' then v_table := '"better_supabase"."donation_funds"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'work_order' then v_table := '"better_supabase"."work_orders"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'shipment' then v_table := '"better_supabase"."shipments"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'contract' then v_table := '"better_supabase"."contracts"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'control' then v_table := '"better_supabase"."controls"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'policy' then v_table := '"better_supabase"."policies"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'incident' then v_table := '"better_supabase"."incidents"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'content_entry' then v_table := '"better_supabase"."content_entries"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'form' then v_table := '"better_supabase"."forms"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'document' then v_table := '"better_supabase"."documents"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'customer' then v_table := '"public"."customers"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    when 'drive_node' then v_table := '"better_supabase"."drive_nodes"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'application' then v_table := '"better_supabase"."applications"'; v_id_col := 'id'; v_tenant_col := 'tenant_id';
    when 'project' then v_table := '"public"."projects"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    when 'task' then v_table := '"public"."tasks"'; v_id_col := 'id'; v_tenant_col := 'organization_id';
    else null;
  end case;
  if v_table is null then
    raise exception 'this subject type has no table' using errcode = '22023', hint = 'RELATION_SUBJECT_UNKNOWN';
  end if;
  select array_agg(w.id) into v_ids
  from "better_supabase"."relation_walk"(relation_rollup.tenant, relation_rollup.kind, relation_rollup.subject_type, relation_rollup.subject_id, false, null) w
  where w.type = relation_rollup.of_type;
  execute format(
    'select to_jsonb(%s) from %s s where s.%I::text = any ($1)%s',
    case when relation_rollup.agg = 'count' and relation_rollup.column_name is null then 'count(*)'
      else format('%s(s.%I)', relation_rollup.agg, relation_rollup.column_name) end,
    v_table,
    v_id_col,
    case when v_tenant_col is null then '' else format(' and s.%I = $2', v_tenant_col) end
  ) into v_result using coalesce(v_ids, '{}'::text[]), relation_rollup.tenant;
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."relation_rollup"(uuid, text, text, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."relation_rollup"(uuid, text, text, text, text, text, text) to authenticated, service_role;

-- on with cascade: deleting a subject row deletes its relations rows.
create or replace function "better_supabase"."relations_subject_deleted"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text := tg_argv[0];
  v_id text := to_jsonb(old) ->> tg_argv[1];
begin
  delete from "better_supabase"."relations"
  where ("source_type" = v_type and "source_id" = v_id)
     or ("target_type" = v_type and "target_id" = v_id);
  return null;
end;
$$;
revoke execute on function "better_supabase"."relations_subject_deleted"() from public, anon, authenticated;

drop trigger if exists "bsb_relations_product_cascade" on "better_supabase"."products";
create trigger "bsb_relations_product_cascade"
  after delete on "better_supabase"."products"
  for each row execute function "better_supabase"."relations_subject_deleted"('product', 'id');

drop trigger if exists "bsb_relations_product_variant_cascade" on "better_supabase"."product_variants";
create trigger "bsb_relations_product_variant_cascade"
  after delete on "better_supabase"."product_variants"
  for each row execute function "better_supabase"."relations_subject_deleted"('product_variant', 'id');

-- Moves this module's rows from one subject record to another when
-- better_supabase.merge_subject_refs merges them.
create or replace function "better_supabase"."relations_subject_merge"(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_keep text := keep;
  v_drop text := drop;
begin
  for v_type in select unnest(case subject_table when 'better_supabase.messages' then array['message'] when 'better_supabase.conversations' then array['conversation'] when 'better_supabase.channels' then array['channel'] when 'better_supabase.companies' then array['company'] when 'better_supabase.people' then array['person'] when 'better_supabase.deals' then array['deal'] when 'better_supabase.courses' then array['course'] when 'better_supabase.posts' then array['post'] when 'better_supabase.engagements' then array['engagement'] when 'better_supabase.quotes' then array['quote'] when 'better_supabase.work_items' then array['work_item'] when 'better_supabase.employees' then array['employee'] when 'better_supabase.invoices' then array['invoice'] when 'better_supabase.ledger_accounts' then array['ledger_account'] when 'better_supabase.products' then array['product'] when 'better_supabase.product_variants' then array['product_variant'] when 'better_supabase.orders' then array['order'] when 'better_supabase.calendar_events' then array['calendar_event'] when 'better_supabase.bookings' then array['booking'] when 'better_supabase.assets' then array['asset'] when 'better_supabase.asset_locations' then array['asset_location'] when 'better_supabase.lease_agreements' then array['lease'] when 'better_supabase.expense_reports' then array['expense_report'] when 'better_supabase.expense_lines' then array['expense_line'] when 'better_supabase.donation_funds' then array['donation_fund'] when 'better_supabase.work_orders' then array['work_order'] when 'better_supabase.shipments' then array['shipment'] when 'better_supabase.contracts' then array['contract'] when 'better_supabase.controls' then array['control'] when 'better_supabase.policies' then array['policy'] when 'better_supabase.incidents' then array['incident'] when 'better_supabase.content_entries' then array['content_entry'] when 'better_supabase.forms' then array['form'] when 'better_supabase.documents' then array['document'] when 'public.customers' then array['customer'] when 'better_supabase.drive_nodes' then array['drive_node'] when 'better_supabase.applications' then array['application'] when 'public.projects' then array['project'] when 'public.tasks' then array['task'] else '{}'::text[] end) loop
    declare
      v_row record;
      v_st text; v_si text; v_tt text; v_ti text;
    begin
      for v_row in
        select x."id" as id, x."tenant_id"::text as tenant, x."kind" as kind, x."source_type" as st, x."source_id" as si, x."target_type" as tt, x."target_id" as ti
        from "better_supabase"."relations" x
        where (x."source_type" = v_type and x."source_id" = v_drop) or (x."target_type" = v_type and x."target_id" = v_drop)
        for update
      loop
        v_st := v_row.st; v_tt := v_row.tt;
        v_si := case when v_row.st = v_type and v_row.si = v_drop then v_keep else v_row.si end;
        v_ti := case when v_row.tt = v_type and v_row.ti = v_drop then v_keep else v_row.ti end;
        if v_row.kind in ('relates') and (v_st, v_si) > (v_tt, v_ti) then
          select v_tt, v_ti, v_st, v_si into v_st, v_si, v_tt, v_ti;
        end if;
        if (v_st = v_tt and v_si = v_ti) or exists (
          select 1 from "better_supabase"."relations" y
          where y."id" <> v_row.id and y."tenant_id"::text = v_row.tenant and y."kind" = v_row.kind
            and y."source_type" = v_st and y."source_id" = v_si and y."target_type" = v_tt and y."target_id" = v_ti
        ) then
          delete from "better_supabase"."relations" y where y."id" = v_row.id;
        else
          update "better_supabase"."relations" y set "source_type" = v_st, "source_id" = v_si, "target_type" = v_tt, "target_id" = v_ti
          where y."id" = v_row.id;
        end if;
      end loop;
    end;
  end loop;
end;
$$;
revoke execute on function "better_supabase"."relations_subject_merge"(text, text, text) from public, anon, authenticated;
comment on function "better_supabase"."relations_subject_merge"(text, text, text) is 'better-supabase:subject-merge';

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
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
drop policy if exists bsb_tenant_scope on "better_supabase"."relations";
create policy bsb_tenant_scope on "better_supabase"."relations" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('relations.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.relations.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."link"(uuid, text, text, text, text, text, jsonb, jsonb);

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

create or replace function "api"."link"(tenant uuid, kind text, source_type text, source_id text, target_type text, target_id text, data jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."link"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."link"(uuid, text, text, text, text, text, jsonb) from public, anon;
grant execute on function "api"."link"(uuid, text, text, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."unlink"(tenant uuid, kind text, source_type text, source_id text, target_type text, target_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unlink"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."unlink"(uuid, text, text, text, text, text) from public, anon;
grant execute on function "api"."unlink"(uuid, text, text, text, text, text) to authenticated, service_role;

create or replace function "api"."relations_of"(tenant uuid, subject_type text, subject_id text, kind text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."relations_of"($1, $2, $3, $4) $$;
revoke execute on function "api"."relations_of"(uuid, text, text, text) from public, anon;
grant execute on function "api"."relations_of"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."relations_by_kind"(tenant uuid, kind text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."relations_by_kind"($1, $2) $$;
revoke execute on function "api"."relations_by_kind"(uuid, text) from public, anon;
grant execute on function "api"."relations_by_kind"(uuid, text) to authenticated, service_role;

create or replace function "api"."relation_walk"(tenant uuid, kind text, subject_type text, subject_id text, up boolean, max_depth integer)
returns table (type text, id text, depth integer)
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."relation_walk"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."relation_walk"(uuid, text, text, text, boolean, integer) from public, anon;
grant execute on function "api"."relation_walk"(uuid, text, text, text, boolean, integer) to authenticated, service_role;

create or replace function "api"."ancestors"(tenant uuid, kind text, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."ancestors"($1, $2, $3, $4) $$;
revoke execute on function "api"."ancestors"(uuid, text, text, text) from public, anon;
grant execute on function "api"."ancestors"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."descendants"(tenant uuid, kind text, subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."descendants"($1, $2, $3, $4) $$;
revoke execute on function "api"."descendants"(uuid, text, text, text) from public, anon;
grant execute on function "api"."descendants"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."converted_into"(tenant uuid, origin_type text, origin_id text, into_type text)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."converted_into"($1, $2, $3, $4) $$;
revoke execute on function "api"."converted_into"(uuid, text, text, text) from public, anon;
grant execute on function "api"."converted_into"(uuid, text, text, text) to authenticated, service_role;

create or replace function "api"."relation_rollup"(tenant uuid, kind text, subject_type text, subject_id text, of_type text, column_name text, agg text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."relation_rollup"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."relation_rollup"(uuid, text, text, text, text, text, text) from public, anon;
grant execute on function "api"."relation_rollup"(uuid, text, text, text, text, text, text) to authenticated, service_role;

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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;
