-- One call for many records: purge_teams, resend_invitations and
-- compute_deadlines_many act on each item as the single call would, and
-- prune_deadlines drops a subject's deadlines of other jurisdictions. The
-- owner (…00a1) runs Acme (…0001); the member (…00a2) belongs to it
-- (supabase/seed.sql).
begin;
select plan(10);

with rule_set as (
  insert into better_supabase.deadline_rule_sets (jurisdiction, kind) values ('pgtap', 'notice') returning id
)
insert into better_supabase.deadline_rule_versions (rule_set_id, version, status, rules, groups, content_hash, effective_from, approved_at)
select id, 1, 'approved',
  '[{"key":"notice","group":"notice","deadline":{"n":30,"unit":"days","from":"start"},"citation":{"reference":"s"}}]',
  '[{"key":"notice","citation":{"reference":"s"}}]',
  'pgtap', '2020-01-01', now()
from rule_set;

insert into better_supabase.deadlines (tenant_id, subject_type, subject_id, jurisdiction, kind, group_key, rule_version_id, result, citation)
select '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'old', 'notice', 'old-notice', v.id, 'pending', '{"reference":"s"}'
from better_supabase.deadline_rule_versions v
join better_supabase.deadline_rule_sets s on s.id = v.rule_set_id
where s.jurisdiction = 'pgtap';

select is(
  (
    select jsonb_agg(item -> 'ok' order by ord)
    from jsonb_array_elements(better_supabase.compute_deadlines_many(
      '00000000-0000-4000-8000-000000000001',
      '[{"subjectType":"customer","subjectId":"00000000-0000-4000-8000-00000000a001","jurisdiction":"pgtap","kind":"notice","facts":{"start":"2026-01-02"},"asOf":"2026-01-05"},
        {"subjectType":"customer","subjectId":"00000000-0000-4000-8000-00000000a002","jurisdiction":"none","kind":"notice","facts":{}}]',
      true
    )) with ordinality as x(item, ord)
  ),
  '[true, false]'::jsonb,
  'compute_deadlines_many answers each subject, and one without rules fails alone'
);
select is(
  (select array_agg(jurisdiction order by jurisdiction) from better_supabase.deadlines
   where subject_id = '00000000-0000-4000-8000-00000000a001'),
  array['pgtap'],
  'with prune, the pending deadline of another jurisdiction is gone'
);
select is(
  better_supabase.prune_deadlines('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'pgtap'),
  0,
  'prune_deadlines keeps the jurisdiction it is given'
);
select is(
  better_supabase.prune_deadlines('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', null, false),
  1,
  'prune_deadlines with pending_only false forgets every deadline of the subject'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.teams', array[
  better_supabase.create_team('00000000-0000-4000-8000-000000000001', 'One', null, 'batch-one') ->> 'id',
  better_supabase.create_team('00000000-0000-4000-8000-000000000001', 'Two', null, 'batch-two') ->> 'id'
]::text, true);

select is(
  better_supabase.purge_teams(current_setting('test.teams')::uuid[]),
  2,
  'the owner purges two teams in one call'
);
select is(
  (select count(*)::integer from better_supabase.teams where id = any (current_setting('test.teams')::uuid[])),
  0,
  'both teams are gone'
);

select set_config('test.invites', array[
  better_supabase.invite_member('00000000-0000-4000-8000-000000000001', 'batch-one@acme.test', 'member') ->> 'id',
  better_supabase.invite_member('00000000-0000-4000-8000-000000000001', 'batch-two@acme.test', 'member') ->> 'id'
]::text, true);

select is(
  (
    select array_agg(item ->> 'email' order by ord)
    from jsonb_array_elements(better_supabase.resend_invitations(current_setting('test.invites')::uuid[])) with ordinality as x(item, ord)
  ),
  array['batch-one@acme.test', 'batch-two@acme.test'],
  'resend_invitations resends each invitation in the order given'
);
select ok(
  (
    select bool_and(item ->> 'token' is not null)
    from jsonb_array_elements(better_supabase.resend_invitations(current_setting('test.invites')::uuid[])) as x(item)
  ),
  'each resent invitation carries its new token'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.resend_invitations(%L::uuid[])$$, current_setting('test.invites')),
  'P0002',
  null,
  'a member cannot resend invitations in one call either; they don''t see them'
);
select throws_ok(
  format($$select better_supabase.purge_teams(array[%L]::uuid[])$$, gen_random_uuid()),
  'P0002',
  null,
  'purge_teams refuses an unknown team'
);

select * from finish();
rollback;
