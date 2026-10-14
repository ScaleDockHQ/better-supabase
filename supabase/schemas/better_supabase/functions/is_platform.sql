create or replace function better_supabase.is_platform(permission text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select false
$$;

revoke execute on function better_supabase.is_platform(text) from public;

grant execute on function better_supabase.is_platform(text) to anon, authenticated, service_role;
