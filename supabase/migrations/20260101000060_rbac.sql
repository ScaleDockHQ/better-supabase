-- Role-based access control, following Supabase's RBAC guide (and the shape
-- `permdock rls generate --rbac supabase` emits): roles live in a table, the
-- custom access token hook copies the user's role into a top-level
-- `user_role` claim, and `authorize()` checks a permission for RLS.
--
-- Kept in its own schema so it stays out of the generated `public` types.
create schema if not exists rbac;

create type rbac.app_role as enum ('admin', 'member');
create type rbac.app_permission as enum (
  'customers.read',
  'customers.write',
  'reports.read',
  'users.manage',
  'billing.manage',
  'audit.read',
  'settings.manage'
);

create table rbac.user_roles (
  user_id uuid primary key references auth.users on delete cascade,
  role rbac.app_role not null
);

create table rbac.role_permissions (
  role rbac.app_role not null,
  permission rbac.app_permission not null,
  primary key (role, permission)
);

alter table rbac.user_roles enable row level security;
alter table rbac.role_permissions enable row level security;

insert into rbac.role_permissions (role, permission)
select 'admin', permission
from unnest(enum_range(null::rbac.app_permission)) as permission;

insert into rbac.role_permissions (role, permission) values
  ('member', 'customers.read');

create or replace function rbac.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  claims jsonb := event -> 'claims';
  user_role rbac.app_role;
begin
  select ur.role into user_role
  from rbac.user_roles ur
  where ur.user_id = (event ->> 'user_id')::uuid;

  if user_role is not null then
    claims := jsonb_set(claims, '{user_role}', to_jsonb(user_role));
  end if;

  return jsonb_set(event, '{claims}', claims);
end;
$$;

create or replace function rbac.authorize(requested_permission rbac.app_permission)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from rbac.role_permissions rp
    where rp.permission = requested_permission
      and rp.role::text = coalesce(
        auth.jwt() ->> 'user_role',
        auth.jwt() -> 'app_metadata' ->> 'user_role'
      )
  )
$$;

grant usage on schema rbac to supabase_auth_admin, authenticated;
grant execute on function rbac.custom_access_token_hook(jsonb) to supabase_auth_admin;
revoke execute on function rbac.custom_access_token_hook(jsonb) from authenticated, anon, public;
grant select on rbac.user_roles to supabase_auth_admin;
revoke all on rbac.user_roles from authenticated, anon, public;
grant execute on function rbac.authorize(rbac.app_permission) to authenticated;

create policy "Auth admin reads user roles" on rbac.user_roles
  as permissive for select
  to supabase_auth_admin
  using (true);
