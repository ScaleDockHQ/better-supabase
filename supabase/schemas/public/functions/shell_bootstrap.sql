create or replace function public.shell_bootstrap(args jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'organizations', coalesce((
      select jsonb_agg(to_jsonb(o))
      from public.my_organizations(50) as o
    ), '[]'::jsonb),
    'profile', (select to_jsonb(p) from public.my_profile() as p limit 1),
    'approvals_pending', (
      select count(*)
      from better_supabase.approval_requests as r
      where r.status = 'pending'
        and r.tenant_id = nullif(args ->> 'tenant', '')::uuid
    ),
    'permissions', better_supabase.bootstrap_permissions()
  );
$$;

comment on function public.shell_bootstrap(jsonb) is
  'The page shell data in one call: the caller''s organizations (the first 50, most recently used first), the profile row, the pending approval requests of the active organization and the compact permissions of every organization. better_supabase.bootstrap_shell runs it as the caller, so RLS scopes the count.';

revoke execute on function public.shell_bootstrap(jsonb) from public, anon;

grant execute on function public.shell_bootstrap(jsonb) to authenticated, service_role;
