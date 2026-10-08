-- The access contract for the SQL modules, which run with `tenant` and
-- `access` in custom mode (`apps/examples/nextjs/better-supabase.config.ts`).
-- A user can belong to several organizations (public.memberships);
-- the active one is the `tenant_id` claim that switch_organization writes.
-- Owners hold every permission, admins everything but deleting and handing
-- over the organization, members read, comment, keep their own API keys and
-- read the settings. There are no platform roles, and nobody is disabled.
-- `rolePermissions` in apps/examples/nextjs/src/features/user/user-permissions.ts
-- mirrors the lists for the UI.

create or replace function better_supabase.role_permissions(role text)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select case role
    when 'owner' then array['*']
    when 'admin' then array[
      'customers.read', 'customers.write', 'reports.read',
      'organization.read', 'organization.update',
      'members.read', 'members.invite', 'members.remove', 'members.update_role',
      'billing.read', 'billing.manage', 'audit.read',
      'settings.read', 'settings.update', 'settings.manage',
      'api_keys.manage', 'api_keys.own',
      'comments.read', 'comments.create', 'comments.moderate', 'activity.read',
      'onboarding.read', 'onboarding.complete', 'usage.read', 'usage.record',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run', 'workflow.edit', 'workflow.publish', 'workflow.admin'
    ]
    when 'member' then array[
      'customers.read', 'organization.read', 'members.read', 'billing.read',
      'settings.read', 'api_keys.own', 'comments.read', 'comments.create', 'activity.read',
      'onboarding.read', 'usage.read', 'usage.record',
      'notifications.send', 'notifications.read',
      'workflow.read', 'workflow.run'
    ]
    else array[]::text[]
  end
$$;

create or replace function better_supabase.role_rank(role text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case role when 'owner' then 3 when 'admin' then 2 when 'member' then 1 else 0 end
$$;

create or replace function better_supabase.organization_member_role(organization uuid, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.memberships m
  where m.organization_id = organization and m.user_id = member
$$;

create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.organization_id
  from public.memberships m
  where m.user_id = auth.uid() and (roles is null or m.role = any (roles))
$$;

create or replace function better_supabase.has_organization_role(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(r.role is not null and (roles is null or r.role = any (roles)), false)
  from (select better_supabase.organization_member_role(organization, auth.uid()) as role) r
$$;

create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object('scope', 'tenant', 'id', m.organization_id, 'roles', jsonb_build_array(m.role))
    order by m.created_at, m.organization_id
  ), '[]'::jsonb)
  from public.memberships m
  where m.user_id = membership_claims.user_id
$$;

create or replace function better_supabase.tenant_disabled(tenant uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select false
$$;

create or replace function better_supabase.user_disabled(user_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select false
$$;

create or replace function better_supabase.can_user(member uuid, scope text, scope_id uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    scope in ('tenant', 'organization')
      and r.role is not null
      and exists (
        select 1 from unnest(better_supabase.role_permissions(r.role)) k(key)
        where k.key = '*' or k.key = permission
      ),
    false
  )
  from (select better_supabase.organization_member_role(scope_id, member) as role) r
$$;

create or replace function better_supabase.member_can(member uuid, tenant uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select better_supabase.can_user(member, 'tenant', tenant, permission)
$$;

create or replace function better_supabase.can(scope text, scope_id uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and better_supabase.can_user(auth.uid(), scope, scope_id, permission)
$$;

-- Only the active tenant, like the CRM policies: rows of the caller's other
-- organizations stay hidden until they switch.
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select t.id
  from (select better_supabase.current_tenant_id() as id) t
  where better_supabase.can('tenant', t.id, permission)
$$;

create or replace function better_supabase.is_platform(permission text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select false
$$;

-- A member who may manage members hands out roles up to their own.
create or replace function better_supabase.can_assign_as(member uuid, tenant uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (better_supabase.member_can(member, tenant, 'members.invite')
      or better_supabase.member_can(member, tenant, 'members.update_role'))
    and better_supabase.role_rank(better_supabase.organization_member_role(tenant, member))
      >= better_supabase.role_rank(role)
    and better_supabase.role_rank(role) > 0,
    false
  )
$$;

create or replace function better_supabase.can_assign(tenant uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or (auth.uid() is not null and better_supabase.can_assign_as(auth.uid(), tenant, role))
$$;

create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select '{}'::jsonb
$$;

revoke execute on function better_supabase.role_permissions(text) from public, anon;
revoke execute on function better_supabase.role_rank(text) from public, anon;
revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
revoke execute on function better_supabase.member_organization_ids(text[]) from public, anon;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public, anon;
revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.tenant_disabled(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.user_disabled(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.can_user(uuid, text, uuid, text) from public, anon, authenticated;
revoke execute on function better_supabase.member_can(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function better_supabase.can_assign_as(uuid, uuid, text) from public, anon, authenticated;
revoke execute on function better_supabase.can(text, uuid, text) from public;
revoke execute on function better_supabase.tenant_ids_with(text) from public;
revoke execute on function better_supabase.is_platform(text) from public;
revoke execute on function better_supabase.can_assign(uuid, text) from public;
revoke execute on function better_supabase.permission_claims(uuid) from public, anon, authenticated;

grant execute on function better_supabase.role_permissions(text) to authenticated, service_role;
grant execute on function better_supabase.role_rank(text) to authenticated, service_role;
grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;
grant execute on function better_supabase.member_organization_ids(text[]) to authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to authenticated, service_role;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.tenant_disabled(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.user_disabled(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.can_user(uuid, text, uuid, text) to service_role, supabase_auth_admin;
grant execute on function better_supabase.member_can(uuid, uuid, text) to service_role;
grant execute on function better_supabase.can_assign_as(uuid, uuid, text) to service_role;
grant execute on function better_supabase.can(text, uuid, text) to anon, authenticated, service_role;
grant execute on function better_supabase.tenant_ids_with(text) to anon, authenticated, service_role;
grant execute on function better_supabase.is_platform(text) to anon, authenticated, service_role;
grant execute on function better_supabase.can_assign(uuid, text) to anon, authenticated, service_role;
grant execute on function better_supabase.permission_claims(uuid) to service_role, supabase_auth_admin;
