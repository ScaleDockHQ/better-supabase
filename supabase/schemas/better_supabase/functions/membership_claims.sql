create or replace function better_supabase.membership_claims(user_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object('scope', 'tenant', 'id', m.organization_id, 'roles', jsonb_build_array(m.role))
    order by m.created_at, m.organization_id
  ), '[]'::jsonb)
  from public.memberships m
  where m.user_id = membership_claims.user_id
$$;

revoke execute on function better_supabase.membership_claims(uuid) from public, anon, authenticated;

grant execute on function better_supabase.membership_claims(uuid) to service_role, supabase_auth_admin;
