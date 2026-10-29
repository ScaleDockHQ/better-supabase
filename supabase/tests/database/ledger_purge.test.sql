begin;
select plan(7);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select set_config('test.acme_from', better_supabase.open_ledger_account(
  '00000000-0000-4000-8000-000000000001', 'credit', 'purge:from', 'From', 'EUR', allow_negative => true
) ->> 'id', true);
select set_config('test.acme_to', better_supabase.open_ledger_account(
  '00000000-0000-4000-8000-000000000001', 'credit', 'purge:to', 'To', 'EUR'
) ->> 'id', true);
select set_config('test.globex_from', better_supabase.open_ledger_account(
  '00000000-0000-4000-8000-000000000002', 'credit', 'purge:from', 'From', 'EUR', allow_negative => true
) ->> 'id', true);
select set_config('test.globex_to', better_supabase.open_ledger_account(
  '00000000-0000-4000-8000-000000000002', 'credit', 'purge:to', 'To', 'EUR'
) ->> 'id', true);

select set_config('test.acme_tx', better_supabase.post_ledger_transaction(
  '00000000-0000-4000-8000-000000000001', 'credit.grant',
  jsonb_build_array(
    jsonb_build_object('account', current_setting('test.acme_from'), 'amount', '-100'),
    jsonb_build_object('account', current_setting('test.acme_to'), 'amount', '100')
  )
) ->> 'id', true);
select set_config('test.globex_tx', better_supabase.post_ledger_transaction(
  '00000000-0000-4000-8000-000000000002', 'credit.grant',
  jsonb_build_array(
    jsonb_build_object('account', current_setting('test.globex_from'), 'amount', '-100'),
    jsonb_build_object('account', current_setting('test.globex_to'), 'amount', '100')
  )
) ->> 'id', true);

select set_config('better_supabase.purge_tenant', '00000000-0000-4000-8000-000000000001', true);

select throws_ok(
  format($$delete from better_supabase.ledger_entries where transaction_id = '%s'$$, current_setting('test.acme_tx')),
  '55000',
  'ledger entries and transactions can''t be changed or deleted; post a reversal',
  'the purge setting alone does not open the ledger without a due deletion'
);

insert into better_supabase.organization_deletions (organization_id, purge_after)
values ('00000000-0000-4000-8000-000000000001', now() - interval '1 minute');

select throws_ok(
  format($$update better_supabase.ledger_transactions set kind = 'changed' where id = '%s'$$, current_setting('test.acme_tx')),
  '55000',
  'ledger entries and transactions can''t be changed or deleted; post a reversal',
  'an update stays refused during a purge'
);
select throws_ok(
  format($$delete from better_supabase.ledger_entries where transaction_id = '%s'$$, current_setting('test.globex_tx')),
  '55000',
  'ledger entries and transactions can''t be changed or deleted; post a reversal',
  'another tenant''s entries stay append-only during a purge'
);

select set_config('request.jwt.claims', '{"role":"authenticated","sub":"00000000-0000-4000-8000-0000000000a1"}', true);
select throws_ok(
  format($$delete from better_supabase.ledger_entries where transaction_id = '%s'$$, current_setting('test.acme_tx')),
  '55000',
  'ledger entries and transactions can''t be changed or deleted; post a reversal',
  'a caller that is not the service role cannot use the purge setting'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select lives_ok(
  format($$delete from better_supabase.ledger_entries where transaction_id = '%s'$$, current_setting('test.acme_tx')),
  'the purge deletes the due tenant''s entries'
);
select lives_ok(
  format($$delete from better_supabase.ledger_transactions where id = '%s'$$, current_setting('test.acme_tx')),
  'the purge deletes the due tenant''s transactions'
);
select is(
  (select count(*)::int from better_supabase.ledger_entries where transaction_id = current_setting('test.globex_tx')::uuid),
  2,
  'the other tenant keeps its entries'
);

select * from finish();
rollback;
