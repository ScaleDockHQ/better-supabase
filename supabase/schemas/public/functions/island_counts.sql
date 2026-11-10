create or replace function public.island_counts(args jsonb)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'customers', (select count(*) from (select 1 from public.customers as c where c.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped),
    'notes', (select count(*) from (select 1 from public.notes as n where n.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped),
    'contacts', (select count(*) from (select 1 from public.contacts as c where c.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped),
    'tags', (select count(*) from (select 1 from public.tags as t where t.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped),
    'tasks', (select count(*) from (select 1 from public.tasks as t where t.organization_id = (args ->> 'tenant')::uuid limit 10000) as capped)
  );
$$;

comment on function public.island_counts(jsonb) is
  'The islands page data: row counts of five tables in the active organization, each stopping at 10,000 (a lower bound above that). better_supabase.bootstrap_islands runs it as the caller, so RLS scopes every count.';

revoke execute on function public.island_counts(jsonb) from public, anon;

grant execute on function public.island_counts(jsonb) to authenticated, service_role;
