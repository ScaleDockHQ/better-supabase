-- ==== alone: schema supabase/schemas/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block quotes@3 managed
-- @bsb-hash sha256:078e802cdf304e9ce5e3c66c83fb891c695c6352a1fbafcc5ca935d34dadc31a
-- Quotes with sections, optional lines, discounts, prices with or without tax, tax per rate and a deposit; published versions; a public link or the signed-in portal the customer accepts, rejects or asks changes through; expiry; and quotes from deals. With catalog, a line that names a product variant takes its price and title.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Quotes: line items, sections, optional lines, discounts and tax per rate,
-- published versions, sending with a public link or to the signed-in portal
-- the customer accepts, rejects or asks changes through, and expiry.

create table if not exists "better_supabase"."quotes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "revision" integer not null default 1,
  "title" text not null check (length("title") between 1 and 300),
  "company_type" text,
  "company_id" text,
  "contact_type" text,
  "contact_id" text,
  "owner_user_id" uuid,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn')),
  "valid_until" date,
  "terms" text,
  "note" text,
  "origin_type" text,
  "origin_id" text,
  "token_hash" text unique,
  "sent_at" timestamptz,
  "viewed_at" timestamptz,
  "decided_at" timestamptz,
  "decided_by" text,
  "decision_note" text,
  "decided_user_id" uuid,
  "decided_ip" text,
  "decided_user_agent" text,
  "prices_include_tax" boolean not null default false,
  "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000),
  "discount_amount" bigint not null default 0 check ("discount_amount" >= 0),
  "deposit_bps" integer check ("deposit_bps" > 0 and "deposit_bps" < 10000),
  "deposit_amount" bigint check ("deposit_amount" > 0),
  "deposit_required" boolean not null default false,
  "deposit_due" bigint not null default 0,
  "unpublished_changes" boolean not null default false,
  "buyer" jsonb,
  "variant_of" uuid,
  "variant_label" text check (length("variant_label") between 1 and 100),
  "is_selected" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "list_total" bigint not null default 0,
  "discount_total" bigint not null default 0,
  "subtotal" bigint not null default 0,
  "tax_total" bigint not null default 0,
  "total" bigint not null default 0,
  unique ("tenant_id", "number", "revision"),
  check (("company_type" is null) = ("company_id" is null)),
  check (("origin_type" is null) = ("origin_id" is null))
);
alter table "better_supabase"."quotes" add column if not exists "deposit_amount" bigint check ("deposit_amount" > 0);
alter table "better_supabase"."quotes" add column if not exists "deposit_required" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "unpublished_changes" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "buyer" jsonb;
alter table "better_supabase"."quotes" add column if not exists "variant_of" uuid;
alter table "better_supabase"."quotes" add column if not exists "variant_label" text check (length("variant_label") between 1 and 100);
alter table "better_supabase"."quotes" add column if not exists "is_selected" boolean not null default false;
create index if not exists quotes_tenant_status_idx on "better_supabase"."quotes" ("tenant_id", "status", "created_at" desc);
create index if not exists quotes_variant_idx on "better_supabase"."quotes" ("variant_of") where "variant_of" is not null;
create index if not exists quotes_origin_idx on "better_supabase"."quotes" ("origin_type", "origin_id");

alter table "better_supabase"."quotes" enable row level security;
revoke all on "better_supabase"."quotes" from public, anon, authenticated;
grant select on "better_supabase"."quotes" to authenticated;
grant all on "better_supabase"."quotes" to service_role;
drop policy if exists quotes_read on "better_supabase"."quotes";
create policy quotes_read on "better_supabase"."quotes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')));

create table if not exists "better_supabase"."quote_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "quote_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
  "revision" integer not null,
  "snapshot" jsonb not null,
  "total" bigint not null,
  "currency" char(3) not null,
  "published_by" uuid,
  "published_at" timestamptz not null default now(),
  unique ("quote_id", "revision")
);
alter table "better_supabase"."quote_versions" enable row level security;
revoke all on "better_supabase"."quote_versions" from public, anon, authenticated;
grant select on "better_supabase"."quote_versions" to authenticated;
grant all on "better_supabase"."quote_versions" to service_role;
drop policy if exists quote_versions_read on "better_supabase"."quote_versions";
create policy quote_versions_read on "better_supabase"."quote_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"));
create or replace function better_supabase.bsb_quote_versions_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'a published quote version never changes' using errcode = '55000', hint = 'QUOTE_VERSION_FROZEN';
end;
$$;
revoke execute on function better_supabase.bsb_quote_versions_frozen() from public, anon, authenticated;
drop trigger if exists "bsb_quote_versions_frozen" on "better_supabase"."quote_versions";
create trigger "bsb_quote_versions_frozen" before update on "better_supabase"."quote_versions"
for each row execute function better_supabase.bsb_quote_versions_frozen();

create table if not exists "better_supabase"."quote_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0
);
create index if not exists quote_tax_lines_parent_idx on "better_supabase"."quote_tax_lines" ("parent_id");
alter table "better_supabase"."quote_tax_lines" enable row level security;
revoke all on "better_supabase"."quote_tax_lines" from public, anon, authenticated;
grant select on "better_supabase"."quote_tax_lines" to authenticated;
grant all on "better_supabase"."quote_tax_lines" to service_role;
drop policy if exists quote_tax_lines_read on "better_supabase"."quote_tax_lines";
create policy quote_tax_lines_read on "better_supabase"."quote_tax_lines"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"));

-- Creates a draft quote. attrs: title (required), currency, company and
-- contact ({ type, id }), ownerId, validUntil, terms, note, origin ({ type,
-- id }, the record it was made from), pricesIncludeTax, discountBps,
-- discountAmount (minor units as text), depositBps, or depositAmount (minor
-- units as text) for a fixed deposit, and depositRequired, which makes the
-- customer pay it before they accept. lines: see set_quote_lines.
create or replace function "better_supabase"."create_quote"(tenant uuid, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "prices_include_tax", "discount_bps", "discount_amount", "deposit_bps", "deposit_amount", "deposit_required", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id',
      coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce((create_quote.attrs ->> 'discountBps')::integer, 0), coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0), (create_quote.attrs ->> 'depositBps')::integer, (create_quote.attrs ->> 'depositAmount')::bigint, coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft quote, or one the customer asked changes on: title,
-- company, contact, currency, ownerId, validUntil, terms, note,
-- pricesIncludeTax, discountBps, discountAmount, depositBps, depositAmount
-- and depositRequired. The totals follow the new pricing.
create or replace function "better_supabase"."update_quote"(quote uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_user_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "prices_include_tax" = case when update_quote.attrs ? 'pricesIncludeTax' then coalesce((update_quote.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "discount_bps" = case when update_quote.attrs ? 'discountBps' then coalesce((update_quote.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_quote.attrs ? 'discountAmount' then coalesce((update_quote.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "deposit_bps" = case when update_quote.attrs ? 'depositBps' then (update_quote.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "deposit_amount" = case when update_quote.attrs ? 'depositAmount' then (update_quote.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "deposit_required" = case when update_quote.attrs ? 'depositRequired' then coalesce((update_quote.attrs ->> 'depositRequired')::boolean, false) else x."deposit_required" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  perform "better_supabase"."set_quote_lines_recount"(v_row."id");
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."update_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_quote"(uuid, jsonb) to authenticated, service_role;
create table if not exists "better_supabase"."quote_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
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
  "section" text check (length("section") between 1 and 300),
  "optional" boolean not null default false,
  "selected" boolean not null default true,
  "periods" integer not null default 1 check ("periods" > 0),
  "position" integer not null,
  "created_at" timestamptz not null default now(),
  check (("product_type" is null) = ("product_id" is null))
);
alter table "better_supabase"."quote_lines" add column if not exists "periods" integer not null default 1 check ("periods" > 0);
create index if not exists "quote_lines_parent_idx" on "better_supabase"."quote_lines" ("parent_id", "position");
alter table "better_supabase"."quote_lines" enable row level security;
revoke all on "better_supabase"."quote_lines" from public, anon, authenticated;
grant select on "better_supabase"."quote_lines" to authenticated;
grant all on "better_supabase"."quote_lines" to service_role;
drop policy if exists "quote_lines_read" on "better_supabase"."quote_lines";
create policy "quote_lines_read" on "better_supabase"."quote_lines" for select to authenticated
using (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"));

-- Writes a record's totals from its counted lines: an optional line counts
-- only when the customer took it. The record discount is spread over the tax
-- rates in proportion to their amounts, and tax is counted once per rate, so
-- the totals and the tax per rate always add up.
create or replace function "better_supabase"."set_quote_lines_recount"(parent uuid)
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
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount", 0
    into v_tenant, v_inclusive, v_record_bps, v_record_amount, v_restriction
  from "better_supabase"."quotes" x where x."id" = set_quote_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount")), 0), coalesce(sum((round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))), 0)
    into v_list, v_line_discount
  from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected");
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) as amount,
      sum(round((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * (10000 - v_restriction) * l."tax_rate_bps" / (10000.0 * (case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)))) as tax
    from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected")
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
  delete from "better_supabase"."quote_tax_lines" x where x."parent_id" = set_quote_lines_recount.parent;
  insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
  select v_tenant, set_quote_lines_recount.parent, r.rate, r.code, r.net, r.tax, r.gross, r.discount
  from jsonb_to_recordset(v_groups) r(rate integer, code text, net bigint, tax bigint, gross bigint, discount bigint);
  update "better_supabase"."quotes" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_subtotal,
    "tax_total" = v_tax,
    "total" = v_total,
    "deposit_due" = case when x."deposit_amount" is not null then least(greatest(v_total, 0), x."deposit_amount") when x."deposit_bps" is not null then round(v_total * x."deposit_bps" / 10000.0)::bigint else 0 end
  where x."id" = set_quote_lines_recount.parent;
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines_recount"(uuid) from public, anon, authenticated;

-- Recounts each record a statement touched once, in id order so concurrent
-- statements lock the records in the same order. A transition table needs a
-- trigger per event, so there are three triggers on one function. The
-- transition tables are read through execute because plpgsql_check (db lint)
-- doesn't know them.
create or replace function better_supabase.bsb_quote_lines_totals()
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
    perform "better_supabase"."set_quote_lines_recount"(v_parent);
  end loop;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_quote_lines_totals() from public, anon, authenticated;
drop trigger if exists bsb_quote_lines_totals on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_insert on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_update on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_delete on "better_supabase"."quote_lines";
create trigger bsb_quote_lines_totals_insert after insert on "better_supabase"."quote_lines"
referencing new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_update after update on "better_supabase"."quote_lines"
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_delete after delete on "better_supabase"."quote_lines"
referencing old table as old_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
create or replace function "better_supabase"."set_quote_lines"(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := set_quote_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."quotes" x where x."id" = v_parent and not (not (x."status" in ('draft', 'changes_requested')));
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."quotes" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false))) then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_quote_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_quote_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."quote_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "section", "optional", "selected", "periods", "position")
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
      nullif(trim(x.value ->> 'section'), ''),
      coalesce((x.value ->> 'optional')::boolean, false),
      coalesce((x.value ->> 'selected')::boolean, not coalesce((x.value ->> 'optional')::boolean, false)),
      coalesce((x.value ->> 'periods')::integer, 1),
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_quote_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_quote_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."quotes" x where x."id" = v_parent);
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) to authenticated, service_role;

-- Sends a quote: it gets a public link the customer opens and a published
-- version, a snapshot that never changes. The quote can't change until it is
-- revised or the customer asks for changes; sending it again then publishes
-- the next revision. Returns the quote with the link's token, which is stored
-- only as a hash and returned this once.
-- actor: who sent it, for the state machine's history.
drop function if exists "better_supabase"."send_quote"(uuid);
create or replace function "better_supabase"."send_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = send_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'the quote was already sent; revise it to send a new version' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if not exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_row."id") then
    raise exception 'a quote needs a line before it is sent' using errcode = '23514', hint = 'QUOTE_EMPTY';
  end if;
  if send_quote.actor is not null then
    if jsonb_typeof(send_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(send_quote.actor ->> 'ip', '')::inet, nullif(send_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(send_quote.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "revision" = case when exists (select 1 from "better_supabase"."quote_versions" v where v."quote_id" = x."id" and v."revision" = x."revision") then x."revision" + 1 else x."revision" end,
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "better_supabase"."quote_versions" ("tenant_id", "quote_id", "revision", "snapshot", "total", "currency", "published_by")
  values (v_row."tenant_id", v_row."id", v_row."revision", (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), v_row."total", v_row."currency", coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid))
  returning "id" into v_version;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)) || jsonb_build_object('token', v_token);
end;
$$;
revoke execute on function "better_supabase"."send_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."send_quote"(uuid, jsonb) to authenticated, service_role;

-- Opens a sent or declined quote again as a draft of its next revision: the
-- same quote, number and lines, a fresh valid-until date, and its link ends.
-- The versions already published stay as they were. An accepted quote is
-- kept as the customer accepted it; start a new quote instead.
drop function if exists "better_supabase"."revise_quote"(uuid);
create or replace function "better_supabase"."revise_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = revise_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft is edited, not revised' using errcode = '55000', hint = 'QUOTE_NOT_SENT';
  end if;
  if v_row."status" = 'accepted' then
    raise exception 'an accepted quote stays as accepted; start a new quote' using errcode = '55000', hint = 'QUOTE_ACCEPTED';
  end if;
  if revise_quote.actor is not null then
    if jsonb_typeof(revise_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(revise_quote.actor ->> 'ip', '')::inet, nullif(revise_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(revise_quote.actor::text, ''), true);
  update "better_supabase"."quotes" x set "status" = 'draft', "revision" = x."revision" + 1, "token_hash" = null, "sent_at" = null, "viewed_at" = null,
    "valid_until" = greatest(x."valid_until", current_date + 30),
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."revise_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."revise_quote"(uuid, jsonb) to authenticated, service_role;

-- Takes back a sent or expired quote the customer hasn't accepted: it can't
-- be answered any more until it is revised and sent again. The actor and
-- reason go to the state machine's history.
drop function if exists "better_supabase"."withdraw_quote"(uuid, jsonb);
create or replace function "better_supabase"."withdraw_quote"(quote uuid, actor jsonb default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = withdraw_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" not in ('sent', 'viewed', 'changes_requested', 'expired') then
    raise exception 'only a sent quote that wasn''t answered is withdrawn' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if withdraw_quote.actor is not null then
    if jsonb_typeof(withdraw_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(withdraw_quote.actor ->> 'ip', '')::inet, nullif(withdraw_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(withdraw_quote.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(withdraw_quote.reason), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = 'withdrawn', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) to authenticated, service_role;

-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name,
-- and without it or an actor the answer names no one. The note is also the
-- reason in the state machine's history.
-- selected lists the positions of the optional lines they took. actor is
-- the customer when the app takes the answer in its own portal: id, name,
-- email, ip and userAgent, kept with the answer and in the state machine's
-- history; a quote past its valid date then expires instead, and the expired
-- quote is returned.
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text);
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."decide_quote"(quote uuid, decision text, note text, by text, selected jsonb default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decided_user_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) to authenticated, service_role;

-- What the customer sees through the link: the quote without internal
-- notes. Opening a sent quote marks it viewed. Callable without signing in.
create or replace function "better_supabase"."public_quote"(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(public_quote.token, 'sha256'), 'hex');
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke all on function "better_supabase"."public_quote"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."public_quote"(text) to anon, authenticated, service_role;

-- The customer's answer through the link: accepted, rejected or
-- changes_requested, with their name, a note and the optional lines they
-- took. Their address and browser are kept with the answer. A quote past its
-- valid date expires instead.
drop function if exists "better_supabase"."respond_to_quote"(text, text, text, text);
create or replace function "better_supabase"."respond_to_quote"(token text, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(respond_to_quote.token, 'sha256'), 'hex') for update;
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  if respond_to_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(respond_to_quote.name), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_quote.selected is not null then
      if jsonb_typeof(respond_to_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(respond_to_quote.name), ''),
    "decision_note" = nullif(trim(respond_to_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke all on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) to anon, authenticated, service_role;

-- A quote shared with the signed-in guest, as the customer sees it: through
-- a grant on the quote or as a guest of its company or contact. Opening a
-- sent quote marks it viewed. No link token is needed. The service role
-- reads it too, for an app's own portal; actor is then the customer who
-- opened it, for the state machine's history.
drop function if exists "better_supabase"."portal_quote"(uuid);
create or replace function "better_supabase"."portal_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if portal_quote.actor is not null and not (auth.role() = 'service_role') then
    raise exception 'only the service role names who opened a quote' using errcode = '42501', hint = 'QUOTE_ACTOR_FORBIDDEN';
  end if;
  if portal_quote.actor is not null then
    if jsonb_typeof(portal_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(portal_quote.actor ->> 'ip', '')::inet, nullif(portal_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(portal_quote.actor::text, ''), true);
  if portal_quote.actor is null then
    begin
      v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
    exception when invalid_text_representation then
      v_ip := null;
    end;
    perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = portal_quote.quote and (false or ((auth.role() = 'service_role') and x."status" <> 'draft'));
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."portal_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."portal_quote"(uuid, jsonb) to authenticated, service_role;

-- The signed-in guest's answer to a quote shared with them, like
-- respond_to_quote without a token. name defaults to their email; the
-- answer keeps who they are, their address and their browser.
create or replace function "better_supabase"."respond_to_portal_quote"(quote uuid, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = respond_to_portal_quote.quote and false for update;
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if respond_to_portal_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_portal_quote.selected is not null then
      if jsonb_typeof(respond_to_portal_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_portal_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_portal_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_portal_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''),
    "decision_note" = nullif(trim(respond_to_portal_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_portal_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_portal_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) to authenticated, service_role;

-- The versions of a quote that were sent, oldest first, without their
-- snapshots.
create or replace function "better_supabase"."quote_versions"(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_versions.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('revision', x."revision", 'total', x."total"::text, 'currency', x."currency",
      'publishedAt', x."published_at", 'publishedBy', x."published_by") order by x."revision")
    from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id"), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."quote_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_versions"(uuid) to authenticated, service_role;

-- The quote as it was sent at revision: the snapshot published then.
create or replace function "better_supabase"."quote_version"(quote uuid, revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_version "better_supabase"."quote_versions";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_version.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id" and x."revision" = quote_version.revision;
  if v_version."id" is null then
    raise exception 'this quote has no such version' using errcode = 'P0002', hint = 'QUOTE_VERSION_NOT_FOUND';
  end if;
  return v_version."snapshot" || jsonb_build_object('revision', v_version."revision", 'publishedAt', v_version."published_at");
end;
$$;
revoke execute on function "better_supabase"."quote_version"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."quote_version"(uuid, integer) to authenticated, service_role;

-- Expires sent quotes past their valid date. Run it daily from a job.
create or replace function "better_supabase"."expire_quotes"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_count integer := 0;
begin
  perform set_config('better_supabase.transition_actor', '', true);
  for v_row in
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now()
    where x."status" in ('sent', 'viewed') and x."valid_until" < current_date
    returning *
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_quotes"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_quotes"() to service_role;

-- Makes another variant of a quote: a new draft quote with the same pricing,
-- party and lines, grouped under the same root. label names it (A, B, Basic,
-- Premium) and is unique within the group; attrs change the new quote like
-- create_quote's. The first variant gives the quote it came from the label
-- Original when it has none.
create or replace function "better_supabase"."create_quote_variant"(quote uuid, label text, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
  v_root uuid;
  v_label text := nullif(trim(create_quote_variant.label), '');
  v_made jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."quotes" x where x."id" = create_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_src."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_label is null or length(v_label) > 100 then
    raise exception 'a variant needs a label of up to 100 characters' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  v_root := coalesce(v_src."variant_of", v_src."id");
  if exists (select 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) and lower(x."variant_label") = lower(v_label)) then
    raise exception 'another variant of this quote has that label' using errcode = '23505', hint = 'QUOTE_VARIANT_LABEL_TAKEN';
  end if;
  v_made := "better_supabase"."create_quote"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'currency', v_src."currency", 'validUntil', v_src."valid_until",
    'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'terms', v_src."terms", 'note', v_src."note", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount"::text, 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount"::text, 'depositRequired', v_src."deposit_required")) || coalesce(create_quote_variant.attrs, '{}'::jsonb), null);
  v_id := (v_made ->> 'id')::uuid;
  insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position", "section", "optional", "selected", "periods")
  select x."tenant_id", v_id, x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position", x."section", x."optional", x."selected", x."periods" from "better_supabase"."quote_lines" x where x."parent_id" = v_src."id";
  update "better_supabase"."quotes" x set "variant_label" = coalesce(x."variant_label", 'Original')
  where x."id" = v_root;
  update "better_supabase"."quotes" x set "variant_of" = v_root, "variant_label" = v_label, "is_selected" = false
  where x."id" = v_id;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) to authenticated, service_role;

-- The quotes of one group of variants, the root first. isSelected tells which
-- one the customer chose.
create or replace function "better_supabase"."list_quote_variants"(quote uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
begin
  select * into v_src from "better_supabase"."quotes" x where x."id" = list_quote_variants.quote;
  if v_src."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'quotes.read'), false)) then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = coalesce(v_src."variant_of", v_src."id") or x."variant_of" = coalesce(v_src."variant_of", v_src."id")));
end;
$$;
revoke execute on function "better_supabase"."list_quote_variants"(uuid) from public, anon;
grant execute on function "better_supabase"."list_quote_variants"(uuid) to authenticated, service_role;

-- Selects one variant of a quote and marks the others of its group not
-- selected; only the selected variant becomes an order or an invoice. A
-- withdrawn, rejected or expired variant can't be selected. options.forward
-- is order or invoice to copy the selected variant forward in the same call
-- (the quote must be accepted, as for order_from_quote and invoice_from_quote);
-- options.attrs go to order_from_quote and options.depositBps to
-- invoice_from_quote.
create or replace function "better_supabase"."select_quote_variant"(quote uuid, options jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_root uuid;
  v_forward text := nullif(select_quote_variant.options ->> 'forward', '');
  v_order jsonb;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = select_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  v_root := coalesce(v_row."variant_of", v_row."id");
  if v_row."variant_of" is null and not exists (select 1 from "better_supabase"."quotes" x where x."variant_of" = v_row."id") then
    raise exception 'this quote has no variants' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  if v_row."status" in ('withdrawn', 'rejected', 'expired') then
    raise exception 'a withdrawn, rejected or expired variant can''t be selected' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTABLE';
  end if;
  if v_forward is not null and v_forward not in ('') then
    raise exception 'forward is order or invoice' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  perform 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) for update;
  update "better_supabase"."quotes" x set "is_selected" = (x."id" = v_row."id"), "updated_at" = now()
  where (x."id" = v_root or x."variant_of" = v_root) and x."is_selected" is distinct from (x."id" = v_row."id");
  if v_forward is not null and v_order is null and v_invoice is null then
    raise exception 'the organization has no block to copy the variant forward to' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  return jsonb_build_object('quote', (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), 'variants', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root)), 'order', v_order, 'invoice', v_invoice);
end;
$$;
revoke execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) to authenticated, service_role;

-- The import target of the quote entity (ADR 0141): item.data is { number,
-- status?, title?, currency, validUntil?, createdAt?, sentAt?, viewedAt?,
-- decidedAt?, decidedBy?, decisionNote?, company?, contact?, origin?,
-- pricesIncludeTax?, attrs?, legalEntityId?, buyer?, lines, taxLines?,
-- totals? }. A quote that is already imported is kept as it is.
create or replace function "better_supabase"."import_quote"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_quote.item ->> 'tenant')::uuid;
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."quotes";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from "better_supabase"."quotes" y where y."id" = import_quote.subject_id::uuid and y."tenant_id" = v_tenant;
    if not found then
      raise exception 'the quote no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
  end if;
  if v_number is null then
    raise exception 'a quote needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    raise exception 'status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a quote needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  v_made := "better_supabase"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Quote ' || v_number),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> 'id')::uuid;
  update "better_supabase"."quotes" y set
    "status" = coalesce(v_data ->> 'status', 'draft'),
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
    "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
    "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
    "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
    "decided_by" = nullif(v_data ->> 'decidedBy', ''),
    "decision_note" = nullif(v_data ->> 'decisionNote', ''),
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
    "updated_at" = now()
  where y."id" = v_id;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(z."tax_code", '') || ':' || z."tax_rate_bps"::text as key, sum(z."net") as net, sum(z."tax") as tax
        from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id;
    insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint), coalesce((g.value ->> 'discount')::bigint, 0)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."quotes" y set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, y."total")
    where y."id" = v_id;
  end if;
  select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_quote"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_quote"(uuid, jsonb, text) to service_role;

-- When a quote last changed, for the conflict check of imports.
create or replace function "better_supabase"."quote_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select y."updated_at" from "better_supabase"."quotes" y where y."id" = $1::uuid
$$;
revoke execute on function "better_supabase"."quote_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."quote_updated_at"(text) to service_role;

-- Totals and cost of one record's lines per billing party (ADR 0141). It runs
-- as the caller, so only lines the caller can read count.
create or replace function "better_supabase"."quote_totals_by_billing_party"(quote uuid)
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
        'lines', count(*), 'net', sum((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))))::text, 'cost', sum(round(l."quantity" * l."unit_cost"))::text
      ) as row
    from "better_supabase"."quote_lines" l
    where l."parent_id" = quote and (not l."optional" or l."selected")
    group by 1, 2, 3
  ) g
$$;
revoke execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
create policy bsb_tenant_scope_select on "better_supabase"."quotes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
create policy bsb_tenant_scope_insert on "better_supabase"."quotes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
create policy bsb_tenant_scope_update on "better_supabase"."quotes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
create policy bsb_tenant_scope_delete on "better_supabase"."quotes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_select on "better_supabase"."quote_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_update on "better_supabase"."quote_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block-data quotes
-- @bsb-hash sha256:fe87f8a5895a1bef6d16712af52cf95116d938edc0a677538bebf4ee466198f0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block quotes@3 managed
-- @bsb-hash sha256:297902127f15808d71bf77e204b92e4ccdbafe2b7f9f060cf0ef338f7e1d258f
-- Quotes with sections, optional lines, discounts, prices with or without tax, tax per rate and a deposit; published versions; a public link or the signed-in portal the customer accepts, rejects or asks changes through; expiry; and quotes from deals. With catalog, a line that names a product variant takes its price and title.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Quotes: line items, sections, optional lines, discounts and tax per rate,
-- published versions, sending with a public link or to the signed-in portal
-- the customer accepts, rejects or asks changes through, and expiry.

create table if not exists "better_supabase"."quotes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "revision" integer not null default 1,
  "title" text not null check (length("title") between 1 and 300),
  "company_type" text,
  "company_id" text,
  "contact_type" text,
  "contact_id" text,
  "owner_user_id" uuid,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn')),
  "valid_until" date,
  "terms" text,
  "note" text,
  "origin_type" text,
  "origin_id" text,
  "token_hash" text unique,
  "sent_at" timestamptz,
  "viewed_at" timestamptz,
  "decided_at" timestamptz,
  "decided_by" text,
  "decision_note" text,
  "decided_user_id" uuid,
  "decided_ip" text,
  "decided_user_agent" text,
  "prices_include_tax" boolean not null default false,
  "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000),
  "discount_amount" bigint not null default 0 check ("discount_amount" >= 0),
  "deposit_bps" integer check ("deposit_bps" > 0 and "deposit_bps" < 10000),
  "deposit_amount" bigint check ("deposit_amount" > 0),
  "deposit_required" boolean not null default false,
  "deposit_due" bigint not null default 0,
  "unpublished_changes" boolean not null default false,
  "buyer" jsonb,
  "variant_of" uuid,
  "variant_label" text check (length("variant_label") between 1 and 100),
  "is_selected" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "list_total" bigint not null default 0,
  "discount_total" bigint not null default 0,
  "subtotal" bigint not null default 0,
  "tax_total" bigint not null default 0,
  "total" bigint not null default 0,
  unique ("tenant_id", "number", "revision"),
  check (("company_type" is null) = ("company_id" is null)),
  check (("origin_type" is null) = ("origin_id" is null))
);
alter table "better_supabase"."quotes" add column if not exists "deposit_amount" bigint check ("deposit_amount" > 0);
alter table "better_supabase"."quotes" add column if not exists "deposit_required" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "unpublished_changes" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "buyer" jsonb;
alter table "better_supabase"."quotes" add column if not exists "variant_of" uuid;
alter table "better_supabase"."quotes" add column if not exists "variant_label" text check (length("variant_label") between 1 and 100);
alter table "better_supabase"."quotes" add column if not exists "is_selected" boolean not null default false;
create index if not exists quotes_tenant_status_idx on "better_supabase"."quotes" ("tenant_id", "status", "created_at" desc);
create index if not exists quotes_variant_idx on "better_supabase"."quotes" ("variant_of") where "variant_of" is not null;
create index if not exists quotes_origin_idx on "better_supabase"."quotes" ("origin_type", "origin_id");

alter table "better_supabase"."quotes" enable row level security;
revoke all on "better_supabase"."quotes" from public, anon, authenticated;
grant select on "better_supabase"."quotes" to authenticated;
grant all on "better_supabase"."quotes" to service_role;
drop policy if exists quotes_read on "better_supabase"."quotes";
create policy quotes_read on "better_supabase"."quotes"
  for select to authenticated
  using (("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read'))) or ("status" <> 'draft' and ((("tenant_id")::text, ('quote')::text, ("id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or (("tenant_id")::text, ("company_type")::text, ("company_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g) or (("tenant_id")::text, ("contact_type")::text, ("contact_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))));

create table if not exists "better_supabase"."quote_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "quote_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
  "revision" integer not null,
  "snapshot" jsonb not null,
  "total" bigint not null,
  "currency" char(3) not null,
  "published_by" uuid,
  "published_at" timestamptz not null default now(),
  unique ("quote_id", "revision")
);
alter table "better_supabase"."quote_versions" enable row level security;
revoke all on "better_supabase"."quote_versions" from public, anon, authenticated;
grant select on "better_supabase"."quote_versions" to authenticated;
grant all on "better_supabase"."quote_versions" to service_role;
drop policy if exists quote_versions_read on "better_supabase"."quote_versions";
create policy quote_versions_read on "better_supabase"."quote_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"));
create or replace function better_supabase.bsb_quote_versions_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'a published quote version never changes' using errcode = '55000', hint = 'QUOTE_VERSION_FROZEN';
end;
$$;
revoke execute on function better_supabase.bsb_quote_versions_frozen() from public, anon, authenticated;
drop trigger if exists "bsb_quote_versions_frozen" on "better_supabase"."quote_versions";
create trigger "bsb_quote_versions_frozen" before update on "better_supabase"."quote_versions"
for each row execute function better_supabase.bsb_quote_versions_frozen();

create table if not exists "better_supabase"."quote_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0
);
create index if not exists quote_tax_lines_parent_idx on "better_supabase"."quote_tax_lines" ("parent_id");
alter table "better_supabase"."quote_tax_lines" enable row level security;
revoke all on "better_supabase"."quote_tax_lines" from public, anon, authenticated;
grant select on "better_supabase"."quote_tax_lines" to authenticated;
grant all on "better_supabase"."quote_tax_lines" to service_role;
drop policy if exists quote_tax_lines_read on "better_supabase"."quote_tax_lines";
create policy quote_tax_lines_read on "better_supabase"."quote_tax_lines"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"));

-- Creates a draft quote. attrs: title (required), currency, company and
-- contact ({ type, id }), ownerId, validUntil, terms, note, origin ({ type,
-- id }, the record it was made from), pricesIncludeTax, discountBps,
-- discountAmount (minor units as text), depositBps, or depositAmount (minor
-- units as text) for a fixed deposit, and depositRequired, which makes the
-- customer pay it before they accept. lines: see set_quote_lines.
create or replace function "better_supabase"."create_quote"(tenant uuid, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "prices_include_tax", "discount_bps", "discount_amount", "deposit_bps", "deposit_amount", "deposit_required", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id',
      coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce((create_quote.attrs ->> 'discountBps')::integer, 0), coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0), (create_quote.attrs ->> 'depositBps')::integer, (create_quote.attrs ->> 'depositAmount')::bigint, coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    insert into "better_supabase"."relations" ("tenant_id", "kind", "source_type", "source_id", "target_type", "target_id", "created_by")
    select v_row."tenant_id", 'created_from', 'quote', v_row."id"::text, v_row."origin_type", v_row."origin_id", auth.uid()
    where not exists (
      select 1 from "better_supabase"."relations" x
      where x."kind" = 'created_from' and x."source_type" = 'quote' and x."source_id" = v_row."id"::text
    );
  end if;
  perform "better_supabase".emit_event('quote.created', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft quote, or one the customer asked changes on: title,
-- company, contact, currency, ownerId, validUntil, terms, note,
-- pricesIncludeTax, discountBps, discountAmount, depositBps, depositAmount
-- and depositRequired. The totals follow the new pricing.
create or replace function "better_supabase"."update_quote"(quote uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_user_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "prices_include_tax" = case when update_quote.attrs ? 'pricesIncludeTax' then coalesce((update_quote.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "discount_bps" = case when update_quote.attrs ? 'discountBps' then coalesce((update_quote.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_quote.attrs ? 'discountAmount' then coalesce((update_quote.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "deposit_bps" = case when update_quote.attrs ? 'depositBps' then (update_quote.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "deposit_amount" = case when update_quote.attrs ? 'depositAmount' then (update_quote.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "deposit_required" = case when update_quote.attrs ? 'depositRequired' then coalesce((update_quote.attrs ->> 'depositRequired')::boolean, false) else x."deposit_required" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  perform "better_supabase"."set_quote_lines_recount"(v_row."id");
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  perform "better_supabase".emit_event('quote.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."update_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_quote"(uuid, jsonb) to authenticated, service_role;
create table if not exists "better_supabase"."quote_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
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
  "section" text check (length("section") between 1 and 300),
  "optional" boolean not null default false,
  "selected" boolean not null default true,
  "periods" integer not null default 1 check ("periods" > 0),
  "position" integer not null,
  "created_at" timestamptz not null default now(),
  check (("product_type" is null) = ("product_id" is null))
);
alter table "better_supabase"."quote_lines" add column if not exists "periods" integer not null default 1 check ("periods" > 0);
create index if not exists "quote_lines_parent_idx" on "better_supabase"."quote_lines" ("parent_id", "position");
alter table "better_supabase"."quote_lines" enable row level security;
revoke all on "better_supabase"."quote_lines" from public, anon, authenticated;
grant select on "better_supabase"."quote_lines" to authenticated;
grant all on "better_supabase"."quote_lines" to service_role;
drop policy if exists "quote_lines_read" on "better_supabase"."quote_lines";
create policy "quote_lines_read" on "better_supabase"."quote_lines" for select to authenticated
using (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"));

-- Writes a record's totals from its counted lines: an optional line counts
-- only when the customer took it. The record discount is spread over the tax
-- rates in proportion to their amounts, and tax is counted once per rate, so
-- the totals and the tax per rate always add up.
create or replace function "better_supabase"."set_quote_lines_recount"(parent uuid)
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
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount", 0
    into v_tenant, v_inclusive, v_record_bps, v_record_amount, v_restriction
  from "better_supabase"."quotes" x where x."id" = set_quote_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount")), 0), coalesce(sum((round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))), 0)
    into v_list, v_line_discount
  from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected");
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) as amount,
      sum(round((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * (10000 - v_restriction) * l."tax_rate_bps" / (10000.0 * (case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)))) as tax
    from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected")
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
  delete from "better_supabase"."quote_tax_lines" x where x."parent_id" = set_quote_lines_recount.parent;
  insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
  select v_tenant, set_quote_lines_recount.parent, r.rate, r.code, r.net, r.tax, r.gross, r.discount
  from jsonb_to_recordset(v_groups) r(rate integer, code text, net bigint, tax bigint, gross bigint, discount bigint);
  update "better_supabase"."quotes" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_subtotal,
    "tax_total" = v_tax,
    "total" = v_total,
    "deposit_due" = case when x."deposit_amount" is not null then least(greatest(v_total, 0), x."deposit_amount") when x."deposit_bps" is not null then round(v_total * x."deposit_bps" / 10000.0)::bigint else 0 end
  where x."id" = set_quote_lines_recount.parent;
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines_recount"(uuid) from public, anon, authenticated;

-- Recounts each record a statement touched once, in id order so concurrent
-- statements lock the records in the same order. A transition table needs a
-- trigger per event, so there are three triggers on one function. The
-- transition tables are read through execute because plpgsql_check (db lint)
-- doesn't know them.
create or replace function better_supabase.bsb_quote_lines_totals()
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
    perform "better_supabase"."set_quote_lines_recount"(v_parent);
  end loop;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_quote_lines_totals() from public, anon, authenticated;
drop trigger if exists bsb_quote_lines_totals on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_insert on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_update on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_delete on "better_supabase"."quote_lines";
create trigger bsb_quote_lines_totals_insert after insert on "better_supabase"."quote_lines"
referencing new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_update after update on "better_supabase"."quote_lines"
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_delete after delete on "better_supabase"."quote_lines"
referencing old table as old_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
-- A line without unitAmount or description takes them from its product.
create or replace function "better_supabase"."set_quote_lines"(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := set_quote_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."quotes" x where x."id" = v_parent and not (not (x."status" in ('draft', 'changes_requested')));
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."quotes" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false))) then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_quote_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_quote_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."quote_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "section", "optional", "selected", "periods", "position")
    select v_tenant,
      v_parent,
      x.value -> 'product' ->> 'type',
      x.value -> 'product' ->> 'id',
      coalesce(x.value ->> 'description', (select coalesce(v."title", (select p."title" from "better_supabase"."products" p where p."id" = v."product_id")) from "better_supabase"."product_variants" v where x.value -> 'product' ->> 'type' = 'product_variant' and v."id" = (x.value -> 'product' ->> 'id')::uuid and v."tenant_id" = v_tenant)),
      coalesce((x.value ->> 'quantity')::numeric, 1),
      coalesce((x.value ->> 'unitAmount')::bigint, (select ("better_supabase"."variant_price"(v."id", v_currency) ->> 'amount')::bigint from "better_supabase"."product_variants" v where x.value -> 'product' ->> 'type' = 'product_variant' and v."id" = (x.value -> 'product' ->> 'id')::uuid and v."tenant_id" = v_tenant)),
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
      nullif(trim(x.value ->> 'section'), ''),
      coalesce((x.value ->> 'optional')::boolean, false),
      coalesce((x.value ->> 'selected')::boolean, not coalesce((x.value ->> 'optional')::boolean, false)),
      coalesce((x.value ->> 'periods')::integer, 1),
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_quote_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_quote_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."quotes" x where x."id" = v_parent);
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) to authenticated, service_role;

-- Sends a quote: it gets a public link the customer opens and a published
-- version, a snapshot that never changes. The quote can't change until it is
-- revised or the customer asks for changes; sending it again then publishes
-- the next revision. Returns the quote with the link's token, which is stored
-- only as a hash and returned this once.
-- actor: who sent it, for the state machine's history.
drop function if exists "better_supabase"."send_quote"(uuid);
create or replace function "better_supabase"."send_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = send_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'the quote was already sent; revise it to send a new version' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if not exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_row."id") then
    raise exception 'a quote needs a line before it is sent' using errcode = '23514', hint = 'QUOTE_EMPTY';
  end if;
  if send_quote.actor is not null then
    if jsonb_typeof(send_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(send_quote.actor ->> 'ip', '')::inet, nullif(send_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(send_quote.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "revision" = case when exists (select 1 from "better_supabase"."quote_versions" v where v."quote_id" = x."id" and v."revision" = x."revision") then x."revision" + 1 else x."revision" end,
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "better_supabase"."quote_versions" ("tenant_id", "quote_id", "revision", "snapshot", "total", "currency", "published_by")
  values (v_row."tenant_id", v_row."id", v_row."revision", (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), v_row."total", v_row."currency", coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid))
  returning "id" into v_version;
  perform "better_supabase".emit_event('quote.sent', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'revision', v_row."revision"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)) || jsonb_build_object('token', v_token);
end;
$$;
revoke execute on function "better_supabase"."send_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."send_quote"(uuid, jsonb) to authenticated, service_role;

-- Opens a sent or declined quote again as a draft of its next revision: the
-- same quote, number and lines, a fresh valid-until date, and its link ends.
-- The versions already published stay as they were. An accepted quote is
-- kept as the customer accepted it; start a new quote instead.
drop function if exists "better_supabase"."revise_quote"(uuid);
create or replace function "better_supabase"."revise_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = revise_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft is edited, not revised' using errcode = '55000', hint = 'QUOTE_NOT_SENT';
  end if;
  if v_row."status" = 'accepted' then
    raise exception 'an accepted quote stays as accepted; start a new quote' using errcode = '55000', hint = 'QUOTE_ACCEPTED';
  end if;
  if revise_quote.actor is not null then
    if jsonb_typeof(revise_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(revise_quote.actor ->> 'ip', '')::inet, nullif(revise_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(revise_quote.actor::text, ''), true);
  update "better_supabase"."quotes" x set "status" = 'draft', "revision" = x."revision" + 1, "token_hash" = null, "sent_at" = null, "viewed_at" = null,
    "valid_until" = greatest(x."valid_until", current_date + 30),
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('quote.revised', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'revision', v_row."revision"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."revise_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."revise_quote"(uuid, jsonb) to authenticated, service_role;

-- Takes back a sent or expired quote the customer hasn't accepted: it can't
-- be answered any more until it is revised and sent again. The actor and
-- reason go to the state machine's history.
drop function if exists "better_supabase"."withdraw_quote"(uuid, jsonb);
create or replace function "better_supabase"."withdraw_quote"(quote uuid, actor jsonb default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = withdraw_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" not in ('sent', 'viewed', 'changes_requested', 'expired') then
    raise exception 'only a sent quote that wasn''t answered is withdrawn' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if withdraw_quote.actor is not null then
    if jsonb_typeof(withdraw_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(withdraw_quote.actor ->> 'ip', '')::inet, nullif(withdraw_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(withdraw_quote.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(withdraw_quote.reason), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = 'withdrawn', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  perform "better_supabase".emit_event('quote.withdrawn', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'revision', v_row."revision"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) to authenticated, service_role;

-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name,
-- and without it or an actor the answer names no one. The note is also the
-- reason in the state machine's history.
-- selected lists the positions of the optional lines they took. actor is
-- the customer when the app takes the answer in its own portal: id, name,
-- email, ip and userAgent, kept with the answer and in the state machine's
-- history; a quote past its valid date then expires instead, and the expired
-- quote is returned.
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text);
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."decide_quote"(quote uuid, decision text, note text, by text, selected jsonb default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decided_user_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_user_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_user_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) to authenticated, service_role;

-- What the customer sees through the link: the quote without internal
-- notes. Opening a sent quote marks it viewed. Callable without signing in.
create or replace function "better_supabase"."public_quote"(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(public_quote.token, 'sha256'), 'hex');
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.viewed', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke all on function "better_supabase"."public_quote"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."public_quote"(text) to anon, authenticated, service_role;

-- The customer's answer through the link: accepted, rejected or
-- changes_requested, with their name, a note and the optional lines they
-- took. Their address and browser are kept with the answer. A quote past its
-- valid date expires instead.
drop function if exists "better_supabase"."respond_to_quote"(text, text, text, text);
create or replace function "better_supabase"."respond_to_quote"(token text, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(respond_to_quote.token, 'sha256'), 'hex') for update;
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  if respond_to_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(respond_to_quote.name), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_quote.selected is not null then
      if jsonb_typeof(respond_to_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(respond_to_quote.name), ''),
    "decision_note" = nullif(trim(respond_to_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_user_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_user_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if respond_to_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke all on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) to anon, authenticated, service_role;

-- A quote shared with the signed-in guest, as the customer sees it: through
-- a grant on the quote or as a guest of its company or contact. Opening a
-- sent quote marks it viewed. No link token is needed. The service role
-- reads it too, for an app's own portal; actor is then the customer who
-- opened it, for the state machine's history.
drop function if exists "better_supabase"."portal_quote"(uuid);
create or replace function "better_supabase"."portal_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if portal_quote.actor is not null and not (auth.role() = 'service_role') then
    raise exception 'only the service role names who opened a quote' using errcode = '42501', hint = 'QUOTE_ACTOR_FORBIDDEN';
  end if;
  if portal_quote.actor is not null then
    if jsonb_typeof(portal_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(portal_quote.actor ->> 'ip', '')::inet, nullif(portal_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(portal_quote.actor::text, ''), true);
  if portal_quote.actor is null then
    begin
      v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
    exception when invalid_text_representation then
      v_ip := null;
    end;
    perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = portal_quote.quote and ((x."status" <> 'draft' and (((x."tenant_id")::text, ('quote')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or ((x."tenant_id")::text, (x."company_type")::text, (x."company_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g) or ((x."tenant_id")::text, (x."contact_type")::text, (x."contact_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) or ((auth.role() = 'service_role') and x."status" <> 'draft'));
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.viewed', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."portal_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."portal_quote"(uuid, jsonb) to authenticated, service_role;

-- The signed-in guest's answer to a quote shared with them, like
-- respond_to_quote without a token. name defaults to their email; the
-- answer keeps who they are, their address and their browser.
create or replace function "better_supabase"."respond_to_portal_quote"(quote uuid, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = respond_to_portal_quote.quote and (x."status" <> 'draft' and (((x."tenant_id")::text, ('quote')::text, (x."id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or ((x."tenant_id")::text, (x."company_type")::text, (x."company_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g) or ((x."tenant_id")::text, (x."contact_type")::text, (x."contact_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))) for update;
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if respond_to_portal_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_portal_quote.selected is not null then
      if jsonb_typeof(respond_to_portal_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_portal_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_portal_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_portal_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''),
    "decision_note" = nullif(trim(respond_to_portal_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_portal_quote.decision
    when 'accepted' then
      perform "better_supabase".emit_event('quote.accepted', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'total', v_row."total"::text, 'currency', v_row."currency", 'byName', v_row."decided_by", 'revision', v_row."revision", 'depositDue', v_row."deposit_due"::text), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    when 'rejected' then
      perform "better_supabase".emit_event('quote.rejected', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    else
      perform "better_supabase".emit_event('quote.changes_requested', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier", 'note', v_row."decision_note"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
  end case;
  if v_row."owner_user_id" is not null then
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'quote.decided',
      'tenant', v_row."tenant_id",
      'subject_type', 'quote',
      'subject_id', v_row."id"::text,
      'subject_label', v_row."identifier" || ' ' || v_row."title",
      'summary', v_row."identifier" || ' ' || v_row."title",
      'recipients', jsonb_build_array(v_row."owner_user_id"),
      'key', 'quote.decided:' || v_row."id"::text,
      'data', jsonb_build_object('quoteId', v_row."id", 'status', v_row."status")
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) to authenticated, service_role;

-- The versions of a quote that were sent, oldest first, without their
-- snapshots.
create or replace function "better_supabase"."quote_versions"(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_versions.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('revision', x."revision", 'total', x."total"::text, 'currency', x."currency",
      'publishedAt', x."published_at", 'publishedBy', x."published_by") order by x."revision")
    from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id"), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."quote_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_versions"(uuid) to authenticated, service_role;

-- The quote as it was sent at revision: the snapshot published then.
create or replace function "better_supabase"."quote_version"(quote uuid, revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_version "better_supabase"."quote_versions";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_version.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id" and x."revision" = quote_version.revision;
  if v_version."id" is null then
    raise exception 'this quote has no such version' using errcode = 'P0002', hint = 'QUOTE_VERSION_NOT_FOUND';
  end if;
  return v_version."snapshot" || jsonb_build_object('revision', v_version."revision", 'publishedAt', v_version."published_at");
end;
$$;
revoke execute on function "better_supabase"."quote_version"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."quote_version"(uuid, integer) to authenticated, service_role;

-- Expires sent quotes past their valid date. Run it daily from a job.
create or replace function "better_supabase"."expire_quotes"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_count integer := 0;
begin
  perform set_config('better_supabase.transition_actor', '', true);
  for v_row in
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now()
    where x."status" in ('sent', 'viewed') and x."valid_until" < current_date
    returning *
  loop
    perform "better_supabase".emit_event('quote.expired', jsonb_build_object('organizationId', v_row."tenant_id", 'quoteId', v_row."id", 'subjectType', 'quote', 'subjectId', v_row."id"::text, 'identifier', v_row."identifier"), 'quotes/' || v_row."id"::text, (v_row."tenant_id"::text)::text, null, 'better-supabase/quotes');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_quotes"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_quotes"() to service_role;

-- A draft quote from a deal: its name, company, primary contact, currency,
-- owner and lines (or one line for its amount). Converting a deal again
-- returns the quote it already made.
create or replace function "better_supabase"."quote_from_deal"(deal uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deal "better_supabase"."deals";
  v_row "better_supabase"."quotes";
  v_contact record;
  v_lines jsonb;
begin
  select * into v_deal from "better_supabase"."deals" x where x."id" = quote_from_deal.deal;
  if v_deal."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_deal."tenant_id", 'quotes.write'), false)) then
    raise exception 'no such deal you can quote' using errcode = 'P0002', hint = 'QUOTE_ORIGIN_NOT_FOUND';
  end if;
  select * into v_row from "better_supabase"."quotes" x
  where x."origin_type" = 'deal' and x."origin_id" = v_deal."id"::text
  order by x."created_at" limit 1;
  if v_row."id" is not null then
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  select x."contact_type" as type, x."contact_id" as id into v_contact
  from "better_supabase"."deal_contacts" x where x."deal_id" = v_deal."id" order by x."is_primary" desc limit 1;
  select coalesce(jsonb_agg(jsonb_build_object('description', x."description", 'quantity', x."quantity", 'unitAmount', x."unit_amount"::text,
      'discountBps', x."discount_bps", 'taxRateBps', x."tax_rate_bps", 'taxCode', x."tax_code",
      'product', case when x."product_type" is null then null else jsonb_build_object('type', x."product_type", 'id', x."product_id") end
    ) order by x."position"), '[]'::jsonb) into v_lines
  from "better_supabase"."deal_lines" x where x."parent_id" = v_deal."id";
  if jsonb_array_length(v_lines) = 0 and v_deal."amount" > 0 then
    v_lines := jsonb_build_array(jsonb_build_object('description', v_deal."name", 'quantity', 1, 'unitAmount', v_deal."amount"::text));
  end if;
  return "better_supabase"."create_quote"(v_deal."tenant_id", jsonb_build_object(
    'title', v_deal."name", 'currency', v_deal."currency", 'ownerId', v_deal."owner_user_id",
    'company', case when v_deal."company_id" is null then null else jsonb_build_object('type', v_deal."company_type", 'id', v_deal."company_id") end,
    'contact', case when v_contact.id is null then null else jsonb_build_object('type', v_contact.type, 'id', v_contact.id) end,
    'origin', jsonb_build_object('type', 'deal', 'id', v_deal."id"::text)), v_lines);
end;
$$;
revoke execute on function "better_supabase"."quote_from_deal"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_from_deal"(uuid) to authenticated, service_role;

-- Makes another variant of a quote: a new draft quote with the same pricing,
-- party and lines, grouped under the same root. label names it (A, B, Basic,
-- Premium) and is unique within the group; attrs change the new quote like
-- create_quote's. The first variant gives the quote it came from the label
-- Original when it has none.
create or replace function "better_supabase"."create_quote_variant"(quote uuid, label text, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
  v_root uuid;
  v_label text := nullif(trim(create_quote_variant.label), '');
  v_made jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."quotes" x where x."id" = create_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_src."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_label is null or length(v_label) > 100 then
    raise exception 'a variant needs a label of up to 100 characters' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  v_root := coalesce(v_src."variant_of", v_src."id");
  if exists (select 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) and lower(x."variant_label") = lower(v_label)) then
    raise exception 'another variant of this quote has that label' using errcode = '23505', hint = 'QUOTE_VARIANT_LABEL_TAKEN';
  end if;
  v_made := "better_supabase"."create_quote"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'currency', v_src."currency", 'validUntil', v_src."valid_until",
    'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'terms', v_src."terms", 'note', v_src."note", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount"::text, 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount"::text, 'depositRequired', v_src."deposit_required")) || coalesce(create_quote_variant.attrs, '{}'::jsonb), null);
  v_id := (v_made ->> 'id')::uuid;
  insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position", "section", "optional", "selected", "periods")
  select x."tenant_id", v_id, x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position", x."section", x."optional", x."selected", x."periods" from "better_supabase"."quote_lines" x where x."parent_id" = v_src."id";
  update "better_supabase"."quotes" x set "variant_label" = coalesce(x."variant_label", 'Original')
  where x."id" = v_root;
  update "better_supabase"."quotes" x set "variant_of" = v_root, "variant_label" = v_label, "is_selected" = false
  where x."id" = v_id;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) to authenticated, service_role;

-- The quotes of one group of variants, the root first. isSelected tells which
-- one the customer chose.
create or replace function "better_supabase"."list_quote_variants"(quote uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
begin
  select * into v_src from "better_supabase"."quotes" x where x."id" = list_quote_variants.quote;
  if v_src."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'quotes.read'), false)) then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = coalesce(v_src."variant_of", v_src."id") or x."variant_of" = coalesce(v_src."variant_of", v_src."id")));
end;
$$;
revoke execute on function "better_supabase"."list_quote_variants"(uuid) from public, anon;
grant execute on function "better_supabase"."list_quote_variants"(uuid) to authenticated, service_role;

-- Selects one variant of a quote and marks the others of its group not
-- selected; only the selected variant becomes an order or an invoice. A
-- withdrawn, rejected or expired variant can't be selected. options.forward
-- is order or invoice to copy the selected variant forward in the same call
-- (the quote must be accepted, as for order_from_quote and invoice_from_quote);
-- options.attrs go to order_from_quote and options.depositBps to
-- invoice_from_quote.
create or replace function "better_supabase"."select_quote_variant"(quote uuid, options jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_root uuid;
  v_forward text := nullif(select_quote_variant.options ->> 'forward', '');
  v_order jsonb;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = select_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  v_root := coalesce(v_row."variant_of", v_row."id");
  if v_row."variant_of" is null and not exists (select 1 from "better_supabase"."quotes" x where x."variant_of" = v_row."id") then
    raise exception 'this quote has no variants' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  if v_row."status" in ('withdrawn', 'rejected', 'expired') then
    raise exception 'a withdrawn, rejected or expired variant can''t be selected' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTABLE';
  end if;
  if v_forward is not null and v_forward not in ('order', 'invoice') then
    raise exception 'forward is order or invoice' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  perform 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) for update;
  update "better_supabase"."quotes" x set "is_selected" = (x."id" = v_row."id"), "updated_at" = now()
  where (x."id" = v_root or x."variant_of" = v_root) and x."is_selected" is distinct from (x."id" = v_row."id");
  if v_forward = 'order' then
    v_order := "better_supabase"."order_from_quote"(v_row."id", select_quote_variant.options -> 'attrs');
  end if;
  if v_forward = 'invoice' then
    v_invoice := "better_supabase"."invoice_from_quote"(v_row."id", (select_quote_variant.options ->> 'depositBps')::integer);
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  return jsonb_build_object('quote', (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), 'variants', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root)), 'order', v_order, 'invoice', v_invoice);
end;
$$;
revoke execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) to authenticated, service_role;

-- The import target of the quote entity (ADR 0141): item.data is { number,
-- status?, title?, currency, validUntil?, createdAt?, sentAt?, viewedAt?,
-- decidedAt?, decidedBy?, decisionNote?, company?, contact?, origin?,
-- pricesIncludeTax?, attrs?, legalEntityId?, buyer?, lines, taxLines?,
-- totals? }. A quote that is already imported is kept as it is.
create or replace function "better_supabase"."import_quote"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_quote.item ->> 'tenant')::uuid;
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."quotes";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from "better_supabase"."quotes" y where y."id" = import_quote.subject_id::uuid and y."tenant_id" = v_tenant;
    if not found then
      raise exception 'the quote no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
  end if;
  if v_number is null then
    raise exception 'a quote needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    raise exception 'status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a quote needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  v_made := "better_supabase"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Quote ' || v_number),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> 'id')::uuid;
  update "better_supabase"."quotes" y set
    "status" = coalesce(v_data ->> 'status', 'draft'),
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
    "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
    "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
    "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
    "decided_by" = nullif(v_data ->> 'decidedBy', ''),
    "decision_note" = nullif(v_data ->> 'decisionNote', ''),
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
    "updated_at" = now()
  where y."id" = v_id;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(z."tax_code", '') || ':' || z."tax_rate_bps"::text as key, sum(z."net") as net, sum(z."tax") as tax
        from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id;
    insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint), coalesce((g.value ->> 'discount')::bigint, 0)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."quotes" y set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, y."total")
    where y."id" = v_id;
  end if;
  select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_quote"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_quote"(uuid, jsonb, text) to service_role;

-- When a quote last changed, for the conflict check of imports.
create or replace function "better_supabase"."quote_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select y."updated_at" from "better_supabase"."quotes" y where y."id" = $1::uuid
$$;
revoke execute on function "better_supabase"."quote_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."quote_updated_at"(text) to service_role;

-- Totals and cost of one record's lines per billing party (ADR 0141). It runs
-- as the caller, so only lines the caller can read count.
create or replace function "better_supabase"."quote_totals_by_billing_party"(quote uuid)
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
        'lines', count(*), 'net', sum((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))))::text, 'cost', sum(round(l."quantity" * l."unit_cost"))::text
      ) as row
    from "better_supabase"."quote_lines" l
    where l."parent_id" = quote and (not l."optional" or l."selected")
    group by 1, 2, 3
  ) g
$$;
revoke execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
create policy bsb_tenant_scope_select on "better_supabase"."quotes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read'))) or ("status" <> 'draft' and ((("tenant_id")::text, ('quote')::text, ("id"::text)::text) in (select g.tenant, g.subject_type, g.subject_id from better_supabase.portal_subjects('read') g) or (("tenant_id")::text, ("company_type")::text, ("company_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g) or (("tenant_id")::text, ("contact_type")::text, ("contact_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g))))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
create policy bsb_tenant_scope_insert on "better_supabase"."quotes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
create policy bsb_tenant_scope_update on "better_supabase"."quotes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
create policy bsb_tenant_scope_delete on "better_supabase"."quotes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_select on "better_supabase"."quote_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_update on "better_supabase"."quote_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block-data quotes
-- @bsb-hash sha256:00b497b8917469395221371c4ecc8b46ed41520e1b677c52de1dcfa09fecdab4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into "better_supabase"."automation_defaults" ("key", "block", "subject_type", "trigger", "name", "description", "actions", "enabled")
values ('quotes.quote_to_order', 'quotes', 'quote', 'quote.accepted', 'Order each accepted quote', 'Creates an order for the accepted quote, linked created_from the quote, so an accepted quote orders once.', '[{"kind":"orders.from_quote","config":{"targetType":"order"}}]'::jsonb, false)
on conflict ("key") do update set "subject_type" = excluded."subject_type", "trigger" = excluded."trigger", "name" = excluded."name", "description" = excluded."description", "actions" = excluded."actions", "enabled" = excluded."enabled", "block" = excluded."block", "updated_at" = now();

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block quotes@3 managed
-- @bsb-hash sha256:c3a644e2ef418b06da6e8c505d3c4a52cf63d688c27f3bccacd5533badab4369
-- Quotes with sections, optional lines, discounts, prices with or without tax, tax per rate and a deposit; published versions; a public link or the signed-in portal the customer accepts, rejects or asks changes through; expiry; and quotes from deals. With catalog, a line that names a product variant takes its price and title.
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
    drop policy if exists bsb_tenant_scope on "app_private"."quotes";
    drop policy if exists bsb_tenant_scope_select on "app_private"."quotes";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."quotes";
    drop policy if exists bsb_tenant_scope_update on "app_private"."quotes";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."quotes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."quote_lines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."quote_lines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."quote_lines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."quote_lines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."quote_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."quote_versions";
    drop policy if exists bsb_tenant_scope_select on "app_private"."quote_versions";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."quote_versions";
    drop policy if exists bsb_tenant_scope_update on "app_private"."quote_versions";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."quote_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."quote_tax_lines";
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
-- Quotes: line items, sections, optional lines, discounts and tax per rate,
-- published versions, sending with a public link or to the signed-in portal
-- the customer accepts, rejects or asks changes through, and expiry.

create table if not exists "app_private"."quotes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "revision" integer not null default 1,
  "title" text not null check (length("title") between 1 and 300),
  "company_type" text,
  "company_id" text,
  "contact_type" text,
  "contact_id" text,
  "owner_user_id" uuid,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn')),
  "valid_until" date,
  "terms" text,
  "note" text,
  "origin_type" text,
  "origin_id" text,
  "token_hash" text unique,
  "sent_at" timestamptz,
  "viewed_at" timestamptz,
  "decided_at" timestamptz,
  "decided_by" text,
  "decision_note" text,
  "decided_user_id" uuid,
  "decided_ip" text,
  "decided_user_agent" text,
  "prices_include_tax" boolean not null default false,
  "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000),
  "discount_amount" bigint not null default 0 check ("discount_amount" >= 0),
  "deposit_bps" integer check ("deposit_bps" > 0 and "deposit_bps" < 10000),
  "deposit_amount" bigint check ("deposit_amount" > 0),
  "deposit_required" boolean not null default false,
  "deposit_due" bigint not null default 0,
  "unpublished_changes" boolean not null default false,
  "buyer" jsonb,
  "variant_of" uuid,
  "variant_label" text check (length("variant_label") between 1 and 100),
  "is_selected" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "list_total" bigint not null default 0,
  "discount_total" bigint not null default 0,
  "subtotal" bigint not null default 0,
  "tax_total" bigint not null default 0,
  "total" bigint not null default 0,
  unique ("tenant_id", "number", "revision"),
  check (("company_type" is null) = ("company_id" is null)),
  check (("origin_type" is null) = ("origin_id" is null))
);
alter table "app_private"."quotes" add column if not exists "deposit_amount" bigint check ("deposit_amount" > 0);
alter table "app_private"."quotes" add column if not exists "deposit_required" boolean not null default false;
alter table "app_private"."quotes" add column if not exists "unpublished_changes" boolean not null default false;
alter table "app_private"."quotes" add column if not exists "buyer" jsonb;
alter table "app_private"."quotes" add column if not exists "variant_of" uuid;
alter table "app_private"."quotes" add column if not exists "variant_label" text check (length("variant_label") between 1 and 100);
alter table "app_private"."quotes" add column if not exists "is_selected" boolean not null default false;
create index if not exists quotes_tenant_status_idx on "app_private"."quotes" ("tenant_id", "status", "created_at" desc);
create index if not exists quotes_variant_idx on "app_private"."quotes" ("variant_of") where "variant_of" is not null;
create index if not exists quotes_origin_idx on "app_private"."quotes" ("origin_type", "origin_id");

alter table "app_private"."quotes" enable row level security;
revoke all on "app_private"."quotes" from public, anon, authenticated;
grant select on "app_private"."quotes" to authenticated;
grant all on "app_private"."quotes" to service_role;
drop policy if exists quotes_read on "app_private"."quotes";
create policy quotes_read on "app_private"."quotes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')));

create table if not exists "app_private"."quote_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "quote_id" uuid not null references "app_private"."quotes" ("id") on delete cascade,
  "revision" integer not null,
  "snapshot" jsonb not null,
  "total" bigint not null,
  "currency" char(3) not null,
  "published_by" uuid,
  "published_at" timestamptz not null default now(),
  unique ("quote_id", "revision")
);
alter table "app_private"."quote_versions" enable row level security;
revoke all on "app_private"."quote_versions" from public, anon, authenticated;
grant select on "app_private"."quote_versions" to authenticated;
grant all on "app_private"."quote_versions" to service_role;
drop policy if exists quote_versions_read on "app_private"."quote_versions";
create policy quote_versions_read on "app_private"."quote_versions"
  for select to authenticated
  using (exists (select 1 from "app_private"."quotes" q where q."id" = "quote_id"));
create or replace function better_supabase.bsb_quote_versions_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'a published quote version never changes' using errcode = '55000', hint = 'QUOTE_VERSION_FROZEN';
end;
$$;
revoke execute on function better_supabase.bsb_quote_versions_frozen() from public, anon, authenticated;
drop trigger if exists "bsb_quote_versions_frozen" on "app_private"."quote_versions";
create trigger "bsb_quote_versions_frozen" before update on "app_private"."quote_versions"
for each row execute function better_supabase.bsb_quote_versions_frozen();

create table if not exists "app_private"."quote_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "app_private"."quotes" ("id") on delete cascade,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0
);
create index if not exists quote_tax_lines_parent_idx on "app_private"."quote_tax_lines" ("parent_id");
alter table "app_private"."quote_tax_lines" enable row level security;
revoke all on "app_private"."quote_tax_lines" from public, anon, authenticated;
grant select on "app_private"."quote_tax_lines" to authenticated;
grant all on "app_private"."quote_tax_lines" to service_role;
drop policy if exists quote_tax_lines_read on "app_private"."quote_tax_lines";
create policy quote_tax_lines_read on "app_private"."quote_tax_lines"
  for select to authenticated
  using (exists (select 1 from "app_private"."quotes" q where q."id" = "parent_id"));

-- Creates a draft quote. attrs: title (required), currency, company and
-- contact ({ type, id }), ownerId, validUntil, terms, note, origin ({ type,
-- id }, the record it was made from), pricesIncludeTax, discountBps,
-- discountAmount (minor units as text), depositBps, or depositAmount (minor
-- units as text) for a fixed deposit, and depositRequired, which makes the
-- customer pay it before they accept. lines: see set_quote_lines.
create or replace function "app_private"."create_quote"(tenant uuid, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_row "app_private"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "app_private"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  end if;
  begin
    insert into "app_private"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "prices_include_tax", "discount_bps", "discount_amount", "deposit_bps", "deposit_amount", "deposit_required", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id',
      coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce((create_quote.attrs ->> 'discountBps')::integer, 0), coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0), (create_quote.attrs ->> 'depositBps')::integer, (create_quote.attrs ->> 'depositAmount')::bigint, coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if create_quote.lines is not null then
    perform "app_private"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "app_private"."quotes" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "app_private"."create_quote"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "app_private"."create_quote"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft quote, or one the customer asked changes on: title,
-- company, contact, currency, ownerId, validUntil, terms, note,
-- pricesIncludeTax, discountBps, discountAmount, depositBps, depositAmount
-- and depositRequired. The totals follow the new pricing.
create or replace function "app_private"."update_quote"(quote uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "app_private"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_user_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "prices_include_tax" = case when update_quote.attrs ? 'pricesIncludeTax' then coalesce((update_quote.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "discount_bps" = case when update_quote.attrs ? 'discountBps' then coalesce((update_quote.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_quote.attrs ? 'discountAmount' then coalesce((update_quote.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "deposit_bps" = case when update_quote.attrs ? 'depositBps' then (update_quote.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "deposit_amount" = case when update_quote.attrs ? 'depositAmount' then (update_quote.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "deposit_required" = case when update_quote.attrs ? 'depositRequired' then coalesce((update_quote.attrs ->> 'depositRequired')::boolean, false) else x."deposit_required" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  perform "app_private"."set_quote_lines_recount"(v_row."id");
  select * into v_row from "app_private"."quotes" x where x."id" = v_row."id";
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."update_quote"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."update_quote"(uuid, jsonb) to authenticated, service_role;
create table if not exists "app_private"."quote_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "app_private"."quotes" ("id") on delete cascade,
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
  "section" text check (length("section") between 1 and 300),
  "optional" boolean not null default false,
  "selected" boolean not null default true,
  "periods" integer not null default 1 check ("periods" > 0),
  "position" integer not null,
  "created_at" timestamptz not null default now(),
  check (("product_type" is null) = ("product_id" is null))
);
alter table "app_private"."quote_lines" add column if not exists "periods" integer not null default 1 check ("periods" > 0);
create index if not exists "quote_lines_parent_idx" on "app_private"."quote_lines" ("parent_id", "position");
alter table "app_private"."quote_lines" enable row level security;
revoke all on "app_private"."quote_lines" from public, anon, authenticated;
grant select on "app_private"."quote_lines" to authenticated;
grant all on "app_private"."quote_lines" to service_role;
drop policy if exists "quote_lines_read" on "app_private"."quote_lines";
create policy "quote_lines_read" on "app_private"."quote_lines" for select to authenticated
using (exists (select 1 from "app_private"."quotes" x where x."id" = "parent_id"));

-- Writes a record's totals from its counted lines: an optional line counts
-- only when the customer took it. The record discount is spread over the tax
-- rates in proportion to their amounts, and tax is counted once per rate, so
-- the totals and the tax per rate always add up.
create or replace function "app_private"."set_quote_lines_recount"(parent uuid)
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
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount", 0
    into v_tenant, v_inclusive, v_record_bps, v_record_amount, v_restriction
  from "app_private"."quotes" x where x."id" = set_quote_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount")), 0), coalesce(sum((round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))), 0)
    into v_list, v_line_discount
  from "app_private"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected");
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) as amount,
      sum(round((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * (10000 - v_restriction) * l."tax_rate_bps" / (10000.0 * (case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)))) as tax
    from "app_private"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected")
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
  delete from "app_private"."quote_tax_lines" x where x."parent_id" = set_quote_lines_recount.parent;
  insert into "app_private"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
  select v_tenant, set_quote_lines_recount.parent, r.rate, r.code, r.net, r.tax, r.gross, r.discount
  from jsonb_to_recordset(v_groups) r(rate integer, code text, net bigint, tax bigint, gross bigint, discount bigint);
  update "app_private"."quotes" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_subtotal,
    "tax_total" = v_tax,
    "total" = v_total,
    "deposit_due" = case when x."deposit_amount" is not null then least(greatest(v_total, 0), x."deposit_amount") when x."deposit_bps" is not null then round(v_total * x."deposit_bps" / 10000.0)::bigint else 0 end
  where x."id" = set_quote_lines_recount.parent;
end;
$$;
revoke execute on function "app_private"."set_quote_lines_recount"(uuid) from public, anon, authenticated;

-- Recounts each record a statement touched once, in id order so concurrent
-- statements lock the records in the same order. A transition table needs a
-- trigger per event, so there are three triggers on one function. The
-- transition tables are read through execute because plpgsql_check (db lint)
-- doesn't know them.
create or replace function better_supabase.bsb_quote_lines_totals()
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
    perform "app_private"."set_quote_lines_recount"(v_parent);
  end loop;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_quote_lines_totals() from public, anon, authenticated;
drop trigger if exists bsb_quote_lines_totals on "app_private"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_insert on "app_private"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_update on "app_private"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_delete on "app_private"."quote_lines";
create trigger bsb_quote_lines_totals_insert after insert on "app_private"."quote_lines"
referencing new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_update after update on "app_private"."quote_lines"
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_delete after delete on "app_private"."quote_lines"
referencing old table as old_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
create or replace function "app_private"."set_quote_lines"(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := set_quote_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "app_private"."quotes" x where x."id" = v_parent and not (not (x."status" in ('draft', 'changes_requested')));
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "app_private"."quotes" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false))) then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_quote_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_quote_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "app_private"."quote_lines" l where l."parent_id" = v_parent;
  begin
    insert into "app_private"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "section", "optional", "selected", "periods", "position")
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
      nullif(trim(x.value ->> 'section'), ''),
      coalesce((x.value ->> 'optional')::boolean, false),
      coalesce((x.value ->> 'selected')::boolean, not coalesce((x.value ->> 'optional')::boolean, false)),
      coalesce((x.value ->> 'periods')::integer, 1),
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_quote_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "app_private"."set_quote_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "app_private"."quotes" x where x."id" = v_parent);
end;
$$;
revoke execute on function "app_private"."set_quote_lines"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."set_quote_lines"(uuid, jsonb) to authenticated, service_role;

-- Sends a quote: it gets a public link the customer opens and a published
-- version, a snapshot that never changes. The quote can't change until it is
-- revised or the customer asks for changes; sending it again then publishes
-- the next revision. Returns the quote with the link's token, which is stored
-- only as a hash and returned this once.
-- actor: who sent it, for the state machine's history.
drop function if exists "app_private"."send_quote"(uuid);
create or replace function "app_private"."send_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."quotes" x where x."id" = send_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'the quote was already sent; revise it to send a new version' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if not exists (select 1 from "app_private"."quote_lines" x where x."parent_id" = v_row."id") then
    raise exception 'a quote needs a line before it is sent' using errcode = '23514', hint = 'QUOTE_EMPTY';
  end if;
  if send_quote.actor is not null then
    if jsonb_typeof(send_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(send_quote.actor ->> 'ip', '')::inet, nullif(send_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(send_quote.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "app_private"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "revision" = case when exists (select 1 from "app_private"."quote_versions" v where v."quote_id" = x."id" and v."revision" = x."revision") then x."revision" + 1 else x."revision" end,
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "app_private"."quote_versions" ("tenant_id", "quote_id", "revision", "snapshot", "total", "currency", "published_by")
  values (v_row."tenant_id", v_row."id", v_row."revision", (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), v_row."total", v_row."currency", coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid))
  returning "id" into v_version;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)) || jsonb_build_object('token', v_token);
end;
$$;
revoke execute on function "app_private"."send_quote"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."send_quote"(uuid, jsonb) to authenticated, service_role;

-- Opens a sent or declined quote again as a draft of its next revision: the
-- same quote, number and lines, a fresh valid-until date, and its link ends.
-- The versions already published stay as they were. An accepted quote is
-- kept as the customer accepted it; start a new quote instead.
drop function if exists "app_private"."revise_quote"(uuid);
create or replace function "app_private"."revise_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."quotes" x where x."id" = revise_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft is edited, not revised' using errcode = '55000', hint = 'QUOTE_NOT_SENT';
  end if;
  if v_row."status" = 'accepted' then
    raise exception 'an accepted quote stays as accepted; start a new quote' using errcode = '55000', hint = 'QUOTE_ACCEPTED';
  end if;
  if revise_quote.actor is not null then
    if jsonb_typeof(revise_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(revise_quote.actor ->> 'ip', '')::inet, nullif(revise_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(revise_quote.actor::text, ''), true);
  update "app_private"."quotes" x set "status" = 'draft', "revision" = x."revision" + 1, "token_hash" = null, "sent_at" = null, "viewed_at" = null,
    "valid_until" = greatest(x."valid_until", current_date + 30),
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."revise_quote"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."revise_quote"(uuid, jsonb) to authenticated, service_role;

-- Takes back a sent or expired quote the customer hasn't accepted: it can't
-- be answered any more until it is revised and sent again. The actor and
-- reason go to the state machine's history.
drop function if exists "app_private"."withdraw_quote"(uuid, jsonb);
create or replace function "app_private"."withdraw_quote"(quote uuid, actor jsonb default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."quotes" x where x."id" = withdraw_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" not in ('sent', 'viewed', 'changes_requested', 'expired') then
    raise exception 'only a sent quote that wasn''t answered is withdrawn' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if withdraw_quote.actor is not null then
    if jsonb_typeof(withdraw_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(withdraw_quote.actor ->> 'ip', '')::inet, nullif(withdraw_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(withdraw_quote.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(withdraw_quote.reason), ''), ''), true);
  update "app_private"."quotes" x set "status" = 'withdrawn', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."withdraw_quote"(uuid, jsonb, text) from public, anon;
grant execute on function "app_private"."withdraw_quote"(uuid, jsonb, text) to authenticated, service_role;

-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name,
-- and without it or an actor the answer names no one. The note is also the
-- reason in the state machine's history.
-- selected lists the positions of the optional lines they took. actor is
-- the customer when the app takes the answer in its own portal: id, name,
-- email, ip and userAgent, kept with the answer and in the state machine's
-- history; a quote past its valid date then expires instead, and the expired
-- quote is returned.
drop function if exists "app_private"."decide_quote"(uuid, text, text, text);
drop function if exists "app_private"."decide_quote"(uuid, text, text, text, jsonb);
create or replace function "app_private"."decide_quote"(quote uuid, decision text, note text, by text, selected jsonb default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "app_private"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "app_private"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "app_private"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "app_private"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decided_user_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."decide_quote"(uuid, text, text, text, jsonb, jsonb) from public, anon;
grant execute on function "app_private"."decide_quote"(uuid, text, text, text, jsonb, jsonb) to authenticated, service_role;

-- What the customer sees through the link: the quote without internal
-- notes. Opening a sent quote marks it viewed. Callable without signing in.
create or replace function "app_private"."public_quote"(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."quotes" x where x."token_hash" = encode(extensions.digest(public_quote.token, 'sha256'), 'hex');
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if v_row."status" = 'sent' then
    update "app_private"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke all on function "app_private"."public_quote"(text) from public, anon, authenticated;
grant execute on function "app_private"."public_quote"(text) to anon, authenticated, service_role;

-- The customer's answer through the link: accepted, rejected or
-- changes_requested, with their name, a note and the optional lines they
-- took. Their address and browser are kept with the answer. A quote past its
-- valid date expires instead.
drop function if exists "app_private"."respond_to_quote"(text, text, text, text);
create or replace function "app_private"."respond_to_quote"(token text, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."quotes" x where x."token_hash" = encode(extensions.digest(respond_to_quote.token, 'sha256'), 'hex') for update;
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  if respond_to_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(respond_to_quote.name), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "app_private"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_quote.selected is not null then
      if jsonb_typeof(respond_to_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "app_private"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "app_private"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "app_private"."quotes" x set "status" = respond_to_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(respond_to_quote.name), ''),
    "decision_note" = nullif(trim(respond_to_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke all on function "app_private"."respond_to_quote"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "app_private"."respond_to_quote"(text, text, text, text, jsonb) to anon, authenticated, service_role;

-- A quote shared with the signed-in guest, as the customer sees it: through
-- a grant on the quote or as a guest of its company or contact. Opening a
-- sent quote marks it viewed. No link token is needed. The service role
-- reads it too, for an app's own portal; actor is then the customer who
-- opened it, for the state machine's history.
drop function if exists "app_private"."portal_quote"(uuid);
create or replace function "app_private"."portal_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if portal_quote.actor is not null and not (auth.role() = 'service_role') then
    raise exception 'only the service role names who opened a quote' using errcode = '42501', hint = 'QUOTE_ACTOR_FORBIDDEN';
  end if;
  if portal_quote.actor is not null then
    if jsonb_typeof(portal_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(portal_quote.actor ->> 'ip', '')::inet, nullif(portal_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(portal_quote.actor::text, ''), true);
  if portal_quote.actor is null then
    begin
      v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
    exception when invalid_text_representation then
      v_ip := null;
    end;
    perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  end if;
  select * into v_row from "app_private"."quotes" x where x."id" = portal_quote.quote and (false or ((auth.role() = 'service_role') and x."status" <> 'draft'));
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'sent' then
    update "app_private"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."portal_quote"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."portal_quote"(uuid, jsonb) to authenticated, service_role;

-- The signed-in guest's answer to a quote shared with them, like
-- respond_to_quote without a token. name defaults to their email; the
-- answer keeps who they are, their address and their browser.
create or replace function "app_private"."respond_to_portal_quote"(quote uuid, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."quotes" x where x."id" = respond_to_portal_quote.quote and false for update;
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if respond_to_portal_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "app_private"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_portal_quote.selected is not null then
      if jsonb_typeof(respond_to_portal_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_portal_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "app_private"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "app_private"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_portal_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "app_private"."quotes" x set "status" = respond_to_portal_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''),
    "decision_note" = nullif(trim(respond_to_portal_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_portal_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_portal_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke execute on function "app_private"."respond_to_portal_quote"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "app_private"."respond_to_portal_quote"(uuid, text, text, text, jsonb) to authenticated, service_role;

-- The versions of a quote that were sent, oldest first, without their
-- snapshots.
create or replace function "app_private"."quote_versions"(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
begin
  select * into v_row from "app_private"."quotes" x where x."id" = quote_versions.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('revision', x."revision", 'total', x."total"::text, 'currency', x."currency",
      'publishedAt', x."published_at", 'publishedBy', x."published_by") order by x."revision")
    from "app_private"."quote_versions" x where x."quote_id" = v_row."id"), '[]'::jsonb);
end;
$$;
revoke execute on function "app_private"."quote_versions"(uuid) from public, anon;
grant execute on function "app_private"."quote_versions"(uuid) to authenticated, service_role;

-- The quote as it was sent at revision: the snapshot published then.
create or replace function "app_private"."quote_version"(quote uuid, revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
  v_version "app_private"."quote_versions";
begin
  select * into v_row from "app_private"."quotes" x where x."id" = quote_version.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  select * into v_version from "app_private"."quote_versions" x where x."quote_id" = v_row."id" and x."revision" = quote_version.revision;
  if v_version."id" is null then
    raise exception 'this quote has no such version' using errcode = 'P0002', hint = 'QUOTE_VERSION_NOT_FOUND';
  end if;
  return v_version."snapshot" || jsonb_build_object('revision', v_version."revision", 'publishedAt', v_version."published_at");
end;
$$;
revoke execute on function "app_private"."quote_version"(uuid, integer) from public, anon;
grant execute on function "app_private"."quote_version"(uuid, integer) to authenticated, service_role;

-- Expires sent quotes past their valid date. Run it daily from a job.
create or replace function "app_private"."expire_quotes"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
  v_count integer := 0;
begin
  perform set_config('better_supabase.transition_actor', '', true);
  for v_row in
    update "app_private"."quotes" x set "status" = 'expired', "updated_at" = now()
    where x."status" in ('sent', 'viewed') and x."valid_until" < current_date
    returning *
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "app_private"."expire_quotes"() from public, anon, authenticated;
grant execute on function "app_private"."expire_quotes"() to service_role;

-- Makes another variant of a quote: a new draft quote with the same pricing,
-- party and lines, grouped under the same root. label names it (A, B, Basic,
-- Premium) and is unique within the group; attrs change the new quote like
-- create_quote's. The first variant gives the quote it came from the label
-- Original when it has none.
create or replace function "app_private"."create_quote_variant"(quote uuid, label text, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "app_private"."quotes";
  v_root uuid;
  v_label text := nullif(trim(create_quote_variant.label), '');
  v_made jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "app_private"."quotes" x where x."id" = create_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_src."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_label is null or length(v_label) > 100 then
    raise exception 'a variant needs a label of up to 100 characters' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  v_root := coalesce(v_src."variant_of", v_src."id");
  if exists (select 1 from "app_private"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) and lower(x."variant_label") = lower(v_label)) then
    raise exception 'another variant of this quote has that label' using errcode = '23505', hint = 'QUOTE_VARIANT_LABEL_TAKEN';
  end if;
  v_made := "app_private"."create_quote"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'currency', v_src."currency", 'validUntil', v_src."valid_until",
    'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'terms', v_src."terms", 'note', v_src."note", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount"::text, 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount"::text, 'depositRequired', v_src."deposit_required")) || coalesce(create_quote_variant.attrs, '{}'::jsonb), null);
  v_id := (v_made ->> 'id')::uuid;
  insert into "app_private"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position", "section", "optional", "selected", "periods")
  select x."tenant_id", v_id, x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position", x."section", x."optional", x."selected", x."periods" from "app_private"."quote_lines" x where x."parent_id" = v_src."id";
  update "app_private"."quotes" x set "variant_label" = coalesce(x."variant_label", 'Original')
  where x."id" = v_root;
  update "app_private"."quotes" x set "variant_of" = v_root, "variant_label" = v_label, "is_selected" = false
  where x."id" = v_id;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "app_private"."quotes" x where x."id" = v_id);
end;
$$;
revoke execute on function "app_private"."create_quote_variant"(uuid, text, jsonb) from public, anon;
grant execute on function "app_private"."create_quote_variant"(uuid, text, jsonb) to authenticated, service_role;

-- The quotes of one group of variants, the root first. isSelected tells which
-- one the customer chose.
create or replace function "app_private"."list_quote_variants"(quote uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_src "app_private"."quotes";
begin
  select * into v_src from "app_private"."quotes" x where x."id" = list_quote_variants.quote;
  if v_src."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'quotes.read'), false)) then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "app_private"."quotes" x where (x."id" = coalesce(v_src."variant_of", v_src."id") or x."variant_of" = coalesce(v_src."variant_of", v_src."id")));
end;
$$;
revoke execute on function "app_private"."list_quote_variants"(uuid) from public, anon;
grant execute on function "app_private"."list_quote_variants"(uuid) to authenticated, service_role;

-- Selects one variant of a quote and marks the others of its group not
-- selected; only the selected variant becomes an order or an invoice. A
-- withdrawn, rejected or expired variant can't be selected. options.forward
-- is order or invoice to copy the selected variant forward in the same call
-- (the quote must be accepted, as for order_from_quote and invoice_from_quote);
-- options.attrs go to order_from_quote and options.depositBps to
-- invoice_from_quote.
create or replace function "app_private"."select_quote_variant"(quote uuid, options jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "app_private"."quotes";
  v_root uuid;
  v_forward text := nullif(select_quote_variant.options ->> 'forward', '');
  v_order jsonb;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."quotes" x where x."id" = select_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  v_root := coalesce(v_row."variant_of", v_row."id");
  if v_row."variant_of" is null and not exists (select 1 from "app_private"."quotes" x where x."variant_of" = v_row."id") then
    raise exception 'this quote has no variants' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  if v_row."status" in ('withdrawn', 'rejected', 'expired') then
    raise exception 'a withdrawn, rejected or expired variant can''t be selected' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTABLE';
  end if;
  if v_forward is not null and v_forward not in ('') then
    raise exception 'forward is order or invoice' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  perform 1 from "app_private"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) for update;
  update "app_private"."quotes" x set "is_selected" = (x."id" = v_row."id"), "updated_at" = now()
  where (x."id" = v_root or x."variant_of" = v_root) and x."is_selected" is distinct from (x."id" = v_row."id");
  if v_forward is not null and v_order is null and v_invoice is null then
    raise exception 'the organization has no block to copy the variant forward to' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  select * into v_row from "app_private"."quotes" x where x."id" = v_row."id";
  return jsonb_build_object('quote', (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "app_private"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "app_private"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), 'variants', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "app_private"."quotes" x where (x."id" = v_root or x."variant_of" = v_root)), 'order', v_order, 'invoice', v_invoice);
end;
$$;
revoke execute on function "app_private"."select_quote_variant"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."select_quote_variant"(uuid, jsonb) to authenticated, service_role;

-- The import target of the quote entity (ADR 0141): item.data is { number,
-- status?, title?, currency, validUntil?, createdAt?, sentAt?, viewedAt?,
-- decidedAt?, decidedBy?, decisionNote?, company?, contact?, origin?,
-- pricesIncludeTax?, attrs?, legalEntityId?, buyer?, lines, taxLines?,
-- totals? }. A quote that is already imported is kept as it is.
create or replace function "app_private"."import_quote"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_quote.item ->> 'tenant')::uuid;
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row "app_private"."quotes";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from "app_private"."quotes" y where y."id" = import_quote.subject_id::uuid and y."tenant_id" = v_tenant;
    if not found then
      raise exception 'the quote no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
  end if;
  if v_number is null then
    raise exception 'a quote needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    raise exception 'status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a quote needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  v_made := "app_private"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Quote ' || v_number),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> 'id')::uuid;
  update "app_private"."quotes" y set
    "status" = coalesce(v_data ->> 'status', 'draft'),
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
    "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
    "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
    "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
    "decided_by" = nullif(v_data ->> 'decidedBy', ''),
    "decision_note" = nullif(v_data ->> 'decisionNote', ''),
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
    "updated_at" = now()
  where y."id" = v_id;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(z."tax_code", '') || ':' || z."tax_rate_bps"::text as key, sum(z."net") as net, sum(z."tax") as tax
        from "app_private"."quote_tax_lines" z where z."parent_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "app_private"."quote_tax_lines" z where z."parent_id" = v_id;
    insert into "app_private"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint), coalesce((g.value ->> 'discount')::bigint, 0)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "app_private"."quotes" y where y."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "app_private"."quotes" y set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, y."total")
    where y."id" = v_id;
  end if;
  select * into v_row from "app_private"."quotes" y where y."id" = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$$;
revoke execute on function "app_private"."import_quote"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "app_private"."import_quote"(uuid, jsonb, text) to service_role;

-- When a quote last changed, for the conflict check of imports.
create or replace function "app_private"."quote_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select y."updated_at" from "app_private"."quotes" y where y."id" = $1::uuid
$$;
revoke execute on function "app_private"."quote_updated_at"(text) from public, anon, authenticated;
grant execute on function "app_private"."quote_updated_at"(text) to service_role;

-- Totals and cost of one record's lines per billing party (ADR 0141). It runs
-- as the caller, so only lines the caller can read count.
create or replace function "app_private"."quote_totals_by_billing_party"(quote uuid)
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
        'lines', count(*), 'net', sum((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))))::text, 'cost', sum(round(l."quantity" * l."unit_cost"))::text
      ) as row
    from "app_private"."quote_lines" l
    where l."parent_id" = quote and (not l."optional" or l."selected")
    group by 1, 2, 3
  ) g
$$;
revoke execute on function "app_private"."quote_totals_by_billing_party"(uuid) from public, anon;
grant execute on function "app_private"."quote_totals_by_billing_party"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."quotes";
drop policy if exists bsb_tenant_scope_select on "app_private"."quotes";
create policy bsb_tenant_scope_select on "app_private"."quotes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."quotes";
create policy bsb_tenant_scope_insert on "app_private"."quotes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."quotes";
create policy bsb_tenant_scope_update on "app_private"."quotes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."quotes";
create policy bsb_tenant_scope_delete on "app_private"."quotes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."quote_lines";
drop policy if exists bsb_tenant_scope_select on "app_private"."quote_lines";
create policy bsb_tenant_scope_select on "app_private"."quote_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "app_private"."quotes" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."quote_lines";
create policy bsb_tenant_scope_insert on "app_private"."quote_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."quote_lines";
create policy bsb_tenant_scope_update on "app_private"."quote_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."quote_lines";
create policy bsb_tenant_scope_delete on "app_private"."quote_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."quote_versions";
drop policy if exists bsb_tenant_scope_select on "app_private"."quote_versions";
create policy bsb_tenant_scope_select on "app_private"."quote_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "app_private"."quotes" q where q."id" = "quote_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."quote_versions";
create policy bsb_tenant_scope_insert on "app_private"."quote_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."quote_versions";
create policy bsb_tenant_scope_update on "app_private"."quote_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."quote_versions";
create policy bsb_tenant_scope_delete on "app_private"."quote_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."quote_tax_lines";
drop policy if exists bsb_tenant_scope_select on "app_private"."quote_tax_lines";
create policy bsb_tenant_scope_select on "app_private"."quote_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "app_private"."quotes" q where q."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."quote_tax_lines";
create policy bsb_tenant_scope_insert on "app_private"."quote_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."quote_tax_lines";
create policy bsb_tenant_scope_update on "app_private"."quote_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."quote_tax_lines";
create policy bsb_tenant_scope_delete on "app_private"."quote_tax_lines" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block-data quotes
-- @bsb-hash sha256:fe87f8a5895a1bef6d16712af52cf95116d938edc0a677538bebf4ee466198f0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block quotes@3 managed
-- @bsb-hash sha256:0bf22764c52cb18b798ef6b38402337bddf44354d406d34d1ecbb094d4a87533
-- Quotes with sections, optional lines, discounts, prices with or without tax, tax per rate and a deposit; published versions; a public link or the signed-in portal the customer accepts, rejects or asks changes through; expiry; and quotes from deals. With catalog, a line that names a product variant takes its price and title.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Quotes: line items, sections, optional lines, discounts and tax per rate,
-- published versions, sending with a public link or to the signed-in portal
-- the customer accepts, rejects or asks changes through, and expiry.

create table if not exists "better_supabase"."quotes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "revision" integer not null default 1,
  "title" text not null check (length("title") between 1 and 300),
  "company_type" text,
  "company_id" text,
  "contact_type" text,
  "contact_id" text,
  "owner_user_id" uuid,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn')),
  "valid_until" date,
  "terms" text,
  "note" text,
  "origin_type" text,
  "origin_id" text,
  "token_hash" text unique,
  "sent_at" timestamptz,
  "viewed_at" timestamptz,
  "decided_at" timestamptz,
  "decided_by" text,
  "decision_note" text,
  "decided_user_id" uuid,
  "decided_ip" text,
  "decided_user_agent" text,
  "prices_include_tax" boolean not null default false,
  "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000),
  "discount_amount" bigint not null default 0 check ("discount_amount" >= 0),
  "deposit_bps" integer check ("deposit_bps" > 0 and "deposit_bps" < 10000),
  "deposit_amount" bigint check ("deposit_amount" > 0),
  "deposit_required" boolean not null default false,
  "deposit_due" bigint not null default 0,
  "unpublished_changes" boolean not null default false,
  "buyer" jsonb,
  "variant_of" uuid,
  "variant_label" text check (length("variant_label") between 1 and 100),
  "is_selected" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "list_total" bigint not null default 0,
  "discount_total" bigint not null default 0,
  "subtotal" bigint not null default 0,
  "tax_total" bigint not null default 0,
  "total" bigint not null default 0,
  unique ("tenant_id", "number", "revision"),
  check (("company_type" is null) = ("company_id" is null)),
  check (("origin_type" is null) = ("origin_id" is null))
);
alter table "better_supabase"."quotes" add column if not exists "deposit_amount" bigint check ("deposit_amount" > 0);
alter table "better_supabase"."quotes" add column if not exists "deposit_required" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "unpublished_changes" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "buyer" jsonb;
alter table "better_supabase"."quotes" add column if not exists "variant_of" uuid;
alter table "better_supabase"."quotes" add column if not exists "variant_label" text check (length("variant_label") between 1 and 100);
alter table "better_supabase"."quotes" add column if not exists "is_selected" boolean not null default false;
create index if not exists quotes_tenant_status_idx on "better_supabase"."quotes" ("tenant_id", "status", "created_at" desc);
create index if not exists quotes_variant_idx on "better_supabase"."quotes" ("variant_of") where "variant_of" is not null;
create index if not exists quotes_origin_idx on "better_supabase"."quotes" ("origin_type", "origin_id");

alter table "better_supabase"."quotes" enable row level security;
revoke all on "better_supabase"."quotes" from public, anon, authenticated;
grant select on "better_supabase"."quotes" to authenticated;
grant all on "better_supabase"."quotes" to service_role;
drop policy if exists quotes_read on "better_supabase"."quotes";
create policy quotes_read on "better_supabase"."quotes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')));

create table if not exists "better_supabase"."quote_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "quote_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
  "revision" integer not null,
  "snapshot" jsonb not null,
  "total" bigint not null,
  "currency" char(3) not null,
  "published_by" uuid,
  "published_at" timestamptz not null default now(),
  unique ("quote_id", "revision")
);
alter table "better_supabase"."quote_versions" enable row level security;
revoke all on "better_supabase"."quote_versions" from public, anon, authenticated;
grant select on "better_supabase"."quote_versions" to authenticated;
grant all on "better_supabase"."quote_versions" to service_role;
drop policy if exists quote_versions_read on "better_supabase"."quote_versions";
create policy quote_versions_read on "better_supabase"."quote_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"));
create or replace function better_supabase.bsb_quote_versions_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'a published quote version never changes' using errcode = '55000', hint = 'QUOTE_VERSION_FROZEN';
end;
$$;
revoke execute on function better_supabase.bsb_quote_versions_frozen() from public, anon, authenticated;
drop trigger if exists "bsb_quote_versions_frozen" on "better_supabase"."quote_versions";
create trigger "bsb_quote_versions_frozen" before update on "better_supabase"."quote_versions"
for each row execute function better_supabase.bsb_quote_versions_frozen();

create table if not exists "better_supabase"."quote_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0
);
create index if not exists quote_tax_lines_parent_idx on "better_supabase"."quote_tax_lines" ("parent_id");
alter table "better_supabase"."quote_tax_lines" enable row level security;
revoke all on "better_supabase"."quote_tax_lines" from public, anon, authenticated;
grant select on "better_supabase"."quote_tax_lines" to authenticated;
grant all on "better_supabase"."quote_tax_lines" to service_role;
drop policy if exists quote_tax_lines_read on "better_supabase"."quote_tax_lines";
create policy quote_tax_lines_read on "better_supabase"."quote_tax_lines"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"));

-- Creates a draft quote. attrs: title (required), currency, company and
-- contact ({ type, id }), ownerId, validUntil, terms, note, origin ({ type,
-- id }, the record it was made from), pricesIncludeTax, discountBps,
-- discountAmount (minor units as text), depositBps, or depositAmount (minor
-- units as text) for a fixed deposit, and depositRequired, which makes the
-- customer pay it before they accept. lines: see set_quote_lines.
create or replace function "better_supabase"."create_quote"(tenant uuid, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "prices_include_tax", "discount_bps", "discount_amount", "deposit_bps", "deposit_amount", "deposit_required", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id',
      coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce((create_quote.attrs ->> 'discountBps')::integer, 0), coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0), (create_quote.attrs ->> 'depositBps')::integer, (create_quote.attrs ->> 'depositAmount')::bigint, coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft quote, or one the customer asked changes on: title,
-- company, contact, currency, ownerId, validUntil, terms, note,
-- pricesIncludeTax, discountBps, discountAmount, depositBps, depositAmount
-- and depositRequired. The totals follow the new pricing.
create or replace function "better_supabase"."update_quote"(quote uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_user_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "prices_include_tax" = case when update_quote.attrs ? 'pricesIncludeTax' then coalesce((update_quote.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "discount_bps" = case when update_quote.attrs ? 'discountBps' then coalesce((update_quote.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_quote.attrs ? 'discountAmount' then coalesce((update_quote.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "deposit_bps" = case when update_quote.attrs ? 'depositBps' then (update_quote.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "deposit_amount" = case when update_quote.attrs ? 'depositAmount' then (update_quote.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "deposit_required" = case when update_quote.attrs ? 'depositRequired' then coalesce((update_quote.attrs ->> 'depositRequired')::boolean, false) else x."deposit_required" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  perform "better_supabase"."set_quote_lines_recount"(v_row."id");
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."update_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_quote"(uuid, jsonb) to authenticated, service_role;
create table if not exists "better_supabase"."quote_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
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
  "section" text check (length("section") between 1 and 300),
  "optional" boolean not null default false,
  "selected" boolean not null default true,
  "periods" integer not null default 1 check ("periods" > 0),
  "position" integer not null,
  "created_at" timestamptz not null default now(),
  check (("product_type" is null) = ("product_id" is null))
);
alter table "better_supabase"."quote_lines" add column if not exists "periods" integer not null default 1 check ("periods" > 0);
create index if not exists "quote_lines_parent_idx" on "better_supabase"."quote_lines" ("parent_id", "position");
alter table "better_supabase"."quote_lines" enable row level security;
revoke all on "better_supabase"."quote_lines" from public, anon, authenticated;
grant select on "better_supabase"."quote_lines" to authenticated;
grant all on "better_supabase"."quote_lines" to service_role;
drop policy if exists "quote_lines_read" on "better_supabase"."quote_lines";
create policy "quote_lines_read" on "better_supabase"."quote_lines" for select to authenticated
using (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"));

-- Writes a record's totals from its counted lines: an optional line counts
-- only when the customer took it. The record discount is spread over the tax
-- rates in proportion to their amounts, and tax is counted once per rate, so
-- the totals and the tax per rate always add up.
create or replace function "better_supabase"."set_quote_lines_recount"(parent uuid)
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
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount", 0
    into v_tenant, v_inclusive, v_record_bps, v_record_amount, v_restriction
  from "better_supabase"."quotes" x where x."id" = set_quote_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount")), 0), coalesce(sum((round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))), 0)
    into v_list, v_line_discount
  from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected");
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) as amount,
      sum(round((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * (10000 - v_restriction) * l."tax_rate_bps" / (10000.0 * (case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)))) as tax
    from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected")
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
  delete from "better_supabase"."quote_tax_lines" x where x."parent_id" = set_quote_lines_recount.parent;
  insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
  select v_tenant, set_quote_lines_recount.parent, r.rate, r.code, r.net, r.tax, r.gross, r.discount
  from jsonb_to_recordset(v_groups) r(rate integer, code text, net bigint, tax bigint, gross bigint, discount bigint);
  update "better_supabase"."quotes" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_subtotal,
    "tax_total" = v_tax,
    "total" = v_total,
    "deposit_due" = case when x."deposit_amount" is not null then least(greatest(v_total, 0), x."deposit_amount") when x."deposit_bps" is not null then round(v_total * x."deposit_bps" / 10000.0)::bigint else 0 end
  where x."id" = set_quote_lines_recount.parent;
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines_recount"(uuid) from public, anon, authenticated;

-- Recounts each record a statement touched once, in id order so concurrent
-- statements lock the records in the same order. A transition table needs a
-- trigger per event, so there are three triggers on one function. The
-- transition tables are read through execute because plpgsql_check (db lint)
-- doesn't know them.
create or replace function better_supabase.bsb_quote_lines_totals()
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
    perform "better_supabase"."set_quote_lines_recount"(v_parent);
  end loop;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_quote_lines_totals() from public, anon, authenticated;
drop trigger if exists bsb_quote_lines_totals on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_insert on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_update on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_delete on "better_supabase"."quote_lines";
create trigger bsb_quote_lines_totals_insert after insert on "better_supabase"."quote_lines"
referencing new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_update after update on "better_supabase"."quote_lines"
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_delete after delete on "better_supabase"."quote_lines"
referencing old table as old_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
create or replace function "better_supabase"."set_quote_lines"(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := set_quote_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."quotes" x where x."id" = v_parent and not (not (x."status" in ('draft', 'changes_requested')));
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."quotes" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false))) then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_quote_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_quote_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."quote_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "section", "optional", "selected", "periods", "position")
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
      nullif(trim(x.value ->> 'section'), ''),
      coalesce((x.value ->> 'optional')::boolean, false),
      coalesce((x.value ->> 'selected')::boolean, not coalesce((x.value ->> 'optional')::boolean, false)),
      coalesce((x.value ->> 'periods')::integer, 1),
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_quote_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_quote_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."quotes" x where x."id" = v_parent);
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) to authenticated, service_role;

-- Sends a quote: it gets a public link the customer opens and a published
-- version, a snapshot that never changes. The quote can't change until it is
-- revised or the customer asks for changes; sending it again then publishes
-- the next revision. Returns the quote with the link's token, which is stored
-- only as a hash and returned this once.
-- actor: who sent it, for the state machine's history.
drop function if exists "better_supabase"."send_quote"(uuid);
create or replace function "better_supabase"."send_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = send_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'the quote was already sent; revise it to send a new version' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if not exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_row."id") then
    raise exception 'a quote needs a line before it is sent' using errcode = '23514', hint = 'QUOTE_EMPTY';
  end if;
  if send_quote.actor is not null then
    if jsonb_typeof(send_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(send_quote.actor ->> 'ip', '')::inet, nullif(send_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(send_quote.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "revision" = case when exists (select 1 from "better_supabase"."quote_versions" v where v."quote_id" = x."id" and v."revision" = x."revision") then x."revision" + 1 else x."revision" end,
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "better_supabase"."quote_versions" ("tenant_id", "quote_id", "revision", "snapshot", "total", "currency", "published_by")
  values (v_row."tenant_id", v_row."id", v_row."revision", (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), v_row."total", v_row."currency", coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid))
  returning "id" into v_version;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)) || jsonb_build_object('token', v_token);
end;
$$;
revoke execute on function "better_supabase"."send_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."send_quote"(uuid, jsonb) to authenticated, service_role;

-- Opens a sent or declined quote again as a draft of its next revision: the
-- same quote, number and lines, a fresh valid-until date, and its link ends.
-- The versions already published stay as they were. An accepted quote is
-- kept as the customer accepted it; start a new quote instead.
drop function if exists "better_supabase"."revise_quote"(uuid);
create or replace function "better_supabase"."revise_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = revise_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft is edited, not revised' using errcode = '55000', hint = 'QUOTE_NOT_SENT';
  end if;
  if v_row."status" = 'accepted' then
    raise exception 'an accepted quote stays as accepted; start a new quote' using errcode = '55000', hint = 'QUOTE_ACCEPTED';
  end if;
  if revise_quote.actor is not null then
    if jsonb_typeof(revise_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(revise_quote.actor ->> 'ip', '')::inet, nullif(revise_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(revise_quote.actor::text, ''), true);
  update "better_supabase"."quotes" x set "status" = 'draft', "revision" = x."revision" + 1, "token_hash" = null, "sent_at" = null, "viewed_at" = null,
    "valid_until" = greatest(x."valid_until", current_date + 30),
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."revise_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."revise_quote"(uuid, jsonb) to authenticated, service_role;

-- Takes back a sent or expired quote the customer hasn't accepted: it can't
-- be answered any more until it is revised and sent again. The actor and
-- reason go to the state machine's history.
drop function if exists "better_supabase"."withdraw_quote"(uuid, jsonb);
create or replace function "better_supabase"."withdraw_quote"(quote uuid, actor jsonb default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = withdraw_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" not in ('sent', 'viewed', 'changes_requested', 'expired') then
    raise exception 'only a sent quote that wasn''t answered is withdrawn' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if withdraw_quote.actor is not null then
    if jsonb_typeof(withdraw_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(withdraw_quote.actor ->> 'ip', '')::inet, nullif(withdraw_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(withdraw_quote.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(withdraw_quote.reason), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = 'withdrawn', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) to authenticated, service_role;

-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name,
-- and without it or an actor the answer names no one. The note is also the
-- reason in the state machine's history.
-- selected lists the positions of the optional lines they took. actor is
-- the customer when the app takes the answer in its own portal: id, name,
-- email, ip and userAgent, kept with the answer and in the state machine's
-- history; a quote past its valid date then expires instead, and the expired
-- quote is returned.
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text);
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."decide_quote"(quote uuid, decision text, note text, by text, selected jsonb default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decided_user_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) to authenticated, service_role;

-- What the customer sees through the link: the quote without internal
-- notes. Opening a sent quote marks it viewed. Callable without signing in.
create or replace function "better_supabase"."public_quote"(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(public_quote.token, 'sha256'), 'hex');
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke all on function "better_supabase"."public_quote"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."public_quote"(text) to anon, authenticated, service_role;

-- The customer's answer through the link: accepted, rejected or
-- changes_requested, with their name, a note and the optional lines they
-- took. Their address and browser are kept with the answer. A quote past its
-- valid date expires instead.
drop function if exists "better_supabase"."respond_to_quote"(text, text, text, text);
create or replace function "better_supabase"."respond_to_quote"(token text, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(respond_to_quote.token, 'sha256'), 'hex') for update;
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  if respond_to_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(respond_to_quote.name), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_quote.selected is not null then
      if jsonb_typeof(respond_to_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(respond_to_quote.name), ''),
    "decision_note" = nullif(trim(respond_to_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke all on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) to anon, authenticated, service_role;

-- A quote shared with the signed-in guest, as the customer sees it: through
-- a grant on the quote or as a guest of its company or contact. Opening a
-- sent quote marks it viewed. No link token is needed. The service role
-- reads it too, for an app's own portal; actor is then the customer who
-- opened it, for the state machine's history.
drop function if exists "better_supabase"."portal_quote"(uuid);
create or replace function "better_supabase"."portal_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if portal_quote.actor is not null and not (auth.role() = 'service_role') then
    raise exception 'only the service role names who opened a quote' using errcode = '42501', hint = 'QUOTE_ACTOR_FORBIDDEN';
  end if;
  if portal_quote.actor is not null then
    if jsonb_typeof(portal_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(portal_quote.actor ->> 'ip', '')::inet, nullif(portal_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(portal_quote.actor::text, ''), true);
  if portal_quote.actor is null then
    begin
      v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
    exception when invalid_text_representation then
      v_ip := null;
    end;
    perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = portal_quote.quote and (false or ((auth.role() = 'service_role') and x."status" <> 'draft'));
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."portal_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."portal_quote"(uuid, jsonb) to authenticated, service_role;

-- The signed-in guest's answer to a quote shared with them, like
-- respond_to_quote without a token. name defaults to their email; the
-- answer keeps who they are, their address and their browser.
create or replace function "better_supabase"."respond_to_portal_quote"(quote uuid, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = respond_to_portal_quote.quote and false for update;
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if respond_to_portal_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_portal_quote.selected is not null then
      if jsonb_typeof(respond_to_portal_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_portal_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_portal_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_portal_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''),
    "decision_note" = nullif(trim(respond_to_portal_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_portal_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_portal_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) to authenticated, service_role;

-- The versions of a quote that were sent, oldest first, without their
-- snapshots.
create or replace function "better_supabase"."quote_versions"(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_versions.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('revision', x."revision", 'total', x."total"::text, 'currency', x."currency",
      'publishedAt', x."published_at", 'publishedBy', x."published_by") order by x."revision")
    from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id"), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."quote_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_versions"(uuid) to authenticated, service_role;

-- The quote as it was sent at revision: the snapshot published then.
create or replace function "better_supabase"."quote_version"(quote uuid, revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_version "better_supabase"."quote_versions";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_version.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id" and x."revision" = quote_version.revision;
  if v_version."id" is null then
    raise exception 'this quote has no such version' using errcode = 'P0002', hint = 'QUOTE_VERSION_NOT_FOUND';
  end if;
  return v_version."snapshot" || jsonb_build_object('revision', v_version."revision", 'publishedAt', v_version."published_at");
end;
$$;
revoke execute on function "better_supabase"."quote_version"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."quote_version"(uuid, integer) to authenticated, service_role;

-- Expires sent quotes past their valid date. Run it daily from a job.
create or replace function "better_supabase"."expire_quotes"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_count integer := 0;
begin
  perform set_config('better_supabase.transition_actor', '', true);
  for v_row in
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now()
    where x."status" in ('sent', 'viewed') and x."valid_until" < current_date
    returning *
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_quotes"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_quotes"() to service_role;

-- Makes another variant of a quote: a new draft quote with the same pricing,
-- party and lines, grouped under the same root. label names it (A, B, Basic,
-- Premium) and is unique within the group; attrs change the new quote like
-- create_quote's. The first variant gives the quote it came from the label
-- Original when it has none.
create or replace function "better_supabase"."create_quote_variant"(quote uuid, label text, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
  v_root uuid;
  v_label text := nullif(trim(create_quote_variant.label), '');
  v_made jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."quotes" x where x."id" = create_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_src."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_label is null or length(v_label) > 100 then
    raise exception 'a variant needs a label of up to 100 characters' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  v_root := coalesce(v_src."variant_of", v_src."id");
  if exists (select 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) and lower(x."variant_label") = lower(v_label)) then
    raise exception 'another variant of this quote has that label' using errcode = '23505', hint = 'QUOTE_VARIANT_LABEL_TAKEN';
  end if;
  v_made := "better_supabase"."create_quote"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'currency', v_src."currency", 'validUntil', v_src."valid_until",
    'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'terms', v_src."terms", 'note', v_src."note", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount"::text, 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount"::text, 'depositRequired', v_src."deposit_required")) || coalesce(create_quote_variant.attrs, '{}'::jsonb), null);
  v_id := (v_made ->> 'id')::uuid;
  insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position", "section", "optional", "selected", "periods")
  select x."tenant_id", v_id, x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position", x."section", x."optional", x."selected", x."periods" from "better_supabase"."quote_lines" x where x."parent_id" = v_src."id";
  update "better_supabase"."quotes" x set "variant_label" = coalesce(x."variant_label", 'Original')
  where x."id" = v_root;
  update "better_supabase"."quotes" x set "variant_of" = v_root, "variant_label" = v_label, "is_selected" = false
  where x."id" = v_id;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) to authenticated, service_role;

-- The quotes of one group of variants, the root first. isSelected tells which
-- one the customer chose.
create or replace function "better_supabase"."list_quote_variants"(quote uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
begin
  select * into v_src from "better_supabase"."quotes" x where x."id" = list_quote_variants.quote;
  if v_src."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'quotes.read'), false)) then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = coalesce(v_src."variant_of", v_src."id") or x."variant_of" = coalesce(v_src."variant_of", v_src."id")));
end;
$$;
revoke execute on function "better_supabase"."list_quote_variants"(uuid) from public, anon;
grant execute on function "better_supabase"."list_quote_variants"(uuid) to authenticated, service_role;

-- Selects one variant of a quote and marks the others of its group not
-- selected; only the selected variant becomes an order or an invoice. A
-- withdrawn, rejected or expired variant can't be selected. options.forward
-- is order or invoice to copy the selected variant forward in the same call
-- (the quote must be accepted, as for order_from_quote and invoice_from_quote);
-- options.attrs go to order_from_quote and options.depositBps to
-- invoice_from_quote.
create or replace function "better_supabase"."select_quote_variant"(quote uuid, options jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_root uuid;
  v_forward text := nullif(select_quote_variant.options ->> 'forward', '');
  v_order jsonb;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = select_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  v_root := coalesce(v_row."variant_of", v_row."id");
  if v_row."variant_of" is null and not exists (select 1 from "better_supabase"."quotes" x where x."variant_of" = v_row."id") then
    raise exception 'this quote has no variants' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  if v_row."status" in ('withdrawn', 'rejected', 'expired') then
    raise exception 'a withdrawn, rejected or expired variant can''t be selected' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTABLE';
  end if;
  if v_forward is not null and v_forward not in ('') then
    raise exception 'forward is order or invoice' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  perform 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) for update;
  update "better_supabase"."quotes" x set "is_selected" = (x."id" = v_row."id"), "updated_at" = now()
  where (x."id" = v_root or x."variant_of" = v_root) and x."is_selected" is distinct from (x."id" = v_row."id");
  if v_forward is not null and v_order is null and v_invoice is null then
    raise exception 'the organization has no block to copy the variant forward to' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  return jsonb_build_object('quote', (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), 'variants', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root)), 'order', v_order, 'invoice', v_invoice);
end;
$$;
revoke execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) to authenticated, service_role;

-- The import target of the quote entity (ADR 0141): item.data is { number,
-- status?, title?, currency, validUntil?, createdAt?, sentAt?, viewedAt?,
-- decidedAt?, decidedBy?, decisionNote?, company?, contact?, origin?,
-- pricesIncludeTax?, attrs?, legalEntityId?, buyer?, lines, taxLines?,
-- totals? }. A quote that is already imported is kept as it is.
create or replace function "better_supabase"."import_quote"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_quote.item ->> 'tenant')::uuid;
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."quotes";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from "better_supabase"."quotes" y where y."id" = import_quote.subject_id::uuid and y."tenant_id" = v_tenant;
    if not found then
      raise exception 'the quote no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
  end if;
  if v_number is null then
    raise exception 'a quote needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    raise exception 'status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a quote needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  v_made := "better_supabase"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Quote ' || v_number),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> 'id')::uuid;
  update "better_supabase"."quotes" y set
    "status" = coalesce(v_data ->> 'status', 'draft'),
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
    "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
    "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
    "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
    "decided_by" = nullif(v_data ->> 'decidedBy', ''),
    "decision_note" = nullif(v_data ->> 'decisionNote', ''),
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
    "updated_at" = now()
  where y."id" = v_id;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(z."tax_code", '') || ':' || z."tax_rate_bps"::text as key, sum(z."net") as net, sum(z."tax") as tax
        from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id;
    insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint), coalesce((g.value ->> 'discount')::bigint, 0)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."quotes" y set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, y."total")
    where y."id" = v_id;
  end if;
  select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_quote"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_quote"(uuid, jsonb, text) to service_role;

-- When a quote last changed, for the conflict check of imports.
create or replace function "better_supabase"."quote_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select y."updated_at" from "better_supabase"."quotes" y where y."id" = $1::uuid
$$;
revoke execute on function "better_supabase"."quote_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."quote_updated_at"(text) to service_role;

-- Totals and cost of one record's lines per billing party (ADR 0141). It runs
-- as the caller, so only lines the caller can read count.
create or replace function "better_supabase"."quote_totals_by_billing_party"(quote uuid)
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
        'lines', count(*), 'net', sum((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))))::text, 'cost', sum(round(l."quantity" * l."unit_cost"))::text
      ) as row
    from "better_supabase"."quote_lines" l
    where l."parent_id" = quote and (not l."optional" or l."selected")
    group by 1, 2, 3
  ) g
$$;
revoke execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
create policy bsb_tenant_scope_select on "better_supabase"."quotes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
create policy bsb_tenant_scope_insert on "better_supabase"."quotes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
create policy bsb_tenant_scope_update on "better_supabase"."quotes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
create policy bsb_tenant_scope_delete on "better_supabase"."quotes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_select on "better_supabase"."quote_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_update on "better_supabase"."quote_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.quotes.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."send_quote"(uuid);
drop function if exists "api"."revise_quote"(uuid);
drop function if exists "api"."withdraw_quote"(uuid, jsonb);
drop function if exists "api"."decide_quote"(uuid, text, text, text);
drop function if exists "api"."decide_quote"(uuid, text, text, text, jsonb);
drop function if exists "api"."respond_to_quote"(text, text, text, text);
drop function if exists "api"."portal_quote"(uuid);

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

create or replace function "api"."create_quote"(tenant uuid, attrs jsonb, lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_quote"($1, $2, $3) $$;
revoke execute on function "api"."create_quote"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."create_quote"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."update_quote"(quote uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_quote"($1, $2) $$;
revoke execute on function "api"."update_quote"(uuid, jsonb) from public, anon;
grant execute on function "api"."update_quote"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."set_quote_lines"(parent uuid, lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_quote_lines"($1, $2) $$;
revoke execute on function "api"."set_quote_lines"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_quote_lines"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."send_quote"(quote uuid, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."send_quote"($1, $2) $$;
revoke execute on function "api"."send_quote"(uuid, jsonb) from public, anon;
grant execute on function "api"."send_quote"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."revise_quote"(quote uuid, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."revise_quote"($1, $2) $$;
revoke execute on function "api"."revise_quote"(uuid, jsonb) from public, anon;
grant execute on function "api"."revise_quote"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."withdraw_quote"(quote uuid, actor jsonb default null, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."withdraw_quote"($1, $2, $3) $$;
revoke execute on function "api"."withdraw_quote"(uuid, jsonb, text) from public, anon;
grant execute on function "api"."withdraw_quote"(uuid, jsonb, text) to authenticated, service_role;

create or replace function "api"."decide_quote"(quote uuid, decision text, note text, by text, selected jsonb default null, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decide_quote"($1, $2, $3, $4, $5, $6) $$;
revoke execute on function "api"."decide_quote"(uuid, text, text, text, jsonb, jsonb) from public, anon;
grant execute on function "api"."decide_quote"(uuid, text, text, text, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."public_quote"(token text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."public_quote"($1) $$;
revoke execute on function "api"."public_quote"(text) from public;
grant execute on function "api"."public_quote"(text) to anon, authenticated, service_role;

create or replace function "api"."respond_to_quote"(token text, decision text, name text, note text, selected jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."respond_to_quote"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."respond_to_quote"(text, text, text, text, jsonb) from public;
grant execute on function "api"."respond_to_quote"(text, text, text, text, jsonb) to anon, authenticated, service_role;

create or replace function "api"."portal_quote"(quote uuid, actor jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."portal_quote"($1, $2) $$;
revoke execute on function "api"."portal_quote"(uuid, jsonb) from public, anon;
grant execute on function "api"."portal_quote"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."respond_to_portal_quote"(quote uuid, decision text, name text, note text, selected jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."respond_to_portal_quote"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."respond_to_portal_quote"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "api"."respond_to_portal_quote"(uuid, text, text, text, jsonb) to authenticated, service_role;

create or replace function "api"."quote_versions"(quote uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."quote_versions"($1) $$;
revoke execute on function "api"."quote_versions"(uuid) from public, anon;
grant execute on function "api"."quote_versions"(uuid) to authenticated, service_role;

create or replace function "api"."quote_version"(quote uuid, revision integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."quote_version"($1, $2) $$;
revoke execute on function "api"."quote_version"(uuid, integer) from public, anon;
grant execute on function "api"."quote_version"(uuid, integer) to authenticated, service_role;

create or replace function "api"."expire_quotes"()
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."expire_quotes"() $$;
revoke execute on function "api"."expire_quotes"() from public, anon, authenticated;
grant execute on function "api"."expire_quotes"() to service_role;

create or replace function "api"."create_quote_variant"(quote uuid, label text, attrs jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_quote_variant"($1, $2, $3) $$;
revoke execute on function "api"."create_quote_variant"(uuid, text, jsonb) from public, anon;
grant execute on function "api"."create_quote_variant"(uuid, text, jsonb) to authenticated, service_role;

create or replace function "api"."list_quote_variants"(quote uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_quote_variants"($1) $$;
revoke execute on function "api"."list_quote_variants"(uuid) from public, anon;
grant execute on function "api"."list_quote_variants"(uuid) to authenticated, service_role;

create or replace function "api"."select_quote_variant"(quote uuid, options jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."select_quote_variant"($1, $2) $$;
revoke execute on function "api"."select_quote_variant"(uuid, jsonb) from public, anon;
grant execute on function "api"."select_quote_variant"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."import_quote"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_quote"($1, $2, $3) $$;
revoke execute on function "api"."import_quote"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_quote"(uuid, jsonb, text) to service_role;

create or replace function "api"."quote_updated_at"(subject_id text)
returns timestamptz
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."quote_updated_at"($1) $$;
revoke execute on function "api"."quote_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."quote_updated_at"(text) to service_role;

create or replace function "api"."quote_totals_by_billing_party"(quote uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."quote_totals_by_billing_party"($1) $$;
revoke execute on function "api"."quote_totals_by_billing_party"(uuid) from public, anon;
grant execute on function "api"."quote_totals_by_billing_party"(uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block-data quotes
-- @bsb-hash sha256:fe87f8a5895a1bef6d16712af52cf95116d938edc0a677538bebf4ee466198f0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block quotes@3 managed
-- @bsb-hash sha256:aecd495a29d19ab036dedd5b140dec07dc40b1abeb49d24a55ba05f9ea41b3bc
-- Quotes with sections, optional lines, discounts, prices with or without tax, tax per rate and a deposit; published versions; a public link or the signed-in portal the customer accepts, rejects or asks changes through; expiry; and quotes from deals. With catalog, a line that names a product variant takes its price and title.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create or replace function better_supabase.as_column_type(value text, target anyelement)
returns anyelement
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return value;
end;
$$;
revoke execute on function better_supabase.as_column_type(text, anyelement) from public;
grant execute on function better_supabase.as_column_type(text, anyelement) to anon, authenticated, service_role;
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Quotes: line items, sections, optional lines, discounts and tax per rate,
-- published versions, sending with a public link or to the signed-in portal
-- the customer accepts, rejects or asks changes through, and expiry.

-- better_supabase.quotes is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."quotes" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."quotes" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."quotes" add column if not exists "number" bigint;
alter table "better_supabase"."quotes" add column if not exists "identifier" text;
alter table "better_supabase"."quotes" add column if not exists "revision" integer not null default 1;
alter table "better_supabase"."quotes" add column if not exists "title" text check (length("title") between 1 and 300);
alter table "better_supabase"."quotes" add column if not exists "company_type" text;
alter table "better_supabase"."quotes" add column if not exists "company_id" text;
alter table "better_supabase"."quotes" add column if not exists "contact_type" text;
alter table "better_supabase"."quotes" add column if not exists "contact_id" text;
alter table "better_supabase"."quotes" add column if not exists "owner_user_id" uuid;
alter table "better_supabase"."quotes" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."quotes" add column if not exists "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn'));
alter table "better_supabase"."quotes" add column if not exists "valid_until" date;
alter table "better_supabase"."quotes" add column if not exists "terms" text;
alter table "better_supabase"."quotes" add column if not exists "note" text;
alter table "better_supabase"."quotes" add column if not exists "origin_type" text;
alter table "better_supabase"."quotes" add column if not exists "origin_id" text;
alter table "better_supabase"."quotes" add column if not exists "token_hash" text;
alter table "better_supabase"."quotes" add column if not exists "sent_at" timestamptz;
alter table "better_supabase"."quotes" add column if not exists "viewed_at" timestamptz;
alter table "better_supabase"."quotes" add column if not exists "decided_at" timestamptz;
alter table "better_supabase"."quotes" add column if not exists "decided_by" text;
alter table "better_supabase"."quotes" add column if not exists "decision_note" text;
alter table "better_supabase"."quotes" add column if not exists "decided_user_id" uuid;
alter table "better_supabase"."quotes" add column if not exists "decided_ip" text;
alter table "better_supabase"."quotes" add column if not exists "decided_user_agent" text;
alter table "better_supabase"."quotes" add column if not exists "prices_include_tax" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000);
alter table "better_supabase"."quotes" add column if not exists "discount_amount" bigint not null default 0 check ("discount_amount" >= 0);
alter table "better_supabase"."quotes" add column if not exists "deposit_bps" integer check ("deposit_bps" > 0 and "deposit_bps" < 10000);
alter table "better_supabase"."quotes" add column if not exists "deposit_amount" bigint check ("deposit_amount" > 0);
alter table "better_supabase"."quotes" add column if not exists "deposit_required" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "deposit_due" bigint not null default 0;
alter table "better_supabase"."quotes" add column if not exists "unpublished_changes" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "buyer" jsonb;
alter table "better_supabase"."quotes" add column if not exists "variant_of" uuid;
alter table "better_supabase"."quotes" add column if not exists "variant_label" text check (length("variant_label") between 1 and 100);
alter table "better_supabase"."quotes" add column if not exists "is_selected" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "created_by" uuid;
alter table "better_supabase"."quotes" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."quotes" add column if not exists "updated_at" timestamptz not null default now();
alter table "better_supabase"."quotes" add column if not exists "list_total" bigint not null default 0;
alter table "better_supabase"."quotes" add column if not exists "discount_total" bigint not null default 0;
alter table "better_supabase"."quotes" add column if not exists "subtotal" bigint not null default 0;
alter table "better_supabase"."quotes" add column if not exists "tax_total" bigint not null default 0;
alter table "better_supabase"."quotes" add column if not exists "total" bigint not null default 0;
alter table "better_supabase"."quotes" add column if not exists "deposit_amount" bigint check ("deposit_amount" > 0);
alter table "better_supabase"."quotes" add column if not exists "deposit_required" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "unpublished_changes" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "buyer" jsonb;
alter table "better_supabase"."quotes" add column if not exists "variant_of" uuid;
alter table "better_supabase"."quotes" add column if not exists "variant_label" text check (length("variant_label") between 1 and 100);
alter table "better_supabase"."quotes" add column if not exists "is_selected" boolean not null default false;
create index if not exists quotes_tenant_status_idx on "better_supabase"."quotes" ("tenant_id", "status", "created_at" desc);
create index if not exists quotes_variant_idx on "better_supabase"."quotes" ("variant_of") where "variant_of" is not null;
create index if not exists quotes_origin_idx on "better_supabase"."quotes" ("origin_type", "origin_id");

create unique index if not exists "quotes_token_hash_key" on "better_supabase"."quotes" ("token_hash");
alter table "better_supabase"."quotes" enable row level security;
grant select on "better_supabase"."quotes" to authenticated;
grant all on "better_supabase"."quotes" to service_role;
drop policy if exists bsb_quotes_select on "better_supabase"."quotes";
create policy bsb_quotes_select on "better_supabase"."quotes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')));

-- better_supabase.quote_versions is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."quote_versions" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."quote_versions" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."quote_versions" add column if not exists "quote_id" uuid references "better_supabase"."quotes" ("id") on delete cascade;
alter table "better_supabase"."quote_versions" add column if not exists "revision" integer;
alter table "better_supabase"."quote_versions" add column if not exists "snapshot" jsonb;
alter table "better_supabase"."quote_versions" add column if not exists "total" bigint;
alter table "better_supabase"."quote_versions" add column if not exists "currency" char(3);
alter table "better_supabase"."quote_versions" add column if not exists "published_by" uuid;
alter table "better_supabase"."quote_versions" add column if not exists "published_at" timestamptz not null default now();
alter table "better_supabase"."quote_versions" enable row level security;
grant select on "better_supabase"."quote_versions" to authenticated;
grant all on "better_supabase"."quote_versions" to service_role;
drop policy if exists bsb_quote_versions_select on "better_supabase"."quote_versions";
create policy bsb_quote_versions_select on "better_supabase"."quote_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"));
create or replace function better_supabase.bsb_quote_versions_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'a published quote version never changes' using errcode = '55000', hint = 'QUOTE_VERSION_FROZEN';
end;
$$;
revoke execute on function better_supabase.bsb_quote_versions_frozen() from public, anon, authenticated;
drop trigger if exists "bsb_quote_versions_frozen" on "better_supabase"."quote_versions";
create trigger "bsb_quote_versions_frozen" before update on "better_supabase"."quote_versions"
for each row execute function better_supabase.bsb_quote_versions_frozen();

-- better_supabase.quote_tax_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."quote_tax_lines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."quote_tax_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."quote_tax_lines" add column if not exists "parent_id" uuid references "better_supabase"."quotes" ("id") on delete cascade;
alter table "better_supabase"."quote_tax_lines" add column if not exists "tax_rate_bps" integer;
alter table "better_supabase"."quote_tax_lines" add column if not exists "tax_code" text;
alter table "better_supabase"."quote_tax_lines" add column if not exists "net" bigint;
alter table "better_supabase"."quote_tax_lines" add column if not exists "tax" bigint;
alter table "better_supabase"."quote_tax_lines" add column if not exists "gross" bigint;
alter table "better_supabase"."quote_tax_lines" add column if not exists "discount" bigint not null default 0;
create index if not exists quote_tax_lines_parent_idx on "better_supabase"."quote_tax_lines" ("parent_id");
alter table "better_supabase"."quote_tax_lines" enable row level security;
grant select on "better_supabase"."quote_tax_lines" to authenticated;
grant all on "better_supabase"."quote_tax_lines" to service_role;
drop policy if exists bsb_quote_tax_lines_select on "better_supabase"."quote_tax_lines";
create policy bsb_quote_tax_lines_select on "better_supabase"."quote_tax_lines"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"));

-- Creates a draft quote. attrs: title (required), currency, company and
-- contact ({ type, id }), ownerId, validUntil, terms, note, origin ({ type,
-- id }, the record it was made from), pricesIncludeTax, discountBps,
-- discountAmount (minor units as text), depositBps, or depositAmount (minor
-- units as text) for a fixed deposit, and depositRequired, which makes the
-- customer pay it before they accept. lines: see set_quote_lines.
create or replace function "better_supabase"."create_quote"(tenant uuid, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "prices_include_tax", "discount_bps", "discount_amount", "deposit_bps", "deposit_amount", "deposit_required", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id',
      coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce((create_quote.attrs ->> 'discountBps')::integer, 0), coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0), (create_quote.attrs ->> 'depositBps')::integer, (create_quote.attrs ->> 'depositAmount')::bigint, coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft quote, or one the customer asked changes on: title,
-- company, contact, currency, ownerId, validUntil, terms, note,
-- pricesIncludeTax, discountBps, discountAmount, depositBps, depositAmount
-- and depositRequired. The totals follow the new pricing.
create or replace function "better_supabase"."update_quote"(quote uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_user_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "prices_include_tax" = case when update_quote.attrs ? 'pricesIncludeTax' then coalesce((update_quote.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "discount_bps" = case when update_quote.attrs ? 'discountBps' then coalesce((update_quote.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_quote.attrs ? 'discountAmount' then coalesce((update_quote.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "deposit_bps" = case when update_quote.attrs ? 'depositBps' then (update_quote.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "deposit_amount" = case when update_quote.attrs ? 'depositAmount' then (update_quote.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "deposit_required" = case when update_quote.attrs ? 'depositRequired' then coalesce((update_quote.attrs ->> 'depositRequired')::boolean, false) else x."deposit_required" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  perform "better_supabase"."set_quote_lines_recount"(v_row."id");
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."update_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_quote"(uuid, jsonb) to authenticated, service_role;
-- better_supabase.quote_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."quote_lines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."quote_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."quote_lines" add column if not exists "parent_id" uuid references "better_supabase"."quotes" ("id") on delete cascade;
alter table "better_supabase"."quote_lines" add column if not exists "product_type" text;
alter table "better_supabase"."quote_lines" add column if not exists "product_id" text;
alter table "better_supabase"."quote_lines" add column if not exists "description" text check (length("description") between 1 and 2000);
alter table "better_supabase"."quote_lines" add column if not exists "quantity" numeric(18, 4) check ("quantity" > 0);
alter table "better_supabase"."quote_lines" add column if not exists "unit_amount" bigint;
alter table "better_supabase"."quote_lines" add column if not exists "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000);
alter table "better_supabase"."quote_lines" add column if not exists "tax_rate_bps" integer not null default 0 check ("tax_rate_bps" >= 0 and "tax_rate_bps" <= 100000);
alter table "better_supabase"."quote_lines" add column if not exists "tax_code" text;
alter table "better_supabase"."quote_lines" add column if not exists "tax_code_id" uuid;
alter table "better_supabase"."quote_lines" add column if not exists "unit_cost" bigint;
alter table "better_supabase"."quote_lines" add column if not exists "discount_amount" bigint not null default 0 check ("discount_amount" >= 0);
alter table "better_supabase"."quote_lines" add column if not exists "cost_source" text check ("cost_source" in ('catalog', 'average', 'manual', 'imported'));
alter table "better_supabase"."quote_lines" add column if not exists "location_id" uuid;
alter table "better_supabase"."quote_lines" add column if not exists "bin_id" uuid;
alter table "better_supabase"."quote_lines" add column if not exists "billing_party" text not null default 'customer' check ("billing_party" in ('customer', 'internal', 'own_warranty', 'supplier_warranty', 'cost_account'));
alter table "better_supabase"."quote_lines" add column if not exists "billing_party_id" text;
alter table "better_supabase"."quote_lines" add column if not exists "billing_account_id" uuid;
alter table "better_supabase"."quote_lines" add column if not exists "section" text check (length("section") between 1 and 300);
alter table "better_supabase"."quote_lines" add column if not exists "optional" boolean not null default false;
alter table "better_supabase"."quote_lines" add column if not exists "selected" boolean not null default true;
alter table "better_supabase"."quote_lines" add column if not exists "periods" integer not null default 1 check ("periods" > 0);
alter table "better_supabase"."quote_lines" add column if not exists "position" integer;
alter table "better_supabase"."quote_lines" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."quote_lines" add column if not exists "periods" integer not null default 1 check ("periods" > 0);
create index if not exists "quote_lines_parent_idx" on "better_supabase"."quote_lines" ("parent_id", "position");
create unique index if not exists "bsb_quote_lines_position_key" on "better_supabase"."quote_lines" ("parent_id", "position");
alter table "better_supabase"."quote_lines" enable row level security;
grant select on "better_supabase"."quote_lines" to authenticated;
grant all on "better_supabase"."quote_lines" to service_role;
drop policy if exists bsb_quote_lines_select on "better_supabase"."quote_lines";
create policy bsb_quote_lines_select on "better_supabase"."quote_lines" for select to authenticated
using (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"));

-- Writes a record's totals from its counted lines: an optional line counts
-- only when the customer took it. The record discount is spread over the tax
-- rates in proportion to their amounts, and tax is counted once per rate, so
-- the totals and the tax per rate always add up.
create or replace function "better_supabase"."set_quote_lines_recount"(parent uuid)
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
  select x."tenant_id", x."prices_include_tax", x."discount_bps", x."discount_amount", 0
    into v_tenant, v_inclusive, v_record_bps, v_record_amount, v_restriction
  from "better_supabase"."quotes" x where x."id" = set_quote_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount")), 0), coalesce(sum((round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))), 0)
    into v_list, v_line_discount
  from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected");
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) as amount,
      sum(round((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * (10000 - v_restriction) * l."tax_rate_bps" / (10000.0 * (case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)))) as tax
    from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected")
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
  delete from "better_supabase"."quote_tax_lines" x where x."parent_id" = set_quote_lines_recount.parent;
  insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
  select v_tenant, set_quote_lines_recount.parent, r.rate, r.code, r.net, r.tax, r.gross, r.discount
  from jsonb_to_recordset(v_groups) r(rate integer, code text, net bigint, tax bigint, gross bigint, discount bigint);
  update "better_supabase"."quotes" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_subtotal,
    "tax_total" = v_tax,
    "total" = v_total,
    "deposit_due" = case when x."deposit_amount" is not null then least(greatest(v_total, 0), x."deposit_amount") when x."deposit_bps" is not null then round(v_total * x."deposit_bps" / 10000.0)::bigint else 0 end
  where x."id" = set_quote_lines_recount.parent;
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines_recount"(uuid) from public, anon, authenticated;

-- Recounts each record a statement touched once, in id order so concurrent
-- statements lock the records in the same order. A transition table needs a
-- trigger per event, so there are three triggers on one function. The
-- transition tables are read through execute because plpgsql_check (db lint)
-- doesn't know them.
create or replace function better_supabase.bsb_quote_lines_totals()
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
    perform "better_supabase"."set_quote_lines_recount"(v_parent);
  end loop;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_quote_lines_totals() from public, anon, authenticated;
drop trigger if exists bsb_quote_lines_totals on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_insert on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_update on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_delete on "better_supabase"."quote_lines";
create trigger bsb_quote_lines_totals_insert after insert on "better_supabase"."quote_lines"
referencing new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_update after update on "better_supabase"."quote_lines"
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_delete after delete on "better_supabase"."quote_lines"
referencing old table as old_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
create or replace function "better_supabase"."set_quote_lines"(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := set_quote_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."currency" into v_tenant, v_currency from "better_supabase"."quotes" x where x."id" = v_parent and not (not (x."status" in ('draft', 'changes_requested')));
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."quotes" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false))) then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_quote_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_quote_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."quote_lines" l where l."parent_id" = v_parent and l."position" > jsonb_array_length(coalesce(set_quote_lines.lines, '[]'));
  begin
    insert into "better_supabase"."quote_lines" as l ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "section", "optional", "selected", "periods", "position")
    select v_tenant,
      v_parent,
      better_supabase.as_column_type(x.value -> 'product' ->> 'type', (null::"better_supabase"."quote_lines")."product_type"),
      better_supabase.as_column_type(x.value -> 'product' ->> 'id', (null::"better_supabase"."quote_lines")."product_id"),
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
      nullif(trim(x.value ->> 'section'), ''),
      coalesce((x.value ->> 'optional')::boolean, false),
      coalesce((x.value ->> 'selected')::boolean, not coalesce((x.value ->> 'optional')::boolean, false)),
      coalesce((x.value ->> 'periods')::integer, 1),
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_quote_lines.lines, '[]')) with ordinality x
    on conflict ("parent_id", "position") do update set "product_type" = excluded."product_type", "product_id" = excluded."product_id", "description" = excluded."description", "quantity" = excluded."quantity", "unit_amount" = excluded."unit_amount", "discount_bps" = excluded."discount_bps", "tax_rate_bps" = excluded."tax_rate_bps", "tax_code" = excluded."tax_code", "tax_code_id" = excluded."tax_code_id", "unit_cost" = excluded."unit_cost", "discount_amount" = excluded."discount_amount", "cost_source" = excluded."cost_source", "location_id" = excluded."location_id", "bin_id" = excluded."bin_id", "billing_party" = excluded."billing_party", "billing_party_id" = excluded."billing_party_id", "billing_account_id" = excluded."billing_account_id", "section" = excluded."section", "optional" = excluded."optional", "selected" = excluded."selected", "periods" = excluded."periods";
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_quote_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."quotes" x where x."id" = v_parent);
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) to authenticated, service_role;

-- Sends a quote: it gets a public link the customer opens and a published
-- version, a snapshot that never changes. The quote can't change until it is
-- revised or the customer asks for changes; sending it again then publishes
-- the next revision. Returns the quote with the link's token, which is stored
-- only as a hash and returned this once.
-- actor: who sent it, for the state machine's history.
drop function if exists "better_supabase"."send_quote"(uuid);
create or replace function "better_supabase"."send_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = send_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'the quote was already sent; revise it to send a new version' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if not exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_row."id") then
    raise exception 'a quote needs a line before it is sent' using errcode = '23514', hint = 'QUOTE_EMPTY';
  end if;
  if send_quote.actor is not null then
    if jsonb_typeof(send_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(send_quote.actor ->> 'ip', '')::inet, nullif(send_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(send_quote.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "revision" = case when exists (select 1 from "better_supabase"."quote_versions" v where v."quote_id" = x."id" and v."revision" = x."revision") then x."revision" + 1 else x."revision" end,
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "better_supabase"."quote_versions" ("tenant_id", "quote_id", "revision", "snapshot", "total", "currency", "published_by")
  values (v_row."tenant_id", v_row."id", v_row."revision", (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), v_row."total", v_row."currency", coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid))
  returning "id" into v_version;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)) || jsonb_build_object('token', v_token);
end;
$$;
revoke execute on function "better_supabase"."send_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."send_quote"(uuid, jsonb) to authenticated, service_role;

-- Opens a sent or declined quote again as a draft of its next revision: the
-- same quote, number and lines, a fresh valid-until date, and its link ends.
-- The versions already published stay as they were. An accepted quote is
-- kept as the customer accepted it; start a new quote instead.
drop function if exists "better_supabase"."revise_quote"(uuid);
create or replace function "better_supabase"."revise_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = revise_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft is edited, not revised' using errcode = '55000', hint = 'QUOTE_NOT_SENT';
  end if;
  if v_row."status" = 'accepted' then
    raise exception 'an accepted quote stays as accepted; start a new quote' using errcode = '55000', hint = 'QUOTE_ACCEPTED';
  end if;
  if revise_quote.actor is not null then
    if jsonb_typeof(revise_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(revise_quote.actor ->> 'ip', '')::inet, nullif(revise_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(revise_quote.actor::text, ''), true);
  update "better_supabase"."quotes" x set "status" = 'draft', "revision" = x."revision" + 1, "token_hash" = null, "sent_at" = null, "viewed_at" = null,
    "valid_until" = greatest(x."valid_until", current_date + 30),
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."revise_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."revise_quote"(uuid, jsonb) to authenticated, service_role;

-- Takes back a sent or expired quote the customer hasn't accepted: it can't
-- be answered any more until it is revised and sent again. The actor and
-- reason go to the state machine's history.
drop function if exists "better_supabase"."withdraw_quote"(uuid, jsonb);
create or replace function "better_supabase"."withdraw_quote"(quote uuid, actor jsonb default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = withdraw_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" not in ('sent', 'viewed', 'changes_requested', 'expired') then
    raise exception 'only a sent quote that wasn''t answered is withdrawn' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if withdraw_quote.actor is not null then
    if jsonb_typeof(withdraw_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(withdraw_quote.actor ->> 'ip', '')::inet, nullif(withdraw_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(withdraw_quote.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(withdraw_quote.reason), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = 'withdrawn', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) to authenticated, service_role;

-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name,
-- and without it or an actor the answer names no one. The note is also the
-- reason in the state machine's history.
-- selected lists the positions of the optional lines they took. actor is
-- the customer when the app takes the answer in its own portal: id, name,
-- email, ip and userAgent, kept with the answer and in the state machine's
-- history; a quote past its valid date then expires instead, and the expired
-- quote is returned.
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text);
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."decide_quote"(quote uuid, decision text, note text, by text, selected jsonb default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = better_supabase.as_column_type(decide_quote.decision, (null::"better_supabase"."quotes")."status"), "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decided_user_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) to authenticated, service_role;

-- What the customer sees through the link: the quote without internal
-- notes. Opening a sent quote marks it viewed. Callable without signing in.
create or replace function "better_supabase"."public_quote"(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(public_quote.token, 'sha256'), 'hex');
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke all on function "better_supabase"."public_quote"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."public_quote"(text) to anon, authenticated, service_role;

-- The customer's answer through the link: accepted, rejected or
-- changes_requested, with their name, a note and the optional lines they
-- took. Their address and browser are kept with the answer. A quote past its
-- valid date expires instead.
drop function if exists "better_supabase"."respond_to_quote"(text, text, text, text);
create or replace function "better_supabase"."respond_to_quote"(token text, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(respond_to_quote.token, 'sha256'), 'hex') for update;
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  if respond_to_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(respond_to_quote.name), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_quote.selected is not null then
      if jsonb_typeof(respond_to_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = better_supabase.as_column_type(respond_to_quote.decision, (null::"better_supabase"."quotes")."status"), "decided_at" = now(), "decided_by" = nullif(trim(respond_to_quote.name), ''),
    "decision_note" = nullif(trim(respond_to_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke all on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) to anon, authenticated, service_role;

-- A quote shared with the signed-in guest, as the customer sees it: through
-- a grant on the quote or as a guest of its company or contact. Opening a
-- sent quote marks it viewed. No link token is needed. The service role
-- reads it too, for an app's own portal; actor is then the customer who
-- opened it, for the state machine's history.
drop function if exists "better_supabase"."portal_quote"(uuid);
create or replace function "better_supabase"."portal_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if portal_quote.actor is not null and not (auth.role() = 'service_role') then
    raise exception 'only the service role names who opened a quote' using errcode = '42501', hint = 'QUOTE_ACTOR_FORBIDDEN';
  end if;
  if portal_quote.actor is not null then
    if jsonb_typeof(portal_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(portal_quote.actor ->> 'ip', '')::inet, nullif(portal_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(portal_quote.actor::text, ''), true);
  if portal_quote.actor is null then
    begin
      v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
    exception when invalid_text_representation then
      v_ip := null;
    end;
    perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = portal_quote.quote and (false or ((auth.role() = 'service_role') and x."status" <> 'draft'));
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."portal_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."portal_quote"(uuid, jsonb) to authenticated, service_role;

-- The signed-in guest's answer to a quote shared with them, like
-- respond_to_quote without a token. name defaults to their email; the
-- answer keeps who they are, their address and their browser.
create or replace function "better_supabase"."respond_to_portal_quote"(quote uuid, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = respond_to_portal_quote.quote and false for update;
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if respond_to_portal_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_portal_quote.selected is not null then
      if jsonb_typeof(respond_to_portal_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_portal_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_portal_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = better_supabase.as_column_type(respond_to_portal_quote.decision, (null::"better_supabase"."quotes")."status"), "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''),
    "decision_note" = nullif(trim(respond_to_portal_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_portal_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_portal_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) to authenticated, service_role;

-- The versions of a quote that were sent, oldest first, without their
-- snapshots.
create or replace function "better_supabase"."quote_versions"(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_versions.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('revision', x."revision", 'total', x."total"::text, 'currency', x."currency",
      'publishedAt', x."published_at", 'publishedBy', x."published_by") order by x."revision")
    from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id"), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."quote_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_versions"(uuid) to authenticated, service_role;

-- The quote as it was sent at revision: the snapshot published then.
create or replace function "better_supabase"."quote_version"(quote uuid, revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_version "better_supabase"."quote_versions";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_version.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id" and x."revision" = quote_version.revision;
  if v_version."id" is null then
    raise exception 'this quote has no such version' using errcode = 'P0002', hint = 'QUOTE_VERSION_NOT_FOUND';
  end if;
  return v_version."snapshot" || jsonb_build_object('revision', v_version."revision", 'publishedAt', v_version."published_at");
end;
$$;
revoke execute on function "better_supabase"."quote_version"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."quote_version"(uuid, integer) to authenticated, service_role;

-- Expires sent quotes past their valid date. Run it daily from a job.
create or replace function "better_supabase"."expire_quotes"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_count integer := 0;
begin
  perform set_config('better_supabase.transition_actor', '', true);
  for v_row in
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now()
    where x."status" in ('sent', 'viewed') and x."valid_until" < current_date
    returning *
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_quotes"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_quotes"() to service_role;

-- Makes another variant of a quote: a new draft quote with the same pricing,
-- party and lines, grouped under the same root. label names it (A, B, Basic,
-- Premium) and is unique within the group; attrs change the new quote like
-- create_quote's. The first variant gives the quote it came from the label
-- Original when it has none.
create or replace function "better_supabase"."create_quote_variant"(quote uuid, label text, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
  v_root uuid;
  v_label text := nullif(trim(create_quote_variant.label), '');
  v_made jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."quotes" x where x."id" = create_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false));
  if v_src."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_label is null or length(v_label) > 100 then
    raise exception 'a variant needs a label of up to 100 characters' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  v_root := coalesce(v_src."variant_of", v_src."id");
  if exists (select 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) and lower(x."variant_label") = lower(v_label)) then
    raise exception 'another variant of this quote has that label' using errcode = '23505', hint = 'QUOTE_VARIANT_LABEL_TAKEN';
  end if;
  v_made := "better_supabase"."create_quote"(v_src."tenant_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'currency', v_src."currency", 'validUntil', v_src."valid_until",
    'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'terms', v_src."terms", 'note', v_src."note", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount"::text, 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount"::text, 'depositRequired', v_src."deposit_required")) || coalesce(create_quote_variant.attrs, '{}'::jsonb), null);
  v_id := (v_made ->> 'id')::uuid;
  insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position", "section", "optional", "selected", "periods")
  select x."tenant_id", v_id, x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position", x."section", x."optional", x."selected", x."periods" from "better_supabase"."quote_lines" x where x."parent_id" = v_src."id";
  update "better_supabase"."quotes" x set "variant_label" = coalesce(x."variant_label", 'Original')
  where x."id" = v_root;
  update "better_supabase"."quotes" x set "variant_of" = v_root, "variant_label" = v_label, "is_selected" = false
  where x."id" = v_id;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) to authenticated, service_role;

-- The quotes of one group of variants, the root first. isSelected tells which
-- one the customer chose.
create or replace function "better_supabase"."list_quote_variants"(quote uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
begin
  select * into v_src from "better_supabase"."quotes" x where x."id" = list_quote_variants.quote;
  if v_src."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."tenant_id", 'quotes.read'), false)) then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = coalesce(v_src."variant_of", v_src."id") or x."variant_of" = coalesce(v_src."variant_of", v_src."id")));
end;
$$;
revoke execute on function "better_supabase"."list_quote_variants"(uuid) from public, anon;
grant execute on function "better_supabase"."list_quote_variants"(uuid) to authenticated, service_role;

-- Selects one variant of a quote and marks the others of its group not
-- selected; only the selected variant becomes an order or an invoice. A
-- withdrawn, rejected or expired variant can't be selected. options.forward
-- is order or invoice to copy the selected variant forward in the same call
-- (the quote must be accepted, as for order_from_quote and invoice_from_quote);
-- options.attrs go to order_from_quote and options.depositBps to
-- invoice_from_quote.
create or replace function "better_supabase"."select_quote_variant"(quote uuid, options jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_root uuid;
  v_forward text := nullif(select_quote_variant.options ->> 'forward', '');
  v_order jsonb;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = select_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  v_root := coalesce(v_row."variant_of", v_row."id");
  if v_row."variant_of" is null and not exists (select 1 from "better_supabase"."quotes" x where x."variant_of" = v_row."id") then
    raise exception 'this quote has no variants' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  if v_row."status" in ('withdrawn', 'rejected', 'expired') then
    raise exception 'a withdrawn, rejected or expired variant can''t be selected' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTABLE';
  end if;
  if v_forward is not null and v_forward not in ('') then
    raise exception 'forward is order or invoice' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  perform 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) for update;
  update "better_supabase"."quotes" x set "is_selected" = (x."id" = v_row."id"), "updated_at" = now()
  where (x."id" = v_root or x."variant_of" = v_root) and x."is_selected" is distinct from (x."id" = v_row."id");
  if v_forward is not null and v_order is null and v_invoice is null then
    raise exception 'the organization has no block to copy the variant forward to' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  return jsonb_build_object('quote', (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), 'variants', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root)), 'order', v_order, 'invoice', v_invoice);
end;
$$;
revoke execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) to authenticated, service_role;

-- The import target of the quote entity (ADR 0141): item.data is { number,
-- status?, title?, currency, validUntil?, createdAt?, sentAt?, viewedAt?,
-- decidedAt?, decidedBy?, decisionNote?, company?, contact?, origin?,
-- pricesIncludeTax?, attrs?, legalEntityId?, buyer?, lines, taxLines?,
-- totals? }. A quote that is already imported is kept as it is.
create or replace function "better_supabase"."import_quote"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_quote.item ->> 'tenant')::uuid;
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."quotes";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from "better_supabase"."quotes" y where y."id" = import_quote.subject_id::uuid and y."tenant_id" = v_tenant;
    if not found then
      raise exception 'the quote no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
  end if;
  if v_number is null then
    raise exception 'a quote needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    raise exception 'status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a quote needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  v_made := "better_supabase"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Quote ' || v_number),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> 'id')::uuid;
  update "better_supabase"."quotes" y set
    "status" = better_supabase.as_column_type(coalesce(v_data ->> 'status', 'draft'), (null::"better_supabase"."quotes")."status"),
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
    "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
    "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
    "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
    "decided_by" = nullif(v_data ->> 'decidedBy', ''),
    "decision_note" = nullif(v_data ->> 'decisionNote', ''),
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
    "updated_at" = now()
  where y."id" = v_id;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(z."tax_code", '') || ':' || z."tax_rate_bps"::text as key, sum(z."net") as net, sum(z."tax") as tax
        from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id;
    insert into "better_supabase"."quote_tax_lines" ("tenant_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint), coalesce((g.value ->> 'discount')::bigint, 0)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."quotes" y set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, y."total")
    where y."id" = v_id;
  end if;
  select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_quote"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_quote"(uuid, jsonb, text) to service_role;

-- When a quote last changed, for the conflict check of imports.
create or replace function "better_supabase"."quote_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select y."updated_at" from "better_supabase"."quotes" y where y."id" = $1::uuid
$$;
revoke execute on function "better_supabase"."quote_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."quote_updated_at"(text) to service_role;

-- Totals and cost of one record's lines per billing party (ADR 0141). It runs
-- as the caller, so only lines the caller can read count.
create or replace function "better_supabase"."quote_totals_by_billing_party"(quote uuid)
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
        'lines', count(*), 'net', sum((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))))::text, 'cost', sum(round(l."quantity" * l."unit_cost"))::text
      ) as row
    from "better_supabase"."quote_lines" l
    where l."parent_id" = quote and (not l."optional" or l."selected")
    group by 1, 2, 3
  ) g
$$;
revoke execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
create policy bsb_tenant_scope_select on "better_supabase"."quotes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
create policy bsb_tenant_scope_insert on "better_supabase"."quotes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
create policy bsb_tenant_scope_update on "better_supabase"."quotes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
create policy bsb_tenant_scope_delete on "better_supabase"."quotes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_select on "better_supabase"."quote_versions" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_versions" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_update on "better_supabase"."quote_versions" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_versions" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_tax_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_tax_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block-data quotes
-- @bsb-hash sha256:fe87f8a5895a1bef6d16712af52cf95116d938edc0a677538bebf4ee466198f0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block quotes@3 managed
-- @bsb-hash sha256:30738cff9d20d0465c055a7623e35be36666b517514017a2cd85eb6edc97ffc4
-- Quotes with sections, optional lines, discounts, prices with or without tax, tax per rate and a deposit; published versions; a public link or the signed-in portal the customer accepts, rejects or asks changes through; expiry; and quotes from deals. With catalog, a line that names a product variant takes its price and title.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Quotes: line items, sections, optional lines, discounts and tax per rate,
-- published versions, sending with a public link or to the signed-in portal
-- the customer accepts, rejects or asks changes through, and expiry.

create table if not exists "better_supabase"."quotes" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "revision" integer not null default 1,
  "title" text not null check (length("title") between 1 and 300),
  "company_type" text,
  "company_id" text,
  "contact_type" text,
  "contact_id" text,
  "owner_user_id" uuid,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn')),
  "valid_until" date,
  "terms" text,
  "note" text,
  "origin_type" text,
  "origin_id" text,
  "token_hash" text unique,
  "sent_at" timestamptz,
  "viewed_at" timestamptz,
  "decided_at" timestamptz,
  "decided_by" text,
  "decision_note" text,
  "decided_user_id" uuid,
  "decided_ip" text,
  "decided_user_agent" text,
  "prices_include_tax" boolean not null default false,
  "discount_bps" integer not null default 0 check ("discount_bps" >= 0 and "discount_bps" <= 10000),
  "discount_amount" bigint not null default 0 check ("discount_amount" >= 0),
  "deposit_bps" integer check ("deposit_bps" > 0 and "deposit_bps" < 10000),
  "deposit_amount" bigint check ("deposit_amount" > 0),
  "deposit_required" boolean not null default false,
  "deposit_due" bigint not null default 0,
  "unpublished_changes" boolean not null default false,
  "buyer" jsonb,
  "variant_of" uuid,
  "variant_label" text check (length("variant_label") between 1 and 100),
  "is_selected" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "list_total" bigint not null default 0,
  "discount_total" bigint not null default 0,
  "subtotal" bigint not null default 0,
  "tax_total" bigint not null default 0,
  "total" bigint not null default 0,
  unique ("org_id", "number", "revision"),
  check (("company_type" is null) = ("company_id" is null)),
  check (("origin_type" is null) = ("origin_id" is null))
);
alter table "better_supabase"."quotes" add column if not exists "deposit_amount" bigint check ("deposit_amount" > 0);
alter table "better_supabase"."quotes" add column if not exists "deposit_required" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "unpublished_changes" boolean not null default false;
alter table "better_supabase"."quotes" add column if not exists "buyer" jsonb;
alter table "better_supabase"."quotes" add column if not exists "variant_of" uuid;
alter table "better_supabase"."quotes" add column if not exists "variant_label" text check (length("variant_label") between 1 and 100);
alter table "better_supabase"."quotes" add column if not exists "is_selected" boolean not null default false;
create index if not exists quotes_tenant_status_idx on "better_supabase"."quotes" ("org_id", "status", "created_at" desc);
create index if not exists quotes_variant_idx on "better_supabase"."quotes" ("variant_of") where "variant_of" is not null;
create index if not exists quotes_origin_idx on "better_supabase"."quotes" ("origin_type", "origin_id");

alter table "better_supabase"."quotes" enable row level security;
revoke all on "better_supabase"."quotes" from public, anon, authenticated;
grant select on "better_supabase"."quotes" to authenticated;
grant all on "better_supabase"."quotes" to service_role;
drop policy if exists quotes_read on "better_supabase"."quotes";
create policy quotes_read on "better_supabase"."quotes"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('quotes.read')));

create table if not exists "better_supabase"."quote_versions" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "quote_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
  "revision" integer not null,
  "snapshot" jsonb not null,
  "total" bigint not null,
  "currency" char(3) not null,
  "published_by" uuid,
  "published_at" timestamptz not null default now(),
  unique ("quote_id", "revision")
);
alter table "better_supabase"."quote_versions" enable row level security;
revoke all on "better_supabase"."quote_versions" from public, anon, authenticated;
grant select on "better_supabase"."quote_versions" to authenticated;
grant all on "better_supabase"."quote_versions" to service_role;
drop policy if exists quote_versions_read on "better_supabase"."quote_versions";
create policy quote_versions_read on "better_supabase"."quote_versions"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"));
create or replace function better_supabase.bsb_quote_versions_frozen()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'a published quote version never changes' using errcode = '55000', hint = 'QUOTE_VERSION_FROZEN';
end;
$$;
revoke execute on function better_supabase.bsb_quote_versions_frozen() from public, anon, authenticated;
drop trigger if exists "bsb_quote_versions_frozen" on "better_supabase"."quote_versions";
create trigger "bsb_quote_versions_frozen" before update on "better_supabase"."quote_versions"
for each row execute function better_supabase.bsb_quote_versions_frozen();

create table if not exists "better_supabase"."quote_tax_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
  "tax_rate_bps" integer not null,
  "tax_code" text,
  "net" bigint not null,
  "tax" bigint not null,
  "gross" bigint not null,
  "discount" bigint not null default 0
);
create index if not exists quote_tax_lines_parent_idx on "better_supabase"."quote_tax_lines" ("parent_id");
alter table "better_supabase"."quote_tax_lines" enable row level security;
revoke all on "better_supabase"."quote_tax_lines" from public, anon, authenticated;
grant select on "better_supabase"."quote_tax_lines" to authenticated;
grant all on "better_supabase"."quote_tax_lines" to service_role;
drop policy if exists quote_tax_lines_read on "better_supabase"."quote_tax_lines";
create policy quote_tax_lines_read on "better_supabase"."quote_tax_lines"
  for select to authenticated
  using (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"));

-- Creates a draft quote. attrs: title (required), currency, company and
-- contact ({ type, id }), ownerId, validUntil, terms, note, origin ({ type,
-- id }, the record it was made from), pricesIncludeTax, discountBps,
-- discountAmount (minor units as text), depositBps, or depositAmount (minor
-- units as text) for a fixed deposit, and depositRequired, which makes the
-- customer pay it before they accept. lines: see set_quote_lines.
create or replace function "better_supabase"."create_quote"(tenant uuid, attrs jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_seq bigint;
  v_identifier text;
  v_row "better_supabase"."quotes";
  v_company_type text := coalesce(create_quote.attrs -> 'company' ->> 'type', 'company');
  v_company_id text := create_quote.attrs -> 'company' ->> 'id';
  v_contact_type text := coalesce(create_quote.attrs -> 'contact' ->> 'type', 'person');
  v_contact_id text := create_quote.attrs -> 'contact' ->> 'id';
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_quote.tenant, 'quotes.write'), false)) then
    raise exception 'not allowed to change quotes' using errcode = '42501', hint = 'QUOTE_FORBIDDEN';
  end if;
  if nullif(trim(create_quote.attrs ->> 'title'), '') is null then
    raise exception 'a quote needs a title' using errcode = '23502', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_identifier := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'quote' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_identifier from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."org_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."quotes" ("org_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "prices_include_tax", "discount_bps", "discount_amount", "deposit_bps", "deposit_amount", "deposit_required", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id',
      coalesce((create_quote.attrs ->> 'pricesIncludeTax')::boolean, false), coalesce((create_quote.attrs ->> 'discountBps')::integer, 0), coalesce((create_quote.attrs ->> 'discountAmount')::bigint, 0), (create_quote.attrs ->> 'depositBps')::integer, (create_quote.attrs ->> 'depositAmount')::bigint, coalesce((create_quote.attrs ->> 'depositRequired')::boolean, false), auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  return (select ((to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft quote, or one the customer asked changes on: title,
-- company, contact, currency, ownerId, validUntil, terms, note,
-- pricesIncludeTax, discountBps, discountAmount, depositBps, depositAmount
-- and depositRequired. The totals follow the new pricing.
create or replace function "better_supabase"."update_quote"(quote uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = update_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.write'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'only a draft quote, or one with changes requested, can change' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if (update_quote.attrs -> 'company' ->> 'id') is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_COMPANY_FORBIDDEN';
  end if;
  if (update_quote.attrs -> 'contact' ->> 'id') is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'QUOTE_CONTACT_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."quotes" x set
      "title" = coalesce(nullif(trim(update_quote.attrs ->> 'title'), ''), x."title"),
      "currency" = coalesce(upper(update_quote.attrs ->> 'currency'), x."currency"),
      "owner_user_id" = case when update_quote.attrs ? 'ownerId' then (update_quote.attrs ->> 'ownerId')::uuid else x."owner_user_id" end,
      "valid_until" = case when update_quote.attrs ? 'validUntil' then (update_quote.attrs ->> 'validUntil')::date else x."valid_until" end,
      "terms" = case when update_quote.attrs ? 'terms' then update_quote.attrs ->> 'terms' else x."terms" end,
      "note" = case when update_quote.attrs ? 'note' then update_quote.attrs ->> 'note' else x."note" end,
      "prices_include_tax" = case when update_quote.attrs ? 'pricesIncludeTax' then coalesce((update_quote.attrs ->> 'pricesIncludeTax')::boolean, false) else x."prices_include_tax" end,
      "discount_bps" = case when update_quote.attrs ? 'discountBps' then coalesce((update_quote.attrs ->> 'discountBps')::integer, 0) else x."discount_bps" end,
      "discount_amount" = case when update_quote.attrs ? 'discountAmount' then coalesce((update_quote.attrs ->> 'discountAmount')::bigint, 0) else x."discount_amount" end,
      "deposit_bps" = case when update_quote.attrs ? 'depositBps' then (update_quote.attrs ->> 'depositBps')::integer else x."deposit_bps" end,
      "deposit_amount" = case when update_quote.attrs ? 'depositAmount' then (update_quote.attrs ->> 'depositAmount')::bigint else x."deposit_amount" end,
      "deposit_required" = case when update_quote.attrs ? 'depositRequired' then coalesce((update_quote.attrs ->> 'depositRequired')::boolean, false) else x."deposit_required" end,
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  exception when check_violation or invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if v_row."deposit_bps" is not null and v_row."deposit_amount" is not null then
    raise exception 'a deposit is a share (depositBps) or an amount (depositAmount), not both' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end if;
  perform "better_supabase"."set_quote_lines_recount"(v_row."id");
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  null;
  return ((to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id")) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."update_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."update_quote"(uuid, jsonb) to authenticated, service_role;
create table if not exists "better_supabase"."quote_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "parent_id" uuid not null references "better_supabase"."quotes" ("id") on delete cascade,
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
  "section" text check (length("section") between 1 and 300),
  "optional" boolean not null default false,
  "selected" boolean not null default true,
  "periods" integer not null default 1 check ("periods" > 0),
  "position" integer not null,
  "created_at" timestamptz not null default now(),
  check (("product_type" is null) = ("product_id" is null))
);
alter table "better_supabase"."quote_lines" add column if not exists "periods" integer not null default 1 check ("periods" > 0);
create index if not exists "quote_lines_parent_idx" on "better_supabase"."quote_lines" ("parent_id", "position");
alter table "better_supabase"."quote_lines" enable row level security;
revoke all on "better_supabase"."quote_lines" from public, anon, authenticated;
grant select on "better_supabase"."quote_lines" to authenticated;
grant all on "better_supabase"."quote_lines" to service_role;
drop policy if exists "quote_lines_read" on "better_supabase"."quote_lines";
create policy "quote_lines_read" on "better_supabase"."quote_lines" for select to authenticated
using (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"));

-- Writes a record's totals from its counted lines: an optional line counts
-- only when the customer took it. The record discount is spread over the tax
-- rates in proportion to their amounts, and tax is counted once per rate, so
-- the totals and the tax per rate always add up.
create or replace function "better_supabase"."set_quote_lines_recount"(parent uuid)
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
  select x."org_id", x."prices_include_tax", x."discount_bps", x."discount_amount", 0
    into v_tenant, v_inclusive, v_record_bps, v_record_amount, v_restriction
  from "better_supabase"."quotes" x where x."id" = set_quote_lines_recount.parent;
  select coalesce(sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount")), 0), coalesce(sum((round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))), 0)
    into v_list, v_line_discount
  from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected");
  v_net := v_list - v_line_discount;
  v_record_discount := case
    when v_net > 0 then least(v_net, round(v_net * coalesce(v_record_bps, 0) / 10000.0)::bigint + coalesce(v_record_amount, 0))
    else 0
  end;
  with grouped as (
    select l."tax_rate_bps" as rate, l."tax_code" as code, sum(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) as amount,
      sum(round((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))) * (10000 - v_restriction) * l."tax_rate_bps" / (10000.0 * (case when v_inclusive then 10000.0 + l."tax_rate_bps" else 10000.0 end)))) as tax
    from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent and (not l."optional" or l."selected")
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
  delete from "better_supabase"."quote_tax_lines" x where x."parent_id" = set_quote_lines_recount.parent;
  insert into "better_supabase"."quote_tax_lines" ("org_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
  select v_tenant, set_quote_lines_recount.parent, r.rate, r.code, r.net, r.tax, r.gross, r.discount
  from jsonb_to_recordset(v_groups) r(rate integer, code text, net bigint, tax bigint, gross bigint, discount bigint);
  update "better_supabase"."quotes" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_subtotal,
    "tax_total" = v_tax,
    "total" = v_total,
    "deposit_due" = case when x."deposit_amount" is not null then least(greatest(v_total, 0), x."deposit_amount") when x."deposit_bps" is not null then round(v_total * x."deposit_bps" / 10000.0)::bigint else 0 end
  where x."id" = set_quote_lines_recount.parent;
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines_recount"(uuid) from public, anon, authenticated;

-- Recounts each record a statement touched once, in id order so concurrent
-- statements lock the records in the same order. A transition table needs a
-- trigger per event, so there are three triggers on one function. The
-- transition tables are read through execute because plpgsql_check (db lint)
-- doesn't know them.
create or replace function better_supabase.bsb_quote_lines_totals()
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
    perform "better_supabase"."set_quote_lines_recount"(v_parent);
  end loop;
  return null;
end;
$$;
revoke execute on function better_supabase.bsb_quote_lines_totals() from public, anon, authenticated;
drop trigger if exists bsb_quote_lines_totals on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_insert on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_update on "better_supabase"."quote_lines";
drop trigger if exists bsb_quote_lines_totals_delete on "better_supabase"."quote_lines";
create trigger bsb_quote_lines_totals_insert after insert on "better_supabase"."quote_lines"
referencing new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_update after update on "better_supabase"."quote_lines"
referencing old table as old_rows new table as new_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();
create trigger bsb_quote_lines_totals_delete after delete on "better_supabase"."quote_lines"
referencing old table as old_rows
for each statement execute function better_supabase.bsb_quote_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units as text), currency, discountBps, taxRateBps,
-- taxCode, product: { type, id } }. A line's currency must be the record's.
-- Returns the record's totals as text, with its currency.
create or replace function "better_supabase"."set_quote_lines"(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := set_quote_lines.parent;
  v_tenant uuid;
  v_currency text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."org_id", x."currency" into v_tenant, v_currency from "better_supabase"."quotes" x where x."id" = v_parent and not (not (x."status" in ('draft', 'changes_requested')));
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."quotes" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.write'), false))) then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_quote_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  if exists (select 1 from jsonb_array_elements(set_quote_lines.lines) x where x.value ? 'currency' and x.value ->> 'currency' is distinct from v_currency) then
    raise exception 'every line must be in the record''s currency' using errcode = '22023', hint = 'LINES_CURRENCY';
  end if;
  delete from "better_supabase"."quote_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."quote_lines" ("org_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "section", "optional", "selected", "periods", "position")
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
      nullif(trim(x.value ->> 'section'), ''),
      coalesce((x.value ->> 'optional')::boolean, false),
      coalesce((x.value ->> 'selected')::boolean, not coalesce((x.value ->> 'optional')::boolean, false)),
      coalesce((x.value ->> 'periods')::integer, 1),
      x.ordinality::integer
    from jsonb_array_elements(coalesce(set_quote_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_quote_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text,
    'currency', x."currency")
    from "better_supabase"."quotes" x where x."id" = v_parent);
end;
$$;
revoke execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_quote_lines"(uuid, jsonb) to authenticated, service_role;

-- Sends a quote: it gets a public link the customer opens and a published
-- version, a snapshot that never changes. The quote can't change until it is
-- revised or the customer asks for changes; sending it again then publishes
-- the next revision. Returns the quote with the link's token, which is stored
-- only as a hash and returned this once.
-- actor: who sent it, for the state machine's history.
drop function if exists "better_supabase"."send_quote"(uuid);
create or replace function "better_supabase"."send_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
  v_version uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = send_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if not (v_row."status" in ('draft', 'changes_requested')) then
    raise exception 'the quote was already sent; revise it to send a new version' using errcode = '55000', hint = 'QUOTE_NOT_EDITABLE';
  end if;
  if not exists (select 1 from "better_supabase"."quote_lines" x where x."parent_id" = v_row."id") then
    raise exception 'a quote needs a line before it is sent' using errcode = '23514', hint = 'QUOTE_EMPTY';
  end if;
  if send_quote.actor is not null then
    if jsonb_typeof(send_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(send_quote.actor ->> 'ip', '')::inet, nullif(send_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(send_quote.actor::text, ''), true);
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "revision" = case when exists (select 1 from "better_supabase"."quote_versions" v where v."quote_id" = x."id" and v."revision" = x."revision") then x."revision" + 1 else x."revision" end,
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  insert into "better_supabase"."quote_versions" ("org_id", "quote_id", "revision", "snapshot", "total", "currency", "published_by")
  values (v_row."org_id", v_row."id", v_row."revision", ((to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id")) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), v_row."total", v_row."currency", coalesce(auth.uid(), nullif(send_quote.actor ->> 'id', '')::uuid))
  returning "id" into v_version;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return ((to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id")) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)) || jsonb_build_object('token', v_token);
end;
$$;
revoke execute on function "better_supabase"."send_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."send_quote"(uuid, jsonb) to authenticated, service_role;

-- Opens a sent or declined quote again as a draft of its next revision: the
-- same quote, number and lines, a fresh valid-until date, and its link ends.
-- The versions already published stay as they were. An accepted quote is
-- kept as the customer accepted it; start a new quote instead.
drop function if exists "better_supabase"."revise_quote"(uuid);
create or replace function "better_supabase"."revise_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = revise_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'draft' then
    raise exception 'a draft is edited, not revised' using errcode = '55000', hint = 'QUOTE_NOT_SENT';
  end if;
  if v_row."status" = 'accepted' then
    raise exception 'an accepted quote stays as accepted; start a new quote' using errcode = '55000', hint = 'QUOTE_ACCEPTED';
  end if;
  if revise_quote.actor is not null then
    if jsonb_typeof(revise_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(revise_quote.actor ->> 'ip', '')::inet, nullif(revise_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(revise_quote.actor::text, ''), true);
  update "better_supabase"."quotes" x set "status" = 'draft', "revision" = x."revision" + 1, "token_hash" = null, "sent_at" = null, "viewed_at" = null,
    "valid_until" = greatest(x."valid_until", current_date + 30),
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "decided_user_id" = null, "decided_ip" = null, "decided_user_agent" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  return ((to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id")) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."revise_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."revise_quote"(uuid, jsonb) to authenticated, service_role;

-- Takes back a sent or expired quote the customer hasn't accepted: it can't
-- be answered any more until it is revised and sent again. The actor and
-- reason go to the state machine's history.
drop function if exists "better_supabase"."withdraw_quote"(uuid, jsonb);
create or replace function "better_supabase"."withdraw_quote"(quote uuid, actor jsonb default null, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = withdraw_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" not in ('sent', 'viewed', 'changes_requested', 'expired') then
    raise exception 'only a sent quote that wasn''t answered is withdrawn' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if withdraw_quote.actor is not null then
    if jsonb_typeof(withdraw_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(withdraw_quote.actor ->> 'ip', '')::inet, nullif(withdraw_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(withdraw_quote.actor::text, ''), true);
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(withdraw_quote.reason), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = 'withdrawn', "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  null;
  return ((to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id")) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."withdraw_quote"(uuid, jsonb, text) to authenticated, service_role;

-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name,
-- and without it or an actor the answer names no one. The note is also the
-- reason in the state machine's history.
-- selected lists the positions of the optional lines they took. actor is
-- the customer when the app takes the answer in its own portal: id, name,
-- email, ip and userAgent, kept with the answer and in the state machine's
-- history; a quote past its valid date then expires instead, and the expired
-- quote is returned.
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text);
drop function if exists "better_supabase"."decide_quote"(uuid, text, text, text, jsonb);
create or replace function "better_supabase"."decide_quote"(quote uuid, decision text, note text, by text, selected jsonb default null, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = decide_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if decide_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.actor is not null then
    if jsonb_typeof(decide_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(decide_quote.actor ->> 'ip', '')::inet, nullif(decide_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(decide_quote.actor::text, ''), true);
  if (decide_quote.actor is not null) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return ((to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id")) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
  end if;
  if decide_quote.decision = 'accepted' then
    if decide_quote.selected is not null then
      if jsonb_typeof(decide_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(decide_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(decide_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  perform set_config('better_supabase.transition_reason', coalesce(nullif(trim(decide_quote.note), ''), ''), true);
  update "better_supabase"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(decide_quote.by), ''), nullif(trim(decide_quote.actor ->> 'name'), ''), decide_quote.actor ->> 'email')), ''),
    "decision_note" = nullif(trim(decide_quote.note), ''), "decided_user_id" = coalesce(nullif(decide_quote.actor ->> 'id', '')::uuid, auth.uid()), "decided_ip" = left(decide_quote.actor ->> 'ip', 64), "decided_user_agent" = left(decide_quote.actor ->> 'userAgent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  perform set_config('better_supabase.transition_reason', '', true);
  case decide_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return ((to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id")) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."decide_quote"(uuid, text, text, text, jsonb, jsonb) to authenticated, service_role;

-- What the customer sees through the link: the quote without internal
-- notes. Opening a sent quote marks it viewed. Callable without signing in.
create or replace function "better_supabase"."public_quote"(token text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(public_quote.token, 'sha256'), 'hex');
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke all on function "better_supabase"."public_quote"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."public_quote"(text) to anon, authenticated, service_role;

-- The customer's answer through the link: accepted, rejected or
-- changes_requested, with their name, a note and the optional lines they
-- took. Their address and browser are kept with the answer. A quote past its
-- valid date expires instead.
drop function if exists "better_supabase"."respond_to_quote"(text, text, text, text);
create or replace function "better_supabase"."respond_to_quote"(token text, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(respond_to_quote.token, 'sha256'), 'hex') for update;
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  if respond_to_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(respond_to_quote.name), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_quote.selected is not null then
      if jsonb_typeof(respond_to_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(respond_to_quote.name), ''),
    "decision_note" = nullif(trim(respond_to_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke all on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."respond_to_quote"(text, text, text, text, jsonb) to anon, authenticated, service_role;

-- A quote shared with the signed-in guest, as the customer sees it: through
-- a grant on the quote or as a guest of its company or contact. Opening a
-- sent quote marks it viewed. No link token is needed. The service role
-- reads it too, for an app's own portal; actor is then the customer who
-- opened it, for the state machine's history.
drop function if exists "better_supabase"."portal_quote"(uuid);
create or replace function "better_supabase"."portal_quote"(quote uuid, actor jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if portal_quote.actor is not null and not (auth.role() = 'service_role') then
    raise exception 'only the service role names who opened a quote' using errcode = '42501', hint = 'QUOTE_ACTOR_FORBIDDEN';
  end if;
  if portal_quote.actor is not null then
    if jsonb_typeof(portal_quote.actor) <> 'object' then
      raise exception 'actor must be an object of id, name, email, ip and userAgent' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end if;
    begin
      perform nullif(portal_quote.actor ->> 'ip', '')::inet, nullif(portal_quote.actor ->> 'id', '')::uuid;
    exception when invalid_text_representation then
      raise exception 'actor.ip must be an IP address and actor.id a user id' using errcode = '22023', hint = 'QUOTE_ACTOR_INVALID';
    end;
  end if;
  perform set_config('better_supabase.transition_actor', coalesce(portal_quote.actor::text, ''), true);
  if portal_quote.actor is null then
    begin
      v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
    exception when invalid_text_representation then
      v_ip := null;
    end;
    perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = portal_quote.quote and (false or ((auth.role() = 'service_role') and x."status" <> 'draft'));
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'pricesIncludeTax', v_row."prices_include_tax",
    'discountBps', v_row."discount_bps", 'discountAmount', v_row."discount_amount"::text,
    'depositBps', v_row."deposit_bps", 'depositAmount', v_row."deposit_amount"::text, 'depositRequired', v_row."deposit_required",
    'depositDue', v_row."deposit_due"::text,
    'listTotal', v_row."list_total"::text, 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text,
    'lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb),
    'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."portal_quote"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."portal_quote"(uuid, jsonb) to authenticated, service_role;

-- The signed-in guest's answer to a quote shared with them, like
-- respond_to_quote without a token. name defaults to their email; the
-- answer keeps who they are, their address and their browser.
create or replace function "better_supabase"."respond_to_portal_quote"(quote uuid, decision text, name text, note text, selected jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_headers jsonb := nullif(current_setting('request.headers', true), '')::jsonb;
  v_ip inet;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = respond_to_portal_quote.quote and false for update;
  if v_row."id" is null then
    raise exception 'no such quote shared with you' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if respond_to_portal_quote.decision not in ('accepted', 'rejected', 'changes_requested') then
    raise exception 'answer accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'this quote no longer takes an answer' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  begin
    v_ip := left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64)::inet;
  exception when invalid_text_representation then
    v_ip := null;
  end;
  perform set_config('better_supabase.transition_actor', jsonb_strip_nulls(jsonb_build_object('name', nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''), 'email', auth.jwt() ->> 'email', 'ip', v_ip::text, 'userAgent', left(v_headers ->> 'user-agent', 512)))::text, true);
  if (true) and v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_portal_quote.decision = 'accepted' then
    if v_row."deposit_required" and v_row."deposit_due" > 0 then
      raise exception 'pay the deposit before accepting; the app records the acceptance once it is paid' using errcode = '55000', hint = 'QUOTE_DEPOSIT_REQUIRED';
    end if;
    if respond_to_portal_quote.selected is not null then
      if jsonb_typeof(respond_to_portal_quote.selected) <> 'array' or exists (
        select 1 from jsonb_array_elements(respond_to_portal_quote.selected) e
        where jsonb_typeof(e.value) not in ('number') or not exists (
          select 1 from "better_supabase"."quote_lines" ql
          where ql."parent_id" = v_row."id" and ql."optional" and ql."position" = (e.value #>> '{}')::numeric
        )
      ) then
        raise exception 'pick optional lines of this quote by position' using errcode = '22023', hint = 'QUOTE_SELECTION_INVALID';
      end if;
      update "better_supabase"."quote_lines" ql set "selected" = ql."position" in (select ((e.value #>> '{}')::numeric)::integer from jsonb_array_elements(respond_to_portal_quote.selected) e)
      where ql."parent_id" = v_row."id" and ql."optional";
    end if;
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_portal_quote.decision, "decided_at" = now(), "decided_by" = nullif(trim(coalesce(nullif(trim(respond_to_portal_quote.name), ''), auth.jwt() ->> 'email')), ''),
    "decision_note" = nullif(trim(respond_to_portal_quote.note), ''), "decided_user_id" = auth.uid(), "decided_ip" = left(nullif(trim(reverse(split_part(reverse(v_headers ->> 'x-forwarded-for'), ',', 1))), ''), 64), "decided_user_agent" = left(v_headers ->> 'user-agent', 512), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  case respond_to_portal_quote.decision
    when 'accepted' then
      null;
    when 'rejected' then
      null;
    else
      null;
  end case;
  if respond_to_portal_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier", 'revision', v_row."revision");
end;
$$;
revoke execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) from public, anon;
grant execute on function "better_supabase"."respond_to_portal_quote"(uuid, text, text, text, jsonb) to authenticated, service_role;

-- The versions of a quote that were sent, oldest first, without their
-- snapshots.
create or replace function "better_supabase"."quote_versions"(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_versions.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('revision', x."revision", 'total', x."total"::text, 'currency', x."currency",
      'publishedAt', x."published_at", 'publishedBy', x."published_by") order by x."revision")
    from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id"), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."quote_versions"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_versions"(uuid) to authenticated, service_role;

-- The quote as it was sent at revision: the snapshot published then.
create or replace function "better_supabase"."quote_version"(quote uuid, revision integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_version "better_supabase"."quote_versions";
begin
  select * into v_row from "better_supabase"."quotes" x where x."id" = quote_version.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.read'), false));
  if v_row."id" is null then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  select * into v_version from "better_supabase"."quote_versions" x where x."quote_id" = v_row."id" and x."revision" = quote_version.revision;
  if v_version."id" is null then
    raise exception 'this quote has no such version' using errcode = 'P0002', hint = 'QUOTE_VERSION_NOT_FOUND';
  end if;
  return v_version."snapshot" || jsonb_build_object('revision', v_version."revision", 'publishedAt', v_version."published_at");
end;
$$;
revoke execute on function "better_supabase"."quote_version"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."quote_version"(uuid, integer) to authenticated, service_role;

-- Expires sent quotes past their valid date. Run it daily from a job.
create or replace function "better_supabase"."expire_quotes"()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_count integer := 0;
begin
  perform set_config('better_supabase.transition_actor', '', true);
  for v_row in
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now()
    where x."status" in ('sent', 'viewed') and x."valid_until" < current_date
    returning *
  loop
    null;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."expire_quotes"() from public, anon, authenticated;
grant execute on function "better_supabase"."expire_quotes"() to service_role;

-- Makes another variant of a quote: a new draft quote with the same pricing,
-- party and lines, grouped under the same root. label names it (A, B, Basic,
-- Premium) and is unique within the group; attrs change the new quote like
-- create_quote's. The first variant gives the quote it came from the label
-- Original when it has none.
create or replace function "better_supabase"."create_quote_variant"(quote uuid, label text, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
  v_root uuid;
  v_label text := nullif(trim(create_quote_variant.label), '');
  v_made jsonb;
  v_id uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_src from "better_supabase"."quotes" x where x."id" = create_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.write'), false));
  if v_src."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_label is null or length(v_label) > 100 then
    raise exception 'a variant needs a label of up to 100 characters' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  v_root := coalesce(v_src."variant_of", v_src."id");
  if exists (select 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) and lower(x."variant_label") = lower(v_label)) then
    raise exception 'another variant of this quote has that label' using errcode = '23505', hint = 'QUOTE_VARIANT_LABEL_TAKEN';
  end if;
  v_made := "better_supabase"."create_quote"(v_src."org_id", jsonb_strip_nulls(jsonb_build_object(
    'title', v_src."title", 'currency', v_src."currency", 'validUntil', v_src."valid_until",
    'company', case when v_src."company_id" is null then null else jsonb_build_object('type', v_src."company_type", 'id', v_src."company_id") end, 'contact', case when v_src."contact_id" is null then null else jsonb_build_object('type', v_src."contact_type", 'id', v_src."contact_id") end, 'terms', v_src."terms", 'note', v_src."note", 'pricesIncludeTax', v_src."prices_include_tax", 'discountBps', v_src."discount_bps", 'discountAmount', v_src."discount_amount"::text, 'depositBps', v_src."deposit_bps", 'depositAmount', v_src."deposit_amount"::text, 'depositRequired', v_src."deposit_required")) || coalesce(create_quote_variant.attrs, '{}'::jsonb), null);
  v_id := (v_made ->> 'id')::uuid;
  insert into "better_supabase"."quote_lines" ("org_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "tax_code_id", "unit_cost", "discount_amount", "cost_source", "location_id", "bin_id", "billing_party", "billing_party_id", "billing_account_id", "position", "section", "optional", "selected", "periods")
  select x."org_id", v_id, x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."tax_code_id", x."unit_cost", x."discount_amount", x."cost_source", x."location_id", x."bin_id", x."billing_party", x."billing_party_id", x."billing_account_id", x."position", x."section", x."optional", x."selected", x."periods" from "better_supabase"."quote_lines" x where x."parent_id" = v_src."id";
  update "better_supabase"."quotes" x set "variant_label" = coalesce(x."variant_label", 'Original')
  where x."id" = v_root;
  update "better_supabase"."quotes" x set "variant_of" = v_root, "variant_label" = v_label, "is_selected" = false
  where x."id" = v_id;
  return (select ((to_jsonb(x) || jsonb_build_object('tenant_id', x."org_id")) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text, 'discount_amount', x."discount_amount"::text, 'deposit_due', x."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = x."id"), '[]'::jsonb)) from "better_supabase"."quotes" x where x."id" = v_id);
end;
$$;
revoke execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote_variant"(uuid, text, jsonb) to authenticated, service_role;

-- The quotes of one group of variants, the root first. isSelected tells which
-- one the customer chose.
create or replace function "better_supabase"."list_quote_variants"(quote uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_src "better_supabase"."quotes";
begin
  select * into v_src from "better_supabase"."quotes" x where x."id" = list_quote_variants.quote;
  if v_src."id" is null or not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', v_src."org_id", 'quotes.read'), false)) then
    raise exception 'no such quote you can read' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = coalesce(v_src."variant_of", v_src."id") or x."variant_of" = coalesce(v_src."variant_of", v_src."id")));
end;
$$;
revoke execute on function "better_supabase"."list_quote_variants"(uuid) from public, anon;
grant execute on function "better_supabase"."list_quote_variants"(uuid) to authenticated, service_role;

-- Selects one variant of a quote and marks the others of its group not
-- selected; only the selected variant becomes an order or an invoice. A
-- withdrawn, rejected or expired variant can't be selected. options.forward
-- is order or invoice to copy the selected variant forward in the same call
-- (the quote must be accepted, as for order_from_quote and invoice_from_quote);
-- options.attrs go to order_from_quote and options.depositBps to
-- invoice_from_quote.
create or replace function "better_supabase"."select_quote_variant"(quote uuid, options jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_root uuid;
  v_forward text := nullif(select_quote_variant.options ->> 'forward', '');
  v_order jsonb;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = select_quote_variant.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."org_id", 'quotes.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  v_root := coalesce(v_row."variant_of", v_row."id");
  if v_row."variant_of" is null and not exists (select 1 from "better_supabase"."quotes" x where x."variant_of" = v_row."id") then
    raise exception 'this quote has no variants' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  if v_row."status" in ('withdrawn', 'rejected', 'expired') then
    raise exception 'a withdrawn, rejected or expired variant can''t be selected' using errcode = '55000', hint = 'QUOTE_VARIANT_NOT_SELECTABLE';
  end if;
  if v_forward is not null and v_forward not in ('') then
    raise exception 'forward is order or invoice' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  perform 1 from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root) for update;
  update "better_supabase"."quotes" x set "is_selected" = (x."id" = v_row."id"), "updated_at" = now()
  where (x."id" = v_root or x."variant_of" = v_root) and x."is_selected" is distinct from (x."id" = v_row."id");
  if v_forward is not null and v_order is null and v_invoice is null then
    raise exception 'the organization has no block to copy the variant forward to' using errcode = '22023', hint = 'QUOTE_VARIANT_INVALID';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  return jsonb_build_object('quote', ((to_jsonb(v_row) || jsonb_build_object('tenant_id', v_row."org_id")) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text, 'discount_amount', v_row."discount_amount"::text, 'deposit_due', v_row."deposit_due"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('position', ql."position", 'description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'section', ql."section", 'optional', ql."optional", 'selected', ql."selected", 'periods', ql."periods", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'taxLines', coalesce((select jsonb_agg(jsonb_build_object('taxRateBps', tl."tax_rate_bps", 'taxCode', tl."tax_code", 'net', tl."net"::text, 'tax', tl."tax"::text, 'gross', tl."gross"::text, 'discount', tl."discount"::text) order by tl."tax_rate_bps", tl."tax_code" nulls first) from "better_supabase"."quote_tax_lines" tl where tl."parent_id" = v_row."id"), '[]'::jsonb)), 'variants', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', x."id", 'identifier', x."identifier", 'variantLabel', x."variant_label",
      'isSelected', x."is_selected", 'status', x."status",
      'currency', x."currency", 'total', x."total"::text, 'isRoot', x."variant_of" is null)
      order by (x."variant_of" is not null), x."number"), '[]'::jsonb)
    from "better_supabase"."quotes" x where (x."id" = v_root or x."variant_of" = v_root)), 'order', v_order, 'invoice', v_invoice);
end;
$$;
revoke execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."select_quote_variant"(uuid, jsonb) to authenticated, service_role;

-- The import target of the quote entity (ADR 0141): item.data is { number,
-- status?, title?, currency, validUntil?, createdAt?, sentAt?, viewedAt?,
-- decidedAt?, decidedBy?, decisionNote?, company?, contact?, origin?,
-- pricesIncludeTax?, attrs?, legalEntityId?, buyer?, lines, taxLines?,
-- totals? }. A quote that is already imported is kept as it is.
create or replace function "better_supabase"."import_quote"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := (import_quote.item ->> 'tenant')::uuid;
  v_data jsonb := import_quote.item -> 'data';
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_made jsonb;
  v_id uuid;
  v_row "better_supabase"."quotes";
  v_warnings jsonb := '[]'::jsonb;
  v_computed jsonb;
  v_given jsonb;
begin
  if import_quote.subject_id is not null then
    select * into v_row from "better_supabase"."quotes" y where y."id" = import_quote.subject_id::uuid and y."org_id" = v_tenant;
    if not found then
      raise exception 'the quote no longer exists' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
    end if;
    return jsonb_build_object('subjectId', v_row."id"::text, 'updatedAt', v_row."updated_at", 'warnings', jsonb_build_array(jsonb_build_object('code', 'IMPORT_DOCUMENT_CHANGED', 'message', 'the source quote changed after it was imported; an imported quote is kept as imported, so import the correction as a new quote')));
  end if;
  if v_number is null then
    raise exception 'a quote needs its number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if coalesce(v_data ->> 'status', 'draft') not in ('draft', 'sent', 'viewed', 'accepted', 'rejected', 'changes_requested', 'expired', 'withdrawn') then
    raise exception 'status is draft, sent, viewed, accepted, rejected, changes_requested, expired or withdrawn' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if jsonb_typeof(v_data -> 'lines') is distinct from 'array' or jsonb_array_length(v_data -> 'lines') = 0 then
    raise exception 'a quote needs at least one line' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  perform set_config('better_supabase.fixed_number', 'quote' || chr(31) || v_number, true);
  v_made := "better_supabase"."create_quote"(v_tenant, coalesce(v_data -> 'attrs', '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'title', coalesce(nullif(v_data ->> 'title', ''), 'Quote ' || v_number),
    'currency', v_data -> 'currency',
    'validUntil', v_data -> 'validUntil',
    'terms', v_data -> 'terms',
    'note', v_data -> 'note',
    'company', v_data -> 'company',
    'contact', v_data -> 'contact',
    'origin', v_data -> 'origin',
    'pricesIncludeTax', v_data -> 'pricesIncludeTax',
    'discountBps', v_data -> 'discountBps',
    'discountAmount', v_data -> 'discountAmount',
    'depositBps', v_data -> 'depositBps',
    'depositAmount', v_data -> 'depositAmount')), v_data -> 'lines');
  perform set_config('better_supabase.fixed_number', '', true);
  v_id := (v_made ->> 'id')::uuid;
  update "better_supabase"."quotes" y set
    "status" = coalesce(v_data ->> 'status', 'draft'),
    "created_at" = coalesce(nullif(v_data ->> 'createdAt', '')::timestamptz, y."created_at"),
    "sent_at" = nullif(v_data ->> 'sentAt', '')::timestamptz,
    "viewed_at" = nullif(v_data ->> 'viewedAt', '')::timestamptz,
    "decided_at" = nullif(v_data ->> 'decidedAt', '')::timestamptz,
    "decided_by" = nullif(v_data ->> 'decidedBy', ''),
    "decision_note" = nullif(v_data ->> 'decisionNote', ''),
    "buyer" = case when jsonb_typeof(v_data -> 'buyer') = 'object' then v_data -> 'buyer' end,
    "updated_at" = now()
  where y."id" = v_id;
  if jsonb_typeof(v_data -> 'taxLines') = 'array' then
    v_computed := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(z."tax_code", '') || ':' || z."tax_rate_bps"::text as key, sum(z."net") as net, sum(z."tax") as tax
        from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id group by 1) k
    ), '{}'::jsonb);
    v_given := coalesce((
      select jsonb_object_agg(k.key, jsonb_build_object('net', k.net, 'tax', k.tax))
      from (select coalesce(g.value ->> 'taxCode', '') || ':' || coalesce((g.value ->> 'taxRateBps')::integer, 0)::text as key,
          sum((g.value ->> 'net')::bigint) as net, sum((g.value ->> 'tax')::bigint) as tax
        from jsonb_array_elements(v_data -> 'taxLines') g group by 1) k
    ), '{}'::jsonb);
    if v_computed <> v_given then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TAX_MISMATCH', 'message', 'the stored tax per code differs from the tax computed from the lines; the stored amounts were kept', 'computed', v_computed, 'given', v_given));
    end if;
    delete from "better_supabase"."quote_tax_lines" z where z."parent_id" = v_id;
    insert into "better_supabase"."quote_tax_lines" ("org_id", "parent_id", "tax_rate_bps", "tax_code", "net", "tax", "gross", "discount")
    select v_tenant, v_id, coalesce((g.value ->> 'taxRateBps')::integer, 0), nullif(g.value ->> 'taxCode', ''), (g.value ->> 'net')::bigint, (g.value ->> 'tax')::bigint,
      coalesce((g.value ->> 'gross')::bigint, (g.value ->> 'net')::bigint + (g.value ->> 'tax')::bigint), coalesce((g.value ->> 'discount')::bigint, 0)
    from jsonb_array_elements(v_data -> 'taxLines') g;
  end if;
  if jsonb_typeof(v_data -> 'totals') = 'object' then
    select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
    if (v_data -> 'totals' ->> 'subtotal' is not null and (v_data -> 'totals' ->> 'subtotal')::bigint <> v_row."subtotal")
      or (v_data -> 'totals' ->> 'tax' is not null and (v_data -> 'totals' ->> 'tax')::bigint <> v_row."tax_total")
      or (v_data -> 'totals' ->> 'total' is not null and (v_data -> 'totals' ->> 'total')::bigint <> v_row."total") then
      v_warnings := v_warnings || jsonb_build_array(jsonb_build_object('code', 'IMPORT_TOTALS_MISMATCH', 'message', 'the stored totals differ from the totals computed from the lines; the stored totals were kept',
        'computed', jsonb_build_object('subtotal', v_row."subtotal"::text, 'tax', v_row."tax_total"::text, 'total', v_row."total"::text),
        'given', v_data -> 'totals'));
    end if;
    update "better_supabase"."quotes" y set
      "subtotal" = coalesce((v_data -> 'totals' ->> 'subtotal')::bigint, y."subtotal"),
      "tax_total" = coalesce((v_data -> 'totals' ->> 'tax')::bigint, y."tax_total"),
      "total" = coalesce((v_data -> 'totals' ->> 'total')::bigint, y."total")
    where y."id" = v_id;
  end if;
  select * into v_row from "better_supabase"."quotes" y where y."id" = v_id;
  return jsonb_build_object('subjectId', v_id::text, 'updatedAt', v_row."updated_at", 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_quote"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_quote"(uuid, jsonb, text) to service_role;

-- When a quote last changed, for the conflict check of imports.
create or replace function "better_supabase"."quote_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select y."updated_at" from "better_supabase"."quotes" y where y."id" = $1::uuid
$$;
revoke execute on function "better_supabase"."quote_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."quote_updated_at"(text) to service_role;

-- Totals and cost of one record's lines per billing party (ADR 0141). It runs
-- as the caller, so only lines the caller can read count.
create or replace function "better_supabase"."quote_totals_by_billing_party"(quote uuid)
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
        'lines', count(*), 'net', sum((round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - (round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0) + least(coalesce(l."discount_amount", 0), greatest(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") - round(round(l."quantity" * coalesce(l."periods", 1) * l."unit_amount") * l."discount_bps" / 10000.0), 0)))))::text, 'cost', sum(round(l."quantity" * l."unit_cost"))::text
      ) as row
    from "better_supabase"."quote_lines" l
    where l."parent_id" = quote and (not l."optional" or l."selected")
    group by 1, 2, 3
  ) g
$$;
revoke execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) from public, anon;
grant execute on function "better_supabase"."quote_totals_by_billing_party"(uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quotes";
create policy bsb_tenant_scope_select on "better_supabase"."quotes" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('quotes.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quotes";
create policy bsb_tenant_scope_insert on "better_supabase"."quotes" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quotes";
create policy bsb_tenant_scope_update on "better_supabase"."quotes" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quotes";
create policy bsb_tenant_scope_delete on "better_supabase"."quotes" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_lines" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_versions";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_select on "better_supabase"."quote_versions" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "quote_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_versions" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_update on "better_supabase"."quote_versions" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_versions";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_versions" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_tax_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_select on "better_supabase"."quote_tax_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" q where q."id" = "parent_id"))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."quote_tax_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_update on "better_supabase"."quote_tax_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."quote_tax_lines" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_097_quotes.sql
-- better-supabase module: quotes
-- @bsb-block-data quotes
-- @bsb-hash sha256:fe87f8a5895a1bef6d16712af52cf95116d938edc0a677538bebf4ee466198f0
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
