-- ==== alone: schema supabase/schemas/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block enrichment@1 managed
-- @bsb-hash sha256:fdb3fda00f686188bfd2a32efff66be658b4945659d814a566dc3f6f2d24b810
-- Company and person data from an enrichment provider, such as a company's industry and size or a person's title: one result per provider, the empty columns a match fills, and a list of the records due for a cron.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Enrichment: what a provider returned for a company or a person, one result
-- per provider, and the empty columns a match filled.
create table if not exists "better_supabase"."enrichments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "company_id" uuid references "better_supabase"."companies" ("id") on delete cascade,
  "person_id" uuid references "better_supabase"."people" ("id") on delete cascade,
  "provider" text not null check ("provider" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "status" text not null check ("status" in ('matched', 'not_found')),
  "data" jsonb not null default '{}'::jsonb check (jsonb_typeof("data") = 'object'),
  "filled" text[] not null default '{}',
  "fetched_at" timestamptz not null default now(),
  "requested_by" uuid references auth.users (id) on delete set null,
  check (num_nonnulls("company_id", "person_id") = 1),
  constraint enrichments_company_provider_key unique ("company_id", "provider"),
  constraint enrichments_person_provider_key unique ("person_id", "provider")
);
create index if not exists enrichments_tenant_idx on "better_supabase"."enrichments" ("tenant_id", "fetched_at");
create index if not exists enrichments_requested_by_idx on "better_supabase"."enrichments" ("requested_by") where "requested_by" is not null;
alter table "better_supabase"."enrichments" enable row level security;
revoke all on "better_supabase"."enrichments" from anon, authenticated;
grant select on "better_supabase"."enrichments" to authenticated;
grant all on "better_supabase"."enrichments" to service_role;
drop policy if exists enrichments_read on "better_supabase"."enrichments";
create policy enrichments_read on "better_supabase"."enrichments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')));

-- What a provider looks up for one company or person: its name and the
-- domain, website or email it can be matched by. Needs enrichment.run.
create or replace function "better_supabase"."enrichment_target"(subject_type text, subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target jsonb;
begin
  if enrichment_target.subject_type = 'company' then
    select jsonb_build_object('kind', 'company', 'organizationId', c."tenant_id", 'subjectType', 'company', 'subjectId', c."id", 'name', c."name", 'domain', c."domain", 'website', c."website") into v_target from "better_supabase"."companies" c
    where c."id" = enrichment_target.subject_id and c."archived_at" is null;
  elsif enrichment_target.subject_type = 'person' then
    select jsonb_build_object('kind', 'person', 'organizationId', p."tenant_id", 'subjectType', 'person', 'subjectId', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'title', p."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = p."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) into v_target from "better_supabase"."people" p
    where p."id" = enrichment_target.subject_id and p."archived_at" is null;
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_target is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', (v_target ->> 'organizationId')::uuid, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  return v_target;
end;
$$;
revoke execute on function "better_supabase"."enrichment_target"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichment_target"(text, uuid) to authenticated, service_role;

-- Stores what a provider returned for a company or person. result is
-- { status: 'matched' | 'not_found', data }. With fill, a match fills the
-- record's empty columns: a company's domain and website, a person's phone
-- and title. A domain another active company holds is left out. Returns the
-- stored result.
create or replace function "better_supabase"."record_enrichment"(subject_type text, subject_id uuid, provider text, result jsonb, fill boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_company "better_supabase"."companies";
  v_person "better_supabase"."people";
  v_row "better_supabase"."enrichments";
  v_status text;
  v_data jsonb;
  v_filled text[] := '{}';
  v_domain text;
  v_website text;
  v_phone text;
  v_title text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(result) is distinct from 'object' then
    raise exception 'result must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_status := result ->> 'status';
  if v_status is null or v_status not in ('matched', 'not_found') then
    raise exception 'result.status must be matched or not_found' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_data := case when v_status = 'matched' then coalesce(result -> 'data', '{}'::jsonb) else '{}'::jsonb end;
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'result.data must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.provider is null or record_enrichment.provider !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'provider must be a lowercase name' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.subject_type = 'company' then
    select * into v_company from "better_supabase"."companies" c
    where c."id" = record_enrichment.subject_id and c."archived_at" is null for update;
    v_tenant := v_company."tenant_id";
  elsif record_enrichment.subject_type = 'person' then
    select * into v_person from "better_supabase"."people" p
    where p."id" = record_enrichment.subject_id and p."archived_at" is null for update;
    v_tenant := v_person."tenant_id";
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  if v_status = 'matched' and coalesce(record_enrichment.fill, true) then
    if v_company."id" is not null then
      v_domain := lower(nullif(trim(v_data ->> 'domain'), ''));
      if v_company."domain" is null and v_domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
        and not exists (
          select 1 from "better_supabase"."companies" c
          where c."tenant_id" = v_tenant and c."domain" = v_domain and c."archived_at" is null
        ) then
        v_filled := v_filled || 'domain'::text;
      else
        v_domain := null;
      end if;
      v_website := nullif(trim(v_data ->> 'website'), '');
      if v_company."website" is null and length(v_website) <= 2048 then
        v_filled := v_filled || 'website'::text;
      else
        v_website := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."companies" c set
          "domain" = coalesce(c."domain", v_domain),
          "website" = coalesce(c."website", v_website),
          "updated_at" = now()
        where c."id" = v_company."id";
      end if;
    else
      v_phone := nullif(trim(v_data ->> 'phone'), '');
      if v_person."phone" is null and length(v_phone) <= 50 then
        v_filled := v_filled || 'phone'::text;
      else
        v_phone := null;
      end if;
      v_title := nullif(trim(v_data ->> 'title'), '');
      if v_person."title" is null and length(v_title) <= 300 then
        v_filled := v_filled || 'title'::text;
      else
        v_title := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."people" p set
          "phone" = coalesce(p."phone", v_phone),
          "title" = coalesce(p."title", v_title),
          "updated_at" = now()
        where p."id" = v_person."id";
      end if;
    end if;
  end if;
  if v_company."id" is not null then
    insert into "better_supabase"."enrichments" ("tenant_id", "company_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_company_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  else
    insert into "better_supabase"."enrichments" ("tenant_id", "person_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_person_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', case when v_row."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(v_row."company_id", v_row."person_id"), 'provider', v_row."provider", 'status', v_row."status", 'data', v_row."data", 'filled', to_jsonb(v_row."filled"), 'fetchedAt', v_row."fetched_at", 'requestedBy', v_row."requested_by");
end;
$$;
revoke execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) to authenticated, service_role;

-- A company's or person's stored results, one per provider, newest first.
create or replace function "better_supabase"."enrichments_of"(subject_type text, subject_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', case when x."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(x."company_id", x."person_id"), 'provider', x."provider", 'status', x."status", 'data', x."data", 'filled', to_jsonb(x."filled"), 'fetchedAt', x."fetched_at", 'requestedBy', x."requested_by") order by x."fetched_at" desc, x."provider"), '[]'::jsonb)
  from "better_supabase"."enrichments" x
  where case
      when enrichments_of.subject_type = 'company' then x."company_id" = enrichments_of.subject_id
      when enrichments_of.subject_type = 'person' then x."person_id" = enrichments_of.subject_id
      else false
    end
    and coalesce(better_supabase.can('tenant', x."tenant_id", 'enrichment.read'), false)
$$;
revoke execute on function "better_supabase"."enrichments_of"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichments_of"(text, uuid) to authenticated, service_role;

-- The companies and people a provider has no result for, or one older than
-- stale_after, never enriched first, for a cron. A company needs a domain or
-- a website and a person an email to be looked up.
create or replace function "better_supabase"."enrichment_due"(provider text, max_count integer default null, stale_after interval default null, subject_type text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.target order by z.fetched_at nulls first, z.id), '[]'::jsonb)
  from (
    select * from (
      select jsonb_build_object('kind', 'company', 'organizationId', x."tenant_id", 'subjectType', 'company', 'subjectId', x."id", 'name', x."name", 'domain', x."domain", 'website', x."website") as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."companies" x
    left join "better_supabase"."enrichments" y on y."company_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'company')
      and (x."domain" is not null or x."website" is not null)
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
      union all
      select jsonb_build_object('kind', 'person', 'organizationId', x."tenant_id", 'subjectType', 'person', 'subjectId', x."id", 'name', x."name", 'email', x."email", 'phone', x."phone", 'title', x."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = x."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."people" x
    left join "better_supabase"."enrichments" y on y."person_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'person')
      and x."email" is not null
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
    ) w
    order by w.fetched_at nulls first, w.id
    limit least(greatest(coalesce(enrichment_due.max_count, 25), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) from public, anon, authenticated;
grant execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
create policy bsb_tenant_scope_select on "better_supabase"."enrichments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrichments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
create policy bsb_tenant_scope_update on "better_supabase"."enrichments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrichments" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:dcb04aea5c6dba2694f8efab01af3f4faf3ae190eaf85c4f2685d756fb3f5cb1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block enrichment@1 managed
-- @bsb-hash sha256:60086459137904c9b31e2b621e04b541eec3324ccead62c3b46528302d614790
-- Company and person data from an enrichment provider, such as a company's industry and size or a person's title: one result per provider, the empty columns a match fills, and a list of the records due for a cron.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Enrichment: what a provider returned for a company or a person, one result
-- per provider, and the empty columns a match filled.
create table if not exists "better_supabase"."enrichments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "company_id" uuid references "better_supabase"."companies" ("id") on delete cascade,
  "person_id" uuid references "better_supabase"."people" ("id") on delete cascade,
  "provider" text not null check ("provider" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "status" text not null check ("status" in ('matched', 'not_found')),
  "data" jsonb not null default '{}'::jsonb check (jsonb_typeof("data") = 'object'),
  "filled" text[] not null default '{}',
  "fetched_at" timestamptz not null default now(),
  "requested_by" uuid references auth.users (id) on delete set null,
  check (num_nonnulls("company_id", "person_id") = 1),
  constraint enrichments_company_provider_key unique ("company_id", "provider"),
  constraint enrichments_person_provider_key unique ("person_id", "provider")
);
create index if not exists enrichments_tenant_idx on "better_supabase"."enrichments" ("tenant_id", "fetched_at");
create index if not exists enrichments_requested_by_idx on "better_supabase"."enrichments" ("requested_by") where "requested_by" is not null;
alter table "better_supabase"."enrichments" enable row level security;
revoke all on "better_supabase"."enrichments" from anon, authenticated;
grant select on "better_supabase"."enrichments" to authenticated;
grant all on "better_supabase"."enrichments" to service_role;
drop policy if exists enrichments_read on "better_supabase"."enrichments";
create policy enrichments_read on "better_supabase"."enrichments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')));

-- What a provider looks up for one company or person: its name and the
-- domain, website or email it can be matched by. Needs enrichment.run.
create or replace function "better_supabase"."enrichment_target"(subject_type text, subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target jsonb;
begin
  if enrichment_target.subject_type = 'company' then
    select jsonb_build_object('kind', 'company', 'organizationId', c."tenant_id", 'subjectType', 'company', 'subjectId', c."id", 'name', c."name", 'domain', c."domain", 'website', c."website") into v_target from "better_supabase"."companies" c
    where c."id" = enrichment_target.subject_id and c."archived_at" is null;
  elsif enrichment_target.subject_type = 'person' then
    select jsonb_build_object('kind', 'person', 'organizationId', p."tenant_id", 'subjectType', 'person', 'subjectId', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'title', p."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = p."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) into v_target from "better_supabase"."people" p
    where p."id" = enrichment_target.subject_id and p."archived_at" is null;
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_target is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', (v_target ->> 'organizationId')::uuid, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  return v_target;
end;
$$;
revoke execute on function "better_supabase"."enrichment_target"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichment_target"(text, uuid) to authenticated, service_role;

-- Stores what a provider returned for a company or person. result is
-- { status: 'matched' | 'not_found', data }. With fill, a match fills the
-- record's empty columns: a company's domain and website, a person's phone
-- and title. A domain another active company holds is left out. Returns the
-- stored result.
create or replace function "better_supabase"."record_enrichment"(subject_type text, subject_id uuid, provider text, result jsonb, fill boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_company "better_supabase"."companies";
  v_person "better_supabase"."people";
  v_row "better_supabase"."enrichments";
  v_status text;
  v_data jsonb;
  v_filled text[] := '{}';
  v_domain text;
  v_website text;
  v_phone text;
  v_title text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(result) is distinct from 'object' then
    raise exception 'result must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_status := result ->> 'status';
  if v_status is null or v_status not in ('matched', 'not_found') then
    raise exception 'result.status must be matched or not_found' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_data := case when v_status = 'matched' then coalesce(result -> 'data', '{}'::jsonb) else '{}'::jsonb end;
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'result.data must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.provider is null or record_enrichment.provider !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'provider must be a lowercase name' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.subject_type = 'company' then
    select * into v_company from "better_supabase"."companies" c
    where c."id" = record_enrichment.subject_id and c."archived_at" is null for update;
    v_tenant := v_company."tenant_id";
  elsif record_enrichment.subject_type = 'person' then
    select * into v_person from "better_supabase"."people" p
    where p."id" = record_enrichment.subject_id and p."archived_at" is null for update;
    v_tenant := v_person."tenant_id";
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  if v_status = 'matched' and coalesce(record_enrichment.fill, true) then
    if v_company."id" is not null then
      v_domain := lower(nullif(trim(v_data ->> 'domain'), ''));
      if v_company."domain" is null and v_domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
        and not exists (
          select 1 from "better_supabase"."companies" c
          where c."tenant_id" = v_tenant and c."domain" = v_domain and c."archived_at" is null
        ) then
        v_filled := v_filled || 'domain'::text;
      else
        v_domain := null;
      end if;
      v_website := nullif(trim(v_data ->> 'website'), '');
      if v_company."website" is null and length(v_website) <= 2048 then
        v_filled := v_filled || 'website'::text;
      else
        v_website := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."companies" c set
          "domain" = coalesce(c."domain", v_domain),
          "website" = coalesce(c."website", v_website),
          "updated_at" = now()
        where c."id" = v_company."id";
      end if;
    else
      v_phone := nullif(trim(v_data ->> 'phone'), '');
      if v_person."phone" is null and length(v_phone) <= 50 then
        v_filled := v_filled || 'phone'::text;
      else
        v_phone := null;
      end if;
      v_title := nullif(trim(v_data ->> 'title'), '');
      if v_person."title" is null and length(v_title) <= 300 then
        v_filled := v_filled || 'title'::text;
      else
        v_title := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."people" p set
          "phone" = coalesce(p."phone", v_phone),
          "title" = coalesce(p."title", v_title),
          "updated_at" = now()
        where p."id" = v_person."id";
      end if;
    end if;
  end if;
  if v_company."id" is not null then
    insert into "better_supabase"."enrichments" ("tenant_id", "company_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_company_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  else
    insert into "better_supabase"."enrichments" ("tenant_id", "person_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_person_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  end if;
  perform "better_supabase".emit_event('party.enriched', jsonb_build_object('organizationId', v_tenant, 'subjectType', record_enrichment.subject_type, 'subjectId', record_enrichment.subject_id, 'provider', record_enrichment.provider, 'status', v_status, 'filled', to_jsonb(v_filled)), 'enrichments/' || v_row."id"::text, (v_tenant::text)::text, null, 'better-supabase/enrichment');
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', case when v_row."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(v_row."company_id", v_row."person_id"), 'provider', v_row."provider", 'status', v_row."status", 'data', v_row."data", 'filled', to_jsonb(v_row."filled"), 'fetchedAt', v_row."fetched_at", 'requestedBy', v_row."requested_by");
end;
$$;
revoke execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) to authenticated, service_role;

-- A company's or person's stored results, one per provider, newest first.
create or replace function "better_supabase"."enrichments_of"(subject_type text, subject_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', case when x."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(x."company_id", x."person_id"), 'provider', x."provider", 'status', x."status", 'data', x."data", 'filled', to_jsonb(x."filled"), 'fetchedAt', x."fetched_at", 'requestedBy', x."requested_by") order by x."fetched_at" desc, x."provider"), '[]'::jsonb)
  from "better_supabase"."enrichments" x
  where case
      when enrichments_of.subject_type = 'company' then x."company_id" = enrichments_of.subject_id
      when enrichments_of.subject_type = 'person' then x."person_id" = enrichments_of.subject_id
      else false
    end
    and coalesce(better_supabase.can('tenant', x."tenant_id", 'enrichment.read'), false)
$$;
revoke execute on function "better_supabase"."enrichments_of"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichments_of"(text, uuid) to authenticated, service_role;

-- The companies and people a provider has no result for, or one older than
-- stale_after, never enriched first, for a cron. A company needs a domain or
-- a website and a person an email to be looked up.
create or replace function "better_supabase"."enrichment_due"(provider text, max_count integer default null, stale_after interval default null, subject_type text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.target order by z.fetched_at nulls first, z.id), '[]'::jsonb)
  from (
    select * from (
      select jsonb_build_object('kind', 'company', 'organizationId', x."tenant_id", 'subjectType', 'company', 'subjectId', x."id", 'name', x."name", 'domain', x."domain", 'website', x."website") as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."companies" x
    left join "better_supabase"."enrichments" y on y."company_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'company')
      and (x."domain" is not null or x."website" is not null)
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
      union all
      select jsonb_build_object('kind', 'person', 'organizationId', x."tenant_id", 'subjectType', 'person', 'subjectId', x."id", 'name', x."name", 'email', x."email", 'phone', x."phone", 'title', x."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = x."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."people" x
    left join "better_supabase"."enrichments" y on y."person_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'person')
      and x."email" is not null
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
    ) w
    order by w.fetched_at nulls first, w.id
    limit least(greatest(coalesce(enrichment_due.max_count, 25), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) from public, anon, authenticated;
grant execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
create policy bsb_tenant_scope_select on "better_supabase"."enrichments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrichments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
create policy bsb_tenant_scope_update on "better_supabase"."enrichments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrichments" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:dcb04aea5c6dba2694f8efab01af3f4faf3ae190eaf85c4f2685d756fb3f5cb1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block enrichment@1 managed
-- @bsb-hash sha256:ae1feb3bcb3e9c78da2f0297b9207670c2e21fe65852b87c3484fc3cbf9649d7
-- Company and person data from an enrichment provider, such as a company's industry and size or a person's title: one result per provider, the empty columns a match fills, and a list of the records due for a cron.
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
    drop policy if exists bsb_tenant_scope on "app_private"."enrichments";
    drop policy if exists bsb_tenant_scope_select on "app_private"."enrichments";
    drop policy if exists bsb_tenant_scope_insert on "app_private"."enrichments";
    drop policy if exists bsb_tenant_scope_update on "app_private"."enrichments";
    drop policy if exists bsb_tenant_scope_delete on "app_private"."enrichments";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
-- Enrichment: what a provider returned for a company or a person, one result
-- per provider, and the empty columns a match filled.
create table if not exists "app_private"."enrichments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "company_id" uuid references "better_supabase"."companies" ("id") on delete cascade,
  "person_id" uuid references "better_supabase"."people" ("id") on delete cascade,
  "provider" text not null check ("provider" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "status" text not null check ("status" in ('matched', 'not_found')),
  "data" jsonb not null default '{}'::jsonb check (jsonb_typeof("data") = 'object'),
  "filled" text[] not null default '{}',
  "fetched_at" timestamptz not null default now(),
  "requested_by" uuid references auth.users (id) on delete set null,
  check (num_nonnulls("company_id", "person_id") = 1),
  constraint enrichments_company_provider_key unique ("company_id", "provider"),
  constraint enrichments_person_provider_key unique ("person_id", "provider")
);
create index if not exists enrichments_tenant_idx on "app_private"."enrichments" ("tenant_id", "fetched_at");
create index if not exists enrichments_requested_by_idx on "app_private"."enrichments" ("requested_by") where "requested_by" is not null;
alter table "app_private"."enrichments" enable row level security;
revoke all on "app_private"."enrichments" from anon, authenticated;
grant select on "app_private"."enrichments" to authenticated;
grant all on "app_private"."enrichments" to service_role;
drop policy if exists enrichments_read on "app_private"."enrichments";
create policy enrichments_read on "app_private"."enrichments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')));

-- What a provider looks up for one company or person: its name and the
-- domain, website or email it can be matched by. Needs enrichment.run.
create or replace function "app_private"."enrichment_target"(subject_type text, subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target jsonb;
begin
  if enrichment_target.subject_type = 'company' then
    select jsonb_build_object('kind', 'company', 'organizationId', c."tenant_id", 'subjectType', 'company', 'subjectId', c."id", 'name', c."name", 'domain', c."domain", 'website', c."website") into v_target from "better_supabase"."companies" c
    where c."id" = enrichment_target.subject_id and c."archived_at" is null;
  elsif enrichment_target.subject_type = 'person' then
    select jsonb_build_object('kind', 'person', 'organizationId', p."tenant_id", 'subjectType', 'person', 'subjectId', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'title', p."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = p."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) into v_target from "better_supabase"."people" p
    where p."id" = enrichment_target.subject_id and p."archived_at" is null;
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_target is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', (v_target ->> 'organizationId')::uuid, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  return v_target;
end;
$$;
revoke execute on function "app_private"."enrichment_target"(text, uuid) from public, anon;
grant execute on function "app_private"."enrichment_target"(text, uuid) to authenticated, service_role;

-- Stores what a provider returned for a company or person. result is
-- { status: 'matched' | 'not_found', data }. With fill, a match fills the
-- record's empty columns: a company's domain and website, a person's phone
-- and title. A domain another active company holds is left out. Returns the
-- stored result.
create or replace function "app_private"."record_enrichment"(subject_type text, subject_id uuid, provider text, result jsonb, fill boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_company "better_supabase"."companies";
  v_person "better_supabase"."people";
  v_row "app_private"."enrichments";
  v_status text;
  v_data jsonb;
  v_filled text[] := '{}';
  v_domain text;
  v_website text;
  v_phone text;
  v_title text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(result) is distinct from 'object' then
    raise exception 'result must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_status := result ->> 'status';
  if v_status is null or v_status not in ('matched', 'not_found') then
    raise exception 'result.status must be matched or not_found' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_data := case when v_status = 'matched' then coalesce(result -> 'data', '{}'::jsonb) else '{}'::jsonb end;
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'result.data must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.provider is null or record_enrichment.provider !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'provider must be a lowercase name' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.subject_type = 'company' then
    select * into v_company from "better_supabase"."companies" c
    where c."id" = record_enrichment.subject_id and c."archived_at" is null for update;
    v_tenant := v_company."tenant_id";
  elsif record_enrichment.subject_type = 'person' then
    select * into v_person from "better_supabase"."people" p
    where p."id" = record_enrichment.subject_id and p."archived_at" is null for update;
    v_tenant := v_person."tenant_id";
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  if v_status = 'matched' and coalesce(record_enrichment.fill, true) then
    if v_company."id" is not null then
      v_domain := lower(nullif(trim(v_data ->> 'domain'), ''));
      if v_company."domain" is null and v_domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
        and not exists (
          select 1 from "better_supabase"."companies" c
          where c."tenant_id" = v_tenant and c."domain" = v_domain and c."archived_at" is null
        ) then
        v_filled := v_filled || 'domain'::text;
      else
        v_domain := null;
      end if;
      v_website := nullif(trim(v_data ->> 'website'), '');
      if v_company."website" is null and length(v_website) <= 2048 then
        v_filled := v_filled || 'website'::text;
      else
        v_website := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."companies" c set
          "domain" = coalesce(c."domain", v_domain),
          "website" = coalesce(c."website", v_website),
          "updated_at" = now()
        where c."id" = v_company."id";
      end if;
    else
      v_phone := nullif(trim(v_data ->> 'phone'), '');
      if v_person."phone" is null and length(v_phone) <= 50 then
        v_filled := v_filled || 'phone'::text;
      else
        v_phone := null;
      end if;
      v_title := nullif(trim(v_data ->> 'title'), '');
      if v_person."title" is null and length(v_title) <= 300 then
        v_filled := v_filled || 'title'::text;
      else
        v_title := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."people" p set
          "phone" = coalesce(p."phone", v_phone),
          "title" = coalesce(p."title", v_title),
          "updated_at" = now()
        where p."id" = v_person."id";
      end if;
    end if;
  end if;
  if v_company."id" is not null then
    insert into "app_private"."enrichments" ("tenant_id", "company_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_company_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  else
    insert into "app_private"."enrichments" ("tenant_id", "person_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_person_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', case when v_row."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(v_row."company_id", v_row."person_id"), 'provider', v_row."provider", 'status', v_row."status", 'data', v_row."data", 'filled', to_jsonb(v_row."filled"), 'fetchedAt', v_row."fetched_at", 'requestedBy', v_row."requested_by");
end;
$$;
revoke execute on function "app_private"."record_enrichment"(text, uuid, text, jsonb, boolean) from public, anon;
grant execute on function "app_private"."record_enrichment"(text, uuid, text, jsonb, boolean) to authenticated, service_role;

-- A company's or person's stored results, one per provider, newest first.
create or replace function "app_private"."enrichments_of"(subject_type text, subject_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', case when x."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(x."company_id", x."person_id"), 'provider', x."provider", 'status', x."status", 'data', x."data", 'filled', to_jsonb(x."filled"), 'fetchedAt', x."fetched_at", 'requestedBy', x."requested_by") order by x."fetched_at" desc, x."provider"), '[]'::jsonb)
  from "app_private"."enrichments" x
  where case
      when enrichments_of.subject_type = 'company' then x."company_id" = enrichments_of.subject_id
      when enrichments_of.subject_type = 'person' then x."person_id" = enrichments_of.subject_id
      else false
    end
    and coalesce(better_supabase.can('tenant', x."tenant_id", 'enrichment.read'), false)
$$;
revoke execute on function "app_private"."enrichments_of"(text, uuid) from public, anon;
grant execute on function "app_private"."enrichments_of"(text, uuid) to authenticated, service_role;

-- The companies and people a provider has no result for, or one older than
-- stale_after, never enriched first, for a cron. A company needs a domain or
-- a website and a person an email to be looked up.
create or replace function "app_private"."enrichment_due"(provider text, max_count integer default null, stale_after interval default null, subject_type text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.target order by z.fetched_at nulls first, z.id), '[]'::jsonb)
  from (
    select * from (
      select jsonb_build_object('kind', 'company', 'organizationId', x."tenant_id", 'subjectType', 'company', 'subjectId', x."id", 'name', x."name", 'domain', x."domain", 'website', x."website") as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."companies" x
    left join "app_private"."enrichments" y on y."company_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'company')
      and (x."domain" is not null or x."website" is not null)
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
      union all
      select jsonb_build_object('kind', 'person', 'organizationId', x."tenant_id", 'subjectType', 'person', 'subjectId', x."id", 'name', x."name", 'email', x."email", 'phone', x."phone", 'title', x."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = x."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."people" x
    left join "app_private"."enrichments" y on y."person_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'person')
      and x."email" is not null
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
    ) w
    order by w.fetched_at nulls first, w.id
    limit least(greatest(coalesce(enrichment_due.max_count, 25), 1), 500)
  ) z
$$;
revoke execute on function "app_private"."enrichment_due"(text, integer, interval, text) from public, anon, authenticated;
grant execute on function "app_private"."enrichment_due"(text, integer, interval, text) to service_role;

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
drop policy if exists bsb_tenant_scope on "app_private"."enrichments";
drop policy if exists bsb_tenant_scope_select on "app_private"."enrichments";
create policy bsb_tenant_scope_select on "app_private"."enrichments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "app_private"."enrichments";
create policy bsb_tenant_scope_insert on "app_private"."enrichments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "app_private"."enrichments";
create policy bsb_tenant_scope_update on "app_private"."enrichments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "app_private"."enrichments";
create policy bsb_tenant_scope_delete on "app_private"."enrichments" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:dcb04aea5c6dba2694f8efab01af3f4faf3ae190eaf85c4f2685d756fb3f5cb1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block enrichment@1 managed
-- @bsb-hash sha256:329d090402a9bbec2dcdfe11f49ed36767aebc5c115ae89c43afc294d62eb3fa
-- Company and person data from an enrichment provider, such as a company's industry and size or a person's title: one result per provider, the empty columns a match fills, and a list of the records due for a cron.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Enrichment: what a provider returned for a company or a person, one result
-- per provider, and the empty columns a match filled.
create table if not exists "better_supabase"."enrichments" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "company_id" uuid references "better_supabase"."companies" ("id") on delete cascade,
  "person_id" uuid references "better_supabase"."people" ("id") on delete cascade,
  "provider" text not null check ("provider" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "status" text not null check ("status" in ('matched', 'not_found')),
  "data" jsonb not null default '{}'::jsonb check (jsonb_typeof("data") = 'object'),
  "filled" text[] not null default '{}',
  "fetched_at" timestamptz not null default now(),
  "requested_by" uuid references auth.users (id) on delete set null,
  check (num_nonnulls("company_id", "person_id") = 1),
  constraint enrichments_company_provider_key unique ("company_id", "provider"),
  constraint enrichments_person_provider_key unique ("person_id", "provider")
);
create index if not exists enrichments_tenant_idx on "better_supabase"."enrichments" ("tenant_id", "fetched_at");
create index if not exists enrichments_requested_by_idx on "better_supabase"."enrichments" ("requested_by") where "requested_by" is not null;
alter table "better_supabase"."enrichments" enable row level security;
revoke all on "better_supabase"."enrichments" from anon, authenticated;
grant select on "better_supabase"."enrichments" to authenticated;
grant all on "better_supabase"."enrichments" to service_role;
drop policy if exists enrichments_read on "better_supabase"."enrichments";
create policy enrichments_read on "better_supabase"."enrichments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')));

-- What a provider looks up for one company or person: its name and the
-- domain, website or email it can be matched by. Needs enrichment.run.
create or replace function "better_supabase"."enrichment_target"(subject_type text, subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target jsonb;
begin
  if enrichment_target.subject_type = 'company' then
    select jsonb_build_object('kind', 'company', 'organizationId', c."tenant_id", 'subjectType', 'company', 'subjectId', c."id", 'name', c."name", 'domain', c."domain", 'website', c."website") into v_target from "better_supabase"."companies" c
    where c."id" = enrichment_target.subject_id and c."archived_at" is null;
  elsif enrichment_target.subject_type = 'person' then
    select jsonb_build_object('kind', 'person', 'organizationId', p."tenant_id", 'subjectType', 'person', 'subjectId', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'title', p."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = p."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) into v_target from "better_supabase"."people" p
    where p."id" = enrichment_target.subject_id and p."archived_at" is null;
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_target is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', (v_target ->> 'organizationId')::uuid, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  return v_target;
end;
$$;
revoke execute on function "better_supabase"."enrichment_target"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichment_target"(text, uuid) to authenticated, service_role;

-- Stores what a provider returned for a company or person. result is
-- { status: 'matched' | 'not_found', data }. With fill, a match fills the
-- record's empty columns: a company's domain and website, a person's phone
-- and title. A domain another active company holds is left out. Returns the
-- stored result.
create or replace function "better_supabase"."record_enrichment"(subject_type text, subject_id uuid, provider text, result jsonb, fill boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_company "better_supabase"."companies";
  v_person "better_supabase"."people";
  v_row "better_supabase"."enrichments";
  v_status text;
  v_data jsonb;
  v_filled text[] := '{}';
  v_domain text;
  v_website text;
  v_phone text;
  v_title text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(result) is distinct from 'object' then
    raise exception 'result must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_status := result ->> 'status';
  if v_status is null or v_status not in ('matched', 'not_found') then
    raise exception 'result.status must be matched or not_found' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_data := case when v_status = 'matched' then coalesce(result -> 'data', '{}'::jsonb) else '{}'::jsonb end;
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'result.data must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.provider is null or record_enrichment.provider !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'provider must be a lowercase name' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.subject_type = 'company' then
    select * into v_company from "better_supabase"."companies" c
    where c."id" = record_enrichment.subject_id and c."archived_at" is null for update;
    v_tenant := v_company."tenant_id";
  elsif record_enrichment.subject_type = 'person' then
    select * into v_person from "better_supabase"."people" p
    where p."id" = record_enrichment.subject_id and p."archived_at" is null for update;
    v_tenant := v_person."tenant_id";
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  if v_status = 'matched' and coalesce(record_enrichment.fill, true) then
    if v_company."id" is not null then
      v_domain := lower(nullif(trim(v_data ->> 'domain'), ''));
      if v_company."domain" is null and v_domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
        and not exists (
          select 1 from "better_supabase"."companies" c
          where c."tenant_id" = v_tenant and c."domain" = v_domain and c."archived_at" is null
        ) then
        v_filled := v_filled || 'domain'::text;
      else
        v_domain := null;
      end if;
      v_website := nullif(trim(v_data ->> 'website'), '');
      if v_company."website" is null and length(v_website) <= 2048 then
        v_filled := v_filled || 'website'::text;
      else
        v_website := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."companies" c set
          "domain" = coalesce(c."domain", v_domain),
          "website" = coalesce(c."website", v_website),
          "updated_at" = now()
        where c."id" = v_company."id";
      end if;
    else
      v_phone := nullif(trim(v_data ->> 'phone'), '');
      if v_person."phone" is null and length(v_phone) <= 50 then
        v_filled := v_filled || 'phone'::text;
      else
        v_phone := null;
      end if;
      v_title := nullif(trim(v_data ->> 'title'), '');
      if v_person."title" is null and length(v_title) <= 300 then
        v_filled := v_filled || 'title'::text;
      else
        v_title := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."people" p set
          "phone" = coalesce(p."phone", v_phone),
          "title" = coalesce(p."title", v_title),
          "updated_at" = now()
        where p."id" = v_person."id";
      end if;
    end if;
  end if;
  if v_company."id" is not null then
    insert into "better_supabase"."enrichments" ("tenant_id", "company_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_company_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  else
    insert into "better_supabase"."enrichments" ("tenant_id", "person_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_person_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', case when v_row."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(v_row."company_id", v_row."person_id"), 'provider', v_row."provider", 'status', v_row."status", 'data', v_row."data", 'filled', to_jsonb(v_row."filled"), 'fetchedAt', v_row."fetched_at", 'requestedBy', v_row."requested_by");
end;
$$;
revoke execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) to authenticated, service_role;

-- A company's or person's stored results, one per provider, newest first.
create or replace function "better_supabase"."enrichments_of"(subject_type text, subject_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', case when x."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(x."company_id", x."person_id"), 'provider', x."provider", 'status', x."status", 'data', x."data", 'filled', to_jsonb(x."filled"), 'fetchedAt', x."fetched_at", 'requestedBy', x."requested_by") order by x."fetched_at" desc, x."provider"), '[]'::jsonb)
  from "better_supabase"."enrichments" x
  where case
      when enrichments_of.subject_type = 'company' then x."company_id" = enrichments_of.subject_id
      when enrichments_of.subject_type = 'person' then x."person_id" = enrichments_of.subject_id
      else false
    end
    and coalesce(better_supabase.can('tenant', x."tenant_id", 'enrichment.read'), false)
$$;
revoke execute on function "better_supabase"."enrichments_of"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichments_of"(text, uuid) to authenticated, service_role;

-- The companies and people a provider has no result for, or one older than
-- stale_after, never enriched first, for a cron. A company needs a domain or
-- a website and a person an email to be looked up.
create or replace function "better_supabase"."enrichment_due"(provider text, max_count integer default null, stale_after interval default null, subject_type text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.target order by z.fetched_at nulls first, z.id), '[]'::jsonb)
  from (
    select * from (
      select jsonb_build_object('kind', 'company', 'organizationId', x."tenant_id", 'subjectType', 'company', 'subjectId', x."id", 'name', x."name", 'domain', x."domain", 'website', x."website") as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."companies" x
    left join "better_supabase"."enrichments" y on y."company_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'company')
      and (x."domain" is not null or x."website" is not null)
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
      union all
      select jsonb_build_object('kind', 'person', 'organizationId', x."tenant_id", 'subjectType', 'person', 'subjectId', x."id", 'name', x."name", 'email', x."email", 'phone', x."phone", 'title', x."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = x."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."people" x
    left join "better_supabase"."enrichments" y on y."person_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'person')
      and x."email" is not null
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
    ) w
    order by w.fetched_at nulls first, w.id
    limit least(greatest(coalesce(enrichment_due.max_count, 25), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) from public, anon, authenticated;
grant execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
create policy bsb_tenant_scope_select on "better_supabase"."enrichments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrichments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
create policy bsb_tenant_scope_update on "better_supabase"."enrichments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrichments" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.enrichment.api: entry points for the Data API.
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

create or replace function "api"."enrichment_target"(subject_type text, subject_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enrichment_target"($1, $2) $$;
revoke execute on function "api"."enrichment_target"(text, uuid) from public, anon;
grant execute on function "api"."enrichment_target"(text, uuid) to authenticated, service_role;

create or replace function "api"."record_enrichment"(subject_type text, subject_id uuid, provider text, result jsonb, fill boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."record_enrichment"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."record_enrichment"(text, uuid, text, jsonb, boolean) from public, anon;
grant execute on function "api"."record_enrichment"(text, uuid, text, jsonb, boolean) to authenticated, service_role;

create or replace function "api"."enrichments_of"(subject_type text, subject_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enrichments_of"($1, $2) $$;
revoke execute on function "api"."enrichments_of"(text, uuid) from public, anon;
grant execute on function "api"."enrichments_of"(text, uuid) to authenticated, service_role;

create or replace function "api"."enrichment_due"(provider text, max_count integer default null, stale_after interval default null, subject_type text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."enrichment_due"($1, $2, $3, $4) $$;
revoke execute on function "api"."enrichment_due"(text, integer, interval, text) from public, anon, authenticated;
grant execute on function "api"."enrichment_due"(text, integer, interval, text) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:dcb04aea5c6dba2694f8efab01af3f4faf3ae190eaf85c4f2685d756fb3f5cb1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block enrichment@1 managed
-- @bsb-hash sha256:fe6be81da21875e139c6d26ecef18f80e08d1ac577f66bbb9c12d850aaa4e6f3
-- Company and person data from an enrichment provider, such as a company's industry and size or a person's title: one result per provider, the empty columns a match fills, and a list of the records due for a cron.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Enrichment: what a provider returned for a company or a person, one result
-- per provider, and the empty columns a match filled.
-- better_supabase.enrichments is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."enrichments" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."enrichments" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."enrichments" add column if not exists "company_id" uuid references "better_supabase"."companies" ("id") on delete cascade;
alter table "better_supabase"."enrichments" add column if not exists "person_id" uuid references "better_supabase"."people" ("id") on delete cascade;
alter table "better_supabase"."enrichments" add column if not exists "provider" text check ("provider" ~ '^[a-z][a-z0-9_-]{0,62}$');
alter table "better_supabase"."enrichments" add column if not exists "status" text check ("status" in ('matched', 'not_found'));
alter table "better_supabase"."enrichments" add column if not exists "data" jsonb not null default '{}'::jsonb check (jsonb_typeof("data") = 'object');
alter table "better_supabase"."enrichments" add column if not exists "filled" text[] not null default '{}';
alter table "better_supabase"."enrichments" add column if not exists "fetched_at" timestamptz not null default now();
alter table "better_supabase"."enrichments" add column if not exists "requested_by" uuid references auth.users (id) on delete set null;
create index if not exists enrichments_tenant_idx on "better_supabase"."enrichments" ("tenant_id", "fetched_at");
create index if not exists enrichments_requested_by_idx on "better_supabase"."enrichments" ("requested_by") where "requested_by" is not null;
create unique index if not exists "bsb_enrichments_company_provider_key" on "better_supabase"."enrichments" ("company_id", "provider");
create unique index if not exists "bsb_enrichments_person_provider_key" on "better_supabase"."enrichments" ("person_id", "provider");
alter table "better_supabase"."enrichments" enable row level security;
grant select on "better_supabase"."enrichments" to authenticated;
grant all on "better_supabase"."enrichments" to service_role;
drop policy if exists bsb_enrichments_select on "better_supabase"."enrichments";
create policy bsb_enrichments_select on "better_supabase"."enrichments"
  for select to authenticated
  using ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')));

-- What a provider looks up for one company or person: its name and the
-- domain, website or email it can be matched by. Needs enrichment.run.
create or replace function "better_supabase"."enrichment_target"(subject_type text, subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target jsonb;
begin
  if enrichment_target.subject_type = 'company' then
    select jsonb_build_object('kind', 'company', 'organizationId', c."tenant_id", 'subjectType', 'company', 'subjectId', c."id", 'name', c."name", 'domain', c."domain", 'website', c."website") into v_target from "better_supabase"."companies" c
    where c."id" = enrichment_target.subject_id and c."archived_at" is null;
  elsif enrichment_target.subject_type = 'person' then
    select jsonb_build_object('kind', 'person', 'organizationId', p."tenant_id", 'subjectType', 'person', 'subjectId', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'title', p."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = p."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) into v_target from "better_supabase"."people" p
    where p."id" = enrichment_target.subject_id and p."archived_at" is null;
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_target is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', (v_target ->> 'organizationId')::uuid, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  return v_target;
end;
$$;
revoke execute on function "better_supabase"."enrichment_target"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichment_target"(text, uuid) to authenticated, service_role;

-- Stores what a provider returned for a company or person. result is
-- { status: 'matched' | 'not_found', data }. With fill, a match fills the
-- record's empty columns: a company's domain and website, a person's phone
-- and title. A domain another active company holds is left out. Returns the
-- stored result.
create or replace function "better_supabase"."record_enrichment"(subject_type text, subject_id uuid, provider text, result jsonb, fill boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_tenant uuid;
  v_company "better_supabase"."companies";
  v_person "better_supabase"."people";
  v_row "better_supabase"."enrichments";
  v_status text;
  v_data jsonb;
  v_filled text[] := '{}';
  v_domain text;
  v_website text;
  v_phone text;
  v_title text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(result) is distinct from 'object' then
    raise exception 'result must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_status := result ->> 'status';
  if v_status is null or v_status not in ('matched', 'not_found') then
    raise exception 'result.status must be matched or not_found' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_data := case when v_status = 'matched' then coalesce(result -> 'data', '{}'::jsonb) else '{}'::jsonb end;
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'result.data must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.provider is null or record_enrichment.provider !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'provider must be a lowercase name' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.subject_type = 'company' then
    select * into v_company from "better_supabase"."companies" c
    where c."id" = record_enrichment.subject_id and c."archived_at" is null for update;
    v_tenant := v_company."tenant_id";
  elsif record_enrichment.subject_type = 'person' then
    select * into v_person from "better_supabase"."people" p
    where p."id" = record_enrichment.subject_id and p."archived_at" is null for update;
    v_tenant := v_person."tenant_id";
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  if v_status = 'matched' and coalesce(record_enrichment.fill, true) then
    if v_company."id" is not null then
      v_domain := lower(nullif(trim(v_data ->> 'domain'), ''));
      if v_company."domain" is null and v_domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
        and not exists (
          select 1 from "better_supabase"."companies" c
          where c."tenant_id" = v_tenant and c."domain" = v_domain and c."archived_at" is null
        ) then
        v_filled := v_filled || 'domain'::text;
      else
        v_domain := null;
      end if;
      v_website := nullif(trim(v_data ->> 'website'), '');
      if v_company."website" is null and length(v_website) <= 2048 then
        v_filled := v_filled || 'website'::text;
      else
        v_website := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."companies" c set
          "domain" = coalesce(c."domain", v_domain),
          "website" = coalesce(c."website", v_website),
          "updated_at" = now()
        where c."id" = v_company."id";
      end if;
    else
      v_phone := nullif(trim(v_data ->> 'phone'), '');
      if v_person."phone" is null and length(v_phone) <= 50 then
        v_filled := v_filled || 'phone'::text;
      else
        v_phone := null;
      end if;
      v_title := nullif(trim(v_data ->> 'title'), '');
      if v_person."title" is null and length(v_title) <= 300 then
        v_filled := v_filled || 'title'::text;
      else
        v_title := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."people" p set
          "phone" = coalesce(p."phone", v_phone),
          "title" = coalesce(p."title", v_title),
          "updated_at" = now()
        where p."id" = v_person."id";
      end if;
    end if;
  end if;
  if v_company."id" is not null then
    insert into "better_supabase"."enrichments" ("tenant_id", "company_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, better_supabase.as_column_type(v_status, (null::"better_supabase"."enrichments")."status"), v_data, v_filled, auth.uid())
    on conflict ("company_id", "provider") do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  else
    insert into "better_supabase"."enrichments" ("tenant_id", "person_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, better_supabase.as_column_type(v_status, (null::"better_supabase"."enrichments")."status"), v_data, v_filled, auth.uid())
    on conflict ("person_id", "provider") do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."tenant_id", 'subjectType', case when v_row."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(v_row."company_id", v_row."person_id"), 'provider', v_row."provider", 'status', v_row."status", 'data', v_row."data", 'filled', to_jsonb(v_row."filled"), 'fetchedAt', v_row."fetched_at", 'requestedBy', v_row."requested_by");
end;
$$;
revoke execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) to authenticated, service_role;

-- A company's or person's stored results, one per provider, newest first.
create or replace function "better_supabase"."enrichments_of"(subject_type text, subject_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."tenant_id", 'subjectType', case when x."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(x."company_id", x."person_id"), 'provider', x."provider", 'status', x."status", 'data', x."data", 'filled', to_jsonb(x."filled"), 'fetchedAt', x."fetched_at", 'requestedBy', x."requested_by") order by x."fetched_at" desc, x."provider"), '[]'::jsonb)
  from "better_supabase"."enrichments" x
  where case
      when enrichments_of.subject_type = 'company' then x."company_id" = enrichments_of.subject_id
      when enrichments_of.subject_type = 'person' then x."person_id" = enrichments_of.subject_id
      else false
    end
    and coalesce(better_supabase.can('tenant', x."tenant_id", 'enrichment.read'), false)
$$;
revoke execute on function "better_supabase"."enrichments_of"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichments_of"(text, uuid) to authenticated, service_role;

-- The companies and people a provider has no result for, or one older than
-- stale_after, never enriched first, for a cron. A company needs a domain or
-- a website and a person an email to be looked up.
create or replace function "better_supabase"."enrichment_due"(provider text, max_count integer default null, stale_after interval default null, subject_type text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.target order by z.fetched_at nulls first, z.id), '[]'::jsonb)
  from (
    select * from (
      select jsonb_build_object('kind', 'company', 'organizationId', x."tenant_id", 'subjectType', 'company', 'subjectId', x."id", 'name', x."name", 'domain', x."domain", 'website', x."website") as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."companies" x
    left join "better_supabase"."enrichments" y on y."company_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'company')
      and (x."domain" is not null or x."website" is not null)
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
      union all
      select jsonb_build_object('kind', 'person', 'organizationId', x."tenant_id", 'subjectType', 'person', 'subjectId', x."id", 'name', x."name", 'email', x."email", 'phone', x."phone", 'title', x."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = x."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."people" x
    left join "better_supabase"."enrichments" y on y."person_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'person')
      and x."email" is not null
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
    ) w
    order by w.fetched_at nulls first, w.id
    limit least(greatest(coalesce(enrichment_due.max_count, 25), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) from public, anon, authenticated;
grant execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
create policy bsb_tenant_scope_select on "better_supabase"."enrichments" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("tenant_id" in (select better_supabase.tenant_ids_with('enrichment.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrichments" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
create policy bsb_tenant_scope_update on "better_supabase"."enrichments" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrichments" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:dcb04aea5c6dba2694f8efab01af3f4faf3ae190eaf85c4f2685d756fb3f5cb1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block enrichment@1 managed
-- @bsb-hash sha256:2cdcfa2d77fb96130950e3dc2dfcea68fce41bed78a2fa872da987acc38d6b31
-- Company and person data from an enrichment provider, such as a company's industry and size or a person's title: one result per provider, the empty columns a match fills, and a list of the records due for a cron.
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
    drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
    drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Enrichment: what a provider returned for a company or a person, one result
-- per provider, and the empty columns a match filled.
create table if not exists "better_supabase"."enrichments" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "company_id" uuid references "better_supabase"."companies" ("id") on delete cascade,
  "person_id" uuid references "better_supabase"."people" ("id") on delete cascade,
  "provider" text not null check ("provider" ~ '^[a-z][a-z0-9_-]{0,62}$'),
  "status" text not null check ("status" in ('matched', 'not_found')),
  "data" jsonb not null default '{}'::jsonb check (jsonb_typeof("data") = 'object'),
  "filled" text[] not null default '{}',
  "fetched_at" timestamptz not null default now(),
  "requested_by" uuid references auth.users (id) on delete set null,
  check (num_nonnulls("company_id", "person_id") = 1),
  constraint enrichments_company_provider_key unique ("company_id", "provider"),
  constraint enrichments_person_provider_key unique ("person_id", "provider")
);
create index if not exists enrichments_tenant_idx on "better_supabase"."enrichments" ("org_id", "fetched_at");
create index if not exists enrichments_requested_by_idx on "better_supabase"."enrichments" ("requested_by") where "requested_by" is not null;
alter table "better_supabase"."enrichments" enable row level security;
revoke all on "better_supabase"."enrichments" from anon, authenticated;
grant select on "better_supabase"."enrichments" to authenticated;
grant all on "better_supabase"."enrichments" to service_role;
drop policy if exists enrichments_read on "better_supabase"."enrichments";
create policy enrichments_read on "better_supabase"."enrichments"
  for select to authenticated
  using ("org_id" in (select better_supabase.tenant_ids_with('enrichment.read')));

-- What a provider looks up for one company or person: its name and the
-- domain, website or email it can be matched by. Needs enrichment.run.
create or replace function "better_supabase"."enrichment_target"(subject_type text, subject_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_target jsonb;
begin
  if enrichment_target.subject_type = 'company' then
    select jsonb_build_object('kind', 'company', 'organizationId', c."org_id", 'subjectType', 'company', 'subjectId', c."id", 'name', c."name", 'domain', c."domain", 'website', c."website") into v_target from "better_supabase"."companies" c
    where c."id" = enrichment_target.subject_id and c."archived_at" is null;
  elsif enrichment_target.subject_type = 'person' then
    select jsonb_build_object('kind', 'person', 'organizationId', p."org_id", 'subjectType', 'person', 'subjectId', p."id", 'name', p."name", 'email', p."email", 'phone', p."phone", 'title', p."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = p."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) into v_target from "better_supabase"."people" p
    where p."id" = enrichment_target.subject_id and p."archived_at" is null;
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_target is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', (v_target ->> 'organizationId')::uuid, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  return v_target;
end;
$$;
revoke execute on function "better_supabase"."enrichment_target"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichment_target"(text, uuid) to authenticated, service_role;

-- Stores what a provider returned for a company or person. result is
-- { status: 'matched' | 'not_found', data }. With fill, a match fills the
-- record's empty columns: a company's domain and website, a person's phone
-- and title. A domain another active company holds is left out. Returns the
-- stored result.
create or replace function "better_supabase"."record_enrichment"(subject_type text, subject_id uuid, provider text, result jsonb, fill boolean default true)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_company "better_supabase"."companies";
  v_person "better_supabase"."people";
  v_row "better_supabase"."enrichments";
  v_status text;
  v_data jsonb;
  v_filled text[] := '{}';
  v_domain text;
  v_website text;
  v_phone text;
  v_title text;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  if jsonb_typeof(result) is distinct from 'object' then
    raise exception 'result must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_status := result ->> 'status';
  if v_status is null or v_status not in ('matched', 'not_found') then
    raise exception 'result.status must be matched or not_found' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  v_data := case when v_status = 'matched' then coalesce(result -> 'data', '{}'::jsonb) else '{}'::jsonb end;
  if jsonb_typeof(v_data) is distinct from 'object' then
    raise exception 'result.data must be an object' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.provider is null or record_enrichment.provider !~ '^[a-z][a-z0-9_-]{0,62}$' then
    raise exception 'provider must be a lowercase name' using errcode = '22023', hint = 'ENRICHMENT_INVALID';
  end if;
  if record_enrichment.subject_type = 'company' then
    select * into v_company from "better_supabase"."companies" c
    where c."id" = record_enrichment.subject_id and c."archived_at" is null for update;
    v_tenant := v_company."org_id";
  elsif record_enrichment.subject_type = 'person' then
    select * into v_person from "better_supabase"."people" p
    where p."id" = record_enrichment.subject_id and p."archived_at" is null for update;
    v_tenant := v_person."org_id";
  else
    raise exception 'subject_type must be the company or the person type' using errcode = '22023', hint = 'ENRICHMENT_SUBJECT_UNKNOWN';
  end if;
  if v_tenant is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', v_tenant, 'enrichment.run'), false)) then
    raise exception 'No company or person you can enrich has this id' using errcode = 'P0002', hint = 'ENRICHMENT_NOT_FOUND';
  end if;
  if v_status = 'matched' and coalesce(record_enrichment.fill, true) then
    if v_company."id" is not null then
      v_domain := lower(nullif(trim(v_data ->> 'domain'), ''));
      if v_company."domain" is null and v_domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
        and not exists (
          select 1 from "better_supabase"."companies" c
          where c."org_id" = v_tenant and c."domain" = v_domain and c."archived_at" is null
        ) then
        v_filled := v_filled || 'domain'::text;
      else
        v_domain := null;
      end if;
      v_website := nullif(trim(v_data ->> 'website'), '');
      if v_company."website" is null and length(v_website) <= 2048 then
        v_filled := v_filled || 'website'::text;
      else
        v_website := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."companies" c set
          "domain" = coalesce(c."domain", v_domain),
          "website" = coalesce(c."website", v_website),
          "updated_at" = now()
        where c."id" = v_company."id";
      end if;
    else
      v_phone := nullif(trim(v_data ->> 'phone'), '');
      if v_person."phone" is null and length(v_phone) <= 50 then
        v_filled := v_filled || 'phone'::text;
      else
        v_phone := null;
      end if;
      v_title := nullif(trim(v_data ->> 'title'), '');
      if v_person."title" is null and length(v_title) <= 300 then
        v_filled := v_filled || 'title'::text;
      else
        v_title := null;
      end if;
      if cardinality(v_filled) > 0 then
        update "better_supabase"."people" p set
          "phone" = coalesce(p."phone", v_phone),
          "title" = coalesce(p."title", v_title),
          "updated_at" = now()
        where p."id" = v_person."id";
      end if;
    end if;
  end if;
  if v_company."id" is not null then
    insert into "better_supabase"."enrichments" ("org_id", "company_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_company_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  else
    insert into "better_supabase"."enrichments" ("org_id", "person_id", "provider", "status", "data", "filled", "requested_by")
    values (v_tenant, record_enrichment.subject_id, record_enrichment.provider, v_status, v_data, v_filled, auth.uid())
    on conflict on constraint enrichments_person_provider_key do update set
      "status" = excluded."status",
      "data" = excluded."data",
      "filled" = excluded."filled",
      "fetched_at" = now(),
      "requested_by" = excluded."requested_by"
    returning * into v_row;
  end if;
  null;
  return jsonb_build_object('id', v_row."id", 'organizationId', v_row."org_id", 'subjectType', case when v_row."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(v_row."company_id", v_row."person_id"), 'provider', v_row."provider", 'status', v_row."status", 'data', v_row."data", 'filled', to_jsonb(v_row."filled"), 'fetchedAt', v_row."fetched_at", 'requestedBy', v_row."requested_by");
end;
$$;
revoke execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) from public, anon;
grant execute on function "better_supabase"."record_enrichment"(text, uuid, text, jsonb, boolean) to authenticated, service_role;

-- A company's or person's stored results, one per provider, newest first.
create or replace function "better_supabase"."enrichments_of"(subject_type text, subject_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organizationId', x."org_id", 'subjectType', case when x."company_id" is not null then 'company' else 'person' end, 'subjectId', coalesce(x."company_id", x."person_id"), 'provider', x."provider", 'status', x."status", 'data', x."data", 'filled', to_jsonb(x."filled"), 'fetchedAt', x."fetched_at", 'requestedBy', x."requested_by") order by x."fetched_at" desc, x."provider"), '[]'::jsonb)
  from "better_supabase"."enrichments" x
  where case
      when enrichments_of.subject_type = 'company' then x."company_id" = enrichments_of.subject_id
      when enrichments_of.subject_type = 'person' then x."person_id" = enrichments_of.subject_id
      else false
    end
    and coalesce(better_supabase.can('tenant', x."org_id", 'enrichment.read'), false)
$$;
revoke execute on function "better_supabase"."enrichments_of"(text, uuid) from public, anon;
grant execute on function "better_supabase"."enrichments_of"(text, uuid) to authenticated, service_role;

-- The companies and people a provider has no result for, or one older than
-- stale_after, never enriched first, for a cron. A company needs a domain or
-- a website and a person an email to be looked up.
create or replace function "better_supabase"."enrichment_due"(provider text, max_count integer default null, stale_after interval default null, subject_type text default null)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(z.target order by z.fetched_at nulls first, z.id), '[]'::jsonb)
  from (
    select * from (
      select jsonb_build_object('kind', 'company', 'organizationId', x."org_id", 'subjectType', 'company', 'subjectId', x."id", 'name', x."name", 'domain', x."domain", 'website', x."website") as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."companies" x
    left join "better_supabase"."enrichments" y on y."company_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'company')
      and (x."domain" is not null or x."website" is not null)
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
      union all
      select jsonb_build_object('kind', 'person', 'organizationId', x."org_id", 'subjectType', 'person', 'subjectId', x."id", 'name', x."name", 'email', x."email", 'phone', x."phone", 'title', x."title", 'companyDomain', (
    select c."domain" from "better_supabase"."company_people" l
    join "better_supabase"."companies" c on c."id" = l."company_id"
    where l."person_id" = x."id" and c."archived_at" is null
    order by l."is_primary" desc, l."created_at"
    limit 1)) as target, y."fetched_at" as fetched_at, x."id" as id
    from "better_supabase"."people" x
    left join "better_supabase"."enrichments" y on y."person_id" = x."id" and y."provider" = enrichment_due.provider
    where x."archived_at" is null
      and (enrichment_due.subject_type is null or enrichment_due.subject_type = 'person')
      and x."email" is not null
      and (y."fetched_at" is null or y."fetched_at" < now() - coalesce(enrichment_due.stale_after, interval '30 days'))
    ) w
    order by w.fetched_at nulls first, w.id
    limit least(greatest(coalesce(enrichment_due.max_count, 25), 1), 500)
  ) z
$$;
revoke execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) from public, anon, authenticated;
grant execute on function "better_supabase"."enrichment_due"(text, integer, interval, text) to service_role;

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
drop policy if exists bsb_tenant_scope on "better_supabase"."enrichments";
drop policy if exists bsb_tenant_scope_select on "better_supabase"."enrichments";
create policy bsb_tenant_scope_select on "better_supabase"."enrichments" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("org_id" in (select better_supabase.tenant_ids_with('enrichment.read')))
  );
drop policy if exists bsb_tenant_scope_insert on "better_supabase"."enrichments";
create policy bsb_tenant_scope_insert on "better_supabase"."enrichments" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "better_supabase"."enrichments";
create policy bsb_tenant_scope_update on "better_supabase"."enrichments" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "better_supabase"."enrichments";
create policy bsb_tenant_scope_delete on "better_supabase"."enrichments" as restrictive
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
revoke all on better_supabase.blocks from anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_135_enrichment.sql
-- better-supabase module: enrichment
-- @bsb-block-data enrichment
-- @bsb-hash sha256:dcb04aea5c6dba2694f8efab01af3f4faf3ae190eaf85c4f2685d756fb3f5cb1
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('enrichment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
