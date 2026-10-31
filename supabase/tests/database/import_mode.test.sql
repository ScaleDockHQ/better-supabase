-- Import mode (ADR 0141): only the service role can begin a session, an import
-- run fires no outbox event unless `imports.events` lists it, audits one
-- entry per entity (`imports.audit: summary`), tags entries as integration and
-- writes one `imported` history row for a row inserted in any status. The
-- fixture sets events to customer.imported: tag and customer.synced: emit.
begin;
select plan(27);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'mode', '{}'::jsonb) ->> 'id'),
  true
);

-- A user session can never turn import mode on.
select set_config('better_supabase.import_run', current_setting('bsb.run'), true);
select is(better_supabase.import_run(), null, 'a user who sets the setting is not importing');
select set_config('better_supabase.import_run', '', true);
select throws_ok(
  format($$select better_supabase.begin_import_session(%L::uuid)$$, current_setting('bsb.run')),
  '42501',
  null,
  'a user cannot begin an import session'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select throws_ok(
  format($$select better_supabase.begin_import_session(%L::uuid)$$, current_setting('bsb.run')),
  '55000',
  null,
  'a pending run takes no session'
);
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

select is(better_supabase.import_run(), null, 'the service role is not importing outside a session');

-- Outside a session an event is emitted and an audit entry written as usual.
select isnt(better_supabase.emit_event('plain.event', '{}'::jsonb), null, 'outside a session an event is emitted');

select is(
  better_supabase.begin_import_session(current_setting('bsb.run')::uuid),
  current_setting('bsb.run')::uuid,
  'the service role begins a session'
);
select is(better_supabase.import_run(), current_setting('bsb.run')::uuid, 'import_run names the run');
select is(
  current_setting('better_supabase.correlation_id'),
  'import:' || current_setting('bsb.run'),
  'the session sets the correlation id'
);

-- Outbox policy: skip by default, tag or emit when listed.
select is(better_supabase.emit_event('unlisted.event', '{}'::jsonb), null, 'an unlisted event is skipped');
select is((select count(*)::int from better_supabase.outbox_events where type = 'unlisted.event'), 0, 'a skipped event leaves no row');
select isnt(better_supabase.emit_event('customer.imported', '{"a":1}'::jsonb), null, 'a tagged event is emitted');
select is(
  (select payload ->> 'importRunId' from better_supabase.outbox_events where type = 'customer.imported'),
  current_setting('bsb.run'),
  'a tagged event carries the run id'
);
select isnt(better_supabase.emit_event('customer.synced', '{"a":1}'::jsonb), null, 'a listed event is emitted');
select is(
  (select payload ? 'importRunId' from better_supabase.outbox_events where type = 'customer.synced'),
  false,
  'an emitted event is left as it is'
);

-- Audit: tagged as integration, one entry per entity in summary mode.
select is(
  (select count(*)::int from (select better_supabase.audit_event(event_type => 'row.imported', category => 'data') as id) a where a.id is not null),
  0,
  'summary mode writes no entry per row'
);
select set_config('better_supabase.import_audit', 'rows', true);
select lives_ok(
  $$select better_supabase.audit_event(event_type => 'row.imported', category => 'data')$$,
  'rows mode writes an entry per row'
);
select is(
  (select actor_kind from better_supabase.audit_events where event_type = 'row.imported'),
  'integration',
  'an entry written in a session is an integration entry'
);
select is(
  (select correlation_id from better_supabase.audit_events where event_type = 'row.imported'),
  'import:' || current_setting('bsb.run'),
  'an entry carries the import correlation id'
);

-- State machine: a row inserted in any status gets one imported history row and no event.
insert into better_supabase.work_items (id, tenant_id, number, identifier, title, state)
values ('00000000-0000-4000-8000-00000000f901', '00000000-0000-4000-8000-000000000001', 9901, 'IM-9901', 'Imported done', 'completed');
select is(
  (select count(*)::int from better_supabase.status_history
    where subject_type = 'work_item' and subject_id = '00000000-0000-4000-8000-00000000f901'
      and from_status is null and to_status = 'completed' and reason = 'imported'),
  1,
  'the insert writes one imported history row'
);
select is(
  (select count(*)::int from better_supabase.outbox_events where type = 'status.changed' and subject = 'statuses/work_item/00000000-0000-4000-8000-00000000f901'),
  0,
  'the insert fires no status event'
);

-- A session ends with the batch: import_upsert_batch restores the caller's settings.
select set_config('better_supabase.import_run', '', true);
select set_config('better_supabase.correlation_id', '', true);
select is(better_supabase.import_run(), null, 'clearing the setting ends the session');
insert into better_supabase.work_items (id, tenant_id, number, identifier, title, state)
values ('00000000-0000-4000-8000-00000000f902', '00000000-0000-4000-8000-000000000001', 9902, 'IM-9902', 'Plain insert', 'completed');
select is(
  (select count(*)::int from better_supabase.status_history where subject_id = '00000000-0000-4000-8000-00000000f902' and reason = 'imported'),
  0,
  'outside a session an insert writes no imported history row'
);

-- import_upsert_batch begins its own session and leaves none behind.
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'customer', '[{"key":"m1","data":{"name":"Mode","kvk":"91"}}]'::jsonb
  ) -> 'inserted'),
  '1'::jsonb,
  'the batch inserts the customer'
);
select is(better_supabase.import_run(), null, 'the batch leaves no session behind');
select is(current_setting('better_supabase.correlation_id', true), '', 'the batch restores the correlation id');

select better_supabase.finish_import_run(current_setting('bsb.run')::uuid);
select is(
  (select count(*)::int from better_supabase.audit_events
    where event_type = 'import.entity_completed' and correlation_id = 'import:' || current_setting('bsb.run')),
  1,
  'finishing writes one summary entry for the entity'
);

-- A second identical run adds no audit entry.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select set_config(
  'bsb.run2',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'mode', '{}'::jsonb) ->> 'id'),
  true
);
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run2')::uuid);
select better_supabase.import_upsert_batch(
  current_setting('bsb.run2')::uuid, 'customer', '[{"key":"m1","data":{"name":"Mode","kvk":"91"}}]'::jsonb
);
select better_supabase.finish_import_run(current_setting('bsb.run2')::uuid);
select is(
  (select count(*)::int from better_supabase.audit_events where correlation_id = 'import:' || current_setting('bsb.run2')),
  0,
  'a second identical run adds zero audit entries'
);

select * from finish();
rollback;
