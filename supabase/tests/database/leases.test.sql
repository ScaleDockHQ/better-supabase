-- The leases module on the fixture's access contract: the owner (…00a1) of
-- Acme (…0001) lets a unit to the customer Road Runner (…a001), posts rent
-- once per period on the ledger, records a payment, renews and terminates the
-- lease. The member (…00a2) files a maintenance request but can't read leases.
begin;
select plan(20);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.unit', better_supabase.create_asset(
  '00000000-0000-4000-8000-000000000001', 'unit', 'Flat 2A'
) ->> 'id', true);

select set_config('test.lease', better_supabase.create_lease(
  '00000000-0000-4000-8000-000000000001', current_setting('test.unit')::uuid,
  'customer', '00000000-0000-4000-8000-00000000a001', '2026-01-01', 100000, 'EUR',
  ends_on => '2026-07-01', deposit => 200000, title => 'Flat 2A'
) ->> 'id', true);

select is(
  better_supabase.get_lease(current_setting('test.lease')::uuid) ->> 'status',
  'draft',
  'a new lease is a draft'
);
select throws_ok(
  format(
    $$select better_supabase.create_lease('00000000-0000-4000-8000-000000000001', %L, 'customer', '00000000-0000-4000-8000-00000000a003', '2026-01-01', 100, 'EUR')$$,
    current_setting('test.unit')
  ),
  '22023',
  'the party is unknown or not in this organization',
  'a lease cannot name a party in another organization'
);
select throws_ok(
  format(
    $$select better_supabase.create_lease('00000000-0000-4000-8000-000000000001', %L, 'customer', '00000000-0000-4000-8000-00000000a001', '2026-01-01', -1, 'EUR')$$,
    current_setting('test.unit')
  ),
  '22023',
  'rent is more than zero minor units',
  'rent must be more than zero'
);

select is(
  better_supabase.activate_lease(current_setting('test.lease')::uuid) ->> 'depositHeld',
  '200000',
  'activating the lease holds the deposit on the ledger'
);
select set_config('test.overlap', better_supabase.create_lease(
  '00000000-0000-4000-8000-000000000001', current_setting('test.unit')::uuid,
  'customer', '00000000-0000-4000-8000-00000000a002', '2026-03-01', 90000, 'EUR'
) ->> 'id', true);
select throws_ok(
  format($$select better_supabase.activate_lease(%L)$$, current_setting('test.overlap')),
  '23P01',
  'another active lease of this unit overlaps these dates',
  'a unit has one active lease at a time'
);

select is(
  better_supabase.post_due_rent('00000000-0000-4000-8000-000000000001', '2026-03-15'),
  3,
  'rent is posted for January, February and March'
);
select is(
  better_supabase.post_due_rent('00000000-0000-4000-8000-000000000001', '2026-03-15'),
  0,
  'a second run posts nothing'
);
select is(
  jsonb_array_length(better_supabase.list_lease_charges(current_setting('test.lease')::uuid)),
  3,
  'each period has one charge'
);
select is(
  (select count(*)::integer from better_supabase.ledger_transactions t
    where t.idempotency_key like 'leases.rent:' || current_setting('test.lease') || ':%'),
  3,
  'each charge is one ledger transaction keyed by its period'
);
select is(
  better_supabase.get_lease(current_setting('test.lease')::uuid) ->> 'balanceDue',
  '300000',
  'the party owes three periods'
);

select is(
  better_supabase.record_rent_payment(current_setting('test.lease')::uuid, 100000, reference => 'bank-1') ->> 'balanceDue',
  '200000',
  'a payment lowers the balance due'
);
select is(
  better_supabase.record_rent_payment(current_setting('test.lease')::uuid, 100000, reference => 'bank-1') ->> 'balanceDue',
  '200000',
  'the same payment reference is recorded once'
);

select is(
  better_supabase.renew_lease(current_setting('test.lease')::uuid, '2026-12-31', 110000) ->> 'rent',
  '110000',
  'a renewal moves the end and sets the new rent'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  better_supabase.file_maintenance_request(
    '00000000-0000-4000-8000-000000000001', current_setting('test.unit')::uuid, 'Leaking tap',
    lease_id => current_setting('test.lease')::uuid
  ) ->> 'status',
  'open',
  'the member files a maintenance request on the unit'
);
select throws_ok(
  format($$select better_supabase.get_lease(%L)$$, current_setting('test.lease')),
  'P0002',
  'no such lease you can read',
  'a lease the member cannot read looks missing'
);
select throws_ok(
  $$select better_supabase.post_due_rent('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  'not allowed to manage leases',
  'the member cannot post rent'
);
select throws_ok(
  $$select better_supabase.post_due_rent()$$,
  '42501',
  'posting rent for every organization needs the service role',
  'posting rent for every organization needs the service role'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  jsonb_array_length(better_supabase.list_maintenance_requests('00000000-0000-4000-8000-000000000001', current_setting('test.unit')::uuid)),
  1,
  'the owner sees the request on the unit'
);
select set_config('test.ended', better_supabase.terminate_lease(
  current_setting('test.lease')::uuid, '2026-04-01', 'moved out', deposit_deduction => 50000
)::text, true);
select is(
  current_setting('test.ended')::jsonb ->> 'status',
  'terminated',
  'the owner terminates the lease'
);
select is(
  current_setting('test.ended')::jsonb ->> 'depositHeld',
  '0',
  'termination releases the deposit hold'
);

select * from finish();
rollback;
