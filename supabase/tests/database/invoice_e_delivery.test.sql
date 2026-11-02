-- Participant ids and the e-invoice delivery log. Ann (…a1) owns Acme (…0001);
-- Carl (…a3) owns Globex (…0002).
begin;
select plan(12);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.invoice', better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001',
  '{"title": "Fence", "currency": "EUR"}',
  '[{"description": "Panels", "quantity": 2, "unitAmount": "5000", "taxRateBps": 2100}]'
) ->> 'id', true);
select lives_ok(
  format($$select better_supabase.issue_invoice(%L, current_date)$$, current_setting('test.invoice')),
  'the invoice is issued'
);

select is(
  better_supabase.set_invoice_e_endpoint('00000000-0000-4000-8000-000000000001', 'organization', '00000000-0000-4000-8000-000000000001', '0106', '12345678'),
  '{"scheme": "0106", "id": "12345678"}'::jsonb,
  'the organization gets a participant id'
);
select is(
  better_supabase.invoice_e_endpoints(current_setting('test.invoice')::uuid) -> 'seller',
  '{"scheme": "0106", "id": "12345678"}'::jsonb,
  'the seller reads the organization id when its legal entity has none'
);
select throws_ok(
  $$select better_supabase.set_invoice_e_endpoint('00000000-0000-4000-8000-000000000001', 'organization', '00000000-0000-4000-8000-000000000001', '01', 'x')$$,
  '22023',
  null,
  'a scheme is four digits'
);

select is(
  better_supabase.record_e_invoice_delivery('00000000-0000-4000-8000-000000000001', 'outbound', 'ap', 'm-1', 'peppol-bis-3', null, current_setting('test.invoice')::uuid, null, repeat('a', 64)) ->> 'created',
  'true',
  'a send is logged'
);
select is(
  better_supabase.record_e_invoice_delivery('00000000-0000-4000-8000-000000000001', 'outbound', 'ap', 'm-1', 'peppol-bis-3', null, current_setting('test.invoice')::uuid, null, repeat('a', 64)) ->> 'created',
  'false',
  'the same message id is logged once'
);
select is(
  better_supabase.set_e_invoice_delivery_state(
    (better_supabase.list_e_invoice_deliveries('00000000-0000-4000-8000-000000000001', 'outbound', 'pending') -> 0 ->> 'id')::uuid,
    'delivered'
  ) ->> 'state',
  'delivered',
  'a pending delivery is delivered'
);
select throws_ok(
  format(
    $$select better_supabase.set_e_invoice_delivery_state(%L::uuid, 'rejected')$$,
    better_supabase.list_e_invoice_deliveries('00000000-0000-4000-8000-000000000001', 'outbound', 'delivered') -> 0 ->> 'id'
  ),
  null,
  null,
  'a delivered one does not move again'
);
select is(
  jsonb_array_length(better_supabase.list_e_invoice_deliveries('00000000-0000-4000-8000-000000000001', null, null, current_setting('test.invoice')::uuid)),
  1,
  'the log lists the invoice''s delivery'
);
select is(
  better_supabase.find_e_endpoint_party('00000000-0000-4000-8000-000000000001', '0106', '12345678') ->> 'partyKind',
  'organization',
  'a participant id finds its party'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;
select throws_ok(
  format($$select better_supabase.invoice_e_endpoints(%L)$$, current_setting('test.invoice')),
  'P0002',
  null,
  'another organization cannot read the invoice''s ids'
);
select throws_ok(
  $$select better_supabase.record_e_invoice_delivery('00000000-0000-4000-8000-000000000001', 'inbound', 'ap', 'm-2')$$,
  '42501',
  null,
  'another organization cannot log a delivery'
);

select * from finish();
rollback;
