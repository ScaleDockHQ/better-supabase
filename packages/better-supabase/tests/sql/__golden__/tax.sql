-- ==== alone: schema supabase/schemas/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block tax@1 managed
-- @bsb-hash sha256:4ead270abdb4626865a9e386e6010e8642866e6f2d2721718daf41ae5aad4e60
-- Tax codes per organization and legal entity with a rate history, the tax of a document per code on its date (margin scheme and credit restriction included), invoice tax lines written when an invoice is issued, tax returns with box totals, and the EU sales list per customer VAT number.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Tax per organization and optional legal entity: tax codes with a rate
-- history, the tax of a document computed per code (the margin scheme and a
-- credit restriction included), the tax lines of issued invoices, and the
-- returns and EU sales lists prepared from them.

-- A tax code of an organization, or of one of its legal entities. The code
-- says how a line is taxed; its rates sit in tax_rates, so a rate change keeps
-- the history. The accounts are plain ids that the functions check against the
-- chart of accounts, because accounting is installed after this block.
create table if not exists "better_supabase"."tax_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "code" text not null check (length("code") between 1 and 50),
  "name" text not null check (length("name") between 1 and 200),
  "type" text not null check ("type" in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin')),
  "sales_account_id" uuid,
  "purchase_account_id" uuid,
  -- The boxes of a tax return the code's base and tax count toward.
  "return_boxes" text[] not null default '{}',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "tax_codes_code_key" on "better_supabase"."tax_codes" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "code");
create index if not exists "tax_codes_tenant_idx" on "better_supabase"."tax_codes" ("tenant_id", "code");
alter table "better_supabase"."tax_codes" enable row level security;
revoke all on "better_supabase"."tax_codes" from public, anon, authenticated;
grant select on "better_supabase"."tax_codes" to authenticated;
grant all on "better_supabase"."tax_codes" to service_role;
drop policy if exists tax_codes_read on "better_supabase"."tax_codes";
create policy tax_codes_read on "better_supabase"."tax_codes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- What a code charges from a day until another. valid_to is the last day the
-- rate applies; without one it runs until a later rate starts.
create table if not exists "better_supabase"."tax_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "tax_code_id" uuid not null references "better_supabase"."tax_codes" ("id") on delete cascade,
  -- Basis points: 2100 is 21%.
  "rate_bps" integer not null check ("rate_bps" >= 0 and "rate_bps" <= 100000),
  "valid_from" date not null default date '1970-01-01',
  "valid_to" date,
  "created_at" timestamptz not null default now(),
  check ("valid_to" is null or "valid_to" >= "valid_from")
);
create unique index if not exists "tax_rates_from_key" on "better_supabase"."tax_rates" ("tax_code_id", "valid_from");
alter table "better_supabase"."tax_rates" enable row level security;
revoke all on "better_supabase"."tax_rates" from public, anon, authenticated;
grant select on "better_supabase"."tax_rates" to authenticated;
grant all on "better_supabase"."tax_rates" to service_role;
drop policy if exists tax_rates_read on "better_supabase"."tax_rates";
create policy tax_rates_read on "better_supabase"."tax_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The tax of an issued invoice per rate and tax code, in the shape of
-- quote_tax_lines, written when the invoice is issued. customer_vat_number is
-- the customer's VAT number at that moment; show_tax is false on a margin
-- scheme invoice, which prints no tax amount.
create table if not exists "better_supabase"."invoice_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "invoice_id" uuid not null,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "tax_code_id" uuid,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0,
  "customer_vat_number" text,
  "show_tax" boolean not null default true
);
create index if not exists "invoice_tax_lines_parent_idx" on "better_supabase"."invoice_tax_lines" ("invoice_id");
create index if not exists "invoice_tax_lines_tenant_code_idx" on "better_supabase"."invoice_tax_lines" ("tenant_id", "tax_code_id");
alter table "better_supabase"."invoice_tax_lines" enable row level security;
revoke all on "better_supabase"."invoice_tax_lines" from public, anon, authenticated;
grant select on "better_supabase"."invoice_tax_lines" to authenticated;
grant all on "better_supabase"."invoice_tax_lines" to service_role;
drop policy if exists invoice_tax_lines_read on "better_supabase"."invoice_tax_lines";
create policy invoice_tax_lines_read on "better_supabase"."invoice_tax_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- A return of one period, prepared from the issued invoices of that period.
-- boxes holds the totals per return box as decimal text.
create table if not exists "better_supabase"."tax_returns" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "period" text not null check (length("period") between 1 and 50),
  "period_start" date not null,
  "period_end" date not null,
  "status" text not null default 'draft' check ("status" in ('draft', 'filed')),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "boxes" jsonb not null default '{}'::jsonb check (jsonb_typeof("boxes") = 'object'),
  "prepared_by" uuid,
  "prepared_at" timestamptz not null default now(),
  "filed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  check (("status" = 'filed') = ("filed_at" is not null))
);
create unique index if not exists "tax_returns_period_key" on "better_supabase"."tax_returns" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "period_start", "period_end");
alter table "better_supabase"."tax_returns" enable row level security;
revoke all on "better_supabase"."tax_returns" from public, anon, authenticated;
grant select on "better_supabase"."tax_returns" to authenticated;
grant all on "better_supabase"."tax_returns" to service_role;
drop policy if exists tax_returns_read on "better_supabase"."tax_returns";
create policy tax_returns_read on "better_supabase"."tax_returns"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The intra-community sales list (ICP) of a return: what was sold to each
-- customer VAT number, as goods or as services.
create table if not exists "better_supabase"."eu_sales_list_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "tax_return_id" uuid not null references "better_supabase"."tax_returns" ("id") on delete cascade,
  "customer_vat_number" text not null check (length("customer_vat_number") between 4 and 20),
  "country" char(2) not null check ("country" ~ '^[A-Z]{2}$'),
  "kind" text not null check ("kind" in ('goods', 'services')),
  "amount" bigint not null,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_count" integer not null check ("invoice_count" > 0)
);
create unique index if not exists "eu_sales_list_lines_key" on "better_supabase"."eu_sales_list_lines" ("tax_return_id", "customer_vat_number", "kind", "currency");
alter table "better_supabase"."eu_sales_list_lines" enable row level security;
revoke all on "better_supabase"."eu_sales_list_lines" from public, anon, authenticated;
grant select on "better_supabase"."eu_sales_list_lines" to authenticated;
grant all on "better_supabase"."eu_sales_list_lines" to service_role;
drop policy if exists eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines";
create policy eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));


-- The rate a tax code charges on a day, in basis points; null when no rate
-- covers the day. A code that doesn't charge a rate (exempt, zero, reverse
-- charge, intra-EU, export) always gives 0.
create or replace function "better_supabase"."tax_rate_on"(code_id uuid, on_date date)
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when x."type" not in ('sales', 'purchase', 'margin') then 0
    else (
      select y."rate_bps" from "better_supabase"."tax_rates" y
      where y."tax_code_id" = x."id" and y."valid_from" <= tax_rate_on.on_date
        and (y."valid_to" is null or y."valid_to" >= tax_rate_on.on_date)
      order by y."valid_from" desc limit 1
    )
  end
  from "better_supabase"."tax_codes" x where x."id" = tax_rate_on.code_id
$$;
revoke execute on function "better_supabase"."tax_rate_on"(uuid, date) from public, anon;
grant execute on function "better_supabase"."tax_rate_on"(uuid, date) to authenticated, service_role;

-- The tax code a code text names: the legal entity's own code first, then the
-- organization's. Null when there is none.
create or replace function "better_supabase"."resolve_tax_code"(tenant uuid, code text, legal_entity uuid default null)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select x."id" from "better_supabase"."tax_codes" x
  where x."tenant_id" = resolve_tax_code.tenant and x."code" = resolve_tax_code.code
    and x."archived_at" is null
    and (x."legal_entity_id" is null or x."legal_entity_id" = resolve_tax_code.legal_entity)
  order by (x."legal_entity_id" is null), x."id" limit 1
$$;
revoke execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) to authenticated, service_role;

-- Adds a rate to a code from valid_from on. A rate that starts after the
-- code's earlier open rate closes it the day before; without valid_to the rate
-- runs until the next later rate. A rate with the same start is replaced.
-- Internal: save_tax_rate and the import check who may call it.
create or replace function "better_supabase"."tax_rate_write"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code "better_supabase"."tax_codes"%rowtype;
  v_from date := coalesce(tax_rate_write.valid_from, date '1970-01-01');
  v_to date := tax_rate_write.valid_to;
  v_row "better_supabase"."tax_rates"%rowtype;
begin
  select * into v_code from "better_supabase"."tax_codes" x
  where x."id" = tax_rate_write.tax_code and x."tenant_id" = tax_rate_write.tenant for update;
  if not found then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if v_code."type" not in ('sales', 'purchase', 'margin') then
    raise exception 'only a sales, purchase or margin code has a rate' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if tax_rate_write.rate_bps is null or tax_rate_write.rate_bps < 0 or tax_rate_write.rate_bps > 100000 then
    raise exception 'a rate is 0 to 100000 basis points' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is not null and v_to < v_from then
    raise exception 'a rate can''t end before it starts' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is null then
    select min(y."valid_from") - 1 into v_to from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from;
  end if;
  if v_to is not null and exists (
    select 1 from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from and y."valid_from" <= v_to
  ) then
    raise exception 'the rate would overlap a later rate of the code' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  update "better_supabase"."tax_rates" y set "valid_to" = v_from - 1
  where y."tax_code_id" = v_code."id" and y."valid_from" < v_from
    and (y."valid_to" is null or y."valid_to" >= v_from);
  insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps", "valid_from", "valid_to")
  values (tax_rate_write.tenant, v_code."id", tax_rate_write.rate_bps, v_from, v_to)
  on conflict ("tax_code_id", "valid_from") do update
    set "rate_bps" = excluded."rate_bps", "valid_to" = excluded."valid_to"
  returning * into v_row;
  update "better_supabase"."tax_codes" x set "updated_at" = now() where x."id" = v_code."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'taxCodeId', v_row."tax_code_id", 'rateBps', v_row."rate_bps", 'validFrom', v_row."valid_from", 'validTo', v_row."valid_to", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."tax_rate_write"(uuid, uuid, integer, date, date) from public, anon, authenticated;

-- Creates or changes a tax code. input: { code, name, type, legalEntityId?,
-- salesAccountId?, purchaseAccountId?, returnBoxes?, archived?, rateBps?,
-- validFrom? }. rateBps adds a rate from validFrom (the epoch for a new code,
-- today for an existing one). Internal: save_tax_code and the import check who
-- may call it.
create or replace function "better_supabase"."tax_code_write"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."tax_codes"%rowtype;
  v_created boolean := false;
  v_type text;
  v_entity uuid;
  v_sales uuid;
  v_purchase uuid;
  v_boxes text[];
  v_rate integer;
  v_from date;
begin
  if jsonb_typeof(tax_code_write.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  if tax_code_write.code_id is not null then
    select * into v_row from "better_supabase"."tax_codes" x
    where x."id" = tax_code_write.code_id and x."tenant_id" = tax_code_write.tenant for update;
    if not found then
      raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(tax_code_write.input ->> 'type', v_row."type");
  if v_type is null or v_type not in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin') then
    raise exception 'a tax code''s type is sales, purchase, exempt, zero, reverse_charge, intra_eu_goods, intra_eu_services, export or margin' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  v_entity := case when tax_code_write.input ? 'legalEntityId'
    then nullif(tax_code_write.input ->> 'legalEntityId', '')::uuid else v_row."legal_entity_id" end;
  v_sales := case when tax_code_write.input ? 'salesAccountId'
    then nullif(tax_code_write.input ->> 'salesAccountId', '')::uuid else v_row."sales_account_id" end;
  v_purchase := case when tax_code_write.input ? 'purchaseAccountId'
    then nullif(tax_code_write.input ->> 'purchaseAccountId', '')::uuid else v_row."purchase_account_id" end;
  if tax_code_write.input ? 'returnBoxes' then
    if jsonb_typeof(tax_code_write.input -> 'returnBoxes') is distinct from 'array' then
      raise exception 'returnBoxes must be a list of box names' using errcode = '22023', hint = 'TAX_CODE_INVALID';
    end if;
    select coalesce(array_agg(trim(b.value) order by b.ordinality), '{}') into v_boxes
    from jsonb_array_elements_text(tax_code_write.input -> 'returnBoxes') with ordinality b;
  else
    v_boxes := coalesce(v_row."return_boxes", '{}');
  end if;
  if v_row."id" is null then
    v_created := true;
    insert into "better_supabase"."tax_codes" ("tenant_id", "legal_entity_id", "code", "name", "type", "sales_account_id", "purchase_account_id", "return_boxes", "archived_at")
    values (tax_code_write.tenant, v_entity, trim(tax_code_write.input ->> 'code'), trim(tax_code_write.input ->> 'name'), v_type, v_sales, v_purchase, v_boxes,
      case when coalesce((tax_code_write.input ->> 'archived')::boolean, false) then now() end)
    returning * into v_row;
  else
    update "better_supabase"."tax_codes" x set
      "legal_entity_id" = v_entity,
      "code" = coalesce(trim(tax_code_write.input ->> 'code'), x."code"),
      "name" = coalesce(trim(tax_code_write.input ->> 'name'), x."name"),
      "type" = v_type,
      "sales_account_id" = v_sales,
      "purchase_account_id" = v_purchase,
      "return_boxes" = v_boxes,
      "archived_at" = case when tax_code_write.input ? 'archived'
        then case when (tax_code_write.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) end
        else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if tax_code_write.input ? 'rateBps' and tax_code_write.input -> 'rateBps' <> 'null'::jsonb then
    v_rate := (tax_code_write.input ->> 'rateBps')::integer;
    v_from := coalesce(nullif(tax_code_write.input ->> 'validFrom', '')::date, case when v_created then date '1970-01-01' else current_date end);
    perform "better_supabase"."tax_rate_write"(tax_code_write.tenant, v_row."id", v_rate, v_from, null);
    select * into v_row from "better_supabase"."tax_codes" x where x."id" = v_row."id";
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'salesAccountId', v_row."sales_account_id", 'purchaseAccountId', v_row."purchase_account_id", 'returnBoxes', to_jsonb(v_row."return_boxes"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = v_row."id"), '[]'::jsonb));
exception
  when check_violation or not_null_violation then
    raise exception 'a tax code has a code of 1 to 50 characters and a name of 1 to 200' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when unique_violation then
    raise exception 'the organization already has a tax code with this code' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'ids must be uuids, rateBps an integer and validFrom a date' using errcode = '22023', hint = 'TAX_CODE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_code_write"(uuid, jsonb, uuid) from public, anon, authenticated;

create or replace function "better_supabase"."save_tax_code"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_code.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_code.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_code_write"(save_tax_code.tenant, save_tax_code.input, save_tax_code.code_id);
end;
$$;
revoke execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_tax_rate"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_rate.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_rate.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax rates' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_rate_write"(save_tax_rate.tenant, save_tax_rate.tax_code, save_tax_rate.rate_bps, save_tax_rate.valid_from, save_tax_rate.valid_to);
end;
$$;
revoke execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) from public, anon;
grant execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) to authenticated, service_role;

-- The organization's tax codes with their rate history. With a legal entity,
-- the codes it can use: its own and the organization's.
create or replace function "better_supabase"."list_tax_codes"(tenant uuid, include_archived boolean default false, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_codes.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'code', x."code", 'name', x."name", 'type', x."type", 'salesAccountId', x."sales_account_id", 'purchaseAccountId', x."purchase_account_id", 'returnBoxes', to_jsonb(x."return_boxes"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = x."id"), '[]'::jsonb)) order by x."code", x."id")
    from "better_supabase"."tax_codes" x
    where x."tenant_id" = list_tax_codes.tenant
      and (coalesce(list_tax_codes.include_archived, false) or x."archived_at" is null)
      and (list_tax_codes.legal_entity is null or x."legal_entity_id" is null or x."legal_entity_id" = list_tax_codes.legal_entity)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) to authenticated, service_role;

-- The import target of the tax_code entity: item.data is the input of
-- save_tax_code, with rateBps and validFrom for the first rate.
create or replace function "better_supabase"."import_tax_code"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_code.item ->> 'tenant')::uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_tax_code.item -> 'data') is distinct from 'object' then
    raise exception 'a tax code item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."tax_code_write"(v_tenant, import_tax_code.item -> 'data', import_tax_code.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
revoke execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) to service_role;

-- When a tax code last changed, for the conflict check of imports.
create or replace function "better_supabase"."tax_code_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."tax_codes" x where x."id"::text = tax_code_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."tax_code_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_code_updated_at"(text) to service_role;

-- The import target of the tax_rate entity: item.data is { taxCodeId or
-- taxCode (the code text), rateBps, validFrom?, validTo? }.
create or replace function "better_supabase"."import_tax_rate"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_rate.item ->> 'tenant')::uuid;
  v_data jsonb := import_tax_rate.item -> 'data';
  v_code uuid;
  v_row jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a tax rate item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_code := coalesce(nullif(v_data ->> 'taxCodeId', '')::uuid, "better_supabase"."resolve_tax_code"(v_tenant, v_data ->> 'taxCode'));
    v_row := "better_supabase"."tax_rate_write"(v_tenant, v_code, (v_data ->> 'rateBps')::integer, nullif(v_data ->> 'validFrom', '')::date, nullif(v_data ->> 'validTo', '')::date);
  exception
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'a tax rate needs a tax code, a rate in basis points and valid dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$$;
revoke execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) to service_role;


-- The tax of lines [{ quantity?, unitAmount, discountBps?, taxCodeId?,
-- taxRateBps?, discountAmount?, unitCost? }] on a day: { groups: [{ taxCodeId, code, type,
-- rateBps, net, tax, gross, discount, showTax }], subtotal, taxTotal, total,
-- discountTotal, showTaxAmount }, amounts as text. A line's rate is its tax
-- code's rate on on_date; taxRateBps stands in when no rate covers the day or
-- the line has no code. It runs as the caller, so a caller only prices lines with
-- the tax codes they can read; compute_document_tax and the invoice issue call it.
create or replace function "better_supabase"."tax_compute_lines"(lines jsonb, on_date date, prices_include_tax boolean, credit_restriction_bps integer, discount_bps integer, discount_amount bigint)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_inclusive boolean := coalesce(tax_compute_lines.prices_include_tax, false);
  v_restriction integer := coalesce(tax_compute_lines.credit_restriction_bps, 0);
  v_on date := coalesce(tax_compute_lines.on_date, current_date);
  v_bps integer := coalesce(tax_compute_lines.discount_bps, 0);
  v_amount bigint := coalesce(tax_compute_lines.discount_amount, 0);
  v_lines jsonb;
  v_groups jsonb;
  v_net bigint;
  v_line_discount bigint;
  v_record_discount bigint;
begin
  if jsonb_typeof(tax_compute_lines.lines) is distinct from 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if v_restriction < 0 or v_restriction > 10000 then
    raise exception 'a credit restriction is 0 to 10000 basis points' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(tax_compute_lines.lines) x where jsonb_typeof(x.value) <> 'object') then
    raise exception 'every line must be an object' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    where x.value ->> 'taxCodeId' is not null
      and not exists (select 1 from "better_supabase"."tax_codes" y where y."id"::text = x.value ->> 'taxCodeId')
  ) then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
    where y."type" = 'margin' and x.value ->> 'unitCost' is null
  ) then
    raise exception 'a margin scheme line needs the unitCost of what it was bought for' using errcode = '22023', hint = 'TAX_MARGIN_COST_REQUIRED';
  end if;
  with src as (
    select x.ordinality as pos,
      coalesce((x.value ->> 'quantity')::numeric, 1) as qty,
      (x.value ->> 'unitAmount')::bigint as unit,
      coalesce((x.value ->> 'discountBps')::integer, 0) as disc_bps,
      coalesce((x.value ->> 'discountAmount')::bigint, 0) as disc_amount,
      coalesce((x.value ->> 'unitCost')::bigint, 0) as unit_cost,
      y."id" as code_id,
      y."code" as code,
      coalesce(y."type", 'sales') as type,
      case
        when y."id" is null then coalesce((x.value ->> 'taxRateBps')::integer, 0)
        when y."type" not in ('sales', 'purchase', 'margin') then 0
        else coalesce("better_supabase"."tax_rate_on"(y."id", v_on), (x.value ->> 'taxRateBps')::integer, -1)
      end as rate
    from jsonb_array_elements(tax_compute_lines.lines) with ordinality x
    left join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
  ), priced as (
    select s.*, round(s.qty * s.unit) as amount from src s
  ), discounted as (
    select p.*, least(p.amount, round(p.amount * p.disc_bps / 10000.0) + p.disc_amount) as disc from priced p
  ), counted as (
    select d.*, d.amount - d.disc as after, round(d.qty * d.unit_cost) as cost from discounted d
  ), taxed as (
    select n.pos, n.rate, n.code_id, n.code, n.type, n.after, n.disc,
      case
        when n.rate <= 0 then 0
        when n.type = 'margin' then round(greatest(n.after - n.cost, 0) * n.rate / (10000.0 + n.rate))
        else round(n.after * (10000 - v_restriction) * n.rate / (10000.0 * (case when v_inclusive then 10000.0 + n.rate else 10000.0 end)))
      end as tax
    from counted n
  )
  select coalesce(jsonb_agg(jsonb_build_object('pos', t.pos, 'rate', t.rate, 'codeId', t.code_id, 'code', t.code, 'type', t.type,
      'after', t.after::bigint, 'disc', t.disc::bigint, 'tax', t.tax::bigint) order by t.pos), '[]'::jsonb)
    into v_lines
  from taxed t;
  if exists (select 1 from jsonb_to_recordset(v_lines) r(rate integer) where r.rate < 0) then
    raise exception 'no rate of a line''s tax code covers the date, and the line gives no taxRateBps' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  select coalesce(sum(r.after), 0), coalesce(sum(r.disc), 0) into v_net, v_line_discount
  from jsonb_to_recordset(v_lines) r(after bigint, disc bigint);
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * v_bps / 10000.0)::bigint + v_amount)
    else 0
  end;
  with grouped as (
    select r.rate, r."codeId" as code_id, r.code, r.type, sum(r.after) as amount, sum(r.tax) as tax
    from jsonb_to_recordset(v_lines) r(rate integer, "codeId" uuid, code text, type text, after bigint, tax bigint)
    group by 1, 2, 3, 4
  ), shared as (
    select g.rate, g.code_id, g.code, g.type, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first, g.code_id nulls first rows between unbounded preceding and current row)
  ), reduced as (
    select s.rate, s.code_id, s.code, s.type, s.share, s.amount - s.share as amount,
      s.tax - case
        when s.rate <= 0 then 0
        when s.type = 'margin' then round(s.share * s.rate / (10000.0 + s.rate))
        else round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end)))
      end as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'taxCodeId', x.code_id,
      'code', x.code,
      'type', x.type,
      'rateBps', x.rate,
      'net', (case when v_inclusive or x.type = 'margin' then x.amount - x.tax else x.amount end)::text,
      'tax', x.tax::text,
      'gross', (case when v_inclusive or x.type = 'margin' then x.amount else x.amount + x.tax end)::text,
      'discount', x.share::text,
      'showTax', x.type <> 'margin'
    ) order by x.rate, x.code nulls first, x.code_id nulls first), '[]'::jsonb)
    into v_groups
  from reduced x;
  return jsonb_build_object(
    'groups', v_groups,
    'subtotal', (select coalesce(sum((g ->> 'net')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'taxTotal', (select coalesce(sum((g ->> 'tax')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'total', (select coalesce(sum((g ->> 'gross')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'discountTotal', (v_line_discount + v_record_discount)::text,
    'showTaxAmount', not exists (select 1 from jsonb_array_elements(v_groups) g where g ->> 'type' = 'margin')
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch then
    raise exception 'quantity, unitAmount, discountBps, unitCost and taxRateBps must be numbers and taxCodeId a uuid' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) from public, anon;
grant execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) to authenticated, service_role;

-- The tax of a document's lines: see tax_compute_lines for the lines and the
-- result. The codes are the caller's (row level security applies).
create or replace function "better_supabase"."compute_document_tax"(lines jsonb, on_date date, prices_include_tax boolean default false, credit_restriction_bps integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."tax_compute_lines"(compute_document_tax.lines, compute_document_tax.on_date, compute_document_tax.prices_include_tax, compute_document_tax.credit_restriction_bps, 0, 0)
$$;
revoke execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) from public, anon;
grant execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) to authenticated, service_role;


-- Prepares the tax return of a period from the tax lines of the issued
-- invoices (not drafts or void ones) dated in it: the totals per return box,
-- what no box takes, the sales and purchase tax, and the EU sales list of
-- intra-EU sales per customer VAT number. A draft return of the same period
-- (and legal entity) is prepared again; a filed one is refused. currency is
-- needed only when invoices of several currencies fall in the period.
create or replace function "better_supabase"."prepare_tax_return"(tenant uuid, since date, until date, legal_entity_id uuid default null, period text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
  v_currencies text[];
  v_currency text;
  v_boxes jsonb;
  v_issues jsonb;
  v_sales bigint;
  v_purchase bigint;
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (prepare_tax_return.tenant is not null and coalesce(better_supabase.can('tenant', prepare_tax_return.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to prepare tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if prepare_tax_return.since is null or prepare_tax_return.until is null or prepare_tax_return.until < prepare_tax_return.since then
    raise exception 'a return needs a period with a start on or before its end' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  if prepare_tax_return.currency is not null and upper(prepare_tax_return.currency) !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three letter code' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  select "better_supabase"."tax_return_source"(prepare_tax_return.tenant, prepare_tax_return.since, prepare_tax_return.until, prepare_tax_return.legal_entity_id) into v_rows;
  select coalesce(array_agg(distinct r.currency order by r.currency), '{}') into v_currencies
  from jsonb_to_recordset(v_rows) r(currency text);
  v_currency := upper(prepare_tax_return.currency);
  if v_currency is null then
    if cardinality(v_currencies) > 1 then
      raise exception 'invoices of several currencies fall in the period; name the currency to prepare the return for' using errcode = '22023', hint = 'TAX_RETURN_CURRENCY_MIXED';
    end if;
    v_currency := v_currencies[1];
  end if;
  select * into v_row from "better_supabase"."tax_returns" y
  where y."tenant_id" = prepare_tax_return.tenant
    and y."legal_entity_id" is not distinct from prepare_tax_return.legal_entity_id
    and y."period_start" = prepare_tax_return.since and y."period_end" = prepare_tax_return.until
  for update;
  if v_row."id" is not null and v_row."status" = 'filed' then
    raise exception 'a filed tax return can''t be prepared again' using errcode = '55000', hint = 'TAX_RETURN_FILED';
  end if;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency
  ), boxed as (
    select b.box, sum(s.sign * s.net) as base, sum(s.sign * s.tax) as tax
    from src s cross join lateral jsonb_array_elements_text(case when jsonb_array_length(s.boxes) = 0 then '[]'::jsonb else s.boxes end) b(box)
    group by b.box
  ), loose as (
    select coalesce(sum(s.sign * s.net), 0) as base, coalesce(sum(s.sign * s.tax), 0) as tax, count(*) as lines
    from src s where jsonb_array_length(s.boxes) = 0
  )
  select jsonb_build_object(
      'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box) from boxed x), '[]'::jsonb),
      'unassigned', (select jsonb_build_object('base', u.base::text, 'tax', u.tax::text, 'lines', u.lines) from loose u)
    ),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'sales'), 0),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'purchase'), 0)
  into v_boxes, v_sales, v_purchase
  from src s;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency and r.direction = 'sales' and r."codeType" in ('intra_eu_goods', 'intra_eu_services')
  )
  select coalesce(jsonb_agg(jsonb_build_object('code', 'EU_SALES_VAT_INVALID', 'invoiceId', s."invoiceId", 'message', 'an intra-EU sale needs the customer''s VAT number, starting with a country code') order by s."invoiceId"), '[]'::jsonb)
  into v_issues
  from src s
  where s.vat is null or upper(s.vat) !~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$';
  v_boxes := v_boxes || jsonb_build_object(
    'salesTax', v_sales::text,
    'purchaseTax', v_purchase::text,
    'netTax', (v_sales - v_purchase)::text,
    'currency', v_currency,
    'issues', v_issues
  );
  if v_row."id" is null then
    insert into "better_supabase"."tax_returns" ("tenant_id", "legal_entity_id", "period", "period_start", "period_end", "currency", "boxes", "prepared_by")
    values (prepare_tax_return.tenant, prepare_tax_return.legal_entity_id,
      coalesce(nullif(trim(prepare_tax_return.period), ''), to_char(prepare_tax_return.since, 'YYYY-MM-DD') || '/' || to_char(prepare_tax_return.until, 'YYYY-MM-DD')),
      prepare_tax_return.since, prepare_tax_return.until, v_currency, v_boxes, (select auth.uid()))
    returning * into v_row;
  else
    delete from "better_supabase"."eu_sales_list_lines" y where y."tax_return_id" = v_row."id";
    update "better_supabase"."tax_returns" y set "period" = coalesce(nullif(trim(prepare_tax_return.period), ''), y."period"),
      "currency" = v_currency, "boxes" = v_boxes, "prepared_by" = (select auth.uid()),
      "prepared_at" = now(), "updated_at" = now()
    where y."id" = v_row."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."eu_sales_list_lines" ("tenant_id", "tax_return_id", "customer_vat_number", "country", "kind", "amount", "currency", "invoice_count")
  select v_row."tenant_id", v_row."id", upper(regexp_replace(s.vat, '[ .-]', '', 'g')), left(upper(s.vat), 2),
    case when s."codeType" = 'intra_eu_goods' then 'goods' else 'services' end,
    sum(s.sign * s.net), v_currency, count(distinct s."invoiceId")::integer
  from jsonb_to_recordset(v_rows) s(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, vat text, net bigint)
  where s.currency is not distinct from v_currency and s.direction = 'sales' and s."codeType" in ('intra_eu_goods', 'intra_eu_services')
    and s.vat is not null and upper(s.vat) ~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$'
  group by 3, 4, 5
  having count(*) > 0;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) to authenticated, service_role;

-- The tax lines of the issued invoices dated in a period, one object per line.
-- Internal: prepare_tax_return reads it.
create or replace function "better_supabase"."tax_return_source"(tenant uuid, since date, until date, legal_entity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select '[]'::jsonb
$$;
revoke execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) to service_role;

-- Files a prepared return: its figures no longer change.
create or replace function "better_supabase"."file_tax_return"(return_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tax_returns" y where y."id" = file_tax_return.return_id for update;
  if v_row."id" is null then
    raise exception 'no such tax return' using errcode = 'P0002', hint = 'TAX_RETURN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tax.manage'), false))) then
    raise exception 'not allowed to file tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if v_row."status" = 'filed' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."tax_returns" y set "status" = 'filed', "filed_at" = now(), "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."file_tax_return"(uuid) from public, anon;
grant execute on function "better_supabase"."file_tax_return"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_tax_returns"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_returns.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_returns.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'period', x."period", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'status', x."status", 'currency', x."currency", 'boxes', x."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = x."id"), '[]'::jsonb), 'preparedBy', x."prepared_by", 'preparedAt', x."prepared_at", 'filedAt', x."filed_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."period_end" desc), '[]'::jsonb)
    from "better_supabase"."tax_returns" x where x."tenant_id" = list_tax_returns.tenant
  );
end;
$$;
revoke execute on function "better_supabase"."list_tax_returns"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_returns"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_select on "better_supabase"."tax_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_update on "better_supabase"."tax_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_select on "better_supabase"."tax_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_update on "better_supabase"."tax_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_select on "better_supabase"."tax_returns" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_returns" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_update on "better_supabase"."tax_returns" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_returns" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block-data tax
-- @bsb-hash sha256:6b65bf14c132fc5ca83f50d742147a433c5580278f63e96348f94a3b922071d7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tax', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block tax@1 managed
-- @bsb-hash sha256:10b47b789ec37d6b13f02ec64e94025591fceceac711a2ecea4af424b4c2f1bb
-- Tax codes per organization and legal entity with a rate history, the tax of a document per code on its date (margin scheme and credit restriction included), invoice tax lines written when an invoice is issued, tax returns with box totals, and the EU sales list per customer VAT number.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Tax per organization and optional legal entity: tax codes with a rate
-- history, the tax of a document computed per code (the margin scheme and a
-- credit restriction included), the tax lines of issued invoices, and the
-- returns and EU sales lists prepared from them.

-- A tax code of an organization, or of one of its legal entities. The code
-- says how a line is taxed; its rates sit in tax_rates, so a rate change keeps
-- the history. The accounts are plain ids that the functions check against the
-- chart of accounts, because accounting is installed after this block.
create table if not exists "better_supabase"."tax_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "code" text not null check (length("code") between 1 and 50),
  "name" text not null check (length("name") between 1 and 200),
  "type" text not null check ("type" in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin')),
  "sales_account_id" uuid,
  "purchase_account_id" uuid,
  -- The boxes of a tax return the code's base and tax count toward.
  "return_boxes" text[] not null default '{}',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "tax_codes_code_key" on "better_supabase"."tax_codes" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "code");
create index if not exists "tax_codes_tenant_idx" on "better_supabase"."tax_codes" ("tenant_id", "code");
alter table "better_supabase"."tax_codes" enable row level security;
revoke all on "better_supabase"."tax_codes" from public, anon, authenticated;
grant select on "better_supabase"."tax_codes" to authenticated;
grant all on "better_supabase"."tax_codes" to service_role;
drop policy if exists tax_codes_read on "better_supabase"."tax_codes";
create policy tax_codes_read on "better_supabase"."tax_codes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- What a code charges from a day until another. valid_to is the last day the
-- rate applies; without one it runs until a later rate starts.
create table if not exists "better_supabase"."tax_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "tax_code_id" uuid not null references "better_supabase"."tax_codes" ("id") on delete cascade,
  -- Basis points: 2100 is 21%.
  "rate_bps" integer not null check ("rate_bps" >= 0 and "rate_bps" <= 100000),
  "valid_from" date not null default date '1970-01-01',
  "valid_to" date,
  "created_at" timestamptz not null default now(),
  check ("valid_to" is null or "valid_to" >= "valid_from")
);
create unique index if not exists "tax_rates_from_key" on "better_supabase"."tax_rates" ("tax_code_id", "valid_from");
alter table "better_supabase"."tax_rates" enable row level security;
revoke all on "better_supabase"."tax_rates" from public, anon, authenticated;
grant select on "better_supabase"."tax_rates" to authenticated;
grant all on "better_supabase"."tax_rates" to service_role;
drop policy if exists tax_rates_read on "better_supabase"."tax_rates";
create policy tax_rates_read on "better_supabase"."tax_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The tax of an issued invoice per rate and tax code, in the shape of
-- quote_tax_lines, written when the invoice is issued. customer_vat_number is
-- the customer's VAT number at that moment; show_tax is false on a margin
-- scheme invoice, which prints no tax amount.
create table if not exists "better_supabase"."invoice_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "tax_code_id" uuid,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0,
  "customer_vat_number" text,
  "show_tax" boolean not null default true
);
create index if not exists "invoice_tax_lines_parent_idx" on "better_supabase"."invoice_tax_lines" ("invoice_id");
create index if not exists "invoice_tax_lines_tenant_code_idx" on "better_supabase"."invoice_tax_lines" ("tenant_id", "tax_code_id");
alter table "better_supabase"."invoice_tax_lines" enable row level security;
revoke all on "better_supabase"."invoice_tax_lines" from public, anon, authenticated;
grant select on "better_supabase"."invoice_tax_lines" to authenticated;
grant all on "better_supabase"."invoice_tax_lines" to service_role;
drop policy if exists invoice_tax_lines_read on "better_supabase"."invoice_tax_lines";
create policy invoice_tax_lines_read on "better_supabase"."invoice_tax_lines"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."invoices" z where z."id" = "invoice_id"));

-- A return of one period, prepared from the issued invoices of that period.
-- boxes holds the totals per return box as decimal text.
create table if not exists "better_supabase"."tax_returns" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "period" text not null check (length("period") between 1 and 50),
  "period_start" date not null,
  "period_end" date not null,
  "status" text not null default 'draft' check ("status" in ('draft', 'filed')),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "boxes" jsonb not null default '{}'::jsonb check (jsonb_typeof("boxes") = 'object'),
  "prepared_by" uuid,
  "prepared_at" timestamptz not null default now(),
  "filed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  check (("status" = 'filed') = ("filed_at" is not null))
);
create unique index if not exists "tax_returns_period_key" on "better_supabase"."tax_returns" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "period_start", "period_end");
alter table "better_supabase"."tax_returns" enable row level security;
revoke all on "better_supabase"."tax_returns" from public, anon, authenticated;
grant select on "better_supabase"."tax_returns" to authenticated;
grant all on "better_supabase"."tax_returns" to service_role;
drop policy if exists tax_returns_read on "better_supabase"."tax_returns";
create policy tax_returns_read on "better_supabase"."tax_returns"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The intra-community sales list (ICP) of a return: what was sold to each
-- customer VAT number, as goods or as services.
create table if not exists "better_supabase"."eu_sales_list_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "tax_return_id" uuid not null references "better_supabase"."tax_returns" ("id") on delete cascade,
  "customer_vat_number" text not null check (length("customer_vat_number") between 4 and 20),
  "country" char(2) not null check ("country" ~ '^[A-Z]{2}$'),
  "kind" text not null check ("kind" in ('goods', 'services')),
  "amount" bigint not null,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_count" integer not null check ("invoice_count" > 0)
);
create unique index if not exists "eu_sales_list_lines_key" on "better_supabase"."eu_sales_list_lines" ("tax_return_id", "customer_vat_number", "kind", "currency");
alter table "better_supabase"."eu_sales_list_lines" enable row level security;
revoke all on "better_supabase"."eu_sales_list_lines" from public, anon, authenticated;
grant select on "better_supabase"."eu_sales_list_lines" to authenticated;
grant all on "better_supabase"."eu_sales_list_lines" to service_role;
drop policy if exists eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines";
create policy eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));


-- The rate a tax code charges on a day, in basis points; null when no rate
-- covers the day. A code that doesn't charge a rate (exempt, zero, reverse
-- charge, intra-EU, export) always gives 0.
create or replace function "better_supabase"."tax_rate_on"(code_id uuid, on_date date)
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when x."type" not in ('sales', 'purchase', 'margin') then 0
    else (
      select y."rate_bps" from "better_supabase"."tax_rates" y
      where y."tax_code_id" = x."id" and y."valid_from" <= tax_rate_on.on_date
        and (y."valid_to" is null or y."valid_to" >= tax_rate_on.on_date)
      order by y."valid_from" desc limit 1
    )
  end
  from "better_supabase"."tax_codes" x where x."id" = tax_rate_on.code_id
$$;
revoke execute on function "better_supabase"."tax_rate_on"(uuid, date) from public, anon;
grant execute on function "better_supabase"."tax_rate_on"(uuid, date) to authenticated, service_role;

-- The tax code a code text names: the legal entity's own code first, then the
-- organization's. Null when there is none.
create or replace function "better_supabase"."resolve_tax_code"(tenant uuid, code text, legal_entity uuid default null)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select x."id" from "better_supabase"."tax_codes" x
  where x."tenant_id" = resolve_tax_code.tenant and x."code" = resolve_tax_code.code
    and x."archived_at" is null
    and (x."legal_entity_id" is null or x."legal_entity_id" = resolve_tax_code.legal_entity)
  order by (x."legal_entity_id" is null), x."id" limit 1
$$;
revoke execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) to authenticated, service_role;

-- Adds a rate to a code from valid_from on. A rate that starts after the
-- code's earlier open rate closes it the day before; without valid_to the rate
-- runs until the next later rate. A rate with the same start is replaced.
-- Internal: save_tax_rate and the import check who may call it.
create or replace function "better_supabase"."tax_rate_write"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code "better_supabase"."tax_codes"%rowtype;
  v_from date := coalesce(tax_rate_write.valid_from, date '1970-01-01');
  v_to date := tax_rate_write.valid_to;
  v_row "better_supabase"."tax_rates"%rowtype;
begin
  select * into v_code from "better_supabase"."tax_codes" x
  where x."id" = tax_rate_write.tax_code and x."tenant_id" = tax_rate_write.tenant for update;
  if not found then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if v_code."type" not in ('sales', 'purchase', 'margin') then
    raise exception 'only a sales, purchase or margin code has a rate' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if tax_rate_write.rate_bps is null or tax_rate_write.rate_bps < 0 or tax_rate_write.rate_bps > 100000 then
    raise exception 'a rate is 0 to 100000 basis points' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is not null and v_to < v_from then
    raise exception 'a rate can''t end before it starts' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is null then
    select min(y."valid_from") - 1 into v_to from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from;
  end if;
  if v_to is not null and exists (
    select 1 from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from and y."valid_from" <= v_to
  ) then
    raise exception 'the rate would overlap a later rate of the code' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  update "better_supabase"."tax_rates" y set "valid_to" = v_from - 1
  where y."tax_code_id" = v_code."id" and y."valid_from" < v_from
    and (y."valid_to" is null or y."valid_to" >= v_from);
  insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps", "valid_from", "valid_to")
  values (tax_rate_write.tenant, v_code."id", tax_rate_write.rate_bps, v_from, v_to)
  on conflict ("tax_code_id", "valid_from") do update
    set "rate_bps" = excluded."rate_bps", "valid_to" = excluded."valid_to"
  returning * into v_row;
  update "better_supabase"."tax_codes" x set "updated_at" = now() where x."id" = v_code."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'taxCodeId', v_row."tax_code_id", 'rateBps', v_row."rate_bps", 'validFrom', v_row."valid_from", 'validTo', v_row."valid_to", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."tax_rate_write"(uuid, uuid, integer, date, date) from public, anon, authenticated;

-- Creates or changes a tax code. input: { code, name, type, legalEntityId?,
-- salesAccountId?, purchaseAccountId?, returnBoxes?, archived?, rateBps?,
-- validFrom? }. rateBps adds a rate from validFrom (the epoch for a new code,
-- today for an existing one). Internal: save_tax_code and the import check who
-- may call it.
create or replace function "better_supabase"."tax_code_write"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."tax_codes"%rowtype;
  v_created boolean := false;
  v_type text;
  v_entity uuid;
  v_sales uuid;
  v_purchase uuid;
  v_boxes text[];
  v_rate integer;
  v_from date;
begin
  if jsonb_typeof(tax_code_write.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  if tax_code_write.code_id is not null then
    select * into v_row from "better_supabase"."tax_codes" x
    where x."id" = tax_code_write.code_id and x."tenant_id" = tax_code_write.tenant for update;
    if not found then
      raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(tax_code_write.input ->> 'type', v_row."type");
  if v_type is null or v_type not in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin') then
    raise exception 'a tax code''s type is sales, purchase, exempt, zero, reverse_charge, intra_eu_goods, intra_eu_services, export or margin' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  v_entity := case when tax_code_write.input ? 'legalEntityId'
    then nullif(tax_code_write.input ->> 'legalEntityId', '')::uuid else v_row."legal_entity_id" end;
  if v_entity is not null and not exists (
    select 1 from "better_supabase"."legal_entities" y
    where y."id" = v_entity and y."tenant_id" = tax_code_write.tenant
  ) then
    raise exception 'a tax code''s legal entity must be a legal entity of the organization' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  v_sales := case when tax_code_write.input ? 'salesAccountId'
    then nullif(tax_code_write.input ->> 'salesAccountId', '')::uuid else v_row."sales_account_id" end;
  if v_sales is not null and not exists (
    select 1 from "better_supabase"."accounting_accounts" y
    where y."id" = v_sales and y."tenant_id" = tax_code_write.tenant
  ) then
    raise exception 'a tax code''s account must be an account of the organization' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  v_purchase := case when tax_code_write.input ? 'purchaseAccountId'
    then nullif(tax_code_write.input ->> 'purchaseAccountId', '')::uuid else v_row."purchase_account_id" end;
  if v_purchase is not null and not exists (
    select 1 from "better_supabase"."accounting_accounts" y
    where y."id" = v_purchase and y."tenant_id" = tax_code_write.tenant
  ) then
    raise exception 'a tax code''s account must be an account of the organization' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  if tax_code_write.input ? 'returnBoxes' then
    if jsonb_typeof(tax_code_write.input -> 'returnBoxes') is distinct from 'array' then
      raise exception 'returnBoxes must be a list of box names' using errcode = '22023', hint = 'TAX_CODE_INVALID';
    end if;
    select coalesce(array_agg(trim(b.value) order by b.ordinality), '{}') into v_boxes
    from jsonb_array_elements_text(tax_code_write.input -> 'returnBoxes') with ordinality b;
  else
    v_boxes := coalesce(v_row."return_boxes", '{}');
  end if;
  if v_row."id" is null then
    v_created := true;
    insert into "better_supabase"."tax_codes" ("tenant_id", "legal_entity_id", "code", "name", "type", "sales_account_id", "purchase_account_id", "return_boxes", "archived_at")
    values (tax_code_write.tenant, v_entity, trim(tax_code_write.input ->> 'code'), trim(tax_code_write.input ->> 'name'), v_type, v_sales, v_purchase, v_boxes,
      case when coalesce((tax_code_write.input ->> 'archived')::boolean, false) then now() end)
    returning * into v_row;
  else
    update "better_supabase"."tax_codes" x set
      "legal_entity_id" = v_entity,
      "code" = coalesce(trim(tax_code_write.input ->> 'code'), x."code"),
      "name" = coalesce(trim(tax_code_write.input ->> 'name'), x."name"),
      "type" = v_type,
      "sales_account_id" = v_sales,
      "purchase_account_id" = v_purchase,
      "return_boxes" = v_boxes,
      "archived_at" = case when tax_code_write.input ? 'archived'
        then case when (tax_code_write.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) end
        else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if tax_code_write.input ? 'rateBps' and tax_code_write.input -> 'rateBps' <> 'null'::jsonb then
    v_rate := (tax_code_write.input ->> 'rateBps')::integer;
    v_from := coalesce(nullif(tax_code_write.input ->> 'validFrom', '')::date, case when v_created then date '1970-01-01' else current_date end);
    perform "better_supabase"."tax_rate_write"(tax_code_write.tenant, v_row."id", v_rate, v_from, null);
    select * into v_row from "better_supabase"."tax_codes" x where x."id" = v_row."id";
  end if;
  if v_created then
    perform "better_supabase".emit_event('tax_code.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'code', v_row."code", 'type', v_row."type", 'legalEntityId', v_row."legal_entity_id"), 'tax-codes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/tax');
  perform better_supabase.audit_event(
    event_type => 'tax_code.created',
    category => 'billing',
    target_type => 'tax_code',
    record_id => v_row."id"::text,
    target_label => v_row."code",
    summary => 'Created a tax code',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'code', v_row."code", 'type', v_row."type", 'legalEntityId', v_row."legal_entity_id")
  );
  else
    perform "better_supabase".emit_event('tax_code.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'code', v_row."code", 'type', v_row."type", 'legalEntityId', v_row."legal_entity_id"), 'tax-codes/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/tax');
  perform better_supabase.audit_event(
    event_type => 'tax_code.updated',
    category => 'billing',
    target_type => 'tax_code',
    record_id => v_row."id"::text,
    target_label => v_row."code",
    summary => 'Changed a tax code',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'code', v_row."code", 'type', v_row."type", 'legalEntityId', v_row."legal_entity_id")
  );
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'salesAccountId', v_row."sales_account_id", 'purchaseAccountId', v_row."purchase_account_id", 'returnBoxes', to_jsonb(v_row."return_boxes"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = v_row."id"), '[]'::jsonb));
exception
  when check_violation or not_null_violation then
    raise exception 'a tax code has a code of 1 to 50 characters and a name of 1 to 200' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when unique_violation then
    raise exception 'the organization already has a tax code with this code' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'ids must be uuids, rateBps an integer and validFrom a date' using errcode = '22023', hint = 'TAX_CODE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_code_write"(uuid, jsonb, uuid) from public, anon, authenticated;

create or replace function "better_supabase"."save_tax_code"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_code.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_code.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_code_write"(save_tax_code.tenant, save_tax_code.input, save_tax_code.code_id);
end;
$$;
revoke execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_tax_rate"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_rate.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_rate.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax rates' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_rate_write"(save_tax_rate.tenant, save_tax_rate.tax_code, save_tax_rate.rate_bps, save_tax_rate.valid_from, save_tax_rate.valid_to);
end;
$$;
revoke execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) from public, anon;
grant execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) to authenticated, service_role;

-- The organization's tax codes with their rate history. With a legal entity,
-- the codes it can use: its own and the organization's.
create or replace function "better_supabase"."list_tax_codes"(tenant uuid, include_archived boolean default false, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_codes.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'code', x."code", 'name', x."name", 'type', x."type", 'salesAccountId', x."sales_account_id", 'purchaseAccountId', x."purchase_account_id", 'returnBoxes', to_jsonb(x."return_boxes"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = x."id"), '[]'::jsonb)) order by x."code", x."id")
    from "better_supabase"."tax_codes" x
    where x."tenant_id" = list_tax_codes.tenant
      and (coalesce(list_tax_codes.include_archived, false) or x."archived_at" is null)
      and (list_tax_codes.legal_entity is null or x."legal_entity_id" is null or x."legal_entity_id" = list_tax_codes.legal_entity)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) to authenticated, service_role;

-- The import target of the tax_code entity: item.data is the input of
-- save_tax_code, with rateBps and validFrom for the first rate.
create or replace function "better_supabase"."import_tax_code"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_code.item ->> 'tenant')::uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_tax_code.item -> 'data') is distinct from 'object' then
    raise exception 'a tax code item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."tax_code_write"(v_tenant, import_tax_code.item -> 'data', import_tax_code.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
revoke execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) to service_role;

-- When a tax code last changed, for the conflict check of imports.
create or replace function "better_supabase"."tax_code_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."tax_codes" x where x."id"::text = tax_code_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."tax_code_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_code_updated_at"(text) to service_role;

-- The import target of the tax_rate entity: item.data is { taxCodeId or
-- taxCode (the code text), rateBps, validFrom?, validTo? }.
create or replace function "better_supabase"."import_tax_rate"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_rate.item ->> 'tenant')::uuid;
  v_data jsonb := import_tax_rate.item -> 'data';
  v_code uuid;
  v_row jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a tax rate item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_code := coalesce(nullif(v_data ->> 'taxCodeId', '')::uuid, "better_supabase"."resolve_tax_code"(v_tenant, v_data ->> 'taxCode'));
    v_row := "better_supabase"."tax_rate_write"(v_tenant, v_code, (v_data ->> 'rateBps')::integer, nullif(v_data ->> 'validFrom', '')::date, nullif(v_data ->> 'validTo', '')::date);
  exception
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'a tax rate needs a tax code, a rate in basis points and valid dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$$;
revoke execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) to service_role;


-- The tax of lines [{ quantity?, unitAmount, discountBps?, taxCodeId?,
-- taxRateBps?, discountAmount?, unitCost? }] on a day: { groups: [{ taxCodeId, code, type,
-- rateBps, net, tax, gross, discount, showTax }], subtotal, taxTotal, total,
-- discountTotal, showTaxAmount }, amounts as text. A line's rate is its tax
-- code's rate on on_date; taxRateBps stands in when no rate covers the day or
-- the line has no code. It runs as the caller, so a caller only prices lines with
-- the tax codes they can read; compute_document_tax and the invoice issue call it.
create or replace function "better_supabase"."tax_compute_lines"(lines jsonb, on_date date, prices_include_tax boolean, credit_restriction_bps integer, discount_bps integer, discount_amount bigint)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_inclusive boolean := coalesce(tax_compute_lines.prices_include_tax, false);
  v_restriction integer := coalesce(tax_compute_lines.credit_restriction_bps, 0);
  v_on date := coalesce(tax_compute_lines.on_date, current_date);
  v_bps integer := coalesce(tax_compute_lines.discount_bps, 0);
  v_amount bigint := coalesce(tax_compute_lines.discount_amount, 0);
  v_lines jsonb;
  v_groups jsonb;
  v_net bigint;
  v_line_discount bigint;
  v_record_discount bigint;
begin
  if jsonb_typeof(tax_compute_lines.lines) is distinct from 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if v_restriction < 0 or v_restriction > 10000 then
    raise exception 'a credit restriction is 0 to 10000 basis points' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(tax_compute_lines.lines) x where jsonb_typeof(x.value) <> 'object') then
    raise exception 'every line must be an object' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    where x.value ->> 'taxCodeId' is not null
      and not exists (select 1 from "better_supabase"."tax_codes" y where y."id"::text = x.value ->> 'taxCodeId')
  ) then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
    where y."type" = 'margin' and x.value ->> 'unitCost' is null
  ) then
    raise exception 'a margin scheme line needs the unitCost of what it was bought for' using errcode = '22023', hint = 'TAX_MARGIN_COST_REQUIRED';
  end if;
  with src as (
    select x.ordinality as pos,
      coalesce((x.value ->> 'quantity')::numeric, 1) as qty,
      (x.value ->> 'unitAmount')::bigint as unit,
      coalesce((x.value ->> 'discountBps')::integer, 0) as disc_bps,
      coalesce((x.value ->> 'discountAmount')::bigint, 0) as disc_amount,
      coalesce((x.value ->> 'unitCost')::bigint, 0) as unit_cost,
      y."id" as code_id,
      y."code" as code,
      coalesce(y."type", 'sales') as type,
      case
        when y."id" is null then coalesce((x.value ->> 'taxRateBps')::integer, 0)
        when y."type" not in ('sales', 'purchase', 'margin') then 0
        else coalesce("better_supabase"."tax_rate_on"(y."id", v_on), (x.value ->> 'taxRateBps')::integer, -1)
      end as rate
    from jsonb_array_elements(tax_compute_lines.lines) with ordinality x
    left join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
  ), priced as (
    select s.*, round(s.qty * s.unit) as amount from src s
  ), discounted as (
    select p.*, least(p.amount, round(p.amount * p.disc_bps / 10000.0) + p.disc_amount) as disc from priced p
  ), counted as (
    select d.*, d.amount - d.disc as after, round(d.qty * d.unit_cost) as cost from discounted d
  ), taxed as (
    select n.pos, n.rate, n.code_id, n.code, n.type, n.after, n.disc,
      case
        when n.rate <= 0 then 0
        when n.type = 'margin' then round(greatest(n.after - n.cost, 0) * n.rate / (10000.0 + n.rate))
        else round(n.after * (10000 - v_restriction) * n.rate / (10000.0 * (case when v_inclusive then 10000.0 + n.rate else 10000.0 end)))
      end as tax
    from counted n
  )
  select coalesce(jsonb_agg(jsonb_build_object('pos', t.pos, 'rate', t.rate, 'codeId', t.code_id, 'code', t.code, 'type', t.type,
      'after', t.after::bigint, 'disc', t.disc::bigint, 'tax', t.tax::bigint) order by t.pos), '[]'::jsonb)
    into v_lines
  from taxed t;
  if exists (select 1 from jsonb_to_recordset(v_lines) r(rate integer) where r.rate < 0) then
    raise exception 'no rate of a line''s tax code covers the date, and the line gives no taxRateBps' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  select coalesce(sum(r.after), 0), coalesce(sum(r.disc), 0) into v_net, v_line_discount
  from jsonb_to_recordset(v_lines) r(after bigint, disc bigint);
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * v_bps / 10000.0)::bigint + v_amount)
    else 0
  end;
  with grouped as (
    select r.rate, r."codeId" as code_id, r.code, r.type, sum(r.after) as amount, sum(r.tax) as tax
    from jsonb_to_recordset(v_lines) r(rate integer, "codeId" uuid, code text, type text, after bigint, tax bigint)
    group by 1, 2, 3, 4
  ), shared as (
    select g.rate, g.code_id, g.code, g.type, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first, g.code_id nulls first rows between unbounded preceding and current row)
  ), reduced as (
    select s.rate, s.code_id, s.code, s.type, s.share, s.amount - s.share as amount,
      s.tax - case
        when s.rate <= 0 then 0
        when s.type = 'margin' then round(s.share * s.rate / (10000.0 + s.rate))
        else round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end)))
      end as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'taxCodeId', x.code_id,
      'code', x.code,
      'type', x.type,
      'rateBps', x.rate,
      'net', (case when v_inclusive or x.type = 'margin' then x.amount - x.tax else x.amount end)::text,
      'tax', x.tax::text,
      'gross', (case when v_inclusive or x.type = 'margin' then x.amount else x.amount + x.tax end)::text,
      'discount', x.share::text,
      'showTax', x.type <> 'margin'
    ) order by x.rate, x.code nulls first, x.code_id nulls first), '[]'::jsonb)
    into v_groups
  from reduced x;
  return jsonb_build_object(
    'groups', v_groups,
    'subtotal', (select coalesce(sum((g ->> 'net')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'taxTotal', (select coalesce(sum((g ->> 'tax')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'total', (select coalesce(sum((g ->> 'gross')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'discountTotal', (v_line_discount + v_record_discount)::text,
    'showTaxAmount', not exists (select 1 from jsonb_array_elements(v_groups) g where g ->> 'type' = 'margin')
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch then
    raise exception 'quantity, unitAmount, discountBps, unitCost and taxRateBps must be numbers and taxCodeId a uuid' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) from public, anon;
grant execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) to authenticated, service_role;

-- The tax of a document's lines: see tax_compute_lines for the lines and the
-- result. The codes are the caller's (row level security applies).
create or replace function "better_supabase"."compute_document_tax"(lines jsonb, on_date date, prices_include_tax boolean default false, credit_restriction_bps integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."tax_compute_lines"(compute_document_tax.lines, compute_document_tax.on_date, compute_document_tax.prices_include_tax, compute_document_tax.credit_restriction_bps, 0, 0)
$$;
revoke execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) from public, anon;
grant execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) to authenticated, service_role;

-- Writes the tax of an invoice per rate and tax code for its issue date, after
-- the lines have taken their tax codes. Internal: issue_invoice calls it.
create or replace function "better_supabase"."issue_invoice_tax"(invoice uuid, on_date date)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inv "better_supabase"."invoices"%rowtype;
  v_result jsonb;
begin
  select * into v_inv from "better_supabase"."invoices" x where x."id" = issue_invoice_tax.invoice;
  if not found then
    return;
  end if;
  -- A line that names a code by text takes the code's id and keeps its rate.
  update "better_supabase"."invoice_lines" x set "tax_code_id" = "better_supabase"."resolve_tax_code"(v_inv."tenant_id", x."tax_code", null::uuid)
  where x."parent_id" = v_inv."id" and x."tax_code_id" is null and x."tax_code" is not null
    and "better_supabase"."resolve_tax_code"(v_inv."tenant_id", x."tax_code", null::uuid) is not null;
  -- A line that names a code by id takes the code's text and its rate on the
  -- issue date; a margin scheme line charges nothing on top of its price.
  update "better_supabase"."invoice_lines" x set
    "tax_code" = y."code",
    "tax_rate_bps" = case when y."type" = 'margin' then 0 else coalesce("better_supabase"."tax_rate_on"(y."id", issue_invoice_tax.on_date), x."tax_rate_bps") end
  from "better_supabase"."tax_codes" y
  where x."parent_id" = v_inv."id" and x."tax_code_id" = y."id";
  select "better_supabase"."tax_compute_lines"(
    coalesce((select jsonb_agg(jsonb_build_object('quantity', x."quantity", 'unitAmount', x."unit_amount"::text, 'discountBps', x."discount_bps", 'discountAmount', x."discount_amount"::text, 'taxRateBps', x."tax_rate_bps", 'taxCodeId', x."tax_code_id", 'unitCost', x."unit_cost"::text) order by x."position") from "better_supabase"."invoice_lines" x
      where x."parent_id" = v_inv."id" and true), '[]'::jsonb),
    issue_invoice_tax.on_date, v_inv."prices_include_tax", coalesce((select z."credit_restriction_bps" from "better_supabase"."payment_terms" z where z."id" = v_inv."payment_terms_id"), 0),
    0, 0)
  into v_result;
  delete from "better_supabase"."invoice_tax_lines" x where x."invoice_id" = v_inv."id";
  insert into "better_supabase"."invoice_tax_lines" ("tenant_id", "invoice_id", "tax_rate_bps", "tax_code", "tax_code_id", "net", "tax", "gross", "discount", "customer_vat_number", "show_tax")
  select v_inv."tenant_id", v_inv."id", g."rateBps", g.code, g."taxCodeId", g.net, g.tax, g.gross, g.discount, (select nullif(trim(z."vat_id"), '') from "better_supabase"."companies" z where z."id"::text = v_inv."company_id"::text), g."showTax"
  from jsonb_to_recordset(v_result -> 'groups') g("rateBps" integer, code text, "taxCodeId" uuid, net bigint, tax bigint, gross bigint, discount bigint, "showTax" boolean);
end;
$$;
revoke execute on function "better_supabase"."issue_invoice_tax"(uuid, date) from public, anon, authenticated;

-- Prepares the tax return of a period from the tax lines of the issued
-- invoices (not drafts or void ones) dated in it: the totals per return box,
-- what no box takes, the sales and purchase tax, and the EU sales list of
-- intra-EU sales per customer VAT number. A draft return of the same period
-- (and legal entity) is prepared again; a filed one is refused. currency is
-- needed only when invoices of several currencies fall in the period.
create or replace function "better_supabase"."prepare_tax_return"(tenant uuid, since date, until date, legal_entity_id uuid default null, period text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
  v_currencies text[];
  v_currency text;
  v_boxes jsonb;
  v_issues jsonb;
  v_sales bigint;
  v_purchase bigint;
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (prepare_tax_return.tenant is not null and coalesce(better_supabase.can('tenant', prepare_tax_return.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to prepare tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if prepare_tax_return.since is null or prepare_tax_return.until is null or prepare_tax_return.until < prepare_tax_return.since then
    raise exception 'a return needs a period with a start on or before its end' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  if prepare_tax_return.currency is not null and upper(prepare_tax_return.currency) !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three letter code' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  select "better_supabase"."tax_return_source"(prepare_tax_return.tenant, prepare_tax_return.since, prepare_tax_return.until, prepare_tax_return.legal_entity_id) into v_rows;
  select coalesce(array_agg(distinct r.currency order by r.currency), '{}') into v_currencies
  from jsonb_to_recordset(v_rows) r(currency text);
  v_currency := upper(prepare_tax_return.currency);
  if v_currency is null then
    if cardinality(v_currencies) > 1 then
      raise exception 'invoices of several currencies fall in the period; name the currency to prepare the return for' using errcode = '22023', hint = 'TAX_RETURN_CURRENCY_MIXED';
    end if;
    v_currency := v_currencies[1];
  end if;
  select * into v_row from "better_supabase"."tax_returns" y
  where y."tenant_id" = prepare_tax_return.tenant
    and y."legal_entity_id" is not distinct from prepare_tax_return.legal_entity_id
    and y."period_start" = prepare_tax_return.since and y."period_end" = prepare_tax_return.until
  for update;
  if v_row."id" is not null and v_row."status" = 'filed' then
    raise exception 'a filed tax return can''t be prepared again' using errcode = '55000', hint = 'TAX_RETURN_FILED';
  end if;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency
  ), boxed as (
    select b.box, sum(s.sign * s.net) as base, sum(s.sign * s.tax) as tax
    from src s cross join lateral jsonb_array_elements_text(case when jsonb_array_length(s.boxes) = 0 then '[]'::jsonb else s.boxes end) b(box)
    group by b.box
  ), loose as (
    select coalesce(sum(s.sign * s.net), 0) as base, coalesce(sum(s.sign * s.tax), 0) as tax, count(*) as lines
    from src s where jsonb_array_length(s.boxes) = 0
  )
  select jsonb_build_object(
      'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box) from boxed x), '[]'::jsonb),
      'unassigned', (select jsonb_build_object('base', u.base::text, 'tax', u.tax::text, 'lines', u.lines) from loose u)
    ),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'sales'), 0),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'purchase'), 0)
  into v_boxes, v_sales, v_purchase
  from src s;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency and r.direction = 'sales' and r."codeType" in ('intra_eu_goods', 'intra_eu_services')
  )
  select coalesce(jsonb_agg(jsonb_build_object('code', 'EU_SALES_VAT_INVALID', 'invoiceId', s."invoiceId", 'message', 'an intra-EU sale needs the customer''s VAT number, starting with a country code') order by s."invoiceId"), '[]'::jsonb)
  into v_issues
  from src s
  where s.vat is null or upper(s.vat) !~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$';
  v_boxes := v_boxes || jsonb_build_object(
    'salesTax', v_sales::text,
    'purchaseTax', v_purchase::text,
    'netTax', (v_sales - v_purchase)::text,
    'currency', v_currency,
    'issues', v_issues
  );
  if v_row."id" is null then
    insert into "better_supabase"."tax_returns" ("tenant_id", "legal_entity_id", "period", "period_start", "period_end", "currency", "boxes", "prepared_by")
    values (prepare_tax_return.tenant, prepare_tax_return.legal_entity_id,
      coalesce(nullif(trim(prepare_tax_return.period), ''), to_char(prepare_tax_return.since, 'YYYY-MM-DD') || '/' || to_char(prepare_tax_return.until, 'YYYY-MM-DD')),
      prepare_tax_return.since, prepare_tax_return.until, v_currency, v_boxes, (select auth.uid()))
    returning * into v_row;
  else
    delete from "better_supabase"."eu_sales_list_lines" y where y."tax_return_id" = v_row."id";
    update "better_supabase"."tax_returns" y set "period" = coalesce(nullif(trim(prepare_tax_return.period), ''), y."period"),
      "currency" = v_currency, "boxes" = v_boxes, "prepared_by" = (select auth.uid()),
      "prepared_at" = now(), "updated_at" = now()
    where y."id" = v_row."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."eu_sales_list_lines" ("tenant_id", "tax_return_id", "customer_vat_number", "country", "kind", "amount", "currency", "invoice_count")
  select v_row."tenant_id", v_row."id", upper(regexp_replace(s.vat, '[ .-]', '', 'g')), left(upper(s.vat), 2),
    case when s."codeType" = 'intra_eu_goods' then 'goods' else 'services' end,
    sum(s.sign * s.net), v_currency, count(distinct s."invoiceId")::integer
  from jsonb_to_recordset(v_rows) s(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, vat text, net bigint)
  where s.currency is not distinct from v_currency and s.direction = 'sales' and s."codeType" in ('intra_eu_goods', 'intra_eu_services')
    and s.vat is not null and upper(s.vat) ~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$'
  group by 3, 4, 5
  having count(*) > 0;
  perform "better_supabase".emit_event('tax_return.prepared', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'legalEntityId', v_row."legal_entity_id", 'netTax', v_row."boxes" ->> 'netTax', 'currency', v_row."currency"), 'tax-returns/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/tax');
  perform better_supabase.audit_event(
    event_type => 'tax_return.prepared',
    category => 'billing',
    target_type => 'tax_return',
    record_id => v_row."id"::text,
    target_label => v_row."period",
    summary => 'Prepared a tax return',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'legalEntityId', v_row."legal_entity_id", 'netTax', v_row."boxes" ->> 'netTax', 'currency', v_row."currency")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) to authenticated, service_role;

-- The tax lines of the issued invoices dated in a period, one object per line.
-- Internal: prepare_tax_return reads it.
create or replace function "better_supabase"."tax_return_source"(tenant uuid, since date, until date, legal_entity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'currency', x."currency", 'sign', case when x."kind"::text = 'credit_note' then -1 else 1 end,
    'direction', coalesce(x."direction"::text, 'sales'), 'invoiceId', x."id", 'codeType', y."type",
    'boxes', coalesce(to_jsonb(y."return_boxes"), '[]'::jsonb), 'net', z."net", 'tax', z."tax",
    'vat', z."customer_vat_number")), '[]'::jsonb)
  from "better_supabase"."invoice_tax_lines" z
  join "better_supabase"."invoices" x on x."id" = z."invoice_id"
  left join "better_supabase"."tax_codes" y on y."id" = z."tax_code_id"
  where z."tenant_id" = tax_return_source.tenant
    and x."status"::text not in ('draft', 'void')
    and x."issued_on" >= tax_return_source.since and x."issued_on" <= tax_return_source.until
    and (tax_return_source.legal_entity_id is null or null::uuid = tax_return_source.legal_entity_id)
$$;
revoke execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) to service_role;

-- Files a prepared return: its figures no longer change.
create or replace function "better_supabase"."file_tax_return"(return_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tax_returns" y where y."id" = file_tax_return.return_id for update;
  if v_row."id" is null then
    raise exception 'no such tax return' using errcode = 'P0002', hint = 'TAX_RETURN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tax.manage'), false))) then
    raise exception 'not allowed to file tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if v_row."status" = 'filed' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."tax_returns" y set "status" = 'filed', "filed_at" = now(), "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."file_tax_return"(uuid) from public, anon;
grant execute on function "better_supabase"."file_tax_return"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_tax_returns"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_returns.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_returns.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'period', x."period", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'status', x."status", 'currency', x."currency", 'boxes', x."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = x."id"), '[]'::jsonb), 'preparedBy', x."prepared_by", 'preparedAt', x."prepared_at", 'filedAt', x."filed_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."period_end" desc), '[]'::jsonb)
    from "better_supabase"."tax_returns" x where x."tenant_id" = list_tax_returns.tenant
  );
end;
$$;
revoke execute on function "better_supabase"."list_tax_returns"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_returns"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_select on "better_supabase"."tax_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_update on "better_supabase"."tax_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_select on "better_supabase"."tax_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_update on "better_supabase"."tax_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."invoices" z where z."id" = "invoice_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_select on "better_supabase"."tax_returns" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_returns" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_update on "better_supabase"."tax_returns" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_returns" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block-data tax
-- @bsb-hash sha256:6b65bf14c132fc5ca83f50d742147a433c5580278f63e96348f94a3b922071d7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tax', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block tax@1 managed
-- @bsb-hash sha256:96aef18c4131181b81eea0ac16575a6e667ec099d0d5f5902afe098b04c9b96c
-- Tax codes per organization and legal entity with a rate history, the tax of a document per code on its date (margin scheme and credit restriction included), invoice tax lines written when an invoice is issued, tax returns with box totals, and the EU sales list per customer VAT number.
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
    drop policy if exists bsb_tenant_scope on "app_private"."tax_codes";
    drop policy if exists bsb_tenant_scope_select on "app_private"."tax_codes";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."tax_codes";
    drop policy if exists bsb_tenant_scope_update on "app_private"."tax_codes";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."tax_codes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."tax_rates";
    drop policy if exists bsb_tenant_scope_select on "app_private"."tax_rates";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."tax_rates";
    drop policy if exists bsb_tenant_scope_update on "app_private"."tax_rates";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."tax_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."invoice_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."tax_returns";
    drop policy if exists bsb_tenant_scope_select on "app_private"."tax_returns";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."tax_returns";
    drop policy if exists bsb_tenant_scope_update on "app_private"."tax_returns";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."tax_returns";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."eu_sales_list_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Tax per organization and optional legal entity: tax codes with a rate
-- history, the tax of a document computed per code (the margin scheme and a
-- credit restriction included), the tax lines of issued invoices, and the
-- returns and EU sales lists prepared from them.

-- A tax code of an organization, or of one of its legal entities. The code
-- says how a line is taxed; its rates sit in tax_rates, so a rate change keeps
-- the history. The accounts are plain ids that the functions check against the
-- chart of accounts, because accounting is installed after this block.
create table if not exists "app_private"."tax_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "code" text not null check (length("code") between 1 and 50),
  "name" text not null check (length("name") between 1 and 200),
  "type" text not null check ("type" in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin')),
  "sales_account_id" uuid,
  "purchase_account_id" uuid,
  -- The boxes of a tax return the code's base and tax count toward.
  "return_boxes" text[] not null default '{}',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "tax_codes_code_key" on "app_private"."tax_codes" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "code");
create index if not exists "tax_codes_tenant_idx" on "app_private"."tax_codes" ("tenant_id", "code");
alter table "app_private"."tax_codes" enable row level security;
revoke all on "app_private"."tax_codes" from public, anon, authenticated;
grant select on "app_private"."tax_codes" to authenticated;
grant all on "app_private"."tax_codes" to service_role;
drop policy if exists tax_codes_read on "app_private"."tax_codes";
create policy tax_codes_read on "app_private"."tax_codes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- What a code charges from a day until another. valid_to is the last day the
-- rate applies; without one it runs until a later rate starts.
create table if not exists "app_private"."tax_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "tax_code_id" uuid not null references "app_private"."tax_codes" ("id") on delete cascade,
  -- Basis points: 2100 is 21%.
  "rate_bps" integer not null check ("rate_bps" >= 0 and "rate_bps" <= 100000),
  "valid_from" date not null default date '1970-01-01',
  "valid_to" date,
  "created_at" timestamptz not null default now(),
  check ("valid_to" is null or "valid_to" >= "valid_from")
);
create unique index if not exists "tax_rates_from_key" on "app_private"."tax_rates" ("tax_code_id", "valid_from");
alter table "app_private"."tax_rates" enable row level security;
revoke all on "app_private"."tax_rates" from public, anon, authenticated;
grant select on "app_private"."tax_rates" to authenticated;
grant all on "app_private"."tax_rates" to service_role;
drop policy if exists tax_rates_read on "app_private"."tax_rates";
create policy tax_rates_read on "app_private"."tax_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The tax of an issued invoice per rate and tax code, in the shape of
-- quote_tax_lines, written when the invoice is issued. customer_vat_number is
-- the customer's VAT number at that moment; show_tax is false on a margin
-- scheme invoice, which prints no tax amount.
create table if not exists "app_private"."invoice_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "invoice_id" uuid not null,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "tax_code_id" uuid,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0,
  "customer_vat_number" text,
  "show_tax" boolean not null default true
);
create index if not exists "invoice_tax_lines_parent_idx" on "app_private"."invoice_tax_lines" ("invoice_id");
create index if not exists "invoice_tax_lines_tenant_code_idx" on "app_private"."invoice_tax_lines" ("tenant_id", "tax_code_id");
alter table "app_private"."invoice_tax_lines" enable row level security;
revoke all on "app_private"."invoice_tax_lines" from public, anon, authenticated;
grant select on "app_private"."invoice_tax_lines" to authenticated;
grant all on "app_private"."invoice_tax_lines" to service_role;
drop policy if exists invoice_tax_lines_read on "app_private"."invoice_tax_lines";
create policy invoice_tax_lines_read on "app_private"."invoice_tax_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- A return of one period, prepared from the issued invoices of that period.
-- boxes holds the totals per return box as decimal text.
create table if not exists "app_private"."tax_returns" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "period" text not null check (length("period") between 1 and 50),
  "period_start" date not null,
  "period_end" date not null,
  "status" text not null default 'draft' check ("status" in ('draft', 'filed')),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "boxes" jsonb not null default '{}'::jsonb check (jsonb_typeof("boxes") = 'object'),
  "prepared_by" uuid,
  "prepared_at" timestamptz not null default now(),
  "filed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  check (("status" = 'filed') = ("filed_at" is not null))
);
create unique index if not exists "tax_returns_period_key" on "app_private"."tax_returns" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "period_start", "period_end");
alter table "app_private"."tax_returns" enable row level security;
revoke all on "app_private"."tax_returns" from public, anon, authenticated;
grant select on "app_private"."tax_returns" to authenticated;
grant all on "app_private"."tax_returns" to service_role;
drop policy if exists tax_returns_read on "app_private"."tax_returns";
create policy tax_returns_read on "app_private"."tax_returns"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The intra-community sales list (ICP) of a return: what was sold to each
-- customer VAT number, as goods or as services.
create table if not exists "app_private"."eu_sales_list_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "tax_return_id" uuid not null references "app_private"."tax_returns" ("id") on delete cascade,
  "customer_vat_number" text not null check (length("customer_vat_number") between 4 and 20),
  "country" char(2) not null check ("country" ~ '^[A-Z]{2}$'),
  "kind" text not null check ("kind" in ('goods', 'services')),
  "amount" bigint not null,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_count" integer not null check ("invoice_count" > 0)
);
create unique index if not exists "eu_sales_list_lines_key" on "app_private"."eu_sales_list_lines" ("tax_return_id", "customer_vat_number", "kind", "currency");
alter table "app_private"."eu_sales_list_lines" enable row level security;
revoke all on "app_private"."eu_sales_list_lines" from public, anon, authenticated;
grant select on "app_private"."eu_sales_list_lines" to authenticated;
grant all on "app_private"."eu_sales_list_lines" to service_role;
drop policy if exists eu_sales_list_lines_read on "app_private"."eu_sales_list_lines";
create policy eu_sales_list_lines_read on "app_private"."eu_sales_list_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));


-- The rate a tax code charges on a day, in basis points; null when no rate
-- covers the day. A code that doesn't charge a rate (exempt, zero, reverse
-- charge, intra-EU, export) always gives 0.
create or replace function "app_private"."tax_rate_on"(code_id uuid, on_date date)
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when x."type" not in ('sales', 'purchase', 'margin') then 0
    else (
      select y."rate_bps" from "app_private"."tax_rates" y
      where y."tax_code_id" = x."id" and y."valid_from" <= tax_rate_on.on_date
        and (y."valid_to" is null or y."valid_to" >= tax_rate_on.on_date)
      order by y."valid_from" desc limit 1
    )
  end
  from "app_private"."tax_codes" x where x."id" = tax_rate_on.code_id
$$;
revoke execute on function "app_private"."tax_rate_on"(uuid, date) from public, anon;
grant execute on function "app_private"."tax_rate_on"(uuid, date) to authenticated, service_role;

-- The tax code a code text names: the legal entity's own code first, then the
-- organization's. Null when there is none.
create or replace function "app_private"."resolve_tax_code"(tenant uuid, code text, legal_entity uuid default null)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select x."id" from "app_private"."tax_codes" x
  where x."tenant_id" = resolve_tax_code.tenant and x."code" = resolve_tax_code.code
    and x."archived_at" is null
    and (x."legal_entity_id" is null or x."legal_entity_id" = resolve_tax_code.legal_entity)
  order by (x."legal_entity_id" is null), x."id" limit 1
$$;
revoke execute on function "app_private"."resolve_tax_code"(uuid, text, uuid) from public, anon;
grant execute on function "app_private"."resolve_tax_code"(uuid, text, uuid) to authenticated, service_role;

-- Adds a rate to a code from valid_from on. A rate that starts after the
-- code's earlier open rate closes it the day before; without valid_to the rate
-- runs until the next later rate. A rate with the same start is replaced.
-- Internal: save_tax_rate and the import check who may call it.
create or replace function "app_private"."tax_rate_write"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code "app_private"."tax_codes"%rowtype;
  v_from date := coalesce(tax_rate_write.valid_from, date '1970-01-01');
  v_to date := tax_rate_write.valid_to;
  v_row "app_private"."tax_rates"%rowtype;
begin
  select * into v_code from "app_private"."tax_codes" x
  where x."id" = tax_rate_write.tax_code and x."tenant_id" = tax_rate_write.tenant for update;
  if not found then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if v_code."type" not in ('sales', 'purchase', 'margin') then
    raise exception 'only a sales, purchase or margin code has a rate' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if tax_rate_write.rate_bps is null or tax_rate_write.rate_bps < 0 or tax_rate_write.rate_bps > 100000 then
    raise exception 'a rate is 0 to 100000 basis points' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is not null and v_to < v_from then
    raise exception 'a rate can''t end before it starts' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is null then
    select min(y."valid_from") - 1 into v_to from "app_private"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from;
  end if;
  if v_to is not null and exists (
    select 1 from "app_private"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from and y."valid_from" <= v_to
  ) then
    raise exception 'the rate would overlap a later rate of the code' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  update "app_private"."tax_rates" y set "valid_to" = v_from - 1
  where y."tax_code_id" = v_code."id" and y."valid_from" < v_from
    and (y."valid_to" is null or y."valid_to" >= v_from);
  insert into "app_private"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps", "valid_from", "valid_to")
  values (tax_rate_write.tenant, v_code."id", tax_rate_write.rate_bps, v_from, v_to)
  on conflict ("tax_code_id", "valid_from") do update
    set "rate_bps" = excluded."rate_bps", "valid_to" = excluded."valid_to"
  returning * into v_row;
  update "app_private"."tax_codes" x set "updated_at" = now() where x."id" = v_code."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'taxCodeId', v_row."tax_code_id", 'rateBps', v_row."rate_bps", 'validFrom', v_row."valid_from", 'validTo', v_row."valid_to", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."tax_rate_write"(uuid, uuid, integer, date, date) from public, anon, authenticated;

-- Creates or changes a tax code. input: { code, name, type, legalEntityId?,
-- salesAccountId?, purchaseAccountId?, returnBoxes?, archived?, rateBps?,
-- validFrom? }. rateBps adds a rate from validFrom (the epoch for a new code,
-- today for an existing one). Internal: save_tax_code and the import check who
-- may call it.
create or replace function "app_private"."tax_code_write"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."tax_codes"%rowtype;
  v_created boolean := false;
  v_type text;
  v_entity uuid;
  v_sales uuid;
  v_purchase uuid;
  v_boxes text[];
  v_rate integer;
  v_from date;
begin
  if jsonb_typeof(tax_code_write.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  if tax_code_write.code_id is not null then
    select * into v_row from "app_private"."tax_codes" x
    where x."id" = tax_code_write.code_id and x."tenant_id" = tax_code_write.tenant for update;
    if not found then
      raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(tax_code_write.input ->> 'type', v_row."type");
  if v_type is null or v_type not in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin') then
    raise exception 'a tax code''s type is sales, purchase, exempt, zero, reverse_charge, intra_eu_goods, intra_eu_services, export or margin' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  v_entity := case when tax_code_write.input ? 'legalEntityId'
    then nullif(tax_code_write.input ->> 'legalEntityId', '')::uuid else v_row."legal_entity_id" end;
  v_sales := case when tax_code_write.input ? 'salesAccountId'
    then nullif(tax_code_write.input ->> 'salesAccountId', '')::uuid else v_row."sales_account_id" end;
  v_purchase := case when tax_code_write.input ? 'purchaseAccountId'
    then nullif(tax_code_write.input ->> 'purchaseAccountId', '')::uuid else v_row."purchase_account_id" end;
  if tax_code_write.input ? 'returnBoxes' then
    if jsonb_typeof(tax_code_write.input -> 'returnBoxes') is distinct from 'array' then
      raise exception 'returnBoxes must be a list of box names' using errcode = '22023', hint = 'TAX_CODE_INVALID';
    end if;
    select coalesce(array_agg(trim(b.value) order by b.ordinality), '{}') into v_boxes
    from jsonb_array_elements_text(tax_code_write.input -> 'returnBoxes') with ordinality b;
  else
    v_boxes := coalesce(v_row."return_boxes", '{}');
  end if;
  if v_row."id" is null then
    v_created := true;
    insert into "app_private"."tax_codes" ("tenant_id", "legal_entity_id", "code", "name", "type", "sales_account_id", "purchase_account_id", "return_boxes", "archived_at")
    values (tax_code_write.tenant, v_entity, trim(tax_code_write.input ->> 'code'), trim(tax_code_write.input ->> 'name'), v_type, v_sales, v_purchase, v_boxes,
      case when coalesce((tax_code_write.input ->> 'archived')::boolean, false) then now() end)
    returning * into v_row;
  else
    update "app_private"."tax_codes" x set
      "legal_entity_id" = v_entity,
      "code" = coalesce(trim(tax_code_write.input ->> 'code'), x."code"),
      "name" = coalesce(trim(tax_code_write.input ->> 'name'), x."name"),
      "type" = v_type,
      "sales_account_id" = v_sales,
      "purchase_account_id" = v_purchase,
      "return_boxes" = v_boxes,
      "archived_at" = case when tax_code_write.input ? 'archived'
        then case when (tax_code_write.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) end
        else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if tax_code_write.input ? 'rateBps' and tax_code_write.input -> 'rateBps' <> 'null'::jsonb then
    v_rate := (tax_code_write.input ->> 'rateBps')::integer;
    v_from := coalesce(nullif(tax_code_write.input ->> 'validFrom', '')::date, case when v_created then date '1970-01-01' else current_date end);
    perform "app_private"."tax_rate_write"(tax_code_write.tenant, v_row."id", v_rate, v_from, null);
    select * into v_row from "app_private"."tax_codes" x where x."id" = v_row."id";
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'salesAccountId', v_row."sales_account_id", 'purchaseAccountId', v_row."purchase_account_id", 'returnBoxes', to_jsonb(v_row."return_boxes"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "app_private"."tax_rates" y where y."tax_code_id" = v_row."id"), '[]'::jsonb));
exception
  when check_violation or not_null_violation then
    raise exception 'a tax code has a code of 1 to 50 characters and a name of 1 to 200' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when unique_violation then
    raise exception 'the organization already has a tax code with this code' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'ids must be uuids, rateBps an integer and validFrom a date' using errcode = '22023', hint = 'TAX_CODE_INVALID';
end;
$$;
revoke execute on function "app_private"."tax_code_write"(uuid, jsonb, uuid) from public, anon, authenticated;

create or replace function "app_private"."save_tax_code"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_code.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_code.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "app_private"."tax_code_write"(save_tax_code.tenant, save_tax_code.input, save_tax_code.code_id);
end;
$$;
revoke execute on function "app_private"."save_tax_code"(uuid, jsonb, uuid) from public, anon;
grant execute on function "app_private"."save_tax_code"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "app_private"."save_tax_rate"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_rate.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_rate.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax rates' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "app_private"."tax_rate_write"(save_tax_rate.tenant, save_tax_rate.tax_code, save_tax_rate.rate_bps, save_tax_rate.valid_from, save_tax_rate.valid_to);
end;
$$;
revoke execute on function "app_private"."save_tax_rate"(uuid, uuid, integer, date, date) from public, anon;
grant execute on function "app_private"."save_tax_rate"(uuid, uuid, integer, date, date) to authenticated, service_role;

-- The organization's tax codes with their rate history. With a legal entity,
-- the codes it can use: its own and the organization's.
create or replace function "app_private"."list_tax_codes"(tenant uuid, include_archived boolean default false, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_codes.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'code', x."code", 'name', x."name", 'type', x."type", 'salesAccountId', x."sales_account_id", 'purchaseAccountId', x."purchase_account_id", 'returnBoxes', to_jsonb(x."return_boxes"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "app_private"."tax_rates" y where y."tax_code_id" = x."id"), '[]'::jsonb)) order by x."code", x."id")
    from "app_private"."tax_codes" x
    where x."tenant_id" = list_tax_codes.tenant
      and (coalesce(list_tax_codes.include_archived, false) or x."archived_at" is null)
      and (list_tax_codes.legal_entity is null or x."legal_entity_id" is null or x."legal_entity_id" = list_tax_codes.legal_entity)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."list_tax_codes"(uuid, boolean, uuid) from public, anon;
grant execute on function "app_private"."list_tax_codes"(uuid, boolean, uuid) to authenticated, service_role;

-- The import target of the tax_code entity: item.data is the input of
-- save_tax_code, with rateBps and validFrom for the first rate.
create or replace function "app_private"."import_tax_code"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_code.item ->> 'tenant')::uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_tax_code.item -> 'data') is distinct from 'object' then
    raise exception 'a tax code item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "app_private"."tax_code_write"(v_tenant, import_tax_code.item -> 'data', import_tax_code.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
revoke execute on function "app_private"."import_tax_code"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "app_private"."import_tax_code"(uuid, jsonb, text) to service_role;

-- When a tax code last changed, for the conflict check of imports.
create or replace function "app_private"."tax_code_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "app_private"."tax_codes" x where x."id"::text = tax_code_updated_at.subject_id
$$;
revoke execute on function "app_private"."tax_code_updated_at"(text) from public, anon, authenticated;
grant execute on function "app_private"."tax_code_updated_at"(text) to service_role;

-- The import target of the tax_rate entity: item.data is { taxCodeId or
-- taxCode (the code text), rateBps, validFrom?, validTo? }.
create or replace function "app_private"."import_tax_rate"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_rate.item ->> 'tenant')::uuid;
  v_data jsonb := import_tax_rate.item -> 'data';
  v_code uuid;
  v_row jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a tax rate item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_code := coalesce(nullif(v_data ->> 'taxCodeId', '')::uuid, "app_private"."resolve_tax_code"(v_tenant, v_data ->> 'taxCode'));
    v_row := "app_private"."tax_rate_write"(v_tenant, v_code, (v_data ->> 'rateBps')::integer, nullif(v_data ->> 'validFrom', '')::date, nullif(v_data ->> 'validTo', '')::date);
  exception
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'a tax rate needs a tax code, a rate in basis points and valid dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$$;
revoke execute on function "app_private"."import_tax_rate"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "app_private"."import_tax_rate"(uuid, jsonb, text) to service_role;


-- The tax of lines [{ quantity?, unitAmount, discountBps?, taxCodeId?,
-- taxRateBps?, discountAmount?, unitCost? }] on a day: { groups: [{ taxCodeId, code, type,
-- rateBps, net, tax, gross, discount, showTax }], subtotal, taxTotal, total,
-- discountTotal, showTaxAmount }, amounts as text. A line's rate is its tax
-- code's rate on on_date; taxRateBps stands in when no rate covers the day or
-- the line has no code. It runs as the caller, so a caller only prices lines with
-- the tax codes they can read; compute_document_tax and the invoice issue call it.
create or replace function "app_private"."tax_compute_lines"(lines jsonb, on_date date, prices_include_tax boolean, credit_restriction_bps integer, discount_bps integer, discount_amount bigint)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_inclusive boolean := coalesce(tax_compute_lines.prices_include_tax, false);
  v_restriction integer := coalesce(tax_compute_lines.credit_restriction_bps, 0);
  v_on date := coalesce(tax_compute_lines.on_date, current_date);
  v_bps integer := coalesce(tax_compute_lines.discount_bps, 0);
  v_amount bigint := coalesce(tax_compute_lines.discount_amount, 0);
  v_lines jsonb;
  v_groups jsonb;
  v_net bigint;
  v_line_discount bigint;
  v_record_discount bigint;
begin
  if jsonb_typeof(tax_compute_lines.lines) is distinct from 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if v_restriction < 0 or v_restriction > 10000 then
    raise exception 'a credit restriction is 0 to 10000 basis points' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(tax_compute_lines.lines) x where jsonb_typeof(x.value) <> 'object') then
    raise exception 'every line must be an object' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    where x.value ->> 'taxCodeId' is not null
      and not exists (select 1 from "app_private"."tax_codes" y where y."id"::text = x.value ->> 'taxCodeId')
  ) then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    join "app_private"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
    where y."type" = 'margin' and x.value ->> 'unitCost' is null
  ) then
    raise exception 'a margin scheme line needs the unitCost of what it was bought for' using errcode = '22023', hint = 'TAX_MARGIN_COST_REQUIRED';
  end if;
  with src as (
    select x.ordinality as pos,
      coalesce((x.value ->> 'quantity')::numeric, 1) as qty,
      (x.value ->> 'unitAmount')::bigint as unit,
      coalesce((x.value ->> 'discountBps')::integer, 0) as disc_bps,
      coalesce((x.value ->> 'discountAmount')::bigint, 0) as disc_amount,
      coalesce((x.value ->> 'unitCost')::bigint, 0) as unit_cost,
      y."id" as code_id,
      y."code" as code,
      coalesce(y."type", 'sales') as type,
      case
        when y."id" is null then coalesce((x.value ->> 'taxRateBps')::integer, 0)
        when y."type" not in ('sales', 'purchase', 'margin') then 0
        else coalesce("app_private"."tax_rate_on"(y."id", v_on), (x.value ->> 'taxRateBps')::integer, -1)
      end as rate
    from jsonb_array_elements(tax_compute_lines.lines) with ordinality x
    left join "app_private"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
  ), priced as (
    select s.*, round(s.qty * s.unit) as amount from src s
  ), discounted as (
    select p.*, least(p.amount, round(p.amount * p.disc_bps / 10000.0) + p.disc_amount) as disc from priced p
  ), counted as (
    select d.*, d.amount - d.disc as after, round(d.qty * d.unit_cost) as cost from discounted d
  ), taxed as (
    select n.pos, n.rate, n.code_id, n.code, n.type, n.after, n.disc,
      case
        when n.rate <= 0 then 0
        when n.type = 'margin' then round(greatest(n.after - n.cost, 0) * n.rate / (10000.0 + n.rate))
        else round(n.after * (10000 - v_restriction) * n.rate / (10000.0 * (case when v_inclusive then 10000.0 + n.rate else 10000.0 end)))
      end as tax
    from counted n
  )
  select coalesce(jsonb_agg(jsonb_build_object('pos', t.pos, 'rate', t.rate, 'codeId', t.code_id, 'code', t.code, 'type', t.type,
      'after', t.after::bigint, 'disc', t.disc::bigint, 'tax', t.tax::bigint) order by t.pos), '[]'::jsonb)
    into v_lines
  from taxed t;
  if exists (select 1 from jsonb_to_recordset(v_lines) r(rate integer) where r.rate < 0) then
    raise exception 'no rate of a line''s tax code covers the date, and the line gives no taxRateBps' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  select coalesce(sum(r.after), 0), coalesce(sum(r.disc), 0) into v_net, v_line_discount
  from jsonb_to_recordset(v_lines) r(after bigint, disc bigint);
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * v_bps / 10000.0)::bigint + v_amount)
    else 0
  end;
  with grouped as (
    select r.rate, r."codeId" as code_id, r.code, r.type, sum(r.after) as amount, sum(r.tax) as tax
    from jsonb_to_recordset(v_lines) r(rate integer, "codeId" uuid, code text, type text, after bigint, tax bigint)
    group by 1, 2, 3, 4
  ), shared as (
    select g.rate, g.code_id, g.code, g.type, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first, g.code_id nulls first rows between unbounded preceding and current row)
  ), reduced as (
    select s.rate, s.code_id, s.code, s.type, s.share, s.amount - s.share as amount,
      s.tax - case
        when s.rate <= 0 then 0
        when s.type = 'margin' then round(s.share * s.rate / (10000.0 + s.rate))
        else round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end)))
      end as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'taxCodeId', x.code_id,
      'code', x.code,
      'type', x.type,
      'rateBps', x.rate,
      'net', (case when v_inclusive or x.type = 'margin' then x.amount - x.tax else x.amount end)::text,
      'tax', x.tax::text,
      'gross', (case when v_inclusive or x.type = 'margin' then x.amount else x.amount + x.tax end)::text,
      'discount', x.share::text,
      'showTax', x.type <> 'margin'
    ) order by x.rate, x.code nulls first, x.code_id nulls first), '[]'::jsonb)
    into v_groups
  from reduced x;
  return jsonb_build_object(
    'groups', v_groups,
    'subtotal', (select coalesce(sum((g ->> 'net')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'taxTotal', (select coalesce(sum((g ->> 'tax')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'total', (select coalesce(sum((g ->> 'gross')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'discountTotal', (v_line_discount + v_record_discount)::text,
    'showTaxAmount', not exists (select 1 from jsonb_array_elements(v_groups) g where g ->> 'type' = 'margin')
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch then
    raise exception 'quantity, unitAmount, discountBps, unitCost and taxRateBps must be numbers and taxCodeId a uuid' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
end;
$$;
revoke execute on function "app_private"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) from public, anon;
grant execute on function "app_private"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) to authenticated, service_role;

-- The tax of a document's lines: see tax_compute_lines for the lines and the
-- result. The codes are the caller's (row level security applies).
create or replace function "app_private"."compute_document_tax"(lines jsonb, on_date date, prices_include_tax boolean default false, credit_restriction_bps integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "app_private"."tax_compute_lines"(compute_document_tax.lines, compute_document_tax.on_date, compute_document_tax.prices_include_tax, compute_document_tax.credit_restriction_bps, 0, 0)
$$;
revoke execute on function "app_private"."compute_document_tax"(jsonb, date, boolean, integer) from public, anon;
grant execute on function "app_private"."compute_document_tax"(jsonb, date, boolean, integer) to authenticated, service_role;


-- Prepares the tax return of a period from the tax lines of the issued
-- invoices (not drafts or void ones) dated in it: the totals per return box,
-- what no box takes, the sales and purchase tax, and the EU sales list of
-- intra-EU sales per customer VAT number. A draft return of the same period
-- (and legal entity) is prepared again; a filed one is refused. currency is
-- needed only when invoices of several currencies fall in the period.
create or replace function "app_private"."prepare_tax_return"(tenant uuid, since date, until date, legal_entity_id uuid default null, period text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
  v_currencies text[];
  v_currency text;
  v_boxes jsonb;
  v_issues jsonb;
  v_sales bigint;
  v_purchase bigint;
  v_row "app_private"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (prepare_tax_return.tenant is not null and coalesce(better_supabase.can('tenant', prepare_tax_return.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to prepare tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if prepare_tax_return.since is null or prepare_tax_return.until is null or prepare_tax_return.until < prepare_tax_return.since then
    raise exception 'a return needs a period with a start on or before its end' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  if prepare_tax_return.currency is not null and upper(prepare_tax_return.currency) !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three letter code' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  select "app_private"."tax_return_source"(prepare_tax_return.tenant, prepare_tax_return.since, prepare_tax_return.until, prepare_tax_return.legal_entity_id) into v_rows;
  select coalesce(array_agg(distinct r.currency order by r.currency), '{}') into v_currencies
  from jsonb_to_recordset(v_rows) r(currency text);
  v_currency := upper(prepare_tax_return.currency);
  if v_currency is null then
    if cardinality(v_currencies) > 1 then
      raise exception 'invoices of several currencies fall in the period; name the currency to prepare the return for' using errcode = '22023', hint = 'TAX_RETURN_CURRENCY_MIXED';
    end if;
    v_currency := v_currencies[1];
  end if;
  select * into v_row from "app_private"."tax_returns" y
  where y."tenant_id" = prepare_tax_return.tenant
    and y."legal_entity_id" is not distinct from prepare_tax_return.legal_entity_id
    and y."period_start" = prepare_tax_return.since and y."period_end" = prepare_tax_return.until
  for update;
  if v_row."id" is not null and v_row."status" = 'filed' then
    raise exception 'a filed tax return can''t be prepared again' using errcode = '55000', hint = 'TAX_RETURN_FILED';
  end if;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency
  ), boxed as (
    select b.box, sum(s.sign * s.net) as base, sum(s.sign * s.tax) as tax
    from src s cross join lateral jsonb_array_elements_text(case when jsonb_array_length(s.boxes) = 0 then '[]'::jsonb else s.boxes end) b(box)
    group by b.box
  ), loose as (
    select coalesce(sum(s.sign * s.net), 0) as base, coalesce(sum(s.sign * s.tax), 0) as tax, count(*) as lines
    from src s where jsonb_array_length(s.boxes) = 0
  )
  select jsonb_build_object(
      'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box) from boxed x), '[]'::jsonb),
      'unassigned', (select jsonb_build_object('base', u.base::text, 'tax', u.tax::text, 'lines', u.lines) from loose u)
    ),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'sales'), 0),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'purchase'), 0)
  into v_boxes, v_sales, v_purchase
  from src s;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency and r.direction = 'sales' and r."codeType" in ('intra_eu_goods', 'intra_eu_services')
  )
  select coalesce(jsonb_agg(jsonb_build_object('code', 'EU_SALES_VAT_INVALID', 'invoiceId', s."invoiceId", 'message', 'an intra-EU sale needs the customer''s VAT number, starting with a country code') order by s."invoiceId"), '[]'::jsonb)
  into v_issues
  from src s
  where s.vat is null or upper(s.vat) !~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$';
  v_boxes := v_boxes || jsonb_build_object(
    'salesTax', v_sales::text,
    'purchaseTax', v_purchase::text,
    'netTax', (v_sales - v_purchase)::text,
    'currency', v_currency,
    'issues', v_issues
  );
  if v_row."id" is null then
    insert into "app_private"."tax_returns" ("tenant_id", "legal_entity_id", "period", "period_start", "period_end", "currency", "boxes", "prepared_by")
    values (prepare_tax_return.tenant, prepare_tax_return.legal_entity_id,
      coalesce(nullif(trim(prepare_tax_return.period), ''), to_char(prepare_tax_return.since, 'YYYY-MM-DD') || '/' || to_char(prepare_tax_return.until, 'YYYY-MM-DD')),
      prepare_tax_return.since, prepare_tax_return.until, v_currency, v_boxes, (select auth.uid()))
    returning * into v_row;
  else
    delete from "app_private"."eu_sales_list_lines" y where y."tax_return_id" = v_row."id";
    update "app_private"."tax_returns" y set "period" = coalesce(nullif(trim(prepare_tax_return.period), ''), y."period"),
      "currency" = v_currency, "boxes" = v_boxes, "prepared_by" = (select auth.uid()),
      "prepared_at" = now(), "updated_at" = now()
    where y."id" = v_row."id"
    returning * into v_row;
  end if;
  insert into "app_private"."eu_sales_list_lines" ("tenant_id", "tax_return_id", "customer_vat_number", "country", "kind", "amount", "currency", "invoice_count")
  select v_row."tenant_id", v_row."id", upper(regexp_replace(s.vat, '[ .-]', '', 'g')), left(upper(s.vat), 2),
    case when s."codeType" = 'intra_eu_goods' then 'goods' else 'services' end,
    sum(s.sign * s.net), v_currency, count(distinct s."invoiceId")::integer
  from jsonb_to_recordset(v_rows) s(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, vat text, net bigint)
  where s.currency is not distinct from v_currency and s.direction = 'sales' and s."codeType" in ('intra_eu_goods', 'intra_eu_services')
    and s.vat is not null and upper(s.vat) ~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$'
  group by 3, 4, 5
  having count(*) > 0;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "app_private"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."prepare_tax_return"(uuid, date, date, uuid, text, text) from public, anon;
grant execute on function "app_private"."prepare_tax_return"(uuid, date, date, uuid, text, text) to authenticated, service_role;

-- The tax lines of the issued invoices dated in a period, one object per line.
-- Internal: prepare_tax_return reads it.
create or replace function "app_private"."tax_return_source"(tenant uuid, since date, until date, legal_entity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select '[]'::jsonb
$$;
revoke execute on function "app_private"."tax_return_source"(uuid, date, date, uuid) from public, anon, authenticated;
grant execute on function "app_private"."tax_return_source"(uuid, date, date, uuid) to service_role;

-- Files a prepared return: its figures no longer change.
create or replace function "app_private"."file_tax_return"(return_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."tax_returns" y where y."id" = file_tax_return.return_id for update;
  if v_row."id" is null then
    raise exception 'no such tax return' using errcode = 'P0002', hint = 'TAX_RETURN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tax.manage'), false))) then
    raise exception 'not allowed to file tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if v_row."status" = 'filed' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "app_private"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "app_private"."tax_returns" y set "status" = 'filed', "filed_at" = now(), "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "app_private"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."file_tax_return"(uuid) from public, anon;
grant execute on function "app_private"."file_tax_return"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_tax_returns"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_returns.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_returns.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'period', x."period", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'status', x."status", 'currency', x."currency", 'boxes', x."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "app_private"."eu_sales_list_lines" z where z."tax_return_id" = x."id"), '[]'::jsonb), 'preparedBy', x."prepared_by", 'preparedAt', x."prepared_at", 'filedAt', x."filed_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."period_end" desc), '[]'::jsonb)
    from "app_private"."tax_returns" x where x."tenant_id" = list_tax_returns.tenant
  );
end;
$$;
revoke execute on function "app_private"."list_tax_returns"(uuid) from public, anon;
grant execute on function "app_private"."list_tax_returns"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."tax_codes";
drop policy if exists bsb_tenant_scope_select on "app_private"."tax_codes";
create policy bsb_tenant_scope_select on "app_private"."tax_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."tax_codes";
create policy bsb_tenant_scope_insert on "app_private"."tax_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."tax_codes";
create policy bsb_tenant_scope_update on "app_private"."tax_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."tax_codes";
create policy bsb_tenant_scope_delete on "app_private"."tax_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."tax_rates";
drop policy if exists bsb_tenant_scope_select on "app_private"."tax_rates";
create policy bsb_tenant_scope_select on "app_private"."tax_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."tax_rates";
create policy bsb_tenant_scope_insert on "app_private"."tax_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."tax_rates";
create policy bsb_tenant_scope_update on "app_private"."tax_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."tax_rates";
create policy bsb_tenant_scope_delete on "app_private"."tax_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."invoice_tax_lines";
drop policy if exists bsb_tenant_scope_select on "app_private"."invoice_tax_lines";
create policy bsb_tenant_scope_select on "app_private"."invoice_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."invoice_tax_lines";
create policy bsb_tenant_scope_insert on "app_private"."invoice_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."invoice_tax_lines";
create policy bsb_tenant_scope_update on "app_private"."invoice_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."invoice_tax_lines";
create policy bsb_tenant_scope_delete on "app_private"."invoice_tax_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."tax_returns";
drop policy if exists bsb_tenant_scope_select on "app_private"."tax_returns";
create policy bsb_tenant_scope_select on "app_private"."tax_returns" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."tax_returns";
create policy bsb_tenant_scope_insert on "app_private"."tax_returns" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."tax_returns";
create policy bsb_tenant_scope_update on "app_private"."tax_returns" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."tax_returns";
create policy bsb_tenant_scope_delete on "app_private"."tax_returns" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."eu_sales_list_lines";
drop policy if exists bsb_tenant_scope_select on "app_private"."eu_sales_list_lines";
create policy bsb_tenant_scope_select on "app_private"."eu_sales_list_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."eu_sales_list_lines";
create policy bsb_tenant_scope_insert on "app_private"."eu_sales_list_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."eu_sales_list_lines";
create policy bsb_tenant_scope_update on "app_private"."eu_sales_list_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."eu_sales_list_lines";
create policy bsb_tenant_scope_delete on "app_private"."eu_sales_list_lines" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block-data tax
-- @bsb-hash sha256:6b65bf14c132fc5ca83f50d742147a433c5580278f63e96348f94a3b922071d7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tax', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block tax@1 managed
-- @bsb-hash sha256:38ee7d0786e24a99f2f77ef203ba4fed50813e179b2abf95d7990f7fcf367dad
-- Tax codes per organization and legal entity with a rate history, the tax of a document per code on its date (margin scheme and credit restriction included), invoice tax lines written when an invoice is issued, tax returns with box totals, and the EU sales list per customer VAT number.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Tax per organization and optional legal entity: tax codes with a rate
-- history, the tax of a document computed per code (the margin scheme and a
-- credit restriction included), the tax lines of issued invoices, and the
-- returns and EU sales lists prepared from them.

-- A tax code of an organization, or of one of its legal entities. The code
-- says how a line is taxed; its rates sit in tax_rates, so a rate change keeps
-- the history. The accounts are plain ids that the functions check against the
-- chart of accounts, because accounting is installed after this block.
create table if not exists "better_supabase"."tax_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "code" text not null check (length("code") between 1 and 50),
  "name" text not null check (length("name") between 1 and 200),
  "type" text not null check ("type" in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin')),
  "sales_account_id" uuid,
  "purchase_account_id" uuid,
  -- The boxes of a tax return the code's base and tax count toward.
  "return_boxes" text[] not null default '{}',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "tax_codes_code_key" on "better_supabase"."tax_codes" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "code");
create index if not exists "tax_codes_tenant_idx" on "better_supabase"."tax_codes" ("tenant_id", "code");
alter table "better_supabase"."tax_codes" enable row level security;
revoke all on "better_supabase"."tax_codes" from public, anon, authenticated;
grant select on "better_supabase"."tax_codes" to authenticated;
grant all on "better_supabase"."tax_codes" to service_role;
drop policy if exists tax_codes_read on "better_supabase"."tax_codes";
create policy tax_codes_read on "better_supabase"."tax_codes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- What a code charges from a day until another. valid_to is the last day the
-- rate applies; without one it runs until a later rate starts.
create table if not exists "better_supabase"."tax_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "tax_code_id" uuid not null references "better_supabase"."tax_codes" ("id") on delete cascade,
  -- Basis points: 2100 is 21%.
  "rate_bps" integer not null check ("rate_bps" >= 0 and "rate_bps" <= 100000),
  "valid_from" date not null default date '1970-01-01',
  "valid_to" date,
  "created_at" timestamptz not null default now(),
  check ("valid_to" is null or "valid_to" >= "valid_from")
);
create unique index if not exists "tax_rates_from_key" on "better_supabase"."tax_rates" ("tax_code_id", "valid_from");
alter table "better_supabase"."tax_rates" enable row level security;
revoke all on "better_supabase"."tax_rates" from public, anon, authenticated;
grant select on "better_supabase"."tax_rates" to authenticated;
grant all on "better_supabase"."tax_rates" to service_role;
drop policy if exists tax_rates_read on "better_supabase"."tax_rates";
create policy tax_rates_read on "better_supabase"."tax_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The tax of an issued invoice per rate and tax code, in the shape of
-- quote_tax_lines, written when the invoice is issued. customer_vat_number is
-- the customer's VAT number at that moment; show_tax is false on a margin
-- scheme invoice, which prints no tax amount.
create table if not exists "better_supabase"."invoice_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "invoice_id" uuid not null,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "tax_code_id" uuid,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0,
  "customer_vat_number" text,
  "show_tax" boolean not null default true
);
create index if not exists "invoice_tax_lines_parent_idx" on "better_supabase"."invoice_tax_lines" ("invoice_id");
create index if not exists "invoice_tax_lines_tenant_code_idx" on "better_supabase"."invoice_tax_lines" ("tenant_id", "tax_code_id");
alter table "better_supabase"."invoice_tax_lines" enable row level security;
revoke all on "better_supabase"."invoice_tax_lines" from public, anon, authenticated;
grant select on "better_supabase"."invoice_tax_lines" to authenticated;
grant all on "better_supabase"."invoice_tax_lines" to service_role;
drop policy if exists invoice_tax_lines_read on "better_supabase"."invoice_tax_lines";
create policy invoice_tax_lines_read on "better_supabase"."invoice_tax_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- A return of one period, prepared from the issued invoices of that period.
-- boxes holds the totals per return box as decimal text.
create table if not exists "better_supabase"."tax_returns" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "legal_entity_id" uuid,
  "period" text not null check (length("period") between 1 and 50),
  "period_start" date not null,
  "period_end" date not null,
  "status" text not null default 'draft' check ("status" in ('draft', 'filed')),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "boxes" jsonb not null default '{}'::jsonb check (jsonb_typeof("boxes") = 'object'),
  "prepared_by" uuid,
  "prepared_at" timestamptz not null default now(),
  "filed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  check (("status" = 'filed') = ("filed_at" is not null))
);
create unique index if not exists "tax_returns_period_key" on "better_supabase"."tax_returns" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "period_start", "period_end");
alter table "better_supabase"."tax_returns" enable row level security;
revoke all on "better_supabase"."tax_returns" from public, anon, authenticated;
grant select on "better_supabase"."tax_returns" to authenticated;
grant all on "better_supabase"."tax_returns" to service_role;
drop policy if exists tax_returns_read on "better_supabase"."tax_returns";
create policy tax_returns_read on "better_supabase"."tax_returns"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The intra-community sales list (ICP) of a return: what was sold to each
-- customer VAT number, as goods or as services.
create table if not exists "better_supabase"."eu_sales_list_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "tax_return_id" uuid not null references "better_supabase"."tax_returns" ("id") on delete cascade,
  "customer_vat_number" text not null check (length("customer_vat_number") between 4 and 20),
  "country" char(2) not null check ("country" ~ '^[A-Z]{2}$'),
  "kind" text not null check ("kind" in ('goods', 'services')),
  "amount" bigint not null,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_count" integer not null check ("invoice_count" > 0)
);
create unique index if not exists "eu_sales_list_lines_key" on "better_supabase"."eu_sales_list_lines" ("tax_return_id", "customer_vat_number", "kind", "currency");
alter table "better_supabase"."eu_sales_list_lines" enable row level security;
revoke all on "better_supabase"."eu_sales_list_lines" from public, anon, authenticated;
grant select on "better_supabase"."eu_sales_list_lines" to authenticated;
grant all on "better_supabase"."eu_sales_list_lines" to service_role;
drop policy if exists eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines";
create policy eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));


-- The rate a tax code charges on a day, in basis points; null when no rate
-- covers the day. A code that doesn't charge a rate (exempt, zero, reverse
-- charge, intra-EU, export) always gives 0.
create or replace function "better_supabase"."tax_rate_on"(code_id uuid, on_date date)
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when x."type" not in ('sales', 'purchase', 'margin') then 0
    else (
      select y."rate_bps" from "better_supabase"."tax_rates" y
      where y."tax_code_id" = x."id" and y."valid_from" <= tax_rate_on.on_date
        and (y."valid_to" is null or y."valid_to" >= tax_rate_on.on_date)
      order by y."valid_from" desc limit 1
    )
  end
  from "better_supabase"."tax_codes" x where x."id" = tax_rate_on.code_id
$$;
revoke execute on function "better_supabase"."tax_rate_on"(uuid, date) from public, anon;
grant execute on function "better_supabase"."tax_rate_on"(uuid, date) to authenticated, service_role;

-- The tax code a code text names: the legal entity's own code first, then the
-- organization's. Null when there is none.
create or replace function "better_supabase"."resolve_tax_code"(tenant uuid, code text, legal_entity uuid default null)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select x."id" from "better_supabase"."tax_codes" x
  where x."tenant_id" = resolve_tax_code.tenant and x."code" = resolve_tax_code.code
    and x."archived_at" is null
    and (x."legal_entity_id" is null or x."legal_entity_id" = resolve_tax_code.legal_entity)
  order by (x."legal_entity_id" is null), x."id" limit 1
$$;
revoke execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) to authenticated, service_role;

-- Adds a rate to a code from valid_from on. A rate that starts after the
-- code's earlier open rate closes it the day before; without valid_to the rate
-- runs until the next later rate. A rate with the same start is replaced.
-- Internal: save_tax_rate and the import check who may call it.
create or replace function "better_supabase"."tax_rate_write"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code "better_supabase"."tax_codes"%rowtype;
  v_from date := coalesce(tax_rate_write.valid_from, date '1970-01-01');
  v_to date := tax_rate_write.valid_to;
  v_row "better_supabase"."tax_rates"%rowtype;
begin
  select * into v_code from "better_supabase"."tax_codes" x
  where x."id" = tax_rate_write.tax_code and x."tenant_id" = tax_rate_write.tenant for update;
  if not found then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if v_code."type" not in ('sales', 'purchase', 'margin') then
    raise exception 'only a sales, purchase or margin code has a rate' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if tax_rate_write.rate_bps is null or tax_rate_write.rate_bps < 0 or tax_rate_write.rate_bps > 100000 then
    raise exception 'a rate is 0 to 100000 basis points' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is not null and v_to < v_from then
    raise exception 'a rate can''t end before it starts' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is null then
    select min(y."valid_from") - 1 into v_to from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from;
  end if;
  if v_to is not null and exists (
    select 1 from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from and y."valid_from" <= v_to
  ) then
    raise exception 'the rate would overlap a later rate of the code' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  update "better_supabase"."tax_rates" y set "valid_to" = v_from - 1
  where y."tax_code_id" = v_code."id" and y."valid_from" < v_from
    and (y."valid_to" is null or y."valid_to" >= v_from);
  insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps", "valid_from", "valid_to")
  values (tax_rate_write.tenant, v_code."id", tax_rate_write.rate_bps, v_from, v_to)
  on conflict ("tax_code_id", "valid_from") do update
    set "rate_bps" = excluded."rate_bps", "valid_to" = excluded."valid_to"
  returning * into v_row;
  update "better_supabase"."tax_codes" x set "updated_at" = now() where x."id" = v_code."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'taxCodeId', v_row."tax_code_id", 'rateBps', v_row."rate_bps", 'validFrom', v_row."valid_from", 'validTo', v_row."valid_to", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."tax_rate_write"(uuid, uuid, integer, date, date) from public, anon, authenticated;

-- Creates or changes a tax code. input: { code, name, type, legalEntityId?,
-- salesAccountId?, purchaseAccountId?, returnBoxes?, archived?, rateBps?,
-- validFrom? }. rateBps adds a rate from validFrom (the epoch for a new code,
-- today for an existing one). Internal: save_tax_code and the import check who
-- may call it.
create or replace function "better_supabase"."tax_code_write"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."tax_codes"%rowtype;
  v_created boolean := false;
  v_type text;
  v_entity uuid;
  v_sales uuid;
  v_purchase uuid;
  v_boxes text[];
  v_rate integer;
  v_from date;
begin
  if jsonb_typeof(tax_code_write.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  if tax_code_write.code_id is not null then
    select * into v_row from "better_supabase"."tax_codes" x
    where x."id" = tax_code_write.code_id and x."tenant_id" = tax_code_write.tenant for update;
    if not found then
      raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(tax_code_write.input ->> 'type', v_row."type");
  if v_type is null or v_type not in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin') then
    raise exception 'a tax code''s type is sales, purchase, exempt, zero, reverse_charge, intra_eu_goods, intra_eu_services, export or margin' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  v_entity := case when tax_code_write.input ? 'legalEntityId'
    then nullif(tax_code_write.input ->> 'legalEntityId', '')::uuid else v_row."legal_entity_id" end;
  v_sales := case when tax_code_write.input ? 'salesAccountId'
    then nullif(tax_code_write.input ->> 'salesAccountId', '')::uuid else v_row."sales_account_id" end;
  v_purchase := case when tax_code_write.input ? 'purchaseAccountId'
    then nullif(tax_code_write.input ->> 'purchaseAccountId', '')::uuid else v_row."purchase_account_id" end;
  if tax_code_write.input ? 'returnBoxes' then
    if jsonb_typeof(tax_code_write.input -> 'returnBoxes') is distinct from 'array' then
      raise exception 'returnBoxes must be a list of box names' using errcode = '22023', hint = 'TAX_CODE_INVALID';
    end if;
    select coalesce(array_agg(trim(b.value) order by b.ordinality), '{}') into v_boxes
    from jsonb_array_elements_text(tax_code_write.input -> 'returnBoxes') with ordinality b;
  else
    v_boxes := coalesce(v_row."return_boxes", '{}');
  end if;
  if v_row."id" is null then
    v_created := true;
    insert into "better_supabase"."tax_codes" ("tenant_id", "legal_entity_id", "code", "name", "type", "sales_account_id", "purchase_account_id", "return_boxes", "archived_at")
    values (tax_code_write.tenant, v_entity, trim(tax_code_write.input ->> 'code'), trim(tax_code_write.input ->> 'name'), v_type, v_sales, v_purchase, v_boxes,
      case when coalesce((tax_code_write.input ->> 'archived')::boolean, false) then now() end)
    returning * into v_row;
  else
    update "better_supabase"."tax_codes" x set
      "legal_entity_id" = v_entity,
      "code" = coalesce(trim(tax_code_write.input ->> 'code'), x."code"),
      "name" = coalesce(trim(tax_code_write.input ->> 'name'), x."name"),
      "type" = v_type,
      "sales_account_id" = v_sales,
      "purchase_account_id" = v_purchase,
      "return_boxes" = v_boxes,
      "archived_at" = case when tax_code_write.input ? 'archived'
        then case when (tax_code_write.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) end
        else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if tax_code_write.input ? 'rateBps' and tax_code_write.input -> 'rateBps' <> 'null'::jsonb then
    v_rate := (tax_code_write.input ->> 'rateBps')::integer;
    v_from := coalesce(nullif(tax_code_write.input ->> 'validFrom', '')::date, case when v_created then date '1970-01-01' else current_date end);
    perform "better_supabase"."tax_rate_write"(tax_code_write.tenant, v_row."id", v_rate, v_from, null);
    select * into v_row from "better_supabase"."tax_codes" x where x."id" = v_row."id";
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'salesAccountId', v_row."sales_account_id", 'purchaseAccountId', v_row."purchase_account_id", 'returnBoxes', to_jsonb(v_row."return_boxes"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = v_row."id"), '[]'::jsonb));
exception
  when check_violation or not_null_violation then
    raise exception 'a tax code has a code of 1 to 50 characters and a name of 1 to 200' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when unique_violation then
    raise exception 'the organization already has a tax code with this code' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'ids must be uuids, rateBps an integer and validFrom a date' using errcode = '22023', hint = 'TAX_CODE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_code_write"(uuid, jsonb, uuid) from public, anon, authenticated;

create or replace function "better_supabase"."save_tax_code"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_code.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_code.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_code_write"(save_tax_code.tenant, save_tax_code.input, save_tax_code.code_id);
end;
$$;
revoke execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_tax_rate"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_rate.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_rate.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax rates' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_rate_write"(save_tax_rate.tenant, save_tax_rate.tax_code, save_tax_rate.rate_bps, save_tax_rate.valid_from, save_tax_rate.valid_to);
end;
$$;
revoke execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) from public, anon;
grant execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) to authenticated, service_role;

-- The organization's tax codes with their rate history. With a legal entity,
-- the codes it can use: its own and the organization's.
create or replace function "better_supabase"."list_tax_codes"(tenant uuid, include_archived boolean default false, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_codes.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'code', x."code", 'name', x."name", 'type', x."type", 'salesAccountId', x."sales_account_id", 'purchaseAccountId', x."purchase_account_id", 'returnBoxes', to_jsonb(x."return_boxes"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = x."id"), '[]'::jsonb)) order by x."code", x."id")
    from "better_supabase"."tax_codes" x
    where x."tenant_id" = list_tax_codes.tenant
      and (coalesce(list_tax_codes.include_archived, false) or x."archived_at" is null)
      and (list_tax_codes.legal_entity is null or x."legal_entity_id" is null or x."legal_entity_id" = list_tax_codes.legal_entity)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) to authenticated, service_role;

-- The import target of the tax_code entity: item.data is the input of
-- save_tax_code, with rateBps and validFrom for the first rate.
create or replace function "better_supabase"."import_tax_code"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_code.item ->> 'tenant')::uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_tax_code.item -> 'data') is distinct from 'object' then
    raise exception 'a tax code item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."tax_code_write"(v_tenant, import_tax_code.item -> 'data', import_tax_code.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
revoke execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) to service_role;

-- When a tax code last changed, for the conflict check of imports.
create or replace function "better_supabase"."tax_code_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."tax_codes" x where x."id"::text = tax_code_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."tax_code_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_code_updated_at"(text) to service_role;

-- The import target of the tax_rate entity: item.data is { taxCodeId or
-- taxCode (the code text), rateBps, validFrom?, validTo? }.
create or replace function "better_supabase"."import_tax_rate"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_rate.item ->> 'tenant')::uuid;
  v_data jsonb := import_tax_rate.item -> 'data';
  v_code uuid;
  v_row jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a tax rate item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_code := coalesce(nullif(v_data ->> 'taxCodeId', '')::uuid, "better_supabase"."resolve_tax_code"(v_tenant, v_data ->> 'taxCode'));
    v_row := "better_supabase"."tax_rate_write"(v_tenant, v_code, (v_data ->> 'rateBps')::integer, nullif(v_data ->> 'validFrom', '')::date, nullif(v_data ->> 'validTo', '')::date);
  exception
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'a tax rate needs a tax code, a rate in basis points and valid dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$$;
revoke execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) to service_role;


-- The tax of lines [{ quantity?, unitAmount, discountBps?, taxCodeId?,
-- taxRateBps?, discountAmount?, unitCost? }] on a day: { groups: [{ taxCodeId, code, type,
-- rateBps, net, tax, gross, discount, showTax }], subtotal, taxTotal, total,
-- discountTotal, showTaxAmount }, amounts as text. A line's rate is its tax
-- code's rate on on_date; taxRateBps stands in when no rate covers the day or
-- the line has no code. It runs as the caller, so a caller only prices lines with
-- the tax codes they can read; compute_document_tax and the invoice issue call it.
create or replace function "better_supabase"."tax_compute_lines"(lines jsonb, on_date date, prices_include_tax boolean, credit_restriction_bps integer, discount_bps integer, discount_amount bigint)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_inclusive boolean := coalesce(tax_compute_lines.prices_include_tax, false);
  v_restriction integer := coalesce(tax_compute_lines.credit_restriction_bps, 0);
  v_on date := coalesce(tax_compute_lines.on_date, current_date);
  v_bps integer := coalesce(tax_compute_lines.discount_bps, 0);
  v_amount bigint := coalesce(tax_compute_lines.discount_amount, 0);
  v_lines jsonb;
  v_groups jsonb;
  v_net bigint;
  v_line_discount bigint;
  v_record_discount bigint;
begin
  if jsonb_typeof(tax_compute_lines.lines) is distinct from 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if v_restriction < 0 or v_restriction > 10000 then
    raise exception 'a credit restriction is 0 to 10000 basis points' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(tax_compute_lines.lines) x where jsonb_typeof(x.value) <> 'object') then
    raise exception 'every line must be an object' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    where x.value ->> 'taxCodeId' is not null
      and not exists (select 1 from "better_supabase"."tax_codes" y where y."id"::text = x.value ->> 'taxCodeId')
  ) then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
    where y."type" = 'margin' and x.value ->> 'unitCost' is null
  ) then
    raise exception 'a margin scheme line needs the unitCost of what it was bought for' using errcode = '22023', hint = 'TAX_MARGIN_COST_REQUIRED';
  end if;
  with src as (
    select x.ordinality as pos,
      coalesce((x.value ->> 'quantity')::numeric, 1) as qty,
      (x.value ->> 'unitAmount')::bigint as unit,
      coalesce((x.value ->> 'discountBps')::integer, 0) as disc_bps,
      coalesce((x.value ->> 'discountAmount')::bigint, 0) as disc_amount,
      coalesce((x.value ->> 'unitCost')::bigint, 0) as unit_cost,
      y."id" as code_id,
      y."code" as code,
      coalesce(y."type", 'sales') as type,
      case
        when y."id" is null then coalesce((x.value ->> 'taxRateBps')::integer, 0)
        when y."type" not in ('sales', 'purchase', 'margin') then 0
        else coalesce("better_supabase"."tax_rate_on"(y."id", v_on), (x.value ->> 'taxRateBps')::integer, -1)
      end as rate
    from jsonb_array_elements(tax_compute_lines.lines) with ordinality x
    left join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
  ), priced as (
    select s.*, round(s.qty * s.unit) as amount from src s
  ), discounted as (
    select p.*, least(p.amount, round(p.amount * p.disc_bps / 10000.0) + p.disc_amount) as disc from priced p
  ), counted as (
    select d.*, d.amount - d.disc as after, round(d.qty * d.unit_cost) as cost from discounted d
  ), taxed as (
    select n.pos, n.rate, n.code_id, n.code, n.type, n.after, n.disc,
      case
        when n.rate <= 0 then 0
        when n.type = 'margin' then round(greatest(n.after - n.cost, 0) * n.rate / (10000.0 + n.rate))
        else round(n.after * (10000 - v_restriction) * n.rate / (10000.0 * (case when v_inclusive then 10000.0 + n.rate else 10000.0 end)))
      end as tax
    from counted n
  )
  select coalesce(jsonb_agg(jsonb_build_object('pos', t.pos, 'rate', t.rate, 'codeId', t.code_id, 'code', t.code, 'type', t.type,
      'after', t.after::bigint, 'disc', t.disc::bigint, 'tax', t.tax::bigint) order by t.pos), '[]'::jsonb)
    into v_lines
  from taxed t;
  if exists (select 1 from jsonb_to_recordset(v_lines) r(rate integer) where r.rate < 0) then
    raise exception 'no rate of a line''s tax code covers the date, and the line gives no taxRateBps' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  select coalesce(sum(r.after), 0), coalesce(sum(r.disc), 0) into v_net, v_line_discount
  from jsonb_to_recordset(v_lines) r(after bigint, disc bigint);
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * v_bps / 10000.0)::bigint + v_amount)
    else 0
  end;
  with grouped as (
    select r.rate, r."codeId" as code_id, r.code, r.type, sum(r.after) as amount, sum(r.tax) as tax
    from jsonb_to_recordset(v_lines) r(rate integer, "codeId" uuid, code text, type text, after bigint, tax bigint)
    group by 1, 2, 3, 4
  ), shared as (
    select g.rate, g.code_id, g.code, g.type, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first, g.code_id nulls first rows between unbounded preceding and current row)
  ), reduced as (
    select s.rate, s.code_id, s.code, s.type, s.share, s.amount - s.share as amount,
      s.tax - case
        when s.rate <= 0 then 0
        when s.type = 'margin' then round(s.share * s.rate / (10000.0 + s.rate))
        else round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end)))
      end as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'taxCodeId', x.code_id,
      'code', x.code,
      'type', x.type,
      'rateBps', x.rate,
      'net', (case when v_inclusive or x.type = 'margin' then x.amount - x.tax else x.amount end)::text,
      'tax', x.tax::text,
      'gross', (case when v_inclusive or x.type = 'margin' then x.amount else x.amount + x.tax end)::text,
      'discount', x.share::text,
      'showTax', x.type <> 'margin'
    ) order by x.rate, x.code nulls first, x.code_id nulls first), '[]'::jsonb)
    into v_groups
  from reduced x;
  return jsonb_build_object(
    'groups', v_groups,
    'subtotal', (select coalesce(sum((g ->> 'net')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'taxTotal', (select coalesce(sum((g ->> 'tax')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'total', (select coalesce(sum((g ->> 'gross')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'discountTotal', (v_line_discount + v_record_discount)::text,
    'showTaxAmount', not exists (select 1 from jsonb_array_elements(v_groups) g where g ->> 'type' = 'margin')
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch then
    raise exception 'quantity, unitAmount, discountBps, unitCost and taxRateBps must be numbers and taxCodeId a uuid' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) from public, anon;
grant execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) to authenticated, service_role;

-- The tax of a document's lines: see tax_compute_lines for the lines and the
-- result. The codes are the caller's (row level security applies).
create or replace function "better_supabase"."compute_document_tax"(lines jsonb, on_date date, prices_include_tax boolean default false, credit_restriction_bps integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."tax_compute_lines"(compute_document_tax.lines, compute_document_tax.on_date, compute_document_tax.prices_include_tax, compute_document_tax.credit_restriction_bps, 0, 0)
$$;
revoke execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) from public, anon;
grant execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) to authenticated, service_role;


-- Prepares the tax return of a period from the tax lines of the issued
-- invoices (not drafts or void ones) dated in it: the totals per return box,
-- what no box takes, the sales and purchase tax, and the EU sales list of
-- intra-EU sales per customer VAT number. A draft return of the same period
-- (and legal entity) is prepared again; a filed one is refused. currency is
-- needed only when invoices of several currencies fall in the period.
create or replace function "better_supabase"."prepare_tax_return"(tenant uuid, since date, until date, legal_entity_id uuid default null, period text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
  v_currencies text[];
  v_currency text;
  v_boxes jsonb;
  v_issues jsonb;
  v_sales bigint;
  v_purchase bigint;
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (prepare_tax_return.tenant is not null and coalesce(better_supabase.can('tenant', prepare_tax_return.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to prepare tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if prepare_tax_return.since is null or prepare_tax_return.until is null or prepare_tax_return.until < prepare_tax_return.since then
    raise exception 'a return needs a period with a start on or before its end' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  if prepare_tax_return.currency is not null and upper(prepare_tax_return.currency) !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three letter code' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  select "better_supabase"."tax_return_source"(prepare_tax_return.tenant, prepare_tax_return.since, prepare_tax_return.until, prepare_tax_return.legal_entity_id) into v_rows;
  select coalesce(array_agg(distinct r.currency order by r.currency), '{}') into v_currencies
  from jsonb_to_recordset(v_rows) r(currency text);
  v_currency := upper(prepare_tax_return.currency);
  if v_currency is null then
    if cardinality(v_currencies) > 1 then
      raise exception 'invoices of several currencies fall in the period; name the currency to prepare the return for' using errcode = '22023', hint = 'TAX_RETURN_CURRENCY_MIXED';
    end if;
    v_currency := v_currencies[1];
  end if;
  select * into v_row from "better_supabase"."tax_returns" y
  where y."tenant_id" = prepare_tax_return.tenant
    and y."legal_entity_id" is not distinct from prepare_tax_return.legal_entity_id
    and y."period_start" = prepare_tax_return.since and y."period_end" = prepare_tax_return.until
  for update;
  if v_row."id" is not null and v_row."status" = 'filed' then
    raise exception 'a filed tax return can''t be prepared again' using errcode = '55000', hint = 'TAX_RETURN_FILED';
  end if;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency
  ), boxed as (
    select b.box, sum(s.sign * s.net) as base, sum(s.sign * s.tax) as tax
    from src s cross join lateral jsonb_array_elements_text(case when jsonb_array_length(s.boxes) = 0 then '[]'::jsonb else s.boxes end) b(box)
    group by b.box
  ), loose as (
    select coalesce(sum(s.sign * s.net), 0) as base, coalesce(sum(s.sign * s.tax), 0) as tax, count(*) as lines
    from src s where jsonb_array_length(s.boxes) = 0
  )
  select jsonb_build_object(
      'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box) from boxed x), '[]'::jsonb),
      'unassigned', (select jsonb_build_object('base', u.base::text, 'tax', u.tax::text, 'lines', u.lines) from loose u)
    ),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'sales'), 0),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'purchase'), 0)
  into v_boxes, v_sales, v_purchase
  from src s;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency and r.direction = 'sales' and r."codeType" in ('intra_eu_goods', 'intra_eu_services')
  )
  select coalesce(jsonb_agg(jsonb_build_object('code', 'EU_SALES_VAT_INVALID', 'invoiceId', s."invoiceId", 'message', 'an intra-EU sale needs the customer''s VAT number, starting with a country code') order by s."invoiceId"), '[]'::jsonb)
  into v_issues
  from src s
  where s.vat is null or upper(s.vat) !~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$';
  v_boxes := v_boxes || jsonb_build_object(
    'salesTax', v_sales::text,
    'purchaseTax', v_purchase::text,
    'netTax', (v_sales - v_purchase)::text,
    'currency', v_currency,
    'issues', v_issues
  );
  if v_row."id" is null then
    insert into "better_supabase"."tax_returns" ("tenant_id", "legal_entity_id", "period", "period_start", "period_end", "currency", "boxes", "prepared_by")
    values (prepare_tax_return.tenant, prepare_tax_return.legal_entity_id,
      coalesce(nullif(trim(prepare_tax_return.period), ''), to_char(prepare_tax_return.since, 'YYYY-MM-DD') || '/' || to_char(prepare_tax_return.until, 'YYYY-MM-DD')),
      prepare_tax_return.since, prepare_tax_return.until, v_currency, v_boxes, (select auth.uid()))
    returning * into v_row;
  else
    delete from "better_supabase"."eu_sales_list_lines" y where y."tax_return_id" = v_row."id";
    update "better_supabase"."tax_returns" y set "period" = coalesce(nullif(trim(prepare_tax_return.period), ''), y."period"),
      "currency" = v_currency, "boxes" = v_boxes, "prepared_by" = (select auth.uid()),
      "prepared_at" = now(), "updated_at" = now()
    where y."id" = v_row."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."eu_sales_list_lines" ("tenant_id", "tax_return_id", "customer_vat_number", "country", "kind", "amount", "currency", "invoice_count")
  select v_row."tenant_id", v_row."id", upper(regexp_replace(s.vat, '[ .-]', '', 'g')), left(upper(s.vat), 2),
    case when s."codeType" = 'intra_eu_goods' then 'goods' else 'services' end,
    sum(s.sign * s.net), v_currency, count(distinct s."invoiceId")::integer
  from jsonb_to_recordset(v_rows) s(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, vat text, net bigint)
  where s.currency is not distinct from v_currency and s.direction = 'sales' and s."codeType" in ('intra_eu_goods', 'intra_eu_services')
    and s.vat is not null and upper(s.vat) ~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$'
  group by 3, 4, 5
  having count(*) > 0;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) to authenticated, service_role;

-- The tax lines of the issued invoices dated in a period, one object per line.
-- Internal: prepare_tax_return reads it.
create or replace function "better_supabase"."tax_return_source"(tenant uuid, since date, until date, legal_entity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select '[]'::jsonb
$$;
revoke execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) to service_role;

-- Files a prepared return: its figures no longer change.
create or replace function "better_supabase"."file_tax_return"(return_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tax_returns" y where y."id" = file_tax_return.return_id for update;
  if v_row."id" is null then
    raise exception 'no such tax return' using errcode = 'P0002', hint = 'TAX_RETURN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tax.manage'), false))) then
    raise exception 'not allowed to file tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if v_row."status" = 'filed' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."tax_returns" y set "status" = 'filed', "filed_at" = now(), "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."file_tax_return"(uuid) from public, anon;
grant execute on function "better_supabase"."file_tax_return"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_tax_returns"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_returns.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_returns.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'period', x."period", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'status', x."status", 'currency', x."currency", 'boxes', x."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = x."id"), '[]'::jsonb), 'preparedBy', x."prepared_by", 'preparedAt', x."prepared_at", 'filedAt', x."filed_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."period_end" desc), '[]'::jsonb)
    from "better_supabase"."tax_returns" x where x."tenant_id" = list_tax_returns.tenant
  );
end;
$$;
revoke execute on function "better_supabase"."list_tax_returns"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_returns"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_select on "better_supabase"."tax_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_update on "better_supabase"."tax_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_select on "better_supabase"."tax_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_update on "better_supabase"."tax_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_select on "better_supabase"."tax_returns" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_returns" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_update on "better_supabase"."tax_returns" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_returns" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.tax.api: entry points for the Data API.
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

create or replace function "api"."tax_rate_on"(code_id uuid, on_date date)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tax_rate_on"($1, $2) $$;
revoke execute on function "api"."tax_rate_on"(uuid, date) from public, anon;
grant execute on function "api"."tax_rate_on"(uuid, date) to authenticated, service_role;

create or replace function "api"."resolve_tax_code"(tenant uuid, code text, legal_entity uuid default null)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."resolve_tax_code"($1, $2, $3) $$;
revoke execute on function "api"."resolve_tax_code"(uuid, text, uuid) from public, anon;
grant execute on function "api"."resolve_tax_code"(uuid, text, uuid) to authenticated, service_role;

create or replace function "api"."save_tax_code"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_tax_code"($1, $2, $3) $$;
revoke execute on function "api"."save_tax_code"(uuid, jsonb, uuid) from public, anon;
grant execute on function "api"."save_tax_code"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "api"."save_tax_rate"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_tax_rate"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."save_tax_rate"(uuid, uuid, integer, date, date) from public, anon;
grant execute on function "api"."save_tax_rate"(uuid, uuid, integer, date, date) to authenticated, service_role;

create or replace function "api"."list_tax_codes"(tenant uuid, include_archived boolean default false, legal_entity uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_tax_codes"($1, $2, $3) $$;
revoke execute on function "api"."list_tax_codes"(uuid, boolean, uuid) from public, anon;
grant execute on function "api"."list_tax_codes"(uuid, boolean, uuid) to authenticated, service_role;

create or replace function "api"."import_tax_code"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_tax_code"($1, $2, $3) $$;
revoke execute on function "api"."import_tax_code"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_tax_code"(uuid, jsonb, text) to service_role;

create or replace function "api"."tax_code_updated_at"(subject_id text)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tax_code_updated_at"($1) $$;
revoke execute on function "api"."tax_code_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."tax_code_updated_at"(text) to service_role;

create or replace function "api"."import_tax_rate"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_tax_rate"($1, $2, $3) $$;
revoke execute on function "api"."import_tax_rate"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_tax_rate"(uuid, jsonb, text) to service_role;

create or replace function "api"."tax_compute_lines"(lines jsonb, on_date date, prices_include_tax boolean, credit_restriction_bps integer, discount_bps integer, discount_amount bigint)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tax_compute_lines"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) from public, anon;
grant execute on function "api"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) to authenticated, service_role;

create or replace function "api"."compute_document_tax"(lines jsonb, on_date date, prices_include_tax boolean default false, credit_restriction_bps integer default 0)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."compute_document_tax"($1, $2, $3, $4) $$;
revoke execute on function "api"."compute_document_tax"(jsonb, date, boolean, integer) from public, anon;
grant execute on function "api"."compute_document_tax"(jsonb, date, boolean, integer) to authenticated, service_role;

create or replace function "api"."prepare_tax_return"(tenant uuid, since date, until date, legal_entity_id uuid default null, period text default null, currency text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."prepare_tax_return"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."prepare_tax_return"(uuid, date, date, uuid, text, text) from public, anon;
grant execute on function "api"."prepare_tax_return"(uuid, date, date, uuid, text, text) to authenticated, service_role;

create or replace function "api"."tax_return_source"(tenant uuid, since date, until date, legal_entity_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tax_return_source"($1, $2, $3, $4) $$;
revoke execute on function "api"."tax_return_source"(uuid, date, date, uuid) from public, anon, authenticated;
grant execute on function "api"."tax_return_source"(uuid, date, date, uuid) to service_role;

create or replace function "api"."file_tax_return"(return_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."file_tax_return"($1) $$;
revoke execute on function "api"."file_tax_return"(uuid) from public, anon;
grant execute on function "api"."file_tax_return"(uuid) to authenticated, service_role;

create or replace function "api"."list_tax_returns"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_tax_returns"($1) $$;
revoke execute on function "api"."list_tax_returns"(uuid) from public, anon;
grant execute on function "api"."list_tax_returns"(uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block-data tax
-- @bsb-hash sha256:6b65bf14c132fc5ca83f50d742147a433c5580278f63e96348f94a3b922071d7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tax', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block tax@1 managed
-- @bsb-hash sha256:6cca0294dac1d3a060ec60d1eefaf1faf558ffad048b9b26001ff573758f0d21
-- Tax codes per organization and legal entity with a rate history, the tax of a document per code on its date (margin scheme and credit restriction included), invoice tax lines written when an invoice is issued, tax returns with box totals, and the EU sales list per customer VAT number.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Tax per organization and optional legal entity: tax codes with a rate
-- history, the tax of a document computed per code (the margin scheme and a
-- credit restriction included), the tax lines of issued invoices, and the
-- returns and EU sales lists prepared from them.

-- A tax code of an organization, or of one of its legal entities. The code
-- says how a line is taxed; its rates sit in tax_rates, so a rate change keeps
-- the history. The accounts are plain ids that the functions check against the
-- chart of accounts, because accounting is installed after this block.
-- better_supabase.tax_codes is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."tax_codes" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."tax_codes" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."tax_codes" add column if not exists "legal_entity_id" uuid;
alter table "better_supabase"."tax_codes" add column if not exists "code" text check (length("code") between 1 and 50);
alter table "better_supabase"."tax_codes" add column if not exists "name" text check (length("name") between 1 and 200);
alter table "better_supabase"."tax_codes" add column if not exists "type" text check ("type" in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin'));
alter table "better_supabase"."tax_codes" add column if not exists "sales_account_id" uuid;
alter table "better_supabase"."tax_codes" add column if not exists "purchase_account_id" uuid;
alter table "better_supabase"."tax_codes" add column if not exists "return_boxes" text[] not null default '{}';
alter table "better_supabase"."tax_codes" add column if not exists "archived_at" timestamptz;
alter table "better_supabase"."tax_codes" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."tax_codes" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_tax_codes_code_key" on "better_supabase"."tax_codes" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "code");
create index if not exists "tax_codes_tenant_idx" on "better_supabase"."tax_codes" ("tenant_id", "code");
alter table "better_supabase"."tax_codes" enable row level security;
grant select on "better_supabase"."tax_codes" to authenticated;
grant all on "better_supabase"."tax_codes" to service_role;
drop policy if exists bsb_tax_codes_read on "better_supabase"."tax_codes";
create policy bsb_tax_codes_read on "better_supabase"."tax_codes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- What a code charges from a day until another. valid_to is the last day the
-- rate applies; without one it runs until a later rate starts.
-- better_supabase.tax_rates is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."tax_rates" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."tax_rates" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."tax_rates" add column if not exists "tax_code_id" uuid references "better_supabase"."tax_codes" ("id") on delete cascade;
alter table "better_supabase"."tax_rates" add column if not exists "rate_bps" integer check ("rate_bps" >= 0 and "rate_bps" <= 100000);
alter table "better_supabase"."tax_rates" add column if not exists "valid_from" date not null default date '1970-01-01';
alter table "better_supabase"."tax_rates" add column if not exists "valid_to" date;
alter table "better_supabase"."tax_rates" add column if not exists "created_at" timestamptz not null default now();
create unique index if not exists "bsb_tax_rates_from_key" on "better_supabase"."tax_rates" ("tax_code_id", "valid_from");
alter table "better_supabase"."tax_rates" enable row level security;
grant select on "better_supabase"."tax_rates" to authenticated;
grant all on "better_supabase"."tax_rates" to service_role;
drop policy if exists bsb_tax_rates_read on "better_supabase"."tax_rates";
create policy bsb_tax_rates_read on "better_supabase"."tax_rates"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The tax of an issued invoice per rate and tax code, in the shape of
-- quote_tax_lines, written when the invoice is issued. customer_vat_number is
-- the customer's VAT number at that moment; show_tax is false on a margin
-- scheme invoice, which prints no tax amount.
-- better_supabase.invoice_tax_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."invoice_tax_lines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."invoice_tax_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "invoice_id" uuid;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "tax_rate_bps" integer;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "tax_code" text;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "tax_code_id" uuid;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "net" bigint;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "tax" bigint;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "gross" bigint;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "discount" bigint not null default 0;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "customer_vat_number" text;
alter table "better_supabase"."invoice_tax_lines" add column if not exists "show_tax" boolean not null default true;
create index if not exists "invoice_tax_lines_parent_idx" on "better_supabase"."invoice_tax_lines" ("invoice_id");
create index if not exists "invoice_tax_lines_tenant_code_idx" on "better_supabase"."invoice_tax_lines" ("tenant_id", "tax_code_id");
alter table "better_supabase"."invoice_tax_lines" enable row level security;
grant select on "better_supabase"."invoice_tax_lines" to authenticated;
grant all on "better_supabase"."invoice_tax_lines" to service_role;
drop policy if exists bsb_invoice_tax_lines_read on "better_supabase"."invoice_tax_lines";
create policy bsb_invoice_tax_lines_read on "better_supabase"."invoice_tax_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- A return of one period, prepared from the issued invoices of that period.
-- boxes holds the totals per return box as decimal text.
-- better_supabase.tax_returns is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."tax_returns" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."tax_returns" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."tax_returns" add column if not exists "legal_entity_id" uuid;
alter table "better_supabase"."tax_returns" add column if not exists "period" text check (length("period") between 1 and 50);
alter table "better_supabase"."tax_returns" add column if not exists "period_start" date;
alter table "better_supabase"."tax_returns" add column if not exists "period_end" date;
alter table "better_supabase"."tax_returns" add column if not exists "status" text not null default 'draft' check ("status" in ('draft', 'filed'));
alter table "better_supabase"."tax_returns" add column if not exists "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."tax_returns" add column if not exists "boxes" jsonb not null default '{}'::jsonb check (jsonb_typeof("boxes") = 'object');
alter table "better_supabase"."tax_returns" add column if not exists "prepared_by" uuid;
alter table "better_supabase"."tax_returns" add column if not exists "prepared_at" timestamptz not null default now();
alter table "better_supabase"."tax_returns" add column if not exists "filed_at" timestamptz;
alter table "better_supabase"."tax_returns" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."tax_returns" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_tax_returns_period_key" on "better_supabase"."tax_returns" ("tenant_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "period_start", "period_end");
alter table "better_supabase"."tax_returns" enable row level security;
grant select on "better_supabase"."tax_returns" to authenticated;
grant all on "better_supabase"."tax_returns" to service_role;
drop policy if exists bsb_tax_returns_read on "better_supabase"."tax_returns";
create policy bsb_tax_returns_read on "better_supabase"."tax_returns"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The intra-community sales list (ICP) of a return: what was sold to each
-- customer VAT number, as goods or as services.
-- better_supabase.eu_sales_list_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."eu_sales_list_lines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."eu_sales_list_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."eu_sales_list_lines" add column if not exists "tax_return_id" uuid references "better_supabase"."tax_returns" ("id") on delete cascade;
alter table "better_supabase"."eu_sales_list_lines" add column if not exists "customer_vat_number" text check (length("customer_vat_number") between 4 and 20);
alter table "better_supabase"."eu_sales_list_lines" add column if not exists "country" char(2) check ("country" ~ '^[A-Z]{2}$');
alter table "better_supabase"."eu_sales_list_lines" add column if not exists "kind" text check ("kind" in ('goods', 'services'));
alter table "better_supabase"."eu_sales_list_lines" add column if not exists "amount" bigint;
alter table "better_supabase"."eu_sales_list_lines" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."eu_sales_list_lines" add column if not exists "invoice_count" integer check ("invoice_count" > 0);
create unique index if not exists "bsb_eu_sales_list_lines_key" on "better_supabase"."eu_sales_list_lines" ("tax_return_id", "customer_vat_number", "kind", "currency");
alter table "better_supabase"."eu_sales_list_lines" enable row level security;
grant select on "better_supabase"."eu_sales_list_lines" to authenticated;
grant all on "better_supabase"."eu_sales_list_lines" to service_role;
drop policy if exists bsb_eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines";
create policy bsb_eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')));


-- The rate a tax code charges on a day, in basis points; null when no rate
-- covers the day. A code that doesn't charge a rate (exempt, zero, reverse
-- charge, intra-EU, export) always gives 0.
create or replace function "better_supabase"."tax_rate_on"(code_id uuid, on_date date)
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when x."type" not in ('sales', 'purchase', 'margin') then 0
    else (
      select y."rate_bps" from "better_supabase"."tax_rates" y
      where y."tax_code_id" = x."id" and y."valid_from" <= tax_rate_on.on_date
        and (y."valid_to" is null or y."valid_to" >= tax_rate_on.on_date)
      order by y."valid_from" desc limit 1
    )
  end
  from "better_supabase"."tax_codes" x where x."id" = tax_rate_on.code_id
$$;
revoke execute on function "better_supabase"."tax_rate_on"(uuid, date) from public, anon;
grant execute on function "better_supabase"."tax_rate_on"(uuid, date) to authenticated, service_role;

-- The tax code a code text names: the legal entity's own code first, then the
-- organization's. Null when there is none.
create or replace function "better_supabase"."resolve_tax_code"(tenant uuid, code text, legal_entity uuid default null)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select x."id" from "better_supabase"."tax_codes" x
  where x."tenant_id" = resolve_tax_code.tenant and x."code" = resolve_tax_code.code
    and x."archived_at" is null
    and (x."legal_entity_id" is null or x."legal_entity_id" = resolve_tax_code.legal_entity)
  order by (x."legal_entity_id" is null), x."id" limit 1
$$;
revoke execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) to authenticated, service_role;

-- Adds a rate to a code from valid_from on. A rate that starts after the
-- code's earlier open rate closes it the day before; without valid_to the rate
-- runs until the next later rate. A rate with the same start is replaced.
-- Internal: save_tax_rate and the import check who may call it.
create or replace function "better_supabase"."tax_rate_write"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code "better_supabase"."tax_codes"%rowtype;
  v_from date := coalesce(tax_rate_write.valid_from, date '1970-01-01');
  v_to date := tax_rate_write.valid_to;
  v_row "better_supabase"."tax_rates"%rowtype;
begin
  select * into v_code from "better_supabase"."tax_codes" x
  where x."id" = tax_rate_write.tax_code and x."tenant_id" = tax_rate_write.tenant for update;
  if not found then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if v_code."type" not in ('sales', 'purchase', 'margin') then
    raise exception 'only a sales, purchase or margin code has a rate' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if tax_rate_write.rate_bps is null or tax_rate_write.rate_bps < 0 or tax_rate_write.rate_bps > 100000 then
    raise exception 'a rate is 0 to 100000 basis points' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is not null and v_to < v_from then
    raise exception 'a rate can''t end before it starts' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is null then
    select min(y."valid_from") - 1 into v_to from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from;
  end if;
  if v_to is not null and exists (
    select 1 from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from and y."valid_from" <= v_to
  ) then
    raise exception 'the rate would overlap a later rate of the code' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  update "better_supabase"."tax_rates" y set "valid_to" = v_from - 1
  where y."tax_code_id" = v_code."id" and y."valid_from" < v_from
    and (y."valid_to" is null or y."valid_to" >= v_from);
  insert into "better_supabase"."tax_rates" ("tenant_id", "tax_code_id", "rate_bps", "valid_from", "valid_to")
  values (tax_rate_write.tenant, v_code."id", tax_rate_write.rate_bps, v_from, v_to)
  on conflict ("tax_code_id", "valid_from") do update
    set "rate_bps" = excluded."rate_bps", "valid_to" = excluded."valid_to"
  returning * into v_row;
  update "better_supabase"."tax_codes" x set "updated_at" = now() where x."id" = v_code."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'taxCodeId', v_row."tax_code_id", 'rateBps', v_row."rate_bps", 'validFrom', v_row."valid_from", 'validTo', v_row."valid_to", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."tax_rate_write"(uuid, uuid, integer, date, date) from public, anon, authenticated;

-- Creates or changes a tax code. input: { code, name, type, legalEntityId?,
-- salesAccountId?, purchaseAccountId?, returnBoxes?, archived?, rateBps?,
-- validFrom? }. rateBps adds a rate from validFrom (the epoch for a new code,
-- today for an existing one). Internal: save_tax_code and the import check who
-- may call it.
create or replace function "better_supabase"."tax_code_write"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."tax_codes"%rowtype;
  v_created boolean := false;
  v_type text;
  v_entity uuid;
  v_sales uuid;
  v_purchase uuid;
  v_boxes text[];
  v_rate integer;
  v_from date;
begin
  if jsonb_typeof(tax_code_write.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  if tax_code_write.code_id is not null then
    select * into v_row from "better_supabase"."tax_codes" x
    where x."id" = tax_code_write.code_id and x."tenant_id" = tax_code_write.tenant for update;
    if not found then
      raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(tax_code_write.input ->> 'type', v_row."type");
  if v_type is null or v_type not in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin') then
    raise exception 'a tax code''s type is sales, purchase, exempt, zero, reverse_charge, intra_eu_goods, intra_eu_services, export or margin' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  v_entity := case when tax_code_write.input ? 'legalEntityId'
    then nullif(tax_code_write.input ->> 'legalEntityId', '')::uuid else v_row."legal_entity_id" end;
  v_sales := case when tax_code_write.input ? 'salesAccountId'
    then nullif(tax_code_write.input ->> 'salesAccountId', '')::uuid else v_row."sales_account_id" end;
  v_purchase := case when tax_code_write.input ? 'purchaseAccountId'
    then nullif(tax_code_write.input ->> 'purchaseAccountId', '')::uuid else v_row."purchase_account_id" end;
  if tax_code_write.input ? 'returnBoxes' then
    if jsonb_typeof(tax_code_write.input -> 'returnBoxes') is distinct from 'array' then
      raise exception 'returnBoxes must be a list of box names' using errcode = '22023', hint = 'TAX_CODE_INVALID';
    end if;
    select coalesce(array_agg(trim(b.value) order by b.ordinality), '{}') into v_boxes
    from jsonb_array_elements_text(tax_code_write.input -> 'returnBoxes') with ordinality b;
  else
    v_boxes := coalesce(v_row."return_boxes", '{}');
  end if;
  if v_row."id" is null then
    v_created := true;
    insert into "better_supabase"."tax_codes" ("tenant_id", "legal_entity_id", "code", "name", "type", "sales_account_id", "purchase_account_id", "return_boxes", "archived_at")
    values (tax_code_write.tenant, v_entity, trim(tax_code_write.input ->> 'code'), trim(tax_code_write.input ->> 'name'), v_type, v_sales, v_purchase, v_boxes,
      case when coalesce((tax_code_write.input ->> 'archived')::boolean, false) then now() end)
    returning * into v_row;
  else
    update "better_supabase"."tax_codes" x set
      "legal_entity_id" = v_entity,
      "code" = coalesce(trim(tax_code_write.input ->> 'code'), x."code"),
      "name" = coalesce(trim(tax_code_write.input ->> 'name'), x."name"),
      "type" = v_type,
      "sales_account_id" = v_sales,
      "purchase_account_id" = v_purchase,
      "return_boxes" = v_boxes,
      "archived_at" = case when tax_code_write.input ? 'archived'
        then case when (tax_code_write.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) end
        else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if tax_code_write.input ? 'rateBps' and tax_code_write.input -> 'rateBps' <> 'null'::jsonb then
    v_rate := (tax_code_write.input ->> 'rateBps')::integer;
    v_from := coalesce(nullif(tax_code_write.input ->> 'validFrom', '')::date, case when v_created then date '1970-01-01' else current_date end);
    perform "better_supabase"."tax_rate_write"(tax_code_write.tenant, v_row."id", v_rate, v_from, null);
    select * into v_row from "better_supabase"."tax_codes" x where x."id" = v_row."id";
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'salesAccountId', v_row."sales_account_id", 'purchaseAccountId', v_row."purchase_account_id", 'returnBoxes', to_jsonb(v_row."return_boxes"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = v_row."id"), '[]'::jsonb));
exception
  when check_violation or not_null_violation then
    raise exception 'a tax code has a code of 1 to 50 characters and a name of 1 to 200' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when unique_violation then
    raise exception 'the organization already has a tax code with this code' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'ids must be uuids, rateBps an integer and validFrom a date' using errcode = '22023', hint = 'TAX_CODE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_code_write"(uuid, jsonb, uuid) from public, anon, authenticated;

create or replace function "better_supabase"."save_tax_code"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_code.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_code.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_code_write"(save_tax_code.tenant, save_tax_code.input, save_tax_code.code_id);
end;
$$;
revoke execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_tax_rate"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_rate.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_rate.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax rates' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_rate_write"(save_tax_rate.tenant, save_tax_rate.tax_code, save_tax_rate.rate_bps, save_tax_rate.valid_from, save_tax_rate.valid_to);
end;
$$;
revoke execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) from public, anon;
grant execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) to authenticated, service_role;

-- The organization's tax codes with their rate history. With a legal entity,
-- the codes it can use: its own and the organization's.
create or replace function "better_supabase"."list_tax_codes"(tenant uuid, include_archived boolean default false, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_codes.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'code', x."code", 'name', x."name", 'type', x."type", 'salesAccountId', x."sales_account_id", 'purchaseAccountId', x."purchase_account_id", 'returnBoxes', to_jsonb(x."return_boxes"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = x."id"), '[]'::jsonb)) order by x."code", x."id")
    from "better_supabase"."tax_codes" x
    where x."tenant_id" = list_tax_codes.tenant
      and (coalesce(list_tax_codes.include_archived, false) or x."archived_at" is null)
      and (list_tax_codes.legal_entity is null or x."legal_entity_id" is null or x."legal_entity_id" = list_tax_codes.legal_entity)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) to authenticated, service_role;

-- The import target of the tax_code entity: item.data is the input of
-- save_tax_code, with rateBps and validFrom for the first rate.
create or replace function "better_supabase"."import_tax_code"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_code.item ->> 'tenant')::uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_tax_code.item -> 'data') is distinct from 'object' then
    raise exception 'a tax code item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."tax_code_write"(v_tenant, import_tax_code.item -> 'data', import_tax_code.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
revoke execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) to service_role;

-- When a tax code last changed, for the conflict check of imports.
create or replace function "better_supabase"."tax_code_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."tax_codes" x where x."id"::text = tax_code_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."tax_code_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_code_updated_at"(text) to service_role;

-- The import target of the tax_rate entity: item.data is { taxCodeId or
-- taxCode (the code text), rateBps, validFrom?, validTo? }.
create or replace function "better_supabase"."import_tax_rate"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_rate.item ->> 'tenant')::uuid;
  v_data jsonb := import_tax_rate.item -> 'data';
  v_code uuid;
  v_row jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a tax rate item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_code := coalesce(nullif(v_data ->> 'taxCodeId', '')::uuid, "better_supabase"."resolve_tax_code"(v_tenant, v_data ->> 'taxCode'));
    v_row := "better_supabase"."tax_rate_write"(v_tenant, v_code, (v_data ->> 'rateBps')::integer, nullif(v_data ->> 'validFrom', '')::date, nullif(v_data ->> 'validTo', '')::date);
  exception
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'a tax rate needs a tax code, a rate in basis points and valid dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$$;
revoke execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) to service_role;


-- The tax of lines [{ quantity?, unitAmount, discountBps?, taxCodeId?,
-- taxRateBps?, discountAmount?, unitCost? }] on a day: { groups: [{ taxCodeId, code, type,
-- rateBps, net, tax, gross, discount, showTax }], subtotal, taxTotal, total,
-- discountTotal, showTaxAmount }, amounts as text. A line's rate is its tax
-- code's rate on on_date; taxRateBps stands in when no rate covers the day or
-- the line has no code. It runs as the caller, so a caller only prices lines with
-- the tax codes they can read; compute_document_tax and the invoice issue call it.
create or replace function "better_supabase"."tax_compute_lines"(lines jsonb, on_date date, prices_include_tax boolean, credit_restriction_bps integer, discount_bps integer, discount_amount bigint)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_inclusive boolean := coalesce(tax_compute_lines.prices_include_tax, false);
  v_restriction integer := coalesce(tax_compute_lines.credit_restriction_bps, 0);
  v_on date := coalesce(tax_compute_lines.on_date, current_date);
  v_bps integer := coalesce(tax_compute_lines.discount_bps, 0);
  v_amount bigint := coalesce(tax_compute_lines.discount_amount, 0);
  v_lines jsonb;
  v_groups jsonb;
  v_net bigint;
  v_line_discount bigint;
  v_record_discount bigint;
begin
  if jsonb_typeof(tax_compute_lines.lines) is distinct from 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if v_restriction < 0 or v_restriction > 10000 then
    raise exception 'a credit restriction is 0 to 10000 basis points' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(tax_compute_lines.lines) x where jsonb_typeof(x.value) <> 'object') then
    raise exception 'every line must be an object' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    where x.value ->> 'taxCodeId' is not null
      and not exists (select 1 from "better_supabase"."tax_codes" y where y."id"::text = x.value ->> 'taxCodeId')
  ) then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
    where y."type" = 'margin' and x.value ->> 'unitCost' is null
  ) then
    raise exception 'a margin scheme line needs the unitCost of what it was bought for' using errcode = '22023', hint = 'TAX_MARGIN_COST_REQUIRED';
  end if;
  with src as (
    select x.ordinality as pos,
      coalesce((x.value ->> 'quantity')::numeric, 1) as qty,
      (x.value ->> 'unitAmount')::bigint as unit,
      coalesce((x.value ->> 'discountBps')::integer, 0) as disc_bps,
      coalesce((x.value ->> 'discountAmount')::bigint, 0) as disc_amount,
      coalesce((x.value ->> 'unitCost')::bigint, 0) as unit_cost,
      y."id" as code_id,
      y."code" as code,
      coalesce(y."type", 'sales') as type,
      case
        when y."id" is null then coalesce((x.value ->> 'taxRateBps')::integer, 0)
        when y."type" not in ('sales', 'purchase', 'margin') then 0
        else coalesce("better_supabase"."tax_rate_on"(y."id", v_on), (x.value ->> 'taxRateBps')::integer, -1)
      end as rate
    from jsonb_array_elements(tax_compute_lines.lines) with ordinality x
    left join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
  ), priced as (
    select s.*, round(s.qty * s.unit) as amount from src s
  ), discounted as (
    select p.*, least(p.amount, round(p.amount * p.disc_bps / 10000.0) + p.disc_amount) as disc from priced p
  ), counted as (
    select d.*, d.amount - d.disc as after, round(d.qty * d.unit_cost) as cost from discounted d
  ), taxed as (
    select n.pos, n.rate, n.code_id, n.code, n.type, n.after, n.disc,
      case
        when n.rate <= 0 then 0
        when n.type = 'margin' then round(greatest(n.after - n.cost, 0) * n.rate / (10000.0 + n.rate))
        else round(n.after * (10000 - v_restriction) * n.rate / (10000.0 * (case when v_inclusive then 10000.0 + n.rate else 10000.0 end)))
      end as tax
    from counted n
  )
  select coalesce(jsonb_agg(jsonb_build_object('pos', t.pos, 'rate', t.rate, 'codeId', t.code_id, 'code', t.code, 'type', t.type,
      'after', t.after::bigint, 'disc', t.disc::bigint, 'tax', t.tax::bigint) order by t.pos), '[]'::jsonb)
    into v_lines
  from taxed t;
  if exists (select 1 from jsonb_to_recordset(v_lines) r(rate integer) where r.rate < 0) then
    raise exception 'no rate of a line''s tax code covers the date, and the line gives no taxRateBps' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  select coalesce(sum(r.after), 0), coalesce(sum(r.disc), 0) into v_net, v_line_discount
  from jsonb_to_recordset(v_lines) r(after bigint, disc bigint);
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * v_bps / 10000.0)::bigint + v_amount)
    else 0
  end;
  with grouped as (
    select r.rate, r."codeId" as code_id, r.code, r.type, sum(r.after) as amount, sum(r.tax) as tax
    from jsonb_to_recordset(v_lines) r(rate integer, "codeId" uuid, code text, type text, after bigint, tax bigint)
    group by 1, 2, 3, 4
  ), shared as (
    select g.rate, g.code_id, g.code, g.type, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first, g.code_id nulls first rows between unbounded preceding and current row)
  ), reduced as (
    select s.rate, s.code_id, s.code, s.type, s.share, s.amount - s.share as amount,
      s.tax - case
        when s.rate <= 0 then 0
        when s.type = 'margin' then round(s.share * s.rate / (10000.0 + s.rate))
        else round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end)))
      end as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'taxCodeId', x.code_id,
      'code', x.code,
      'type', x.type,
      'rateBps', x.rate,
      'net', (case when v_inclusive or x.type = 'margin' then x.amount - x.tax else x.amount end)::text,
      'tax', x.tax::text,
      'gross', (case when v_inclusive or x.type = 'margin' then x.amount else x.amount + x.tax end)::text,
      'discount', x.share::text,
      'showTax', x.type <> 'margin'
    ) order by x.rate, x.code nulls first, x.code_id nulls first), '[]'::jsonb)
    into v_groups
  from reduced x;
  return jsonb_build_object(
    'groups', v_groups,
    'subtotal', (select coalesce(sum((g ->> 'net')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'taxTotal', (select coalesce(sum((g ->> 'tax')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'total', (select coalesce(sum((g ->> 'gross')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'discountTotal', (v_line_discount + v_record_discount)::text,
    'showTaxAmount', not exists (select 1 from jsonb_array_elements(v_groups) g where g ->> 'type' = 'margin')
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch then
    raise exception 'quantity, unitAmount, discountBps, unitCost and taxRateBps must be numbers and taxCodeId a uuid' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) from public, anon;
grant execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) to authenticated, service_role;

-- The tax of a document's lines: see tax_compute_lines for the lines and the
-- result. The codes are the caller's (row level security applies).
create or replace function "better_supabase"."compute_document_tax"(lines jsonb, on_date date, prices_include_tax boolean default false, credit_restriction_bps integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."tax_compute_lines"(compute_document_tax.lines, compute_document_tax.on_date, compute_document_tax.prices_include_tax, compute_document_tax.credit_restriction_bps, 0, 0)
$$;
revoke execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) from public, anon;
grant execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) to authenticated, service_role;


-- Prepares the tax return of a period from the tax lines of the issued
-- invoices (not drafts or void ones) dated in it: the totals per return box,
-- what no box takes, the sales and purchase tax, and the EU sales list of
-- intra-EU sales per customer VAT number. A draft return of the same period
-- (and legal entity) is prepared again; a filed one is refused. currency is
-- needed only when invoices of several currencies fall in the period.
create or replace function "better_supabase"."prepare_tax_return"(tenant uuid, since date, until date, legal_entity_id uuid default null, period text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
  v_currencies text[];
  v_currency text;
  v_boxes jsonb;
  v_issues jsonb;
  v_sales bigint;
  v_purchase bigint;
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (prepare_tax_return.tenant is not null and coalesce(better_supabase.can('tenant', prepare_tax_return.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to prepare tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if prepare_tax_return.since is null or prepare_tax_return.until is null or prepare_tax_return.until < prepare_tax_return.since then
    raise exception 'a return needs a period with a start on or before its end' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  if prepare_tax_return.currency is not null and upper(prepare_tax_return.currency) !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three letter code' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  select "better_supabase"."tax_return_source"(prepare_tax_return.tenant, prepare_tax_return.since, prepare_tax_return.until, prepare_tax_return.legal_entity_id) into v_rows;
  select coalesce(array_agg(distinct r.currency order by r.currency), '{}') into v_currencies
  from jsonb_to_recordset(v_rows) r(currency text);
  v_currency := upper(prepare_tax_return.currency);
  if v_currency is null then
    if cardinality(v_currencies) > 1 then
      raise exception 'invoices of several currencies fall in the period; name the currency to prepare the return for' using errcode = '22023', hint = 'TAX_RETURN_CURRENCY_MIXED';
    end if;
    v_currency := v_currencies[1];
  end if;
  select * into v_row from "better_supabase"."tax_returns" y
  where y."tenant_id" = prepare_tax_return.tenant
    and y."legal_entity_id" is not distinct from prepare_tax_return.legal_entity_id
    and y."period_start" = prepare_tax_return.since and y."period_end" = prepare_tax_return.until
  for update;
  if v_row."id" is not null and v_row."status" = 'filed' then
    raise exception 'a filed tax return can''t be prepared again' using errcode = '55000', hint = 'TAX_RETURN_FILED';
  end if;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency
  ), boxed as (
    select b.box, sum(s.sign * s.net) as base, sum(s.sign * s.tax) as tax
    from src s cross join lateral jsonb_array_elements_text(case when jsonb_array_length(s.boxes) = 0 then '[]'::jsonb else s.boxes end) b(box)
    group by b.box
  ), loose as (
    select coalesce(sum(s.sign * s.net), 0) as base, coalesce(sum(s.sign * s.tax), 0) as tax, count(*) as lines
    from src s where jsonb_array_length(s.boxes) = 0
  )
  select jsonb_build_object(
      'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box) from boxed x), '[]'::jsonb),
      'unassigned', (select jsonb_build_object('base', u.base::text, 'tax', u.tax::text, 'lines', u.lines) from loose u)
    ),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'sales'), 0),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'purchase'), 0)
  into v_boxes, v_sales, v_purchase
  from src s;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency and r.direction = 'sales' and r."codeType" in ('intra_eu_goods', 'intra_eu_services')
  )
  select coalesce(jsonb_agg(jsonb_build_object('code', 'EU_SALES_VAT_INVALID', 'invoiceId', s."invoiceId", 'message', 'an intra-EU sale needs the customer''s VAT number, starting with a country code') order by s."invoiceId"), '[]'::jsonb)
  into v_issues
  from src s
  where s.vat is null or upper(s.vat) !~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$';
  v_boxes := v_boxes || jsonb_build_object(
    'salesTax', v_sales::text,
    'purchaseTax', v_purchase::text,
    'netTax', (v_sales - v_purchase)::text,
    'currency', v_currency,
    'issues', v_issues
  );
  if v_row."id" is null then
    insert into "better_supabase"."tax_returns" ("tenant_id", "legal_entity_id", "period", "period_start", "period_end", "currency", "boxes", "prepared_by")
    values (prepare_tax_return.tenant, prepare_tax_return.legal_entity_id,
      coalesce(nullif(trim(prepare_tax_return.period), ''), to_char(prepare_tax_return.since, 'YYYY-MM-DD') || '/' || to_char(prepare_tax_return.until, 'YYYY-MM-DD')),
      prepare_tax_return.since, prepare_tax_return.until, v_currency, v_boxes, (select auth.uid()))
    returning * into v_row;
  else
    delete from "better_supabase"."eu_sales_list_lines" y where y."tax_return_id" = v_row."id";
    update "better_supabase"."tax_returns" y set "period" = coalesce(nullif(trim(prepare_tax_return.period), ''), y."period"),
      "currency" = v_currency, "boxes" = v_boxes, "prepared_by" = (select auth.uid()),
      "prepared_at" = now(), "updated_at" = now()
    where y."id" = v_row."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."eu_sales_list_lines" ("tenant_id", "tax_return_id", "customer_vat_number", "country", "kind", "amount", "currency", "invoice_count")
  select v_row."tenant_id", v_row."id", upper(regexp_replace(s.vat, '[ .-]', '', 'g')), left(upper(s.vat), 2),
    case when s."codeType" = 'intra_eu_goods' then 'goods' else 'services' end,
    sum(s.sign * s.net), v_currency, count(distinct s."invoiceId")::integer
  from jsonb_to_recordset(v_rows) s(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, vat text, net bigint)
  where s.currency is not distinct from v_currency and s.direction = 'sales' and s."codeType" in ('intra_eu_goods', 'intra_eu_services')
    and s.vat is not null and upper(s.vat) ~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$'
  group by 3, 4, 5
  having count(*) > 0;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) to authenticated, service_role;

-- The tax lines of the issued invoices dated in a period, one object per line.
-- Internal: prepare_tax_return reads it.
create or replace function "better_supabase"."tax_return_source"(tenant uuid, since date, until date, legal_entity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select '[]'::jsonb
$$;
revoke execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) to service_role;

-- Files a prepared return: its figures no longer change.
create or replace function "better_supabase"."file_tax_return"(return_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tax_returns" y where y."id" = file_tax_return.return_id for update;
  if v_row."id" is null then
    raise exception 'no such tax return' using errcode = 'P0002', hint = 'TAX_RETURN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'tax.manage'), false))) then
    raise exception 'not allowed to file tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if v_row."status" = 'filed' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."tax_returns" y set "status" = 'filed', "filed_at" = now(), "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."file_tax_return"(uuid) from public, anon;
grant execute on function "better_supabase"."file_tax_return"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_tax_returns"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_returns.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_returns.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'legalEntityId', x."legal_entity_id", 'period', x."period", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'status', x."status", 'currency', x."currency", 'boxes', x."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = x."id"), '[]'::jsonb), 'preparedBy', x."prepared_by", 'preparedAt', x."prepared_at", 'filedAt', x."filed_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."period_end" desc), '[]'::jsonb)
    from "better_supabase"."tax_returns" x where x."tenant_id" = list_tax_returns.tenant
  );
end;
$$;
revoke execute on function "better_supabase"."list_tax_returns"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_returns"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_select on "better_supabase"."tax_codes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_codes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_update on "better_supabase"."tax_codes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_codes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_select on "better_supabase"."tax_rates" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_rates" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_update on "better_supabase"."tax_rates" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_rates" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_select on "better_supabase"."tax_returns" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_returns" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_update on "better_supabase"."tax_returns" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_returns" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block-data tax
-- @bsb-hash sha256:6b65bf14c132fc5ca83f50d742147a433c5580278f63e96348f94a3b922071d7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tax', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block tax@1 managed
-- @bsb-hash sha256:36d5dd61f4bb01b878e63ece01988ec3b944738a746281de18dfc5ced30b606b
-- Tax codes per organization and legal entity with a rate history, the tax of a document per code on its date (margin scheme and credit restriction included), invoice tax lines written when an invoice is issued, tax returns with box totals, and the EU sales list per customer VAT number.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Tax per organization and optional legal entity: tax codes with a rate
-- history, the tax of a document computed per code (the margin scheme and a
-- credit restriction included), the tax lines of issued invoices, and the
-- returns and EU sales lists prepared from them.

-- A tax code of an organization, or of one of its legal entities. The code
-- says how a line is taxed; its rates sit in tax_rates, so a rate change keeps
-- the history. The accounts are plain ids that the functions check against the
-- chart of accounts, because accounting is installed after this block.
create table if not exists "better_supabase"."tax_codes" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "legal_entity_id" uuid,
  "code" text not null check (length("code") between 1 and 50),
  "name" text not null check (length("name") between 1 and 200),
  "type" text not null check ("type" in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin')),
  "sales_account_id" uuid,
  "purchase_account_id" uuid,
  -- The boxes of a tax return the code's base and tax count toward.
  "return_boxes" text[] not null default '{}',
  "archived_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create unique index if not exists "tax_codes_code_key" on "better_supabase"."tax_codes" ("org_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "code");
create index if not exists "tax_codes_tenant_idx" on "better_supabase"."tax_codes" ("org_id", "code");
alter table "better_supabase"."tax_codes" enable row level security;
revoke all on "better_supabase"."tax_codes" from public, anon, authenticated;
grant select on "better_supabase"."tax_codes" to authenticated;
grant all on "better_supabase"."tax_codes" to service_role;
drop policy if exists tax_codes_read on "better_supabase"."tax_codes";
create policy tax_codes_read on "better_supabase"."tax_codes"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- What a code charges from a day until another. valid_to is the last day the
-- rate applies; without one it runs until a later rate starts.
create table if not exists "better_supabase"."tax_rates" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "tax_code_id" uuid not null references "better_supabase"."tax_codes" ("id") on delete cascade,
  -- Basis points: 2100 is 21%.
  "rate_bps" integer not null check ("rate_bps" >= 0 and "rate_bps" <= 100000),
  "valid_from" date not null default date '1970-01-01',
  "valid_to" date,
  "created_at" timestamptz not null default now(),
  check ("valid_to" is null or "valid_to" >= "valid_from")
);
create unique index if not exists "tax_rates_from_key" on "better_supabase"."tax_rates" ("tax_code_id", "valid_from");
alter table "better_supabase"."tax_rates" enable row level security;
revoke all on "better_supabase"."tax_rates" from public, anon, authenticated;
grant select on "better_supabase"."tax_rates" to authenticated;
grant all on "better_supabase"."tax_rates" to service_role;
drop policy if exists tax_rates_read on "better_supabase"."tax_rates";
create policy tax_rates_read on "better_supabase"."tax_rates"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The tax of an issued invoice per rate and tax code, in the shape of
-- quote_tax_lines, written when the invoice is issued. customer_vat_number is
-- the customer's VAT number at that moment; show_tax is false on a margin
-- scheme invoice, which prints no tax amount.
create table if not exists "better_supabase"."invoice_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "invoice_id" uuid not null,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "tax_code_id" uuid,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0,
  "customer_vat_number" text,
  "show_tax" boolean not null default true
);
create index if not exists "invoice_tax_lines_parent_idx" on "better_supabase"."invoice_tax_lines" ("invoice_id");
create index if not exists "invoice_tax_lines_tenant_code_idx" on "better_supabase"."invoice_tax_lines" ("org_id", "tax_code_id");
alter table "better_supabase"."invoice_tax_lines" enable row level security;
revoke all on "better_supabase"."invoice_tax_lines" from public, anon, authenticated;
grant select on "better_supabase"."invoice_tax_lines" to authenticated;
grant all on "better_supabase"."invoice_tax_lines" to service_role;
drop policy if exists invoice_tax_lines_read on "better_supabase"."invoice_tax_lines";
create policy invoice_tax_lines_read on "better_supabase"."invoice_tax_lines"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- A return of one period, prepared from the issued invoices of that period.
-- boxes holds the totals per return box as decimal text.
create table if not exists "better_supabase"."tax_returns" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "legal_entity_id" uuid,
  "period" text not null check (length("period") between 1 and 50),
  "period_start" date not null,
  "period_end" date not null,
  "status" text not null default 'draft' check ("status" in ('draft', 'filed')),
  "currency" char(3) check ("currency" is null or "currency" ~ '^[A-Z]{3}$'),
  "boxes" jsonb not null default '{}'::jsonb check (jsonb_typeof("boxes") = 'object'),
  "prepared_by" uuid,
  "prepared_at" timestamptz not null default now(),
  "filed_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  check (("status" = 'filed') = ("filed_at" is not null))
);
create unique index if not exists "tax_returns_period_key" on "better_supabase"."tax_returns" ("org_id", (coalesce("legal_entity_id", '00000000-0000-0000-0000-000000000000'::uuid)), "period_start", "period_end");
alter table "better_supabase"."tax_returns" enable row level security;
revoke all on "better_supabase"."tax_returns" from public, anon, authenticated;
grant select on "better_supabase"."tax_returns" to authenticated;
grant all on "better_supabase"."tax_returns" to service_role;
drop policy if exists tax_returns_read on "better_supabase"."tax_returns";
create policy tax_returns_read on "better_supabase"."tax_returns"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tax.read')));

-- The intra-community sales list (ICP) of a return: what was sold to each
-- customer VAT number, as goods or as services.
create table if not exists "better_supabase"."eu_sales_list_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "tax_return_id" uuid not null references "better_supabase"."tax_returns" ("id") on delete cascade,
  "customer_vat_number" text not null check (length("customer_vat_number") between 4 and 20),
  "country" char(2) not null check ("country" ~ '^[A-Z]{2}$'),
  "kind" text not null check ("kind" in ('goods', 'services')),
  "amount" bigint not null,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_count" integer not null check ("invoice_count" > 0)
);
create unique index if not exists "eu_sales_list_lines_key" on "better_supabase"."eu_sales_list_lines" ("tax_return_id", "customer_vat_number", "kind", "currency");
alter table "better_supabase"."eu_sales_list_lines" enable row level security;
revoke all on "better_supabase"."eu_sales_list_lines" from public, anon, authenticated;
grant select on "better_supabase"."eu_sales_list_lines" to authenticated;
grant all on "better_supabase"."eu_sales_list_lines" to service_role;
drop policy if exists eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines";
create policy eu_sales_list_lines_read on "better_supabase"."eu_sales_list_lines"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('tax.read')));


-- The rate a tax code charges on a day, in basis points; null when no rate
-- covers the day. A code that doesn't charge a rate (exempt, zero, reverse
-- charge, intra-EU, export) always gives 0.
create or replace function "better_supabase"."tax_rate_on"(code_id uuid, on_date date)
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when x."type" not in ('sales', 'purchase', 'margin') then 0
    else (
      select y."rate_bps" from "better_supabase"."tax_rates" y
      where y."tax_code_id" = x."id" and y."valid_from" <= tax_rate_on.on_date
        and (y."valid_to" is null or y."valid_to" >= tax_rate_on.on_date)
      order by y."valid_from" desc limit 1
    )
  end
  from "better_supabase"."tax_codes" x where x."id" = tax_rate_on.code_id
$$;
revoke execute on function "better_supabase"."tax_rate_on"(uuid, date) from public, anon;
grant execute on function "better_supabase"."tax_rate_on"(uuid, date) to authenticated, service_role;

-- The tax code a code text names: the legal entity's own code first, then the
-- organization's. Null when there is none.
create or replace function "better_supabase"."resolve_tax_code"(tenant uuid, code text, legal_entity uuid default null)
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$
  select x."id" from "better_supabase"."tax_codes" x
  where x."org_id" = resolve_tax_code.tenant and x."code" = resolve_tax_code.code
    and x."archived_at" is null
    and (x."legal_entity_id" is null or x."legal_entity_id" = resolve_tax_code.legal_entity)
  order by (x."legal_entity_id" is null), x."id" limit 1
$$;
revoke execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."resolve_tax_code"(uuid, text, uuid) to authenticated, service_role;

-- Adds a rate to a code from valid_from on. A rate that starts after the
-- code's earlier open rate closes it the day before; without valid_to the rate
-- runs until the next later rate. A rate with the same start is replaced.
-- Internal: save_tax_rate and the import check who may call it.
create or replace function "better_supabase"."tax_rate_write"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_code "better_supabase"."tax_codes"%rowtype;
  v_from date := coalesce(tax_rate_write.valid_from, date '1970-01-01');
  v_to date := tax_rate_write.valid_to;
  v_row "better_supabase"."tax_rates"%rowtype;
begin
  select * into v_code from "better_supabase"."tax_codes" x
  where x."id" = tax_rate_write.tax_code and x."org_id" = tax_rate_write.tenant for update;
  if not found then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if v_code."type" not in ('sales', 'purchase', 'margin') then
    raise exception 'only a sales, purchase or margin code has a rate' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if tax_rate_write.rate_bps is null or tax_rate_write.rate_bps < 0 or tax_rate_write.rate_bps > 100000 then
    raise exception 'a rate is 0 to 100000 basis points' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is not null and v_to < v_from then
    raise exception 'a rate can''t end before it starts' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  if v_to is null then
    select min(y."valid_from") - 1 into v_to from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from;
  end if;
  if v_to is not null and exists (
    select 1 from "better_supabase"."tax_rates" y
    where y."tax_code_id" = v_code."id" and y."valid_from" > v_from and y."valid_from" <= v_to
  ) then
    raise exception 'the rate would overlap a later rate of the code' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  update "better_supabase"."tax_rates" y set "valid_to" = v_from - 1
  where y."tax_code_id" = v_code."id" and y."valid_from" < v_from
    and (y."valid_to" is null or y."valid_to" >= v_from);
  insert into "better_supabase"."tax_rates" ("org_id", "tax_code_id", "rate_bps", "valid_from", "valid_to")
  values (tax_rate_write.tenant, v_code."id", tax_rate_write.rate_bps, v_from, v_to)
  on conflict ("tax_code_id", "valid_from") do update
    set "rate_bps" = excluded."rate_bps", "valid_to" = excluded."valid_to"
  returning * into v_row;
  update "better_supabase"."tax_codes" x set "updated_at" = now() where x."id" = v_code."id";
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'taxCodeId', v_row."tax_code_id", 'rateBps', v_row."rate_bps", 'validFrom', v_row."valid_from", 'validTo', v_row."valid_to", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."tax_rate_write"(uuid, uuid, integer, date, date) from public, anon, authenticated;

-- Creates or changes a tax code. input: { code, name, type, legalEntityId?,
-- salesAccountId?, purchaseAccountId?, returnBoxes?, archived?, rateBps?,
-- validFrom? }. rateBps adds a rate from validFrom (the epoch for a new code,
-- today for an existing one). Internal: save_tax_code and the import check who
-- may call it.
create or replace function "better_supabase"."tax_code_write"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."tax_codes"%rowtype;
  v_created boolean := false;
  v_type text;
  v_entity uuid;
  v_sales uuid;
  v_purchase uuid;
  v_boxes text[];
  v_rate integer;
  v_from date;
begin
  if jsonb_typeof(tax_code_write.input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  if tax_code_write.code_id is not null then
    select * into v_row from "better_supabase"."tax_codes" x
    where x."id" = tax_code_write.code_id and x."org_id" = tax_code_write.tenant for update;
    if not found then
      raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
    end if;
  end if;
  v_type := coalesce(tax_code_write.input ->> 'type', v_row."type");
  if v_type is null or v_type not in ('sales', 'purchase', 'exempt', 'zero', 'reverse_charge', 'intra_eu_goods', 'intra_eu_services', 'export', 'margin') then
    raise exception 'a tax code''s type is sales, purchase, exempt, zero, reverse_charge, intra_eu_goods, intra_eu_services, export or margin' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  end if;
  v_entity := case when tax_code_write.input ? 'legalEntityId'
    then nullif(tax_code_write.input ->> 'legalEntityId', '')::uuid else v_row."legal_entity_id" end;
  v_sales := case when tax_code_write.input ? 'salesAccountId'
    then nullif(tax_code_write.input ->> 'salesAccountId', '')::uuid else v_row."sales_account_id" end;
  v_purchase := case when tax_code_write.input ? 'purchaseAccountId'
    then nullif(tax_code_write.input ->> 'purchaseAccountId', '')::uuid else v_row."purchase_account_id" end;
  if tax_code_write.input ? 'returnBoxes' then
    if jsonb_typeof(tax_code_write.input -> 'returnBoxes') is distinct from 'array' then
      raise exception 'returnBoxes must be a list of box names' using errcode = '22023', hint = 'TAX_CODE_INVALID';
    end if;
    select coalesce(array_agg(trim(b.value) order by b.ordinality), '{}') into v_boxes
    from jsonb_array_elements_text(tax_code_write.input -> 'returnBoxes') with ordinality b;
  else
    v_boxes := coalesce(v_row."return_boxes", '{}');
  end if;
  if v_row."id" is null then
    v_created := true;
    insert into "better_supabase"."tax_codes" ("org_id", "legal_entity_id", "code", "name", "type", "sales_account_id", "purchase_account_id", "return_boxes", "archived_at")
    values (tax_code_write.tenant, v_entity, trim(tax_code_write.input ->> 'code'), trim(tax_code_write.input ->> 'name'), v_type, v_sales, v_purchase, v_boxes,
      case when coalesce((tax_code_write.input ->> 'archived')::boolean, false) then now() end)
    returning * into v_row;
  else
    update "better_supabase"."tax_codes" x set
      "legal_entity_id" = v_entity,
      "code" = coalesce(trim(tax_code_write.input ->> 'code'), x."code"),
      "name" = coalesce(trim(tax_code_write.input ->> 'name'), x."name"),
      "type" = v_type,
      "sales_account_id" = v_sales,
      "purchase_account_id" = v_purchase,
      "return_boxes" = v_boxes,
      "archived_at" = case when tax_code_write.input ? 'archived'
        then case when (tax_code_write.input ->> 'archived')::boolean then coalesce(x."archived_at", now()) end
        else x."archived_at" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  end if;
  if tax_code_write.input ? 'rateBps' and tax_code_write.input -> 'rateBps' <> 'null'::jsonb then
    v_rate := (tax_code_write.input ->> 'rateBps')::integer;
    v_from := coalesce(nullif(tax_code_write.input ->> 'validFrom', '')::date, case when v_created then date '1970-01-01' else current_date end);
    perform "better_supabase"."tax_rate_write"(tax_code_write.tenant, v_row."id", v_rate, v_from, null);
    select * into v_row from "better_supabase"."tax_codes" x where x."id" = v_row."id";
  end if;
  if v_created then
    null;
  else
    null;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'code', v_row."code", 'name', v_row."name", 'type', v_row."type", 'salesAccountId', v_row."sales_account_id", 'purchaseAccountId', v_row."purchase_account_id", 'returnBoxes', to_jsonb(v_row."return_boxes"), 'archivedAt', v_row."archived_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = v_row."id"), '[]'::jsonb));
exception
  when check_violation or not_null_violation then
    raise exception 'a tax code has a code of 1 to 50 characters and a name of 1 to 200' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when unique_violation then
    raise exception 'the organization already has a tax code with this code' using errcode = '22023', hint = 'TAX_CODE_INVALID';
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'ids must be uuids, rateBps an integer and validFrom a date' using errcode = '22023', hint = 'TAX_CODE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_code_write"(uuid, jsonb, uuid) from public, anon, authenticated;

create or replace function "better_supabase"."save_tax_code"(tenant uuid, input jsonb, code_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_code.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_code.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_code_write"(save_tax_code.tenant, save_tax_code.input, save_tax_code.code_id);
end;
$$;
revoke execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_tax_code"(uuid, jsonb, uuid) to authenticated, service_role;

create or replace function "better_supabase"."save_tax_rate"(tenant uuid, tax_code uuid, rate_bps integer, valid_from date default null, valid_to date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (save_tax_rate.tenant is not null and coalesce(better_supabase.can('tenant', save_tax_rate.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to manage tax rates' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return "better_supabase"."tax_rate_write"(save_tax_rate.tenant, save_tax_rate.tax_code, save_tax_rate.rate_bps, save_tax_rate.valid_from, save_tax_rate.valid_to);
end;
$$;
revoke execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) from public, anon;
grant execute on function "better_supabase"."save_tax_rate"(uuid, uuid, integer, date, date) to authenticated, service_role;

-- The organization's tax codes with their rate history. With a legal entity,
-- the codes it can use: its own and the organization's.
create or replace function "better_supabase"."list_tax_codes"(tenant uuid, include_archived boolean default false, legal_entity uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_codes.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_codes.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax codes' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'legalEntityId', x."legal_entity_id", 'code', x."code", 'name', x."name", 'type', x."type", 'salesAccountId', x."sales_account_id", 'purchaseAccountId', x."purchase_account_id", 'returnBoxes', to_jsonb(x."return_boxes"), 'archivedAt', x."archived_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at", 'rates', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'taxCodeId', y."tax_code_id", 'rateBps', y."rate_bps", 'validFrom', y."valid_from", 'validTo', y."valid_to", 'createdAt', y."created_at") order by y."valid_from") from "better_supabase"."tax_rates" y where y."tax_code_id" = x."id"), '[]'::jsonb)) order by x."code", x."id")
    from "better_supabase"."tax_codes" x
    where x."org_id" = list_tax_codes.tenant
      and (coalesce(list_tax_codes.include_archived, false) or x."archived_at" is null)
      and (list_tax_codes.legal_entity is null or x."legal_entity_id" is null or x."legal_entity_id" = list_tax_codes.legal_entity)
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_codes"(uuid, boolean, uuid) to authenticated, service_role;

-- The import target of the tax_code entity: item.data is the input of
-- save_tax_code, with rateBps and validFrom for the first rate.
create or replace function "better_supabase"."import_tax_code"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_code.item ->> 'tenant')::uuid;
  v_row jsonb;
begin
  if jsonb_typeof(import_tax_code.item -> 'data') is distinct from 'object' then
    raise exception 'a tax code item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."tax_code_write"(v_tenant, import_tax_code.item -> 'data', import_tax_code.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
revoke execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_code"(uuid, jsonb, text) to service_role;

-- When a tax code last changed, for the conflict check of imports.
create or replace function "better_supabase"."tax_code_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."tax_codes" x where x."id"::text = tax_code_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."tax_code_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_code_updated_at"(text) to service_role;

-- The import target of the tax_rate entity: item.data is { taxCodeId or
-- taxCode (the code text), rateBps, validFrom?, validTo? }.
create or replace function "better_supabase"."import_tax_rate"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_tax_rate.item ->> 'tenant')::uuid;
  v_data jsonb := import_tax_rate.item -> 'data';
  v_code uuid;
  v_row jsonb;
begin
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'a tax rate item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  begin
    v_code := coalesce(nullif(v_data ->> 'taxCodeId', '')::uuid, "better_supabase"."resolve_tax_code"(v_tenant, v_data ->> 'taxCode'));
    v_row := "better_supabase"."tax_rate_write"(v_tenant, v_code, (v_data ->> 'rateBps')::integer, nullif(v_data ->> 'validFrom', '')::date, nullif(v_data ->> 'validTo', '')::date);
  exception
    when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
      raise exception 'a tax rate needs a tax code, a rate in basis points and valid dates' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end;
  return jsonb_build_object('subjectId', v_row ->> 'id');
end;
$$;
revoke execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_tax_rate"(uuid, jsonb, text) to service_role;


-- The tax of lines [{ quantity?, unitAmount, discountBps?, taxCodeId?,
-- taxRateBps?, discountAmount?, unitCost? }] on a day: { groups: [{ taxCodeId, code, type,
-- rateBps, net, tax, gross, discount, showTax }], subtotal, taxTotal, total,
-- discountTotal, showTaxAmount }, amounts as text. A line's rate is its tax
-- code's rate on on_date; taxRateBps stands in when no rate covers the day or
-- the line has no code. It runs as the caller, so a caller only prices lines with
-- the tax codes they can read; compute_document_tax and the invoice issue call it.
create or replace function "better_supabase"."tax_compute_lines"(lines jsonb, on_date date, prices_include_tax boolean, credit_restriction_bps integer, discount_bps integer, discount_amount bigint)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_inclusive boolean := coalesce(tax_compute_lines.prices_include_tax, false);
  v_restriction integer := coalesce(tax_compute_lines.credit_restriction_bps, 0);
  v_on date := coalesce(tax_compute_lines.on_date, current_date);
  v_bps integer := coalesce(tax_compute_lines.discount_bps, 0);
  v_amount bigint := coalesce(tax_compute_lines.discount_amount, 0);
  v_lines jsonb;
  v_groups jsonb;
  v_net bigint;
  v_line_discount bigint;
  v_record_discount bigint;
begin
  if jsonb_typeof(tax_compute_lines.lines) is distinct from 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if v_restriction < 0 or v_restriction > 10000 then
    raise exception 'a credit restriction is 0 to 10000 basis points' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(tax_compute_lines.lines) x where jsonb_typeof(x.value) <> 'object') then
    raise exception 'every line must be an object' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    where x.value ->> 'taxCodeId' is not null
      and not exists (select 1 from "better_supabase"."tax_codes" y where y."id"::text = x.value ->> 'taxCodeId')
  ) then
    raise exception 'no such tax code' using errcode = 'P0002', hint = 'TAX_CODE_NOT_FOUND';
  end if;
  if exists (
    select 1 from jsonb_array_elements(tax_compute_lines.lines) x
    join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
    where y."type" = 'margin' and x.value ->> 'unitCost' is null
  ) then
    raise exception 'a margin scheme line needs the unitCost of what it was bought for' using errcode = '22023', hint = 'TAX_MARGIN_COST_REQUIRED';
  end if;
  with src as (
    select x.ordinality as pos,
      coalesce((x.value ->> 'quantity')::numeric, 1) as qty,
      (x.value ->> 'unitAmount')::bigint as unit,
      coalesce((x.value ->> 'discountBps')::integer, 0) as disc_bps,
      coalesce((x.value ->> 'discountAmount')::bigint, 0) as disc_amount,
      coalesce((x.value ->> 'unitCost')::bigint, 0) as unit_cost,
      y."id" as code_id,
      y."code" as code,
      coalesce(y."type", 'sales') as type,
      case
        when y."id" is null then coalesce((x.value ->> 'taxRateBps')::integer, 0)
        when y."type" not in ('sales', 'purchase', 'margin') then 0
        else coalesce("better_supabase"."tax_rate_on"(y."id", v_on), (x.value ->> 'taxRateBps')::integer, -1)
      end as rate
    from jsonb_array_elements(tax_compute_lines.lines) with ordinality x
    left join "better_supabase"."tax_codes" y on y."id"::text = x.value ->> 'taxCodeId'
  ), priced as (
    select s.*, round(s.qty * s.unit) as amount from src s
  ), discounted as (
    select p.*, least(p.amount, round(p.amount * p.disc_bps / 10000.0) + p.disc_amount) as disc from priced p
  ), counted as (
    select d.*, d.amount - d.disc as after, round(d.qty * d.unit_cost) as cost from discounted d
  ), taxed as (
    select n.pos, n.rate, n.code_id, n.code, n.type, n.after, n.disc,
      case
        when n.rate <= 0 then 0
        when n.type = 'margin' then round(greatest(n.after - n.cost, 0) * n.rate / (10000.0 + n.rate))
        else round(n.after * (10000 - v_restriction) * n.rate / (10000.0 * (case when v_inclusive then 10000.0 + n.rate else 10000.0 end)))
      end as tax
    from counted n
  )
  select coalesce(jsonb_agg(jsonb_build_object('pos', t.pos, 'rate', t.rate, 'codeId', t.code_id, 'code', t.code, 'type', t.type,
      'after', t.after::bigint, 'disc', t.disc::bigint, 'tax', t.tax::bigint) order by t.pos), '[]'::jsonb)
    into v_lines
  from taxed t;
  if exists (select 1 from jsonb_to_recordset(v_lines) r(rate integer) where r.rate < 0) then
    raise exception 'no rate of a line''s tax code covers the date, and the line gives no taxRateBps' using errcode = '22023', hint = 'TAX_RATE_INVALID';
  end if;
  select coalesce(sum(r.after), 0), coalesce(sum(r.disc), 0) into v_net, v_line_discount
  from jsonb_to_recordset(v_lines) r(after bigint, disc bigint);
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * v_bps / 10000.0)::bigint + v_amount)
    else 0
  end;
  with grouped as (
    select r.rate, r."codeId" as code_id, r.code, r.type, sum(r.after) as amount, sum(r.tax) as tax
    from jsonb_to_recordset(v_lines) r(rate integer, "codeId" uuid, code text, type text, after bigint, tax bigint)
    group by 1, 2, 3, 4
  ), shared as (
    select g.rate, g.code_id, g.code, g.type, g.amount, g.tax,
      case when v_net > 0
        then round(v_record_discount * sum(g.amount) over w / v_net) - round(v_record_discount * (sum(g.amount) over w - g.amount) / v_net)
        else 0
      end as share
    from grouped g
    window w as (order by g.rate, g.code nulls first, g.code_id nulls first rows between unbounded preceding and current row)
  ), reduced as (
    select s.rate, s.code_id, s.code, s.type, s.share, s.amount - s.share as amount,
      s.tax - case
        when s.rate <= 0 then 0
        when s.type = 'margin' then round(s.share * s.rate / (10000.0 + s.rate))
        else round(s.share * (10000 - v_restriction) * s.rate / (10000.0 * (case when v_inclusive then 10000.0 + s.rate else 10000.0 end)))
      end as tax
    from shared s
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'taxCodeId', x.code_id,
      'code', x.code,
      'type', x.type,
      'rateBps', x.rate,
      'net', (case when v_inclusive or x.type = 'margin' then x.amount - x.tax else x.amount end)::text,
      'tax', x.tax::text,
      'gross', (case when v_inclusive or x.type = 'margin' then x.amount else x.amount + x.tax end)::text,
      'discount', x.share::text,
      'showTax', x.type <> 'margin'
    ) order by x.rate, x.code nulls first, x.code_id nulls first), '[]'::jsonb)
    into v_groups
  from reduced x;
  return jsonb_build_object(
    'groups', v_groups,
    'subtotal', (select coalesce(sum((g ->> 'net')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'taxTotal', (select coalesce(sum((g ->> 'tax')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'total', (select coalesce(sum((g ->> 'gross')::bigint), 0) from jsonb_array_elements(v_groups) g)::text,
    'discountTotal', (v_line_discount + v_record_discount)::text,
    'showTaxAmount', not exists (select 1 from jsonb_array_elements(v_groups) g where g ->> 'type' = 'margin')
  );
exception
  when invalid_text_representation or numeric_value_out_of_range or datatype_mismatch then
    raise exception 'quantity, unitAmount, discountBps, unitCost and taxRateBps must be numbers and taxCodeId a uuid' using errcode = '22023', hint = 'TAX_COMPUTE_INVALID';
end;
$$;
revoke execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) from public, anon;
grant execute on function "better_supabase"."tax_compute_lines"(jsonb, date, boolean, integer, integer, bigint) to authenticated, service_role;

-- The tax of a document's lines: see tax_compute_lines for the lines and the
-- result. The codes are the caller's (row level security applies).
create or replace function "better_supabase"."compute_document_tax"(lines jsonb, on_date date, prices_include_tax boolean default false, credit_restriction_bps integer default 0)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select "better_supabase"."tax_compute_lines"(compute_document_tax.lines, compute_document_tax.on_date, compute_document_tax.prices_include_tax, compute_document_tax.credit_restriction_bps, 0, 0)
$$;
revoke execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) from public, anon;
grant execute on function "better_supabase"."compute_document_tax"(jsonb, date, boolean, integer) to authenticated, service_role;


-- Prepares the tax return of a period from the tax lines of the issued
-- invoices (not drafts or void ones) dated in it: the totals per return box,
-- what no box takes, the sales and purchase tax, and the EU sales list of
-- intra-EU sales per customer VAT number. A draft return of the same period
-- (and legal entity) is prepared again; a filed one is refused. currency is
-- needed only when invoices of several currencies fall in the period.
create or replace function "better_supabase"."prepare_tax_return"(tenant uuid, since date, until date, legal_entity_id uuid default null, period text default null, currency text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_rows jsonb;
  v_currencies text[];
  v_currency text;
  v_boxes jsonb;
  v_issues jsonb;
  v_sales bigint;
  v_purchase bigint;
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (prepare_tax_return.tenant is not null and coalesce(better_supabase.can('tenant', prepare_tax_return.tenant, 'tax.manage'), false))) then
    raise exception 'not allowed to prepare tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if prepare_tax_return.since is null or prepare_tax_return.until is null or prepare_tax_return.until < prepare_tax_return.since then
    raise exception 'a return needs a period with a start on or before its end' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  if prepare_tax_return.currency is not null and upper(prepare_tax_return.currency) !~ '^[A-Z]{3}$' then
    raise exception 'currency must be a three letter code' using errcode = '22023', hint = 'TAX_RETURN_INVALID';
  end if;
  select "better_supabase"."tax_return_source"(prepare_tax_return.tenant, prepare_tax_return.since, prepare_tax_return.until, prepare_tax_return.legal_entity_id) into v_rows;
  select coalesce(array_agg(distinct r.currency order by r.currency), '{}') into v_currencies
  from jsonb_to_recordset(v_rows) r(currency text);
  v_currency := upper(prepare_tax_return.currency);
  if v_currency is null then
    if cardinality(v_currencies) > 1 then
      raise exception 'invoices of several currencies fall in the period; name the currency to prepare the return for' using errcode = '22023', hint = 'TAX_RETURN_CURRENCY_MIXED';
    end if;
    v_currency := v_currencies[1];
  end if;
  select * into v_row from "better_supabase"."tax_returns" y
  where y."org_id" = prepare_tax_return.tenant
    and y."legal_entity_id" is not distinct from prepare_tax_return.legal_entity_id
    and y."period_start" = prepare_tax_return.since and y."period_end" = prepare_tax_return.until
  for update;
  if v_row."id" is not null and v_row."status" = 'filed' then
    raise exception 'a filed tax return can''t be prepared again' using errcode = '55000', hint = 'TAX_RETURN_FILED';
  end if;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency
  ), boxed as (
    select b.box, sum(s.sign * s.net) as base, sum(s.sign * s.tax) as tax
    from src s cross join lateral jsonb_array_elements_text(case when jsonb_array_length(s.boxes) = 0 then '[]'::jsonb else s.boxes end) b(box)
    group by b.box
  ), loose as (
    select coalesce(sum(s.sign * s.net), 0) as base, coalesce(sum(s.sign * s.tax), 0) as tax, count(*) as lines
    from src s where jsonb_array_length(s.boxes) = 0
  )
  select jsonb_build_object(
      'boxes', coalesce((select jsonb_agg(jsonb_build_object('box', x.box, 'base', x.base::text, 'tax', x.tax::text) order by x.box) from boxed x), '[]'::jsonb),
      'unassigned', (select jsonb_build_object('base', u.base::text, 'tax', u.tax::text, 'lines', u.lines) from loose u)
    ),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'sales'), 0),
    coalesce(sum(s.sign * s.tax) filter (where s.direction = 'purchase'), 0)
  into v_boxes, v_sales, v_purchase
  from src s;
  with src as (
    select r.* from jsonb_to_recordset(v_rows) r(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, boxes jsonb, net bigint, tax bigint, vat text)
    where r.currency is not distinct from v_currency and r.direction = 'sales' and r."codeType" in ('intra_eu_goods', 'intra_eu_services')
  )
  select coalesce(jsonb_agg(jsonb_build_object('code', 'EU_SALES_VAT_INVALID', 'invoiceId', s."invoiceId", 'message', 'an intra-EU sale needs the customer''s VAT number, starting with a country code') order by s."invoiceId"), '[]'::jsonb)
  into v_issues
  from src s
  where s.vat is null or upper(s.vat) !~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$';
  v_boxes := v_boxes || jsonb_build_object(
    'salesTax', v_sales::text,
    'purchaseTax', v_purchase::text,
    'netTax', (v_sales - v_purchase)::text,
    'currency', v_currency,
    'issues', v_issues
  );
  if v_row."id" is null then
    insert into "better_supabase"."tax_returns" ("org_id", "legal_entity_id", "period", "period_start", "period_end", "currency", "boxes", "prepared_by")
    values (prepare_tax_return.tenant, prepare_tax_return.legal_entity_id,
      coalesce(nullif(trim(prepare_tax_return.period), ''), to_char(prepare_tax_return.since, 'YYYY-MM-DD') || '/' || to_char(prepare_tax_return.until, 'YYYY-MM-DD')),
      prepare_tax_return.since, prepare_tax_return.until, v_currency, v_boxes, (select auth.uid()))
    returning * into v_row;
  else
    delete from "better_supabase"."eu_sales_list_lines" y where y."tax_return_id" = v_row."id";
    update "better_supabase"."tax_returns" y set "period" = coalesce(nullif(trim(prepare_tax_return.period), ''), y."period"),
      "currency" = v_currency, "boxes" = v_boxes, "prepared_by" = (select auth.uid()),
      "prepared_at" = now(), "updated_at" = now()
    where y."id" = v_row."id"
    returning * into v_row;
  end if;
  insert into "better_supabase"."eu_sales_list_lines" ("org_id", "tax_return_id", "customer_vat_number", "country", "kind", "amount", "currency", "invoice_count")
  select v_row."org_id", v_row."id", upper(regexp_replace(s.vat, '[ .-]', '', 'g')), left(upper(s.vat), 2),
    case when s."codeType" = 'intra_eu_goods' then 'goods' else 'services' end,
    sum(s.sign * s.net), v_currency, count(distinct s."invoiceId")::integer
  from jsonb_to_recordset(v_rows) s(currency text, sign integer, direction text, "invoiceId" uuid, "codeType" text, vat text, net bigint)
  where s.currency is not distinct from v_currency and s.direction = 'sales' and s."codeType" in ('intra_eu_goods', 'intra_eu_services')
    and s.vat is not null and upper(s.vat) ~ '^[A-Z]{2}[A-Z0-9 .-]{2,18}$'
  group by 3, 4, 5
  having count(*) > 0;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) from public, anon;
grant execute on function "better_supabase"."prepare_tax_return"(uuid, date, date, uuid, text, text) to authenticated, service_role;

-- The tax lines of the issued invoices dated in a period, one object per line.
-- Internal: prepare_tax_return reads it.
create or replace function "better_supabase"."tax_return_source"(tenant uuid, since date, until date, legal_entity_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select '[]'::jsonb
$$;
revoke execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."tax_return_source"(uuid, date, date, uuid) to service_role;

-- Files a prepared return: its figures no longer change.
create or replace function "better_supabase"."file_tax_return"(return_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."tax_returns"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."tax_returns" y where y."id" = file_tax_return.return_id for update;
  if v_row."id" is null then
    raise exception 'no such tax return' using errcode = 'P0002', hint = 'TAX_RETURN_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."org_id" is not null and coalesce(better_supabase.can('tenant', v_row."org_id", 'tax.manage'), false))) then
    raise exception 'not allowed to file tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  if v_row."status" = 'filed' then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  update "better_supabase"."tax_returns" y set "status" = 'filed', "filed_at" = now(), "updated_at" = now()
  where y."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'legalEntityId', v_row."legal_entity_id", 'period', v_row."period", 'periodStart', v_row."period_start", 'periodEnd', v_row."period_end", 'status', v_row."status", 'currency', v_row."currency", 'boxes', v_row."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = v_row."id"), '[]'::jsonb), 'preparedBy', v_row."prepared_by", 'preparedAt', v_row."prepared_at", 'filedAt', v_row."filed_at", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."file_tax_return"(uuid) from public, anon;
grant execute on function "better_supabase"."file_tax_return"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_tax_returns"(tenant uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_tax_returns.tenant is not null and coalesce(better_supabase.can('tenant', list_tax_returns.tenant, 'tax.read'), false))) then
    raise exception 'not allowed to read tax returns' using errcode = '42501', hint = 'TAX_FORBIDDEN';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'legalEntityId', x."legal_entity_id", 'period', x."period", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'status', x."status", 'currency', x."currency", 'boxes', x."boxes", 'euSalesList', coalesce((select jsonb_agg(jsonb_build_object('customerVatNumber', z."customer_vat_number", 'country', z."country", 'kind', z."kind", 'amount', z."amount"::text, 'currency', z."currency", 'invoiceCount', z."invoice_count") order by z."customer_vat_number", z."kind", z."currency") from "better_supabase"."eu_sales_list_lines" z where z."tax_return_id" = x."id"), '[]'::jsonb), 'preparedBy', x."prepared_by", 'preparedAt', x."prepared_at", 'filedAt', x."filed_at", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."period_end" desc), '[]'::jsonb)
    from "better_supabase"."tax_returns" x where x."org_id" = list_tax_returns.tenant
  );
end;
$$;
revoke execute on function "better_supabase"."list_tax_returns"(uuid) from public, anon;
grant execute on function "better_supabase"."list_tax_returns"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_codes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_select on "better_supabase"."tax_codes" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_codes" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_update on "better_supabase"."tax_codes" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_codes";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_codes" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_rates";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_select on "better_supabase"."tax_rates" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_rates" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_update on "better_supabase"."tax_rates" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_rates";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_rates" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."invoice_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."invoice_tax_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."invoice_tax_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."invoice_tax_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."invoice_tax_lines" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."tax_returns";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_select on "better_supabase"."tax_returns" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_insert on "better_supabase"."tax_returns" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_update on "better_supabase"."tax_returns" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."tax_returns";
create policy bsb_tenant_scope_delete on "better_supabase"."tax_returns" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."eu_sales_list_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_select on "better_supabase"."eu_sales_list_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('tax.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."eu_sales_list_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_update on "better_supabase"."eu_sales_list_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."eu_sales_list_lines" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_145_tax.sql
-- better-supabase module: tax
-- @bsb-block-data tax
-- @bsb-hash sha256:6b65bf14c132fc5ca83f50d742147a433c5580278f63e96348f94a3b922071d7
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('tax', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
