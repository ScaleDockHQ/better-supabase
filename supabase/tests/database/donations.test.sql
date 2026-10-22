-- The donations module on the fixture's access contract: the owner (…00a1) of
-- Acme (…0001) runs a campaign, records gifts from the customers Road Runner
-- (…a001) and Wile E. (…a002) on the ledger, settles a provider charge,
-- tracks a pledge and issues numbered receipts. The member (…00a2) reads
-- nothing.
begin;
select plan(20);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.fund', better_supabase.save_donation_fund(
  '00000000-0000-4000-8000-000000000001', 'roof', 'New roof', kind => 'campaign', goal => 1000000, currency => 'EUR'
) ->> 'id', true);

select set_config('test.gift', better_supabase.record_gift(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 25000, 'EUR',
  fund_id => current_setting('test.fund')::uuid, received_on => '2026-03-01', method => 'bank'
)::text, true);
select is(
  current_setting('test.gift')::jsonb ->> 'status',
  'posted',
  'a gift recorded by hand is posted at once'
);
select is(
  (select count(*)::integer from better_supabase.ledger_transactions t
    where t.idempotency_key = 'donation:' || (current_setting('test.gift')::jsonb ->> 'id') || ':posted'),
  1,
  'the gift is one ledger transaction'
);
select is(
  (better_supabase.list_donation_funds('00000000-0000-4000-8000-000000000001') -> 0 ->> 'raised'),
  '25000',
  'the campaign shows what it raised'
);
select throws_ok(
  $$select better_supabase.record_gift('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a003', 100, 'EUR')$$,
  '22023',
  'the donor is unknown or not in this organization',
  'a donor in another organization is refused'
);
select throws_ok(
  $$select better_supabase.record_gift('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 0, 'EUR')$$,
  '22023',
  'an amount is more than zero minor units',
  'a gift is more than zero'
);

select set_config('test.charge', better_supabase.open_gift(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a002', 10000, 'EUR', provider => 'stripe'
) ->> 'id', true);
select throws_ok(
  format($$select better_supabase.issue_gift_receipt(%L)$$, current_setting('test.charge')),
  '55000',
  'only a posted gift gets a receipt',
  'a pending gift gets no receipt'
);
select is(
  better_supabase.record_gift_payment(current_setting('test.charge')::uuid, 'stripe', 'pi_1', 'succeeded') ->> 'status',
  'posted',
  'a succeeded charge posts the gift'
);
select is(
  better_supabase.record_gift_payment(null, 'stripe', 'pi_1', 'succeeded') ->> 'status',
  'posted',
  'the same report found by payment id changes nothing'
);
select is(
  (select count(*)::integer from better_supabase.ledger_transactions t
    where t.idempotency_key = 'donation:' || current_setting('test.charge') || ':posted'),
  1,
  'a repeated report posts the gift once'
);

select set_config('test.pledge', better_supabase.create_pledge(
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 5000, 'EUR',
  starts_on => '2026-01-01', provider => 'stripe', provider_customer => 'cus_1'
) ->> 'id', true);
select is(
  jsonb_array_length(better_supabase.due_pledge_installments('00000000-0000-4000-8000-000000000001', '2026-03-15')),
  3,
  'three monthly installments are due'
);
select lives_ok(
  format(
    $$select better_supabase.open_gift('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 5000, 'EUR',
      pledge_id => %L, period_start => '2026-01-01', provider => 'stripe')$$,
    current_setting('test.pledge')
  ),
  'the charge run opens the first installment'
);
select is(
  better_supabase.due_pledge_installments('00000000-0000-4000-8000-000000000001', '2026-03-15') -> 0 ->> 'periodStart',
  '2026-01-01',
  'an opened installment without a payment stays due'
);

select set_config('test.receipt', better_supabase.issue_gift_receipt((current_setting('test.gift')::jsonb ->> 'id')::uuid)::text, true);
select matches(
  current_setting('test.receipt')::jsonb ->> 'number',
  '^R-[0-9]+$',
  'a gift receipt gets the next number'
);
select is(
  better_supabase.issue_gift_receipt((current_setting('test.gift')::jsonb ->> 'id')::uuid) ->> 'id',
  current_setting('test.receipt')::jsonb ->> 'id',
  'a second call returns the same receipt'
);
select is(
  better_supabase.issue_yearly_receipt('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 2026, 'EUR') ->> 'amount',
  '25000',
  'the yearly receipt sums the posted gifts of the year'
);
select is(
  better_supabase.yearly_giving_summary('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 2026) -> 'totals',
  '[{"gifts": 1, "amount": "25000", "currency": "EUR"}]'::jsonb,
  'the yearly summary totals the posted gifts per currency'
);
select is(
  better_supabase.record_gift_payment(current_setting('test.charge')::uuid, 'stripe', 'pi_1', 'refunded') ->> 'status',
  'refunded',
  'a refund reverses the posted gift'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select better_supabase.list_gifts('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  'not allowed to read donations',
  'the member cannot read gifts'
);
select throws_ok(
  $$select better_supabase.record_gift('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 100, 'EUR')$$,
  '42501',
  'not allowed to manage donations',
  'the member cannot record gifts'
);
select throws_ok(
  format($$select better_supabase.get_gift(%L)$$, current_setting('test.gift')::jsonb ->> 'id'),
  'P0002',
  'no such gift you can read',
  'a gift the member cannot read looks missing'
);

select * from finish();
rollback;
