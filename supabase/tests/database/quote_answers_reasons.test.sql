-- A staff answer without a name, the owner notification with its label,
-- a withdraw reason and a payment reason, and the refusals around them.
-- The check constraint stands in for an app table that requires a label.
-- Ann (…a1) owns Acme (…0001); Carl (…a3) owns Globex (…0002).
begin;
select plan(10);

alter table better_supabase.notification_events
  add constraint quote_decided_label_required
  check (type <> 'quote.decided' or subject_label is not null);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.id', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001',
  '{"title": "Fence", "currency": "EUR"}',
  '[{"description": "Panels", "quantity": 2, "unitAmount": "5000", "taxRateBps": 2100}]'
) ->> 'id', true);
select better_supabase.send_quote(current_setting('test.id')::uuid);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select lives_ok(
  format($$select better_supabase.decide_quote(%L, 'accepted', null, null)$$, current_setting('test.id')),
  'an answer recorded without a name is accepted'
);
reset role;
select is(
  (select decided_by from better_supabase.quotes where id = current_setting('test.id')::uuid),
  null,
  'an answer without a name names no signer'
);
select is(
  (select subject_label from better_supabase.notification_events
   where type = 'quote.decided' and subject_id = current_setting('test.id')),
  (select identifier || ' Fence' from better_supabase.quotes where id = current_setting('test.id')::uuid),
  'the owner notification carries the quote as its label'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select set_config('test.sent', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001', '{"title": "Gate", "currency": "EUR"}', '[{"description": "Gate", "unitAmount": "100"}]'
) ->> 'id', true);
select better_supabase.send_quote(current_setting('test.sent')::uuid);
select set_config('test.invoice', better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Gate", "currency": "EUR"}', '[{"description": "Gate", "unitAmount": "100"}]'
) ->> 'id', true);
select better_supabase.issue_invoice(current_setting('test.invoice')::uuid, current_date);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;
select throws_ok(
  format($$select better_supabase.decide_quote(%L, 'rejected', 'no', null)$$, current_setting('test.sent')),
  'P0002',
  'no such quote you can edit',
  'another organization cannot answer the quote'
);
select throws_ok(
  format($$select better_supabase.withdraw_quote(%L, null, 'Taken')$$, current_setting('test.sent')),
  'P0002',
  'no such quote you can edit',
  'another organization cannot withdraw the quote with a reason'
);
select throws_ok(
  format($$select better_supabase.record_invoice_payment(%L, 121, 'EUR', now(), 'bank', null, null, null, 'Paid')$$, current_setting('test.invoice')),
  'P0002',
  'no such invoice you can edit',
  'another organization cannot record a payment with a reason'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select is(
  better_supabase.withdraw_quote(current_setting('test.sent')::uuid, null, 'Prices changed') ->> 'status',
  'withdrawn',
  'a quote is withdrawn with a reason'
);
select is(
  better_supabase.record_invoice_payment(current_setting('test.invoice')::uuid, 121, 'EUR', now(), 'bank', 'tx-45', null, null, 'Paid by bank') ->> 'status',
  'paid',
  'a payment is recorded with a reason'
);
select is(
  better_supabase.record_invoice_payment(current_setting('test.invoice')::uuid, -121, 'EUR', now(), 'bank', 'tx-45-refund') ->> 'status',
  'issued',
  'a refund is recorded without a reason, as before'
);
select is(
  current_setting('better_supabase.transition_reason', true),
  '',
  'no reason is left for later changes in the transaction'
);

select * from finish();
rollback;
