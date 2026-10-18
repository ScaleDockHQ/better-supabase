-- A read the Next.js example needs that no SQL module provides yet: the
-- block keeps its tables in `better_supabase`, which the Data API doesn't
-- expose. SECURITY INVOKER, so the block's read policies decide what each
-- caller sees.
create or replace function api.shop_orders(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', o.id,
        'number', o.number,
        'status', o.status,
        'currency', o.currency,
        'total', o.total::text,
        'placedAt', o.placed_at,
        'lines', (select count(*) from better_supabase.order_lines ol where ol.order_id = o.id)
      ) order by o.placed_at desc)
      from better_supabase.orders o
      where o.tenant_id = shop_orders.tenant
    ), '[]'::jsonb),
    'drafts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', c.id,
        'currency', c.currency,
        'createdAt', c.created_at,
        'lines', (select count(*) from better_supabase.cart_lines cl where cl.cart_id = c.id)
      ) order by c.created_at desc)
      from better_supabase.carts c
      where c.tenant_id = shop_orders.tenant
        and c.user_id = (select auth.uid())
        and c.status = 'open'
    ), '[]'::jsonb)
  );
$$;

revoke all on function api.shop_orders(uuid) from public, anon;
grant execute on function api.shop_orders(uuid) to authenticated;
