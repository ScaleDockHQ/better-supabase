create or replace function better_supabase.has_organization_role(organization uuid, roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(r.role is not null and (roles is null or r.role = any (roles)), false)
  from (select better_supabase.organization_member_role(organization, auth.uid()) as role) r
$$;

revoke execute on function better_supabase.has_organization_role(uuid, text[]) from public;

grant execute on function better_supabase.has_organization_role(uuid, text[]) to anon, authenticated, service_role;
