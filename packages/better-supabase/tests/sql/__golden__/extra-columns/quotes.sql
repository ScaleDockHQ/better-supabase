-- ==== schema supabase/schemas/900_better_supabase_97_quotes.sql
-- better-supabase module: quotes
-- @bsb-block quotes@2 managed
-- Quotes with line items and totals, a revision chain, a public link the customer accepts, rejects or asks changes through, expiry, and quotes from deals. With catalog, a line that names a product variant takes its price and title.
-- Managed by `better-supabase add`; re-running it overwrites this file.
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
create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Quotes: line items and totals, a revision chain, sending with a public
-- link the customer accepts, rejects or asks changes through, and expiry.

create table if not exists "better_supabase"."quotes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" bigint not null,
  "identifier" text not null,
  "revision" integer not null default 1,
  "supersedes_id" uuid references "better_supabase"."quotes" ("id") on delete set null,
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
create index if not exists quotes_tenant_status_idx on "better_supabase"."quotes" ("tenant_id", "status", "created_at" desc);
create index if not exists quotes_origin_idx on "better_supabase"."quotes" ("origin_type", "origin_id");
create index if not exists quotes_supersedes_idx on "better_supabase"."quotes" ("supersedes_id");
alter table "better_supabase"."quotes" add column if not exists "app_note" text;
alter table "better_supabase"."quotes" enable row level security;
revoke all on "better_supabase"."quotes" from anon, authenticated;
grant select on "better_supabase"."quotes" to authenticated;
grant all on "better_supabase"."quotes" to service_role;
drop policy if exists quotes_read on "better_supabase"."quotes";
create policy quotes_read on "better_supabase"."quotes" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')));

-- Creates a draft quote. attrs: title (required), currency, company and
-- contact ({ type, id }), ownerId, validUntil, terms, note, origin ({ type,
-- id }, the record it was made from). lines: see set_quote_lines.
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
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_quote.tenant::text || ':quote', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from "better_supabase"."quotes" x where x."tenant_id" = create_quote.tenant;
  v_identifier := 'Q-' || v_seq::text;
  begin
    insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "title", "company_type", "company_id", "contact_type", "contact_id",
      "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "created_by")
    values (create_quote.tenant, v_seq, v_identifier, trim(create_quote.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      coalesce((create_quote.attrs ->> 'ownerId')::uuid, auth.uid()), upper(coalesce(create_quote.attrs ->> 'currency', 'EUR')),
      coalesce((create_quote.attrs ->> 'validUntil')::date, current_date + 30),
      create_quote.attrs ->> 'terms', create_quote.attrs ->> 'note',
      create_quote.attrs -> 'origin' ->> 'type', create_quote.attrs -> 'origin' ->> 'id', auth.uid())
    returning * into v_row;
  update "better_supabase"."quotes" x set "app_note" = case when (create_quote.attrs -> 'fields') ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."quotes", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((create_quote.attrs -> 'fields')) e where e.key in ('app_note'))) r
  where x."id" = v_row."id";
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  if create_quote.lines is not null then
    perform "better_supabase"."set_quote_lines"(v_row."id", create_quote.lines);
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_quote"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft quote, or one the customer asked changes on: title,
-- company, contact, currency, ownerId, validUntil, terms, note.
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
      "company_type" = case when update_quote.attrs ? 'company' then case when update_quote.attrs -> 'company' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'company' ->> 'type', 'company') end else x."company_type" end,
      "company_id" = case when update_quote.attrs ? 'company' then update_quote.attrs -> 'company' ->> 'id' else x."company_id" end,
      "contact_type" = case when update_quote.attrs ? 'contact' then case when update_quote.attrs -> 'contact' ->> 'id' is null then null else coalesce(update_quote.attrs -> 'contact' ->> 'type', 'person') end else x."contact_type" end,
      "contact_id" = case when update_quote.attrs ? 'contact' then update_quote.attrs -> 'contact' ->> 'id' else x."contact_id" end,
      "updated_at" = now()
    where x."id" = v_row."id"
    returning * into v_row;
  update "better_supabase"."quotes" x set "app_note" = case when (update_quote.attrs -> 'fields') ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."quotes", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each((update_quote.attrs -> 'fields')) e where e.key in ('app_note'))) r
  where x."id" = v_row."id";
    select * into v_row from "better_supabase"."quotes" x where x."id" = v_row."id";
  exception when check_violation or invalid_text_representation or datetime_field_overflow then
    raise exception 'a quote field has an invalid value' using errcode = '22023', hint = 'QUOTE_ATTRS_INVALID';
  end;
  null;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', v_row."app_note"));
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
  "position" integer not null,
  "created_at" timestamptz not null default now(),
  check (("product_type" is null) = ("product_id" is null))
);
create index if not exists "quote_lines_parent_idx" on "better_supabase"."quote_lines" ("parent_id", "position");
alter table "better_supabase"."quote_lines" enable row level security;
revoke all on "better_supabase"."quote_lines" from anon, authenticated;
grant select on "better_supabase"."quote_lines" to authenticated;
grant all on "better_supabase"."quote_lines" to service_role;
drop policy if exists "quote_lines_read" on "better_supabase"."quote_lines";
create policy "quote_lines_read" on "better_supabase"."quote_lines" for select to authenticated
using (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"));

-- Writes a record's totals from its lines. A record without lines keeps
-- zero totals.
create or replace function "better_supabase"."set_quote_lines_recount"(parent uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_list bigint;
  v_discount bigint;
  v_tax bigint;
begin
  select coalesce(sum(round(l."quantity" * l."unit_amount")), 0), coalesce(sum(round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)), 0), coalesce(sum(round((round(l."quantity" * l."unit_amount") - round(round(l."quantity" * l."unit_amount") * l."discount_bps" / 10000.0)) * l."tax_rate_bps" / 10000.0)), 0)
    into v_list, v_discount, v_tax
  from "better_supabase"."quote_lines" l where l."parent_id" = set_quote_lines_recount.parent;
  update "better_supabase"."quotes" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_list - v_discount,
    "tax_total" = v_tax,
    "total" = v_list - v_discount + v_tax
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
    insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select v_tenant, v_parent, x.value -> 'product' ->> 'type', x.value -> 'product' ->> 'id', x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1), (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0), coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode', x.ordinality::integer
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

-- Sends a quote: it gets a public link the customer opens, and can't
-- change until it is revised. Returns the quote with the link's token,
-- which is stored only as a hash and returned this once.
create or replace function "better_supabase"."send_quote"(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."quotes";
  v_token text := encode(extensions.gen_random_bytes(24), 'hex');
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
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  update "better_supabase"."quotes" x set "status" = 'sent', "sent_at" = now(), "token_hash" = encode(extensions.digest(v_token, 'sha256'), 'hex'),
    "decided_at" = null, "decided_by" = null, "decision_note" = null, "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_quote_send"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', v_row."app_note")) || jsonb_build_object('token', v_token);
end;
$$;
revoke execute on function "better_supabase"."send_quote"(uuid) from public, anon;
grant execute on function "better_supabase"."send_quote"(uuid) to authenticated, service_role;

-- Records the customer's answer taken another way (by phone, by email):
-- decision is accepted, rejected or changes_requested; by is their name.
create or replace function "better_supabase"."decide_quote"(quote uuid, decision text, note text, by text)
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
    raise exception 'decide accepted, rejected or changes_requested' using errcode = '22023', hint = 'QUOTE_DECISION_INVALID';
  end if;
  if v_row."status" not in ('sent', 'viewed') then
    raise exception 'only a sent quote takes a decision' using errcode = '55000', hint = 'QUOTE_NOT_OPEN';
  end if;
  if decide_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = decide_quote.decision, "decided_at" = now(), "decided_by" = coalesce(nullif(trim(decide_quote.by), ''), auth.uid()::text),
    "decision_note" = nullif(trim(decide_quote.note), ''), "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
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
  return (to_jsonb(v_row) - 'token_hash') || jsonb_build_object('number', v_row."number"::text, 'list_total', v_row."list_total"::text, 'discount_total', v_row."discount_total"::text, 'subtotal', v_row."subtotal"::text, 'tax_total', v_row."tax_total"::text, 'total', v_row."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', v_row."app_note"));
end;
$$;
revoke execute on function "better_supabase"."decide_quote"(uuid, text, text, text) from public, anon;
grant execute on function "better_supabase"."decide_quote"(uuid, text, text, text) to authenticated, service_role;

-- A new draft of a sent or decided quote with the same number, the next
-- revision and the same lines. The old one is withdrawn unless accepted.
create or replace function "better_supabase"."revise_quote"(quote uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old "better_supabase"."quotes";
  v_row "better_supabase"."quotes";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_old from "better_supabase"."quotes" x where x."id" = revise_quote.quote and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'quotes.write'), false)) for update;
  if v_old."id" is null then
    raise exception 'no such quote you can edit' using errcode = 'P0002', hint = 'QUOTE_NOT_FOUND';
  end if;
  if v_old."status" = 'draft' then
    raise exception 'a draft is edited, not revised' using errcode = '55000', hint = 'QUOTE_NOT_SENT';
  end if;
  if exists (select 1 from "better_supabase"."quotes" x where x."supersedes_id" = v_old."id") then
    raise exception 'this quote already has a newer revision' using errcode = '55000', hint = 'QUOTE_ALREADY_REVISED';
  end if;
  insert into "better_supabase"."quotes" ("tenant_id", "number", "identifier", "revision", "supersedes_id", "title", "company_type", "company_id",
    "contact_type", "contact_id", "owner_user_id", "currency", "valid_until", "terms", "note", "origin_type", "origin_id", "created_by")
  select x."tenant_id", x."number", x."identifier", x."revision" + 1, x."id", x."title", x."company_type", x."company_id",
    x."contact_type", x."contact_id", x."owner_user_id", x."currency", greatest(x."valid_until", current_date + 30), x."terms", x."note",
    x."origin_type", x."origin_id", auth.uid()
  from "better_supabase"."quotes" x where x."id" = v_old."id"
  returning * into v_row;
  update "better_supabase"."quotes" x set "app_note" = o."app_note"
  from "better_supabase"."quotes" o where o."id" = v_old."id" and x."id" = v_row."id";
  insert into "better_supabase"."quote_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
  select x."tenant_id", v_row."id", x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."position"
  from "better_supabase"."quote_lines" x where x."parent_id" = v_old."id";
  if v_old."status" <> 'accepted' then
    update "better_supabase"."quotes" x set "status" = 'withdrawn', "token_hash" = null, "updated_at" = now() where x."id" = v_old."id";
  end if;
  null;
  return (select (to_jsonb(x) - 'token_hash') || jsonb_build_object('number', x."number"::text, 'list_total', x."list_total"::text, 'discount_total', x."discount_total"::text, 'subtotal', x."subtotal"::text, 'tax_total', x."tax_total"::text, 'total', x."total"::text) || jsonb_build_object('lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = x."id"), '[]'::jsonb), 'fields', jsonb_build_object('app_note', x."app_note")) from "better_supabase"."quotes" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."revise_quote"(uuid) from public, anon;
grant execute on function "better_supabase"."revise_quote"(uuid) to authenticated, service_role;

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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."quotes" x where x."token_hash" = encode(extensions.digest(public_quote.token, 'sha256'), 'hex');
  if v_row."id" is null then
    raise exception 'this link is not valid' using errcode = 'P0002', hint = 'QUOTE_LINK_INVALID';
  end if;
  if v_row."status" = 'sent' then
    update "better_supabase"."quotes" x set "status" = 'viewed', "viewed_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
  end if;
  return jsonb_build_object(
    'identifier', v_row."identifier", 'revision', v_row."revision", 'title', v_row."title",
    'status', v_row."status", 'currency', v_row."currency", 'validUntil', v_row."valid_until",
    'terms', v_row."terms", 'subtotal', v_row."subtotal"::text, 'discountTotal', v_row."discount_total"::text,
    'taxTotal', v_row."tax_total"::text, 'total', v_row."total"::text, 'lines', coalesce((select jsonb_agg(jsonb_build_object('description', ql."description", 'quantity', ql."quantity", 'unitAmount', ql."unit_amount"::text, 'discountBps', ql."discount_bps", 'taxRateBps', ql."tax_rate_bps", 'taxCode', ql."tax_code", 'product', case when ql."product_type" is null then null else jsonb_build_object('type', ql."product_type", 'id', ql."product_id") end) order by ql."position") from "better_supabase"."quote_lines" ql where ql."parent_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke all on function "better_supabase"."public_quote"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."public_quote"(text) to anon, authenticated, service_role;

-- The customer's answer through the link: accepted, rejected or
-- changes_requested, with their name and a note. A quote past its valid
-- date expires instead.
create or replace function "better_supabase"."respond_to_quote"(token text, decision text, name text, note text)
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
  if v_row."valid_until" < current_date then
    update "better_supabase"."quotes" x set "status" = 'expired', "updated_at" = now() where x."id" = v_row."id"
    returning * into v_row;
    null;
    return jsonb_build_object('status', 'expired');
  end if;
  if nullif(trim(respond_to_quote.name), '') is null then
    raise exception 'say who answers' using errcode = '23502', hint = 'QUOTE_NAME_REQUIRED';
  end if;
  if respond_to_quote.decision = 'accepted' then
    declare
    v_hook regprocedure := to_regprocedure('"public"."before_quote_accept"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  end if;
  update "better_supabase"."quotes" x set "status" = respond_to_quote.decision, "decided_at" = now(), "decided_by" = trim(respond_to_quote.name),
    "decision_note" = nullif(trim(respond_to_quote.note), ''), "updated_at" = now()
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
  return jsonb_build_object('status', v_row."status", 'identifier', v_row."identifier");
end;
$$;
revoke all on function "better_supabase"."respond_to_quote"(text, text, text, text) from public, anon, authenticated;
grant execute on function "better_supabase"."respond_to_quote"(text, text, text, text) to anon, authenticated, service_role;

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

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."quotes";
create policy bsb_tenant_scope on "better_supabase"."quotes" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('quotes.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."quote_lines";
create policy bsb_tenant_scope on "better_supabase"."quote_lines" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or (exists (select 1 from "better_supabase"."quotes" x where x."id" = "parent_id"))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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

-- ==== data supabase/better-supabase-data/900_better_supabase_97_quotes.sql
-- better-supabase module: quotes
-- @bsb-block-data quotes
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('quotes', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
