-- Reads the Next.js example needs that the quotes module doesn't provide
-- yet: the organization's latest quotes and one quote, in the shape
-- `create_quote` returns. SECURITY INVOKER, so the quotes read policy
-- (`quotes.read`) decides what each caller sees.
create or replace function better_supabase.app_quote_json(q better_supabase.quotes)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select (to_jsonb(q) - 'token_hash')
    || jsonb_build_object(
      'number', q.number::text,
      'list_total', q.list_total::text,
      'discount_total', q.discount_total::text,
      'subtotal', q.subtotal::text,
      'tax_total', q.tax_total::text,
      'total', q.total::text,
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
          'description', ql.description,
          'quantity', ql.quantity,
          'unitAmount', ql.unit_amount::text,
          'discountBps', ql.discount_bps,
          'taxRateBps', ql.tax_rate_bps,
          'taxCode', ql.tax_code
        ) order by ql.position)
        from better_supabase.quote_lines ql
        where ql.parent_id = q.id
      ), '[]'::jsonb)
    );
$$;

create or replace function api.list_quotes(tenant uuid, page_size integer)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(better_supabase.app_quote_json(x.q) order by (x.q).created_at desc), '[]'::jsonb)
  from (
    select q
    from better_supabase.quotes q
    where q.tenant_id = list_quotes.tenant
    order by q.created_at desc
    limit least(greatest(list_quotes.page_size, 1), 100)
  ) x;
$$;

create or replace function api.get_quote(quote uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select better_supabase.app_quote_json(q)
  from better_supabase.quotes q
  where q.id = get_quote.quote;
$$;

revoke all on function better_supabase.app_quote_json(better_supabase.quotes) from public, anon;
revoke all on function api.list_quotes(uuid, integer) from public, anon;
revoke all on function api.get_quote(uuid) from public, anon;
grant execute on function better_supabase.app_quote_json(better_supabase.quotes) to authenticated;
grant execute on function api.list_quotes(uuid, integer) to authenticated;
grant execute on function api.get_quote(uuid) to authenticated;
