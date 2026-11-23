-- The built-in batch targets (ADR 1217): party, product, stock_allocation and
-- stock_count write through their batch function on one source and through
-- the per-item write on the other, with the batch function replaced by one
-- that raises so the import falls back item by item. Counts, errors, rows,
-- record map entries, reruns, repeated keys and refused rows must match.
begin;
select plan(25);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

create temp table saved (fn text primary key, def text);

-- Swap a batch function for one that raises, and back.
create function pg_temp.batch_off(fn text) returns void language plpgsql as $$
begin
  insert into saved values (fn, pg_get_functiondef(fn::regproc)) on conflict do nothing;
  execute format('create or replace function %s(run uuid, items jsonb) returns jsonb language plpgsql as $f$ begin raise exception ''batch off''; end $f$', fn);
end $$;

create function pg_temp.batch_on(fn text) returns void language plpgsql as $$
begin
  execute (select def from saved s where s.fn = batch_on.fn);
end $$;

create function pg_temp.items(prefix text, n int, data text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  execute format('select jsonb_agg(jsonb_build_object(''key'', ''k-'' || g, ''scope'', '''', ''data'', %s, ''refs'', ''{}''::jsonb)) from generate_series(1, $2) g, (select $1 as p) p', data)
    into v using prefix, n;
  return v;
end $$;

-- Runs the items on source par-a-<entity> through the batch target and on
-- par-b-<entity> through the per-item write; returns both results.
create function pg_temp.pair(entity text, fn text, a jsonb, b jsonb) returns jsonb language plpgsql as $$
declare
  ra uuid := (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'par-a-' || entity, '{}'::jsonb) ->> 'id')::uuid;
  rb uuid := (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'par-b-' || entity, '{}'::jsonb) ->> 'id')::uuid;
  va jsonb;
  vb jsonb;
begin
  perform better_supabase.mark_import_running(ra);
  perform better_supabase.mark_import_running(rb);
  va := better_supabase.import_upsert_batch(ra, entity, a);
  perform pg_temp.batch_off(fn);
  vb := better_supabase.import_upsert_batch(rb, entity, b);
  perform pg_temp.batch_on(fn);
  perform better_supabase.finish_import_run(ra);
  perform better_supabase.finish_import_run(rb);
  return jsonb_build_object('a', va - 'dryRun' - 'warnings', 'b', vb - 'dryRun' - 'warnings');
end $$;

create function pg_temp.same(r jsonb) returns boolean language sql as $$
  select r -> 'a' = r -> 'b'
$$;

create function pg_temp.map(entity text, side text) returns jsonb language sql as $$
  select jsonb_build_array(count(*), count(distinct content_hash), min(subject_type))
  from better_supabase.import_records where source = 'par-' || side || '-' || entity
$$;

create function pg_temp.subjects(entity text, side text) returns setof uuid language sql as $$
  select subject_id::uuid from better_supabase.import_records where source = 'par-' || side || '-' || entity
$$;

-- Fixture rows the stock entities point at, with stock on hand for half the variants.
insert into better_supabase.inventory_locations (tenant_id, code, name)
values ('00000000-0000-4000-8000-000000000001', 'parity', 'Parity');
select id as location from better_supabase.inventory_locations where code = 'parity' \gset
insert into better_supabase.products (tenant_id, title, slug)
select '00000000-0000-4000-8000-000000000001', 'Parity stock ' || g, 'parity-stock-' || g from generate_series(1, 60) g;
insert into better_supabase.product_variants (tenant_id, product_id, sku)
select p.tenant_id, p.id, p.slug from better_supabase.products p where p.slug like 'parity-stock-%';
create temp table variants as
  select row_number() over (order by sku) as n, id from better_supabase.product_variants where sku like 'parity-stock-%';
insert into better_supabase.stock_levels (tenant_id, variant_id, location_id, on_hand)
select '00000000-0000-4000-8000-000000000001', v.id, :'location', v.n * 2 from variants v where v.n % 2 = 0;

-- party: companies, people with an email, auto kinds and a name fallback.
create temp table r (name text primary key, result jsonb);
insert into r values ('party', pg_temp.pair('party', 'better_supabase.import_party_batch',
  pg_temp.items('A', 60, $$case when g % 3 = 0 then jsonb_build_object('displayName', p || ' Co ' || g || ' B.V.', 'roles', '[]'::jsonb)
    when g % 3 = 1 then jsonb_build_object('kind', 'person', 'displayName', p || ' Person ' || g, 'email', lower(p) || g || '@parity.test', 'roles', '[]'::jsonb)
    else jsonb_build_object('kind', 'company', 'legalName', p || ' Legal ' || g, 'roles', '[]'::jsonb) end$$),
  pg_temp.items('B', 60, $$case when g % 3 = 0 then jsonb_build_object('displayName', p || ' Co ' || g || ' B.V.', 'roles', '[]'::jsonb)
    when g % 3 = 1 then jsonb_build_object('kind', 'person', 'displayName', p || ' Person ' || g, 'email', lower(p) || g || '@parity.test', 'roles', '[]'::jsonb)
    else jsonb_build_object('kind', 'company', 'legalName', p || ' Legal ' || g, 'roles', '[]'::jsonb) end$$)));
select ok(pg_temp.same((select result from r where name = 'party')), 'party: the counts and errors are equal');
select is((select (result -> 'a' ->> 'inserted')::int from r where name = 'party'), 60, 'party: the batch path inserted every item');
select is(pg_temp.map('party', 'a'), pg_temp.map('party', 'b'), 'party: the record maps have the same shape');
select is(
  (select md5(string_agg(substr(x.name, 3) || '|' || substr(coalesce(x.legal_name, ''), 3) || '|' || x.lifecycle, ',' order by substr(x.name, 3)))
    from better_supabase.companies x where x.id in (select pg_temp.subjects('party', 'a'))),
  (select md5(string_agg(substr(x.name, 3) || '|' || substr(coalesce(x.legal_name, ''), 3) || '|' || x.lifecycle, ',' order by substr(x.name, 3)))
    from better_supabase.companies x where x.id in (select pg_temp.subjects('party', 'b'))),
  'party: the company rows are equal'
);
select is(
  (select md5(string_agg(substr(x.name, 3) || '|' || substr(x.email, 2) || '|' || x.lifecycle, ',' order by substr(x.name, 3)))
    from better_supabase.people x where x.id in (select pg_temp.subjects('party', 'a'))),
  (select md5(string_agg(substr(x.name, 3) || '|' || substr(x.email, 2) || '|' || x.lifecycle, ',' order by substr(x.name, 3)))
    from better_supabase.people x where x.id in (select pg_temp.subjects('party', 'b'))),
  'party: the person rows are equal'
);
-- One email twice, a repeated key and a party without a name.
insert into r values ('party2', pg_temp.pair('party', 'better_supabase.import_party_batch',
  '[{"key":"d-1","data":{"kind":"person","displayName":"Dup","email":"dup-a@parity.test","roles":[]}},{"key":"d-2","data":{"kind":"person","displayName":"Dup two","email":"dup-a@parity.test","roles":[]}},{"key":"d-3","data":{"displayName":"Rep","roles":[]}},{"key":"d-3","data":{"displayName":"Rep again","roles":[]}},{"key":"d-4","data":{"roles":[]}}]',
  '[{"key":"d-1","data":{"kind":"person","displayName":"Dup","email":"dup-b@parity.test","roles":[]}},{"key":"d-2","data":{"kind":"person","displayName":"Dup two","email":"dup-b@parity.test","roles":[]}},{"key":"d-3","data":{"displayName":"Rep","roles":[]}},{"key":"d-3","data":{"displayName":"Rep again","roles":[]}},{"key":"d-4","data":{"roles":[]}}]'));
select is(
  (select jsonb_build_array(result -> 'a' -> 'inserted', jsonb_path_query_array(result -> 'a' -> 'errors', '$[*].key')) from r where name = 'party2'),
  (select jsonb_build_array(result -> 'b' -> 'inserted', jsonb_path_query_array(result -> 'b' -> 'errors', '$[*].key')) from r where name = 'party2'),
  'party: a shared email, a repeated key and a refused row come out the same'
);
-- A rerun of the first items: unchanged on both paths.
insert into r values ('party3', pg_temp.pair('party', 'better_supabase.import_party_batch',
  pg_temp.items('A', 60, $$case when g % 3 = 0 then jsonb_build_object('displayName', p || ' Co ' || g || ' B.V.', 'roles', '[]'::jsonb)
    when g % 3 = 1 then jsonb_build_object('kind', 'person', 'displayName', p || ' Person ' || g, 'email', lower(p) || g || '@parity.test', 'roles', '[]'::jsonb)
    else jsonb_build_object('kind', 'company', 'legalName', p || ' Legal ' || g, 'roles', '[]'::jsonb) end$$),
  pg_temp.items('B', 60, $$case when g % 3 = 0 then jsonb_build_object('displayName', p || ' Co ' || g || ' B.V.', 'roles', '[]'::jsonb)
    when g % 3 = 1 then jsonb_build_object('kind', 'person', 'displayName', p || ' Person ' || g, 'email', lower(p) || g || '@parity.test', 'roles', '[]'::jsonb)
    else jsonb_build_object('kind', 'company', 'legalName', p || ' Legal ' || g, 'roles', '[]'::jsonb) end$$)));
select ok(pg_temp.same((select result from r where name = 'party3')), 'party: a rerun counts the same on both paths');

-- product: a name, a sku and an ean; the slug repeats once.
insert into r values ('product', pg_temp.pair('product', 'better_supabase.import_product_batch',
  pg_temp.items('a', 40, $$jsonb_build_object('name', p || ' Product ' || case when g = 40 then '1' else g::text end, 'sku', case when g % 4 = 0 then null else p || '-sku-' || g end, 'ean', '87' || g, 'price', g * 100)$$),
  pg_temp.items('b', 40, $$jsonb_build_object('name', p || ' Product ' || case when g = 40 then '1' else g::text end, 'sku', case when g % 4 = 0 then null else p || '-sku-' || g end, 'ean', '87' || g, 'price', g * 100)$$)));
select ok(pg_temp.same((select result from r where name = 'product')), 'product: the counts and errors are equal');
select is(pg_temp.map('product', 'a'), pg_temp.map('product', 'b'), 'product: the record maps have the same shape');
select is(
  (select md5(string_agg(substr(x.title, 3) || '|' || substr(x.slug, 2) || '|' || substr(y.sku, 2) || '|' || coalesce(y.barcode, ''), ',' order by substr(x.title, 3), substr(x.slug, 2)))
    from better_supabase.products x join better_supabase.product_variants y on y.product_id = x.id where x.id in (select pg_temp.subjects('product', 'a'))),
  (select md5(string_agg(substr(x.title, 3) || '|' || substr(x.slug, 2) || '|' || substr(y.sku, 2) || '|' || coalesce(y.barcode, ''), ',' order by substr(x.title, 3), substr(x.slug, 2)))
    from better_supabase.products x join better_supabase.product_variants y on y.product_id = x.id where x.id in (select pg_temp.subjects('product', 'b'))),
  'product: the products and their variants are equal'
);
insert into r values ('product2', pg_temp.pair('product', 'better_supabase.import_product_batch',
  '[{"key":"d-1","data":{"name":"a Dup","sku":"a-dup"}},{"key":"d-2","data":{"name":"a Other","sku":"a-dup"}},{"key":"d-3","data":{"name":"   "}},{"key":"d-4","data":{"name":"a Price","price":"x"}}]',
  '[{"key":"d-1","data":{"name":"b Dup","sku":"b-dup"}},{"key":"d-2","data":{"name":"b Other","sku":"b-dup"}},{"key":"d-3","data":{"name":"   "}},{"key":"d-4","data":{"name":"b Price","price":"x"}}]'));
select is(
  (select jsonb_build_array(result -> 'a' -> 'inserted', jsonb_path_query_array(result -> 'a' -> 'errors', '$[*].key')) from r where name = 'product2'),
  (select jsonb_build_array(result -> 'b' -> 'inserted', jsonb_path_query_array(result -> 'b' -> 'errors', '$[*].key')) from r where name = 'product2'),
  'product: a shared sku, a blank name and a bad price come out the same'
);
insert into r values ('product3', pg_temp.pair('product', 'better_supabase.import_product_batch',
  pg_temp.items('a', 40, $$jsonb_build_object('name', p || ' Product ' || case when g = 40 then '1' when g <= 5 then g || ' v2' else g::text end, 'sku', case when g % 4 = 0 then null else p || '-sku-' || g end, 'ean', '87' || g, 'price', g * 100)$$),
  pg_temp.items('b', 40, $$jsonb_build_object('name', p || ' Product ' || case when g = 40 then '1' when g <= 5 then g || ' v2' else g::text end, 'sku', case when g % 4 = 0 then null else p || '-sku-' || g end, 'ean', '87' || g, 'price', g * 100)$$)));
select ok(pg_temp.same((select result from r where name = 'product3')), 'product: a rerun with five renames counts the same');
select is((select (result -> 'a' ->> 'updated')::int from r where name = 'product3'), 5, 'product: five products updated');

-- stock_allocation: two allocations per variant across the paths.
insert into r values ('allocation', pg_temp.pair('stock_allocation', 'better_supabase.import_stock_allocation_batch',
  pg_temp.items('a', 60, format($$jsonb_build_object('variantId', (select id from variants where n = g), 'locationId', %L, 'quantity', g %% 5 + 1, 'allocated', g %% 2, 'documentType', 'order', 'documentId', md5(p || g)::uuid)$$, :'location')),
  pg_temp.items('b', 60, format($$jsonb_build_object('variantId', (select id from variants where n = g), 'locationId', %L, 'quantity', g %% 5 + 1, 'allocated', g %% 2, 'documentType', 'order', 'documentId', md5(p || g)::uuid)$$, :'location'))));
select ok(pg_temp.same((select result from r where name = 'allocation')), 'stock_allocation: the counts and errors are equal');
select is((select (result -> 'a' ->> 'inserted')::int from r where name = 'allocation'), 60, 'stock_allocation: the batch path inserted every item');
select is(pg_temp.map('stock_allocation', 'a'), pg_temp.map('stock_allocation', 'b'), 'stock_allocation: the record maps have the same shape');
select is(
  (select md5(string_agg(x.variant_id || '|' || x.quantity || '|' || x.allocated || '|' || x.status, ',' order by x.variant_id))
    from better_supabase.stock_allocations x where x.id in (select pg_temp.subjects('stock_allocation', 'a'))),
  (select md5(string_agg(x.variant_id || '|' || x.quantity || '|' || x.allocated || '|' || x.status, ',' order by x.variant_id))
    from better_supabase.stock_allocations x where x.id in (select pg_temp.subjects('stock_allocation', 'b'))),
  'stock_allocation: the allocation rows are equal'
);
select is(
  (select count(*)::int from better_supabase.stock_levels l where l.location_id = :'location'
    and l.reserved <> (select coalesce(sum(x.allocated), 0) from better_supabase.stock_allocations x where x.variant_id = l.variant_id and x.location_id = l.location_id)),
  0,
  'stock_allocation: every level reserves what its allocations hold'
);
insert into r values ('allocation2', pg_temp.pair('stock_allocation', 'better_supabase.import_stock_allocation_batch',
  format('[{"key":"d-1","data":{"variantId":"%s","locationId":"%s","quantity":1,"documentType":"order","documentId":"%s"}},{"key":"d-2","data":{"variantId":"00000000-0000-4000-8000-0000000000ff","locationId":"%s","quantity":1,"documentType":"order"}},{"key":"d-3","data":{"variantId":"%s","locationId":"%s","quantity":-1,"documentType":"order"}}]',
    (select id from variants where n = 1), :'location', md5('dup-a')::uuid, :'location', (select id from variants where n = 2), :'location')::jsonb,
  format('[{"key":"d-1","data":{"variantId":"%s","locationId":"%s","quantity":1,"documentType":"order","documentId":"%s"}},{"key":"d-2","data":{"variantId":"00000000-0000-4000-8000-0000000000ff","locationId":"%s","quantity":1,"documentType":"order"}},{"key":"d-3","data":{"variantId":"%s","locationId":"%s","quantity":-1,"documentType":"order"}}]',
    (select id from variants where n = 1), :'location', md5('dup-b')::uuid, :'location', (select id from variants where n = 2), :'location')::jsonb));
select is(
  (select jsonb_build_array(result -> 'a' -> 'inserted', jsonb_path_query_array(result -> 'a' -> 'errors', '$[*].key')) from r where name = 'allocation2'),
  (select jsonb_build_array(result -> 'b' -> 'inserted', jsonb_path_query_array(result -> 'b' -> 'errors', '$[*].key')) from r where name = 'allocation2'),
  'stock_allocation: an unknown variant and a negative quantity come out the same'
);

-- stock_count: one or two lines, with the expected quantity from the books.
insert into r values ('count', pg_temp.pair('stock_count', 'better_supabase.import_stock_count_batch',
  pg_temp.items('a', 30, format($$jsonb_build_object('locationId', %L, 'note', p || g, 'lines', jsonb_build_array(jsonb_build_object('variantId', (select id from variants where n = g), 'counted', g %% 7))
    || case when g %% 2 = 0 then jsonb_build_array(jsonb_build_object('variantId', (select id from variants where n = g + 30), 'counted', 1, 'expected', 9)) else '[]'::jsonb end)$$, :'location')),
  pg_temp.items('b', 30, format($$jsonb_build_object('locationId', %L, 'note', p || g, 'lines', jsonb_build_array(jsonb_build_object('variantId', (select id from variants where n = g), 'counted', g %% 7))
    || case when g %% 2 = 0 then jsonb_build_array(jsonb_build_object('variantId', (select id from variants where n = g + 30), 'counted', 1, 'expected', 9)) else '[]'::jsonb end)$$, :'location'))));
select ok(pg_temp.same((select result from r where name = 'count')), 'stock_count: the counts and errors are equal');
select is((select (result -> 'a' ->> 'inserted')::int from r where name = 'count'), 30, 'stock_count: the batch path inserted every item');
select is(pg_temp.map('stock_count', 'a'), pg_temp.map('stock_count', 'b'), 'stock_count: the record maps have the same shape');
select is(
  (select md5(string_agg(substr(c.note, 2) || '|' || x.variant_id || '|' || x.expected || '|' || x.counted, ',' order by substr(c.note, 2), x.variant_id))
    from better_supabase.stock_counts c join better_supabase.stock_count_lines x on x.count_id = c.id where c.id in (select pg_temp.subjects('stock_count', 'a'))),
  (select md5(string_agg(substr(c.note, 2) || '|' || x.variant_id || '|' || x.expected || '|' || x.counted, ',' order by substr(c.note, 2), x.variant_id))
    from better_supabase.stock_counts c join better_supabase.stock_count_lines x on x.count_id = c.id where c.id in (select pg_temp.subjects('stock_count', 'b'))),
  'stock_count: the counts and their lines are equal'
);
select ok(
  (select bool_and(x.expected = coalesce((select l.on_hand from better_supabase.stock_levels l where l.variant_id = x.variant_id and l.location_id = :'location'), 0))
    from better_supabase.stock_count_lines x where x.count_id in (select pg_temp.subjects('stock_count', 'a')) and x.expected <> 9),
  'stock_count: a line without an expected quantity takes the books'
);
insert into r values ('count2', pg_temp.pair('stock_count', 'better_supabase.import_stock_count_batch',
  format('[{"key":"d-1","data":{"locationId":"%1$s","lines":[{"variantId":"%2$s","counted":-1}]}},{"key":"d-2","data":{"locationId":"%1$s","lines":[{"variantId":"%2$s","counted":1},{"variantId":"%2$s","counted":2}]}},{"key":"d-3","data":{"locationId":"%1$s","lines":[{"variantId":"%2$s","counted":4}]}},{"key":"d-3","data":{"locationId":"%1$s","lines":[{"variantId":"%2$s","counted":5}]}}]',
    :'location', (select id from variants where n = 3))::jsonb,
  format('[{"key":"d-1","data":{"locationId":"%1$s","lines":[{"variantId":"%2$s","counted":-1}]}},{"key":"d-2","data":{"locationId":"%1$s","lines":[{"variantId":"%2$s","counted":1},{"variantId":"%2$s","counted":2}]}},{"key":"d-3","data":{"locationId":"%1$s","lines":[{"variantId":"%2$s","counted":4}]}},{"key":"d-3","data":{"locationId":"%1$s","lines":[{"variantId":"%2$s","counted":5}]}}]',
    :'location', (select id from variants where n = 3))::jsonb));
select is(
  (select jsonb_build_array(result -> 'a' -> 'inserted', result -> 'a' -> 'updated', jsonb_path_query_array(result -> 'a' -> 'errors', '$[*].key')) from r where name = 'count2'),
  (select jsonb_build_array(result -> 'b' -> 'inserted', result -> 'b' -> 'updated', jsonb_path_query_array(result -> 'b' -> 'errors', '$[*].key')) from r where name = 'count2'),
  'stock_count: a negative count, a repeated variant and a repeated key come out the same'
);

select * from finish();
rollback;
