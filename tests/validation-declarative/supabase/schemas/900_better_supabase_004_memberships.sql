-- better-supabase module: memberships
-- @bsb-block memberships@3 managed
-- @bsb-hash sha256:954391e1c473f40dd386e9813d69332f1dab6713e30753483eb2c4d7e806c854
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.memberships.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

grant usage on schema better_supabase to supabase_auth_admin;
set check_function_bodies = off;

-- public.memberships is the app's table, and it has every column this block needs.
-- public.memberships already has an index on (user_id), so this block adds none.
alter table "public"."memberships" add column if not exists "updated_at" timestamptz not null default now();
create trigger bsb_updated_at before update on "public"."memberships"
  for each row
  execute function better_supabase.set_updated_at('updated_at');
alter table "public"."memberships" add column if not exists "last_used_at" timestamptz;

alter table "public"."memberships" enable row level security;
grant select on "public"."memberships" to authenticated;
grant all on "public"."memberships" to service_role;


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
    (select m."organization_id"::text from "public"."memberships" m where m."organization_id"::text = nullif(current_setting('better_supabase.tenant', true), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "public"."memberships" m where m."organization_id"::text = nullif(current_setting('request.headers', true)::jsonb ->> 'x-bsb-tenant', '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "public"."memberships" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1)
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
  from "public"."memberships" m
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
    from "public"."memberships" m
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
  select m."role" from "public"."memberships" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member
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
  from "public"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member
$$;
revoke execute on function better_supabase.organization_member_roles(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.organization_member_roles(uuid, uuid) to service_role;

create policy bsb_memberships_read on "public"."memberships"
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
  from "public"."memberships" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id")
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;
reset check_function_bodies;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "public"."memberships" as restrictive
  for select to public
  using (
    "organization_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()))
  );
create policy bsb_tenant_scope_insert on "public"."memberships" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "public"."memberships" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "public"."memberships" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
