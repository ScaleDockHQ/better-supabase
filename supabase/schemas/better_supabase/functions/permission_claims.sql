create or replace function better_supabase.permission_claims(user_id uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select '{}'::jsonb
$$;

revoke execute on function better_supabase.permission_claims(uuid) from public, anon, authenticated;

grant execute on function better_supabase.permission_claims(uuid) to service_role, supabase_auth_admin;
