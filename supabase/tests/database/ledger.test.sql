-- The ledger module on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) opens accounts and posts balanced transactions, the member
-- (…00a2) reads only the account they own, and Globex (…0002) sees nothing.
begin;
select plan(16);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.credit', better_supabase.open_ledger_account(
  '00000000-0000-4000-8000-000000000001', 'credit', 'credit:a001', 'Store credit', 'EUR',
  holder_type => 'customer', holder_id => '00000000-0000-4000-8000-00000000a001',
  owner_id => '00000000-0000-4000-8000-0000000000a2'
) ->> 'id', true);
select set_config('test.source', better_supabase.open_ledger_account(
  '00000000-0000-4000-8000-000000000001', 'credit_source', 'credit:promotions', 'Promotions', 'EUR',
  allow_negative => true
) ->> 'id', true);

select throws_ok(
  $$select better_supabase.open_ledger_account('00000000-0000-4000-8000-000000000001', 'credit', 'credit:a001', 'Again', 'EUR')$$,
  '23505',
  'an account with this code already exists',
  'an account code is unique in the organization'
);

select set_config('test.grant', better_supabase.post_ledger_transaction(
  '00000000-0000-4000-8000-000000000001', 'credit.grant',
  jsonb_build_array(
    jsonb_build_object('account', current_setting('test.credit'), 'amount', '2500'),
    jsonb_build_object('account', current_setting('test.source'), 'amount', '-2500')
  ),
  idempotency_key => 'welcome:a001'
) ->> 'id', true);

select is(
  (select balance from better_supabase.ledger_balances where account_id = current_setting('test.credit')::uuid),
  2500::bigint,
  'a posting moves the amount into the credit account'
);
select is(
  better_supabase.post_ledger_transaction(
    '00000000-0000-4000-8000-000000000001', 'credit.grant',
    jsonb_build_array(
      jsonb_build_object('account', current_setting('test.credit'), 'amount', '2500'),
      jsonb_build_object('account', current_setting('test.source'), 'amount', '-2500')
    ),
    idempotency_key => 'welcome:a001'
  ) ->> 'id',
  current_setting('test.grant'),
  'the same idempotency key returns the first transaction'
);
select throws_ok(
  format($$select better_supabase.post_ledger_transaction('00000000-0000-4000-8000-000000000001', 'credit.grant', '[{"account":"%s","amount":"100"},{"account":"%s","amount":"-90"}]')$$,
    current_setting('test.credit'), current_setting('test.source')),
  '23514',
  'the lines of a ledger transaction must sum to zero per unit',
  'an unbalanced transaction is refused'
);
select throws_ok(
  format($$select better_supabase.post_ledger_transaction('00000000-0000-4000-8000-000000000001', 'credit.spend', '[{"account":"%s","amount":"-3000"},{"account":"%s","amount":"3000"}]')$$,
    current_setting('test.credit'), current_setting('test.source')),
  '23514',
  'the account doesn''t have enough available',
  'an account without allow_negative cannot go below zero'
);
select throws_ok(
  $$update better_supabase.ledger_entries set amount = 1$$,
  '42501',
  null,
  'members cannot update entries directly'
);

select set_config('test.hold', better_supabase.place_ledger_hold(
  current_setting('test.credit')::uuid, 1000
) ->> 'id', true);
select is(
  (select (x ->> 'available')::bigint from jsonb_array_elements(better_supabase.list_ledger_accounts('00000000-0000-4000-8000-000000000001', 'credit')) x),
  1500::bigint,
  'a hold reserves part of the available balance'
);
select is(
  better_supabase.capture_ledger_hold(current_setting('test.hold')::uuid, current_setting('test.source')::uuid, 400) ->> 'status',
  'captured',
  'a partial capture closes the hold'
);
select is(
  (select balance from better_supabase.ledger_balances where account_id = current_setting('test.credit')::uuid),
  2100::bigint,
  'the capture moves only the captured amount'
);
select throws_ok(
  format($$select better_supabase.release_ledger_hold('%s')$$, current_setting('test.hold')),
  '55000',
  'this hold is no longer active',
  'a captured hold cannot be released'
);

select set_config('test.bonus', better_supabase.post_ledger_transaction(
  '00000000-0000-4000-8000-000000000001', 'credit.grant',
  jsonb_build_array(
    jsonb_build_object('account', current_setting('test.credit'), 'amount', '100'),
    jsonb_build_object('account', current_setting('test.source'), 'amount', '-100')
  )
) ->> 'id', true);
select is(
  better_supabase.reverse_ledger_transaction(current_setting('test.bonus')::uuid) ->> 'reverses',
  current_setting('test.bonus'),
  'a reversal points at the transaction it reverses'
);
select throws_ok(
  format($$select better_supabase.reverse_ledger_transaction('%s')$$, current_setting('test.bonus')),
  '55000',
  'this transaction is a reversal or is already reversed',
  'a transaction reverses once'
);

-- Acme member: owns the credit account, holds no ledger permission.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select results_eq(
  $$select code from better_supabase.ledger_accounts where tenant_id = '00000000-0000-4000-8000-000000000001' and kind like 'credit%'$$,
  $$values ('credit:a001')$$,
  'the member reads the account they own and not the source'
);
select throws_ok(
  format($$select better_supabase.post_ledger_transaction('00000000-0000-4000-8000-000000000001', 'credit.grant', '[{"account":"%s","amount":"1"},{"account":"%s","amount":"-1"}]')$$,
    current_setting('test.credit'), current_setting('test.source')),
  '42501',
  'not allowed to post ledger transactions',
  'a member without ledger.post cannot post'
);
select throws_ok(
  $$select better_supabase.open_ledger_account('00000000-0000-4000-8000-000000000001', 'credit', 'credit:mine', 'Mine', 'EUR')$$,
  '42501',
  'not allowed to manage ledger accounts',
  'a member without ledger.manage cannot open an account'
);

-- Globex owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.ledger_accounts where tenant_id = '00000000-0000-4000-8000-000000000001'),
  0::bigint,
  'Globex reads no Acme accounts'
);

select * from finish();
rollback;
