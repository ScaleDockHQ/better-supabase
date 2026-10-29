-- An answer with an actor past the quote's date returns the expired quote,
-- and the final invoice takes a deposit off per tax rate of its lines.
-- Ann (…a1) owns Acme (…0001); Carl (…a3) owns Globex (…0002).
begin;
select plan(7);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select set_config('test.late', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001', '{"title": "Shed", "currency": "EUR"}', '[{"description": "Shed", "unitAmount": "100"}]'
) ->> 'id', true);
select better_supabase.send_quote(current_setting('test.late')::uuid);
select set_config('test.quote', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001',
  '{"title": "Garden", "currency": "EUR"}',
  '[{"description": "Work", "quantity": 1, "unitAmount": "10000", "taxRateBps": 2100},
    {"description": "Plants", "quantity": 1, "unitAmount": "5000", "taxRateBps": 900}]'
) ->> 'id', true);
select better_supabase.send_quote(current_setting('test.quote')::uuid);
select better_supabase.decide_quote(current_setting('test.quote')::uuid, 'accepted', null, 'Ann');
select set_config('test.deposit', better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Deposit', 'currency', 'EUR', 'depositBps', 2000,
    'origin', jsonb_build_object('type', 'quote', 'id', current_setting('test.quote'))),
  '[{"description": "Work", "unitAmount": "2000", "taxRateBps": 2100},
    {"description": "Plants", "unitAmount": "1000", "taxRateBps": 900}]'
) ->> 'id', true);
select better_supabase.issue_invoice(current_setting('test.deposit')::uuid, current_date);

reset role;
update better_supabase.quotes set valid_until = current_date - 1 where id = current_setting('test.late')::uuid;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select set_config('test.answer', better_supabase.decide_quote(
  current_setting('test.late')::uuid, 'accepted', null, null, null, '{"email": "els@example.com"}'
)::text, true);
reset role;
select is(
  current_setting('test.answer')::jsonb ->> 'status',
  'expired',
  'an answer past the date returns the quote as expired'
);
select is(
  current_setting('test.answer')::jsonb ->> 'id',
  current_setting('test.late'),
  'the expired answer is the quote row'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;
select throws_ok(
  format($$select better_supabase.invoice_from_quote(%L, null)$$, current_setting('test.quote')),
  'P0002',
  'no such quote you can invoice',
  'another organization cannot invoice the quote'
);
reset role;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select set_config('test.final', better_supabase.invoice_from_quote(current_setting('test.quote')::uuid, null) ->> 'id', true);
reset role;
select is(
  (select count(*)::integer from better_supabase.invoice_lines where parent_id = current_setting('test.final')::uuid and unit_amount < 0),
  2,
  'the deposit comes off in one line per tax rate'
);
select is(
  (select unit_amount from better_supabase.invoice_lines where parent_id = current_setting('test.final')::uuid and unit_amount < 0 and tax_rate_bps = 2100),
  -2000::bigint,
  'the 21% part of the deposit comes off at 21%'
);
select is(
  (select unit_amount from better_supabase.invoice_lines where parent_id = current_setting('test.final')::uuid and unit_amount < 0 and tax_rate_bps = 900),
  -1000::bigint,
  'the 9% part of the deposit comes off at 9%'
);
select is(
  (select min(description) from better_supabase.invoice_lines where parent_id = current_setting('test.final')::uuid and unit_amount < 0),
  (select 'Deposit ' || identifier from better_supabase.invoices where id = current_setting('test.deposit')::uuid),
  'the deduction keeps the default description'
);

select * from finish();
rollback;
