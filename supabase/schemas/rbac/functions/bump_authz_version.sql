-- Bumps the user's authorization version when their role changes.
create or replace function rbac.bump_authz_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed uuid := coalesce(new.user_id, old.user_id);
begin
  insert into rbac.user_authz_versions as v (user_id)
  values (changed)
  on conflict (user_id) do update
    set version = v.version + 1, updated_at = now();

  return null;
end;
$$;

revoke execute on function rbac.bump_authz_version() from authenticated, anon, public;
