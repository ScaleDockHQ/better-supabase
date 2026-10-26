-- ==== schema supabase/schemas/900_better_supabase_084_orders.sql
-- better-supabase module: orders
-- @bsb-block orders@2 managed
-- @bsb-hash sha256:c9ec879b3b882695ffd17a18f7787470fd42d76581086432c606a135aa98ffac
-- Carts on anonymous or signed-in users, checkout priced from the catalog, gapless order and invoice numbers, payments, fulfillments, returns and refunds, with an optional kitchen display. With invoices, a paid order gets an issued, paid invoice.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."carts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."carts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."carts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."carts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."carts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."cart_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."cart_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cart_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."cart_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cart_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."shipping_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."shipping_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shipping_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."shipping_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shipping_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."orders";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."orders";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."orders";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."orders";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."orders";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."order_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."order_payments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_payments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_payments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_payments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_payments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."fulfillments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."fulfillments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."fulfillments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."fulfillments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."fulfillments";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."fulfillment_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."fulfillment_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."fulfillment_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."fulfillment_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."fulfillment_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."order_returns";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_returns";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_returns";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_returns";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_returns";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."order_return_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_return_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_return_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_return_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_return_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."order_refunds";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_refunds";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_refunds";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_refunds";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_refunds";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Carts on any signed-in user (anonymous sign-ins included), checkout into
-- orders with numbers, payments, fulfillments, returns and refunds.

create table if not exists "better_supabase"."shipping_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "countries" text[] not null default '{}',
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "kind" text not null default 'flat' check ("kind" in ('flat', 'weight')),
  "amount" bigint not null default 0 check ("amount" >= 0),
  "amount_per_kg" bigint not null default 0 check ("amount_per_kg" >= 0),
  "free_over" bigint check ("free_over" >= 0),
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists shipping_rates_tenant_idx on "better_supabase"."shipping_rates" ("tenant_id", "currency");
alter table "better_supabase"."shipping_rates" enable row level security;
revoke all on "better_supabase"."shipping_rates" from anon, authenticated;
grant select on "better_supabase"."shipping_rates" to authenticated;
grant all on "better_supabase"."shipping_rates" to service_role;
drop policy if exists shipping_rates_read on "better_supabase"."shipping_rates";
create policy shipping_rates_read on "better_supabase"."shipping_rates" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')));

create table if not exists "better_supabase"."carts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "price_list_id" uuid references "better_supabase"."price_lists" ("id") on delete set null,
  "status" text not null default 'open' check ("status" in ('open', 'converted', 'abandoned')),
  "email" text check (length("email") <= 320),
  "shipping_address" jsonb check (jsonb_typeof("shipping_address") = 'object'),
  "billing_address" jsonb check (jsonb_typeof("billing_address") = 'object'),
  "shipping_rate_id" uuid references "better_supabase"."shipping_rates" ("id") on delete set null,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "converted_at" timestamptz
);
create unique index if not exists carts_open_idx on "better_supabase"."carts" ("tenant_id", "user_id", "currency") where "status" = 'open';
create index if not exists carts_user_idx on "better_supabase"."carts" ("user_id");
create index if not exists carts_rate_idx on "better_supabase"."carts" ("shipping_rate_id");
create index if not exists carts_price_list_idx on "better_supabase"."carts" ("price_list_id");
alter table "better_supabase"."carts" enable row level security;
revoke all on "better_supabase"."carts" from anon, authenticated;
grant select on "better_supabase"."carts" to authenticated;
grant all on "better_supabase"."carts" to service_role;
drop policy if exists carts_read on "better_supabase"."carts";
create policy carts_read on "better_supabase"."carts" for select to authenticated
using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('orders.read')));

create table if not exists "better_supabase"."cart_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "cart_id" uuid not null references "better_supabase"."carts" ("id") on delete cascade,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "quantity" integer not null check ("quantity" between 1 and 10000),
  "unit_amount" bigint check ("unit_amount" >= 0),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("cart_id", "variant_id")
);
create index if not exists cart_lines_variant_idx on "better_supabase"."cart_lines" ("variant_id");
alter table "better_supabase"."cart_lines" enable row level security;
revoke all on "better_supabase"."cart_lines" from anon, authenticated;
grant select on "better_supabase"."cart_lines" to authenticated;
grant all on "better_supabase"."cart_lines" to service_role;
drop policy if exists cart_lines_read on "better_supabase"."cart_lines";
create policy cart_lines_read on "better_supabase"."cart_lines" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."carts" x where x."id" = "cart_id" and x."user_id" = (select auth.uid())));

create table if not exists "better_supabase"."orders" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" text not null,
  "sequence" bigint not null,
  "cart_id" uuid unique references "better_supabase"."carts" ("id") on delete set null,
  "customer_id" uuid references auth.users (id) on delete set null,
  "email" text,
  "status" text not null default 'pending_payment',
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "subtotal" bigint not null default 0 check ("subtotal" >= 0),
  "discount_total" bigint not null default 0 check ("discount_total" >= 0),
  "shipping_total" bigint not null default 0 check ("shipping_total" >= 0),
  "tax_total" bigint not null default 0 check ("tax_total" >= 0),
  "total" bigint not null default 0 check ("total" >= 0),
  "paid_total" bigint not null default 0 check ("paid_total" >= 0),
  "refunded_total" bigint not null default 0 check ("refunded_total" >= 0),
  "tax_inclusive" boolean not null default false,
  "shipping_address" jsonb,
  "billing_address" jsonb,
  "shipping" jsonb,
  "promotions" jsonb not null default '[]',
  "tax" jsonb,
  "tax_transaction" jsonb,
  "invoice_number" text,
  "invoice_sequence" bigint,
  "invoiced_at" timestamptz,
  "placed_at" timestamptz not null default now(),
  "paid_at" timestamptz,
  "fulfilled_at" timestamptz,
  "completed_at" timestamptz,
  "cancelled_at" timestamptz,
  "cancel_reason" text,
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "number"),
  unique ("tenant_id", "invoice_number")
);
create index if not exists orders_status_idx on "better_supabase"."orders" ("tenant_id", "status", "placed_at");
create index if not exists orders_customer_idx on "better_supabase"."orders" ("customer_id");
create index if not exists orders_sequence_idx on "better_supabase"."orders" ("tenant_id", "sequence");
alter table "better_supabase"."orders" add column if not exists "app_note" text;
alter table "better_supabase"."orders" enable row level security;
revoke all on "better_supabase"."orders" from anon, authenticated;
grant select on "better_supabase"."orders" to authenticated;
grant all on "better_supabase"."orders" to service_role;
drop policy if exists orders_read on "better_supabase"."orders";
create policy orders_read on "better_supabase"."orders" for select to authenticated
using ("customer_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('orders.read')));

create table if not exists "better_supabase"."order_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null references "better_supabase"."orders" ("id") on delete cascade,
  "position" integer not null default 0,
  "variant_id" uuid references "better_supabase"."product_variants" ("id") on delete set null,
  "product_id" uuid,
  "sku" text not null,
  "title" text not null,
  "quantity" integer not null check ("quantity" > 0),
  "unit_amount" bigint not null default 0 check ("unit_amount" >= 0),
  "subtotal" bigint not null default 0 check ("subtotal" >= 0),
  "discount" bigint not null default 0 check ("discount" >= 0),
  "tax" bigint not null default 0 check ("tax" >= 0),
  "total" bigint not null default 0 check ("total" >= 0),
  "requires_shipping" boolean not null default true,
  "location_id" uuid,
  "reservation_id" uuid,
  "quantity_fulfilled" integer not null default 0 check ("quantity_fulfilled" between 0 and "quantity"),
  "quantity_returned" integer not null default 0 check ("quantity_returned" between 0 and "quantity"),
  "backordered" boolean not null default false
);
create index if not exists order_lines_order_idx on "better_supabase"."order_lines" ("order_id");
create index if not exists order_lines_variant_idx on "better_supabase"."order_lines" ("variant_id");
alter table "better_supabase"."order_lines" enable row level security;
revoke all on "better_supabase"."order_lines" from anon, authenticated;
grant select on "better_supabase"."order_lines" to authenticated;
grant all on "better_supabase"."order_lines" to service_role;
drop policy if exists order_lines_read on "better_supabase"."order_lines";
create policy order_lines_read on "better_supabase"."order_lines" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())));

create table if not exists "better_supabase"."order_payments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null references "better_supabase"."orders" ("id") on delete cascade,
  "provider" text not null,
  "reference" text not null,
  "status" text not null check ("status" in ('requires_action', 'processing', 'authorized', 'succeeded', 'failed', 'canceled')),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint not null default 0 check ("amount" >= 0),
  "captured" bigint not null default 0 check ("captured" >= 0),
  "refunded" bigint not null default 0 check ("refunded" >= 0),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("provider", "reference")
);
create index if not exists order_payments_order_idx on "better_supabase"."order_payments" ("order_id");
alter table "better_supabase"."order_payments" enable row level security;
revoke all on "better_supabase"."order_payments" from anon, authenticated;
grant select on "better_supabase"."order_payments" to authenticated;
grant all on "better_supabase"."order_payments" to service_role;
drop policy if exists order_payments_read on "better_supabase"."order_payments";
create policy order_payments_read on "better_supabase"."order_payments" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())));

create table if not exists "better_supabase"."fulfillments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null references "better_supabase"."orders" ("id") on delete cascade,
  "location_id" uuid,
  "status" text not null default 'pending' check ("status" in ('pending', 'shipped', 'delivered', 'cancelled')),
  "carrier" text,
  "tracking_number" text,
  "tracking_url" text check ("tracking_url" ~ '^https://'),
  "created_at" timestamptz not null default now(),
  "shipped_at" timestamptz,
  "delivered_at" timestamptz
);
create index if not exists fulfillments_order_idx on "better_supabase"."fulfillments" ("order_id");
alter table "better_supabase"."fulfillments" enable row level security;
revoke all on "better_supabase"."fulfillments" from anon, authenticated;
grant select on "better_supabase"."fulfillments" to authenticated;
grant all on "better_supabase"."fulfillments" to service_role;
drop policy if exists fulfillments_read on "better_supabase"."fulfillments";
create policy fulfillments_read on "better_supabase"."fulfillments" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())));

create table if not exists "better_supabase"."fulfillment_lines" (
  "tenant_id" uuid not null,
  "fulfillment_id" uuid not null references "better_supabase"."fulfillments" ("id") on delete cascade,
  "order_line_id" uuid not null references "better_supabase"."order_lines" ("id") on delete cascade,
  "quantity" integer not null check ("quantity" > 0),
  primary key ("fulfillment_id", "order_line_id")
);
create index if not exists fulfillment_lines_line_idx on "better_supabase"."fulfillment_lines" ("order_line_id");
alter table "better_supabase"."fulfillment_lines" enable row level security;
revoke all on "better_supabase"."fulfillment_lines" from anon, authenticated;
grant select on "better_supabase"."fulfillment_lines" to authenticated;
grant all on "better_supabase"."fulfillment_lines" to service_role;
drop policy if exists fulfillment_lines_read on "better_supabase"."fulfillment_lines";
create policy fulfillment_lines_read on "better_supabase"."fulfillment_lines" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')));

create table if not exists "better_supabase"."order_returns" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null references "better_supabase"."orders" ("id") on delete cascade,
  "status" text not null default 'requested' check ("status" in ('requested', 'received', 'rejected')),
  "reason" text check (length("reason") <= 2000),
  "requested_by" uuid default auth.uid(),
  "created_at" timestamptz not null default now(),
  "received_at" timestamptz
);
create index if not exists order_returns_order_idx on "better_supabase"."order_returns" ("order_id");
alter table "better_supabase"."order_returns" enable row level security;
revoke all on "better_supabase"."order_returns" from anon, authenticated;
grant select on "better_supabase"."order_returns" to authenticated;
grant all on "better_supabase"."order_returns" to service_role;
drop policy if exists order_returns_read on "better_supabase"."order_returns";
create policy order_returns_read on "better_supabase"."order_returns" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())));

create table if not exists "better_supabase"."order_return_lines" (
  "tenant_id" uuid not null,
  "return_id" uuid not null references "better_supabase"."order_returns" ("id") on delete cascade,
  "order_line_id" uuid not null references "better_supabase"."order_lines" ("id") on delete cascade,
  "quantity" integer not null check ("quantity" > 0),
  primary key ("return_id", "order_line_id")
);
create index if not exists order_return_lines_line_idx on "better_supabase"."order_return_lines" ("order_line_id");
alter table "better_supabase"."order_return_lines" enable row level security;
revoke all on "better_supabase"."order_return_lines" from anon, authenticated;
grant select on "better_supabase"."order_return_lines" to authenticated;
grant all on "better_supabase"."order_return_lines" to service_role;
drop policy if exists order_return_lines_read on "better_supabase"."order_return_lines";
create policy order_return_lines_read on "better_supabase"."order_return_lines" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')));

create table if not exists "better_supabase"."order_refunds" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "order_id" uuid not null references "better_supabase"."orders" ("id") on delete cascade,
  "payment_id" uuid not null references "better_supabase"."order_payments" ("id") on delete cascade,
  "return_id" uuid references "better_supabase"."order_returns" ("id") on delete set null,
  "amount" bigint not null check ("amount" > 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "status" text not null default 'pending' check ("status" in ('pending', 'succeeded', 'failed')),
  "reason" text check (length("reason") <= 2000),
  "provider_reference" text,
  "created_at" timestamptz not null default now(),
  "completed_at" timestamptz
);
create index if not exists order_refunds_order_idx on "better_supabase"."order_refunds" ("order_id");
create index if not exists order_refunds_payment_idx on "better_supabase"."order_refunds" ("payment_id");
create index if not exists order_refunds_return_idx on "better_supabase"."order_refunds" ("return_id");
create unique index if not exists order_refunds_provider_reference_idx on "better_supabase"."order_refunds" ("provider_reference") where "provider_reference" is not null;
alter table "better_supabase"."order_refunds" enable row level security;
revoke all on "better_supabase"."order_refunds" from anon, authenticated;
grant select on "better_supabase"."order_refunds" to authenticated;
grant all on "better_supabase"."order_refunds" to service_role;
drop policy if exists order_refunds_read on "better_supabase"."order_refunds";
create policy order_refunds_read on "better_supabase"."order_refunds" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())));

-- Creates or updates a shipping rate: a flat amount, plus an amount per
-- started kilogram for weight rates, free from an order subtotal when
-- free_over is set. Countries are ISO 3166-1 alpha-2; none means anywhere.
-- Amounts are text in minor units.
create or replace function "better_supabase"."save_shipping_rate"(tenant uuid, rate uuid, data jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_countries text[];
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_shipping_rate.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if jsonb_typeof(data) is distinct from 'object' then
    raise exception 'the rate is an object' using errcode = '22023', hint = 'ORDERS_RATE_INVALID';
  end if;
  if "better_supabase"."currency_minor_units"(data ->> 'currency') is null then
    raise exception 'the currency is not an ISO 4217 code' using errcode = '22023', hint = 'ORDERS_CURRENCY_INVALID';
  end if;
  if (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end) is null
    or (data ? 'amountPerKg' and (case when (data ->> 'amountPerKg') ~ '^[0-9]{1,18}$' then (data ->> 'amountPerKg')::bigint end) is null)
    or (data ->> 'freeOver' is not null and (case when (data ->> 'freeOver') ~ '^[0-9]{1,18}$' then (data ->> 'freeOver')::bigint end) is null) then
    raise exception 'amounts are whole minor units of zero or more, as text' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
  end if;
  select coalesce(array_agg(value order by value), '{}') into v_countries
  from jsonb_array_elements_text(coalesce(data -> 'countries', '[]'::jsonb));
  if exists (select 1 from unnest(v_countries) as c(value) where c.value !~ '^[A-Z]{2}$') then
    raise exception 'countries are ISO 3166-1 alpha-2 codes' using errcode = '22023', hint = 'ORDERS_ADDRESS_INVALID';
  end if;
  if save_shipping_rate.rate is null then
    insert into "better_supabase"."shipping_rates" ("tenant_id", "name", "countries", "currency", "kind", "amount", "amount_per_kg", "free_over", "active")
    values (save_shipping_rate.tenant, data ->> 'name', v_countries, data ->> 'currency', coalesce(data ->> 'kind', 'flat'),
      (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end), coalesce((case when (data ->> 'amountPerKg') ~ '^[0-9]{1,18}$' then (data ->> 'amountPerKg')::bigint end), 0), (case when (data ->> 'freeOver') ~ '^[0-9]{1,18}$' then (data ->> 'freeOver')::bigint end), coalesce((data ->> 'active')::boolean, true))
    returning "id" into v_id;
  else
    update "better_supabase"."shipping_rates" x set "name" = data ->> 'name', "countries" = v_countries, "currency" = data ->> 'currency',
      "kind" = coalesce(data ->> 'kind', 'flat'), "amount" = (case when (data ->> 'amount') ~ '^[0-9]{1,18}$' then (data ->> 'amount')::bigint end), "amount_per_kg" = coalesce((case when (data ->> 'amountPerKg') ~ '^[0-9]{1,18}$' then (data ->> 'amountPerKg')::bigint end), 0),
      "free_over" = (case when (data ->> 'freeOver') ~ '^[0-9]{1,18}$' then (data ->> 'freeOver')::bigint end), "active" = coalesce((data ->> 'active')::boolean, true), "updated_at" = now()
    where x."id" = save_shipping_rate.rate and x."tenant_id" = save_shipping_rate.tenant
    returning x."id" into v_id;
    if v_id is null then
      raise exception 'shipping rate not found' using errcode = 'P0002', hint = 'ORDERS_RATE_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_shipping_rate"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_shipping_rate"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."delete_shipping_rate"(rate uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."shipping_rates" x where x."id" = delete_shipping_rate.rate;
  if not found then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  delete from "better_supabase"."shipping_rates" x where x."id" = delete_shipping_rate.rate;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_shipping_rate"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_shipping_rate"(uuid) to authenticated, service_role;

-- A cart's lines at today's catalog prices, its discounts, shipping and the
-- problems that keep it from checkout. Refreshes each line's price
-- snapshot. Internal: price_cart and place_order call it after their checks.
-- Amounts are text: JSON numbers lose bigint precision.
create or replace function "better_supabase"."cart_totals"(p_cart uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_line record;
  v_rate record;
  v_amount bigint;
  v_lines jsonb := '[]';
  v_problems jsonb := '[]';
  v_subtotal bigint := 0;
  v_discount bigint := 0;
  v_shipping bigint := 0;
  v_weight bigint := 0;
  v_ships boolean := false;
  v_free boolean := false;
  v_promo jsonb;
  v_discounts jsonb := '{}';
  v_applied jsonb := '[]';
  v_snapshot jsonb;
  v_country text;
begin
  select x."tenant_id" as tenant, x."currency" as currency, x."price_list_id" as price_list,
    x."shipping_address" as shipping_address, x."shipping_rate_id" as shipping_rate,
    x."user_id" as owner, x."status" as status, x."email" as email, x."billing_address" as billing_address
  into v_cart from "better_supabase"."carts" x where x."id" = p_cart;
  for v_line in
    select l."id" as id, l."variant_id" as variant, l."quantity" as quantity, l."unit_amount" as unit_amount,
      cv."sku" as sku, concat_ws(' / ', cp."title", nullif(cv."title", '')) as title, cp."id" as product, cp."status" as status,
      cp."kind" as kind, cv."weight_grams" as weight
    from "better_supabase"."cart_lines" l
    join "better_supabase"."product_variants" cv on cv."id" = l."variant_id"
    join "better_supabase"."products" cp on cp."id" = cv."product_id"
    where l."cart_id" = p_cart
    order by l."created_at", l."id"
  loop
    v_amount := ("better_supabase"."variant_price"(v_line.variant, v_cart.currency, v_cart.price_list, null) ->> 'amount')::bigint;
    if v_line.status <> 'active' or v_amount is null then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object('lineId', v_line.id, 'variantId', v_line.variant,
        'problem', case when v_line.status <> 'active' then 'unavailable' else 'unpriced' end));
      continue;
    end if;
    if v_line.unit_amount is distinct from v_amount then
      update "better_supabase"."cart_lines" x set "unit_amount" = v_amount, "updated_at" = now() where x."id" = v_line.id;
    end if;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'id', v_line.id, 'variantId', v_line.variant, 'productId', v_line.product, 'sku', v_line.sku, 'title', v_line.title,
      'quantity', v_line.quantity, 'unitAmount', v_amount::text, 'previousUnitAmount', v_line.unit_amount::text,
      'subtotal', (v_amount * v_line.quantity)::text, 'requiresShipping', v_line.kind = 'physical'));
    v_subtotal := v_subtotal + v_amount * v_line.quantity;
    if v_line.kind = 'physical' then
      v_ships := true;
      v_weight := v_weight + coalesce(v_line.weight, 0)::bigint * v_line.quantity;
    end if;
  end loop;
  select coalesce(jsonb_agg(e.l || jsonb_build_object(
      'discount', coalesce(v_discounts ->> (e.l ->> 'id'), '0'),
      'total', ((e.l ->> 'subtotal')::bigint - coalesce((v_discounts ->> (e.l ->> 'id'))::bigint, 0))::text) order by e.n), '[]'::jsonb),
    coalesce(sum(coalesce((v_discounts ->> (e.l ->> 'id'))::bigint, 0)), 0)
  into v_lines, v_discount
  from jsonb_array_elements(v_lines) with ordinality as e(l, n);
  v_country := v_cart.shipping_address ->> 'country';
  if v_ships and v_cart.shipping_rate is not null then
    select x."id" as id, x."name" as name, x."countries" as countries, x."kind" as kind,
      x."amount" as amount, x."amount_per_kg" as per_kg, x."free_over" as free_over
    into v_rate from "better_supabase"."shipping_rates" x
    where x."id" = v_cart.shipping_rate and x."active" and x."currency" = v_cart.currency;
    if not found or (cardinality(v_rate.countries) > 0 and (v_country is null or not v_country = any (v_rate.countries))) then
      v_problems := v_problems || jsonb_build_array(jsonb_build_object('problem', 'shipping_unavailable'));
    else
      v_shipping := v_rate.amount + case when v_rate.kind = 'weight' then (v_rate.per_kg * v_weight + 999) / 1000 else 0 end;
      if v_free or (v_rate.free_over is not null and v_subtotal - v_discount >= v_rate.free_over) then
        v_shipping := 0;
      end if;
      v_snapshot := jsonb_build_object('rateId', v_rate.id, 'name', v_rate.name, 'amount', v_shipping::text);
    end if;
  elsif v_ships and exists (
    select 1 from "better_supabase"."shipping_rates" x
    where x."tenant_id" = v_cart.tenant and x."active" and x."currency" = v_cart.currency
  ) then
    v_problems := v_problems || jsonb_build_array(jsonb_build_object('problem', 'shipping_required'));
  end if;
  return jsonb_build_object(
    'cartId', p_cart, 'organizationId', v_cart.tenant, 'customerId', v_cart.owner, 'status', v_cart.status,
    'email', v_cart.email, 'shippingAddress', v_cart.shipping_address, 'billingAddress', v_cart.billing_address,
    'currency', v_cart.currency, 'lines', v_lines,
    'subtotal', v_subtotal::text, 'discountTotal', v_discount::text, 'shippingTotal', v_shipping::text,
    'total', (v_subtotal - v_discount + v_shipping)::text, 'requiresShipping', v_ships,
    'weightGrams', v_weight::text, 'shipping', v_snapshot, 'promotions', v_applied, 'problems', v_problems);
end;
$$;
revoke execute on function "better_supabase"."cart_totals"(uuid) from public, anon, authenticated;

-- The caller's open cart in an organization and currency, created on first
-- use. Every signed-in user can have one, anonymous sign-ins included;
-- merge_carts moves it when the user signs up. Only staff set a price list.
create or replace function "better_supabase"."create_cart"(tenant uuid, currency text, price_list uuid default null, email text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if auth.uid() is null then
    raise exception 'sign in (anonymously is enough) to keep a cart' using errcode = '42501', hint = 'ORDERS_SIGN_IN_REQUIRED';
  end if;
  if "better_supabase"."currency_minor_units"(create_cart.currency) is null then
    raise exception 'the currency is not an ISO 4217 code' using errcode = '22023', hint = 'ORDERS_CURRENCY_INVALID';
  end if;
  if create_cart.price_list is not null then
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', create_cart.tenant, 'orders.manage'), false)) then
      raise exception 'only staff can put a cart on a price list' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
    end if;
    if not exists (select 1 from "better_supabase"."price_lists" x where x."id" = create_cart.price_list and x."tenant_id" = create_cart.tenant) then
      raise exception 'price list not found' using errcode = 'P0002', hint = 'ORDERS_PRICE_LIST_NOT_FOUND';
    end if;
  end if;
  insert into "better_supabase"."carts" as x ("tenant_id", "user_id", "currency", "price_list_id", "email")
  values (create_cart.tenant, auth.uid(), create_cart.currency, create_cart.price_list, create_cart.email)
  on conflict ("tenant_id", "user_id", "currency") where "status" = 'open' do update
    set "price_list_id" = coalesce(excluded."price_list_id", x."price_list_id"),
      "email" = coalesce(excluded."email", x."email"), "updated_at" = now()
  returning x."id" into v_id;
  return jsonb_build_object('id', v_id, 'currency', create_cart.currency, 'status', 'open');
end;
$$;
revoke execute on function "better_supabase"."create_cart"(uuid, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."create_cart"(uuid, text, uuid, text) to authenticated, service_role;

-- Adds units of a variant to the cart; a variant already in it gets more.
create or replace function "better_supabase"."add_to_cart"(cart uuid, variant uuid, quantity integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_id uuid;
  v_quantity integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status,
    x."currency" as currency, x."price_list_id" as price_list, x."shipping_address" as shipping_address
  into v_cart from "better_supabase"."carts" x where x."id" = add_to_cart.cart for update;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  if add_to_cart.quantity is null or add_to_cart.quantity < 1 then
    raise exception 'the quantity must be a positive whole number' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
  end if;
  if not exists (
    select 1 from "better_supabase"."product_variants" cv join "better_supabase"."products" cp on cp."id" = cv."product_id"
    where cv."id" = add_to_cart.variant and cv."tenant_id" = v_cart.tenant and cp."status" = 'active'
  ) then
    raise exception 'this variant is not for sale' using errcode = 'P0002', hint = 'ORDERS_VARIANT_UNAVAILABLE';
  end if;
  select x."quantity" + add_to_cart.quantity into v_quantity from "better_supabase"."cart_lines" x
  where x."cart_id" = add_to_cart.cart and x."variant_id" = add_to_cart.variant;
  if coalesce(v_quantity, add_to_cart.quantity) > 10000 then
    raise exception 'a cart line holds at most 10000 units' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
  end if;
  insert into "better_supabase"."cart_lines" as x ("tenant_id", "cart_id", "variant_id", "quantity")
  values (v_cart.tenant, add_to_cart.cart, add_to_cart.variant, add_to_cart.quantity)
  on conflict ("cart_id", "variant_id") do update
    set "quantity" = x."quantity" + excluded."quantity", "updated_at" = now()
  returning x."id", x."quantity" into v_id, v_quantity;
  update "better_supabase"."carts" x set "updated_at" = now() where x."id" = add_to_cart.cart;
  return jsonb_build_object('lineId', v_id, 'quantity', v_quantity);
end;
$$;
revoke execute on function "better_supabase"."add_to_cart"(uuid, uuid, integer) from public, anon;
grant execute on function "better_supabase"."add_to_cart"(uuid, uuid, integer) to authenticated, service_role;

-- Sets a variant's quantity in the cart; zero removes the line.
create or replace function "better_supabase"."set_cart_line"(cart uuid, variant uuid, quantity integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status,
    x."currency" as currency, x."price_list_id" as price_list, x."shipping_address" as shipping_address
  into v_cart from "better_supabase"."carts" x where x."id" = set_cart_line.cart for update;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  if set_cart_line.quantity is null or set_cart_line.quantity < 0 or set_cart_line.quantity > 10000 then
    raise exception 'the quantity is a whole number from 0 to 10000' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
  end if;
  if set_cart_line.quantity = 0 then
    delete from "better_supabase"."cart_lines" x where x."cart_id" = set_cart_line.cart and x."variant_id" = set_cart_line.variant;
    update "better_supabase"."carts" x set "updated_at" = now() where x."id" = set_cart_line.cart;
    return jsonb_build_object('lineId', null, 'quantity', 0);
  end if;
  if not exists (
    select 1 from "better_supabase"."product_variants" cv join "better_supabase"."products" cp on cp."id" = cv."product_id"
    where cv."id" = set_cart_line.variant and cv."tenant_id" = v_cart.tenant and cp."status" = 'active'
  ) then
    raise exception 'this variant is not for sale' using errcode = 'P0002', hint = 'ORDERS_VARIANT_UNAVAILABLE';
  end if;
  insert into "better_supabase"."cart_lines" as x ("tenant_id", "cart_id", "variant_id", "quantity")
  values (v_cart.tenant, set_cart_line.cart, set_cart_line.variant, set_cart_line.quantity)
  on conflict ("cart_id", "variant_id") do update
    set "quantity" = excluded."quantity", "updated_at" = now()
  returning x."id" into v_id;
  update "better_supabase"."carts" x set "updated_at" = now() where x."id" = set_cart_line.cart;
  return jsonb_build_object('lineId', v_id, 'quantity', set_cart_line.quantity);
end;
$$;
revoke execute on function "better_supabase"."set_cart_line"(uuid, uuid, integer) from public, anon;
grant execute on function "better_supabase"."set_cart_line"(uuid, uuid, integer) to authenticated, service_role;

-- Sets the cart's email and addresses; a null argument keeps the value.
create or replace function "better_supabase"."set_cart_details"(cart uuid, email text default null, shipping_address jsonb default null, billing_address jsonb default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status,
    x."currency" as currency, x."price_list_id" as price_list, x."shipping_address" as shipping_address
  into v_cart from "better_supabase"."carts" x where x."id" = set_cart_details.cart for update;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  if set_cart_details.shipping_address is not null and (jsonb_typeof(set_cart_details.shipping_address) <> 'object' or (set_cart_details.shipping_address ? 'country' and coalesce(set_cart_details.shipping_address ->> 'country', '') !~ '^[A-Z]{2}$')) then
    raise exception 'an address is an object whose country is an ISO 3166-1 alpha-2 code' using errcode = '22023', hint = 'ORDERS_ADDRESS_INVALID';
  end if;
  if set_cart_details.billing_address is not null and (jsonb_typeof(set_cart_details.billing_address) <> 'object' or (set_cart_details.billing_address ? 'country' and coalesce(set_cart_details.billing_address ->> 'country', '') !~ '^[A-Z]{2}$')) then
    raise exception 'an address is an object whose country is an ISO 3166-1 alpha-2 code' using errcode = '22023', hint = 'ORDERS_ADDRESS_INVALID';
  end if;
  update "better_supabase"."carts" x set
    "email" = coalesce(set_cart_details.email, x."email"),
    "shipping_address" = coalesce(set_cart_details.shipping_address, x."shipping_address"),
    "billing_address" = coalesce(set_cart_details.billing_address, x."billing_address"),
    "updated_at" = now()
  where x."id" = set_cart_details.cart;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_cart_details"(uuid, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."set_cart_details"(uuid, text, jsonb, jsonb) to authenticated, service_role;

-- Picks one of the cart's shipping options, or clears it with null.
create or replace function "better_supabase"."set_cart_shipping_rate"(cart uuid, rate uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status,
    x."currency" as currency, x."price_list_id" as price_list, x."shipping_address" as shipping_address
  into v_cart from "better_supabase"."carts" x where x."id" = set_cart_shipping_rate.cart for update;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid()) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  if set_cart_shipping_rate.rate is not null and not exists (
    select 1 from "better_supabase"."shipping_rates" x
    where x."id" = set_cart_shipping_rate.rate and x."tenant_id" = v_cart.tenant and x."active"
      and x."currency" = v_cart.currency
      and (cardinality(x."countries") = 0 or (v_cart.shipping_address ->> 'country') = any (x."countries"))
  ) then
    raise exception 'this shipping rate doesn''t serve the cart' using errcode = 'P0002', hint = 'ORDERS_RATE_NOT_FOUND';
  end if;
  update "better_supabase"."carts" x set "shipping_rate_id" = set_cart_shipping_rate.rate, "updated_at" = now()
  where x."id" = set_cart_shipping_rate.cart;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_cart_shipping_rate"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."set_cart_shipping_rate"(uuid, uuid) to authenticated, service_role;

-- The active rates that serve the cart's currency and shipping country,
-- each with what it costs for this cart.
create or replace function "better_supabase"."shipping_options"(cart uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_totals jsonb;
  v_after_discount bigint;
  v_weight bigint;
begin
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status,
    x."currency" as currency, x."price_list_id" as price_list, x."shipping_address" as shipping_address
  into v_cart from "better_supabase"."carts" x where x."id" = shipping_options.cart;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid() or coalesce(better_supabase.can('tenant', v_cart.tenant, 'orders.read'), false)) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  v_totals := "better_supabase"."cart_totals"(shipping_options.cart);
  v_after_discount := (v_totals ->> 'subtotal')::bigint - (v_totals ->> 'discountTotal')::bigint;
  v_weight := (v_totals ->> 'weightGrams')::bigint;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', x."id", 'name', x."name", 'kind', x."kind", 'currency', x."currency",
      'amount', (case
        when x."free_over" is not null and v_after_discount >= x."free_over" then 0
        else x."amount" + case when x."kind" = 'weight' then (x."amount_per_kg" * v_weight + 999) / 1000 else 0 end
      end)::text) order by x."amount", x."name")
    from "better_supabase"."shipping_rates" x
    where x."tenant_id" = v_cart.tenant and x."active" and x."currency" = v_cart.currency
      and (cardinality(x."countries") = 0 or (v_cart.shipping_address ->> 'country') = any (x."countries"))
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."shipping_options"(uuid) from public, anon;
grant execute on function "better_supabase"."shipping_options"(uuid) to authenticated, service_role;

-- The cart at today's prices: lines, discounts, shipping, the pre-tax
-- total and what keeps it from checkout. Its owner and the organization's
-- order readers can price it.
create or replace function "better_supabase"."price_cart"(cart uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
begin
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status,
    x."currency" as currency, x."price_list_id" as price_list, x."shipping_address" as shipping_address
  into v_cart from "better_supabase"."carts" x where x."id" = price_cart.cart;
  if not found or not (auth.role() = 'service_role' or v_cart.owner = auth.uid() or coalesce(better_supabase.can('tenant', v_cart.tenant, 'orders.read'), false)) then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  return "better_supabase"."cart_totals"(price_cart.cart);
end;
$$;
revoke execute on function "better_supabase"."price_cart"(uuid) from public, anon;
grant execute on function "better_supabase"."price_cart"(uuid) to authenticated, service_role;

-- Moves a user's open carts to another user, such as an anonymous user who
-- signed up or signed in. A cart in the same organization and currency
-- takes the lines, adding up quantities, and its promotion codes. Returns
-- the carts moved or merged.
create or replace function "better_supabase"."merge_carts"(from_user uuid, to_user uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from record;
  v_to uuid;
  v_count integer := 0;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if merge_carts.from_user = merge_carts.to_user then
    return 0;
  end if;
  for v_from in
    select x."id" as id, x."tenant_id" as tenant, x."currency" as currency
    from "better_supabase"."carts" x where x."user_id" = merge_carts.from_user and x."status" = 'open'
    for update
  loop
    select x."id" into v_to from "better_supabase"."carts" x
    where x."user_id" = merge_carts.to_user and x."tenant_id" = v_from.tenant
      and x."currency" = v_from.currency and x."status" = 'open'
    for update;
    if v_to is null then
      update "better_supabase"."carts" x set "user_id" = merge_carts.to_user, "updated_at" = now() where x."id" = v_from.id;
    else
      insert into "better_supabase"."cart_lines" as x ("tenant_id", "cart_id", "variant_id", "quantity", "unit_amount")
      select l."tenant_id", v_to, l."variant_id", l."quantity", l."unit_amount"
      from "better_supabase"."cart_lines" l where l."cart_id" = v_from.id
      on conflict ("cart_id", "variant_id") do update
        set "quantity" = least(x."quantity" + excluded."quantity", 10000), "updated_at" = now();
      update "better_supabase"."carts" x set "status" = 'abandoned', "updated_at" = now() where x."id" = v_from.id;
    end if;
    v_to := null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."merge_carts"(uuid, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."merge_carts"(uuid, uuid) to service_role;

-- Moves an order to p_to and stamps when it happened. Internal: the order
-- functions call it after their own checks.
create or replace function "better_supabase"."order_transition"(p_order uuid, p_to text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from text;
begin
  select x."status" into v_from from "better_supabase"."orders" x where x."id" = p_order for update;
  if v_from = p_to then
    return v_from;
  end if;
  if not (case v_from
    when 'pending_payment' then p_to = any ('{paid,cancelled}'::text[])
    when 'paid' then p_to = any ('{fulfilled,refunded}'::text[])
    when 'fulfilled' then p_to = any ('{paid,completed,refunded}'::text[])
    when 'completed' then p_to = any ('{refunded}'::text[])
    when 'cancelled' then p_to = any ('{}'::text[])
    when 'refunded' then p_to = any ('{}'::text[])
    else false end) then
    raise exception 'the order can''t move to this status' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  update "better_supabase"."orders" x set "status" = p_to, "updated_at" = now(),
    "paid_at" = case when p_to = 'paid' then coalesce(x."paid_at", now()) else x."paid_at" end,
    "fulfilled_at" = case when p_to = 'fulfilled' then now() when p_to = 'paid' then null else x."fulfilled_at" end,
    "completed_at" = case when p_to = 'completed' then now() else x."completed_at" end,
    "cancelled_at" = case when p_to = 'cancelled' then now() else x."cancelled_at" end
  where x."id" = p_order;
  return v_from;
end;
$$;
revoke execute on function "better_supabase"."order_transition"(uuid, text) from public, anon, authenticated;

-- The order as one object. Amounts are text. Internal: get_order and
-- place_order return it after their checks.
create or replace function "better_supabase"."order_json"(p_order uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id", 'organizationId', x."tenant_id", 'number', x."number", 'cartId', x."cart_id",
    'customerId', x."customer_id", 'email', x."email", 'status', x."status", 'currency', x."currency",
    'subtotal', x."subtotal"::text, 'discountTotal', x."discount_total"::text,
    'shippingTotal', x."shipping_total"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'paidTotal', x."paid_total"::text, 'refundedTotal', x."refunded_total"::text, 'taxInclusive', x."tax_inclusive",
    'shippingAddress', x."shipping_address", 'billingAddress', x."billing_address", 'shipping', x."shipping",
    'promotions', x."promotions", 'tax', x."tax", 'taxTransaction', x."tax_transaction",
    'invoiceNumber', x."invoice_number", 'invoicedAt', x."invoiced_at", 'placedAt', x."placed_at",
    'paidAt', x."paid_at", 'fulfilledAt', x."fulfilled_at", 'completedAt', x."completed_at",
    'cancelledAt', x."cancelled_at", 'cancelReason', x."cancel_reason",
    'lines', coalesce((select jsonb_agg(jsonb_build_object(
        'id', l."id", 'variantId', l."variant_id", 'productId', l."product_id", 'sku', l."sku",
        'title', l."title", 'quantity', l."quantity", 'unitAmount', l."unit_amount"::text,
        'subtotal', l."subtotal"::text, 'discount', l."discount"::text, 'tax', l."tax"::text,
        'total', l."total"::text, 'requiresShipping', l."requires_shipping", 'locationId', l."location_id",
        'reservationId', l."reservation_id", 'fulfilled', l."quantity_fulfilled", 'returned', l."quantity_returned",
        'backordered', l."backordered") order by l."position")
      from "better_supabase"."order_lines" l where l."order_id" = x."id"), '[]'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y."id", 'provider', y."provider", 'reference', y."reference", 'status', y."status",
        'amount', y."amount"::text, 'captured', y."captured"::text, 'refunded', y."refunded"::text,
        'createdAt', y."created_at") order by y."created_at")
      from "better_supabase"."order_payments" y where y."order_id" = x."id"), '[]'::jsonb),
    'fulfillments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y."id", 'status', y."status", 'locationId', y."location_id", 'carrier', y."carrier",
        'trackingNumber', y."tracking_number", 'trackingUrl', y."tracking_url", 'createdAt', y."created_at",
        'shippedAt', y."shipped_at", 'deliveredAt', y."delivered_at",
        'lines', coalesce((select jsonb_agg(jsonb_build_object('lineId', z."order_line_id", 'quantity', z."quantity"))
          from "better_supabase"."fulfillment_lines" z where z."fulfillment_id" = y."id"), '[]'::jsonb)) order by y."created_at")
      from "better_supabase"."fulfillments" y where y."order_id" = x."id"), '[]'::jsonb),
    'returns', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y."id", 'status', y."status", 'reason', y."reason", 'createdAt', y."created_at",
        'receivedAt', y."received_at",
        'lines', coalesce((select jsonb_agg(jsonb_build_object('lineId', z."order_line_id", 'quantity', z."quantity"))
          from "better_supabase"."order_return_lines" z where z."return_id" = y."id"), '[]'::jsonb)) order by y."created_at")
      from "better_supabase"."order_returns" y where y."order_id" = x."id"), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object(
        'id', y."id", 'paymentId', y."payment_id", 'returnId', y."return_id", 'amount', y."amount"::text,
        'status', y."status", 'reason', y."reason", 'providerReference', y."provider_reference",
        'createdAt', y."created_at", 'completedAt', y."completed_at") order by y."created_at")
      from "better_supabase"."order_refunds" y where y."order_id" = x."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', x."app_note"))
  from "better_supabase"."orders" x where x."id" = p_order
$$;
revoke execute on function "better_supabase"."order_json"(uuid) from public, anon, authenticated;

-- Turns an open cart into an order: prices it again, refuses a total that
-- moved since the caller quoted tax (ORDERS_PRICE_CHANGED), numbers the
-- order, reserves its stock for the payment window and redeems its
-- promotions. tax is the TaxQuote as JSON (amounts as text) or null.
-- Placing the same cart again returns its order. Service only: the
-- TypeScript checkout calls the tax and payment providers around it.
drop function if exists "better_supabase"."place_order"(uuid, jsonb, bigint, uuid);
create or replace function "better_supabase"."place_order"(cart uuid, tax jsonb default null, expected_total bigint default null, location uuid default null, fields jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cart record;
  v_order record;
  v_line record;
  v_priced jsonb;
  v_tax bigint := 0;
  v_line_tax bigint;
  v_invalid boolean;
  v_inclusive boolean := false;
  v_total bigint;
  v_seq bigint;
  v_number text;
  v_id uuid;
  v_location uuid;
  v_reservation jsonb;
  v_claims text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  select x."tenant_id" as tenant, x."user_id" as owner, x."status" as status, x."currency" as currency,
    x."email" as email, x."shipping_address" as shipping_address, x."billing_address" as billing_address
  into v_cart from "better_supabase"."carts" x where x."id" = place_order.cart for update;
  if not found then
    raise exception 'cart not found' using errcode = 'P0002', hint = 'ORDERS_CART_NOT_FOUND';
  end if;
  if v_cart.status = 'converted' then
    select x."id" into v_id from "better_supabase"."orders" x where x."cart_id" = place_order.cart;
    if v_id is not null then
      return "better_supabase"."order_json"(v_id) || jsonb_build_object('created', false);
    end if;
  end if;
  if v_cart.status <> 'open' then
    raise exception 'the cart is no longer open' using errcode = '55000', hint = 'ORDERS_CART_CLOSED';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_order_place"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using place_order.cart;
    end if;
  end;
  v_priced := "better_supabase"."cart_totals"(place_order.cart);
  if jsonb_array_length(v_priced -> 'lines') = 0 then
    raise exception 'the cart has no lines to order' using errcode = '55000', hint = 'ORDERS_CART_EMPTY';
  end if;
  if jsonb_array_length(v_priced -> 'problems') > 0 then
    raise exception 'the cart can''t be ordered: %', v_priced -> 'problems' using errcode = '55000', hint = 'ORDERS_CART_INVALID';
  end if;
  if place_order.expected_total is not null and (v_priced ->> 'total')::bigint <> place_order.expected_total then
    raise exception 'the cart''s total changed; price it and quote tax again' using errcode = '40001', hint = 'ORDERS_PRICE_CHANGED';
  end if;
  if place_order.tax is not null then
    if jsonb_typeof(place_order.tax) <> 'object' or (case when (place_order.tax ->> 'totalTax') ~ '^[0-9]{1,18}$' then (place_order.tax ->> 'totalTax')::bigint end) is null
      or coalesce(place_order.tax ->> 'currency', v_cart.currency) <> v_cart.currency then
      raise exception 'tax is a quote in the cart''s currency with a totalTax of zero or more' using errcode = '22023', hint = 'ORDERS_TAX_INVALID';
    end if;
    v_tax := (case when (place_order.tax ->> 'totalTax') ~ '^[0-9]{1,18}$' then (place_order.tax ->> 'totalTax')::bigint end);
    v_inclusive := coalesce((place_order.tax ->> 'inclusive')::boolean, false);
    select coalesce(sum((case when (e ->> 'tax') ~ '^[0-9]{1,18}$' then (e ->> 'tax')::bigint end)), 0), coalesce(bool_or((case when (e ->> 'tax') ~ '^[0-9]{1,18}$' then (e ->> 'tax')::bigint end) is null), false)
    into v_line_tax, v_invalid
    from jsonb_array_elements(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) e;
    if v_invalid or (jsonb_array_length(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) > 0 and v_line_tax <> v_tax) then
      raise exception 'the tax lines don''t add up to totalTax' using errcode = '22023', hint = 'ORDERS_TAX_INVALID';
    end if;
  end if;
  v_total := (v_priced ->> 'total')::bigint + case when v_inclusive then 0 else v_tax end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_cart.tenant::text || ':commerce:order', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."orders" x where x."tenant_id" = v_cart.tenant;
  v_number := v_seq::text;
  insert into "better_supabase"."orders" ("tenant_id", "number", "sequence", "cart_id", "customer_id", "email", "currency",
    "subtotal", "discount_total", "shipping_total", "tax_total", "total", "tax_inclusive",
    "shipping_address", "billing_address", "shipping", "promotions", "tax")
  values (v_cart.tenant, v_number, v_seq, place_order.cart, v_cart.owner, v_cart.email, v_cart.currency,
    (v_priced ->> 'subtotal')::bigint, (v_priced ->> 'discountTotal')::bigint, (v_priced ->> 'shippingTotal')::bigint,
    v_tax, v_total, v_inclusive, v_cart.shipping_address, v_cart.billing_address, v_priced -> 'shipping',
    v_priced -> 'promotions', place_order.tax)
  returning "id" into v_id;
  update "better_supabase"."orders" x set "app_note" = case when place_order.fields ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."orders", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(place_order.fields) e where e.key in ('app_note'))) r
  where x."id" = v_id;
  insert into "better_supabase"."order_lines" ("tenant_id", "order_id", "position", "variant_id", "product_id", "sku", "title",
    "quantity", "unit_amount", "subtotal", "discount", "tax", "total", "requires_shipping")
  select v_cart.tenant, v_id, e.n, (e.l ->> 'variantId')::uuid, (e.l ->> 'productId')::uuid, e.l ->> 'sku', e.l ->> 'title',
    (e.l ->> 'quantity')::integer, (e.l ->> 'unitAmount')::bigint, (e.l ->> 'subtotal')::bigint, (e.l ->> 'discount')::bigint,
    coalesce((select (case when (t ->> 'tax') ~ '^[0-9]{1,18}$' then (t ->> 'tax')::bigint end) from jsonb_array_elements(coalesce(place_order.tax -> 'lines', '[]'::jsonb)) t
      where t ->> 'lineId' = e.l ->> 'id' limit 1), 0),
    (e.l ->> 'total')::bigint, (e.l ->> 'requiresShipping')::boolean
  from jsonb_array_elements(v_priced -> 'lines') with ordinality as e(l, n);
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_id;
  update "better_supabase"."carts" x set "status" = 'converted', "converted_at" = now(), "updated_at" = now()
  where x."id" = place_order.cart;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_order_place"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_order.id;
    end if;
  end;
  return "better_supabase"."order_json"(v_order.id) || jsonb_build_object('created', true);
end;
$$;
revoke execute on function "better_supabase"."place_order"(uuid, jsonb, bigint, uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."place_order"(uuid, jsonb, bigint, uuid, jsonb) to service_role;

-- Records what a payment provider reports for an order's payment, keyed on
-- provider and reference, so a redelivered webhook changes nothing. A late
-- event never moves a settled payment back. Once the succeeded payments
-- cover the total, the order is paid: its reservations become sales, it
-- gets a gapless invoice number and order.paid is recorded. order may be
-- null for a payment recorded before. Amounts are minor units.
create or replace function "better_supabase"."record_payment"(order_id uuid, provider text, reference text, status text, currency text,
  amount bigint, captured bigint default 0, refunded bigint default 0)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_order record;
  v_line record;
  v_id uuid := record_payment.order_id;
  v_paid bigint;
  v_newly boolean := false;
  v_seq bigint;
  v_number text;
  v_claims text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_id is null then
    select x."order_id" into v_id from "better_supabase"."order_payments" x
    where x."provider" = record_payment.provider and x."reference" = record_payment.reference;
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if record_payment.status is null or record_payment.status not in ('requires_action', 'processing', 'authorized', 'succeeded', 'failed', 'canceled') then
    raise exception 'unknown payment status' using errcode = '22023', hint = 'ORDERS_PAYMENT_STATUS_INVALID';
  end if;
  if record_payment.currency is distinct from v_order.currency then
    raise exception 'the payment is in another currency than the order' using errcode = '22023', hint = 'ORDERS_CURRENCY_MISMATCH';
  end if;
  if coalesce(record_payment.amount, -1) < 0 or coalesce(record_payment.captured, 0) < 0 or coalesce(record_payment.refunded, 0) < 0 then
    raise exception 'payment amounts are zero or more' using errcode = '22023', hint = 'ORDERS_AMOUNT_INVALID';
  end if;
  insert into "better_supabase"."order_payments" as x ("tenant_id", "order_id", "provider", "reference", "status", "currency",
    "amount", "captured", "refunded")
  values (v_order.tenant, v_order.id, record_payment.provider, record_payment.reference, record_payment.status, record_payment.currency,
    record_payment.amount, coalesce(record_payment.captured, 0), coalesce(record_payment.refunded, 0))
  on conflict ("provider", "reference") do update set
    "status" = case when x."status" in ('succeeded', 'failed', 'canceled') and excluded."status" not in ('succeeded', 'failed', 'canceled') then x."status" else excluded."status" end,
    "amount" = excluded."amount",
    "captured" = greatest(x."captured", excluded."captured"),
    "refunded" = greatest(x."refunded", excluded."refunded"),
    "updated_at" = now()
  where x."order_id" = excluded."order_id";
  if not found then
    raise exception 'this payment reference belongs to another order' using errcode = '23505', hint = 'ORDERS_PAYMENT_CONFLICT';
  end if;
  select coalesce(sum(x."captured"), 0) into v_paid from "better_supabase"."order_payments" x
  where x."order_id" = v_order.id and x."status" = 'succeeded';
  update "better_supabase"."orders" x set "paid_total" = v_paid, "updated_at" = now() where x."id" = v_order.id;
  if v_order.status = 'pending_payment' and v_paid >= v_order.total then
    perform "better_supabase"."order_transition"(v_order.id, 'paid');
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_order.tenant::text || ':commerce:invoice', 0));
  select coalesce(max(x."invoice_sequence"), 0) + 1 into v_seq from "better_supabase"."orders" x where x."tenant_id" = v_order.tenant;
  v_number := v_seq::text;
    update "better_supabase"."orders" x set "invoice_number" = v_number, "invoice_sequence" = v_seq, "invoiced_at" = now()
    where x."id" = v_order.id;
    null;
    v_newly := true;
  end if;
  return jsonb_build_object('orderId', v_order.id, 'status', (select x."status" from "better_supabase"."orders" x where x."id" = v_order.id),
    'paidTotal', v_paid::text, 'newlyPaid', v_newly,
    'invoiceNumber', coalesce(v_number, v_order.invoice_number));
end;
$$;
revoke execute on function "better_supabase"."record_payment"(uuid, text, text, text, text, bigint, bigint, bigint) from public, anon, authenticated;
grant execute on function "better_supabase"."record_payment"(uuid, text, text, text, text, bigint, bigint, bigint) to service_role;

-- Stores the tax provider's transaction for the sale, to reverse it on a refund.
create or replace function "better_supabase"."set_order_tax_transaction"(order_id uuid, tax_transaction jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  update "better_supabase"."orders" x set "tax_transaction" = set_order_tax_transaction.tax_transaction, "updated_at" = now()
  where x."id" = set_order_tax_transaction.order_id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."set_order_tax_transaction"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."set_order_tax_transaction"(uuid, jsonb) to service_role;

-- Cancels an order waiting for payment: releases its stock and its
-- promotion redemptions. Internal: cancel_order and expire_orders check first.
create or replace function "better_supabase"."order_cancel"(p_order uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_line record;
  v_claims text;
begin
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = p_order for update;
  perform "better_supabase"."order_transition"(v_order.id, 'cancelled');
  update "better_supabase"."orders" x set "cancel_reason" = p_reason where x."id" = v_order.id;
  null;
end;
$$;
revoke execute on function "better_supabase"."order_cancel"(uuid, text) from public, anon, authenticated;

-- Cancels an order that is waiting for payment. Staff with orders.manage
-- and the customer who placed it can.
create or replace function "better_supabase"."cancel_order"(order_id uuid, reason text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
begin
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = cancel_order.order_id for update;
  if not found or not (auth.role() = 'service_role' or v_order.customer = auth.uid() or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.read'), false)) then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or v_order.customer = auth.uid() or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to cancel this order' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_order.status = 'cancelled' then
    return false;
  end if;
  if v_order.status <> 'pending_payment' then
    raise exception 'only an order waiting for payment can be cancelled; refund a paid one' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  perform "better_supabase"."order_cancel"(v_order.id, cancel_order.reason);
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_order"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_order"(uuid, text) to authenticated, service_role;

-- Cancels orders still waiting for payment once the payment window
-- (30 minutes) is over. Service only; run it from a job.
create or replace function "better_supabase"."expire_orders"(max_rows integer default 100)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  for v_id in
    select x."id" from "better_supabase"."orders" x
    where x."status" = 'pending_payment' and x."placed_at" < now() - interval '30 minutes'
    order by x."placed_at"
    limit greatest(coalesce(expire_orders.max_rows, 100), 1)
    for update skip locked
  loop
    perform "better_supabase"."order_cancel"(v_id, 'payment_expired');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_orders"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."expire_orders"(integer) to service_role;

-- The order with its lines, payments, fulfillments, returns and refunds,
-- for its customer and the organization's order readers.
create or replace function "better_supabase"."get_order"(order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_order record;
begin
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = get_order.order_id;
  if not found or not (auth.role() = 'service_role' or v_order.customer = auth.uid() or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.read'), false)) then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  return "better_supabase"."order_json"(v_order.id);
end;
$$;
revoke execute on function "better_supabase"."get_order"(uuid) from public, anon;
grant execute on function "better_supabase"."get_order"(uuid) to authenticated, service_role;

-- Fulfills lines of a paid order from one location. lines is
-- [{lineId, quantity}]; null fulfills everything not yet fulfilled.
create or replace function "better_supabase"."create_fulfillment"(order_id uuid, lines jsonb default null, location uuid default null,
  carrier text default null, tracking_number text default null, tracking_url text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_item record;
  v_requested jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = create_fulfillment.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_order.status <> 'paid' then
    raise exception 'only a paid order can be fulfilled' using errcode = '55000', hint = 'ORDERS_NOT_PAID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_fulfillment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_order.id;
    end if;
  end;
  v_requested := coalesce(create_fulfillment.lines, (
    select jsonb_agg(jsonb_build_object('lineId', l."id", 'quantity', l."quantity" - l."quantity_fulfilled") order by l."position")
    from "better_supabase"."order_lines" l where l."order_id" = v_order.id and l."quantity" > l."quantity_fulfilled"));
  if v_requested is null or jsonb_typeof(v_requested) <> 'array' or jsonb_array_length(v_requested) = 0 then
    raise exception 'no lines left to fulfill' using errcode = '55000', hint = 'ORDERS_NOTHING_TO_FULFILL';
  end if;
  insert into "better_supabase"."fulfillments" ("tenant_id", "order_id", "location_id", "carrier", "tracking_number", "tracking_url")
  values (v_order.tenant, v_order.id,
    coalesce(create_fulfillment.location, (select l."location_id" from "better_supabase"."order_lines" l where l."order_id" = v_order.id and l."location_id" is not null order by l."position" limit 1)),
    create_fulfillment.carrier, create_fulfillment.tracking_number, create_fulfillment.tracking_url)
  returning "id" into v_id;
  for v_item in
    select (e ->> 'lineId')::uuid as line, (e ->> 'quantity')::integer as quantity from jsonb_array_elements(v_requested) e
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'each quantity is a whole number above zero' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
    end if;
    update "better_supabase"."order_lines" x set "quantity_fulfilled" = x."quantity_fulfilled" + v_item.quantity
    where x."id" = v_item.line and x."order_id" = v_order.id and x."quantity_fulfilled" + v_item.quantity <= x."quantity";
    if not found then
      raise exception 'a line isn''t on this order or has less left to fulfill' using errcode = '22023', hint = 'ORDERS_FULFILLMENT_INVALID';
    end if;
    insert into "better_supabase"."fulfillment_lines" as x ("tenant_id", "fulfillment_id", "order_line_id", "quantity")
    values (v_order.tenant, v_id, v_item.line, v_item.quantity)
    on conflict ("fulfillment_id", "order_line_id") do update set "quantity" = x."quantity" + excluded."quantity";
  end loop;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_fulfillment_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'orderId', v_order.id, 'status', 'pending');
end;
$$;
revoke execute on function "better_supabase"."create_fulfillment"(uuid, jsonb, uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."create_fulfillment"(uuid, jsonb, uuid, text, text, text) to authenticated, service_role;

-- Marks a fulfillment shipped. Once every line has shipped, the order is
-- fulfilled.
create or replace function "better_supabase"."ship_fulfillment"(fulfillment uuid, carrier text default null, tracking_number text default null, tracking_url text default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fulfillment record;
  v_order record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."order_id" as order_id, x."status" as status into v_fulfillment
  from "better_supabase"."fulfillments" x where x."id" = ship_fulfillment.fulfillment for update;
  if not found then
    raise exception 'fulfillment not found' using errcode = 'P0002', hint = 'ORDERS_FULFILLMENT_NOT_FOUND';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_fulfillment.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_fulfillment.status = 'shipped' then
    return false;
  end if;
  if v_fulfillment.status <> 'pending' then
    raise exception 'only a pending fulfillment can ship' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  update "better_supabase"."fulfillments" x set "status" = 'shipped', "shipped_at" = now(),
    "carrier" = coalesce(ship_fulfillment.carrier, x."carrier"),
    "tracking_number" = coalesce(ship_fulfillment.tracking_number, x."tracking_number"),
    "tracking_url" = coalesce(ship_fulfillment.tracking_url, x."tracking_url")
  where x."id" = v_fulfillment.id;
  null;
  if v_order.status = 'paid'
    and not exists (select 1 from "better_supabase"."order_lines" l where l."order_id" = v_order.id and l."quantity_fulfilled" < l."quantity")
    and not exists (select 1 from "better_supabase"."fulfillments" x where x."order_id" = v_order.id and x."status" = 'pending') then
    perform "better_supabase"."order_transition"(v_order.id, 'fulfilled');
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."ship_fulfillment"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."ship_fulfillment"(uuid, text, text, text) to authenticated, service_role;

-- Marks a shipped fulfillment delivered, from staff or a carrier webhook.
-- Once everything is delivered, the order is completed.
create or replace function "better_supabase"."deliver_fulfillment"(fulfillment uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fulfillment record;
  v_order record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."order_id" as order_id, x."status" as status into v_fulfillment
  from "better_supabase"."fulfillments" x where x."id" = deliver_fulfillment.fulfillment for update;
  if not found then
    raise exception 'fulfillment not found' using errcode = 'P0002', hint = 'ORDERS_FULFILLMENT_NOT_FOUND';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_fulfillment.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_fulfillment.status = 'delivered' then
    return false;
  end if;
  if v_fulfillment.status <> 'shipped' then
    raise exception 'only a shipped fulfillment can be delivered' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  update "better_supabase"."fulfillments" x set "status" = 'delivered', "delivered_at" = now() where x."id" = v_fulfillment.id;
  null;
  if v_order.status = 'fulfilled'
    and not exists (select 1 from "better_supabase"."fulfillments" x where x."order_id" = v_order.id and x."status" in ('pending', 'shipped')) then
    perform "better_supabase"."order_transition"(v_order.id, 'completed');
    null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."deliver_fulfillment"(uuid) from public, anon;
grant execute on function "better_supabase"."deliver_fulfillment"(uuid) to authenticated, service_role;

-- Cancels a fulfillment that hasn't shipped; its lines can be fulfilled again.
create or replace function "better_supabase"."cancel_fulfillment"(fulfillment uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fulfillment record;
  v_order record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."order_id" as order_id, x."status" as status into v_fulfillment
  from "better_supabase"."fulfillments" x where x."id" = cancel_fulfillment.fulfillment for update;
  if not found then
    raise exception 'fulfillment not found' using errcode = 'P0002', hint = 'ORDERS_FULFILLMENT_NOT_FOUND';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_fulfillment.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_fulfillment.status = 'cancelled' then
    return false;
  end if;
  if v_fulfillment.status <> 'pending' then
    raise exception 'a shipped fulfillment can''t be cancelled; request a return' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  update "better_supabase"."order_lines" x set "quantity_fulfilled" = x."quantity_fulfilled" - y."quantity"
  from "better_supabase"."fulfillment_lines" y
  where y."fulfillment_id" = v_fulfillment.id and x."id" = y."order_line_id";
  update "better_supabase"."fulfillments" x set "status" = 'cancelled' where x."id" = v_fulfillment.id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."cancel_fulfillment"(uuid) from public, anon;
grant execute on function "better_supabase"."cancel_fulfillment"(uuid) to authenticated, service_role;

-- Requests a return of fulfilled lines. lines is [{lineId, quantity}].
-- The customer who placed the order and staff with orders.manage can.
create or replace function "better_supabase"."request_return"(order_id uuid, lines jsonb, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_item record;
  v_id uuid;
  v_open integer;
  v_units integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = request_return.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or v_order.customer = auth.uid() or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to return this order' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_order.status not in ('paid', 'fulfilled', 'completed') then
    raise exception 'only a paid order can be returned' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  if request_return.lines is null or jsonb_typeof(request_return.lines) <> 'array' or jsonb_array_length(request_return.lines) = 0 then
    raise exception 'lines is a non-empty array of {lineId, quantity}' using errcode = '22023', hint = 'ORDERS_RETURN_INVALID';
  end if;
  insert into "better_supabase"."order_returns" ("tenant_id", "order_id", "reason")
  values (v_order.tenant, v_order.id, request_return.reason)
  returning "id" into v_id;
  for v_item in
    select (e ->> 'lineId')::uuid as line, (e ->> 'quantity')::integer as quantity from jsonb_array_elements(request_return.lines) e
  loop
    if v_item.quantity is null or v_item.quantity <= 0 then
      raise exception 'each quantity is a whole number above zero' using errcode = '22023', hint = 'ORDERS_QUANTITY_INVALID';
    end if;
    select coalesce(sum(y."quantity"), 0) into v_open
    from "better_supabase"."order_return_lines" y join "better_supabase"."order_returns" z on z."id" = y."return_id"
    where y."order_line_id" = v_item.line and z."status" = 'requested';
    if not exists (select 1 from "better_supabase"."order_lines" l where l."id" = v_item.line and l."order_id" = v_order.id
      and l."quantity_fulfilled" - l."quantity_returned" - v_open >= v_item.quantity) then
      raise exception 'a line isn''t on this order or has fewer fulfilled units left to return' using errcode = '22023', hint = 'ORDERS_RETURN_INVALID';
    end if;
    insert into "better_supabase"."order_return_lines" as x ("tenant_id", "return_id", "order_line_id", "quantity")
    values (v_order.tenant, v_id, v_item.line, v_item.quantity)
    on conflict ("return_id", "order_line_id") do update set "quantity" = x."quantity" + excluded."quantity";
    v_units := v_units + v_item.quantity;
  end loop;
  null;
  return jsonb_build_object('id', v_id, 'orderId', v_order.id, 'status', 'requested', 'quantity', v_units);
end;
$$;
revoke execute on function "better_supabase"."request_return"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."request_return"(uuid, jsonb, text) to authenticated, service_role;

-- Receives a requested return. With restock, tracked units go back on hand
-- at location (or where the line was reserved). Refund it with create_refund.
create or replace function "better_supabase"."receive_return"(return_id uuid, restock boolean default true, location uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_return record;
  v_order record;
  v_line record;
  v_units integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."order_id" as order_id, x."status" as status into v_return
  from "better_supabase"."order_returns" x where x."id" = receive_return.return_id for update;
  if not found then
    raise exception 'return not found' using errcode = 'P0002', hint = 'ORDERS_RETURN_NOT_FOUND';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_return.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_return.status = 'received' then
    return false;
  end if;
  if v_return.status <> 'requested' then
    raise exception 'only a requested return can be received' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  for v_line in
    select y."order_line_id" as line, y."quantity" as quantity, l."variant_id" as variant, l."location_id" as location
    from "better_supabase"."order_return_lines" y join "better_supabase"."order_lines" l on l."id" = y."order_line_id"
    where y."return_id" = v_return.id
  loop
    update "better_supabase"."order_lines" x set "quantity_returned" = x."quantity_returned" + v_line.quantity where x."id" = v_line.line;
    v_units := v_units + v_line.quantity;
  end loop;
  update "better_supabase"."order_returns" x set "status" = 'received', "received_at" = now() where x."id" = v_return.id;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."receive_return"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."receive_return"(uuid, boolean, uuid) to authenticated, service_role;

create or replace function "better_supabase"."reject_return"(return_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_return record;
  v_order record;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."order_id" as order_id, x."status" as status into v_return
  from "better_supabase"."order_returns" x where x."id" = reject_return.return_id for update;
  if not found then
    raise exception 'return not found' using errcode = 'P0002', hint = 'ORDERS_RETURN_NOT_FOUND';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_return.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if v_return.status <> 'requested' then
    raise exception 'only a requested return can be rejected' using errcode = '55000', hint = 'ORDERS_TRANSITION_INVALID';
  end if;
  update "better_supabase"."order_returns" x set "status" = 'rejected' where x."id" = v_return.id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."reject_return"(uuid) from public, anon;
grant execute on function "better_supabase"."reject_return"(uuid) to authenticated, service_role;

-- Starts a refund against the order's captured payment: amount null
-- refunds what is left. The TypeScript block sends it to the payment
-- provider and finishes it with complete_refund.
create or replace function "better_supabase"."create_refund"(order_id uuid, amount bigint default null, return_id uuid default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order record;
  v_pending bigint;
  v_left bigint;
  v_amount bigint;
  v_payment record;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = create_refund.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_order.tenant, 'orders.manage'), false)) then
    raise exception 'not allowed to manage these orders' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_refund_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_order.id;
    end if;
  end;
  if create_refund.return_id is not null and not exists (
    select 1 from "better_supabase"."order_returns" x where x."id" = create_refund.return_id and x."order_id" = v_order.id) then
    raise exception 'return not found on this order' using errcode = 'P0002', hint = 'ORDERS_RETURN_NOT_FOUND';
  end if;
  select coalesce(sum(x."amount"), 0) into v_pending from "better_supabase"."order_refunds" x
  where x."order_id" = v_order.id and x."status" = 'pending';
  v_left := v_order.paid_total - v_order.refunded_total - v_pending;
  v_amount := coalesce(create_refund.amount, v_left);
  if v_amount <= 0 or v_amount > v_left then
    raise exception 'the amount is above zero and at most what was paid and not refunded yet' using errcode = '22023', hint = 'ORDERS_REFUND_INVALID';
  end if;
  select y."id" as id, y."provider" as provider, y."reference" as reference into v_payment
  from "better_supabase"."order_payments" y
  where y."order_id" = v_order.id and y."status" = 'succeeded'
    and y."captured" - y."refunded" - coalesce((select sum(z."amount") from "better_supabase"."order_refunds" z
      where z."payment_id" = y."id" and z."status" = 'pending'), 0) >= v_amount
  order by y."created_at" desc
  limit 1;
  if not found then
    raise exception 'no single captured payment covers this amount; refund in parts' using errcode = '22023', hint = 'ORDERS_REFUND_INVALID';
  end if;
  insert into "better_supabase"."order_refunds" ("tenant_id", "order_id", "payment_id", "return_id", "amount", "currency", "reason")
  values (v_order.tenant, v_order.id, v_payment.id, create_refund.return_id, v_amount, v_order.currency, create_refund.reason)
  returning "id" into v_id;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_refund_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_id;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'orderId', v_order.id, 'paymentId', v_payment.id, 'provider', v_payment.provider,
    'paymentReference', v_payment.reference, 'amount', v_amount::text, 'currency', v_order.currency, 'status', 'pending');
end;
$$;
revoke execute on function "better_supabase"."create_refund"(uuid, bigint, uuid, text) from public, anon;
grant execute on function "better_supabase"."create_refund"(uuid, bigint, uuid, text) to authenticated, service_role;

-- Records the payment provider's answer to a refund, found by its id or,
-- from a webhook, by the provider's refund id. pending only stores that
-- id. A succeeded refund adds to the order's refunded total and records
-- order.refunded; once everything paid is refunded, the order is
-- refunded. Repeating it changes nothing.
create or replace function "better_supabase"."complete_refund"(refund uuid, status text, provider_reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refund record;
  v_order record;
  v_total bigint;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'only the service role can do this' using errcode = '42501', hint = 'ORDERS_FORBIDDEN';
  end if;
  if complete_refund.status is null or complete_refund.status not in ('pending', 'succeeded', 'failed') then
    raise exception 'status is pending, succeeded or failed' using errcode = '22023', hint = 'ORDERS_REFUND_STATUS_INVALID';
  end if;
  select x."id" as id, x."order_id" as order_id, x."payment_id" as payment, x."amount" as amount,
    x."status" as status
  into v_refund from "better_supabase"."order_refunds" x
  where (complete_refund.refund is not null and x."id" = complete_refund.refund)
    or (complete_refund.refund is null and x."provider_reference" = complete_refund.provider_reference)
  for update;
  if not found then
    raise exception 'refund not found' using errcode = 'P0002', hint = 'ORDERS_REFUND_NOT_FOUND';
  end if;
  select x."id" as id, x."tenant_id" as tenant, x."number" as number, x."customer_id" as customer, x."status" as status, x."currency" as currency, x."total" as total, x."paid_total" as paid_total, x."refunded_total" as refunded_total, x."tax_total" as tax_total, x."tax_inclusive" as tax_inclusive, x."invoice_number" as invoice_number, x."placed_at" as placed_at into v_order from "better_supabase"."orders" x where x."id" = v_refund.order_id for update;
  if not found then
    raise exception 'order not found' using errcode = 'P0002', hint = 'ORDERS_ORDER_NOT_FOUND';
  end if;
  if v_refund.status = 'pending' and complete_refund.status = 'pending' then
    update "better_supabase"."order_refunds" x set "provider_reference" = coalesce(complete_refund.provider_reference, x."provider_reference")
    where x."id" = v_refund.id;
  elsif v_refund.status = 'pending' then
    update "better_supabase"."order_refunds" x set "status" = complete_refund.status, "completed_at" = now(),
      "provider_reference" = coalesce(complete_refund.provider_reference, x."provider_reference")
    where x."id" = v_refund.id;
    if complete_refund.status = 'succeeded' then
      update "better_supabase"."order_payments" x set "refunded" = x."refunded" + v_refund.amount, "updated_at" = now()
      where x."id" = v_refund.payment;
      update "better_supabase"."orders" x set "refunded_total" = x."refunded_total" + v_refund.amount, "updated_at" = now()
      where x."id" = v_order.id
      returning x."refunded_total" into v_total;
      if v_total >= v_order.paid_total and v_order.status in ('paid', 'fulfilled', 'completed') then
        perform "better_supabase"."order_transition"(v_order.id, 'refunded');
      end if;
      null;
    end if;
  end if;
  return (select jsonb_build_object('id', x."id", 'orderId', x."order_id", 'status', x."status",
      'amount', x."amount"::text, 'orderStatus', y."status", 'refundedTotal', y."refunded_total"::text)
    from "better_supabase"."order_refunds" x join "better_supabase"."orders" y on y."id" = x."order_id" where x."id" = v_refund.id);
end;
$$;
revoke execute on function "better_supabase"."complete_refund"(uuid, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."complete_refund"(uuid, text, text) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."carts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."carts";
create policy bsb_tenant_scope_select on "better_supabase"."carts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('orders.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."carts";
create policy bsb_tenant_scope_insert on "better_supabase"."carts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."carts";
create policy bsb_tenant_scope_update on "better_supabase"."carts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."carts";
create policy bsb_tenant_scope_delete on "better_supabase"."carts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."cart_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."cart_lines";
create policy bsb_tenant_scope_select on "better_supabase"."cart_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."carts" x where x."id" = "cart_id" and x."user_id" = (select auth.uid())))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."cart_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."cart_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."cart_lines";
create policy bsb_tenant_scope_update on "better_supabase"."cart_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."cart_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."cart_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."shipping_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."shipping_rates";
create policy bsb_tenant_scope_select on "better_supabase"."shipping_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."shipping_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."shipping_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."shipping_rates";
create policy bsb_tenant_scope_update on "better_supabase"."shipping_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."shipping_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."shipping_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."orders";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."orders";
create policy bsb_tenant_scope_select on "better_supabase"."orders" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("customer_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('orders.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."orders";
create policy bsb_tenant_scope_insert on "better_supabase"."orders" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."orders";
create policy bsb_tenant_scope_update on "better_supabase"."orders" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."orders";
create policy bsb_tenant_scope_delete on "better_supabase"."orders" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."order_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_lines";
create policy bsb_tenant_scope_select on "better_supabase"."order_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."order_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_lines";
create policy bsb_tenant_scope_update on "better_supabase"."order_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."order_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."order_payments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_payments";
create policy bsb_tenant_scope_select on "better_supabase"."order_payments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_payments";
create policy bsb_tenant_scope_insert on "better_supabase"."order_payments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_payments";
create policy bsb_tenant_scope_update on "better_supabase"."order_payments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_payments";
create policy bsb_tenant_scope_delete on "better_supabase"."order_payments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."fulfillments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."fulfillments";
create policy bsb_tenant_scope_select on "better_supabase"."fulfillments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."fulfillments";
create policy bsb_tenant_scope_insert on "better_supabase"."fulfillments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."fulfillments";
create policy bsb_tenant_scope_update on "better_supabase"."fulfillments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."fulfillments";
create policy bsb_tenant_scope_delete on "better_supabase"."fulfillments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."fulfillment_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."fulfillment_lines";
create policy bsb_tenant_scope_select on "better_supabase"."fulfillment_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."fulfillment_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."fulfillment_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."fulfillment_lines";
create policy bsb_tenant_scope_update on "better_supabase"."fulfillment_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."fulfillment_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."fulfillment_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."order_returns";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_returns";
create policy bsb_tenant_scope_select on "better_supabase"."order_returns" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_returns";
create policy bsb_tenant_scope_insert on "better_supabase"."order_returns" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_returns";
create policy bsb_tenant_scope_update on "better_supabase"."order_returns" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_returns";
create policy bsb_tenant_scope_delete on "better_supabase"."order_returns" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."order_return_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_return_lines";
create policy bsb_tenant_scope_select on "better_supabase"."order_return_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_return_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."order_return_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_return_lines";
create policy bsb_tenant_scope_update on "better_supabase"."order_return_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_return_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."order_return_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."order_refunds";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."order_refunds";
create policy bsb_tenant_scope_select on "better_supabase"."order_refunds" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('orders.read')) or exists (select 1 from "better_supabase"."orders" o where o."id" = "order_id" and o."customer_id" = (select auth.uid())))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."order_refunds";
create policy bsb_tenant_scope_insert on "better_supabase"."order_refunds" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."order_refunds";
create policy bsb_tenant_scope_update on "better_supabase"."order_refunds" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."order_refunds";
create policy bsb_tenant_scope_delete on "better_supabase"."order_refunds" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_084_orders.sql
-- better-supabase module: orders
-- @bsb-block-data orders
-- @bsb-hash sha256:c9bc11c486e155d2bff54416c110f7ac493ce50a3e165d01e31dbe6e357e8814
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('orders', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
