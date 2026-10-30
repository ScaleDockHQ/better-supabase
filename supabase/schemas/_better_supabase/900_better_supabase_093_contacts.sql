-- better-supabase module: contacts
-- @bsb-block contacts@2 managed
-- @bsb-hash sha256:f2be363a6d3cda0d1e08f28a0fedf73262435420adf8e7afd93bf31085c59824
-- Companies and people an organization works with: lifecycle stages, owners, party roles (customer, supplier and so on), payment terms, credit limits and a supplier status, who works where with a role and a primary contact, each person's addresses on channels (the inbox's contacts), domain and email dedupe, merges and keyset-paged search.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Moves every installed module's rows from record drop to record keep of the
-- subject table subject_table (schema.table): comments, attachments, tags and
-- the rest. Each module marks its handler with a comment, so this finds them
-- without naming them.
create or replace function better_supabase.merge_subject_refs(subject_table text, keep text, drop text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fn regproc;
begin
  for v_fn in
    select p.oid::regproc
    from pg_catalog.pg_proc p
    join pg_catalog.pg_description d on d.objoid = p.oid and d.classoid = 'pg_catalog.pg_proc'::regclass and d.objsubid = 0
    where d.description = 'better-supabase:subject-merge'
      -- Only the owner's functions, so a marked function in a schema another
      -- role can write to never runs with this function's rights.
      and p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)
    order by p.oid::regproc::text
  loop
    execute format('select %s($1, $2, $3)', v_fn) using subject_table, keep, drop;
  end loop;
end;
$$;
revoke execute on function better_supabase.merge_subject_refs(text, text, text) from public, anon, authenticated;

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
    drop policy if exists bsb_tenant_scope on "better_supabase"."companies";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."companies";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."companies";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."companies";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."companies";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."people";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."people";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."people";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."people";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."people";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."company_people";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."company_people";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."company_people";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."company_people";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."company_people";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."person_identities";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."person_identities";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."person_identities";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."person_identities";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."person_identities";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Companies and people an organization works with, and who works where.

create table if not exists "better_supabase"."companies" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 300),
  "domain" text check ("domain" = lower("domain") and "domain" ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  "website" text,
  "vat_id" text,
  "lifecycle" text not null,
  "owner_user_id" uuid,
  "address" jsonb check ("address" is null or jsonb_typeof("address") = 'object'),
  "roles" text[] not null default '{}'::text[],
  "payment_terms_days" integer check ("payment_terms_days" >= 0 and "payment_terms_days" <= 3650),
  "credit_currency" text check ("credit_currency" ~ '^[A-Z]{3}$'),
  "credit_limit" bigint check ("credit_limit" >= 0 and num_nulls("credit_limit", "credit_currency") <> 1),
  "supplier_status" text check ("supplier_status" in ('approved', 'conditional', 'blocked')),
  "merged_into" uuid references "better_supabase"."companies" ("id"),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists companies_tenant_name_idx on "better_supabase"."companies" ("tenant_id", lower("name"), "id");
create unique index if not exists companies_domain_idx on "better_supabase"."companies" ("tenant_id", "domain")
  where "domain" is not null and "archived_at" is null;
create index if not exists companies_owner_idx on "better_supabase"."companies" ("owner_user_id");
create index if not exists companies_merged_into_idx on "better_supabase"."companies" ("merged_into");
create index if not exists companies_roles_idx on "better_supabase"."companies" using gin ("roles");
create index if not exists companies_supplier_status_idx on "better_supabase"."companies" ("tenant_id", "supplier_status") where "supplier_status" is not null;
alter table "better_supabase"."companies" enable row level security;
revoke all on "better_supabase"."companies" from public, anon, authenticated;
grant select on "better_supabase"."companies" to authenticated;
grant all on "better_supabase"."companies" to service_role;
drop policy if exists companies_read on "better_supabase"."companies";
create policy companies_read on "better_supabase"."companies"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table if not exists "better_supabase"."people" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "name" text not null check (length("name") between 1 and 300),
  "email" text check ("email" = lower("email") and "email" ~ '^[^@[:space:]]+@[^@[:space:]]+$'),
  "phone" text,
  "title" text,
  "lifecycle" text not null,
  "owner_user_id" uuid,
  "user_id" uuid,
  "avatar_url" text,
  "metadata" jsonb not null default '{}'::jsonb check (jsonb_typeof("metadata") = 'object'),
  "roles" text[] not null default '{}'::text[],
  "payment_terms_days" integer check ("payment_terms_days" >= 0 and "payment_terms_days" <= 3650),
  "credit_currency" text check ("credit_currency" ~ '^[A-Z]{3}$'),
  "credit_limit" bigint check ("credit_limit" >= 0 and num_nulls("credit_limit", "credit_currency") <> 1),
  "supplier_status" text check ("supplier_status" in ('approved', 'conditional', 'blocked')),
  "merged_into" uuid references "better_supabase"."people" ("id"),
  "archived_at" timestamptz,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists people_tenant_name_idx on "better_supabase"."people" ("tenant_id", lower("name"), "id");
create unique index if not exists people_email_idx on "better_supabase"."people" ("tenant_id", "email")
  where "email" is not null and "archived_at" is null;
create index if not exists people_owner_idx on "better_supabase"."people" ("owner_user_id");
create index if not exists people_user_idx on "better_supabase"."people" ("user_id");
create index if not exists people_merged_into_idx on "better_supabase"."people" ("merged_into");
create index if not exists people_roles_idx on "better_supabase"."people" using gin ("roles");
create index if not exists people_supplier_status_idx on "better_supabase"."people" ("tenant_id", "supplier_status") where "supplier_status" is not null;
alter table "better_supabase"."people" enable row level security;
revoke all on "better_supabase"."people" from public, anon, authenticated;
grant select on "better_supabase"."people" to authenticated;
grant all on "better_supabase"."people" to service_role;
drop policy if exists people_read on "better_supabase"."people";
create policy people_read on "better_supabase"."people"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table if not exists "better_supabase"."company_people" (
  "tenant_id" uuid not null,
  "company_id" uuid not null references "better_supabase"."companies" ("id") on delete cascade,
  "person_id" uuid not null references "better_supabase"."people" ("id") on delete cascade,
  "role" text,
  "is_primary" boolean not null default false,
  "created_at" timestamptz not null default now(),
  primary key ("company_id", "person_id")
);
create index if not exists company_people_person_idx on "better_supabase"."company_people" ("person_id");
create unique index if not exists company_people_primary_idx on "better_supabase"."company_people" ("company_id") where "is_primary";
alter table "better_supabase"."company_people" enable row level security;
revoke all on "better_supabase"."company_people" from public, anon, authenticated;
grant select on "better_supabase"."company_people" to authenticated;
grant all on "better_supabase"."company_people" to service_role;
drop policy if exists company_people_read on "better_supabase"."company_people";
create policy company_people_read on "better_supabase"."company_people"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')));

create table if not exists "better_supabase"."person_identities" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "person_id" uuid not null references "better_supabase"."people" ("id") on delete cascade,
  "channel" text not null check (length("channel") between 1 and 50),
  "address" text not null check (length("address") between 1 and 500),
  "verified_at" timestamptz,
  "created_at" timestamptz not null default now(),
  unique ("tenant_id", "channel", "address")
);
create index if not exists person_identities_person_idx on "better_supabase"."person_identities" ("person_id");
alter table "better_supabase"."person_identities" enable row level security;
revoke all on "better_supabase"."person_identities" from public, anon, authenticated;
grant select on "better_supabase"."person_identities" to authenticated;
grant all on "better_supabase"."person_identities" to service_role;
drop policy if exists person_identities_read on "better_supabase"."person_identities";
create policy person_identities_read on "better_supabase"."person_identities"
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
  if save_company.attrs ->> 'paymentTermsDays' is not null and (case when save_company.attrs ->> 'paymentTermsDays' ~ '^[0-9]{1,4}$' then (save_company.attrs ->> 'paymentTermsDays')::integer > 3650 else true end) then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditLimit' is not null and save_company.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ->> 'creditCurrency' is not null and upper(trim(save_company.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' <> save_company.attrs ? 'creditCurrency' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_company.attrs ? 'creditLimit' and (save_company.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_company.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
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
      insert into "better_supabase"."companies" ("tenant_id", "name", "domain", "website", "vat_id", "lifecycle", "owner_user_id", "payment_terms_days", "credit_limit", "credit_currency", "address", "created_by")
      values (save_company.tenant, nullif(trim(save_company.attrs ->> 'name'), ''), lower(nullif(trim(save_company.attrs ->> 'domain'), '')), nullif(trim(save_company.attrs ->> 'website'), ''), nullif(trim(save_company.attrs ->> 'vatId'), ''), coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(save_company.attrs ->> 'ownerId', '')::uuid, nullif(trim(save_company.attrs ->> 'paymentTermsDays'), '')::integer, nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')), save_company.attrs -> 'address', auth.uid())
      returning "id", "owner_user_id" into v_id, v_owner;
    else
      select x."owner_user_id" into v_previous_owner from "better_supabase"."companies" x
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant;
      update "better_supabase"."companies" x set "name" = case when save_company.attrs ? 'name' then coalesce(nullif(trim(save_company.attrs ->> 'name'), ''), x."name") else x."name" end,
        "domain" = case when save_company.attrs ? 'domain' then lower(nullif(trim(save_company.attrs ->> 'domain'), '')) else x."domain" end,
        "website" = case when save_company.attrs ? 'website' then nullif(trim(save_company.attrs ->> 'website'), '') else x."website" end,
        "vat_id" = case when save_company.attrs ? 'vatId' then nullif(trim(save_company.attrs ->> 'vatId'), '') else x."vat_id" end,
        "lifecycle" = case when save_company.attrs ? 'lifecycle' then coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_user_id" = case when save_company.attrs ? 'ownerId' then nullif(save_company.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
        "payment_terms_days" = case when save_company.attrs ? 'paymentTermsDays' then nullif(trim(save_company.attrs ->> 'paymentTermsDays'), '')::integer else x."payment_terms_days" end,
        "credit_limit" = case when save_company.attrs ? 'creditLimit' then nullif(trim(save_company.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_company.attrs ? 'creditCurrency' then upper(nullif(trim(save_company.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "address" = case when save_company.attrs ? 'address' then save_company.attrs -> 'address' else x."address" end,
        "updated_at" = now()
      where x."id" = save_company.company and x."tenant_id" = save_company.tenant and x."merged_into" is null
      returning x."owner_user_id" into v_owner;
      if not found then
        raise exception 'company not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another company has this domain' using errcode = '23505', hint = 'PARTY_DOMAIN_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status") into v_row from "better_supabase"."companies" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('company.created', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('company.updated', jsonb_build_object('organizationId', save_company.tenant, 'companyId', v_id, 'name', v_row ->> 'name'), 'companies/' || v_id::text, (save_company.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
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
  if save_person.attrs ->> 'paymentTermsDays' is not null and (case when save_person.attrs ->> 'paymentTermsDays' ~ '^[0-9]{1,4}$' then (save_person.attrs ->> 'paymentTermsDays')::integer > 3650 else true end) then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditLimit' is not null and save_person.attrs ->> 'creditLimit' !~ '^[0-9]{1,18}$' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ->> 'creditCurrency' is not null and upper(trim(save_person.attrs ->> 'creditCurrency')) !~ '^[A-Z]{3}$' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' <> save_person.attrs ? 'creditCurrency' then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
  end if;
  if save_person.attrs ? 'creditLimit' and (save_person.attrs ->> 'creditLimit' is null) <> (nullif(trim(save_person.attrs ->> 'creditCurrency'), '') is null) then
    raise exception 'payment terms are 0 to 3650 days; a credit limit is minor units with a currency' using errcode = '22023', hint = 'PARTY_TERMS_INVALID';
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
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "title", "lifecycle", "owner_user_id", "user_id", "payment_terms_days", "credit_limit", "credit_currency", "created_by")
      values (save_person.tenant, nullif(trim(save_person.attrs ->> 'name'), ''), lower(nullif(trim(save_person.attrs ->> 'email'), '')), nullif(trim(save_person.attrs ->> 'phone'), ''), nullif(trim(save_person.attrs ->> 'title'), ''), coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(save_person.attrs ->> 'ownerId', '')::uuid, nullif(save_person.attrs ->> 'userId', '')::uuid, nullif(trim(save_person.attrs ->> 'paymentTermsDays'), '')::integer, nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint, upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')), auth.uid())
      returning "id", "owner_user_id" into v_id, v_owner;
    else
      select x."owner_user_id" into v_previous_owner from "better_supabase"."people" x
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant;
      update "better_supabase"."people" x set "name" = case when save_person.attrs ? 'name' then coalesce(nullif(trim(save_person.attrs ->> 'name'), ''), x."name") else x."name" end,
        "email" = case when save_person.attrs ? 'email' then lower(nullif(trim(save_person.attrs ->> 'email'), '')) else x."email" end,
        "phone" = case when save_person.attrs ? 'phone' then nullif(trim(save_person.attrs ->> 'phone'), '') else x."phone" end,
        "title" = case when save_person.attrs ? 'title' then nullif(trim(save_person.attrs ->> 'title'), '') else x."title" end,
        "lifecycle" = case when save_person.attrs ? 'lifecycle' then coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), x."lifecycle") else x."lifecycle" end,
        "owner_user_id" = case when save_person.attrs ? 'ownerId' then nullif(save_person.attrs ->> 'ownerId', '')::uuid else x."owner_user_id" end,
        "user_id" = case when save_person.attrs ? 'userId' then nullif(save_person.attrs ->> 'userId', '')::uuid else x."user_id" end,
        "payment_terms_days" = case when save_person.attrs ? 'paymentTermsDays' then nullif(trim(save_person.attrs ->> 'paymentTermsDays'), '')::integer else x."payment_terms_days" end,
        "credit_limit" = case when save_person.attrs ? 'creditLimit' then nullif(trim(save_person.attrs ->> 'creditLimit'), '')::bigint else x."credit_limit" end,
        "credit_currency" = case when save_person.attrs ? 'creditCurrency' then upper(nullif(trim(save_person.attrs ->> 'creditCurrency'), '')) else x."credit_currency" end,
        "updated_at" = now()
      where x."id" = save_person.person and x."tenant_id" = save_person.tenant and x."merged_into" is null
      returning x."owner_user_id" into v_owner;
      if not found then
        raise exception 'person not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'another person has this email' using errcode = '23505', hint = 'PARTY_EMAIL_TAKEN';
  end;
  select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status") into v_row from "better_supabase"."people" x where x."id" = v_id;
  if v_created then
    perform "better_supabase".emit_event('person.created', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  else
    perform "better_supabase".emit_event('person.updated', jsonb_build_object('organizationId', save_person.tenant, 'personId', v_id, 'name', v_row ->> 'name'), 'persons/' || v_id::text, (save_person.tenant::text)::text, null, 'better-supabase/contacts');
  end if;
  if v_owner is not null and v_owner is distinct from v_previous_owner then
    insert into "better_supabase"."notification_subscriptions" ("organization_id", "user_id", "subject_type", "subject_id", "level")
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
  update "better_supabase"."companies" x set "domain" = coalesce(x."domain", v_drop."domain"), "website" = coalesce(x."website", v_drop."website"), "vat_id" = coalesce(x."vat_id", v_drop."vat_id"), "owner_user_id" = coalesce(x."owner_user_id", v_drop."owner_user_id"), "payment_terms_days" = coalesce(x."payment_terms_days", v_drop."payment_terms_days"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
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
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status") from "better_supabase"."companies" x where x."id" = merge_companies.keep);
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
  update "better_supabase"."people" x set "email" = coalesce(x."email", v_drop."email"), "phone" = coalesce(x."phone", v_drop."phone"), "title" = coalesce(x."title", v_drop."title"), "owner_user_id" = coalesce(x."owner_user_id", v_drop."owner_user_id"), "user_id" = coalesce(x."user_id", v_drop."user_id"), "payment_terms_days" = coalesce(x."payment_terms_days", v_drop."payment_terms_days"), "credit_limit" = coalesce(x."credit_limit", v_drop."credit_limit"), "credit_currency" = coalesce(x."credit_currency", v_drop."credit_currency"), "supplier_status" = coalesce(x."supplier_status", v_drop."supplier_status"), "updated_at" = now()
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
  return (select to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status") from "better_supabase"."people" x where x."id" = merge_people.keep);
end;
$$;
revoke execute on function "better_supabase"."merge_people"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_people"(uuid, uuid) to authenticated, service_role;

-- A page of the organization's active companies, by name. search matches
-- the name and domain; after_name and after_id continue after the
-- last row of the previous page. role keeps the ones with that role, and
-- supplier_status the suppliers in that status.
drop function if exists "better_supabase"."list_companies"(uuid, text, text, uuid, text, uuid, integer);
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
    select jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'payment_terms_days', p."payment_terms_days", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'supplier_status', p."supplier_status") order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."companies" x
      where x."tenant_id" = list_companies.tenant
        and x."archived_at" is null
        and (list_companies.search is null or x."name" ilike v_like or x."domain" ilike v_like)
        and (list_companies.lifecycle is null or x."lifecycle" = list_companies.lifecycle)
        and (list_companies.owner is null or x."owner_user_id" = list_companies.owner)
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
drop function if exists "better_supabase"."list_people"(uuid, text, text, uuid, text, uuid, integer);
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
    select jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'payment_terms_days', p."payment_terms_days", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'supplier_status', p."supplier_status") order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."people" x
      where x."tenant_id" = list_people.tenant
        and x."archived_at" is null
        and (list_people.search is null or x."name" ilike v_like or x."email" ilike v_like)
        and (list_people.lifecycle is null or x."lifecycle" = list_people.lifecycle)
        and (list_people.owner is null or x."owner_user_id" = list_people.owner)
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

-- The people of a company with their role, primary contact first.
create or replace function "better_supabase"."company_people_of"(company uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('roles', p."roles", 'payment_terms_days', p."payment_terms_days", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'supplier_status', p."supplier_status") || jsonb_build_object('role', l."role", 'is_primary', l."is_primary")
    order by l."is_primary" desc, lower(p."name"), p."id"), '[]'::jsonb)
  from "better_supabase"."company_people" l join "better_supabase"."people" p on p."id" = l."person_id"
  where l."company_id" = company_people_of.company and p."archived_at" is null
$$;
revoke execute on function "better_supabase"."company_people_of"(uuid) from public, anon;
grant execute on function "better_supabase"."company_people_of"(uuid) to authenticated, service_role;
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
    when 'company' then (select jsonb_build_object('type', 'company', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status")) from "better_supabase"."companies" x where x."id" = set_party_roles.party)
    when 'person' then (select jsonb_build_object('type', 'person', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status")) from "better_supabase"."people" x where x."id" = set_party_roles.party)
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
    when 'company' then (select jsonb_build_object('type', 'company', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status")) from "better_supabase"."companies" x where x."id" = set_supplier_status.party)
    when 'person' then (select jsonb_build_object('type', 'person', 'party', to_jsonb(x) || jsonb_build_object('roles', x."roles", 'payment_terms_days', x."payment_terms_days", 'credit_currency', x."credit_currency", 'credit_limit', x."credit_limit"::text, 'supplier_status', x."supplier_status")) from "better_supabase"."people" x where x."id" = set_supplier_status.party)
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
  select to_jsonb(p) || jsonb_build_object('roles', p."roles", 'payment_terms_days', p."payment_terms_days", 'credit_currency', p."credit_currency", 'credit_limit', p."credit_limit"::text, 'supplier_status', p."supplier_status") from "better_supabase"."person_identities" i
  join "better_supabase"."people" p on p."id" = i."person_id"
  where i."tenant_id" = find_person_by_identity.tenant
    and i."channel" = trim(find_person_by_identity.channel)
    and i."address" = trim(find_person_by_identity.address)
$$;
revoke execute on function "better_supabase"."find_person_by_identity"(uuid, text, text) from public, anon;
grant execute on function "better_supabase"."find_person_by_identity"(uuid, text, text) to authenticated, service_role;

-- A conversation's contact and an identity link's contact are people.
alter table "better_supabase"."inbox_conversations" drop constraint if exists "inbox_conversations_contact_id_fkey";
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
drop policy if exists bsb_tenant_scope on "better_supabase"."companies";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."companies";
create policy bsb_tenant_scope_select on "better_supabase"."companies" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."companies";
create policy bsb_tenant_scope_insert on "better_supabase"."companies" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."companies";
create policy bsb_tenant_scope_update on "better_supabase"."companies" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."companies";
create policy bsb_tenant_scope_delete on "better_supabase"."companies" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."people";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."people";
create policy bsb_tenant_scope_select on "better_supabase"."people" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."people";
create policy bsb_tenant_scope_insert on "better_supabase"."people" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."people";
create policy bsb_tenant_scope_update on "better_supabase"."people" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."people";
create policy bsb_tenant_scope_delete on "better_supabase"."people" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."company_people";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."company_people";
create policy bsb_tenant_scope_select on "better_supabase"."company_people" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."company_people";
create policy bsb_tenant_scope_insert on "better_supabase"."company_people" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."company_people";
create policy bsb_tenant_scope_update on "better_supabase"."company_people" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."company_people";
create policy bsb_tenant_scope_delete on "better_supabase"."company_people" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."person_identities";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."person_identities";
create policy bsb_tenant_scope_select on "better_supabase"."person_identities" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('contacts.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."person_identities";
create policy bsb_tenant_scope_insert on "better_supabase"."person_identities" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."person_identities";
create policy bsb_tenant_scope_update on "better_supabase"."person_identities" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."person_identities";
create policy bsb_tenant_scope_delete on "better_supabase"."person_identities" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

drop trigger if exists "bsb_search_company_index" on "better_supabase"."companies";
create trigger "bsb_search_company_index"
  after insert or delete or update of "id", "tenant_id", "name", "domain" on "better_supabase"."companies"
  for each row execute function "better_supabase"."search_index_row"('company', 'id');

drop trigger if exists "bsb_search_person_index" on "better_supabase"."people";
create trigger "bsb_search_person_index"
  after insert or delete or update of "id", "tenant_id", "name", "email", "title" on "better_supabase"."people"
  for each row execute function "better_supabase"."search_index_row"('person', 'id');

-- blocks.contacts.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

drop function if exists "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer);
drop function if exists "api"."list_people"(uuid, text, text, uuid, text, uuid, integer);

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
security invoker
set search_path = ''
as $$ select "better_supabase"."list_companies"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) from public, anon;
grant execute on function "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer, text, text) to authenticated, service_role;

create or replace function "api"."list_people"(tenant uuid, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer, role text default null, supplier_status text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_people"($1, $2, $3, $4, $5, $6, $7, $8, $9) $$;
revoke execute on function "api"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) from public, anon;
grant execute on function "api"."list_people"(uuid, text, text, uuid, text, uuid, integer, text, text) to authenticated, service_role;

create or replace function "api"."company_people_of"(company uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."company_people_of"($1) $$;
revoke execute on function "api"."company_people_of"(uuid) from public, anon;
grant execute on function "api"."company_people_of"(uuid) to authenticated, service_role;

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
security invoker
set search_path = ''
as $$ select "better_supabase"."supplier_status_from_qualifications"($1) $$;
revoke execute on function "api"."supplier_status_from_qualifications"(uuid) from public, anon;
grant execute on function "api"."supplier_status_from_qualifications"(uuid) to authenticated, service_role;

create or replace function "api"."list_person_identities"(person uuid)
returns jsonb
language sql
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
security invoker
set search_path = ''
as $$ select "better_supabase"."find_person_by_identity"($1, $2, $3) $$;
revoke execute on function "api"."find_person_by_identity"(uuid, text, text) from public, anon;
grant execute on function "api"."find_person_by_identity"(uuid, text, text) to authenticated, service_role;

create or replace function "api"."list_representatives"(subject_type text, subject_id text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_representatives"($1, $2) $$;
revoke execute on function "api"."list_representatives"(text, text) from public, anon;
grant execute on function "api"."list_representatives"(text, text) to authenticated, service_role;

create or replace function "api"."represented_by_me"(tenant uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."represented_by_me"($1) $$;
revoke execute on function "api"."represented_by_me"(uuid) from public, anon;
grant execute on function "api"."represented_by_me"(uuid) to authenticated, service_role;

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
