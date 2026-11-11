-- Purchase order tax lines (ADR 0666). Saving a draft with taxRateBps on its
-- lines writes one tax line per code and rate, rounded per line; saving again
-- rebuilds them; a line without a rate adds none; a rate above 100000 is
-- refused; Globex (…b1) can't read them. Run with `supabase test db`.
begin;
select plan(7);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.p1', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Washer 1', 'washer-po-tax-1', null, 'physical', null) ->> 'id', true);
select set_config('t.p2', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Washer 2', 'washer-po-tax-2', null, 'physical', null) ->> 'id', true);
select set_config('t.p3', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Washer 3', 'washer-po-tax-3', null, 'physical', null) ->> 'id', true);
select set_config('t.v1', better_supabase.save_variant(current_setting('t.p1')::uuid, null, 'WASHER-1', null, 'Washer 1', null, null, true, false, null) ->> 'id', true);
select set_config('t.v2', better_supabase.save_variant(current_setting('t.p2')::uuid, null, 'WASHER-2', null, 'Washer 2', null, null, true, false, null) ->> 'id', true);
select set_config('t.v3', better_supabase.save_variant(current_setting('t.p3')::uuid, null, 'WASHER-3', null, 'Washer 3', null, null, true, false, null) ->> 'id', true);
select set_config('t.location', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'POTAX', 'PO tax dock', null, null) ->> 'id', true);

select set_config('t.po', better_supabase.save_purchase_order('00000000-0000-4000-8000-000000000001', null, current_setting('t.location')::uuid, null, null, 'EUR', null,
  jsonb_build_array(
    jsonb_build_object('variantId', current_setting('t.v1'), 'quantity', 3, 'unitCost', '1005', 'taxRateBps', 2100, 'taxCode', 'NL-21'),
    jsonb_build_object('variantId', current_setting('t.v2'), 'quantity', 1, 'unitCost', '2000', 'taxRateBps', 2100, 'taxCode', 'NL-21'),
    jsonb_build_object('variantId', current_setting('t.v3'), 'quantity', 2, 'unitCost', '500')),
  null) ->> 'id', true);

select is(
  better_supabase.purchase_order_tax_lines(current_setting('t.po')::uuid),
  '{"currency": "EUR", "lines": [{"taxCode": "NL-21", "taxRateBps": 2100, "net": "5015", "tax": "1053", "gross": "6068"}]}'::jsonb,
  'lines at one code and rate add up into one tax line, and a line without a rate adds none'
);
select is(
  (select count(*)::int from better_supabase.purchase_order_tax_lines where purchase_order_id = current_setting('t.po')::uuid),
  1,
  'the tax line is stored in purchase_order_tax_lines'
);

select better_supabase.save_purchase_order('00000000-0000-4000-8000-000000000001', current_setting('t.po')::uuid, current_setting('t.location')::uuid, null, null, 'EUR', null,
  jsonb_build_array(
    jsonb_build_object('variantId', current_setting('t.v1'), 'quantity', 1, 'unitCost', '1000', 'taxRateBps', 900, 'taxCode', 'NL-9'),
    jsonb_build_object('variantId', current_setting('t.v2'), 'quantity', 1, 'unitCost', '1000', 'taxRateBps', 2100, 'taxCode', 'NL-21')),
  null);
select is(
  (select jsonb_agg(l -> 'taxRateBps' order by (l ->> 'taxRateBps')::int) from jsonb_array_elements(better_supabase.purchase_order_tax_lines(current_setting('t.po')::uuid) -> 'lines') l),
  '[900, 2100]'::jsonb,
  'saving the draft again rebuilds the tax lines, one per code and rate'
);
select is(
  (select jsonb_agg(l ->> 'tax' order by (l ->> 'taxRateBps')::int) from jsonb_array_elements(better_supabase.purchase_order_tax_lines(current_setting('t.po')::uuid) -> 'lines') l),
  '["90", "210"]'::jsonb,
  'each tax line rounds its tax from its net'
);

select throws_ok(
  format($$select better_supabase.save_purchase_order('00000000-0000-4000-8000-000000000001', %L, %L, null, null, 'EUR', null,
    '[{"variantId": "%s", "quantity": 1, "unitCost": "100", "taxRateBps": 100001}]', null)$$,
    current_setting('t.po'), current_setting('t.location'), current_setting('t.v1')),
  '22023',
  null,
  'a rate above 100000 basis points is refused'
);
select is(
  (select count(*)::int from better_supabase.purchase_order_tax_lines where purchase_order_id = current_setting('t.po')::uuid),
  2,
  'a refused save leaves the tax lines as they were'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select throws_ok(
  format($$select better_supabase.purchase_order_tax_lines(%L)$$, current_setting('t.po')),
  'P0002',
  'purchase order not found',
  'another organization can''t read the tax lines'
);

select * from finish();
rollback;
