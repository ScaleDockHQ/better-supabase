create or replace function public.organization_members(organization uuid)
returns table (user_id uuid, role text, full_name text, email text, avatar_url text, avatar_path text, joined_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from better_supabase.app_organization_members(organization)
$$;

revoke execute on function public.organization_members(uuid) from public, anon;

grant execute on function public.organization_members(uuid) to authenticated, service_role;
