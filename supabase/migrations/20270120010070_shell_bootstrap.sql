SET local check_function_bodies = off;

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

create or replace function better_supabase.bootstrap_shell(args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select better_supabase.session_active()) then
    return jsonb_build_object(
      'session_active', false,
      'end_reason', better_supabase.session_end_reason(),
      'authz_version', auth.jwt() -> 'authz_ver',
      'token_authz_version', auth.jwt() -> 'authz_ver',
      'tenant', args ->> 'tenant',
      'data', null
    );
  end if;
  return jsonb_build_object(
    'session_active', true,
    'authz_version', to_jsonb(better_supabase.caller_authz_version()),
    'token_authz_version', auth.jwt() -> 'authz_ver',
    'tenant', args ->> 'tenant',
    'data', to_jsonb(public.shell_bootstrap(args))
  );
end;
$$;

revoke execute on function better_supabase.bootstrap_shell(jsonb) from public, anon;
grant execute on function better_supabase.bootstrap_shell(jsonb) to authenticated;

create or replace function "api"."bootstrap_shell"(args jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."bootstrap_shell"($1) $$;
revoke execute on function "api"."bootstrap_shell"(jsonb) from public, anon, service_role;
grant execute on function "api"."bootstrap_shell"(jsonb) to authenticated;
