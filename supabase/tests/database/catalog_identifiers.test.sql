-- Product identifiers, relations, supplier items with column mappings,
-- promote_supplier_item, trade codes and location addresses on the fixture's
-- access contract. The admin (…00a1) of Acme (…0001) writes; the member (…00a2)
-- reads but can't write; Globex (…00b1) sees none of it.
begin;
select plan(37);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.p', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Valve', 'valve', null, 'physical', null) ->> 'id', true);
select set_config('t.a', better_supabase.save_variant(current_setting('t.p')::uuid, null, 'VALVE-A', null, 'Valve A', null, null, true, false, null) ->> 'id', true);
select set_config('t.p2', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Valve B', 'valve-b', null, 'physical', null) ->> 'id', true);
select set_config('t.b', better_supabase.save_variant(current_setting('t.p2')::uuid, null, 'VALVE-B', null, 'Valve B', null, null, true, false, null) ->> 'id', true);
select set_config('t.party', '00000000-0000-4000-8000-00000000c001', true);

-- Identifiers.
select is(
  (better_supabase.save_product_identifier('00000000-0000-4000-8000-000000000001', current_setting('t.a')::uuid, 'ean', '4006381333931') ->> 'created')::boolean,
  true,
  'an EAN is stored on the variant'
);
select is(
  (better_supabase.save_product_identifier('00000000-0000-4000-8000-000000000001', current_setting('t.a')::uuid, 'ean', '4006381333931') ->> 'created')::boolean,
  false,
  'the same identifier is stored once'
);
select throws_ok(
  format($$select better_supabase.save_product_identifier('00000000-0000-4000-8000-000000000001', %L, 'ean', '123')$$, current_setting('t.a')),
  '22023',
  null,
  'an EAN needs 8, 12, 13 or 14 digits'
);
select throws_ok(
  format($$select better_supabase.save_product_identifier('00000000-0000-4000-8000-000000000001', %L, 'barcode', '123')$$, current_setting('t.a')),
  '22023',
  null,
  'the type must be one of the allowed ones'
);
select is(
  (better_supabase.save_product_identifier('00000000-0000-4000-8000-000000000001', current_setting('t.a')::uuid, 'supplier', 'AC-9', current_setting('t.party')::uuid) ->> 'created')::boolean,
  true,
  'a supplier code is stored with its party'
);
select is(
  (better_supabase.find_variants_by_identifier('00000000-0000-4000-8000-000000000001', 'AC-9', 'supplier', current_setting('t.party')::uuid) -> 0 ->> 'sku'),
  'VALVE-A',
  'a code finds its variant'
);
select is(
  jsonb_array_length(better_supabase.variant_identifiers(current_setting('t.a')::uuid)),
  2,
  'a variant lists its identifiers'
);

-- Relations.
select is(
  (better_supabase.save_product_relation('00000000-0000-4000-8000-000000000001', current_setting('t.a')::uuid, current_setting('t.b')::uuid, 'alternative') ->> 'created')::boolean,
  true,
  'an alternative links two variants'
);
select is(
  (better_supabase.save_product_relation('00000000-0000-4000-8000-000000000001', current_setting('t.a')::uuid, current_setting('t.b')::uuid, 'alternative') ->> 'created')::boolean,
  false,
  'the same relation is stored once'
);
select is(
  (select r ->> 'direction' from jsonb_array_elements(better_supabase.variant_relations(current_setting('t.a')::uuid)) r where r ->> 'kind' = 'alternative'),
  'outgoing',
  'the variant that has the alternative sees it outgoing'
);
select is(
  (select r ->> 'direction' from jsonb_array_elements(better_supabase.variant_relations(current_setting('t.b')::uuid)) r where r ->> 'kind' = 'alternative'),
  'incoming',
  'the alternative sees the relation incoming'
);
select throws_ok(
  format($$select better_supabase.save_product_relation('00000000-0000-4000-8000-000000000001', %L, %L, 'accessory')$$, current_setting('t.a'), current_setting('t.a')),
  '22023',
  null,
  'a variant can''t relate to itself'
);
select is(
  (better_supabase.save_product_relation('00000000-0000-4000-8000-000000000001', current_setting('t.a')::uuid, current_setting('t.b')::uuid, 'superseded_by') ->> 'created')::boolean,
  true,
  'a variant is superseded by another'
);
select throws_ok(
  format($$select better_supabase.save_product_relation('00000000-0000-4000-8000-000000000001', %L, %L, 'superseded_by')$$, current_setting('t.b'), current_setting('t.a')),
  '22023',
  null,
  'a replacement can''t point back along its own chain'
);
select is(
  better_supabase.replacement_variant(current_setting('t.a')::uuid),
  current_setting('t.b')::uuid,
  'the replacement is the end of the chain'
);
select is(
  better_supabase.replacement_variant(current_setting('t.b')::uuid),
  current_setting('t.b')::uuid,
  'a variant nothing replaces is its own replacement'
);

-- Supplier items, mappings and promotion.
select set_config('t.s', '00000000-0000-4000-8000-00000000d001', true);
select ok(
  better_supabase.set_supplier_item_mapping('00000000-0000-4000-8000-000000000001', current_setting('t.s')::uuid, '{"code": "Artikel", "description": "Omschrijving", "price": "Prijs", "keywords": ["Merk", "Groep"]}', '{"currency": "EUR", "unit": "pcs"}') is not null,
  'a supplier gets a column mapping'
);
select throws_ok(
  format($$select better_supabase.set_supplier_item_mapping('00000000-0000-4000-8000-000000000001', %L, '{"color": "x"}')$$, current_setting('t.s')),
  '22023',
  null,
  'a mapping fills only known fields'
);
select is(
  better_supabase.supplier_item_from_row('00000000-0000-4000-8000-000000000001', current_setting('t.s')::uuid, '{"Artikel": "GV-100", "Omschrijving": "Gate valve", "Prijs": "1.234,50", "Merk": "Acme", "Groep": "valves"}'),
  '{"code": "GV-100", "description": "Gate valve", "price": 123450, "currency": "EUR", "unit": "pcs", "keywords": "Acme valves"}'::jsonb,
  'a row maps to supplier item fields with the price in minor units'
);
select is(
  (better_supabase.supplier_item_from_row('00000000-0000-4000-8000-000000000001', current_setting('t.s')::uuid, '{"Artikel": "GV-101", "Prijs": "12,5"}') ->> 'price')::bigint,
  1250::bigint,
  'a lone comma is the decimal separator'
);
select set_config('t.i', better_supabase.save_supplier_item('00000000-0000-4000-8000-000000000001', null, current_setting('t.s')::uuid, 'GV-100', 'Gate valve brass', 123450, 'EUR', 'pcs', 'Acme valves') ->> 'id', true);
select throws_ok(
  format($$select better_supabase.save_supplier_item('00000000-0000-4000-8000-000000000001', null, %L, 'GV-100', 'Again', null, null, null, null)$$, current_setting('t.s')),
  '23505',
  null,
  'a supplier has a code once'
);
select is(
  (better_supabase.search_supplier_items('00000000-0000-4000-8000-000000000001', 'brass gate') -> 0 ->> 'code'),
  'GV-100',
  'words in the description find the item'
);
select is(
  (better_supabase.search_supplier_items('00000000-0000-4000-8000-000000000001', 'GV-1') -> 0 ->> 'code'),
  'GV-100',
  'the start of a code finds the item'
);
select is(
  (better_supabase.promote_supplier_item(current_setting('t.i')::uuid) ->> 'created')::boolean,
  true,
  'promoting an item creates its product and variant'
);
select is(
  (select count(*)::int from better_supabase.product_identifiers x join better_supabase.product_variants v on v.id = x.variant_id where v.sku = 'GV-100' and x.type = 'supplier' and x.value = 'GV-100' and x.party_id = current_setting('t.s')::uuid),
  1,
  'the supplier code becomes an identifier of the new variant'
);
select is(
  (better_supabase.promote_supplier_item(current_setting('t.i')::uuid) ->> 'created')::boolean,
  false,
  'promoting again returns the same variant'
);

-- Trade codes and addresses.
select ok(better_supabase.set_variant_trade_code(current_setting('t.a')::uuid, '8481 80 99'), 'a trade code is set');
select is(
  (select trade_code from better_supabase.product_variants where id = current_setting('t.a')::uuid),
  '84818099',
  'a trade code drops its spaces'
);
select throws_ok(
  format($$select better_supabase.set_variant_trade_code(%L, 'ABC')$$, current_setting('t.a')),
  '22023',
  null,
  'a trade code is 4 to 10 digits'
);
select set_config('t.loc', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'WH9', 'Warehouse 9', null, null) ->> 'id', true);
select throws_ok(
  format($$select better_supabase.set_location_address(%L, '{"country": "Netherlands"}')$$, current_setting('t.loc')),
  '22023',
  null,
  'a country is a two-letter code'
);

select ok(better_supabase.set_location_address(current_setting('t.loc')::uuid, '{"line1": "Dam 1", "postalCode": "1012 JS", "city": "Amsterdam", "country": "NL"}'), 'a location address is set');
select is(
  (select address ->> 'city' from better_supabase.inventory_locations where id = current_setting('t.loc')::uuid),
  'Amsterdam',
  'a location stores its address'
);

-- Imports write as the service role.
reset role;
set local role service_role;
select set_config('t.imp', better_supabase.import_supplier_item(gen_random_uuid(), jsonb_build_object('tenant', '00000000-0000-4000-8000-000000000001', 'data', jsonb_build_object('supplierId', current_setting('t.s'), 'row', jsonb_build_object('Artikel', 'GV-200', 'Prijs', '9.99'), 'description', 'Check valve')), null) ->> 'subjectId', true);
select is(
  (select jsonb_build_array(x.code, x.description, x.price) from better_supabase.supplier_items x where x.id = current_setting('t.imp')::uuid),
  '["GV-200", "Check valve", 999]'::jsonb,
  'an imported row goes through the mapping and explicit fields win'
);
select is(
  better_supabase.import_supplier_item(gen_random_uuid(), jsonb_build_object('tenant', '00000000-0000-4000-8000-000000000001', 'data', jsonb_build_object('supplierId', current_setting('t.s'), 'code', 'GV-200', 'price', 1099)), null) ->> 'subjectId',
  current_setting('t.imp'),
  'a new key for a code the supplier has takes over that item'
);
select is(
  better_supabase.import_product_identifier(gen_random_uuid(), jsonb_build_object('tenant', '00000000-0000-4000-8000-000000000001', 'data', jsonb_build_object('sku', 'VALVE-B', 'type', 'manufacturer', 'value', 'MF-7')), null) ->> 'subjectId' is not null,
  true,
  'an identifier imports by SKU'
);

-- Access.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  format($$select better_supabase.save_product_identifier('00000000-0000-4000-8000-000000000001', %L, 'other', 'X1')$$, current_setting('t.a')),
  '42501',
  null,
  'a member without catalog.manage can''t add an identifier'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.supplier_items) + (select count(*)::int from better_supabase.product_identifiers) + (select count(*)::int from better_supabase.product_relations) + (select count(*)::int from better_supabase.supplier_item_mappings),
  0,
  'another tenant sees no identifiers, relations, supplier items or mappings'
);

select * from finish();
rollback;
