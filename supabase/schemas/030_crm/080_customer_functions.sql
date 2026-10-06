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

create or replace function public.customer_note_counts(p_customer_ids uuid[] default null)
returns table (customer_id uuid, note_count bigint, last_note_at timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  select c.id, count(n.id), max(n.created_at)
  from public.customers as c
  left join public.notes as n on n.customer_id = c.id
  where p_customer_ids is null or c.id = any (p_customer_ids)
  group by c.id;
$$;
