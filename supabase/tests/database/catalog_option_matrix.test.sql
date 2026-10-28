begin;
select plan(7);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Matrix Tee', 'matrix-tee', null, 'physical', null) ->> 'id', true);
select set_config('t.matrix', better_supabase.set_product_options(current_setting('t.product')::uuid, '[{"name": "Size", "values": ["S", "M"]}, {"name": "Colour", "values": ["Red"]}]')::text, true);

select is(
  (select array_agg(x.sku order by x.sku) from better_supabase.product_variants x where x.product_id = current_setting('t.product')::uuid),
  array['MATRIX-TEE-M-RED', 'MATRIX-TEE-S-RED'],
  'every combination gets a variant with a SKU from the slug and the values'
);
select is(
  (select array_agg(x.title order by x.sku) from better_supabase.product_variants x where x.product_id = current_setting('t.product')::uuid),
  array['M / Red', 'S / Red'],
  'titles are the values joined in option order'
);
select set_config('t.m', (select x.id::text from better_supabase.product_variants x where x.sku = 'MATRIX-TEE-M-RED'), true);

select is(
  jsonb_array_length(better_supabase.set_product_options(current_setting('t.product')::uuid, '[{"name": "Size", "values": ["M", "L"]}]') -> 'variants'),
  2,
  'dropping an option and a value leaves the new matrix'
);
select ok(
  exists (select 1 from better_supabase.product_variants x where x.id = current_setting('t.m')::uuid and x.title = 'M'),
  'the variant of a surviving combination keeps its id'
);
select ok(
  not exists (select 1 from better_supabase.product_variants x where x.sku = 'MATRIX-TEE-S-RED'),
  'the variant of a removed value is deleted'
);
select throws_ok(
  format($$select better_supabase.set_product_options(%L, '[{"name": "Size", "values": "M"}]')$$, current_setting('t.product')),
  '22023',
  null,
  'values must be a list'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  format($$select better_supabase.set_product_options(%L, '[]')$$, current_setting('t.product')),
  '42501',
  null,
  'a member without the update permission cannot replace options'
);

select * from finish();
rollback;
