create or replace function public.organization_invitations(organization uuid)
returns table (id uuid, email text, role text, invited_by text, created_at timestamptz, expires_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select * from better_supabase.app_organization_invitations(organization)
$$;

revoke execute on function public.organization_invitations(uuid) from public, anon;

grant execute on function public.organization_invitations(uuid) to authenticated, service_role;
