-- better-supabase module: contacts
-- @bsb-block contacts@1 managed
-- @bsb-hash sha256:e3cda62064a4aad6be17bd90f779452e1f547bf4031e7b2787afbe117f7f6777
-- Companies and people an organization works with: lifecycle stages, owners, who works where with a role and a primary contact, domain and email dedupe, merges and keyset-paged search.
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
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."people";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."company_people";
  exception when undefined_table or invalid_schema_name then null;
  end;
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."person_inbox_contacts";
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
alter table "better_supabase"."companies" enable row level security;
revoke all on "better_supabase"."companies" from anon, authenticated;
grant select on "better_supabase"."companies" to authenticated;
grant all on "better_supabase"."companies" to service_role;
drop policy if exists companies_read on "better_supabase"."companies";
create policy companies_read on "better_supabase"."companies" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('parties.read')));

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
alter table "better_supabase"."people" enable row level security;
revoke all on "better_supabase"."people" from anon, authenticated;
grant select on "better_supabase"."people" to authenticated;
grant all on "better_supabase"."people" to service_role;
drop policy if exists people_read on "better_supabase"."people";
create policy people_read on "better_supabase"."people" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('parties.read')));

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
revoke all on "better_supabase"."company_people" from anon, authenticated;
grant select on "better_supabase"."company_people" to authenticated;
grant all on "better_supabase"."company_people" to service_role;
drop policy if exists company_people_read on "better_supabase"."company_people";
create policy company_people_read on "better_supabase"."company_people" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('parties.read')));

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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_company.tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_company.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_company.attrs ? 'lifecycle' and not (save_company.attrs ->> 'lifecycle' = any ('{lead,prospect,customer,churned}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
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
      insert into "better_supabase"."companies" ("tenant_id", "name", "domain", "website", "vat_id", "lifecycle", "owner_user_id", "address", "created_by")
      values (save_company.tenant, nullif(trim(save_company.attrs ->> 'name'), ''), lower(nullif(trim(save_company.attrs ->> 'domain'), '')), nullif(trim(save_company.attrs ->> 'website'), ''), nullif(trim(save_company.attrs ->> 'vatId'), ''), coalesce(nullif(trim(save_company.attrs ->> 'lifecycle'), ''), ('{lead,prospect,customer,churned}'::text[])[1]), nullif(save_company.attrs ->> 'ownerId', '')::uuid, save_company.attrs -> 'address', auth.uid())
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
  select to_jsonb(x) into v_row from "better_supabase"."companies" x where x."id" = v_id;
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', save_person.tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  if jsonb_typeof(coalesce(save_person.attrs, '{}')) <> 'object' then
    raise exception 'attrs must be an object' using errcode = '22023', hint = 'PARTY_ATTRS_INVALID';
  end if;
  if save_person.attrs ? 'lifecycle' and not (save_person.attrs ->> 'lifecycle' = any ('{lead,mql,sql,opportunity,customer}'::text[])) then
    raise exception 'unknown lifecycle stage' using errcode = '22023', hint = 'PARTY_LIFECYCLE_INVALID';
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
      insert into "better_supabase"."people" ("tenant_id", "name", "email", "phone", "title", "lifecycle", "owner_user_id", "user_id", "created_by")
      values (save_person.tenant, nullif(trim(save_person.attrs ->> 'name'), ''), lower(nullif(trim(save_person.attrs ->> 'email'), '')), nullif(trim(save_person.attrs ->> 'phone'), ''), nullif(trim(save_person.attrs ->> 'title'), ''), coalesce(nullif(trim(save_person.attrs ->> 'lifecycle'), ''), ('{lead,mql,sql,opportunity,customer}'::text[])[1]), nullif(save_person.attrs ->> 'ownerId', '')::uuid, nullif(save_person.attrs ->> 'userId', '')::uuid, auth.uid())
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
  select to_jsonb(x) into v_row from "better_supabase"."people" x where x."id" = v_id;
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'parties.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."companies" x set "domain" = null, "merged_into" = merge_companies.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_companies.drop;
  update "better_supabase"."companies" x set "domain" = coalesce(x."domain", v_drop."domain"), "website" = coalesce(x."website", v_drop."website"), "vat_id" = coalesce(x."vat_id", v_drop."vat_id"), "owner_user_id" = coalesce(x."owner_user_id", v_drop."owner_user_id"), "updated_at" = now()
  where x."id" = merge_companies.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", merge_companies.keep, l."person_id", l."role", false
  from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."company_id" = merge_companies.drop;
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
  return (select to_jsonb(x) from "better_supabase"."companies" x where x."id" = merge_companies.keep);
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
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_keep."tenant_id", 'parties.manage'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  update "better_supabase"."people" x set "email" = null, "merged_into" = merge_people.keep,
    "archived_at" = coalesce(x."archived_at", now()), "updated_at" = now()
  where x."id" = merge_people.drop;
  update "better_supabase"."people" x set "email" = coalesce(x."email", v_drop."email"), "phone" = coalesce(x."phone", v_drop."phone"), "title" = coalesce(x."title", v_drop."title"), "owner_user_id" = coalesce(x."owner_user_id", v_drop."owner_user_id"), "user_id" = coalesce(x."user_id", v_drop."user_id"), "updated_at" = now()
  where x."id" = merge_people.keep;
  insert into "better_supabase"."company_people" ("tenant_id", "company_id", "person_id", "role", "is_primary")
  select l."tenant_id", l."company_id", merge_people.keep, l."role", false
  from "better_supabase"."company_people" l where l."person_id" = merge_people.drop
  on conflict do nothing;
  delete from "better_supabase"."company_people" l where l."person_id" = merge_people.drop;
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
  return (select to_jsonb(x) from "better_supabase"."people" x where x."id" = merge_people.keep);
end;
$$;
revoke execute on function "better_supabase"."merge_people"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."merge_people"(uuid, uuid) to authenticated, service_role;

-- A page of the organization's active companies, by name. search matches
-- the name and domain; after_name and after_id continue after the
-- last row of the previous page.
create or replace function "better_supabase"."list_companies"(tenant uuid, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer)
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
    select jsonb_agg(to_jsonb(p) order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."companies" x
      where x."tenant_id" = list_companies.tenant
        and x."archived_at" is null
        and (list_companies.search is null or x."name" ilike v_like or x."domain" ilike v_like)
        and (list_companies.lifecycle is null or x."lifecycle" = list_companies.lifecycle)
        and (list_companies.owner is null or x."owner_user_id" = list_companies.owner)
        and (list_companies.after_name is null or (lower(x."name"), x."id") > (lower(list_companies.after_name), list_companies.after_id))
      order by lower(x."name"), x."id"
      limit least(greatest(coalesce(list_companies.page_size, 50), 1), 200)
    ) p
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_companies"(uuid, text, text, uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_companies"(uuid, text, text, uuid, text, uuid, integer) to authenticated, service_role;

-- A page of the organization's active people, by name. search matches
-- the name and email; after_name and after_id continue after the
-- last row of the previous page.
create or replace function "better_supabase"."list_people"(tenant uuid, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer)
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
    select jsonb_agg(to_jsonb(p) order by lower(p."name"), p."id")
    from (
      select x.* from "better_supabase"."people" x
      where x."tenant_id" = list_people.tenant
        and x."archived_at" is null
        and (list_people.search is null or x."name" ilike v_like or x."email" ilike v_like)
        and (list_people.lifecycle is null or x."lifecycle" = list_people.lifecycle)
        and (list_people.owner is null or x."owner_user_id" = list_people.owner)
        and (list_people.after_name is null or (lower(x."name"), x."id") > (lower(list_people.after_name), list_people.after_id))
      order by lower(x."name"), x."id"
      limit least(greatest(coalesce(list_people.page_size, 50), 1), 200)
    ) p
  ), '[]'::jsonb);
end;
$$;
revoke execute on function "better_supabase"."list_people"(uuid, text, text, uuid, text, uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_people"(uuid, text, text, uuid, text, uuid, integer) to authenticated, service_role;

-- The people of a company with their role, primary contact first.
create or replace function "better_supabase"."company_people_of"(company uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(p) || jsonb_build_object('role', l."role", 'is_primary', l."is_primary")
    order by l."is_primary" desc, lower(p."name"), p."id"), '[]'::jsonb)
  from "better_supabase"."company_people" l join "better_supabase"."people" p on p."id" = l."person_id"
  where l."company_id" = company_people_of.company and p."archived_at" is null
$$;
revoke execute on function "better_supabase"."company_people_of"(uuid) from public, anon;
grant execute on function "better_supabase"."company_people_of"(uuid) to authenticated, service_role;
create table if not exists "better_supabase"."person_inbox_contacts" (
  "tenant_id" uuid not null,
  "person_id" uuid not null references "better_supabase"."people" ("id") on delete cascade,
  "contact_id" uuid not null unique references "better_supabase"."contacts" ("id") on delete cascade,
  "created_at" timestamptz not null default now(),
  primary key ("person_id", "contact_id")
);
alter table "better_supabase"."person_inbox_contacts" enable row level security;
revoke all on "better_supabase"."person_inbox_contacts" from anon, authenticated;
grant select on "better_supabase"."person_inbox_contacts" to authenticated;
grant all on "better_supabase"."person_inbox_contacts" to service_role;
drop policy if exists person_inbox_contacts_read on "better_supabase"."person_inbox_contacts";
create policy person_inbox_contacts_read on "better_supabase"."person_inbox_contacts" for select to authenticated
using ("tenant_id" in (select better_supabase.tenant_ids_with('parties.read')));

-- Links an inbox contact to a person in the same organization; a contact
-- linked to someone else moves.
create or replace function "better_supabase"."link_inbox_contact"(person uuid, contact uuid)
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
  select p."tenant_id" into v_tenant from "better_supabase"."people" p
  join "better_supabase"."contacts" k on k."id" = link_inbox_contact.contact and k."tenant_id"::text = p."tenant_id"::text
  where p."id" = link_inbox_contact.person;
  if v_tenant is null then
    raise exception 'person or contact not found in one organization' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  insert into "better_supabase"."person_inbox_contacts" ("tenant_id", "person_id", "contact_id")
  values (v_tenant, link_inbox_contact.person, link_inbox_contact.contact)
  on conflict ("contact_id") do update set "person_id" = excluded."person_id";
  return true;
end;
$$;
revoke execute on function "better_supabase"."link_inbox_contact"(uuid, uuid) from public, anon;
grant execute on function "better_supabase"."link_inbox_contact"(uuid, uuid) to authenticated, service_role;

create or replace function "better_supabase"."unlink_inbox_contact"(contact uuid)
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
  select x."tenant_id" into v_tenant from "better_supabase"."person_inbox_contacts" x where x."contact_id" = unlink_inbox_contact.contact;
  if v_tenant is null then
    return false;
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_tenant, 'parties.write'), false)) then
    raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  delete from "better_supabase"."person_inbox_contacts" x where x."contact_id" = unlink_inbox_contact.contact;
  return true;
end;
$$;
revoke execute on function "better_supabase"."unlink_inbox_contact"(uuid) from public, anon;
grant execute on function "better_supabase"."unlink_inbox_contact"(uuid) to authenticated, service_role;

-- The person an inbox contact is linked to. Without a link, the active
-- person with the contact's email is linked first; with create, a contact
-- with a name and no match becomes a new lead.
create or replace function "better_supabase"."person_for_inbox_contact"(contact uuid, "create" boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contact "better_supabase"."contacts";
  v_person uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_contact from "better_supabase"."contacts" k where k."id" = person_for_inbox_contact.contact;
  if v_contact."id" is null then
    raise exception 'contact not found' using errcode = 'P0002', hint = 'PARTY_NOT_FOUND';
  end if;
  if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_contact."tenant_id", 'parties.read'), false)) then
    raise exception 'not allowed to read people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
  end if;
  select x."person_id" into v_person from "better_supabase"."person_inbox_contacts" x where x."contact_id" = v_contact."id";
  if v_person is null and v_contact."email" is not null then
    select p."id" into v_person from "better_supabase"."people" p
    where p."tenant_id"::text = v_contact."tenant_id"::text and p."email" = lower(v_contact."email") and p."archived_at" is null;
  end if;
  if v_person is null and person_for_inbox_contact."create" and nullif(trim(v_contact."name"), '') is not null then
    if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', v_contact."tenant_id", 'parties.write'), false)) then
      raise exception 'not allowed to change companies and people' using errcode = '42501', hint = 'PARTY_FORBIDDEN';
    end if;
    v_person := ("better_supabase"."save_person"(v_contact."tenant_id", null, jsonb_strip_nulls(jsonb_build_object(
      'name', v_contact."name", 'email', v_contact."email", 'phone', v_contact."phone"))) ->> 'id')::uuid;
  end if;
  if v_person is null then
    return null;
  end if;
  insert into "better_supabase"."person_inbox_contacts" ("tenant_id", "person_id", "contact_id")
  select p."tenant_id", v_person, v_contact."id" from "better_supabase"."people" p where p."id" = v_person
  on conflict do nothing;
  return (select to_jsonb(p) from "better_supabase"."people" p where p."id" = v_person);
end;
$$;
revoke execute on function "better_supabase"."person_for_inbox_contact"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."person_for_inbox_contact"(uuid, boolean) to authenticated, service_role;

-- Tenant isolation (ADR 0098): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."companies";
create policy bsb_tenant_scope on "better_supabase"."companies" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('parties.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."people";
create policy bsb_tenant_scope on "better_supabase"."people" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('parties.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."company_people";
create policy bsb_tenant_scope on "better_supabase"."company_people" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('parties.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "better_supabase"."person_inbox_contacts";
create policy bsb_tenant_scope on "better_supabase"."person_inbox_contacts" as restrictive
  for all to authenticated
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('parties.read')))
  )
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));

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

create or replace function "api"."list_companies"(tenant uuid, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_companies"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer) from public, anon;
grant execute on function "api"."list_companies"(uuid, text, text, uuid, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."list_people"(tenant uuid, search text, lifecycle text, owner uuid, after_name text, after_id uuid, page_size integer)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_people"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."list_people"(uuid, text, text, uuid, text, uuid, integer) from public, anon;
grant execute on function "api"."list_people"(uuid, text, text, uuid, text, uuid, integer) to authenticated, service_role;

create or replace function "api"."company_people_of"(company uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."company_people_of"($1) $$;
revoke execute on function "api"."company_people_of"(uuid) from public, anon;
grant execute on function "api"."company_people_of"(uuid) to authenticated, service_role;

create or replace function "api"."link_inbox_contact"(person uuid, contact uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."link_inbox_contact"($1, $2) $$;
revoke execute on function "api"."link_inbox_contact"(uuid, uuid) from public, anon;
grant execute on function "api"."link_inbox_contact"(uuid, uuid) to authenticated, service_role;

create or replace function "api"."unlink_inbox_contact"(contact uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."unlink_inbox_contact"($1) $$;
revoke execute on function "api"."unlink_inbox_contact"(uuid) from public, anon;
grant execute on function "api"."unlink_inbox_contact"(uuid) to authenticated, service_role;

create or replace function "api"."person_for_inbox_contact"(contact uuid, "create" boolean)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."person_for_inbox_contact"($1, $2) $$;
revoke execute on function "api"."person_for_inbox_contact"(uuid, boolean) from public, anon;
grant execute on function "api"."person_for_inbox_contact"(uuid, boolean) to authenticated, service_role;

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
