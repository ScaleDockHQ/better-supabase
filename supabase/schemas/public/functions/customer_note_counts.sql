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

revoke execute on function public.customer_note_counts(uuid[]) from public, anon;

grant execute on function public.customer_note_counts(uuid[]) to authenticated, service_role;
