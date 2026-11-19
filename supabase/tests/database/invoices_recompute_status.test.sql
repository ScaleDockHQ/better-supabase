-- recompute_invoice_status: derives an issued invoice's status, paid total and
-- credited total from its ledger payments and issued credit notes, so an app
-- never writes the status itself. A draft keeps its status, and a caller
-- without invoices.manage is refused. Run with `supabase test db`.
begin;
select plan(6);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('test.paid', (better_supabase.issue_invoice((better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Recompute paid", "currency": "EUR"}'::jsonb,
  '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid, current_date) ->> 'id'), true);
select set_config('test.total', (select total::text from better_supabase.invoices where id = current_setting('test.paid')::uuid), true);
select better_supabase.record_invoice_payment(current_setting('test.paid')::uuid, current_setting('test.total')::bigint, 'EUR', now(), 'bank', 'recompute-status-1');
update better_supabase.invoices set status = 'issued', paid_total = 0, paid_at = null where id = current_setting('test.paid')::uuid;

select is(
  better_supabase.recompute_invoice_status(current_setting('test.paid')::uuid) ->> 'status',
  'paid',
  'a paid invoice whose status drifted is paid again'
);
select is(
  (select paid_total::text from better_supabase.invoices where id = current_setting('test.paid')::uuid),
  current_setting('test.total'),
  'its paid total comes from the ledger'
);

select set_config('test.credited', (better_supabase.issue_invoice((better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Recompute credited", "currency": "EUR"}'::jsonb,
  '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id')::uuid, current_date) ->> 'id'), true);
select better_supabase.issue_invoice((better_supabase.credit_invoice(current_setting('test.credited')::uuid, null, 'credit') ->> 'id')::uuid, current_date);
update better_supabase.invoices set status = 'issued', credited_total = 0 where id = current_setting('test.credited')::uuid;
select better_supabase.recompute_invoice_status(current_setting('test.credited')::uuid);

select is(
  (select credited_total = total from better_supabase.invoices where id = current_setting('test.credited')::uuid),
  true,
  'the credited total comes from the issued credit notes'
);
select isnt(
  (select status::text from better_supabase.invoices where id = current_setting('test.credited')::uuid),
  'issued',
  'a fully credited invoice is settled again'
);

select set_config('test.draft', (better_supabase.create_invoice(
  '00000000-0000-4000-8000-000000000001', '{"title": "Recompute draft", "currency": "EUR"}'::jsonb,
  '[{"description": "Work", "quantity": 1, "unitAmount": "10000"}]'::jsonb) ->> 'id'), true);
select is(
  better_supabase.recompute_invoice_status(current_setting('test.draft')::uuid) ->> 'status',
  'draft',
  'a draft keeps its status'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e9","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  format('select better_supabase.recompute_invoice_status(%L::uuid)', current_setting('test.paid')),
  'P0002',
  null,
  'a caller who can''t read the invoice is refused'
);

select * from finish();
rollback;
