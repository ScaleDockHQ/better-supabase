-- reconcile_bank_account (ADR 1235): the Acme owner matches an account's
-- unmatched transactions to their best open invoice in one call. Run with
-- `supabase test db`.
begin;
select plan(7);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select better_supabase.setup_accounting('00000000-0000-4000-8000-000000000001', 'EUR');
select better_supabase.open_fiscal_year('00000000-0000-4000-8000-000000000001', 2026);

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('journal', (select id from better_supabase.accounting_journals
  where tenant_id = '00000000-0000-4000-8000-000000000001' and code = 'BNK'));

insert into ids values ('account', (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('name', 'Main', 'iban', 'nl02 abna 0123 4567 89', 'currency', 'EUR', 'journalId', (select id from ids where name = 'journal'))) ->> 'id')::uuid);
select is(
  (select jsonb_build_array(iban, currency, journal_id = (select id from ids where name = 'journal'))
   from better_supabase.bank_accounts where id = (select id from ids where name = 'account')),
  '["NL02ABNA0123456789", "EUR", true]'::jsonb,
  'the owner adds an account; the IBAN is stored upper case without spaces'
);

insert into ids values ('customer', (better_supabase.save_company('00000000-0000-4000-8000-000000000001', null,
  '{"name": "Banking customer"}') ->> 'id')::uuid);
insert into ids values ('invoice', (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Consulting', 'currency', 'EUR', 'company', jsonb_build_object('id', (select id from ids where name = 'customer'))),
  jsonb_build_array(jsonb_build_object('description', 'Consulting', 'quantity', 1, 'unitAmount', 50000))) ->> 'id')::uuid);
select better_supabase.issue_invoice((select id from ids where name = 'invoice'), current_date);

select set_config('t.total', (select total::text from better_supabase.invoices where id = (select id from ids where name = 'invoice')), true);
select set_config('t.statement', jsonb_build_object(
  'reference', 'STMT-2026-10', 'format', 'camt053', 'fromOn', '2026-10-01', 'untilOn', '2026-10-31',
  'openingBalance', '100000', 'closingBalance', (100000 + current_setting('t.total')::bigint - 2500 + 999)::text,
  'transactions', jsonb_build_array(
    jsonb_build_object('externalId', 'T1', 'bookedOn', '2026-10-15', 'amount', current_setting('t.total'),
      'counterpartyName', 'Banking customer', 'counterpartyIban', 'DE89370400440532013000',
      'remittance', 'Payment ' || coalesce((select identifier from better_supabase.invoices where id = (select id from ids where name = 'invoice')), 'invoice')),
    jsonb_build_object('externalId', 'T2', 'bookedOn', '2026-10-20', 'amount', '-2500', 'counterpartyName', 'Bank', 'remittance', 'Account fees'),
    jsonb_build_object('externalId', 'T3', 'bookedOn', '2026-10-25', 'amount', '999', 'counterpartyName', 'Own savings', 'remittance', 'Transfer'))
)::text, true);


select better_supabase.import_bank_statement((select id from ids where name = 'account'), current_setting('t.statement')::jsonb);

select set_config('t.run', better_supabase.reconcile_bank_account((select id from ids where name = 'account'))::text, true);
select is(
  jsonb_array_length(current_setting('t.run')::jsonb -> 'matched'),
  1,
  'the transaction that names the invoice is matched'
);
select is(
  (current_setting('t.run')::jsonb -> 'matched' -> 0 ->> 'status'),
  'matched',
  'the matched transaction comes back as matched'
);
select is(
  jsonb_array_length(current_setting('t.run')::jsonb -> 'unmatched'),
  2,
  'the transactions without an invoice are listed as unmatched'
);
select is(
  jsonb_array_length(current_setting('t.run')::jsonb -> 'failed'),
  0,
  'nothing failed'
);
select is(
  (select status from better_supabase.invoices where id = (select id from ids where name = 'invoice')),
  'paid',
  'the match paid the invoice'
);
select is(
  (select jsonb_array_length(better_supabase.reconcile_bank_account((select id from ids where name = 'account')) -> 'matched')),
  0,
  'a second run matches nothing'
);

select * from finish();
rollback;
