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

revoke execute on function rbac.authorize(rbac.app_permission) from public, anon;

grant execute on function rbac.authorize(rbac.app_permission) to authenticated;
