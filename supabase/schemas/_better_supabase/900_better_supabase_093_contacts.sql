-- better-supabase module: contacts
-- @bsb-block contacts@3 managed
-- @bsb-hash sha256:c2848394db9e9bb7e521d26a07a5791678a4c3a381a878054614ae74838ad326
-- Companies and people an organization works with: lifecycle stages, owners, party roles (customer, supplier and so on), payment terms with early-payment discounts and credit restrictions, credit limits with a soft or hard block, a language, delivery preferences per document type and a supplier status, who works where with a role and a primary contact, each person's addresses on channels (the inbox's contacts), domain and email dedupe, merges and keyset-paged search.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Companies and people an organization works with, and who works where.

create table "better_supabase"."payment_terms" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "code" text not null constraint bsb_payment_terms_code_check check (length("code") >= 1 and length("code") <= 50),
  "name" text not null constraint bsb_payment_terms_name_check check (length("name") >= 1 and length("name") <= 300),
  "days" integer not null default 30 constraint bsb_payment_terms_days_check check ("days" >= 0 and "days" <= 3650),
  "discount_bps" integer not null default 0 constraint bsb_payment_terms_discount_bps_check check ("discount_bps" >= 0 and "discount_bps" <= 10000),
  "discount_days" integer not null default 0 constraint bsb_payment_terms_discount_days_check check ("discount_days" >= 0 and "discount_days" <= 3650),
  "credit_restriction_bps" integer not null default 0 constraint bsb_payment_terms_credit_restriction_bps_check check ("credit_restriction_bps" >= 0 and "credit_restriction_bps" <= 10000),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "code")
);
alter table "better_supabase"."payment_terms" enable row level security;
revoke all on "better_supabase"."payment_terms" from public, anon, authenticated;
grant select on "better_supabase"."payment_terms" to authenticated;
grant all on "better_supabase"."payment_terms" to service_role;
create policy bsb_payment_terms_read on "better_supabase"."payment_terms"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table "better_supabase"."companies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_companies_name_check check (length("name") >= 1 and length("name") <= 300),
  "domain" text constraint bsb_companies_domain_check check ("domain" = lower("domain") and "domain" ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  "website" text,
  "vat_id" text,
  "legal_name" text constraint bsb_companies_legal_name check (length("legal_name") >= 1 and length("legal_name") <= 300),
  "registration_id" text constraint bsb_companies_registration_id check (length("registration_id") >= 1 and length("registration_id") <= 100),
  "phone" text,
  "billing_email" text,
  "bill_to_id" uuid,
  "lifecycle" text not null,
  "owner_id" uuid,
  "address" jsonb constraint bsb_companies_address_check check ("address" is null or jsonb_typeof("address") = 'object'),
  "roles" text[] not null default '{}'::text[],
  "customer_terms_id" uuid references "better_supabase"."payment_terms" ("id") on delete set null,
  "supplier_terms_id" uuid references "better_supabase"."payment_terms" ("id") on delete set null,
  "credit_currency" text constraint bsb_companies_credit_currency_check check ("credit_currency" ~ '^[A-Z]{3}$'),
  "credit_limit" bigint constraint bsb_companies_check check ("credit_limit" >= 0 and num_nulls("credit_limit", "credit_currency") <> 1),
  "credit_block" text constraint bsb_companies_credit_block_check check ("credit_block" in ('none', 'soft', 'hard')),
  "supplier_status" text constraint bsb_companies_supplier_status_check check ("supplier_status" in ('approved', 'conditional', 'blocked')),
  "language" text constraint bsb_companies_language_check check ("language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  "merged_into" uuid references "better_supabase"."companies" ("id"),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index companies_tenant_name_idx on "better_supabase"."companies" ("tenant_id", lower("name"), "id");
create unique index companies_domain_idx on "better_supabase"."companies" ("tenant_id", "domain")
  where "domain" is not null and "archived_at" is null;
create index companies_owner_idx on "better_supabase"."companies" ("owner_id");
create index companies_merged_into_idx on "better_supabase"."companies" ("merged_into");
create index companies_roles_idx on "better_supabase"."companies" using gin ("roles");
create index companies_supplier_status_idx on "better_supabase"."companies" ("tenant_id", "supplier_status") where "supplier_status" is not null;
create index companies_customer_terms_id_idx on "better_supabase"."companies" ("customer_terms_id") where "customer_terms_id" is not null;
create index companies_supplier_terms_id_idx on "better_supabase"."companies" ("supplier_terms_id") where "supplier_terms_id" is not null;
alter table "better_supabase"."companies" enable row level security;
revoke all on "better_supabase"."companies" from public, anon, authenticated;
grant select on "better_supabase"."companies" to authenticated;
grant all on "better_supabase"."companies" to service_role;
create policy bsb_companies_read on "better_supabase"."companies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table "better_supabase"."people" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null constraint bsb_people_name_check check (length("name") >= 1 and length("name") <= 300),
  "given_name" text,
  "last_name" text,
  "initials" text,
  "infix" text,
  "email" text constraint bsb_people_email_check check ("email" = lower("email") and "email" ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  "phone" text,
  "title" text,
  "mode" text not null default 'external' constraint bsb_people_mode check ("mode" in ('external', 'tenant') and ("mode" = 'external' or "user_id" is not null)),
  "lifecycle" text not null,
  "owner_id" uuid,
  "user_id" uuid,
  "avatar_url" text,
  "metadata" jsonb not null default '{}'::jsonb constraint bsb_people_metadata_check check (jsonb_typeof("metadata") = 'object'),
  "roles" text[] not null default '{}'::text[],
  "customer_terms_id" uuid references "better_supabase"."payment_terms" ("id") on delete set null,
  "supplier_terms_id" uuid references "better_supabase"."payment_terms" ("id") on delete set null,
  "credit_currency" text constraint bsb_people_credit_currency_check check ("credit_currency" ~ '^[A-Z]{3}$'),
  "credit_limit" bigint constraint bsb_people_check check ("credit_limit" >= 0 and num_nulls("credit_limit", "credit_currency") <> 1),
  "credit_block" text constraint bsb_people_credit_block_check check ("credit_block" in ('none', 'soft', 'hard')),
  "supplier_status" text constraint bsb_people_supplier_status_check check ("supplier_status" in ('approved', 'conditional', 'blocked')),
  "language" text constraint bsb_people_language_check check ("language" ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
  "merged_into" uuid references "better_supabase"."people" ("id"),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index people_tenant_name_idx on "better_supabase"."people" ("tenant_id", lower("name"), "id");
create unique index people_email_idx on "better_supabase"."people" ("tenant_id", "email")
  where "email" is not null and "archived_at" is null;
create index people_owner_idx on "better_supabase"."people" ("owner_id");
create index people_user_idx on "better_supabase"."people" ("user_id");
create index people_merged_into_idx on "better_supabase"."people" ("merged_into");
create index people_roles_idx on "better_supabase"."people" using gin ("roles");
create index people_supplier_status_idx on "better_supabase"."people" ("tenant_id", "supplier_status") where "supplier_status" is not null;
create index people_customer_terms_id_idx on "better_supabase"."people" ("customer_terms_id") where "customer_terms_id" is not null;
create index people_supplier_terms_id_idx on "better_supabase"."people" ("supplier_terms_id") where "supplier_terms_id" is not null;
alter table "better_supabase"."people" enable row level security;
revoke all on "better_supabase"."people" from public, anon, authenticated;
grant select on "better_supabase"."people" to authenticated;
grant all on "better_supabase"."people" to service_role;
create policy bsb_people_read on "better_supabase"."people"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table "better_supabase"."company_people" (
  "tenant_id" uuid not null,
  "company_id" uuid not null references "better_supabase"."companies" ("id") on delete cascade,
  "person_id" uuid not null references "better_supabase"."people" ("id") on delete cascade,
  "role" text,
  "is_primary" boolean not null default false,
  "created_at" timestamptz not null default now(),
  primary key ("company_id", "person_id")
);
create index company_people_person_idx on "better_supabase"."company_people" ("person_id");
create unique index company_people_primary_idx on "better_supabase"."company_people" ("company_id") where "is_primary";
alter table "better_supabase"."company_people" enable row level security;
revoke all on "better_supabase"."company_people" from public, anon, authenticated;
grant select on "better_supabase"."company_people" to authenticated;
grant all on "better_supabase"."company_people" to service_role;
create policy bsb_company_people_read on "better_supabase"."company_people"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table "better_supabase"."party_locations" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "party_id" uuid not null,
  "kind" text not null default 'other',
  "line1" text,
  "line2" text,
  "postal_code" text,
  "city" text,
  "country" text,
  "latitude" double precision,
  "longitude" double precision,
  "is_primary" boolean not null default false,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."party_locations" enable row level security;
revoke all on "better_supabase"."party_locations" from public, anon, authenticated;
grant select on "better_supabase"."party_locations" to authenticated;
grant all on "better_supabase"."party_locations" to service_role;
create policy bsb_party_locations_read on "better_supabase"."party_locations"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create unique index party_locations_primary_idx
  on "better_supabase"."party_locations" ("tenant_id", "party_id") where "is_primary";

create table "better_supabase"."party_bank_accounts" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "party_id" uuid not null,
  "iban" text not null,
  "bic" text,
  "holder" text,
  "is_primary" boolean not null default false,
  unique ("tenant_id", "iban"),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."party_bank_accounts" enable row level security;
revoke all on "better_supabase"."party_bank_accounts" from public, anon, authenticated;
grant select on "better_supabase"."party_bank_accounts" to authenticated;
grant all on "better_supabase"."party_bank_accounts" to service_role;
create policy bsb_party_bank_accounts_read on "better_supabase"."party_bank_accounts"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create unique index party_bank_accounts_primary_idx
  on "better_supabase"."party_bank_accounts" ("tenant_id", "party_id") where "is_primary";

create table "better_supabase"."party_channels" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "party_id" uuid not null,
  "party_kind" text not null constraint bsb_party_channels_party_kind_check check ("party_kind" in ('person', 'company')),
  "channel" text not null constraint bsb_party_channels_channel_check check ("channel" in ('email', 'phone', 'mobile', 'fax', 'whatsapp')),
  "label" text,
  "address" text not null,
  "is_primary" boolean not null default false,
  unique ("tenant_id", "party_id", "channel", "address"),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
alter table "better_supabase"."party_channels" enable row level security;
revoke all on "better_supabase"."party_channels" from public, anon, authenticated;
grant select on "better_supabase"."party_channels" to authenticated;
grant all on "better_supabase"."party_channels" to service_role;
create policy bsb_party_channels_read on "better_supabase"."party_channels"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));


create table "better_supabase"."document_delivery_preferences" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "party_id" uuid not null,
  "document_type" text not null constraint bsb_document_delivery_preferences_document_type_check check (length("document_type") >= 1 and length("document_type") <= 100),
  "channel" text not null constraint bsb_document_delivery_preferences_channel_check check ("channel" in ('email', 'post', 'portal')),
  "copies" integer not null default 1 constraint bsb_document_delivery_preferences_copies_check check ("copies" >= 1 and "copies" <= 20),
  "email" text constraint bsb_document_delivery_preferences_email_check check ("email" = lower("email") and "email" ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("tenant_id", "party_id", "document_type", "channel")
);
create index document_delivery_preferences_party_idx on "better_supabase"."document_delivery_preferences" ("party_id");
alter table "better_supabase"."document_delivery_preferences" enable row level security;
revoke all on "better_supabase"."document_delivery_preferences" from public, anon, authenticated;
grant select on "better_supabase"."document_delivery_preferences" to authenticated;
grant all on "better_supabase"."document_delivery_preferences" to service_role;
create policy bsb_document_delivery_preferences_read on "better_supabase"."document_delivery_preferences"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table "better_supabase"."person_identities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "person_id" uuid not null references "better_supabase"."people" ("id") on delete cascade,
  "channel" text not null constraint bsb_person_identities_channel_check check (length("channel") >= 1 and length("channel") <= 50),
  "address" text not null constraint bsb_person_identities_address_check check (length("address") >= 1 and length("address") <= 500),
  "verified_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "channel", "address")
);
create index person_identities_person_idx on "better_supabase"."person_identities" ("person_id");
alter table "better_supabase"."person_identities" enable row level security;
revoke all on "better_supabase"."person_identities" from public, anon, authenticated;
grant select on "better_supabase"."person_identities" to authenticated;
grant all on "better_supabase"."person_identities" to service_role;
create policy bsb_person_identities_read on "better_supabase"."person_identities"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

-- Creates a company (company null) or updates the keys attrs names.
-- Returns its row. The owner watches it when notifications is installed.
create or replace function "better_supabase"."save_company"(tenant uuid, company uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_company.company;
  v_created boolean := save_company.company is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_company.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_company.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_company.attrs ? 'lifecycle' and not (save_company.attrs ->> 'lifecycle' = any ('{lead,prospect,customer,churned}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_company.attrs ->> 'customerTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_company.attrs ->> 'customerTermsId' and pt."tenant_id" = save_company.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'supplierTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_company.attrs ->> 'supplierTermsId' and pt."tenant_id" = save_company.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditBlock' is not null and lower(trim(save_company.attrs ->> 'creditBlock')) not in ('none', 'soft', 'hard') then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'language' is not null and nullif(trim(save_company.attrs ->> 'language'), '') is not null and trim(save_company.attrs ->> 'language') !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditLimit' is not null and save_company.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditCurrency' is not null and upper(trim(save_company.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' <> save_company.attrs ? 'creditCurrency' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' and (save_company.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_company.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_company_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_company.tenant, save_company.company, save_company.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_company.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."companies" ("tenant_id", "name", "domain", "website", "vat_id", "legal_name", "registration_id", "phone", "lifecycle", "owner_id", "customer_terms_id", "supplier_terms_id", "credit_limit", "credit_currency", "credit_block", "language", "address", "created_by")
      values (save_company.tenant, nullif(trim(save_company.attrs ->> 'name'), ''), lower(nullif(trim(save_company.attrs ->> 'domain'), '')), nullif(trim(save_company.attrs ->> 'website'), ''), nullif(trim(save_company.attrs ->> 'vatId'), ''), nullif(trim(save_company.attrs ->> 'legalName'), ''), nullif(trim(save_company.attrs ->> 'registrationId'), ''), nullif(trim(save_company.attrs ->> 'phone'), ''), coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(save_company.attrs ->> 'ownerId', '')::uuid, nullif(save_company.attrs ->> 'customerTermsId', '')::uuid, nullif(save_company.attrs ->> 'supplierTermsId', '')::uuid, nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')), lower(nullif(trim(save_company.attrs ->> 'creditBlock'), '')), nullif(trim(save_company.attrs ->> 'language'), ''), save_company.attrs -> 'address', auth.uid())
      returning "id", "owner_id" into v_id, v_owner;
    else
      select x."owner_id" into v_previous_owner from "better_supabase"."companies" x
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant;
      update "better_supabase"."companies" x set "name" = case when save_company.attrs ? 'name' then coalesce(nullif(trim(save_company.attrs ->> 'name'), ''), x."name") else x."name" end,
        "domain" = case when save_company.attrs ? 'domain' then lower(nullif(trim(save_company.attrs ->> 'domain'), '')) else x."domain" end,
        "website" = case when save_company.attrs ? 'website' then nullif(trim(save_company.attrs ->> 'website'), '') else x."website" end,
        "vat_id" = case when save_company.attrs ? 'vatId' then nullif(trim(save_company.attrs ->> 'vatId'), '') else x."vat_id" end,
        "legal_name" = case when save_company.attrs ? 'legalName' then nullif(trim(save_company.attrs ->> 'legalName'), '') else x."legal_name" end,
        "registration_id" = case when save_company.attrs ? 'registrationId' then nullif(trim(save_company.attrs ->> 'registrationId'), '') else x."registration_id" end,
        "phone" = case when save_company.attrs ? 'phone' then nullif(trim(save_company.attrs ->> 'phone'), '') else x."phone" end,
        "lifecycle" = case when save_company.attrs ? 'lifecycle' then coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_id" = case when save_company.attrs ? 'ownerId' then nullif(save_company.attrs ->> 'ownerId', '')::uuid else x."owner_id" end,
        "customer_terms_id" = case when save_company.attrs ? 'customerTermsId' then nullif(save_company.attrs ->> 'customerTermsId', '')::uuid else x."customer_terms_id" end,
        "supplier_terms_id" = case when save_company.attrs ? 'supplierTermsId' then nullif(save_company.attrs ->> 'supplierTermsId', '')::uuid else x."supplier_terms_id" end,
        "credit_limit" = case when save_company.attrs ? 'creditLimit' then nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_company.attrs ? 'creditCurrency' then upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "credit_block" = case when save_company.attrs ? 'creditBlock' then lower(nullif(trim(save_company.attrs ->> 'creditBlock'), '')) else x."credit_block" end,
        "language" = case when save_company.attrs ? 'language' then nullif(trim(save_company.attrs ->> 'language'), '') else x."language" end,
        "address" = case when save_company.attrs ? 'address' then save_company.attrs -> 'address' else x."address" end,
        "updated_at" = now()
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant and x."merged_into" is null
      returning x."owner_id" into v_owner;
      if not found then
        raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") into v_row from "better_supabase"."companies" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('company.created', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('company.updated', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (save_company.tenant, v_owner, 'company', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_company_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."save_company"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_company"(uuid, uuid, jsonb) to authenticated, service_role;

-- Creates a person (person null) or updates the keys attrs names.
-- Returns its row. The owner watches it when notifications is installed.
create or replace function "better_supabase"."save_person"(tenant uuid, person uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_person.person;
  v_created boolean := save_person.person is null;
  v_row jsonb;
  v_owner uuid;
  v_previous_owner uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_person.tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_person.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_person.attrs ? 'lifecycle' and not (save_person.attrs ->> 'lifecycle' = any ('{lead,mql,sql,opportunity,customer}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
  end if;
  if save_person.attrs ? 'mode' and coalesce(lower(trim(save_person.attrs ->> 'mode')), '') not in ('external', 'tenant') then
    raise exception 'a person is external or tenant' using errcode = '22023', hint = 'PARTY_MODE_INVALID';
  end if;
  if v_created and lower(trim(save_person.attrs ->> 'mode')) = 'tenant' and nullif(save_person.attrs ->> 'userId', '') is null then
    raise exception 'a tenant person needs a userId' using errcode = '22023', hint = 'PARTY_MODE_INVALID';
  end if;
  if save_person.attrs ->> 'customerTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_person.attrs ->> 'customerTermsId' and pt."tenant_id" = save_person.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'supplierTermsId' is not null and not exists (select 1 from "better_supabase"."payment_terms" pt where pt."id"::text = save_person.attrs ->> 'supplierTermsId' and pt."tenant_id" = save_person.tenant) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditBlock' is not null and lower(trim(save_person.attrs ->> 'creditBlock')) not in ('none', 'soft', 'hard') then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'language' is not null and nullif(trim(save_person.attrs ->> 'language'), '') is not null and trim(save_person.attrs ->> 'language') !~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditLimit' is not null and save_person.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditCurrency' is not null and upper(trim(save_person.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' <> save_person.attrs ? 'creditCurrency' then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' and (save_person.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_person.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'a terms id names a payment terms row of this organization; a credit limit is minor units with a currency; a credit block is none, soft or hard; a language is a tag such as nl or pt-BR' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."before_person_save"(uuid, uuid, jsonb)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::uuid, $3::jsonb)', v_hook::oid::regproc)
        using save_person.tenant, save_person.person, save_person.attrs;
    end if;
  end;
  begin
    if v_created then
      if nullif(trim(save_person.attrs ->> 'name'), '') is null then
        raise exception 'a name is required' using errcode = '23502', hint = 'PARTY_NAME_REQUIRED';
      end if;
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "title", "mode", "lifecycle", "owner_id", "user_id", "customer_terms_id", "supplier_terms_id", "credit_limit", "credit_currency", "credit_block", "language", "created_by")
      values (save_person.tenant, nullif(trim(save_person.attrs ->> 'name'), ''), lower(nullif(trim(save_person.attrs ->> 'email'), '')), nullif(trim(save_person.attrs ->> 'phone'), ''), nullif(trim(save_person.attrs ->> 'title'), ''), coalesce(lower(nullif(trim(save_person.attrs ->> 'mode'), '')), 'external'), coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(save_person.attrs ->> 'ownerId', '')::uuid, nullif(save_person.attrs ->> 'userId', '')::uuid, nullif(save_person.attrs ->> 'customerTermsId', '')::uuid, nullif(save_person.attrs ->> 'supplierTermsId', '')::uuid, nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')), lower(nullif(trim(save_person.attrs ->> 'creditBlock'), '')), nullif(trim(save_person.attrs ->> 'language'), ''), auth.uid())
      returning "id", "owner_id" into v_id, v_owner;
    else
      select x."owner_id" into v_previous_owner from "better_supabase"."people" x
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant;
      update "better_supabase"."people" x set "name" = case when save_person.attrs ? 'name' then coalesce(nullif(trim(save_person.attrs ->> 'name'), ''), x."name") else x."name" end,
        "email" = case when save_person.attrs ? 'email' then lower(nullif(trim(save_person.attrs ->> 'email'), '')) else x."email" end,
        "phone" = case when save_person.attrs ? 'phone' then nullif(trim(save_person.attrs ->> 'phone'), '') else x."phone" end,
        "title" = case when save_person.attrs ? 'title' then nullif(trim(save_person.attrs ->> 'title'), '') else x."title" end,
        "mode" = case when save_person.attrs ? 'mode' then coalesce(lower(nullif(trim(save_person.attrs ->> 'mode'), '')), x."mode") else x."mode" end,
        "lifecycle" = case when save_person.attrs ? 'lifecycle' then coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_id" = case when save_person.attrs ? 'ownerId' then nullif(save_person.attrs ->> 'ownerId', '')::uuid else x."owner_id" end,
        "user_id" = case when save_person.attrs ? 'userId' then nullif(save_person.attrs ->> 'userId', '')::uuid else x."user_id" end,
        "customer_terms_id" = case when save_person.attrs ? 'customerTermsId' then nullif(save_person.attrs ->> 'customerTermsId', '')::uuid else x."customer_terms_id" end,
        "supplier_terms_id" = case when save_person.attrs ? 'supplierTermsId' then nullif(save_person.attrs ->> 'supplierTermsId', '')::uuid else x."supplier_terms_id" end,
        "credit_limit" = case when save_person.attrs ? 'creditLimit' then nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_person.attrs ? 'creditCurrency' then upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "credit_block" = case when save_person.attrs ? 'creditBlock' then lower(nullif(trim(save_person.attrs ->> 'creditBlock'), '')) else x."credit_block" end,
        "language" = case when save_person.attrs ? 'language' then nullif(trim(save_person.attrs ->> 'language'), '') else x."language" end,
        "updated_at" = now()
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant and x."merged_into" is null
      returning x."owner_id" into v_owner;
      if not found then
        raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") into v_row from "better_supabase"."people" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('person.created', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('person.updated', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("tenant_id", "user_id", "subject_type", "subject_id", "level")
    values (save_person.tenant, v_owner, 'person', v_id::text, 'participating')
    on conflict do nothing;
  end if;
  declare
    v_hook regprocedure := to_regprocedure('"public"."after_person_save"(uuid, boolean)');
  begin
    if v_hook is not null then
      execute format('select %s($1::uuid, $2::boolean)', v_hook::oid::regproc)
        using v_id, v_created;
    end if;
  end;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."save_person"(uuid, uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_person"(uuid, uuid, jsonb) to authenticated, service_role;


-- Archives a company (archived true) or restores it.
create or replace function "better_supabase"."archive_company"(id uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_name text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."name" into v_tenant, v_name from "better_supabase"."companies" x where x."id" = archive_company.id;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."companies" x set "archived_at" = case when archive_company.archived then coalesce(x."archived_at", now()) end, "updated_at" = now()
    where x."id" = archive_company.id;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  if archive_company.archived then
    perform "better_supabase".emit_event('company.archived', jsonb_build_object('organizationId', v_tenant, 'companyId', archive_company.id, 'name', v_name), 'companies/' || archive_company.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_company"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_company"(uuid, boolean) to authenticated, service_role;


-- Archives a person (archived true) or restores it.
create or replace function "better_supabase"."archive_person"(id uuid, archived boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_name text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id", x."name" into v_tenant, v_name from "better_supabase"."people" x where x."id" = archive_person.id;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  begin
    update "better_supabase"."people" x set "archived_at" = case when archive_person.archived then coalesce(x."archived_at", now()) end, "updated_at" = now()
    where x."id" = archive_person.id;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  if archive_person.archived then
    perform "better_supabase".emit_event('person.archived', jsonb_build_object('organizationId', v_tenant, 'personId', archive_person.id, 'name', v_name), 'persons/' || archive_person.id::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."archive_person"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."archive_person"(uuid, boolean) to authenticated, service_role;

-- Links a person to a company with a role, or changes the link. A primary
-- link replaces the company's previous primary contact.
create or replace function "better_supabase"."set_company_person"(company uuid, person uuid, role text, is_primary boolean)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_role text := nullif(trim(set_company_person.role), '');
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select x."tenant_id" into v_tenant from "better_supabase"."companies" x
  join "better_supabase"."people" p on p."id" = set_company_person.person and p."tenant_id" = x."tenant_id"
  where x."id" = set_company_person.company;
  if v_tenant is null then
    raise exception 'company or person not found in one organization' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if coalesce(set_company_person.is_primary, false) then
    update "better_supabase"."company_people" l set "is_primary" = false
    where l."company_id" = set_company_person.company and l."person_id" <> set_company_person.person and l."is_primary";
  end if;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select x."tenant_id", set_company_person.company, set_company_person.person, v_role, coalesce(set_company_person.is_primary, false)
  from "better_supabase"."companies" x where x."id" = set_company_person.company
  on conflict ("company_id", "person_id") do update set "role" = excluded."role", "is_primary" = excluded."is_primary";
  perform "better_supabase".emit_event('company.person_linked', jsonb_build_object('organizationId', v_tenant, 'companyId', set_company_person.company, 'personId', set_company_person.person, 'role', v_role), 'companies/' || set_company_person.company::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  return true;
end;
$$;
revoke execute on function "better_supabase"."set_company_person"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "better_supabase"."set_company_person"(uuid, uuid, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_company_person"(company uuid, person uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_role text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select l."tenant_id", l."role" into v_tenant, v_role from "better_supabase"."company_people" l
  where l."company_id" = remove_company_person.company and l."person_id" = remove_company_person.person;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  delete from "better_supabase"."company_people" l where l."company_id" = remove_company_person.company and l."person_id" = remove_company_person.person;
  perform "better_supabase".emit_event('company.person_unlinked', jsonb_build_object('organizationId', v_tenant, 'companyId', remove_company_person.company, 'personId', remove_company_person.person, 'role', v_role), 'companies/' || remove_company_person.company::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_company_person"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."remove_company_person"(uuid, uuid) to authenticated, service_role;

-- Merges drop into keep: keep's empty fields take drop's values, every
-- installed module moves its rows from drop to keep, and drop is archived
-- with merged_into set.
create or replace function "better_supabase"."merge_companies"(keep uuid, drop uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_keep "better_supabase"."companies";
  v_drop "better_supabase"."companies";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_keep from "better_supabase"."companies" x where x."id" = merge_companies.keep for update;
  select * into v_drop from "better_supabase"."companies" x where x."id" = merge_companies.drop for update;
  if v_keep."id" is null or v_drop."id" is null then
    raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if v_keep."tenant_id" <> v_drop."tenant_id" or v_keep."id" = v_drop."id" or v_drop."merged_into" is not null then
    raise exception 'merge two different, unmerged records of one organization' using errcode = '22023', hint = 'PARTY_MERGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'contacts.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."companies" x set "domain" = null, "merged_into" = merge_companies.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_companies.drop;
  update "better_supabase"."companies" x set "domain" = coalesce(x."domain", v_drop."domain"), "website" = coalesce(x."website", v_drop."website"), "vat_id" = coalesce(x."vat_id", v_drop."vat_id"), "legal_name" = coalesce(x."legal_name", v_drop."legal_name"), "registration_id" = coalesce(x."registration_id", v_drop."registration_id"), "phone" = coalesce(x."phone", v_drop."phone"), "owner_id" = coalesce(x."owner_id", v_drop."owner_id"), "customer_terms_id" = coalesce(x."customer_terms_id", v_drop."customer_terms_id"), "supplier_terms_id" = coalesce(x."supplier_terms_id", v_drop."supplier_terms_id"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "credit_block" = coalesce(x."credit_block", v_drop."credit_block"), "language" = coalesce(x."language", v_drop."language"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
  where x."id" = merge_companies.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", merge_companies.keep, l."person_id", l."role", false
  from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop;
  update "better_supabase"."companies" x set "roles" = array(select distinct r from unnest(x."roles" || v_drop."roles") r order by 1) where x."id" = merge_companies.keep;
  perform better_supabase.merge_subject_refs('better_supabase.companies', merge_companies.keep::text, merge_companies.drop::text);
  perform "better_supabase".emit_event('company.merged', jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop), 'companies/' || merge_companies.keep::text, (v_keep."tenant_id"::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'company.merged',
    category => 'data',
    target_type => 'company',
    record_id => merge_companies.keep::text,
    target_label => v_keep."name",
    summary => 'merged ' || v_drop."name" || ' into ' || v_keep."name",
    tenant => (v_keep."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_keep."tenant_id", 'companyId', merge_companies.keep, 'name', v_keep."name", 'mergedId', merge_companies.drop)
  );
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."companies" x where x."id" = merge_companies.keep);
end;
$$;
revoke execute on function "better_supabase"."merge_companies"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_companies"(uuid, uuid) to authenticated, service_role;

-- Merges drop into keep: keep's empty fields take drop's values, every
-- installed module moves its rows from drop to keep, and drop is archived
-- with merged_into set.
create or replace function "better_supabase"."merge_people"(keep uuid, drop uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_keep "better_supabase"."people";
  v_drop "better_supabase"."people";
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_keep from "better_supabase"."people" x where x."id" = merge_people.keep for update;
  select * into v_drop from "better_supabase"."people" x where x."id" = merge_people.drop for update;
  if v_keep."id" is null or v_drop."id" is null then
    raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if v_keep."tenant_id" <> v_drop."tenant_id" or v_keep."id" = v_drop."id" or v_drop."merged_into" is not null then
    raise exception 'merge two different, unmerged records of one organization' using errcode = '22023', hint = 'PARTY_MERGE_INVALID';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'contacts.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."people" x set "email" = null, "merged_into" = merge_people.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_people.drop;
  update "better_supabase"."people" x set "email" = coalesce(x."email", v_drop."email"), "phone" = coalesce(x."phone", v_drop."phone"), "title" = coalesce(x."title", v_drop."title"), "owner_id" = coalesce(x."owner_id", v_drop."owner_id"), "user_id" = coalesce(x."user_id", v_drop."user_id"), "customer_terms_id" = coalesce(x."customer_terms_id", v_drop."customer_terms_id"), "supplier_terms_id" = coalesce(x."supplier_terms_id", v_drop."supplier_terms_id"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "credit_block" = coalesce(x."credit_block", v_drop."credit_block"), "language" = coalesce(x."language", v_drop."language"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
  where x."id" = merge_people.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", l."company_id", merge_people.keep, l."role", false
  from "better_supabase"."company_people" l where l."person_id" = merge_people.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."person_id" = merge_people.drop;
  update "better_supabase"."people" x set "roles" = array(select distinct r from unnest(x."roles" || v_drop."roles") r order by 1) where x."id" = merge_people.keep;
  update "better_supabase"."person_identities" i set "person_id" = merge_people.keep where i."person_id" = merge_people.drop;
  update "better_supabase"."inbox_conversations" x set "contact_id" = merge_people.keep where x."contact_id" = merge_people.drop;
  perform better_supabase.merge_subject_refs('better_supabase.people', merge_people.keep::text, merge_people.drop::text);
  perform "better_supabase".emit_event('person.merged', jsonb_build_object('organizationId', v_keep."tenant_id", 'personId', merge_people.keep, 'name', v_keep."name", 'mergedId', merge_people.drop), 'persons/' || merge_people.keep::text, (v_keep."tenant_id"::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'person.merged',
    category => 'data',
    target_type => 'person',
    record_id => merge_people.keep::text,
    target_label => v_keep."name",
    summary => 'merged ' || v_drop."name" || ' into ' || v_keep."name",
    tenant => (v_keep."tenant_id"::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_keep."tenant_id", 'personId', merge_people.keep, 'name', v_keep."name", 'mergedId', merge_people.drop)
  );
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."people" x where x."id" = merge_people.keep);
end;
$$;
revoke execute on function "better_supabase"."merge_people"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_people"(uuid, uuid) to authenticated, service_role;

-- A page of the organization's active companies, by name. search matches
-- the name and domain; after_name and after_id continue after the
-- last row of the previous page. role keeps the ones with that role, and
-- supplier_status the suppliers in that status.

create or replace function "better_supabase"."list_companies"(tenant uuid, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer, role text default null, supplier_status text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_like text := '%' || replace(replace(replace(coalesce(list_companies.search, ''), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'customer_terms_id', p."customer_terms_id", 'supplier_terms_id', p."supplier_terms_id", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'credit_block', p."credit_block", 'supplier_status', p."supplier_status", 'language', p."language") order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."companies" x
      where x."tenant_id" = list_companies.tenant
        and x."archived_at" is null
        and (list_companies.search is null or x."name" ilike v_like or x."domain" ilike v_like)
        and (list_companies.lifecycle is null or x."lifecycle" = list_companies.lifecycle)
        and (list_companies.owner is null or x."owner_id" = list_companies.owner)
        and (list_companies.role is null or list_companies.role = any (x."roles"))
        and (list_companies.supplier_status is null or x."supplier_status" = list_companies.supplier_status)
        and (list_companies.after_name is null or (lower(x."name"), x."id") > (lower(list_companies.after_name), list_companies.after_id))
      order by lower(x."name"), x."id"
      limit least(greatest(coalesce(list_companies.page_size, 50), 1), 200)
    ) p
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) from public, anon;
grant execute on function "better_supabase"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) to authenticated, service_role;

-- A page of the organization's active people, by name. search matches
-- the name and email; after_name and after_id continue after the
-- last row of the previous page. role keeps the ones with that role, and
-- supplier_status the suppliers in that status.

create or replace function "better_supabase"."list_people"(tenant uuid, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer, role text default null, supplier_status text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_like text := '%' || replace(replace(replace(coalesce(list_people.search, ''), '\', '\\'), '%', '\%'), '_', '\_') || '%';
begin
  return coalesce((
    select jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'customer_terms_id', p."customer_terms_id", 'supplier_terms_id', p."supplier_terms_id", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'credit_block', p."credit_block", 'supplier_status', p."supplier_status", 'language', p."language") order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."people" x
      where x."tenant_id" = list_people.tenant
        and x."archived_at" is null
        and (list_people.search is null or x."name" ilike v_like or x."email" ilike v_like)
        and (list_people.lifecycle is null or x."lifecycle" = list_people.lifecycle)
        and (list_people.owner is null or x."owner_id" = list_people.owner)
        and (list_people.role is null or list_people.role = any (x."roles"))
        and (list_people.supplier_status is null or x."supplier_status" = list_people.supplier_status)
        and (list_people.after_name is null or (lower(x."name"), x."id") > (lower(list_people.after_name), list_people.after_id))
      order by lower(x."name"), x."id"
      limit least(greatest(coalesce(list_people.page_size, 50), 1), 200)
    ) p
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) from public, anon;
grant execute on function "better_supabase"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) to authenticated, service_role;

-- One active company by id, or null when it is archived, missing or hidden by
-- row level security.
create or replace function "better_supabase"."get_company"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."companies" x
  where x."id" = get_company.id and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."get_company"(uuid) from public, anon;
grant execute on function "better_supabase"."get_company"(uuid) to authenticated, service_role;

-- One active person by id, or null when it is archived, missing or hidden by
-- row level security.
create or replace function "better_supabase"."get_person"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language") from "better_supabase"."people" x
  where x."id" = get_person.id and x."archived_at" is null
$$;
revoke execute on function "better_supabase"."get_person"(uuid) from public, anon;
grant execute on function "better_supabase"."get_person"(uuid) to authenticated, service_role;

-- The people of a company with their role, primary contact first.
create or replace function "better_supabase"."company_people_of"(company uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'customer_terms_id', p."customer_terms_id", 'supplier_terms_id', p."supplier_terms_id", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'credit_block', p."credit_block", 'supplier_status', p."supplier_status", 'language', p."language") || jsonb_build_object('role', l."role", 'is_primary', l."is_primary")
    order by l."is_primary" desc, lower(p."name"), p."id"), '[]'::jsonb)
  from "better_supabase"."company_people" l join "better_supabase"."people" p on p."id" = l."person_id"
  where l."company_id" = company_people_of.company and p."archived_at" is null
$$;
revoke execute on function "better_supabase"."company_people_of"(uuid) from public, anon;
grant execute on function "better_supabase"."company_people_of"(uuid) to authenticated, service_role;
-- Creates or changes payment terms. data: code (unique per organization),
-- name, days (due days), discountBps and discountDays (an early-payment
-- discount the buyer may deduct), creditRestrictionBps (the part of the
-- document the tax does not apply to). A key that is not in data keeps its
-- value. Internal: save_payment_term and the import target call it.
create or replace function "better_supabase"."payment_term_write"(tenant uuid, data jsonb, id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := coalesce(payment_term_write.data, '{}'::jsonb);
  v_id uuid := payment_term_write.id;
  v_row "better_supabase"."payment_terms";
begin
  if jsonb_typeof(v_data) <> 'object'
    or (v_data ? 'days' and (coalesce(v_data ->> 'days', '') !~ '^[0-9]{1,5}$' or (v_data ->> 'days')::integer > 3650)) or (v_data ? 'discountBps' and (coalesce(v_data ->> 'discountBps', '') !~ '^[0-9]{1,5}$' or (v_data ->> 'discountBps')::integer > 10000))
    or (v_data ? 'discountDays' and (coalesce(v_data ->> 'discountDays', '') !~ '^[0-9]{1,5}$' or (v_data ->> 'discountDays')::integer > 3650)) or (v_data ? 'creditRestrictionBps' and (coalesce(v_data ->> 'creditRestrictionBps', '') !~ '^[0-9]{1,5}$' or (v_data ->> 'creditRestrictionBps')::integer > 10000))
    or coalesce((v_data ->> 'discountDays')::integer, 0) > coalesce((v_data ->> 'days')::integer, 30)
    or (v_data ? 'code' and length(coalesce(trim(v_data ->> 'code'), '')) not between 1 and 50)
    or (v_data ? 'name' and length(coalesce(trim(v_data ->> 'name'), '')) not between 1 and 300) then
    raise exception 'payment terms need a code and a name; days are 0 to 3650, the discount and the credit restriction are 0 to 10000 basis points, discountDays 0 to 3650' using errcode = '22023', hint = 'PAYMENT_TERM_INVALID';
  end if;
  if v_id is null and v_data ->> 'code' is not null then
    select x."id" into v_id from "better_supabase"."payment_terms" x
    where x."tenant_id" = payment_term_write.tenant and x."code" = trim(v_data ->> 'code');
  end if;
  if v_id is null then
    if not (v_data ? 'code' and v_data ? 'name') then
      raise exception 'payment terms need a code and a name; days are 0 to 3650, the discount and the credit restriction are 0 to 10000 basis points, discountDays 0 to 3650' using errcode = '22023', hint = 'PAYMENT_TERM_INVALID';
    end if;
    insert into "better_supabase"."payment_terms" ("tenant_id", "code", "name", "days", "discount_bps", "discount_days", "credit_restriction_bps")
    values (payment_term_write.tenant, trim(v_data ->> 'code'), trim(v_data ->> 'name'),
      coalesce((v_data ->> 'days')::integer, 30), coalesce((v_data ->> 'discountBps')::integer, 0),
      coalesce((v_data ->> 'discountDays')::integer, 0), coalesce((v_data ->> 'creditRestrictionBps')::integer, 0))
    returning * into v_row;
  else
    begin
      update "better_supabase"."payment_terms" x set
        "code" = coalesce(trim(v_data ->> 'code'), x."code"),
        "name" = coalesce(trim(v_data ->> 'name'), x."name"),
        "days" = coalesce((v_data ->> 'days')::integer, x."days"),
        "discount_bps" = coalesce((v_data ->> 'discountBps')::integer, x."discount_bps"),
        "discount_days" = coalesce((v_data ->> 'discountDays')::integer, x."discount_days"),
        "credit_restriction_bps" = coalesce((v_data ->> 'creditRestrictionBps')::integer, x."credit_restriction_bps"),
        "updated_at" = now()
      where x."id" = v_id and x."tenant_id" = payment_term_write.tenant
      returning * into v_row;
    exception when unique_violation then
      raise exception 'another payment terms row has this code' using errcode = '23505', hint = 'PAYMENT_TERM_CODE_TAKEN';
    end;
    if v_row."id" is null then
      raise exception 'payment terms not found' using errcode = 'P0002', hint = 'PAYMENT_TERM_NOT_FOUND';
    end if;
  end if;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'code', v_row."code", 'name', v_row."name", 'days', v_row."days", 'discountBps', v_row."discount_bps", 'discountDays', v_row."discount_days", 'creditRestrictionBps', v_row."credit_restriction_bps", 'createdAt', v_row."created_at", 'updatedAt', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."payment_term_write"(uuid, jsonb, uuid) from public, anon, authenticated;

-- Creates payment terms, or changes the ones with the same code. Needs
-- contacts.manage. Returns the row.
create or replace function "better_supabase"."save_payment_term"(tenant uuid, attrs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_payment_term.tenant, 'contacts.manage'), false)) then
    raise exception 'not allowed to manage payment terms' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  return "better_supabase"."payment_term_write"(save_payment_term.tenant, save_payment_term.attrs, null);
end;
$$;
revoke execute on function "better_supabase"."save_payment_term"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."save_payment_term"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."list_payment_terms"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'code', x."code", 'name', x."name", 'days', x."days", 'discountBps', x."discount_bps", 'discountDays', x."discount_days", 'creditRestrictionBps', x."credit_restriction_bps", 'createdAt', x."created_at", 'updatedAt', x."updated_at") order by x."code"), '[]'::jsonb)
  from "better_supabase"."payment_terms" x
  where x."tenant_id" = list_payment_terms.tenant
$$;
revoke execute on function "better_supabase"."list_payment_terms"(uuid) from public, anon;
grant execute on function "better_supabase"."list_payment_terms"(uuid) to authenticated, service_role;

-- Deletes payment terms. Parties that point at them lose the link; invoices
-- keep the terms they copied. Needs contacts.manage.
create or replace function "better_supabase"."delete_payment_term"(id uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."payment_terms" x where x."id" = delete_payment_term.id;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.manage'), false)) then
    raise exception 'not allowed to manage payment terms' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  delete from "better_supabase"."payment_terms" x where x."id" = delete_payment_term.id;
  return found;
end;
$$;
revoke execute on function "better_supabase"."delete_payment_term"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_payment_term"(uuid) to authenticated, service_role;

-- Replaces how a party gets its documents. prefs: [{ documentType, channel
-- (email, post or portal), copies (default 1), email }]; an email channel
-- without an email uses the party's own. Returns the stored list. Needs
-- contacts.write.
create or replace function "better_supabase"."set_document_delivery_preferences"(party uuid, prefs jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_tenant uuid;
  v_name text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select 'company', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."companies" x where x."id" = set_document_delivery_preferences.party and x."merged_into" is null;
  if v_kind is null then
    select 'person', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."people" x where x."id" = set_document_delivery_preferences.party and x."merged_into" is null;
  end if;
  if v_kind is null then
    raise exception 'company or person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(set_document_delivery_preferences.prefs) is distinct from 'array'
    or jsonb_array_length(set_document_delivery_preferences.prefs) > 100
    or exists (
      select 1 from jsonb_array_elements(set_document_delivery_preferences.prefs) e
      where jsonb_typeof(e) <> 'object'
        or length(coalesce(trim(e ->> 'documentType'), '')) not between 1 and 100
        or coalesce(e ->> 'channel', '') not in ('email', 'post', 'portal')
        or coalesce(e ->> 'copies', '1') !~ '^[0-9]{1,2}$'
        or coalesce(nullif(e ->> 'copies', '')::integer, 1) not between 1 and 20
        or (e ->> 'email' is not null and lower(trim(e ->> 'email')) !~ '^[^@[:space:]]+@[^@[:space:]]+$')
    ) or (
      select count(*) <> count(distinct (trim(e ->> 'documentType'), e ->> 'channel'))
      from jsonb_array_elements(set_document_delivery_preferences.prefs) e
    ) then
    raise exception 'prefs is an array of at most 100 { documentType, channel, copies, email } with a unique documentType and channel' using errcode = '22023', hint = 'DELIVERY_PREFERENCE_INVALID';
  end if;
  delete from "better_supabase"."document_delivery_preferences" x where x."party_id" = set_document_delivery_preferences.party and x."tenant_id" = v_tenant;
  insert into "better_supabase"."document_delivery_preferences" ("tenant_id", "party_id", "document_type", "channel", "copies", "email")
  select v_tenant, set_document_delivery_preferences.party, trim(e ->> 'documentType'), e ->> 'channel',
    coalesce(nullif(e ->> 'copies', '')::integer, 1), nullif(lower(trim(e ->> 'email')), '')
  from jsonb_array_elements(set_document_delivery_preferences.prefs) e;
  return "better_supabase"."list_document_delivery_preferences"(set_document_delivery_preferences.party);
end;
$$;
revoke execute on function "better_supabase"."set_document_delivery_preferences"(uuid, jsonb) from public, anon;
grant execute on function "better_supabase"."set_document_delivery_preferences"(uuid, jsonb) to authenticated, service_role;

create or replace function "better_supabase"."list_document_delivery_preferences"(party uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'partyId', x."party_id", 'documentType', x."document_type", 'channel', x."channel", 'copies', x."copies", 'email', x."email") order by x."document_type", x."channel"), '[]'::jsonb)
  from "better_supabase"."document_delivery_preferences" x
  where x."party_id" = list_document_delivery_preferences.party
$$;
revoke execute on function "better_supabase"."list_document_delivery_preferences"(uuid) from public, anon;
grant execute on function "better_supabase"."list_document_delivery_preferences"(uuid) to authenticated, service_role;

-- The writer of one delivery preference for imports. data: { partyId,
-- documentType, channel, copies, email }.
create or replace function "better_supabase"."delivery_preference_write"(tenant uuid, data jsonb, id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row "better_supabase"."document_delivery_preferences";
begin
  if jsonb_typeof(delivery_preference_write.data) is distinct from 'object'
    or coalesce(delivery_preference_write.data ->> 'partyId', '') !~ '^[0-9a-fA-F-]{36}$'
    or length(coalesce(trim(delivery_preference_write.data ->> 'documentType'), '')) not between 1 and 100
    or coalesce(delivery_preference_write.data ->> 'channel', '') not in ('email', 'post', 'portal')
    or coalesce(delivery_preference_write.data ->> 'copies', '1') !~ '^[0-9]{1,2}$'
    or coalesce(nullif(delivery_preference_write.data ->> 'copies', '')::integer, 1) not between 1 and 20
    or (delivery_preference_write.data ->> 'email' is not null and lower(trim(delivery_preference_write.data ->> 'email')) !~ '^[^@[:space:]]+@[^@[:space:]]+$') then
    raise exception 'a delivery preference needs a party, a document type and a channel of email, post or portal' using errcode = '22023', hint = 'DELIVERY_PREFERENCE_INVALID';
  end if;
  insert into "better_supabase"."document_delivery_preferences" ("tenant_id", "party_id", "document_type", "channel", "copies", "email")
  values (delivery_preference_write.tenant, (delivery_preference_write.data ->> 'partyId')::uuid, trim(delivery_preference_write.data ->> 'documentType'),
    delivery_preference_write.data ->> 'channel', coalesce(nullif(delivery_preference_write.data ->> 'copies', '')::integer, 1),
    nullif(lower(trim(delivery_preference_write.data ->> 'email')), ''))
  on conflict ("tenant_id", "party_id", "document_type", "channel") do update
    set "copies" = excluded."copies", "email" = excluded."email", "updated_at" = now()
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'partyId', v_row."party_id", 'documentType', v_row."document_type", 'channel', v_row."channel", 'copies', v_row."copies", 'email', v_row."email");
end;
$$;
revoke execute on function "better_supabase"."delivery_preference_write"(uuid, jsonb, uuid) from public, anon, authenticated;

-- The payment terms an invoice copies: terms_id when it is given, otherwise
-- the party's customer terms (supplier terms for direction purchase). Null
-- when there are none. Internal: create_invoice calls it.
create or replace function "better_supabase"."resolve_payment_terms"(tenant uuid, terms_id uuid, party text, direction text default 'sales')
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object('id', z."id", 'days', z."days", 'discountBps', z."discount_bps", 'discountDays', z."discount_days", 'creditRestrictionBps', z."credit_restriction_bps")
  from "better_supabase"."payment_terms" z
  where z."tenant_id" = resolve_payment_terms.tenant
    and z."id" = coalesce(resolve_payment_terms.terms_id, (select o.id from (select case when resolve_payment_terms.direction = 'purchase' then p."supplier_terms_id" else p."customer_terms_id" end as id
      from "better_supabase"."companies" p where p."id"::text = resolve_payment_terms.party and p."tenant_id" = resolve_payment_terms.tenant
      union all
      select case when resolve_payment_terms.direction = 'purchase' then p."supplier_terms_id" else p."customer_terms_id" end as id
      from "better_supabase"."people" p where p."id"::text = resolve_payment_terms.party and p."tenant_id" = resolve_payment_terms.tenant) o where o.id is not null limit 1))
$$;
revoke execute on function "better_supabase"."resolve_payment_terms"(uuid, uuid, text, text) from public, anon, authenticated;

-- The import target of the payment terms entity: item.data is the input of the writer.
create or replace function "better_supabase"."import_payment_term"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  if jsonb_typeof(import_payment_term.item -> 'data') is distinct from 'object' then
    raise exception 'a payment terms item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."payment_term_write"((import_payment_term.item ->> 'tenant')::uuid, import_payment_term.item -> 'data', import_payment_term.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
revoke execute on function "better_supabase"."import_payment_term"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_payment_term"(uuid, jsonb, text) to service_role;

-- When a payment terms row last changed, for the conflict check of imports.
create or replace function "better_supabase"."payment_term_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."payment_terms" x where x."id"::text = payment_term_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."payment_term_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."payment_term_updated_at"(text) to service_role;

-- The import target of the delivery preference entity: item.data is the input of the writer.
create or replace function "better_supabase"."import_document_delivery_preference"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  if jsonb_typeof(import_document_delivery_preference.item -> 'data') is distinct from 'object' then
    raise exception 'a delivery preference item needs data' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  v_row := "better_supabase"."delivery_preference_write"((import_document_delivery_preference.item ->> 'tenant')::uuid, import_document_delivery_preference.item -> 'data', import_document_delivery_preference.subject_id::uuid);
  return jsonb_build_object('subjectId', v_row ->> 'id', 'updatedAt', v_row ->> 'updatedAt');
end;
$$;
revoke execute on function "better_supabase"."import_document_delivery_preference"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_document_delivery_preference"(uuid, jsonb, text) to service_role;

-- When a delivery preference row last changed, for the conflict check of imports.
create or replace function "better_supabase"."document_delivery_preference_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."document_delivery_preferences" x where x."id"::text = document_delivery_preference_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."document_delivery_preference_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."document_delivery_preference_updated_at"(text) to service_role;

-- Sets the roles of a company or person (customer, supplier and so on),
-- sorted and without duplicates. Returns { type, party }.
create or replace function "better_supabase"."set_party_roles"(party uuid, roles text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_tenant uuid;
  v_name text;
  v_roles text[] := array(select distinct trim(r) from unnest(coalesce(set_party_roles.roles, '{}'::text[])) r where nullif(trim(r), '') is not null order by 1);
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select 'company', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."companies" x where x."id" = set_party_roles.party and x."merged_into" is null;
  if v_kind is null then
    select 'person', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."people" x where x."id" = set_party_roles.party and x."merged_into" is null;
  end if;
  if v_kind is null then
    raise exception 'company or person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if not (v_roles <@ '{customer,supplier,funder,partner}'::text[]) then
    raise exception 'unknown party role' using errcode = '22023', hint = 'PARTY_ROLES_INVALID';
  end if;
  if v_kind = 'company' then
    update "better_supabase"."companies" x set "roles" = v_roles, "updated_at" = now()
    where x."id" = set_party_roles.party and x."roles" is distinct from v_roles;
    if found then
      perform "better_supabase".emit_event('company.updated', jsonb_build_object('organizationId', v_tenant, 'companyId', set_party_roles.party, 'name', v_name), 'companies/' || set_party_roles.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
    end if;
  elsif v_kind = 'person' then
    update "better_supabase"."people" x set "roles" = v_roles, "updated_at" = now()
    where x."id" = set_party_roles.party and x."roles" is distinct from v_roles;
    if found then
      perform "better_supabase".emit_event('person.updated', jsonb_build_object('organizationId', v_tenant, 'personId', set_party_roles.party, 'name', v_name), 'persons/' || set_party_roles.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
    end if;
  end if;
  return case v_kind
    when 'company' then (select jsonb_build_object('type', 'company', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language")) from "better_supabase"."companies" x where x."id" = set_party_roles.party)
    when 'person' then (select jsonb_build_object('type', 'person', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language")) from "better_supabase"."people" x where x."id" = set_party_roles.party)
  end;
end;
$$;
revoke execute on function "better_supabase"."set_party_roles"(uuid, text[]) from public, anon;
grant execute on function "better_supabase"."set_party_roles"(uuid, text[]) to authenticated, service_role;

-- Sets where a supplier stands: approved, conditional, blocked, or null for
-- not assessed. Needs contacts.approve_supplier. Returns { type, party }.
create or replace function "better_supabase"."set_supplier_status"(party uuid, status text, reason text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind text;
  v_tenant uuid;
  v_name text;
  v_status text := nullif(trim(set_supplier_status.status), '');
  v_reason text := nullif(trim(set_supplier_status.reason), '');
  v_previous text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select 'company', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."companies" x where x."id" = set_supplier_status.party and x."merged_into" is null;
  if v_kind is null then
    select 'person', x."tenant_id", x."name" into v_kind, v_tenant, v_name
  from "better_supabase"."people" x where x."id" = set_supplier_status.party and x."merged_into" is null;
  end if;
  if v_kind is null then
    raise exception 'company or person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.approve_supplier'), false)) then
    raise exception 'not allowed to approve suppliers' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if v_status is not null and v_status not in ('approved', 'conditional', 'blocked') then
    raise exception 'a supplier status is approved, conditional or blocked' using errcode = '22023', hint = 'PARTY_SUPPLIER_STATUS_INVALID';
  end if;
  if length(v_reason) > 2000 then
    raise exception 'a reason has at most 2000 characters' using errcode = '22023', hint = 'PARTY_SUPPLIER_STATUS_INVALID';
  end if;
  if v_kind = 'company' then
    select x."supplier_status" into v_previous from "better_supabase"."companies" x where x."id" = set_supplier_status.party for update;
    update "better_supabase"."companies" x set "supplier_status" = v_status, "updated_at" = now()
    where x."id" = set_supplier_status.party and x."supplier_status" is distinct from v_status;
    if found then
      perform "better_supabase".emit_event('company.supplier_status_changed', jsonb_build_object('organizationId', v_tenant, 'companyId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason), 'companies/' || set_supplier_status.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'company.supplier_status_changed',
    category => 'data',
    target_type => 'company',
    record_id => set_supplier_status.party::text,
    target_label => v_name,
    summary => 'supplier status of ' || v_name || ' set to ' || coalesce(v_status, 'none'),
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'companyId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason)
  );
    end if;
  elsif v_kind = 'person' then
    select x."supplier_status" into v_previous from "better_supabase"."people" x where x."id" = set_supplier_status.party for update;
    update "better_supabase"."people" x set "supplier_status" = v_status, "updated_at" = now()
    where x."id" = set_supplier_status.party and x."supplier_status" is distinct from v_status;
    if found then
      perform "better_supabase".emit_event('person.supplier_status_changed', jsonb_build_object('organizationId', v_tenant, 'personId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason), 'persons/' || set_supplier_status.party::text, (v_tenant::text)::text, null, 'better-supabase/contacts');
  perform better_supabase.audit_event(
    event_type => 'person.supplier_status_changed',
    category => 'data',
    target_type => 'person',
    record_id => set_supplier_status.party::text,
    target_label => v_name,
    summary => 'supplier status of ' || v_name || ' set to ' || coalesce(v_status, 'none'),
    tenant => (v_tenant::text)::uuid,
    metadata => jsonb_build_object('organizationId', v_tenant, 'personId', set_supplier_status.party, 'name', v_name, 'status', v_status, 'previousStatus', v_previous, 'reason', v_reason)
  );
    end if;
  end if;
  return case v_kind
    when 'company' then (select jsonb_build_object('type', 'company', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language")) from "better_supabase"."companies" x where x."id" = set_supplier_status.party)
    when 'person' then (select jsonb_build_object('type', 'person', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'customer_terms_id', x."customer_terms_id", 'supplier_terms_id', x."supplier_terms_id", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'credit_block', x."credit_block", 'supplier_status', x."supplier_status", 'language', x."language")) from "better_supabase"."people" x where x."id" = set_supplier_status.party)
  end;
end;
$$;
revoke execute on function "better_supabase"."set_supplier_status"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."set_supplier_status"(uuid, text, text) to authenticated, service_role;

-- The supplier status a company's qualifications give it: approved when the
-- gap report lists no missing or expired qualification for it, conditional
-- otherwise. Pass it to set_supplier_status to apply it.
create or replace function "better_supabase"."supplier_status_from_qualifications"(party uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_gaps jsonb;
begin
  select x."tenant_id" into v_tenant from "better_supabase"."companies" x
  where x."id" = supplier_status_from_qualifications.party and x."merged_into" is null;
  if v_tenant is null then
    raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.read'), false)) then
    raise exception 'not allowed to read companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  v_gaps := "better_supabase"."qualification_gaps"(v_tenant, 'company', jsonb_build_object('holderId', supplier_status_from_qualifications.party::text));
  return case when exists (
    select 1 from jsonb_array_elements(v_gaps) g where g ->> 'status' in ('missing', 'expired')
  ) then 'conditional' else 'approved' end;
end;
$$;
revoke execute on function "better_supabase"."supplier_status_from_qualifications"(uuid) from public, anon;
grant execute on function "better_supabase"."supplier_status_from_qualifications"(uuid) to authenticated, service_role;

-- The person contact fields name, for the inbox and the channels: by id,
-- then by the identity on a channel ({ channel, address }), the user, then
-- the email. Fills in what the person lacks, or creates a lead; an identity
-- is attached when given. A merged person resolves to the one it was merged
-- into. No permission check: callers check.
create or replace function "better_supabase"."resolve_person"(tenant uuid, input jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_person uuid;
  v_identity jsonb := input -> 'identity';
  v_channel text := nullif(trim(v_identity ->> 'channel'), '');
  v_address text := nullif(trim(coalesce(v_identity ->> 'address', v_identity ->> 'external_id')), '');
  v_email text := lower(nullif(trim(input ->> 'email'), ''));
  v_name text;
begin
  if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+$' then
    v_email := null;
  end if;
  if nullif(trim(input ->> 'id'), '') is not null then
    select p."id" into v_person from "better_supabase"."people" p
    where p."id" = nullif(trim(input ->> 'id'), '')::uuid and p."tenant_id" = resolve_person.tenant;
    if v_person is null then
      raise exception 'contact not found' using errcode = 'P0002', hint = 'CONTACT_NOT_FOUND';
    end if;
  end if;
  if v_person is null and v_channel is not null and v_address is not null then
    select i."person_id" into v_person from "better_supabase"."person_identities" i
    where i."tenant_id" = resolve_person.tenant and i."channel" = v_channel and i."address" = v_address;
  end if;
  if v_person is null and nullif(trim(input ->> 'user_id'), '') is not null then
    select p."id" into v_person from "better_supabase"."people" p
    where p."tenant_id" = resolve_person.tenant and p."user_id" = nullif(trim(input ->> 'user_id'), '')::uuid
    order by p."archived_at" nulls first, p."created_at", p."id" limit 1;
  end if;
  if v_person is null and v_email is not null then
    select p."id" into v_person from "better_supabase"."people" p
    where p."tenant_id" = resolve_person.tenant and p."email" = v_email and p."archived_at" is null;
  end if;
  if v_person is not null then
    select coalesce(p."merged_into", p."id") into v_person from "better_supabase"."people" p where p."id" = v_person;
    update "better_supabase"."people" p set
      "email" = coalesce(p."email", case when not exists (select 1 from "better_supabase"."people" o where o."tenant_id" = p."tenant_id" and o."email" = v_email and o."archived_at" is null and o."id" <> p."id") then v_email end),
      "phone" = coalesce(p."phone", nullif(trim(input ->> 'phone'), '')),
      "user_id" = coalesce(p."user_id", nullif(trim(input ->> 'user_id'), '')::uuid),
      "avatar_url" = coalesce(nullif(trim(input ->> 'avatar_url'), ''), p."avatar_url"),
      "metadata" = p."metadata" || case when jsonb_typeof(input -> 'metadata') = 'object' then input -> 'metadata' else '{}'::jsonb end,
      "updated_at" = now()
    where p."id" = v_person
      and (p."email", p."phone", p."user_id", p."avatar_url", p."metadata") is distinct from (coalesce(p."email", case when not exists (select 1 from "better_supabase"."people" o where o."tenant_id" = p."tenant_id" and o."email" = v_email and o."archived_at" is null and o."id" <> p."id") then v_email end), coalesce(p."phone", nullif(trim(input ->> 'phone'), '')), coalesce(p."user_id", nullif(trim(input ->> 'user_id'), '')::uuid), coalesce(nullif(trim(input ->> 'avatar_url'), ''), p."avatar_url"), p."metadata" || case when jsonb_typeof(input -> 'metadata') = 'object' then input -> 'metadata' else '{}'::jsonb end);
  else
    v_name := left(coalesce(nullif(trim(input ->> 'name'), ''), v_email, nullif(trim(input ->> 'phone'), ''), v_address, 'Unknown contact'), 300);
    begin
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "lifecycle", "user_id", "avatar_url", "metadata", "created_by")
      values (resolve_person.tenant, v_name, v_email, nullif(trim(input ->> 'phone'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1], nullif(trim(input ->> 'user_id'), '')::uuid, nullif(trim(input ->> 'avatar_url'), ''), case when jsonb_typeof(input -> 'metadata') = 'object' then input -> 'metadata' else '{}'::jsonb end || case when v_email is null and nullif(trim(input ->> 'email'), '') is not null then jsonb_build_object('email', nullif(trim(input ->> 'email'), '')) else '{}'::jsonb end, auth.uid())
      returning "id" into v_person;
      perform "better_supabase".emit_event('person.created', jsonb_build_object('organizationId', resolve_person.tenant, 'personId', v_person, 'name', v_name), 'persons/' || v_person::text, (resolve_person.tenant::text)::text, null, 'better-supabase/contacts');
    exception when unique_violation then
      select p."id" into v_person from "better_supabase"."people" p
      where p."tenant_id" = resolve_person.tenant and p."email" = v_email and p."archived_at" is null;
      if v_person is null then
        raise;
      end if;
    end;
  end if;
  if v_channel is not null and v_address is not null then
    insert into "better_supabase"."person_identities" ("tenant_id", "person_id", "channel", "address")
    values (resolve_person.tenant, v_person, v_channel, v_address)
    on conflict do nothing;
  end if;
  return v_person;
end;
$$;
revoke execute on function "better_supabase"."resolve_person"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."resolve_person"(uuid, jsonb) to service_role;

-- A person's identities, by channel and address.
create or replace function "better_supabase"."list_person_identities"(person uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', i."id", 'tenant_id', i."tenant_id", 'person_id', i."person_id", 'channel', i."channel", 'address', i."address", 'verified_at', i."verified_at", 'created_at', i."created_at") order by i."channel", i."address"), '[]'::jsonb)
  from "better_supabase"."person_identities" i where i."person_id" = list_person_identities.person
$$;
revoke execute on function "better_supabase"."list_person_identities"(uuid) from public, anon;
grant execute on function "better_supabase"."list_person_identities"(uuid) to authenticated, service_role;

-- Adds an address on a channel to a person, or marks it verified. An address
-- another person of the organization holds is refused.
create or replace function "better_supabase"."add_person_identity"(person uuid, channel text, address text, verified boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_channel text := nullif(trim(add_person_identity.channel), '');
  v_address text := nullif(trim(add_person_identity.address), '');
  v_holder uuid;
  v_row jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select p."tenant_id" into v_tenant from "better_supabase"."people" p
  where p."id" = add_person_identity.person and p."merged_into" is null;
  if v_tenant is null then
    raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if v_channel is null or v_address is null then
    raise exception 'an identity needs a channel and an address' using errcode = '22023', hint = 'PARTY_IDENTITY_INVALID';
  end if;
  select i."person_id" into v_holder from "better_supabase"."person_identities" i
  where i."tenant_id" = v_tenant and i."channel" = v_channel and i."address" = v_address;
  if v_holder is not null and v_holder <> add_person_identity.person then
    raise exception 'another person has this address' using errcode = '23505', hint = 'PARTY_IDENTITY_TAKEN';
  end if;
  insert into "better_supabase"."person_identities" ("tenant_id", "person_id", "channel", "address", "verified_at")
  values (v_tenant, add_person_identity.person, v_channel, v_address, case when add_person_identity.verified then now() end)
  on conflict do nothing;
  if add_person_identity.verified then
    update "better_supabase"."person_identities" i set "verified_at" = coalesce(i."verified_at", now())
    where i."tenant_id" = v_tenant and i."channel" = v_channel and i."address" = v_address;
  end if;
  select jsonb_build_object('id', i."id", 'tenant_id', i."tenant_id", 'person_id', i."person_id", 'channel', i."channel", 'address', i."address", 'verified_at', i."verified_at", 'created_at', i."created_at") into v_row from "better_supabase"."person_identities" i
  where i."tenant_id" = v_tenant and i."channel" = v_channel and i."address" = v_address;
  return v_row;
end;
$$;
revoke execute on function "better_supabase"."add_person_identity"(uuid, text, text, boolean) from public, anon;
grant execute on function "better_supabase"."add_person_identity"(uuid, text, text, boolean) to authenticated, service_role;

create or replace function "better_supabase"."remove_person_identity"(identity uuid)
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
  select i."tenant_id" into v_tenant from "better_supabase"."person_identities" i where i."id" = remove_person_identity.identity;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'contacts.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  delete from "better_supabase"."person_identities" i where i."id" = remove_person_identity.identity;
  return true;
end;
$$;
revoke execute on function "better_supabase"."remove_person_identity"(uuid) from public, anon;
grant execute on function "better_supabase"."remove_person_identity"(uuid) to authenticated, service_role;

-- The person an address on a channel belongs to, or null.
create or replace function "better_supabase"."find_person_by_identity"(tenant uuid, channel text, address text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(p) || jsonb_build_object('roles', p."roles", 'customer_terms_id', p."customer_terms_id", 'supplier_terms_id', p."supplier_terms_id", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'credit_block', p."credit_block", 'supplier_status', p."supplier_status", 'language', p."language") from "better_supabase"."person_identities" i
  join "better_supabase"."people" p on p."id" = i."person_id"
  where i."tenant_id" = find_person_by_identity.tenant
    and i."channel" = trim(find_person_by_identity.channel)
    and i."address" = trim(find_person_by_identity.address)
$$;
revoke execute on function "better_supabase"."find_person_by_identity"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."find_person_by_identity"(uuid, text, text) to authenticated, service_role;

-- A conversation's contact and an identity link's contact are people.

alter table "better_supabase"."inbox_conversations" add constraint "inbox_conversations_contact_id_fkey"
  foreign key ("contact_id") references "better_supabase"."people" ("id") on delete cascade;

-- The people who represent a record (a client's guardian, a legal
-- representative), with their role and authority. Runs as the caller, so the
-- relations and people policies decide what they see. Ended links come last.
create or replace function "better_supabase"."list_representatives"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r."id", 'organizationId', r."tenant_id"::text,
    'personId', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone",
    'role', r."data" ->> 'role', 'authority', r."data" ->> 'authority',
    'validFrom', r."data" ->> 'valid_from', 'validUntil', r."data" ->> 'valid_until',
    'active', (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end), 'createdAt', r."created_at"
  ) order by (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end) desc, p."name", r."id"), '[]'::jsonb)
  from "better_supabase"."relations" r
  join "better_supabase"."people" p on p."id"::text = r."source_id" and p."tenant_id" = r."tenant_id"
  where r."kind" = 'represents' and r."source_type" = 'person'
    and r."target_type" = list_representatives.subject_type
    and r."target_id" = list_representatives.subject_id
$$;
revoke execute on function "better_supabase"."list_representatives"(text, text) from public, anon;
grant execute on function "better_supabase"."list_representatives"(text, text) to authenticated, service_role;

-- The records the caller represents in tenant, as a guest whose party is the
-- representative, while the link holds.
create or replace function "better_supabase"."represented_by_me"(tenant uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r."id", 'organizationId', r."tenant_id"::text, 'personId', r."source_id",
      'subjectType', r."target_type", 'subjectId', r."target_id",
      'role', r."data" ->> 'role', 'authority', r."data" ->> 'authority',
    'validFrom', r."data" ->> 'valid_from', 'validUntil', r."data" ->> 'valid_until'
    ) order by r."created_at", r."id"), '[]'::jsonb)
    from "better_supabase"."relations" r
    where r."tenant_id" = represented_by_me.tenant
      and r."kind" = 'represents' and r."source_type" = 'person'
      and (case when r."data" ->> 'valid_from' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_from', 'date') then (r."data" ->> 'valid_from')::date <= current_date
      else false end) and (case when r."data" ->> 'valid_until' is null then true
      when pg_input_is_valid(r."data" ->> 'valid_until', 'date') then (r."data" ->> 'valid_until')::date >= current_date
      else false end)
      and ((represented_by_me.tenant)::text, ('person')::text, (r."source_id")::text) in (select g.tenant, g.party_type, g.party_id from better_supabase.portal_parties() g)
  );
end;
$$;
revoke execute on function "better_supabase"."represented_by_me"(uuid) from public, anon;
grant execute on function "better_supabase"."represented_by_me"(uuid) to authenticated, service_role;

-- One party. kind is person, company or auto (a legal suffix is a company).
-- A name comes from displayName, then legalName, then the person names, then
-- number. Anything but displayName adds IMPORT_NAME_FALLBACK. A repeat whose
-- stored columns already match returns without writing.
create or replace function "better_supabase"."import_party"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_party.item -> 'data';
  v_tenant uuid := (import_party.item ->> 'tenant')::uuid;
  v_display text := nullif(btrim(v_data ->> 'displayName'), '');
  v_legal text := nullif(btrim(v_data ->> 'legalName'), '');
  v_person text := nullif(btrim(concat_ws(' ', v_data ->> 'givenName', v_data ->> 'infix', v_data ->> 'lastName')), '');
  v_number text := nullif(btrim(v_data ->> 'number'), '');
  v_name text := coalesce(v_display, v_legal, v_person, v_number);
  v_kind text := coalesce(nullif(v_data ->> 'kind', ''), 'auto');
  v_warnings jsonb := '[]'::jsonb;
  v_id uuid;
  v_updated timestamptz;
  v_same boolean;
begin
  if jsonb_typeof(v_data) is distinct from 'object' or v_name is null then
    raise exception 'a party needs a display name, a legal name, a person name or a number' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if v_display is null then
    v_warnings := jsonb_build_array(jsonb_build_object('code', 'IMPORT_NAME_FALLBACK', 'message', 'the party name came from a fallback'));
  end if;
  if v_kind = 'auto' then
    v_kind := case when v_name ~* '\m(b\.?v\.?|n\.?v\.?|gmbh|ltd\.?|llc|inc\.?|bvba|vof|stichting|holding)\M' then 'company' else 'person' end;
  end if;
  if v_kind = 'company' then
    if import_party.subject_id is not null then
      select x."id", x."updated_at", x."name" is not distinct from v_name and x."legal_name" is not distinct from coalesce(v_legal, v_name) and x."vat_id" is not distinct from nullif(btrim(v_data ->> 'vatId'), '') and x."registration_id" is not distinct from nullif(btrim(v_data ->> 'registrationId'), '') and x."phone" is not distinct from better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region') and x."billing_email" is not distinct from nullif(lower(btrim(v_data ->> 'billingEmail')), '') and x."bill_to_id" is not distinct from nullif(coalesce(import_party.item -> 'resolved' ->> 'billTo', v_data ->> 'billToId'), '')::uuid and x."lifecycle" is not distinct from coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,prospect,customer,churned}'::text[])[1]) and x."language" is not distinct from nullif(btrim(v_data ->> 'language'), '') and x."roles" is not distinct from case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end and x."customer_terms_id" is not distinct from (select p."id" from "better_supabase"."payment_terms" p where p."tenant_id" = v_tenant and p."code" = nullif(btrim(v_data ->> 'termsCode'), '')) and x."archived_at" is not distinct from nullif(v_data ->> 'archivedAt', '')::timestamptz into v_id, v_updated, v_same
      from "better_supabase"."companies" x
      where x."id" = import_party.subject_id::uuid and x."tenant_id" = v_tenant;
      if v_id is not null and v_same then
        return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated, 'warnings', v_warnings);
      end if;
      update "better_supabase"."companies" x set "name" = v_name, "legal_name" = coalesce(v_legal, v_name), "vat_id" = nullif(btrim(v_data ->> 'vatId'), ''), "registration_id" = nullif(btrim(v_data ->> 'registrationId'), ''), "phone" = better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), "billing_email" = nullif(lower(btrim(v_data ->> 'billingEmail')), ''), "bill_to_id" = nullif(coalesce(import_party.item -> 'resolved' ->> 'billTo', v_data ->> 'billToId'), '')::uuid, "lifecycle" = coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,prospect,customer,churned}'::text[])[1]), "language" = nullif(btrim(v_data ->> 'language'), ''), "roles" = case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, "customer_terms_id" = (select p."id" from "better_supabase"."payment_terms" p where p."tenant_id" = v_tenant and p."code" = nullif(btrim(v_data ->> 'termsCode'), '')), "archived_at" = nullif(v_data ->> 'archivedAt', '')::timestamptz, "updated_at" = now()
      where x."id" = import_party.subject_id::uuid and x."tenant_id" = v_tenant
      returning x."id", x."updated_at" into v_id, v_updated;
    end if;
    if v_id is null then
      insert into "better_supabase"."companies" ("tenant_id", "name", "legal_name", "vat_id", "registration_id", "phone", "billing_email", "bill_to_id", "lifecycle", "language", "roles", "customer_terms_id", "archived_at")
      values (v_tenant, v_name, coalesce(v_legal, v_name), nullif(btrim(v_data ->> 'vatId'), ''), nullif(btrim(v_data ->> 'registrationId'), ''), better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), nullif(lower(btrim(v_data ->> 'billingEmail')), ''), nullif(coalesce(import_party.item -> 'resolved' ->> 'billTo', v_data ->> 'billToId'), '')::uuid, coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(btrim(v_data ->> 'language'), ''), case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, (select p."id" from "better_supabase"."payment_terms" p where p."tenant_id" = v_tenant and p."code" = nullif(btrim(v_data ->> 'termsCode'), '')), nullif(v_data ->> 'archivedAt', '')::timestamptz)
      returning "id", "updated_at" into v_id, v_updated;
    end if;
  elsif v_kind = 'person' then
    if import_party.subject_id is not null then
      select x."id", x."updated_at", x."name" is not distinct from v_name and x."given_name" is not distinct from nullif(btrim(v_data ->> 'givenName'), '') and x."last_name" is not distinct from nullif(btrim(v_data ->> 'lastName'), '') and x."initials" is not distinct from nullif(btrim(v_data ->> 'initials'), '') and x."infix" is not distinct from nullif(btrim(v_data ->> 'infix'), '') and x."email" is not distinct from nullif(lower(btrim(v_data ->> 'email')), '') and x."phone" is not distinct from better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region') and x."lifecycle" is not distinct from coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]) and x."language" is not distinct from nullif(btrim(v_data ->> 'language'), '') and x."roles" is not distinct from case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end and x."archived_at" is not distinct from nullif(v_data ->> 'archivedAt', '')::timestamptz into v_id, v_updated, v_same
      from "better_supabase"."people" x
      where x."id" = import_party.subject_id::uuid and x."tenant_id" = v_tenant;
      if v_id is not null and v_same then
        return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated, 'warnings', v_warnings);
      end if;
      update "better_supabase"."people" x set "name" = v_name, "given_name" = nullif(btrim(v_data ->> 'givenName'), ''), "last_name" = nullif(btrim(v_data ->> 'lastName'), ''), "initials" = nullif(btrim(v_data ->> 'initials'), ''), "infix" = nullif(btrim(v_data ->> 'infix'), ''), "email" = nullif(lower(btrim(v_data ->> 'email')), ''), "phone" = better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), "lifecycle" = coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), "language" = nullif(btrim(v_data ->> 'language'), ''), "roles" = case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, "archived_at" = nullif(v_data ->> 'archivedAt', '')::timestamptz, "updated_at" = now()
      where x."id" = import_party.subject_id::uuid and x."tenant_id" = v_tenant
      returning x."id", x."updated_at" into v_id, v_updated;
    end if;
    if v_id is null then
      insert into "better_supabase"."people" ("tenant_id", "name", "given_name", "last_name", "initials", "infix", "email", "phone", "lifecycle", "language", "roles", "archived_at")
      values (v_tenant, v_name, nullif(btrim(v_data ->> 'givenName'), ''), nullif(btrim(v_data ->> 'lastName'), ''), nullif(btrim(v_data ->> 'initials'), ''), nullif(btrim(v_data ->> 'infix'), ''), nullif(lower(btrim(v_data ->> 'email')), ''), better_supabase.normalize_phone(v_data ->> 'phone', v_data ->> 'region'), coalesce(nullif(v_data ->> 'lifecycle', ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(btrim(v_data ->> 'language'), ''), case when jsonb_typeof(v_data -> 'roles') = 'array' then (select coalesce(array_agg(r), '{}'::text[]) from jsonb_array_elements_text(v_data -> 'roles') r) else null end, nullif(v_data ->> 'archivedAt', '')::timestamptz)
      returning "id", "updated_at" into v_id, v_updated;
    end if;
  else
    raise exception 'kind is person, company or auto' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated, 'warnings', v_warnings);
end;
$$;
revoke execute on function "better_supabase"."import_party"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_party"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."party_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select x."updated_at" from "better_supabase"."companies" x where x."id"::text = party_updated_at.subject_id),
    (select x."updated_at" from "better_supabase"."people" x where x."id"::text = party_updated_at.subject_id))
$$;
revoke execute on function "better_supabase"."party_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."party_updated_at"(text) to service_role;

create or replace function "better_supabase"."import_party_contact"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_party_contact.item -> 'data';
  v_company uuid := nullif(coalesce(import_party_contact.item -> 'resolved' ->> 'company', v_data ->> 'companyId'), '')::uuid;
  v_person uuid := nullif(coalesce(import_party_contact.item -> 'resolved' ->> 'person', v_data ->> 'personId'), '')::uuid;
  v_primary boolean := coalesce((v_data ->> 'isPrimary')::boolean, false);
begin
  if v_company is null or v_person is null then
    raise exception 'a party contact needs a company and a person' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if exists (
    select 1 from "better_supabase"."company_people" x
    where x."company_id" = v_company and x."person_id" = v_person
      and x."is_primary" is not distinct from v_primary
      and x."role" is not distinct from nullif(btrim(v_data ->> 'role'), '')
  ) then
    return jsonb_build_object('subjectId', v_company::text || ':' || v_person::text, 'updatedAt',
      (select x."created_at" from "better_supabase"."company_people" x where x."company_id" = v_company and x."person_id" = v_person));
  end if;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "is_primary", "role")
  values ((import_party_contact.item ->> 'tenant')::uuid, v_company, v_person, v_primary, nullif(btrim(v_data ->> 'role'), ''))
  on conflict ("company_id", "person_id") do update
    set "is_primary" = excluded."is_primary", "role" = nullif(btrim(v_data ->> 'role'), '');
  return jsonb_build_object('subjectId', v_company::text || ':' || v_person::text, 'updatedAt', now());
end;
$$;
revoke execute on function "better_supabase"."import_party_contact"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_party_contact"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."party_contact_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."created_at" from "better_supabase"."company_people" x
  where x."company_id"::text = split_part(party_contact_updated_at.subject_id, ':', 1)
    and x."person_id"::text = split_part(party_contact_updated_at.subject_id, ':', 2)
$$;
revoke execute on function "better_supabase"."party_contact_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."party_contact_updated_at"(text) to service_role;


create or replace function "better_supabase"."import_contact_method"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_contact_method.item -> 'data';
  v_party uuid := nullif(coalesce(import_contact_method.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_kind text := coalesce(nullif(v_data ->> 'partyKind', ''), 'person');
  v_channel text := nullif(v_data ->> 'channel', '');
  v_address text := nullif(btrim(v_data ->> 'address'), '');
  v_id uuid;
  v_updated timestamptz;
begin
  if v_channel in ('email') then
    v_address := nullif(lower(v_address), '');
  elsif v_channel in ('phone', 'mobile', 'fax', 'whatsapp') then
    v_address := nullif(better_supabase.normalize_phone(v_address, v_data ->> 'region'), '');
  end if;
  if v_party is null or v_kind not in ('person', 'company') or v_channel not in ('email', 'phone', 'mobile', 'fax', 'whatsapp') or v_address is null then
    raise exception 'a contact method needs a party, a channel and an address' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select x."id", x."updated_at" into v_id, v_updated from "better_supabase"."party_channels" x
  where x."tenant_id" = (import_contact_method.item ->> 'tenant')::uuid
    and x."party_id" = v_party and x."channel" = v_channel and x."address" = v_address
    and x."label" is not distinct from nullif(btrim(v_data ->> 'label'), '')
    and x."is_primary" is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, false);
  if v_id is not null then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
  end if;
  insert into "better_supabase"."party_channels" ("tenant_id", "party_id", "party_kind", "channel", "label", "address", "is_primary")
  values ((import_contact_method.item ->> 'tenant')::uuid, v_party, v_kind, v_channel, nullif(btrim(v_data ->> 'label'), ''), v_address, coalesce((v_data ->> 'isPrimary')::boolean, false))
  on conflict ("tenant_id", "party_id", "channel", "address") do update
    set "label" = excluded."label", "is_primary" = excluded."is_primary", "updated_at" = now()
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$$;
revoke execute on function "better_supabase"."import_contact_method"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_contact_method"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."contact_method_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."party_channels" x where x."id"::text = contact_method_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."contact_method_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."contact_method_updated_at"(text) to service_role;


create or replace function "better_supabase"."import_party_location"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_party_location.item -> 'data';
  v_party uuid := nullif(coalesce(import_party_location.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_id uuid;
  v_updated timestamptz;
  v_same boolean;
begin
  if v_party is null then
    raise exception 'a location needs a party' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  if import_party_location.subject_id is not null then
    select x."id", x."updated_at", x."party_id" is not distinct from v_party and x."kind" is not distinct from coalesce(nullif(v_data ->> 'kind', ''), 'other') and x."line1" is not distinct from nullif(btrim(v_data ->> 'line1'), '') and x."line2" is not distinct from nullif(btrim(v_data ->> 'line2'), '') and x."postal_code" is not distinct from nullif(btrim(v_data ->> 'postalCode'), '') and x."city" is not distinct from nullif(btrim(v_data ->> 'city'), '') and x."country" is not distinct from nullif(btrim(v_data ->> 'country'), '') and x."latitude" is not distinct from nullif(v_data ->> 'latitude', '')::double precision and x."longitude" is not distinct from nullif(v_data ->> 'longitude', '')::double precision and x."is_primary" is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, false) into v_id, v_updated, v_same
    from "better_supabase"."party_locations" x
    where x."id" = import_party_location.subject_id::uuid and x."tenant_id" = (import_party_location.item ->> 'tenant')::uuid;
    if v_id is not null and v_same then
      return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
    end if;
    update "better_supabase"."party_locations" x set "party_id" = v_party, "kind" = coalesce(nullif(v_data ->> 'kind', ''), 'other'), "line1" = nullif(btrim(v_data ->> 'line1'), ''), "line2" = nullif(btrim(v_data ->> 'line2'), ''), "postal_code" = nullif(btrim(v_data ->> 'postalCode'), ''), "city" = nullif(btrim(v_data ->> 'city'), ''), "country" = nullif(btrim(v_data ->> 'country'), ''), "latitude" = nullif(v_data ->> 'latitude', '')::double precision, "longitude" = nullif(v_data ->> 'longitude', '')::double precision, "is_primary" = coalesce((v_data ->> 'isPrimary')::boolean, false), "updated_at" = now()
    where x."id" = import_party_location.subject_id::uuid
    returning x."id", x."updated_at" into v_id, v_updated;
  end if;
  if v_id is null then
    insert into "better_supabase"."party_locations" ("tenant_id", "party_id", "kind", "line1", "line2", "postal_code", "city", "country", "latitude", "longitude", "is_primary")
    values ((import_party_location.item ->> 'tenant')::uuid, v_party, coalesce(nullif(v_data ->> 'kind', ''), 'other'), nullif(btrim(v_data ->> 'line1'), ''), nullif(btrim(v_data ->> 'line2'), ''), nullif(btrim(v_data ->> 'postalCode'), ''), nullif(btrim(v_data ->> 'city'), ''), nullif(btrim(v_data ->> 'country'), ''), nullif(v_data ->> 'latitude', '')::double precision, nullif(v_data ->> 'longitude', '')::double precision, coalesce((v_data ->> 'isPrimary')::boolean, false))
    returning "id", "updated_at" into v_id, v_updated;
  end if;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$$;
revoke execute on function "better_supabase"."import_party_location"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_party_location"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."party_location_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."party_locations" x where x."id"::text = party_location_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."party_location_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."party_location_updated_at"(text) to service_role;


create or replace function "better_supabase"."import_party_bank_account"(run uuid, item jsonb, subject_id text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_data jsonb := import_party_bank_account.item -> 'data';
  v_party uuid := nullif(coalesce(import_party_bank_account.item -> 'resolved' ->> 'party', v_data ->> 'partyId'), '')::uuid;
  v_iban text := upper(regexp_replace(coalesce(v_data ->> 'iban', ''), '\s', '', 'g'));
  v_id uuid;
  v_updated timestamptz;
begin
  if v_party is null or not better_supabase.validate_iban(v_iban) then
    raise exception 'a bank account needs a party and a valid IBAN' using errcode = '22023', hint = 'IMPORT_ITEM_INVALID';
  end if;
  select x."id", x."updated_at" into v_id, v_updated from "better_supabase"."party_bank_accounts" x
  where x."tenant_id" = (import_party_bank_account.item ->> 'tenant')::uuid and x."iban" = v_iban
    and x."bic" is not distinct from nullif(upper(btrim(v_data ->> 'bic')), '')
    and x."holder" is not distinct from nullif(btrim(v_data ->> 'holder'), '')
    and x."is_primary" is not distinct from coalesce((v_data ->> 'isPrimary')::boolean, x."is_primary");
  if v_id is not null then
    return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
  end if;
  insert into "better_supabase"."party_bank_accounts" ("tenant_id", "party_id", "iban", "bic", "holder", "is_primary")
  values ((import_party_bank_account.item ->> 'tenant')::uuid, v_party, v_iban,
    nullif(upper(btrim(v_data ->> 'bic')), ''), nullif(btrim(v_data ->> 'holder'), ''), coalesce((v_data ->> 'isPrimary')::boolean, false))
  on conflict ("tenant_id", "iban") do update
    set "bic" = excluded."bic", "holder" = excluded."holder",
      "is_primary" = coalesce((v_data ->> 'isPrimary')::boolean, "better_supabase"."party_bank_accounts"."is_primary"),
      "updated_at" = now()
  returning "id", "updated_at" into v_id, v_updated;
  return jsonb_build_object('subjectId', v_id, 'updatedAt', v_updated);
end;
$$;
revoke execute on function "better_supabase"."import_party_bank_account"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "better_supabase"."import_party_bank_account"(uuid, jsonb, text) to service_role;

create or replace function "better_supabase"."party_bank_account_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$
  select x."updated_at" from "better_supabase"."party_bank_accounts" x where x."id"::text = party_bank_account_updated_at.subject_id
$$;
revoke execute on function "better_supabase"."party_bank_account_updated_at"(text) from public, anon, authenticated;
grant execute on function "better_supabase"."party_bank_account_updated_at"(text) to service_role;

create or replace function "better_supabase"."party_bank_account_id"(tenant uuid, item jsonb)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select x."id"::text from "better_supabase"."party_bank_accounts" x
  where x."tenant_id" = party_bank_account_id.tenant
    and x."iban" = upper(regexp_replace(coalesce(party_bank_account_id.item -> 'data' ->> 'iban', ''), '\s', '', 'g'))
$$;
revoke execute on function "better_supabase"."party_bank_account_id"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."party_bank_account_id"(uuid, jsonb) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."companies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."companies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."companies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."companies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."people" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."people" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."people" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."people" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."company_people" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."company_people" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."company_people" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."company_people" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."payment_terms" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."payment_terms" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."payment_terms" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."payment_terms" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."document_delivery_preferences" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."document_delivery_preferences" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."document_delivery_preferences" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."document_delivery_preferences" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."person_identities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."person_identities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."person_identities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."person_identities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."party_locations" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."party_locations" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."party_locations" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."party_locations" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."party_bank_accounts" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."party_bank_accounts" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."party_bank_accounts" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."party_bank_accounts" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."party_channels" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."party_channels" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."party_channels" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."party_channels" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create trigger "bsb_search_company_index"
  after insert or delete or update of "id", "tenant_id", "name", "domain" on "better_supabase"."companies"
  for each row execute function "better_supabase"."search_index_row"('company', 'id');
create trigger "bsb_search_person_index"
  after insert or delete or update of "id", "tenant_id", "name", "email", "title" on "better_supabase"."people"
  for each row execute function "better_supabase"."search_index_row"('person', 'id');

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.companies deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"company","event_prefix":"company"}');
create constraint trigger bsb_audit after insert or update or delete on better_supabase.people deferrable initially deferred for each row when (better_supabase.import_run() is null or current_setting('better_supabase.import_audit', true) is distinct from 'summary') execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"person","event_prefix":"person"}');

-- blocks.contacts.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

-- Helpers for the module's policies and triggers have no entry point.


create or replace function "api"."save_company"(tenant uuid, company uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_company"($1, $2, $3) $$;
revoke execute on function "api"."save_company"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_company"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."save_person"(tenant uuid, person uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_person"($1, $2, $3) $$;
revoke execute on function "api"."save_person"(uuid, uuid, jsonb) from public, anon;
grant execute on function "api"."save_person"(uuid, uuid, jsonb) to authenticated, service_role;

create or replace function "api"."archive_company"(id uuid, archived boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_company"($1, $2) $$;
revoke execute on function "api"."archive_company"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_company"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."archive_person"(id uuid, archived boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."archive_person"($1, $2) $$;
revoke execute on function "api"."archive_person"(uuid, boolean) from public, anon;
grant execute on function "api"."archive_person"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."set_company_person"(company uuid, person uuid, role text, is_primary boolean)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_company_person"($1, $2, $3, $4) $$;
revoke execute on function "api"."set_company_person"(uuid, uuid, text, boolean) from public, anon;
grant execute on function "api"."set_company_person"(uuid, uuid, text, boolean) to authenticated, service_role;

create or replace function "api"."remove_company_person"(company uuid, person uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_company_person"($1, $2) $$;
revoke execute on function "api"."remove_company_person"(uuid, uuid) from public, anon;
grant execute on function "api"."remove_company_person"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."merge_companies"(keep uuid, drop uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."merge_companies"($1, $2) $$;
revoke execute on function "api"."merge_companies"(uuid, uuid) from public, anon;
grant execute on function "api"."merge_companies"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."merge_people"(keep uuid, drop uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."merge_people"($1, $2) $$;
revoke execute on function "api"."merge_people"(uuid, uuid) from public, anon;
grant execute on function "api"."merge_people"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."list_companies"(tenant uuid, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer, role text default null, supplier_status text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_companies"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) from public, anon;
grant execute on function "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) to authenticated, service_role;

create or replace function "api"."list_people"(tenant uuid, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer, role text default null, supplier_status text default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_people"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) from public, anon;
grant execute on function "api"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) to authenticated, service_role;

create or replace function "api"."get_company"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_company"($1) $$;
revoke execute on function "api"."get_company"(uuid) from public, anon;
grant execute on function "api"."get_company"(uuid) to authenticated, service_role;

create or replace function "api"."get_person"(id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."get_person"($1) $$;
revoke execute on function "api"."get_person"(uuid) from public, anon;
grant execute on function "api"."get_person"(uuid) to authenticated, service_role;

create or replace function "api"."company_people_of"(company uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."company_people_of"($1) $$;
revoke execute on function "api"."company_people_of"(uuid) from public, anon;
grant execute on function "api"."company_people_of"(uuid) to authenticated, service_role;

create or replace function "api"."save_payment_term"(tenant uuid, attrs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_payment_term"($1, $2) $$;
revoke execute on function "api"."save_payment_term"(uuid, jsonb) from public, anon;
grant execute on function "api"."save_payment_term"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_payment_terms"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_payment_terms"($1) $$;
revoke execute on function "api"."list_payment_terms"(uuid) from public, anon;
grant execute on function "api"."list_payment_terms"(uuid) to authenticated, service_role;

create or replace function "api"."delete_payment_term"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_payment_term"($1) $$;
revoke execute on function "api"."delete_payment_term"(uuid) from public, anon;
grant execute on function "api"."delete_payment_term"(uuid) to authenticated, service_role;

create or replace function "api"."set_document_delivery_preferences"(party uuid, prefs jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_document_delivery_preferences"($1, $2) $$;
revoke execute on function "api"."set_document_delivery_preferences"(uuid, jsonb) from public, anon;
grant execute on function "api"."set_document_delivery_preferences"(uuid, jsonb) to authenticated, service_role;

create or replace function "api"."list_document_delivery_preferences"(party uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_document_delivery_preferences"($1) $$;
revoke execute on function "api"."list_document_delivery_preferences"(uuid) from public, anon;
grant execute on function "api"."list_document_delivery_preferences"(uuid) to authenticated, service_role;

create or replace function "api"."import_payment_term"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_payment_term"($1, $2, $3) $$;
revoke execute on function "api"."import_payment_term"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_payment_term"(uuid, jsonb, text) to service_role;

create or replace function "api"."payment_term_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."payment_term_updated_at"($1) $$;
revoke execute on function "api"."payment_term_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."payment_term_updated_at"(text) to service_role;

create or replace function "api"."import_document_delivery_preference"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_document_delivery_preference"($1, $2, $3) $$;
revoke execute on function "api"."import_document_delivery_preference"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_document_delivery_preference"(uuid, jsonb, text) to service_role;

create or replace function "api"."document_delivery_preference_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."document_delivery_preference_updated_at"($1) $$;
revoke execute on function "api"."document_delivery_preference_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."document_delivery_preference_updated_at"(text) to service_role;

create or replace function "api"."set_party_roles"(party uuid, roles text[])
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_party_roles"($1, $2) $$;
revoke execute on function "api"."set_party_roles"(uuid, text[]) from public, anon;
grant execute on function "api"."set_party_roles"(uuid, text[]) to authenticated, service_role;

create or replace function "api"."set_supplier_status"(party uuid, status text, reason text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."set_supplier_status"($1, $2, $3) $$;
revoke execute on function "api"."set_supplier_status"(uuid, text, text) from public, anon;
grant execute on function "api"."set_supplier_status"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."supplier_status_from_qualifications"(party uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."supplier_status_from_qualifications"($1) $$;
revoke execute on function "api"."supplier_status_from_qualifications"(uuid) from public, anon;
grant execute on function "api"."supplier_status_from_qualifications"(uuid) to authenticated, service_role;

create or replace function "api"."list_person_identities"(person uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_person_identities"($1) $$;
revoke execute on function "api"."list_person_identities"(uuid) from public, anon;
grant execute on function "api"."list_person_identities"(uuid) to authenticated, service_role;

create or replace function "api"."add_person_identity"(person uuid, channel text, address text, verified boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."add_person_identity"($1, $2, $3, $4) $$;
revoke execute on function "api"."add_person_identity"(uuid, text, text, boolean) from public, anon;
grant execute on function "api"."add_person_identity"(uuid, text, text, boolean) to authenticated, service_role;

create or replace function "api"."remove_person_identity"(identity uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."remove_person_identity"($1) $$;
revoke execute on function "api"."remove_person_identity"(uuid) from public, anon;
grant execute on function "api"."remove_person_identity"(uuid) to authenticated, service_role;

create or replace function "api"."find_person_by_identity"(tenant uuid, channel text, address text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."find_person_by_identity"($1, $2, $3) $$;
revoke execute on function "api"."find_person_by_identity"(uuid, text, text) from public, anon;
grant execute on function "api"."find_person_by_identity"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."list_representatives"(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_representatives"($1, $2) $$;
revoke execute on function "api"."list_representatives"(text, text) from public, anon;
grant execute on function "api"."list_representatives"(text, text) to authenticated, service_role;

create or replace function "api"."represented_by_me"(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."represented_by_me"($1) $$;
revoke execute on function "api"."represented_by_me"(uuid) from public, anon;
grant execute on function "api"."represented_by_me"(uuid) to authenticated, service_role;

create or replace function "api"."import_party"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_party"($1, $2, $3) $$;
revoke execute on function "api"."import_party"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_party"(uuid, jsonb, text) to service_role;

create or replace function "api"."party_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."party_updated_at"($1) $$;
revoke execute on function "api"."party_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."party_updated_at"(text) to service_role;

create or replace function "api"."import_party_contact"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_party_contact"($1, $2, $3) $$;
revoke execute on function "api"."import_party_contact"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_party_contact"(uuid, jsonb, text) to service_role;

create or replace function "api"."party_contact_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."party_contact_updated_at"($1) $$;
revoke execute on function "api"."party_contact_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."party_contact_updated_at"(text) to service_role;

create or replace function "api"."import_contact_method"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_contact_method"($1, $2, $3) $$;
revoke execute on function "api"."import_contact_method"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_contact_method"(uuid, jsonb, text) to service_role;

create or replace function "api"."contact_method_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."contact_method_updated_at"($1) $$;
revoke execute on function "api"."contact_method_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."contact_method_updated_at"(text) to service_role;

create or replace function "api"."import_party_location"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_party_location"($1, $2, $3) $$;
revoke execute on function "api"."import_party_location"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_party_location"(uuid, jsonb, text) to service_role;

create or replace function "api"."party_location_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."party_location_updated_at"($1) $$;
revoke execute on function "api"."party_location_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."party_location_updated_at"(text) to service_role;

create or replace function "api"."import_party_bank_account"(run uuid, item jsonb, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."import_party_bank_account"($1, $2, $3) $$;
revoke execute on function "api"."import_party_bank_account"(uuid, jsonb, text) from public, anon, authenticated;
grant execute on function "api"."import_party_bank_account"(uuid, jsonb, text) to service_role;

create or replace function "api"."party_bank_account_updated_at"(subject_id text)
returns timestamptz
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."party_bank_account_updated_at"($1) $$;
revoke execute on function "api"."party_bank_account_updated_at"(text) from public, anon, authenticated;
grant execute on function "api"."party_bank_account_updated_at"(text) to service_role;

create or replace function "api"."party_bank_account_id"(tenant uuid, item jsonb)
returns text
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."party_bank_account_id"($1, $2) $$;
revoke execute on function "api"."party_bank_account_id"(uuid, jsonb) from public, anon, authenticated;
grant execute on function "api"."party_bank_account_id"(uuid, jsonb) to service_role;
