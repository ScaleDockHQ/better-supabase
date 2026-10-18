-- better-supabase module: tenant (0.8.0)
-- @bs-module tenant@2 adopt
-- Memberships with roles, member_organization_ids() and has_organization_role() for RLS policies, and membership_claims() for the access token hook. Adopt an existing memberships table through blocks.tenant.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
grant usage on schema better_supabase to supabase_auth_admin;
set check_function_bodies = off;

-- Adopted: "centrakit"."organization_users" belongs to the app (blocks.tenant.tables.memberships).

-- blocks.tenant.options.roleThrough.where names the tenant roles. Every
-- write to "centrakit"."organization_users" stores one of them, whoever writes it: a client policy, the
-- service role or an admin connection.
create or replace function "better_supabase"."membership_role_scope"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new."role_id" is not null and not exists (
    select 1 from "centrakit"."roles" r
    where r."id"::text = new."role_id"::text and (r.scope = 'organization')
  ) then
    raise exception 'Role % is not a tenant role', new."role_id"
      using errcode = '23514', hint = 'MEMBERSHIP_ROLE_SCOPE';
  end if;
  return new;
end;
$$;
revoke execute on function "better_supabase"."membership_role_scope"() from public, anon, authenticated;
drop trigger if exists "bs_role_scope" on "centrakit"."organization_users";
create trigger "bs_role_scope" before insert or update of "role_id" on "centrakit"."organization_users"
  for each row execute function "better_supabase"."membership_role_scope"();

-- blocks.tenant.options.sameTenant: a row may reference only a row of
-- its own tenant, whoever writes it (a client policy, the service role or an
-- admin connection). Arguments: the column, the row's tenant column, the
-- referenced table, its key and tenant columns, and an optional condition on
-- the referenced row p. A null reference passes; the foreign key, if any,
-- still checks that the row exists.
create or replace function better_supabase.same_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  matched boolean;
  extra text := '';
  i integer := 6;
begin
  if pg_catalog.to_jsonb(new) -> tg_argv[0] = 'null'::jsonb then
    return new;
  end if;
  if tg_nargs > 5 and tg_argv[5] <> '' then
    extra := ' and (' || tg_argv[5] || ')';
  end if;
  while i + 1 < tg_nargs loop
    extra := extra || pg_catalog.format(' and p.%I is not distinct from ($1).%I', tg_argv[i + 1], tg_argv[i]);
    i := i + 2;
  end loop;
  execute pg_catalog.format(
    'select exists (select 1 from %s p where p.%I = ($1).%I and p.%I is not distinct from ($1).%I%s)',
    tg_argv[2], tg_argv[3], tg_argv[0], tg_argv[4], tg_argv[1], extra
  ) into matched using new;
  if not matched then
    raise exception '%.% must reference a row of % in the same tenant', tg_table_name, tg_argv[0], tg_argv[2]
      using errcode = '23514', hint = 'TENANT_MISMATCH';
  end if;
  return new;
end;
$$;
revoke execute on function better_supabase.same_tenant() from public, anon, authenticated;
drop trigger if exists "bs_same_tenant_project_id" on "centrakit"."tasks";
create trigger "bs_same_tenant_project_id" before insert or update of "project_id", "organization_id" on "centrakit"."tasks"
  for each row execute function better_supabase.same_tenant('project_id', 'organization_id', '"centrakit"."projects"', 'id', 'organization_id');
drop trigger if exists "bs_same_tenant_customer_id" on "centrakit"."customer_contacts";
create trigger "bs_same_tenant_customer_id" before insert or update of "customer_id", "organization_id" on "centrakit"."customer_contacts"
  for each row execute function better_supabase.same_tenant('customer_id', 'organization_id', '"centrakit"."customers"', 'id', 'organization_id');
drop trigger if exists "bs_same_tenant_contact_id" on "centrakit"."tasks";
create trigger "bs_same_tenant_contact_id" before insert or update of "contact_id", "organization_id", "customer_id" on "centrakit"."tasks"
  for each row execute function better_supabase.same_tenant('contact_id', 'organization_id', '"centrakit"."customer_contacts"', 'id', 'organization_id', '', 'customer_id', 'customer_id');
drop trigger if exists "bs_same_tenant_customer_id" on "centrakit"."tasks";
create trigger "bs_same_tenant_customer_id" before insert or update of "customer_id", "organization_id", "project_id" on "centrakit"."tasks"
  for each row execute function better_supabase.same_tenant('customer_id', 'organization_id', '"centrakit"."customers"', 'id', 'organization_id', 'p."id" is not distinct from (select h."customer_id" from "centrakit"."projects" h where h."id" = ($1)."project_id")');
drop trigger if exists "bs_same_tenant_label_id" on "centrakit"."tasks";
create trigger "bs_same_tenant_label_id" before insert or update of "label_id", "organization_id" on "centrakit"."tasks"
  for each row execute function better_supabase.same_tenant('label_id', 'organization_id', '"centrakit"."organization_tags"', 'id', 'tenant_id', 'p.kind = ''task''');
drop trigger if exists "bs_same_tenant_team_id" on "centrakit"."file_node_grant";
create trigger "bs_same_tenant_team_id" before insert or update of "team_id", "organization_id" on "centrakit"."file_node_grant"
  for each row execute function better_supabase.same_tenant('team_id', 'organization_id', '"centrakit"."teams"', 'id', 'tenant_id');
drop trigger if exists "bs_same_tenant_department_team_id" on "centrakit"."employees";
create trigger "bs_same_tenant_department_team_id" before insert or update of "department_team_id", "organization_id" on "centrakit"."employees"
  for each row execute function better_supabase.same_tenant('department_team_id', 'organization_id', '"centrakit"."teams"', 'id', 'tenant_id');
drop trigger if exists "bs_same_tenant_destination_id" on "centrakit"."webhook_deliveries";
create trigger "bs_same_tenant_destination_id" before insert or update of "destination_id", "organization_id" on "centrakit"."webhook_deliveries"
  for each row execute function better_supabase.same_tenant('destination_id', 'organization_id', '"centrakit"."webhook_destinations"', 'id', 'organization_id');


-- The `tenant_id` claim, then centrakit.profiles.active_organization_id, while the
-- caller is still a member.
create or replace function better_supabase.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select m."organization_id"::text from "centrakit"."organization_users" m where m."organization_id"::text = nullif(coalesce(auth.jwt() ->> 'tenant_id', auth.jwt() -> 'app_metadata' ->> 'tenant_id'), '') and m."user_id" = auth.uid() limit 1),
    (select m."organization_id"::text from "centrakit"."organization_users" m where m."organization_id"::text = (select p."active_organization_id"::text from "centrakit"."profiles" p where p."user_id" = auth.uid()) and m."user_id" = auth.uid() limit 1)
  )::uuid
$$;
revoke execute on function better_supabase.current_tenant_id() from public;
grant execute on function better_supabase.current_tenant_id() to anon, authenticated, service_role, supabase_auth_admin;

-- Policies compare against the set once per statement:
--   using (organization_id in (select better_supabase.member_organization_ids('{owner,admin}')))
-- has_organization_role(organization) answers for one organization, in functions and checks.
-- Prefer the access contract (better_supabase.can, tenant_ids_with) for
-- permission checks; these answer by role name.
-- Under the authorization provider, membership comes from its memberIds;
-- the memberships table only names roles.
create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select p.id
  from centrakit.authz_organization_member_ids() as p(id)
  where member_organization_ids.roles is null
    and not better_supabase.user_disabled((select auth.uid()))
    and not better_supabase.tenant_disabled(p.id)
  union
  select m."organization_id"
  from "centrakit"."organization_users" m
  where member_organization_ids.roles is not null
    and m."user_id" = (select auth.uid())
    and (select r."key"::text from "centrakit"."roles" r where r."id"::text = (m."role_id")::text) = any (member_organization_ids.roles)
    and not better_supabase.user_disabled(m."user_id")
    and not better_supabase.tenant_disabled(m."organization_id")
    and m."organization_id" in (select p.id from centrakit.authz_organization_member_ids() as p(id))
$$;

create or replace function better_supabase.has_organization_role(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select has_organization_role.organization in (
    select better_supabase.member_organization_ids(has_organization_role.roles)
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
  select (select r."key"::text from "centrakit"."roles" r where r."id"::text = (m."role_id")::text) from "centrakit"."organization_users" m where m."organization_id" = organization_member_role.organization and m."user_id" = organization_member_role.member and m."organization_id" in (select p.id from centrakit.authz_organization_member_ids_for(organization_member_role.member) as p(id))
$$;

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
-- Disabled users and tenants (blocks.access.disabled) are left out.
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
      'roles', jsonb_build_array((select r."key"::text from "centrakit"."roles" r where r."id"::text = (m."role_id")::text))
    ) order by m."created_at", m."organization_id"), '[]'::jsonb)
  from "centrakit"."organization_users" m
  where m."user_id" = membership_claims.user_id
    and not better_supabase.user_disabled(membership_claims.user_id)
    and not better_supabase.tenant_disabled(m."organization_id")
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;
reset check_function_bodies;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
