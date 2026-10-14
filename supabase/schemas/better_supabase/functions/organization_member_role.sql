create or replace function better_supabase.organization_member_role(organization uuid, member uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select m.role
  from public.memberships m
  where m.organization_id = organization and m.user_id = member
$$;

revoke execute on function better_supabase.organization_member_role(uuid, uuid) from public, anon, authenticated;

grant execute on function better_supabase.organization_member_role(uuid, uuid) to service_role;
