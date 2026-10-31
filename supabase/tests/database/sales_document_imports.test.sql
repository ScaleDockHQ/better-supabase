-- Historical sales documents (ADR 0141). Invoices, credit notes, quotes and
-- orders import through the record map with their own number, dates and final
-- status, the stored totals and tax per code taken as given (a difference is a
-- warning), payments with their real dates and no events. Importing the same
-- document twice writes nothing, a document a user edited is a conflict, and
-- lines carry a billing party that `document_totals_by_billing_party` reports.
-- Run with `supabase test db`.
begin;
select plan(28);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'sales', '{}'::jsonb) ->> 'id'),
  true
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

create temporary table out (name text primary key, result jsonb) on commit drop;
grant all on out to authenticated, service_role;

-- An invoice: two lines of the same product and a free-text line, 21 percent
-- tax on all of them, two payments on their real dates. 2 * 10000 + 1 * 10000 +
-- 5000 = 35000 net, 7350 tax, 42350 gross.
insert into out values ('invoice', better_supabase.import_upsert_batch(
  current_setting('bsb.run')::uuid, 'invoice',
  $json$[{"key":"inv-2019-0007","data":{
    "number":"INV-2019-0007","status":"paid","issuedOn":"2019-03-04","dueOn":"2019-04-03",
    "createdAt":"2019-03-01T09:00:00Z","currency":"EUR","title":"March 2019",
    "buyer":{"name":"Old Customer BV","vat":"NL123"},
    "lines":[
      {"description":"Widget","quantity":2,"unitAmount":10000,"taxRateBps":2100,"productId":"p-1","billingParty":"customer"},
      {"description":"Widget","quantity":1,"unitAmount":10000,"taxRateBps":2100,"productId":"p-1","billingParty":"own_warranty"},
      {"description":"Free text","quantity":1,"unitAmount":5000,"taxRateBps":2100,"billingParty":"customer"}],
    "totals":{"subtotal":35000,"tax":7350,"total":42350},
    "payments":[{"amount":20000,"paidAt":"2019-03-20T10:00:00Z"},{"amount":22350,"paidAt":"2019-04-02T11:00:00Z"}]
  }}]$json$::jsonb));

select is(
  (select (result - 'warnings' - 'errors' - 'dryRun') from out where name = 'invoice'),
  '{"inserted":1,"updated":0,"unchanged":0,"conflicted":0}'::jsonb,
  'the invoice imports'
);
select is((select jsonb_array_length(result -> 'errors') from out where name = 'invoice'), 0, 'the invoice has no errors');
select is((select result ? 'warnings' from out where name = 'invoice'), false, 'matching totals give no warning');

select is(
  (select jsonb_build_array(identifier, status::text, issued_on::text, due_on::text, created_at::date::text, total::text, tax_total::text)
   from better_supabase.invoices where identifier = 'INV-2019-0007'),
  '["INV-2019-0007", "paid", "2019-03-04", "2019-04-03", "2019-03-01", "42350", "7350"]'::jsonb,
  'the invoice keeps its number, dates, status and totals'
);
select is(
  (select buyer ->> 'name' from better_supabase.invoices where identifier = 'INV-2019-0007'),
  'Old Customer BV',
  'the buyer snapshot is stored as given'
);
select is(
  (select count(*)::int from better_supabase.invoice_lines l join better_supabase.invoices i on i.id = l.parent_id
   where i.identifier = 'INV-2019-0007'),
  3,
  'free-text lines and the same product on several lines are kept'
);
select is(
  (select jsonb_agg(left(p ->> 'paidAt', 10) order by p ->> 'paidAt')
   from jsonb_array_elements(better_supabase.list_invoice_payments(
     (select id from better_supabase.invoices where identifier = 'INV-2019-0007')) -> 'payments') p),
  '["2019-03-20", "2019-04-02"]'::jsonb,
  'the payments keep their real dates'
);
select is(
  (select count(*)::int from better_supabase.outbox_events where type like 'invoice.%' and created_at >= transaction_timestamp()),
  0,
  'an imported invoice emits no event'
);

-- Totals that differ from the lines are kept and reported.
insert into out values ('mismatch', better_supabase.import_upsert_batch(
  current_setting('bsb.run')::uuid, 'invoice',
  $json$[{"key":"inv-2019-0008","data":{
    "number":"INV-2019-0008","status":"issued","issuedOn":"2019-05-01","currency":"EUR",
    "lines":[{"description":"Service","quantity":1,"unitAmount":10000,"taxRateBps":2100}],
    "totals":{"subtotal":10000,"tax":2000,"total":12000}
  }}]$json$::jsonb));
select is(
  (select result -> 'warnings' -> 0 ->> 'code' from out where name = 'mismatch'),
  'IMPORT_TOTALS_MISMATCH',
  'stored totals that differ from the lines give a warning'
);
select is(
  (select jsonb_build_array(tax_total::text, total::text) from better_supabase.invoices where identifier = 'INV-2019-0008'),
  '["2000", "12000"]'::jsonb,
  'the stored totals are kept, never rejected'
);
select is(
  (select result ->> 'inserted' from out where name = 'mismatch'),
  '1',
  'the invoice with mismatched totals still imports'
);

-- The same document again writes nothing.
create temporary table before_counts as
select (select count(*) from better_supabase.invoices) as invoices,
  (select count(*) from better_supabase.invoice_lines) as lines,
  (select count(*) from better_supabase.ledger_transactions) as transactions;
grant all on before_counts to authenticated, service_role;

select is(
  (select (better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'invoice',
    $json$[{"key":"inv-2019-0007","data":{
    "number":"INV-2019-0007","status":"paid","issuedOn":"2019-03-04","dueOn":"2019-04-03",
    "createdAt":"2019-03-01T09:00:00Z","currency":"EUR","title":"March 2019",
    "buyer":{"name":"Old Customer BV","vat":"NL123"},
    "lines":[
      {"description":"Widget","quantity":2,"unitAmount":10000,"taxRateBps":2100,"productId":"p-1","billingParty":"customer"},
      {"description":"Widget","quantity":1,"unitAmount":10000,"taxRateBps":2100,"productId":"p-1","billingParty":"own_warranty"},
      {"description":"Free text","quantity":1,"unitAmount":5000,"taxRateBps":2100,"billingParty":"customer"}],
    "totals":{"subtotal":35000,"tax":7350,"total":42350},
    "payments":[{"amount":20000,"paidAt":"2019-03-20T10:00:00Z"},{"amount":22350,"paidAt":"2019-04-02T11:00:00Z"}]
  }}]$json$::jsonb) - 'errors' - 'dryRun' - 'warnings')),
  '{"inserted":0,"updated":0,"unchanged":1,"conflicted":0}'::jsonb,
  'the same invoice twice is unchanged'
);
select is(
  (select jsonb_build_array(
    (select count(*) from better_supabase.invoices) - invoices,
    (select count(*) from better_supabase.invoice_lines) - lines,
    (select count(*) from better_supabase.ledger_transactions) - transactions) from before_counts),
  '[0, 0, 0]'::jsonb,
  'importing the same document twice writes no invoice, line or payment'
);

-- A user who edited the invoice after the import makes the next import a conflict.
update better_supabase.invoices set updated_at = now() + interval '1 hour', note = 'edited by a user'
where identifier = 'INV-2019-0007';
select is(
  (select (better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'invoice',
    $json$[{"key":"inv-2019-0007","data":{
    "number":"INV-2019-0007","status":"paid","issuedOn":"2019-03-04","currency":"EUR","title":"Changed in the source",
    "lines":[{"description":"Widget","quantity":2,"unitAmount":10000,"taxRateBps":2100}]
  }}]$json$::jsonb) - 'errors' - 'dryRun' - 'warnings')),
  '{"inserted":0,"updated":0,"unchanged":0,"conflicted":1}'::jsonb,
  'an invoice a user edited is reported as a conflict'
);
select is(
  (select note from better_supabase.invoices where identifier = 'INV-2019-0007'),
  'edited by a user',
  'the conflicting import leaves the user''s edit'
);

-- The billing party report: customer lines 2 * 10000 + 5000 = 25000, the
-- warranty line 10000.
select is(
  (select jsonb_agg(jsonb_build_array(r ->> 'billingParty', r ->> 'lines', r ->> 'net') order by r ->> 'billingParty')
   from jsonb_array_elements(better_supabase.document_totals_by_billing_party(
     (select id from better_supabase.invoices where identifier = 'INV-2019-0007'))) r),
  '[["customer", "2", "25000"], ["own_warranty", "1", "10000"]]'::jsonb,
  'document_totals_by_billing_party reports the net per billing party'
);

-- A credit note with its own number against the imported invoice.
insert into out values ('credit', better_supabase.import_upsert_batch(
  current_setting('bsb.run')::uuid, 'credit_note',
  $json$[{"key":"cn-2019-0001","data":{
    "number":"CN-2019-0001","issuedOn":"2019-06-01","original":"INV-2019-0007","note":"Returned widget",
    "lines":[{"description":"Widget","quantity":1,"unitAmount":10000,"taxRateBps":2100}]
  }}]$json$::jsonb));
select is(
  (select result ->> 'inserted' from out where name = 'credit'),
  '1',
  'the credit note imports'
);
select is(
  (select jsonb_build_array(identifier, issued_on::text, status::text) from better_supabase.invoices where identifier = 'CN-2019-0001'),
  '["CN-2019-0001", "2019-06-01", "issued"]'::jsonb,
  'the credit note keeps its number and date'
);

-- A final status the document never reached is refused item by item.
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'invoice',
    '[{"key":"bad","data":{"number":"INV-BAD","status":"nonsense","issuedOn":"2019-01-01","lines":[{"description":"x","quantity":1,"unitAmount":1}]}}]'::jsonb
  ) -> 'errors' -> 0 ->> 'code'),
  'IMPORT_ITEM_INVALID',
  'an unknown status is an item error'
);

-- A quote in its final status with its own dates and stored totals.
insert into out values ('quote', better_supabase.import_upsert_batch(
  current_setting('bsb.run')::uuid, 'quote',
  $json$[{"key":"q-2018-0042","data":{
    "number":"Q-2018-0042","status":"accepted","title":"Website","currency":"EUR",
    "createdAt":"2018-11-01T10:00:00Z","sentAt":"2018-11-02T10:00:00Z","decidedAt":"2018-11-10T10:00:00Z","decidedBy":"Jane",
    "buyer":{"name":"Prospect BV"},
    "lines":[
      {"description":"Design","quantity":1,"unitAmount":50000,"taxRateBps":2100,"billingParty":"customer"},
      {"description":"Design","quantity":1,"unitAmount":50000,"taxRateBps":2100,"billingParty":"internal"}],
    "totals":{"subtotal":100000,"tax":21000,"total":121000}
  }}]$json$::jsonb));
select is(
  (select result ->> 'inserted' from out where name = 'quote'),
  '1',
  'the quote imports'
);
select is(
  (select jsonb_build_array(status::text, sent_at::date::text, decided_at::date::text, total::text, buyer ->> 'name')
   from better_supabase.quotes where title = 'Website'),
  '["accepted", "2018-11-02", "2018-11-10", "121000", "Prospect BV"]'::jsonb,
  'the quote keeps its final status, dates, totals and buyer'
);
select is(
  (select jsonb_agg(jsonb_build_array(r ->> 'billingParty', r ->> 'net') order by r ->> 'billingParty')
   from jsonb_array_elements(better_supabase.quote_totals_by_billing_party(
     (select id from better_supabase.quotes where title = 'Website'))) r),
  '[["customer", "50000"], ["internal", "50000"]]'::jsonb,
  'quote_totals_by_billing_party reports the net per billing party'
);
select is(
  (select count(*)::int from better_supabase.outbox_events where type like 'quote.%' and created_at >= transaction_timestamp()),
  0,
  'an imported quote emits no event'
);

-- An order with a free-text line and a payment with its real date.
insert into out values ('order', better_supabase.import_upsert_batch(
  current_setting('bsb.run')::uuid, 'order',
  $json$[{"key":"ord-5001","data":{
    "number":"ORD-5001","status":"completed","currency":"EUR","email":"old@example.com",
    "placedAt":"2017-05-01T08:00:00Z","paidAt":"2017-05-01T08:05:00Z","completedAt":"2017-05-03T08:00:00Z",
    "buyer":{"name":"Shopper"},
    "lines":[
      {"sku":"FREE","title":"Delivery and set-up","quantity":1,"unitAmount":"2500","billingParty":"customer"},
      {"sku":"FREE","title":"Delivery and set-up","quantity":1,"unitAmount":"2500","billingParty":"internal"}],
    "totals":{"subtotal":"5000","taxTotal":"0","total":"5000"},
    "payments":[{"amount":"5000","paidAt":"2017-05-01T08:05:00Z"}]
  }}]$json$::jsonb));
-- The order tables have no policy for the service role, so the checks read as
-- the table owner.
reset role;
select is(
  (select result ->> 'inserted' from out where name = 'order'),
  '1',
  'the order imports'
);
select is(
  (select jsonb_build_array(status, total::text, placed_at::date::text, buyer ->> 'name') from better_supabase.orders where number = 'ORD-5001'),
  '["completed", "5000", "2017-05-01", "Shopper"]'::jsonb,
  'the order keeps its status, total, date and buyer'
);
select is(
  (select count(*)::int from better_supabase.order_lines l join better_supabase.orders o on o.id = l.order_id where o.number = 'ORD-5001'),
  2,
  'the order keeps both free-text lines'
);
select is(
  (select result ? 'warnings' from out where name = 'order'),
  false,
  'matching order totals give no warning'
);

-- Stock never moves for an imported document.
select is(
  (select count(*)::int from better_supabase.ledger_transactions t where t.kind = 'stock' and t.created_at >= transaction_timestamp()),
  0,
  'an imported document moves no stock'
);

select * from finish();
rollback;
