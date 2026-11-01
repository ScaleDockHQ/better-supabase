-- The banking module on the fixture (ADR 0149). The Acme owner (…a1) adds a
-- bank account on the bank journal, imports a statement twice (the second
-- import adds nothing), matches the customer's payment to its invoice and
-- books the bank's fees through a rule. The member (…a2) reconciles but can't
-- change accounts, and the Globex owner (…a3) sees none of it. Run with
-- `supabase test db`.
begin;
select plan(30);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('bank_accounts', 'bank_statements', 'bank_transactions', 'bank_matches', 'bank_rules')
     and rowsecurity),
  5::bigint,
  'the banking tables have RLS enabled'
);
select table_privs_are('better_supabase', 'bank_transactions', 'anon', '{}'::text[],
  'anon has no privileges on bank transactions');
select table_privs_are('better_supabase', 'bank_transactions', 'authenticated', array['SELECT'],
  'authenticated only reads bank transactions; writes go through the functions');

select is(better_supabase.bank_reference('RF18 5390 0754 7034'), '539007547034',
  'an ISO 11649 creditor reference yields its payload');
select is(better_supabase.bank_reference('4000000202612345'), '202612345',
  'a Dutch betalingskenmerk yields its number without leading zeros');
select is(better_supabase.bank_reference('5000000202612345'), null,
  'a betalingskenmerk with a wrong check digit yields nothing');

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

select throws_ok(
  $$select better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001', '{"name": "Main", "iban": "NL92ABNA0417164300", "currency": "EUR"}')$$,
  '22023',
  'the IBAN''s check digits don''t match',
  'an IBAN with wrong check digits is refused'
);
insert into ids values ('account', (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('name', 'Main', 'iban', 'nl91 abna 0417 1643 00', 'currency', 'EUR', 'journalId', (select id from ids where name = 'journal'))) ->> 'id')::uuid);
select is(
  (select jsonb_build_array(iban, currency, journal_id = (select id from ids where name = 'journal'))
   from better_supabase.bank_accounts where id = (select id from ids where name = 'account')),
  '["NL91ABNA0417164300", "EUR", true]'::jsonb,
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

select is(
  (select jsonb_build_array(r ->> 'imported', r ->> 'skipped')
   from (select better_supabase.import_bank_statement((select id from ids where name = 'account'), current_setting('t.statement')::jsonb) r) x),
  '["3", "0"]'::jsonb,
  'the owner imports a statement with three transactions'
);
select is(
  (select jsonb_build_array(r ->> 'imported', r ->> 'skipped')
   from (select better_supabase.import_bank_statement((select id from ids where name = 'account'), current_setting('t.statement')::jsonb) r) x),
  '["0", "3"]'::jsonb,
  'importing the same statement again adds nothing'
);
select is(
  (select count(*) from better_supabase.bank_statements where account_id = (select id from ids where name = 'account')),
  1::bigint,
  'the second import adds to the statement with the same reference'
);
select throws_ok(
  format($$select better_supabase.import_bank_statement(%L, '{"transactions": [{"bookedOn": "2026-10-01", "amount": "100", "currency": "USD"}]}')$$,
    (select id from ids where name = 'account')),
  '22023',
  'a transaction is in its bank account''s currency',
  'a transaction in another currency is refused'
);

insert into ids select 'tx_' || lower(external_id), id from better_supabase.bank_transactions
where account_id = (select id from ids where name = 'account');

select is(
  (select jsonb_build_array(s -> 0 ->> 'targetId' = (select id from ids where name = 'invoice')::text, s -> 0 -> 'reasons' ? 'amount')
   from (select better_supabase.suggest_bank_matches((select id from ids where name = 'tx_t1')) s) x),
  '[true, true]'::jsonb,
  'the open invoice of the same amount is the first suggestion'
);
select is(
  (select jsonb_build_array(
      jsonb_array_length(b -> 'lines') > 0,
      b #>> '{status,accountId}' = (select id from ids where name = 'account')::text,
      exists (select 1 from jsonb_array_elements(b -> 'suggestions') s
        where s ->> 'transactionId' = (select id from ids where name = 'tx_t1')::text
          and s ->> 'targetId' = (select id from ids where name = 'invoice')::text))
   from (select better_supabase.bank_reconciliation_board((select id from ids where name = 'account')) b) x),
  '[true, true, true]'::jsonb,
  'the reconciliation board holds the status, the lines and the invoice suggestion in one call'
);
select throws_ok(
  format($$select better_supabase.match_bank_transaction(%L, jsonb_build_array(jsonb_build_object('targetType', 'invoice', 'targetId', %L, 'amount', '100')))$$,
    (select id from ids where name = 'tx_t1'), (select id from ids where name = 'invoice')),
  '22023',
  'the matches must add up to the transaction''s amount',
  'matches that don''t add up to the transaction are refused'
);
select is(
  better_supabase.match_bank_transaction((select id from ids where name = 'tx_t1'),
    jsonb_build_array(jsonb_build_object('targetType', 'invoice', 'targetId', (select id from ids where name = 'invoice')))) ->> 'status',
  'matched',
  'the owner matches the payment to its invoice'
);
select is(
  (select status from better_supabase.invoices where id = (select id from ids where name = 'invoice')),
  'paid',
  'matching the payment pays the invoice'
);
select throws_ok(
  format($$select better_supabase.match_bank_transaction(%L, jsonb_build_array(jsonb_build_object('targetType', 'invoice', 'targetId', %L)))$$,
    (select id from ids where name = 'tx_t1'), (select id from ids where name = 'invoice')),
  '55000',
  'a matched bank transaction can''t be matched',
  'a matched transaction can''t be matched again'
);

select better_supabase.save_bank_rule('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'name', 'Bank fees',
  'conditions', '{"type": "group", "combinator": "and", "rules": [{"type": "rule", "path": ["counterpartyName"], "operator": "is", "value": "Bank"}, {"type": "rule", "path": ["direction"], "operator": "is", "value": "out"}]}'::jsonb,
  'accountId', (select id from better_supabase.accounting_accounts where tenant_id = '00000000-0000-4000-8000-000000000001' and code = '6000'),
  'priority', 10));
select better_supabase.save_bank_rule('00000000-0000-4000-8000-000000000001',
  '{"name": "Own transfers", "conditions": {"type": "group", "combinator": "and", "rules": [{"type": "rule", "path": ["counterpartyName"], "operator": "contains", "value": "savings"}]}}');
select throws_ok(
  $$select better_supabase.save_bank_rule('00000000-0000-4000-8000-000000000001', '{"name": "Bad", "conditions": {"type": "rule", "path": ["amount"], "operator": "resembles"}}')$$,
  '22023',
  'conditions must be a filter tree of known operators',
  'a rule with an unknown operator is refused'
);

select is(
  better_supabase.apply_bank_rules((select id from ids where name = 'account')),
  '{"matched": 1, "ignored": 1}'::jsonb,
  'the rules book the fees and set the transfer aside'
);
select is(
  (select jsonb_build_array(t.status, m.target_type, e.status)
   from better_supabase.bank_transactions t
   join better_supabase.bank_matches m on m.transaction_id = t.id
   join better_supabase.accounting_entries e on e.id = m.target_id
   where t.id = (select id from ids where name = 'tx_t2')),
  '["matched", "accounting_entry", "posted"]'::jsonb,
  'the fees are booked as a posted entry on the bank journal'
);
select is(
  (select jsonb_build_array(r ->> 'unmatchedCount', r ->> 'statementBalance', r ->> 'transactionTotal')
   from (select better_supabase.bank_reconciliation_status((select id from ids where name = 'account'), '2026-10-31') r) x),
  jsonb_build_array('0', (100000 + current_setting('t.total')::bigint - 2500 + 999)::text, (current_setting('t.total')::bigint - 2500 + 999)::text),
  'nothing is left unmatched at the end of the statement'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001', '{"name": "Petty", "currency": "EUR"}')$$,
  '42501',
  'not allowed to manage bank accounts',
  'a member can''t add a bank account'
);
select is(
  better_supabase.unmatch_bank_transaction((select id from ids where name = 'tx_t2')) ->> 'status',
  'unmatched',
  'a member undoes the rule''s match, which reverses its entry'
);
select is(
  (select status from better_supabase.invoices where id = (select id from ids where name = 'invoice')),
  'paid',
  'undoing another transaction leaves the invoice paid'
);
select is(
  better_supabase.ignore_bank_transaction((select id from ids where name = 'tx_t2')) ->> 'status',
  'ignored',
  'a member sets an unmatched transaction aside'
);
select throws_ok(
  $$select better_supabase.ignore_bank_transaction((select id from ids where name = 'tx_t2'))$$,
  '55000',
  'a ignored bank transaction can''t be ignored',
  'an ignored transaction can''t be ignored twice'
);
select is(
  better_supabase.ignore_bank_transaction((select id from ids where name = 'tx_t2'), false) ->> 'status',
  'unmatched',
  'un-ignoring puts the transaction back in the queue'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*) from better_supabase.bank_transactions),
  0::bigint,
  'another organization''s owner sees no bank transactions'
);
select throws_ok(
  $$select better_supabase.list_bank_accounts('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  'not allowed to read bank accounts',
  'another organization''s owner can''t list the accounts'
);

select * from finish();
rollback;
