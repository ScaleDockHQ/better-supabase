-- Fixed deposits, subscription periods, withdrawing a sent quote, a deposit
-- the customer pays before accepting, and an answer the app takes in its own
-- portal. Ann (…a1) owns Acme (…0001); Carl (…a3) owns Globex (…0002).
begin;
select plan(9);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.quote', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001',
  '{"title": "Hosting", "currency": "EUR", "depositAmount": "5000", "depositRequired": true}',
  '[{"description": "Plan", "quantity": 2, "periods": 12, "unitAmount": "1000"}, {"description": "Setup", "unitAmount": "500"}]'
)::text, true);
select set_config('test.id', current_setting('test.quote')::jsonb ->> 'id', true);

select is(
  (select jsonb_build_array(x ->> 'total', x ->> 'deposit_due') from (select current_setting('test.quote')::jsonb as x) q),
  '["24500", "5000"]'::jsonb,
  'a subscription line counts each period, and a fixed deposit is due'
);
select throws_ok(
  format($$select better_supabase.update_quote(%L, '{"depositBps": 1000}')$$, current_setting('test.id')),
  '22023',
  'a deposit is a share (depositBps) or an amount (depositAmount), not both',
  'a quote takes a share or an amount as its deposit, not both'
);

select set_config('test.token', better_supabase.send_quote(current_setting('test.id')::uuid) ->> 'token', true);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;
select throws_ok(
  format($$select better_supabase.respond_to_quote(%L, 'accepted', 'Cleo', null)$$, current_setting('test.token')),
  '55000',
  'pay the deposit before accepting; the app records the acceptance once it is paid',
  'the customer pays the deposit before their own acceptance'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;
select throws_ok(
  format($$select better_supabase.withdraw_quote(%L)$$, current_setting('test.id')),
  'P0002',
  'no such quote you can edit',
  'another organization cannot withdraw the quote'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(
  better_supabase.decide_quote(current_setting('test.id')::uuid, 'accepted', null, null, null,
    '{"name": "Cleo", "email": "cleo@example.test", "ip": "198.51.100.4", "userAgent": "Portal/1"}') ->> 'decided_ip',
  '198.51.100.4',
  'the app records the paid acceptance with the customer it took it from'
);
select is(
  (select decided_by || ' ' || decided_user_agent from better_supabase.quotes where id = current_setting('test.id')::uuid),
  'Cleo Portal/1',
  'the answer keeps the customer name and browser'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select set_config('test.other', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001', '{"title": "Second", "currency": "EUR"}', '[{"description": "Plan", "unitAmount": "100"}]'
) ->> 'id', true);
select lives_ok(
  format($$select better_supabase.send_quote(%L)$$, current_setting('test.other')),
  'the second quote is sent'
);
select is(
  better_supabase.withdraw_quote(current_setting('test.other')::uuid) ->> 'status',
  'withdrawn',
  'a sent quote is withdrawn'
);
select throws_ok(
  format($$select better_supabase.withdraw_quote(%L)$$, current_setting('test.other')),
  '55000',
  'only a sent quote that wasn''t answered is withdrawn',
  'a withdrawn quote is not withdrawn twice'
);

select * from finish();
rollback;
