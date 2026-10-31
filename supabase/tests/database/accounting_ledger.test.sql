-- The general ledger on accounting (ADR 0144): closed against locked periods,
-- opening balances and the year-end carry forward, the trial balance per
-- period and a repeatable ledger import. The admin (…00a1) of Acme (…0001)
-- keeps the books, the service role runs the import.
begin;
select plan(24);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select better_supabase.setup_accounting('00000000-0000-4000-8000-000000000001', 'EUR');
select better_supabase.open_fiscal_year('00000000-0000-4000-8000-000000000001', 2026);

select set_config('test.journal', (
  select id::text from better_supabase.accounting_journals
  where tenant_id = '00000000-0000-4000-8000-000000000001' and code = 'SAL'
), true);
select set_config('test.entry', better_supabase.save_accounting_entry(
  current_setting('test.journal')::uuid, '2026-03-05',
  '[{"accountCode":"1200","debit":"12100"},{"accountCode":"4000","credit":"12100"}]'
) ->> 'id', true);
select better_supabase.post_accounting_entry(current_setting('test.entry')::uuid);

select set_config('test.feb', (
  select id::text from better_supabase.accounting_periods
  where tenant_id = '00000000-0000-4000-8000-000000000001' and fiscal_year = 2026 and number = 2
), true);
select set_config('test.march', (
  select id::text from better_supabase.accounting_periods
  where tenant_id = '00000000-0000-4000-8000-000000000001' and fiscal_year = 2026 and number = 3
), true);

-- Accounts and journals.
select is(
  (select normal_side from better_supabase.accounting_accounts
   where tenant_id = '00000000-0000-4000-8000-000000000001' and code = '1200'),
  'debit',
  'a receivable account is debit normal'
);
select is(
  (select normal_side from better_supabase.accounting_accounts
   where tenant_id = '00000000-0000-4000-8000-000000000001' and code = '4000'),
  'credit',
  'a revenue account is credit normal'
);
select throws_ok(
  $$select better_supabase.save_accounting_account('00000000-0000-4000-8000-000000000001', '9999', 'Odd', 'asset', null, null, null, false, null, 'sideways')$$,
  null,
  null,
  'an unknown normal side is refused'
);

-- Trial balance per period.
select is(
  better_supabase.accounting_period_trial_balance(current_setting('test.march')::uuid) #>> '{totals,debit}',
  '12100',
  'the March trial balance holds the March entry'
);
select is(
  better_supabase.accounting_period_trial_balance(current_setting('test.feb')::uuid) #>> '{totals,debit}',
  '0',
  'the February trial balance is empty'
);
select is(
  better_supabase.accounting_period_trial_balance(current_setting('test.march')::uuid) #>> '{totals,opening}',
  '0',
  'the March trial balance opens at zero'
);
select is(
  better_supabase.accounting_column_balance('00000000-0000-4000-8000-000000000001', '2026-03-01', '2026-03-31') #>> '{totals,closingDebit}',
  '12100',
  'the column balance closes with the debit column'
);
select is(
  jsonb_array_length(better_supabase.accounting_journal_listing('00000000-0000-4000-8000-000000000001', '2026-03-01', '2026-03-31') -> 'journals'),
  1,
  'the journal listing names the journal with entries'
);

-- Closed against locked.
select better_supabase.close_accounting_period(current_setting('test.feb')::uuid);
select better_supabase.close_accounting_period(current_setting('test.march')::uuid);
select throws_ok(
  $$select better_supabase.lock_accounting_period(gen_random_uuid())$$,
  null,
  null,
  'a period that does not exist can''t be locked'
);
select is(
  better_supabase.lock_accounting_period(current_setting('test.march')::uuid) ->> 'status',
  'locked',
  'a closed period locks'
);
select throws_ok(
  format(
    $$select better_supabase.post_accounting_entry((better_supabase.save_accounting_entry(%L::uuid, '2026-03-20', '[{"accountCode":"1200","debit":"100"},{"accountCode":"4000","credit":"100"}]') ->> 'id')::uuid)$$,
    current_setting('test.journal')
  ),
  '55000',
  null,
  'a locked period takes no new entries'
);

-- The ledger import: closed takes it, locked refuses it, a second run is a no-op.
select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'ledger', '{}'::jsonb) ->> 'id'),
  true
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'accounting_account',
    '[{"key":"1900","data":{"code":"1900","name":"Clearing","type":"asset","parentCode":"1200"}}]'::jsonb
  ) ->> 'inserted'),
  '1',
  'the import writes an account under its parent by code'
);
select is(
  (select level::int from better_supabase.accounting_accounts
   where tenant_id = '00000000-0000-4000-8000-000000000001' and code = '1900'),
  (select level::int + 1 from better_supabase.accounting_accounts
   where tenant_id = '00000000-0000-4000-8000-000000000001' and code = '1200'),
  'an account sits one level below its parent'
);

select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'accounting_entry',
    '[{"key":"feb-1","data":{"journalCode":"SAL","entryDate":"2026-02-10","lines":[{"accountCode":"1200","debit":"500"},{"accountCode":"4000","credit":"500"}]}}]'::jsonb
  ) ->> 'inserted'),
  '1',
  'the import posts an entry into a closed period'
);
select is(
  (select count(*)::int from better_supabase.accounting_entries
   where tenant_id = '00000000-0000-4000-8000-000000000001' and entry_date = '2026-02-10' and status = 'posted'),
  1,
  'the imported entry is posted'
);
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'accounting_entry',
    '[{"key":"feb-1","data":{"journalCode":"SAL","entryDate":"2026-02-10","lines":[{"accountCode":"1200","debit":"500"},{"accountCode":"4000","credit":"500"}]}}]'::jsonb
  ) ->> 'unchanged'),
  '1',
  'the same file again changes nothing'
);
select is(
  (select count(*)::int from better_supabase.accounting_entries
   where tenant_id = '00000000-0000-4000-8000-000000000001' and entry_date = '2026-02-10'),
  1,
  'and writes no second entry'
);
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'accounting_entry',
    '[{"key":"mar-1","data":{"journalCode":"SAL","entryDate":"2026-03-12","lines":[{"accountCode":"1200","debit":"500"},{"accountCode":"4000","credit":"500"}]}}]'::jsonb
  ) -> 'errors' -> 0 ->> 'code'),
  'ACCOUNTING_PERIOD_LOCKED',
  'a locked period refuses the import item'
);
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'accounting_entry',
    '[{"key":"bad-1","data":{"journalCode":"SAL","entryDate":"2026-02-11","lines":[{"accountCode":"1200","debit":"500"},{"accountCode":"4000","credit":"400"}]}}]'::jsonb
  ) -> 'errors' -> 0 ->> 'code'),
  'IMPORT_ITEM_INVALID',
  'unbalanced lines are reported on their item'
);

-- Opening balances and the carry forward.
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'accounting_opening_balance',
    '[{"key":"2026-1200","data":{"fiscalYear":2026,"accountCode":"1200","amount":"7000"}},{"key":"2026-4000","data":{"fiscalYear":2026,"accountCode":"4000","amount":"-7000"}}]'::jsonb
  ) ->> 'inserted'),
  '2',
  'the import writes opening balances'
);
select is(
  better_supabase.list_accounting_opening_balances('00000000-0000-4000-8000-000000000001', 2026) ->> 'total',
  '0',
  'the imported balances add up to zero'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.post_accounting_opening_balances('00000000-0000-4000-8000-000000000001', 2026) ->> 'id',
  better_supabase.post_accounting_opening_balances('00000000-0000-4000-8000-000000000001', 2026) ->> 'id',
  'posting the opening balances twice returns one entry'
);
select throws_ok(
  $$select better_supabase.save_accounting_opening_balances('00000000-0000-4000-8000-000000000001', 2026, '[{"accountCode":"1200","amount":"1"}]')$$,
  null,
  null,
  'a posted year takes no more opening balances'
);

select better_supabase.close_fiscal_year('00000000-0000-4000-8000-000000000001', 2026);
select ok(
  (select count(*) from jsonb_array_elements(
    better_supabase.list_accounting_opening_balances('00000000-0000-4000-8000-000000000001', 2027) -> 'balances'
  ) b where b ->> 'source' = 'carried') > 0,
  'closing the year carries the balance accounts into the next year'
);

select * from finish();
rollback;
