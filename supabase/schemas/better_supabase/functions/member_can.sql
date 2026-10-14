create or replace function better_supabase.member_can(member uuid, tenant uuid, permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select better_supabase.can_user(member, 'tenant', tenant, permission)
$$;

revoke execute on function better_supabase.member_can(uuid, uuid, text) from public, anon, authenticated;

grant execute on function better_supabase.member_can(uuid, uuid, text) to service_role;
