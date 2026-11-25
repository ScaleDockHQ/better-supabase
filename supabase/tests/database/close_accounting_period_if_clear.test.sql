-- close_accounting_period_if_clear (ADR 1235): finance.closePeriod as one
-- function. The admin (…a1) of Acme (…0001) closes a period with no blockers
-- in one call, and a second call returns the closed period unchanged.
begin;
select plan(3);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select better_supabase.setup_accounting('00000000-0000-4000-8000-000000000001', 'EUR');
select better_supabase.open_fiscal_year('00000000-0000-4000-8000-000000000001', 2026);
select set_config('test.march', (
  select id::text from better_supabase.accounting_periods
  where tenant_id = '00000000-0000-4000-8000-000000000001' and fiscal_year = 2026 and number = 3
), true);

select set_config('test.first',
  better_supabase.close_accounting_period_if_clear(current_setting('test.march')::uuid)::text, true);

select is(
  (current_setting('test.first')::jsonb ->> 'closed')::boolean,
  true,
  'a period without blockers closes'
);
select is(
  current_setting('test.first')::jsonb -> 'period' ->> 'status',
  'closed',
  'the closed period comes back'
);
select is(
  better_supabase.close_accounting_period_if_clear(current_setting('test.march')::uuid) -> 'period' ->> 'status',
  'closed',
  'a second call returns the closed period'
);

select * from finish();
rollback;
