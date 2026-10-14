create or replace function better_supabase.app_organization_members(organization uuid)
returns table (user_id uuid, role text, full_name text, email text, avatar_url text, avatar_path text, joined_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not better_supabase.member_can((select auth.uid()), organization, 'members.read') then
    raise exception 'Not allowed to list members' using errcode = '42501';
  end if;
  return query
  select m.user_id, m.role, p.full_name, coalesce(p.email, u.email::text), p.avatar_url, p.avatar_path, m.created_at
  from public.memberships m
  join auth.users u on u.id = m.user_id
  left join better_supabase.profiles p on p.id = m.user_id
  where m.organization_id = organization
  order by better_supabase.role_rank(m.role) desc, coalesce(p.full_name, u.email::text);
end;
$$;

revoke execute on function better_supabase.app_organization_members(uuid) from public, anon;

grant execute on function better_supabase.app_organization_members(uuid) to authenticated, service_role;
