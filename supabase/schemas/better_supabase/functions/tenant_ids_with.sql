-- Only the active tenant, like the CRM policies: rows of the caller's other
-- organizations stay hidden until they switch.
create or replace function better_supabase.tenant_ids_with(permission text)
returns setof uuid
language sql
rows 1
stable
security definer
set search_path = ''
as $$
  select t.id
  from (select better_supabase.current_tenant_id() as id) t
  where better_supabase.can('tenant', t.id, permission)
$$;

revoke execute on function better_supabase.tenant_ids_with(text) from public;

grant execute on function better_supabase.tenant_ids_with(text) to anon, authenticated, service_role;
