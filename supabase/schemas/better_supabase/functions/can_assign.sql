create or replace function better_supabase.can_assign(tenant uuid, role text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(auth.jwt() ->> 'role', '') = 'service_role'
    or (auth.uid() is not null and better_supabase.can_assign_as(auth.uid(), tenant, role))
$$;

revoke execute on function better_supabase.can_assign(uuid, text) from public;

grant execute on function better_supabase.can_assign(uuid, text) to anon, authenticated, service_role;
