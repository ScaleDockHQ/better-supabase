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

revoke execute on function better_supabase.can_user(uuid, text, uuid, text) from public, anon, authenticated;

grant execute on function better_supabase.can_user(uuid, text, uuid, text) to service_role, supabase_auth_admin;
