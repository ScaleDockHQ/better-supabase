-- Sending a declined quote again in one call, withdrawing an expired quote,
-- a fixed deposit invoice, the final invoice that deducts it, and the
-- refusals around them. Ann (…a1) owns Acme (…0001); Carl (…a3) owns
-- Globex (…0002).
begin;
select plan(11);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.id', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001',
  '{"title": "Fence", "currency": "EUR", "discountBps": 1000}',
  '[{"description": "Panels", "quantity": 2, "unitAmount": "5000", "taxRateBps": 2100}]'
) ->> 'id', true);
select lives_ok(
  format($$select better_supabase.send_quote(%L)$$, current_setting('test.id')),
  'the quote is sent'
);
select lives_ok(
  format($$select better_supabase.decide_quote(%L, 'rejected', 'too much', 'Cleo')$$, current_setting('test.id')),
  'the customer rejects it'
);
select is(
  (select jsonb_build_array(x ->> 'status', x ->> 'revision', x ->> 'decided_by') from (select better_supabase.send_quote(current_setting('test.id')::uuid) as x) s),
  '["sent", "2", null]'::jsonb,
  'a rejected quote is sent again in one call as the next revision'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;
select throws_ok(
  format($$select better_supabase.send_quote(%L)$$, current_setting('test.id')),
  'P0002',
  'no such quote you can edit',
  'another organization cannot send the quote again'
);
select throws_ok(
  format($$select better_supabase.portal_quote(%L, '{"name": "Someone"}')$$, current_setting('test.id')),
  '42501',
  'only the service role names who opened a quote',
  'a signed-in caller cannot name who opened a quote'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select lives_ok(
  format($$select better_supabase.decide_quote(%L, 'accepted', null, 'Cleo')$$, current_setting('test.id')),
  'the customer accepts the second revision'
);
select throws_ok(
  format($$select better_supabase.invoice_from_quote(%L, null, 999999)$$, current_setting('test.id')),
  '22023',
  'a deposit amount is positive and at most the quote''s total',
  'a deposit is at most the quote''s total'
);
select set_config('test.deposit', better_supabase.invoice_from_quote(current_setting('test.id')::uuid, null, 2178)::text, true);
select is(
  (select jsonb_build_array(x ->> 'deposit_amount', x ->> 'total') from (select current_setting('test.deposit')::jsonb as x) d),
  '["2178", "2178"]'::jsonb,
  'a fixed deposit invoice is made for that amount, tax included'
);
select lives_ok(
  format($$select better_supabase.issue_invoice(%L, current_date)$$, current_setting('test.deposit')::jsonb ->> 'id'),
  'the deposit invoice is issued'
);
select is(
  (select jsonb_build_array(x ->> 'discount_bps', x ->> 'total') from (select better_supabase.invoice_from_quote(current_setting('test.id')::uuid, null) as x) f),
  '["0", "8712"]'::jsonb,
  'the final invoice deducts the deposit and keeps the discount as lines then'
);

select set_config('test.expired', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001', '{"title": "Gate", "currency": "EUR"}', '[{"description": "Gate", "unitAmount": "100"}]'
) ->> 'id', true);
select better_supabase.send_quote(current_setting('test.expired')::uuid);
reset role;
update better_supabase.quotes set status = 'expired' where id = current_setting('test.expired')::uuid;
set local role authenticated;
select is(
  better_supabase.withdraw_quote(current_setting('test.expired')::uuid) ->> 'status',
  'withdrawn',
  'an expired quote is withdrawn'
);

select * from finish();
rollback;
