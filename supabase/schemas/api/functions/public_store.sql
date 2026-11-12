-- The public store: what an anonymous visitor may read of an organization that
-- published its storefront. SECURITY DEFINER because the block tables grant
-- nothing to anon; each function checks the published storefront itself and
-- returns only public fields. Stock is a bucket (in_stock, low, out), never a
-- count.
create or replace function api.public_store_catalog(
  org_slug text,
  q text default null,
  sort text default 'newest',
  only_in_stock boolean default false,
  currency text default 'EUR'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with store as (
    select o.id, o.name, o.slug
    from public.organizations o
    join better_supabase.catalog_storefronts s
      on s.tenant_id = o.id and s.published_at is not null
    where o.slug = public_store_catalog.org_slug
  ),
  items as (
    select
      p.id,
      p.slug,
      p.title,
      p.description,
      p.kind,
      p.created_at,
      first_variant.id as variant_id,
      first_variant.sku,
      price.amount,
      price.compare_at_amount,
      stock.available,
      coalesce(
        not first_variant.track_inventory or first_variant.allow_backorder or stock.available > 0,
        false
      ) as in_stock
    from store
    join better_supabase.products p on p.tenant_id = store.id and p.status = 'active'
    join lateral (
      select v.id, v.sku, v.track_inventory, v.allow_backorder
      from better_supabase.product_variants v
      where v.product_id = p.id
      order by v.rank collate "C"
      limit 1
    ) first_variant on true
    left join lateral (
      select pr.amount, pr.compare_at_amount
      from better_supabase.product_prices pr
      where pr.variant_id = first_variant.id
        and pr.currency = public_store_catalog.currency
        and pr.price_list_id is null
        and (pr.starts_at is null or pr.starts_at <= now())
        and (pr.expires_at is null or pr.expires_at > now())
      order by pr.starts_at desc nulls last
      limit 1
    ) price on true
    left join lateral (
      select sum(l.available) as available
      from better_supabase.stock_levels l
      where l.variant_id = first_variant.id
    ) stock on true
    where (
      public_store_catalog.q is null
      or public_store_catalog.q = ''
      or p.title ilike '%' || replace(replace(replace(public_store_catalog.q, '\', '\\'), '%', '\%'), '_', '\_') || '%'
      or coalesce(p.description, '') ilike '%' || replace(replace(replace(public_store_catalog.q, '\', '\\'), '%', '\%'), '_', '\_') || '%'
    )
  )
  select jsonb_build_object(
    'store', (select jsonb_build_object('name', name, 'slug', slug) from store),
    'products', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', i.id,
          'slug', i.slug,
          'title', i.title,
          'description', i.description,
          'kind', i.kind,
          'variantId', i.variant_id,
          'sku', i.sku,
          'amount', i.amount::text,
          'compareAt', i.compare_at_amount::text,
          'stock', case
            when i.in_stock and coalesce(i.available, 0) between 1 and 5 then 'low'
            when i.in_stock then 'in_stock'
            else 'out'
          end
        )
        order by
          case when public_store_catalog.sort = 'price_asc' then i.amount end asc nulls last,
          case when public_store_catalog.sort = 'price_desc' then i.amount end desc nulls last,
          case when public_store_catalog.sort = 'title' then i.title end asc,
          i.created_at desc,
          i.id
      )
      from items i
      where not public_store_catalog.only_in_stock or i.in_stock
    ), '[]'::jsonb)
  )
  where exists (select 1 from store);
$$;

create or replace function api.public_store_product(
  org_slug text,
  product_slug text,
  currency text default 'EUR'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'store', jsonb_build_object('name', o.name, 'slug', o.slug),
    'product', jsonb_build_object(
      'id', p.id,
      'slug', p.slug,
      'title', p.title,
      'description', p.description,
      'kind', p.kind,
      'manufacturer', p.manufacturer,
      'model', p.model,
      'variants', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', v.id,
            'sku', v.sku,
            'title', v.title,
            'amount', price.amount::text,
            'compareAt', price.compare_at_amount::text,
            'stock', case
              when not v.track_inventory or v.allow_backorder or stock.available > 5 then 'in_stock'
              when stock.available > 0 then 'low'
              else 'out'
            end
          )
          order by v.rank collate "C"
        )
        from better_supabase.product_variants v
        left join lateral (
          select pr.amount, pr.compare_at_amount
          from better_supabase.product_prices pr
          where pr.variant_id = v.id
            and pr.currency = public_store_product.currency
            and pr.price_list_id is null
            and (pr.starts_at is null or pr.starts_at <= now())
            and (pr.expires_at is null or pr.expires_at > now())
          order by pr.starts_at desc nulls last
          limit 1
        ) price on true
        left join lateral (
          select sum(l.available) as available
          from better_supabase.stock_levels l
          where l.variant_id = v.id
        ) stock on true
        where v.product_id = p.id
      ), '[]'::jsonb)
    )
  )
  from public.organizations o
  join better_supabase.catalog_storefronts s
    on s.tenant_id = o.id and s.published_at is not null
  join better_supabase.products p
    on p.tenant_id = o.id and p.status = 'active' and p.slug = public_store_product.product_slug
  where o.slug = public_store_product.org_slug;
$$;

-- The variants in a visitor's cart, with their current price and stock bucket.
create or replace function api.public_store_variants(
  org_slug text,
  variant_ids uuid[],
  currency text default 'EUR'
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'variantId', v.id,
      'productSlug', p.slug,
      'title', p.title,
      'variantTitle', v.title,
      'sku', v.sku,
      'amount', price.amount::text,
      'stock', case
        when not v.track_inventory or v.allow_backorder or stock.available > 5 then 'in_stock'
        when stock.available > 0 then 'low'
        else 'out'
      end
    )
    order by p.title, v.rank collate "C"
  ), '[]'::jsonb)
  from public.organizations o
  join better_supabase.catalog_storefronts s
    on s.tenant_id = o.id and s.published_at is not null
  join better_supabase.products p on p.tenant_id = o.id and p.status = 'active'
  join better_supabase.product_variants v on v.product_id = p.id
  left join lateral (
    select pr.amount
    from better_supabase.product_prices pr
    where pr.variant_id = v.id
      and pr.currency = public_store_variants.currency
      and pr.price_list_id is null
      and (pr.starts_at is null or pr.starts_at <= now())
      and (pr.expires_at is null or pr.expires_at > now())
    order by pr.starts_at desc nulls last
    limit 1
  ) price on true
  left join lateral (
    select sum(l.available) as available
    from better_supabase.stock_levels l
    where l.variant_id = v.id
  ) stock on true
  where o.slug = public_store_variants.org_slug
    and v.id = any (public_store_variants.variant_ids);
$$;

revoke all on function api.public_store_catalog(text, text, text, boolean, text) from public;
revoke all on function api.public_store_product(text, text, text) from public;
revoke all on function api.public_store_variants(text, uuid[], text) from public;
grant execute on function api.public_store_catalog(text, text, text, boolean, text) to anon, authenticated, service_role;
grant execute on function api.public_store_product(text, text, text) to anon, authenticated, service_role;
grant execute on function api.public_store_variants(text, uuid[], text) to anon, authenticated, service_role;
