-- The external record map (ADR 0141): every rule of `import_upsert_batch`,
-- driven through the fixture target `customer` (public.import_customer) as
-- the admin (…00a1) of Acme (…0001) and the service role.
begin;
select plan(29);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- One active run per tenant and source.
select set_config(
  'bsb.run1',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp', '{"full":true}'::jsonb) ->> 'id'),
  true
);
select ok(current_setting('bsb.run1') <> '', 'the admin starts a run');
select throws_ok(
  $$select better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp')$$,
  '55P03',
  null,
  'a second run of the same source is refused while one is open'
);
select lives_ok(
  $$select better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'other')$$,
  'another source starts at the same time'
);
select is(
  (select count(*)::int from better_supabase.list_import_runs('00000000-0000-4000-8000-000000000001', 'erp')),
  1,
  'the run is listed'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select throws_ok(
  format($$select better_supabase.import_upsert_batch(%L::uuid, 'customer', '[]'::jsonb)$$, current_setting('bsb.run1')),
  '55000',
  null,
  'a pending run takes no items'
);

select better_supabase.mark_import_running(current_setting('bsb.run1')::uuid);

-- Insert.
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run1')::uuid, 'customer',
    '[{"key":"c1","data":{"name":"Alpha","kvk":"1"}},{"key":"c2","data":{"name":"Beta","kvk":"2"}}]'::jsonb
  ) - 'errors' - 'dryRun'),
  '{"inserted":2,"updated":0,"unchanged":0,"conflicted":0}'::jsonb,
  'new keys insert'
);
select is(
  (select count(*)::int from public.customers where name in ('Alpha', 'Beta')),
  2,
  'the target wrote both customers'
);
select is(
  (select count(*)::int from better_supabase.import_records where source = 'erp' and entity = 'customer'),
  2,
  'the record map keeps both keys'
);

-- An invalid item is reported and the run goes on; an unknown entity is refused.
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run1')::uuid, 'customer', '[{"data":{"name":"No key"}}]'::jsonb
  ) -> 'errors' -> 0 ->> 'code'),
  'IMPORT_ITEM_INVALID',
  'an item without a key is an error'
);
select throws_ok(
  format($$select better_supabase.import_upsert_batch(%L::uuid, 'nothing', '[{"key":"x","data":{}}]'::jsonb)$$, current_setting('bsb.run1')),
  '22023',
  'no import target for this entity',
  'an entity without a target is refused'
);

select is(
  (select jsonb_array_length(better_supabase.get_import_run(current_setting('bsb.run1')::uuid) -> 'errors')),
  1,
  'the run keeps the item error'
);

select is(
  (select better_supabase.get_import_run(current_setting('bsb.run1')::uuid) -> 'counts' -> 'customer' ->> 'inserted'),
  '2',
  'the run counts per entity'
);

select is(
  (select jsonb_array_length(better_supabase.import_resolve(current_setting('bsb.run1')::uuid, 'customer', '["c1","c2","c3"]'::jsonb))),
  2,
  'resolve leaves a never-imported key out'
);

select better_supabase.finish_import_run(current_setting('bsb.run1')::uuid);

select is(
  (select status from better_supabase.import_runs where id = current_setting('bsb.run1')::uuid),
  'completed',
  'finish completes the run'
);

-- Unchanged: no write, no audit row.
reset role;
select set_config('bsb.audit', (select count(*)::text from better_supabase.audit_events), true);
select set_config('bsb.updated', (select updated_at::text from public.customers where name = 'Alpha'), true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select set_config(
  'bsb.run2',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp', '{"full":true}'::jsonb) ->> 'id'),
  true
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run2')::uuid);

select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run2')::uuid, 'customer', '[{"key":"c1","data":{"name":"Alpha","kvk":"1"}}]'::jsonb
  ) - 'errors' - 'dryRun'),
  '{"inserted":0,"updated":0,"unchanged":1,"conflicted":0}'::jsonb,
  'the same data is unchanged'
);

reset role;
select is(
  (select updated_at::text from public.customers where name = 'Alpha'),
  current_setting('bsb.updated'),
  'an unchanged item does not touch the target'
);
select is(
  (select count(*)::text from better_supabase.audit_events),
  current_setting('bsb.audit'),
  'an unchanged item writes no audit row'
);

-- Missing marking on a full run: c2 is not sent, so it is marked and kept.
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(
  (select better_supabase.finish_import_run(current_setting('bsb.run2')::uuid) -> 'customer' ->> 'missing'),
  '1',
  'a full run counts the keys it did not send'
);
reset role;
select isnt(
  (select missing_since from better_supabase.import_records where external_key = 'c2' and source = 'erp'),
  null,
  'the missing record is marked'
);
select is(
  (select count(*)::int from public.customers where name = 'Beta'),
  1,
  'a full run never deletes the target'
);

-- Changed: the target updates.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select set_config(
  'bsb.run3',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp') ->> 'id'),
  true
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run3')::uuid);
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run3')::uuid, 'customer', '[{"key":"c1","data":{"name":"Alpha 2","kvk":"1"}}]'::jsonb
  ) - 'errors' - 'dryRun'),
  '{"inserted":0,"updated":1,"unchanged":0,"conflicted":0}'::jsonb,
  'changed data updates the target'
);
select is(
  (select count(*)::int from public.customers where name = 'Alpha 2'),
  1,
  'the customer has the new name'
);
select better_supabase.import_upsert_batch(
  current_setting('bsb.run3')::uuid, 'customer', '[{"key":"c2","data":{"name":"Beta","kvk":"2"}}]'::jsonb
);
select is(
  (select missing_since from better_supabase.import_records where external_key = 'c2' and source = 'erp'),
  null,
  'a run that sends a missing key clears its mark'
);

-- Conflict: a user changed the target after the last import.
reset role;
update better_supabase.import_records
  set subject_updated_at_at_import = now() - interval '1 hour'
  where external_key = 'c1' and source = 'erp';
set local role service_role;
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run3')::uuid, 'customer', '[{"key":"c1","data":{"name":"Alpha 3","kvk":"1"}}]'::jsonb
  ) - 'errors' - 'dryRun'),
  '{"inserted":0,"updated":0,"unchanged":0,"conflicted":1}'::jsonb,
  'a target a user edited is a conflict'
);
select is(
  (select count(*)::int from public.customers where name = 'Alpha 2'),
  1,
  'a conflict leaves the target as the user has it'
);
select better_supabase.finish_import_run(current_setting('bsb.run3')::uuid);

-- Scope aliases: scope B reuses what scope A imported.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select set_config(
  'bsb.run4',
  (better_supabase.start_import_run(
    '00000000-0000-4000-8000-000000000001', 'erp-scoped',
    '{"scopeAliases":[{"scope":"B","of":"A","entities":["customer"]}]}'::jsonb
  ) ->> 'id'),
  true
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run4')::uuid);
select better_supabase.import_upsert_batch(
  current_setting('bsb.run4')::uuid, 'customer',
  '[{"key":"s1","scope":"A","data":{"name":"Shared","kvk":"9"}}]'::jsonb
);
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run4')::uuid, 'customer',
    '[{"key":"s1","scope":"B","data":{"name":"Shared","kvk":"9"}}]'::jsonb
  ) - 'errors' - 'dryRun'),
  '{"inserted":0,"updated":0,"unchanged":1,"conflicted":0}'::jsonb,
  'an aliased scope reuses the other scope''s record'
);
select is(
  (select count(*)::int from public.customers where name = 'Shared'),
  1,
  'the alias created no second customer'
);
select better_supabase.finish_import_run(current_setting('bsb.run4')::uuid);

-- Dry run: counts only, nothing written.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select set_config(
  'bsb.run5',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp-dry', '{"dryRun":true}'::jsonb) ->> 'id'),
  true
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run5')::uuid);
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run5')::uuid, 'customer', '[{"key":"d1","data":{"name":"Dry","kvk":"7"}}]'::jsonb
  ) - 'errors'),
  '{"inserted":1,"updated":0,"unchanged":0,"conflicted":0,"dryRun":true}'::jsonb,
  'a dry run reports what would insert'
);
select is(
  (select count(*)::int from public.customers where name = 'Dry')
    + (select count(*)::int from better_supabase.import_records where source = 'erp-dry'),
  0,
  'a dry run writes neither the target nor the map'
);

select * from finish();
rollback;
