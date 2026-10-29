begin;
select plan(5);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Unique Mug', 'unique-mug', null, 'physical', null) ->> 'id', true);
select set_config('t.other', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Unique Cup', 'unique-cup', null, 'physical', null) ->> 'id', true);
select set_config('t.variant', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'UNIQUE-MUG', null, null, null, null, null, null) ->> 'id', true);

select ok(
  (select x.title is null and x.barcode is null from better_supabase.product_variants x where x.id = current_setting('t.variant')::uuid),
  'a variant without a title or barcode keeps the block table defaults'
);
select throws_ok(
  $$select better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Unique Mug', 'unique-mug', null, 'physical', null)$$,
  '23505',
  'another product has this slug',
  'a taken slug is reported as CATALOG_SLUG_TAKEN'
);
select throws_ok(
  format($$select better_supabase.save_variant(%L, null, 'UNIQUE-MUG', null, null, null, null, null, null)$$, current_setting('t.other')),
  '23505',
  'another variant has this SKU',
  'a taken SKU is reported as CATALOG_SKU_TAKEN'
);
select throws_ok(
  $$select better_supabase.save_category('00000000-0000-4000-8000-000000000001', null, null, 'Unique Kitchen', 'unique-kitchen', null), better_supabase.save_category('00000000-0000-4000-8000-000000000001', null, null, 'Unique Kitchen', 'unique-kitchen', null)$$,
  '23505',
  'another category has this slug',
  'a taken category slug is reported as CATALOG_SLUG_TAKEN'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  format($$select better_supabase.save_variant(%L, null, 'UNIQUE-CUP', null, null, null, null, null, null)$$, current_setting('t.other')),
  '42501',
  null,
  'a member without the create permission cannot add a variant'
);

select * from finish();
rollback;
