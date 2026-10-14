create or replace function better_supabase.member_organization_ids(roles text[] default null)
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select m.organization_id
  from public.memberships m
  where m.user_id = auth.uid() and (roles is null or m.role = any (roles))
$$;

revoke execute on function better_supabase.member_organization_ids(text[]) from public, anon;

grant execute on function better_supabase.member_organization_ids(text[]) to authenticated, service_role;
