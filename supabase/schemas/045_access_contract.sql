-- The access contract for the SQL modules, which run with `tenant` and
-- `access` in custom mode (`apps/examples/nextjs/better-supabase.config.ts`).
-- A user belongs to the organization in `app_metadata.tenant_id`, with the
-- role in rbac.user_roles. Admins hold every module permission; members read,
-- comment, keep their own API keys and read the settings. There are no
-- platform roles, and nobody is disabled.

create or replace function better_supabase.organization_member_role(organization uuid, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(ur.role::text, 'member')
  from auth.users u
  left join rbac.user_roles ur on ur.user_id = u.id
  where u.id = member
    and nullif(u.raw_app_meta_data ->> 'tenant_id', '') = organization::text
$$;

create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select t.id
  from (select better_supabase.current_tenant_id() as id) t
  cross join lateral (select better_supabase.organization_member_role(t.id, auth.uid()) as role) r
  where r.role is not null and (roles is null or r.role = any (roles))
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
  select coalesce(jsonb_agg(jsonb_build_object('scope', 'tenant', 'id', t.id, 'roles', jsonb_build_array(r.role))), '[]'::jsonb)
  from (
    select nullif(u.raw_app_meta_data ->> 'tenant_id', '')::uuid as id
    from auth.users u
    where u.id = membership_claims.user_id
  ) t
  cross join lateral (select better_supabase.organization_member_role(t.id, membership_claims.user_id) as role) r
  where r.role is not null
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
    scope = 'tenant'
      and r.role is not null
      and (r.role = 'admin' or permission = any (array[
        'comments.read', 'comments.create', 'activity.read', 'api_keys.own', 'settings.read'
      ])),
    false
  )
  from (select better_supabase.organization_member_role(scope_id, member) as role) r
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

create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid
language sql
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

create or replace function better_supabase.can_assign(tenant uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or better_supabase.organization_member_role(tenant, auth.uid()) = 'admin'
$$;

create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select '{}'::jsonb
$$;

revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;
revoke execute on function better_supabase.member_organization_ids(text[]) from public, anon;
revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public, anon;
revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.tenant_disabled(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.user_disabled(uuid) from public, anon, authenticated;
revoke execute on function better_supabase.can_user(uuid, text, uuid, text) from public, anon, authenticated;
revoke execute on function better_supabase.can(text, uuid, text) from public;
revoke execute on function better_supabase.tenant_ids_with(text) from public;
revoke execute on function better_supabase.is_platform(text) from public;
revoke execute on function better_supabase.can_assign(uuid, text) from public;
revoke execute on function better_supabase.permission_claims(uuid) from public, anon, authenticated;

grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;
grant execute on function better_supabase.member_organization_ids(text[]) to authenticated, service_role;
grant execute on function better_supabase.has_organization_role(uuid, text[]) to authenticated, service_role;
grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.tenant_disabled(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.user_disabled(uuid) to service_role, supabase_auth_admin;
grant execute on function better_supabase.can_user(uuid, text, uuid, text) to service_role, supabase_auth_admin;
grant execute on function better_supabase.can(text, uuid, text) to anon, authenticated, service_role;
grant execute on function better_supabase.tenant_ids_with(text) to anon, authenticated, service_role;
grant execute on function better_supabase.is_platform(text) to anon, authenticated, service_role;
grant execute on function better_supabase.can_assign(uuid, text) to anon, authenticated, service_role;
grant execute on function better_supabase.permission_claims(uuid) to service_role, supabase_auth_admin;
