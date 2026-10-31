-- Tills on the fixture. The Acme owner (…a1) opens a till session with a float,
-- records cash movements, closes it with a count that is short and books the
-- difference, deposits the cash and reconciles the deposit against a bank
-- transaction. A second open session, a refund above the drawer, a deposit above
-- the count and an open-session deposit are refused. The Acme member (…a2) holds
-- no tills keys and sees nothing, and the Globex owner (…a3) sees none of it.
-- Run with `supabase test db`.
begin;
select plan(19);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('tills', 'till_sessions', 'till_movements', 'till_counts', 'till_deposits')
     and rowsecurity),
  5::bigint,
  'the tills tables have RLS enabled'
);
select table_privs_are('better_supabase', 'tills', 'anon', '{}'::text[], 'anon has no privileges on tills');
select table_privs_are('better_supabase', 'till_counts', 'anon', '{}'::text[], 'anon has no privileges on counts');
select table_privs_are('better_supabase', 'till_deposits', 'authenticated', array['SELECT'], 'members can only read deposits');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select better_supabase.setup_accounting('00000000-0000-4000-8000-000000000001', 'EUR');
select better_supabase.open_fiscal_year('00000000-0000-4000-8000-000000000001', 2026);
select set_config('t.account', (
  select id::text from better_supabase.accounting_accounts
  where tenant_id = '00000000-0000-4000-8000-000000000001' and code = '1200'
), true);

select better_supabase.set_accounting_account_role('00000000-0000-4000-8000-000000000001', 'bank', (
  select id from better_supabase.accounting_accounts
  where tenant_id = '00000000-0000-4000-8000-000000000001' and code <> '1200' order by code limit 1));

select set_config('t.till', better_supabase.create_till(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('name', 'Front counter', 'currency', 'EUR', 'accountId', current_setting('t.account'))) ->> 'id', true);
select is(
  (select t ->> 'currency' from (select better_supabase.list_tills('00000000-0000-4000-8000-000000000001') -> 0 t) x),
  'EUR',
  'a till keeps its currency'
);

select set_config('t.session', better_supabase.open_till_session(current_setting('t.till')::uuid, 10000, 'Morning shift') ->> 'id', true);
select throws_ok(
  format($$select better_supabase.open_till_session(%L)$$, current_setting('t.till')),
  '55000',
  null,
  'a till has one open session at a time'
);

select better_supabase.record_till_movement(current_setting('t.session')::uuid, 'cash_sale', 25000);
select better_supabase.record_till_movement(current_setting('t.session')::uuid, 'cash_refund', 2000, 'wrong size');
select is(
  (better_supabase.get_till_session(current_setting('t.session')::uuid) ->> 'expected'),
  '33000',
  'the expected cash is the float plus sales minus refunds'
);
select throws_ok(
  format($$select better_supabase.record_till_movement(%L, 'cash_out', 99999999)$$, current_setting('t.session')),
  '22023',
  null,
  'cash out cannot exceed the drawer'
);
select throws_ok(
  format($$select better_supabase.deposit_till_cash(%L, '{"amount": "100"}')$$, current_setting('t.session')),
  '55000',
  null,
  'cash is deposited only from a closed session'
);

select is(
  (select jsonb_build_array(r ->> 'status', r -> 'count' ->> 'counted', r -> 'count' ->> 'variance')
   from (select better_supabase.close_till_session(current_setting('t.session')::uuid, '{"denominations": {"5000": 6, "1000": 2}}') r) x),
  '["closed", "32000", "-1000"]'::jsonb,
  'closing counts the denominations and keeps the variance'
);
select isnt(
  (select entry_id from better_supabase.till_counts where session_id = current_setting('t.session')::uuid),
  null,
  'a count with a variance books an accounting entry'
);
select throws_ok(
  format($$select better_supabase.record_till_movement(%L, 'cash_in', 100)$$, current_setting('t.session')),
  '55000',
  null,
  'a closed session takes no movements'
);
select throws_ok(
  format($$select better_supabase.deposit_till_cash(%L, '{"amount": "32001"}')$$, current_setting('t.session')),
  '22023',
  null,
  'deposits cannot exceed the counted cash'
);
select set_config('t.deposit', better_supabase.deposit_till_cash(current_setting('t.session')::uuid, '{"amount": "32000", "reference": "Bag 1"}') ->> 'id', true);
select is(
  (select status from better_supabase.till_deposits where id = current_setting('t.deposit')::uuid),
  'pending',
  'a deposit waits for the bank'
);

select set_config('t.bank', better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001', '{"name": "Till bank", "iban": "NL91ABNA0417164300", "currency": "EUR"}') ->> 'id', true);
select better_supabase.import_bank_statement(current_setting('t.bank')::uuid,
  '{"transactions": [{"bookedOn": "2026-10-31", "amount": "32000", "currency": "EUR", "description": "Cash deposit"}]}'::jsonb);
select set_config('t.tx', (select id::text from better_supabase.bank_transactions limit 1), true);
select is(
  (better_supabase.reconcile_till_deposit(current_setting('t.deposit')::uuid, current_setting('t.tx')::uuid) ->> 'status'),
  'reconciled',
  'a deposit reconciles against the matching bank transaction'
);
select throws_ok(
  format($$select better_supabase.reconcile_till_deposit(%L, %L)$$, current_setting('t.deposit'), current_setting('t.tx')),
  '55000',
  null,
  'a reconciled deposit cannot be reconciled again'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.get_till_session(%L)$$, current_setting('t.session')),
  'P0002',
  null,
  'a member without tills keys cannot see the session'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  jsonb_array_length(better_supabase.list_tills('00000000-0000-4000-8000-000000000002')),
  0,
  'another organization sees no tills'
);
select is(
  (select count(*)::integer from better_supabase.till_sessions),
  0,
  'another organization reads no sessions'
);

select * from finish();
rollback;
