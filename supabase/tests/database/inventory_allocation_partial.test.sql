-- Partial release and transfer of an allocation. The admin (…00a1) of Acme
-- (…0001) holds 6 of 10 pieces for a quote with 4 on backorder. Releasing 3
-- frees backorder first, and transferring 5 splits the allocation and moves
-- the held stock first.
begin;
select plan(11);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Nut', 'nut', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'NUT-1', null, 'Nut', null, null, true, false, null) ->> 'id', true);
select set_config('t.l', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'WH8', 'Warehouse 8', null, null) ->> 'id', true);
select better_supabase.adjust_stock(current_setting('t.v')::uuid, current_setting('t.l')::uuid, 6, 'receipt', 'in', null);
select set_config('t.a', (better_supabase.allocate_stock('00000000-0000-4000-8000-000000000001', current_setting('t.v')::uuid, current_setting('t.l')::uuid, 10, 'quote', 'q1', 'l1', true) ->> 'id'), true);

select is(
  (select jsonb_build_array((x ->> 'quantity')::numeric, (x ->> 'allocated')::numeric, (x ->> 'backordered')::numeric)
   from jsonb_array_elements(better_supabase.list_allocations('00000000-0000-4000-8000-000000000001', 'quote', 'q1')) x),
  '[10, 6, 4]'::jsonb,
  'the allocation holds 6 and waits for 4'
);

select is(
  (select jsonb_build_array((x ->> 'quantity')::numeric, (x ->> 'allocated')::numeric, x ->> 'status')
   from jsonb_array_elements(jsonb_build_array(better_supabase.release_allocation(current_setting('t.a')::uuid, 3))) x),
  '[7, 6, "open"]'::jsonb,
  'releasing 3 frees backorder first and keeps what it holds'
);

select throws_ok(
  format($$select better_supabase.release_allocation(%L, 0)$$, current_setting('t.a')),
  '22023',
  'the quantity must be more than zero and at most what the allocation has left',
  'a release of nothing is refused'
);
select throws_ok(
  format($$select better_supabase.release_allocation(%L, 8)$$, current_setting('t.a')),
  '22023',
  'the quantity must be more than zero and at most what the allocation has left',
  'a release of more than is left is refused'
);

select is(
  (select jsonb_build_array((x ->> 'quantity')::numeric, (x ->> 'allocated')::numeric, x ->> 'documentId')
   from jsonb_array_elements(jsonb_build_array(better_supabase.transfer_allocation(current_setting('t.a')::uuid, 'order', 'o1', 'l9', 5))) x),
  '[5, 5, "o1"]'::jsonb,
  'transferring 5 moves held stock first into a new allocation on the order'
);
select is(
  (select jsonb_build_array((x ->> 'quantity')::numeric, (x ->> 'allocated')::numeric, (x ->> 'backordered')::numeric)
   from jsonb_array_elements(better_supabase.list_allocations('00000000-0000-4000-8000-000000000001', 'quote', 'q1')) x),
  '[2, 1, 1]'::jsonb,
  'the quote keeps the rest'
);
select is(
  (select (y ->> 'allocated')::numeric from jsonb_array_elements(better_supabase.inventory_levels('00000000-0000-4000-8000-000000000001', array[current_setting('t.v')::uuid])) y limit 1),
  6::numeric,
  'the split reserves the same stock in total'
);
select throws_ok(
  format($$select better_supabase.transfer_allocation(%L, 'order', 'o2', null, 3)$$, current_setting('t.a')),
  '22023',
  'the quantity must be more than zero and at most what the allocation has left',
  'a transfer of more than is left is refused'
);

select is(
  better_supabase.release_allocation(current_setting('t.a')::uuid, 2) ->> 'status',
  'released',
  'releasing all that is left releases the allocation'
);
reset role;
select is(
  (select count(*)::int from better_supabase.outbox_events where type = 'allocation.released' and payload ->> 'released' = '3'),
  1,
  'a partial release records the released quantity'
);
select is(
  (select count(*)::int from better_supabase.outbox_events where type = 'allocation.transferred' and payload ->> 'transferred' = '5'),
  1,
  'a partial transfer records the transferred quantity'
);

select * from finish();
rollback;
