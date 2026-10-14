-- Fixture functions for `$rpc` result decoding: one returns rows of a table,
-- one a `returns table (...)` record. Both run as the caller, so RLS applies.
create or replace function public.customers_by_status(p_status text, p_limit integer default 50)
returns setof public.customers
language sql
stable
security invoker
set search_path = ''
as $$
  select *
  from public.customers
  where status = p_status
  order by name
  limit p_limit;
$$;

revoke execute on function public.customers_by_status(text, integer) from public, anon;

grant execute on function public.customers_by_status(text, integer) to authenticated, service_role;
