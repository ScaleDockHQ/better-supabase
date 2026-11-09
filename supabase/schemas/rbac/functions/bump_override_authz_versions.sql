-- Bumps the authorization version of every member an organization's
-- permission override changes, once per statement. A row trigger would bump
-- the same member once per key in the statement.
create or replace function rbac.bump_override_authz_versions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(
    select m.user_id
    from public.memberships m
    where (m.organization_id, m.role) in (
      select tenant_id, role_id from changed
    )
  ));

  return null;
end;
$$;

revoke execute on function rbac.bump_override_authz_versions() from authenticated, anon, public;

drop trigger if exists bsb_permission_overrides_bump_authz_versions on better_supabase.permission_overrides;
drop trigger if exists bsb_permission_overrides_bump_insert on better_supabase.permission_overrides;
drop trigger if exists bsb_permission_overrides_bump_update on better_supabase.permission_overrides;
drop trigger if exists bsb_permission_overrides_bump_delete on better_supabase.permission_overrides;

create trigger bsb_permission_overrides_bump_insert
  after insert on better_supabase.permission_overrides
  referencing new table as changed
  for each statement execute function rbac.bump_override_authz_versions();

create trigger bsb_permission_overrides_bump_update
  after update on better_supabase.permission_overrides
  referencing new table as changed
  for each statement execute function rbac.bump_override_authz_versions();

create trigger bsb_permission_overrides_bump_delete
  after delete on better_supabase.permission_overrides
  referencing old table as changed
  for each statement execute function rbac.bump_override_authz_versions();
