-- ==== alone: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@2 managed
-- @bsb-hash sha256:5387ddcdbe633e9a92c8dd3a3295e749b7ed3d317c422bfeea21b06e6ba79d2c
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."memberships";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;

create table if not exists "better_supabase"."memberships" (
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id")
);
create index if not exists memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."memberships";
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column if not exists "last_used_at" timestamptz;
alter table "better_supabase"."memberships" add column if not exists "disabled_at" timestamptz;
alter table "better_supabase"."memberships" drop constraint if exists memberships_role_check;
alter table "better_supabase"."memberships"
  add constraint memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "better_supabase"."memberships" enable row level security;
grant select on "better_supabase"."memberships" to authenticated;
grant all on "better_supabase"."memberships" to service_role;

-- Disabled tenants and users get no permissions and no membership claims
-- (blocks.permissions.disabled; with the managed organizations module, its
-- disabled_at and deleted_at columns).
create or replace function better_supabase.tenant_disabled(tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

create or replace function better_supabase.user_disabled(user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

revoke execute on function better_supabase.tenant_disabled(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.user_disabled(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_disabled(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.user_disabled(uuid) to service_role, supabase_auth_admin;

-- The tenant the server resolved (the better_supabase.tenant setting over Postgres,
-- the x-bsb-tenant header over the Data API), then the `tenant_id` claim.
-- A tenant the caller isn't a member of counts as none.
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
  )::uuid
$$;
revoke execute on function better_supabase.current_tenant_id() from public;
grant execute on function better_supabase.current_tenant_id() to anon, authenticated, service_role, supabase_auth_admin;

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
-- has_organization_role(organization) answers for one organization, in functions and checks.
-- Prefer the access contract (better_supabase.can, tenant_ids_with) for
-- permission checks; these answer by role name.
create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select m."organization_id"
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and (member_organization_ids.roles is null or m."role" = any (member_organization_ids.roles))
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

create or replace function better_supabase.has_organization_role(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from "better_supabase"."memberships" m
    where m."organization_id" = has_organization_role.organization
      and m."user_id" = auth.uid()
      and (has_organization_role.roles is null or m."role" = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
  )
$$;

-- The role of a user in a tenant, or null when they aren't a member.
create or replace function better_supabase.organization_member_role(organization uuid, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m."role" from "better_supabase"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member and m."disabled_at" is null
$$;

drop policy if exists bsb_memberships_read on "better_supabase"."memberships";
create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public, anon;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public, anon;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to authenticated, service_role;
grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;

-- The memberships claim. `claimFormat: 'array'` (the default) is
-- [{ scope, id, roles }]; `'map'` is { [tenant id]: role }. When an
-- authorization provider's hook writes this claim, use its hook instead.
-- Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
-- Disabled users and tenants (blocks.permissions.disabled) are left out.
create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', 'tenant',
      'id', m."organization_id",
      'roles', jsonb_build_array(m."role")
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."memberships";
create policy bsb_tenant_scope on "better_supabase"."memberships" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0bf566194ea1eda38d7475a6cb148c1899e3ee0dfbae1e37c0de887381adeb28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@2 managed
-- @bsb-hash sha256:62cfba67261f2e80b82318415cd3fcaac3ead2f09baae2a5d9a33c88759bf4e2
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."memberships";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;
set check_function_bodies = off;

create table if not exists "better_supabase"."memberships" (
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id")
);
create index if not exists memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."memberships";
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column if not exists "last_used_at" timestamptz;
alter table "better_supabase"."memberships" add column if not exists "disabled_at" timestamptz;
alter table "better_supabase"."memberships" drop constraint if exists memberships_role_check;
alter table "better_supabase"."memberships"
  add constraint memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "better_supabase"."memberships" enable row level security;
grant select on "better_supabase"."memberships" to authenticated;
grant all on "better_supabase"."memberships" to service_role;


-- The tenant the server resolved (the better_supabase.tenant setting over Postgres,
-- the x-bsb-tenant header over the Data API), then the `tenant_id` claim.
-- A tenant the caller isn't a member of counts as none.
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
  )::uuid
$$;
revoke execute on function better_supabase.current_tenant_id() from public;
grant execute on function better_supabase.current_tenant_id() to anon, authenticated, service_role, supabase_auth_admin;

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
-- has_organization_role(organization) answers for one organization, in functions and checks.
-- Prefer the access contract (better_supabase.can, tenant_ids_with) for
-- permission checks; these answer by role name.
create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select m."organization_id"
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and (member_organization_ids.roles is null or m."role" = any (member_organization_ids.roles))
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

create or replace function better_supabase.has_organization_role(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from "better_supabase"."memberships" m
    where m."organization_id" = has_organization_role.organization
      and m."user_id" = auth.uid()
      and (has_organization_role.roles is null or m."role" = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
  )
$$;

-- The role of a user in a tenant, or null when they aren't a member.
create or replace function better_supabase.organization_member_role(organization uuid, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m."role" from "better_supabase"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member and m."disabled_at" is null
$$;

drop policy if exists bsb_memberships_read on "better_supabase"."memberships";
create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public, anon;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public, anon;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to authenticated, service_role;
grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;

-- The memberships claim. `claimFormat: 'array'` (the default) is
-- [{ scope, id, roles }]; `'map'` is { [tenant id]: role }. When an
-- authorization provider's hook writes this claim, use its hook instead.
-- Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
-- Disabled users and tenants (blocks.permissions.disabled) are left out.
create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', 'tenant',
      'id', m."organization_id",
      'roles', jsonb_build_array(m."role")
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;
reset check_function_bodies;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."memberships";
create policy bsb_tenant_scope on "better_supabase"."memberships" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0bf566194ea1eda38d7475a6cb148c1899e3ee0dfbae1e37c0de887381adeb28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@2 managed
-- @bsb-hash sha256:ecdcb3f24e6a455bd7c703bedc3cfa258af3105f100bbb9990bdf51bfd285113
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "app_private"."memberships";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;

create table if not exists "app_private"."memberships" (
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id")
);
create index if not exists memberships_user_idx on "app_private"."memberships" ("user_id");
alter table "app_private"."memberships" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "app_private"."memberships";
create trigger bsb_updated_at before update on "app_private"."memberships"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "app_private"."memberships" add column if not exists "last_used_at" timestamptz;
alter table "app_private"."memberships" add column if not exists "disabled_at" timestamptz;
alter table "app_private"."memberships" drop constraint if exists memberships_role_check;
alter table "app_private"."memberships"
  add constraint memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "app_private"."memberships" enable row level security;
grant select on "app_private"."memberships" to authenticated;
grant all on "app_private"."memberships" to service_role;

-- Disabled tenants and users get no permissions and no membership claims
-- (blocks.permissions.disabled; with the managed organizations module, its
-- disabled_at and deleted_at columns).
create or replace function better_supabase.tenant_disabled(tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

create or replace function better_supabase.user_disabled(user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

revoke execute on function better_supabase.tenant_disabled(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.user_disabled(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_disabled(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.user_disabled(uuid) to service_role, supabase_auth_admin;

-- The tenant the server resolved (the better_supabase.tenant setting over Postgres,
-- the x-bsb-tenant header over the Data API), then the `tenant_id` claim.
-- A tenant the caller isn't a member of counts as none.
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select m."organization_id"::text from "app_private"."memberships" m where m."organization_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "app_private"."memberships" m where m."organization_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "app_private"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
  )::uuid
$$;
revoke execute on function better_supabase.current_tenant_id() from public;
grant execute on function better_supabase.current_tenant_id() to anon, authenticated, service_role, supabase_auth_admin;

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
-- has_organization_role(organization) answers for one organization, in functions and checks.
-- Prefer the access contract (better_supabase.can, tenant_ids_with) for
-- permission checks; these answer by role name.
create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select m."organization_id"
  from "app_private"."memberships" m
  where m."user_id" = (select auth.uid())
    and (member_organization_ids.roles is null or m."role" = any (member_organization_ids.roles))
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

create or replace function better_supabase.has_organization_role(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from "app_private"."memberships" m
    where m."organization_id" = has_organization_role.organization
      and m."user_id" = auth.uid()
      and (has_organization_role.roles is null or m."role" = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
  )
$$;

-- The role of a user in a tenant, or null when they aren't a member.
create or replace function better_supabase.organization_member_role(organization uuid, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m."role" from "app_private"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member and m."disabled_at" is null
$$;

drop policy if exists bsb_memberships_read on "app_private"."memberships";
create policy bsb_memberships_read on "app_private"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public, anon;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public, anon;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to authenticated, service_role;
grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;

-- The memberships claim. `claimFormat: 'array'` (the default) is
-- [{ scope, id, roles }]; `'map'` is { [tenant id]: role }. When an
-- authorization provider's hook writes this claim, use its hook instead.
-- Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
-- Disabled users and tenants (blocks.permissions.disabled) are left out.
create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', 'tenant',
      'id', m."organization_id",
      'roles', jsonb_build_array(m."role")
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "app_private"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "app_private"."memberships";
create policy bsb_tenant_scope on "app_private"."memberships" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0bf566194ea1eda38d7475a6cb148c1899e3ee0dfbae1e37c0de887381adeb28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@2 managed
-- @bsb-hash sha256:a7265596feb4119e0a7554c8438b340e64f35fbe4c6716b90060be68ef54288c
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."memberships";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;

create table if not exists "better_supabase"."memberships" (
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id")
);
create index if not exists memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."memberships";
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column if not exists "last_used_at" timestamptz;
alter table "better_supabase"."memberships" add column if not exists "disabled_at" timestamptz;
alter table "better_supabase"."memberships" drop constraint if exists memberships_role_check;
alter table "better_supabase"."memberships"
  add constraint memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

alter table "better_supabase"."memberships" enable row level security;
grant select on "better_supabase"."memberships" to authenticated;
grant all on "better_supabase"."memberships" to service_role;

-- Disabled tenants and users get no permissions and no membership claims
-- (blocks.permissions.disabled; with the managed organizations module, its
-- disabled_at and deleted_at columns).
create or replace function better_supabase.tenant_disabled(tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

create or replace function better_supabase.user_disabled(user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

revoke execute on function better_supabase.tenant_disabled(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.user_disabled(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_disabled(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.user_disabled(uuid) to service_role, supabase_auth_admin;

-- The tenant the server resolved (the better_supabase.tenant setting over Postgres,
-- the x-bsb-tenant header over the Data API), then the `tenant_id` claim.
-- A tenant the caller isn't a member of counts as none.
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
  )::uuid
$$;
revoke execute on function better_supabase.current_tenant_id() from public;
grant execute on function better_supabase.current_tenant_id() to anon, authenticated, service_role, supabase_auth_admin;

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
-- has_organization_role(organization) answers for one organization, in functions and checks.
-- Prefer the access contract (better_supabase.can, tenant_ids_with) for
-- permission checks; these answer by role name.
create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select m."organization_id"
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and (member_organization_ids.roles is null or m."role" = any (member_organization_ids.roles))
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

create or replace function better_supabase.has_organization_role(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from "better_supabase"."memberships" m
    where m."organization_id" = has_organization_role.organization
      and m."user_id" = auth.uid()
      and (has_organization_role.roles is null or m."role" = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
  )
$$;

-- The role of a user in a tenant, or null when they aren't a member.
create or replace function better_supabase.organization_member_role(organization uuid, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m."role" from "better_supabase"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member and m."disabled_at" is null
$$;

drop policy if exists bsb_memberships_read on "better_supabase"."memberships";
create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public, anon;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public, anon;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to authenticated, service_role;
grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;

-- The memberships claim. `claimFormat: 'array'` (the default) is
-- [{ scope, id, roles }]; `'map'` is { [tenant id]: role }. When an
-- authorization provider's hook writes this claim, use its hook instead.
-- Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
-- Disabled users and tenants (blocks.permissions.disabled) are left out.
create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', 'tenant',
      'id', m."organization_id",
      'roles', jsonb_build_array(m."role")
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id") and m."disabled_at" is null
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."memberships";
create policy bsb_tenant_scope on "better_supabase"."memberships" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

-- blocks.memberships.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."tenant_disabled"(tenant uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."tenant_disabled"($1) $$;
revoke execute on function "api"."tenant_disabled"(uuid) from public, anon, authenticated;
grant execute on function "api"."tenant_disabled"(uuid) to service_role;

create or replace function "api"."user_disabled"(user_id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."user_disabled"($1) $$;
revoke execute on function "api"."user_disabled"(uuid) from public, anon, authenticated;
grant execute on function "api"."user_disabled"(uuid) to service_role;

create or replace function "api"."current_tenant_id"()
returns uuid
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."current_tenant_id"() $$;
revoke execute on function "api"."current_tenant_id"() from public;
grant execute on function "api"."current_tenant_id"() to anon, authenticated, service_role;

create or replace function "api"."member_organization_ids"(roles text[] default null)
returns setof uuid
language sql
security invoker
set search_path = ''
as $$ select * from "better_supabase"."member_organization_ids"($1) $$;
revoke execute on function "api"."member_organization_ids"(text[]) from public, anon;
grant execute on function "api"."member_organization_ids"(text[]) to authenticated, service_role;

create or replace function "api"."has_organization_role"(organization uuid, roles text[] default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."has_organization_role"($1, $2) $$;
revoke execute on function "api"."has_organization_role"(uuid, text[]) from public, anon;
grant execute on function "api"."has_organization_role"(uuid, text[]) to authenticated, service_role;

create or replace function "api"."organization_member_role"(organization uuid, member uuid)
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."organization_member_role"($1, $2) $$;
revoke execute on function "api"."organization_member_role"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."organization_member_role"(uuid, uuid) to service_role;

create or replace function "api"."membership_claims"(user_id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."membership_claims"($1) $$;
revoke execute on function "api"."membership_claims"(uuid) from public, anon, authenticated;
grant execute on function "api"."membership_claims"(uuid) to service_role;

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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0bf566194ea1eda38d7475a6cb148c1899e3ee0dfbae1e37c0de887381adeb28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@2 managed
-- @bsb-hash sha256:a17540dac3c698f7c5886cd99880d58dcf028cf569648c45266103711791518b
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- The tenant scope policies call the module's functions, so they go before
-- the module drops or replaces one and come back at the end.
do $$
begin
  begin
    drop policy if exists bsb_tenant_scope on "better_supabase"."memberships";
  exception when undefined_table or invalid_schema_name then null;
  end;
end $$;

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;

-- better_supabase.memberships is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."memberships" add column if not exists "organization_id" uuid;
alter table "better_supabase"."memberships" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."memberships" add column if not exists "role" text not null default 'member';
alter table "better_supabase"."memberships" add column if not exists "created_at" timestamptz not null default now();
create index if not exists memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column if not exists "updated_at" timestamptz not null default now();
drop trigger if exists bsb_updated_at on "better_supabase"."memberships";
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column if not exists "last_used_at" timestamptz;

alter table "better_supabase"."memberships" enable row level security;
grant select on "better_supabase"."memberships" to authenticated;
grant all on "better_supabase"."memberships" to service_role;

drop trigger if exists "bsb_role_scope" on "better_supabase"."memberships";
drop function if exists "better_supabase"."membership_role_scope"();

-- Disabled tenants and users get no permissions and no membership claims
-- (blocks.permissions.disabled; with the managed organizations module, its
-- disabled_at and deleted_at columns).
create or replace function better_supabase.tenant_disabled(tenant uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

create or replace function better_supabase.user_disabled(user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

revoke execute on function better_supabase.tenant_disabled(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.user_disabled(uuid) from public, anon, authenticated;
grant execute on function better_supabase.tenant_disabled(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.user_disabled(uuid) to service_role, supabase_auth_admin;

-- The tenant the server resolved (the better_supabase.tenant setting over Postgres,
-- the x-bsb-tenant header over the Data API), then the `tenant_id` claim.
-- A tenant the caller isn't a member of counts as none.
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "better_supabase"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
  )::uuid
$$;
revoke execute on function better_supabase.current_tenant_id() from public;
grant execute on function better_supabase.current_tenant_id() to anon, authenticated, service_role, supabase_auth_admin;

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
-- has_organization_role(organization) answers for one organization, in functions and checks.
-- Prefer the access contract (better_supabase.can, tenant_ids_with) for
-- permission checks; these answer by role name.
create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select m."organization_id"
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and (member_organization_ids.roles is null or m."role" = any (member_organization_ids.roles))
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."organization_id")
$$;

create or replace function better_supabase.has_organization_role(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from "better_supabase"."memberships" m
    where m."organization_id" = has_organization_role.organization
      and m."user_id" = auth.uid()
      and (has_organization_role.roles is null or m."role" = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."organization_id")
  )
$$;

-- The role of a user in a tenant, or null when they aren't a member.
create or replace function better_supabase.organization_member_role(organization uuid, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m."role" from "better_supabase"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member
$$;

drop policy if exists bsb_memberships_read on "better_supabase"."memberships";
create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public, anon;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public, anon;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to authenticated, service_role;
grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;

-- The memberships claim. `claimFormat: 'array'` (the default) is
-- [{ scope, id, roles }]; `'map'` is { [tenant id]: role }. When an
-- authorization provider's hook writes this claim, use its hook instead.
-- Otherwise call it from your custom access token hook:
--   return jsonb_set(event, '{claims,memberships}',
--     better_supabase.membership_claims((event ->> 'user_id')::uuid));
-- Disabled users and tenants (blocks.permissions.disabled) are left out.
create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'scope', 'tenant',
      'id', m."organization_id",
      'roles', jsonb_build_array(m."role")
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id")
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
drop policy if exists bsb_tenant_scope on "better_supabase"."memberships";
create policy bsb_tenant_scope on "better_supabase"."memberships" as restrictive
  for all to authenticated
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  )
  with check ("organization_id" in (select better_supabase.member_organization_ids()));

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

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0bf566194ea1eda38d7475a6cb148c1899e3ee0dfbae1e37c0de887381adeb28
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
