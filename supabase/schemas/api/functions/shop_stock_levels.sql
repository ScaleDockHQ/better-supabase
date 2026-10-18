-- A read the Next.js example needs that no SQL module provides yet: the
-- block keeps its tables in `better_supabase`, which the Data API doesn't
-- expose. SECURITY INVOKER, so the block's read policies decide what each
-- caller sees.
create or replace function api.shop_stock_levels(tenant uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'locations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', loc.id, 'code', loc.code, 'name', loc.name, 'active', loc.active
      ) order by loc.code)
      from better_supabase.inventory_locations loc
      where loc.tenant_id = shop_stock_levels.tenant
    ), '[]'::jsonb),
    'levels', coalesce((
      select jsonb_agg(jsonb_build_object(
        'variantId', v.id,
        'productTitle', p.title,
        'sku', v.sku,
        'locationId', loc.id,
        'onHand', coalesce(l.on_hand, 0),
        'reserved', coalesce(l.reserved, 0),
        'available', coalesce(l.available, 0),
        'reorderPoint', l.reorder_point
      ) order by p.title, v.sku, loc.code)
      from better_supabase.product_variants v
      join better_supabase.products p on p.id = v.product_id
      join better_supabase.inventory_locations loc
        on loc.tenant_id = v.tenant_id and loc.active
      left join better_supabase.stock_levels l
        on l.variant_id = v.id and l.location_id = loc.id
      where v.tenant_id = shop_stock_levels.tenant
        and v.track_inventory
        and p.status <> 'archived'
    ), '[]'::jsonb)
  );
$$;

revoke all on function api.shop_stock_levels(uuid) from public, anon;
grant execute on function api.shop_stock_levels(uuid) to authenticated;
