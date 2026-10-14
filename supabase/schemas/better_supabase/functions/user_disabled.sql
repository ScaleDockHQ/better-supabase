create or replace function better_supabase.user_disabled(user_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select false
$$;

revoke execute on function better_supabase.user_disabled(uuid) from public, anon, authenticated;

grant execute on function better_supabase.user_disabled(uuid) to service_role, supabase_auth_admin;
