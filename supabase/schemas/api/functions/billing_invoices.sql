-- A read the Next.js example needs that no SQL module provides yet: the
-- block keeps its tables in `better_supabase`, which the Data API doesn't
-- expose. SECURITY INVOKER, so the block's read policies decide what each
-- caller sees.
create or replace function api.billing_invoices(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', i.id,
    'kind', i.kind,
    'identifier', i.identifier,
    'title', i.title,
    'status', i.status,
    'currency', i.currency,
    'total', i.total::text,
    'balance', (i.total - i.credited_total - i.paid_total)::text,
    'issuedOn', i.issued_on,
    'dueOn', i.due_on,
    'overdue', i.status in ('issued', 'partially_paid') and i.due_on < current_date
  ) order by i.created_at desc), '[]'::jsonb)
  from better_supabase.invoices i
  where i.tenant_id = billing_invoices.tenant;
$$;

revoke all on function api.billing_invoices(uuid) from public, anon;
grant execute on function api.billing_invoices(uuid) to authenticated;
