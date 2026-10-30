-- Asset book values, disposal and project budgets on the fixture's access
-- contract. Ann (…a1) owns Acme (…0001) (supabase/seed.sql).
begin;
select plan(9);

select has_table('better_supabase', 'asset_depreciations', 'the depreciation months table exists');
select has_column('better_supabase', 'time_rates', 'cost_amount', 'a rate card carries a cost');
select has_column('better_supabase', 'work_projects', 'budget_amount', 'a project carries a budget');
select ok(
  not has_function_privilege('authenticated', 'api.run_asset_depreciation(uuid, date)', 'execute'),
  'only the service runs depreciation'
);
select ok(
  not has_table_privilege('authenticated', 'better_supabase.asset_depreciations', 'insert'),
  'members cannot write depreciation months'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'test.asset',
  api.create_asset('00000000-0000-4000-8000-000000000001', 'laptop', 'Laptop') ->> 'id',
  true
);

select throws_ok(
  format($$select api.update_asset(%L, '{"depreciationMethod":"straight_line"}')$$, current_setting('test.asset')),
  '22023',
  null,
  'a depreciation method needs a cost and an acquisition date'
);
select is(
  api.dispose_asset(current_setting('test.asset')::uuid, '2026-06-30', 0) ->> 'status',
  'retired',
  'a disposed asset is retired'
);
select throws_ok(
  format($$select api.update_asset(%L, '{"status":"available"}')$$, current_setting('test.asset')),
  '55000',
  'a disposed asset stays retired and its book value can''t change',
  'a disposed asset cannot come back'
);
select throws_ok(
  $$select api.save_project('00000000-0000-4000-8000-000000000001', null, '{"key":"BGT","name":"Budget","budgetAmount":"100"}')$$,
  '22023',
  null,
  'a budget amount needs a currency'
);

select * from finish();
rollback;
