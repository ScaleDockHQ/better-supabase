-- Open items, payment allocation, purchase approval and payment batches (ADR 0155).
-- Opening open items import through the record map and repeat to nothing. A
-- payment is allocated in part, an early-payment discount is taken only inside
-- its window, and unallocating restores the balances. Bills over an approval
-- level stay out of a payment batch until the approver signs; the batch posts,
-- and matching the bank debit to it allocates the payments and closes the items.
-- Run with `supabase test db`.
begin;
select plan(29);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select better_supabase.setup_accounting('00000000-0000-4000-8000-000000000001', 'EUR');
select better_supabase.open_fiscal_year('00000000-0000-4000-8000-000000000001', 2026);

create function pg_temp.bal(identifier text) returns text language sql stable as $$
  select coalesce((select i ->> 'balance' from jsonb_array_elements(better_supabase.open_items_for_party(
    '00000000-0000-4000-8000-000000000001', null, '2026-12-31', null)) i where i ->> 'identifier' = $1), '0')
$$;
create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, service_role;
insert into ids values
  ('supplier', (better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Open item supplier"}') ->> 'id')::uuid),
  ('customer', (better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Open item customer"}') ->> 'id')::uuid);

select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'open_items', '{}'::jsonb) ->> 'id'),
  true
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

create temporary table out (name text primary key, result jsonb) on commit drop;
grant all on out to authenticated, service_role;

-- Opening lists keep their original dates: two supplier bills and a customer invoice.
select set_config('t.items', jsonb_build_array(
  jsonb_build_object('key', 'bill-1', 'data', jsonb_build_object('number', 'BILL-1', 'side', 'supplier', 'issuedOn', '2026-09-15',
    'dueOn', '2026-10-15', 'currency', 'EUR', 'balance', 100000, 'company', jsonb_build_object('id', (select id from ids where name = 'supplier')))),
  jsonb_build_object('key', 'bill-2', 'data', jsonb_build_object('number', 'BILL-2', 'side', 'supplier', 'issuedOn', '2026-09-20',
    'dueOn', '2026-10-20', 'currency', 'EUR', 'balance', 50000, 'company', jsonb_build_object('id', (select id from ids where name = 'supplier')))),
  jsonb_build_object('key', 'inv-1', 'data', jsonb_build_object('number', 'INV-1', 'side', 'customer', 'issuedOn', '2026-09-01',
    'dueOn', '2026-10-01', 'currency', 'EUR', 'balance', 80000, 'company', jsonb_build_object('id', (select id from ids where name = 'customer'))))
)::text, true);

insert into out values ('first', better_supabase.import_upsert_batch(
  current_setting('bsb.run')::uuid, 'open_item', current_setting('t.items')::jsonb));
select is(
  (select (result - 'warnings' - 'errors' - 'dryRun') from out where name = 'first'),
  '{"inserted":3,"updated":0,"unchanged":0,"conflicted":0}'::jsonb,
  'three opening open items import'
);

insert into out values ('second', better_supabase.import_upsert_batch(
  current_setting('bsb.run')::uuid, 'open_item', current_setting('t.items')::jsonb));
select is(
  (select (result - 'warnings' - 'errors' - 'dryRun') from out where name = 'second'),
  '{"inserted":0,"updated":0,"unchanged":3,"conflicted":0}'::jsonb,
  'importing the same list again writes nothing'
);
select is(
  (select count(*)::int from better_supabase.invoices where identifier in ('BILL-1', 'BILL-2', 'INV-1')),
  3,
  'the repeat adds no document'
);
select is(
  (select jsonb_build_array(issued_on::text, due_on::text, total::text, direction::text)
   from better_supabase.invoices where identifier = 'BILL-1'),
  '["2026-09-15", "2026-10-15", "100000", "purchase"]'::jsonb,
  'an open item keeps its original dates and balance, and a supplier item is a purchase bill'
);

-- BILL-1 offers 2 000 off when paid by 2026-10-01.
update better_supabase.invoices
set discount_due_on = '2026-10-01', discount_amount_early = 2000
where identifier = 'BILL-1';

insert into ids select identifier, id from better_supabase.invoices where identifier in ('BILL-1', 'BILL-2', 'INV-1');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select jsonb_agg(jsonb_build_array(i ->> 'identifier', i ->> 'balance', i ->> 'bucket', i ->> 'discountAmount') order by i ->> 'identifier')
   from jsonb_array_elements(better_supabase.open_items_for_party('00000000-0000-4000-8000-000000000001',
     (select id::text from ids where name = 'supplier'), '2026-10-25', 'supplier')) i),
  '[["BILL-1","100000","days1To30","2000"],["BILL-2","50000","days1To30","0"]]'::jsonb,
  'a supplier''s open items carry the balance, the ageing bucket and the discount on offer'
);
select is(
  (select jsonb_build_array(r ->> 'days1To30', r ->> 'outstanding')
   from jsonb_array_elements(better_supabase.open_item_ageing('00000000-0000-4000-8000-000000000001', 'supplier', '2026-10-25')) r),
  '["150000", "150000"]'::jsonb,
  'the ageing sums the buckets per party'
);
select is(
  (select jsonb_array_length(better_supabase.open_items_for_party('00000000-0000-4000-8000-000000000001', null, '2026-09-10', null))),
  1,
  'as of a date, documents issued later are not open yet'
);

-- A partial payment after the discount window takes no discount.
select is(
  (better_supabase.allocate_payment('00000000-0000-4000-8000-000000000001',
    jsonb_build_object('partyId', (select id from ids where name = 'supplier'), 'side', 'supplier', 'amount', '40000',
      'currency', 'EUR', 'receivedOn', '2026-10-20', 'reference', 'pay-1'),
    jsonb_build_array(jsonb_build_object('invoiceId', (select id from ids where name = 'BILL-1'), 'amount', '40000')))
   - 'allocations' - 'currency'),
  jsonb_build_object('reference', 'pay-1', 'partyId', (select id::text from ids where name = 'supplier'), 'allocated', '40000', 'discount', '0', 'credited', '0'),
  'a partial payment allocates what was paid and takes no discount outside the window'
);
select is(
  pg_temp.bal('BILL-1'),
  '60000',
  'the bill keeps the rest as its balance'
);
select is(
  (select status::text from better_supabase.invoices where identifier = 'BILL-1'),
  'partially_paid',
  'the bill is partially paid'
);

select is(
  (better_supabase.allocate_payment('00000000-0000-4000-8000-000000000001',
    jsonb_build_object('partyId', (select id from ids where name = 'supplier'), 'side', 'supplier', 'amount', '40000',
      'currency', 'EUR', 'receivedOn', '2026-10-20', 'reference', 'pay-1'),
    jsonb_build_array(jsonb_build_object('invoiceId', (select id from ids where name = 'BILL-1'), 'amount', '40000'))) ->> 'allocated'),
  '40000',
  'a replay of the same reference answers the same allocation'
);
select is(
  pg_temp.bal('BILL-1'),
  '60000',
  'a replay moves no money'
);

select is(
  (better_supabase.unallocate_payment('00000000-0000-4000-8000-000000000001', 'pay-1') ->> 'unallocated'),
  '1',
  'unallocating a reference reverses its allocation'
);
select is(
  (select jsonb_build_array(pg_temp.bal('BILL-1'), status::text) from better_supabase.invoices where identifier = 'BILL-1'),
  '["100000", "issued"]'::jsonb,
  'the bill reopens with its full balance'
);

-- Inside the window the discount is taken and posted through accounting.
select is(
  (better_supabase.allocate_payment('00000000-0000-4000-8000-000000000001',
    jsonb_build_object('partyId', (select id from ids where name = 'supplier'), 'side', 'supplier', 'amount', '98000',
      'currency', 'EUR', 'receivedOn', '2026-09-28', 'reference', 'pay-2'),
    jsonb_build_array(jsonb_build_object('invoiceId', (select id from ids where name = 'BILL-1'), 'amount', '98000')))
   ->> 'discount'),
  '2000',
  'paying the balance less the discount inside the window takes the discount'
);
select is(
  (select jsonb_build_array(pg_temp.bal('BILL-1'), status::text) from better_supabase.invoices where identifier = 'BILL-1'),
  '["0", "paid"]'::jsonb,
  'the discount settles the bill'
);
select is(
  (select count(*)::int from better_supabase.ledger_accounts where code = 'invoices:discount:purchase:EUR'),
  1,
  'the discount is booked on its own ledger account'
);
select is(
  (better_supabase.list_invoice_allocations('00000000-0000-4000-8000-000000000001', 'pay-2') -> 0 ->> 'discount'),
  '2000',
  'the allocation list reports the discount'
);

select better_supabase.unallocate_payment('00000000-0000-4000-8000-000000000001', 'pay-2');
select is(
  pg_temp.bal('BILL-1'),
  '100000',
  'unallocating restores the balance including the discount'
);

-- Approval: bills from 60 000 up need the owner's approval.
select is(
  (select jsonb_array_length(better_supabase.set_invoice_approval_levels('00000000-0000-4000-8000-000000000001',
    jsonb_build_array(jsonb_build_object('minAmount', '60000', 'approverId', '00000000-0000-4000-8000-0000000000a1')))) ),
  1,
  'the organization sets one approval level'
);
select is(
  (select jsonb_build_array(better_supabase.purchase_invoice_approval_status((select id from ids where name = 'BILL-1')) ->> 'status',
    better_supabase.purchase_invoice_approval_status((select id from ids where name = 'BILL-2')) ->> 'status')),
  '["pending", "not_required"]'::jsonb,
  'a bill over the level is pending, one under it needs nothing'
);

insert into ids values ('journal', (select id from better_supabase.accounting_journals
  where tenant_id = '00000000-0000-4000-8000-000000000001' and code = 'BNK'));
insert into ids values ('account', (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('name', 'Main', 'iban', 'NL91ABNA0417164300', 'currency', 'EUR', 'journalId', (select id from ids where name = 'journal'))) ->> 'id')::uuid);

select throws_ok(
  format($$select better_supabase.create_payment_batch('00000000-0000-4000-8000-000000000001', jsonb_build_object(
    'accountId', %L, 'dueBy', '2026-10-31', 'invoiceIds', jsonb_build_array(%L),
    'creditors', jsonb_build_object(%L, jsonb_build_object('name', 'Open item supplier', 'iban', 'NL02ABNA0123456789'))))$$,
    (select id from ids where name = 'account'), (select id from ids where name = 'BILL-1'), (select id from ids where name = 'supplier')),
  '55000',
  'a bill in the batch still needs approval',
  'naming a pending bill refuses the batch'
);

insert into ids values ('batch1', (better_supabase.create_payment_batch('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'accountId', (select id from ids where name = 'account'), 'dueBy', '2026-10-31', 'executionOn', '2026-10-26',
  'creditors', jsonb_build_object((select id::text from ids where name = 'supplier'), jsonb_build_object('name', 'Open item supplier', 'iban', 'NL02ABNA0123456789')))) ->> 'id')::uuid);
select is(
  (select jsonb_agg(i ->> 'invoiceId' order by i ->> 'invoiceId')
   from jsonb_array_elements(better_supabase.get_payment_batch((select id from ids where name = 'batch1')) -> 'items') i),
  jsonb_build_array((select id::text from ids where name = 'BILL-2')),
  'without approval only the bill that needs none is selected'
);

select is(
  (better_supabase.approve_purchase_invoice((select id from ids where name = 'BILL-1'), 'ok') -> 'approval' ->> 'status'),
  'approved',
  'the approver signs the bill'
);
select better_supabase.cancel_payment_batch((select id from ids where name = 'batch1'));

insert into ids values ('batch2', (better_supabase.create_payment_batch('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'accountId', (select id from ids where name = 'account'), 'dueBy', '2026-10-31', 'executionOn', '2026-10-26',
  'creditors', jsonb_build_object((select id::text from ids where name = 'supplier'), jsonb_build_object('name', 'Open item supplier', 'iban', 'NL02ABNA0123456789')))) ->> 'id')::uuid);
select is(
  (select jsonb_build_array(b ->> 'itemCount', b ->> 'total', b ->> 'status')
   from (select better_supabase.get_payment_batch((select id from ids where name = 'batch2')) b) x),
  '["2", "150000", "draft"]'::jsonb,
  'once approved both bills are in the batch'
);

select is(
  (better_supabase.post_payment_batch((select id from ids where name = 'batch2')) ->> 'status'),
  'posted',
  'the batch posts'
);
select is(
  pg_temp.bal('BILL-2'),
  '50000',
  'posting only marks the bills pending bank confirmation; they stay open'
);

-- The bank debit closes the batch.
select better_supabase.import_bank_statement((select id from ids where name = 'account'), jsonb_build_object(
  'reference', 'STMT-SEPA', 'format', 'camt053', 'fromOn', '2026-10-26', 'untilOn', '2026-10-26',
  'openingBalance', '1000000', 'closingBalance', '850000',
  'transactions', jsonb_build_array(jsonb_build_object('externalId', 'DEBIT-1', 'bookedOn', '2026-10-26', 'amount', '-150000',
    'counterpartyName', 'SEPA batch', 'remittance', 'Batch'))));
insert into ids select 'tx', id from better_supabase.bank_transactions where external_id = 'DEBIT-1';
select better_supabase.match_bank_transaction((select id from ids where name = 'tx'),
  jsonb_build_array(jsonb_build_object('targetType', 'payment_batch', 'targetId', (select id from ids where name = 'batch2'), 'amount', '-150000')));
select is(
  (select jsonb_build_array(b ->> 'status', b -> 'items' -> 0 ->> 'status')
   from (select better_supabase.get_payment_batch((select id from ids where name = 'batch2')) b) x),
  '["reconciled", "paid"]'::jsonb,
  'matching the bank debit reconciles the batch and marks its items paid'
);
select is(
  (select jsonb_agg(status::text order by identifier) from better_supabase.invoices where identifier in ('BILL-1', 'BILL-2')),
  '["paid", "paid"]'::jsonb,
  'the bills are paid'
);

select * from finish();
rollback;
