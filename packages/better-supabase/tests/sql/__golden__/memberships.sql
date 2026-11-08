-- ==== alone: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@3 managed
-- @bsb-hash sha256:5db915ac66a7b8c291295718eec59b5ecc81c74fe293b995cd5663251d021a00
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

grant usage on schema better_supabase to supabase_auth_admin;

create table "better_supabase"."memberships" (
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id")
);
create index memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column "last_used_at" timestamptz;
alter table "better_supabase"."memberships" add column "disabled_at" timestamptz;
alter table "better_supabase"."memberships"
  add constraint bsb_memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

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

-- The roles of a user in a tenant, highest-ranked first, or null when they
-- aren't a member.
create or replace function better_supabase.organization_member_roles(organization uuid, member uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array[m."role"]::text[]
  from "better_supabase"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member and m."disabled_at" is null
$$;
revoke execute on function better_supabase.organization_member_roles(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.organization_member_roles(uuid, uuid) to service_role;

create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to anon, authenticated, service_role;
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
create policy bsb_tenant_scope_select on "better_supabase"."memberships" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."memberships" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."memberships" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."memberships" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0820ad92b94361500e57ffda4d2de42e2213687cbbe32e5f1981b88983f689fa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@3 managed
-- @bsb-hash sha256:3e787b5daf84c533f62d2b73b621f41f8f751ef7996e88657f262b8a5617e552
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

grant usage on schema better_supabase to supabase_auth_admin;
set check_function_bodies = off;

create table "better_supabase"."memberships" (
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id")
);
create index memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column "last_used_at" timestamptz;
alter table "better_supabase"."memberships" add column "disabled_at" timestamptz;
alter table "better_supabase"."memberships"
  add constraint bsb_memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

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

-- The roles of a user in a tenant, highest-ranked first, or null when they
-- aren't a member.
create or replace function better_supabase.organization_member_roles(organization uuid, member uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array[m."role"]::text[]
  from "better_supabase"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member and m."disabled_at" is null
$$;
revoke execute on function better_supabase.organization_member_roles(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.organization_member_roles(uuid, uuid) to service_role;

create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to anon, authenticated, service_role;
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
create policy bsb_tenant_scope_select on "better_supabase"."memberships" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."memberships" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."memberships" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."memberships" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0820ad92b94361500e57ffda4d2de42e2213687cbbe32e5f1981b88983f689fa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@3 managed
-- @bsb-hash sha256:f3ebedb0a04fe9be230a5c82dfc17fa27504c6ae9fbe51c70fbce0c1894e2f07
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
grant usage on schema better_supabase to supabase_auth_admin;

create table "app_private"."memberships" (
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id")
);
create index memberships_user_idx on "app_private"."memberships" ("user_id");
alter table "app_private"."memberships" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "app_private"."memberships"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "app_private"."memberships" add column "last_used_at" timestamptz;
alter table "app_private"."memberships" add column "disabled_at" timestamptz;
alter table "app_private"."memberships"
  add constraint bsb_memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

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

-- The roles of a user in a tenant, highest-ranked first, or null when they
-- aren't a member.
create or replace function better_supabase.organization_member_roles(organization uuid, member uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array[m."role"]::text[]
  from "app_private"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member and m."disabled_at" is null
$$;
revoke execute on function better_supabase.organization_member_roles(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.organization_member_roles(uuid, uuid) to service_role;

create policy bsb_memberships_read on "app_private"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to anon, authenticated, service_role;
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
create policy bsb_tenant_scope_select on "app_private"."memberships" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  );
create policy bsb_tenant_scope_insert on "app_private"."memberships" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."memberships" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."memberships" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0820ad92b94361500e57ffda4d2de42e2213687cbbe32e5f1981b88983f689fa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@3 managed
-- @bsb-hash sha256:0d69bdefe9790935e6fbd45871c1e00e4cc1b8526ff259418c6ba79c5ce0a00b
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

grant usage on schema better_supabase to supabase_auth_admin;

create table "better_supabase"."memberships" (
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id")
);
create index memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column "last_used_at" timestamptz;
alter table "better_supabase"."memberships" add column "disabled_at" timestamptz;
alter table "better_supabase"."memberships"
  add constraint bsb_memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

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

-- The roles of a user in a tenant, highest-ranked first, or null when they
-- aren't a member.
create or replace function better_supabase.organization_member_roles(organization uuid, member uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array[m."role"]::text[]
  from "better_supabase"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member and m."disabled_at" is null
$$;
revoke execute on function better_supabase.organization_member_roles(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.organization_member_roles(uuid, uuid) to service_role;

create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to anon, authenticated, service_role;
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
create policy bsb_tenant_scope_select on "better_supabase"."memberships" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."memberships" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."memberships" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."memberships" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

-- blocks.memberships.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."tenant_disabled"(tenant uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."tenant_disabled"($1) $$;
revoke execute on function "api"."tenant_disabled"(uuid) from public, anon, authenticated;
grant execute on function "api"."tenant_disabled"(uuid) to service_role;

create or replace function "api"."user_disabled"(user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."user_disabled"($1) $$;
revoke execute on function "api"."user_disabled"(uuid) from public, anon, authenticated;
grant execute on function "api"."user_disabled"(uuid) to service_role;

create or replace function "api"."current_tenant_id"()
returns uuid
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."current_tenant_id"() $$;
revoke execute on function "api"."current_tenant_id"() from public;
grant execute on function "api"."current_tenant_id"() to anon, authenticated, service_role;

create or replace function "api"."organization_member_roles"(organization uuid, member uuid)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."organization_member_roles"($1, $2) $$;
revoke execute on function "api"."organization_member_roles"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."organization_member_roles"(uuid, uuid) to service_role;

create or replace function "api"."member_organization_ids"(roles text[] default null)
returns setof uuid
language sql
stable
security invoker
set search_path = ''
as $$ select * from "better_supabase"."member_organization_ids"($1) $$;
revoke execute on function "api"."member_organization_ids"(text[]) from public;
grant execute on function "api"."member_organization_ids"(text[]) to anon, authenticated, service_role;

create or replace function "api"."has_organization_role"(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."has_organization_role"($1, $2) $$;
revoke execute on function "api"."has_organization_role"(uuid, text[]) from public;
grant execute on function "api"."has_organization_role"(uuid, text[]) to anon, authenticated, service_role;

create or replace function "api"."organization_member_role"(organization uuid, member uuid)
returns text
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."organization_member_role"($1, $2) $$;
revoke execute on function "api"."organization_member_role"(uuid, uuid) from public, anon, authenticated;
grant execute on function "api"."organization_member_role"(uuid, uuid) to service_role;

create or replace function "api"."membership_claims"(user_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."membership_claims"($1) $$;
revoke execute on function "api"."membership_claims"(uuid) from public, anon, authenticated;
grant execute on function "api"."membership_claims"(uuid) to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0820ad92b94361500e57ffda4d2de42e2213687cbbe32e5f1981b88983f689fa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@3 managed
-- @bsb-hash sha256:30ab843cb667ee7acc4faf03455a47e2d71affac8269a6c6a195cf7e1ddc0341
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

grant usage on schema better_supabase to supabase_auth_admin;

-- better_supabase.memberships is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."memberships" add column if not exists "organization_id" uuid;
alter table "better_supabase"."memberships" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."memberships" add column if not exists "role" text not null default 'member';
alter table "better_supabase"."memberships" add column if not exists "created_at" timestamptz not null default now();
create index if not exists memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column if not exists "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column if not exists "last_used_at" timestamptz;

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

-- The roles of a user in a tenant, highest-ranked first, or null when they
-- aren't a member.
create or replace function better_supabase.organization_member_roles(organization uuid, member uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array[m."role"]::text[]
  from "better_supabase"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member
$$;
revoke execute on function better_supabase.organization_member_roles(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.organization_member_roles(uuid, uuid) to service_role;

create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to anon, authenticated, service_role;
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
create policy bsb_tenant_scope_select on "better_supabase"."memberships" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."memberships" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."memberships" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."memberships" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0820ad92b94361500e57ffda4d2de42e2213687cbbe32e5f1981b88983f689fa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block memberships@3 managed
-- @bsb-hash sha256:f6b7df028430efcb1315da0441a9018e87c75cca8f15f609455383397462df26
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

grant usage on schema better_supabase to supabase_auth_admin;
set check_function_bodies = off;

create table "better_supabase"."memberships" (
  "org_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "role" text not null default 'member',
  "created_at" timestamptz not null default now(),
  primary key ("org_id", "user_id")
);
create index memberships_user_idx on "better_supabase"."memberships" ("user_id");
alter table "better_supabase"."memberships" add column "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "better_supabase"."memberships"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "better_supabase"."memberships" add column "last_used_at" timestamptz;
alter table "better_supabase"."memberships" add column "disabled_at" timestamptz;
alter table "better_supabase"."memberships"
  add constraint bsb_memberships_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));

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
    (select m."org_id"::text from "better_supabase"."memberships" m where m."org_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."org_id"::text from "better_supabase"."memberships" m where m."org_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."org_id"::text from "better_supabase"."memberships" m where m."org_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
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
  select m."org_id"
  from "better_supabase"."memberships" m
  where m."user_id" = (select auth.uid())
    and (member_organization_ids.roles is null or m."role" = any (member_organization_ids.roles))
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."org_id") and m."disabled_at" is null
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
    where m."org_id" = has_organization_role.organization
      and m."user_id" = auth.uid()
      and (has_organization_role.roles is null or m."role" = any (has_organization_role.roles))
      and not better_supabase.user_disabled(m."user_id")
      and not better_supabase.tenant_disabled(m."org_id") and m."disabled_at" is null
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
  select m."role" from "better_supabase"."memberships" m where m."org_id" = organization_member_role.organization and m."user_id" = organization_member_role.member and m."disabled_at" is null
$$;

-- The roles of a user in a tenant, highest-ranked first, or null when they
-- aren't a member.
create or replace function better_supabase.organization_member_roles(organization uuid, member uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select array[m."role"]::text[]
  from "better_supabase"."memberships" m where m."org_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member and m."disabled_at" is null
$$;
revoke execute on function better_supabase.organization_member_roles(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.organization_member_roles(uuid, uuid) to service_role;

create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to anon, authenticated, service_role;
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
      'id', m."org_id",
      'roles', jsonb_build_array(m."role")
    ) order by m."created_at", m."org_id"), '[]'::jsonb)
  from "better_supabase"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."org_id") and m."disabled_at" is null
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;
reset check_function_bodies;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."memberships" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.member_organization_ids()))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."memberships" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."memberships" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."memberships" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_004_memberships.sql
-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:0820ad92b94361500e57ffda4d2de42e2213687cbbe32e5f1981b88983f689fa
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
