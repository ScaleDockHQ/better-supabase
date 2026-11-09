-- Statement-level bumps when a role's default keys or a platform assignment
-- change. The sessions module renders the same triggers; these stay so the
-- fixture applies them before the next full render of that module. Each
-- statement drops its trigger first, so a later render can replace it.
create or replace function rbac.bump_role_permission_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(
    select m.user_id
    from public.memberships m
    where m.role in (select role_id from changed)
  ));
  return null;
end;
$$;

revoke execute on function rbac.bump_role_permission_members() from authenticated, anon, public;

drop trigger if exists bsb_role_permissions_bump_insert on better_supabase.role_permissions;
drop trigger if exists bsb_role_permissions_bump_delete on better_supabase.role_permissions;

create trigger bsb_role_permissions_bump_insert
  after insert on better_supabase.role_permissions
  referencing new table as changed
  for each statement execute function rbac.bump_role_permission_members();

create trigger bsb_role_permissions_bump_delete
  after delete on better_supabase.role_permissions
  referencing old table as changed
  for each statement execute function rbac.bump_role_permission_members();

create or replace function rbac.bump_platform_role_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(
    select user_id from changed
  ));
  return null;
end;
$$;

revoke execute on function rbac.bump_platform_role_members() from authenticated, anon, public;

drop trigger if exists bsb_platform_roles_bump_insert on better_supabase.platform_roles;
drop trigger if exists bsb_platform_roles_bump_delete on better_supabase.platform_roles;

create trigger bsb_platform_roles_bump_insert
  after insert on better_supabase.platform_roles
  referencing new table as changed
  for each statement execute function rbac.bump_platform_role_members();

create trigger bsb_platform_roles_bump_delete
  after delete on better_supabase.platform_roles
  referencing old table as changed
  for each statement execute function rbac.bump_platform_role_members();
