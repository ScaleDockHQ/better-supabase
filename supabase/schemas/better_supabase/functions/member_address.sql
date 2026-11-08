create or replace function better_supabase.member_address(p_user uuid, p_channel text)
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select case when p_channel = 'email' then 'work.' || u.email end
  from auth.users as u
  where u.id = p_user;
$$;

revoke execute on function better_supabase.member_address(uuid, text) from public, anon, authenticated;

grant execute on function better_supabase.member_address(uuid, text) to service_role;
