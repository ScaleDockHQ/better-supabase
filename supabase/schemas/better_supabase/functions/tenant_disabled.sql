create or replace function better_supabase.tenant_disabled(tenant uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select false
$$;

revoke execute on function better_supabase.tenant_disabled(uuid) from public, anon, authenticated;

grant execute on function better_supabase.tenant_disabled(uuid) to service_role, supabase_auth_admin;
