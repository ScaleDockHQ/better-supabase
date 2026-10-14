create or replace function better_supabase.role_rank(role text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case role when 'owner' then 3 when 'admin' then 2 when 'member' then 1 else 0 end
$$;

revoke execute on function better_supabase.role_rank(text) from public, anon;

grant execute on function better_supabase.role_rank(text) to authenticated, service_role;
