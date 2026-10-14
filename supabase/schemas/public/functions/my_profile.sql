create or replace function public.my_profile()
returns table (full_name text, email text, username text, avatar_url text, avatar_path text)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  return query
  select p.full_name, p.email, p.username, p.avatar_url, p.avatar_path
  from better_supabase.profiles p
  where p.id = (select auth.uid());
end;
$$;

revoke execute on function public.my_profile() from public, anon;

grant execute on function public.my_profile() to authenticated, service_role;
