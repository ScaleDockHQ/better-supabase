create or replace function public.island_counts(args jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'customers', (select count(*) from public.customers as c where c.organization_id = (args ->> 'tenant')::uuid),
    'notes', (select count(*) from public.notes as n where n.organization_id = (args ->> 'tenant')::uuid),
    'contacts', (select count(*) from public.contacts as c where c.organization_id = (args ->> 'tenant')::uuid),
    'tags', (select count(*) from public.tags as t where t.organization_id = (args ->> 'tenant')::uuid),
    'tasks', (select count(*) from public.tasks as t where t.organization_id = (args ->> 'tenant')::uuid)
  );
$$;

comment on function public.island_counts(jsonb) is
  'The islands page data: row counts of five tables in the active organization. better_supabase.bootstrap_islands runs it as the caller, so RLS scopes every count.';

revoke execute on function public.island_counts(jsonb) from public, anon;

grant execute on function public.island_counts(jsonb) to authenticated, service_role;
