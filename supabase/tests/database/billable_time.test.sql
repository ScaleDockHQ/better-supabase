-- The billable-time module on the fixture's access contract: the admin
-- (…00a1) of Acme (…0001) sets a rate card, previews the unbilled time on the
-- customer Road Runner (…a001), bills it on a draft invoice, and voids the
-- invoice to release the entries. The member (…00a2) can't change rates.
begin;
select plan(24);

insert into better_supabase.time_entries (id, tenant_id, user_id, subject_type, subject_id, started_at, ended_at, billable, rate, rate_currency, note) values
  -- Two hours at the customer's card rate.
  ('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'customer', '00000000-0000-4000-8000-00000000a001',
    '2026-10-01 09:00+00', '2026-10-01 11:00+00', true, null, null, 'Workshop'),
  -- An hour and a half at the entry's own rate.
  ('00000000-0000-4000-8000-00000000d002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'customer', '00000000-0000-4000-8000-00000000a001',
    '2026-10-01 10:00+00', '2026-10-01 11:30+00', true, 15000, 'EUR', null),
  -- Not billable.
  ('00000000-0000-4000-8000-00000000d003', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'customer', '00000000-0000-4000-8000-00000000a001',
    '2026-10-01 12:00+00', '2026-10-01 13:00+00', false, null, null, null),
  -- Still running.
  ('00000000-0000-4000-8000-00000000d004', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'customer', '00000000-0000-4000-8000-00000000a001',
    '2026-10-02 09:00+00', null, true, null, null, null),
  -- Before any rate is effective.
  ('00000000-0000-4000-8000-00000000d005', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', null, null,
    '2025-12-01 09:00+00', '2025-12-01 10:00+00', true, null, null, null);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.set_time_rate('00000000-0000-4000-8000-000000000001', 10000, 'EUR', effective_from => '2026-01-01') ->> 'rate',
  '10000',
  'the admin sets the organization rate'
);
select lives_ok(
  $$select better_supabase.set_time_rate('00000000-0000-4000-8000-000000000001', 12000, 'EUR',
    subject_type => 'customer', subject_id => '00000000-0000-4000-8000-00000000a001', effective_from => '2026-09-01')$$,
  'the admin sets a customer rate'
);
select lives_ok(
  $$select better_supabase.set_time_rate('00000000-0000-4000-8000-000000000001', 14000, 'EUR',
    user_id => '00000000-0000-4000-8000-0000000000a1', subject_type => 'customer', subject_id => '00000000-0000-4000-8000-00000000a001',
    effective_from => '2026-10-02')$$,
  'the admin sets a member rate on the customer from a later day'
);
select is(
  (better_supabase.set_time_rate('00000000-0000-4000-8000-000000000001', 11000, 'EUR', effective_from => '2026-01-01') ->> 'rate'),
  '11000',
  'the same key and day replaces the rate'
);
select is(
  jsonb_array_length(better_supabase.list_time_rates('00000000-0000-4000-8000-000000000001')),
  3,
  'the rate card lists three rates'
);
select throws_ok(
  $$select better_supabase.set_time_rate('00000000-0000-4000-8000-000000000001', 100, 'EUR', subject_type => 'customer', subject_id => '00000000-0000-4000-8000-00000000a003')$$,
  '22023',
  'the record is unknown or not in this organization',
  'a rate cannot name a record in another organization'
);
select throws_ok(
  $$select better_supabase.set_time_rate('00000000-0000-4000-8000-000000000001', 100, 'eur')$$,
  '22023',
  'currency must be a three-letter currency code',
  'a rate needs an upper-case currency code'
);

select is(
  better_supabase.time_rate('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'customer', '00000000-0000-4000-8000-00000000a001', '2026-10-01') ->> 'rate',
  '12000',
  'the customer rate applies before the member rate starts'
);
select is(
  better_supabase.time_rate('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'customer', '00000000-0000-4000-8000-00000000a001', '2026-10-05') ->> 'rate',
  '14000',
  'the member rate on the customer wins once it starts'
);
select is(
  better_supabase.time_rate('00000000-0000-4000-8000-000000000001', on_day => '2025-06-01'),
  null,
  'no rate applies before the card starts'
);

select set_config('test.preview', better_supabase.unbilled_time(
  '00000000-0000-4000-8000-000000000001',
  '{"subject":{"type":"customer","id":"00000000-0000-4000-8000-00000000a001"}}'
)::text, true);
select is(
  (select jsonb_agg(l ->> 'amount' order by l ->> 'amount') from jsonb_array_elements(current_setting('test.preview')::jsonb -> 'lines') l),
  '["22500", "24000"]'::jsonb,
  'the preview bills the entry rate and the card rate as two lines'
);
select is(
  current_setting('test.preview')::jsonb -> 'totals',
  '[{"amount": "46500", "currency": "EUR"}]'::jsonb,
  'the preview totals the lines per currency'
);
select is(
  better_supabase.unbilled_time('00000000-0000-4000-8000-000000000001') -> 'unrated',
  '["00000000-0000-4000-8000-00000000d005"]'::jsonb,
  'an entry no rate covers is listed as unrated'
);
select throws_ok(
  $$select better_supabase.invoice_from_time('00000000-0000-4000-8000-000000000001', '{"title":"All time"}')$$,
  '22023',
  'some billable entries have no rate; set one on the entry or the rate card',
  'invoicing fails while a selected entry has no rate'
);

select set_config('test.invoice', better_supabase.invoice_from_time(
  '00000000-0000-4000-8000-000000000001',
  '{"title":"October","origin":{"type":"customer","id":"x"}}',
  '{"subject":{"type":"customer","id":"00000000-0000-4000-8000-00000000a001"}}'
)::text, true);
select is(
  current_setting('test.invoice')::jsonb ->> 'total',
  '46500',
  'invoicing bills the previewed total'
);
select is(
  (select x."subtotal"::text from better_supabase.invoices x where x."id" = (current_setting('test.invoice')::jsonb ->> 'invoiceId')::uuid),
  '46500',
  'the draft invoice carries the lines'
);
select is(
  jsonb_array_length(better_supabase.unbilled_time('00000000-0000-4000-8000-000000000001',
    '{"subject":{"type":"customer","id":"00000000-0000-4000-8000-00000000a001"}}') -> 'lines'),
  0,
  'billed time is no longer unbilled'
);
select is(
  jsonb_array_length(better_supabase.list_invoiced_time((current_setting('test.invoice')::jsonb ->> 'invoiceId')::uuid)),
  2,
  'the invoice lists the entries it billed'
);

reset role;
select throws_ok(
  $$update better_supabase.time_entries set ended_at = '2026-10-01 12:00+00' where id = '00000000-0000-4000-8000-00000000d001'$$,
  '55000',
  'this entry is on an invoice; void the invoice to change it',
  'a billed entry''s time is locked'
);
select throws_ok(
  $$delete from better_supabase.time_entries where id = '00000000-0000-4000-8000-00000000d001'$$,
  '23001',
  'this entry is on an invoice; void the invoice to delete it',
  'a billed entry cannot be deleted'
);
insert into better_supabase.time_rates (tenant_id, subject_type, subject_id, rate, currency, effective_from) values
  ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a002', 5000, 'EUR', '2026-09-01'),
  ('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a002', 6000, 'EUR', '2026-03-01');
select better_supabase.merge_subject_refs('public.customers', '00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-00000000a002');
select is(
  (select array_agg(x.rate order by x.effective_from) from better_supabase.time_rates x
   where x.subject_id = '00000000-0000-4000-8000-00000000a001' and x.user_id is null),
  array[6000, 12000]::bigint[],
  'a merge moves rates to the kept record, keeping its own rate on the same day'
);
set local role authenticated;

select lives_ok(
  format('select better_supabase.void_invoice(%L, %L)', current_setting('test.invoice')::jsonb ->> 'invoiceId', 'wrong rate'),
  'the admin voids the invoice'
);
select is(
  jsonb_array_length(better_supabase.unbilled_time('00000000-0000-4000-8000-000000000001',
    '{"subject":{"type":"customer","id":"00000000-0000-4000-8000-00000000a001"}}') -> 'lines'),
  2,
  'voiding the invoice releases its entries'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select better_supabase.set_time_rate('00000000-0000-4000-8000-000000000001', 1, 'EUR')$$,
  '42501',
  'not allowed to change the rate card',
  'a member cannot change the rate card'
);

select * from finish();
rollback;
