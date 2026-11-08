-- The parties and documents gaps of the declarative base layer plan (ADR 0268):
-- person modes and company fields, open-ended periods, line units and discount
-- kinds, the identifier key on invoices, a shipment's direction, the letterhead
-- seed and the purchase order document. The admin (…00a1) of Acme (…0001) does
-- the work; the member (…00a2) can't set a shipment's direction.
begin;
select plan(21);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- Person modes.
select is(
  better_supabase.save_person('00000000-0000-4000-8000-000000000001', null, '{"name": "Outside Olga"}') ->> 'mode',
  'external',
  'a person is external by default'
);
select throws_ok(
  $$select better_supabase.save_person('00000000-0000-4000-8000-000000000001', null, '{"name": "Tenant Tim", "mode": "tenant"}')$$,
  '22023',
  'a tenant person needs a userId',
  'a tenant person needs a user'
);
select throws_ok(
  $$select better_supabase.save_person('00000000-0000-4000-8000-000000000001', null, '{"name": "Odd Otto", "mode": "guest"}')$$,
  '22023',
  'a person is external or tenant',
  'a mode is external or tenant'
);
select is(
  better_supabase.save_person('00000000-0000-4000-8000-000000000001', null,
    '{"name": "Member Mia", "mode": "tenant", "userId": "00000000-0000-4000-8000-0000000000a2"}') ->> 'mode',
  'tenant',
  'a tenant person has its user'
);
select set_config('t.person', better_supabase.save_person('00000000-0000-4000-8000-000000000001', null, '{"name": "Plain Paul"}') ->> 'id', true);
select throws_ok(
  format($$select better_supabase.save_person('00000000-0000-4000-8000-000000000001', %L, '{"mode": "tenant"}')$$, current_setting('t.person')),
  '23514',
  null,
  'a person without a user can not become a tenant person'
);

-- Company fields.
select is(
  (select jsonb_build_array(c ->> 'legal_name', c ->> 'registration_id', c ->> 'phone')
   from (select better_supabase.save_company('00000000-0000-4000-8000-000000000001', null,
     '{"name": "Gaps BV", "legalName": "Gaps Holding B.V.", "registrationId": "12345678", "phone": "+31 10 555 0100"}') as c) x),
  '["Gaps Holding B.V.", "12345678", "+31 10 555 0100"]'::jsonb,
  'a company keeps its legal name, register number and phone'
);

-- Open-ended periods, units and discount kinds on quote lines.
select set_config('t.quote', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001',
  '{"title": "Hosting", "currency": "EUR"}',
  '[{"description": "Hosting", "unitAmount": "1000", "periods": null, "unit": "month", "discountKind": "fixed"},
    {"description": "Setup", "unitAmount": "500"}]'
)::text, true);
select is(
  (select array_agg(l.periods order by l.position) from better_supabase.quote_lines l
   where l.parent_id = (current_setting('t.quote')::jsonb ->> 'id')::uuid),
  array[null, 1]::integer[],
  'a null periods runs until cancelled and a missing one is a single period'
);
select is(
  (select jsonb_build_array(l.unit, l.discount_kind) from better_supabase.quote_lines l
   where l.parent_id = (current_setting('t.quote')::jsonb ->> 'id')::uuid and l.position = 1),
  '["month", "fixed"]'::jsonb,
  'a line keeps its unit and discount kind'
);
select is(
  current_setting('t.quote')::jsonb -> 'lines' -> 0 -> 'periods',
  'null'::jsonb,
  'the quote reads an open-ended line as a null periods'
);
select is(
  current_setting('t.quote')::jsonb ->> 'list_total',
  '1500',
  'an open-ended line counts one period in the totals'
);
select throws_ok(
  format($$select better_supabase.set_quote_lines(%L, '[{"description": "Bad", "unitAmount": "1", "discountKind": "half"}]')$$, current_setting('t.quote')::jsonb ->> 'id'),
  null,
  null,
  'a discount kind is a percentage or fixed'
);

-- Invoices are unique by identifier.
select has_index('better_supabase', 'invoices', 'invoices_tenant_id_direction_kind_identifier_key', 'the invoice key is the identifier');
select hasnt_index('better_supabase', 'invoices', 'invoices_tenant_id_direction_kind_number_key', 'the number alone is no longer the key');

-- A shipment's direction.
select set_config('t.ship', better_supabase.create_shipment(
  '00000000-0000-4000-8000-000000000001',
  '{"line1": "Dock 4", "city": "Rotterdam", "country": "NL"}',
  '{"line1": "Main St 1", "city": "Berlin", "country": "DE"}',
  '[{"weightGrams": 1000}]',
  reference => 'SHP-DIR'
) ->> 'id', true);
select is(
  better_supabase.get_shipment(current_setting('t.ship')::uuid) ->> 'direction',
  'outbound',
  'a shipment is outbound by default'
);
select is(
  better_supabase.set_shipment_direction(current_setting('t.ship')::uuid, 'inbound') ->> 'direction',
  'inbound',
  'a draft shipment can come inbound'
);
select throws_ok(
  format($$select better_supabase.set_shipment_direction(%L, 'sideways')$$, current_setting('t.ship')),
  '22023',
  'a shipment is outbound or inbound',
  'a direction is outbound or inbound'
);
select better_supabase.set_shipment_label(
  current_setting('t.ship')::uuid, 'flat-rate', 'standard', 'FR-DIR', 'lbl_dir', 695, 'EUR',
  label_url => 'https://labels.example.test/lbl_dir.pdf'
);
select throws_ok(
  format($$select better_supabase.set_shipment_direction(%L, 'outbound')$$, current_setting('t.ship')),
  '55000',
  'only a draft changes direction',
  'a labeled shipment keeps its direction'
);

-- The purchase order document.
select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Gasket', 'gasket-po-doc', null, 'physical', null) ->> 'id', true);
select set_config('t.variant', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'GASKET-1', null, 'Gasket', null, null, true, false, null) ->> 'id', true);
select set_config('t.location', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'PODOC', 'PO dock', null, null) ->> 'id', true);
select set_config('t.supplier', better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Gasket Supplies"}') ->> 'id', true);
select set_config('t.po', better_supabase.save_purchase_order('00000000-0000-4000-8000-000000000001', null, current_setting('t.location')::uuid, 'company',
  current_setting('t.supplier'), 'EUR', null,
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.variant'), 'quantity', 4, 'unitCost', '1000')),
  null) ->> 'id', true);
select set_config('t.doc', better_supabase.document_variables('00000000-0000-4000-8000-000000000001', 'purchase_order', current_setting('t.po')::uuid)::text, true);
select is(
  jsonb_build_array(
    current_setting('t.doc')::jsonb -> 'document' ->> 'type',
    current_setting('t.doc')::jsonb -> 'buyer' ->> 'name',
    current_setting('t.doc')::jsonb -> 'totals' ->> 'total',
    current_setting('t.doc')::jsonb -> 'lines' -> 0 ->> 'description'
  ),
  '["purchase_order", "Gasket Supplies", "4000", "Gasket"]'::jsonb,
  'a purchase order is a document of its supplier with its lines at their unit cost'
);
select matches(
  current_setting('t.doc')::jsonb -> 'document' ->> 'number',
  '^PO-[0-9A-F]{8}$',
  'a purchase order number comes from its id'
);

-- The letterhead seed, run twice.
reset role;
set local role service_role;
select better_supabase.seed_document_templates_defaults('00000000-0000-4000-8000-000000000001', null, 'nl');
select better_supabase.seed_document_templates_defaults('00000000-0000-4000-8000-000000000001', null, 'nl');
select is(
  (select count(*)::int from better_supabase.document_text_blocks
   where tenant_id = '00000000-0000-4000-8000-000000000001' and key = 'letterhead' and language = 'nl'),
  1,
  'the Dutch letterhead is seeded once however often the defaults run'
);
select is(
  (select count(*)::int from better_supabase.document_text_blocks
   where tenant_id = '00000000-0000-4000-8000-000000000001' and key = 'letterhead' and language = 'fr'),
  0,
  'a locale that was not seeded has no letterhead'
);

select * from finish();
rollback;
