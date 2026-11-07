-- One allocation released or moved to another document. The admin (…00a1) of
-- Acme (…0001) holds 10 pieces for a quote, moves the allocation to the
-- order, and releases it; a second allocation waits on backorder and takes the
-- freed stock. Globex (…00b1) moves and releases nothing of it.
begin;
select plan(14);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Bolt', 'bolt', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'BOLT-1', null, 'Bolt', null, null, true, false, null) ->> 'id', true);
select set_config('t.l', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'WH9', 'Warehouse 9', null, null) ->> 'id', true);
select better_supabase.adjust_stock(current_setting('t.v')::uuid, current_setting('t.l')::uuid, 10, 'receipt', 'in', null);

select set_config('t.a', (better_supabase.allocate_stock('00000000-0000-4000-8000-000000000001', current_setting('t.v')::uuid, current_setting('t.l')::uuid, 10, 'quote', 'q1', 'l1', true) ->> 'id'), true);
select set_config('t.b', (better_supabase.allocate_stock('00000000-0000-4000-8000-000000000001', current_setting('t.v')::uuid, current_setting('t.l')::uuid, 4, 'order', 'o2', null, true) ->> 'id'), true);

select is(
  (select (x ->> 'backordered')::numeric from jsonb_array_elements(better_supabase.list_allocations('00000000-0000-4000-8000-000000000001', 'order', 'o2')) x),
  4::numeric,
  'the second allocation waits on backorder'
);

select is(
  (select jsonb_build_array(x ->> 'documentType', x ->> 'documentId', x ->> 'lineId', (x ->> 'allocated')::numeric)
   from jsonb_array_elements(jsonb_build_array(better_supabase.transfer_allocation(current_setting('t.a')::uuid, 'order', 'o1', 'l7'))) x),
  '["order", "o1", "l7", 10]'::jsonb,
  'transfer_allocation moves the allocation to the order and keeps what it holds'
);
reset role;
select is(
  (select count(*)::int from better_supabase.outbox_events where type = 'allocation.transferred' and payload ->> 'toDocumentId' = 'o1' and payload ->> 'documentId' = 'q1'),
  1,
  'the move records allocation.transferred with the old and the new document'
);
set local role authenticated;
select is(
  jsonb_array_length(better_supabase.list_allocations('00000000-0000-4000-8000-000000000001', 'quote', 'q1')),
  0,
  'the quote has no allocation left'
);
select is(
  jsonb_array_length(better_supabase.list_allocations('00000000-0000-4000-8000-000000000001', 'order', 'o1')),
  1,
  'the order has it'
);
select throws_ok(
  format($$select better_supabase.transfer_allocation(%L, null, 'x', null)$$, current_setting('t.a')),
  '22023',
  'an allocation names its document type and id',
  'a transfer needs the new document'
);
select throws_ok(
  $$select better_supabase.transfer_allocation(gen_random_uuid(), 'order', 'o9', null)$$,
  'P0002',
  'allocation not found',
  'an unknown allocation cannot move'
);

select is(
  better_supabase.release_allocation(current_setting('t.a')::uuid) ->> 'status',
  'released',
  'release_allocation releases the one allocation'
);
select is(
  (select (x ->> 'allocated')::numeric from jsonb_array_elements(better_supabase.list_allocations('00000000-0000-4000-8000-000000000001', 'order', 'o2')) x),
  4::numeric,
  'the freed stock fills the waiting allocation'
);
select throws_ok(
  format($$select better_supabase.release_allocation(%L)$$, current_setting('t.a')),
  '55000',
  'the allocation is no longer open',
  'a released allocation cannot be released again'
);
select throws_ok(
  format($$select better_supabase.transfer_allocation(%L, 'order', 'o3', null)$$, current_setting('t.a')),
  '55000',
  'the allocation is no longer open',
  'a released allocation cannot move'
);
select is(
  (select x ->> 'status' from jsonb_array_elements(better_supabase.list_allocations('00000000-0000-4000-8000-000000000001', 'order', 'o2')) x),
  'open',
  'the other allocation stays open'
);

-- Another organization moves and releases nothing.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select throws_ok(
  format($$select better_supabase.transfer_allocation(%L, 'order', 'o5', null)$$, current_setting('t.b')),
  '42501',
  null,
  'a stranger cannot move the allocation'
);
select throws_ok(
  format($$select better_supabase.release_allocation(%L)$$, current_setting('t.b')),
  '42501',
  null,
  'a stranger cannot release the allocation'
);

select * from finish();
rollback;
