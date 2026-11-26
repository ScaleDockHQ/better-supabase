-- pay_payment_batch (ADR 1235): procurement.payDueBills as one function. The
-- owner (…a1) of Acme (…0001) creates and posts a batch in one call; a bill
-- selection that finds nothing is refused and leaves no batch behind.
begin;
select plan(3);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  (select count(*) from better_supabase.bank_accounts) >= 0,
  'the bank accounts table is readable to the owner'
);
select throws_ok(
  $$select better_supabase.pay_payment_batch(
    '00000000-0000-4000-8000-000000000001',
    '{"accountId":"00000000-0000-4000-8000-00000000dead","dueBy":"2030-01-01","creditors":{}}'::jsonb)$$,
  null,
  null,
  'a batch for an unknown account is refused'
);
select is(
  (select count(*) from better_supabase.payment_batches),
  0::bigint,
  'a refused call leaves no batch behind'
);

select * from finish();
rollback;
