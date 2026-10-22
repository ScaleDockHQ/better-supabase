-- Engagement recordings on the fixture's access contract: the admin (…00a1)
-- of Acme (…0001) attaches an ai-files recording to a call, saves its
-- transcript and the call's notes, and someone outside Acme (…00e2) reads
-- none of it.
begin;
select plan(12);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e2', 'someone@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

insert into better_supabase.engagements (id, tenant_id, type, title, created_by) values
  ('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-000000000001', 'call', 'Discovery call', '00000000-0000-4000-8000-0000000000a1');
insert into better_supabase.ai_files (id, organization_id, owner_id, bucket, filename, media_type, byte_size, status) values
  ('00000000-0000-4000-8000-00000000d101', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'ai-files', 'call.webm', 'audio/webm', 3, 'ready'),
  ('00000000-0000-4000-8000-00000000d102', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'ai-files', 'late.webm', 'audio/webm', 3, 'pending');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.recording', better_supabase.attach_engagement_recording(
  '00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-00000000d101', 'en'
)::text, true);

select is(
  current_setting('test.recording')::jsonb ->> 'status',
  'pending',
  'an attached recording waits for its transcript'
);
select is(
  current_setting('test.recording')::jsonb ->> 'filename',
  'call.webm',
  'a recording takes the file''s name'
);
select throws_ok(
  $$select better_supabase.attach_engagement_recording('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-00000000d101', null)$$,
  '23505',
  null,
  'a file is attached once'
);
select throws_ok(
  $$select better_supabase.attach_engagement_recording('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-00000000d102', null)$$,
  'P0002',
  null,
  'a file still uploading is not a recording'
);
select throws_ok(
  $$select better_supabase.save_engagement_transcript(
    (current_setting('test.recording')::jsonb ->> 'id')::uuid,
    '[{"startMs": 500, "endMs": 100, "text": "Backwards"}]', '{}')$$,
  '22023',
  null,
  'a segment that ends before it starts is refused'
);
select is(
  (better_supabase.save_engagement_transcript(
    (current_setting('test.recording')::jsonb ->> 'id')::uuid,
    '[{"speaker": "Rep", "startMs": 0, "endMs": 3000, "text": "Thanks for joining."},
      {"speaker": "Buyer", "startMs": 3000, "endMs": 8000, "text": "Send the proposal.", "confidence": 0.8}]',
    '{"language": "en", "durationSeconds": 8, "model": "stt-test"}'
  ) ->> 'segmentCount')::int,
  2,
  'a saved transcript has a segment per turn'
);
select is(
  better_supabase.engagement_transcript((current_setting('test.recording')::jsonb ->> 'id')::uuid, 1, null) -> 0 ->> 'speaker',
  'Buyer',
  'the transcript pages by position'
);
select is(
  better_supabase.save_engagement_notes(
    '00000000-0000-4000-8000-00000000d001',
    '{"summary": "They want a proposal.", "actionItems": [{"text": "Send the proposal"}], "model": "notes-test"}'
  ) ->> 'source',
  'ai',
  'notes default to an AI source'
);
select throws_ok(
  $$select better_supabase.fail_engagement_recording((current_setting('test.recording')::jsonb ->> 'id')::uuid, 'boom')$$,
  '42501',
  null,
  'only the service role marks a recording failed'
);

reset role;
select is(
  (select count(*) from better_supabase.outbox_events
   where type in ('engagement.recorded', 'engagement.transcribed', 'engagement.summarized')),
  3::bigint,
  'recording, transcribing and summarizing each record an event'
);

-- Someone outside Acme.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;

select is(
  better_supabase.engagement_recordings('00000000-0000-4000-8000-00000000d001'),
  '[]'::jsonb,
  'an outsider sees no recordings'
);
select is(
  better_supabase.engagement_notes('00000000-0000-4000-8000-00000000d001'),
  null,
  'an outsider reads no notes'
);

select * from finish();
rollback;
