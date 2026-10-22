-- The expenses module on the fixture's access contract: the owner (…00a1) of
-- Acme (…0001) sets spend policies on categories, the member (…00a2) files a
-- report that the policy checks on submit, the owner approves it through the
-- approvals block, which books it on the ledger, and then reimburses it.
begin;
select plan(20);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.travel', better_supabase.save_expense_category(
  '00000000-0000-4000-8000-000000000001', 'travel', 'Travel', 'EUR', limit_amount => 50000, receipt_over => 20000
) ->> 'id', true);
select set_config('test.meals', better_supabase.save_expense_category(
  '00000000-0000-4000-8000-000000000001', 'meals', 'Meals'
) ->> 'id', true);
select throws_ok(
  $$select better_supabase.save_expense_category('00000000-0000-4000-8000-000000000001', 'Bad Key', 'Bad')$$,
  '22023',
  'a key is lowercase letters, digits and underscores',
  'a category key is lowercase'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  jsonb_array_length(better_supabase.list_expense_categories('00000000-0000-4000-8000-000000000001')),
  2,
  'the member reads the categories to file lines'
);
select throws_ok(
  $$select better_supabase.save_expense_category('00000000-0000-4000-8000-000000000001', 'gifts', 'Gifts')$$,
  '42501',
  'not allowed to manage expense categories',
  'the member cannot change the policy'
);

select set_config('test.report', better_supabase.create_expense_report(
  '00000000-0000-4000-8000-000000000001', 'Berlin trip', 'EUR'
) ->> 'id', true);
select set_config('test.train', better_supabase.add_expense_line(
  current_setting('test.report')::uuid, current_setting('test.travel')::uuid, '2026-10-01', 30000, 'Train', 'DB'
) ->> 'id', true);
select is(
  better_supabase.add_expense_line(
    current_setting('test.report')::uuid, current_setting('test.meals')::uuid, '2026-10-01', 4000, 'Dinner'
  ) ->> 'currency',
  'EUR',
  'a line takes the report currency'
);
select is(
  better_supabase.get_expense_report(current_setting('test.report')::uuid) ->> 'total',
  '34000',
  'the report totals its lines'
);
select throws_ok(
  format(
    $$select better_supabase.add_expense_line(%L, %L, '2026-10-02', 1000, 'Taxi', currency => 'USD')$$,
    current_setting('test.report'), current_setting('test.travel')
  ),
  '22023',
  'the amount is in another currency than the report',
  'a line is in the report currency'
);
select throws_ok(
  $$select better_supabase.submit_expense_report(gen_random_uuid())$$,
  'P0002',
  'no such expense report',
  'submitting an unknown report fails'
);

select is(
  better_supabase.check_expense_report(current_setting('test.report')::uuid) -> 0 ->> 'kind',
  'receipt',
  'a line over the receipt threshold without a receipt is a finding'
);
select throws_like(
  format($$select better_supabase.submit_expense_report(%L)$$, current_setting('test.report')),
  'the report breaks the spend policy: %',
  'the spend policy is checked on submit'
);
select lives_ok(
  format($$select better_supabase.update_expense_line(%L, amount => 15000)$$, current_setting('test.train')),
  'the member lowers the line under the receipt threshold'
);
select is(
  jsonb_array_length(better_supabase.check_expense_report(current_setting('test.report')::uuid)),
  0,
  'the report now meets the policy'
);
select set_config('test.submitted', better_supabase.submit_expense_report(current_setting('test.report')::uuid)::text, true);
select is(
  current_setting('test.submitted')::jsonb ->> 'status',
  'submitted',
  'the member submits the report for approval'
);
select throws_ok(
  format(
    $$select better_supabase.add_expense_line(%L, %L, '2026-10-02', 1000, 'Taxi')$$,
    current_setting('test.report'), current_setting('test.travel')
  ),
  '55000',
  'only a draft or rejected report can change',
  'a submitted report is locked'
);
select throws_ok(
  format($$select better_supabase.reimburse_expense_report(%L)$$, current_setting('test.report')),
  '42501',
  'not allowed to reimburse expenses',
  'the member cannot reimburse'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select lives_ok(
  format(
    $$select better_supabase.decide_approval(%L, 'approved')$$,
    current_setting('test.submitted')::jsonb ->> 'approvalId'
  ),
  'the owner approves the report'
);
select is(
  better_supabase.get_expense_report(current_setting('test.report')::uuid) ->> 'status',
  'approved',
  'the final approval approves the report'
);
select is(
  (select count(*)::integer from better_supabase.ledger_transactions t
    where t.idempotency_key = 'expense:' || current_setting('test.report') || ':approved'),
  1,
  'the approval books the report on the ledger once'
);
select is(
  better_supabase.reimburse_expense_report(current_setting('test.report')::uuid, reference => 'SEPA-1') ->> 'status',
  'reimbursed',
  'the owner reimburses the report'
);
select is(
  (select b.balance::integer from better_supabase.ledger_balances b
    join better_supabase.ledger_accounts a on a.id = b.account_id
    where a.code = 'expenses:payable:00000000-0000-4000-8000-0000000000a2:EUR'),
  0,
  'nothing is owed to the member after reimbursement'
);
select throws_ok(
  format($$select better_supabase.reimburse_expense_report(%L)$$, current_setting('test.report')),
  '55000',
  'only an approved report can be reimbursed',
  'a report is reimbursed once'
);

select * from finish();
rollback;
