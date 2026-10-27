-- Bumps the authorization version of every member an organization's
-- permission override changes (set_permission_override), so their tokens
-- carry the new keys after the next refresh.
create or replace function rbac.bump_override_authz_versions()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_organization uuid := coalesce(new.organization_id, old.organization_id);
  changed_role uuid := coalesce(new.role_id, old.role_id);
begin
  insert into rbac.user_authz_versions as v (user_id)
  select m.user_id
  from public.memberships m
  where m.organization_id = changed_organization
    and m.role = changed_role
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now();

  return null;
end;
$$;

revoke execute on function rbac.bump_override_authz_versions() from authenticated, anon, public;

create trigger permission_overrides_bump_authz_versions
  after insert or update or delete on better_supabase.permission_overrides
  for each row execute function rbac.bump_override_authz_versions();
