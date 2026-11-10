-- better-supabase module: memberships
-- @bsb-block memberships@3 managed
-- @bsb-hash sha256:e156ec30b04394f2fc9e01c29131ae26c2bf483a272129656281d2ad0089d16d
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

-- blocks.memberships.options.roles.many: every membership holds a set of
-- roles. "better_supabase"."memberships"."role" keeps the highest-ranked one (the order of
-- blocks.permissions.roles), so readers of the single role keep working.
create table "better_supabase"."membership_roles" (
  "organization_id" uuid not null,
  "user_id" uuid not null,
  "role" text not null,
  "created_at" timestamptz not null default now(),
  primary key ("organization_id", "user_id", "role"),
  foreign key ("organization_id", "user_id") references "better_supabase"."memberships" ("organization_id", "user_id") on delete cascade
);
create index membership_roles_user_idx on "better_supabase"."membership_roles" ("user_id");
alter table "better_supabase"."membership_roles"
  add constraint bsb_membership_roles_role_check check ("role" in ('owner', 'admin', 'member', 'viewer'));
alter table "better_supabase"."membership_roles" enable row level security;
grant select on "better_supabase"."membership_roles" to authenticated;
grant all on "better_supabase"."membership_roles" to service_role;

-- Writing "role" directly (update_member_role, a client policy, the service
-- role) swaps the previous primary role for the new one and keeps the written
-- one primary. The member's other roles, custom ones included, stay in the set.
create or replace function "better_supabase"."membership_roles_from_role"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."role" is null or current_setting('better_supabase.membership_role_sync', true) = 'on' then
    return null;
  end if;
  perform set_config('better_supabase.membership_role_sync', 'on', true);
  if tg_op = 'UPDATE' and old."role" is not null and old."role"::text <> new."role"::text then
    delete from "better_supabase"."membership_roles" r where r."organization_id" = new."organization_id" and r."user_id" = new."user_id" and r."role" = old."role"::text;
  end if;
  insert into "better_supabase"."membership_roles" ("organization_id", "user_id", "role") values (new."organization_id", new."user_id", new."role"::text)
  on conflict do nothing;
  perform set_config('better_supabase.membership_role_sync', '', true);
  return null;
end;
$$;
revoke execute on function "better_supabase"."membership_roles_from_role"() from public, anon, authenticated;
create trigger "bsb_membership_roles" after insert or update of "role" on "better_supabase"."memberships"
  for each row execute function "better_supabase"."membership_roles_from_role"();

-- Adding or removing a role moves "role" to the highest-ranked one left. An
-- emptied set leaves it alone; remove_member_role refuses the last role.
create or replace function "better_supabase"."membership_role_from_roles"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := coalesce(new."organization_id", old."organization_id");
  v_user uuid := coalesce(new."user_id", old."user_id");
  v_primary text;
begin
  if current_setting('better_supabase.membership_role_sync', true) = 'on' then
    return null;
  end if;
  select r."role" into v_primary from "better_supabase"."membership_roles" r
  where r."organization_id" = v_tenant and r."user_id" = v_user
  order by array_position(array['owner', 'admin', 'member', 'viewer']::text[], r."role"), r."role"
  limit 1;
  if v_primary is not null then
    perform set_config('better_supabase.membership_role_sync', 'on', true);
    update "better_supabase"."memberships" m set "role" = v_primary
    where m."organization_id" = v_tenant and m."user_id" = v_user and m."role"::text is distinct from v_primary;
    perform set_config('better_supabase.membership_role_sync', '', true);
  end if;
  return null;
end;
$$;
revoke execute on function "better_supabase"."membership_role_from_roles"() from public, anon, authenticated;
create trigger "bsb_membership_role_primary" after insert or delete on "better_supabase"."membership_roles"
  for each row execute function "better_supabase"."membership_role_from_roles"();


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
    and (member_organization_ids.roles is null or exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and mr."role" = any (member_organization_ids.roles)))
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
      and (has_organization_role.roles is null or exists (select 1 from "better_supabase"."membership_roles" mr where mr."organization_id" = m."organization_id" and mr."user_id" = m."user_id" and mr."role" = any (has_organization_role.roles)))
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
  select (
    select array_agg(r."role" order by array_position(array['owner', 'admin', 'member', 'viewer']::text[], r."role"), r."role")
    from "better_supabase"."membership_roles" r where r."organization_id" = m."organization_id" and r."user_id" = m."user_id"
  )
  from "better_supabase"."memberships" m where m."organization_id" = organization_member_roles.organization and m."user_id" = organization_member_roles.member and m."disabled_at" is null
$$;
revoke execute on function better_supabase.organization_member_roles(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.organization_member_roles(uuid, uuid) to service_role;

create policy bsb_memberships_read on "better_supabase"."memberships"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

create policy bsb_membership_roles_read on "better_supabase"."membership_roles"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.member_organization_ids()));

revoke execute on function better_supabase.member_organization_ids(text[]) from public;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
grant execute on function better_supabase.member_organization_ids(text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to anon, authenticated, service_role;
grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;

-- The memberships claim. `claimFormat: 'array'` (the default) is
-- [{ scope, id, roles }]; `'map'` is { [tenant id]: role }; `'summary'`
-- is { form, roles, tenants } with a role index per tenant, or a sorted
-- array of indexes when a member holds several roles. When an
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
  select jsonb_build_object(
      'form', 'summary',
      'roles', coalesce((
        select jsonb_agg(names.role_name order by names.role_name)
        from (
          select distinct r."role" as role_name
          from "better_supabase"."membership_roles" r
          join "better_supabase"."memberships" named
            on named."organization_id" = r."organization_id" and named."user_id" = r."user_id"
          where r."user_id" = membership_claims.user_id
            and not better_supabase.user_disabled(r."user_id")
            and not better_supabase.tenant_disabled(r."organization_id") and named."disabled_at" is null
        ) names
      ), '[]'::jsonb),
      'tenants', coalesce(jsonb_object_agg(m."organization_id"::text, (
        select coalesce(jsonb_agg(idx order by idx), '[]'::jsonb)
        from (
          select (
            select count(*)::integer
            from (
          select distinct r."role" as role_name
          from "better_supabase"."membership_roles" r
          join "better_supabase"."memberships" named
            on named."organization_id" = r."organization_id" and named."user_id" = r."user_id"
          where r."user_id" = membership_claims.user_id
            and not better_supabase.user_disabled(r."user_id")
            and not better_supabase.tenant_disabled(r."organization_id") and named."disabled_at" is null
            ) all_roles
            where all_roles.role_name < mine."role"
          ) as idx
          from "better_supabase"."membership_roles" mine
          where mine."organization_id" = m."organization_id" and mine."user_id" = m."user_id"
        ) indexed
      )), '{}'::jsonb)
    )
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

-- better-supabase module: memberships
-- @bsb-block-data memberships
-- @bsb-hash sha256:01807a57c2608444bd77875fbb02e8a50d3a9202f1a6aa1092a050e20162d87b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Every membership holds its primary role in the role set.
insert into "better_supabase"."membership_roles" ("organization_id", "user_id", "role")
select m."organization_id", m."user_id", m."role"::text from "better_supabase"."memberships" m
where m."role" is not null
on conflict ("organization_id", "user_id", "role") do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('memberships', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
