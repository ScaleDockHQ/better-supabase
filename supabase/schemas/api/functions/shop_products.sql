-- A read the Next.js example needs that no SQL module provides yet: the
-- block keeps its tables in `better_supabase`, which the Data API doesn't
-- expose. SECURITY INVOKER, so the block's read policies decide what each
-- caller sees.
create or replace function api.shop_products(tenant uuid, currency text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.item order by p.created_at desc), '[]'::jsonb)
  from better_supabase.products p
  join lateral (
    select v.id, v.sku
    from better_supabase.product_variants v
    where v.product_id = p.id
    order by v.rank collate "C"
    limit 1
  ) first_variant on true
  left join lateral (
    select pr.amount
    from better_supabase.product_prices pr
    where pr.variant_id = first_variant.id
      and pr.currency = shop_products.currency
      and pr.price_list_id is null
      and (pr.valid_from is null or pr.valid_from <= now())
      and (pr.valid_until is null or pr.valid_until > now())
    order by pr.valid_from desc nulls last
    limit 1
  ) price on true
  left join lateral (
    select sum(l.available)::int as available
    from better_supabase.stock_levels l
    join better_supabase.product_variants v on v.id = l.variant_id
    where v.product_id = p.id
  ) stock on true
  cross join lateral (
    select jsonb_build_object(
      'id', p.id,
      'title', p.title,
      'slug', p.slug,
      'description', p.description,
      'kind', p.kind,
      'status', p.status,
      'variantId', first_variant.id,
      'sku', first_variant.sku,
      'amount', price.amount::text,
      'available', stock.available
    ) as item
  ) r
  where p.tenant_id = shop_products.tenant;
$$;

revoke all on function api.shop_products(uuid, text) from public, anon;
grant execute on function api.shop_products(uuid, text) to authenticated;
