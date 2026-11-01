-- ==== schema supabase/schemas/900_better_supabase_098_invoices.sql
-- better-supabase module: invoices
-- @bsb-block invoices@2 managed
-- @bsb-hash sha256:bb06e8363517d1aa529d8cdabb02aba797e714ee969c9b69653594ebc3bd51f9
-- Invoices an organization sends its own customers and bills from its suppliers: drafts with lines, a gapless number per direction on issue, payments, credit notes, void and write-off, overdue and aging per currency, credit limits, the three-way match of a purchase bill, party payments split over invoices with the rest kept as credit, dunning levels, and invoices from accepted quotes.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.column_default(relation text, name text, target anyelement)
returns anyelement
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  result alias for $0;
  v_default text;
begin
  select pg_catalog.pg_get_expr(d.adbin, d.adrelid) into v_default
  from pg_catalog.pg_attribute a
  join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
  where a.attrelid = pg_catalog.to_regclass(column_default.relation) and a.attname = column_default.name and not a.attisdropped;
  if v_default is not null then
    execute 'select ' || v_default into result;
  end if;
  return result;
end;
$$;
revoke execute on function better_supabase.column_default(text, text, anyelement) from public, anon, authenticated, service_role;
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
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_dunning_runs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_dunning_runs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_runs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_dunning_runs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_runs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_dunning_run_items";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_dunning_run_items";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_run_items";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_dunning_run_items";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_run_items";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_dunning_history";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_dunning_history";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_history";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_dunning_history";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_history";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_allocations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_allocations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_allocations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_allocations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_allocations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_approval_levels";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_approval_levels";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_approval_levels";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_approval_levels";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_approval_levels";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_approvals";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_approvals";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_approvals";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_approvals";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_approvals";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_e_endpoints";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_e_endpoints";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_e_endpoints";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_e_endpoints";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_e_endpoints";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_e_deliveries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_e_deliveries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_e_deliveries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_e_deliveries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_e_deliveries";
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
  "buyer" jsonb,
  "payment_terms_id" uuid,
  "discount_due_on" date,
  "discount_amount_early" bigint check ("discount_amount_early" >= 0),
  "collection_status" text check ("collection_status" in ('handed_over')),
  "collection_agency_id" text,
  "collection_handed_at" timestamptz,
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
create index if not exists invoices_tenant_status_idx on "better_supabase"."invoices" ("tenant_id", "status", "due_on");
create index if not exists invoices_origin_idx on "better_supabase"."invoices" ("origin_type", "origin_id");
create index if not exists invoices_original_idx on "better_supabase"."invoices" ("original_id");
create index if not exists invoices_company_idx on "better_supabase"."invoices" ("company_type", "company_id");
alter table "better_supabase"."invoices" add column if not exists "app_note" text;
create index if not exists invoices_purchase_order_idx on "better_supabase"."invoices" ("purchase_order_id");
alter table "better_supabase"."invoices" enable row level security;
revoke all on "better_supabase"."invoices" from public, anon, authenticated;
grant select on "better_supabase"."invoices" to authenticated;
grant all on "better_supabase"."invoices" to service_role;
drop policy if exists invoices_read on "better_supabase"."invoices";
create policy invoices_read on "better_supabase"."invoices"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));

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
  "text_key" text check (length("text_key") between 1 and 200),
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

create table if not exists "better_supabase"."invoice_dunning_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "as_of" date not null,
  "created_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists invoice_dunning_runs_tenant_idx on "better_supabase"."invoice_dunning_runs" ("tenant_id", "created_at" desc);
alter table "better_supabase"."invoice_dunning_runs" enable row level security;
revoke all on "better_supabase"."invoice_dunning_runs" from public, anon, authenticated;
grant select on "better_supabase"."invoice_dunning_runs" to authenticated;
grant all on "better_supabase"."invoice_dunning_runs" to service_role;
drop policy if exists invoice_dunning_runs_read on "better_supabase"."invoice_dunning_runs";
create policy invoice_dunning_runs_read on "better_supabase"."invoice_dunning_runs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));

create table if not exists "better_supabase"."invoice_dunning_run_items" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "run_id" uuid not null references "better_supabase"."invoice_dunning_runs" ("id") on delete cascade,
  "party_id" text,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "level" integer not null check ("level" >= 1),
  "text_key" text,
  "template_key" text not null,
  "fee" bigint not null default 0 check ("fee" >= 0),
  "balance" bigint not null,
  "due_on" date not null,
  "created_at" timestamptz not null default now(),
  unique ("run_id", "invoice_id")
);
create index if not exists invoice_dunning_run_items_run_idx on "better_supabase"."invoice_dunning_run_items" ("run_id", "party_id");
create index if not exists invoice_dunning_run_items_invoice_idx on "better_supabase"."invoice_dunning_run_items" ("invoice_id");
alter table "better_supabase"."invoice_dunning_run_items" enable row level security;
revoke all on "better_supabase"."invoice_dunning_run_items" from public, anon, authenticated;
grant select on "better_supabase"."invoice_dunning_run_items" to authenticated;
grant all on "better_supabase"."invoice_dunning_run_items" to service_role;
drop policy if exists invoice_dunning_run_items_read on "better_supabase"."invoice_dunning_run_items";
create policy invoice_dunning_run_items_read on "better_supabase"."invoice_dunning_run_items"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));

create table if not exists "better_supabase"."invoice_dunning_history" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "run_id" uuid references "better_supabase"."invoice_dunning_runs" ("id") on delete set null,
  "kind" text not null check ("kind" in ('reminder', 'handed_over')),
  "level" integer not null default 0,
  "text_key" text,
  "template_key" text,
  "fee" bigint not null default 0,
  "balance" bigint not null default 0,
  "note" text,
  "created_at" timestamptz not null default clock_timestamp()
);
create index if not exists invoice_dunning_history_invoice_idx on "better_supabase"."invoice_dunning_history" ("invoice_id", "created_at");
create index if not exists invoice_dunning_history_run_idx on "better_supabase"."invoice_dunning_history" ("run_id") where "run_id" is not null;
alter table "better_supabase"."invoice_dunning_history" enable row level security;
revoke all on "better_supabase"."invoice_dunning_history" from public, anon, authenticated;
grant select on "better_supabase"."invoice_dunning_history" to authenticated;
grant all on "better_supabase"."invoice_dunning_history" to service_role;
drop policy if exists invoice_dunning_history_read on "better_supabase"."invoice_dunning_history";
create policy invoice_dunning_history_read on "better_supabase"."invoice_dunning_history"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));

create table if not exists "better_supabase"."invoice_allocations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "reference" text not null check (length("reference") between 1 and 200),
  "party_id" text not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "source" text not null default 'payment' check ("source" in ('payment', 'credit')),
  "amount" bigint not null check ("amount" > 0),
  "discount" bigint not null default 0 check ("discount" >= 0),
  -- The ledger transactions of the cash (or credit) and of the discount.
  "payment_id" uuid,
  "discount_payment_id" uuid,
  "allocated_on" date not null,
  "unallocated_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "reference", "invoice_id")
);
create index if not exists invoice_allocations_invoice_idx on "better_supabase"."invoice_allocations" ("invoice_id");
create index if not exists invoice_allocations_party_idx on "better_supabase"."invoice_allocations" ("tenant_id", "party_id", "created_at" desc);
alter table "better_supabase"."invoice_allocations" enable row level security;
revoke all on "better_supabase"."invoice_allocations" from public, anon, authenticated;
grant select on "better_supabase"."invoice_allocations" to authenticated;
grant all on "better_supabase"."invoice_allocations" to service_role;
drop policy if exists invoice_allocations_read on "better_supabase"."invoice_allocations";
create policy invoice_allocations_read on "better_supabase"."invoice_allocations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));

create table if not exists "better_supabase"."invoice_approval_levels" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- Null: the level counts for every legal entity without levels of its own.
  "legal_entity_id" uuid,
  "level" integer not null check ("level" >= 1),
  "min_amount" bigint not null check ("min_amount" >= 0),
  "currency" text check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "approver_id" uuid not null,
  "created_at" timestamptz not null default now()
);
create unique index if not exists invoice_approval_levels_level_key on "better_supabase"."invoice_approval_levels" ("tenant_id", coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid), "level");
alter table "better_supabase"."invoice_approval_levels" enable row level security;
revoke all on "better_supabase"."invoice_approval_levels" from public, anon, authenticated;
grant select on "better_supabase"."invoice_approval_levels" to authenticated;
grant all on "better_supabase"."invoice_approval_levels" to service_role;
drop policy if exists invoice_approval_levels_read on "better_supabase"."invoice_approval_levels";
create policy invoice_approval_levels_read on "better_supabase"."invoice_approval_levels"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));

create table if not exists "better_supabase"."invoice_approvals" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "level" integer not null check ("level" >= 1),
  "approver_id" uuid not null,
  "comment" text check ("comment" is null or length("comment") <= 2000),
  "decided_at" timestamptz not null default now(),
  unique ("invoice_id", "level")
);
create index if not exists invoice_approvals_tenant_idx on "better_supabase"."invoice_approvals" ("tenant_id", "invoice_id");
alter table "better_supabase"."invoice_approvals" enable row level security;
revoke all on "better_supabase"."invoice_approvals" from public, anon, authenticated;
grant select on "better_supabase"."invoice_approvals" to authenticated;
grant all on "better_supabase"."invoice_approvals" to service_role;
drop policy if exists invoice_approvals_read on "better_supabase"."invoice_approvals";
create policy invoice_approvals_read on "better_supabase"."invoice_approvals"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));

create table if not exists "better_supabase"."invoice_e_endpoints" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "party_kind" text not null check ("party_kind" in ('organization', 'legal_entity', 'company')),
  "party_id" text not null check (length("party_id") between 1 and 150),
  -- The Electronic Address Scheme code from the Peppol EAS list, such as 0106.
  "scheme" text not null check ("scheme" ~ '^[0-9]{4}$'),
  "endpoint_id" text not null check (length("endpoint_id") between 1 and 200),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists invoice_e_endpoints_party_key on "better_supabase"."invoice_e_endpoints" ("tenant_id", "party_kind", "party_id");
create index if not exists invoice_e_endpoints_lookup_idx on "better_supabase"."invoice_e_endpoints" ("tenant_id", "scheme", "endpoint_id");
alter table "better_supabase"."invoice_e_endpoints" enable row level security;
revoke all on "better_supabase"."invoice_e_endpoints" from public, anon, authenticated;
grant select on "better_supabase"."invoice_e_endpoints" to authenticated;
grant all on "better_supabase"."invoice_e_endpoints" to service_role;
drop policy if exists invoice_e_endpoints_read on "better_supabase"."invoice_e_endpoints";
create policy invoice_e_endpoints_read on "better_supabase"."invoice_e_endpoints"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));

create table if not exists "better_supabase"."invoice_e_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "invoice_id" uuid references "better_supabase"."invoices" ("id") on delete set null,
  "direction" text not null check ("direction" in ('outbound', 'inbound')),
  "format" text check ("format" is null or length("format") between 1 and 100),
  "channel" text not null check (length("channel") between 1 and 100),
  "message_id" text not null check (length("message_id") between 1 and 300),
  "state" text not null check ("state" in ('pending', 'delivered', 'rejected', 'received', 'unmatched')),
  "reason" text check ("reason" is null or length("reason") <= 2000),
  "document_hash" text check ("document_hash" is null or "document_hash" ~ '^[0-9a-f]{64}$'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists invoice_e_deliveries_message_key on "better_supabase"."invoice_e_deliveries" ("tenant_id", "channel", "message_id");
create index if not exists invoice_e_deliveries_invoice_idx on "better_supabase"."invoice_e_deliveries" ("invoice_id", "tenant_id");
create index if not exists invoice_e_deliveries_state_idx on "better_supabase"."invoice_e_deliveries" ("tenant_id", "direction", "state");
alter table "better_supabase"."invoice_e_deliveries" enable row level security;
revoke all on "better_supabase"."invoice_e_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."invoice_e_deliveries" to authenticated;
grant all on "better_supabase"."invoice_e_deliveries" to service_role;
drop policy if exists invoice_e_deliveries_read on "better_supabase"."invoice_e_deliveries";
create policy invoice_e_deliveries_read on "better_supabase"."invoice_e_deliveries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));


-- Creates a draft invoice. attrs: title (required), currency, company and
-- contact ({ type, id }), termsDays, note, origin ({ type, id }) and the
-- extra columns by name.
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
    raise exception 'purchase orders need the inventory block' using errcode = '22023', hint = 'INVOICE_PURCHASE_ORDER_UNSUPPORTED';
  end if;
  if create_invoice.attrs ? 'dimensions' and jsonb_typeof(create_invoice.attrs -> 'dimensions') not in ('object', 'null') then
    raise exception 'dimensions is an object of dimension keys and value codes' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_CONTACT_FORBIDDEN';
  end if;
  if create_invoice.attrs ->> 'depositAmount' is not null then
    raise exception 'this invoices table has no deposit amount column' using errcode = '22023', hint = 'INVOICE_DEPOSIT_UNSUPPORTED';
  end if;
  if nullif(create_invoice.attrs ->> 'discountBps', '0') is not null then
    raise exception 'this invoices table has no discount column' using errcode = '22023', hint = 'INVOICE_DISCOUNT_UNSUPPORTED';
  end if;
  if nullif(create_invoice.attrs ->> 'discountAmount', '0') is not null then
    raise exception 'this invoices table has no discount amount column' using errcode = '22023', hint = 'INVOICE_DISCOUNT_UNSUPPORTED';
  end if;
  begin
    insert into "better_supabase"."invoices" ("tenant_id", "title", "company_type", "company_id", "contact_type", "contact_id", "currency",
      "terms_days", "note", "origin_type", "origin_id", "deposit_bps", "prices_include_tax", "direction", "supplier_reference", "purchase_order_id", "dimensions", "created_by", "app_note")
    values (create_invoice.tenant, trim(create_invoice.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      upper(coalesce(create_invoice.attrs ->> 'currency', 'EUR')), case when create_invoice.attrs ? 'termsDays' then (create_invoice.attrs ->> 'termsDays')::integer else 30 end,
      create_invoice.attrs ->> 'note', create_invoice.attrs -> 'origin' ->> 'type', create_invoice.attrs -> 'origin' ->> 'id',
      (create_invoice.attrs ->> 'depositBps')::integer, coalesce((create_invoice.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce(create_invoice.attrs ->> 'direction', 'sales'), nullif(trim(create_invoice.attrs ->> 'supplierReference'), ''), (create_invoice.attrs ->> 'purchaseOrderId')::uuid, coalesce(nullif(create_invoice.attrs -> 'dimensions', 'null'::jsonb), '{}'::jsonb), auth.uid(), case when create_invoice.attrs ? 'app_note' then (jsonb_populate_record(null::"better_supabase"."invoices", jsonb_build_object('app_note', create_invoice.attrs -> 'app_note')))."app_note" else better_supabase.column_default('"better_supabase"."invoices"', 'app_note', (null::"better_supabase"."invoices")."app_note") end)
    returning * into v_row;
  exception when check_violation or invalid_text_representation then
    raise exception 'an invoice field has an invalid value' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end;
  if create_invoice.lines is not null then
    perform "better_supabase"."set_invoice_lines"(v_row."id", create_invoice.lines);
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_invoice"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_invoice"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft's header. attrs: title, company and contact ({ type, id },
-- null clears), termsDays, note, depositBps, pricesIncludeTax and the extra
-- columns by name. A key left out keeps its value.
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
    raise exception 'purchase orders need the inventory block' using errcode = '22023', hint = 'INVOICE_PURCHASE_ORDER_UNSUPPORTED';
  end if;
  if update_invoice.attrs ? 'dimensions' and jsonb_typeof(update_invoice.attrs -> 'dimensions') not in ('object', 'null') then
    raise exception 'dimensions is an object of dimension keys and value codes' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_CONTACT_FORBIDDEN';
  end if;
  if update_invoice.attrs ->> 'depositAmount' is not null then
    raise exception 'this invoices table has no deposit amount column' using errcode = '22023', hint = 'INVOICE_DEPOSIT_UNSUPPORTED';
  end if;
  if nullif(update_invoice.attrs ->> 'discountBps', '0') is not null then
    raise exception 'this invoices table has no discount column' using errcode = '22023', hint = 'INVOICE_DISCOUNT_UNSUPPORTED';
  end if;
  if nullif(update_invoice.attrs ->> 'discountAmount', '0') is not null then
    raise exception 'this invoices table has no discount amount column' using errcode = '22023', hint = 'INVOICE_DISCOUNT_UNSUPPORTED';
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
      "supplier_reference" = case when update_invoice.attrs ? 'supplierReference' then nullif(trim(update_invoice.attrs ->> 'supplierReference'), '') else x."supplier_reference" end,
      "purchase_order_id" = case when update_invoice.attrs ? 'purchaseOrderId' then (update_invoice.attrs ->> 'purchaseOrderId')::uuid else x."purchase_order_id" end,
      "dimensions" = case when update_invoice.attrs ? 'dimensions' then coalesce(nullif(update_invoice.attrs -> 'dimensions', 'null'::jsonb), '{}'::jsonb) else x."dimensions" end,
      "updated_at" = now(), "app_note" = case when update_invoice.attrs ? 'app_note' then (jsonb_populate_record(null::"better_supabase"."invoices", jsonb_build_object('app_note', update_invoice.attrs -> 'app_note')))."app_note" else x."app_note" end
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or not_null_violation then
    raise exception 'an invoice field has an invalid value' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end;
  if update_invoice.attrs ? 'pricesIncludeTax' then
    perform "better_supabase"."set_invoice_lines_recount"(v_row."id");
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
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
  delete from "better_supabase"."invoices" x where x."id" = v_row."id";
  null;
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
  "tax_code_id" uuid,
  "unit_cost" bigint,
  "discount_amount" bigint not null default 0 check ("discount_amount" >= 0),
  "cost_source" text check ("cost_source" in ('catalog', 'average', 'manual', 'imported')),
  "location_id" uuid,
  "bin_id" uuid,
  "billing_party" text not null default 'customer' check ("billing_party" in ('customer', 'internal', 'own_warranty', 'supplier_warranty', 'cost_account')),
  "billing_party_id" text,
  "billing_account_id" uuid,
  "dimensions" jsonb not null default '{}'::jsonb check (jsonb_typeof("dimensions") = 'object'),
  "position" integer not null,
  "created_at" timestamptz not null default now(),
  check (("product_type" is null) = ("product_id" is null))
);
alter table "better_supabase"."invoice_lines" add column if not exists "dimensions" jsonb not null default '{}'::jsonb check (jsonb_typeof("dimensions") = 'object');
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
  v_restriction integer;
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
  select x."tenant_id", x."prices_include_tax", 0, 0, 0
    into v_tenant, v_inclusive, v_record_bps, v_record_amount, v_restriction
  from "better_supabase"."invoices" x where x."id" = set_invoice_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * l."unit_amount")), 0), coalesce(sum((round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0)))), 0)
    into v_list, v_line_discount
  from "better_supabase"."invoice_lines" l where l."parent_id" = set_invoice_lines_recount.parent and true;
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * l."unit_amount") - (round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) as amount,
      sum(round((round(l."quantity" * l."unit_amount") - (round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * (10000 - v_restriction) * l."tax_rate_bps" / (10000.0 * (case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)))) as tax
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
      s.tax - round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end))) as tax
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
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "dimensions", "position")
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
      nullif(x.value ->> 'taxCodeId', '')::uuid,
      (x.value ->> 'unitCost')::bigint,
      coalesce((x.value ->> 'discountAmount')::bigint, 0),
      nullif(x.value ->> 'costSource', ''),
      nullif(x.value ->> 'locationId', '')::uuid,
      nullif(x.value ->> 'binId', '')::uuid,
      coalesce(nullif(x.value ->> 'billingParty', ''), 'customer'),
      nullif(x.value ->> 'billingPartyId', ''),
      nullif(x.value ->> 'billingAccountId', '')::uuid,
      coalesce(nullif(x.value -> 'dimensions', 'null'::jsonb), '{}'::jsonb),
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
drop function if exists "better_supabase"."issue_invoice"(uuid, date, date, jsonb);
-- fixed_number: a historical number to keep as is, only while an import runs
-- (better_supabase.import_run()); NUMBER_FIXED_FORBIDDEN otherwise. The counter
-- of its series (kind, direction, legal entity, period) rises to it.
create or replace function "better_supabase"."issue_invoice"(invoice uuid, issued_on date, due_on date default null, actor jsonb default null, fixed_number text default null)
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
  v_warnings jsonb;
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
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_credit_note', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'BCN-' || v_seq::text;
  end if;
    else
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'credit_note' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':credit_note', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'CN-' || v_seq::text;
  end if;
    end if;
  else
    if v_row."direction" = 'purchase' then
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_bill' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'purchase_bill' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':purchase_bill', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'purchase' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'BILL-' || v_seq::text;
  end if;
    else
      if coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'invoice' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end)) is not null then
    v_identifier := coalesce(issue_invoice.fixed_number, (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'invoice' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end));
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':invoice', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."direction" = 'sales' and k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'INV-' || v_seq::text;
  end if;
    end if;
  end if;
  update "better_supabase"."invoices" x set "status" = 'issued', "number" = v_seq, "identifier" = v_identifier,
    "issued_on" = v_issued_on,
    "due_on" = coalesce(issue_invoice.due_on, v_issued_on + x."terms_days"),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
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
    null;
    if v_original."status" = 'paid' then
      null;
    end if;
  end if;
  
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_issue"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb))|| case when v_warnings is null then '{}'::jsonb else jsonb_build_object('warnings', v_warnings) end;
end;
$$;
revoke execute on function "better_supabase"."issue_invoice"(uuid, date, date, jsonb, text) from public, anon;
grant execute on function "better_supabase"."issue_invoice"(uuid, date, date, jsonb, text) to authenticated, service_role;

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
    return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
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
  
  perform set_config('better_supabase.transition_reason', '', true);
  null;
  if v_row."status" = 'paid' and v_was <> 'paid' then
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_invoice_payment"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using v_row."id", v_payment;
    end if;
  end;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
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
-- lines for a partial credit. Issue it to apply it. fixed_number: during an
-- import (better_supabase.import_run()), a historical credit note number; the
-- credit note is then issued at once on issued_on (today by default) with that
-- number. NUMBER_FIXED_FORBIDDEN outside an import.
drop function if exists "better_supabase"."credit_invoice"(uuid, jsonb, text);
create or replace function "better_supabase"."credit_invoice"(invoice uuid, lines jsonb, note text, fixed_number text default null, issued_on date default null)
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
  if credit_invoice.fixed_number is not null and better_supabase.import_run() is null then
    raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
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
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position")
    select x."tenant_id", v_row."id", x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position"
    from "better_supabase"."invoice_lines" x where x."parent_id" = v_original."id";
  else
    perform "better_supabase"."set_invoice_lines"(v_row."id", credit_invoice.lines);
  end if;
  null;
  if credit_invoice.fixed_number is not null then
    perform "better_supabase"."issue_invoice"(v_row."id", coalesce(credit_invoice.issued_on, current_date), null, null, credit_invoice.fixed_number);
  end if;
  return (select to_jsonb(x) || jsonb_build_object('number', x."number"::text, 'paid_total', x."paid_total"::text, 'credited_total', x."credited_total"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount_early', x."discount_amount_early"::text) || jsonb_build_object(
      'balance', (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), '[]'::jsonb),
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text)), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."credit_invoice"(uuid, jsonb, text, text, date) from public, anon;
grant execute on function "better_supabase"."credit_invoice"(uuid, jsonb, text, text, date) to authenticated, service_role;

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
  
  perform set_config('better_supabase.transition_reason', '', true);
  null;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
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
  
  perform set_config('better_supabase.transition_reason', '', true);
  null;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
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
  
  perform set_config('better_supabase.transition_reason', '', true);
  null;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
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
  
  null;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
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
  
  null;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
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
  v_result := jsonb_build_object('invoiceId', v_row."id", 'currency', v_row."currency", 'purchaseOrderId', null, 'status', 'matched', 'lines', '[]'::jsonb);
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
  null;
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
  null;
  if v_row."status" = 'paid' and v_was <> 'paid' then
    null;
  end if;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
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
  return coalesce((select jsonb_agg(jsonb_build_object('level', l."level", 'daysAfterDue', l."days_after_due", 'templateKey', l."template_key", 'textKey', l."text_key", 'fee', l."fee"::text, 'final', l."final") order by l."level") from "better_supabase"."invoice_dunning_levels" l where l."tenant_id" = list_invoice_dunning_levels.tenant), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_invoice_dunning_levels"(uuid) from public, anon;
grant execute on function "better_supabase"."list_invoice_dunning_levels"(uuid) to authenticated, service_role;

-- Replaces an organization's reminder levels. levels: [{ daysAfterDue,
-- templateKey, textKey, fee, final }], numbered 1, 2, ... in order, with daysAfterDue
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
        or length(coalesce(nullif(trim(x.value ->> 'textKey'), ''), 'x')) not between 1 and 200
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
  insert into "better_supabase"."invoice_dunning_levels" ("tenant_id", "level", "days_after_due", "template_key", "text_key", "fee", "final")
  select set_invoice_dunning_levels.tenant, x.ordinality, (x.value ->> 'daysAfterDue')::integer, trim(x.value ->> 'templateKey'),
    nullif(trim(x.value ->> 'textKey'), ''),
    coalesce((x.value ->> 'fee')::bigint, 0), coalesce((x.value ->> 'final')::boolean, false)
  from jsonb_array_elements(set_invoice_dunning_levels.levels) with ordinality x;
  return coalesce((select jsonb_agg(jsonb_build_object('level', l."level", 'daysAfterDue', l."days_after_due", 'templateKey', l."template_key", 'textKey', l."text_key", 'fee', l."fee"::text, 'final', l."final") order by l."level") from "better_supabase"."invoice_dunning_levels" l where l."tenant_id" = set_invoice_dunning_levels.tenant), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."set_invoice_dunning_levels"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_invoice_dunning_levels"(uuid, jsonb) to authenticated, service_role;

-- Raises each overdue invoice with a balance to the highest reminder level it
-- has reached (one organization, or all), adds the level's fee as a charge,
-- notifies who created the invoice and records invoice.dunning_escalated with
-- the level's template key, for a sink that sends the reminder. Each
-- organization's invoices go into one run (invoice_dunning_runs) with the
-- items picked per customer and a history row per invoice. Invoices paused
-- until today or later, and invoices handed over to collection, wait. Returns how many invoices moved up.
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
  v_run uuid;
  v_run_tenant uuid;
begin
  for v_row in
    select x.* from "better_supabase"."invoices" x
    where (run_invoice_dunning.tenant is null or x."tenant_id" = run_invoice_dunning.tenant)
      and x."kind" = 'invoice' and x."status" in ('issued', 'partially_paid') and x."direction" = 'sales'
      and x."due_on" < v_today
      and x."collection_status" is null
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
    null;

    if v_run is null or v_run_tenant is distinct from v_row."tenant_id" then
      insert into "better_supabase"."invoice_dunning_runs" ("tenant_id", "as_of", "created_by")
      values (v_row."tenant_id", v_today, auth.uid())
      returning "id" into v_run;
      v_run_tenant := v_row."tenant_id";
    end if;
    insert into "better_supabase"."invoice_dunning_run_items" ("tenant_id", "run_id", "party_id", "invoice_id", "level", "text_key", "template_key", "fee", "balance", "due_on")
    values (v_row."tenant_id", v_run, coalesce(v_row."company_id"::text, v_row."contact_id"::text), v_row."id", v_level."level", v_level."text_key", v_level."template_key", v_level."fee", (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total"), v_row."due_on");
    insert into "better_supabase"."invoice_dunning_history" ("tenant_id", "invoice_id", "run_id", "kind", "level", "text_key", "template_key", "fee", "balance")
    values (v_row."tenant_id", v_row."id", v_run, 'reminder', v_level."level", v_level."text_key", v_level."template_key", v_level."fee", (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total"));
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
  null;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."pause_invoice_dunning"(uuid, date, text) from public, anon;
grant execute on function "better_supabase"."pause_invoice_dunning"(uuid, date, text) to authenticated, service_role;

-- The dunning runs of an organization, newest first: { id, asOf, items,
-- customers }.
create or replace function "better_supabase"."list_invoice_dunning_runs"(tenant uuid, max integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_invoice_dunning_runs.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', z.id, 'asOf', z.as_of, 'createdAt', z.created_at, 'items', z.items, 'customers', z.customers) order by z.created_at desc)
    from (
      select a."id" as id, a."as_of" as as_of, a."created_at" as created_at,
        (select count(*) from "better_supabase"."invoice_dunning_run_items" x where x."run_id" = a."id") as items,
        (select count(distinct x."party_id") from "better_supabase"."invoice_dunning_run_items" x where x."run_id" = a."id") as customers
      from "better_supabase"."invoice_dunning_runs" a where a."tenant_id" = list_invoice_dunning_runs.tenant
      order by a."created_at" desc limit least(greatest(coalesce(list_invoice_dunning_runs.max, 50), 1), 500)
    ) z
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_invoice_dunning_runs"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_invoice_dunning_runs"(uuid, integer) to authenticated, service_role;

-- The items a run picked, grouped by customer: [{ partyId, balance, fee,
-- items: [{ invoiceId, level, textKey, templateKey, fee, balance, dueOn }] }].
-- Amounts are text.
create or replace function "better_supabase"."list_invoice_dunning_run_items"(run uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select a."tenant_id" into v_tenant from "better_supabase"."invoice_dunning_runs" a where a."id" = list_invoice_dunning_run_items.run;
  if v_tenant is null then
    raise exception 'no such dunning run' using errcode = 'P0002', hint = 'INVOICE_DUNNING_RUN_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('partyId', g.party, 'balance', g.balance::text, 'fee', g.fee::text, 'items', g.items) order by g.party nulls last)
    from (
      select x."party_id" as party, sum(x."balance") as balance, sum(x."fee") as fee,
        jsonb_agg(jsonb_build_object('invoiceId', x."invoice_id", 'level', x."level", 'textKey', x."text_key", 'templateKey', x."template_key",
          'fee', x."fee"::text, 'balance', x."balance"::text, 'dueOn', x."due_on") order by x."due_on", x."invoice_id") as items
      from "better_supabase"."invoice_dunning_run_items" x where x."run_id" = list_invoice_dunning_run_items.run
      group by x."party_id"
    ) g
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_invoice_dunning_run_items"(uuid) from public, anon;
grant execute on function "better_supabase"."list_invoice_dunning_run_items"(uuid) to authenticated, service_role;

-- What happened to an invoice in collections, oldest first: [{ kind
-- (reminder or handed_over), level, textKey, templateKey, fee, balance, note,
-- runId, at }].
create or replace function "better_supabase"."list_invoice_dunning_history"(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."invoices" x where x."id" = list_invoice_dunning_history.invoice;
  if v_tenant is null then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('kind', x."kind", 'level', x."level", 'textKey', x."text_key", 'templateKey', x."template_key",
      'fee', x."fee"::text, 'balance', x."balance"::text, 'note', x."note", 'runId', x."run_id", 'at', x."created_at")
      order by x."created_at", x."id")
    from "better_supabase"."invoice_dunning_history" x where x."invoice_id" = list_invoice_dunning_history.invoice
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_invoice_dunning_history"(uuid) from public, anon;
grant execute on function "better_supabase"."list_invoice_dunning_history"(uuid) to authenticated, service_role;

-- Hands open sales invoices over to a collection agency, a company or person
-- (agency_party_id). Their dunning stops, collection_status becomes
-- handed_over, and each invoice records invoice.collection_started and
-- a history row. At most 500 invoices; one that isn't an open sales invoice,
-- or was handed over already, refuses the whole call. Needs invoices.collect.
-- Returns the invoices.
create or replace function "better_supabase"."hand_over_to_collection"(invoice_ids uuid[], agency_party_id text, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_id uuid;
  v_result jsonb := '[]'::jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if nullif(trim(hand_over_to_collection.agency_party_id), '') is null or length(hand_over_to_collection.agency_party_id) > 150
    or coalesce(array_length(hand_over_to_collection.invoice_ids, 1), 0) not between 1 and 500
    or length(hand_over_to_collection.note) > 2000 then
    raise exception 'hand over 1 to 500 invoices to an agency party, with a note of at most 2000 characters' using errcode = '22023', hint = 'INVOICE_HAND_OVER_INVALID';
  end if;
  for v_id in select distinct x from unnest(hand_over_to_collection.invoice_ids) x order by x loop
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", case when x."direction" = 'purchase' then 'invoices.purchase' else 'invoices.collect' end), false)) for update;
    if v_row."id" is null then
      raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
    end if;
    if not v_row."kind" = 'invoice' or v_row."status" not in ('issued', 'partially_paid') or v_row."direction" <> 'sales' then
      raise exception 'only an open sales invoice goes to collection' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
    end if;
    if v_row."collection_status" is not null then
      raise exception 'the invoice was handed over to collection already' using errcode = '55000', hint = 'INVOICE_ALREADY_HANDED_OVER';
    end if;
    update "better_supabase"."invoices" x set
      "collection_status" = 'handed_over',
      "collection_agency_id" = trim(hand_over_to_collection.agency_party_id),
      "collection_handed_at" = now(),
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
    insert into "better_supabase"."invoice_dunning_history" ("tenant_id", "invoice_id", "kind", "level", "balance", "note")
    values (v_row."tenant_id", v_row."id", 'handed_over', v_row."dunning_level", (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total"), nullif(trim(hand_over_to_collection.note), ''));
    null;
    v_result := v_result || to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb));
  end loop;
  return v_result;
end;
$$;
revoke execute on function "better_supabase"."hand_over_to_collection"(uuid[], text, text) from public, anon;
grant execute on function "better_supabase"."hand_over_to_collection"(uuid[], text, text) to authenticated, service_role;

-- The approval a purchase bill needs: the levels of its legal entity (or the
-- organization's, when the entity has none) whose minimum amount the bill's
-- total reaches in the level's currency. Every such level needs its approver.
-- Returns { status, required, approved, pending }; status is not_required,
-- pending or approved. Internal: payment batches call it.
create or replace function "better_supabase"."invoice_approval_state"(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_entity uuid;
  v_scoped boolean;
  v_required jsonb;
  v_approved jsonb;
  v_pending jsonb;
  v_status text;
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = invoice_approval_state.invoice;
  if not found then
    return null;
  end if;
  if v_row."direction" <> 'purchase' or v_row."kind" <> 'invoice' then
    return jsonb_build_object('status', 'not_required', 'required', '[]'::jsonb, 'approved', '[]'::jsonb, 'pending', '[]'::jsonb);
  end if;
  v_entity := null::uuid;
  v_scoped := v_entity is not null and exists (
    select 1 from "better_supabase"."invoice_approval_levels" l where l."tenant_id" = v_row."tenant_id" and l."legal_entity_id" = v_entity
  );
  select coalesce(jsonb_agg(l."level" order by l."level"), '[]'::jsonb),
    coalesce(jsonb_agg(l."level" order by l."level") filter (where a."id" is not null), '[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object('level', l."level", 'approverId', l."approver_id", 'minAmount', l."min_amount"::text) order by l."level") filter (where a."id" is null), '[]'::jsonb)
  into v_required, v_approved, v_pending
  from "better_supabase"."invoice_approval_levels" l
  left join "better_supabase"."invoice_approvals" a on a."invoice_id" = v_row."id" and a."level" = l."level"
  where l."tenant_id" = v_row."tenant_id"
    and l."legal_entity_id" is not distinct from (case when v_scoped then v_entity end)
    and l."min_amount" <= v_row."total"
    and (l."currency" is null or l."currency" = v_row."currency"::text);
  v_status := case when jsonb_array_length(v_required) = 0 then 'not_required'
    when jsonb_array_length(v_pending) = 0 then 'approved' else 'pending' end;
  return jsonb_build_object('status', v_status, 'required', v_required, 'approved', v_approved, 'pending', v_pending);
end;
$$;
revoke execute on function "better_supabase"."invoice_approval_state"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."invoice_approval_state"(uuid) to service_role;
revoke execute on function "better_supabase"."invoice_approval_state"(uuid) from public, anon, authenticated;

-- Replaces the approval levels of an organization, or of one legal entity.
-- levels: [{ minAmount, currency?, approverId }]; they are numbered from 1 in
-- order of minAmount. A bill needs every level its total reaches, so a
-- bigger bill needs more approvers. Approvals already given keep their level
-- number. Needs invoices.manage.
create or replace function "better_supabase"."set_invoice_approval_levels"(tenant uuid, levels jsonb, legal_entity_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', set_invoice_approval_levels.tenant, 'invoices.manage'), false)) then
    raise exception 'not allowed to manage invoices in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if jsonb_typeof(set_invoice_approval_levels.levels) is distinct from 'array'
    or jsonb_array_length(set_invoice_approval_levels.levels) > 20
    or exists (
      select 1 from jsonb_array_elements(set_invoice_approval_levels.levels) x
      where jsonb_typeof(x.value) <> 'object'
        or coalesce(x.value ->> 'minAmount', '') !~ '^[0-9]{1,18}$'
        or coalesce(x.value ->> 'approverId', '') !~ '^[0-9a-fA-F-]{36}$'
        or (x.value ->> 'currency' is not null and upper(x.value ->> 'currency') !~ '^[A-Z]{3}$')
    ) then
    raise exception 'levels is an array of at most 20 { minAmount, currency?, approverId }' using errcode = '22023', hint = 'INVOICE_APPROVAL_LEVELS_INVALID';
  end if;
  delete from "better_supabase"."invoice_approval_levels" l
  where l."tenant_id" = set_invoice_approval_levels.tenant
    and l."legal_entity_id" is not distinct from set_invoice_approval_levels.legal_entity_id;
  insert into "better_supabase"."invoice_approval_levels" ("tenant_id", "legal_entity_id", "level", "min_amount", "currency", "approver_id")
  select set_invoice_approval_levels.tenant, set_invoice_approval_levels.legal_entity_id,
    (row_number() over (order by (x.value ->> 'minAmount')::bigint, x.ordinality))::integer,
    (x.value ->> 'minAmount')::bigint, upper(nullif(x.value ->> 'currency', '')), (x.value ->> 'approverId')::uuid
  from jsonb_array_elements(set_invoice_approval_levels.levels) with ordinality x;
  return "better_supabase"."list_invoice_approval_levels"(set_invoice_approval_levels.tenant);
end;
$$;
revoke execute on function "better_supabase"."set_invoice_approval_levels"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."set_invoice_approval_levels"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_invoice_approval_levels"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_invoice_approval_levels.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('legalEntityId', l."legal_entity_id", 'level', l."level",
        'minAmount', l."min_amount"::text, 'currency', l."currency", 'approverId', l."approver_id")
      order by l."legal_entity_id" nulls first, l."level")
    from "better_supabase"."invoice_approval_levels" l where l."tenant_id" = list_invoice_approval_levels.tenant
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_invoice_approval_levels"(uuid) from public, anon;
grant execute on function "better_supabase"."list_invoice_approval_levels"(uuid) to authenticated, service_role;

-- The approval of a purchase bill: its status and the levels required,
-- approved and pending.
create or replace function "better_supabase"."purchase_invoice_approval_status"(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = purchase_invoice_approval_status.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false));
  if v_row."id" is null then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  return "better_supabase"."invoice_approval_state"(v_row."id");
end;
$$;
revoke execute on function "better_supabase"."purchase_invoice_approval_status"(uuid) from public, anon;
grant execute on function "better_supabase"."purchase_invoice_approval_status"(uuid) to authenticated, service_role;

-- Approves a purchase bill at every pending level the caller is the approver
-- of; the service role approves the lowest pending level for its approver.
-- Needs invoices.approve and an open bill. Returns the bill with its approval.
create or replace function "better_supabase"."approve_purchase_invoice"(invoice uuid, comment text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_state jsonb;
  v_level record;
  v_actor uuid := auth.uid();
  v_done integer := 0;
  v_last integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x
  where x."id" = approve_purchase_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.approve'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can approve' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."direction" <> 'purchase' or v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid') then
    raise exception 'only an open purchase bill is approved' using errcode = '55000', hint = 'INVOICE_NOT_APPROVABLE';
  end if;
  if length(approve_purchase_invoice.comment) > 2000 then
    raise exception 'a comment has at most 2000 characters' using errcode = '22023', hint = 'INVOICE_APPROVAL_INVALID';
  end if;
  v_state := "better_supabase"."invoice_approval_state"(v_row."id");
  if v_state ->> 'status' = 'not_required' then
    raise exception 'no approval level applies to this bill' using errcode = '55000', hint = 'INVOICE_APPROVAL_NOT_REQUIRED';
  end if;
  if v_state ->> 'status' = 'approved' then
    raise exception 'the bill has every approval it needs' using errcode = '55000', hint = 'INVOICE_ALREADY_APPROVED';
  end if;
  for v_level in
    select (p.value ->> 'level')::integer as level, (p.value ->> 'approverId')::uuid as approver
    from jsonb_array_elements(v_state -> 'pending') p
    order by 1
  loop
    if (v_actor is null and v_done = 0) or v_level.approver = v_actor then
      insert into "better_supabase"."invoice_approvals" ("tenant_id", "invoice_id", "level", "approver_id", "comment")
      values (v_row."tenant_id", v_row."id", v_level.level, v_level.approver, nullif(trim(approve_purchase_invoice.comment), ''));
      v_done := v_done + 1;
      v_last := v_level.level;
    end if;
  end loop;
  if v_done = 0 then
    raise exception 'the caller is not the approver of a pending level' using errcode = '42501', hint = 'INVOICE_APPROVER_FORBIDDEN';
  end if;
  v_state := "better_supabase"."invoice_approval_state"(v_row."id");
  null;
  return to_jsonb(v_row) || jsonb_build_object('number', v_row."number"::text, 'paid_total', v_row."paid_total"::text, 'credited_total', v_row."credited_total"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount_early', v_row."discount_amount_early"::text) || jsonb_build_object(
      'balance', (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total")::text,
      'charged_total', coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0)::text,
      'charges', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', y."amount"::text, 'description', y."description", 'createdAt', y."created_at") order by y."created_at") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), '[]'::jsonb),
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code", 'taxCodeId', il."tax_code_id", 'unitCost', il."unit_cost"::text, 'dimensions', il."dimensions") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'amount', (-e."amount")::text, 'paidAt', y."effective_at", 'method', y."metadata" ->> 'method', 'reference', y."metadata" ->> 'reference', 'note', y."metadata" ->> 'note', 'recordedBy', y."actor_id") order by y."effective_at", y."created_at")
        from "better_supabase"."ledger_entries" e join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
        where e."account_id" = (select a."id" from "better_supabase"."ledger_accounts" a where a."tenant_id" = v_row."tenant_id" and a."code" = 'invoice:' || v_row."id"::text)), '[]'::jsonb)) || jsonb_build_object('approval', v_state);
end;
$$;
revoke execute on function "better_supabase"."approve_purchase_invoice"(uuid, text) from public, anon;
grant execute on function "better_supabase"."approve_purchase_invoice"(uuid, text) to authenticated, service_role;

-- Sets the Peppol participant id of an organization ('organization' with the
-- organization id), a legal entity or a company. A null scheme and endpoint
-- remove it. Needs invoices.manage.
create or replace function "better_supabase"."set_invoice_e_endpoint"(tenant uuid, party_kind text, party_id text, scheme text default null, endpoint_id text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."invoice_e_endpoints";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', set_invoice_e_endpoint.tenant, 'invoices.manage'), false)) then
    raise exception 'not allowed to manage invoices in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if set_invoice_e_endpoint.party_kind not in ('organization', 'legal_entity', 'company')
    or nullif(trim(set_invoice_e_endpoint.party_id), '') is null
    or length(set_invoice_e_endpoint.party_id) > 150 then
    raise exception 'party_kind is organization, legal_entity or company, and party_id is a non-empty text of at most 150 characters' using errcode = '22023', hint = 'EINVOICE_ENDPOINT_INVALID';
  end if;
  if set_invoice_e_endpoint.scheme is null and set_invoice_e_endpoint.endpoint_id is null then
    delete from "better_supabase"."invoice_e_endpoints" x
    where x."tenant_id" = set_invoice_e_endpoint.tenant
      and x."party_kind" = set_invoice_e_endpoint.party_kind
      and x."party_id" = set_invoice_e_endpoint.party_id;
    return null;
  end if;
  if set_invoice_e_endpoint.scheme !~ '^[0-9]{4}$'
    or nullif(trim(set_invoice_e_endpoint.endpoint_id), '') is null
    or length(set_invoice_e_endpoint.endpoint_id) > 200 then
    raise exception 'an endpoint is a four-digit EAS scheme and a non-empty id of at most 200 characters' using errcode = '22023', hint = 'EINVOICE_ENDPOINT_INVALID';
  end if;
  insert into "better_supabase"."invoice_e_endpoints" ("tenant_id", "party_kind", "party_id", "scheme", "endpoint_id")
  values (set_invoice_e_endpoint.tenant, set_invoice_e_endpoint.party_kind, set_invoice_e_endpoint.party_id, set_invoice_e_endpoint.scheme, trim(set_invoice_e_endpoint.endpoint_id))
  on conflict ("tenant_id", "party_kind", "party_id") do update
    set "scheme" = excluded."scheme", "endpoint_id" = excluded."endpoint_id", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('scheme', v_row."scheme", 'id', v_row."endpoint_id");
end;
$$;
revoke execute on function "better_supabase"."set_invoice_e_endpoint"(uuid, text, text, text, text) from public, anon;
grant execute on function "better_supabase"."set_invoice_e_endpoint"(uuid, text, text, text, text) to authenticated, service_role;

-- The Peppol participant ids of an invoice: the seller (its legal entity, else
-- the organization) and the buyer (its company). Each is null when none is set.
create or replace function "better_supabase"."invoice_e_endpoints"(invoice uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_seller jsonb;
  v_buyer jsonb;
begin
  select * into v_row from "better_supabase"."invoices" x where x."id" = invoice_e_endpoints.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.read'), false));
  if v_row."id" is null then
    raise exception 'no such invoice you can read' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  select coalesce(
    (select jsonb_build_object('scheme', e."scheme", 'id', e."endpoint_id") from "better_supabase"."invoice_e_endpoints" e where e."tenant_id" = v_row."tenant_id" and e."party_kind" = 'legal_entity' and e."party_id" = null::text),
    (select jsonb_build_object('scheme', e."scheme", 'id', e."endpoint_id") from "better_supabase"."invoice_e_endpoints" e where e."tenant_id" = v_row."tenant_id" and e."party_kind" = 'organization' and e."party_id" = v_row."tenant_id"::text)
  ) into v_seller;
  select jsonb_build_object('scheme', e."scheme", 'id', e."endpoint_id") into v_buyer from "better_supabase"."invoice_e_endpoints" e
  where e."tenant_id" = v_row."tenant_id" and e."party_kind" = 'company' and e."party_id" = v_row."company_id"::text;
  return jsonb_build_object('seller', v_seller, 'buyer', v_buyer);
end;
$$;
revoke execute on function "better_supabase"."invoice_e_endpoints"(uuid) from public, anon;
grant execute on function "better_supabase"."invoice_e_endpoints"(uuid) to authenticated, service_role;

-- The party that has a participant id: { partyKind, partyId }, or null. A
-- received document's supplier is found by it.
create or replace function "better_supabase"."find_e_endpoint_party"(tenant uuid, scheme text, endpoint_id text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', find_e_endpoint_party.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return (
    select jsonb_build_object('partyKind', e."party_kind", 'partyId', e."party_id")
    from "better_supabase"."invoice_e_endpoints" e
    where e."tenant_id" = find_e_endpoint_party.tenant
      and e."scheme" = find_e_endpoint_party.scheme
      and lower(e."endpoint_id") = lower(find_e_endpoint_party.endpoint_id)
    order by case e."party_kind" when 'company' then 0 else 1 end, e."created_at"
    limit 1
  );
end;
$$;
revoke execute on function "better_supabase"."find_e_endpoint_party"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."find_e_endpoint_party"(uuid, text, text) to authenticated, service_role;

-- Records a document a channel took from the app (outbound, pending) or
-- delivered to it (inbound, received with an invoice, else unmatched). A repeat
-- of the same channel and message id changes nothing and returns created =
-- false. Needs invoices.send. Returns { created, delivery }.
create or replace function "better_supabase"."record_e_invoice_delivery"(tenant uuid, direction text, channel text, message_id text, format text default null, state text default null, invoice uuid default null, reason text default null, document_hash text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."invoices";
  v_delivery "better_supabase"."invoice_e_deliveries";
  v_state text;
  v_created boolean := true;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', record_e_invoice_delivery.tenant, 'invoices.send'), false)) then
    raise exception 'not allowed to send invoices in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if record_e_invoice_delivery.direction not in ('outbound', 'inbound') then
    raise exception 'direction is outbound or inbound' using errcode = '22023', hint = 'EINVOICE_DELIVERY_INVALID';
  end if;
  v_state := coalesce(record_e_invoice_delivery.state, case
    when record_e_invoice_delivery.direction = 'outbound' then 'pending'
    when record_e_invoice_delivery.invoice is null then 'unmatched'
    else 'received' end);
  if v_state not in ('pending', 'delivered', 'rejected', 'received', 'unmatched')
    or (record_e_invoice_delivery.direction = 'outbound' and v_state in ('received', 'unmatched'))
    or (record_e_invoice_delivery.direction = 'inbound' and v_state in ('pending', 'delivered', 'rejected'))
    or (v_state in ('pending', 'delivered', 'rejected') and record_e_invoice_delivery.invoice is null)
    or nullif(trim(record_e_invoice_delivery.channel), '') is null
    or nullif(trim(record_e_invoice_delivery.message_id), '') is null then
    raise exception 'a delivery needs a channel and a message id, and a state that fits its direction (an outbound one an invoice)' using errcode = '22023', hint = 'EINVOICE_DELIVERY_INVALID';
  end if;
  if record_e_invoice_delivery.invoice is not null then
    select * into v_row from "better_supabase"."invoices" x
    where x."id" = record_e_invoice_delivery.invoice and x."tenant_id" = record_e_invoice_delivery.tenant;
    if v_row."id" is null then
      raise exception 'no such invoice in this organization' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
    end if;
  end if;
  insert into "better_supabase"."invoice_e_deliveries" ("tenant_id", "invoice_id", "direction", "format", "channel", "message_id", "state", "reason", "document_hash")
  values (record_e_invoice_delivery.tenant, record_e_invoice_delivery.invoice, record_e_invoice_delivery.direction, nullif(trim(record_e_invoice_delivery.format), ''), record_e_invoice_delivery.channel, record_e_invoice_delivery.message_id, v_state, nullif(trim(record_e_invoice_delivery.reason), ''), record_e_invoice_delivery.document_hash)
  on conflict ("tenant_id", "channel", "message_id") do nothing
  returning * into v_delivery;
  if v_delivery."id" is null then
    v_created := false;
    select * into v_delivery from "better_supabase"."invoice_e_deliveries" x
    where x."tenant_id" = record_e_invoice_delivery.tenant and x."channel" = record_e_invoice_delivery.channel and x."message_id" = record_e_invoice_delivery.message_id;
  elsif v_row."id" is not null then
    if v_state = 'received' then
      null;
    else
      null;
    end if;
  end if;
  return jsonb_build_object('created', v_created, 'delivery', jsonb_build_object('id', v_delivery."id", 'organizationId', v_delivery."tenant_id", 'invoiceId', v_delivery."invoice_id", 'direction', v_delivery."direction", 'format', v_delivery."format", 'channel', v_delivery."channel", 'messageId', v_delivery."message_id", 'state', v_delivery."state", 'reason', v_delivery."reason", 'documentHash', v_delivery."document_hash", 'createdAt', v_delivery."created_at", 'updatedAt', v_delivery."updated_at"));
end;
$$;
revoke execute on function "better_supabase"."record_e_invoice_delivery"(uuid, text, text, text, text, text, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."record_e_invoice_delivery"(uuid, text, text, text, text, text, uuid, text, text) to authenticated, service_role;

-- Moves a delivery on: a pending one to delivered or rejected, an unmatched
-- one to received (with the invoice it became) or unmatched again with a new
-- reason. Needs invoices.send. Returns the delivery.
create or replace function "better_supabase"."set_e_invoice_delivery_state"(delivery uuid, state text, reason text default null, invoice uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_delivery "better_supabase"."invoice_e_deliveries";
  v_row "better_supabase"."invoices";
  v_target uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_delivery from "better_supabase"."invoice_e_deliveries" x
  where x."id" = set_e_invoice_delivery_state.delivery and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.send'), false)) for update;
  if v_delivery."id" is null then
    raise exception 'no such delivery you can update' using errcode = 'P0002', hint = 'EINVOICE_DELIVERY_NOT_FOUND';
  end if;
  if not (
    (v_delivery."state" = 'pending' and set_e_invoice_delivery_state.state in ('delivered', 'rejected'))
    or (v_delivery."state" = 'unmatched' and set_e_invoice_delivery_state.state in ('received', 'unmatched'))
  ) then
    raise exception 'a pending delivery becomes delivered or rejected, an unmatched one received or unmatched' using errcode = '55000', hint = 'EINVOICE_DELIVERY_STATE';
  end if;
  v_target := coalesce(set_e_invoice_delivery_state.invoice, v_delivery."invoice_id");
  if set_e_invoice_delivery_state.state = 'received' and v_target is null then
    raise exception 'a received delivery names the invoice it became' using errcode = '22023', hint = 'EINVOICE_DELIVERY_INVALID';
  end if;
  if v_target is not null then
    select * into v_row from "better_supabase"."invoices" x
    where x."id" = v_target and x."tenant_id" = v_delivery."tenant_id";
    if v_row."id" is null then
      raise exception 'no such invoice in this organization' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
    end if;
  end if;
  update "better_supabase"."invoice_e_deliveries" x set
    "state" = set_e_invoice_delivery_state.state,
    "reason" = nullif(trim(set_e_invoice_delivery_state.reason), ''),
    "invoice_id" = v_target,
    "updated_at" = now()
  where x."id" = v_delivery."id"
  returning * into v_delivery;
  if v_row."id" is not null and v_delivery."state" <> 'unmatched' then
    if v_delivery."state" = 'delivered' then
      null;
    elsif v_delivery."state" = 'rejected' then
      null;
    else
      null;
    end if;
  end if;
  return jsonb_build_object('id', v_delivery."id", 'organizationId', v_delivery."tenant_id", 'invoiceId', v_delivery."invoice_id", 'direction', v_delivery."direction", 'format', v_delivery."format", 'channel', v_delivery."channel", 'messageId', v_delivery."message_id", 'state', v_delivery."state", 'reason', v_delivery."reason", 'documentHash', v_delivery."document_hash", 'createdAt', v_delivery."created_at", 'updatedAt', v_delivery."updated_at");
end;
$$;
revoke execute on function "better_supabase"."set_e_invoice_delivery_state"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."set_e_invoice_delivery_state"(uuid, text, text, uuid) to authenticated, service_role;

-- The deliveries of an organization, newest first, at most 500, filtered by
-- direction, state or invoice.
create or replace function "better_supabase"."list_e_invoice_deliveries"(tenant uuid, direction text default null, state text default null, invoice uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_e_invoice_deliveries.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'invoiceId', x."invoice_id", 'direction', x."direction", 'format', x."format", 'channel', x."channel", 'messageId', x."message_id", 'state', x."state", 'reason', x."reason", 'documentHash', x."document_hash", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."created_at" desc)
    from (
      select * from "better_supabase"."invoice_e_deliveries" y
      where y."tenant_id" = list_e_invoice_deliveries.tenant
        and (list_e_invoice_deliveries.direction is null or y."direction" = list_e_invoice_deliveries.direction)
        and (list_e_invoice_deliveries.state is null or y."state" = list_e_invoice_deliveries.state)
        and (list_e_invoice_deliveries.invoice is null or y."invoice_id" = list_e_invoice_deliveries.invoice)
      order by y."created_at" desc
      limit 500
    ) x
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_e_invoice_deliveries"(uuid, text, text, uuid) from public, anon;
grant execute on function "better_supabase"."list_e_invoice_deliveries"(uuid, text, text, uuid) to authenticated, service_role;

-- Everything a party still owes or is owed on an invoice date: open invoices
-- and bills with their balance as of the day (payments dated later don't
-- count), and the party's unallocated payments as negative balances. Each item
-- has a bucket by days past due: current, days1To30, days31To60, days61To90,
-- over90 or unallocated. party_id and side (customer or supplier) narrow it.
-- Credit notes are counted as they stand today.
create or replace function "better_supabase"."open_items_for_party"(tenant uuid, party_id text default null, as_of date default null, side text default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_as_of date := coalesce(open_items_for_party.as_of, current_date);
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', open_items_for_party.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if open_items_for_party.side is not null and open_items_for_party.side not in ('customer', 'supplier') then
    raise exception 'side is customer or supplier' using errcode = '22023', hint = 'INVOICE_OPEN_ITEMS_INVALID';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'side', e.side, 'partyId', e.party, 'documentType', e.document_type, 'documentId', e.id,
        'identifier', e.identifier, 'currency', e.currency, 'issuedOn', e.issued_on, 'dueOn', e.due_on,
        'amount', e.gross::text, 'balance', e.balance::text, 'daysOverdue', e.days,
        'bucket', case when e.document_type = 'unallocated_payment' then 'unallocated'
          when e.days <= 0 then 'current' when e.days <= 30 then 'days1To30' when e.days <= 60 then 'days31To60'
          when e.days <= 90 then 'days61To90' else 'over90' end,
        'discountDueOn', e.discount_due_on, 'discountAmount', e.discount_amount::text,
        'legalEntityId', e.entity, 'approvalStatus', e.approval)
      order by e.side, e.party, e.due_on nulls last, e.id)
    from (
      select d.*, case when d.due_on is null then 0 else v_as_of - d.due_on end as days
      from (
        select 'invoice'::text as document_type, x."id" as id, case when x."direction" = 'purchase' then 'supplier' else 'customer' end as side, coalesce(x."company_id"::text, x."contact_id"::text) as party,
          x."identifier"::text as identifier, x."currency"::text as currency, x."issued_on" as issued_on, x."due_on" as due_on,
          (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total")::bigint as gross,
          (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - (select coalesce(-sum(e."amount"), 0)::bigint from "better_supabase"."ledger_entries" e
      join "better_supabase"."ledger_accounts" a on a."id" = e."account_id"
      join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
      where a."tenant_id" = x."tenant_id" and a."code" = 'invoice:' || x."id"::text
        and (y."effective_at" at time zone 'UTC')::date <= v_as_of))::bigint as balance,
          x."discount_due_on" as discount_due_on,
          coalesce(x."discount_amount_early", 0)::bigint as discount_amount,
          null::uuid as entity,
          case when x."direction" = 'purchase' then "better_supabase"."invoice_approval_state"(x."id") ->> 'status' end as approval
        from "better_supabase"."invoices" x
        where x."tenant_id" = open_items_for_party.tenant
          and x."kind" = 'invoice'
          and x."status" in ('issued', 'partially_paid', 'paid')
          and x."issued_on" <= v_as_of
          and (open_items_for_party.party_id is null or (x."company_id"::text = open_items_for_party.party_id or x."contact_id"::text = open_items_for_party.party_id))
        union all
        select 'unallocated_payment'::text, a."id", 'customer'::text, a."holder_id", null::text, a."unit"::text,
          null::date, null::date, (-c.amount)::bigint, (-c.amount)::bigint, null::date, 0::bigint, null::uuid, null::text
        from "better_supabase"."ledger_accounts" a
        cross join lateral (
          select coalesce(-sum(e."amount"), 0)::bigint as amount from "better_supabase"."ledger_entries" e
          join "better_supabase"."ledger_transactions" y on y."id" = e."transaction_id"
          where e."account_id" = a."id" and (y."effective_at" at time zone 'UTC')::date <= v_as_of
        ) c
        where a."tenant_id" = open_items_for_party.tenant and a."managed_by" = 'invoices'
          and a."holder_type" = 'invoice_party'
          and (open_items_for_party.party_id is null or a."holder_id" = open_items_for_party.party_id)
          and c.amount > 0
      ) d
      where d.balance <> 0
    ) e
    where open_items_for_party.side is null or e.side = open_items_for_party.side
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."open_items_for_party"(uuid, text, date, text) from public, anon;
grant execute on function "better_supabase"."open_items_for_party"(uuid, text, date, text) to authenticated, service_role;

-- The open items of an organization summed per party and currency in the ageing
-- buckets, with what is outstanding after unallocated payments.
create or replace function "better_supabase"."open_item_ageing"(tenant uuid, side text default null, as_of date default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object('side', k.side, 'partyId', k.party, 'currency', k.currency,
        'current', k.cur::text, 'days1To30', k.d30::text, 'days31To60', k.d60::text, 'days61To90', k.d90::text,
        'over90', k.over::text, 'unallocated', k.unal::text, 'outstanding', k.total::text)
      order by k.side, k.party, k.currency)
    from (
      select r.side, r."partyId" as party, r.currency,
        coalesce(sum(r.balance) filter (where r.bucket = 'current'), 0) as cur,
        coalesce(sum(r.balance) filter (where r.bucket = 'days1To30'), 0) as d30,
        coalesce(sum(r.balance) filter (where r.bucket = 'days31To60'), 0) as d60,
        coalesce(sum(r.balance) filter (where r.bucket = 'days61To90'), 0) as d90,
        coalesce(sum(r.balance) filter (where r.bucket = 'over90'), 0) as over,
        coalesce(sum(r.balance) filter (where r.bucket = 'unallocated'), 0) as unal,
        coalesce(sum(r.balance), 0) as total
      from jsonb_to_recordset("better_supabase"."open_items_for_party"(open_item_ageing.tenant, null, open_item_ageing.as_of, open_item_ageing.side))
        as r(side text, "partyId" text, currency text, balance bigint, bucket text)
      group by r.side, r."partyId", r.currency
    ) k
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."open_item_ageing"(uuid, text, date) from public, anon;
grant execute on function "better_supabase"."open_item_ageing"(uuid, text, date) to authenticated, service_role;

-- What allocate_payment covered, per payment reference.
create or replace function "better_supabase"."list_invoice_allocations"(tenant uuid, reference text default null, invoice_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', list_invoice_allocations.tenant, 'invoices.read'), false)) then
    raise exception 'not allowed to read this organization''s invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('currency', (select x."currency"::text from "better_supabase"."invoices" x where x."id" = b."invoice_id"), 'reference', b."reference", 'partyId', b."party_id", 'invoiceId', b."invoice_id",
        'source', b."source", 'amount', b."amount"::text, 'discount', b."discount"::text,
        'paymentId', b."payment_id", 'discountPaymentId', b."discount_payment_id",
        'allocatedOn', b."allocated_on", 'unallocatedAt', b."unallocated_at") order by b."created_at", b."id")
    from "better_supabase"."invoice_allocations" b
    where b."tenant_id" = list_invoice_allocations.tenant
      and (list_invoice_allocations.reference is null or b."reference" = list_invoice_allocations.reference)
      and (list_invoice_allocations.invoice_id is null or b."invoice_id" = list_invoice_allocations.invoice_id)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_invoice_allocations"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."list_invoice_allocations"(uuid, text, uuid) to authenticated, service_role;

-- Allocates one payment (or party credit) to several invoices or bills.
-- payment: { partyId, side (customer or supplier, default customer), amount,
-- currency, receivedOn, reference, method, note, source (payment or credit) };
-- allocations: [{ invoiceId, amount, takeDiscount (default true) }]. An
-- allocation under the balance is a partial payment. A customer's payment that
-- is more than its allocations leaves the rest as the party's credit; a
-- supplier payment is allocated in full. When the payment arrives by the
-- invoice's discount_due_on and leaves at most discount_amount_early open, the
-- rest is taken as an early payment discount, posted as its own ledger
-- transaction and booked in accounting. source credit draws on the party's
-- credit instead of receiving cash. The reference is required and unique per
-- organization; repeating a call returns what it allocated.
create or replace function "better_supabase"."allocate_payment"(tenant uuid, payment jsonb, allocations jsonb, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := allocate_payment.tenant;
  v_party text := nullif(trim(allocate_payment.payment ->> 'partyId'), '');
  v_side text := coalesce(allocate_payment.payment ->> 'side', 'customer');
  v_supplier boolean;
  v_use_credit boolean := coalesce(allocate_payment.payment ->> 'source', 'payment') = 'credit';
  v_currency text := upper(allocate_payment.payment ->> 'currency');
  v_reference text := nullif(trim(allocate_payment.payment ->> 'reference'), '');
  v_received date;
  v_amount bigint;
  v_allocations jsonb := coalesce(allocate_payment.allocations, '[]'::jsonb);
  v_sum bigint := 0;
  v_remainder bigint := 0;
  v_alloc record;
  v_row "better_supabase"."invoices";
  v_balance bigint;
  v_early bigint;
  v_due date;
  v_discount bigint;
  v_ref text;
  v_pay uuid;
  v_disc uuid;
  v_account uuid;
  v_credit uuid;
  v_was text;
  v_method text := coalesce(nullif(trim(allocate_payment.payment ->> 'method'), ''), 'allocation');
  v_note text := nullif(trim(allocate_payment.payment ->> 'note'), '');
  v_credited bigint := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', allocate_payment.tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to record payments in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if jsonb_typeof(allocate_payment.payment) is distinct from 'object' then
    raise exception 'payment is an object of partyId, amount, currency and reference' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  if v_party is null or length(v_party) > 150 then
    raise exception 'a party id is a non-empty text of at most 150 characters' using errcode = '22023', hint = 'INVOICE_PARTY_INVALID';
  end if;
  if v_side not in ('customer', 'supplier') then
    raise exception 'side is customer or supplier' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  v_supplier := v_side = 'supplier';
  if v_supplier and v_use_credit then
    raise exception 'only a customer''s credit is drawn on' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'INVOICE_CURRENCY_INVALID';
  end if;
  if v_reference is null then
    raise exception 'a payment needs a reference, such as the bank transaction id' using errcode = '22023', hint = 'INVOICE_PAYMENT_REFERENCE_REQUIRED';
  end if;
  begin
    v_received := coalesce(nullif(allocate_payment.payment ->> 'receivedOn', '')::date, current_date);
  exception when others then
    raise exception 'receivedOn is a date' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end;
  if not v_use_credit then
    if coalesce(allocate_payment.payment ->> 'amount', '') !~ '^[0-9]{1,18}$' or (allocate_payment.payment ->> 'amount')::bigint = 0 then
      raise exception 'a payment has a positive amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
    end if;
    v_amount := (allocate_payment.payment ->> 'amount')::bigint;
  end if;
  if jsonb_typeof(v_allocations) <> 'array' or jsonb_array_length(v_allocations) = 0 or exists (
    select 1 from jsonb_array_elements(v_allocations) x
    where jsonb_typeof(x.value) <> 'object'
      or coalesce(x.value ->> 'invoiceId', '') !~ '^[0-9a-fA-F-]{36}$'
      or coalesce(x.value ->> 'amount', '') !~ '^[0-9]{1,18}$'
      or (x.value ->> 'amount')::bigint = 0
      or (x.value ? 'takeDiscount' and jsonb_typeof(x.value -> 'takeDiscount') <> 'boolean')
  ) or (
    select count(*) <> count(distinct x.value ->> 'invoiceId') from jsonb_array_elements(v_allocations) x
  ) then
    raise exception 'allocations is a non-empty array of { invoiceId, amount, takeDiscount? } with a positive amount, one per invoice' using errcode = '22023', hint = 'INVOICE_ALLOCATIONS_INVALID';
  end if;
  if exists (select 1 from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference) then
    if exists (select 1 from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is not null) then
      raise exception 'this payment reference was allocated and unallocated; allocate the payment again under a new reference' using errcode = '55000', hint = 'INVOICE_ALLOCATION_REFERENCE_USED';
    end if;
    return jsonb_build_object(
      'reference', v_reference,
      'currency', (select min(x."currency"::text) from "better_supabase"."invoices" x join "better_supabase"."invoice_allocations" b on b."invoice_id" = x."id" where b."tenant_id" = v_tenant and b."reference" = v_reference),
      'partyId', (select min(b."party_id") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference),
      'allocated', coalesce((select sum(b."amount") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is null), 0)::text,
      'discount', coalesce((select sum(b."discount") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is null), 0)::text,
      'allocations', coalesce((select jsonb_agg(jsonb_build_object('invoiceId', b."invoice_id", 'source', b."source", 'amount', b."amount"::text, 'discount', b."discount"::text,
          'paymentId', b."payment_id", 'discountPaymentId', b."discount_payment_id", 'allocatedOn', b."allocated_on", 'unallocatedAt', b."unallocated_at") order by b."created_at", b."id")
        from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference), '[]'::jsonb)) || jsonb_build_object('credited', coalesce((
      select (y."metadata" ->> 'amount') from "better_supabase"."ledger_transactions" y
      where y."tenant_id" = v_tenant and y."idempotency_key" = 'invoice-party-payment:' || v_reference), '0'));
  end if;
  select coalesce(sum((x.value ->> 'amount')::bigint), 0) into v_sum from jsonb_array_elements(v_allocations) x;
  if v_use_credit then
    v_amount := v_sum;
  elsif v_sum > v_amount then
    raise exception 'the allocations add up to more than the payment' using errcode = '23514', hint = 'INVOICE_ALLOCATIONS_TOO_LARGE';
  end if;
  v_remainder := v_amount - v_sum;
  if v_supplier and v_remainder > 0 then
    raise exception 'a supplier payment is allocated in full; lower the payment or allocate the rest' using errcode = '23514', hint = 'INVOICE_ALLOCATIONS_REMAINDER';
  end if;
  if allocate_payment.actor is not null then
    if jsonb_typeof(allocate_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(allocate_payment.actor ->> 'ip', '')::inet, nullif(allocate_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(allocate_payment.actor::text, ''), true);
  for v_alloc in
    select (x.value ->> 'invoiceId')::uuid as invoice, (x.value ->> 'amount')::bigint as amount,
      coalesce((x.value ->> 'takeDiscount')::boolean, true) as take
    from jsonb_array_elements(v_allocations) with ordinality x
    order by x.ordinality
  loop
    select * into v_row from "better_supabase"."invoices" x
    where x."id" = v_alloc.invoice and x."tenant_id" = v_tenant
      and (x."company_id"::text = v_party or x."contact_id"::text = v_party) and (x."direction" = 'purchase') = v_supplier
    for update;
    if v_row."id" is null then
      raise exception 'an allocation names no invoice of this party and side' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
    end if;
    if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid') then
      raise exception 'only an open invoice takes an allocation' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
    end if;
    if v_row."currency"::text <> v_currency then
      raise exception 'an allocation must be in the invoice''s currency' using errcode = '22023', hint = 'INVOICE_CURRENCY_MISMATCH';
    end if;
    v_balance := (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total");
    if v_alloc.amount > v_balance then
      raise exception 'an allocation is more than the invoice''s balance' using errcode = '23514', hint = 'INVOICE_ALLOCATION_TOO_LARGE';
    end if;
    v_early := coalesce(v_row."discount_amount_early", 0);
    v_due := v_row."discount_due_on";
    v_discount := 0;
    if v_alloc.take and v_early > 0 and v_due is not null and v_received <= v_due
      and v_alloc.amount < v_balance and v_alloc.amount >= v_balance - v_early then
      v_discount := v_balance - v_alloc.amount;
    end if;
    v_ref := v_reference || '/' || v_alloc.invoice::text;
    v_was := v_row."status";
    if v_use_credit then
      select a."id" into v_account from "better_supabase"."ledger_accounts" a
      where a."tenant_id" = v_tenant and a."code" = 'invoices:credit:' || v_party || ':' || v_row."currency"
      for update;
      if v_account is null or v_alloc.amount > coalesce(-(select sum(e."amount") from "better_supabase"."ledger_entries" e where e."account_id" = v_account), 0) then
        raise exception 'the party doesn''t have this much credit in the invoice''s currency' using errcode = '23514', hint = 'INVOICE_CREDIT_INSUFFICIENT';
      end if;
      v_pay := "better_supabase"."ledger_post"(v_tenant, 'invoice.credit_applied',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -v_alloc.amount),
          jsonb_build_object('account', v_account, 'amount', v_alloc.amount)),
        'invoices', v_row."id"::text, null, 'invoice-payment:' || v_ref, v_received::timestamptz,
        jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row."id", 'method', 'credit', 'partyId', v_party, 'reference', v_ref)));
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
    else
      perform "better_supabase"."record_invoice_payment"(v_row."id", v_alloc.amount, v_currency, v_received::timestamptz,
        v_method, v_ref, v_note, allocate_payment.actor, null);
      select y."id" into v_pay from "better_supabase"."ledger_transactions" y where y."tenant_id" = v_tenant and y."idempotency_key" = 'invoice-payment:' || v_ref;
      select * into v_row from "better_supabase"."invoices" x where x."id" = v_alloc.invoice;
    end if;
    if v_discount > 0 then
      v_disc := "better_supabase"."ledger_post"(v_tenant, 'invoice.discount',
        jsonb_build_array(
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_row."tenant_id", 'receivable',
      'invoice:' || v_row."id"::text, 'Receivable ' || coalesce(v_row."identifier", v_row."id"::text),
      v_row."currency"::text, 0::smallint, 'invoices', v_row."id"::text,
      null, true, 'invoices.read', 'invoices', null), 'amount', -v_discount),
          jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_tenant, 'discount',
      'invoices:discount:' || case when v_row."direction" = 'purchase' then 'purchase' else 'sales' end || ':' || v_row."currency"::text,
      'Early payment discount ' || v_row."currency"::text, v_row."currency"::text, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', v_discount)),
        'invoices', v_row."id"::text, null, 'invoice-discount:' || v_ref, v_received::timestamptz,
        jsonb_strip_nulls(jsonb_build_object('invoiceId', v_row."id", 'method', 'early_payment_discount', 'reference', v_ref, 'partyId', v_party)));
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
      
      null;
    else
      v_disc := null;
    end if;
    insert into "better_supabase"."invoice_allocations" ("tenant_id", "reference", "party_id", "invoice_id", "source", "amount", "discount", "payment_id", "discount_payment_id", "allocated_on", "created_by")
    values (v_tenant, v_reference, v_party, v_row."id", case when v_use_credit then 'credit' else 'payment' end, v_alloc.amount, v_discount, v_pay, v_disc, v_received, auth.uid());
    null;
    if v_row."status" = 'paid' and v_was <> 'paid' and (v_use_credit or v_discount > 0) then
      null;
    end if;
  end loop;
  if v_remainder > 0 then
    v_credit := "better_supabase"."ledger_post"(v_tenant, 'invoice.party_payment',
      jsonb_build_array(
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_tenant, 'cash', 'invoices:cash:' || v_currency,
      'Invoice payments ' || v_currency, v_currency, 0::smallint, null, null,
      null, true, 'invoices.read', 'invoices', null), 'amount', v_remainder),
        jsonb_build_object('account', "better_supabase"."ledger_account_for"(v_tenant, 'credit', 'invoices:credit:' || v_party || ':' || v_currency,
      'Credit ' || v_party || ' ' || v_currency, v_currency, 0::smallint, 'invoice_party', v_party,
      null, true, 'invoices.read', 'invoices', null), 'amount', -v_remainder)),
      'invoices', v_party, null, 'invoice-party-payment:' || v_reference, v_received::timestamptz,
      jsonb_strip_nulls(jsonb_build_object('partyId', v_party, 'currency', v_currency, 'method', v_method,
        'reference', v_reference, 'note', v_note, 'amount', v_remainder::text)));
    
    v_credited := v_remainder;
  end if;
  return jsonb_build_object(
      'reference', v_reference,
      'currency', (select min(x."currency"::text) from "better_supabase"."invoices" x join "better_supabase"."invoice_allocations" b on b."invoice_id" = x."id" where b."tenant_id" = v_tenant and b."reference" = v_reference),
      'partyId', (select min(b."party_id") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference),
      'allocated', coalesce((select sum(b."amount") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is null), 0)::text,
      'discount', coalesce((select sum(b."discount") from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference and b."unallocated_at" is null), 0)::text,
      'allocations', coalesce((select jsonb_agg(jsonb_build_object('invoiceId', b."invoice_id", 'source', b."source", 'amount', b."amount"::text, 'discount', b."discount"::text,
          'paymentId', b."payment_id", 'discountPaymentId', b."discount_payment_id", 'allocatedOn', b."allocated_on", 'unallocatedAt', b."unallocated_at") order by b."created_at", b."id")
        from "better_supabase"."invoice_allocations" b where b."tenant_id" = v_tenant and b."reference" = v_reference), '[]'::jsonb)) || jsonb_build_object('credited', v_credited::text);
end;
$$;
revoke execute on function "better_supabase"."allocate_payment"(uuid, jsonb, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."allocate_payment"(uuid, jsonb, jsonb, jsonb) to authenticated, service_role;

-- Undoes allocate_payment for a reference: each cash payment, credit draw and
-- discount of it is reversed on the ledger, so the invoices reopen with their
-- balance and the credit is restored. The unallocated rest of a customer
-- payment stays the party's credit, and a reference can't be allocated again.
-- Needs the permission to reverse payments.
create or replace function "better_supabase"."unallocate_payment"(tenant uuid, reference text, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := unallocate_payment.tenant;
  v_alloc "better_supabase"."invoice_allocations"%rowtype;
  v_row "better_supabase"."invoices";
  v_reversal uuid;
  v_count integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', unallocate_payment.tenant, 'invoices.manage'), false)) then
    raise exception 'not allowed to reverse payments in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if unallocate_payment.actor is not null then
    if jsonb_typeof(unallocate_payment.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(unallocate_payment.actor ->> 'ip', '')::inet, nullif(unallocate_payment.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'INVOICE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(unallocate_payment.actor::text, ''), true);
  for v_alloc in
    select * from "better_supabase"."invoice_allocations" b
    where b."tenant_id" = v_tenant and b."reference" = unallocate_payment.reference and b."unallocated_at" is null
    order by b."created_at" desc, b."id"
    for update
  loop
    if v_alloc."discount_payment_id" is not null then
      select * into v_row from "better_supabase"."invoices" x where x."id" = v_alloc."invoice_id" for update;
      v_reversal := "better_supabase"."ledger_post"(v_row."tenant_id", 'invoice.payment_reversal',
    (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
      from "better_supabase"."ledger_entries" e where e."transaction_id" = v_alloc."discount_payment_id"),
    'invoices', v_row."id"::text, null, null, null,
    (select y."metadata" from "better_supabase"."ledger_transactions" y where y."id" = v_alloc."discount_payment_id") || jsonb_strip_nulls(jsonb_build_object('reversal', true, 'reason', 'Unallocated')),
    v_alloc."discount_payment_id");
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
      
    end if;
    if v_alloc."source" = 'credit' then
      select * into v_row from "better_supabase"."invoices" x where x."id" = v_alloc."invoice_id" for update;
      v_reversal := "better_supabase"."ledger_post"(v_row."tenant_id", 'invoice.payment_reversal',
    (select jsonb_agg(jsonb_build_object('account', e."account_id", 'amount', (-e."amount")::text) order by e."created_at", e."id")
      from "better_supabase"."ledger_entries" e where e."transaction_id" = v_alloc."payment_id"),
    'invoices', v_row."id"::text, null, null, null,
    (select y."metadata" from "better_supabase"."ledger_transactions" y where y."id" = v_alloc."payment_id") || jsonb_strip_nulls(jsonb_build_object('reversal', true, 'reason', 'Unallocated')),
    v_alloc."payment_id");
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
    else
      perform "better_supabase"."reverse_invoice_payment"(v_alloc."payment_id", 'Unallocated', unallocate_payment.actor);
    end if;
    update "better_supabase"."invoice_allocations" b set "unallocated_at" = now() where b."id" = v_alloc."id";
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_alloc."invoice_id";
    null;
    v_count := v_count + 1;
  end loop;
  if v_count = 0 then
    raise exception 'no allocation with this reference is active' using errcode = 'P0002', hint = 'INVOICE_ALLOCATION_NOT_FOUND';
  end if;
  return jsonb_build_object('reference', unallocate_payment.reference, 'unallocated', v_count);
end;
$$;
revoke execute on function "better_supabase"."unallocate_payment"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."unallocate_payment"(uuid, text, jsonb) to authenticated, service_role;

-- Recounts the totals of issued invoices (not drafts or voided ones) with the
-- credit restriction of their payment terms, for invoices issued before the
-- totals followed it. invoice_ids null means every issued invoice of the
-- organization. dry_run (the default) writes nothing. An invoice whose stored
-- totals already match is left alone, so a second run changes nothing. It
-- never changes a number, an issue date or a status. The result lists the
-- invoices that differ with their old and new totals and balance, and says
-- whether a posted accounting entry books the old amounts: the entry is not
-- touched, and it needs a correcting entry. Each corrected invoice gets an
-- audit entry as a system correction; options.correctionEvents also sends an
-- event. Needs invoices.manage.
create or replace function "better_supabase"."recompute_invoice_totals"(tenant uuid, invoice_ids uuid[] default null, dry_run boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_old jsonb;
  v_new jsonb;
  v_balance bigint;
  v_balance_after bigint;
  v_entry uuid;
  v_entry_number text;
  v_period text;
  v_detail jsonb;
  v_ledger jsonb;
  v_items jsonb := '[]'::jsonb;
  v_checked integer := 0;
  v_changed integer := 0;
begin
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', recompute_invoice_totals.tenant, 'invoices.manage'), false)) then
    raise exception 'not allowed to manage invoices in this organization' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  for v_row in
    select * from "better_supabase"."invoices" x
    where x."tenant_id" = recompute_invoice_totals.tenant
      and x."status" not in ('draft', 'void')
      and (recompute_invoice_totals.invoice_ids is null or x."id" = any (recompute_invoice_totals.invoice_ids))
    order by x."created_at", x."id"
    for update
  loop
    v_checked := v_checked + 1;
    v_old := jsonb_build_object('listTotal', v_row."list_total"::text, 'discountTotal', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text);
    v_balance := (v_row."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = v_row."id"), 0) - v_row."credited_total" - v_row."paid_total");
    begin
      perform "better_supabase"."set_invoice_lines_recount"(v_row."id");
      select jsonb_build_object('listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text), (x."total" + coalesce((select sum(y."amount") from "better_supabase"."invoice_charges" y where y."invoice_id" = x."id"), 0) - x."credited_total" - x."paid_total") into v_new, v_balance_after
      from "better_supabase"."invoices" x where x."id" = v_row."id";
      if v_new = v_old then
        raise exception using errcode = 'P0BSB', message = 'unchanged';
      end if;
      if recompute_invoice_totals.dry_run then
        raise exception using errcode = 'P0BSB', message = 'dry run';
      end if;
    exception
      when sqlstate 'P0BSB' then
        null;
    end;
    if v_new = v_old then
      continue;
    end if;
    v_changed := v_changed + 1;
    v_entry := null;
    v_entry_number := null;
    v_period := null;
    v_ledger := jsonb_build_object('posted', v_entry is not null, 'entryId', v_entry, 'entryNumber', v_entry_number,
      'periodStatus', v_period, 'needsCorrectingEntry', v_entry is not null);
    v_detail := jsonb_build_object('correction', 'credit_restriction', 'old', v_old, 'new', v_new, 'ledger', v_ledger);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'invoiceId', v_row."id", 'identifier', v_row."identifier", 'currency', v_row."currency", 'status', v_row."status",
      'old', v_old, 'new', v_new, 'balance', v_balance::text, 'balanceAfter', v_balance_after::text,
      'ledger', v_ledger));
    if not recompute_invoice_totals.dry_run then
      null;
      
    end if;
  end loop;
  return jsonb_build_object('dryRun', recompute_invoice_totals.dry_run, 'checked', v_checked, 'changed', v_changed,
    'applied', case when recompute_invoice_totals.dry_run then 0 else v_changed end, 'invoices', v_items);
end;
$$;
revoke execute on function "better_supabase"."recompute_invoice_totals"(uuid, uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."recompute_invoice_totals"(uuid, uuid[], boolean) to authenticated, service_role;

-- The shared body of the invoice and credit_note import targets (ADR 0141).
-- item.data is { number, issuedOn, dueOn?, status?, title?, currency, termsDays?, note?,
-- company?, contact?, origin?, direction?, legalEntityId?, buyer?, createdAt?,
-- pricesIncludeTax?, attrs?, lines, taxLines?, totals?, payments? }; a credit
-- note adds originalId or original (the identifier of the credited invoice).
-- The document is created and issued with its number as is, takes the stored
-- tax and totals, then its payments with their original dates. A document that
-- is already imported is kept as it is: the item reports a warning.
create or replace function "better_supabase"."import_invoice_document"(item jsonb, subject_id text, v_credit boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_invoice_document.item ->> 'tenant')::uuid;
  v_data jsonb := import_invoice_document.item -> 'data';
  v_status text := case when v_credit then 'issued' else coalesce(v_data ->> 'status', 'issued') end;
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_issued_on date;
  v_due_on date;
  v_original uuid;
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."invoices";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
  v_pay jsonb;
  v_index integer := 0;
begin
  if import_invoice_document.subject_id is not null then
    select * into v_row from "better_supabase"."invoices" x where x."id" = import_invoice_document.subject_id::uuid and x."tenant_id" = v_tenant;
    if not found then
      raise exception 'the invoice no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source document changed after it was imported; an imported document is kept as imported, so void or credit it and import the correction as a new document')));
  end if;
  if v_status not in ('draft', 'issued', 'partially_paid', 'paid', 'void', 'uncollectible') then
    raise exception 'status is draft, issued, partially_paid, paid, void or uncollectible' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a document needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_status <> 'draft' and v_number is null then
    raise exception 'an issued document needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_issued_on := nullif(v_data ->> 'issuedOn', '')::date;
    v_due_on := nullif(v_data ->> 'dueOn', '')::date;
  exception when others then
    raise exception 'issuedOn and dueOn are dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  if v_status <> 'draft' and v_issued_on is null then
    raise exception 'an issued document needs its issue date' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;

  if v_credit then
    v_original := coalesce(
      nullif(v_data ->> 'originalId', '')::uuid,
      (select x."id" from "better_supabase"."invoices" x where x."tenant_id" = v_tenant and x."identifier" = v_data ->> 'original' limit 1)
    );
    if v_original is null then
      raise exception 'a credit note names the invoice it credits (originalId or original)' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    v_made := "better_supabase"."credit_invoice"(v_original, v_data -> 'lines', nullif(v_data ->> 'note', ''), v_number, v_issued_on);
    v_id := (v_made ->> 'id')::uuid;
  else
    v_made := "better_supabase"."create_invoice"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'title', coalesce(nullif(v_data ->> 'title', ''), 'Invoice ' || coalesce(v_number, 'draft')),
      'currency', v_data -> 'currency',
      'termsDays', v_data -> 'termsDays',
      'note', v_data -> 'note',
      'company', v_data -> 'company',
      'contact', v_data -> 'contact',
      'origin', v_data -> 'origin',
      'direction', v_data -> 'direction',
      'pricesIncludeTax', v_data -> 'pricesIncludeTax',
      'discountBps', v_data -> 'discountBps',
      'discountAmount', v_data -> 'discountAmount')), v_data -> 'lines');
    v_id := (v_made ->> 'id')::uuid;
  end if;
  update "better_supabase"."invoices" x set "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' else x."buyer" end,
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, x."created_at")
  where x."id" = v_id;
  if v_status <> 'draft' and not v_credit then
    perform "better_supabase"."issue_invoice"(v_id, v_issued_on, v_due_on, null, v_number);
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."invoices" x set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, x."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, x."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, x."total")
    where x."id" = v_id;
  end if;
  if jsonb_typeof(v_data -> 'payments') = 'array' and jsonb_array_length(v_data -> 'payments') > 0 then
    if v_credit or v_status = 'draft' then
      raise exception 'only an issued invoice takes payments' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
    for v_pay in select p.value from jsonb_array_elements(v_data -> 'payments') p loop
      v_index := v_index + 1;
      perform "better_supabase"."record_invoice_payment"(
        v_id, (v_pay ->> 'amount')::bigint, upper(coalesce(v_pay ->> 'currency', v_row."currency")),
        (v_pay ->> 'paidAt')::timestamptz, coalesce(nullif(v_pay ->> 'method', ''), 'import'),
        coalesce(nullif(v_pay ->> 'reference', ''), import_invoice_document.item ->> 'key' || ':payment:' || v_index::text),
        nullif(v_pay ->> 'note', ''), null, null);
    end loop;
    update "better_supabase"."invoices" x set "paid_at" = (select max((p.value ->> 'paidAt')::timestamptz) from jsonb_array_elements(v_data -> 'payments') p)
    where x."id" = v_id and x."paid_at" is not null and jsonb_typeof(v_data -> 'payments') = 'array';
  end if;
  if v_status = 'void' then
    perform "better_supabase"."void_invoice"(v_id, coalesce(nullif(v_data ->> 'voidReason', ''), 'imported as void'));
  elsif v_status = 'uncollectible' then
    perform "better_supabase"."write_off_invoice"(v_id, nullif(v_data ->> 'writeOffReason', ''));
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = v_id;
  if v_status in ('partially_paid', 'paid') and v_row."status"::text <> v_status then
    v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_STATUS_MISMATCH', 'message', 'the payments give the status ' || v_row."status"::text || ', not ' || v_status, 'status', v_row."status"::text));
  end if;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_invoice_document"(jsonb, text, boolean) from public, anon, authenticated;

create or replace function "better_supabase"."import_invoice"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."import_invoice_document"(import_invoice.item, import_invoice.subject_id, false)
$$;
revoke execute on function "better_supabase"."import_invoice"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_invoice"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."import_credit_note"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select "better_supabase"."import_invoice_document"(import_credit_note.item, import_credit_note.subject_id, true)
$$;
revoke execute on function "better_supabase"."import_credit_note"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_credit_note"(uuid, jsonb, text) to service_role;

-- The open_item import target: an opening open-item list. item.data is
-- { number, issuedOn, dueOn?, currency, balance, side? (customer or supplier),
-- title?, company?, contact?, legalEntityId? } for one open invoice or bill; it
-- imports as an issued document of one line for the open balance with its
-- original number and dates, so ageing and allocation work on it. Importing the
-- same row again writes nothing.
create or replace function "better_supabase"."import_open_item"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_open_item.item -> 'data';
  v_balance bigint;
begin
  if jsonb_typeof(v_data) is distinct from 'object' or coalesce(v_data ->> 'balance', '') !~ '^[0-9]{1,18}$' or (v_data ->> 'balance')::bigint = 0 then
    raise exception 'an open item has a positive integer balance in minor units' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'side', 'customer') not in ('customer', 'supplier') then
    raise exception 'side is customer or supplier' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_balance := (v_data ->> 'balance')::bigint;
  return "better_supabase"."import_invoice_document"(jsonb_set(import_open_item.item, '{data}', jsonb_strip_nulls(jsonb_build_object(
    'number', v_data -> 'number', 'status', 'issued', 'issuedOn', v_data -> 'issuedOn', 'dueOn', v_data -> 'dueOn',
    'currency', v_data -> 'currency', 'company', v_data -> 'company', 'contact', v_data -> 'contact',
    'legalEntityId', v_data -> 'legalEntityId',
    'direction', case when v_data ->> 'side' = 'supplier' then 'purchase' else 'sales' end,
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Opening balance ' || coalesce(v_data ->> 'number', '')),
    'lines', jsonb_build_array(jsonb_build_object('description', 'Opening balance ' || coalesce(v_data ->> 'number', ''),
      'quantity', 1, 'unitAmount', v_balance, 'taxRateBps', 0)),
    'totals', jsonb_build_object('subtotal', v_balance, 'tax', 0, 'total', v_balance)))),
    import_open_item.subject_id, false);
end;
$$;
revoke execute on function "better_supabase"."import_open_item"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_open_item"(uuid, jsonb, text) to service_role;

-- When an invoice last changed, for the conflict check of imports.
create or replace function "better_supabase"."invoice_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."invoices" x where x."id" = $1::uuid
$$;
revoke execute on function "better_supabase"."invoice_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."invoice_updated_at"(text) to service_role;

-- Totals and cost of one record's lines per billing party (ADR 0141). It runs
-- as the caller, so only lines the caller can read count.
create or replace function "better_supabase"."document_totals_by_billing_party"(document uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(g.row order by g.party, g.party_id, g.account_id), '[]'::jsonb)
  from (
    select l."billing_party" as party, l."billing_party_id" as party_id, l."billing_account_id"::text as account_id,
      jsonb_build_object(
        'billingParty', l."billing_party", 'billingPartyId', l."billing_party_id", 'billingAccountId', l."billing_account_id"::text,
        'lines', count(*), 'net', sum((round(l."quantity" * l."unit_amount") - (round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0), 0)))))::text, 'cost', sum(round(l."quantity" * l."unit_cost"))::text
      ) as row
    from "better_supabase"."invoice_lines" l
    where l."parent_id" = document and true
    group by 1, 2, 3
  ) g
$$;
revoke execute on function "better_supabase"."document_totals_by_billing_party"(uuid) from public, anon;
grant execute on function "better_supabase"."document_totals_by_billing_party"(uuid) to authenticated, service_role;

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
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
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
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_dunning_runs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_dunning_runs";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_dunning_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_runs";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_dunning_runs";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_dunning_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_runs";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_dunning_run_items";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_dunning_run_items";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_dunning_run_items" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_run_items";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_run_items" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_dunning_run_items";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_dunning_run_items" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_run_items";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_run_items" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_dunning_history";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_dunning_history";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_dunning_history" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_history";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_dunning_history" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_dunning_history";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_dunning_history" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_history";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_dunning_history" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_allocations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_allocations";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_allocations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_allocations";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_allocations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_allocations";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_allocations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_allocations";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_allocations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_approval_levels";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_approval_levels";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_approval_levels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_approval_levels";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_approval_levels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_approval_levels";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_approval_levels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_approval_levels";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_approval_levels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_approvals";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_approvals";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_approvals" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_approvals";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_approvals" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_approvals";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_approvals" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_approvals";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_approvals" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_e_endpoints";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_e_endpoints";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_e_endpoints" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_e_endpoints";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_e_endpoints" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_e_endpoints";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_e_endpoints" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_e_endpoints";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_e_endpoints" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_e_deliveries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_e_deliveries";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_e_deliveries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_e_deliveries";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_e_deliveries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_e_deliveries";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_e_deliveries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_e_deliveries";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_e_deliveries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_098_invoices.sql
-- better-supabase module: invoices
-- @bsb-block-data invoices
-- @bsb-hash sha256:c00c51a11ad9c8aaa07dd314eed28f6c5079977dd7aed37e8fb1a704b4023060
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('invoices', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
