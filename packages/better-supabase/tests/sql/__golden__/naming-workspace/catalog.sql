-- ==== schema supabase/schemas/900_better_supabase_069_catalog.sql
-- better-supabase module: catalog
-- @bsb-block catalog@3 managed
-- @bsb-hash sha256:4dc052185e035ccef768d0090a310d0650ccb5af3c4942f0f000af62b8cf5eb9
-- Products with options, variants and prices in minor units, price lists, a category tree, collections, sales channels, translations per locale, product media and an optional public storefront.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."products";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."products";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."products";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."products";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."product_options";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_options";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_options";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_options";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_options";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."product_option_values";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_option_values";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_option_values";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_option_values";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_option_values";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."product_variants";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_variants";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_variants";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_variants";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_variants";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."product_variant_values";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_variant_values";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_variant_values";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_variant_values";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_variant_values";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."price_lists";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."price_lists";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."price_lists";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."price_lists";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."price_lists";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."product_prices";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_prices";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_prices";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_prices";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_prices";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."categories";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."categories";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."categories";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."categories";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."categories";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."product_categories";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_categories";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_categories";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_categories";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_categories";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."product_collections";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_collections";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_collections";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_collections";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_collections";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."collection_products";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."collection_products";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."collection_products";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."collection_products";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."collection_products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."storefronts";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."storefronts";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."storefronts";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."storefronts";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."storefronts";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."catalog_channels";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."catalog_channels";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."catalog_channels";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."catalog_channels";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."catalog_channels";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."catalog_channel_products";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."catalog_channel_products";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."catalog_channel_products";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."catalog_channel_products";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."catalog_channel_products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."product_translations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_translations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_translations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_translations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_translations";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."product_variant_translations";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_variant_translations";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_variant_translations";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_variant_translations";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_variant_translations";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Products with options, variants and prices in minor units, plus
-- categories, collections, price lists, sales channels, translations,
-- product media and an optional public storefront.
create or replace function "better_supabase"."currency_minor_units"(code text)
returns integer
language sql
immutable
parallel safe
set search_path = ''
as $$
  select c.units from (values ('AED', 2), ('AFN', 2), ('ALL', 2), ('AMD', 2), ('AOA', 2), ('ARS', 2), ('AUD', 2), ('AWG', 2), ('AZN', 2), ('BAM', 2), ('BBD', 2), ('BDT', 2), ('BHD', 3), ('BIF', 0), ('BMD', 2), ('BND', 2), ('BOB', 2), ('BOV', 2), ('BRL', 2), ('BSD', 2), ('BTN', 2), ('BWP', 2), ('BYN', 2), ('BZD', 2), ('CAD', 2), ('CDF', 2), ('CHE', 2), ('CHF', 2), ('CHW', 2), ('CLF', 4), ('CLP', 0), ('CNY', 2), ('COP', 2), ('COU', 2), ('CRC', 2), ('CUP', 2), ('CVE', 2), ('CZK', 2), ('DJF', 0), ('DKK', 2), ('DOP', 2), ('DZD', 2), ('EGP', 2), ('ERN', 2), ('ETB', 2), ('EUR', 2), ('FJD', 2), ('FKP', 2), ('GBP', 2), ('GEL', 2), ('GHS', 2), ('GIP', 2), ('GMD', 2), ('GNF', 0), ('GTQ', 2), ('GYD', 2), ('HKD', 2), ('HNL', 2), ('HTG', 2), ('HUF', 2), ('IDR', 2), ('ILS', 2), ('INR', 2), ('IQD', 3), ('IRR', 2), ('ISK', 0), ('JMD', 2), ('JOD', 3), ('JPY', 0), ('KES', 2), ('KGS', 2), ('KHR', 2), ('KMF', 0), ('KPW', 2), ('KRW', 0), ('KWD', 3), ('KYD', 2), ('KZT', 2), ('LAK', 2), ('LBP', 2), ('LKR', 2), ('LRD', 2), ('LSL', 2), ('LYD', 3), ('MAD', 2), ('MDL', 2), ('MGA', 2), ('MKD', 2), ('MMK', 2), ('MNT', 2), ('MOP', 2), ('MRU', 2), ('MUR', 2), ('MVR', 2), ('MWK', 2), ('MXN', 2), ('MXV', 2), ('MYR', 2), ('MZN', 2), ('NAD', 2), ('NGN', 2), ('NIO', 2), ('NOK', 2), ('NPR', 2), ('NZD', 2), ('OMR', 3), ('PAB', 2), ('PEN', 2), ('PGK', 2), ('PHP', 2), ('PKR', 2), ('PLN', 2), ('PYG', 0), ('QAR', 2), ('RON', 2), ('RSD', 2), ('RUB', 2), ('RWF', 0), ('SAR', 2), ('SBD', 2), ('SCR', 2), ('SDG', 2), ('SEK', 2), ('SGD', 2), ('SHP', 2), ('SLE', 2), ('SOS', 2), ('SRD', 2), ('SSP', 2), ('STN', 2), ('SVC', 2), ('SYP', 2), ('SZL', 2), ('THB', 2), ('TJS', 2), ('TMT', 2), ('TND', 3), ('TOP', 2), ('TRY', 2), ('TTD', 2), ('TWD', 2), ('TZS', 2), ('UAH', 2), ('UGX', 0), ('USD', 2), ('USN', 2), ('UYI', 0), ('UYU', 2), ('UYW', 4), ('UZS', 2), ('VED', 2), ('VES', 2), ('VND', 0), ('VUV', 0), ('WST', 2), ('XAD', 2), ('XAF', 0), ('XCD', 2), ('XCG', 2), ('XOF', 0), ('XPF', 0), ('YER', 2), ('ZAR', 2), ('ZMW', 2), ('ZWG', 2)) as c (code, units) where c.code = $1
$$;
grant execute on function "better_supabase"."currency_minor_units"(text) to anon, authenticated, service_role;

create table if not exists "better_supabase"."products" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "slug" text not null check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "title" text not null check (length("title") between 1 and 500),
  "description" text,
  "kind" text not null default 'physical' check ("kind" in ('physical', 'digital', 'service')),
  "status" text not null default 'draft',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "slug")
);
create index if not exists products_status_idx on "better_supabase"."products" ("tenant_id", "status");
alter table "better_supabase"."products" enable row level security;
revoke all on "better_supabase"."products" from public, anon, authenticated;
grant select on "better_supabase"."products" to authenticated;
grant all on "better_supabase"."products" to service_role;
drop policy if exists products_read on "better_supabase"."products";
create policy products_read on "better_supabase"."products"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."product_options" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "product_id" uuid not null references "better_supabase"."products" ("id") on delete cascade,
  "name" text not null check (length("name") between 1 and 80),
  "rank" text collate "C" not null default 'V',
  unique ("product_id", "name")
);
alter table "better_supabase"."product_options" enable row level security;
revoke all on "better_supabase"."product_options" from public, anon, authenticated;
grant select on "better_supabase"."product_options" to authenticated;
grant all on "better_supabase"."product_options" to service_role;
drop policy if exists product_options_read on "better_supabase"."product_options";
create policy product_options_read on "better_supabase"."product_options"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."product_option_values" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "option_id" uuid not null references "better_supabase"."product_options" ("id") on delete cascade,
  "value" text not null check (length("value") between 1 and 80),
  "rank" text collate "C" not null default 'V',
  unique ("option_id", "value")
);
alter table "better_supabase"."product_option_values" enable row level security;
revoke all on "better_supabase"."product_option_values" from public, anon, authenticated;
grant select on "better_supabase"."product_option_values" to authenticated;
grant all on "better_supabase"."product_option_values" to service_role;
drop policy if exists product_option_values_read on "better_supabase"."product_option_values";
create policy product_option_values_read on "better_supabase"."product_option_values"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."product_variants" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "product_id" uuid not null references "better_supabase"."products" ("id") on delete cascade,
  "sku" text not null check (length("sku") between 1 and 100),
  "title" text,
  "barcode" text,
  "weight_grams" integer check ("weight_grams" >= 0),
  "track_inventory" boolean not null default true,
  "allow_backorder" boolean not null default false,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "sku")
);
create index if not exists product_variants_product_idx on "better_supabase"."product_variants" ("product_id");
alter table "better_supabase"."product_variants" enable row level security;
revoke all on "better_supabase"."product_variants" from public, anon, authenticated;
grant select on "better_supabase"."product_variants" to authenticated;
grant all on "better_supabase"."product_variants" to service_role;
drop policy if exists product_variants_read on "better_supabase"."product_variants";
create policy product_variants_read on "better_supabase"."product_variants"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."product_variant_values" (
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "option_value_id" uuid not null references "better_supabase"."product_option_values" ("id"),
  primary key ("variant_id", "option_value_id")
);
create index if not exists product_variant_values_value_idx on "better_supabase"."product_variant_values" ("option_value_id");
alter table "better_supabase"."product_variant_values" enable row level security;
revoke all on "better_supabase"."product_variant_values" from public, anon, authenticated;
grant select on "better_supabase"."product_variant_values" to authenticated;
grant all on "better_supabase"."product_variant_values" to service_role;
drop policy if exists product_variant_values_read on "better_supabase"."product_variant_values";
create policy product_variant_values_read on "better_supabase"."product_variant_values"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."price_lists" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 200),
  "customer_group" text,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "name")
);
alter table "better_supabase"."price_lists" enable row level security;
revoke all on "better_supabase"."price_lists" from public, anon, authenticated;
grant select on "better_supabase"."price_lists" to authenticated;
grant all on "better_supabase"."price_lists" to service_role;
drop policy if exists price_lists_read on "better_supabase"."price_lists";
create policy price_lists_read on "better_supabase"."price_lists"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."product_prices" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "price_list_id" uuid references "better_supabase"."price_lists" ("id") on delete cascade,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "amount" bigint not null check ("amount" >= 0),
  "compare_at_amount" bigint check ("compare_at_amount" > "amount"),
  "valid_from" timestamptz,
  "valid_until" timestamptz check ("valid_until" > "valid_from"),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists product_prices_variant_idx on "better_supabase"."product_prices" ("variant_id", "currency");
create index if not exists product_prices_price_list_idx on "better_supabase"."product_prices" ("price_list_id");
alter table "better_supabase"."product_prices" enable row level security;
revoke all on "better_supabase"."product_prices" from public, anon, authenticated;
grant select on "better_supabase"."product_prices" to authenticated;
grant all on "better_supabase"."product_prices" to service_role;
drop policy if exists product_prices_read on "better_supabase"."product_prices";
create policy product_prices_read on "better_supabase"."product_prices"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."categories" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid references "better_supabase"."categories" ("id"),
  "name" text not null check (length("name") between 1 and 200),
  "slug" text not null check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "description" text,
  "rank" text collate "C" not null default 'V',
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "slug")
);
create index if not exists categories_parent_idx on "better_supabase"."categories" ("parent_id");
alter table "better_supabase"."categories" enable row level security;
revoke all on "better_supabase"."categories" from public, anon, authenticated;
grant select on "better_supabase"."categories" to authenticated;
grant all on "better_supabase"."categories" to service_role;
drop policy if exists categories_read on "better_supabase"."categories";
create policy categories_read on "better_supabase"."categories"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."product_categories" (
  "tenant_id" uuid not null,
  "product_id" uuid not null references "better_supabase"."products" ("id") on delete cascade,
  "category_id" uuid not null references "better_supabase"."categories" ("id") on delete cascade,
  primary key ("product_id", "category_id")
);
create index if not exists product_categories_category_idx on "better_supabase"."product_categories" ("category_id");
alter table "better_supabase"."product_categories" enable row level security;
revoke all on "better_supabase"."product_categories" from public, anon, authenticated;
grant select on "better_supabase"."product_categories" to authenticated;
grant all on "better_supabase"."product_categories" to service_role;
drop policy if exists product_categories_read on "better_supabase"."product_categories";
create policy product_categories_read on "better_supabase"."product_categories"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."product_collections" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "title" text not null check (length("title") between 1 and 200),
  "slug" text not null check ("slug" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "kind" text not null default 'manual' check ("kind" in ('manual', 'rule')),
  "rule" jsonb,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "slug"),
  check (("kind" = 'rule') = ("rule" is not null))
);
alter table "better_supabase"."product_collections" enable row level security;
revoke all on "better_supabase"."product_collections" from public, anon, authenticated;
grant select on "better_supabase"."product_collections" to authenticated;
grant all on "better_supabase"."product_collections" to service_role;
drop policy if exists product_collections_read on "better_supabase"."product_collections";
create policy product_collections_read on "better_supabase"."product_collections"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."collection_products" (
  "tenant_id" uuid not null,
  "collection_id" uuid not null references "better_supabase"."product_collections" ("id") on delete cascade,
  "product_id" uuid not null references "better_supabase"."products" ("id") on delete cascade,
  "rank" text collate "C" not null default 'V',
  primary key ("collection_id", "product_id")
);
create index if not exists collection_products_product_idx on "better_supabase"."collection_products" ("product_id");
alter table "better_supabase"."collection_products" enable row level security;
revoke all on "better_supabase"."collection_products" from public, anon, authenticated;
grant select on "better_supabase"."collection_products" to authenticated;
grant all on "better_supabase"."collection_products" to service_role;
drop policy if exists collection_products_read on "better_supabase"."collection_products";
create policy collection_products_read on "better_supabase"."collection_products"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."storefronts" (
  "tenant_id" uuid primary key,
  "published_at" timestamptz
);
alter table "better_supabase"."storefronts" enable row level security;
revoke all on "better_supabase"."storefronts" from public, anon, authenticated;
grant select on "better_supabase"."storefronts" to authenticated;
grant all on "better_supabase"."storefronts" to service_role;
drop policy if exists storefronts_read on "better_supabase"."storefronts";
create policy storefronts_read on "better_supabase"."storefronts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."catalog_channels" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "key" text not null check ("key" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  "name" text not null check (length("name") between 1 and 200),
  "currency" char(3) check ("currency" ~ '^[A-Z]{3}$'),
  "price_list_id" uuid references "better_supabase"."price_lists" ("id") on delete set null,
  "active" boolean not null default true,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "key")
);
create index if not exists catalog_channels_price_list_idx on "better_supabase"."catalog_channels" ("price_list_id");
alter table "better_supabase"."catalog_channels" enable row level security;
revoke all on "better_supabase"."catalog_channels" from public, anon, authenticated;
grant select on "better_supabase"."catalog_channels" to authenticated;
grant all on "better_supabase"."catalog_channels" to service_role;
drop policy if exists catalog_channels_read on "better_supabase"."catalog_channels";
create policy catalog_channels_read on "better_supabase"."catalog_channels"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."catalog_channel_products" (
  "tenant_id" uuid not null,
  "channel_id" uuid not null references "better_supabase"."catalog_channels" ("id") on delete cascade,
  "product_id" uuid not null references "better_supabase"."products" ("id") on delete cascade,
  "listed_at" timestamptz not null default now(),
  primary key ("channel_id", "product_id")
);
create index if not exists catalog_channel_products_product_idx on "better_supabase"."catalog_channel_products" ("product_id");
alter table "better_supabase"."catalog_channel_products" enable row level security;
revoke all on "better_supabase"."catalog_channel_products" from public, anon, authenticated;
grant select on "better_supabase"."catalog_channel_products" to authenticated;
grant all on "better_supabase"."catalog_channel_products" to service_role;
drop policy if exists catalog_channel_products_read on "better_supabase"."catalog_channel_products";
create policy catalog_channel_products_read on "better_supabase"."catalog_channel_products"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."product_translations" (
  "tenant_id" uuid not null,
  "product_id" uuid not null references "better_supabase"."products" ("id") on delete cascade,
  "locale" text not null check ("locale" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  "title" text check (length("title") between 1 and 500),
  "description" text,
  "updated_at" timestamptz not null default now(),
  primary key ("product_id", "locale")
);
alter table "better_supabase"."product_translations" enable row level security;
revoke all on "better_supabase"."product_translations" from public, anon, authenticated;
grant select on "better_supabase"."product_translations" to authenticated;
grant all on "better_supabase"."product_translations" to service_role;
drop policy if exists product_translations_read on "better_supabase"."product_translations";
create policy product_translations_read on "better_supabase"."product_translations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

create table if not exists "better_supabase"."product_variant_translations" (
  "tenant_id" uuid not null,
  "variant_id" uuid not null references "better_supabase"."product_variants" ("id") on delete cascade,
  "locale" text not null check ("locale" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  "title" text check (length("title") between 1 and 500),
  "updated_at" timestamptz not null default now(),
  primary key ("variant_id", "locale")
);
alter table "better_supabase"."product_variant_translations" enable row level security;
revoke all on "better_supabase"."product_variant_translations" from public, anon, authenticated;
grant select on "better_supabase"."product_variant_translations" to authenticated;
grant all on "better_supabase"."product_variant_translations" to service_role;
drop policy if exists product_variant_translations_read on "better_supabase"."product_variant_translations";
create policy product_variant_translations_read on "better_supabase"."product_variant_translations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')));

-- Creates a product (product null) or updates one. Returns its id, slug and
-- status. On an update a null argument keeps the column and clear names the
-- columns to empty; a cleared slug is derived from the title again.
drop function if exists "better_supabase"."save_product"(uuid, uuid, text, text, text, text);
drop function if exists "better_supabase"."save_product"(uuid, uuid, text, text, text, text, jsonb);
drop function if exists "better_supabase"."save_product"(uuid, uuid, text, text, text, text);
drop function if exists "better_supabase"."save_product"(uuid, uuid, text, text, text, text, jsonb);
drop function if exists "better_supabase"."save_product"(uuid, uuid, text, text, text, text, text[], jsonb);
create or replace function "better_supabase"."save_product"(tenant uuid, product uuid, title text, slug text, description text, kind text, clear text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_product.product;
  v_title text := save_product.title;
  v_slug text := nullif(save_product.slug, '');
  v_status text;
  v_created boolean := save_product.product is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if v_created then
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_product.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  else
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_product.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  end if;
  if exists (select 1 from unnest(coalesce(save_product.clear, '{}'::text[])) c where c <> all ('{slug,description}'::text[])) then
    raise exception 'clear names only slug, description' using errcode = '22023', hint = 'CATALOG_CLEAR_INVALID';
  end if;
  if not v_created then
    select coalesce(v_title, x."title"), case when v_slug is null and not 'slug' = any (coalesce(save_product.clear, '{}'::text[])) then x."slug" else v_slug end
    into v_title, v_slug
    from "better_supabase"."products" x where x."id" = save_product.product and x."tenant_id" = save_product.tenant;
    if not found then
      raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
    end if;
  end if;
  v_slug := coalesce(v_slug, trim(both '-' from regexp_replace(lower(v_title), '[^a-z0-9]+', '-', 'g')));
  if v_slug is null or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'the slug must be lower-case letters, digits and hyphens' using errcode = '22023', hint = 'CATALOG_SLUG_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_product_save"(uuid, uuid, text, text, text)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::text, $5::text)', v_hook::oid::regproc)
        using save_product.tenant, save_product.product, v_title, v_slug, save_product.kind;
    end if;
  end;
  begin
    if v_created then
      insert into "better_supabase"."products" ("tenant_id", "title", "slug", "description", "kind")
      values (save_product.tenant, v_title, v_slug, save_product.description, coalesce(save_product.kind, 'physical'))
      returning "id", "status" into v_id, v_status;
    else
      update "better_supabase"."products" x set "title" = v_title, "slug" = v_slug, "description" = case when 'description' = any (coalesce(save_product.clear, '{}'::text[])) then null else coalesce(save_product.description, x."description") end, "kind" = coalesce(save_product.kind, x."kind"), "updated_at" = now()
      where x."id" = save_product.product and x."tenant_id" = save_product.tenant
      returning x."status" into v_status;
      if not found then
        raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another product has this slug' using errcode = '23505', hint = 'CATALOG_SLUG_TAKEN';
  end;
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_product_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'status', v_status);
end;
$$;
revoke execute on function "better_supabase"."save_product"(uuid, uuid, text, text, text, text, text[]) from public, anon;
grant execute on function "better_supabase"."save_product"(uuid, uuid, text, text, text, text, text[]) to authenticated, service_role;

-- Moves a product to another status: draft, active or archived.
create or replace function "better_supabase"."set_product_status"(product uuid, status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_from text;
  v_from_raw text;
  v_to text := set_product_status.status;
  v_to_raw text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."status", x."status"::text into v_tenant, v_from, v_from_raw from "better_supabase"."products" x where x."id" = set_product_status.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_to is null or v_to not in ('draft', 'active', 'archived') then
    raise exception 'the status must be draft, active or archived' using errcode = '22023', hint = 'CATALOG_STATUS_INVALID';
  end if;
  v_to_raw := (set_product_status.status)::text;
  if v_from_raw = v_to_raw then
    return jsonb_build_object('id', set_product_status.product, 'status', v_from, 'from', v_from);
  end if;
  if v_from <> v_to and not (case v_from
    when 'draft' then v_to = any ('{active,archived}'::text[])
    when 'active' then v_to = any ('{draft,archived}'::text[])
    when 'archived' then v_to = any ('{draft}'::text[])
    else false
  end) then
    raise exception 'the product can''t move to this status' using errcode = '22023', hint = 'CATALOG_TRANSITION_INVALID';
  end if;
  update "better_supabase"."products" x set "status" = set_product_status.status, "updated_at" = now()
  where x."id" = set_product_status.product;
  null;
  return jsonb_build_object('id', set_product_status.product, 'status', v_to, 'from', v_from);
end;
$$;
revoke execute on function "better_supabase"."set_product_status"(uuid, text) from public, anon;
grant execute on function "better_supabase"."set_product_status"(uuid, text) to authenticated, service_role;

-- Deletes a product with its options, variants and prices.
create or replace function "better_supabase"."delete_product"(product uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = delete_product.product;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."products" x where x."id" = delete_product.product;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_product"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_product"(uuid) to authenticated, service_role;

-- Creates a variant (variant null) or updates one. option_values holds one
-- option value id per product option; no two variants share a combination.
-- On an update a null argument keeps the column and clear names the columns
-- to empty. fields: the extra columns (options.variantExtraColumns) to set.
drop function if exists "better_supabase"."save_variant"(uuid, uuid, text, uuid[], text, text, integer, boolean, boolean);
drop function if exists "better_supabase"."save_variant"(uuid, uuid, text, uuid[], text, text, integer, boolean, boolean, jsonb);
drop function if exists "better_supabase"."save_variant"(uuid, uuid, text, uuid[], text, text, integer, boolean, boolean, text[], jsonb);
create or replace function "better_supabase"."save_variant"(product uuid, variant uuid, sku text, option_values uuid[], title text, barcode text, weight_grams integer, track_inventory boolean, allow_backorder boolean, clear text[] default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid := save_variant.variant;
  v_created boolean := save_variant.variant is null;
  v_wanted uuid[];
  v_last text;
  v_rank text;
  v_sku text := save_variant.sku;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = save_variant.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if v_created then
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  else
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  end if;
  if exists (select 1 from unnest(coalesce(save_variant.clear, '{}'::text[])) c where c <> all ('{sku,title,barcode,weight}'::text[])) then
    raise exception 'clear names only sku, title, barcode, weight' using errcode = '22023', hint = 'CATALOG_CLEAR_INVALID';
  end if;
  if v_created or save_variant.option_values is not null then
  v_wanted := coalesce((select array_agg(distinct x order by x) from unnest(save_variant.option_values) x), '{}'::uuid[]);
  if cardinality(v_wanted) <> coalesce(cardinality(save_variant.option_values), 0)
    or exists (
      select 1 from unnest(v_wanted) x
      where not exists (
        select 1 from "better_supabase"."product_option_values" ov join "better_supabase"."product_options" o on o."id" = ov."option_id"
        where ov."id" = x and o."product_id" = save_variant.product
      )
    )
    or (select count(distinct ov."option_id") from "better_supabase"."product_option_values" ov where ov."id" = any (v_wanted)) <> cardinality(v_wanted)
    or (select count(*) from "better_supabase"."product_options" o where o."product_id" = save_variant.product) <> cardinality(v_wanted) then
    raise exception 'a variant needs exactly one value of each product option' using errcode = '22023', hint = 'CATALOG_VARIANT_OPTIONS';
  end if;
  if exists (
    select 1 from "better_supabase"."product_variants" x
    where x."product_id" = save_variant.product
      and x."id" is distinct from save_variant.variant
      and coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]) = v_wanted
  ) then
    raise exception 'another variant has these option values' using errcode = '23505', hint = 'CATALOG_VARIANT_DUPLICATE';
  end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_variant_save"(uuid, uuid, text, uuid[])');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::text, $4::uuid[])', v_hook::oid::regproc)
        using save_variant.product, save_variant.variant, save_variant.sku, v_wanted;
    end if;
  end;
  begin
    if v_created then
      select max(x."rank" collate "C") into v_last from "better_supabase"."product_variants" x where x."product_id" = save_variant.product;
      v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
      insert into "better_supabase"."product_variants" ("tenant_id", "product_id", "sku", "title", "barcode", "weight_grams", "track_inventory", "allow_backorder", "rank")
      values (v_tenant, save_variant.product, save_variant.sku, save_variant.title, save_variant.barcode, save_variant.weight_grams, coalesce(save_variant.track_inventory, true), coalesce(save_variant.allow_backorder, false), v_rank)
      returning "id" into v_id;
    else
      update "better_supabase"."product_variants" x set "sku" = case when 'sku' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.sku, x."sku") end, "title" = case when 'title' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.title, x."title") end, "barcode" = case when 'barcode' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.barcode, x."barcode") end, "weight_grams" = case when 'weight' = any (coalesce(save_variant.clear, '{}'::text[])) then null else coalesce(save_variant.weight_grams, x."weight_grams") end, "track_inventory" = coalesce(save_variant.track_inventory, x."track_inventory"), "allow_backorder" = coalesce(save_variant.allow_backorder, x."allow_backorder"), "updated_at" = now()
      where x."id" = save_variant.variant and x."product_id" = save_variant.product
      returning x."rank", x."sku" into v_rank, v_sku;
      if not found then
        raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another variant has this SKU' using errcode = '23505', hint = 'CATALOG_SKU_TAKEN';
  end;
  if v_wanted is not null then
  delete from "better_supabase"."product_variant_values" x where x."variant_id" = v_id and not (x."option_value_id" = any (v_wanted));
  insert into "better_supabase"."product_variant_values" ("tenant_id", "variant_id", "option_value_id")
  select v_tenant, v_id, x from unnest(v_wanted) x
  on conflict do nothing;
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_variant_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'sku', v_sku, 'rank', v_rank);
end;
$$;
revoke execute on function "better_supabase"."save_variant"(uuid, uuid, text, uuid[], text, text, integer, boolean, boolean, text[]) from public, anon;
grant execute on function "better_supabase"."save_variant"(uuid, uuid, text, uuid[], text, text, integer, boolean, boolean, text[]) to authenticated, service_role;

-- Sets a variant's rank key among the product's variants.
create or replace function "better_supabase"."rank_variant"(variant uuid, rank text)
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
  if rank_variant.rank is null or rank_variant.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'CATALOG_RANK_INVALID';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."product_variants" x where x."id" = rank_variant.variant;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  update "better_supabase"."product_variants" x set "rank" = rank_variant.rank, "updated_at" = now() where x."id" = rank_variant.variant;
  return true;
end;
$$;
revoke execute on function "better_supabase"."rank_variant"(uuid, text) from public, anon;
grant execute on function "better_supabase"."rank_variant"(uuid, text) to authenticated, service_role;

-- Deletes a variant with its prices.
create or replace function "better_supabase"."delete_variant"(variant uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_product uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."product_id" into v_tenant, v_product from "better_supabase"."product_variants" x where x."id" = delete_variant.variant;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."product_variants" x where x."id" = delete_variant.variant;
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_variant"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_variant"(uuid) to authenticated, service_role;

-- Creates an option (option null) or updates one, with its values in order.
-- Values missing from the list are removed with the variants that use them;
-- a variant something still references is archived instead.
create or replace function "better_supabase"."save_product_option"(product uuid, option uuid, name text, option_values text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid := save_product_option.option;
  v_last text;
  v_rank text;
  v_value text;
  v_variant uuid;
  v_new boolean := save_product_option.option is null;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = save_product_option.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if coalesce(cardinality(save_product_option.option_values), 0) = 0 then
    raise exception 'an option needs at least one value' using errcode = '22023', hint = 'CATALOG_OPTION_EMPTY';
  end if;
  if (select count(distinct x) from unnest(save_product_option.option_values) x) <> cardinality(save_product_option.option_values) then
    raise exception 'an option lists the same value twice' using errcode = '22023', hint = 'CATALOG_OPTION_DUPLICATE';
  end if;
  begin
    if v_id is null then
      select max(x."rank" collate "C") into v_last from "better_supabase"."product_options" x where x."product_id" = save_product_option.product;
      insert into "better_supabase"."product_options" ("tenant_id", "product_id", "name", "rank")
      values (v_tenant, save_product_option.product, save_product_option.name, case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end)
      returning "id" into v_id;
    else
      update "better_supabase"."product_options" x set "name" = save_product_option.name
      where x."id" = save_product_option.option and x."product_id" = save_product_option.product;
      if not found then
        raise exception 'option not found' using errcode = 'P0002', hint = 'CATALOG_OPTION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'the product has another option with this name' using errcode = '23505', hint = 'CATALOG_OPTION_TAKEN';
  end;
  for v_variant in
    select distinct x."variant_id" from "better_supabase"."product_variant_values" x
    join "better_supabase"."product_option_values" y on y."id" = x."option_value_id"
    where y."option_id" = v_id and not (y."value" = any (save_product_option.option_values))
  loop
    begin
      delete from "better_supabase"."product_variants" x where x."id" = v_variant;
      null;
    exception when foreign_key_violation then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
    end;
  end loop;
  begin
    delete from "better_supabase"."product_option_values" x where x."option_id" = v_id and not (x."value" = any (save_product_option.option_values));
  exception when foreign_key_violation then
    raise exception 'a variant uses a value this list removes' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
  end;
  v_rank := null;
  foreach v_value in array save_product_option.option_values loop
    v_rank := case
    when v_rank is null then 'V'
    when length(substring(v_rank from '^z*')) = length(v_rank) then v_rank || 'V'
    else left(v_rank, length(substring(v_rank from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_rank, length(substring(v_rank from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    update "better_supabase"."product_option_values" x set "rank" = v_rank where x."option_id" = v_id and x."value" = v_value;
    if not found then
      insert into "better_supabase"."product_option_values" ("tenant_id", "option_id", "value", "rank")
      values (v_tenant, v_id, v_value, v_rank);
    end if;
  end loop;
  if v_new then
    insert into "better_supabase"."product_variant_values" ("tenant_id", "variant_id", "option_value_id")
    select v_tenant, x."id", (select y."id" from "better_supabase"."product_option_values" y where y."option_id" = v_id and y."value" = save_product_option.option_values[1])
    from "better_supabase"."product_variants" x where x."product_id" = save_product_option.product;
  end if;
  return jsonb_build_object(
    'id', v_id,
    'values', (select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'value', x."value") order by x."rank" collate "C"), '[]'::jsonb) from "better_supabase"."product_option_values" x where x."option_id" = v_id)
  );
end;
$$;
revoke execute on function "better_supabase"."save_product_option"(uuid, uuid, text, text[]) from public, anon;
grant execute on function "better_supabase"."save_product_option"(uuid, uuid, text, text[]) to authenticated, service_role;

-- Puts a product's options in the given order; the list names each once.
create or replace function "better_supabase"."reorder_product_options"(product uuid, options uuid[])
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_rank text;
  v_option uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = reorder_product_options.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if coalesce(cardinality(reorder_product_options.options), 0) <> (select count(*) from "better_supabase"."product_options" x where x."product_id" = reorder_product_options.product)
    or (select count(distinct y) from unnest(reorder_product_options.options) y) <> cardinality(reorder_product_options.options)
    or exists (select 1 from unnest(reorder_product_options.options) y where not exists (select 1 from "better_supabase"."product_options" x where x."id" = y and x."product_id" = reorder_product_options.product)) then
    raise exception 'the list must name each option of the product once' using errcode = '22023', hint = 'CATALOG_OPTION_ORDER_INVALID';
  end if;
  foreach v_option in array reorder_product_options.options loop
    v_rank := case
    when v_rank is null then 'V'
    when length(substring(v_rank from '^z*')) = length(v_rank) then v_rank || 'V'
    else left(v_rank, length(substring(v_rank from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_rank, length(substring(v_rank from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
    update "better_supabase"."product_options" x set "rank" = v_rank where x."id" = v_option;
  end loop;
  return true;
end;
$$;
revoke execute on function "better_supabase"."reorder_product_options"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."reorder_product_options"(uuid, uuid[]) to authenticated, service_role;

-- Deletes an option and its values; refused while a variant uses one.
create or replace function "better_supabase"."delete_product_option"(option uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."product_options" x where x."id" = delete_product_option.option;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  begin
    delete from "better_supabase"."product_options" x where x."id" = delete_product_option.option;
  exception when foreign_key_violation then
    raise exception 'a variant uses a value of this option' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_product_option"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_product_option"(uuid) to authenticated, service_role;

-- Replaces a product's options by name and makes its variants the full matrix
-- of their values in one transaction.
create or replace function "better_supabase"."set_product_options"(product uuid, options jsonb, title_separator text default ' / ')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_slug text;
  v_item jsonb;
  v_option uuid;
  v_ids uuid[] := '{}';
  v_variant uuid;
  v_combo uuid[];
  v_label text;
  v_count numeric := 1;
  v_sku_required boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."slug" into v_tenant, v_slug from "better_supabase"."products" x where x."id" = set_product_options.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if jsonb_typeof(set_product_options.options) is distinct from 'array'
    or exists (
      select 1 from jsonb_array_elements(set_product_options.options) e
      where jsonb_typeof(e) is distinct from 'object'
        or jsonb_typeof(e -> 'name') is distinct from 'string'
        or jsonb_typeof(e -> 'values') is distinct from 'array'
        or exists (select 1 from jsonb_array_elements(e -> 'values') y where jsonb_typeof(y) <> 'string')
    ) then
    raise exception 'options is a list of { name, values } with text values' using errcode = '22023', hint = 'CATALOG_OPTIONS_INVALID';
  end if;
  if (select count(distinct e ->> 'name') from jsonb_array_elements(set_product_options.options) e) <> jsonb_array_length(set_product_options.options) then
    raise exception 'the list names an option twice' using errcode = '23505', hint = 'CATALOG_OPTION_TAKEN';
  end if;
  for v_item in select e from jsonb_array_elements(set_product_options.options) e loop
    v_count := v_count * jsonb_array_length(v_item -> 'values');
  end loop;
  if v_count > 100 then
    raise exception 'a product has at most 100 variants' using errcode = '22023', hint = 'CATALOG_VARIANT_LIMIT';
  end if;
  for v_option in
    select x."id" from "better_supabase"."product_options" x
    where x."product_id" = set_product_options.product
      and not (x."name" = any (array(select e ->> 'name' from jsonb_array_elements(set_product_options.options) e)))
  loop
    delete from "better_supabase"."product_variant_values" y using "better_supabase"."product_option_values" z where y."option_value_id" = z."id" and z."option_id" = v_option;
    delete from "better_supabase"."product_options" x where x."id" = v_option;
  end loop;
  for v_variant in
    select d.id from (
      select x."id" as id, row_number() over (partition by coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]) order by x."rank" collate "C", x."id") as n
      from "better_supabase"."product_variants" x where x."product_id" = set_product_options.product
    ) d where d.n > 1
  loop
    begin
      delete from "better_supabase"."product_variants" x where x."id" = v_variant;
      null;
    exception when foreign_key_violation then
      raise exception 'a variant this list removes is still in use' using errcode = '23503', hint = 'CATALOG_OPTION_VALUE_IN_USE';
    end;
  end loop;
  for v_item in select e from jsonb_array_elements(set_product_options.options) with ordinality as a(e, n) order by a.n loop
    select x."id" into v_option from "better_supabase"."product_options" x where x."product_id" = set_product_options.product and x."name" = v_item ->> 'name';
    v_option := ("better_supabase"."save_product_option"(set_product_options.product, v_option, v_item ->> 'name', array(select y from jsonb_array_elements_text(v_item -> 'values') with ordinality as b(y, n) order by b.n)) ->> 'id')::uuid;
    v_ids := v_ids || v_option;
  end loop;
  if cardinality(v_ids) > 0 then
    perform "better_supabase"."reorder_product_options"(set_product_options.product, v_ids);
  end if;
  select a.attnotnull into v_sku_required from pg_catalog.pg_attribute a
  where a.attrelid = '"better_supabase"."product_variants"'::regclass and a.attname = 'sku';
  for v_combo, v_label in
    with recursive k as (
      select x."id" as id, row_number() over (order by x."rank" collate "C") as n
      from "better_supabase"."product_options" x where x."product_id" = set_product_options.product
    ), z as (
      select y."id" as id, y."value" as value, y."option_id" as option, row_number() over (partition by y."option_id" order by y."rank" collate "C") as n
      from "better_supabase"."product_option_values" y where y."option_id" in (select k.id from k)
    ), c(depth, ids, labels, sort) as (
      select 0::bigint, '{}'::uuid[], '{}'::text[], '{}'::bigint[]
      union all
      select k.n, c.ids || z.id, c.labels || z.value, c.sort || z.n
      from c join k on k.n = c.depth + 1 join z on z.option = k.id
    )
    select c.ids, array_to_string(c.labels, '-') from c where c.depth = (select count(*) from k) order by c.sort
  loop
    if not exists (
      select 1 from "better_supabase"."product_variants" x
      where x."product_id" = set_product_options.product
        and coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]) = (select coalesce(array_agg(u order by u), '{}'::uuid[]) from unnest(v_combo) u)
    ) then
      perform "better_supabase"."save_variant"(set_product_options.product, null, case when v_sku_required then upper(trim(both '-' from regexp_replace(concat_ws('-', v_slug, nullif(v_label, '')), '[^A-Za-z0-9]+', '-', 'g'))) end, v_combo, null, null, null, null, null);
    end if;
  end loop;
  if set_product_options.title_separator is not null then
    update "better_supabase"."product_variants" x set "title" = t.title, "updated_at" = now()
    from (
      select y."variant_id" as variant, string_agg(z."value", set_product_options.title_separator order by k."rank" collate "C") as title
      from "better_supabase"."product_variant_values" y
      join "better_supabase"."product_option_values" z on z."id" = y."option_value_id"
      join "better_supabase"."product_options" k on k."id" = z."option_id"
      where k."product_id" = set_product_options.product
      group by y."variant_id"
    ) t
    where x."id" = t.variant and x."title" is distinct from t.title;
  end if;
  return jsonb_build_object(
    'options', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', k."id",
        'name', k."name",
        'values', (select coalesce(jsonb_agg(jsonb_build_object('id', z."id", 'value', z."value") order by z."rank" collate "C"), '[]'::jsonb) from "better_supabase"."product_option_values" z where z."option_id" = k."id")
      ) order by k."rank" collate "C"), '[]'::jsonb)
      from "better_supabase"."product_options" k where k."product_id" = set_product_options.product
    ),
    'variants', (
      select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'sku', x."sku", 'optionValueIds', to_jsonb(coalesce((select array_agg(y."option_value_id" order by y."option_value_id") from "better_supabase"."product_variant_values" y where y."variant_id" = x."id"), '{}'::uuid[]))) order by x."rank" collate "C"), '[]'::jsonb)
      from "better_supabase"."product_variants" x where x."product_id" = set_product_options.product
    )
  );
end;
$$;
revoke execute on function "better_supabase"."set_product_options"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."set_product_options"(uuid, jsonb, text) to authenticated, service_role;

-- Creates a price list (price_list null) or renames one. customer_group
-- names the customers it is for, such as a B2B tier.
create or replace function "better_supabase"."save_price_list"(tenant uuid, price_list uuid, name text, customer_group text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_price_list.price_list;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_price_list.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."price_lists" ("tenant_id", "name", "customer_group")
      values (save_price_list.tenant, save_price_list.name, save_price_list.customer_group)
      returning "id" into v_id;
    else
      update "better_supabase"."price_lists" x set "name" = save_price_list.name, "customer_group" = save_price_list.customer_group
      where x."id" = v_id and x."tenant_id" = save_price_list.tenant;
      if not found then
        raise exception 'price list not found' using errcode = 'P0002', hint = 'CATALOG_PRICE_LIST_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another price list has this name' using errcode = '23505', hint = 'CATALOG_PRICE_LIST_TAKEN';
  end;
  return jsonb_build_object('id', v_id);
end;
$$;
revoke execute on function "better_supabase"."save_price_list"(uuid, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."save_price_list"(uuid, uuid, text, text) to authenticated, service_role;

-- Deletes a price list and its prices.
create or replace function "better_supabase"."delete_price_list"(price_list uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."price_lists" x where x."id" = delete_price_list.price_list;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."price_lists" x where x."id" = delete_price_list.price_list;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_price_list"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_price_list"(uuid) to authenticated, service_role;

-- Sets a variant's price in a currency, in minor units, for a price list
-- (null for the base price) and a validity window. The same window is
-- updated in place; a window that overlaps another price is refused.
create or replace function "better_supabase"."set_price"(variant uuid, currency text, amount text, compare_at text, price_list uuid, valid_from timestamptz, valid_until timestamptz)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_amount bigint := case when set_price.amount ~ '^[0-9]{1,18}$' then set_price.amount::bigint end;
  v_compare bigint := case when set_price.compare_at ~ '^[0-9]{1,18}$' then set_price.compare_at::bigint end;
  v_id uuid;
  v_previous bigint;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."product_variants" x where x."id" = set_price.variant for update;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if "better_supabase"."currency_minor_units"(set_price.currency) is null then
    raise exception 'not an ISO 4217 currency code' using errcode = '22023', hint = 'CATALOG_CURRENCY_INVALID';
  end if;
  if v_amount is null then
    raise exception 'the amount must be a whole number of minor units' using errcode = '22023', hint = 'CATALOG_AMOUNT_INVALID';
  end if;
  if set_price.compare_at is not null and (v_compare is null or v_compare <= v_amount) then
    raise exception 'the compare-at amount must be above the amount' using errcode = '22023', hint = 'CATALOG_COMPARE_AT_INVALID';
  end if;
  if set_price.valid_until is not null and set_price.valid_until <= coalesce(set_price.valid_from, '-infinity'::timestamptz) then
    raise exception 'valid_until must be after valid_from' using errcode = '22023', hint = 'CATALOG_VALIDITY_INVALID';
  end if;
  if set_price.price_list is not null and not exists (select 1 from "better_supabase"."price_lists" x where x."id" = set_price.price_list and x."tenant_id" = v_tenant) then
    raise exception 'price list not found' using errcode = 'P0002', hint = 'CATALOG_PRICE_LIST_NOT_FOUND';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_price_set"(uuid, text, bigint, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::bigint, $4::uuid)', v_hook::oid::regproc)
        using set_price.variant, set_price.currency, v_amount, set_price.price_list;
    end if;
  end;
  select x."id", x."amount" into v_id, v_previous from "better_supabase"."product_prices" x
  where x."variant_id" = set_price.variant and x."currency" = set_price.currency and x."price_list_id" is not distinct from set_price.price_list
    and x."valid_from" is not distinct from set_price.valid_from and x."valid_until" is not distinct from set_price.valid_until;
  if exists (
    select 1 from "better_supabase"."product_prices" x
    where x."variant_id" = set_price.variant and x."currency" = set_price.currency and x."price_list_id" is not distinct from set_price.price_list
      and x."id" is distinct from v_id
      and tstzrange(coalesce(x."valid_from", '-infinity'::timestamptz), coalesce(x."valid_until", 'infinity'::timestamptz), '[)') && tstzrange(coalesce(set_price.valid_from, '-infinity'::timestamptz), coalesce(set_price.valid_until, 'infinity'::timestamptz), '[)')
  ) then
    raise exception 'another price of this variant, currency and list covers part of this window' using errcode = '23P01', hint = 'CATALOG_PRICE_OVERLAP';
  end if;
  if v_id is null then
    insert into "better_supabase"."product_prices" ("tenant_id", "variant_id", "currency", "amount", "price_list_id", "compare_at_amount", "valid_from", "valid_until")
    values (v_tenant, set_price.variant, set_price.currency, v_amount, set_price.price_list, v_compare, set_price.valid_from, set_price.valid_until)
    returning "id" into v_id;
  else
    update "better_supabase"."product_prices" x set "amount" = v_amount, "compare_at_amount" = v_compare, "updated_at" = now()
    where x."id" = v_id;
  end if;
  if v_previous is distinct from v_amount then
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_price_set"(uuid, bigint)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::bigint)', v_hook::oid::regproc)
        using v_id, v_previous;
    end if;
  end;
  return jsonb_build_object('id', v_id, 'amount', v_amount::text, 'previousAmount', v_previous::text);
end;
$$;
revoke execute on function "better_supabase"."set_price"(uuid, text, text, text, uuid, timestamptz, timestamptz) from public, anon;
grant execute on function "better_supabase"."set_price"(uuid, text, text, text, uuid, timestamptz, timestamptz) to authenticated, service_role;

-- Deletes a price.
create or replace function "better_supabase"."delete_price"(price uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."product_prices" x where x."id" = delete_price.price;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."product_prices" x where x."id" = delete_price.price;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_price"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_price"(uuid) to authenticated, service_role;

-- The price a variant sells at in a currency at a time: the price list's
-- price when it has one, otherwise the base price. Runs as the caller, so
-- the read policies decide which prices it sees. Amounts are text: JSON
-- numbers lose bigint precision.
create or replace function "better_supabase"."variant_price"(variant uuid, currency text, price_list uuid default null, as_of timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', x."id",
    'variantId', x."variant_id",
    'currency', x."currency",
    'amount', x."amount"::text,
    'compareAt', x."compare_at_amount"::text,
    'priceListId', x."price_list_id"
  )
  from "better_supabase"."product_prices" x
  where x."variant_id" = $1 and x."currency" = $2
    and (x."price_list_id" is null or x."price_list_id" = $3)
    and tstzrange(coalesce(x."valid_from", '-infinity'::timestamptz), coalesce(x."valid_until", 'infinity'::timestamptz), '[)') @> coalesce($4, now())
  order by (x."price_list_id" is null), x."updated_at" desc
  limit 1
$$;
revoke execute on function "better_supabase"."variant_price"(uuid, text, uuid, timestamptz) from public;
grant execute on function "better_supabase"."variant_price"(uuid, text, uuid, timestamptz) to anon, authenticated, service_role;

-- Creates a category (category null) or updates one, under parent (null
-- for the top level). A new category goes after its siblings. fields: the
-- extra columns (options.categoryExtraColumns) to set.
drop function if exists "better_supabase"."save_category"(uuid, uuid, uuid, text, text, text, jsonb);
create or replace function "better_supabase"."save_category"(tenant uuid, category uuid, parent uuid, name text, slug text, description text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_category.category;
  v_slug text := coalesce(nullif(save_category.slug, ''), trim(both '-' from regexp_replace(lower(save_category.name), '[^a-z0-9]+', '-', 'g')));
  v_last text;
  v_rank text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_category.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_slug is null or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'the slug must be lower-case letters, digits and hyphens' using errcode = '22023', hint = 'CATALOG_SLUG_INVALID';
  end if;
  if save_category.parent is not null and not exists (select 1 from "better_supabase"."categories" x where x."id" = save_category.parent and x."tenant_id" = save_category.tenant) then
    raise exception 'parent category not found' using errcode = 'P0002', hint = 'CATALOG_CATEGORY_NOT_FOUND';
  end if;
  if save_category.parent is not null and exists (
    with recursive up (id) as (
      select save_category.parent
      union
      select x."parent_id" from "better_supabase"."categories" x join up on x."id" = up.id where x."parent_id" is not null
    )
    select 1 from up where up.id = v_id
  ) then
    raise exception 'a category can''t sit under itself' using errcode = '22023', hint = 'CATALOG_CATEGORY_CYCLE';
  end if;
  begin
    if v_id is null then
      select max(x."rank" collate "C") into v_last from "better_supabase"."categories" x
      where x."tenant_id" = save_category.tenant and x."parent_id" is not distinct from save_category.parent;
      v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
      insert into "better_supabase"."categories" ("tenant_id", "parent_id", "name", "slug", "description", "rank")
      values (save_category.tenant, save_category.parent, save_category.name, v_slug, save_category.description, v_rank)
      returning "id" into v_id;
    else
      update "better_supabase"."categories" x set "parent_id" = save_category.parent, "name" = save_category.name, "slug" = v_slug,
        "description" = save_category.description, "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_category.tenant
      returning x."rank" into v_rank;
      if not found then
        raise exception 'category not found' using errcode = 'P0002', hint = 'CATALOG_CATEGORY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another category has this slug' using errcode = '23505', hint = 'CATALOG_SLUG_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'rank', v_rank);
end;
$$;
revoke execute on function "better_supabase"."save_category"(uuid, uuid, uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."save_category"(uuid, uuid, uuid, text, text, text) to authenticated, service_role;

-- Moves a category under parent (null for the top level) at rank, a key
-- from rankBetween over its new siblings' keys.
create or replace function "better_supabase"."move_category"(category uuid, parent uuid, rank text)
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
  if move_category.rank is null or move_category.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'CATALOG_RANK_INVALID';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."categories" x where x."id" = move_category.category for update;
  if v_tenant is null then
    raise exception 'category not found' using errcode = 'P0002', hint = 'CATALOG_CATEGORY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if move_category.parent is not null and not exists (select 1 from "better_supabase"."categories" x where x."id" = move_category.parent and x."tenant_id" = v_tenant) then
    raise exception 'parent category not found' using errcode = 'P0002', hint = 'CATALOG_CATEGORY_NOT_FOUND';
  end if;
  if move_category.parent is not null and exists (
    with recursive up (id) as (
      select move_category.parent
      union
      select x."parent_id" from "better_supabase"."categories" x join up on x."id" = up.id where x."parent_id" is not null
    )
    select 1 from up where up.id = move_category.category
  ) then
    raise exception 'a category can''t sit under itself' using errcode = '22023', hint = 'CATALOG_CATEGORY_CYCLE';
  end if;
  update "better_supabase"."categories" x set "parent_id" = move_category.parent, "rank" = move_category.rank, "updated_at" = now()
  where x."id" = move_category.category;
  return true;
end;
$$;
revoke execute on function "better_supabase"."move_category"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."move_category"(uuid, uuid, text) to authenticated, service_role;

-- Deletes a category without subcategories; products leave it.
create or replace function "better_supabase"."delete_category"(category uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."categories" x where x."id" = delete_category.category;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  begin
    delete from "better_supabase"."categories" x where x."id" = delete_category.category;
  exception when foreign_key_violation then
    raise exception 'move or delete the subcategories first' using errcode = '23503', hint = 'CATALOG_CATEGORY_HAS_CHILDREN';
  end;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_category"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_category"(uuid) to authenticated, service_role;

-- Replaces the categories a product is filed under.
create or replace function "better_supabase"."set_product_categories"(product uuid, categories uuid[])
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
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = set_product_categories.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if exists (
    select 1 from unnest(coalesce(set_product_categories.categories, '{}'::uuid[])) c
    where not exists (select 1 from "better_supabase"."categories" x where x."id" = c and x."tenant_id" = v_tenant)
  ) then
    raise exception 'category not found' using errcode = 'P0002', hint = 'CATALOG_CATEGORY_NOT_FOUND';
  end if;
  delete from "better_supabase"."product_categories" x
  where x."product_id" = set_product_categories.product
    and not (x."category_id" = any (coalesce(set_product_categories.categories, '{}'::uuid[])));
  insert into "better_supabase"."product_categories" ("tenant_id", "product_id", "category_id")
  select distinct v_tenant, set_product_categories.product, c from unnest(coalesce(set_product_categories.categories, '{}'::uuid[])) c
  on conflict do nothing;
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_product_categories"(uuid, uuid[]) from public, anon;
grant execute on function "better_supabase"."set_product_categories"(uuid, uuid[]) to authenticated, service_role;

-- Creates a collection (collection null) or updates one. A manual
-- collection lists ranked products; a rule collection stores a filter tree
-- (a FilterQuery group) that picks them.
create or replace function "better_supabase"."save_collection"(tenant uuid, collection uuid, title text, slug text, kind text, rule jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_collection.collection;
  v_kind text := coalesce(save_collection.kind, 'manual');
  v_slug text := coalesce(nullif(save_collection.slug, ''), trim(both '-' from regexp_replace(lower(save_collection.title), '[^a-z0-9]+', '-', 'g')));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_collection.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_slug is null or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'the slug must be lower-case letters, digits and hyphens' using errcode = '22023', hint = 'CATALOG_SLUG_INVALID';
  end if;
  if v_kind not in ('manual', 'rule') then
    raise exception 'the kind must be manual or rule' using errcode = '22023', hint = 'CATALOG_COLLECTION_KIND';
  end if;
  if (v_kind = 'rule') <> (save_collection.rule is not null) then
    raise exception 'a rule collection needs a rule and a manual one none' using errcode = '22023', hint = 'CATALOG_COLLECTION_RULE';
  end if;
  if v_kind = 'rule' and not (
    jsonb_typeof(save_collection.rule) = 'object'
    and save_collection.rule ->> 'type' = 'group'
    and save_collection.rule ->> 'combinator' in ('and', 'or')
    and jsonb_typeof(save_collection.rule -> 'rules') = 'array'
  ) then
    raise exception 'the rule must be a filter group with a combinator and rules' using errcode = '22023', hint = 'CATALOG_COLLECTION_RULE';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."product_collections" ("tenant_id", "title", "slug", "kind", "rule")
      values (save_collection.tenant, save_collection.title, v_slug, v_kind, save_collection.rule)
      returning "id" into v_id;
    else
      update "better_supabase"."product_collections" x set "title" = save_collection.title, "slug" = v_slug, "kind" = v_kind,
        "rule" = save_collection.rule, "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_collection.tenant;
      if not found then
        raise exception 'collection not found' using errcode = 'P0002', hint = 'CATALOG_COLLECTION_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another collection has this slug' using errcode = '23505', hint = 'CATALOG_SLUG_TAKEN';
  end;
  if v_kind = 'rule' then
    delete from "better_supabase"."collection_products" x where x."collection_id" = v_id;
  end if;
  return jsonb_build_object('id', v_id, 'slug', v_slug, 'kind', v_kind);
end;
$$;
revoke execute on function "better_supabase"."save_collection"(uuid, uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."save_collection"(uuid, uuid, text, text, text, jsonb) to authenticated, service_role;

-- Deletes a collection.
create or replace function "better_supabase"."delete_collection"(collection uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."product_collections" x where x."id" = delete_collection.collection;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."product_collections" x where x."id" = delete_collection.collection;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_collection"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_collection"(uuid) to authenticated, service_role;

-- Adds a product to a manual collection at rank (null to append), or moves
-- it there. Returns its rank key.
create or replace function "better_supabase"."add_to_collection"(collection uuid, product uuid, rank text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_kind text;
  v_last text;
  v_rank text := add_to_collection.rank;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."kind" into v_tenant, v_kind from "better_supabase"."product_collections" x where x."id" = add_to_collection.collection for update;
  if v_tenant is null then
    raise exception 'collection not found' using errcode = 'P0002', hint = 'CATALOG_COLLECTION_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if v_kind <> 'manual' then
    raise exception 'a rule collection picks its products from its rule' using errcode = '22023', hint = 'CATALOG_COLLECTION_RULE';
  end if;
  if not exists (select 1 from "better_supabase"."products" x where x."id" = add_to_collection.product and x."tenant_id" = v_tenant) then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if v_rank is not null and v_rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then
    raise exception 'not a rank key' using errcode = '22023', hint = 'CATALOG_RANK_INVALID';
  end if;
  if v_rank is null then
    select max(x."rank" collate "C") into v_last from "better_supabase"."collection_products" x where x."collection_id" = add_to_collection.collection;
    v_rank := case
    when v_last is null then 'V'
    when length(substring(v_last from '^z*')) = length(v_last) then v_last || 'V'
    else left(v_last, length(substring(v_last from '^z*'))) || substr('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', (strpos('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', substr(v_last, length(substring(v_last from '^z*')) + 1, 1)) - 1 + 62) / 2 + 1, 1)
  end;
  end if;
  insert into "better_supabase"."collection_products" as x ("tenant_id", "collection_id", "product_id", "rank")
  values (v_tenant, add_to_collection.collection, add_to_collection.product, v_rank)
  on conflict ("collection_id", "product_id") do update set "rank" = excluded."rank";
  return v_rank;
end;
$$;
revoke execute on function "better_supabase"."add_to_collection"(uuid, uuid, text) from public, anon;
grant execute on function "better_supabase"."add_to_collection"(uuid, uuid, text) to authenticated, service_role;

-- Removes a product from a manual collection.
create or replace function "better_supabase"."remove_from_collection"(collection uuid, product uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."product_collections" x where x."id" = remove_from_collection.collection;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."collection_products" x where x."collection_id" = remove_from_collection.collection and x."product_id" = remove_from_collection.product;
  return found;
end;
$$;
revoke execute on function "better_supabase"."remove_from_collection"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_from_collection"(uuid, uuid) to authenticated, service_role;

-- Tenants whose storefront is published. The storefront read policies
-- call it, so it runs as its owner and returns nothing else.
create or replace function "better_supabase"."storefront_tenants"()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select x."tenant_id" from "better_supabase"."storefronts" x where x."published_at" is not null
$$;
revoke execute on function "better_supabase"."storefront_tenants"() from public;
grant execute on function "better_supabase"."storefront_tenants"() to anon, authenticated, service_role;

-- Active products of published storefronts, for the storefront policies.
create or replace function "better_supabase"."storefront_products"()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select x."id" from "better_supabase"."products" x
  where x."status" = 'active'
    and x."tenant_id" in (select y."tenant_id" from "better_supabase"."storefronts" y where y."published_at" is not null)
$$;
revoke execute on function "better_supabase"."storefront_products"() from public;
grant execute on function "better_supabase"."storefront_products"() to anon, authenticated, service_role;

-- Publishes or unpublishes a tenant's storefront. With options.storefront
-- "public", anyone can read the active products of a published storefront.
create or replace function "better_supabase"."publish_storefront"(tenant uuid, published boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', publish_storefront.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  insert into "better_supabase"."storefronts" as x ("tenant_id", "published_at")
  values (publish_storefront.tenant, case when publish_storefront.published then now() end)
  on conflict ("tenant_id") do update
    set "published_at" = case when publish_storefront.published then coalesce(x."published_at", now()) end;
  if publish_storefront.published then
    null;
  else
    null;
  end if;
  return publish_storefront.published;
end;
$$;
revoke execute on function "better_supabase"."publish_storefront"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."publish_storefront"(uuid, boolean) to authenticated, service_role;

-- Creates a sales channel (channel null) or updates one. A channel has a
-- key, unique per organization, and optionally a currency and a price list
-- its prices come from.
create or replace function "better_supabase"."save_catalog_channel"(tenant uuid, channel uuid, key text, name text, currency text, price_list uuid, active boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid := save_catalog_channel.channel;
  v_active boolean;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_catalog_channel.tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if save_catalog_channel.key is null or save_catalog_channel.key !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'the channel key must be lower-case letters, digits and hyphens' using errcode = '22023', hint = 'CATALOG_CHANNEL_KEY_INVALID';
  end if;
  if save_catalog_channel.currency is not null and "better_supabase"."currency_minor_units"(save_catalog_channel.currency) is null then
    raise exception 'not an ISO 4217 currency code' using errcode = '22023', hint = 'CATALOG_CURRENCY_INVALID';
  end if;
  if save_catalog_channel.price_list is not null and not exists (select 1 from "better_supabase"."price_lists" x where x."id" = save_catalog_channel.price_list and x."tenant_id" = save_catalog_channel.tenant) then
    raise exception 'price list not found' using errcode = 'P0002', hint = 'CATALOG_PRICE_LIST_NOT_FOUND';
  end if;
  begin
    if v_id is null then
      insert into "better_supabase"."catalog_channels" as x ("tenant_id", "key", "name", "currency", "price_list_id", "active")
      values (save_catalog_channel.tenant, save_catalog_channel.key, save_catalog_channel.name, save_catalog_channel.currency, save_catalog_channel.price_list, coalesce(save_catalog_channel.active, true))
      returning x."id", x."active" into v_id, v_active;
    else
      update "better_supabase"."catalog_channels" x set "key" = save_catalog_channel.key, "name" = save_catalog_channel.name, "currency" = save_catalog_channel.currency, "price_list_id" = save_catalog_channel.price_list, "active" = coalesce(save_catalog_channel.active, x."active"), "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = save_catalog_channel.tenant
      returning x."active" into v_active;
      if not found then
        raise exception 'channel not found' using errcode = 'P0002', hint = 'CATALOG_CHANNEL_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another channel has this key' using errcode = '23505', hint = 'CATALOG_CHANNEL_TAKEN';
  end;
  return jsonb_build_object('id', v_id, 'key', save_catalog_channel.key, 'active', v_active);
end;
$$;
revoke execute on function "better_supabase"."save_catalog_channel"(uuid, uuid, text, text, text, uuid, boolean) from public, anon;
grant execute on function "better_supabase"."save_catalog_channel"(uuid, uuid, text, text, text, uuid, boolean) to authenticated, service_role;

-- Deletes a channel and its listings.
create or replace function "better_supabase"."delete_catalog_channel"(channel uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."catalog_channels" x where x."id" = delete_catalog_channel.channel;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  delete from "better_supabase"."catalog_channels" x where x."id" = delete_catalog_channel.channel;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_catalog_channel"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_catalog_channel"(uuid) to authenticated, service_role;

-- The price a variant sells at on a channel: variant_price in the channel's
-- currency and price list. Null when the channel has no currency.
create or replace function "better_supabase"."channel_price"(channel uuid, variant uuid, as_of timestamptz default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."variant_price"($2, k."currency", k."price_list_id", $3)
  from "better_supabase"."catalog_channels" k
  where k."id" = $1 and k."currency" is not null
$$;
revoke execute on function "better_supabase"."channel_price"(uuid, uuid, timestamptz) from public;
grant execute on function "better_supabase"."channel_price"(uuid, uuid, timestamptz) to anon, authenticated, service_role;

-- Lists products on a channel (listed true) or takes them off it. Returns
-- how many listings changed.
create or replace function "better_supabase"."set_channel_listing"(channel uuid, products uuid[], listed boolean)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_count integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."catalog_channels" x where x."id" = set_channel_listing.channel for update;
  if v_tenant is null then
    raise exception 'channel not found' using errcode = 'P0002', hint = 'CATALOG_CHANNEL_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if exists (
    select 1 from unnest(coalesce(set_channel_listing.products, '{}'::uuid[])) i
    where not exists (select 1 from "better_supabase"."products" x where x."id" = i and x."tenant_id" = v_tenant)
  ) then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if coalesce(set_channel_listing.listed, true) then
    insert into "better_supabase"."catalog_channel_products" ("tenant_id", "channel_id", "product_id")
    select distinct v_tenant, set_channel_listing.channel, i from unnest(coalesce(set_channel_listing.products, '{}'::uuid[])) i
    on conflict do nothing;
  else
    delete from "better_supabase"."catalog_channel_products" x
    where x."channel_id" = set_channel_listing.channel
      and x."product_id" = any (coalesce(set_channel_listing.products, '{}'::uuid[]));
  end if;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."set_channel_listing"(uuid, uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."set_channel_listing"(uuid, uuid[], boolean) to authenticated, service_role;

-- The products listed on a channel by slug, with their text in locale
-- (the default text where a translation is missing). after is the last
-- slug of the previous page. Runs as the caller, so the read policies
-- decide what it sees.
create or replace function "better_supabase"."channel_products"(channel uuid, locale text default null, page_size integer default null, after text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(item order by slug collate "C"), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', p."id",
      'slug', p."slug",
      'status', p."status",
      'kind', p."kind",
      'locale', (case when $2 = any ('{en}'::text[]) then $2 when split_part($2, '-', 1) = any ('{en}'::text[]) then split_part($2, '-', 1) else 'en' end),
      'title', coalesce(t."title", p."title"),
      'description', coalesce(t."description", p."description"),
      'listedAt', l."listed_at"
    ) as item, p."slug" as slug
    from "better_supabase"."catalog_channel_products" l
    join "better_supabase"."products" p on p."id" = l."product_id"
    left join "better_supabase"."product_translations" t on t."product_id" = p."id" and t."locale" = (case when $2 = any ('{en}'::text[]) then $2 when split_part($2, '-', 1) = any ('{en}'::text[]) then split_part($2, '-', 1) else 'en' end)
    where l."channel_id" = $1
      and ($4 is null or p."slug" collate "C" > $4 collate "C")
    order by p."slug" collate "C"
    limit least(greatest(coalesce($3, 100), 1), 500)
  ) items
$$;
revoke execute on function "better_supabase"."channel_products"(uuid, text, integer, text) from public;
grant execute on function "better_supabase"."channel_products"(uuid, text, integer, text) to anon, authenticated, service_role;

-- Sets a product's title and description in a locale other than the
-- default. Null text falls back to the default text; both null removes the
-- translation. Returns whether one is stored.
create or replace function "better_supabase"."set_product_translation"(product uuid, locale text, title text, description text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."products" x where x."id" = set_product_translation.product for update;
  if v_tenant is null then
    raise exception 'product not found' using errcode = 'P0002', hint = 'CATALOG_PRODUCT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if set_product_translation.locale is null or not (set_product_translation.locale = any ('{en}'::text[])) then
    raise exception 'the locale is not one of blocks.catalog.options.locales' using errcode = '22023', hint = 'CATALOG_LOCALE_INVALID';
  end if;
  if set_product_translation.locale = 'en' then
    raise exception 'the default locale''s text lives on the record itself' using errcode = '22023', hint = 'CATALOG_LOCALE_DEFAULT';
  end if;
  if set_product_translation.title is not null and length(set_product_translation.title) not between 1 and 500 then
    raise exception 'a title has 1 to 500 characters' using errcode = '22023', hint = 'CATALOG_TITLE_INVALID';
  end if;
  if set_product_translation.title is null and set_product_translation.description is null then
    delete from "better_supabase"."product_translations" x
    where x."product_id" = set_product_translation.product and x."locale" = set_product_translation.locale;
    return false;
  end if;
  insert into "better_supabase"."product_translations" as x ("tenant_id", "product_id", "locale", "title", "description")
  values (v_tenant, set_product_translation.product, set_product_translation.locale, set_product_translation.title, set_product_translation.description)
  on conflict ("product_id", "locale") do update
    set "title" = excluded."title", "description" = excluded."description", "updated_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_product_translation"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."set_product_translation"(uuid, text, text, text) to authenticated, service_role;

-- Sets a variant's title in a locale other than the default; a null title
-- removes the translation. Returns whether one is stored.
create or replace function "better_supabase"."set_variant_translation"(variant uuid, locale text, title text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."product_variants" x where x."id" = set_variant_translation.variant for update;
  if v_tenant is null then
    raise exception 'variant not found' using errcode = 'P0002', hint = 'CATALOG_VARIANT_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'catalog.manage'), false)) then
    raise exception 'not allowed to manage the catalog' using errcode = '42501', hint = 'CATALOG_FORBIDDEN';
  end if;
  if set_variant_translation.locale is null or not (set_variant_translation.locale = any ('{en}'::text[])) then
    raise exception 'the locale is not one of blocks.catalog.options.locales' using errcode = '22023', hint = 'CATALOG_LOCALE_INVALID';
  end if;
  if set_variant_translation.locale = 'en' then
    raise exception 'the default locale''s text lives on the record itself' using errcode = '22023', hint = 'CATALOG_LOCALE_DEFAULT';
  end if;
  if set_variant_translation.title is not null and length(set_variant_translation.title) not between 1 and 500 then
    raise exception 'a title has 1 to 500 characters' using errcode = '22023', hint = 'CATALOG_TITLE_INVALID';
  end if;
  if set_variant_translation.title is null then
    delete from "better_supabase"."product_variant_translations" x
    where x."variant_id" = set_variant_translation.variant and x."locale" = set_variant_translation.locale;
    return false;
  end if;
  insert into "better_supabase"."product_variant_translations" as x ("tenant_id", "variant_id", "locale", "title")
  values (v_tenant, set_variant_translation.variant, set_variant_translation.locale, set_variant_translation.title)
  on conflict ("variant_id", "locale") do update
    set "title" = excluded."title", "updated_at" = now();
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_variant_translation"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_variant_translation"(uuid, text, text) to authenticated, service_role;

-- A product's text and its variants' titles in locale: the locale itself,
-- then its language, then the default locale's text on the product. Runs
-- as the caller, so the read policies decide what it sees.
create or replace function "better_supabase"."product_text"(product uuid, locale text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'id', p."id",
    'slug', p."slug",
    'locale', (case when $2 = any ('{en}'::text[]) then $2 when split_part($2, '-', 1) = any ('{en}'::text[]) then split_part($2, '-', 1) else 'en' end),
    'title', coalesce(t."title", p."title"),
    'description', coalesce(t."description", p."description"),
    'variants', coalesce((
      select jsonb_agg(jsonb_build_object('id', w."id", 'sku', w."sku", 'title', coalesce((select y."title" from "better_supabase"."product_variant_translations" y where y."variant_id" = w."id" and y."locale" = (case when $2 = any ('{en}'::text[]) then $2 when split_part($2, '-', 1) = any ('{en}'::text[]) then split_part($2, '-', 1) else 'en' end)), w."title")) order by w."rank" collate "C", w."id")
      from "better_supabase"."product_variants" w where w."product_id" = p."id"
    ), '[]'::jsonb)
  )
  from "better_supabase"."products" p
  left join "better_supabase"."product_translations" t on t."product_id" = p."id" and t."locale" = (case when $2 = any ('{en}'::text[]) then $2 when split_part($2, '-', 1) = any ('{en}'::text[]) then split_part($2, '-', 1) else 'en' end)
  where p."id" = $1
$$;
revoke execute on function "better_supabase"."product_text"(uuid, text) from public;
grant execute on function "better_supabase"."product_text"(uuid, text) to anon, authenticated, service_role;

drop policy if exists products_storefront on "better_supabase"."products";
drop policy if exists product_options_storefront on "better_supabase"."product_options";
drop policy if exists product_option_values_storefront on "better_supabase"."product_option_values";
drop policy if exists product_variants_storefront on "better_supabase"."product_variants";
drop policy if exists product_variant_values_storefront on "better_supabase"."product_variant_values";
drop policy if exists product_prices_storefront on "better_supabase"."product_prices";
drop policy if exists categories_storefront on "better_supabase"."categories";
drop policy if exists product_categories_storefront on "better_supabase"."product_categories";
drop policy if exists product_collections_storefront on "better_supabase"."product_collections";
drop policy if exists collection_products_storefront on "better_supabase"."collection_products";
drop policy if exists catalog_channels_storefront on "better_supabase"."catalog_channels";
drop policy if exists catalog_channel_products_storefront on "better_supabase"."catalog_channel_products";
drop policy if exists product_translations_storefront on "better_supabase"."product_translations";
drop policy if exists product_variant_translations_storefront on "better_supabase"."product_variant_translations";

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
-- Until memberships installs, the caller is a member of no organization.
do $$
begin
  if to_regprocedure('better_supabase.member_workspace_ids(text[])') is null then
    create function better_supabase.member_workspace_ids(roles text[] default null)
    returns setof uuid
    language sql
    stable
    set search_path = ''
    as $members$ select null::uuid where false $members$;
  end if;
end $$;
drop policy if exists bsb_tenant_scope on "better_supabase"."products";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."products";
create policy bsb_tenant_scope_select on "better_supabase"."products" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."products";
create policy bsb_tenant_scope_insert on "better_supabase"."products" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."products";
create policy bsb_tenant_scope_update on "better_supabase"."products" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."products";
create policy bsb_tenant_scope_delete on "better_supabase"."products" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."product_options";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_options";
create policy bsb_tenant_scope_select on "better_supabase"."product_options" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_options";
create policy bsb_tenant_scope_insert on "better_supabase"."product_options" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_options";
create policy bsb_tenant_scope_update on "better_supabase"."product_options" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_options";
create policy bsb_tenant_scope_delete on "better_supabase"."product_options" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."product_option_values";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_option_values";
create policy bsb_tenant_scope_select on "better_supabase"."product_option_values" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_option_values";
create policy bsb_tenant_scope_insert on "better_supabase"."product_option_values" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_option_values";
create policy bsb_tenant_scope_update on "better_supabase"."product_option_values" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_option_values";
create policy bsb_tenant_scope_delete on "better_supabase"."product_option_values" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."product_variants";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_variants";
create policy bsb_tenant_scope_select on "better_supabase"."product_variants" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_variants";
create policy bsb_tenant_scope_insert on "better_supabase"."product_variants" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_variants";
create policy bsb_tenant_scope_update on "better_supabase"."product_variants" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_variants";
create policy bsb_tenant_scope_delete on "better_supabase"."product_variants" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."product_variant_values";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_variant_values";
create policy bsb_tenant_scope_select on "better_supabase"."product_variant_values" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_variant_values";
create policy bsb_tenant_scope_insert on "better_supabase"."product_variant_values" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_variant_values";
create policy bsb_tenant_scope_update on "better_supabase"."product_variant_values" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_variant_values";
create policy bsb_tenant_scope_delete on "better_supabase"."product_variant_values" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."price_lists";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."price_lists";
create policy bsb_tenant_scope_select on "better_supabase"."price_lists" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."price_lists";
create policy bsb_tenant_scope_insert on "better_supabase"."price_lists" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."price_lists";
create policy bsb_tenant_scope_update on "better_supabase"."price_lists" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."price_lists";
create policy bsb_tenant_scope_delete on "better_supabase"."price_lists" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."product_prices";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_prices";
create policy bsb_tenant_scope_select on "better_supabase"."product_prices" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_prices";
create policy bsb_tenant_scope_insert on "better_supabase"."product_prices" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_prices";
create policy bsb_tenant_scope_update on "better_supabase"."product_prices" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_prices";
create policy bsb_tenant_scope_delete on "better_supabase"."product_prices" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."categories";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."categories";
create policy bsb_tenant_scope_select on "better_supabase"."categories" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."categories";
create policy bsb_tenant_scope_insert on "better_supabase"."categories" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."categories";
create policy bsb_tenant_scope_update on "better_supabase"."categories" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."categories";
create policy bsb_tenant_scope_delete on "better_supabase"."categories" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."product_categories";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_categories";
create policy bsb_tenant_scope_select on "better_supabase"."product_categories" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_categories";
create policy bsb_tenant_scope_insert on "better_supabase"."product_categories" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_categories";
create policy bsb_tenant_scope_update on "better_supabase"."product_categories" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_categories";
create policy bsb_tenant_scope_delete on "better_supabase"."product_categories" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."product_collections";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_collections";
create policy bsb_tenant_scope_select on "better_supabase"."product_collections" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_collections";
create policy bsb_tenant_scope_insert on "better_supabase"."product_collections" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_collections";
create policy bsb_tenant_scope_update on "better_supabase"."product_collections" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_collections";
create policy bsb_tenant_scope_delete on "better_supabase"."product_collections" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."collection_products";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."collection_products";
create policy bsb_tenant_scope_select on "better_supabase"."collection_products" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."collection_products";
create policy bsb_tenant_scope_insert on "better_supabase"."collection_products" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."collection_products";
create policy bsb_tenant_scope_update on "better_supabase"."collection_products" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."collection_products";
create policy bsb_tenant_scope_delete on "better_supabase"."collection_products" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."storefronts";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."storefronts";
create policy bsb_tenant_scope_select on "better_supabase"."storefronts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."storefronts";
create policy bsb_tenant_scope_insert on "better_supabase"."storefronts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."storefronts";
create policy bsb_tenant_scope_update on "better_supabase"."storefronts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."storefronts";
create policy bsb_tenant_scope_delete on "better_supabase"."storefronts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."catalog_channels";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."catalog_channels";
create policy bsb_tenant_scope_select on "better_supabase"."catalog_channels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."catalog_channels";
create policy bsb_tenant_scope_insert on "better_supabase"."catalog_channels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."catalog_channels";
create policy bsb_tenant_scope_update on "better_supabase"."catalog_channels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."catalog_channels";
create policy bsb_tenant_scope_delete on "better_supabase"."catalog_channels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."catalog_channel_products";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."catalog_channel_products";
create policy bsb_tenant_scope_select on "better_supabase"."catalog_channel_products" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."catalog_channel_products";
create policy bsb_tenant_scope_insert on "better_supabase"."catalog_channel_products" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."catalog_channel_products";
create policy bsb_tenant_scope_update on "better_supabase"."catalog_channel_products" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."catalog_channel_products";
create policy bsb_tenant_scope_delete on "better_supabase"."catalog_channel_products" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."product_translations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_translations";
create policy bsb_tenant_scope_select on "better_supabase"."product_translations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_translations";
create policy bsb_tenant_scope_insert on "better_supabase"."product_translations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_translations";
create policy bsb_tenant_scope_update on "better_supabase"."product_translations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_translations";
create policy bsb_tenant_scope_delete on "better_supabase"."product_translations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."product_variant_translations";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."product_variant_translations";
create policy bsb_tenant_scope_select on "better_supabase"."product_variant_translations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_workspace_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('catalog.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."product_variant_translations";
create policy bsb_tenant_scope_insert on "better_supabase"."product_variant_translations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."product_variant_translations";
create policy bsb_tenant_scope_update on "better_supabase"."product_variant_translations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()))
  with check ("tenant_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."product_variant_translations";
create policy bsb_tenant_scope_delete on "better_supabase"."product_variant_translations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_workspace_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_069_catalog.sql
-- better-supabase module: catalog
-- @bsb-block-data catalog
-- @bsb-hash sha256:c3ced8535b68687c89d10c7e474f654ad0172725bed2fa28ecfd0a3febb42c52
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('catalog', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
