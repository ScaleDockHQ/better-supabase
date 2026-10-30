-- The accounting module on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) sets up the books, posts a balanced entry and closes a period,
-- the member (…00a2) can't read or write them, and Globex (…0002) sees nothing.
begin;
select plan(20);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.setup_accounting('00000000-0000-4000-8000-000000000001', 'EUR') ->> 'functionalCurrency',
  'EUR',
  'the admin sets up the books'
);
select is(
  (select count(*)::integer from better_supabase.accounting_journals
   where tenant_id = '00000000-0000-4000-8000-000000000001'),
  5,
  'setup seeds the default journals'
);
select is(
  jsonb_array_length(better_supabase.open_fiscal_year('00000000-0000-4000-8000-000000000001', 2026)),
  12,
  'a fiscal year opens twelve monthly periods'
);

select set_config('test.journal', (
  select id::text from better_supabase.accounting_journals
  where tenant_id = '00000000-0000-4000-8000-000000000001' and code = 'SAL'
), true);
select set_config('test.entry', better_supabase.save_accounting_entry(
  current_setting('test.journal')::uuid, '2026-03-05',
  '[{"accountCode":"1200","debit":"12100"},{"accountCode":"4000","credit":"12100"}]'
) ->> 'id', true);

select is(
  better_supabase.post_accounting_entry(current_setting('test.entry')::uuid) ->> 'number',
  'SAL-2026-00001',
  'posting numbers the entry per journal and fiscal year'
);
select throws_ok(
  $$update better_supabase.accounting_entries set memo = 'edited'$$,
  '42501',
  null,
  'members can''t write entries directly'
);
select throws_ok(
  format(
    $$select better_supabase.post_accounting_entry((better_supabase.save_accounting_entry(%L::uuid, '2026-03-06', '[{"accountCode":"1200","debit":"500"},{"accountCode":"4000","credit":"400"}]') ->> 'id')::uuid)$$,
    current_setting('test.journal')
  ),
  '23514',
  'the debits and credits of the entry differ in the functional currency',
  'an unbalanced entry is refused'
);
select is(
  better_supabase.accounting_trial_balance('00000000-0000-4000-8000-000000000001') #>> '{totals,debit}',
  '12100',
  'the trial balance sums the posted lines'
);
select is(
  (better_supabase.accounting_balance_sheet('00000000-0000-4000-8000-000000000001', '2026-12-31') ->> 'balanced')::boolean,
  true,
  'the balance sheet balances with the year''s earnings'
);

select set_config('test.march', (
  select id::text from better_supabase.accounting_periods
  where tenant_id = '00000000-0000-4000-8000-000000000001' and fiscal_year = 2026 and number = 3
), true);

select is(
  better_supabase.close_accounting_period(current_setting('test.march')::uuid) ->> 'status',
  'closed',
  'the admin closes a period without drafts'
);
select throws_ok(
  format(
    $$select better_supabase.post_accounting_entry((better_supabase.save_accounting_entry(%L::uuid, '2026-03-20', '[{"accountCode":"1200","debit":"100"},{"accountCode":"4000","credit":"100"}]') ->> 'id')::uuid)$$,
    current_setting('test.journal')
  ),
  '55000',
  'the entry date is in a closed period or on or before the lock date',
  'a closed period takes no new entries'
);

select throws_ok(
  $$select better_supabase.post_accounting_source('unknown_source', 'x')$$,
  '22023',
  'no installed block books this source type',
  'a source type no block books is refused'
);
select is(
  better_supabase.post_accounting_source('invoice', '00000000-0000-4000-8000-00000000ffff'),
  null,
  'a source with nothing to book books nothing'
);

select set_config('test.budget', better_supabase.save_accounting_budget(
  '00000000-0000-4000-8000-000000000001', 'Plan 2026', 2026, null,
  '[{"accountCode":"4000","periodNumber":3,"amount":"10000"}]'
) ->> 'id', true);

select is(
  better_supabase.accounting_budget_vs_actual(current_setting('test.budget')::uuid, 3) #>> '{lines,0,variance}',
  '2100',
  'budget against actual sets the posted revenue against the plan'
);
select is(
  jsonb_array_length(better_supabase.list_accounting_budgets('00000000-0000-4000-8000-000000000001', 2026)),
  1,
  'the budgets of a fiscal year are listed'
);
select is(
  better_supabase.accounting_tax_report('00000000-0000-4000-8000-000000000001', '2026-01-01', '2026-12-31') ->> 'netTax',
  '0',
  'the tax report is empty without posted tax lines'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select better_supabase.save_accounting_budget('00000000-0000-4000-8000-000000000001', 'Member plan', 2026)$$,
  '42501',
  null,
  'a member without accounting.write can''t save budgets'
);
select is(
  (select count(*)::integer from better_supabase.accounting_entries),
  0,
  'a member without accounting.read sees no entries'
);
select throws_ok(
  format(
    $$select better_supabase.save_accounting_entry(%L::uuid, '2026-04-01', '[{"accountCode":"1200","debit":"1"},{"accountCode":"4000","credit":"1"}]')$$,
    current_setting('test.journal')
  ),
  '42501',
  null,
  'a member without accounting.write can''t save entries'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*)::integer from better_supabase.accounting_accounts),
  0,
  'another organization sees none of the accounts'
);
select is(
  better_supabase.accounting_trial_balance('00000000-0000-4000-8000-000000000001') #>> '{totals,debit}',
  '0',
  'another organization''s trial balance of Acme is empty'
);

select * from finish();
rollback;
