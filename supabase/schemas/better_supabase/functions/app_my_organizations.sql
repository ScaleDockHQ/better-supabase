-- Reads the Next.js example needs that no SQL module provides: the caller's
-- organizations for the switcher, an organization's members and open
-- invitations for the settings pages, and the caller's own profile. The
-- profiles and invitations tables live in `better_supabase`, which the Data
-- API doesn't expose, and public.organizations shows only the active one.
-- The SECURITY DEFINER bodies stay in `better_supabase` so splinter does not
-- flag public RPCs that authenticated can execute.
create or replace function better_supabase.app_my_organizations()
returns table (id uuid, name text, slug text, role text, plan text, last_used_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return query
  select o.id, o.name, o.slug, r.key, s.plan_key, m.last_used_at
  from public.memberships m
  join public.organizations o on o.id = m.organization_id
  join better_supabase.roles r on r.id = m.role
  left join public.subscriptions s on s.organization_id = o.id
  where m.user_id = (select auth.uid())
  order by o.name;
end;
$$;

revoke execute on function better_supabase.app_my_organizations() from public, anon;

grant execute on function better_supabase.app_my_organizations() to authenticated, service_role;
