-- ==== schema supabase/schemas/900_better_supabase_98_invoices.sql
-- better-supabase module: invoices
-- @bs-module invoices@1 managed
-- Invoices an organization sends its own customers: drafts with lines, a gapless number on issue, payments, credit notes, void and write-off, overdue and aging per currency, and invoices from accepted quotes.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
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
    when coalesce(auth.jwt() -> 'act' ->> 'read_only', '') = 'false' then true
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' ->> 'read_only', '') <> 'true'
    when auth.jwt() -> 'act' ->> 'kind' in ('support', 'impersonation') then false
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
-- Invoices an organization sends its own customers: drafts with lines, a
-- number on issue, payments, credit notes, void and write-off, and aging.

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
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  "list_total" bigint not null default 0,
  "discount_total" bigint not null default 0,
  "subtotal" bigint not null default 0,
  "tax_total" bigint not null default 0,
  "total" bigint not null default 0,
  unique ("tenant_id", "kind", "number"),
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
alter table "better_supabase"."invoices" enable row level security;
revoke all on "better_supabase"."invoices" from anon, authenticated;
grant select on "better_supabase"."invoices" to authenticated;
grant all on "better_supabase"."invoices" to service_role;
drop policy if exists invoices_read on "better_supabase"."invoices";
create policy invoices_read on "better_supabase"."invoices" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('invoices.read')));

create table if not exists "better_supabase"."invoice_payments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "invoice_id" uuid not null references "better_supabase"."invoices" ("id") on delete cascade,
  "amount" bigint not null check ("amount" <> 0),
  "paid_at" timestamptz not null default now(),
  "method" text,
  "reference" text,
  "recorded_by" uuid,
  "created_at" timestamptz not null default now()
);
create index if not exists invoice_payments_invoice_idx on "better_supabase"."invoice_payments" ("invoice_id", "paid_at");
create unique index if not exists invoice_payments_reference_idx on "better_supabase"."invoice_payments" ("tenant_id", "reference") where "reference" is not null;
alter table "better_supabase"."invoice_payments" enable row level security;
revoke all on "better_supabase"."invoice_payments" from anon, authenticated;
grant select on "better_supabase"."invoice_payments" to authenticated;
grant all on "better_supabase"."invoice_payments" to service_role;
drop policy if exists invoice_payments_read on "better_supabase"."invoice_payments";
create policy invoice_payments_read on "better_supabase"."invoice_payments" for select to authenticated
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
  if not ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', create_invoice.tenant, 'invoices.write'), false)) then
    raise exception 'not allowed to change invoices' using errcode = '42501', hint = 'INVOICE_FORBIDDEN';
  end if;
  if nullif(trim(create_invoice.attrs ->> 'title'), '') is null then
    raise exception 'an invoice needs a title' using errcode = '23502', hint = 'INVOICE_ATTRS_INVALID';
  end if;
  if v_company_id is not null and not false then
    raise exception 'the company is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_COMPANY_FORBIDDEN';
  end if;
  if v_contact_id is not null and not false then
    raise exception 'the contact is unknown or not readable in this organization' using errcode = '42501', hint = 'INVOICE_CONTACT_FORBIDDEN';
  end if;
  begin
    insert into "better_supabase"."invoices" ("tenant_id", "title", "company_type", "company_id", "contact_type", "contact_id", "currency",
      "terms_days", "note", "origin_type", "origin_id", "deposit_bps", "created_by")
    values (create_invoice.tenant, trim(create_invoice.attrs ->> 'title'),
      case when v_company_id is null then null else v_company_type end, v_company_id,
      case when v_contact_id is null then null else v_contact_type end, v_contact_id,
      upper(coalesce(create_invoice.attrs ->> 'currency', 'EUR')), coalesce((create_invoice.attrs ->> 'termsDays')::integer, 30),
      create_invoice.attrs ->> 'note', create_invoice.attrs -> 'origin' ->> 'type', create_invoice.attrs -> 'origin' ->> 'id',
      (create_invoice.attrs ->> 'depositBps')::integer, auth.uid())
    returning * into v_row;
  exception when check_violation or invalid_text_representation then
    raise exception 'an invoice field has an invalid value' using errcode = '22023', hint = 'INVOICE_ATTRS_INVALID';
  end;
  update "better_supabase"."invoices" x set "app_note" = case when create_invoice.attrs ? 'app_note' then r."app_note" else x."app_note" end
  from jsonb_populate_record(null::"better_supabase"."invoices", (select coalesce(jsonb_object_agg(e.key, e.value), '{}') from jsonb_each(create_invoice.attrs) e where e.key in ('app_note'))) r
  where x."id" = v_row."id";
  if create_invoice.lines is not null then
    perform "better_supabase"."set_invoice_lines"(v_row."id", create_invoice.lines);
  end if;
  if v_row."origin_id" is not null then
    
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object(
      'balance', (x."total" - x."credited_total" - x."paid_total")::text,
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', ip."id", 'amount', ip."amount"::text, 'paidAt', ip."paid_at", 'method', ip."method", 'reference', ip."reference") order by ip."paid_at") from "better_supabase"."invoice_payments" ip where ip."invoice_id" = x."id"), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."create_invoice"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_invoice"(uuid, jsonb, jsonb) to authenticated, service_role;
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
revoke all on "better_supabase"."invoice_lines" from anon, authenticated;
grant select on "better_supabase"."invoice_lines" to authenticated;
grant all on "better_supabase"."invoice_lines" to service_role;
drop policy if exists "invoice_lines_read" on "better_supabase"."invoice_lines";
create policy "invoice_lines_read" on "better_supabase"."invoice_lines" for select to authenticated
using (exists (select 1 from "better_supabase"."invoices" x where x."id" = "parent_id"));

-- Writes a record's totals from its lines. A record without lines keeps
-- zero totals.
create or replace function "better_supabase"."set_invoice_lines_recount"(parent uuid)
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
  from "better_supabase"."invoice_lines" l where l."parent_id" = set_invoice_lines_recount.parent;
  update "better_supabase"."invoices" x set
    "list_total" = v_list,
    "discount_total" = v_discount,
    "subtotal" = v_list - v_discount,
    "tax_total" = v_tax,
    "total" = v_list - v_discount + v_tax
  where x."id" = set_invoice_lines_recount.parent;
end;
$$;
revoke execute on function "better_supabase"."set_invoice_lines_recount"(uuid) from public, anon, authenticated;

create or replace function better_supabase.bs_invoice_lines_totals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform "better_supabase"."set_invoice_lines_recount"(coalesce(new."parent_id", old."parent_id"));
  return null;
end;
$$;
drop trigger if exists bs_invoice_lines_totals on "better_supabase"."invoice_lines";
create trigger bs_invoice_lines_totals after insert or update or delete on "better_supabase"."invoice_lines"
for each row execute function better_supabase.bs_invoice_lines_totals();

-- Replaces a record's lines with lines: a list of { description, quantity,
-- unitAmount (minor units, as text or a number), discountBps, taxRateBps,
-- taxCode, product: { type, id } }. Returns the record's totals.
create or replace function "better_supabase"."set_invoice_lines"(parent uuid, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent uuid := set_invoice_lines.parent;
  v_tenant uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."invoices" x where x."id" = v_parent and not (x."status" <> 'draft');
  if v_tenant is null then
    raise exception 'no such record, or its lines are locked' using errcode = 'P0002', hint = 'LINES_RECORD_INVALID';
  end if;
  if not exists (select 1 from "better_supabase"."invoices" x where x."id" = v_parent and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false))) then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if jsonb_typeof(coalesce(set_invoice_lines.lines, '[]')) <> 'array' then
    raise exception 'lines must be a list' using errcode = '22023', hint = 'LINES_INVALID';
  end if;
  delete from "better_supabase"."invoice_lines" l where l."parent_id" = v_parent;
  begin
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select v_tenant, v_parent, x.value -> 'product' ->> 'type', x.value -> 'product' ->> 'id', x.value ->> 'description',
      coalesce((x.value ->> 'quantity')::numeric, 1), (x.value ->> 'unitAmount')::bigint,
      coalesce((x.value ->> 'discountBps')::integer, 0), coalesce((x.value ->> 'taxRateBps')::integer, 0),
      x.value ->> 'taxCode', x.ordinality::integer
    from jsonb_array_elements(coalesce(set_invoice_lines.lines, '[]')) with ordinality x;
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'every line needs a description, a positive quantity and a unit amount' using errcode = '22023', hint = 'LINES_INVALID';
  end;
  perform "better_supabase"."set_invoice_lines_recount"(v_parent);
  return (select jsonb_build_object(
    'listTotal', x."list_total"::text, 'discountTotal', x."discount_total"::text,
    'subtotal', x."subtotal"::text, 'taxTotal', x."tax_total"::text, 'total', x."total"::text)
    from "better_supabase"."invoices" x where x."id" = v_parent);
end;
$$;
revoke execute on function "better_supabase"."set_invoice_lines"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_invoice_lines"(uuid, jsonb) to authenticated, service_role;

-- Issues a draft: it gets the next number of its kind (gapless, so a
-- number is only taken when the invoice is final), its issue and due date,
-- and its lines freeze. A credit note reduces the balance of its original.
create or replace function "better_supabase"."issue_invoice"(invoice uuid, issued_on date)
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
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = issue_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'the invoice was already issued' using errcode = '55000', hint = 'INVOICE_NOT_DRAFT';
  end if;
  if not exists (select 1 from "better_supabase"."invoice_lines" x where x."parent_id" = v_row."id") then
    raise exception 'an invoice needs a line before it is issued' using errcode = '23514', hint = 'INVOICE_EMPTY';
  end if;
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
    if v_row."total" > (v_original."total" - v_original."credited_total" - v_original."paid_total") then
      raise exception 'a credit note can''t exceed what is still owed' using errcode = '23514', hint = 'INVOICE_CREDIT_TOO_LARGE';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':credit_note', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."kind" = 'credit_note') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'CN-' || v_seq::text;
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_row."tenant_id"::text || ':invoice', 0));
  select coalesce(max(x."number"), 0) + 1 into v_seq from (select * from "better_supabase"."invoices" k where k."kind" = 'invoice') x where x."tenant_id" = v_row."tenant_id";
  v_identifier := 'INV-' || v_seq::text;
  end if;
  update "better_supabase"."invoices" x set "status" = 'issued', "number" = v_seq, "identifier" = v_identifier,
    "issued_on" = coalesce(issue_invoice.issued_on, current_date),
    "due_on" = coalesce(issue_invoice.issued_on, current_date) + x."terms_days",
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  null;
  if v_row."kind" = 'credit_note' then
    update "better_supabase"."invoices" x set "credited_total" = x."credited_total" + v_row."total", "updated_at" = now()
    where x."id" = v_original."id"
    returning * into v_original;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce((select sum(y."amount") from "better_supabase"."invoice_payments" y where y."invoice_id" = x."id"), 0),
    "updated_at" = now()
  where x."id" = v_original."id"
  returning * into v_original;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
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
  return to_jsonb(v_row) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', ip."id", 'amount', ip."amount"::text, 'paidAt', ip."paid_at", 'method', ip."method", 'reference', ip."reference") order by ip."paid_at") from "better_supabase"."invoice_payments" ip where ip."invoice_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."issue_invoice"(uuid, date) from public, anon;
grant execute on function "better_supabase"."issue_invoice"(uuid, date) to authenticated, service_role;

-- Records a payment (a negative amount is a refund). A reference, such as
-- a bank or payment provider id, is unique per organization, so recording
-- the same payment twice adds it once.
create or replace function "better_supabase"."record_invoice_payment"(invoice uuid, amount bigint, paid_at timestamptz, method text, reference text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."invoices";
  v_payment uuid;
  v_was text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."invoices" x where x."id" = record_invoice_payment.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."kind" <> 'invoice' or v_row."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice takes payments' using errcode = '55000', hint = 'INVOICE_NOT_PAYABLE';
  end if;
  if coalesce(record_invoice_payment.amount, 0) = 0 then
    raise exception 'a payment has an amount' using errcode = '22023', hint = 'INVOICE_PAYMENT_INVALID';
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
  insert into "better_supabase"."invoice_payments" ("tenant_id", "invoice_id", "amount", "paid_at", "method", "reference", "recorded_by")
  values (v_row."tenant_id", v_row."id", record_invoice_payment.amount, coalesce(record_invoice_payment.paid_at, now()),
    record_invoice_payment.method, nullif(trim(record_invoice_payment.reference), ''), auth.uid())
  on conflict do nothing
  returning "id" into v_payment;
  if v_payment is null then
    return to_jsonb(v_row) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', ip."id", 'amount', ip."amount"::text, 'paidAt', ip."paid_at", 'method', ip."method", 'reference', ip."reference") order by ip."paid_at") from "better_supabase"."invoice_payments" ip where ip."invoice_id" = v_row."id"), '[]'::jsonb));
  end if;
  update "better_supabase"."invoices" x set
    "paid_total" = coalesce((select sum(y."amount") from "better_supabase"."invoice_payments" y where y."invoice_id" = x."id"), 0),
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  update "better_supabase"."invoices" x set
    "status" = case
      when (x."total" - x."credited_total" - x."paid_total") <= 0 then 'paid'
      when x."paid_total" > 0 or x."credited_total" > 0 then 'partially_paid'
      else 'issued' end,
    "paid_at" = case when (x."total" - x."credited_total" - x."paid_total") <= 0 then coalesce(x."paid_at", now()) end
  where x."id" = v_row."id" and x."status" in ('issued', 'partially_paid', 'paid')
  returning * into v_row;
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
  return to_jsonb(v_row) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', ip."id", 'amount', ip."amount"::text, 'paidAt', ip."paid_at", 'method', ip."method", 'reference', ip."reference") order by ip."paid_at") from "better_supabase"."invoice_payments" ip where ip."invoice_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."record_invoice_payment"(uuid, bigint, timestamptz, text, text) from public, anon;
grant execute on function "better_supabase"."record_invoice_payment"(uuid, bigint, timestamptz, text, text) to authenticated, service_role;

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
  select * into v_original from "better_supabase"."invoices" x where x."id" = credit_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.write'), false));
  if v_original."id" is null then
    raise exception 'no such invoice you can edit' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_original."kind" <> 'invoice' or v_original."status" not in ('issued', 'partially_paid', 'paid') then
    raise exception 'only an issued invoice is credited' using errcode = '55000', hint = 'INVOICE_NOT_CREDITABLE';
  end if;
  insert into "better_supabase"."invoices" ("tenant_id", "kind", "original_id", "title", "company_type", "company_id", "contact_type", "contact_id",
    "currency", "terms_days", "note", "created_by")
  values (v_original."tenant_id", 'credit_note', v_original."id", 'Credit for ' || coalesce(v_original."identifier", v_original."title"),
    v_original."company_type", v_original."company_id", v_original."contact_type", v_original."contact_id",
    v_original."currency", 0, nullif(trim(credit_invoice.note), ''), auth.uid())
  returning * into v_row;
  if credit_invoice.lines is null then
    insert into "better_supabase"."invoice_lines" ("tenant_id", "parent_id", "product_type", "product_id", "description", "quantity", "unit_amount", "discount_bps", "tax_rate_bps", "tax_code", "position")
    select x."tenant_id", v_row."id", x."product_type", x."product_id", x."description", x."quantity", x."unit_amount", x."discount_bps", x."tax_rate_bps", x."tax_code", x."position"
    from "better_supabase"."invoice_lines" x where x."parent_id" = v_original."id";
  else
    perform "better_supabase"."set_invoice_lines"(v_row."id", credit_invoice.lines);
  end if;
  null;
  return (select to_jsonb(x) || jsonb_build_object(
      'balance', (x."total" - x."credited_total" - x."paid_total")::text,
      'overdue', x."status" in ('issued', 'partially_paid') and x."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = x."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', ip."id", 'amount', ip."amount"::text, 'paidAt', ip."paid_at", 'method', ip."method", 'reference', ip."reference") order by ip."paid_at") from "better_supabase"."invoice_payments" ip where ip."invoice_id" = x."id"), '[]'::jsonb)) from "better_supabase"."invoices" x where x."id" = v_row."id");
end;
$$;
revoke execute on function "better_supabase"."credit_invoice"(uuid, jsonb, text) from public, anon;
grant execute on function "better_supabase"."credit_invoice"(uuid, jsonb, text) to authenticated, service_role;

-- Voids an invoice without payments: a draft, or an issued one sent in
-- error. Its number stays taken. Needs invoices.manage.
create or replace function "better_supabase"."void_invoice"(invoice uuid, reason text)
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
  select * into v_row from "better_supabase"."invoices" x where x."id" = void_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.manage'), false)) for update;
  if v_row."id" is null then
    raise exception 'no such invoice you can manage' using errcode = 'P0002', hint = 'INVOICE_NOT_FOUND';
  end if;
  if v_row."status" not in ('draft', 'issued') or v_row."paid_total" <> 0 or v_row."credited_total" <> 0 then
    raise exception 'an invoice with payments or credits is credited, not voided' using errcode = '55000', hint = 'INVOICE_NOT_VOIDABLE';
  end if;
  update "better_supabase"."invoices" x set "status" = 'void', "voided_at" = now(),
    "void_reason" = nullif(trim(void_invoice.reason), ''), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  null;
  return to_jsonb(v_row) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', ip."id", 'amount', ip."amount"::text, 'paidAt', ip."paid_at", 'method', ip."method", 'reference', ip."reference") order by ip."paid_at") from "better_supabase"."invoice_payments" ip where ip."invoice_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."void_invoice"(uuid, text) from public, anon;
grant execute on function "better_supabase"."void_invoice"(uuid, text) to authenticated, service_role;

-- Writes an open invoice off as uncollectible. Needs invoices.manage.
create or replace function "better_supabase"."write_off_invoice"(invoice uuid)
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
  update "better_supabase"."invoices" x set "status" = 'uncollectible', "updated_at" = now()
  where x."id" = write_off_invoice.invoice and ((auth.role() = 'service_role') or coalesce(better_supabase.can('tenant', x."tenant_id", 'invoices.manage'), false)) and x."status" in ('issued', 'partially_paid')
  returning * into v_row;
  if v_row."id" is null then
    raise exception 'only an open invoice you can manage is written off' using errcode = '55000', hint = 'INVOICE_NOT_OPEN';
  end if;
  null;
  return to_jsonb(v_row) || jsonb_build_object(
      'balance', (v_row."total" - v_row."credited_total" - v_row."paid_total")::text,
      'overdue', v_row."status" in ('issued', 'partially_paid') and v_row."due_on" < current_date,
      'lines', coalesce((select jsonb_agg(jsonb_build_object('description', il."description", 'quantity', il."quantity", 'unitAmount', il."unit_amount"::text, 'discountBps', il."discount_bps", 'taxRateBps', il."tax_rate_bps", 'taxCode', il."tax_code") order by il."position") from "better_supabase"."invoice_lines" il where il."parent_id" = v_row."id"), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('id', ip."id", 'amount', ip."amount"::text, 'paidAt', ip."paid_at", 'method', ip."method", 'reference', ip."reference") order by ip."paid_at") from "better_supabase"."invoice_payments" ip where ip."invoice_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."write_off_invoice"(uuid) from public, anon;
grant execute on function "better_supabase"."write_off_invoice"(uuid) to authenticated, service_role;

-- What a tenant is owed in one currency on as_of, by days past due:
-- not yet due, 1 to 30, 31 to 60, 61 to 90 and over 90. Amounts are text.
create or replace function "better_supabase"."invoice_aging"(tenant uuid, currency text, as_of date)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with open as (
    select (x."total" - x."credited_total" - x."paid_total") as balance, coalesce(invoice_aging.as_of, current_date) - x."due_on" as late
    from "better_supabase"."invoices" x
    where x."tenant_id" = invoice_aging.tenant and x."currency" = upper(invoice_aging.currency)
      and x."kind" = 'invoice' and x."status" in ('issued', 'partially_paid')
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
revoke execute on function "better_supabase"."invoice_aging"(uuid, text, date) from public, anon;
grant execute on function "better_supabase"."invoice_aging"(uuid, text, date) to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;

-- ==== data supabase/better-supabase-data/900_better_supabase_98_invoices.sql
-- better-supabase module: invoices
-- @bs-module-data invoices
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('invoices', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
