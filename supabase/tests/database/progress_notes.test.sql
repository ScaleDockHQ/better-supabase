-- Progress notes on the fixture's access contract: the owner (…00a1) of Acme
-- (…0001) logs a team, a subject and a restricted note on the customer
-- Road Runner Inc (…a001). The member (…00a2) reads the restricted note only
-- once they are on its team in a named role, a guest (…00e1) of the customer
-- reads only the subject note, and a locked note takes addenda and an
-- in-error flag instead of edits.
begin;
select plan(16);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e1', 'client@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.team', better_supabase.log_activity(
  '00000000-0000-4000-8000-000000000001',
  '{"type": "note", "title": "Weekly check-in", "category": "care"}',
  '[{"type": "customer", "id": "00000000-0000-4000-8000-00000000a001"}]'
) ->> 'id', true);
select set_config('test.subject', better_supabase.log_activity(
  '00000000-0000-4000-8000-000000000001',
  '{"type": "note", "title": "Shared with the family", "audience": "subject"}',
  '[{"type": "customer", "id": "00000000-0000-4000-8000-00000000a001"}]'
) ->> 'id', true);
select set_config('test.restricted', better_supabase.log_activity(
  '00000000-0000-4000-8000-000000000001',
  '{"type": "note", "title": "Assessment", "audience": "restricted", "restrictedRoles": ["lead"]}',
  '[{"type": "customer", "id": "00000000-0000-4000-8000-00000000a001"}]'
) ->> 'id', true);

select ok(
  (select locked_at > now() and locked_at <= now() + interval '24 hours'
   from better_supabase.engagements where id = current_setting('test.team')::uuid),
  'a note locks 24 hours after it is logged'
);
select is(
  (select restricted_roles from better_supabase.engagements where id = current_setting('test.restricted')::uuid),
  array['lead'],
  'a restricted note keeps its roles'
);
select throws_ok(
  $$select better_supabase.log_activity('00000000-0000-4000-8000-000000000001',
    '{"type": "note", "title": "Bad", "audience": "everyone"}', '[]')$$,
  '22023',
  'audience must be one of team, subject, restricted',
  'an unknown audience is refused'
);
select throws_ok(
  $$select better_supabase.log_activity('00000000-0000-4000-8000-000000000001',
    '{"type": "note", "title": "Bad", "category": "gossip"}', '[]')$$,
  '22023',
  null,
  'an unknown category is refused'
);

-- Acme member, on no team and without activities.read_restricted.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.engagements
   where id in (current_setting('test.team')::uuid, current_setting('test.subject')::uuid)),
  2,
  'a member reads team and subject notes'
);
select is(
  (select count(*)::int from better_supabase.engagements where id = current_setting('test.restricted')::uuid),
  0,
  'a member outside the named roles does not read a restricted note'
);

-- Acme owner: the member joins the customer's team as a member, then as lead.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select better_supabase.add_subject_member('customer', '00000000-0000-4000-8000-00000000a001',
  '00000000-0000-4000-8000-0000000000a2', role => 'member');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.engagements where id = current_setting('test.restricted')::uuid),
  0,
  'team membership in another role does not open a restricted note'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select better_supabase.add_subject_member('customer', '00000000-0000-4000-8000-00000000a001',
  '00000000-0000-4000-8000-0000000000a2', role => 'lead');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.engagements where id = current_setting('test.restricted')::uuid),
  1,
  'a lead on the customer''s team reads the restricted note'
);

-- Acme owner invites the client as a guest of the customer.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select set_config('test.invite', better_supabase.invite_guest(
  '00000000-0000-4000-8000-000000000001', 'client@example.test', 'Client',
  party_type => 'customer', party_id => '00000000-0000-4000-8000-00000000a001'
)::text, true);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;
select better_supabase.accept_guest_invite(current_setting('test.invite')::jsonb ->> 'token');

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select better_supabase.grant_guest_access(
  (current_setting('test.invite')::jsonb ->> 'id')::uuid, 'customer', '00000000-0000-4000-8000-00000000a001'
);

-- The guest.
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e1","role":"authenticated"}', true);
set local role authenticated;

select results_eq(
  $$select id from better_supabase.engagements$$,
  format($$values ('%s'::uuid)$$, current_setting('test.subject')),
  'a guest reads only the subject note'
);
select is(
  (select count(*)::int from better_supabase.engagement_subjects
   where engagement_id = current_setting('test.subject')::uuid),
  1,
  'a guest reads the subject note''s record link'
);

-- The team note's lock passes.
reset role;
update better_supabase.engagements set locked_at = now() - interval '1 minute'
where id = current_setting('test.team')::uuid;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  format($$select better_supabase.update_activity('%s', '{"title": "Changed"}', null)$$, current_setting('test.team')),
  '55000',
  'the engagement is locked: add an addendum with amend_activity instead',
  'a locked note cannot be edited'
);
select throws_ok(
  format($$select better_supabase.complete_activity('%s', true, null)$$, current_setting('test.team')),
  '55000',
  null,
  'a locked note cannot be completed'
);
select is(
  better_supabase.amend_activity(current_setting('test.team')::uuid, 'Also spoke with the GP.') ->> 'amends_id',
  current_setting('test.team'),
  'an addendum links to the note it amends'
);
select is(
  better_supabase.mark_activity_error(current_setting('test.subject')::uuid, 'Wrong client') ->> 'marked_error_reason',
  'Wrong client',
  'a note is marked as entered in error with a reason'
);
select throws_ok(
  format($$select better_supabase.update_activity('%s', '{"title": "Changed"}', null)$$, current_setting('test.subject')),
  '55000',
  null,
  'a note marked in error is locked'
);
select throws_ok(
  format($$select better_supabase.mark_activity_error('%s', 'Again')$$, current_setting('test.subject')),
  '55000',
  'the engagement is already marked in error',
  'a note is marked in error once'
);

select * from finish();
rollback;
