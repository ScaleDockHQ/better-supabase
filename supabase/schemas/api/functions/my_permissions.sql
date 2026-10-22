-- The Data API entry point for better_supabase.my_permissions, which the
-- fixture writes itself because the access module runs in custom mode.
create or replace function api.my_permissions(tenant uuid, keys text[] default null)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select better_supabase.my_permissions(my_permissions.tenant, my_permissions.keys)
$$;

revoke execute on function api.my_permissions(uuid, text[]) from public, anon;

grant execute on function api.my_permissions(uuid, text[]) to authenticated, service_role;
