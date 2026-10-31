-- better-supabase module: rfqs
-- @bsb-block rfqs@1 managed
-- @bsb-hash sha256:992d086193516cc17e896389b78a4552f3da85382da23c136bf2019048e3024e
-- Requests for quotation to invited suppliers, their quotes per line, a side by side comparison and an award that marks the winner and can create the purchase order.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."rfqs";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfqs";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfqs";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfqs";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfqs";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."rfq_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfq_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfq_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfq_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfq_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."rfq_suppliers";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfq_suppliers";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfq_suppliers";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfq_suppliers";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfq_suppliers";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."rfq_quotes";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfq_quotes";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfq_quotes";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfq_quotes";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfq_quotes";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."rfq_quote_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfq_quote_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfq_quote_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfq_quote_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfq_quote_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Requests for quotation: lines to price, invited suppliers, their quotes, a
-- comparison and an award that can create the purchase order.

-- A request for quotation sent to suppliers. The number is RFQ-1, RFQ-2 and so
-- on, or the numbering block's format. awarded_quote_id and purchase_order_id
-- are set when the request is awarded.
create table if not exists "better_supabase"."rfqs" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "number" text not null,
  "sequence" bigint not null,
  "title" text not null check (length("title") between 1 and 200),
  "status" text not null default 'draft' check ("status" in ('draft', 'open', 'closed', 'awarded', 'cancelled')),
  "currency" text not null check ("currency" ~ '^[A-Z]{3}$'),
  "due_at" timestamptz,
  "notes" text check ("notes" is null or length("notes") <= 4000),
  "awarded_quote_id" uuid,
  "purchase_order_id" uuid,
  "cancel_reason" text check ("cancel_reason" is null or length("cancel_reason") <= 500),
  "opened_at" timestamptz,
  "closed_at" timestamptz,
  "awarded_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "sequence")
);
create index if not exists "rfqs_status_idx" on "better_supabase"."rfqs" ("tenant_id", "status");
alter table "better_supabase"."rfqs" enable row level security;
revoke all on "better_supabase"."rfqs" from public, anon, authenticated;
grant select on "better_supabase"."rfqs" to authenticated;
grant all on "better_supabase"."rfqs" to service_role;
drop policy if exists rfqs_read on "better_supabase"."rfqs";
create policy rfqs_read on "better_supabase"."rfqs"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')));

-- What is requested: a description, optionally a product variant of the
-- inventory block (needed to award into a purchase order), and a quantity.
create table if not exists "better_supabase"."rfq_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "rfq_id" uuid not null references "better_supabase"."rfqs" ("id") on delete cascade,
  "ordinal" integer not null check ("ordinal" > 0),
  "description" text not null check (length("description") between 1 and 500),
  "variant_id" uuid,
  "quantity" numeric not null check ("quantity" > 0),
  "unit" text check ("unit" is null or length("unit") <= 40),
  unique ("rfq_id", "ordinal")
);
alter table "better_supabase"."rfq_lines" enable row level security;
revoke all on "better_supabase"."rfq_lines" from public, anon, authenticated;
grant select on "better_supabase"."rfq_lines" to authenticated;
grant all on "better_supabase"."rfq_lines" to service_role;
drop policy if exists rfq_lines_read on "better_supabase"."rfq_lines";
create policy rfq_lines_read on "better_supabase"."rfq_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')));

-- A supplier invited to quote. supplier_type and supplier_id name a contacts
-- party (or another config.subjects record without the contacts block).
create table if not exists "better_supabase"."rfq_suppliers" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "rfq_id" uuid not null references "better_supabase"."rfqs" ("id") on delete cascade,
  "supplier_type" text not null check (length("supplier_type") between 1 and 100),
  "supplier_id" text not null check (length("supplier_id") between 1 and 200),
  "status" text not null default 'invited' check ("status" in ('invited', 'declined', 'quoted')),
  "invited_at" timestamptz not null default now(),
  "responded_at" timestamptz,
  unique ("rfq_id", "supplier_type", "supplier_id")
);
alter table "better_supabase"."rfq_suppliers" enable row level security;
revoke all on "better_supabase"."rfq_suppliers" from public, anon, authenticated;
grant select on "better_supabase"."rfq_suppliers" to authenticated;
grant all on "better_supabase"."rfq_suppliers" to service_role;
drop policy if exists rfq_suppliers_read on "better_supabase"."rfq_suppliers";
create policy rfq_suppliers_read on "better_supabase"."rfq_suppliers"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')));

-- A supplier's answer. One quote per invitation; recording again replaces its
-- prices and raises the revision. total_amount is minor units of the request's
-- currency.
create table if not exists "better_supabase"."rfq_quotes" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "rfq_id" uuid not null references "better_supabase"."rfqs" ("id") on delete cascade,
  "invitation_id" uuid not null references "better_supabase"."rfq_suppliers" ("id") on delete cascade,
  "status" text not null default 'submitted' check ("status" in ('submitted', 'withdrawn', 'awarded', 'rejected')),
  "total_amount" bigint not null check ("total_amount" >= 0),
  "lead_time_days" integer check ("lead_time_days" is null or "lead_time_days" >= 0),
  "valid_until" date,
  "notes" text check ("notes" is null or length("notes") <= 4000),
  "revision" integer not null default 1,
  "submitted_by" uuid,
  "submitted_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("rfq_id", "invitation_id")
);
alter table "better_supabase"."rfq_quotes" enable row level security;
revoke all on "better_supabase"."rfq_quotes" from public, anon, authenticated;
grant select on "better_supabase"."rfq_quotes" to authenticated;
grant all on "better_supabase"."rfq_quotes" to service_role;
drop policy if exists rfq_quotes_read on "better_supabase"."rfq_quotes";
create policy rfq_quotes_read on "better_supabase"."rfq_quotes"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')));

-- The unit price of one requested line in a quote, in minor units. A quote
-- need not price every line, but only a complete quote can be awarded.
create table if not exists "better_supabase"."rfq_quote_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "quote_id" uuid not null references "better_supabase"."rfq_quotes" ("id") on delete cascade,
  "line_id" uuid not null references "better_supabase"."rfq_lines" ("id") on delete cascade,
  "unit_amount" bigint not null check ("unit_amount" >= 0),
  "lead_time_days" integer check ("lead_time_days" is null or "lead_time_days" >= 0),
  unique ("quote_id", "line_id")
);
alter table "better_supabase"."rfq_quote_lines" enable row level security;
revoke all on "better_supabase"."rfq_quote_lines" from public, anon, authenticated;
grant select on "better_supabase"."rfq_quote_lines" to authenticated;
grant all on "better_supabase"."rfq_quote_lines" to service_role;
drop policy if exists rfq_quote_lines_read on "better_supabase"."rfq_quote_lines";
create policy rfq_quote_lines_read on "better_supabase"."rfq_quote_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')));


-- Creates a draft request for quotation and numbers it (RFQ-1, or the
-- numbering block's format for rfq). input is { title, currency, dueAt, notes };
-- currency is an ISO 4217 code. lines is [{ description, variantId, quantity,
-- unit }]; a variantId (inventory) is only needed to award into a purchase
-- order. Needs rfqs.write.
create or replace function "better_supabase"."create_rfq"(tenant uuid, input jsonb, lines jsonb default '[]')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
  v_seq bigint;
  v_number text;
  v_input jsonb := coalesce(create_rfq.input, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (create_rfq.tenant is not null and coalesce(better_supabase.can('tenant', create_rfq.tenant, 'rfqs.write'), false))) then
    raise exception 'not allowed to create requests for quotation' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_rfq_create"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using create_rfq.tenant, create_rfq.input;
    end if;
  end;
  if (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'rfq' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end) is not null then
    v_number := (case when split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 1) = 'rfq' then nullif(split_part(coalesce(current_setting('better_supabase.fixed_number', true), ''), chr(31), 2), '') end);
    if better_supabase.import_run() is null then
      raise exception 'a fixed number is only accepted during an import' using errcode = '42501', hint = 'NUMBER_FIXED_FORBIDDEN';
    end if;
    v_seq := coalesce(substring(v_number from '([0-9]+)$')::bigint, 0);
    perform set_config('better_supabase.fixed_number', '', true);
  else
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(create_rfq.tenant::text || ':rfq', 0));
  select coalesce(max(x."sequence"), 0) + 1 into v_seq from "better_supabase"."rfqs" x where x."tenant_id" = create_rfq.tenant;
  v_number := 'RFQ-' || v_seq::text;
  end if;
  begin
    insert into "better_supabase"."rfqs" ("tenant_id", "number", "sequence", "title", "currency", "due_at", "notes", "created_by")
    values (create_rfq.tenant, v_number, v_seq, trim(v_input ->> 'title'), upper(trim(v_input ->> 'currency')),
      (v_input ->> 'dueAt')::timestamptz, nullif(trim(v_input ->> 'notes'), ''), auth.uid())
    returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a request needs a title of 1 to 200 characters, a three letter currency, a valid dueAt and notes of up to 4000' using errcode = '22023', hint = 'RFQ_INVALID';
  end;
  if jsonb_typeof(create_rfq.lines) is distinct from 'array'
    or exists (select 1 from jsonb_array_elements(create_rfq.lines) e where jsonb_typeof(e) is distinct from 'object') then
    raise exception 'create_rfq: lines must be a list of objects' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  begin
    insert into "better_supabase"."rfq_lines" ("tenant_id", "rfq_id", "ordinal", "description", "variant_id", "quantity", "unit")
    select create_rfq.tenant, v_row."id", t.ord::integer, trim(t.e ->> 'description'), (t.e ->> 'variantId')::uuid,
      (t.e ->> 'quantity')::numeric, nullif(trim(t.e ->> 'unit'), '')
    from jsonb_array_elements(create_rfq.lines) with ordinality as t(e, ord);
  exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
    raise exception 'a line needs a description of 1 to 500 characters, a quantity above zero and, when given, a variantId that is a uuid' using errcode = '22023', hint = 'RFQ_INVALID';
  end;
  perform "better_supabase".emit_event('rfq.created', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id"), 'rfqs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/rfqs');
  perform better_supabase.audit_event(
    event_type => 'rfq.created',
    category => 'data',
    target_type => 'rfq',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'request for quotation created',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_rfq_create"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'currency', v_row."currency", 'dueAt', v_row."due_at", 'notes', v_row."notes", 'awardedQuoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id", 'cancelReason', v_row."cancel_reason", 'openedAt', v_row."opened_at", 'closedAt', v_row."closed_at", 'awardedAt', v_row."awarded_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'lines', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'rfqId', y."rfq_id", 'ordinal', y."ordinal", 'description', y."description", 'variantId', y."variant_id", 'quantity', y."quantity", 'unit', y."unit") order by y."ordinal") from "better_supabase"."rfq_lines" y where y."rfq_id" = v_row."id"), '[]'::jsonb),
    'suppliers', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'rfqId', y."rfq_id", 'supplierType', y."supplier_type", 'supplierId', y."supplier_id", 'status', y."status", 'invitedAt', y."invited_at", 'respondedAt', y."responded_at") order by y."invited_at", y."id") from "better_supabase"."rfq_suppliers" y where y."rfq_id" = v_row."id"), '[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'rfqId', y."rfq_id", 'invitationId', y."invitation_id", 'status', y."status", 'currency', (select x."currency" from "better_supabase"."rfqs" x where x."id" = y."rfq_id"), 'total', y."total_amount"::text, 'leadTimeDays', y."lead_time_days", 'validUntil', y."valid_until", 'notes', y."notes", 'revision', y."revision", 'submittedBy', y."submitted_by", 'submittedAt', y."submitted_at", 'updatedAt', y."updated_at") || jsonb_build_object('lines', coalesce((
        select jsonb_agg(jsonb_build_object('id', z."id", 'quoteId', z."quote_id", 'lineId', z."line_id", 'unitAmount', z."unit_amount"::text, 'leadTimeDays', z."lead_time_days") order by z."id") from "better_supabase"."rfq_quote_lines" z where z."quote_id" = y."id"
      ), '[]'::jsonb)) order by y."submitted_at", y."id") from "better_supabase"."rfq_quotes" y where y."rfq_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."create_rfq"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."create_rfq"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Changes a draft: input is the same object as create_rfq (omitted keys stay),
-- lines replaces every line when given. Needs rfqs.write.
create or replace function "better_supabase"."update_rfq"(rfq_id uuid, input jsonb, lines jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
  v_input jsonb := coalesce(update_rfq.input, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rfqs" x where x."id" = update_rfq.rfq_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such request for quotation' using errcode = 'P0002', hint = 'RFQ_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.write'), false))) then
    raise exception 'not allowed to change requests for quotation' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft request can change' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  begin
    update "better_supabase"."rfqs" x set
      "title" = coalesce(trim(v_input ->> 'title'), x."title"),
      "currency" = coalesce(upper(trim(v_input ->> 'currency')), x."currency"),
      "due_at" = case when v_input ? 'dueAt' then (v_input ->> 'dueAt')::timestamptz else x."due_at" end,
      "notes" = case when v_input ? 'notes' then nullif(trim(v_input ->> 'notes'), '') else x."notes" end,
      "updated_at" = now()
    where x."id" = v_row."id" returning * into v_row;
  exception when check_violation or not_null_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'a request needs a title of 1 to 200 characters, a three letter currency, a valid dueAt and notes of up to 4000' using errcode = '22023', hint = 'RFQ_INVALID';
  end;
  if update_rfq.lines is not null then
    if jsonb_typeof(update_rfq.lines) is distinct from 'array'
    or exists (select 1 from jsonb_array_elements(update_rfq.lines) e where jsonb_typeof(e) is distinct from 'object') then
    raise exception 'update_rfq: lines must be a list of objects' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
    delete from "better_supabase"."rfq_lines" y where y."rfq_id" = v_row."id";
    begin
      insert into "better_supabase"."rfq_lines" ("tenant_id", "rfq_id", "ordinal", "description", "variant_id", "quantity", "unit")
    select v_row."tenant_id", v_row."id", t.ord::integer, trim(t.e ->> 'description'), (t.e ->> 'variantId')::uuid,
      (t.e ->> 'quantity')::numeric, nullif(trim(t.e ->> 'unit'), '')
    from jsonb_array_elements(update_rfq.lines) with ordinality as t(e, ord);
    exception when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range then
      raise exception 'a line needs a description of 1 to 500 characters, a quantity above zero and, when given, a variantId that is a uuid' using errcode = '22023', hint = 'RFQ_INVALID';
    end;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'currency', v_row."currency", 'dueAt', v_row."due_at", 'notes', v_row."notes", 'awardedQuoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id", 'cancelReason', v_row."cancel_reason", 'openedAt', v_row."opened_at", 'closedAt', v_row."closed_at", 'awardedAt', v_row."awarded_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'lines', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'rfqId', y."rfq_id", 'ordinal', y."ordinal", 'description', y."description", 'variantId', y."variant_id", 'quantity', y."quantity", 'unit', y."unit") order by y."ordinal") from "better_supabase"."rfq_lines" y where y."rfq_id" = v_row."id"), '[]'::jsonb),
    'suppliers', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'rfqId', y."rfq_id", 'supplierType', y."supplier_type", 'supplierId', y."supplier_id", 'status', y."status", 'invitedAt', y."invited_at", 'respondedAt', y."responded_at") order by y."invited_at", y."id") from "better_supabase"."rfq_suppliers" y where y."rfq_id" = v_row."id"), '[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'rfqId', y."rfq_id", 'invitationId', y."invitation_id", 'status', y."status", 'currency', (select x."currency" from "better_supabase"."rfqs" x where x."id" = y."rfq_id"), 'total', y."total_amount"::text, 'leadTimeDays', y."lead_time_days", 'validUntil', y."valid_until", 'notes', y."notes", 'revision', y."revision", 'submittedBy', y."submitted_by", 'submittedAt', y."submitted_at", 'updatedAt', y."updated_at") || jsonb_build_object('lines', coalesce((
        select jsonb_agg(jsonb_build_object('id', z."id", 'quoteId', z."quote_id", 'lineId', z."line_id", 'unitAmount', z."unit_amount"::text, 'leadTimeDays', z."lead_time_days") order by z."id") from "better_supabase"."rfq_quote_lines" z where z."quote_id" = y."id"
      ), '[]'::jsonb)) order by y."submitted_at", y."id") from "better_supabase"."rfq_quotes" y where y."rfq_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."update_rfq"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."update_rfq"(uuid, jsonb, jsonb) to authenticated, service_role;

-- One request with its lines, invited suppliers and quotes (each with its
-- prices).
create or replace function "better_supabase"."get_rfq"(rfq_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
begin
  select * into v_row from "better_supabase"."rfqs" x where x."id" = get_rfq.rfq_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such request for quotation' using errcode = 'P0002', hint = 'RFQ_NOT_FOUND';
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'currency', v_row."currency", 'dueAt', v_row."due_at", 'notes', v_row."notes", 'awardedQuoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id", 'cancelReason', v_row."cancel_reason", 'openedAt', v_row."opened_at", 'closedAt', v_row."closed_at", 'awardedAt', v_row."awarded_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at") || jsonb_build_object(
    'lines', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'rfqId', y."rfq_id", 'ordinal', y."ordinal", 'description', y."description", 'variantId', y."variant_id", 'quantity', y."quantity", 'unit', y."unit") order by y."ordinal") from "better_supabase"."rfq_lines" y where y."rfq_id" = v_row."id"), '[]'::jsonb),
    'suppliers', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'rfqId', y."rfq_id", 'supplierType', y."supplier_type", 'supplierId', y."supplier_id", 'status', y."status", 'invitedAt', y."invited_at", 'respondedAt', y."responded_at") order by y."invited_at", y."id") from "better_supabase"."rfq_suppliers" y where y."rfq_id" = v_row."id"), '[]'::jsonb),
    'quotes', coalesce((select jsonb_agg(jsonb_build_object('id', y."id", 'rfqId', y."rfq_id", 'invitationId', y."invitation_id", 'status', y."status", 'currency', (select x."currency" from "better_supabase"."rfqs" x where x."id" = y."rfq_id"), 'total', y."total_amount"::text, 'leadTimeDays', y."lead_time_days", 'validUntil', y."valid_until", 'notes', y."notes", 'revision', y."revision", 'submittedBy', y."submitted_by", 'submittedAt', y."submitted_at", 'updatedAt', y."updated_at") || jsonb_build_object('lines', coalesce((
        select jsonb_agg(jsonb_build_object('id', z."id", 'quoteId', z."quote_id", 'lineId', z."line_id", 'unitAmount', z."unit_amount"::text, 'leadTimeDays', z."lead_time_days") order by z."id") from "better_supabase"."rfq_quote_lines" z where z."quote_id" = y."id"
      ), '[]'::jsonb)) order by y."submitted_at", y."id") from "better_supabase"."rfq_quotes" y where y."rfq_id" = v_row."id"), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_rfq"(uuid) from public, anon;
grant execute on function "better_supabase"."get_rfq"(uuid) to authenticated, service_role;

-- Requests, newest first. filters is { status, limit, offset }.
create or replace function "better_supabase"."list_rfqs"(tenant uuid, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_rfqs.filters, '{}'::jsonb);
  v_limit integer := least(greatest(coalesce((v_filters ->> 'limit')::integer, 50), 1), 200);
begin
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (list_rfqs.tenant is not null and coalesce(better_supabase.can('tenant', list_rfqs.tenant, 'rfqs.read'), false))) then
    raise exception 'not allowed to read requests for quotation' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'number', y."number", 'title', y."title", 'status', y."status", 'currency', y."currency", 'dueAt', y."due_at", 'notes', y."notes", 'awardedQuoteId', y."awarded_quote_id", 'purchaseOrderId', y."purchase_order_id", 'cancelReason', y."cancel_reason", 'openedAt', y."opened_at", 'closedAt', y."closed_at", 'awardedAt', y."awarded_at", 'createdBy', y."created_by", 'createdAt', y."created_at", 'updatedAt', y."updated_at") order by y."sequence" desc)
    from (
      select * from "better_supabase"."rfqs" x
      where x."tenant_id" = list_rfqs.tenant
        and (not v_filters ? 'status' or x."status" = v_filters ->> 'status')
      order by x."sequence" desc
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_rfqs"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_rfqs"(uuid, jsonb) to authenticated, service_role;

-- Invites a supplier to quote on a draft or open request. With the contacts
-- block the supplier must be a company or person that holds the supplier role
-- and is not blocked. Needs rfqs.write.
create or replace function "better_supabase"."invite_rfq_supplier"(rfq_id uuid, supplier_type text, supplier_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
  v_invitation "better_supabase"."rfq_suppliers";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rfqs" x where x."id" = invite_rfq_supplier.rfq_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such request for quotation' using errcode = 'P0002', hint = 'RFQ_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.write'), false))) then
    raise exception 'not allowed to invite suppliers' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if v_row."status" not in ('draft', 'open') then
    raise exception 'suppliers can only be invited while the request is a draft or open' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  if coalesce(trim(invite_rfq_supplier.supplier_type), '') = '' or coalesce(trim(invite_rfq_supplier.supplier_id), '') = '' then
    raise exception 'a supplier needs a type and an id' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  if not exists (select 1 from (select p."roles", p."supplier_status" from "better_supabase"."companies" p where p."id"::text = invite_rfq_supplier.supplier_id and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null union all select p."roles", p."supplier_status" from "better_supabase"."people" p where p."id"::text = invite_rfq_supplier.supplier_id and p."tenant_id" = v_row."tenant_id" and p."merged_into" is null) s(roles, status) where (s.roles is null or cardinality(s.roles) = 0 or 'supplier' = any(s.roles)) and s.status is distinct from 'blocked') then
    raise exception 'the supplier is not an active supplier in contacts' using errcode = '22023', hint = 'RFQ_SUPPLIER_INVALID';
  end if;
  begin
    insert into "better_supabase"."rfq_suppliers" ("tenant_id", "rfq_id", "supplier_type", "supplier_id")
    values (v_row."tenant_id", v_row."id", trim(invite_rfq_supplier.supplier_type), trim(invite_rfq_supplier.supplier_id))
    returning * into v_invitation;
  exception when unique_violation then
    raise exception 'this supplier is already invited' using errcode = '22023', hint = 'RFQ_INVALID';
  when check_violation then
    raise exception 'a supplier needs a type of up to 100 and an id of up to 200 characters' using errcode = '22023', hint = 'RFQ_INVALID';
  end;
  return jsonb_build_object('id', v_invitation."id", 'rfqId', v_invitation."rfq_id", 'supplierType', v_invitation."supplier_type", 'supplierId', v_invitation."supplier_id", 'status', v_invitation."status", 'invitedAt', v_invitation."invited_at", 'respondedAt', v_invitation."responded_at");
end;
$$;
revoke execute on function "better_supabase"."invite_rfq_supplier"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."invite_rfq_supplier"(uuid, text, text) to authenticated, service_role;

-- Records that an invited supplier will not quote. Needs rfqs.write.
create or replace function "better_supabase"."decline_rfq_supplier"(invitation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_invitation "better_supabase"."rfq_suppliers";
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_invitation from "better_supabase"."rfq_suppliers" x where x."id" = decline_rfq_supplier.invitation_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_invitation."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_invitation."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such invited supplier' using errcode = 'P0002', hint = 'RFQ_SUPPLIER_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_invitation."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_invitation."tenant_id", 'rfqs.write'), false))) then
    raise exception 'not allowed to change invited suppliers' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  select r."status" into v_status from "better_supabase"."rfqs" r where r."id" = v_invitation."rfq_id";
  if v_status not in ('draft', 'open') then
    raise exception 'a supplier can only decline while the request is a draft or open' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  if v_invitation."status" <> 'invited' then
    raise exception 'only a supplier that has not quoted can decline' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  update "better_supabase"."rfq_suppliers" x set "status" = 'declined', "responded_at" = now()
  where x."id" = v_invitation."id" returning * into v_invitation;
  return jsonb_build_object('id', v_invitation."id", 'rfqId', v_invitation."rfq_id", 'supplierType', v_invitation."supplier_type", 'supplierId', v_invitation."supplier_id", 'status', v_invitation."status", 'invitedAt', v_invitation."invited_at", 'respondedAt', v_invitation."responded_at");
end;
$$;
revoke execute on function "better_supabase"."decline_rfq_supplier"(uuid) from public, anon;
grant execute on function "better_supabase"."decline_rfq_supplier"(uuid) to authenticated, service_role;

-- Opens a draft for quotes. It needs at least one line and one invited
-- supplier. Needs rfqs.write.
create or replace function "better_supabase"."open_rfq"(rfq_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rfqs" x where x."id" = open_rfq.rfq_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such request for quotation' using errcode = 'P0002', hint = 'RFQ_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.write'), false))) then
    raise exception 'not allowed to open requests for quotation' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if v_row."status" <> 'draft' then
    raise exception 'only a draft request can be opened' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  if not exists (select 1 from "better_supabase"."rfq_lines" y where y."rfq_id" = v_row."id")
    or not exists (select 1 from "better_supabase"."rfq_suppliers" y where y."rfq_id" = v_row."id") then
    raise exception 'a request needs a line and an invited supplier before it opens' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  update "better_supabase"."rfqs" x set "status" = 'open', "opened_at" = now(), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('rfq.opened', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id"), 'rfqs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/rfqs');
  perform better_supabase.audit_event(
    event_type => 'rfq.opened',
    category => 'data',
    target_type => 'rfq',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'request for quotation opened',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'currency', v_row."currency", 'dueAt', v_row."due_at", 'notes', v_row."notes", 'awardedQuoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id", 'cancelReason', v_row."cancel_reason", 'openedAt', v_row."opened_at", 'closedAt', v_row."closed_at", 'awardedAt', v_row."awarded_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."open_rfq"(uuid) from public, anon;
grant execute on function "better_supabase"."open_rfq"(uuid) to authenticated, service_role;

-- Stops taking quotes on an open request so the quotes can be compared and
-- one awarded. Needs rfqs.write.
create or replace function "better_supabase"."close_rfq"(rfq_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rfqs" x where x."id" = close_rfq.rfq_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such request for quotation' using errcode = 'P0002', hint = 'RFQ_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.write'), false))) then
    raise exception 'not allowed to close requests for quotation' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'only an open request can be closed' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  update "better_supabase"."rfqs" x set "status" = 'closed', "closed_at" = now(), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('rfq.closed', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id"), 'rfqs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/rfqs');
  perform better_supabase.audit_event(
    event_type => 'rfq.closed',
    category => 'data',
    target_type => 'rfq',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'request for quotation closed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'currency', v_row."currency", 'dueAt', v_row."due_at", 'notes', v_row."notes", 'awardedQuoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id", 'cancelReason', v_row."cancel_reason", 'openedAt', v_row."opened_at", 'closedAt', v_row."closed_at", 'awardedAt', v_row."awarded_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."close_rfq"(uuid) from public, anon;
grant execute on function "better_supabase"."close_rfq"(uuid) to authenticated, service_role;

-- Cancels a request that is not awarded and says why. Needs rfqs.manage.
create or replace function "better_supabase"."cancel_rfq"(rfq_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rfqs" x where x."id" = cancel_rfq.rfq_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such request for quotation' using errcode = 'P0002', hint = 'RFQ_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.manage'), false))) then
    raise exception 'not allowed to cancel requests for quotation' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if v_row."status" in ('awarded', 'cancelled') then
    raise exception 'an awarded or cancelled request cannot be cancelled' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  if coalesce(trim(cancel_rfq.reason), '') = '' or length(cancel_rfq.reason) > 500 then
    raise exception 'a reason of 1 to 500 characters is required' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  update "better_supabase"."rfqs" x set "status" = 'cancelled', "cancel_reason" = trim(cancel_rfq.reason), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('rfq.cancelled', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id"), 'rfqs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/rfqs');
  perform better_supabase.audit_event(
    event_type => 'rfq.cancelled',
    category => 'data',
    target_type => 'rfq',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'request for quotation cancelled',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'currency', v_row."currency", 'dueAt', v_row."due_at", 'notes', v_row."notes", 'awardedQuoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id", 'cancelReason', v_row."cancel_reason", 'openedAt', v_row."opened_at", 'closedAt', v_row."closed_at", 'awardedAt', v_row."awarded_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."cancel_rfq"(uuid, text) from public, anon;
grant execute on function "better_supabase"."cancel_rfq"(uuid, text) to authenticated, service_role;


-- Records a supplier's quote, or replaces its earlier one (the revision goes
-- up). input is { leadTimeDays, validUntil, notes }; lines is [{ lineId,
-- unitAmount, leadTimeDays }] with unitAmount in minor units of the request's
-- currency. The request must be open and the supplier invited. The total is
-- the sum of unit amount times quantity. Needs rfqs.write.
create or replace function "better_supabase"."record_rfq_quote"(rfq_id uuid, invitation_id uuid, input jsonb, lines jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
  v_invitation "better_supabase"."rfq_suppliers";
  v_quote "better_supabase"."rfq_quotes";
  v_input jsonb := coalesce(record_rfq_quote.input, '{}'::jsonb);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rfqs" x where x."id" = record_rfq_quote.rfq_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such request for quotation' using errcode = 'P0002', hint = 'RFQ_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.write'), false))) then
    raise exception 'not allowed to record quotes' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if v_row."status" <> 'open' then
    raise exception 'quotes can only be recorded on an open request' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  select * into v_invitation from "better_supabase"."rfq_suppliers" y
  where y."id" = record_rfq_quote.invitation_id and y."rfq_id" = v_row."id" for update;
  if not found then
    raise exception 'no such invited supplier' using errcode = 'P0002', hint = 'RFQ_SUPPLIER_NOT_FOUND';
  end if;
  if v_invitation."status" = 'declined' then
    raise exception 'this supplier declined to quote' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  if jsonb_typeof(v_input) is distinct from 'object' then
    raise exception 'input must be an object' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  if jsonb_typeof(record_rfq_quote.lines) is distinct from 'array' or jsonb_array_length(record_rfq_quote.lines) = 0
    or exists (
      select 1 from jsonb_array_elements(record_rfq_quote.lines) e
      where jsonb_typeof(e) is distinct from 'object'
        or coalesce(e ->> 'lineId', '') !~ '^[0-9a-fA-F-]{36}$'
        or coalesce(e ->> 'unitAmount', '') !~ '^[0-9]{1,18}$'
    )
    or (select count(distinct e ->> 'lineId') from jsonb_array_elements(record_rfq_quote.lines) e) <> jsonb_array_length(record_rfq_quote.lines) then
    raise exception 'lines must be a non-empty list with a unique lineId and a unitAmount in minor units each' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  if exists (
    select 1 from jsonb_array_elements(record_rfq_quote.lines) e
    where not exists (select 1 from "better_supabase"."rfq_lines" y where y."id" = (e ->> 'lineId')::uuid and y."rfq_id" = v_row."id")
  ) then
    raise exception 'a lineId is not a line of this request' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_rfq_quote_record"(uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::jsonb)', v_hook::oid::regproc)
        using record_rfq_quote.rfq_id, record_rfq_quote.input;
    end if;
  end;
  begin
    select * into v_quote from "better_supabase"."rfq_quotes" y
    where y."rfq_id" = v_row."id" and y."invitation_id" = v_invitation."id" for update;
    if found then
      delete from "better_supabase"."rfq_quote_lines" z where z."quote_id" = v_quote."id";
      update "better_supabase"."rfq_quotes" y set "status" = 'submitted', "total_amount" = 0,
        "lead_time_days" = (v_input ->> 'leadTimeDays')::integer, "valid_until" = (v_input ->> 'validUntil')::date,
        "notes" = nullif(trim(v_input ->> 'notes'), ''), "revision" = y."revision" + 1,
        "submitted_by" = auth.uid(), "submitted_at" = now(), "updated_at" = now()
      where y."id" = v_quote."id" returning * into v_quote;
    else
      insert into "better_supabase"."rfq_quotes" ("tenant_id", "rfq_id", "invitation_id", "total_amount", "lead_time_days", "valid_until", "notes", "submitted_by")
      values (v_row."tenant_id", v_row."id", v_invitation."id", 0, (v_input ->> 'leadTimeDays')::integer,
        (v_input ->> 'validUntil')::date, nullif(trim(v_input ->> 'notes'), ''), auth.uid())
      returning * into v_quote;
    end if;
    insert into "better_supabase"."rfq_quote_lines" ("tenant_id", "quote_id", "line_id", "unit_amount", "lead_time_days")
    select v_row."tenant_id", v_quote."id", (e ->> 'lineId')::uuid, (e ->> 'unitAmount')::bigint, (e ->> 'leadTimeDays')::integer
    from jsonb_array_elements(record_rfq_quote.lines) e;
    update "better_supabase"."rfq_quotes" y set "total_amount" = coalesce((
      select round(sum(z."unit_amount" * ln."quantity"))::bigint
      from "better_supabase"."rfq_quote_lines" z join "better_supabase"."rfq_lines" ln on ln."id" = z."line_id" where z."quote_id" = y."id"
    ), 0)
    where y."id" = v_quote."id" returning * into v_quote;
  exception when check_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then
    raise exception 'a quote needs a leadTimeDays of zero or more, a valid validUntil, notes of up to 4000 and unit amounts in minor units' using errcode = '22023', hint = 'RFQ_INVALID';
  end;
  update "better_supabase"."rfq_suppliers" y set "status" = 'quoted', "responded_at" = now() where y."id" = v_invitation."id";
  perform "better_supabase".emit_event('rfq_quote.submitted', jsonb_build_object('organizationId', v_quote."tenant_id", 'id', v_quote."id", 'rfqId', v_quote."rfq_id", 'invitationId', v_quote."invitation_id", 'total', v_quote."total_amount"::text), 'rfqs/' || v_quote."rfq_id"::text, (v_quote."tenant_id")::text, null, 'better-supabase/rfqs');
  perform better_supabase.audit_event(
    event_type => 'rfq_quote.submitted',
    category => 'data',
    target_type => 'rfq',
    record_id => v_quote."rfq_id"::text,
    target_label => v_row."number",
    summary => 'quote recorded',
    tenant => (v_quote."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_quote."tenant_id", 'id', v_quote."id", 'rfqId', v_quote."rfq_id", 'invitationId', v_quote."invitation_id", 'total', v_quote."total_amount"::text)
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_rfq_quote_record"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_quote."id";
    end if;
  end;
  return jsonb_build_object('id', v_quote."id", 'rfqId', v_quote."rfq_id", 'invitationId', v_quote."invitation_id", 'status', v_quote."status", 'currency', (select x."currency" from "better_supabase"."rfqs" x where x."id" = v_quote."rfq_id"), 'total', v_quote."total_amount"::text, 'leadTimeDays', v_quote."lead_time_days", 'validUntil', v_quote."valid_until", 'notes', v_quote."notes", 'revision', v_quote."revision", 'submittedBy', v_quote."submitted_by", 'submittedAt', v_quote."submitted_at", 'updatedAt', v_quote."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'quoteId', z."quote_id", 'lineId', z."line_id", 'unitAmount', z."unit_amount"::text, 'leadTimeDays', z."lead_time_days") order by z."id") from "better_supabase"."rfq_quote_lines" z where z."quote_id" = v_quote."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."record_rfq_quote"(uuid, uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."record_rfq_quote"(uuid, uuid, jsonb, jsonb) to authenticated, service_role;

-- Withdraws a submitted quote of an open request; the supplier can quote
-- again. Needs rfqs.write.
create or replace function "better_supabase"."withdraw_rfq_quote"(quote_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_quote "better_supabase"."rfq_quotes";
  v_row "better_supabase"."rfqs";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_quote from "better_supabase"."rfq_quotes" y where y."id" = withdraw_rfq_quote.quote_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_quote."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_quote."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such quote' using errcode = 'P0002', hint = 'RFQ_QUOTE_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_quote."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_quote."tenant_id", 'rfqs.write'), false))) then
    raise exception 'not allowed to withdraw quotes' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  select * into v_row from "better_supabase"."rfqs" x where x."id" = v_quote."rfq_id";
  if v_row."status" <> 'open' or v_quote."status" <> 'submitted' then
    raise exception 'only a submitted quote of an open request can be withdrawn' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  update "better_supabase"."rfq_quotes" y set "status" = 'withdrawn', "updated_at" = now()
  where y."id" = v_quote."id" returning * into v_quote;
  update "better_supabase"."rfq_suppliers" y set "status" = 'invited' where y."id" = v_quote."invitation_id";
  perform "better_supabase".emit_event('rfq_quote.withdrawn', jsonb_build_object('organizationId', v_quote."tenant_id", 'id', v_quote."id", 'rfqId', v_quote."rfq_id", 'invitationId', v_quote."invitation_id", 'total', v_quote."total_amount"::text), 'rfqs/' || v_quote."rfq_id"::text, (v_quote."tenant_id")::text, null, 'better-supabase/rfqs');
  perform better_supabase.audit_event(
    event_type => 'rfq_quote.withdrawn',
    category => 'data',
    target_type => 'rfq',
    record_id => v_quote."rfq_id"::text,
    target_label => v_row."number",
    summary => 'quote withdrawn',
    tenant => (v_quote."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_quote."tenant_id", 'id', v_quote."id", 'rfqId', v_quote."rfq_id", 'invitationId', v_quote."invitation_id", 'total', v_quote."total_amount"::text)
  );
  return jsonb_build_object('id', v_quote."id", 'rfqId', v_quote."rfq_id", 'invitationId', v_quote."invitation_id", 'status', v_quote."status", 'currency', (select x."currency" from "better_supabase"."rfqs" x where x."id" = v_quote."rfq_id"), 'total', v_quote."total_amount"::text, 'leadTimeDays', v_quote."lead_time_days", 'validUntil', v_quote."valid_until", 'notes', v_quote."notes", 'revision', v_quote."revision", 'submittedBy', v_quote."submitted_by", 'submittedAt', v_quote."submitted_at", 'updatedAt', v_quote."updated_at");
end;
$$;
revoke execute on function "better_supabase"."withdraw_rfq_quote"(uuid) from public, anon;
grant execute on function "better_supabase"."withdraw_rfq_quote"(uuid) to authenticated, service_role;

-- The quotes side by side. lines has one entry per requested line with every
-- live quote's unit price and line total (lowest marks the best price); quotes
-- has one entry per live quote with its total, whether it prices every line
-- (complete) and whether it is the lowest complete total. Amounts are minor
-- units as text.
create or replace function "better_supabase"."compare_rfq"(rfq_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
begin
  select * into v_row from "better_supabase"."rfqs" x where x."id" = compare_rfq.rfq_id;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such request for quotation' using errcode = 'P0002', hint = 'RFQ_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'rfqId', v_row."id",
    'currency', v_row."currency",
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lineId', ln."id", 'ordinal', ln."ordinal", 'description', ln."description", 'quantity', ln."quantity",
        'offers', coalesce((
          select jsonb_agg(jsonb_build_object(
            'quoteId', y."id", 'invitationId', y."invitation_id", 'unitAmount', z."unit_amount"::text,
            'lineTotal', round(z."unit_amount" * ln."quantity")::bigint::text,
            'leadTimeDays', coalesce(z."lead_time_days", y."lead_time_days"),
            'lowest', z."unit_amount" = (
              select min(z2."unit_amount") from "better_supabase"."rfq_quote_lines" z2 join "better_supabase"."rfq_quotes" y2 on y2."id" = z2."quote_id"
              where z2."line_id" = ln."id" and y2."status" in ('submitted', 'awarded')
            )
          ) order by z."unit_amount", y."submitted_at", y."id")
          from "better_supabase"."rfq_quote_lines" z join "better_supabase"."rfq_quotes" y on y."id" = z."quote_id"
          where z."line_id" = ln."id" and y."status" in ('submitted', 'awarded')
        ), '[]'::jsonb)
      ) order by ln."ordinal")
      from "better_supabase"."rfq_lines" ln where ln."rfq_id" = v_row."id"
    ), '[]'::jsonb),
    'quotes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'quoteId', c.id, 'invitationId', c.invitation_id, 'supplierType', c.supplier_type, 'supplierId', c.supplier_id,
        'status', c.status, 'total', c.total::text, 'leadTimeDays', c.lead_time_days, 'validUntil', c.valid_until,
        'complete', c.complete,
        'lowest', c.complete and c.total = c.best
      ) order by c.total, c.submitted_at, c.id)
      from (
        select d.*, min(d.total) filter (where d.complete) over () as best
        from (
        select y."id" as id, y."invitation_id" as invitation_id, i."supplier_type" as supplier_type,
          i."supplier_id" as supplier_id, y."status" as status, y."total_amount" as total,
          y."lead_time_days" as lead_time_days, y."valid_until" as valid_until, y."submitted_at" as submitted_at,
          (select count(*) from "better_supabase"."rfq_quote_lines" z where z."quote_id" = y."id")
            = (select count(*) from "better_supabase"."rfq_lines" ln where ln."rfq_id" = v_row."id") as complete
        from "better_supabase"."rfq_quotes" y join "better_supabase"."rfq_suppliers" i on i."id" = y."invitation_id"
        where y."rfq_id" = v_row."id" and y."status" in ('submitted', 'awarded')
        ) d
      ) c
    ), '[]'::jsonb)
  );
end;
$$;
revoke execute on function "better_supabase"."compare_rfq"(uuid) from public, anon;
grant execute on function "better_supabase"."compare_rfq"(uuid) to authenticated, service_role;

-- Awards a closed or open request to one complete quote: the quote becomes
-- awarded, the other live quotes rejected and the request awarded. With a
-- location (and the inventory block) a draft purchase order for the quote's
-- supplier and prices is created and its id kept on the request; every line
-- then needs a variantId. Needs rfqs.manage and, for the purchase order, the
-- inventory purchase permission.
create or replace function "better_supabase"."award_rfq"(rfq_id uuid, quote_id uuid, location uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row "better_supabase"."rfqs";
  v_quote "better_supabase"."rfq_quotes";
  v_invitation "better_supabase"."rfq_suppliers";
  v_order uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."rfqs" x where x."id" = award_rfq.rfq_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.read'), false))) then
    raise exception 'no such request for quotation' using errcode = 'P0002', hint = 'RFQ_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or (v_row."tenant_id" is not null and coalesce(better_supabase.can('tenant', v_row."tenant_id", 'rfqs.manage'), false))) then
    raise exception 'not allowed to award requests for quotation' using errcode = '42501', hint = 'RFQ_FORBIDDEN';
  end if;
  if v_row."status" not in ('open', 'closed') then
    raise exception 'only an open or closed request can be awarded' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  select * into v_quote from "better_supabase"."rfq_quotes" y where y."id" = award_rfq.quote_id and y."rfq_id" = v_row."id" for update;
  if not found then
    raise exception 'no such quote' using errcode = 'P0002', hint = 'RFQ_QUOTE_NOT_FOUND';
  end if;
  if v_quote."status" <> 'submitted' then
    raise exception 'only a submitted quote can be awarded' using errcode = '55000', hint = 'RFQ_STATUS';
  end if;
  if (select count(*) from "better_supabase"."rfq_quote_lines" z where z."quote_id" = v_quote."id")
    <> (select count(*) from "better_supabase"."rfq_lines" ln where ln."rfq_id" = v_row."id") then
    raise exception 'only a quote that prices every line can be awarded' using errcode = '22023', hint = 'RFQ_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_rfq_award"(uuid, uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid)', v_hook::oid::regproc)
        using award_rfq.rfq_id, award_rfq.quote_id;
    end if;
  end;
  select * into v_invitation from "better_supabase"."rfq_suppliers" i where i."id" = v_quote."invitation_id";
  if award_rfq.location is not null then
    if exists (select 1 from "better_supabase"."rfq_lines" y where y."rfq_id" = v_row."id" and y."variant_id" is null) then
      raise exception 'every line needs a variantId to create a purchase order' using errcode = '22023', hint = 'RFQ_INVALID';
    end if;
    v_order := ("better_supabase"."save_purchase_order"(
      v_row."tenant_id", null, award_rfq.location, v_invitation."supplier_type", v_invitation."supplier_id",
      v_row."currency",
      case when v_quote."lead_time_days" is null then null else now() + make_interval(days => v_quote."lead_time_days") end,
      (select jsonb_agg(jsonb_build_object('variantId', y."variant_id", 'quantity', y."quantity", 'unitCost', z."unit_amount"::text) order by y."ordinal")
        from "better_supabase"."rfq_lines" y join "better_supabase"."rfq_quote_lines" z on z."line_id" = y."id" and z."quote_id" = v_quote."id"
        where y."rfq_id" = v_row."id"),
      v_row."number"
    ) ->> 'id')::uuid;
  end if;
  update "better_supabase"."rfq_quotes" y set "status" = case when y."id" = v_quote."id" then 'awarded' else 'rejected' end, "updated_at" = now()
  where y."rfq_id" = v_row."id" and y."status" = 'submitted';
  update "better_supabase"."rfqs" x set "status" = 'awarded', "awarded_quote_id" = v_quote."id", "purchase_order_id" = v_order,
    "awarded_at" = now(), "closed_at" = coalesce(x."closed_at", now()), "updated_at" = now()
  where x."id" = v_row."id" returning * into v_row;
  perform "better_supabase".emit_event('rfq.awarded', jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id"), 'rfqs/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/rfqs');
  perform better_supabase.audit_event(
    event_type => 'rfq.awarded',
    category => 'data',
    target_type => 'rfq',
    record_id => v_row."id"::text,
    target_label => v_row."number",
    summary => 'request for quotation awarded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'id', v_row."id", 'number', v_row."number", 'status', v_row."status", 'quoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_rfq_award"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'number', v_row."number", 'title', v_row."title", 'status', v_row."status", 'currency', v_row."currency", 'dueAt', v_row."due_at", 'notes', v_row."notes", 'awardedQuoteId', v_row."awarded_quote_id", 'purchaseOrderId', v_row."purchase_order_id", 'cancelReason', v_row."cancel_reason", 'openedAt', v_row."opened_at", 'closedAt', v_row."closed_at", 'awardedAt', v_row."awarded_at", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."award_rfq"(uuid, uuid, uuid) from public, anon;
grant execute on function "better_supabase"."award_rfq"(uuid, uuid, uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."rfqs";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfqs";
create policy bsb_tenant_scope_select on "better_supabase"."rfqs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfqs";
create policy bsb_tenant_scope_insert on "better_supabase"."rfqs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfqs";
create policy bsb_tenant_scope_update on "better_supabase"."rfqs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfqs";
create policy bsb_tenant_scope_delete on "better_supabase"."rfqs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rfq_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfq_lines";
create policy bsb_tenant_scope_select on "better_supabase"."rfq_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfq_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."rfq_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfq_lines";
create policy bsb_tenant_scope_update on "better_supabase"."rfq_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfq_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."rfq_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rfq_suppliers";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfq_suppliers";
create policy bsb_tenant_scope_select on "better_supabase"."rfq_suppliers" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfq_suppliers";
create policy bsb_tenant_scope_insert on "better_supabase"."rfq_suppliers" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfq_suppliers";
create policy bsb_tenant_scope_update on "better_supabase"."rfq_suppliers" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfq_suppliers";
create policy bsb_tenant_scope_delete on "better_supabase"."rfq_suppliers" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rfq_quotes";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfq_quotes";
create policy bsb_tenant_scope_select on "better_supabase"."rfq_quotes" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfq_quotes";
create policy bsb_tenant_scope_insert on "better_supabase"."rfq_quotes" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfq_quotes";
create policy bsb_tenant_scope_update on "better_supabase"."rfq_quotes" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfq_quotes";
create policy bsb_tenant_scope_delete on "better_supabase"."rfq_quotes" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."rfq_quote_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."rfq_quote_lines";
create policy bsb_tenant_scope_select on "better_supabase"."rfq_quote_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('rfqs.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."rfq_quote_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."rfq_quote_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."rfq_quote_lines";
create policy bsb_tenant_scope_update on "better_supabase"."rfq_quote_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."rfq_quote_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."rfq_quote_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.rfqs.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

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

create or replace function "api"."create_rfq"(tenant uuid, input jsonb, lines jsonb default '[]')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."create_rfq"($1, $2, $3) $$;
revoke execute on function "api"."create_rfq"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."create_rfq"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."update_rfq"(rfq_id uuid, input jsonb, lines jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."update_rfq"($1, $2, $3) $$;
revoke execute on function "api"."update_rfq"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."update_rfq"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."get_rfq"(rfq_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_rfq"($1) $$;
revoke execute on function "api"."get_rfq"(uuid) from public, anon;
grant execute on function "api"."get_rfq"(uuid) to authenticated, service_role;

create or replace function "api"."list_rfqs"(tenant uuid, filters jsonb default '{}')
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_rfqs"($1, $2) $$;
revoke execute on function "api"."list_rfqs"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_rfqs"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."invite_rfq_supplier"(rfq_id uuid, supplier_type text, supplier_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."invite_rfq_supplier"($1, $2, $3) $$;
revoke execute on function "api"."invite_rfq_supplier"(uuid, text, text) from public, anon;
grant execute on function "api"."invite_rfq_supplier"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."decline_rfq_supplier"(invitation_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."decline_rfq_supplier"($1) $$;
revoke execute on function "api"."decline_rfq_supplier"(uuid) from public, anon;
grant execute on function "api"."decline_rfq_supplier"(uuid) to authenticated, service_role;

create or replace function "api"."open_rfq"(rfq_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."open_rfq"($1) $$;
revoke execute on function "api"."open_rfq"(uuid) from public, anon;
grant execute on function "api"."open_rfq"(uuid) to authenticated, service_role;

create or replace function "api"."close_rfq"(rfq_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."close_rfq"($1) $$;
revoke execute on function "api"."close_rfq"(uuid) from public, anon;
grant execute on function "api"."close_rfq"(uuid) to authenticated, service_role;

create or replace function "api"."cancel_rfq"(rfq_id uuid, reason text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."cancel_rfq"($1, $2) $$;
revoke execute on function "api"."cancel_rfq"(uuid, text) from public, anon;
grant execute on function "api"."cancel_rfq"(uuid, text) to authenticated, service_role;

create or replace function "api"."record_rfq_quote"(rfq_id uuid, invitation_id uuid, input jsonb, lines jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_rfq_quote"($1, $2, $3, $4) $$;
revoke execute on function "api"."record_rfq_quote"(uuid, uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."record_rfq_quote"(uuid, uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."withdraw_rfq_quote"(quote_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."withdraw_rfq_quote"($1) $$;
revoke execute on function "api"."withdraw_rfq_quote"(uuid) from public, anon;
grant execute on function "api"."withdraw_rfq_quote"(uuid) to authenticated, service_role;

create or replace function "api"."compare_rfq"(rfq_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."compare_rfq"($1) $$;
revoke execute on function "api"."compare_rfq"(uuid) from public, anon;
grant execute on function "api"."compare_rfq"(uuid) to authenticated, service_role;

create or replace function "api"."award_rfq"(rfq_id uuid, quote_id uuid, location uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."award_rfq"($1, $2, $3) $$;
revoke execute on function "api"."award_rfq"(uuid, uuid, uuid) from public, anon;
grant execute on function "api"."award_rfq"(uuid, uuid, uuid) to authenticated, service_role;

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
