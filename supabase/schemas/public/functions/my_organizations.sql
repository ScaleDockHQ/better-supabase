create or replace function public.my_organizations()
returns table (id uuid, name text, slug text, role text, plan text, last_used_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from better_supabase.app_my_organizations()
$$;

revoke execute on function public.my_organizations() from public, anon;

grant execute on function public.my_organizations() to authenticated, service_role;
