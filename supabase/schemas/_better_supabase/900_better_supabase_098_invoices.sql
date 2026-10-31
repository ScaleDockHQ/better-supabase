-- better-supabase module: invoices
-- @bsb-block invoices@2 managed
-- @bsb-hash sha256:d8f7de863c47fdabe2a1925336de1078a8c9fd4c88571f717f512927f1e30c4b
-- Invoices an organization sends its own customers and bills from its suppliers: drafts with lines, a gapless number per direction on issue, payments, credit notes, void and write-off, overdue and aging per currency, credit limits, the three-way match of a purchase bill, party payments split over invoices with the rest kept as credit, dunning levels, and invoices from accepted quotes.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.import_run()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when nullif(current_setting('better_supabase.import_run', true), '') is not null and coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')
    then nullif(current_setting('better_supabase.import_run', true), '')::uuid
  end;
$$;
revoke execute on function better_supabase.import_run() from public;
grant execute on function better_supabase.import_run() to anon, authenticated, service_role;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoices";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoices";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoices";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoices";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoices";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_charges";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_charges";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_charges";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_charges";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_charges";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_dunning_levels";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_dunning_levels";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_levels";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_dunning_levels";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_levels";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Invoices an organization sends its own customers and the bills its
-- suppliers send it: drafts with lines, a number on issue, payments, credit
-- notes, void and write-off, aging and the three-way match of a bill.

create table if not exists "better_supabase"."invoices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "kind" text not null default 'invoice' check ("kind" in ('invoice', 'credit_note')),
  "number" bigint,
  "identifier" text,
  "original_id" uuid references "better_supabase"."invoices" ("id"),
  "title" text not null check (length("title") between 1 and 300),
  "company_type" text,
  "company_id" text,
  "contact_type" text,
  "contact_id" text,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible')),
  "terms_days" integer not null default 30 check ("terms_days" >= 0),
  "issued_on" date,
  "due_on" date,
  "paid_total" bigint not null default 0,
  "credited_total" bigint not null default 0,
  "paid_at" timestamptz,
  "voided_at" timestamptz,
  "void_reason" text,
  "note" text,
  "origin_type" text,
  "origin_id" text,
  "deposit_bps" integer check ("deposit_bps" > 0 and "deposit_bps" < 10000),
  "prices_include_tax" boolean not null default false,
  "direction" text not null default 'sales' check ("direction" in ('sales', 'purchase')),
  "supplier_reference" text check (length("supplier_reference") <= 200),
  "purchase_order_id" uuid,
  "dimensions" jsonb not null default '{}'::jsonb check (jsonb_typeof("dimensions") = 'object'),
  "dunning_level" integer not null default 0,
  "dunning_at" timestamptz,
  "dunning_paused_until" date,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "list_total" bigint not null default 0,
  "discount_total" bigint not null default 0,
  "subtotal" bigint not null default 0,
  "tax_total" bigint not null default 0,
  "total" bigint not null default 0,
  unique ("tenant_id", "direction", "kind", "number"),
  check (("kind" = 'credit_note') = ("original_id" is not null)),
  check ("status" <> 'draft' or "number" is null),
  check ("status" in ('draft', 'void') or "number" is not null),
  check (("company_type" is null) = ("company_id" is null))
);
alter table "better_supabase"."invoices" add column if not exists "deposit_amount" bigint check ("deposit_amount" > 0);
alter table "better_supabase"."invoices" add column if not exists "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000);
alter table "better_supabase"."invoices" add column if not exists "discount_amount" bigint not null default 0 check ("discount_amount" >= 0);
create index if not exists invoices_tenant_status_idx on "better_supabase"."invoices" ("tenant_id", "status", "due_on");
create index if not exists invoices_origin_idx on "better_supabase"."invoices" ("origin_type", "origin_id");
create index if not exists invoices_original_idx on "better_supabase"."invoices" ("original_id");
create index if not exists invoices_company_idx on "better_supabase"."invoices" ("company_type", "company_id");
create index if not exists invoices_purchase_order_idx on "better_supabase"."invoices" ("purchase_order_id");
alter table "better_supabase"."invoices" enable row level security;
revoke all on "better_supabase"."invoices" from public, anon, authenticated;
grant select on "better_supabase"."invoices" to authenticated;
grant all on "better_supabase"."invoices" to service_role;
drop policy if exists invoices_read on "better_supabase"."invoices";
create policy invoices_read on "better_supabase"."invoices"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read'))) or (("tenant_id")::text, ('invoice')::text, ("id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or (("tenant_id")::text, ("company_type")::text, ("company_id"::text)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g) or (("tenant_id")::text, ("contact_type")::text, ("contact_id"::text)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g));

create table if not exists "better_supabase"."invoice_charges" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "description" text check (length("description") <= 2000),
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists invoice_charges_invoice_idx on "better_supabase"."invoice_charges" ("invoice_id");
alter table "better_supabase"."invoice_charges" enable row level security;
revoke all on "better_supabase"."invoice_charges" from public, anon, authenticated;
grant select on "better_supabase"."invoice_charges" to authenticated;
grant all on "better_supabase"."invoice_charges" to service_role;
drop policy if exists invoice_charges_read on "better_supabase"."invoice_charges";
create policy invoice_charges_read on "better_supabase"."invoice_charges"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."invoices" x where x."id" = "invoice_id"));

create table if not exists "better_supabase"."invoice_dunning_levels" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "level" integer not null check ("level" between 1 and 20),
  "days_after_due" integer not null check ("days_after_due" >= 0),
  "template_key" text not null check (length("template_key") between 1 and 200),
  "fee" bigint not null default 0 check ("fee" >= 0),
  "final" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "level")
);
alter table "better_supabase"."invoice_dunning_levels" enable row level security;
revoke all on "better_supabase"."invoice_dunning_levels" from public, anon, authenticated;
grant select on "better_supabase"."invoice_dunning_levels" to authenticated;
grant all on "better_supabase"."invoice_dunning_levels" to service_role;
drop policy if exists invoice_dunning_levels_read on "better_supabase"."invoice_dunning_levels";
create policy invoice_dunning_levels_read on "better_supabase"."invoice_dunning_levels"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));


-- Creates a draft invoice. attrs: title (required), currency, company and
-- contact ({ type, id }), termsDays, note, origin ({ type, id }) and the
-- extra columns by name, with depositAmount and the header discount (discountBps,
-- discountAmount) when the table has them.
create or replace function "better_supabase"."create_invoice"(tenant uuid, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_company_type text := coalesce(create_invoice.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_invoice.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_invoice.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_invoice.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_invoice.tenant, case when create_invoice.attrs ->> 'direction' = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if nullif(trim(create_invoice.attrs ->> 'title'), '') is null then
    raise exception 'an invoice needs a title' using errcode = '23502', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if create_invoice.attrs ->> 'purchaseOrderId' is not null then
    if create_invoice.attrs ->> 'direction' is distinct from 'purchase' then
      raise exception 'only a purchase bill refers to a purchase order' using errcode = '22023', hint = 'INVOICE_PURCHASE_ORDER_INVALID';
    end if;
    if not exists (select 1 from "better_supabase"."purchase_orders" y where y."id"::text = (create_invoice.attrs ->> 'purchaseOrderId') and y."tenant_id" = create_invoice.tenant) then
      raise exception 'no such purchase order in this organization' using errcode = 'P0002', hint = 'INVOICE_PURCHASE_ORDER_NOT_FOUND';
    end if;
  end if;
  if create_invoice.attrs ? 'dimensions' and jsonb_typeof(create_invoice.attrs -> 'dimensions') not in ('object', 'null') then
    raise exception 'dimensions is an object of dimension keys and value codes' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = create_invoice.tenant::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = create_invoice.tenant::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_CONTACT_FORBIDDEN';
  end if;
  begin
    insert into "better_supabase"."invoices" ("tenant_id", "title", "company_type", "company_id", "contact_type", "contact_id", "currency",
      "terms_days", "note", "origin_type", "origin_id", "deposit_bps", "deposit_amount", "discount_bps", "discount_amount", "prices_include_tax", "direction", "supplier_reference", "purchase_order_id", "dimensions", "created_by")
    values (create_invoice.tenant, trim(create_invoice.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      upper(coalesce(create_invoice.attrs ->> 'currency', 'EUR')), case when create_invoice.attrs ? 'termsDays' then (create_invoice.attrs ->> 'termsDays')::integer else 30 end,
      create_invoice.attrs ->> 'note', create_invoice.attrs -> 'origin' ->> 'type', create_invoice.attrs -> 'origin' ->> 'id',
      (create_invoice.attrs ->> 'depositBps')::integer, (create_invoice.attrs ->> 'depositAmount')::bigint, coalesce((create_invoice.attrs ->> 'discountBps')::integer, 0), coalesce((create_invoice.attrs ->> 'discountAmount')::bigint, 0), coalesce((create_invoice.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce(create_invoice.attrs ->> 'direction', 'sales'), nullif(trim(create_invoice.attrs ->> 'supplierReference'), ''), (create_invoice.attrs ->> 'purchaseOrderId')::uuid, coalesce(nullif(create_invoice.attrs -> 'dimensions', 'null'::jsonb), '{}'::jsonb), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'an invoice field has an invalid value' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end;
  if create_invoice.lines is not null then
    perform "better_supabase"."set_invoice_lines"(v_row."id", create_invoice.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'invoice', v_row."id"::text, v_row."origin_type", v_row."origin_id"::text, auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'invoice' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('invoice.created', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_invoice"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_invoice"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft's header. attrs: title, company and contact ({ type, id },
-- null clears), termsDays, note, depositBps, pricesIncludeTax and the extra
-- columns by name, and the header discount (discountBps, discountAmount). A key left out keeps its value.
create or replace function "better_supabase"."update_invoice"(invoice uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_company_type text := coalesce(update_invoice.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := update_invoice.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(update_invoice.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := update_invoice.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = update_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft changes' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  if jsonb_typeof(update_invoice.attrs) is distinct from 'object'
    or (update_invoice.attrs ? 'title' and nullif(trim(update_invoice.attrs ->> 'title'), '') is null) then
    raise exception 'attrs is an object, and a title isn''t empty' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if update_invoice.attrs ->> 'purchaseOrderId' is not null then
    if v_row."direction" is distinct from 'purchase' then
      raise exception 'only a purchase bill refers to a purchase order' using errcode = '22023', hint = 'INVOICE_PURCHASE_ORDER_INVALID';
    end if;
    if not exists (select 1 from "better_supabase"."purchase_orders" y where y."id"::text = (update_invoice.attrs ->> 'purchaseOrderId') and y."tenant_id" = v_row."tenant_id") then
      raise exception 'no such purchase order in this organization' using errcode = 'P0002', hint = 'INVOICE_PURCHASE_ORDER_NOT_FOUND';
    end if;
  end if;
  if update_invoice.attrs ? 'dimensions' and jsonb_typeof(update_invoice.attrs -> 'dimensions') not in ('object', 'null') then
    raise exception 'dimensions is an object of dimension keys and value codes' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not (case v_company_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_company_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_company_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_company_type, v_company_id, 'read')) then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not (case v_contact_type
      when 'message' then exists (select 1 from "better_supabase"."messages" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'conversation' then exists (select 1 from "better_supabase"."conversations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'channel' then exists (select 1 from "better_supabase"."channels" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'company' then exists (select 1 from "better_supabase"."companies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'person' then exists (select 1 from "better_supabase"."people" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'deal' then exists (select 1 from "better_supabase"."deals" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'course' then exists (select 1 from "better_supabase"."courses" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'post' then exists (select 1 from "better_supabase"."posts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'activity' then exists (select 1 from "better_supabase"."activities" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'quote' then exists (select 1 from "better_supabase"."quotes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_item' then exists (select 1 from "better_supabase"."work_items" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'employee' then exists (select 1 from "better_supabase"."employees" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'invoice' then exists (select 1 from "better_supabase"."invoices" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'ledger_account' then exists (select 1 from "better_supabase"."ledger_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product' then exists (select 1 from "better_supabase"."products" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'product_variant' then exists (select 1 from "better_supabase"."product_variants" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'order' then exists (select 1 from "better_supabase"."orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'calendar_event' then exists (select 1 from "better_supabase"."calendar_events" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'booking' then exists (select 1 from "better_supabase"."bookings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset' then exists (select 1 from "better_supabase"."assets" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'asset_location' then exists (select 1 from "better_supabase"."asset_locations" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'lease' then exists (select 1 from "better_supabase"."leases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_report' then exists (select 1 from "better_supabase"."expense_reports" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'expense_line' then exists (select 1 from "better_supabase"."expense_lines" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'donation_fund' then exists (select 1 from "better_supabase"."donation_funds" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_order' then exists (select 1 from "better_supabase"."work_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'shipment' then exists (select 1 from "better_supabase"."shipments" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'contract' then exists (select 1 from "better_supabase"."contracts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'control' then exists (select 1 from "better_supabase"."controls" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'compliance_policy' then exists (select 1 from "better_supabase"."compliance_policies" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'qualification_type' then exists (select 1 from "better_supabase"."qualification_types" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'risk' then exists (select 1 from "better_supabase"."risks" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'case' then exists (select 1 from "better_supabase"."cases" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection' then exists (select 1 from "better_supabase"."inspections" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_program' then exists (select 1 from "better_supabase"."inspection_programs" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'inspection_finding' then exists (select 1 from "better_supabase"."inspection_findings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'form' then exists (select 1 from "better_supabase"."forms" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting' then exists (select 1 from "better_supabase"."meetings" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'meeting_decision' then exists (select 1 from "better_supabase"."meeting_decisions" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'production_order' then exists (select 1 from "better_supabase"."production_orders" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'work_center' then exists (select 1 from "better_supabase"."work_centers" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'bank_account' then exists (select 1 from "better_supabase"."bank_accounts" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'care_plan' then exists (select 1 from "better_supabase"."care_plans" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'incident' then exists (select 1 from "better_supabase"."incidents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'content_entry' then exists (select 1 from "better_supabase"."content_entries" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'document' then exists (select 1 from "better_supabase"."documents" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'customer' then exists (select 1 from "public"."customers" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'drive_node' then exists (select 1 from "better_supabase"."drive_nodes" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'application' then exists (select 1 from "better_supabase"."applications" s where s."id" = (v_contact_id)::uuid and s."tenant_id"::text = v_row."tenant_id"::text)
      when 'change_request' then exists (select 1 from "public"."change_requests" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'project' then exists (select 1 from "public"."projects" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      when 'task' then exists (select 1 from "public"."tasks" s where s."id" = (v_contact_id)::uuid and s."organization_id"::text = v_row."tenant_id"::text)
      else false
    end and "better_supabase"."can_subject"(v_contact_type, v_contact_id, 'read')) then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."invoices" x set
      "title" = case when update_invoice.attrs ? 'title' then trim(update_invoice.attrs ->> 'title') else x."title" end,
      "company_type" = case when update_invoice.attrs ? 'company' then case when v_company_id is null then null else v_company_type end else x."company_type" end,
      "company_id" = case when update_invoice.attrs ? 'company' then v_company_id else x."company_id" end,
      "contact_type" = case when update_invoice.attrs ? 'contact' then case when v_contact_id is null then null else v_contact_type end else x."contact_type" end,
      "contact_id" = case when update_invoice.attrs ? 'contact' then v_contact_id else x."contact_id" end,
      "terms_days" = case when update_invoice.attrs ? 'termsDays' then (update_invoice.attrs ->> 'termsDays')::integer else x."terms_days" end,
      "note" = case when update_invoice.attrs ? 'note' then update_invoice.attrs ->> 'note' else x."note" end,
      "deposit_bps" = case when update_invoice.attrs ? 'depositBps' then (update_invoice.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "prices_include_tax" = case when update_invoice.attrs ? 'pricesIncludeTax' then coalesce((update_invoice.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "deposit_amount" = case when update_invoice.attrs ? 'depositAmount' then (update_invoice.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "discount_bps" = case when update_invoice.attrs ? 'discountBps' then coalesce((update_invoice.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_invoice.attrs ? 'discountAmount' then coalesce((update_invoice.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "supplier_reference" = case when update_invoice.attrs ? 'supplierReference' then nullif(trim(update_invoice.attrs ->> 'supplierReference'), '') else x."supplier_reference" end,
      "purchase_order_id" = case when update_invoice.attrs ? 'purchaseOrderId' then (update_invoice.attrs ->> 'purchaseOrderId')::uuid else x."purchase_order_id" end,
      "dimensions" = case when update_invoice.attrs ? 'dimensions' then coalesce(nullif(update_invoice.attrs -> 'dimensions', 'null'::jsonb), '{}'::jsonb) else x."dimensions" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or not_null_violation or numeric_value_out_of_range then
    raise exception 'an invoice field has an invalid value' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end;
  if update_invoice.attrs ? 'pricesIncludeTax' or update_invoice.attrs ? 'discountBps' or update_invoice.attrs ? 'discountAmount' then
    perform "better_supabase"."set_invoice_lines_recount"(v_row."id");
  end if;
  perform "better_supabase".emit_event('invoice.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."update_invoice"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_invoice"(uuid, jsonb) to authenticated, service_role;

-- Deletes a draft with its lines and charges. An issued invoice is voided instead.
create or replace function "better_supabase"."delete_invoice"(invoice uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = delete_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can delete' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft is deleted; void an issued invoice' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  delete from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id";
  delete from "better_supabase"."invoice_lines" y where y."parent_id" = v_row."id";
  delete from "better_supabase"."relations" y
  where y."kind" = 'created_from' and y."source_type" = 'invoice' and y."source_id" = v_row."id"::text;
  delete from "better_supabase"."invoices" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('invoice.deleted', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_invoice"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_invoice"(uuid) to authenticated, service_role;
create table if not exists "better_supabase"."invoice_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "product_type" text,
  "product_id" text,
  "description" text not null check (length("description") between 1 and 2000),
  "quantity" numeric(18, 4) not null check ("quantity" > 0),
  "unit_amount" bigint not null,
  "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000),
  "tax_rate_bps" integer not null default 0 check ("tax_rate_bps" >= 0 and "tax_rate_bps" <= 100000),
  "tax_code" text,
  "position" integer not null,
  "created_at" timestamptz not null default now(),
  check (("product_type" is null) = ("product_id" is null))
);
create index if not exists "invoice_lines_parent_idx" on "better_supabase"."invoice_lines" ("parent_id", "position");
alter table "better_supabase"."invoice_lines" enable row level security;
revoke all on "better_supabase"."invoice_lines" from public, anon, authenticated;
grant select on "better_supabase"."invoice_lines" to authenticated;
grant all on "better_supabase"."invoice_lines" to service_role;
drop policy if exists "invoice_lines_read" on "better_supabase"."invoice_lines";
create policy "invoice_lines_read" on "better_supabase"."invoice_lines" for select to authenticated
using (exists (select 1 from "better_supabase"."invoices" x where x."id" = "parent_id"));

-- Writes a record's totals from its counted lines: an optional line counts
-- only when the customer took it. The record discount is spread over the tax
-- rates in proportion to their amounts, and tax is counted once per rate, so
-- the totals and the tax per rate always add up.
create or replace function "better_supabase"."set_invoice_lines_recount"(parent uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_inclusive boolean;
  v_record_bps integer;
  v_record_amount bigint;
  v_list bigint;
  v_line_discount bigint;
  v_net bigint;
  v_record_discount bigint;
  v_groups jsonb;
  v_discount bigint;
  v_subtotal bigint;
  v_tax bigint;
  v_total bigint;
begin
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount"
    into v_tenant, v_inclusive, v_record_bps, v_record_amount
  from "better_supabase"."invoices" x where x."id" = set_invoice_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * l."unit_amount")), 0), coalesce(sum(round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)), 0)
    into v_list, v_line_discount
  from "better_supabase"."invoice_lines" l where l."parent_id" = set_invoice_lines_recount.parent and true;
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)) as amount,
      sum(round((round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)) * l."tax_rate_bps" / case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)) as tax
    from "better_supabase"."invoice_lines" l where l."parent_id" = set_invoice_lines_recount.parent and true
    group by 1, 2
  ), shared as (
    select g.rate, g.code, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first rows between unbounded preceding and current row)
  ), taxed as (
    select s.rate, s.code, s.share, s.amount - s.share as amount,
      s.tax - round(s.share * s.rate / case when v_inclusive then 10000.0 + s.rate else 10000.0 end) as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rate', x.rate,
      'code', x.code,
      'net', case when v_inclusive then x.amount - x.tax else x.amount end,
      'tax', x.tax,
      'discount', x.share,
      'gross', case when v_inclusive then x.amount else x.amount + x.tax end
    ) order by x.rate, x.code nulls first), '[]'::jsonb)
    into v_groups
  from taxed x;
  select coalesce(sum(r.net), 0), coalesce(sum(r.tax), 0), coalesce(sum(r.gross), 0)
    into v_subtotal, v_tax, v_total
  from jsonb_to_recordset(v_groups) r(net bigint, tax bigint, gross bigint);
  v_discount := v_line_discount + v_record_discount;
  update "better_supabase"."invoices" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_subtotal,
    "tax_total" = v_tax,
    "total" = v_total
  where x."id" = set_invoice_lines_recount.parent;
end;
$$;
revoke execute on function "better_supabase"."set_invoice_lines_recount"(uuid) from public, anon, authenticated;

-- Recounts each record a statement touched once, in id order so concurrent
-- statements lock the records in the same order. A transition table needs a
-- trigger per event, so there are three triggers on one function. The
-- transition tables are read through execute because plpgsql_check (db lint)
-- doesn't know them.
create or replace function better_supabase.bsb_invoice_lines_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid;
begin
  for v_parent in execute case tg_op
    when 'INSERT' then 'select distinct n."parent_id" from new_rows n order by 1'
    when 'DELETE' then 'select distinct o."parent_id" from old_rows o order by 1'
    else 'select n."parent_id" from new_rows n union select o."parent_id" from old_rows o order by 1'
  end loop
    perform "better_supabase"."set_invoice_lines_recount"(v_parent);
  end loop;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_invoice_lines_totals() from public, anon, authenticated;
drop trigger if exists bsb_invoice_lines_totals on "better_supabase"."invoice_lines";
drop trigger if exists bsb_invoice_lines_totals_insert on "better_supabase"."invoice_lines";
drop trigger if exists bsb_invoice_lines_totals_update on "better_supabase"."invoice_lines";
drop trigger if exists bsb_invoice_lines_totals_delete on "better_supabase"."invoice_lines";
create trigger bsb_invoice_lines_totals_insert after insert on "better_supabase"."invoice_lines"
referencing new table as new_rows
for each statement execute function better_supabase.bsb_invoice_lines_totals();
create trigger bsb_invoice_lines_totals_update after update on "better_supabase"."invoice_lines"
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.bsb_invoice_lines_totals();
create trigger bsb_invoice_lines_totals_delete after delete on "better_supabase"."invoice_lines"
referencing old table as old_rows
for each statement execute function better_supabase.bsb_invoice_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
create or replace function "better_supabase"."set_invoice_lines"(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := set_invoice_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."invoices" x where x."id" = v_parent and not (x."status" <> 'draft');
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."invoices" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false))) then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_invoice_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_invoice_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."invoice_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1),
      (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0),
      coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode',
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_invoice_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_invoice_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."invoices" x where x."id" = v_parent);
end;
$$;
revoke execute on function "better_supabase"."set_invoice_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_invoice_lines"(uuid, jsonb) to authenticated, service_role;

-- Issues a draft: it gets the next number of its kind (gapless, so a
-- number is only taken when the invoice is final), its issue and due date,
-- and its lines freeze. A credit note reduces the balance of its original.
-- actor: who issued it, for the state machine's history.
drop function if exists "better_supabase"."issue_invoice"(uuid, date);
drop function if exists "better_supabase"."issue_invoice"(uuid, date, date);
create or replace function "better_supabase"."issue_invoice"(invoice uuid, issued_on date, due_on date default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_original "better_supabase"."invoices";
  v_seq bigint;
  v_identifier text;
  v_issued_on date := coalesce(issue_invoice.issued_on, current_date);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'the invoice was already issued' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  if not exists (select 1 from "better_supabase"."invoice_lines" x where x."parent_id" = v_row."id") then
    raise exception 'an invoice needs a line before it is issued' using errcode = '23514', hint = 'INVOICE_EMPTY';
  end if;
  if issue_invoice.due_on < v_issued_on then
    raise exception 'an invoice falls due on or after its issue date' using errcode = '22023', hint = 'INVOICE_DUE_INVALID';
  end if;
  if issue_invoice.actor is not null then
    if jsonb_typeof(issue_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(issue_invoice.actor ->> 'ip', '')::inet, nullif(issue_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(issue_invoice.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  if v_row."kind" = 'credit_note' then
    select * into v_original from "better_supabase"."invoices" x where x."id" = v_row."original_id" for update;
    if v_row."total" > v_original."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_original."id"), 0) - v_original."credited_total" then
      raise exception 'a credit note can''t exceed the invoice''s total less its earlier credits' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
    end if;
    if v_row."direction" = 'purchase' then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_credit_note', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'BCN-' || v_seq::text;
    else
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':credit_note', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'CN-' || v_seq::text;
    end if;
  else
    if v_row."direction" = 'purchase' then
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_bill', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'BILL-' || v_seq::text;
    else
      perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':invoice', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'INV-' || v_seq::text;
    end if;
  end if;
  if v_row."kind" = 'invoice' and not v_row."direction" = 'purchase' and coalesce(v_row."company_id"::text, v_row."contact_id"::text) is not null then
    declare
      v_limit bigint;
    begin
      select s.credit_limit into v_limit from (select p."credit_limit", p."credit_currency" from "better_supabase"."companies" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null union all select p."credit_limit", p."credit_currency" from "better_supabase"."people" p where p."id"::text = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null) s(credit_limit, credit_currency)
      where s.credit_limit is not null and coalesce(s.credit_currency, v_row."currency") = v_row."currency"
      order by s.credit_limit limit 1;
      if v_limit is not null and (select coalesce(sum((o."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = o."id"), 0) - o."credited_total" - o."paid_total")), 0) from "better_supabase"."invoices" o
        where o."tenant_id" = v_row."tenant_id" and o."id" <> v_row."id" and o."currency" = v_row."currency"
          and coalesce(o."company_id"::text, o."contact_id"::text) = coalesce(v_row."company_id"::text, v_row."contact_id"::text) and not o."direction" = 'purchase'
          and o."kind" = 'invoice' and o."status" in ('issued', 'partially_paid')) + v_row."total" > v_limit and not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'orders.override_credit'), false)) then
        raise exception 'this invoice takes the customer over their credit limit' using errcode = '55000', hint = 'INVOICE_CREDIT_LIMIT_EXCEEDED';
      end if;
    end;
  end if;
  update "better_supabase"."invoices" x set "status" = 'issued', "number" = v_seq, "identifier" = v_identifier,
    "issued_on" = v_issued_on,
    "due_on" = coalesce(issue_invoice.due_on, v_issued_on + x."terms_days"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.issued', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'dueOn', v_row."due_on"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."kind" = 'credit_note' then
    update "better_supabase"."invoices" x set "credited_total" = x."credited_total" + v_row."total", "updated_at" = now()
    where x."id" = v_original."id"
    returning * into v_original;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_original."id"
  returning * into v_original;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_original."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_original;
    perform "better_supabase".emit_event('invoice.credited', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'creditNoteId', v_row."id", 'amount', v_row."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    if v_original."status" = 'paid' then
      perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_original."tenant_id", 'invoiceId', v_original."id", 'subjectType', 'invoice', 'subjectId', v_original."id"::text, 'identifier', v_original."identifier", 'total', v_original."total"::text), 'invoices/' || v_original."id"::text, (v_original."tenant_id"::text)::text, null, 'better-supabase/invoices');
    end if;
  end if;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice', v_row."id"::text);
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."issue_invoice"(uuid, date, date, jsonb) from public, anon;
grant execute on function "better_supabase"."issue_invoice"(uuid, date, date, jsonb) to authenticated, service_role;

-- Records a payment (a negative amount is a refund) in the invoice's
-- currency as a ledger transaction from the invoice's receivable account to
-- cash. A reference, such as a bank or payment provider id, is unique per
-- organization, so recording the same payment twice adds it once. actor:
-- who recorded it, and reason: why the status changes, for the state
-- machine's history.
drop function if exists "better_supabase"."record_invoice_payment"(uuid, bigint, timestamptz, text, text);
drop function if exists "better_supabase"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text);
drop function if exists "better_supabase"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text, text);
drop function if exists "better_supabase"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text, text, jsonb);
create or replace function "better_supabase"."record_invoice_payment"(invoice uuid, amount bigint, currency text, paid_at timestamptz, method text, reference text, note text default null, actor jsonb default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_payment uuid;
  v_reference text;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = record_invoice_payment.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice takes payments' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
  end if;
  if coalesce(record_invoice_payment.amount, 0) = 0 then
    raise exception 'a payment has an amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
  end if;
  if upper(record_invoice_payment.currency) is distinct from v_row."currency" then
    raise exception 'a payment must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
  end if;
  if v_row."direction" = 'purchase' and v_row."purchase_order_id" is not null and record_invoice_payment.amount > 0
    and "better_supabase"."invoice_match_result"(v_row."id") ->> 'status' <> 'matched'
    and not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'invoices.override_match'), false)) then
    raise exception 'the bill doesn''t match its purchase order and receipts; someone with invoices.override_match can pay it' using errcode = '55000', hint = 'INVOICE_MATCH_FAILED';
  end if;
  if record_invoice_payment.actor is not null then
    if jsonb_typeof(record_invoice_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(record_invoice_payment.actor ->> 'ip', '')::inet, nullif(record_invoice_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(record_invoice_payment.actor::text, ''), true);
  -- A recorded reference is a replay that adds nothing, so it skips the check.
  v_reference := nullif(trim(record_invoice_payment.reference), '');
  if v_reference is not null and exists (
    select 1 from "better_supabase"."ledger_transactions" y
    where y."tenant_id" = v_row."tenant_id" and y."idempotency_key" = 'invoice-payment:' || v_reference
  ) then
    return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
  end if;
  if record_invoice_payment.amount < 0 and v_row."paid_total" + record_invoice_payment.amount < 0 then
    raise exception 'a refund can''t exceed what was paid' using errcode = '23514', hint = 'INVOICE_REFUND_TOO_LARGE';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_invoice_payment"(uuid, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::bigint)', v_hook::oid::regproc)
        using v_row."id", record_invoice_payment.amount;
    end if;
  end;
  v_was := v_row."status";
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(record_invoice_payment.reason), ''), ''), true);
  v_payment := "better_supabase"."ledger_post"(v_row."tenant_id", case when record_invoice_payment.amount < 0 then 'invoice.refund' else 'invoice.payment' end,
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -record_invoice_payment.amount),
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'cash',
      case when v_row."direction" = 'purchase' then 'invoices:paid:' || v_row."currency" else 'invoices:cash:' || v_row."currency" end, 'Invoice payments ' || v_row."currency",
      v_row."currency"::text, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', record_invoice_payment.amount)),
    'invoices', v_row."id"::text, null,
    case when v_reference is not null then 'invoice-payment:' || v_reference end, coalesce(record_invoice_payment.paid_at, now()),
    jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row."id", 'method', record_invoice_payment.method, 'reference', v_reference, 'note', nullif(trim(record_invoice_payment.note), ''))));
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_payment', v_payment::text);
  end if;
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.payment_recorded', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', v_payment, 'amount', record_invoice_payment.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  if v_row."status" = 'paid' and v_was <> 'paid' then
    perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_payment"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_row."id", v_payment;
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text, text, jsonb, text) to authenticated, service_role;

create or replace function "better_supabase"."list_invoice_payments"(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = list_invoice_payments.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false));
  if v_row."id" is null then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return jsonb_build_object('currency', v_row."currency", 'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."list_invoice_payments"(uuid) from public, anon;
grant execute on function "better_supabase"."list_invoice_payments"(uuid) to authenticated, service_role;

-- A draft credit note against an issued invoice: its lines, or the given
-- lines for a partial credit. Issue it to apply it.
create or replace function "better_supabase"."credit_invoice"(invoice uuid, lines jsonb, note text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_original "better_supabase"."invoices";
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_original from "better_supabase"."invoices" x where x."id" = credit_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false));
  if v_original."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_original."kind" <> 'invoice' or v_original."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice is credited' using errcode = '55000', hint = 'INVOICE_NOT_CREDITABLE';
  end if;
  insert into "better_supabase"."invoices" ("tenant_id", "kind", "original_id", "title", "company_type", "company_id", "contact_type", "contact_id",
    "currency", "terms_days", "note", "prices_include_tax", "direction", "supplier_reference", "purchase_order_id", "dimensions", "created_by")
  values (v_original."tenant_id", 'credit_note', v_original."id", 'Credit for ' || coalesce(v_original."identifier", v_original."title"),
    v_original."company_type", v_original."company_id", v_original."contact_type", v_original."contact_id",
    v_original."currency", 0, nullif(trim(credit_invoice.note), ''), v_original."prices_include_tax", v_original."direction", v_original."supplier_reference", v_original."purchase_order_id", v_original."dimensions", auth.uid())
  returning * into v_row;
  if credit_invoice.lines is null then
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select x."tenant_id", v_row."id", x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."position"
    from "better_supabase"."invoice_lines" x where x."parent_id" = v_original."id";
  else
    perform "better_supabase"."set_invoice_lines"(v_row."id", credit_invoice.lines);
  end if;
  perform "better_supabase".emit_event('invoice.created', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'deposit_amount', x."deposit_amount"::text, 'discount_amount', x."discount_amount"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."credit_invoice"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."credit_invoice"(uuid, jsonb, text) to authenticated, service_role;

-- Voids an invoice without payments: a draft, or an issued one sent in
-- error. Its number stays taken. Needs invoices.manage. The reason and actor
-- go to the state machine's history.
drop function if exists "better_supabase"."void_invoice"(uuid, text);
create or replace function "better_supabase"."void_invoice"(invoice uuid, reason text, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = void_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.manage' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can manage' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'issued') or v_row."paid_total" <> 0 or v_row."credited_total" <> 0 then
    raise exception 'an invoice with payments or credits is credited, not voided' using errcode = '55000', hint = 'INVOICE_NOT_VOIDABLE';
  end if;
  if void_invoice.actor is not null then
    if jsonb_typeof(void_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(void_invoice.actor ->> 'ip', '')::inet, nullif(void_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(void_invoice.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(void_invoice.reason), ''), ''), true);
  update "better_supabase"."invoices" x set "status" = 'void', "voided_at" = now(),
    "void_reason" = nullif(trim(void_invoice.reason), ''), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice', v_row."id"::text);
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice_charge', c."id"::text)
  from "better_supabase"."invoice_charges" c where c."invoice_id" = v_row."id";
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.voided', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reason', v_row."void_reason"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.voided',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice voided',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'reason', v_row."void_reason")
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."void_invoice"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."void_invoice"(uuid, text, jsonb) to authenticated, service_role;

-- Writes an open invoice off as uncollectible. Needs invoices.manage. The
-- reason and actor go to the state machine's history.
drop function if exists "better_supabase"."write_off_invoice"(uuid);
drop function if exists "better_supabase"."write_off_invoice"(uuid, text);
create or replace function "better_supabase"."write_off_invoice"(invoice uuid, reason text default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if write_off_invoice.actor is not null then
    if jsonb_typeof(write_off_invoice.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(write_off_invoice.actor ->> 'ip', '')::inet, nullif(write_off_invoice.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(write_off_invoice.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(write_off_invoice.reason), ''), ''), true);
  update "better_supabase"."invoices" x set "status" = 'uncollectible', "updated_at" = now()
  where x."id" = write_off_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.manage' end), false)) and x."status" in ('issued', 'partially_paid')
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'only an open invoice you can manage is written off' using errcode = '55000', hint = 'INVOICE_NOT_OPEN';
  end if;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_write_off', v_row."id"::text);
  end if;
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.uncollected', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(write_off_invoice.reason), '')), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.uncollected',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice uncollected',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(write_off_invoice.reason), ''))
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."write_off_invoice"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."write_off_invoice"(uuid, text, jsonb) to authenticated, service_role;

-- Reverses a recorded payment. The reason and actor go to the state machine's
-- history.
drop function if exists "better_supabase"."reverse_invoice_payment"(uuid, text);
create or replace function "better_supabase"."reverse_invoice_payment"(payment uuid, reason text default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_meta jsonb;
  v_amount bigint;
  v_reversal uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select y."metadata" into v_meta from "better_supabase"."ledger_transactions" y
  where y."id" = reverse_invoice_payment.payment and y."reference_type" = 'invoices';
  select * into v_row from "better_supabase"."invoices" x where x."id" = (v_meta ->> 'invoiceId')::uuid and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.manage' end), false)) for update;
  if v_meta is null or v_row."id" is null then
    raise exception 'no such payment on an invoice you can manage' using errcode = 'P0002', hint = 'INVOICE_PAYMENT_NOT_FOUND';
  end if;
  if coalesce(v_meta ->> 'method', '') = any ('{stripe,order}'::text[]) then
    raise exception 'a payment provider''s payment is refunded through the provider, not reversed' using errcode = '55000', hint = 'INVOICE_PAYMENT_PROVIDER';
  end if;
  if (v_meta ->> 'reversal')::boolean is true
    or exists (select 1 from "better_supabase"."ledger_transactions" y where y."reverses" = reverse_invoice_payment.payment) then
    raise exception 'this payment is a reversal or is already reversed' using errcode = '55000', hint = 'INVOICE_PAYMENT_REVERSED';
  end if;
  if reverse_invoice_payment.actor is not null then
    if jsonb_typeof(reverse_invoice_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(reverse_invoice_payment.actor ->> 'ip', '')::inet, nullif(reverse_invoice_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(reverse_invoice_payment.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(reverse_invoice_payment.reason), ''), ''), true);
  v_amount := coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), 0);
  v_reversal := "better_supabase"."ledger_post"(v_row."tenant_id", 'invoice.payment_reversal',
    (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
      from "better_supabase"."ledger_entries" e where e."transaction_id" = reverse_invoice_payment.payment),
    'invoices', v_row."id"::text, null, null, null,
    (select y."metadata" from "better_supabase"."ledger_transactions" y where y."id" = reverse_invoice_payment.payment) || jsonb_strip_nulls(jsonb_build_object('reversal', true, 'reason', nullif(trim(reverse_invoice_payment.reason), ''))),
    reverse_invoice_payment.payment);
  v_amount := v_amount - coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), 0);
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice_payment', reverse_invoice_payment.payment::text);
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('invoice.payment_reversed', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', reverse_invoice_payment.payment, 'reversalId', v_reversal, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(reverse_invoice_payment.reason), '')), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.payment_reversed',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice payment_reversed',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', reverse_invoice_payment.payment, 'reversalId', v_reversal, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'reason', nullif(trim(reverse_invoice_payment.reason), ''))
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."reverse_invoice_payment"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."reverse_invoice_payment"(uuid, text, jsonb) to authenticated, service_role;

drop function if exists "better_supabase"."add_invoice_charge"(uuid, bigint, text, text, jsonb);
drop function if exists "better_supabase"."add_invoice_charge"(uuid, bigint, text, text);
-- Adds a charge on top of an issued invoice's total, such as collection
-- costs or a late fee, in the invoice's currency. It raises the balance, so
-- a paid invoice is open again until the charge is paid too. fields: the
-- charge's extra columns (options.chargeExtraColumns). actor: who added it,
-- for the state machine's history.
create or replace function "better_supabase"."add_invoice_charge"(invoice uuid, amount bigint, currency text, description text, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_charge uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = add_invoice_charge.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice takes charges' using errcode = '55000', hint = 'INVOICE_NOT_CHARGEABLE';
  end if;
  if coalesce(add_invoice_charge.amount, 0) <= 0 then
    raise exception 'a charge has a positive amount' using errcode = '22023', hint = 'INVOICE_CHARGE_INVALID';
  end if;
  if upper(add_invoice_charge.currency) is distinct from v_row."currency" then
    raise exception 'a charge must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
  end if;
  if add_invoice_charge.actor is not null then
    if jsonb_typeof(add_invoice_charge.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(add_invoice_charge.actor ->> 'ip', '')::inet, nullif(add_invoice_charge.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(add_invoice_charge.actor::text, ''), true);
  insert into "better_supabase"."invoice_charges" ("tenant_id", "invoice_id", "amount", "currency", "description", "created_by")
  values (v_row."tenant_id", v_row."id", add_invoice_charge.amount, v_row."currency", nullif(trim(add_invoice_charge.description), ''), auth.uid())
  returning "id" into v_charge;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_charge', v_charge::text);
  end if;
  perform "better_supabase".emit_event('invoice.charged', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', v_charge, 'amount', add_invoice_charge.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.charged',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice charged',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', v_charge, 'amount', add_invoice_charge.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."add_invoice_charge"(uuid, bigint, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."add_invoice_charge"(uuid, bigint, text, text, jsonb) to authenticated, service_role;

drop function if exists "better_supabase"."remove_invoice_charge"(uuid);
create or replace function "better_supabase"."remove_invoice_charge"(charge uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_amount bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x.* into v_row from "better_supabase"."invoices" x join "better_supabase"."invoice_charges" c on c."invoice_id" = x."id"
  where c."id" = remove_invoice_charge.charge and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false))
  for update of x;
  if v_row."id" is null then
    raise exception 'no such charge on an invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_CHARGE_NOT_FOUND';
  end if;
  if v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice changes its charges' using errcode = '55000', hint = 'INVOICE_NOT_CHARGEABLE';
  end if;
  if remove_invoice_charge.actor is not null then
    if jsonb_typeof(remove_invoice_charge.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(remove_invoice_charge.actor ->> 'ip', '')::inet, nullif(remove_invoice_charge.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(remove_invoice_charge.actor::text, ''), true);
  delete from "better_supabase"."invoice_charges" c where c."id" = remove_invoice_charge.charge
  returning c."amount" into v_amount;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  perform "better_supabase"."accounting_reverse_source"(v_row."tenant_id", 'invoice_charge', remove_invoice_charge.charge::text);
  perform "better_supabase".emit_event('invoice.charge_removed', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', remove_invoice_charge.charge, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.charge_removed',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice charge_removed',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'chargeId', remove_invoice_charge.charge, 'amount', v_amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."remove_invoice_charge"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."remove_invoice_charge"(uuid, jsonb) to authenticated, service_role;

-- What a tenant is owed in one currency on as_of, by days past due:
-- not yet due, 1 to 30, 31 to 60, 61 to 90 and over 90. Amounts are text.
-- direction: sales (what customers owe) or purchase (what it owes suppliers).
drop function if exists "better_supabase"."invoice_aging"(uuid, text, date);
create or replace function "better_supabase"."invoice_aging"(tenant uuid, currency text, as_of date, direction text default 'sales')
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with open as (
    select (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") as balance, coalesce(invoice_aging.as_of, current_date) - x."due_on" as late
    from "better_supabase"."invoices" x
    where x."tenant_id" = invoice_aging.tenant and x."currency" = upper(invoice_aging.currency)
      and x."kind" = 'invoice' and x."status" in ('issued', 'partially_paid') and x."direction" = coalesce(invoice_aging.direction, 'sales')
  )
  select jsonb_build_object(
    'currency', upper(invoice_aging.currency),
    'current', coalesce(sum(balance) filter (where late <= 0), 0)::text,
    'days1To30', coalesce(sum(balance) filter (where late between 1 and 30), 0)::text,
    'days31To60', coalesce(sum(balance) filter (where late between 31 and 60), 0)::text,
    'days61To90', coalesce(sum(balance) filter (where late between 61 and 90), 0)::text,
    'over90', coalesce(sum(balance) filter (where late > 90), 0)::text,
    'outstanding', coalesce(sum(balance), 0)::text,
    'overdueCount', count(*) filter (where late > 0)
  )
  from open
$$;
revoke execute on function "better_supabase"."invoice_aging"(uuid, text, date, text) from public, anon;
grant execute on function "better_supabase"."invoice_aging"(uuid, text, date, text) to authenticated, service_role;

-- An invoice from an accepted quote. With deposit_bps (2000 for 20%) it is
-- a deposit invoice for that share of the quote, and with deposit_amount
-- one for that amount, tax included; without, the full invoice,
-- which subtracts the deposits already issued, one line per deposit and tax
-- rate described by deposit_description ({identifier} is the deposit's), and
-- is made once per quote.
-- The quote's document discount stays on the invoice's header.
drop function if exists "better_supabase"."invoice_from_quote"(uuid, integer);
drop function if exists "better_supabase"."invoice_from_quote"(uuid, integer, bigint);
create or replace function "better_supabase"."invoice_from_quote"(quote uuid, deposit_bps integer, deposit_amount bigint default null, deposit_description text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_quote "better_supabase"."quotes";
  v_row "better_supabase"."invoices";
  v_lines jsonb;
  v_header jsonb := '{}'::jsonb;
begin
  select * into v_quote from "better_supabase"."quotes" x where x."id" = invoice_from_quote.quote;
  if v_quote."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_quote."tenant_id", 'invoices.write'), false)) then
    raise exception 'no such quote you can invoice' using errcode = 'P0002', hint = 'INVOICE_ORIGIN_NOT_FOUND';
  end if;
  if v_quote."status" <> 'accepted' then
    raise exception 'only an accepted quote is invoiced' using errcode = '55000', hint = 'INVOICE_QUOTE_NOT_ACCEPTED';
  end if;
  if invoice_from_quote.deposit_bps is not null and (invoice_from_quote.deposit_bps <= 0 or invoice_from_quote.deposit_bps >= 10000) then
    raise exception 'a deposit is between 0 and 100 percent' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_bps is not null and invoice_from_quote.deposit_amount is not null then
    raise exception 'a deposit is a share (deposit_bps) or an amount (deposit_amount), not both' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_amount is not null and (invoice_from_quote.deposit_amount <= 0 or invoice_from_quote.deposit_amount > v_quote."total") then
    raise exception 'a deposit amount is positive and at most the quote''s total' using errcode = '22023', hint = 'INVOICE_DEPOSIT_INVALID';
  end if;
  if invoice_from_quote.deposit_bps is null and invoice_from_quote.deposit_amount is null then
    select * into v_row from "better_supabase"."invoices" x
    where x."origin_type" = 'quote' and x."origin_id"::text = v_quote."id"::text
      and x."deposit_bps" is null and x."deposit_amount" is null and x."status" <> 'void' and x."kind" = 'invoice' and not (x."total" > 0 and x."credited_total" >= x."total")
    limit 1;
    if v_row."id" is not null then
      return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('description', x."description", 'quantity', x."quantity" * coalesce(x."periods", 1), 'unitAmount', x."unit_amount"::text,
        'discountBps', x."discount_bps", 'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code",
        'product', case when x."product_type" is null then null else jsonb_build_object('type', x."product_type", 'id', x."product_id") end
      ) order by x."position"), '[]'::jsonb) into v_lines
    from "better_supabase"."quote_lines" x where x."parent_id" = v_quote."id" and (not x."optional" or x."selected");
    if not exists (select 1 from "better_supabase"."invoices" d where d."origin_type" = 'quote' and d."origin_id"::text = v_quote."id"::text and (d."deposit_bps" is not null or d."deposit_amount" is not null) and d."status" not in ('draft', 'void') and not (d."total" > 0 and d."credited_total" >= d."total")) then
      v_header := jsonb_build_object('discountBps', v_quote."discount_bps", 'discountAmount', v_quote."discount_amount"::text);
    else
      select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', 'Discount', 'quantity', 1, 'unitAmount', (-x."discount")::text,
          'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code") order by x."tax_rate_bps"), '[]'::jsonb)
        into v_lines
      from "better_supabase"."quote_tax_lines" x where x."parent_id" = v_quote."id" and x."discount" <> 0;
    end if;
    select v_lines || coalesce(jsonb_agg(jsonb_build_object('description', replace(coalesce(nullif(trim(invoice_from_quote.deposit_description), ''), 'Deposit {identifier}'), '{identifier}', d."identifier"), 'quantity', 1, 'unitAmount', (-(case when d."prices_include_tax" = v_quote."prices_include_tax" then y.amount when d."prices_include_tax" then round(y.amount * 10000.0 / (10000 + y.rate))::bigint else round(y.amount * (10000 + y.rate) / 10000.0)::bigint end))::text,
        'taxRateBps', y.rate) order by d."identifier", y.rate), '[]'::jsonb)
      into v_lines
    from "better_supabase"."invoices" d
    cross join lateral (
      select dl."tax_rate_bps" as rate, sum(round(dl."quantity" * dl."unit_amount") - round(round(dl."quantity" * dl."unit_amount") * dl."discount_bps" / 10000.0))::bigint as amount
      from "better_supabase"."invoice_lines" dl where dl."parent_id" = d."id" and true
      group by 1
    ) y
    where d."origin_type" = 'quote' and d."origin_id"::text = v_quote."id"::text and (d."deposit_bps" is not null or d."deposit_amount" is not null) and d."status" not in ('draft', 'void') and not (d."total" > 0 and d."credited_total" >= d."total") and y.amount <> 0;
  elsif invoice_from_quote.deposit_amount is not null then
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit of ' || v_quote."identifier",
      'quantity', 1,
      'unitAmount', (case when v_quote."prices_include_tax" or v_quote."total" = 0 then invoice_from_quote.deposit_amount
        else round(invoice_from_quote.deposit_amount::numeric * v_quote."subtotal" / v_quote."total")::bigint end)::text,
      'taxRateBps', case when v_quote."subtotal" = 0 then 0 else round(v_quote."tax_total" * 10000.0 / v_quote."subtotal")::integer end));
  else
    v_lines := jsonb_build_array(jsonb_build_object(
      'description', 'Deposit ' || (invoice_from_quote.deposit_bps / 100.0)::text || '% of ' || v_quote."identifier",
      'quantity', 1,
      'unitAmount', round(case when v_quote."prices_include_tax" then v_quote."total" else v_quote."subtotal" end::numeric * invoice_from_quote.deposit_bps / 10000)::bigint::text,
      'taxRateBps', case when v_quote."subtotal" = 0 then 0 else round(v_quote."tax_total" * 10000.0 / v_quote."subtotal")::integer end));
  end if;
  v_row := null;
  return "better_supabase"."create_invoice"(v_quote."tenant_id", jsonb_build_object(
    'title', v_quote."title", 'currency', v_quote."currency", 'depositBps', invoice_from_quote.deposit_bps, 'depositAmount', invoice_from_quote.deposit_amount::text, 'pricesIncludeTax', v_quote."prices_include_tax",
    'company', case when v_quote."company_id" is null then null else jsonb_build_object('type', v_quote."company_type", 'id', v_quote."company_id") end,
    'contact', case when v_quote."contact_id" is null then null else jsonb_build_object('type', v_quote."contact_type", 'id', v_quote."contact_id") end,
    'origin', jsonb_build_object('type', 'quote', 'id', v_quote."id"::text)) || v_header, v_lines);
end;
$$;
revoke execute on function "better_supabase"."invoice_from_quote"(uuid, integer, bigint, text) from public, anon;
grant execute on function "better_supabase"."invoice_from_quote"(uuid, integer, bigint, text) to authenticated, service_role;

-- The three-way match of a purchase bill: each product line against its
-- purchase order line (by variant) and what was received. A variant billed
-- beyond what arrived, across the order's bills, is a quantity variance; a
-- line whose amount differs from the order's unit cost by more than
-- options.matchTolerance (100 basis points or 500 minor units, whichever
-- is larger) is a price variance; nothing received is not_received. The
-- worst line decides. A bill without a purchase order is not_applicable.
create or replace function "better_supabase"."invoice_match_result"(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_result jsonb;
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = invoice_match_result.invoice;
  if v_row."purchase_order_id" is null then
    return jsonb_build_object('invoiceId', v_row."id", 'currency', v_row."currency", 'purchaseOrderId', null, 'status', 'not_applicable', 'lines', '[]'::jsonb);
  end if;
  with billed as (
    select il."parent_id" as bill, (il."product_id")::text as variant, sum(il."quantity") as quantity,
      sum(case when b."prices_include_tax" then round((round(il."quantity" * il."unit_amount") - round(round(il."quantity" * il."unit_amount") * il."discount_bps" / 10000.0)) * 10000.0 / (10000 + il."tax_rate_bps")) else round(il."quantity" * il."unit_amount") - round(round(il."quantity" * il."unit_amount") * il."discount_bps" / 10000.0) end) as net
    from "better_supabase"."invoice_lines" il join "better_supabase"."invoices" b on b."id" = il."parent_id"
    where b."purchase_order_id" = v_row."purchase_order_id" and b."direction" = 'purchase'
      and b."kind" = 'invoice' and (b."id" = v_row."id" or b."status" in ('issued', 'partially_paid', 'paid'))
      and il."product_id" is not null
    group by 1, 2
  ),
  ordered as (
    select y."variant_id"::text as variant, sum(y."quantity_ordered") as ordered, sum(y."quantity_received") as received,
      sum(y."quantity_ordered" * y."unit_cost") / nullif(sum(y."quantity_ordered"), 0) as unit_cost
    from "better_supabase"."purchase_order_lines" y where y."purchase_order_id" = v_row."purchase_order_id"
    group by 1
  ),
  checked as (
    select x.variant, x.quantity, x.net, coalesce(o.ordered, 0) as ordered, coalesce(o.received, 0) as received,
      round(x.quantity * coalesce(o.unit_cost, 0)) as expected,
      (select coalesce(sum(e.quantity), 0) from billed e where e.variant = x.variant) as billed_total
    from billed x left join ordered o on o.variant = x.variant
    where x.bill = v_row."id"
  ),
  rated as (
    select c.*, case
      when c.received <= 0 then 'not_received'
      when c.billed_total > c.received then 'quantity_variance'
      when abs(c.net - c.expected) > greatest(round(c.expected * 100 / 10000.0), 500) then 'price_variance'
      else 'matched' end as status
    from checked c
  )
  select jsonb_build_object('invoiceId', v_row."id", 'currency', v_row."currency", 'purchaseOrderId', v_row."purchase_order_id",
    'status', coalesce((select r.status from rated r order by array_position(array['not_received', 'quantity_variance', 'price_variance', 'matched'], r.status) limit 1), 'matched'),
    'lines', coalesce((select jsonb_agg(jsonb_build_object('variantId', r.variant, 'quantity', r.quantity::text, 'billedQuantity', r.billed_total::text,
      'orderedQuantity', r.ordered::text, 'receivedQuantity', r.received::text, 'amount', r.net::bigint::text, 'expectedAmount', r.expected::bigint::text, 'status', r.status) order by r.variant) from rated r), '[]'::jsonb))
  into v_result;
  return v_result;
end;
$$;
revoke all on function "better_supabase"."invoice_match_result"(uuid) from public, anon, authenticated;

-- Runs the three-way match of a purchase bill the caller can read and
-- records invoice.match_checked with its result.
create or replace function "better_supabase"."purchase_bill_match"(invoice uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_result jsonb;
begin
  select * into v_row from "better_supabase"."invoices" x
  where x."id" = purchase_bill_match.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false));
  if v_row."id" is null then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."direction" <> 'purchase' or (v_row."kind" = 'invoice') is not true then
    raise exception 'only a purchase bill is matched' using errcode = '22023', hint = 'INVOICE_NOT_PURCHASE_BILL';
  end if;
  v_result := "better_supabase"."invoice_match_result"(v_row."id");
  perform "better_supabase".emit_event('invoice.match_checked', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'purchaseOrderId', v_row."purchase_order_id", 'status', v_result ->> 'status'), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."purchase_bill_match"(uuid) from public, anon;
grant execute on function "better_supabase"."purchase_bill_match"(uuid) to authenticated, service_role;

-- A party's unallocated payments, per currency: what record_party_payment
-- kept as credit, less what apply_party_credit drew on.
create or replace function "better_supabase"."list_party_credits"(tenant uuid, party_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_party_credits.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('currency', a."unit", 'amount', coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = a."id"), 0)::text) order by a."unit")
    from "better_supabase"."ledger_accounts" a
    where a."tenant_id" = list_party_credits.tenant and a."managed_by" = 'invoices'
      and a."holder_type" = 'invoice_party' and a."holder_id" = list_party_credits.party_id
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_party_credits"(uuid, text) from public, anon;
grant execute on function "better_supabase"."list_party_credits"(uuid, text) to authenticated, service_role;

-- Records one payment from a party over several of its invoices.
-- allocations: [{ invoiceId, amount }], each recorded as a payment of that
-- invoice with the reference "<reference>/<invoiceId>". What the allocations
-- leave over becomes the party's credit in the payment's currency. The
-- reference is required and unique per organization, so recording the same
-- payment twice adds it once.
create or replace function "better_supabase"."record_party_payment"(tenant uuid, party_id text, amount bigint, currency text, allocations jsonb, received_on date, reference text, method text default null, note text default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_currency text := upper(record_party_payment.currency);
  v_reference text := nullif(trim(record_party_payment.reference), '');
  v_allocations jsonb := coalesce(record_party_payment.allocations, '[]'::jsonb);
  v_paid_at timestamptz := coalesce(record_party_payment.received_on::timestamptz, now());
  v_allocated bigint := 0;
  v_remainder bigint;
  v_alloc record;
  v_row "better_supabase"."invoices";
  v_credit uuid;
  v_key text;
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', record_party_payment.tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to record payments in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if nullif(trim(record_party_payment.party_id), '') is null or length(record_party_payment.party_id) > 150 then
    raise exception 'a party id is a non-empty text of at most 150 characters' using errcode = '22023', hint = 'INVOICE_PARTY_INVALID';
  end if;
  if coalesce(record_party_payment.amount, 0) <= 0 then
    raise exception 'a party payment has a positive amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'INVOICE_CURRENCY_INVALID';
  end if;
  if v_reference is null then
    raise exception 'a party payment needs a reference, such as the bank transaction id' using errcode = '22023', hint = 'INVOICE_PAYMENT_REFERENCE_REQUIRED';
  end if;
  if jsonb_typeof(v_allocations) <> 'array' or exists (
    select 1 from jsonb_array_elements(v_allocations) x
    where jsonb_typeof(x.value) <> 'object'
      or coalesce(x.value ->> 'invoiceId', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(x.value ->> 'amount', '') !~ '^[0-9]{1,18}$'
      or (x.value ->> 'amount')::bigint = 0
  ) or (
    select count(*) <> count(distinct x.value ->> 'invoiceId') from jsonb_array_elements(v_allocations) x
  ) then
    raise exception 'allocations is an array of { invoiceId, amount } with a positive amount, one per invoice' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  select coalesce(sum((x.value ->> 'amount')::bigint), 0) into v_allocated from jsonb_array_elements(v_allocations) x;
  if v_allocated > record_party_payment.amount then
    raise exception 'the allocations add up to more than the payment' using errcode = '23514', hint = 'INVOICE_ALLOCATIONS_TOO_LARGE';
  end if;
  if record_party_payment.actor is not null then
    if jsonb_typeof(record_party_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(record_party_payment.actor ->> 'ip', '')::inet, nullif(record_party_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(record_party_payment.actor::text, ''), true);
  for v_alloc in
    select (x.value ->> 'invoiceId')::uuid as invoice, (x.value ->> 'amount')::bigint as amount
    from jsonb_array_elements(v_allocations) with ordinality x
    order by x.ordinality
  loop
    select * into v_row from "better_supabase"."invoices" x
    where x."id" = v_alloc.invoice and x."tenant_id" = record_party_payment.tenant
      and (x."company_id"::text = record_party_payment.party_id or x."contact_id"::text = record_party_payment.party_id) and x."direction" = 'sales';
    if v_row."id" is null then
      raise exception 'an allocation names no invoice of this party' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
    end if;
    if v_alloc.amount > (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total") and not exists (
      select 1 from "better_supabase"."ledger_transactions" y
      where y."tenant_id" = v_row."tenant_id" and y."idempotency_key" = 'invoice-payment:' || (v_reference || '/' || v_alloc.invoice::text)
    ) then
      raise exception 'an allocation is more than the invoice''s balance; keep the rest as credit' using errcode = '23514', hint = 'INVOICE_ALLOCATION_TOO_LARGE';
    end if;
    perform "better_supabase"."record_invoice_payment"(v_alloc.invoice, v_alloc.amount, v_currency, v_paid_at,
      record_party_payment.method, v_reference || '/' || v_alloc.invoice::text,
      record_party_payment.note, record_party_payment.actor, null);
  end loop;
  v_remainder := record_party_payment.amount - v_allocated;
  v_key := 'invoice-party-payment:' || v_reference;
  if v_remainder > 0 then
    select y."id" into v_credit from "better_supabase"."ledger_transactions" y
    where y."tenant_id" = record_party_payment.tenant and y."idempotency_key" = v_key;
    if v_credit is null then
      v_credit := "better_supabase"."ledger_post"(record_party_payment.tenant, 'invoice.party_payment',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(record_party_payment.tenant, 'cash', 'invoices:cash:' || v_currency,
      'Invoice payments ' || v_currency, v_currency, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', v_remainder),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(record_party_payment.tenant, 'credit', 'invoices:credit:' || record_party_payment.party_id || ':' || v_currency,
      'Credit ' || record_party_payment.party_id || ' ' || v_currency, v_currency, 0::smallint, 'invoice_party', record_party_payment.party_id,
      null, true, 'invoices.read', 'invoices', null), 'amount', -v_remainder)),
        'invoices', record_party_payment.party_id, null, v_key, v_paid_at,
        jsonb_strip_nulls(jsonb_build_object('partyId', record_party_payment.party_id, 'currency', v_currency,
          'method', record_party_payment.method, 'reference', v_reference, 'note', nullif(trim(record_party_payment.note), ''))));
      if not better_supabase.import_run() is not null then
    perform "better_supabase"."accounting_post_source"('invoice_party_payment', v_credit::text);
  end if;
    end if;
  end if;
  return jsonb_build_object(
    'partyId', record_party_payment.party_id,
    'currency', v_currency,
    'amount', record_party_payment.amount::text,
    'allocated', v_allocated::text,
    'credited', v_remainder::text,
    'creditTransactionId', v_credit,
    'credit', coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = record_party_payment.tenant and a."code" = 'invoices:credit:' || record_party_payment.party_id || ':' || v_currency)), 0)::text
  );
end;
$$;
revoke execute on function "better_supabase"."record_party_payment"(uuid, text, bigint, text, jsonb, date, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."record_party_payment"(uuid, text, bigint, text, jsonb, date, text, text, text, jsonb) to authenticated, service_role;

-- Pays part or all of an open invoice from its party's credit in the
-- invoice's currency, as a ledger transaction from the receivable to the
-- credit account. It shows among the invoice's payments with method credit.
create or replace function "better_supabase"."apply_party_credit"(party_id text, invoice uuid, amount bigint, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_account uuid;
  v_payment uuid;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = apply_party_credit.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.write' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if not (v_row."company_id"::text = apply_party_credit.party_id or v_row."contact_id"::text = apply_party_credit.party_id) then
    raise exception 'the invoice isn''t this party''s' using errcode = '22023', hint = 'INVOICE_PARTY_MISMATCH';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid') or v_row."direction" <> 'sales' then
    raise exception 'only an open sales invoice takes credit' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
  end if;
  if coalesce(apply_party_credit.amount, 0) <= 0 then
    raise exception 'credit is applied in a positive amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
  end if;
  if apply_party_credit.amount > (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total") then
    raise exception 'the amount is more than the invoice''s balance' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
  end if;
  select a."id" into v_account from "better_supabase"."ledger_accounts" a
  where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoices:credit:' || apply_party_credit.party_id || ':' || v_row."currency"
  for update;
  if v_account is null or apply_party_credit.amount > coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = v_account), 0) then
    raise exception 'the party doesn''t have this much credit in the invoice''s currency' using errcode = '23514', hint = 'INVOICE_CREDIT_INSUFFICIENT';
  end if;
  if apply_party_credit.actor is not null then
    if jsonb_typeof(apply_party_credit.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(apply_party_credit.actor ->> 'ip', '')::inet, nullif(apply_party_credit.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(apply_party_credit.actor::text, ''), true);
  v_was := v_row."status";
  v_payment := "better_supabase"."ledger_post"(v_row."tenant_id", 'invoice.credit_applied',
    jsonb_build_array(
      jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -apply_party_credit.amount),
      jsonb_build_object('account', v_account, 'amount', apply_party_credit.amount)),
    'invoices', v_row."id"::text, null, null, now(),
    jsonb_build_object('invoiceId', v_row."id", 'method', 'credit', 'partyId', apply_party_credit.party_id));
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.credit_applied', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', v_payment, 'partyId', apply_party_credit.party_id, 'amount', apply_party_credit.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.credit_applied',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice credit_applied',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'paymentId', v_payment, 'partyId', apply_party_credit.party_id, 'amount', apply_party_credit.amount::text, 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text)
  );
  if v_row."status" = 'paid' and v_was <> 'paid' then
    perform "better_supabase".emit_event('invoice.paid', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  end if;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."apply_party_credit"(text, uuid, bigint, jsonb) from public, anon;
grant execute on function "better_supabase"."apply_party_credit"(text, uuid, bigint, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."list_invoice_dunning_levels"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_invoice_dunning_levels.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('level', l."level", 'daysAfterDue', l."days_after_due", 'templateKey', l."template_key", 'fee', l."fee"::text, 'final', l."final") order by l."level") from "better_supabase"."invoice_dunning_levels" l where l."tenant_id" = list_invoice_dunning_levels.tenant), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_invoice_dunning_levels"(uuid) from public, anon;
grant execute on function "better_supabase"."list_invoice_dunning_levels"(uuid) to authenticated, service_role;

-- Replaces an organization's reminder levels. levels: [{ daysAfterDue,
-- templateKey, fee, final }], numbered 1, 2, ... in order, with daysAfterDue
-- rising. fee: minor units of the invoice's currency, added as a charge when
-- the level is reached. Only the last level can be final.
create or replace function "better_supabase"."set_invoice_dunning_levels"(tenant uuid, levels jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', set_invoice_dunning_levels.tenant, 'invoices.manage'), false)) then
    raise exception 'not allowed to manage this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if jsonb_typeof(set_invoice_dunning_levels.levels) is distinct from 'array'
    or jsonb_array_length(set_invoice_dunning_levels.levels) > 20
    or exists (
      select 1 from jsonb_array_elements(set_invoice_dunning_levels.levels) with ordinality x
      where jsonb_typeof(x.value) <> 'object'
        or coalesce(x.value ->> 'daysAfterDue', '') !~ '^[0-9]{1,5}$'
        or length(coalesce(trim(x.value ->> 'templateKey'), '')) not between 1 and 200
        or coalesce(x.value ->> 'fee', '0') !~ '^[0-9]{1,18}$'
        or jsonb_typeof(coalesce(x.value -> 'final', 'false'::jsonb)) <> 'boolean'
        or ((x.value ->> 'final')::boolean is true and x.ordinality < jsonb_array_length(set_invoice_dunning_levels.levels))
    ) then
    raise exception 'levels is an array of at most 20 { daysAfterDue, templateKey, fee, final }, and only the last is final' using errcode = '22023', hint = 'INVOICE_DUNNING_LEVELS_INVALID';
  end if;
  if exists (
    select 1 from (
      select (x.value ->> 'daysAfterDue')::integer as days,
        lag((x.value ->> 'daysAfterDue')::integer) over (order by x.ordinality) as before
      from jsonb_array_elements(set_invoice_dunning_levels.levels) with ordinality x
    ) s where s.days <= s.before
  ) then
    raise exception 'each level comes more days after the due date than the one before' using errcode = '22023', hint = 'INVOICE_DUNNING_LEVELS_INVALID';
  end if;
  delete from "better_supabase"."invoice_dunning_levels" l where l."tenant_id" = set_invoice_dunning_levels.tenant;
  insert into "better_supabase"."invoice_dunning_levels" ("tenant_id", "level", "days_after_due", "template_key", "fee", "final")
  select set_invoice_dunning_levels.tenant, x.ordinality, (x.value ->> 'daysAfterDue')::integer, trim(x.value ->> 'templateKey'),
    coalesce((x.value ->> 'fee')::bigint, 0), coalesce((x.value ->> 'final')::boolean, false)
  from jsonb_array_elements(set_invoice_dunning_levels.levels) with ordinality x;
  return coalesce((select jsonb_agg(jsonb_build_object('level', l."level", 'daysAfterDue', l."days_after_due", 'templateKey', l."template_key", 'fee', l."fee"::text, 'final', l."final") order by l."level") from "better_supabase"."invoice_dunning_levels" l where l."tenant_id" = set_invoice_dunning_levels.tenant), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."set_invoice_dunning_levels"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_invoice_dunning_levels"(uuid, jsonb) to authenticated, service_role;

-- Raises each overdue invoice with a balance to the highest reminder level it
-- has reached (one organization, or all), adds the level's fee as a charge,
-- notifies who created the invoice and records invoice.dunning_escalated with
-- the level's template key, for a sink that sends the reminder. Invoices
-- paused until today or later wait. Returns how many invoices moved up.
create or replace function "better_supabase"."run_invoice_dunning"(tenant uuid default null, as_of date default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_today date := coalesce(run_invoice_dunning.as_of, current_date);
  v_row "better_supabase"."invoices";
  v_level "better_supabase"."invoice_dunning_levels";
  v_count integer := 0;
  v_claims text;
begin
  for v_row in
    select x.* from "better_supabase"."invoices" x
    where (run_invoice_dunning.tenant is null or x."tenant_id" = run_invoice_dunning.tenant)
      and x."kind" = 'invoice' and x."status" in ('issued', 'partially_paid') and x."direction" = 'sales'
      and x."due_on" < v_today
      and (x."dunning_paused_until" is null or x."dunning_paused_until" < v_today)
      and (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") > 0
      and exists (select 1 from "better_supabase"."invoice_dunning_levels" l where l."tenant_id" = x."tenant_id" and l."level" > x."dunning_level" and x."due_on" + l."days_after_due" <= v_today)
    order by x."tenant_id", x."due_on", x."id"
    for update of x skip locked
  loop
    select l.* into v_level from "better_supabase"."invoice_dunning_levels" l where l."tenant_id" = v_row."tenant_id" and l."level" > v_row."dunning_level" and v_row."due_on" + l."days_after_due" <= v_today order by l."level" desc limit 1;
    update "better_supabase"."invoices" x set
      "dunning_level" = v_level."level",
      "dunning_at" = now(),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    if v_level."fee" > 0 then
      perform "better_supabase"."add_invoice_charge"(invoice => v_row."id", amount => v_level."fee", currency => v_row."currency"::text,
        description => 'Reminder fee, level ' || v_level."level");
      select * into v_row from "better_supabase"."invoices" x where x."id" = v_row."id";
    end if;
    if v_row."created_by" is not null then
      if better_supabase.import_run() is null then
        v_claims := current_setting('request.jwt.claims', true);
        perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
        perform "better_supabase"."notify"(jsonb_build_object(
        'type', 'invoice.dunning_escalated',
        'tenant', v_row."tenant_id",
        'actor', null,
        'subject_type', 'invoice',
        'subject_id', v_row."id"::text,
        'summary', coalesce(v_row."identifier", v_row."title") || ' reached reminder level ' || v_level."level",
        'recipients', to_jsonb(array[v_row."created_by"]),
        'key', 'invoice.dunning_escalated:' || v_row."id"::text || ':' || v_level."level",
        'data', jsonb_build_object('level', v_level."level", 'templateKey', v_level."template_key", 'final', v_level."final")
      ));
        perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
      end if;
    end if;
    perform "better_supabase".emit_event('invoice.dunning_escalated', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'level', v_level."level", 'templateKey', v_level."template_key", 'fee', v_level."fee"::text, 'final', v_level."final", 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'dueOn', v_row."due_on"), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.dunning_escalated',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice dunning_escalated',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'level', v_level."level", 'templateKey', v_level."template_key", 'fee', v_level."fee"::text, 'final', v_level."final", 'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text, 'dueOn', v_row."due_on")
  );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."run_invoice_dunning"(uuid, date) from public, anon, authenticated;
grant execute on function "better_supabase"."run_invoice_dunning"(uuid, date) to service_role;

-- Holds an invoice's reminders until a date, such as while the customer
-- disputes it; until null resumes them. reason: why, for the audit log.
create or replace function "better_supabase"."pause_invoice_dunning"(invoice uuid, until date, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = pause_invoice_dunning.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.collect' end), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if pause_invoice_dunning.until < current_date then
    raise exception 'a pause lasts until today or later' using errcode = '22023', hint = 'INVOICE_DUNNING_PAUSE_INVALID';
  end if;
  if length(pause_invoice_dunning.reason) > 2000 then
    raise exception 'a reason is at most 2000 characters' using errcode = '22023', hint = 'INVOICE_DUNNING_PAUSE_INVALID';
  end if;
  update "better_supabase"."invoices" x set
    "dunning_paused_until" = pause_invoice_dunning.until,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('invoice.dunning_paused', jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'until', pause_invoice_dunning.until, 'reason', nullif(trim(pause_invoice_dunning.reason), '')), 'invoices/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/invoices');
  perform better_supabase.audit_event(
    event_type => 'invoice.dunning_paused',
    category => 'billing',
    target_type => 'invoice',
    record_id => v_row."id"::text,
    target_label => v_row."identifier",
    summary => 'invoice dunning_paused',
    tenant => (v_row."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'invoiceId', v_row."id", 'subjectType', 'invoice', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'until', pause_invoice_dunning.until, 'reason', nullif(trim(pause_invoice_dunning.reason), ''))
  );
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'deposit_amount', v_row."deposit_amount"::text, 'discount_amount', v_row."discount_amount"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."pause_invoice_dunning"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."pause_invoice_dunning"(uuid, date, text) to authenticated, service_role;

-- The entry of an issued invoice or credit note for accounting: the receivable
-- against revenue and tax per rate, mirrored for a credit note. A purchase bill
-- credits the supplier's payable against expense and deductible tax.
create or replace function "better_supabase"."accounting_invoice_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with inv as (
    select x."id" as id, x."tenant_id" as tenant, x."issued_on" as issued_on, x."currency" as currency,
      x."identifier" as identifier, x."title" as title, x."subtotal" as subtotal, x."tax_total" as tax_total,
      x."total" as total, x."company_id"::text as party, x."prices_include_tax" as inclusive,
      case when x."kind" = 'credit_note' then -1 else 1 end as sign,
      x."direction" = 'purchase' as purchase, nullif(x."dimensions", '{}'::jsonb) as dimensions,
      x."purchase_order_id" is not null as ordered
    from "better_supabase"."invoices" x
    where x."id"::text = source_id and x."status" not in ('draft', 'void')
  ),
  groups as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, (inv.purchase and inv.ordered and l."product_id" is not null) as clearing, sum(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)) as net,
      sum((round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)) * l."tax_rate_bps" / case when inv.inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end) as tax
    from "better_supabase"."invoice_lines" l cross join inv
    where l."parent_id" = inv.id and true
    group by 1, 2, 3
  ),
  shares as (
    select g.rate, g.code, g.clearing,
      case when sum(g.net) over () = 0
        then case when row_number() over w = count(*) over () then inv.subtotal else 0 end
        else round(inv.subtotal * sum(g.net) over w / sum(g.net) over ()) - round(inv.subtotal * (sum(g.net) over w - g.net) / sum(g.net) over ())
      end as net,
      case when sum(g.tax) over () = 0
        then case when row_number() over w = count(*) over () then inv.tax_total else 0 end
        else round(inv.tax_total * sum(g.tax) over w / sum(g.tax) over ()) - round(inv.tax_total * (sum(g.tax) over w - g.tax) / sum(g.tax) over ())
      end as tax
    from groups g cross join inv
    window w as (order by g.rate, g.code nulls first, g.clearing rows between unbounded preceding and current row)
  )
  select jsonb_build_object(
    'organizationId', inv.tenant,
    'entryDate', inv.issued_on,
    'currency', inv.currency,
    'reference', inv.identifier,
    'memo', inv.title,
    'lines', case when inv.purchase then jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('role', 'payable', 'credit', (inv.sign * inv.total)::text, 'partyId', inv.party)))
      || coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('role', case when s.clearing then 'payable' else 'expense' end, 'debit', (inv.sign * s.net)::text, 'taxCode', s.code, 'taxRateBps', s.rate, 'dimensions', case when not s.clearing then inv.dimensions end))) from shares s where s.net <> 0), '[]'::jsonb)
      || coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('role', 'tax_receivable', 'debit', (inv.sign * s.tax)::text, 'taxCode', s.code, 'taxRateBps', s.rate, 'partyId', inv.party))) from shares s where s.tax <> 0), '[]'::jsonb) else jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'debit', (inv.sign * inv.total)::text, 'partyId', inv.party)))
      || coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('role', 'revenue', 'credit', (inv.sign * s.net)::text, 'taxCode', s.code, 'taxRateBps', s.rate, 'partyId', inv.party))) from shares s where s.net <> 0), '[]'::jsonb)
      || coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('role', 'tax_payable', 'credit', (inv.sign * s.tax)::text, 'taxCode', s.code, 'taxRateBps', s.rate, 'partyId', inv.party))) from shares s where s.tax <> 0), '[]'::jsonb) end
  ) || case when inv.purchase then jsonb_build_object('journal', 'purchase') else '{}'::jsonb end
  from inv
$$;
revoke execute on function "better_supabase"."accounting_invoice_lines"(text) from public, anon, authenticated;

-- The entry of an invoice payment for accounting: bank against the receivable,
-- the other way round for a refund. Paying a purchase bill debits the payable
-- and credits bank.
create or replace function "better_supabase"."accounting_invoice_payment_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', inv."tenant_id",
    'entryDate', (y."effective_at" at time zone 'UTC')::date,
    'currency', inv."currency",
    'reference', coalesce(y."metadata" ->> 'reference', inv."identifier"),
    'memo', 'Payment of ' || coalesce(inv."identifier", inv."title"),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', case when inv."direction" = 'purchase' then 'credit' else 'debit' end, p.amount::text),
      jsonb_strip_nulls(jsonb_build_object('role', case when inv."direction" = 'purchase' then 'payable' else 'receivable' end, case when inv."direction" = 'purchase' then 'debit' else 'credit' end, p.amount::text, 'partyId', inv."company_id"::text)))
  )
  from "better_supabase"."ledger_transactions" y
  join "better_supabase"."invoices" inv on inv."id"::text = y."metadata" ->> 'invoiceId'
  cross join lateral (
    select sum(e."amount") as amount from "better_supabase"."ledger_entries" e
    join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
    where e."transaction_id" = y."id" and a."code" = case when inv."direction" = 'purchase' then 'invoices:paid:' || inv."currency" else 'invoices:cash:' || inv."currency" end
  ) p
  where y."id"::text = source_id and y."reference_type" = 'invoices' and p.amount <> 0
$$;
revoke execute on function "better_supabase"."accounting_invoice_payment_lines"(text) from public, anon, authenticated;

-- The entry of an invoice charge for accounting: the receivable against
-- revenue, with no tax.
create or replace function "better_supabase"."accounting_invoice_charge_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', inv."tenant_id",
    'entryDate', (c."created_at" at time zone 'UTC')::date,
    'currency', inv."currency",
    'reference', inv."identifier",
    'memo', 'Charge on ' || coalesce(inv."identifier", inv."title"),
    'lines', jsonb_build_array(
      jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'debit', c."amount"::text, 'partyId', inv."company_id"::text)),
      jsonb_strip_nulls(jsonb_build_object('role', 'revenue', 'credit', c."amount"::text, 'description', c."description")))
  )
  from "better_supabase"."invoice_charges" c
  join "better_supabase"."invoices" inv on inv."id" = c."invoice_id"
  where c."id"::text = source_id and c."amount" <> 0 and not (inv."direction" = 'purchase')
$$;
revoke execute on function "better_supabase"."accounting_invoice_charge_lines"(text) from public, anon, authenticated;

-- The entry of a written-off invoice for accounting: the open balance against
-- expenses, the receivable cleared.
create or replace function "better_supabase"."accounting_invoice_write_off_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', inv."tenant_id",
    'currency', inv."currency",
    'reference', inv."identifier",
    'memo', 'Write-off of ' || coalesce(inv."identifier", inv."title"),
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'expense', 'debit', b.balance::text),
      jsonb_strip_nulls(jsonb_build_object('role', 'receivable', 'credit', b.balance::text, 'partyId', inv."company_id"::text)))
  )
  from "better_supabase"."invoices" inv
  cross join lateral (select inv."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = inv."id"), 0) - inv."credited_total" - inv."paid_total" as balance) b
  where inv."id"::text = source_id and b.balance > 0 and not (inv."direction" = 'purchase')
$$;
revoke execute on function "better_supabase"."accounting_invoice_write_off_lines"(text) from public, anon, authenticated;

-- The entry of a party payment's unallocated rest for accounting: bank against
-- the party's receivable.
create or replace function "better_supabase"."accounting_invoice_party_payment_lines"(source_id text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'organizationId', y."tenant_id",
    'entryDate', (y."effective_at" at time zone 'UTC')::date,
    'currency', y."metadata" ->> 'currency',
    'reference', y."metadata" ->> 'reference',
    'memo', 'Payment on account',
    'lines', jsonb_build_array(
      jsonb_build_object('role', 'bank', 'debit', p.amount::text),
      jsonb_build_object('role', 'receivable', 'credit', p.amount::text, 'partyId', y."metadata" ->> 'partyId'))
  )
  from "better_supabase"."ledger_transactions" y
  cross join lateral (
    select sum(e."amount") as amount from "better_supabase"."ledger_entries" e
    join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
    where e."transaction_id" = y."id" and a."code" = 'invoices:cash:' || (y."metadata" ->> 'currency')
  ) p
  where y."id"::text = source_id and y."reference_type" = 'invoices'
    and y."metadata" ? 'partyId' and not y."metadata" ? 'invoiceId' and p.amount <> 0
$$;
revoke execute on function "better_supabase"."accounting_invoice_party_payment_lines"(text) from public, anon, authenticated;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."invoices";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoices";
create policy bsb_tenant_scope_select on "better_supabase"."invoices" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read'))) or (("tenant_id")::text, ('invoice')::text, ("id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or (("tenant_id")::text, ("company_type")::text, ("company_id"::text)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g) or (("tenant_id")::text, ("contact_type")::text, ("contact_id"::text)::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoices";
create policy bsb_tenant_scope_insert on "better_supabase"."invoices" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoices";
create policy bsb_tenant_scope_update on "better_supabase"."invoices" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoices";
create policy bsb_tenant_scope_delete on "better_supabase"."invoices" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_lines";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."invoices" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_lines";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_charges";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_charges";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_charges" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."invoices" x where x."id" = "invoice_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_charges";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_charges" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_charges";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_charges" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_charges";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_charges" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_dunning_levels";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_dunning_levels";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_dunning_levels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_levels";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_levels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_dunning_levels";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_dunning_levels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_levels";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_levels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.invoices.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."issue_invoice"(uuid, date);
drop function if exists "api"."issue_invoice"(uuid, date, date);
drop function if exists "api"."record_invoice_payment"(uuid, bigint, timestamptz, text, text);
drop function if exists "api"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text);
drop function if exists "api"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text, text);
drop function if exists "api"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text, text, jsonb);
drop function if exists "api"."void_invoice"(uuid, text);
drop function if exists "api"."write_off_invoice"(uuid);
drop function if exists "api"."write_off_invoice"(uuid, text);
drop function if exists "api"."reverse_invoice_payment"(uuid, text);
drop function if exists "api"."add_invoice_charge"(uuid, bigint, text, text, jsonb);
drop function if exists "api"."add_invoice_charge"(uuid, bigint, text, text);
drop function if exists "api"."remove_invoice_charge"(uuid);
drop function if exists "api"."invoice_aging"(uuid, text, date);
drop function if exists "api"."invoice_from_quote"(uuid, integer);
drop function if exists "api"."invoice_from_quote"(uuid, integer, bigint);

create or replace function "api"."import_run"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_run"() $$;
revoke execute on function "api"."import_run"() from public;
grant execute on function "api"."import_run"() to anon, authenticated, service_role;

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

create or replace function "api"."create_invoice"(tenant uuid, attrs jsonb, lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_invoice"($1, $2, $3) $$;
revoke execute on function "api"."create_invoice"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."create_invoice"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."update_invoice"(invoice uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_invoice"($1, $2) $$;
revoke execute on function "api"."update_invoice"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_invoice"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."delete_invoice"(invoice uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_invoice"($1) $$;
revoke execute on function "api"."delete_invoice"(uuid) from public, anon;
grant execute on function "api"."delete_invoice"(uuid) to authenticated, service_role;

create or replace function "api"."set_invoice_lines"(parent uuid, lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_invoice_lines"($1, $2) $$;
revoke execute on function "api"."set_invoice_lines"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_invoice_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."issue_invoice"(invoice uuid, issued_on date, due_on date default null, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."issue_invoice"($1, $2, $3, $4) $$;
revoke execute on function "api"."issue_invoice"(uuid, date, date, jsonb) from public, anon;
grant execute on function "api"."issue_invoice"(uuid, date, date, jsonb) to authenticated, service_role;

create or replace function "api"."record_invoice_payment"(invoice uuid, amount bigint, currency text, paid_at timestamptz, method text, reference text, note text default null, actor jsonb default null, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_invoice_payment"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text, text, jsonb, text) from public, anon;
grant execute on function "api"."record_invoice_payment"(uuid, bigint, text, timestamptz, text, text, text, jsonb, text) to authenticated, service_role;

create or replace function "api"."list_invoice_payments"(invoice uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_invoice_payments"($1) $$;
revoke execute on function "api"."list_invoice_payments"(uuid) from public, anon;
grant execute on function "api"."list_invoice_payments"(uuid) to authenticated, service_role;

create or replace function "api"."credit_invoice"(invoice uuid, lines jsonb, note text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."credit_invoice"($1, $2, $3) $$;
revoke execute on function "api"."credit_invoice"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."credit_invoice"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."void_invoice"(invoice uuid, reason text, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."void_invoice"($1, $2, $3) $$;
revoke execute on function "api"."void_invoice"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."void_invoice"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."write_off_invoice"(invoice uuid, reason text default null, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."write_off_invoice"($1, $2, $3) $$;
revoke execute on function "api"."write_off_invoice"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."write_off_invoice"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."reverse_invoice_payment"(payment uuid, reason text default null, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."reverse_invoice_payment"($1, $2, $3) $$;
revoke execute on function "api"."reverse_invoice_payment"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."reverse_invoice_payment"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."add_invoice_charge"(invoice uuid, amount bigint, currency text, description text, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_invoice_charge"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."add_invoice_charge"(uuid, bigint, text, text, jsonb) from public, anon;
grant execute on function "api"."add_invoice_charge"(uuid, bigint, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."remove_invoice_charge"(charge uuid, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_invoice_charge"($1, $2) $$;
revoke execute on function "api"."remove_invoice_charge"(uuid, jsonb) from public, anon;
grant execute on function "api"."remove_invoice_charge"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."invoice_aging"(tenant uuid, currency text, as_of date, direction text default 'sales')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."invoice_aging"($1, $2, $3, $4) $$;
revoke execute on function "api"."invoice_aging"(uuid, text, date, text) from public, anon;
grant execute on function "api"."invoice_aging"(uuid, text, date, text) to authenticated, service_role;

create or replace function "api"."invoice_from_quote"(quote uuid, deposit_bps integer, deposit_amount bigint default null, deposit_description text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."invoice_from_quote"($1, $2, $3, $4) $$;
revoke execute on function "api"."invoice_from_quote"(uuid, integer, bigint, text) from public, anon;
grant execute on function "api"."invoice_from_quote"(uuid, integer, bigint, text) to authenticated, service_role;

create or replace function "api"."purchase_bill_match"(invoice uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."purchase_bill_match"($1) $$;
revoke execute on function "api"."purchase_bill_match"(uuid) from public, anon;
grant execute on function "api"."purchase_bill_match"(uuid) to authenticated, service_role;

create or replace function "api"."list_party_credits"(tenant uuid, party_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_party_credits"($1, $2) $$;
revoke execute on function "api"."list_party_credits"(uuid, text) from public, anon;
grant execute on function "api"."list_party_credits"(uuid, text) to authenticated, service_role;

create or replace function "api"."record_party_payment"(tenant uuid, party_id text, amount bigint, currency text, allocations jsonb, received_on date, reference text, method text default null, note text default null, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_party_payment"($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) $$;
revoke execute on function "api"."record_party_payment"(uuid, text, bigint, text, jsonb, date, text, text, text, jsonb) from public, anon;
grant execute on function "api"."record_party_payment"(uuid, text, bigint, text, jsonb, date, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."apply_party_credit"(party_id text, invoice uuid, amount bigint, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."apply_party_credit"($1, $2, $3, $4) $$;
revoke execute on function "api"."apply_party_credit"(text, uuid, bigint, jsonb) from public, anon;
grant execute on function "api"."apply_party_credit"(text, uuid, bigint, jsonb) to authenticated, service_role;

create or replace function "api"."list_invoice_dunning_levels"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_invoice_dunning_levels"($1) $$;
revoke execute on function "api"."list_invoice_dunning_levels"(uuid) from public, anon;
grant execute on function "api"."list_invoice_dunning_levels"(uuid) to authenticated, service_role;

create or replace function "api"."set_invoice_dunning_levels"(tenant uuid, levels jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_invoice_dunning_levels"($1, $2) $$;
revoke execute on function "api"."set_invoice_dunning_levels"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_invoice_dunning_levels"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."run_invoice_dunning"(tenant uuid default null, as_of date default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."run_invoice_dunning"($1, $2) $$;
revoke execute on function "api"."run_invoice_dunning"(uuid, date) from public, anon, authenticated;
grant execute on function "api"."run_invoice_dunning"(uuid, date) to service_role;

create or replace function "api"."pause_invoice_dunning"(invoice uuid, until date, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."pause_invoice_dunning"($1, $2, $3) $$;
revoke execute on function "api"."pause_invoice_dunning"(uuid, date, text) from public, anon;
grant execute on function "api"."pause_invoice_dunning"(uuid, date, text) to authenticated, service_role;

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
