-- Each built-in import entity, 2,000 new items, timed three ways (ADRs 0436
-- and 1217): the import (import_upsert_batch, through the entity's batch
-- function when it has one), the one-row write function
-- called in a loop, and one set-based insert of the same rows. The loop minus
-- the set insert bounds what a batch target can save. Timings print as
-- SCALE_MS lines.
begin;
select plan(6);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

create temp table t0 (t timestamptz);
grant all on t0 to public;

create function pg_temp.mark() returns void language sql as $$
  delete from t0; insert into t0 values (clock_timestamp());
$$;

create function pg_temp.ms(label text) returns text language sql as $$
  select diag('SCALE_MS ' || label || '=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));
$$;

create function pg_temp.run(name text) returns uuid language plpgsql as $$
declare v uuid;
begin
  v := (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', name, '{}'::jsonb) ->> 'id')::uuid;
  perform better_supabase.mark_import_running(v);
  return v;
end $$;

create function pg_temp.loop(fn regproc, run uuid, items jsonb) returns void language plpgsql as $$
declare i jsonb;
begin
  for i in select e from jsonb_array_elements(items) e loop
    execute format('select %s($1, $2, null)', fn)
      using run, jsonb_build_object('tenant', '00000000-0000-4000-8000-000000000001', 'data', i -> 'data', 'resolved', '{}'::jsonb);
  end loop;
end $$;

create function pg_temp.items(prefix text, data text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  execute format($q$select jsonb_agg(jsonb_build_object('key', %L || g, 'scope', '', 'data', %s, 'refs', '{}'::jsonb)) from generate_series(1, 2000) g$q$, prefix, data) into v;
  return v;
end $$;

-- Fixture rows the stock entities point at.
insert into better_supabase.inventory_locations (tenant_id, code, name)
values ('00000000-0000-4000-8000-000000000001', 'scale-paths', 'Scale paths');
select id as location from better_supabase.inventory_locations where code = 'scale-paths' \gset
insert into better_supabase.companies (tenant_id, name, legal_name, lifecycle, roles) values ('00000000-0000-4000-8000-000000000001', 'Scale supplier', 'Scale supplier', 'lead', '{}') returning id as supplier \gset
insert into better_supabase.products (tenant_id, title, slug)
select '00000000-0000-4000-8000-000000000001', 'Scale ' || g, 'scale-paths-' || g from generate_series(1, 2000) g;
insert into better_supabase.product_variants (tenant_id, product_id, sku)
select p.tenant_id, p.id, 'scale-paths-' || substr(p.slug, 13) from better_supabase.products p where p.slug like 'scale-paths-%';
create temp table variants as
  select row_number() over (order by sku) as n, id from better_supabase.product_variants where sku like 'scale-paths-%';
grant all on variants to public;

set local role service_role;

-- party
select pg_temp.mark();
select (better_supabase.import_upsert_batch(pg_temp.run('p-import'), 'party', pg_temp.items('pi', $$jsonb_build_object('displayName', 'Party ' || g || ' B.V.', 'kind', 'company', 'roles', jsonb_build_array())$$)) ->> 'inserted')::int as n \gset
select pg_temp.ms('party_import');
select is(:n, 2000, 'party: every item imported');
select pg_temp.mark();
select pg_temp.loop('better_supabase.import_party', pg_temp.run('p-loop'), pg_temp.items('pl', $$jsonb_build_object('displayName', 'Loop ' || g || ' B.V.', 'kind', 'company', 'roles', jsonb_build_array())$$));
select pg_temp.ms('party_loop');
select pg_temp.mark();
insert into better_supabase.companies (tenant_id, name, legal_name, lifecycle, roles)
select '00000000-0000-4000-8000-000000000001', 'Set ' || g || ' B.V.', 'Set ' || g || ' B.V.', 'lead', '{}' from generate_series(1, 2000) g;
select pg_temp.ms('party_set');

-- product
select pg_temp.mark();
select (better_supabase.import_upsert_batch(pg_temp.run('pr-import'), 'product', pg_temp.items('ri', $$jsonb_build_object('name', 'Product ' || g, 'sku', 'ri-' || g)$$)) ->> 'inserted')::int as n \gset
select pg_temp.ms('product_import');
select is(:n, 2000, 'product: every item imported');
select pg_temp.mark();
select pg_temp.loop('better_supabase.import_product', pg_temp.run('pr-loop'), pg_temp.items('rl', $$jsonb_build_object('name', 'Loop product ' || g, 'sku', 'rl-' || g)$$));
select pg_temp.ms('product_loop');
select pg_temp.mark();
with p as (
  insert into better_supabase.products (tenant_id, title, slug)
  select '00000000-0000-4000-8000-000000000001', 'Set product ' || g, 'set-product-' || g from generate_series(1, 2000) g
  returning id, tenant_id, slug
)
insert into better_supabase.product_variants (tenant_id, product_id, sku)
select tenant_id, id, 'rs-' || substr(slug, 13) from p;
select pg_temp.ms('product_set');

-- supplier_item
select pg_temp.mark();
select (better_supabase.import_upsert_batch(pg_temp.run('s-import'), 'supplier_item', pg_temp.items('si', format($$jsonb_build_object('supplierId', %L, 'code', 'si-' || g, 'price', 100, 'currency', 'EUR')$$, :'supplier'))) ->> 'inserted')::int as n \gset
select pg_temp.ms('supplier_item_import');
select is(:n, 2000, 'supplier_item: every item imported');
select pg_temp.mark();
select pg_temp.loop('better_supabase.import_supplier_item', pg_temp.run('s-loop'), pg_temp.items('sl', format($$jsonb_build_object('supplierId', %L, 'code', 'sl-' || g, 'price', 100, 'currency', 'EUR')$$, :'supplier')));
select pg_temp.ms('supplier_item_loop');
select pg_temp.mark();
insert into better_supabase.supplier_items (tenant_id, supplier_id, code, price, currency)
select '00000000-0000-4000-8000-000000000001', :'supplier', 'ss-' || g, 100, 'EUR' from generate_series(1, 2000) g;
select pg_temp.ms('supplier_item_set');

-- asset
select pg_temp.mark();
select (better_supabase.import_upsert_batch(pg_temp.run('a-import'), 'asset', pg_temp.items('ai', $$jsonb_build_object('name', 'Asset ' || g)$$)) ->> 'inserted')::int as n \gset
select pg_temp.ms('asset_import');
select is(:n, 2000, 'asset: every item imported');
select pg_temp.mark();
select pg_temp.loop('better_supabase.import_asset', pg_temp.run('a-loop'), pg_temp.items('al', $$jsonb_build_object('name', 'Loop asset ' || g)$$));
select pg_temp.ms('asset_loop');
select pg_temp.mark();
insert into better_supabase.assets (tenant_id, kind, name)
select '00000000-0000-4000-8000-000000000001', 'asset', 'Set asset ' || g from generate_series(1, 2000) g;
select pg_temp.ms('asset_set');

-- stock_allocation
select pg_temp.mark();
select (better_supabase.import_upsert_batch(pg_temp.run('sa-import'), 'stock_allocation', pg_temp.items('ai', format($$jsonb_build_object('variantId', (select id from variants where n = g), 'locationId', %L, 'quantity', 1, 'documentType', 'order', 'documentId', gen_random_uuid())$$, :'location'))) ->> 'inserted')::int as n \gset
select pg_temp.ms('stock_allocation_import');
select is(:n, 2000, 'stock_allocation: every item imported');
select pg_temp.mark();
select pg_temp.loop('better_supabase.import_stock_allocation', pg_temp.run('sa-loop'), pg_temp.items('al', format($$jsonb_build_object('variantId', (select id from variants where n = g), 'locationId', %L, 'quantity', 1, 'documentType', 'order', 'documentId', gen_random_uuid())$$, :'location')));
select pg_temp.ms('stock_allocation_loop');
select pg_temp.mark();
insert into better_supabase.stock_allocations (tenant_id, variant_id, location_id, document_type, document_id, quantity)
select '00000000-0000-4000-8000-000000000001', v.id, :'location', 'order', gen_random_uuid(), 1 from variants v;
select pg_temp.ms('stock_allocation_set');

-- stock_count, one line each
select pg_temp.mark();
select (better_supabase.import_upsert_batch(pg_temp.run('c-import'), 'stock_count', pg_temp.items('ci', format($$jsonb_build_object('locationId', %L, 'lines', jsonb_build_array(jsonb_build_object('variantId', (select id from variants where n = g), 'counted', 3)))$$, :'location'))) ->> 'inserted')::int as n \gset
select pg_temp.ms('stock_count_import');
select is(:n, 2000, 'stock_count: every item imported');
select pg_temp.mark();
select pg_temp.loop('better_supabase.import_stock_count', pg_temp.run('c-loop'), pg_temp.items('cl', format($$jsonb_build_object('locationId', %L, 'lines', jsonb_build_array(jsonb_build_object('variantId', (select id from variants where n = g), 'counted', 3)))$$, :'location')));
select pg_temp.ms('stock_count_loop');
select pg_temp.mark();
with c as (
  insert into better_supabase.stock_counts (tenant_id, location_id)
  select '00000000-0000-4000-8000-000000000001', :'location' from generate_series(1, 2000) g
  returning id
), n as (select row_number() over () as n, id from c)
insert into better_supabase.stock_count_lines (tenant_id, count_id, variant_id, counted)
select '00000000-0000-4000-8000-000000000001', n.id, v.id, 3 from n join variants v using (n);
select pg_temp.ms('stock_count_set');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
