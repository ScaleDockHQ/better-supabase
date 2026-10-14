-- Removing a membership clears the tenant claim that points at it, so the
-- next token carries no tenant (the managed tenant module does the same).
create or replace function better_supabase.clear_tenant_claim()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update auth.users u
  set raw_app_meta_data = u.raw_app_meta_data - 'tenant_id'
  where u.id = old.user_id
    and u.raw_app_meta_data ->> 'tenant_id' = old.organization_id::text;
  return null;
end;
$$;

revoke execute on function better_supabase.clear_tenant_claim() from public, anon, authenticated;
