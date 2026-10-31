-- Collections on the fixture (ADR 0149). The Acme owner (…a1) records one
-- payment over two invoices, keeps the rest as party credit and applies it to
-- a third, sets dunning levels and pauses an invoice; the Acme member (…a2)
-- can't manage the levels or pause, only the service role runs dunning, and
-- the Globex owner (…a3) reads none of it. Run with `supabase test db`.
begin;
select plan(19);

select has_table('better_supabase', 'invoice_dunning_levels', 'dunning levels are a table');
select col_default_is('better_supabase', 'invoices', 'dunning_level', 0, 'an invoice starts at dunning level 0');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.party', better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Collections customer"}') ->> 'id', true);

create temporary table t_invoices (n int primary key, id uuid) on commit drop;
grant all on t_invoices to authenticated, service_role;

insert into t_invoices
select n, (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Collections ' || n, 'currency', 'EUR', 'termsDays', 10,
    'company', jsonb_build_object('id', current_setting('t.party'))),
  jsonb_build_array(jsonb_build_object('description', 'Service', 'quantity', 1, 'unitAmount', 1000))) ->> 'id')::uuid
from generate_series(1, 3) n;

select better_supabase.issue_invoice(id, current_date - 40) from t_invoices order by n;

select set_config('t.paid', better_supabase.record_party_payment('00000000-0000-4000-8000-000000000001', current_setting('t.party'), 1500, 'EUR',
  jsonb_build_array(
    jsonb_build_object('invoiceId', (select id from t_invoices where n = 1), 'amount', 1000),
    jsonb_build_object('invoiceId', (select id from t_invoices where n = 2), 'amount', 300)),
  current_date, 'bank-0001')::text, true);

select is(
  (select jsonb_build_array(r ->> 'allocated', r ->> 'credited', r ->> 'credit') from (select current_setting('t.paid')::jsonb r) x),
  '["1300", "200", "200"]'::jsonb,
  'a party payment allocates 1300 and keeps 200 as credit'
);
select is(
  (select array_agg(status order by n) from better_supabase.invoices x join t_invoices t using (id)),
  array['paid', 'partially_paid', 'issued'],
  'the allocations pay the first invoice and part of the second'
);

select lives_ok(
  format($$select better_supabase.record_party_payment('00000000-0000-4000-8000-000000000001', %L, 1500, 'EUR', %L, current_date, 'bank-0001')$$,
    current_setting('t.party'), jsonb_build_array(
      jsonb_build_object('invoiceId', (select id from t_invoices where n = 1), 'amount', 1000),
      jsonb_build_object('invoiceId', (select id from t_invoices where n = 2), 'amount', 300))),
  'recording the same payment again is a no-op'
);
select is(
  (select x ->> 'amount' from jsonb_array_elements(better_supabase.list_party_credits('00000000-0000-4000-8000-000000000001', current_setting('t.party'))) x
   where x ->> 'currency' = 'EUR'),
  '200',
  'the replay adds no credit'
);

select throws_ok(
  format($$select better_supabase.record_party_payment('00000000-0000-4000-8000-000000000001', %L, 100, 'EUR', %L, current_date, 'bank-0002')$$,
    current_setting('t.party'), jsonb_build_array(jsonb_build_object('invoiceId', (select id from t_invoices where n = 3), 'amount', 200))),
  '23514',
  'the allocations add up to more than the payment',
  'allocations are no more than the payment'
);

select is(
  better_supabase.apply_party_credit(current_setting('t.party'), (select id from t_invoices where n = 3), 150) ->> 'status',
  'partially_paid',
  'credit pays part of the third invoice'
);
select throws_ok(
  format($$select better_supabase.apply_party_credit(%L, %L, 100)$$, current_setting('t.party'), (select id from t_invoices where n = 3)),
  '23514',
  'the party doesn''t have this much credit in the invoice''s currency',
  'credit is no more than the party has'
);

select throws_ok(
  $$select better_supabase.set_invoice_dunning_levels('00000000-0000-4000-8000-000000000001',
    '[{"daysAfterDue": 7, "templateKey": "reminder", "final": true}, {"daysAfterDue": 21, "templateKey": "second"}]')$$,
  '22023',
  'levels is an array of at most 20 { daysAfterDue, templateKey, fee, final }, and only the last is final',
  'only the last level is final'
);
select lives_ok(
  $$select better_supabase.set_invoice_dunning_levels('00000000-0000-4000-8000-000000000001',
    '[{"daysAfterDue": 7, "templateKey": "reminder"}, {"daysAfterDue": 21, "templateKey": "second", "fee": 500}, {"daysAfterDue": 60, "templateKey": "final", "final": true}]')$$,
  'the owner sets three dunning levels'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select better_supabase.set_invoice_dunning_levels('00000000-0000-4000-8000-000000000001', '[]')$$,
  '42501',
  'not allowed to manage this organization''s invoices',
  'a member does not manage the dunning levels'
);
select throws_ok(
  format($$select better_supabase.pause_invoice_dunning(%L, current_date + 7, 'Disputed')$$, (select id from t_invoices where n = 2)),
  'P0002',
  'no such invoice you can edit',
  'pausing dunning needs invoices.collect'
);
select throws_ok(
  $$select better_supabase.run_invoice_dunning('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'a user does not run dunning'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  better_supabase.run_invoice_dunning('00000000-0000-4000-8000-000000000001'),
  2,
  'dunning raises the two open overdue invoices'
);
select is(
  (select array_agg(jsonb_build_array(x.dunning_level, (select coalesce(sum(c.amount), 0) from better_supabase.invoice_charges c where c.invoice_id = x.id)) order by t.n)
   from better_supabase.invoices x join t_invoices t using (id) where t.n > 1),
  array['[2, 500]'::jsonb, '[2, 500]'::jsonb],
  'an invoice 30 days overdue skips to level 2 and gets its fee once'
);
select is(
  better_supabase.run_invoice_dunning('00000000-0000-4000-8000-000000000001'),
  0,
  'a second run raises nothing'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.pause_invoice_dunning((select id from t_invoices where n = 2), current_date + 7, 'Disputed') ->> 'dunning_paused_until',
  (current_date + 7)::text,
  'the owner pauses an invoice''s dunning'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*) from better_supabase.invoice_dunning_levels where tenant_id = '00000000-0000-4000-8000-000000000001'),
  0::bigint,
  'another organization does not read the dunning levels'
);

select * from finish();
rollback;
