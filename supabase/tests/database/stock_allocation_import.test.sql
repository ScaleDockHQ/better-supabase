-- Stock allocation import (ADR 0669). A run imports an open allocation that
-- holds four of five units, one that already shipped and one released. The open
-- one adds four to the location's reserved stock; the others hold nothing. A
-- second run replaces the open allocation and keeps the shipped one as
-- imported, with a warning. No movement and no event is written. Run with
-- `supabase test db`.
begin;
select plan(8);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.p1', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Nut', 'nut-alloc-import', null, 'physical', null) ->> 'id', true);
select set_config('t.v1', better_supabase.save_variant(current_setting('t.p1')::uuid, null, 'NUT-1', null, 'Nut', null, null, true, false, null) ->> 'id', true);
select set_config('t.location', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'ALIMP', 'Allocation import dock', null, null) ->> 'id', true);

create function pg_temp.start_run(source text) returns void language plpgsql as $$
begin
  perform set_config('better_supabase.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', source, '{}'::jsonb) ->> 'id'), true);
end;
$$;

select pg_temp.start_run('allocations-hist');
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);
select is(
  (select better_supabase.import_upsert_batch(current_setting('better_supabase.run')::uuid, 'stock_allocation',
    jsonb_build_array(
      jsonb_build_object('key', 'a1', 'data', jsonb_build_object('variantId', current_setting('t.v1'), 'locationId', current_setting('t.location'),
        'documentType', 'sales_order', 'documentId', 'SO-1', 'lineId', '1', 'quantity', 5, 'allocated', 4)),
      jsonb_build_object('key', 'a2', 'data', jsonb_build_object('sku', 'NUT-1', 'location', 'ALIMP',
        'documentType', 'sales_order', 'documentId', 'SO-2', 'quantity', 3, 'status', 'fulfilled')),
      jsonb_build_object('key', 'a3', 'data', jsonb_build_object('variantId', current_setting('t.v1'), 'locationId', current_setting('t.location'),
        'documentType', 'sales_order', 'documentId', 'SO-3', 'quantity', 2, 'status', 'released'))
    )) ->> 'inserted'),
  '3',
  'the run inserts three allocations'
);
select better_supabase.finish_import_run(current_setting('better_supabase.run')::uuid);

select is(
  (select jsonb_agg(jsonb_build_array(document_id, quantity, allocated, fulfilled, backordered, status) order by document_id)
   from better_supabase.stock_allocations where document_id like 'SO-%' and variant_id = current_setting('t.v1')::uuid),
  '[["SO-1", 5, 4, 0, 1, "open"], ["SO-2", 3, 0, 3, 0, "fulfilled"], ["SO-3", 2, 0, 0, 0, "released"]]'::jsonb,
  'each allocation keeps what the source system had'
);
select is(
  (select reserved from better_supabase.stock_levels where variant_id = current_setting('t.v1')::uuid and location_id = current_setting('t.location')::uuid),
  4::numeric,
  'the open allocation reserves what it holds and the others hold nothing'
);
select is(
  (select on_hand from better_supabase.stock_levels where variant_id = current_setting('t.v1')::uuid and location_id = current_setting('t.location')::uuid),
  0::numeric,
  'no stock moved'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select pg_temp.start_run('allocations-hist');
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);
select is(
  (select better_supabase.import_upsert_batch(current_setting('better_supabase.run')::uuid, 'stock_allocation',
    jsonb_build_array(
      jsonb_build_object('key', 'a1', 'data', jsonb_build_object('variantId', current_setting('t.v1'), 'locationId', current_setting('t.location'),
        'documentType', 'sales_order', 'documentId', 'SO-1', 'lineId', '1', 'quantity', 5, 'allocated', 2, 'fulfilled', 2)),
      jsonb_build_object('key', 'a2', 'data', jsonb_build_object('sku', 'NUT-1', 'location', 'ALIMP',
        'documentType', 'sales_order', 'documentId', 'SO-2', 'quantity', 9, 'status', 'open', 'allocated', 9))
    )) -> 'warnings' -> 0 ->> 'code'),
  'IMPORT_DOCUMENT_CHANGED',
  'a fulfilled allocation is kept as imported, with a warning'
);
select better_supabase.finish_import_run(current_setting('better_supabase.run')::uuid);
select is(
  (select jsonb_build_array(quantity, allocated, fulfilled) from better_supabase.stock_allocations where document_id = 'SO-1' and variant_id = current_setting('t.v1')::uuid),
  '[5, 2, 2]'::jsonb,
  'an open allocation is replaced'
);
select is(
  (select quantity from better_supabase.stock_allocations where document_id = 'SO-2' and variant_id = current_setting('t.v1')::uuid),
  3::numeric,
  'the shipped allocation keeps its quantity'
);
select is(
  (select reserved from better_supabase.stock_levels where variant_id = current_setting('t.v1')::uuid and location_id = current_setting('t.location')::uuid),
  2::numeric,
  'the reserved stock follows the replaced allocation'
);

select * from finish();
rollback;
