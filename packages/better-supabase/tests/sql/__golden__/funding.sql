-- ==== alone: schema supabase/schemas/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block funding@1 managed
-- @bsb-hash sha256:6b46b37b5ee90381951895d78318547ae958a58c620633db1e67cc3f80f076a1
-- Products a funder pays for, awards of units per period to a record from a funder in contacts, care delivered against an award from time entries, bookings or by hand, usage against the award per period, and claims per funder and period with the funder's response per line, rendered and sent through app-supplied formats and channels.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Funding: the products a funder pays for, awards of units per period to a
-- record, the care delivered against them, and claims to the funder with its
-- response per line.

create table if not exists "better_supabase"."funding_products" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The funder's product code, such as 45A48 for a Wlz product.
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 300),
  "unit" text not null check ("unit" in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece')),
  -- The price of one unit, in minor units of currency.
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "valid_from" date,
  "valid_until" date,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("valid_until" is null or "valid_from" is null or "valid_until" >= "valid_from"),
  unique ("tenant_id", "id")
);
create unique index if not exists "funding_products_code_idx" on "better_supabase"."funding_products" ("tenant_id", "code");
alter table "better_supabase"."funding_products" enable row level security;
revoke all on "better_supabase"."funding_products" from public, anon, authenticated;
grant select on "better_supabase"."funding_products" to authenticated;
grant all on "better_supabase"."funding_products" to service_role;
drop policy if exists funding_products_read on "better_supabase"."funding_products";
create policy funding_products_read on "better_supabase"."funding_products"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_awards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The record the award is for, a type in config.subjects.
  "subject_type" text not null,
  "subject_id" text not null,
  -- The contacts company or person that pays, holding the funder role.
  "funder_id" uuid not null,
  "product_id" uuid not null,
  -- The units awarded per period.
  "units" numeric not null check ("units" > 0),
  "period" text not null check ("period" in ('week', 'month', 'total')),
  "starts_on" date not null,
  "ends_on" date,
  -- The funder's reference for the award, such as an indication number.
  "reference" text check ("reference" is null or length("reference") <= 200),
  "status" text not null default 'active' check ("status" in ('requested', 'active', 'ended', 'canceled')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_on" is null or "ends_on" >= "starts_on"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "product_id") references "better_supabase"."funding_products" ("tenant_id", "id")
);
create index if not exists "funding_awards_product_idx" on "better_supabase"."funding_awards" ("tenant_id", "product_id");
create index if not exists "funding_awards_subject_idx" on "better_supabase"."funding_awards" ("subject_type", "subject_id");
create index if not exists "funding_awards_funder_idx" on "better_supabase"."funding_awards" ("tenant_id", "funder_id", "status");
alter table "better_supabase"."funding_awards" enable row level security;
revoke all on "better_supabase"."funding_awards" from public, anon, authenticated;
grant select on "better_supabase"."funding_awards" to authenticated;
grant all on "better_supabase"."funding_awards" to service_role;
drop policy if exists funding_awards_read on "better_supabase"."funding_awards";
create policy funding_awards_read on "better_supabase"."funding_awards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

create table if not exists "better_supabase"."funding_claims" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "funder_id" uuid not null,
  "number" text not null check (length("number") between 1 and 100),
  "period_start" date not null,
  "period_end" date not null,
  -- The FundingClaimFormat key that renders the claim, such as iwlz-aw319.
  "format" text not null check ("format" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'accepted', 'partially_accepted', 'rejected')),
  -- The funder's or the channel's reference for the sent claim.
  "external_ref" text check ("external_ref" is null or length("external_ref") <= 200),
  "sent_at" timestamptz,
  -- The SHA-256 of the rendered file that was sent, in hex.
  "payload_sha256" text check ("payload_sha256" is null or "payload_sha256" ~ '^[0-9a-f]{64}$'),
  -- The funder's response as the format parsed it.
  "response" jsonb,
  "total" bigint not null default 0,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  unique ("tenant_id", "id")
);
create unique index if not exists "funding_claims_number_idx" on "better_supabase"."funding_claims" ("tenant_id", "number");
create index if not exists "funding_claims_funder_idx" on "better_supabase"."funding_claims" ("tenant_id", "funder_id", "status");
alter table "better_supabase"."funding_claims" enable row level security;
revoke all on "better_supabase"."funding_claims" from public, anon, authenticated;
grant select on "better_supabase"."funding_claims" to authenticated;
grant all on "better_supabase"."funding_claims" to service_role;
drop policy if exists funding_claims_read on "better_supabase"."funding_claims";
create policy funding_claims_read on "better_supabase"."funding_claims"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_claim_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "claim_id" uuid not null,
  "award_id" uuid not null,
  "product_id" uuid not null,
  "units" numeric not null check ("units" > 0),
  -- The units times the product rate, in minor units of the claim currency.
  "amount" bigint not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'accepted', 'rejected')),
  -- The funder's code for a rejected line.
  "rejection_code" text check ("rejection_code" is null or length("rejection_code") <= 100),
  foreign key ("tenant_id", "claim_id") references "better_supabase"."funding_claims" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "award_id") references "better_supabase"."funding_awards" ("tenant_id", "id"),
  foreign key ("tenant_id", "product_id") references "better_supabase"."funding_products" ("tenant_id", "id")
);
create index if not exists "funding_claim_lines_claim_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "claim_id");
create index if not exists "funding_claim_lines_award_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "award_id");
create index if not exists "funding_claim_lines_product_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "product_id");
alter table "better_supabase"."funding_claim_lines" enable row level security;
revoke all on "better_supabase"."funding_claim_lines" from public, anon, authenticated;
grant select on "better_supabase"."funding_claim_lines" to authenticated;
grant all on "better_supabase"."funding_claim_lines" to service_role;
drop policy if exists funding_claim_lines_read on "better_supabase"."funding_claim_lines";
create policy funding_claim_lines_read on "better_supabase"."funding_claim_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "award_id" uuid not null,
  -- Where the delivery came from; source_id is the time entry or booking id.
  "source_type" text not null default 'manual' check ("source_type" in ('time_entry', 'booking', 'manual')),
  "source_id" text check ("source_id" is null or length("source_id") <= 200),
  "delivered_on" date not null,
  "units" numeric not null check ("units" > 0),
  "performer_id" uuid,
  "status" text not null default 'registered' check ("status" in ('registered', 'approved', 'claimed', 'rejected')),
  -- The claim line that claims it, once a claim gathered it.
  "claim_line_id" uuid references "better_supabase"."funding_claim_lines" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  check ("source_type" = 'manual' or "source_id" is not null),
  foreign key ("tenant_id", "award_id") references "better_supabase"."funding_awards" ("tenant_id", "id") on delete cascade
);
create index if not exists "funding_deliveries_award_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "award_id", "delivered_on");
create index if not exists "funding_deliveries_status_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "status", "delivered_on");
create index if not exists "funding_deliveries_claim_line_idx" on "better_supabase"."funding_deliveries" ("claim_line_id");
create unique index if not exists "funding_deliveries_source_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "source_type", "source_id") where "source_id" is not null;
alter table "better_supabase"."funding_deliveries" enable row level security;
revoke all on "better_supabase"."funding_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."funding_deliveries" to authenticated;
grant all on "better_supabase"."funding_deliveries" to service_role;
drop policy if exists funding_deliveries_read on "better_supabase"."funding_deliveries";
create policy funding_deliveries_read on "better_supabase"."funding_deliveries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)));

-- Adds a product a funder pays for, or changes one (product_id): its code,
-- unit and rate in minor units. The code is unique in the organization.
create or replace function "better_supabase"."save_funding_product"(tenant uuid, code text, title text, unit text, rate bigint, currency text, valid_from date default null, valid_until date default null, product_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_products"%rowtype;
  v_code text := nullif(trim(save_funding_product.code), '');
  v_title text := nullif(trim(save_funding_product.title), '');
  v_unit text := nullif(trim(save_funding_product.unit), '');
  v_currency text := upper(nullif(trim(save_funding_product.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_product.tenant, 'funding.manage'), false)) then
    raise exception 'not allowed to manage funding products' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_code is null or length(v_code) > 50 then
    raise exception 'a product needs a code of at most 50 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_title is null or length(v_title) > 300 then
    raise exception 'a product needs a title of at most 300 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_unit is null or v_unit not in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece') then
    raise exception 'unit is minute, hour, day_part, day, visit or piece' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.rate is null or save_funding_product.rate < 0 then
    raise exception 'a rate is zero or more minor units' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.valid_until < save_funding_product.valid_from then
    raise exception 'a product is valid until on or after it is valid from' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."funding_products" x
    where x."tenant_id" = save_funding_product.tenant and x."code" = v_code
      and x."id" is distinct from save_funding_product.product_id
  ) then
    raise exception 'the organization already has a funding product with this code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.product_id is null then
    insert into "better_supabase"."funding_products" ("tenant_id", "code", "title", "unit", "rate", "currency", "valid_from", "valid_until")
    values (save_funding_product.tenant, v_code, v_title, v_unit, save_funding_product.rate, v_currency, save_funding_product.valid_from, save_funding_product.valid_until)
    returning * into v_row;
  else
    update "better_supabase"."funding_products" x set
      "code" = v_code,
      "title" = v_title,
      "unit" = v_unit,
      "rate" = save_funding_product.rate,
      "currency" = v_currency,
      "valid_from" = save_funding_product.valid_from,
      "valid_until" = save_funding_product.valid_until, "updated_at" = now()
    where x."id" = save_funding_product.product_id and x."tenant_id" = save_funding_product.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'title', v_row."title", 'unit', v_row."unit", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_products"(tenant uuid, include_expired boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'title', x."title", 'unit', x."unit", 'rate', x."rate"::text, 'currency', x."currency", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code", x."id"), '[]'::jsonb)
  from "better_supabase"."funding_products" x
  where x."tenant_id" = list_funding_products.tenant
    and (coalesce(list_funding_products.include_expired, false) or x."valid_until" is null or x."valid_until" >= current_date)
$$;
revoke execute on function "better_supabase"."list_funding_products"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_products"(uuid, boolean) to authenticated, service_role;

-- Awards units of a product per period to a record, from a funder in
-- contacts, or changes an award (award_id); a key attrs leaves out keeps its
-- value. attrs holds funderId, productId, units, period (week, month or
-- total), startsOn, endsOn, reference, status (requested or active) and
-- fields, the extra columns by name.
create or replace function "better_supabase"."save_funding_award"(tenant uuid, subject_type text, subject_id text, attrs jsonb, award_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_attrs jsonb := coalesce(save_funding_award.attrs, '{}'::jsonb);
  v_funder uuid;
  v_product uuid;
  v_units numeric;
  v_period text;
  v_starts date;
  v_ends date;
  v_reference text;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_award.tenant, 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  
  if save_funding_award.award_id is null then
    if not false then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else null end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else null end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else null end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else null end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else null end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else null end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else null end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else 'active' end;
  else
    select * into v_row from "better_supabase"."funding_awards" x
    where x."id" = save_funding_award.award_id and x."tenant_id" = save_funding_award.tenant
    for update;
    if not found then
      raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
    end if;
    if v_row."subject_type" <> save_funding_award.subject_type or v_row."subject_id" <> save_funding_award.subject_id then
      raise exception 'an award stays with its record' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_row."status" in ('ended', 'canceled') then
      raise exception 'the funding award has ended' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else v_row."funder_id" end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else v_row."product_id" end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else v_row."units" end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else v_row."period" end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else v_row."ends_on" end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else v_row."reference" end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else v_row."status" end;
  end if;
  if v_funder is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if v_product is null or not exists (select 1 from "better_supabase"."funding_products" x where x."id" = v_product and x."tenant_id" = save_funding_award.tenant) then
    raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
  end if;
  if v_units is null or v_units <= 0 then
    raise exception 'an award needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_period is null or v_period not in ('week', 'month', 'total') then
    raise exception 'period is week, month or total' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an award needs a start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an award ends on or after its start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_reference is not null and length(v_reference) > 200 then
    raise exception 'reference is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_status is null or v_status not in ('requested', 'active') then
    raise exception 'a saved award is requested or active; end_funding_award ends it' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_award_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_attrs;
    end if;
  end;
  if save_funding_award.award_id is null then
    insert into "better_supabase"."funding_awards" ("tenant_id", "subject_type", "subject_id", "funder_id", "product_id", "units", "period", "starts_on", "ends_on", "reference", "status", "created_by")
    values (save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_funder, v_product, v_units, v_period, v_starts, v_ends, v_reference, v_status, (select auth.uid()))
    returning * into v_row;
    null;
  else
    update "better_supabase"."funding_awards" x set
    "funder_id" = v_funder,
    "product_id" = v_product,
    "units" = v_units,
    "period" = v_period,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "reference" = v_reference,
    "status" = v_status, "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_award_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) to authenticated, service_role;

-- Ends an award on ends_on (today by default), or cancels it (canceled).
-- Deliveries already registered stay.
create or replace function "better_supabase"."end_funding_award"(award_id uuid, ends_on date default null, canceled boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_ends date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."funding_awards" x where x."id" = end_funding_award.award_id for update;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_row."status" in ('ended', 'canceled') then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  v_ends := case
    when coalesce(end_funding_award.canceled, false) then coalesce(end_funding_award.ends_on, v_row."ends_on")
    else coalesce(end_funding_award.ends_on, least(current_date, coalesce(v_row."ends_on", current_date)))
  end;
  if v_ends is not null and v_ends < v_row."starts_on" then
    if coalesce(end_funding_award.canceled, false) then
      v_ends := null;
    else
      raise exception 'an award ends on or after its start date; cancel it instead' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end if;
  update "better_supabase"."funding_awards" x set
    "status" = case when coalesce(end_funding_award.canceled, false) then 'canceled' else 'ended' end,
    "ends_on" = v_ends, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) from public, anon;
grant execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_awards"(tenant uuid, subject_type text default null, subject_id text default null, include_ended boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'funderId', x."funder_id", 'productId', x."product_id", 'units', x."units", 'period', x."period", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'reference', x."reference", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('product', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text, 'currency', y."currency", 'validFrom', y."valid_from", 'validUntil', y."valid_until", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."funding_awards" x
  join "better_supabase"."funding_products" y on y."tenant_id" = x."tenant_id" and y."id" = x."product_id"
  where x."tenant_id" = list_funding_awards.tenant
    and (list_funding_awards.subject_type is null or x."subject_type" = list_funding_awards.subject_type)
    and (list_funding_awards.subject_id is null or x."subject_id" = list_funding_awards.subject_id)
    and (coalesce(list_funding_awards.include_ended, false) or x."status" in ('requested', 'active'))
$$;
revoke execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) to authenticated, service_role;

-- The units used against the units awarded, per period of the award from its
-- start to its end (today while it runs). Rejected deliveries don't count.
create or replace function "better_supabase"."funding_award_usage"(award_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'awardId', a."id",
    'units', a."units",
    'period', a."period",
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', s.start,
        'end', nullif(s.finish, 'infinity'::date) - 1,
        'awarded', a."units",
        'used', s.used,
        'over', greatest(s.used - a."units", 0),
        'under', greatest(a."units" - s.used, 0)
      ) order by s.start)
      from (
        select g.start, (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end) as finish, (
          select coalesce(sum(x."units"), 0) from "better_supabase"."funding_deliveries" x
          where x."tenant_id" = a."tenant_id" and x."award_id" = a."id" and x."status" <> 'rejected'
            and x."delivered_on" >= g.start and x."delivered_on" < (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end)
        ) as used
        from (
          select pg_catalog.generate_series(
            (case a."period" when 'week' then date_trunc('week', a."starts_on")::date when 'month' then date_trunc('month', a."starts_on")::date else a."starts_on" end)::timestamp,
            coalesce(a."ends_on", current_date)::timestamp,
            case a."period" when 'week' then interval '1 week' else interval '1 month' end
          )::date as start
          where a."period" <> 'total'
          union all
          select a."starts_on" where a."period" = 'total'
        ) g
      ) s
    ), '[]'::jsonb)
  )
  from "better_supabase"."funding_awards" a
  where a."id" = funding_award_usage.award_id
$$;
revoke execute on function "better_supabase"."funding_award_usage"(uuid) from public, anon;
grant execute on function "better_supabase"."funding_award_usage"(uuid) to authenticated, service_role;

-- Registers care delivered on an award: units on a day, from a time entry, a
-- booking or by hand (manual). A source registered before returns its
-- delivery, so registering it twice is safe. Crossing the units of a period
-- emits funding_award.exceeded.
create or replace function "better_supabase"."register_funding_delivery"(award_id uuid, delivered_on date, units numeric, source_type text default 'manual', source_id text default null, performer_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_award "better_supabase"."funding_awards"%rowtype;
  v_product "better_supabase"."funding_products"%rowtype;
  v_source text := coalesce(nullif(trim(register_funding_delivery.source_type), ''), 'manual');
  v_source_id text := nullif(trim(register_funding_delivery.source_id), '');
  v_note text := nullif(trim(register_funding_delivery.note), '');
  v_start date;
  v_used numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_award from "better_supabase"."funding_awards" x where x."id" = register_funding_delivery.award_id;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_award."tenant_id", 'funding.register'), false)) then
    raise exception 'not allowed to register funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_source not in ('time_entry', 'booking', 'manual') then
    raise exception 'source_type is time_entry, booking or manual' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source <> 'manual' and v_source_id is null then
    raise exception 'a delivery from a time entry or booking needs its source_id' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source_id is not null then
    select * into v_row from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = v_award."tenant_id" and x."source_type" = v_source and x."source_id" = v_source_id;
    if found then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
    end if;
  end if;
  if register_funding_delivery.delivered_on is null then
    raise exception 'a delivery needs the day it was delivered' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if register_funding_delivery.units is null or register_funding_delivery.units <= 0 then
    raise exception 'a delivery needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_award."status" <> 'active'
    or register_funding_delivery.delivered_on < v_award."starts_on"
    or register_funding_delivery.delivered_on > coalesce(v_award."ends_on", register_funding_delivery.delivered_on) then
    raise exception 'the funding award isn''t active on that day' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
  end if;
  select * into v_product from "better_supabase"."funding_products" x where x."tenant_id" = v_award."tenant_id" and x."id" = v_award."product_id";
  if (v_product."valid_from" is not null and register_funding_delivery.delivered_on < v_product."valid_from")
    or (v_product."valid_until" is not null and register_funding_delivery.delivered_on > v_product."valid_until") then
    raise exception 'the funding product isn''t valid on that day' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_delivery_register"(uuid, date, numeric)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::date, $3::numeric)', v_hook::oid::regproc)
        using v_award."id", register_funding_delivery.delivered_on, register_funding_delivery.units;
    end if;
  end;
  insert into "better_supabase"."funding_deliveries" ("tenant_id", "award_id", "source_type", "source_id", "delivered_on", "units", "performer_id", "note")
  values (v_award."tenant_id", v_award."id", v_source, v_source_id, register_funding_delivery.delivered_on, register_funding_delivery.units, coalesce(register_funding_delivery.performer_id, (select auth.uid())), v_note)
  returning * into v_row;
  null;
  v_start := (case v_award."period" when 'week' then date_trunc('week', v_row."delivered_on")::date when 'month' then date_trunc('month', v_row."delivered_on")::date else v_award."starts_on" end);
  select coalesce(sum(x."units"), 0) into v_used from "better_supabase"."funding_deliveries" x
  where x."tenant_id" = v_award."tenant_id" and x."award_id" = v_award."id" and x."status" <> 'rejected'
    and x."delivered_on" >= v_start and x."delivered_on" < (case v_award."period" when 'week' then (v_start + 7) when 'month' then (v_start + interval '1 month')::date else coalesce(v_award."ends_on" + 1, 'infinity'::date) end);
  if v_used > v_award."units" and v_used - v_row."units" <= v_award."units" then
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_delivery_register"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) to authenticated, service_role;

-- Approves registered deliveries for a claim (approved true) or rejects them.
-- A delivery a claim holds can't change. Returns how many changed.
create or replace function "better_supabase"."approve_funding_deliveries"(ids uuid[], approved boolean default true)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_status text := case when coalesce(approve_funding_deliveries.approved, true) then 'approved' else 'rejected' end;
  v_found integer := 0;
  v_changed integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    select * from "better_supabase"."funding_deliveries" x
    where x."id" = any (coalesce(approve_funding_deliveries.ids, '{}'::uuid[]))
    order by x."id"
    for update
  loop
    v_found := v_found + 1;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.approve'), false)) then
      raise exception 'not allowed to approve funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
    end if;
    if v_row."status" = 'claimed' then
      raise exception 'a claim holds this delivery' using errcode = '22023', hint = 'FUNDING_DELIVERY_CLAIMED';
    end if;
    if v_row."status" <> v_status then
      update "better_supabase"."funding_deliveries" x set "status" = v_status where x."id" = v_row."id";
      v_changed := v_changed + 1;
    end if;
  end loop;
  if v_found < (select count(distinct i) from unnest(coalesce(approve_funding_deliveries.ids, '{}'::uuid[])) i) then
    raise exception 'funding delivery not found' using errcode = 'P0002', hint = 'FUNDING_DELIVERY_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) to authenticated, service_role;

-- The deliveries of an organization, newest first. filter holds awardId,
-- status, since and until (days), and limit (500 by default, 1000 at most).
create or replace function "better_supabase"."list_funding_deliveries"(tenant uuid, filter jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.row order by z.day desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'awardId', x."award_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'deliveredOn', x."delivered_on", 'units', x."units", 'performerId', x."performer_id", 'status', x."status", 'claimLineId', x."claim_line_id", 'note', x."note", 'createdAt', x."created_at") as row, x."delivered_on" as day, x."id" as id
    from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = list_funding_deliveries.tenant
      and (list_funding_deliveries.filter ->> 'awardId' is null or x."award_id" = (list_funding_deliveries.filter ->> 'awardId')::uuid)
      and (list_funding_deliveries.filter ->> 'status' is null or x."status" = list_funding_deliveries.filter ->> 'status')
      and (list_funding_deliveries.filter ->> 'since' is null or x."delivered_on" >= (list_funding_deliveries.filter ->> 'since')::date)
      and (list_funding_deliveries.filter ->> 'until' is null or x."delivered_on" <= (list_funding_deliveries.filter ->> 'until')::date)
    order by x."delivered_on" desc, x."id"
    limit least(greatest(coalesce((list_funding_deliveries.filter ->> 'limit')::integer, 500), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) to authenticated, service_role;

-- Gathers the approved deliveries of a funder from period_start to
-- period_end into a draft claim in format (a FundingClaimFormat key), one
-- line per award, priced at the product rate. The deliveries become claimed.
create or replace function "better_supabase"."build_funding_claim"(tenant uuid, funder_id uuid, period_start date, period_end date, format text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_format text := nullif(trim(build_funding_claim.format), '');
  v_currencies integer;
  v_currency text;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', build_funding_claim.tenant, 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_format is null or v_format !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'the claim format isn''t one this organization claims in' using errcode = '22023', hint = 'FUNDING_FORMAT_UNKNOWN';
  end if;
  if build_funding_claim.funder_id is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if build_funding_claim.period_start is null or build_funding_claim.period_end is null
    or build_funding_claim.period_end < build_funding_claim.period_start then
    raise exception 'a claim period ends on or after it starts' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_claim_build"(uuid, uuid, date, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date, $4::date)', v_hook::oid::regproc)
        using build_funding_claim.tenant, build_funding_claim.funder_id, build_funding_claim.period_start, build_funding_claim.period_end;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb_funding_claim:' || build_funding_claim.tenant::text, 0));
  perform 1 from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  for update of x;
  select count(distinct y."currency"), min(y."currency") into v_currencies, v_currency
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  if v_currencies = 0 then
    raise exception 'no approved deliveries of this funder in the period' using errcode = '22023', hint = 'FUNDING_CLAIM_EMPTY';
  end if;
  if v_currencies > 1 then
    raise exception 'the deliveries are priced in several currencies; claim each product''s currency apart' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  select coalesce(max(x."number"::bigint) filter (where x."number" ~ '^[0-9]{1,18}$'), 0) + 1 into v_seq
  from "better_supabase"."funding_claims" x where x."tenant_id" = build_funding_claim.tenant;
  v_number := v_seq::text;
  insert into "better_supabase"."funding_claims" ("tenant_id", "funder_id", "number", "period_start", "period_end", "format", "currency", "created_by")
  values (build_funding_claim.tenant, build_funding_claim.funder_id, v_number, build_funding_claim.period_start, build_funding_claim.period_end, v_format, v_currency, (select auth.uid()))
  returning * into v_claim;
  insert into "better_supabase"."funding_claim_lines" ("tenant_id", "claim_id", "award_id", "product_id", "units", "amount")
  select build_funding_claim.tenant, v_claim."id", a."id", y."id", sum(x."units"), round(sum(x."units") * y."rate")::bigint
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  group by a."id", y."id", y."rate";
  update "better_supabase"."funding_deliveries" x set "status" = 'claimed', "claim_line_id" = z."id"
  from "better_supabase"."funding_claim_lines" z
  where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
    and x."tenant_id" = z."tenant_id" and x."award_id" = z."award_id"
    and x."status" = 'approved' and x."claim_line_id" is null
    and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  update "better_supabase"."funding_claims" x set "total" = (
    select coalesce(sum(z."amount"), 0) from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  )
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_claim_build"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_claim."id";
    end if;
  end;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) from public, anon;
grant execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) to authenticated, service_role;

-- A claim with its lines, each with its award, product and deliveries: what a
-- FundingClaimFormat renders.
create or replace function "better_supabase"."get_funding_claim"(claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = get_funding_claim.claim_id;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.read'), false)) then
    raise exception 'not allowed to read funding claims' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."get_funding_claim"(uuid) to authenticated, service_role;

-- Marks a draft claim sent, with the channel's reference and the SHA-256 of
-- the file that was sent.
create or replace function "better_supabase"."mark_funding_claim_sent"(claim_id uuid, external_ref text default null, payload_sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_ref text := nullif(trim(mark_funding_claim_sent.external_ref), '');
  v_sha text := lower(nullif(trim(mark_funding_claim_sent.payload_sha256), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = mark_funding_claim_sent.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'external_ref is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'payload_sha256 is a SHA-256 in hex' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  update "better_supabase"."funding_claims" x set "status" = 'sent', "sent_at" = now(), "external_ref" = v_ref, "payload_sha256" = v_sha, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at");
end;
$$;
revoke execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) to authenticated, service_role;

-- Records the funder's response to a sent claim: lines is an array of
-- { lineId, status (accepted or rejected), rejectionCode }, or null for
-- none. A line the response leaves out is accepted. The deliveries of a rejected line go back
-- to approved, for correction and a later claim.
create or replace function "better_supabase"."record_funding_claim_response"(claim_id uuid, lines jsonb, response jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_line jsonb;
  v_status text;
  v_code text;
  v_accepted integer;
  v_rejected integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = record_funding_claim_response.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'sent' then
    raise exception 'only a sent claim takes a response' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if jsonb_typeof(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) <> 'array' then
    raise exception 'lines is an array' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_line in select value from jsonb_array_elements(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) loop
    v_status := v_line ->> 'status';
    v_code := nullif(trim(v_line ->> 'rejectionCode'), '');
    if jsonb_typeof(v_line) <> 'object' or v_status is null or v_status not in ('accepted', 'rejected') then
      raise exception 'each line has a lineId and a status of accepted or rejected' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_code is not null and length(v_code) > 100 then
      raise exception 'a rejection code is at most 100 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    update "better_supabase"."funding_claim_lines" x set "status" = v_status, "rejection_code" = case when v_status = 'rejected' then v_code end
    where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id"
      and x."id"::text = v_line ->> 'lineId';
    if not found then
      raise exception 'a line in the response isn''t a line of this claim' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end loop;
  update "better_supabase"."funding_claim_lines" x set "status" = 'accepted'
  where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id" and x."status" = 'pending';
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id" and z."status" = 'rejected');
  select count(*) filter (where z."status" = 'accepted'), count(*) filter (where z."status" = 'rejected')
  into v_accepted, v_rejected
  from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id";
  update "better_supabase"."funding_claims" x set
    "status" = case when v_rejected = 0 then 'accepted' when v_accepted = 0 then 'rejected' else 'partially_accepted' end,
    "response" = record_funding_claim_response.response, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Deletes a draft claim; its deliveries go back to approved.
create or replace function "better_supabase"."delete_funding_claim"(claim_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = delete_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id");
  delete from "better_supabase"."funding_claims" x where x."id" = v_claim."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_funding_claim"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_claims"(tenant uuid, status text default null, funder_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'funderId', x."funder_id", 'number', x."number", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'format', x."format", 'status', x."status", 'externalRef', x."external_ref", 'sentAt', x."sent_at", 'payloadSha256', x."payload_sha256", 'response', x."response", 'total', x."total"::text, 'currency', x."currency", 'invoiceId', x."invoice_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."number" desc), '[]'::jsonb)
  from "better_supabase"."funding_claims" x
  where x."tenant_id" = list_funding_claims.tenant
    and (list_funding_claims.status is null or x."status" = list_funding_claims.status)
    and (list_funding_claims.funder_id is null or x."funder_id" = list_funding_claims.funder_id)
$$;
revoke execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
create policy bsb_tenant_scope_select on "better_supabase"."funding_products" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_products" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
create policy bsb_tenant_scope_update on "better_supabase"."funding_products" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_products" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_select on "better_supabase"."funding_awards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_awards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_update on "better_supabase"."funding_awards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_awards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_select on "better_supabase"."funding_deliveries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_deliveries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_update on "better_supabase"."funding_deliveries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_deliveries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claims" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claim_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claim_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines" as restrictive
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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block-data funding
-- @bsb-hash sha256:5f2aaa76a9d6c8414def54826e938bc7edcce178f14b0d9edd894653bfab3d11
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block funding@1 managed
-- @bsb-hash sha256:992215017fd4aa888d086cfd9be2f1d5c34b90eee374ec3755fb25701ba9fcb9
-- Products a funder pays for, awards of units per period to a record from a funder in contacts, care delivered against an award from time entries, bookings or by hand, usage against the award per period, and claims per funder and period with the funder's response per line, rendered and sent through app-supplied formats and channels.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Funding: the products a funder pays for, awards of units per period to a
-- record, the care delivered against them, and claims to the funder with its
-- response per line.

create table if not exists "better_supabase"."funding_products" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The funder's product code, such as 45A48 for a Wlz product.
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 300),
  "unit" text not null check ("unit" in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece')),
  -- The price of one unit, in minor units of currency.
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "valid_from" date,
  "valid_until" date,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("valid_until" is null or "valid_from" is null or "valid_until" >= "valid_from"),
  unique ("tenant_id", "id")
);
create unique index if not exists "funding_products_code_idx" on "better_supabase"."funding_products" ("tenant_id", "code");
alter table "better_supabase"."funding_products" enable row level security;
revoke all on "better_supabase"."funding_products" from public, anon, authenticated;
grant select on "better_supabase"."funding_products" to authenticated;
grant all on "better_supabase"."funding_products" to service_role;
drop policy if exists funding_products_read on "better_supabase"."funding_products";
create policy funding_products_read on "better_supabase"."funding_products"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_awards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The record the award is for, a type in config.subjects.
  "subject_type" text not null,
  "subject_id" text not null,
  -- The contacts company or person that pays, holding the funder role.
  "funder_id" uuid not null,
  "product_id" uuid not null,
  -- The units awarded per period.
  "units" numeric not null check ("units" > 0),
  "period" text not null check ("period" in ('week', 'month', 'total')),
  "starts_on" date not null,
  "ends_on" date,
  -- The funder's reference for the award, such as an indication number.
  "reference" text check ("reference" is null or length("reference") <= 200),
  "status" text not null default 'active' check ("status" in ('requested', 'active', 'ended', 'canceled')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_on" is null or "ends_on" >= "starts_on"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "product_id") references "better_supabase"."funding_products" ("tenant_id", "id")
);
create index if not exists "funding_awards_product_idx" on "better_supabase"."funding_awards" ("tenant_id", "product_id");
create index if not exists "funding_awards_subject_idx" on "better_supabase"."funding_awards" ("subject_type", "subject_id");
create index if not exists "funding_awards_funder_idx" on "better_supabase"."funding_awards" ("tenant_id", "funder_id", "status");
alter table "better_supabase"."funding_awards" enable row level security;
revoke all on "better_supabase"."funding_awards" from public, anon, authenticated;
grant select on "better_supabase"."funding_awards" to authenticated;
grant all on "better_supabase"."funding_awards" to service_role;
drop policy if exists funding_awards_read on "better_supabase"."funding_awards";
create policy funding_awards_read on "better_supabase"."funding_awards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

create table if not exists "better_supabase"."funding_claims" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "funder_id" uuid not null,
  "number" text not null check (length("number") between 1 and 100),
  "period_start" date not null,
  "period_end" date not null,
  -- The FundingClaimFormat key that renders the claim, such as iwlz-aw319.
  "format" text not null check ("format" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'accepted', 'partially_accepted', 'rejected')),
  -- The funder's or the channel's reference for the sent claim.
  "external_ref" text check ("external_ref" is null or length("external_ref") <= 200),
  "sent_at" timestamptz,
  -- The SHA-256 of the rendered file that was sent, in hex.
  "payload_sha256" text check ("payload_sha256" is null or "payload_sha256" ~ '^[0-9a-f]{64}$'),
  -- The funder's response as the format parsed it.
  "response" jsonb,
  "total" bigint not null default 0,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  unique ("tenant_id", "id")
);
create unique index if not exists "funding_claims_number_idx" on "better_supabase"."funding_claims" ("tenant_id", "number");
create index if not exists "funding_claims_funder_idx" on "better_supabase"."funding_claims" ("tenant_id", "funder_id", "status");
alter table "better_supabase"."funding_claims" enable row level security;
revoke all on "better_supabase"."funding_claims" from public, anon, authenticated;
grant select on "better_supabase"."funding_claims" to authenticated;
grant all on "better_supabase"."funding_claims" to service_role;
drop policy if exists funding_claims_read on "better_supabase"."funding_claims";
create policy funding_claims_read on "better_supabase"."funding_claims"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_claim_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "claim_id" uuid not null,
  "award_id" uuid not null,
  "product_id" uuid not null,
  "units" numeric not null check ("units" > 0),
  -- The units times the product rate, in minor units of the claim currency.
  "amount" bigint not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'accepted', 'rejected')),
  -- The funder's code for a rejected line.
  "rejection_code" text check ("rejection_code" is null or length("rejection_code") <= 100),
  foreign key ("tenant_id", "claim_id") references "better_supabase"."funding_claims" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "award_id") references "better_supabase"."funding_awards" ("tenant_id", "id"),
  foreign key ("tenant_id", "product_id") references "better_supabase"."funding_products" ("tenant_id", "id")
);
create index if not exists "funding_claim_lines_claim_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "claim_id");
create index if not exists "funding_claim_lines_award_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "award_id");
create index if not exists "funding_claim_lines_product_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "product_id");
alter table "better_supabase"."funding_claim_lines" enable row level security;
revoke all on "better_supabase"."funding_claim_lines" from public, anon, authenticated;
grant select on "better_supabase"."funding_claim_lines" to authenticated;
grant all on "better_supabase"."funding_claim_lines" to service_role;
drop policy if exists funding_claim_lines_read on "better_supabase"."funding_claim_lines";
create policy funding_claim_lines_read on "better_supabase"."funding_claim_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "award_id" uuid not null,
  -- Where the delivery came from; source_id is the time entry or booking id.
  "source_type" text not null default 'manual' check ("source_type" in ('time_entry', 'booking', 'manual')),
  "source_id" text check ("source_id" is null or length("source_id") <= 200),
  "delivered_on" date not null,
  "units" numeric not null check ("units" > 0),
  "performer_id" uuid,
  "status" text not null default 'registered' check ("status" in ('registered', 'approved', 'claimed', 'rejected')),
  -- The claim line that claims it, once a claim gathered it.
  "claim_line_id" uuid references "better_supabase"."funding_claim_lines" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  check ("source_type" = 'manual' or "source_id" is not null),
  foreign key ("tenant_id", "award_id") references "better_supabase"."funding_awards" ("tenant_id", "id") on delete cascade
);
create index if not exists "funding_deliveries_award_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "award_id", "delivered_on");
create index if not exists "funding_deliveries_status_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "status", "delivered_on");
create index if not exists "funding_deliveries_claim_line_idx" on "better_supabase"."funding_deliveries" ("claim_line_id");
create unique index if not exists "funding_deliveries_source_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "source_type", "source_id") where "source_id" is not null;
alter table "better_supabase"."funding_deliveries" enable row level security;
revoke all on "better_supabase"."funding_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."funding_deliveries" to authenticated;
grant all on "better_supabase"."funding_deliveries" to service_role;
drop policy if exists funding_deliveries_read on "better_supabase"."funding_deliveries";
create policy funding_deliveries_read on "better_supabase"."funding_deliveries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)));

-- Adds a product a funder pays for, or changes one (product_id): its code,
-- unit and rate in minor units. The code is unique in the organization.
create or replace function "better_supabase"."save_funding_product"(tenant uuid, code text, title text, unit text, rate bigint, currency text, valid_from date default null, valid_until date default null, product_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_products"%rowtype;
  v_code text := nullif(trim(save_funding_product.code), '');
  v_title text := nullif(trim(save_funding_product.title), '');
  v_unit text := nullif(trim(save_funding_product.unit), '');
  v_currency text := upper(nullif(trim(save_funding_product.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_product.tenant, 'funding.manage'), false)) then
    raise exception 'not allowed to manage funding products' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_code is null or length(v_code) > 50 then
    raise exception 'a product needs a code of at most 50 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_title is null or length(v_title) > 300 then
    raise exception 'a product needs a title of at most 300 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_unit is null or v_unit not in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece') then
    raise exception 'unit is minute, hour, day_part, day, visit or piece' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.rate is null or save_funding_product.rate < 0 then
    raise exception 'a rate is zero or more minor units' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.valid_until < save_funding_product.valid_from then
    raise exception 'a product is valid until on or after it is valid from' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."funding_products" x
    where x."tenant_id" = save_funding_product.tenant and x."code" = v_code
      and x."id" is distinct from save_funding_product.product_id
  ) then
    raise exception 'the organization already has a funding product with this code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.product_id is null then
    insert into "better_supabase"."funding_products" ("tenant_id", "code", "title", "unit", "rate", "currency", "valid_from", "valid_until")
    values (save_funding_product.tenant, v_code, v_title, v_unit, save_funding_product.rate, v_currency, save_funding_product.valid_from, save_funding_product.valid_until)
    returning * into v_row;
  else
    update "better_supabase"."funding_products" x set
      "code" = v_code,
      "title" = v_title,
      "unit" = v_unit,
      "rate" = save_funding_product.rate,
      "currency" = v_currency,
      "valid_from" = save_funding_product.valid_from,
      "valid_until" = save_funding_product.valid_until, "updated_at" = now()
    where x."id" = save_funding_product.product_id and x."tenant_id" = save_funding_product.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'title', v_row."title", 'unit', v_row."unit", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_products"(tenant uuid, include_expired boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'title', x."title", 'unit', x."unit", 'rate', x."rate"::text, 'currency', x."currency", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code", x."id"), '[]'::jsonb)
  from "better_supabase"."funding_products" x
  where x."tenant_id" = list_funding_products.tenant
    and (coalesce(list_funding_products.include_expired, false) or x."valid_until" is null or x."valid_until" >= current_date)
$$;
revoke execute on function "better_supabase"."list_funding_products"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_products"(uuid, boolean) to authenticated, service_role;

-- Awards units of a product per period to a record, from a funder in
-- contacts, or changes an award (award_id); a key attrs leaves out keeps its
-- value. attrs holds funderId, productId, units, period (week, month or
-- total), startsOn, endsOn, reference, status (requested or active) and
-- fields, the extra columns by name.
create or replace function "better_supabase"."save_funding_award"(tenant uuid, subject_type text, subject_id text, attrs jsonb, award_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_attrs jsonb := coalesce(save_funding_award.attrs, '{}'::jsonb);
  v_funder uuid;
  v_product uuid;
  v_units numeric;
  v_period text;
  v_starts date;
  v_ends date;
  v_reference text;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_award.tenant, 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  
  if save_funding_award.award_id is null then
    if not false then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else null end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else null end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else null end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else null end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else null end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else null end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else null end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else 'active' end;
  else
    select * into v_row from "better_supabase"."funding_awards" x
    where x."id" = save_funding_award.award_id and x."tenant_id" = save_funding_award.tenant
    for update;
    if not found then
      raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
    end if;
    if v_row."subject_type" <> save_funding_award.subject_type or v_row."subject_id" <> save_funding_award.subject_id then
      raise exception 'an award stays with its record' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_row."status" in ('ended', 'canceled') then
      raise exception 'the funding award has ended' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else v_row."funder_id" end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else v_row."product_id" end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else v_row."units" end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else v_row."period" end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else v_row."ends_on" end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else v_row."reference" end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else v_row."status" end;
  end if;
  if v_funder is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if v_product is null or not exists (select 1 from "better_supabase"."funding_products" x where x."id" = v_product and x."tenant_id" = save_funding_award.tenant) then
    raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
  end if;
  if v_units is null or v_units <= 0 then
    raise exception 'an award needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_period is null or v_period not in ('week', 'month', 'total') then
    raise exception 'period is week, month or total' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an award needs a start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an award ends on or after its start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_reference is not null and length(v_reference) > 200 then
    raise exception 'reference is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_status is null or v_status not in ('requested', 'active') then
    raise exception 'a saved award is requested or active; end_funding_award ends it' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_award_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_attrs;
    end if;
  end;
  if save_funding_award.award_id is null then
    insert into "better_supabase"."funding_awards" ("tenant_id", "subject_type", "subject_id", "funder_id", "product_id", "units", "period", "starts_on", "ends_on", "reference", "status", "created_by")
    values (save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_funder, v_product, v_units, v_period, v_starts, v_ends, v_reference, v_status, (select auth.uid()))
    returning * into v_row;
    perform "better_supabase".emit_event('funding_award.created', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'funding-awards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_award.created',
    category => 'data',
    target_type => 'funding_award',
    record_id => v_row."id"::text,
    summary => 'Funding awarded',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  else
    update "better_supabase"."funding_awards" x set
    "funder_id" = v_funder,
    "product_id" = v_product,
    "units" = v_units,
    "period" = v_period,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "reference" = v_reference,
    "status" = v_status, "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    perform "better_supabase".emit_event('funding_award.updated', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status"), 'funding-awards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_award.updated',
    category => 'data',
    target_type => 'funding_award',
    record_id => v_row."id"::text,
    summary => 'Funding award changed',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status")
  );
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_award_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) to authenticated, service_role;

-- Ends an award on ends_on (today by default), or cancels it (canceled).
-- Deliveries already registered stay.
create or replace function "better_supabase"."end_funding_award"(award_id uuid, ends_on date default null, canceled boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_ends date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."funding_awards" x where x."id" = end_funding_award.award_id for update;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_row."status" in ('ended', 'canceled') then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  v_ends := case
    when coalesce(end_funding_award.canceled, false) then coalesce(end_funding_award.ends_on, v_row."ends_on")
    else coalesce(end_funding_award.ends_on, least(current_date, coalesce(v_row."ends_on", current_date)))
  end;
  if v_ends is not null and v_ends < v_row."starts_on" then
    if coalesce(end_funding_award.canceled, false) then
      v_ends := null;
    else
      raise exception 'an award ends on or after its start date; cancel it instead' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end if;
  update "better_supabase"."funding_awards" x set
    "status" = case when coalesce(end_funding_award.canceled, false) then 'canceled' else 'ended' end,
    "ends_on" = v_ends, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  perform "better_supabase".emit_event('funding_award.ended', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'endsOn', v_row."ends_on"), 'funding-awards/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_award.ended',
    category => 'data',
    target_type => 'funding_award',
    record_id => v_row."id"::text,
    summary => 'Funding award ended',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."id", 'fundingProductId', v_row."product_id", 'funderId', v_row."funder_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'status', v_row."status", 'endsOn', v_row."ends_on")
  );
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) from public, anon;
grant execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_awards"(tenant uuid, subject_type text default null, subject_id text default null, include_ended boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'funderId', x."funder_id", 'productId', x."product_id", 'units', x."units", 'period', x."period", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'reference', x."reference", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('product', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text, 'currency', y."currency", 'validFrom', y."valid_from", 'validUntil', y."valid_until", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."funding_awards" x
  join "better_supabase"."funding_products" y on y."tenant_id" = x."tenant_id" and y."id" = x."product_id"
  where x."tenant_id" = list_funding_awards.tenant
    and (list_funding_awards.subject_type is null or x."subject_type" = list_funding_awards.subject_type)
    and (list_funding_awards.subject_id is null or x."subject_id" = list_funding_awards.subject_id)
    and (coalesce(list_funding_awards.include_ended, false) or x."status" in ('requested', 'active'))
$$;
revoke execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) to authenticated, service_role;

-- The units used against the units awarded, per period of the award from its
-- start to its end (today while it runs). Rejected deliveries don't count.
create or replace function "better_supabase"."funding_award_usage"(award_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'awardId', a."id",
    'units', a."units",
    'period', a."period",
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', s.start,
        'end', nullif(s.finish, 'infinity'::date) - 1,
        'awarded', a."units",
        'used', s.used,
        'over', greatest(s.used - a."units", 0),
        'under', greatest(a."units" - s.used, 0)
      ) order by s.start)
      from (
        select g.start, (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end) as finish, (
          select coalesce(sum(x."units"), 0) from "better_supabase"."funding_deliveries" x
          where x."tenant_id" = a."tenant_id" and x."award_id" = a."id" and x."status" <> 'rejected'
            and x."delivered_on" >= g.start and x."delivered_on" < (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end)
        ) as used
        from (
          select pg_catalog.generate_series(
            (case a."period" when 'week' then date_trunc('week', a."starts_on")::date when 'month' then date_trunc('month', a."starts_on")::date else a."starts_on" end)::timestamp,
            coalesce(a."ends_on", current_date)::timestamp,
            case a."period" when 'week' then interval '1 week' else interval '1 month' end
          )::date as start
          where a."period" <> 'total'
          union all
          select a."starts_on" where a."period" = 'total'
        ) g
      ) s
    ), '[]'::jsonb)
  )
  from "better_supabase"."funding_awards" a
  where a."id" = funding_award_usage.award_id
$$;
revoke execute on function "better_supabase"."funding_award_usage"(uuid) from public, anon;
grant execute on function "better_supabase"."funding_award_usage"(uuid) to authenticated, service_role;

-- Registers care delivered on an award: units on a day, from a time entry, a
-- booking or by hand (manual). A source registered before returns its
-- delivery, so registering it twice is safe. Crossing the units of a period
-- emits funding_award.exceeded.
create or replace function "better_supabase"."register_funding_delivery"(award_id uuid, delivered_on date, units numeric, source_type text default 'manual', source_id text default null, performer_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_award "better_supabase"."funding_awards"%rowtype;
  v_product "better_supabase"."funding_products"%rowtype;
  v_source text := coalesce(nullif(trim(register_funding_delivery.source_type), ''), 'manual');
  v_source_id text := nullif(trim(register_funding_delivery.source_id), '');
  v_note text := nullif(trim(register_funding_delivery.note), '');
  v_start date;
  v_used numeric;
  v_claims text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_award from "better_supabase"."funding_awards" x where x."id" = register_funding_delivery.award_id;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_award."tenant_id", 'funding.register'), false)) then
    raise exception 'not allowed to register funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_source not in ('time_entry', 'booking', 'manual') then
    raise exception 'source_type is time_entry, booking or manual' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source <> 'manual' and v_source_id is null then
    raise exception 'a delivery from a time entry or booking needs its source_id' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source_id is not null then
    select * into v_row from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = v_award."tenant_id" and x."source_type" = v_source and x."source_id" = v_source_id;
    if found then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
    end if;
  end if;
  if register_funding_delivery.delivered_on is null then
    raise exception 'a delivery needs the day it was delivered' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if register_funding_delivery.units is null or register_funding_delivery.units <= 0 then
    raise exception 'a delivery needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_award."status" <> 'active'
    or register_funding_delivery.delivered_on < v_award."starts_on"
    or register_funding_delivery.delivered_on > coalesce(v_award."ends_on", register_funding_delivery.delivered_on) then
    raise exception 'the funding award isn''t active on that day' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
  end if;
  select * into v_product from "better_supabase"."funding_products" x where x."tenant_id" = v_award."tenant_id" and x."id" = v_award."product_id";
  if (v_product."valid_from" is not null and register_funding_delivery.delivered_on < v_product."valid_from")
    or (v_product."valid_until" is not null and register_funding_delivery.delivered_on > v_product."valid_until") then
    raise exception 'the funding product isn''t valid on that day' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source = 'time_entry' and not exists (
    select 1 from "better_supabase"."time_entries" x
    where x."id"::text = v_source_id and x."tenant_id" = v_award."tenant_id"
  ) then
    raise exception 'the time entry isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source = 'booking' and not exists (
    select 1 from "better_supabase"."bookings" x
    where x."id"::text = v_source_id and x."tenant_id" = v_award."tenant_id"
  ) then
    raise exception 'the booking isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_delivery_register"(uuid, date, numeric)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::date, $3::numeric)', v_hook::oid::regproc)
        using v_award."id", register_funding_delivery.delivered_on, register_funding_delivery.units;
    end if;
  end;
  insert into "better_supabase"."funding_deliveries" ("tenant_id", "award_id", "source_type", "source_id", "delivered_on", "units", "performer_id", "note")
  values (v_award."tenant_id", v_award."id", v_source, v_source_id, register_funding_delivery.delivered_on, register_funding_delivery.units, coalesce(register_funding_delivery.performer_id, (select auth.uid())), v_note)
  returning * into v_row;
  perform "better_supabase".emit_event('funding_delivery.registered', jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."award_id", 'fundingDeliveryId', v_row."id", 'subjectType', v_award."subject_type", 'subjectId', v_award."subject_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units"), 'funding-awards/' || v_row."award_id"::text, (v_row."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_delivery.registered',
    category => 'data',
    target_type => 'funding_delivery',
    record_id => v_row."id"::text,
    summary => 'Funded care registered',
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_row."tenant_id", 'fundingAwardId', v_row."award_id", 'fundingDeliveryId', v_row."id", 'subjectType', v_award."subject_type", 'subjectId', v_award."subject_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units")
  );
  v_start := (case v_award."period" when 'week' then date_trunc('week', v_row."delivered_on")::date when 'month' then date_trunc('month', v_row."delivered_on")::date else v_award."starts_on" end);
  select coalesce(sum(x."units"), 0) into v_used from "better_supabase"."funding_deliveries" x
  where x."tenant_id" = v_award."tenant_id" and x."award_id" = v_award."id" and x."status" <> 'rejected'
    and x."delivered_on" >= v_start and x."delivered_on" < (case v_award."period" when 'week' then (v_start + 7) when 'month' then (v_start + interval '1 month')::date else coalesce(v_award."ends_on" + 1, 'infinity'::date) end);
  if v_used > v_award."units" and v_used - v_row."units" <= v_award."units" then
    perform "better_supabase".emit_event('funding_award.exceeded', jsonb_build_object('organizationId', v_award."tenant_id", 'fundingAwardId', v_award."id", 'fundingProductId', v_award."product_id", 'funderId', v_award."funder_id", 'subjectType', v_award."subject_type", 'subjectId', v_award."subject_id", 'status', v_award."status", 'periodStart', v_start, 'awarded', v_award."units", 'used', v_used), 'funding-awards/' || v_award."id"::text, (v_award."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_award.exceeded',
    category => 'data',
    target_type => 'funding_award',
    record_id => v_award."id"::text,
    summary => 'Funding award exceeded',
    tenant => (v_award."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_award."tenant_id", 'fundingAwardId', v_award."id", 'fundingProductId', v_award."product_id", 'funderId', v_award."funder_id", 'subjectType', v_award."subject_type", 'subjectId', v_award."subject_id", 'status', v_award."status", 'periodStart', v_start, 'awarded', v_award."units", 'used', v_used)
  );
    if better_supabase.import_run() is null then
      v_claims := current_setting('request.jwt.claims', true);
      perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
      perform "better_supabase"."notify"(jsonb_build_object(
      'type', 'funding_award.exceeded',
      'tenant', v_award."tenant_id",
      'actor', (select auth.uid()),
      'subject_type', v_award."subject_type",
      'subject_id', v_award."subject_id"::text,
      'summary', 'A funding award went over its units',
      'permission', 'funding.manage',
      'watchers', false,
      'key', 'funding-exceeded:' || v_award."id"::text || ':' || v_start::text,
      'data', jsonb_build_object('awardId', v_award."id", 'periodStart', v_start, 'awarded', v_award."units", 'used', v_used)
    ));
      perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
    end if;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_delivery_register"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) to authenticated, service_role;

-- Approves registered deliveries for a claim (approved true) or rejects them.
-- A delivery a claim holds can't change. Returns how many changed.
create or replace function "better_supabase"."approve_funding_deliveries"(ids uuid[], approved boolean default true)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_status text := case when coalesce(approve_funding_deliveries.approved, true) then 'approved' else 'rejected' end;
  v_found integer := 0;
  v_changed integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    select * from "better_supabase"."funding_deliveries" x
    where x."id" = any (coalesce(approve_funding_deliveries.ids, '{}'::uuid[]))
    order by x."id"
    for update
  loop
    v_found := v_found + 1;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.approve'), false)) then
      raise exception 'not allowed to approve funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
    end if;
    if v_row."status" = 'claimed' then
      raise exception 'a claim holds this delivery' using errcode = '22023', hint = 'FUNDING_DELIVERY_CLAIMED';
    end if;
    if v_row."status" <> v_status then
      update "better_supabase"."funding_deliveries" x set "status" = v_status where x."id" = v_row."id";
      v_changed := v_changed + 1;
    end if;
  end loop;
  if v_found < (select count(distinct i) from unnest(coalesce(approve_funding_deliveries.ids, '{}'::uuid[])) i) then
    raise exception 'funding delivery not found' using errcode = 'P0002', hint = 'FUNDING_DELIVERY_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) to authenticated, service_role;

-- The deliveries of an organization, newest first. filter holds awardId,
-- status, since and until (days), and limit (500 by default, 1000 at most).
create or replace function "better_supabase"."list_funding_deliveries"(tenant uuid, filter jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.row order by z.day desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'awardId', x."award_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'deliveredOn', x."delivered_on", 'units', x."units", 'performerId', x."performer_id", 'status', x."status", 'claimLineId', x."claim_line_id", 'note', x."note", 'createdAt', x."created_at") as row, x."delivered_on" as day, x."id" as id
    from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = list_funding_deliveries.tenant
      and (list_funding_deliveries.filter ->> 'awardId' is null or x."award_id" = (list_funding_deliveries.filter ->> 'awardId')::uuid)
      and (list_funding_deliveries.filter ->> 'status' is null or x."status" = list_funding_deliveries.filter ->> 'status')
      and (list_funding_deliveries.filter ->> 'since' is null or x."delivered_on" >= (list_funding_deliveries.filter ->> 'since')::date)
      and (list_funding_deliveries.filter ->> 'until' is null or x."delivered_on" <= (list_funding_deliveries.filter ->> 'until')::date)
    order by x."delivered_on" desc, x."id"
    limit least(greatest(coalesce((list_funding_deliveries.filter ->> 'limit')::integer, 500), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) to authenticated, service_role;

-- Registers the approved time entries that started from since to until (days
-- in the time-tracking zone) as deliveries. An entry delivers on the active
-- award of its record; an
-- entry with no award, or with several, is returned as unmatched. Minutes and
-- hours count the entry's duration; other units count one per entry. An entry
-- registered before is skipped, so the import can run again.
create or replace function "better_supabase"."register_funding_deliveries_from_time"(tenant uuid, since date, until date)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_entry record;
  v_awards uuid[];
  v_units numeric;
  v_award uuid;
  v_unit text;
  v_delivery jsonb;
  v_registered jsonb := '[]'::jsonb;
  v_unmatched jsonb := '[]'::jsonb;
begin
  if register_funding_deliveries_from_time.since is null or register_funding_deliveries_from_time.until is null
    or register_funding_deliveries_from_time.until < register_funding_deliveries_from_time.since then
    raise exception 'since and until are days, until on or after since' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_entry in
    select x."id"::text as id, x."subject_type" as subject_type, x."subject_id"::text as subject_id,
      (x."started_at" at time zone 'UTC')::date as day,
      extract(epoch from x."ended_at" - x."started_at") as seconds,
      x."user_id" as performer, null::text as category
    from "better_supabase"."time_entries" x
    where x."tenant_id" = register_funding_deliveries_from_time.tenant
      and x."ended_at" is not null
      and x."subject_type" is not null
      and x."started_at" >= (register_funding_deliveries_from_time.since::timestamp at time zone 'UTC')
      and x."started_at" < ((register_funding_deliveries_from_time.until + 1)::timestamp at time zone 'UTC')
      and exists (
        select 1 from "better_supabase"."timesheets" s
        where s."tenant_id" = x."tenant_id" and s."user_id" = x."user_id"
          and s."week" = "better_supabase"."time_week"(x."started_at") and s."approved_at" is not null
      )
      and not exists (
        select 1 from "better_supabase"."funding_deliveries" z
        where z."tenant_id" = x."tenant_id" and z."source_type" = 'time_entry' and z."source_id" = x."id"::text
      )
    order by x."started_at", x."id"
  loop
    select array_agg(a."id" order by a."id"), min(y."unit") into v_awards, v_unit
    from "better_supabase"."funding_awards" a
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where a."tenant_id" = register_funding_deliveries_from_time.tenant
      and a."subject_type" = v_entry.subject_type and a."subject_id" = v_entry.subject_id
      and a."status" = 'active'
      and v_entry.day >= a."starts_on" and v_entry.day <= coalesce(a."ends_on", v_entry.day)
      and (y."valid_from" is null or v_entry.day >= y."valid_from")
      and (y."valid_until" is null or v_entry.day <= y."valid_until");
    if coalesce(cardinality(v_awards), 0) <> 1 then
      v_unmatched := v_unmatched || jsonb_build_array(jsonb_build_object(
        'entryId', v_entry.id,
        'subjectType', v_entry.subject_type,
        'subjectId', v_entry.subject_id,
        'deliveredOn', v_entry.day,
        'reason', case when coalesce(cardinality(v_awards), 0) = 0 then 'no_award' else 'several_awards' end
      ));
      continue;
    end if;
    v_award := v_awards[1];
    v_units := case v_unit
      when 'minute' then round(v_entry.seconds / 60, 2)
      when 'hour' then round(v_entry.seconds / 3600, 4)
      else 1
    end;
    if v_units <= 0 then
      v_unmatched := v_unmatched || jsonb_build_array(jsonb_build_object(
        'entryId', v_entry.id,
        'subjectType', v_entry.subject_type,
        'subjectId', v_entry.subject_id,
        'deliveredOn', v_entry.day,
        'reason', 'no_duration'
      ));
      continue;
    end if;
    v_delivery := "better_supabase"."register_funding_delivery"(v_award, v_entry.day, v_units, 'time_entry', v_entry.id, v_entry.performer, null);
    v_registered := v_registered || jsonb_build_array(v_delivery);
  end loop;
  return jsonb_build_object('registered', v_registered, 'unmatched', v_unmatched);
end;
$$;
revoke execute on function "better_supabase"."register_funding_deliveries_from_time"(uuid, date, date) from public, anon, authenticated;
grant execute on function "better_supabase"."register_funding_deliveries_from_time"(uuid, date, date) to service_role;

-- Gathers the approved deliveries of a funder from period_start to
-- period_end into a draft claim in format (a FundingClaimFormat key), one
-- line per award, priced at the product rate. The deliveries become claimed.
create or replace function "better_supabase"."build_funding_claim"(tenant uuid, funder_id uuid, period_start date, period_end date, format text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_format text := nullif(trim(build_funding_claim.format), '');
  v_currencies integer;
  v_currency text;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', build_funding_claim.tenant, 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_format is null or v_format !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'the claim format isn''t one this organization claims in' using errcode = '22023', hint = 'FUNDING_FORMAT_UNKNOWN';
  end if;
  if build_funding_claim.funder_id is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if build_funding_claim.period_start is null or build_funding_claim.period_end is null
    or build_funding_claim.period_end < build_funding_claim.period_start then
    raise exception 'a claim period ends on or after it starts' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_claim_build"(uuid, uuid, date, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date, $4::date)', v_hook::oid::regproc)
        using build_funding_claim.tenant, build_funding_claim.funder_id, build_funding_claim.period_start, build_funding_claim.period_end;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb_funding_claim:' || build_funding_claim.tenant::text, 0));
  perform 1 from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  for update of x;
  select count(distinct y."currency"), min(y."currency") into v_currencies, v_currency
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  if v_currencies = 0 then
    raise exception 'no approved deliveries of this funder in the period' using errcode = '22023', hint = 'FUNDING_CLAIM_EMPTY';
  end if;
  if v_currencies > 1 then
    raise exception 'the deliveries are priced in several currencies; claim each product''s currency apart' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  select coalesce(max(x."number"::bigint) filter (where x."number" ~ '^[0-9]{1,18}$'), 0) + 1 into v_seq
  from "better_supabase"."funding_claims" x where x."tenant_id" = build_funding_claim.tenant;
  v_number := v_seq::text;
  insert into "better_supabase"."funding_claims" ("tenant_id", "funder_id", "number", "period_start", "period_end", "format", "currency", "created_by")
  values (build_funding_claim.tenant, build_funding_claim.funder_id, v_number, build_funding_claim.period_start, build_funding_claim.period_end, v_format, v_currency, (select auth.uid()))
  returning * into v_claim;
  insert into "better_supabase"."funding_claim_lines" ("tenant_id", "claim_id", "award_id", "product_id", "units", "amount")
  select build_funding_claim.tenant, v_claim."id", a."id", y."id", sum(x."units"), round(sum(x."units") * y."rate")::bigint
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  group by a."id", y."id", y."rate";
  update "better_supabase"."funding_deliveries" x set "status" = 'claimed', "claim_line_id" = z."id"
  from "better_supabase"."funding_claim_lines" z
  where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
    and x."tenant_id" = z."tenant_id" and x."award_id" = z."award_id"
    and x."status" = 'approved' and x."claim_line_id" is null
    and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  update "better_supabase"."funding_claims" x set "total" = (
    select coalesce(sum(z."amount"), 0) from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  )
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  perform "better_supabase".emit_event('funding_claim.created', jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency"), 'funding-claims/' || v_claim."id"::text, (v_claim."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.created',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_claim."id"::text,
    summary => 'Funding claim built',
    tenant => (v_claim."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency")
  );
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_claim_build"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_claim."id";
    end if;
  end;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) from public, anon;
grant execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) to authenticated, service_role;

-- A claim with its lines, each with its award, product and deliveries: what a
-- FundingClaimFormat renders.
create or replace function "better_supabase"."get_funding_claim"(claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = get_funding_claim.claim_id;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.read'), false)) then
    raise exception 'not allowed to read funding claims' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."get_funding_claim"(uuid) to authenticated, service_role;

-- Marks a draft claim sent, with the channel's reference and the SHA-256 of
-- the file that was sent.
create or replace function "better_supabase"."mark_funding_claim_sent"(claim_id uuid, external_ref text default null, payload_sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_ref text := nullif(trim(mark_funding_claim_sent.external_ref), '');
  v_sha text := lower(nullif(trim(mark_funding_claim_sent.payload_sha256), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = mark_funding_claim_sent.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'external_ref is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'payload_sha256 is a SHA-256 in hex' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  update "better_supabase"."funding_claims" x set "status" = 'sent', "sent_at" = now(), "external_ref" = v_ref, "payload_sha256" = v_sha, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  perform "better_supabase".emit_event('funding_claim.sent', jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'externalRef', v_claim."external_ref"), 'funding-claims/' || v_claim."id"::text, (v_claim."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.sent',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_claim."id"::text,
    summary => 'Funding claim sent',
    tenant => (v_claim."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'externalRef', v_claim."external_ref")
  );
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at");
end;
$$;
revoke execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) to authenticated, service_role;

-- Records the funder's response to a sent claim: lines is an array of
-- { lineId, status (accepted or rejected), rejectionCode }, or null for
-- none. A line the response leaves out is accepted. The deliveries of a rejected line go back
-- to approved, for correction and a later claim.
create or replace function "better_supabase"."record_funding_claim_response"(claim_id uuid, lines jsonb, response jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_line jsonb;
  v_status text;
  v_code text;
  v_accepted integer;
  v_rejected integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = record_funding_claim_response.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'sent' then
    raise exception 'only a sent claim takes a response' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if jsonb_typeof(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) <> 'array' then
    raise exception 'lines is an array' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_line in select value from jsonb_array_elements(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) loop
    v_status := v_line ->> 'status';
    v_code := nullif(trim(v_line ->> 'rejectionCode'), '');
    if jsonb_typeof(v_line) <> 'object' or v_status is null or v_status not in ('accepted', 'rejected') then
      raise exception 'each line has a lineId and a status of accepted or rejected' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_code is not null and length(v_code) > 100 then
      raise exception 'a rejection code is at most 100 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    update "better_supabase"."funding_claim_lines" x set "status" = v_status, "rejection_code" = case when v_status = 'rejected' then v_code end
    where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id"
      and x."id"::text = v_line ->> 'lineId';
    if not found then
      raise exception 'a line in the response isn''t a line of this claim' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end loop;
  update "better_supabase"."funding_claim_lines" x set "status" = 'accepted'
  where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id" and x."status" = 'pending';
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id" and z."status" = 'rejected');
  select count(*) filter (where z."status" = 'accepted'), count(*) filter (where z."status" = 'rejected')
  into v_accepted, v_rejected
  from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id";
  update "better_supabase"."funding_claims" x set
    "status" = case when v_rejected = 0 then 'accepted' when v_accepted = 0 then 'rejected' else 'partially_accepted' end,
    "response" = record_funding_claim_response.response, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  perform "better_supabase".emit_event('funding_claim.responded', jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency"), 'funding-claims/' || v_claim."id"::text, (v_claim."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.responded',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_claim."id"::text,
    summary => 'Funding claim response recorded',
    tenant => (v_claim."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency")
  );
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Deletes a draft claim; its deliveries go back to approved.
create or replace function "better_supabase"."delete_funding_claim"(claim_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = delete_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id");
  delete from "better_supabase"."funding_claims" x where x."id" = v_claim."id";
  perform "better_supabase".emit_event('funding_claim.deleted', jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency"), 'funding-claims/' || v_claim."id"::text, (v_claim."tenant_id")::text, null, 'better-supabase/funding');
  perform better_supabase.audit_event(
    event_type => 'funding_claim.deleted',
    category => 'data',
    target_type => 'funding_claim',
    record_id => v_claim."id"::text,
    summary => 'Draft funding claim deleted',
    tenant => (v_claim."tenant_id")::uuid,
    metadata => jsonb_build_object('organizationId', v_claim."tenant_id", 'fundingClaimId', v_claim."id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'status', v_claim."status", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'total', v_claim."total"::text, 'currency', v_claim."currency")
  );
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_funding_claim"(uuid) to authenticated, service_role;

-- Invoices the funder for the accepted lines of a claim, through
-- create_invoice: one invoice line per claim line at the product rate. attrs
-- goes to create_invoice (title, termsDays, note); a claim is invoiced once.
create or replace function "better_supabase"."invoice_funding_claim"(claim_id uuid, attrs jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_party jsonb;
  v_lines jsonb;
  v_invoice jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = invoice_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" not in ('accepted', 'partially_accepted') then
    raise exception 'only a claim the funder accepted is invoiced' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if v_claim."invoice_id" is not null then
    raise exception 'the funding claim is invoiced already' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  v_party := case
    when exists (select 1 from "better_supabase"."companies" x where x."id" = v_claim."funder_id")
      then jsonb_build_object('company', jsonb_build_object('id', v_claim."funder_id"))
    else jsonb_build_object('contact', jsonb_build_object('id', v_claim."funder_id"))
  end;
  select coalesce(jsonb_agg(jsonb_build_object(
    'description', y."code" || ' ' || y."title",
    'quantity', z."units",
    'unitAmount', y."rate"::text
  ) order by y."code", z."id"), '[]'::jsonb) into v_lines
  from "better_supabase"."funding_claim_lines" z
  join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
  where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id" and z."status" = 'accepted';
  v_invoice := "better_supabase"."create_invoice"(v_claim."tenant_id",
    v_party || (coalesce(invoice_funding_claim.attrs, '{}'::jsonb) - 'origin' - 'company' - 'contact') || jsonb_build_object('currency', v_claim."currency",
      'title', coalesce(nullif(trim(invoice_funding_claim.attrs ->> 'title'), ''), 'Funding claim ' || v_claim."number")),
    v_lines);
  update "better_supabase"."funding_claims" x set "invoice_id" = (v_invoice ->> 'id')::uuid, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  return jsonb_build_object('claim', jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at"), 'invoice', v_invoice);
end;
$$;
revoke execute on function "better_supabase"."invoice_funding_claim"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."invoice_funding_claim"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_claims"(tenant uuid, status text default null, funder_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'funderId', x."funder_id", 'number', x."number", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'format', x."format", 'status', x."status", 'externalRef', x."external_ref", 'sentAt', x."sent_at", 'payloadSha256', x."payload_sha256", 'response', x."response", 'total', x."total"::text, 'currency', x."currency", 'invoiceId', x."invoice_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."number" desc), '[]'::jsonb)
  from "better_supabase"."funding_claims" x
  where x."tenant_id" = list_funding_claims.tenant
    and (list_funding_claims.status is null or x."status" = list_funding_claims.status)
    and (list_funding_claims.funder_id is null or x."funder_id" = list_funding_claims.funder_id)
$$;
revoke execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
create policy bsb_tenant_scope_select on "better_supabase"."funding_products" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_products" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
create policy bsb_tenant_scope_update on "better_supabase"."funding_products" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_products" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_select on "better_supabase"."funding_awards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_awards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_update on "better_supabase"."funding_awards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_awards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_select on "better_supabase"."funding_deliveries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_deliveries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_update on "better_supabase"."funding_deliveries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_deliveries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claims" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claim_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claim_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines" as restrictive
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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block-data funding
-- @bsb-hash sha256:5f2aaa76a9d6c8414def54826e938bc7edcce178f14b0d9edd894653bfab3d11
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block funding@1 managed
-- @bsb-hash sha256:646067f3b59bac78523894ed47e5c4114216e0e1426dbe97b4029b5a30633c0c
-- Products a funder pays for, awards of units per period to a record from a funder in contacts, care delivered against an award from time entries, bookings or by hand, usage against the award per period, and claims per funder and period with the funder's response per line, rendered and sent through app-supplied formats and channels.
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
    drop policy if exists bsb_tenant_scope on "app_private"."funding_products";
    drop policy if exists bsb_tenant_scope_select on "app_private"."funding_products";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_products";
    drop policy if exists bsb_tenant_scope_update on "app_private"."funding_products";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."funding_awards";
    drop policy if exists bsb_tenant_scope_select on "app_private"."funding_awards";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_awards";
    drop policy if exists bsb_tenant_scope_update on "app_private"."funding_awards";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_awards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_select on "app_private"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_update on "app_private"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."funding_claims";
    drop policy if exists bsb_tenant_scope_select on "app_private"."funding_claims";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_claims";
    drop policy if exists bsb_tenant_scope_update on "app_private"."funding_claims";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_claims";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_select on "app_private"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_update on "app_private"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_claim_lines";
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
-- Funding: the products a funder pays for, awards of units per period to a
-- record, the care delivered against them, and claims to the funder with its
-- response per line.

create table if not exists "app_private"."funding_products" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The funder's product code, such as 45A48 for a Wlz product.
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 300),
  "unit" text not null check ("unit" in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece')),
  -- The price of one unit, in minor units of currency.
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "valid_from" date,
  "valid_until" date,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("valid_until" is null or "valid_from" is null or "valid_until" >= "valid_from"),
  unique ("tenant_id", "id")
);
create unique index if not exists "funding_products_code_idx" on "app_private"."funding_products" ("tenant_id", "code");
alter table "app_private"."funding_products" enable row level security;
revoke all on "app_private"."funding_products" from public, anon, authenticated;
grant select on "app_private"."funding_products" to authenticated;
grant all on "app_private"."funding_products" to service_role;
drop policy if exists funding_products_read on "app_private"."funding_products";
create policy funding_products_read on "app_private"."funding_products"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "app_private"."funding_awards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The record the award is for, a type in config.subjects.
  "subject_type" text not null,
  "subject_id" text not null,
  -- The contacts company or person that pays, holding the funder role.
  "funder_id" uuid not null,
  "product_id" uuid not null,
  -- The units awarded per period.
  "units" numeric not null check ("units" > 0),
  "period" text not null check ("period" in ('week', 'month', 'total')),
  "starts_on" date not null,
  "ends_on" date,
  -- The funder's reference for the award, such as an indication number.
  "reference" text check ("reference" is null or length("reference") <= 200),
  "status" text not null default 'active' check ("status" in ('requested', 'active', 'ended', 'canceled')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_on" is null or "ends_on" >= "starts_on"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "product_id") references "app_private"."funding_products" ("tenant_id", "id")
);
create index if not exists "funding_awards_product_idx" on "app_private"."funding_awards" ("tenant_id", "product_id");
create index if not exists "funding_awards_subject_idx" on "app_private"."funding_awards" ("subject_type", "subject_id");
create index if not exists "funding_awards_funder_idx" on "app_private"."funding_awards" ("tenant_id", "funder_id", "status");
alter table "app_private"."funding_awards" enable row level security;
revoke all on "app_private"."funding_awards" from public, anon, authenticated;
grant select on "app_private"."funding_awards" to authenticated;
grant all on "app_private"."funding_awards" to service_role;
drop policy if exists funding_awards_read on "app_private"."funding_awards";
create policy funding_awards_read on "app_private"."funding_awards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

create table if not exists "app_private"."funding_claims" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "funder_id" uuid not null,
  "number" text not null check (length("number") between 1 and 100),
  "period_start" date not null,
  "period_end" date not null,
  -- The FundingClaimFormat key that renders the claim, such as iwlz-aw319.
  "format" text not null check ("format" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'accepted', 'partially_accepted', 'rejected')),
  -- The funder's or the channel's reference for the sent claim.
  "external_ref" text check ("external_ref" is null or length("external_ref") <= 200),
  "sent_at" timestamptz,
  -- The SHA-256 of the rendered file that was sent, in hex.
  "payload_sha256" text check ("payload_sha256" is null or "payload_sha256" ~ '^[0-9a-f]{64}$'),
  -- The funder's response as the format parsed it.
  "response" jsonb,
  "total" bigint not null default 0,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  unique ("tenant_id", "id")
);
create unique index if not exists "funding_claims_number_idx" on "app_private"."funding_claims" ("tenant_id", "number");
create index if not exists "funding_claims_funder_idx" on "app_private"."funding_claims" ("tenant_id", "funder_id", "status");
alter table "app_private"."funding_claims" enable row level security;
revoke all on "app_private"."funding_claims" from public, anon, authenticated;
grant select on "app_private"."funding_claims" to authenticated;
grant all on "app_private"."funding_claims" to service_role;
drop policy if exists funding_claims_read on "app_private"."funding_claims";
create policy funding_claims_read on "app_private"."funding_claims"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "app_private"."funding_claim_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "claim_id" uuid not null,
  "award_id" uuid not null,
  "product_id" uuid not null,
  "units" numeric not null check ("units" > 0),
  -- The units times the product rate, in minor units of the claim currency.
  "amount" bigint not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'accepted', 'rejected')),
  -- The funder's code for a rejected line.
  "rejection_code" text check ("rejection_code" is null or length("rejection_code") <= 100),
  foreign key ("tenant_id", "claim_id") references "app_private"."funding_claims" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "award_id") references "app_private"."funding_awards" ("tenant_id", "id"),
  foreign key ("tenant_id", "product_id") references "app_private"."funding_products" ("tenant_id", "id")
);
create index if not exists "funding_claim_lines_claim_idx" on "app_private"."funding_claim_lines" ("tenant_id", "claim_id");
create index if not exists "funding_claim_lines_award_idx" on "app_private"."funding_claim_lines" ("tenant_id", "award_id");
create index if not exists "funding_claim_lines_product_idx" on "app_private"."funding_claim_lines" ("tenant_id", "product_id");
alter table "app_private"."funding_claim_lines" enable row level security;
revoke all on "app_private"."funding_claim_lines" from public, anon, authenticated;
grant select on "app_private"."funding_claim_lines" to authenticated;
grant all on "app_private"."funding_claim_lines" to service_role;
drop policy if exists funding_claim_lines_read on "app_private"."funding_claim_lines";
create policy funding_claim_lines_read on "app_private"."funding_claim_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "app_private"."funding_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "award_id" uuid not null,
  -- Where the delivery came from; source_id is the time entry or booking id.
  "source_type" text not null default 'manual' check ("source_type" in ('time_entry', 'booking', 'manual')),
  "source_id" text check ("source_id" is null or length("source_id") <= 200),
  "delivered_on" date not null,
  "units" numeric not null check ("units" > 0),
  "performer_id" uuid,
  "status" text not null default 'registered' check ("status" in ('registered', 'approved', 'claimed', 'rejected')),
  -- The claim line that claims it, once a claim gathered it.
  "claim_line_id" uuid references "app_private"."funding_claim_lines" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  check ("source_type" = 'manual' or "source_id" is not null),
  foreign key ("tenant_id", "award_id") references "app_private"."funding_awards" ("tenant_id", "id") on delete cascade
);
create index if not exists "funding_deliveries_award_idx" on "app_private"."funding_deliveries" ("tenant_id", "award_id", "delivered_on");
create index if not exists "funding_deliveries_status_idx" on "app_private"."funding_deliveries" ("tenant_id", "status", "delivered_on");
create index if not exists "funding_deliveries_claim_line_idx" on "app_private"."funding_deliveries" ("claim_line_id");
create unique index if not exists "funding_deliveries_source_idx" on "app_private"."funding_deliveries" ("tenant_id", "source_type", "source_id") where "source_id" is not null;
alter table "app_private"."funding_deliveries" enable row level security;
revoke all on "app_private"."funding_deliveries" from public, anon, authenticated;
grant select on "app_private"."funding_deliveries" to authenticated;
grant all on "app_private"."funding_deliveries" to service_role;
drop policy if exists funding_deliveries_read on "app_private"."funding_deliveries";
create policy funding_deliveries_read on "app_private"."funding_deliveries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "app_private"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)));

-- Adds a product a funder pays for, or changes one (product_id): its code,
-- unit and rate in minor units. The code is unique in the organization.
create or replace function "app_private"."save_funding_product"(tenant uuid, code text, title text, unit text, rate bigint, currency text, valid_from date default null, valid_until date default null, product_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."funding_products"%rowtype;
  v_code text := nullif(trim(save_funding_product.code), '');
  v_title text := nullif(trim(save_funding_product.title), '');
  v_unit text := nullif(trim(save_funding_product.unit), '');
  v_currency text := upper(nullif(trim(save_funding_product.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_product.tenant, 'funding.manage'), false)) then
    raise exception 'not allowed to manage funding products' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_code is null or length(v_code) > 50 then
    raise exception 'a product needs a code of at most 50 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_title is null or length(v_title) > 300 then
    raise exception 'a product needs a title of at most 300 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_unit is null or v_unit not in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece') then
    raise exception 'unit is minute, hour, day_part, day, visit or piece' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.rate is null or save_funding_product.rate < 0 then
    raise exception 'a rate is zero or more minor units' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.valid_until < save_funding_product.valid_from then
    raise exception 'a product is valid until on or after it is valid from' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if exists (
    select 1 from "app_private"."funding_products" x
    where x."tenant_id" = save_funding_product.tenant and x."code" = v_code
      and x."id" is distinct from save_funding_product.product_id
  ) then
    raise exception 'the organization already has a funding product with this code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.product_id is null then
    insert into "app_private"."funding_products" ("tenant_id", "code", "title", "unit", "rate", "currency", "valid_from", "valid_until")
    values (save_funding_product.tenant, v_code, v_title, v_unit, save_funding_product.rate, v_currency, save_funding_product.valid_from, save_funding_product.valid_until)
    returning * into v_row;
  else
    update "app_private"."funding_products" x set
      "code" = v_code,
      "title" = v_title,
      "unit" = v_unit,
      "rate" = save_funding_product.rate,
      "currency" = v_currency,
      "valid_from" = save_funding_product.valid_from,
      "valid_until" = save_funding_product.valid_until, "updated_at" = now()
    where x."id" = save_funding_product.product_id and x."tenant_id" = save_funding_product.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'title', v_row."title", 'unit', v_row."unit", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) from public, anon;
grant execute on function "app_private"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) to authenticated, service_role;

create or replace function "app_private"."list_funding_products"(tenant uuid, include_expired boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'title', x."title", 'unit', x."unit", 'rate', x."rate"::text, 'currency', x."currency", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code", x."id"), '[]'::jsonb)
  from "app_private"."funding_products" x
  where x."tenant_id" = list_funding_products.tenant
    and (coalesce(list_funding_products.include_expired, false) or x."valid_until" is null or x."valid_until" >= current_date)
$$;
revoke execute on function "app_private"."list_funding_products"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_funding_products"(uuid, boolean) to authenticated, service_role;

-- Awards units of a product per period to a record, from a funder in
-- contacts, or changes an award (award_id); a key attrs leaves out keeps its
-- value. attrs holds funderId, productId, units, period (week, month or
-- total), startsOn, endsOn, reference, status (requested or active) and
-- fields, the extra columns by name.
create or replace function "app_private"."save_funding_award"(tenant uuid, subject_type text, subject_id text, attrs jsonb, award_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."funding_awards"%rowtype;
  v_attrs jsonb := coalesce(save_funding_award.attrs, '{}'::jsonb);
  v_funder uuid;
  v_product uuid;
  v_units numeric;
  v_period text;
  v_starts date;
  v_ends date;
  v_reference text;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_award.tenant, 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  
  if save_funding_award.award_id is null then
    if not false then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else null end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else null end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else null end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else null end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else null end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else null end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else null end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else 'active' end;
  else
    select * into v_row from "app_private"."funding_awards" x
    where x."id" = save_funding_award.award_id and x."tenant_id" = save_funding_award.tenant
    for update;
    if not found then
      raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
    end if;
    if v_row."subject_type" <> save_funding_award.subject_type or v_row."subject_id" <> save_funding_award.subject_id then
      raise exception 'an award stays with its record' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_row."status" in ('ended', 'canceled') then
      raise exception 'the funding award has ended' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else v_row."funder_id" end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else v_row."product_id" end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else v_row."units" end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else v_row."period" end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else v_row."ends_on" end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else v_row."reference" end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else v_row."status" end;
  end if;
  if v_funder is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if v_product is null or not exists (select 1 from "app_private"."funding_products" x where x."id" = v_product and x."tenant_id" = save_funding_award.tenant) then
    raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
  end if;
  if v_units is null or v_units <= 0 then
    raise exception 'an award needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_period is null or v_period not in ('week', 'month', 'total') then
    raise exception 'period is week, month or total' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an award needs a start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an award ends on or after its start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_reference is not null and length(v_reference) > 200 then
    raise exception 'reference is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_status is null or v_status not in ('requested', 'active') then
    raise exception 'a saved award is requested or active; end_funding_award ends it' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_award_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_attrs;
    end if;
  end;
  if save_funding_award.award_id is null then
    insert into "app_private"."funding_awards" ("tenant_id", "subject_type", "subject_id", "funder_id", "product_id", "units", "period", "starts_on", "ends_on", "reference", "status", "created_by")
    values (save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_funder, v_product, v_units, v_period, v_starts, v_ends, v_reference, v_status, (select auth.uid()))
    returning * into v_row;
    null;
  else
    update "app_private"."funding_awards" x set
    "funder_id" = v_funder,
    "product_id" = v_product,
    "units" = v_units,
    "period" = v_period,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "reference" = v_reference,
    "status" = v_status, "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_award_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_funding_award"(uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function "app_private"."save_funding_award"(uuid, text, text, jsonb, uuid) to authenticated, service_role;

-- Ends an award on ends_on (today by default), or cancels it (canceled).
-- Deliveries already registered stay.
create or replace function "app_private"."end_funding_award"(award_id uuid, ends_on date default null, canceled boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."funding_awards"%rowtype;
  v_ends date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."funding_awards" x where x."id" = end_funding_award.award_id for update;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_row."status" in ('ended', 'canceled') then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  v_ends := case
    when coalesce(end_funding_award.canceled, false) then coalesce(end_funding_award.ends_on, v_row."ends_on")
    else coalesce(end_funding_award.ends_on, least(current_date, coalesce(v_row."ends_on", current_date)))
  end;
  if v_ends is not null and v_ends < v_row."starts_on" then
    if coalesce(end_funding_award.canceled, false) then
      v_ends := null;
    else
      raise exception 'an award ends on or after its start date; cancel it instead' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end if;
  update "app_private"."funding_awards" x set
    "status" = case when coalesce(end_funding_award.canceled, false) then 'canceled' else 'ended' end,
    "ends_on" = v_ends, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."end_funding_award"(uuid, date, boolean) from public, anon;
grant execute on function "app_private"."end_funding_award"(uuid, date, boolean) to authenticated, service_role;

create or replace function "app_private"."list_funding_awards"(tenant uuid, subject_type text default null, subject_id text default null, include_ended boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'funderId', x."funder_id", 'productId', x."product_id", 'units', x."units", 'period', x."period", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'reference', x."reference", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('product', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text, 'currency', y."currency", 'validFrom', y."valid_from", 'validUntil', y."valid_until", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "app_private"."funding_awards" x
  join "app_private"."funding_products" y on y."tenant_id" = x."tenant_id" and y."id" = x."product_id"
  where x."tenant_id" = list_funding_awards.tenant
    and (list_funding_awards.subject_type is null or x."subject_type" = list_funding_awards.subject_type)
    and (list_funding_awards.subject_id is null or x."subject_id" = list_funding_awards.subject_id)
    and (coalesce(list_funding_awards.include_ended, false) or x."status" in ('requested', 'active'))
$$;
revoke execute on function "app_private"."list_funding_awards"(uuid, text, text, boolean) from public, anon;
grant execute on function "app_private"."list_funding_awards"(uuid, text, text, boolean) to authenticated, service_role;

-- The units used against the units awarded, per period of the award from its
-- start to its end (today while it runs). Rejected deliveries don't count.
create or replace function "app_private"."funding_award_usage"(award_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'awardId', a."id",
    'units', a."units",
    'period', a."period",
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', s.start,
        'end', nullif(s.finish, 'infinity'::date) - 1,
        'awarded', a."units",
        'used', s.used,
        'over', greatest(s.used - a."units", 0),
        'under', greatest(a."units" - s.used, 0)
      ) order by s.start)
      from (
        select g.start, (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end) as finish, (
          select coalesce(sum(x."units"), 0) from "app_private"."funding_deliveries" x
          where x."tenant_id" = a."tenant_id" and x."award_id" = a."id" and x."status" <> 'rejected'
            and x."delivered_on" >= g.start and x."delivered_on" < (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end)
        ) as used
        from (
          select pg_catalog.generate_series(
            (case a."period" when 'week' then date_trunc('week', a."starts_on")::date when 'month' then date_trunc('month', a."starts_on")::date else a."starts_on" end)::timestamp,
            coalesce(a."ends_on", current_date)::timestamp,
            case a."period" when 'week' then interval '1 week' else interval '1 month' end
          )::date as start
          where a."period" <> 'total'
          union all
          select a."starts_on" where a."period" = 'total'
        ) g
      ) s
    ), '[]'::jsonb)
  )
  from "app_private"."funding_awards" a
  where a."id" = funding_award_usage.award_id
$$;
revoke execute on function "app_private"."funding_award_usage"(uuid) from public, anon;
grant execute on function "app_private"."funding_award_usage"(uuid) to authenticated, service_role;

-- Registers care delivered on an award: units on a day, from a time entry, a
-- booking or by hand (manual). A source registered before returns its
-- delivery, so registering it twice is safe. Crossing the units of a period
-- emits funding_award.exceeded.
create or replace function "app_private"."register_funding_delivery"(award_id uuid, delivered_on date, units numeric, source_type text default 'manual', source_id text default null, performer_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."funding_deliveries"%rowtype;
  v_award "app_private"."funding_awards"%rowtype;
  v_product "app_private"."funding_products"%rowtype;
  v_source text := coalesce(nullif(trim(register_funding_delivery.source_type), ''), 'manual');
  v_source_id text := nullif(trim(register_funding_delivery.source_id), '');
  v_note text := nullif(trim(register_funding_delivery.note), '');
  v_start date;
  v_used numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_award from "app_private"."funding_awards" x where x."id" = register_funding_delivery.award_id;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_award."tenant_id", 'funding.register'), false)) then
    raise exception 'not allowed to register funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_source not in ('time_entry', 'booking', 'manual') then
    raise exception 'source_type is time_entry, booking or manual' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source <> 'manual' and v_source_id is null then
    raise exception 'a delivery from a time entry or booking needs its source_id' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source_id is not null then
    select * into v_row from "app_private"."funding_deliveries" x
    where x."tenant_id" = v_award."tenant_id" and x."source_type" = v_source and x."source_id" = v_source_id;
    if found then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
    end if;
  end if;
  if register_funding_delivery.delivered_on is null then
    raise exception 'a delivery needs the day it was delivered' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if register_funding_delivery.units is null or register_funding_delivery.units <= 0 then
    raise exception 'a delivery needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_award."status" <> 'active'
    or register_funding_delivery.delivered_on < v_award."starts_on"
    or register_funding_delivery.delivered_on > coalesce(v_award."ends_on", register_funding_delivery.delivered_on) then
    raise exception 'the funding award isn''t active on that day' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
  end if;
  select * into v_product from "app_private"."funding_products" x where x."tenant_id" = v_award."tenant_id" and x."id" = v_award."product_id";
  if (v_product."valid_from" is not null and register_funding_delivery.delivered_on < v_product."valid_from")
    or (v_product."valid_until" is not null and register_funding_delivery.delivered_on > v_product."valid_until") then
    raise exception 'the funding product isn''t valid on that day' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_delivery_register"(uuid, date, numeric)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::date, $3::numeric)', v_hook::oid::regproc)
        using v_award."id", register_funding_delivery.delivered_on, register_funding_delivery.units;
    end if;
  end;
  insert into "app_private"."funding_deliveries" ("tenant_id", "award_id", "source_type", "source_id", "delivered_on", "units", "performer_id", "note")
  values (v_award."tenant_id", v_award."id", v_source, v_source_id, register_funding_delivery.delivered_on, register_funding_delivery.units, coalesce(register_funding_delivery.performer_id, (select auth.uid())), v_note)
  returning * into v_row;
  null;
  v_start := (case v_award."period" when 'week' then date_trunc('week', v_row."delivered_on")::date when 'month' then date_trunc('month', v_row."delivered_on")::date else v_award."starts_on" end);
  select coalesce(sum(x."units"), 0) into v_used from "app_private"."funding_deliveries" x
  where x."tenant_id" = v_award."tenant_id" and x."award_id" = v_award."id" and x."status" <> 'rejected'
    and x."delivered_on" >= v_start and x."delivered_on" < (case v_award."period" when 'week' then (v_start + 7) when 'month' then (v_start + interval '1 month')::date else coalesce(v_award."ends_on" + 1, 'infinity'::date) end);
  if v_used > v_award."units" and v_used - v_row."units" <= v_award."units" then
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_delivery_register"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "app_private"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) from public, anon;
grant execute on function "app_private"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) to authenticated, service_role;

-- Approves registered deliveries for a claim (approved true) or rejects them.
-- A delivery a claim holds can't change. Returns how many changed.
create or replace function "app_private"."approve_funding_deliveries"(ids uuid[], approved boolean default true)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "app_private"."funding_deliveries"%rowtype;
  v_status text := case when coalesce(approve_funding_deliveries.approved, true) then 'approved' else 'rejected' end;
  v_found integer := 0;
  v_changed integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    select * from "app_private"."funding_deliveries" x
    where x."id" = any (coalesce(approve_funding_deliveries.ids, '{}'::uuid[]))
    order by x."id"
    for update
  loop
    v_found := v_found + 1;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.approve'), false)) then
      raise exception 'not allowed to approve funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
    end if;
    if v_row."status" = 'claimed' then
      raise exception 'a claim holds this delivery' using errcode = '22023', hint = 'FUNDING_DELIVERY_CLAIMED';
    end if;
    if v_row."status" <> v_status then
      update "app_private"."funding_deliveries" x set "status" = v_status where x."id" = v_row."id";
      v_changed := v_changed + 1;
    end if;
  end loop;
  if v_found < (select count(distinct i) from unnest(coalesce(approve_funding_deliveries.ids, '{}'::uuid[])) i) then
    raise exception 'funding delivery not found' using errcode = 'P0002', hint = 'FUNDING_DELIVERY_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "app_private"."approve_funding_deliveries"(uuid[], boolean) from public, anon;
grant execute on function "app_private"."approve_funding_deliveries"(uuid[], boolean) to authenticated, service_role;

-- The deliveries of an organization, newest first. filter holds awardId,
-- status, since and until (days), and limit (500 by default, 1000 at most).
create or replace function "app_private"."list_funding_deliveries"(tenant uuid, filter jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.row order by z.day desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'awardId', x."award_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'deliveredOn', x."delivered_on", 'units', x."units", 'performerId', x."performer_id", 'status', x."status", 'claimLineId', x."claim_line_id", 'note', x."note", 'createdAt', x."created_at") as row, x."delivered_on" as day, x."id" as id
    from "app_private"."funding_deliveries" x
    where x."tenant_id" = list_funding_deliveries.tenant
      and (list_funding_deliveries.filter ->> 'awardId' is null or x."award_id" = (list_funding_deliveries.filter ->> 'awardId')::uuid)
      and (list_funding_deliveries.filter ->> 'status' is null or x."status" = list_funding_deliveries.filter ->> 'status')
      and (list_funding_deliveries.filter ->> 'since' is null or x."delivered_on" >= (list_funding_deliveries.filter ->> 'since')::date)
      and (list_funding_deliveries.filter ->> 'until' is null or x."delivered_on" <= (list_funding_deliveries.filter ->> 'until')::date)
    order by x."delivered_on" desc, x."id"
    limit least(greatest(coalesce((list_funding_deliveries.filter ->> 'limit')::integer, 500), 1), 1000)
  ) z
$$;
revoke execute on function "app_private"."list_funding_deliveries"(uuid, jsonb) from public, anon;
grant execute on function "app_private"."list_funding_deliveries"(uuid, jsonb) to authenticated, service_role;

-- Gathers the approved deliveries of a funder from period_start to
-- period_end into a draft claim in format (a FundingClaimFormat key), one
-- line per award, priced at the product rate. The deliveries become claimed.
create or replace function "app_private"."build_funding_claim"(tenant uuid, funder_id uuid, period_start date, period_end date, format text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "app_private"."funding_claims"%rowtype;
  v_format text := nullif(trim(build_funding_claim.format), '');
  v_currencies integer;
  v_currency text;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', build_funding_claim.tenant, 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_format is null or v_format !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'the claim format isn''t one this organization claims in' using errcode = '22023', hint = 'FUNDING_FORMAT_UNKNOWN';
  end if;
  if build_funding_claim.funder_id is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if build_funding_claim.period_start is null or build_funding_claim.period_end is null
    or build_funding_claim.period_end < build_funding_claim.period_start then
    raise exception 'a claim period ends on or after it starts' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_claim_build"(uuid, uuid, date, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date, $4::date)', v_hook::oid::regproc)
        using build_funding_claim.tenant, build_funding_claim.funder_id, build_funding_claim.period_start, build_funding_claim.period_end;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb_funding_claim:' || build_funding_claim.tenant::text, 0));
  perform 1 from "app_private"."funding_deliveries" x
    join "app_private"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "app_private"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  for update of x;
  select count(distinct y."currency"), min(y."currency") into v_currencies, v_currency
  from "app_private"."funding_deliveries" x
    join "app_private"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "app_private"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  if v_currencies = 0 then
    raise exception 'no approved deliveries of this funder in the period' using errcode = '22023', hint = 'FUNDING_CLAIM_EMPTY';
  end if;
  if v_currencies > 1 then
    raise exception 'the deliveries are priced in several currencies; claim each product''s currency apart' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  select coalesce(max(x."number"::bigint) filter (where x."number" ~ '^[0-9]{1,18}$'), 0) + 1 into v_seq
  from "app_private"."funding_claims" x where x."tenant_id" = build_funding_claim.tenant;
  v_number := v_seq::text;
  insert into "app_private"."funding_claims" ("tenant_id", "funder_id", "number", "period_start", "period_end", "format", "currency", "created_by")
  values (build_funding_claim.tenant, build_funding_claim.funder_id, v_number, build_funding_claim.period_start, build_funding_claim.period_end, v_format, v_currency, (select auth.uid()))
  returning * into v_claim;
  insert into "app_private"."funding_claim_lines" ("tenant_id", "claim_id", "award_id", "product_id", "units", "amount")
  select build_funding_claim.tenant, v_claim."id", a."id", y."id", sum(x."units"), round(sum(x."units") * y."rate")::bigint
  from "app_private"."funding_deliveries" x
    join "app_private"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "app_private"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  group by a."id", y."id", y."rate";
  update "app_private"."funding_deliveries" x set "status" = 'claimed', "claim_line_id" = z."id"
  from "app_private"."funding_claim_lines" z
  where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
    and x."tenant_id" = z."tenant_id" and x."award_id" = z."award_id"
    and x."status" = 'approved' and x."claim_line_id" is null
    and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  update "app_private"."funding_claims" x set "total" = (
    select coalesce(sum(z."amount"), 0) from "app_private"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  )
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_claim_build"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_claim."id";
    end if;
  end;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "app_private"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "app_private"."funding_claim_lines" z
    join "app_private"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "app_private"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."build_funding_claim"(uuid, uuid, date, date, text) from public, anon;
grant execute on function "app_private"."build_funding_claim"(uuid, uuid, date, date, text) to authenticated, service_role;

-- A claim with its lines, each with its award, product and deliveries: what a
-- FundingClaimFormat renders.
create or replace function "app_private"."get_funding_claim"(claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "app_private"."funding_claims"%rowtype;
begin
  select * into v_claim from "app_private"."funding_claims" x where x."id" = get_funding_claim.claim_id;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.read'), false)) then
    raise exception 'not allowed to read funding claims' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "app_private"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "app_private"."funding_claim_lines" z
    join "app_private"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "app_private"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."get_funding_claim"(uuid) from public, anon;
grant execute on function "app_private"."get_funding_claim"(uuid) to authenticated, service_role;

-- Marks a draft claim sent, with the channel's reference and the SHA-256 of
-- the file that was sent.
create or replace function "app_private"."mark_funding_claim_sent"(claim_id uuid, external_ref text default null, payload_sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "app_private"."funding_claims"%rowtype;
  v_ref text := nullif(trim(mark_funding_claim_sent.external_ref), '');
  v_sha text := lower(nullif(trim(mark_funding_claim_sent.payload_sha256), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "app_private"."funding_claims" x where x."id" = mark_funding_claim_sent.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'external_ref is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'payload_sha256 is a SHA-256 in hex' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  update "app_private"."funding_claims" x set "status" = 'sent', "sent_at" = now(), "external_ref" = v_ref, "payload_sha256" = v_sha, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at");
end;
$$;
revoke execute on function "app_private"."mark_funding_claim_sent"(uuid, text, text) from public, anon;
grant execute on function "app_private"."mark_funding_claim_sent"(uuid, text, text) to authenticated, service_role;

-- Records the funder's response to a sent claim: lines is an array of
-- { lineId, status (accepted or rejected), rejectionCode }, or null for
-- none. A line the response leaves out is accepted. The deliveries of a rejected line go back
-- to approved, for correction and a later claim.
create or replace function "app_private"."record_funding_claim_response"(claim_id uuid, lines jsonb, response jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "app_private"."funding_claims"%rowtype;
  v_line jsonb;
  v_status text;
  v_code text;
  v_accepted integer;
  v_rejected integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "app_private"."funding_claims" x where x."id" = record_funding_claim_response.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'sent' then
    raise exception 'only a sent claim takes a response' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if jsonb_typeof(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) <> 'array' then
    raise exception 'lines is an array' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_line in select value from jsonb_array_elements(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) loop
    v_status := v_line ->> 'status';
    v_code := nullif(trim(v_line ->> 'rejectionCode'), '');
    if jsonb_typeof(v_line) <> 'object' or v_status is null or v_status not in ('accepted', 'rejected') then
      raise exception 'each line has a lineId and a status of accepted or rejected' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_code is not null and length(v_code) > 100 then
      raise exception 'a rejection code is at most 100 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    update "app_private"."funding_claim_lines" x set "status" = v_status, "rejection_code" = case when v_status = 'rejected' then v_code end
    where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id"
      and x."id"::text = v_line ->> 'lineId';
    if not found then
      raise exception 'a line in the response isn''t a line of this claim' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end loop;
  update "app_private"."funding_claim_lines" x set "status" = 'accepted'
  where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id" and x."status" = 'pending';
  update "app_private"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "app_private"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id" and z."status" = 'rejected');
  select count(*) filter (where z."status" = 'accepted'), count(*) filter (where z."status" = 'rejected')
  into v_accepted, v_rejected
  from "app_private"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id";
  update "app_private"."funding_claims" x set
    "status" = case when v_rejected = 0 then 'accepted' when v_accepted = 0 then 'rejected' else 'partially_accepted' end,
    "response" = record_funding_claim_response.response, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "app_private"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "app_private"."funding_claim_lines" z
    join "app_private"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "app_private"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "app_private"."record_funding_claim_response"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "app_private"."record_funding_claim_response"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Deletes a draft claim; its deliveries go back to approved.
create or replace function "app_private"."delete_funding_claim"(claim_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "app_private"."funding_claims"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "app_private"."funding_claims" x where x."id" = delete_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  update "app_private"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "app_private"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id");
  delete from "app_private"."funding_claims" x where x."id" = v_claim."id";
  null;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_funding_claim"(uuid) from public, anon;
grant execute on function "app_private"."delete_funding_claim"(uuid) to authenticated, service_role;

create or replace function "app_private"."list_funding_claims"(tenant uuid, status text default null, funder_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'funderId', x."funder_id", 'number', x."number", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'format', x."format", 'status', x."status", 'externalRef', x."external_ref", 'sentAt', x."sent_at", 'payloadSha256', x."payload_sha256", 'response', x."response", 'total', x."total"::text, 'currency', x."currency", 'invoiceId', x."invoice_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."number" desc), '[]'::jsonb)
  from "app_private"."funding_claims" x
  where x."tenant_id" = list_funding_claims.tenant
    and (list_funding_claims.status is null or x."status" = list_funding_claims.status)
    and (list_funding_claims.funder_id is null or x."funder_id" = list_funding_claims.funder_id)
$$;
revoke execute on function "app_private"."list_funding_claims"(uuid, text, uuid) from public, anon;
grant execute on function "app_private"."list_funding_claims"(uuid, text, uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."funding_products";
drop policy if exists bsb_tenant_scope_select on "app_private"."funding_products";
create policy bsb_tenant_scope_select on "app_private"."funding_products" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_products";
create policy bsb_tenant_scope_insert on "app_private"."funding_products" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."funding_products";
create policy bsb_tenant_scope_update on "app_private"."funding_products" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_products";
create policy bsb_tenant_scope_delete on "app_private"."funding_products" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."funding_awards";
drop policy if exists bsb_tenant_scope_select on "app_private"."funding_awards";
create policy bsb_tenant_scope_select on "app_private"."funding_awards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_awards";
create policy bsb_tenant_scope_insert on "app_private"."funding_awards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."funding_awards";
create policy bsb_tenant_scope_update on "app_private"."funding_awards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_awards";
create policy bsb_tenant_scope_delete on "app_private"."funding_awards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."funding_deliveries";
drop policy if exists bsb_tenant_scope_select on "app_private"."funding_deliveries";
create policy bsb_tenant_scope_select on "app_private"."funding_deliveries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "app_private"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_deliveries";
create policy bsb_tenant_scope_insert on "app_private"."funding_deliveries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."funding_deliveries";
create policy bsb_tenant_scope_update on "app_private"."funding_deliveries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_deliveries";
create policy bsb_tenant_scope_delete on "app_private"."funding_deliveries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."funding_claims";
drop policy if exists bsb_tenant_scope_select on "app_private"."funding_claims";
create policy bsb_tenant_scope_select on "app_private"."funding_claims" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_claims";
create policy bsb_tenant_scope_insert on "app_private"."funding_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."funding_claims";
create policy bsb_tenant_scope_update on "app_private"."funding_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_claims";
create policy bsb_tenant_scope_delete on "app_private"."funding_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "app_private"."funding_claim_lines";
drop policy if exists bsb_tenant_scope_select on "app_private"."funding_claim_lines";
create policy bsb_tenant_scope_select on "app_private"."funding_claim_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."funding_claim_lines";
create policy bsb_tenant_scope_insert on "app_private"."funding_claim_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."funding_claim_lines";
create policy bsb_tenant_scope_update on "app_private"."funding_claim_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."funding_claim_lines";
create policy bsb_tenant_scope_delete on "app_private"."funding_claim_lines" as restrictive
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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block-data funding
-- @bsb-hash sha256:5f2aaa76a9d6c8414def54826e938bc7edcce178f14b0d9edd894653bfab3d11
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block funding@1 managed
-- @bsb-hash sha256:185a8047c717e1730bbf5b0d58101551d7a36c7c7a4d87eed937c1c932f576af
-- Products a funder pays for, awards of units per period to a record from a funder in contacts, care delivered against an award from time entries, bookings or by hand, usage against the award per period, and claims per funder and period with the funder's response per line, rendered and sent through app-supplied formats and channels.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Funding: the products a funder pays for, awards of units per period to a
-- record, the care delivered against them, and claims to the funder with its
-- response per line.

create table if not exists "better_supabase"."funding_products" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The funder's product code, such as 45A48 for a Wlz product.
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 300),
  "unit" text not null check ("unit" in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece')),
  -- The price of one unit, in minor units of currency.
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "valid_from" date,
  "valid_until" date,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("valid_until" is null or "valid_from" is null or "valid_until" >= "valid_from"),
  unique ("tenant_id", "id")
);
create unique index if not exists "funding_products_code_idx" on "better_supabase"."funding_products" ("tenant_id", "code");
alter table "better_supabase"."funding_products" enable row level security;
revoke all on "better_supabase"."funding_products" from public, anon, authenticated;
grant select on "better_supabase"."funding_products" to authenticated;
grant all on "better_supabase"."funding_products" to service_role;
drop policy if exists funding_products_read on "better_supabase"."funding_products";
create policy funding_products_read on "better_supabase"."funding_products"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_awards" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  -- The record the award is for, a type in config.subjects.
  "subject_type" text not null,
  "subject_id" text not null,
  -- The contacts company or person that pays, holding the funder role.
  "funder_id" uuid not null,
  "product_id" uuid not null,
  -- The units awarded per period.
  "units" numeric not null check ("units" > 0),
  "period" text not null check ("period" in ('week', 'month', 'total')),
  "starts_on" date not null,
  "ends_on" date,
  -- The funder's reference for the award, such as an indication number.
  "reference" text check ("reference" is null or length("reference") <= 200),
  "status" text not null default 'active' check ("status" in ('requested', 'active', 'ended', 'canceled')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_on" is null or "ends_on" >= "starts_on"),
  unique ("tenant_id", "id"),
  foreign key ("tenant_id", "product_id") references "better_supabase"."funding_products" ("tenant_id", "id")
);
create index if not exists "funding_awards_product_idx" on "better_supabase"."funding_awards" ("tenant_id", "product_id");
create index if not exists "funding_awards_subject_idx" on "better_supabase"."funding_awards" ("subject_type", "subject_id");
create index if not exists "funding_awards_funder_idx" on "better_supabase"."funding_awards" ("tenant_id", "funder_id", "status");
alter table "better_supabase"."funding_awards" enable row level security;
revoke all on "better_supabase"."funding_awards" from public, anon, authenticated;
grant select on "better_supabase"."funding_awards" to authenticated;
grant all on "better_supabase"."funding_awards" to service_role;
drop policy if exists funding_awards_read on "better_supabase"."funding_awards";
create policy funding_awards_read on "better_supabase"."funding_awards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

create table if not exists "better_supabase"."funding_claims" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "funder_id" uuid not null,
  "number" text not null check (length("number") between 1 and 100),
  "period_start" date not null,
  "period_end" date not null,
  -- The FundingClaimFormat key that renders the claim, such as iwlz-aw319.
  "format" text not null check ("format" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'accepted', 'partially_accepted', 'rejected')),
  -- The funder's or the channel's reference for the sent claim.
  "external_ref" text check ("external_ref" is null or length("external_ref") <= 200),
  "sent_at" timestamptz,
  -- The SHA-256 of the rendered file that was sent, in hex.
  "payload_sha256" text check ("payload_sha256" is null or "payload_sha256" ~ '^[0-9a-f]{64}$'),
  -- The funder's response as the format parsed it.
  "response" jsonb,
  "total" bigint not null default 0,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  unique ("tenant_id", "id")
);
create unique index if not exists "funding_claims_number_idx" on "better_supabase"."funding_claims" ("tenant_id", "number");
create index if not exists "funding_claims_funder_idx" on "better_supabase"."funding_claims" ("tenant_id", "funder_id", "status");
alter table "better_supabase"."funding_claims" enable row level security;
revoke all on "better_supabase"."funding_claims" from public, anon, authenticated;
grant select on "better_supabase"."funding_claims" to authenticated;
grant all on "better_supabase"."funding_claims" to service_role;
drop policy if exists funding_claims_read on "better_supabase"."funding_claims";
create policy funding_claims_read on "better_supabase"."funding_claims"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_claim_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "claim_id" uuid not null,
  "award_id" uuid not null,
  "product_id" uuid not null,
  "units" numeric not null check ("units" > 0),
  -- The units times the product rate, in minor units of the claim currency.
  "amount" bigint not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'accepted', 'rejected')),
  -- The funder's code for a rejected line.
  "rejection_code" text check ("rejection_code" is null or length("rejection_code") <= 100),
  foreign key ("tenant_id", "claim_id") references "better_supabase"."funding_claims" ("tenant_id", "id") on delete cascade,
  foreign key ("tenant_id", "award_id") references "better_supabase"."funding_awards" ("tenant_id", "id"),
  foreign key ("tenant_id", "product_id") references "better_supabase"."funding_products" ("tenant_id", "id")
);
create index if not exists "funding_claim_lines_claim_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "claim_id");
create index if not exists "funding_claim_lines_award_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "award_id");
create index if not exists "funding_claim_lines_product_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "product_id");
alter table "better_supabase"."funding_claim_lines" enable row level security;
revoke all on "better_supabase"."funding_claim_lines" from public, anon, authenticated;
grant select on "better_supabase"."funding_claim_lines" to authenticated;
grant all on "better_supabase"."funding_claim_lines" to service_role;
drop policy if exists funding_claim_lines_read on "better_supabase"."funding_claim_lines";
create policy funding_claim_lines_read on "better_supabase"."funding_claim_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "award_id" uuid not null,
  -- Where the delivery came from; source_id is the time entry or booking id.
  "source_type" text not null default 'manual' check ("source_type" in ('time_entry', 'booking', 'manual')),
  "source_id" text check ("source_id" is null or length("source_id") <= 200),
  "delivered_on" date not null,
  "units" numeric not null check ("units" > 0),
  "performer_id" uuid,
  "status" text not null default 'registered' check ("status" in ('registered', 'approved', 'claimed', 'rejected')),
  -- The claim line that claims it, once a claim gathered it.
  "claim_line_id" uuid references "better_supabase"."funding_claim_lines" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  check ("source_type" = 'manual' or "source_id" is not null),
  foreign key ("tenant_id", "award_id") references "better_supabase"."funding_awards" ("tenant_id", "id") on delete cascade
);
create index if not exists "funding_deliveries_award_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "award_id", "delivered_on");
create index if not exists "funding_deliveries_status_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "status", "delivered_on");
create index if not exists "funding_deliveries_claim_line_idx" on "better_supabase"."funding_deliveries" ("claim_line_id");
create unique index if not exists "funding_deliveries_source_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "source_type", "source_id") where "source_id" is not null;
alter table "better_supabase"."funding_deliveries" enable row level security;
revoke all on "better_supabase"."funding_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."funding_deliveries" to authenticated;
grant all on "better_supabase"."funding_deliveries" to service_role;
drop policy if exists funding_deliveries_read on "better_supabase"."funding_deliveries";
create policy funding_deliveries_read on "better_supabase"."funding_deliveries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)));

-- Adds a product a funder pays for, or changes one (product_id): its code,
-- unit and rate in minor units. The code is unique in the organization.
create or replace function "better_supabase"."save_funding_product"(tenant uuid, code text, title text, unit text, rate bigint, currency text, valid_from date default null, valid_until date default null, product_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_products"%rowtype;
  v_code text := nullif(trim(save_funding_product.code), '');
  v_title text := nullif(trim(save_funding_product.title), '');
  v_unit text := nullif(trim(save_funding_product.unit), '');
  v_currency text := upper(nullif(trim(save_funding_product.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_product.tenant, 'funding.manage'), false)) then
    raise exception 'not allowed to manage funding products' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_code is null or length(v_code) > 50 then
    raise exception 'a product needs a code of at most 50 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_title is null or length(v_title) > 300 then
    raise exception 'a product needs a title of at most 300 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_unit is null or v_unit not in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece') then
    raise exception 'unit is minute, hour, day_part, day, visit or piece' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.rate is null or save_funding_product.rate < 0 then
    raise exception 'a rate is zero or more minor units' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.valid_until < save_funding_product.valid_from then
    raise exception 'a product is valid until on or after it is valid from' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."funding_products" x
    where x."tenant_id" = save_funding_product.tenant and x."code" = v_code
      and x."id" is distinct from save_funding_product.product_id
  ) then
    raise exception 'the organization already has a funding product with this code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.product_id is null then
    insert into "better_supabase"."funding_products" ("tenant_id", "code", "title", "unit", "rate", "currency", "valid_from", "valid_until")
    values (save_funding_product.tenant, v_code, v_title, v_unit, save_funding_product.rate, v_currency, save_funding_product.valid_from, save_funding_product.valid_until)
    returning * into v_row;
  else
    update "better_supabase"."funding_products" x set
      "code" = v_code,
      "title" = v_title,
      "unit" = v_unit,
      "rate" = save_funding_product.rate,
      "currency" = v_currency,
      "valid_from" = save_funding_product.valid_from,
      "valid_until" = save_funding_product.valid_until, "updated_at" = now()
    where x."id" = save_funding_product.product_id and x."tenant_id" = save_funding_product.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'title', v_row."title", 'unit', v_row."unit", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_products"(tenant uuid, include_expired boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'title', x."title", 'unit', x."unit", 'rate', x."rate"::text, 'currency', x."currency", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code", x."id"), '[]'::jsonb)
  from "better_supabase"."funding_products" x
  where x."tenant_id" = list_funding_products.tenant
    and (coalesce(list_funding_products.include_expired, false) or x."valid_until" is null or x."valid_until" >= current_date)
$$;
revoke execute on function "better_supabase"."list_funding_products"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_products"(uuid, boolean) to authenticated, service_role;

-- Awards units of a product per period to a record, from a funder in
-- contacts, or changes an award (award_id); a key attrs leaves out keeps its
-- value. attrs holds funderId, productId, units, period (week, month or
-- total), startsOn, endsOn, reference, status (requested or active) and
-- fields, the extra columns by name.
create or replace function "better_supabase"."save_funding_award"(tenant uuid, subject_type text, subject_id text, attrs jsonb, award_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_attrs jsonb := coalesce(save_funding_award.attrs, '{}'::jsonb);
  v_funder uuid;
  v_product uuid;
  v_units numeric;
  v_period text;
  v_starts date;
  v_ends date;
  v_reference text;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_award.tenant, 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  
  if save_funding_award.award_id is null then
    if not false then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else null end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else null end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else null end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else null end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else null end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else null end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else null end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else 'active' end;
  else
    select * into v_row from "better_supabase"."funding_awards" x
    where x."id" = save_funding_award.award_id and x."tenant_id" = save_funding_award.tenant
    for update;
    if not found then
      raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
    end if;
    if v_row."subject_type" <> save_funding_award.subject_type or v_row."subject_id" <> save_funding_award.subject_id then
      raise exception 'an award stays with its record' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_row."status" in ('ended', 'canceled') then
      raise exception 'the funding award has ended' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else v_row."funder_id" end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else v_row."product_id" end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else v_row."units" end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else v_row."period" end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else v_row."ends_on" end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else v_row."reference" end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else v_row."status" end;
  end if;
  if v_funder is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if v_product is null or not exists (select 1 from "better_supabase"."funding_products" x where x."id" = v_product and x."tenant_id" = save_funding_award.tenant) then
    raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
  end if;
  if v_units is null or v_units <= 0 then
    raise exception 'an award needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_period is null or v_period not in ('week', 'month', 'total') then
    raise exception 'period is week, month or total' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an award needs a start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an award ends on or after its start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_reference is not null and length(v_reference) > 200 then
    raise exception 'reference is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_status is null or v_status not in ('requested', 'active') then
    raise exception 'a saved award is requested or active; end_funding_award ends it' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_award_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_attrs;
    end if;
  end;
  if save_funding_award.award_id is null then
    insert into "better_supabase"."funding_awards" ("tenant_id", "subject_type", "subject_id", "funder_id", "product_id", "units", "period", "starts_on", "ends_on", "reference", "status", "created_by")
    values (save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_funder, v_product, v_units, v_period, v_starts, v_ends, v_reference, v_status, (select auth.uid()))
    returning * into v_row;
    null;
  else
    update "better_supabase"."funding_awards" x set
    "funder_id" = v_funder,
    "product_id" = v_product,
    "units" = v_units,
    "period" = v_period,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "reference" = v_reference,
    "status" = v_status, "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_award_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) to authenticated, service_role;

-- Ends an award on ends_on (today by default), or cancels it (canceled).
-- Deliveries already registered stay.
create or replace function "better_supabase"."end_funding_award"(award_id uuid, ends_on date default null, canceled boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_ends date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."funding_awards" x where x."id" = end_funding_award.award_id for update;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_row."status" in ('ended', 'canceled') then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  v_ends := case
    when coalesce(end_funding_award.canceled, false) then coalesce(end_funding_award.ends_on, v_row."ends_on")
    else coalesce(end_funding_award.ends_on, least(current_date, coalesce(v_row."ends_on", current_date)))
  end;
  if v_ends is not null and v_ends < v_row."starts_on" then
    if coalesce(end_funding_award.canceled, false) then
      v_ends := null;
    else
      raise exception 'an award ends on or after its start date; cancel it instead' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end if;
  update "better_supabase"."funding_awards" x set
    "status" = case when coalesce(end_funding_award.canceled, false) then 'canceled' else 'ended' end,
    "ends_on" = v_ends, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) from public, anon;
grant execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_awards"(tenant uuid, subject_type text default null, subject_id text default null, include_ended boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'funderId', x."funder_id", 'productId', x."product_id", 'units', x."units", 'period', x."period", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'reference', x."reference", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('product', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text, 'currency', y."currency", 'validFrom', y."valid_from", 'validUntil', y."valid_until", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."funding_awards" x
  join "better_supabase"."funding_products" y on y."tenant_id" = x."tenant_id" and y."id" = x."product_id"
  where x."tenant_id" = list_funding_awards.tenant
    and (list_funding_awards.subject_type is null or x."subject_type" = list_funding_awards.subject_type)
    and (list_funding_awards.subject_id is null or x."subject_id" = list_funding_awards.subject_id)
    and (coalesce(list_funding_awards.include_ended, false) or x."status" in ('requested', 'active'))
$$;
revoke execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) to authenticated, service_role;

-- The units used against the units awarded, per period of the award from its
-- start to its end (today while it runs). Rejected deliveries don't count.
create or replace function "better_supabase"."funding_award_usage"(award_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'awardId', a."id",
    'units', a."units",
    'period', a."period",
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', s.start,
        'end', nullif(s.finish, 'infinity'::date) - 1,
        'awarded', a."units",
        'used', s.used,
        'over', greatest(s.used - a."units", 0),
        'under', greatest(a."units" - s.used, 0)
      ) order by s.start)
      from (
        select g.start, (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end) as finish, (
          select coalesce(sum(x."units"), 0) from "better_supabase"."funding_deliveries" x
          where x."tenant_id" = a."tenant_id" and x."award_id" = a."id" and x."status" <> 'rejected'
            and x."delivered_on" >= g.start and x."delivered_on" < (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end)
        ) as used
        from (
          select pg_catalog.generate_series(
            (case a."period" when 'week' then date_trunc('week', a."starts_on")::date when 'month' then date_trunc('month', a."starts_on")::date else a."starts_on" end)::timestamp,
            coalesce(a."ends_on", current_date)::timestamp,
            case a."period" when 'week' then interval '1 week' else interval '1 month' end
          )::date as start
          where a."period" <> 'total'
          union all
          select a."starts_on" where a."period" = 'total'
        ) g
      ) s
    ), '[]'::jsonb)
  )
  from "better_supabase"."funding_awards" a
  where a."id" = funding_award_usage.award_id
$$;
revoke execute on function "better_supabase"."funding_award_usage"(uuid) from public, anon;
grant execute on function "better_supabase"."funding_award_usage"(uuid) to authenticated, service_role;

-- Registers care delivered on an award: units on a day, from a time entry, a
-- booking or by hand (manual). A source registered before returns its
-- delivery, so registering it twice is safe. Crossing the units of a period
-- emits funding_award.exceeded.
create or replace function "better_supabase"."register_funding_delivery"(award_id uuid, delivered_on date, units numeric, source_type text default 'manual', source_id text default null, performer_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_award "better_supabase"."funding_awards"%rowtype;
  v_product "better_supabase"."funding_products"%rowtype;
  v_source text := coalesce(nullif(trim(register_funding_delivery.source_type), ''), 'manual');
  v_source_id text := nullif(trim(register_funding_delivery.source_id), '');
  v_note text := nullif(trim(register_funding_delivery.note), '');
  v_start date;
  v_used numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_award from "better_supabase"."funding_awards" x where x."id" = register_funding_delivery.award_id;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_award."tenant_id", 'funding.register'), false)) then
    raise exception 'not allowed to register funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_source not in ('time_entry', 'booking', 'manual') then
    raise exception 'source_type is time_entry, booking or manual' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source <> 'manual' and v_source_id is null then
    raise exception 'a delivery from a time entry or booking needs its source_id' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source_id is not null then
    select * into v_row from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = v_award."tenant_id" and x."source_type" = v_source and x."source_id" = v_source_id;
    if found then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
    end if;
  end if;
  if register_funding_delivery.delivered_on is null then
    raise exception 'a delivery needs the day it was delivered' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if register_funding_delivery.units is null or register_funding_delivery.units <= 0 then
    raise exception 'a delivery needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_award."status" <> 'active'
    or register_funding_delivery.delivered_on < v_award."starts_on"
    or register_funding_delivery.delivered_on > coalesce(v_award."ends_on", register_funding_delivery.delivered_on) then
    raise exception 'the funding award isn''t active on that day' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
  end if;
  select * into v_product from "better_supabase"."funding_products" x where x."tenant_id" = v_award."tenant_id" and x."id" = v_award."product_id";
  if (v_product."valid_from" is not null and register_funding_delivery.delivered_on < v_product."valid_from")
    or (v_product."valid_until" is not null and register_funding_delivery.delivered_on > v_product."valid_until") then
    raise exception 'the funding product isn''t valid on that day' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_delivery_register"(uuid, date, numeric)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::date, $3::numeric)', v_hook::oid::regproc)
        using v_award."id", register_funding_delivery.delivered_on, register_funding_delivery.units;
    end if;
  end;
  insert into "better_supabase"."funding_deliveries" ("tenant_id", "award_id", "source_type", "source_id", "delivered_on", "units", "performer_id", "note")
  values (v_award."tenant_id", v_award."id", v_source, v_source_id, register_funding_delivery.delivered_on, register_funding_delivery.units, coalesce(register_funding_delivery.performer_id, (select auth.uid())), v_note)
  returning * into v_row;
  null;
  v_start := (case v_award."period" when 'week' then date_trunc('week', v_row."delivered_on")::date when 'month' then date_trunc('month', v_row."delivered_on")::date else v_award."starts_on" end);
  select coalesce(sum(x."units"), 0) into v_used from "better_supabase"."funding_deliveries" x
  where x."tenant_id" = v_award."tenant_id" and x."award_id" = v_award."id" and x."status" <> 'rejected'
    and x."delivered_on" >= v_start and x."delivered_on" < (case v_award."period" when 'week' then (v_start + 7) when 'month' then (v_start + interval '1 month')::date else coalesce(v_award."ends_on" + 1, 'infinity'::date) end);
  if v_used > v_award."units" and v_used - v_row."units" <= v_award."units" then
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_delivery_register"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) to authenticated, service_role;

-- Approves registered deliveries for a claim (approved true) or rejects them.
-- A delivery a claim holds can't change. Returns how many changed.
create or replace function "better_supabase"."approve_funding_deliveries"(ids uuid[], approved boolean default true)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_status text := case when coalesce(approve_funding_deliveries.approved, true) then 'approved' else 'rejected' end;
  v_found integer := 0;
  v_changed integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    select * from "better_supabase"."funding_deliveries" x
    where x."id" = any (coalesce(approve_funding_deliveries.ids, '{}'::uuid[]))
    order by x."id"
    for update
  loop
    v_found := v_found + 1;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.approve'), false)) then
      raise exception 'not allowed to approve funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
    end if;
    if v_row."status" = 'claimed' then
      raise exception 'a claim holds this delivery' using errcode = '22023', hint = 'FUNDING_DELIVERY_CLAIMED';
    end if;
    if v_row."status" <> v_status then
      update "better_supabase"."funding_deliveries" x set "status" = v_status where x."id" = v_row."id";
      v_changed := v_changed + 1;
    end if;
  end loop;
  if v_found < (select count(distinct i) from unnest(coalesce(approve_funding_deliveries.ids, '{}'::uuid[])) i) then
    raise exception 'funding delivery not found' using errcode = 'P0002', hint = 'FUNDING_DELIVERY_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) to authenticated, service_role;

-- The deliveries of an organization, newest first. filter holds awardId,
-- status, since and until (days), and limit (500 by default, 1000 at most).
create or replace function "better_supabase"."list_funding_deliveries"(tenant uuid, filter jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.row order by z.day desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'awardId', x."award_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'deliveredOn', x."delivered_on", 'units', x."units", 'performerId', x."performer_id", 'status', x."status", 'claimLineId', x."claim_line_id", 'note', x."note", 'createdAt', x."created_at") as row, x."delivered_on" as day, x."id" as id
    from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = list_funding_deliveries.tenant
      and (list_funding_deliveries.filter ->> 'awardId' is null or x."award_id" = (list_funding_deliveries.filter ->> 'awardId')::uuid)
      and (list_funding_deliveries.filter ->> 'status' is null or x."status" = list_funding_deliveries.filter ->> 'status')
      and (list_funding_deliveries.filter ->> 'since' is null or x."delivered_on" >= (list_funding_deliveries.filter ->> 'since')::date)
      and (list_funding_deliveries.filter ->> 'until' is null or x."delivered_on" <= (list_funding_deliveries.filter ->> 'until')::date)
    order by x."delivered_on" desc, x."id"
    limit least(greatest(coalesce((list_funding_deliveries.filter ->> 'limit')::integer, 500), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) to authenticated, service_role;

-- Gathers the approved deliveries of a funder from period_start to
-- period_end into a draft claim in format (a FundingClaimFormat key), one
-- line per award, priced at the product rate. The deliveries become claimed.
create or replace function "better_supabase"."build_funding_claim"(tenant uuid, funder_id uuid, period_start date, period_end date, format text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_format text := nullif(trim(build_funding_claim.format), '');
  v_currencies integer;
  v_currency text;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', build_funding_claim.tenant, 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_format is null or v_format !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'the claim format isn''t one this organization claims in' using errcode = '22023', hint = 'FUNDING_FORMAT_UNKNOWN';
  end if;
  if build_funding_claim.funder_id is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if build_funding_claim.period_start is null or build_funding_claim.period_end is null
    or build_funding_claim.period_end < build_funding_claim.period_start then
    raise exception 'a claim period ends on or after it starts' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_claim_build"(uuid, uuid, date, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date, $4::date)', v_hook::oid::regproc)
        using build_funding_claim.tenant, build_funding_claim.funder_id, build_funding_claim.period_start, build_funding_claim.period_end;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb_funding_claim:' || build_funding_claim.tenant::text, 0));
  perform 1 from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  for update of x;
  select count(distinct y."currency"), min(y."currency") into v_currencies, v_currency
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  if v_currencies = 0 then
    raise exception 'no approved deliveries of this funder in the period' using errcode = '22023', hint = 'FUNDING_CLAIM_EMPTY';
  end if;
  if v_currencies > 1 then
    raise exception 'the deliveries are priced in several currencies; claim each product''s currency apart' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  select coalesce(max(x."number"::bigint) filter (where x."number" ~ '^[0-9]{1,18}$'), 0) + 1 into v_seq
  from "better_supabase"."funding_claims" x where x."tenant_id" = build_funding_claim.tenant;
  v_number := v_seq::text;
  insert into "better_supabase"."funding_claims" ("tenant_id", "funder_id", "number", "period_start", "period_end", "format", "currency", "created_by")
  values (build_funding_claim.tenant, build_funding_claim.funder_id, v_number, build_funding_claim.period_start, build_funding_claim.period_end, v_format, v_currency, (select auth.uid()))
  returning * into v_claim;
  insert into "better_supabase"."funding_claim_lines" ("tenant_id", "claim_id", "award_id", "product_id", "units", "amount")
  select build_funding_claim.tenant, v_claim."id", a."id", y."id", sum(x."units"), round(sum(x."units") * y."rate")::bigint
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  group by a."id", y."id", y."rate";
  update "better_supabase"."funding_deliveries" x set "status" = 'claimed', "claim_line_id" = z."id"
  from "better_supabase"."funding_claim_lines" z
  where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
    and x."tenant_id" = z."tenant_id" and x."award_id" = z."award_id"
    and x."status" = 'approved' and x."claim_line_id" is null
    and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  update "better_supabase"."funding_claims" x set "total" = (
    select coalesce(sum(z."amount"), 0) from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  )
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_claim_build"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_claim."id";
    end if;
  end;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) from public, anon;
grant execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) to authenticated, service_role;

-- A claim with its lines, each with its award, product and deliveries: what a
-- FundingClaimFormat renders.
create or replace function "better_supabase"."get_funding_claim"(claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = get_funding_claim.claim_id;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.read'), false)) then
    raise exception 'not allowed to read funding claims' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."get_funding_claim"(uuid) to authenticated, service_role;

-- Marks a draft claim sent, with the channel's reference and the SHA-256 of
-- the file that was sent.
create or replace function "better_supabase"."mark_funding_claim_sent"(claim_id uuid, external_ref text default null, payload_sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_ref text := nullif(trim(mark_funding_claim_sent.external_ref), '');
  v_sha text := lower(nullif(trim(mark_funding_claim_sent.payload_sha256), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = mark_funding_claim_sent.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'external_ref is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'payload_sha256 is a SHA-256 in hex' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  update "better_supabase"."funding_claims" x set "status" = 'sent', "sent_at" = now(), "external_ref" = v_ref, "payload_sha256" = v_sha, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at");
end;
$$;
revoke execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) to authenticated, service_role;

-- Records the funder's response to a sent claim: lines is an array of
-- { lineId, status (accepted or rejected), rejectionCode }, or null for
-- none. A line the response leaves out is accepted. The deliveries of a rejected line go back
-- to approved, for correction and a later claim.
create or replace function "better_supabase"."record_funding_claim_response"(claim_id uuid, lines jsonb, response jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_line jsonb;
  v_status text;
  v_code text;
  v_accepted integer;
  v_rejected integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = record_funding_claim_response.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'sent' then
    raise exception 'only a sent claim takes a response' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if jsonb_typeof(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) <> 'array' then
    raise exception 'lines is an array' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_line in select value from jsonb_array_elements(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) loop
    v_status := v_line ->> 'status';
    v_code := nullif(trim(v_line ->> 'rejectionCode'), '');
    if jsonb_typeof(v_line) <> 'object' or v_status is null or v_status not in ('accepted', 'rejected') then
      raise exception 'each line has a lineId and a status of accepted or rejected' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_code is not null and length(v_code) > 100 then
      raise exception 'a rejection code is at most 100 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    update "better_supabase"."funding_claim_lines" x set "status" = v_status, "rejection_code" = case when v_status = 'rejected' then v_code end
    where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id"
      and x."id"::text = v_line ->> 'lineId';
    if not found then
      raise exception 'a line in the response isn''t a line of this claim' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end loop;
  update "better_supabase"."funding_claim_lines" x set "status" = 'accepted'
  where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id" and x."status" = 'pending';
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id" and z."status" = 'rejected');
  select count(*) filter (where z."status" = 'accepted'), count(*) filter (where z."status" = 'rejected')
  into v_accepted, v_rejected
  from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id";
  update "better_supabase"."funding_claims" x set
    "status" = case when v_rejected = 0 then 'accepted' when v_accepted = 0 then 'rejected' else 'partially_accepted' end,
    "response" = record_funding_claim_response.response, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Deletes a draft claim; its deliveries go back to approved.
create or replace function "better_supabase"."delete_funding_claim"(claim_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = delete_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id");
  delete from "better_supabase"."funding_claims" x where x."id" = v_claim."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_funding_claim"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_claims"(tenant uuid, status text default null, funder_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'funderId', x."funder_id", 'number', x."number", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'format', x."format", 'status', x."status", 'externalRef', x."external_ref", 'sentAt', x."sent_at", 'payloadSha256', x."payload_sha256", 'response', x."response", 'total', x."total"::text, 'currency', x."currency", 'invoiceId', x."invoice_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."number" desc), '[]'::jsonb)
  from "better_supabase"."funding_claims" x
  where x."tenant_id" = list_funding_claims.tenant
    and (list_funding_claims.status is null or x."status" = list_funding_claims.status)
    and (list_funding_claims.funder_id is null or x."funder_id" = list_funding_claims.funder_id)
$$;
revoke execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
create policy bsb_tenant_scope_select on "better_supabase"."funding_products" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_products" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
create policy bsb_tenant_scope_update on "better_supabase"."funding_products" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_products" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_select on "better_supabase"."funding_awards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_awards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_update on "better_supabase"."funding_awards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_awards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_select on "better_supabase"."funding_deliveries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_deliveries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_update on "better_supabase"."funding_deliveries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_deliveries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claims" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claim_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claim_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.funding.api: entry points for the Data API.
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

create or replace function "api"."save_funding_product"(tenant uuid, code text, title text, unit text, rate bigint, currency text, valid_from date default null, valid_until date default null, product_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_funding_product"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) from public, anon;
grant execute on function "api"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) to authenticated, service_role;

create or replace function "api"."list_funding_products"(tenant uuid, include_expired boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_funding_products"($1, $2) $$;
revoke execute on function "api"."list_funding_products"(uuid, boolean) from public, anon;
grant execute on function "api"."list_funding_products"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."save_funding_award"(tenant uuid, subject_type text, subject_id text, attrs jsonb, award_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_funding_award"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."save_funding_award"(uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function "api"."save_funding_award"(uuid, text, text, jsonb, uuid) to authenticated, service_role;

create or replace function "api"."end_funding_award"(award_id uuid, ends_on date default null, canceled boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."end_funding_award"($1, $2, $3) $$;
revoke execute on function "api"."end_funding_award"(uuid, date, boolean) from public, anon;
grant execute on function "api"."end_funding_award"(uuid, date, boolean) to authenticated, service_role;

create or replace function "api"."list_funding_awards"(tenant uuid, subject_type text default null, subject_id text default null, include_ended boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_funding_awards"($1, $2, $3, $4) $$;
revoke execute on function "api"."list_funding_awards"(uuid, text, text, boolean) from public, anon;
grant execute on function "api"."list_funding_awards"(uuid, text, text, boolean) to authenticated, service_role;

create or replace function "api"."funding_award_usage"(award_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."funding_award_usage"($1) $$;
revoke execute on function "api"."funding_award_usage"(uuid) from public, anon;
grant execute on function "api"."funding_award_usage"(uuid) to authenticated, service_role;

create or replace function "api"."register_funding_delivery"(award_id uuid, delivered_on date, units numeric, source_type text default 'manual', source_id text default null, performer_id uuid default null, note text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."register_funding_delivery"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) from public, anon;
grant execute on function "api"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) to authenticated, service_role;

create or replace function "api"."approve_funding_deliveries"(ids uuid[], approved boolean default true)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."approve_funding_deliveries"($1, $2) $$;
revoke execute on function "api"."approve_funding_deliveries"(uuid[], boolean) from public, anon;
grant execute on function "api"."approve_funding_deliveries"(uuid[], boolean) to authenticated, service_role;

create or replace function "api"."list_funding_deliveries"(tenant uuid, filter jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_funding_deliveries"($1, $2) $$;
revoke execute on function "api"."list_funding_deliveries"(uuid, jsonb) from public, anon;
grant execute on function "api"."list_funding_deliveries"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."build_funding_claim"(tenant uuid, funder_id uuid, period_start date, period_end date, format text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."build_funding_claim"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."build_funding_claim"(uuid, uuid, date, date, text) from public, anon;
grant execute on function "api"."build_funding_claim"(uuid, uuid, date, date, text) to authenticated, service_role;

create or replace function "api"."get_funding_claim"(claim_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."get_funding_claim"($1) $$;
revoke execute on function "api"."get_funding_claim"(uuid) from public, anon;
grant execute on function "api"."get_funding_claim"(uuid) to authenticated, service_role;

create or replace function "api"."mark_funding_claim_sent"(claim_id uuid, external_ref text default null, payload_sha256 text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."mark_funding_claim_sent"($1, $2, $3) $$;
revoke execute on function "api"."mark_funding_claim_sent"(uuid, text, text) from public, anon;
grant execute on function "api"."mark_funding_claim_sent"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."record_funding_claim_response"(claim_id uuid, lines jsonb, response jsonb default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_funding_claim_response"($1, $2, $3) $$;
revoke execute on function "api"."record_funding_claim_response"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "api"."record_funding_claim_response"(uuid, jsonb, jsonb) to authenticated, service_role;

create or replace function "api"."delete_funding_claim"(claim_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_funding_claim"($1) $$;
revoke execute on function "api"."delete_funding_claim"(uuid) from public, anon;
grant execute on function "api"."delete_funding_claim"(uuid) to authenticated, service_role;

create or replace function "api"."list_funding_claims"(tenant uuid, status text default null, funder_id uuid default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_funding_claims"($1, $2, $3) $$;
revoke execute on function "api"."list_funding_claims"(uuid, text, uuid) from public, anon;
grant execute on function "api"."list_funding_claims"(uuid, text, uuid) to authenticated, service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block-data funding
-- @bsb-hash sha256:5f2aaa76a9d6c8414def54826e938bc7edcce178f14b0d9edd894653bfab3d11
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block funding@1 managed
-- @bsb-hash sha256:6350166097e3d73f1e93519b69e6a9cdff1fb33d26bb1c058822d6cfb34ab6c9
-- Products a funder pays for, awards of units per period to a record from a funder in contacts, care delivered against an award from time entries, bookings or by hand, usage against the award per period, and claims per funder and period with the funder's response per line, rendered and sent through app-supplied formats and channels.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Funding: the products a funder pays for, awards of units per period to a
-- record, the care delivered against them, and claims to the funder with its
-- response per line.

-- better_supabase.funding_products is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."funding_products" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."funding_products" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."funding_products" add column if not exists "code" text check (length("code") between 1 and 50);
alter table "better_supabase"."funding_products" add column if not exists "title" text check (length("title") between 1 and 300);
alter table "better_supabase"."funding_products" add column if not exists "unit" text check ("unit" in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece'));
alter table "better_supabase"."funding_products" add column if not exists "rate" bigint check ("rate" >= 0);
alter table "better_supabase"."funding_products" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."funding_products" add column if not exists "valid_from" date;
alter table "better_supabase"."funding_products" add column if not exists "valid_until" date;
alter table "better_supabase"."funding_products" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."funding_products" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_funding_products_tenant_id_key" on "better_supabase"."funding_products" ("tenant_id", "id");
create unique index if not exists "funding_products_code_idx" on "better_supabase"."funding_products" ("tenant_id", "code");
alter table "better_supabase"."funding_products" enable row level security;
grant select on "better_supabase"."funding_products" to authenticated;
grant all on "better_supabase"."funding_products" to service_role;
drop policy if exists bsb_funding_products_read on "better_supabase"."funding_products";
create policy bsb_funding_products_read on "better_supabase"."funding_products"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

-- better_supabase.funding_awards is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."funding_awards" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."funding_awards" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."funding_awards" add column if not exists "subject_type" text;
alter table "better_supabase"."funding_awards" add column if not exists "subject_id" text;
alter table "better_supabase"."funding_awards" add column if not exists "funder_id" uuid;
alter table "better_supabase"."funding_awards" add column if not exists "product_id" uuid;
alter table "better_supabase"."funding_awards" add column if not exists "units" numeric check ("units" > 0);
alter table "better_supabase"."funding_awards" add column if not exists "period" text check ("period" in ('week', 'month', 'total'));
alter table "better_supabase"."funding_awards" add column if not exists "starts_on" date;
alter table "better_supabase"."funding_awards" add column if not exists "ends_on" date;
alter table "better_supabase"."funding_awards" add column if not exists "reference" text check ("reference" is null or length("reference") <= 200);
alter table "better_supabase"."funding_awards" add column if not exists "status" text not null default 'active' check ("status" in ('requested', 'active', 'ended', 'canceled'));
alter table "better_supabase"."funding_awards" add column if not exists "created_by" uuid;
alter table "better_supabase"."funding_awards" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."funding_awards" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_funding_awards_tenant_id_key" on "better_supabase"."funding_awards" ("tenant_id", "id");
create index if not exists "funding_awards_product_idx" on "better_supabase"."funding_awards" ("tenant_id", "product_id");
create index if not exists "funding_awards_subject_idx" on "better_supabase"."funding_awards" ("subject_type", "subject_id");
create index if not exists "funding_awards_funder_idx" on "better_supabase"."funding_awards" ("tenant_id", "funder_id", "status");
alter table "better_supabase"."funding_awards" enable row level security;
grant select on "better_supabase"."funding_awards" to authenticated;
grant all on "better_supabase"."funding_awards" to service_role;
drop policy if exists bsb_funding_awards_read on "better_supabase"."funding_awards";
create policy bsb_funding_awards_read on "better_supabase"."funding_awards"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

-- better_supabase.funding_claims is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."funding_claims" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."funding_claims" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."funding_claims" add column if not exists "funder_id" uuid;
alter table "better_supabase"."funding_claims" add column if not exists "number" text check (length("number") between 1 and 100);
alter table "better_supabase"."funding_claims" add column if not exists "period_start" date;
alter table "better_supabase"."funding_claims" add column if not exists "period_end" date;
alter table "better_supabase"."funding_claims" add column if not exists "format" text check ("format" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$');
alter table "better_supabase"."funding_claims" add column if not exists "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'accepted', 'partially_accepted', 'rejected'));
alter table "better_supabase"."funding_claims" add column if not exists "external_ref" text check ("external_ref" is null or length("external_ref") <= 200);
alter table "better_supabase"."funding_claims" add column if not exists "sent_at" timestamptz;
alter table "better_supabase"."funding_claims" add column if not exists "payload_sha256" text check ("payload_sha256" is null or "payload_sha256" ~ '^[0-9a-f]{64}$');
alter table "better_supabase"."funding_claims" add column if not exists "response" jsonb;
alter table "better_supabase"."funding_claims" add column if not exists "total" bigint not null default 0;
alter table "better_supabase"."funding_claims" add column if not exists "currency" char(3) check ("currency" ~ '^[A-Z]{3}$');
alter table "better_supabase"."funding_claims" add column if not exists "invoice_id" uuid;
alter table "better_supabase"."funding_claims" add column if not exists "created_by" uuid;
alter table "better_supabase"."funding_claims" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."funding_claims" add column if not exists "updated_at" timestamptz not null default now();
create unique index if not exists "bsb_funding_claims_tenant_id_key" on "better_supabase"."funding_claims" ("tenant_id", "id");
create unique index if not exists "funding_claims_number_idx" on "better_supabase"."funding_claims" ("tenant_id", "number");
create index if not exists "funding_claims_funder_idx" on "better_supabase"."funding_claims" ("tenant_id", "funder_id", "status");
alter table "better_supabase"."funding_claims" enable row level security;
grant select on "better_supabase"."funding_claims" to authenticated;
grant all on "better_supabase"."funding_claims" to service_role;
drop policy if exists bsb_funding_claims_read on "better_supabase"."funding_claims";
create policy bsb_funding_claims_read on "better_supabase"."funding_claims"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

-- better_supabase.funding_claim_lines is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."funding_claim_lines" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."funding_claim_lines" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."funding_claim_lines" add column if not exists "claim_id" uuid;
alter table "better_supabase"."funding_claim_lines" add column if not exists "award_id" uuid;
alter table "better_supabase"."funding_claim_lines" add column if not exists "product_id" uuid;
alter table "better_supabase"."funding_claim_lines" add column if not exists "units" numeric check ("units" > 0);
alter table "better_supabase"."funding_claim_lines" add column if not exists "amount" bigint;
alter table "better_supabase"."funding_claim_lines" add column if not exists "status" text not null default 'pending' check ("status" in ('pending', 'accepted', 'rejected'));
alter table "better_supabase"."funding_claim_lines" add column if not exists "rejection_code" text check ("rejection_code" is null or length("rejection_code") <= 100);
create index if not exists "funding_claim_lines_claim_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "claim_id");
create index if not exists "funding_claim_lines_award_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "award_id");
create index if not exists "funding_claim_lines_product_idx" on "better_supabase"."funding_claim_lines" ("tenant_id", "product_id");
alter table "better_supabase"."funding_claim_lines" enable row level security;
grant select on "better_supabase"."funding_claim_lines" to authenticated;
grant all on "better_supabase"."funding_claim_lines" to service_role;
drop policy if exists bsb_funding_claim_lines_read on "better_supabase"."funding_claim_lines";
create policy bsb_funding_claim_lines_read on "better_supabase"."funding_claim_lines"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')));

-- better_supabase.funding_deliveries is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."funding_deliveries" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."funding_deliveries" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."funding_deliveries" add column if not exists "award_id" uuid;
alter table "better_supabase"."funding_deliveries" add column if not exists "source_type" text not null default 'manual' check ("source_type" in ('time_entry', 'booking', 'manual'));
alter table "better_supabase"."funding_deliveries" add column if not exists "source_id" text check ("source_id" is null or length("source_id") <= 200);
alter table "better_supabase"."funding_deliveries" add column if not exists "delivered_on" date;
alter table "better_supabase"."funding_deliveries" add column if not exists "units" numeric check ("units" > 0);
alter table "better_supabase"."funding_deliveries" add column if not exists "performer_id" uuid;
alter table "better_supabase"."funding_deliveries" add column if not exists "status" text not null default 'registered' check ("status" in ('registered', 'approved', 'claimed', 'rejected'));
alter table "better_supabase"."funding_deliveries" add column if not exists "claim_line_id" uuid references "better_supabase"."funding_claim_lines" ("id") on delete set null;
alter table "better_supabase"."funding_deliveries" add column if not exists "note" text check ("note" is null or length("note") <= 2000);
alter table "better_supabase"."funding_deliveries" add column if not exists "created_at" timestamptz not null default now();
create index if not exists "funding_deliveries_award_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "award_id", "delivered_on");
create index if not exists "funding_deliveries_status_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "status", "delivered_on");
create index if not exists "funding_deliveries_claim_line_idx" on "better_supabase"."funding_deliveries" ("claim_line_id");
create unique index if not exists "funding_deliveries_source_idx" on "better_supabase"."funding_deliveries" ("tenant_id", "source_type", "source_id") where "source_id" is not null;
alter table "better_supabase"."funding_deliveries" enable row level security;
grant select on "better_supabase"."funding_deliveries" to authenticated;
grant all on "better_supabase"."funding_deliveries" to service_role;
drop policy if exists bsb_funding_deliveries_read on "better_supabase"."funding_deliveries";
create policy bsb_funding_deliveries_read on "better_supabase"."funding_deliveries"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)));

-- Adds a product a funder pays for, or changes one (product_id): its code,
-- unit and rate in minor units. The code is unique in the organization.
create or replace function "better_supabase"."save_funding_product"(tenant uuid, code text, title text, unit text, rate bigint, currency text, valid_from date default null, valid_until date default null, product_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_products"%rowtype;
  v_code text := nullif(trim(save_funding_product.code), '');
  v_title text := nullif(trim(save_funding_product.title), '');
  v_unit text := nullif(trim(save_funding_product.unit), '');
  v_currency text := upper(nullif(trim(save_funding_product.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_product.tenant, 'funding.manage'), false)) then
    raise exception 'not allowed to manage funding products' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_code is null or length(v_code) > 50 then
    raise exception 'a product needs a code of at most 50 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_title is null or length(v_title) > 300 then
    raise exception 'a product needs a title of at most 300 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_unit is null or v_unit not in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece') then
    raise exception 'unit is minute, hour, day_part, day, visit or piece' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.rate is null or save_funding_product.rate < 0 then
    raise exception 'a rate is zero or more minor units' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.valid_until < save_funding_product.valid_from then
    raise exception 'a product is valid until on or after it is valid from' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."funding_products" x
    where x."tenant_id" = save_funding_product.tenant and x."code" = v_code
      and x."id" is distinct from save_funding_product.product_id
  ) then
    raise exception 'the organization already has a funding product with this code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.product_id is null then
    insert into "better_supabase"."funding_products" ("tenant_id", "code", "title", "unit", "rate", "currency", "valid_from", "valid_until")
    values (save_funding_product.tenant, v_code, v_title, v_unit, save_funding_product.rate, v_currency, save_funding_product.valid_from, save_funding_product.valid_until)
    returning * into v_row;
  else
    update "better_supabase"."funding_products" x set
      "code" = v_code,
      "title" = v_title,
      "unit" = v_unit,
      "rate" = save_funding_product.rate,
      "currency" = v_currency,
      "valid_from" = save_funding_product.valid_from,
      "valid_until" = save_funding_product.valid_until, "updated_at" = now()
    where x."id" = save_funding_product.product_id and x."tenant_id" = save_funding_product.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'title', v_row."title", 'unit', v_row."unit", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_products"(tenant uuid, include_expired boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'title', x."title", 'unit', x."unit", 'rate', x."rate"::text, 'currency', x."currency", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code", x."id"), '[]'::jsonb)
  from "better_supabase"."funding_products" x
  where x."tenant_id" = list_funding_products.tenant
    and (coalesce(list_funding_products.include_expired, false) or x."valid_until" is null or x."valid_until" >= current_date)
$$;
revoke execute on function "better_supabase"."list_funding_products"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_products"(uuid, boolean) to authenticated, service_role;

-- Awards units of a product per period to a record, from a funder in
-- contacts, or changes an award (award_id); a key attrs leaves out keeps its
-- value. attrs holds funderId, productId, units, period (week, month or
-- total), startsOn, endsOn, reference, status (requested or active) and
-- fields, the extra columns by name.
create or replace function "better_supabase"."save_funding_award"(tenant uuid, subject_type text, subject_id text, attrs jsonb, award_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_attrs jsonb := coalesce(save_funding_award.attrs, '{}'::jsonb);
  v_funder uuid;
  v_product uuid;
  v_units numeric;
  v_period text;
  v_starts date;
  v_ends date;
  v_reference text;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_award.tenant, 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  
  if save_funding_award.award_id is null then
    if not false then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else null end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else null end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else null end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else null end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else null end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else null end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else null end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else 'active' end;
  else
    select * into v_row from "better_supabase"."funding_awards" x
    where x."id" = save_funding_award.award_id and x."tenant_id" = save_funding_award.tenant
    for update;
    if not found then
      raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
    end if;
    if v_row."subject_type" <> save_funding_award.subject_type or v_row."subject_id" <> save_funding_award.subject_id then
      raise exception 'an award stays with its record' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_row."status" in ('ended', 'canceled') then
      raise exception 'the funding award has ended' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else v_row."funder_id" end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else v_row."product_id" end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else v_row."units" end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else v_row."period" end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else v_row."ends_on" end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else v_row."reference" end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else v_row."status" end;
  end if;
  if v_funder is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = v_funder and x."tenant_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if v_product is null or not exists (select 1 from "better_supabase"."funding_products" x where x."id" = v_product and x."tenant_id" = save_funding_award.tenant) then
    raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
  end if;
  if v_units is null or v_units <= 0 then
    raise exception 'an award needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_period is null or v_period not in ('week', 'month', 'total') then
    raise exception 'period is week, month or total' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an award needs a start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an award ends on or after its start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_reference is not null and length(v_reference) > 200 then
    raise exception 'reference is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_status is null or v_status not in ('requested', 'active') then
    raise exception 'a saved award is requested or active; end_funding_award ends it' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_award_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_attrs;
    end if;
  end;
  if save_funding_award.award_id is null then
    insert into "better_supabase"."funding_awards" ("tenant_id", "subject_type", "subject_id", "funder_id", "product_id", "units", "period", "starts_on", "ends_on", "reference", "status", "created_by")
    values (save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_funder, v_product, v_units, v_period, v_starts, v_ends, v_reference, v_status, (select auth.uid()))
    returning * into v_row;
    null;
  else
    update "better_supabase"."funding_awards" x set
    "funder_id" = v_funder,
    "product_id" = v_product,
    "units" = v_units,
    "period" = v_period,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "reference" = v_reference,
    "status" = v_status, "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_award_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) to authenticated, service_role;

-- Ends an award on ends_on (today by default), or cancels it (canceled).
-- Deliveries already registered stay.
create or replace function "better_supabase"."end_funding_award"(award_id uuid, ends_on date default null, canceled boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_ends date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."funding_awards" x where x."id" = end_funding_award.award_id for update;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_row."status" in ('ended', 'canceled') then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  v_ends := case
    when coalesce(end_funding_award.canceled, false) then coalesce(end_funding_award.ends_on, v_row."ends_on")
    else coalesce(end_funding_award.ends_on, least(current_date, coalesce(v_row."ends_on", current_date)))
  end;
  if v_ends is not null and v_ends < v_row."starts_on" then
    if coalesce(end_funding_award.canceled, false) then
      v_ends := null;
    else
      raise exception 'an award ends on or after its start date; cancel it instead' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end if;
  update "better_supabase"."funding_awards" x set
    "status" = case when coalesce(end_funding_award.canceled, false) then 'canceled' else 'ended' end,
    "ends_on" = v_ends, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) from public, anon;
grant execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_awards"(tenant uuid, subject_type text default null, subject_id text default null, include_ended boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'funderId', x."funder_id", 'productId', x."product_id", 'units', x."units", 'period', x."period", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'reference', x."reference", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('product', jsonb_build_object('id', y."id", 'organizationId', y."tenant_id", 'code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text, 'currency', y."currency", 'validFrom', y."valid_from", 'validUntil', y."valid_until", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."funding_awards" x
  join "better_supabase"."funding_products" y on y."tenant_id" = x."tenant_id" and y."id" = x."product_id"
  where x."tenant_id" = list_funding_awards.tenant
    and (list_funding_awards.subject_type is null or x."subject_type" = list_funding_awards.subject_type)
    and (list_funding_awards.subject_id is null or x."subject_id" = list_funding_awards.subject_id)
    and (coalesce(list_funding_awards.include_ended, false) or x."status" in ('requested', 'active'))
$$;
revoke execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) to authenticated, service_role;

-- The units used against the units awarded, per period of the award from its
-- start to its end (today while it runs). Rejected deliveries don't count.
create or replace function "better_supabase"."funding_award_usage"(award_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'awardId', a."id",
    'units', a."units",
    'period', a."period",
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', s.start,
        'end', nullif(s.finish, 'infinity'::date) - 1,
        'awarded', a."units",
        'used', s.used,
        'over', greatest(s.used - a."units", 0),
        'under', greatest(a."units" - s.used, 0)
      ) order by s.start)
      from (
        select g.start, (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end) as finish, (
          select coalesce(sum(x."units"), 0) from "better_supabase"."funding_deliveries" x
          where x."tenant_id" = a."tenant_id" and x."award_id" = a."id" and x."status" <> 'rejected'
            and x."delivered_on" >= g.start and x."delivered_on" < (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end)
        ) as used
        from (
          select pg_catalog.generate_series(
            (case a."period" when 'week' then date_trunc('week', a."starts_on")::date when 'month' then date_trunc('month', a."starts_on")::date else a."starts_on" end)::timestamp,
            coalesce(a."ends_on", current_date)::timestamp,
            case a."period" when 'week' then interval '1 week' else interval '1 month' end
          )::date as start
          where a."period" <> 'total'
          union all
          select a."starts_on" where a."period" = 'total'
        ) g
      ) s
    ), '[]'::jsonb)
  )
  from "better_supabase"."funding_awards" a
  where a."id" = funding_award_usage.award_id
$$;
revoke execute on function "better_supabase"."funding_award_usage"(uuid) from public, anon;
grant execute on function "better_supabase"."funding_award_usage"(uuid) to authenticated, service_role;

-- Registers care delivered on an award: units on a day, from a time entry, a
-- booking or by hand (manual). A source registered before returns its
-- delivery, so registering it twice is safe. Crossing the units of a period
-- emits funding_award.exceeded.
create or replace function "better_supabase"."register_funding_delivery"(award_id uuid, delivered_on date, units numeric, source_type text default 'manual', source_id text default null, performer_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_award "better_supabase"."funding_awards"%rowtype;
  v_product "better_supabase"."funding_products"%rowtype;
  v_source text := coalesce(nullif(trim(register_funding_delivery.source_type), ''), 'manual');
  v_source_id text := nullif(trim(register_funding_delivery.source_id), '');
  v_note text := nullif(trim(register_funding_delivery.note), '');
  v_start date;
  v_used numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_award from "better_supabase"."funding_awards" x where x."id" = register_funding_delivery.award_id;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_award."tenant_id", 'funding.register'), false)) then
    raise exception 'not allowed to register funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_source not in ('time_entry', 'booking', 'manual') then
    raise exception 'source_type is time_entry, booking or manual' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source <> 'manual' and v_source_id is null then
    raise exception 'a delivery from a time entry or booking needs its source_id' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source_id is not null then
    select * into v_row from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = v_award."tenant_id" and x."source_type" = v_source and x."source_id" = v_source_id;
    if found then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
    end if;
  end if;
  if register_funding_delivery.delivered_on is null then
    raise exception 'a delivery needs the day it was delivered' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if register_funding_delivery.units is null or register_funding_delivery.units <= 0 then
    raise exception 'a delivery needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_award."status" <> 'active'
    or register_funding_delivery.delivered_on < v_award."starts_on"
    or register_funding_delivery.delivered_on > coalesce(v_award."ends_on", register_funding_delivery.delivered_on) then
    raise exception 'the funding award isn''t active on that day' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
  end if;
  select * into v_product from "better_supabase"."funding_products" x where x."tenant_id" = v_award."tenant_id" and x."id" = v_award."product_id";
  if (v_product."valid_from" is not null and register_funding_delivery.delivered_on < v_product."valid_from")
    or (v_product."valid_until" is not null and register_funding_delivery.delivered_on > v_product."valid_until") then
    raise exception 'the funding product isn''t valid on that day' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_delivery_register"(uuid, date, numeric)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::date, $3::numeric)', v_hook::oid::regproc)
        using v_award."id", register_funding_delivery.delivered_on, register_funding_delivery.units;
    end if;
  end;
  insert into "better_supabase"."funding_deliveries" ("tenant_id", "award_id", "source_type", "source_id", "delivered_on", "units", "performer_id", "note")
  values (v_award."tenant_id", v_award."id", v_source, v_source_id, register_funding_delivery.delivered_on, register_funding_delivery.units, coalesce(register_funding_delivery.performer_id, (select auth.uid())), v_note)
  returning * into v_row;
  null;
  v_start := (case v_award."period" when 'week' then date_trunc('week', v_row."delivered_on")::date when 'month' then date_trunc('month', v_row."delivered_on")::date else v_award."starts_on" end);
  select coalesce(sum(x."units"), 0) into v_used from "better_supabase"."funding_deliveries" x
  where x."tenant_id" = v_award."tenant_id" and x."award_id" = v_award."id" and x."status" <> 'rejected'
    and x."delivered_on" >= v_start and x."delivered_on" < (case v_award."period" when 'week' then (v_start + 7) when 'month' then (v_start + interval '1 month')::date else coalesce(v_award."ends_on" + 1, 'infinity'::date) end);
  if v_used > v_award."units" and v_used - v_row."units" <= v_award."units" then
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_delivery_register"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) to authenticated, service_role;

-- Approves registered deliveries for a claim (approved true) or rejects them.
-- A delivery a claim holds can't change. Returns how many changed.
create or replace function "better_supabase"."approve_funding_deliveries"(ids uuid[], approved boolean default true)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_status text := case when coalesce(approve_funding_deliveries.approved, true) then 'approved' else 'rejected' end;
  v_found integer := 0;
  v_changed integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    select * from "better_supabase"."funding_deliveries" x
    where x."id" = any (coalesce(approve_funding_deliveries.ids, '{}'::uuid[]))
    order by x."id"
    for update
  loop
    v_found := v_found + 1;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'funding.approve'), false)) then
      raise exception 'not allowed to approve funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
    end if;
    if v_row."status" = 'claimed' then
      raise exception 'a claim holds this delivery' using errcode = '22023', hint = 'FUNDING_DELIVERY_CLAIMED';
    end if;
    if v_row."status" <> v_status then
      update "better_supabase"."funding_deliveries" x set "status" = v_status where x."id" = v_row."id";
      v_changed := v_changed + 1;
    end if;
  end loop;
  if v_found < (select count(distinct i) from unnest(coalesce(approve_funding_deliveries.ids, '{}'::uuid[])) i) then
    raise exception 'funding delivery not found' using errcode = 'P0002', hint = 'FUNDING_DELIVERY_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) to authenticated, service_role;

-- The deliveries of an organization, newest first. filter holds awardId,
-- status, since and until (days), and limit (500 by default, 1000 at most).
create or replace function "better_supabase"."list_funding_deliveries"(tenant uuid, filter jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.row order by z.day desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'awardId', x."award_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'deliveredOn', x."delivered_on", 'units', x."units", 'performerId', x."performer_id", 'status', x."status", 'claimLineId', x."claim_line_id", 'note', x."note", 'createdAt', x."created_at") as row, x."delivered_on" as day, x."id" as id
    from "better_supabase"."funding_deliveries" x
    where x."tenant_id" = list_funding_deliveries.tenant
      and (list_funding_deliveries.filter ->> 'awardId' is null or x."award_id" = (list_funding_deliveries.filter ->> 'awardId')::uuid)
      and (list_funding_deliveries.filter ->> 'status' is null or x."status" = list_funding_deliveries.filter ->> 'status')
      and (list_funding_deliveries.filter ->> 'since' is null or x."delivered_on" >= (list_funding_deliveries.filter ->> 'since')::date)
      and (list_funding_deliveries.filter ->> 'until' is null or x."delivered_on" <= (list_funding_deliveries.filter ->> 'until')::date)
    order by x."delivered_on" desc, x."id"
    limit least(greatest(coalesce((list_funding_deliveries.filter ->> 'limit')::integer, 500), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) to authenticated, service_role;

-- Gathers the approved deliveries of a funder from period_start to
-- period_end into a draft claim in format (a FundingClaimFormat key), one
-- line per award, priced at the product rate. The deliveries become claimed.
create or replace function "better_supabase"."build_funding_claim"(tenant uuid, funder_id uuid, period_start date, period_end date, format text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_format text := nullif(trim(build_funding_claim.format), '');
  v_currencies integer;
  v_currency text;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', build_funding_claim.tenant, 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_format is null or v_format !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'the claim format isn''t one this organization claims in' using errcode = '22023', hint = 'FUNDING_FORMAT_UNKNOWN';
  end if;
  if build_funding_claim.funder_id is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = build_funding_claim.funder_id and x."tenant_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if build_funding_claim.period_start is null or build_funding_claim.period_end is null
    or build_funding_claim.period_end < build_funding_claim.period_start then
    raise exception 'a claim period ends on or after it starts' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_claim_build"(uuid, uuid, date, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date, $4::date)', v_hook::oid::regproc)
        using build_funding_claim.tenant, build_funding_claim.funder_id, build_funding_claim.period_start, build_funding_claim.period_end;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb_funding_claim:' || build_funding_claim.tenant::text, 0));
  perform 1 from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  for update of x;
  select count(distinct y."currency"), min(y."currency") into v_currencies, v_currency
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  if v_currencies = 0 then
    raise exception 'no approved deliveries of this funder in the period' using errcode = '22023', hint = 'FUNDING_CLAIM_EMPTY';
  end if;
  if v_currencies > 1 then
    raise exception 'the deliveries are priced in several currencies; claim each product''s currency apart' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  select coalesce(max(x."number"::bigint) filter (where x."number" ~ '^[0-9]{1,18}$'), 0) + 1 into v_seq
  from "better_supabase"."funding_claims" x where x."tenant_id" = build_funding_claim.tenant;
  v_number := v_seq::text;
  insert into "better_supabase"."funding_claims" ("tenant_id", "funder_id", "number", "period_start", "period_end", "format", "currency", "created_by")
  values (build_funding_claim.tenant, build_funding_claim.funder_id, v_number, build_funding_claim.period_start, build_funding_claim.period_end, v_format, v_currency, (select auth.uid()))
  returning * into v_claim;
  insert into "better_supabase"."funding_claim_lines" ("tenant_id", "claim_id", "award_id", "product_id", "units", "amount")
  select build_funding_claim.tenant, v_claim."id", a."id", y."id", sum(x."units"), round(sum(x."units") * y."rate")::bigint
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."tenant_id" = x."tenant_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = a."tenant_id" and y."id" = a."product_id"
    where x."tenant_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  group by a."id", y."id", y."rate";
  update "better_supabase"."funding_deliveries" x set "status" = 'claimed', "claim_line_id" = z."id"
  from "better_supabase"."funding_claim_lines" z
  where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
    and x."tenant_id" = z."tenant_id" and x."award_id" = z."award_id"
    and x."status" = 'approved' and x."claim_line_id" is null
    and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  update "better_supabase"."funding_claims" x set "total" = (
    select coalesce(sum(z."amount"), 0) from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  )
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_claim_build"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_claim."id";
    end if;
  end;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) from public, anon;
grant execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) to authenticated, service_role;

-- A claim with its lines, each with its award, product and deliveries: what a
-- FundingClaimFormat renders.
create or replace function "better_supabase"."get_funding_claim"(claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = get_funding_claim.claim_id;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.read'), false)) then
    raise exception 'not allowed to read funding claims' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."get_funding_claim"(uuid) to authenticated, service_role;

-- Marks a draft claim sent, with the channel's reference and the SHA-256 of
-- the file that was sent.
create or replace function "better_supabase"."mark_funding_claim_sent"(claim_id uuid, external_ref text default null, payload_sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_ref text := nullif(trim(mark_funding_claim_sent.external_ref), '');
  v_sha text := lower(nullif(trim(mark_funding_claim_sent.payload_sha256), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = mark_funding_claim_sent.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'external_ref is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'payload_sha256 is a SHA-256 in hex' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  update "better_supabase"."funding_claims" x set "status" = 'sent', "sent_at" = now(), "external_ref" = v_ref, "payload_sha256" = v_sha, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at");
end;
$$;
revoke execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) to authenticated, service_role;

-- Records the funder's response to a sent claim: lines is an array of
-- { lineId, status (accepted or rejected), rejectionCode }, or null for
-- none. A line the response leaves out is accepted. The deliveries of a rejected line go back
-- to approved, for correction and a later claim.
create or replace function "better_supabase"."record_funding_claim_response"(claim_id uuid, lines jsonb, response jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_line jsonb;
  v_status text;
  v_code text;
  v_accepted integer;
  v_rejected integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = record_funding_claim_response.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'sent' then
    raise exception 'only a sent claim takes a response' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if jsonb_typeof(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) <> 'array' then
    raise exception 'lines is an array' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_line in select value from jsonb_array_elements(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) loop
    v_status := v_line ->> 'status';
    v_code := nullif(trim(v_line ->> 'rejectionCode'), '');
    if jsonb_typeof(v_line) <> 'object' or v_status is null or v_status not in ('accepted', 'rejected') then
      raise exception 'each line has a lineId and a status of accepted or rejected' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_code is not null and length(v_code) > 100 then
      raise exception 'a rejection code is at most 100 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    update "better_supabase"."funding_claim_lines" x set "status" = v_status, "rejection_code" = case when v_status = 'rejected' then v_code end
    where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id"
      and x."id"::text = v_line ->> 'lineId';
    if not found then
      raise exception 'a line in the response isn''t a line of this claim' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end loop;
  update "better_supabase"."funding_claim_lines" x set "status" = 'accepted'
  where x."tenant_id" = v_claim."tenant_id" and x."claim_id" = v_claim."id" and x."status" = 'pending';
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id" and z."status" = 'rejected');
  select count(*) filter (where z."status" = 'accepted'), count(*) filter (where z."status" = 'rejected')
  into v_accepted, v_rejected
  from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id";
  update "better_supabase"."funding_claims" x set
    "status" = case when v_rejected = 0 then 'accepted' when v_accepted = 0 then 'rejected' else 'partially_accepted' end,
    "response" = record_funding_claim_response.response, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."tenant_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."tenant_id" = z."tenant_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."tenant_id" = z."tenant_id" and y."id" = z."product_id"
    where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Deletes a draft claim; its deliveries go back to approved.
create or replace function "better_supabase"."delete_funding_claim"(claim_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = delete_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."tenant_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."tenant_id" = v_claim."tenant_id" and z."claim_id" = v_claim."id");
  delete from "better_supabase"."funding_claims" x where x."id" = v_claim."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_funding_claim"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_claims"(tenant uuid, status text default null, funder_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'funderId', x."funder_id", 'number', x."number", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'format', x."format", 'status', x."status", 'externalRef', x."external_ref", 'sentAt', x."sent_at", 'payloadSha256', x."payload_sha256", 'response', x."response", 'total', x."total"::text, 'currency', x."currency", 'invoiceId', x."invoice_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."number" desc), '[]'::jsonb)
  from "better_supabase"."funding_claims" x
  where x."tenant_id" = list_funding_claims.tenant
    and (list_funding_claims.status is null or x."status" = list_funding_claims.status)
    and (list_funding_claims.funder_id is null or x."funder_id" = list_funding_claims.funder_id)
$$;
revoke execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
create policy bsb_tenant_scope_select on "better_supabase"."funding_products" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_products" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
create policy bsb_tenant_scope_update on "better_supabase"."funding_products" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_products" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_select on "better_supabase"."funding_awards" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_awards" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_update on "better_supabase"."funding_awards" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_awards" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_select on "better_supabase"."funding_deliveries" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."tenant_id" = "tenant_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_deliveries" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_update on "better_supabase"."funding_deliveries" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_deliveries" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claims" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claims" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claims" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claims" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claim_lines" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claim_lines" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines" as restrictive
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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block-data funding
-- @bsb-hash sha256:5f2aaa76a9d6c8414def54826e938bc7edcce178f14b0d9edd894653bfab3d11
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block funding@1 managed
-- @bsb-hash sha256:d18eea1ea0980a19103a6b4367a00a4b626f2ed2e10cbd5753b4617bc7f1b7c2
-- Products a funder pays for, awards of units per period to a record from a funder in contacts, care delivered against an award from time entries, bookings or by hand, usage against the award per period, and claims per funder and period with the funder's response per line, rendered and sent through app-supplied formats and channels.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Funding: the products a funder pays for, awards of units per period to a
-- record, the care delivered against them, and claims to the funder with its
-- response per line.

create table if not exists "better_supabase"."funding_products" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  -- The funder's product code, such as 45A48 for a Wlz product.
  "code" text not null check (length("code") between 1 and 50),
  "title" text not null check (length("title") between 1 and 300),
  "unit" text not null check ("unit" in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece')),
  -- The price of one unit, in minor units of currency.
  "rate" bigint not null check ("rate" >= 0),
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "valid_from" date,
  "valid_until" date,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("valid_until" is null or "valid_from" is null or "valid_until" >= "valid_from"),
  unique ("org_id", "id")
);
create unique index if not exists "funding_products_code_idx" on "better_supabase"."funding_products" ("org_id", "code");
alter table "better_supabase"."funding_products" enable row level security;
revoke all on "better_supabase"."funding_products" from public, anon, authenticated;
grant select on "better_supabase"."funding_products" to authenticated;
grant all on "better_supabase"."funding_products" to service_role;
drop policy if exists funding_products_read on "better_supabase"."funding_products";
create policy funding_products_read on "better_supabase"."funding_products"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_awards" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  -- The record the award is for, a type in config.subjects.
  "subject_type" text not null,
  "subject_id" text not null,
  -- The contacts company or person that pays, holding the funder role.
  "funder_id" uuid not null,
  "product_id" uuid not null,
  -- The units awarded per period.
  "units" numeric not null check ("units" > 0),
  "period" text not null check ("period" in ('week', 'month', 'total')),
  "starts_on" date not null,
  "ends_on" date,
  -- The funder's reference for the award, such as an indication number.
  "reference" text check ("reference" is null or length("reference") <= 200),
  "status" text not null default 'active' check ("status" in ('requested', 'active', 'ended', 'canceled')),
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("ends_on" is null or "ends_on" >= "starts_on"),
  unique ("org_id", "id"),
  foreign key ("org_id", "product_id") references "better_supabase"."funding_products" ("org_id", "id")
);
create index if not exists "funding_awards_product_idx" on "better_supabase"."funding_awards" ("org_id", "product_id");
create index if not exists "funding_awards_subject_idx" on "better_supabase"."funding_awards" ("subject_type", "subject_id");
create index if not exists "funding_awards_funder_idx" on "better_supabase"."funding_awards" ("org_id", "funder_id", "status");
alter table "better_supabase"."funding_awards" enable row level security;
revoke all on "better_supabase"."funding_awards" from public, anon, authenticated;
grant select on "better_supabase"."funding_awards" to authenticated;
grant all on "better_supabase"."funding_awards" to service_role;
drop policy if exists funding_awards_read on "better_supabase"."funding_awards";
create policy funding_awards_read on "better_supabase"."funding_awards"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false));

create table if not exists "better_supabase"."funding_claims" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "funder_id" uuid not null,
  "number" text not null check (length("number") between 1 and 100),
  "period_start" date not null,
  "period_end" date not null,
  -- The FundingClaimFormat key that renders the claim, such as iwlz-aw319.
  "format" text not null check ("format" ~ '^[a-z0-9][a-z0-9_.-]{0,62}$'),
  "status" text not null default 'draft' check ("status" in ('draft', 'sent', 'accepted', 'partially_accepted', 'rejected')),
  -- The funder's or the channel's reference for the sent claim.
  "external_ref" text check ("external_ref" is null or length("external_ref") <= 200),
  "sent_at" timestamptz,
  -- The SHA-256 of the rendered file that was sent, in hex.
  "payload_sha256" text check ("payload_sha256" is null or "payload_sha256" ~ '^[0-9a-f]{64}$'),
  -- The funder's response as the format parsed it.
  "response" jsonb,
  "total" bigint not null default 0,
  "currency" char(3) not null check ("currency" ~ '^[A-Z]{3}$'),
  "invoice_id" uuid,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  check ("period_end" >= "period_start"),
  unique ("org_id", "id")
);
create unique index if not exists "funding_claims_number_idx" on "better_supabase"."funding_claims" ("org_id", "number");
create index if not exists "funding_claims_funder_idx" on "better_supabase"."funding_claims" ("org_id", "funder_id", "status");
alter table "better_supabase"."funding_claims" enable row level security;
revoke all on "better_supabase"."funding_claims" from public, anon, authenticated;
grant select on "better_supabase"."funding_claims" to authenticated;
grant all on "better_supabase"."funding_claims" to service_role;
drop policy if exists funding_claims_read on "better_supabase"."funding_claims";
create policy funding_claims_read on "better_supabase"."funding_claims"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_claim_lines" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "claim_id" uuid not null,
  "award_id" uuid not null,
  "product_id" uuid not null,
  "units" numeric not null check ("units" > 0),
  -- The units times the product rate, in minor units of the claim currency.
  "amount" bigint not null,
  "status" text not null default 'pending' check ("status" in ('pending', 'accepted', 'rejected')),
  -- The funder's code for a rejected line.
  "rejection_code" text check ("rejection_code" is null or length("rejection_code") <= 100),
  foreign key ("org_id", "claim_id") references "better_supabase"."funding_claims" ("org_id", "id") on delete cascade,
  foreign key ("org_id", "award_id") references "better_supabase"."funding_awards" ("org_id", "id"),
  foreign key ("org_id", "product_id") references "better_supabase"."funding_products" ("org_id", "id")
);
create index if not exists "funding_claim_lines_claim_idx" on "better_supabase"."funding_claim_lines" ("org_id", "claim_id");
create index if not exists "funding_claim_lines_award_idx" on "better_supabase"."funding_claim_lines" ("org_id", "award_id");
create index if not exists "funding_claim_lines_product_idx" on "better_supabase"."funding_claim_lines" ("org_id", "product_id");
alter table "better_supabase"."funding_claim_lines" enable row level security;
revoke all on "better_supabase"."funding_claim_lines" from public, anon, authenticated;
grant select on "better_supabase"."funding_claim_lines" to authenticated;
grant all on "better_supabase"."funding_claim_lines" to service_role;
drop policy if exists funding_claim_lines_read on "better_supabase"."funding_claim_lines";
create policy funding_claim_lines_read on "better_supabase"."funding_claim_lines"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('funding.read')));

create table if not exists "better_supabase"."funding_deliveries" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "award_id" uuid not null,
  -- Where the delivery came from; source_id is the time entry or booking id.
  "source_type" text not null default 'manual' check ("source_type" in ('time_entry', 'booking', 'manual')),
  "source_id" text check ("source_id" is null or length("source_id") <= 200),
  "delivered_on" date not null,
  "units" numeric not null check ("units" > 0),
  "performer_id" uuid,
  "status" text not null default 'registered' check ("status" in ('registered', 'approved', 'claimed', 'rejected')),
  -- The claim line that claims it, once a claim gathered it.
  "claim_line_id" uuid references "better_supabase"."funding_claim_lines" ("id") on delete set null,
  "note" text check ("note" is null or length("note") <= 2000),
  "created_at" timestamptz not null default now(),
  check ("source_type" = 'manual' or "source_id" is not null),
  foreign key ("org_id", "award_id") references "better_supabase"."funding_awards" ("org_id", "id") on delete cascade
);
create index if not exists "funding_deliveries_award_idx" on "better_supabase"."funding_deliveries" ("org_id", "award_id", "delivered_on");
create index if not exists "funding_deliveries_status_idx" on "better_supabase"."funding_deliveries" ("org_id", "status", "delivered_on");
create index if not exists "funding_deliveries_claim_line_idx" on "better_supabase"."funding_deliveries" ("claim_line_id");
create unique index if not exists "funding_deliveries_source_idx" on "better_supabase"."funding_deliveries" ("org_id", "source_type", "source_id") where "source_id" is not null;
alter table "better_supabase"."funding_deliveries" enable row level security;
revoke all on "better_supabase"."funding_deliveries" from public, anon, authenticated;
grant select on "better_supabase"."funding_deliveries" to authenticated;
grant all on "better_supabase"."funding_deliveries" to service_role;
drop policy if exists funding_deliveries_read on "better_supabase"."funding_deliveries";
create policy funding_deliveries_read on "better_supabase"."funding_deliveries"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."org_id" = "org_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)));

-- Adds a product a funder pays for, or changes one (product_id): its code,
-- unit and rate in minor units. The code is unique in the organization.
create or replace function "better_supabase"."save_funding_product"(tenant uuid, code text, title text, unit text, rate bigint, currency text, valid_from date default null, valid_until date default null, product_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_products"%rowtype;
  v_code text := nullif(trim(save_funding_product.code), '');
  v_title text := nullif(trim(save_funding_product.title), '');
  v_unit text := nullif(trim(save_funding_product.unit), '');
  v_currency text := upper(nullif(trim(save_funding_product.currency), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_product.tenant, 'funding.manage'), false)) then
    raise exception 'not allowed to manage funding products' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_code is null or length(v_code) > 50 then
    raise exception 'a product needs a code of at most 50 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_title is null or length(v_title) > 300 then
    raise exception 'a product needs a title of at most 300 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_unit is null or v_unit not in ('minute', 'hour', 'day_part', 'day', 'visit', 'piece') then
    raise exception 'unit is minute, hour, day_part, day, visit or piece' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.rate is null or save_funding_product.rate < 0 then
    raise exception 'a rate is zero or more minor units' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_currency is null or v_currency !~ '^[A-Z]{3}$' then
    raise exception 'currency is a three-letter ISO 4217 code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.valid_until < save_funding_product.valid_from then
    raise exception 'a product is valid until on or after it is valid from' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."funding_products" x
    where x."org_id" = save_funding_product.tenant and x."code" = v_code
      and x."id" is distinct from save_funding_product.product_id
  ) then
    raise exception 'the organization already has a funding product with this code' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if save_funding_product.product_id is null then
    insert into "better_supabase"."funding_products" ("org_id", "code", "title", "unit", "rate", "currency", "valid_from", "valid_until")
    values (save_funding_product.tenant, v_code, v_title, v_unit, save_funding_product.rate, v_currency, save_funding_product.valid_from, save_funding_product.valid_until)
    returning * into v_row;
  else
    update "better_supabase"."funding_products" x set
      "code" = v_code,
      "title" = v_title,
      "unit" = v_unit,
      "rate" = save_funding_product.rate,
      "currency" = v_currency,
      "valid_from" = save_funding_product.valid_from,
      "valid_until" = save_funding_product.valid_until, "updated_at" = now()
    where x."id" = save_funding_product.product_id and x."org_id" = save_funding_product.tenant
    returning x.* into v_row;
    if not found then
      raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'code', v_row."code", 'title', v_row."title", 'unit', v_row."unit", 'rate', v_row."rate"::text, 'currency', v_row."currency", 'validFrom', v_row."valid_from", 'validUntil', v_row."valid_until", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_product"(uuid, text, text, text, bigint, text, date, date, uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_products"(tenant uuid, include_expired boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'code', x."code", 'title', x."title", 'unit', x."unit", 'rate', x."rate"::text, 'currency', x."currency", 'validFrom', x."valid_from", 'validUntil', x."valid_until", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code", x."id"), '[]'::jsonb)
  from "better_supabase"."funding_products" x
  where x."org_id" = list_funding_products.tenant
    and (coalesce(list_funding_products.include_expired, false) or x."valid_until" is null or x."valid_until" >= current_date)
$$;
revoke execute on function "better_supabase"."list_funding_products"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_products"(uuid, boolean) to authenticated, service_role;

-- Awards units of a product per period to a record, from a funder in
-- contacts, or changes an award (award_id); a key attrs leaves out keeps its
-- value. attrs holds funderId, productId, units, period (week, month or
-- total), startsOn, endsOn, reference, status (requested or active) and
-- fields, the extra columns by name.
create or replace function "better_supabase"."save_funding_award"(tenant uuid, subject_type text, subject_id text, attrs jsonb, award_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_attrs jsonb := coalesce(save_funding_award.attrs, '{}'::jsonb);
  v_funder uuid;
  v_product uuid;
  v_units numeric;
  v_period text;
  v_starts date;
  v_ends date;
  v_reference text;
  v_status text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_funding_award.tenant, 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if jsonb_typeof(v_attrs) <> 'object' then
    raise exception 'attrs is an object' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  
  if save_funding_award.award_id is null then
    if not false then
      raise exception 'the record isn''t in this organization' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else null end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else null end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else null end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else null end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else null end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else null end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else null end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else 'active' end;
  else
    select * into v_row from "better_supabase"."funding_awards" x
    where x."id" = save_funding_award.award_id and x."org_id" = save_funding_award.tenant
    for update;
    if not found then
      raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
    end if;
    if v_row."subject_type" <> save_funding_award.subject_type or v_row."subject_id" <> save_funding_award.subject_id then
      raise exception 'an award stays with its record' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_row."status" in ('ended', 'canceled') then
      raise exception 'the funding award has ended' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
    end if;
    v_funder := case when v_attrs ? 'funderId' then nullif(trim(v_attrs ->> 'funderId'), '')::uuid else v_row."funder_id" end;
  v_product := case when v_attrs ? 'productId' then nullif(trim(v_attrs ->> 'productId'), '')::uuid else v_row."product_id" end;
  v_units := case when v_attrs ? 'units' then nullif(trim(v_attrs ->> 'units'), '')::numeric else v_row."units" end;
  v_period := case when v_attrs ? 'period' then nullif(trim(v_attrs ->> 'period'), '') else v_row."period" end;
  v_starts := case when v_attrs ? 'startsOn' then nullif(trim(v_attrs ->> 'startsOn'), '')::date else v_row."starts_on" end;
  v_ends := case when v_attrs ? 'endsOn' then nullif(trim(v_attrs ->> 'endsOn'), '')::date else v_row."ends_on" end;
  v_reference := case when v_attrs ? 'reference' then nullif(trim(v_attrs ->> 'reference'), '') else v_row."reference" end;
  v_status := case when v_attrs ? 'status' then nullif(trim(v_attrs ->> 'status'), '') else v_row."status" end;
  end if;
  if v_funder is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = v_funder and x."org_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = v_funder and x."org_id" = save_funding_award.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if v_product is null or not exists (select 1 from "better_supabase"."funding_products" x where x."id" = v_product and x."org_id" = save_funding_award.tenant) then
    raise exception 'funding product not found' using errcode = 'P0002', hint = 'FUNDING_PRODUCT_NOT_FOUND';
  end if;
  if v_units is null or v_units <= 0 then
    raise exception 'an award needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_period is null or v_period not in ('week', 'month', 'total') then
    raise exception 'period is week, month or total' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_starts is null then
    raise exception 'an award needs a start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_ends is not null and v_ends < v_starts then
    raise exception 'an award ends on or after its start date' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_reference is not null and length(v_reference) > 200 then
    raise exception 'reference is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_status is null or v_status not in ('requested', 'active') then
    raise exception 'a saved award is requested or active; end_funding_award ends it' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_award_save"(uuid, text, text, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::text, $3::text, $4::jsonb)', v_hook::oid::regproc)
        using save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_attrs;
    end if;
  end;
  if save_funding_award.award_id is null then
    insert into "better_supabase"."funding_awards" ("org_id", "subject_type", "subject_id", "funder_id", "product_id", "units", "period", "starts_on", "ends_on", "reference", "status", "created_by")
    values (save_funding_award.tenant, save_funding_award.subject_type, save_funding_award.subject_id, v_funder, v_product, v_units, v_period, v_starts, v_ends, v_reference, v_status, (select auth.uid()))
    returning * into v_row;
    null;
  else
    update "better_supabase"."funding_awards" x set
    "funder_id" = v_funder,
    "product_id" = v_product,
    "units" = v_units,
    "period" = v_period,
    "starts_on" = v_starts,
    "ends_on" = v_ends,
    "reference" = v_reference,
    "status" = v_status, "updated_at" = now()
    where x."id" = v_row."id"
    returning x.* into v_row;
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_award_save"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) from public, anon;
grant execute on function "better_supabase"."save_funding_award"(uuid, text, text, jsonb, uuid) to authenticated, service_role;

-- Ends an award on ends_on (today by default), or cancels it (canceled).
-- Deliveries already registered stay.
create or replace function "better_supabase"."end_funding_award"(award_id uuid, ends_on date default null, canceled boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_awards"%rowtype;
  v_ends date;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."funding_awards" x where x."id" = end_funding_award.award_id for update;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'funding.write'), false)) then
    raise exception 'not allowed to change funding awards' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_row."status" in ('ended', 'canceled') then
    return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
  end if;
  v_ends := case
    when coalesce(end_funding_award.canceled, false) then coalesce(end_funding_award.ends_on, v_row."ends_on")
    else coalesce(end_funding_award.ends_on, least(current_date, coalesce(v_row."ends_on", current_date)))
  end;
  if v_ends is not null and v_ends < v_row."starts_on" then
    if coalesce(end_funding_award.canceled, false) then
      v_ends := null;
    else
      raise exception 'an award ends on or after its start date; cancel it instead' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end if;
  update "better_supabase"."funding_awards" x set
    "status" = case when coalesce(end_funding_award.canceled, false) then 'canceled' else 'ended' end,
    "ends_on" = v_ends, "updated_at" = now()
  where x."id" = v_row."id"
  returning x.* into v_row;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'funderId', v_row."funder_id", 'productId', v_row."product_id", 'units', v_row."units", 'period', v_row."period", 'startsOn', v_row."starts_on", 'endsOn', v_row."ends_on", 'reference', v_row."reference", 'status', v_row."status", 'createdBy', v_row."created_by", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) from public, anon;
grant execute on function "better_supabase"."end_funding_award"(uuid, date, boolean) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_awards"(tenant uuid, subject_type text default null, subject_id text default null, include_ended boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'subjectType', x."subject_type", 'subjectId', x."subject_id", 'funderId', x."funder_id", 'productId', x."product_id", 'units', x."units", 'period', x."period", 'startsOn', x."starts_on", 'endsOn', x."ends_on", 'reference', x."reference", 'status', x."status", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") || jsonb_build_object('product', jsonb_build_object('id', y."id", 'organizationId', y."org_id", 'code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text, 'currency', y."currency", 'validFrom', y."valid_from", 'validUntil', y."valid_until", 'createdAt', y."created_at", 'updatedAt', y."updated_at")) order by x."starts_on" desc, x."id"), '[]'::jsonb)
  from "better_supabase"."funding_awards" x
  join "better_supabase"."funding_products" y on y."org_id" = x."org_id" and y."id" = x."product_id"
  where x."org_id" = list_funding_awards.tenant
    and (list_funding_awards.subject_type is null or x."subject_type" = list_funding_awards.subject_type)
    and (list_funding_awards.subject_id is null or x."subject_id" = list_funding_awards.subject_id)
    and (coalesce(list_funding_awards.include_ended, false) or x."status" in ('requested', 'active'))
$$;
revoke execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."list_funding_awards"(uuid, text, text, boolean) to authenticated, service_role;

-- The units used against the units awarded, per period of the award from its
-- start to its end (today while it runs). Rejected deliveries don't count.
create or replace function "better_supabase"."funding_award_usage"(award_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'awardId', a."id",
    'units', a."units",
    'period', a."period",
    'periods', coalesce((
      select jsonb_agg(jsonb_build_object(
        'start', s.start,
        'end', nullif(s.finish, 'infinity'::date) - 1,
        'awarded', a."units",
        'used', s.used,
        'over', greatest(s.used - a."units", 0),
        'under', greatest(a."units" - s.used, 0)
      ) order by s.start)
      from (
        select g.start, (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end) as finish, (
          select coalesce(sum(x."units"), 0) from "better_supabase"."funding_deliveries" x
          where x."org_id" = a."org_id" and x."award_id" = a."id" and x."status" <> 'rejected'
            and x."delivered_on" >= g.start and x."delivered_on" < (case a."period" when 'week' then (g.start + 7) when 'month' then (g.start + interval '1 month')::date else coalesce(a."ends_on" + 1, 'infinity'::date) end)
        ) as used
        from (
          select pg_catalog.generate_series(
            (case a."period" when 'week' then date_trunc('week', a."starts_on")::date when 'month' then date_trunc('month', a."starts_on")::date else a."starts_on" end)::timestamp,
            coalesce(a."ends_on", current_date)::timestamp,
            case a."period" when 'week' then interval '1 week' else interval '1 month' end
          )::date as start
          where a."period" <> 'total'
          union all
          select a."starts_on" where a."period" = 'total'
        ) g
      ) s
    ), '[]'::jsonb)
  )
  from "better_supabase"."funding_awards" a
  where a."id" = funding_award_usage.award_id
$$;
revoke execute on function "better_supabase"."funding_award_usage"(uuid) from public, anon;
grant execute on function "better_supabase"."funding_award_usage"(uuid) to authenticated, service_role;

-- Registers care delivered on an award: units on a day, from a time entry, a
-- booking or by hand (manual). A source registered before returns its
-- delivery, so registering it twice is safe. Crossing the units of a period
-- emits funding_award.exceeded.
create or replace function "better_supabase"."register_funding_delivery"(award_id uuid, delivered_on date, units numeric, source_type text default 'manual', source_id text default null, performer_id uuid default null, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_award "better_supabase"."funding_awards"%rowtype;
  v_product "better_supabase"."funding_products"%rowtype;
  v_source text := coalesce(nullif(trim(register_funding_delivery.source_type), ''), 'manual');
  v_source_id text := nullif(trim(register_funding_delivery.source_id), '');
  v_note text := nullif(trim(register_funding_delivery.note), '');
  v_start date;
  v_used numeric;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_award from "better_supabase"."funding_awards" x where x."id" = register_funding_delivery.award_id;
  if not found then
    raise exception 'funding award not found' using errcode = 'P0002', hint = 'FUNDING_AWARD_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_award."org_id", 'funding.register'), false)) then
    raise exception 'not allowed to register funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_source not in ('time_entry', 'booking', 'manual') then
    raise exception 'source_type is time_entry, booking or manual' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source <> 'manual' and v_source_id is null then
    raise exception 'a delivery from a time entry or booking needs its source_id' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_source_id is not null then
    select * into v_row from "better_supabase"."funding_deliveries" x
    where x."org_id" = v_award."org_id" and x."source_type" = v_source and x."source_id" = v_source_id;
    if found then
      return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
    end if;
  end if;
  if register_funding_delivery.delivered_on is null then
    raise exception 'a delivery needs the day it was delivered' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if register_funding_delivery.units is null or register_funding_delivery.units <= 0 then
    raise exception 'a delivery needs units above zero' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'a note is at most 2000 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_award."status" <> 'active'
    or register_funding_delivery.delivered_on < v_award."starts_on"
    or register_funding_delivery.delivered_on > coalesce(v_award."ends_on", register_funding_delivery.delivered_on) then
    raise exception 'the funding award isn''t active on that day' using errcode = '22023', hint = 'FUNDING_AWARD_INACTIVE';
  end if;
  select * into v_product from "better_supabase"."funding_products" x where x."org_id" = v_award."org_id" and x."id" = v_award."product_id";
  if (v_product."valid_from" is not null and register_funding_delivery.delivered_on < v_product."valid_from")
    or (v_product."valid_until" is not null and register_funding_delivery.delivered_on > v_product."valid_until") then
    raise exception 'the funding product isn''t valid on that day' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_delivery_register"(uuid, date, numeric)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::date, $3::numeric)', v_hook::oid::regproc)
        using v_award."id", register_funding_delivery.delivered_on, register_funding_delivery.units;
    end if;
  end;
  insert into "better_supabase"."funding_deliveries" ("org_id", "award_id", "source_type", "source_id", "delivered_on", "units", "performer_id", "note")
  values (v_award."org_id", v_award."id", v_source, v_source_id, register_funding_delivery.delivered_on, register_funding_delivery.units, coalesce(register_funding_delivery.performer_id, (select auth.uid())), v_note)
  returning * into v_row;
  null;
  v_start := (case v_award."period" when 'week' then date_trunc('week', v_row."delivered_on")::date when 'month' then date_trunc('month', v_row."delivered_on")::date else v_award."starts_on" end);
  select coalesce(sum(x."units"), 0) into v_used from "better_supabase"."funding_deliveries" x
  where x."org_id" = v_award."org_id" and x."award_id" = v_award."id" and x."status" <> 'rejected'
    and x."delivered_on" >= v_start and x."delivered_on" < (case v_award."period" when 'week' then (v_start + 7) when 'month' then (v_start + interval '1 month')::date else coalesce(v_award."ends_on" + 1, 'infinity'::date) end);
  if v_used > v_award."units" and v_used - v_row."units" <= v_award."units" then
    null;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_delivery_register"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_row."id";
    end if;
  end;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'awardId', v_row."award_id", 'sourceType', v_row."source_type", 'sourceId', v_row."source_id", 'deliveredOn', v_row."delivered_on", 'units', v_row."units", 'performerId', v_row."performer_id", 'status', v_row."status", 'claimLineId', v_row."claim_line_id", 'note', v_row."note", 'createdAt', v_row."created_at");
end;
$$;
revoke execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) from public, anon;
grant execute on function "better_supabase"."register_funding_delivery"(uuid, date, numeric, text, text, uuid, text) to authenticated, service_role;

-- Approves registered deliveries for a claim (approved true) or rejects them.
-- A delivery a claim holds can't change. Returns how many changed.
create or replace function "better_supabase"."approve_funding_deliveries"(ids uuid[], approved boolean default true)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row "better_supabase"."funding_deliveries"%rowtype;
  v_status text := case when coalesce(approve_funding_deliveries.approved, true) then 'approved' else 'rejected' end;
  v_found integer := 0;
  v_changed integer := 0;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  for v_row in
    select * from "better_supabase"."funding_deliveries" x
    where x."id" = any (coalesce(approve_funding_deliveries.ids, '{}'::uuid[]))
    order by x."id"
    for update
  loop
    v_found := v_found + 1;
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_row."org_id", 'funding.approve'), false)) then
      raise exception 'not allowed to approve funded care' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
    end if;
    if v_row."status" = 'claimed' then
      raise exception 'a claim holds this delivery' using errcode = '22023', hint = 'FUNDING_DELIVERY_CLAIMED';
    end if;
    if v_row."status" <> v_status then
      update "better_supabase"."funding_deliveries" x set "status" = v_status where x."id" = v_row."id";
      v_changed := v_changed + 1;
    end if;
  end loop;
  if v_found < (select count(distinct i) from unnest(coalesce(approve_funding_deliveries.ids, '{}'::uuid[])) i) then
    raise exception 'funding delivery not found' using errcode = 'P0002', hint = 'FUNDING_DELIVERY_NOT_FOUND';
  end if;
  return v_changed;
end;
$$;
revoke execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) from public, anon;
grant execute on function "better_supabase"."approve_funding_deliveries"(uuid[], boolean) to authenticated, service_role;

-- The deliveries of an organization, newest first. filter holds awardId,
-- status, since and until (days), and limit (500 by default, 1000 at most).
create or replace function "better_supabase"."list_funding_deliveries"(tenant uuid, filter jsonb default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.row order by z.day desc, z.id), '[]'::jsonb)
  from (
    select jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'awardId', x."award_id", 'sourceType', x."source_type", 'sourceId', x."source_id", 'deliveredOn', x."delivered_on", 'units', x."units", 'performerId', x."performer_id", 'status', x."status", 'claimLineId', x."claim_line_id", 'note', x."note", 'createdAt', x."created_at") as row, x."delivered_on" as day, x."id" as id
    from "better_supabase"."funding_deliveries" x
    where x."org_id" = list_funding_deliveries.tenant
      and (list_funding_deliveries.filter ->> 'awardId' is null or x."award_id" = (list_funding_deliveries.filter ->> 'awardId')::uuid)
      and (list_funding_deliveries.filter ->> 'status' is null or x."status" = list_funding_deliveries.filter ->> 'status')
      and (list_funding_deliveries.filter ->> 'since' is null or x."delivered_on" >= (list_funding_deliveries.filter ->> 'since')::date)
      and (list_funding_deliveries.filter ->> 'until' is null or x."delivered_on" <= (list_funding_deliveries.filter ->> 'until')::date)
    order by x."delivered_on" desc, x."id"
    limit least(greatest(coalesce((list_funding_deliveries.filter ->> 'limit')::integer, 500), 1), 1000)
  ) z
$$;
revoke execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."list_funding_deliveries"(uuid, jsonb) to authenticated, service_role;

-- Gathers the approved deliveries of a funder from period_start to
-- period_end into a draft claim in format (a FundingClaimFormat key), one
-- line per award, priced at the product rate. The deliveries become claimed.
create or replace function "better_supabase"."build_funding_claim"(tenant uuid, funder_id uuid, period_start date, period_end date, format text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_format text := nullif(trim(build_funding_claim.format), '');
  v_currencies integer;
  v_currency text;
  v_seq bigint;
  v_number text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', build_funding_claim.tenant, 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_format is null or v_format !~ '^[a-z0-9][a-z0-9_.-]{0,62}$' then
    raise exception 'the claim format isn''t one this organization claims in' using errcode = '22023', hint = 'FUNDING_FORMAT_UNKNOWN';
  end if;
  if build_funding_claim.funder_id is null or not (exists (select 1 from "better_supabase"."companies" x where x."id" = build_funding_claim.funder_id and x."org_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles")) or exists (select 1 from "better_supabase"."people" x where x."id" = build_funding_claim.funder_id and x."org_id" = build_funding_claim.tenant and x."merged_into" is null and 'funder' = any (x."roles"))) then
    raise exception 'the funder is a company or person in this organization''s contacts with the funder role' using errcode = '22023', hint = 'FUNDING_FUNDER_INVALID';
  end if;
  if build_funding_claim.period_start is null or build_funding_claim.period_end is null
    or build_funding_claim.period_end < build_funding_claim.period_start then
    raise exception 'a claim period ends on or after it starts' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_funding_claim_build"(uuid, uuid, date, date)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::date, $4::date)', v_hook::oid::regproc)
        using build_funding_claim.tenant, build_funding_claim.funder_id, build_funding_claim.period_start, build_funding_claim.period_end;
    end if;
  end;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('bsb_funding_claim:' || build_funding_claim.tenant::text, 0));
  perform 1 from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."org_id" = x."org_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."org_id" = a."org_id" and y."id" = a."product_id"
    where x."org_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  for update of x;
  select count(distinct y."currency"), min(y."currency") into v_currencies, v_currency
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."org_id" = x."org_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."org_id" = a."org_id" and y."id" = a."product_id"
    where x."org_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  if v_currencies = 0 then
    raise exception 'no approved deliveries of this funder in the period' using errcode = '22023', hint = 'FUNDING_CLAIM_EMPTY';
  end if;
  if v_currencies > 1 then
    raise exception 'the deliveries are priced in several currencies; claim each product''s currency apart' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  select coalesce(max(x."number"::bigint) filter (where x."number" ~ '^[0-9]{1,18}$'), 0) + 1 into v_seq
  from "better_supabase"."funding_claims" x where x."org_id" = build_funding_claim.tenant;
  v_number := v_seq::text;
  insert into "better_supabase"."funding_claims" ("org_id", "funder_id", "number", "period_start", "period_end", "format", "currency", "created_by")
  values (build_funding_claim.tenant, build_funding_claim.funder_id, v_number, build_funding_claim.period_start, build_funding_claim.period_end, v_format, v_currency, (select auth.uid()))
  returning * into v_claim;
  insert into "better_supabase"."funding_claim_lines" ("org_id", "claim_id", "award_id", "product_id", "units", "amount")
  select build_funding_claim.tenant, v_claim."id", a."id", y."id", sum(x."units"), round(sum(x."units") * y."rate")::bigint
  from "better_supabase"."funding_deliveries" x
    join "better_supabase"."funding_awards" a on a."org_id" = x."org_id" and a."id" = x."award_id"
    join "better_supabase"."funding_products" y on y."org_id" = a."org_id" and y."id" = a."product_id"
    where x."org_id" = build_funding_claim.tenant and a."funder_id" = build_funding_claim.funder_id
      and x."status" = 'approved' and x."claim_line_id" is null
      and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end
  group by a."id", y."id", y."rate";
  update "better_supabase"."funding_deliveries" x set "status" = 'claimed', "claim_line_id" = z."id"
  from "better_supabase"."funding_claim_lines" z
  where z."org_id" = v_claim."org_id" and z."claim_id" = v_claim."id"
    and x."org_id" = z."org_id" and x."award_id" = z."award_id"
    and x."status" = 'approved' and x."claim_line_id" is null
    and x."delivered_on" >= build_funding_claim.period_start and x."delivered_on" <= build_funding_claim.period_end;
  update "better_supabase"."funding_claims" x set "total" = (
    select coalesce(sum(z."amount"), 0) from "better_supabase"."funding_claim_lines" z where z."org_id" = v_claim."org_id" and z."claim_id" = v_claim."id"
  )
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_funding_claim_build"(uuid)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid)', v_hook::oid::regproc)
        using v_claim."id";
    end if;
  end;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."org_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."org_id" = z."org_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."org_id" = z."org_id" and y."id" = z."product_id"
    where z."org_id" = v_claim."org_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) from public, anon;
grant execute on function "better_supabase"."build_funding_claim"(uuid, uuid, date, date, text) to authenticated, service_role;

-- A claim with its lines, each with its award, product and deliveries: what a
-- FundingClaimFormat renders.
create or replace function "better_supabase"."get_funding_claim"(claim_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = get_funding_claim.claim_id;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."org_id", 'funding.read'), false)) then
    raise exception 'not allowed to read funding claims' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."org_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."org_id" = z."org_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."org_id" = z."org_id" and y."id" = z."product_id"
    where z."org_id" = v_claim."org_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."get_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."get_funding_claim"(uuid) to authenticated, service_role;

-- Marks a draft claim sent, with the channel's reference and the SHA-256 of
-- the file that was sent.
create or replace function "better_supabase"."mark_funding_claim_sent"(claim_id uuid, external_ref text default null, payload_sha256 text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_ref text := nullif(trim(mark_funding_claim_sent.external_ref), '');
  v_sha text := lower(nullif(trim(mark_funding_claim_sent.payload_sha256), ''));
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = mark_funding_claim_sent.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."org_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if v_ref is not null and length(v_ref) > 200 then
    raise exception 'external_ref is at most 200 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'payload_sha256 is a SHA-256 in hex' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  update "better_supabase"."funding_claims" x set "status" = 'sent', "sent_at" = now(), "external_ref" = v_ref, "payload_sha256" = v_sha, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."org_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at");
end;
$$;
revoke execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."mark_funding_claim_sent"(uuid, text, text) to authenticated, service_role;

-- Records the funder's response to a sent claim: lines is an array of
-- { lineId, status (accepted or rejected), rejectionCode }, or null for
-- none. A line the response leaves out is accepted. The deliveries of a rejected line go back
-- to approved, for correction and a later claim.
create or replace function "better_supabase"."record_funding_claim_response"(claim_id uuid, lines jsonb, response jsonb default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
  v_line jsonb;
  v_status text;
  v_code text;
  v_accepted integer;
  v_rejected integer;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = record_funding_claim_response.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."org_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'sent' then
    raise exception 'only a sent claim takes a response' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  if jsonb_typeof(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) <> 'array' then
    raise exception 'lines is an array' using errcode = '22023', hint = 'FUNDING_INVALID';
  end if;
  for v_line in select value from jsonb_array_elements(coalesce(record_funding_claim_response.lines, '[]'::jsonb)) loop
    v_status := v_line ->> 'status';
    v_code := nullif(trim(v_line ->> 'rejectionCode'), '');
    if jsonb_typeof(v_line) <> 'object' or v_status is null or v_status not in ('accepted', 'rejected') then
      raise exception 'each line has a lineId and a status of accepted or rejected' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    if v_code is not null and length(v_code) > 100 then
      raise exception 'a rejection code is at most 100 characters' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
    update "better_supabase"."funding_claim_lines" x set "status" = v_status, "rejection_code" = case when v_status = 'rejected' then v_code end
    where x."org_id" = v_claim."org_id" and x."claim_id" = v_claim."id"
      and x."id"::text = v_line ->> 'lineId';
    if not found then
      raise exception 'a line in the response isn''t a line of this claim' using errcode = '22023', hint = 'FUNDING_INVALID';
    end if;
  end loop;
  update "better_supabase"."funding_claim_lines" x set "status" = 'accepted'
  where x."org_id" = v_claim."org_id" and x."claim_id" = v_claim."id" and x."status" = 'pending';
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."org_id" = v_claim."org_id" and z."claim_id" = v_claim."id" and z."status" = 'rejected');
  select count(*) filter (where z."status" = 'accepted'), count(*) filter (where z."status" = 'rejected')
  into v_accepted, v_rejected
  from "better_supabase"."funding_claim_lines" z where z."org_id" = v_claim."org_id" and z."claim_id" = v_claim."id";
  update "better_supabase"."funding_claims" x set
    "status" = case when v_rejected = 0 then 'accepted' when v_accepted = 0 then 'rejected' else 'partially_accepted' end,
    "response" = record_funding_claim_response.response, "updated_at" = now()
  where x."id" = v_claim."id"
  returning x.* into v_claim;
  null;
  return jsonb_build_object('id', v_claim."id", 'organizationId', v_claim."org_id", 'funderId', v_claim."funder_id", 'number', v_claim."number", 'periodStart', v_claim."period_start", 'periodEnd', v_claim."period_end", 'format', v_claim."format", 'status', v_claim."status", 'externalRef', v_claim."external_ref", 'sentAt', v_claim."sent_at", 'payloadSha256', v_claim."payload_sha256", 'response', v_claim."response", 'total', v_claim."total"::text, 'currency', v_claim."currency", 'invoiceId', v_claim."invoice_id", 'createdBy', v_claim."created_by", 'createdAt', v_claim."created_at", 'updatedAt', v_claim."updated_at") || jsonb_build_object('lines', coalesce((
    select jsonb_agg(jsonb_build_object('id', z."id", 'claimId', z."claim_id", 'awardId', z."award_id", 'productId', z."product_id", 'units', z."units", 'amount', z."amount"::text, 'status', z."status", 'rejectionCode', z."rejection_code") || jsonb_build_object(
      'award', jsonb_build_object('subjectType', a."subject_type", 'subjectId', a."subject_id", 'reference', a."reference", 'period', a."period"),
      'product', jsonb_build_object('code', y."code", 'title', y."title", 'unit', y."unit", 'rate', y."rate"::text),
      'deliveries', coalesce((
        select jsonb_agg(jsonb_build_object('id', x."id", 'deliveredOn', x."delivered_on", 'units', x."units", 'sourceType', x."source_type", 'sourceId', x."source_id", 'performerId', x."performer_id") order by x."delivered_on", x."id")
        from "better_supabase"."funding_deliveries" x where x."claim_line_id" = z."id"
      ), '[]'::jsonb)
    ) order by y."code", a."subject_id", z."id")
    from "better_supabase"."funding_claim_lines" z
    join "better_supabase"."funding_awards" a on a."org_id" = z."org_id" and a."id" = z."award_id"
    join "better_supabase"."funding_products" y on y."org_id" = z."org_id" and y."id" = z."product_id"
    where z."org_id" = v_claim."org_id" and z."claim_id" = v_claim."id"
  ), '[]'::jsonb));
end;
$$;
revoke execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) from public, anon;
grant execute on function "better_supabase"."record_funding_claim_response"(uuid, jsonb, jsonb) to authenticated, service_role;

-- Deletes a draft claim; its deliveries go back to approved.
create or replace function "better_supabase"."delete_funding_claim"(claim_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_claim "better_supabase"."funding_claims"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_claim from "better_supabase"."funding_claims" x where x."id" = delete_funding_claim.claim_id for update;
  if not found then
    raise exception 'funding claim not found' using errcode = 'P0002', hint = 'FUNDING_CLAIM_NOT_FOUND';
  end if;
  if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_claim."org_id", 'funding.claim'), false)) then
    raise exception 'not allowed to claim funding' using errcode = '42501', hint = 'FUNDING_FORBIDDEN';
  end if;
  if v_claim."status" <> 'draft' then
    raise exception 'the funding claim was sent already' using errcode = '22023', hint = 'FUNDING_CLAIM_STATUS_INVALID';
  end if;
  update "better_supabase"."funding_deliveries" x set "status" = 'approved', "claim_line_id" = null
  where x."claim_line_id" in (select z."id" from "better_supabase"."funding_claim_lines" z where z."org_id" = v_claim."org_id" and z."claim_id" = v_claim."id");
  delete from "better_supabase"."funding_claims" x where x."id" = v_claim."id";
  null;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_funding_claim"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_funding_claim"(uuid) to authenticated, service_role;

create or replace function "better_supabase"."list_funding_claims"(tenant uuid, status text default null, funder_id uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'funderId', x."funder_id", 'number', x."number", 'periodStart', x."period_start", 'periodEnd', x."period_end", 'format', x."format", 'status', x."status", 'externalRef', x."external_ref", 'sentAt', x."sent_at", 'payloadSha256', x."payload_sha256", 'response', x."response", 'total', x."total"::text, 'currency', x."currency", 'invoiceId', x."invoice_id", 'createdBy', x."created_by", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."period_start" desc, x."number" desc), '[]'::jsonb)
  from "better_supabase"."funding_claims" x
  where x."org_id" = list_funding_claims.tenant
    and (list_funding_claims.status is null or x."status" = list_funding_claims.status)
    and (list_funding_claims.funder_id is null or x."funder_id" = list_funding_claims.funder_id)
$$;
revoke execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) from public, anon;
grant execute on function "better_supabase"."list_funding_claims"(uuid, text, uuid) to authenticated, service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_products";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_products";
create policy bsb_tenant_scope_select on "better_supabase"."funding_products" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_products";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_products" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_products";
create policy bsb_tenant_scope_update on "better_supabase"."funding_products" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_products";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_products" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_awards";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_select on "better_supabase"."funding_awards" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('funding.read')) and coalesce("better_supabase"."can_subject"("subject_type", "subject_id", 'read'), false))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_awards" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_update on "better_supabase"."funding_awards" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_awards";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_awards" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_deliveries";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_select on "better_supabase"."funding_deliveries" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('funding.read')) and exists (select 1 from "better_supabase"."funding_awards" x where x."org_id" = "org_id" and x."id" = "award_id" and coalesce("better_supabase"."can_subject"(x."subject_type", x."subject_id", 'read'), false)))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_deliveries" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_update on "better_supabase"."funding_deliveries" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_deliveries";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_deliveries" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claims";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claims" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claims" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claims" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claims";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claims" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."funding_claim_lines";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_select on "better_supabase"."funding_claim_lines" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('funding.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_insert on "better_supabase"."funding_claim_lines" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_update on "better_supabase"."funding_claim_lines" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines";
create policy bsb_tenant_scope_delete on "better_supabase"."funding_claim_lines" as restrictive
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

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_158_funding.sql
-- better-supabase module: funding
-- @bsb-block-data funding
-- @bsb-hash sha256:5f2aaa76a9d6c8414def54826e938bc7edcce178f14b0d9edd894653bfab3d11
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('funding', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
