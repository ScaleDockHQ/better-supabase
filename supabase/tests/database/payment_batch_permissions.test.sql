-- Payment batches move money, so creating, posting and cancelling one checks
-- the banking manage key (or the key an app sets per operation), not
-- banking.reconcile. The member (…00a2) of Acme (…0001) holds
-- banking.reconcile but not banking.manage. Each operation is audited.
begin;
select plan(4);

insert into better_supabase.bank_accounts (id, tenant_id, name, iban, currency)
values ('00000000-0000-4000-8000-0000000bba01', '00000000-0000-4000-8000-000000000001', 'Batch test', 'DE89370400440532013000', 'EUR');

insert into better_supabase.payment_batches (id, tenant_id, bank_account_id, reference, message_id, currency, due_by, execution_on, total, item_count)
values
  ('00000000-0000-4000-8000-0000000bb001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000bba01', 'Batch A', 'BSBA', 'EUR', current_date, current_date, 1, 1),
  ('00000000-0000-4000-8000-0000000bb002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000bba01', 'Batch B', 'BSBB', 'EUR', current_date, current_date, 1, 1);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);

select throws_ok(
  $$select better_supabase.create_payment_batch('00000000-0000-4000-8000-000000000001', '{}')$$,
  '42501', null, 'banking.reconcile does not create a payment batch'
);
select throws_ok(
  $$select better_supabase.post_payment_batch('00000000-0000-4000-8000-0000000bb001')$$,
  'P0002', null, 'banking.reconcile does not post a payment batch'
);
select throws_ok(
  $$select better_supabase.cancel_payment_batch('00000000-0000-4000-8000-0000000bb002')$$,
  'P0002', null, 'banking.reconcile does not cancel a payment batch'
);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
select better_supabase.cancel_payment_batch('00000000-0000-4000-8000-0000000bb002');
reset role;
select is(
  (select count(*)::int from better_supabase.audit_events
   where event_type = 'payment_batch.cancelled' and record_id = '00000000-0000-4000-8000-0000000bb002'),
  1, 'cancelling a payment batch writes an audit entry'
);

select * from finish();
rollback;
