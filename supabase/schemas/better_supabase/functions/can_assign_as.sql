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

revoke execute on function better_supabase.can_assign_as(uuid, uuid, text) from public, anon, authenticated;

grant execute on function better_supabase.can_assign_as(uuid, uuid, text) to service_role;
