-- prune_deadlines deletes pending deadlines for any caller with deadlines.write,
-- but deleting every state (pending_only false, satisfied history included)
-- needs the prune key: deadlines.manage unless permissions.prune names another.
-- Acme (…0001) owns Road Runner Inc (…a001); …00a1 owns Acme and …00a2 is a
-- member (supabase/seed.sql).
begin;
select plan(5);

insert into better_supabase.permissions (key)
values ('deadlines.read'), ('deadlines.write'), ('deadlines.manage')
on conflict do nothing;
insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id from better_supabase.roles r, better_supabase.permissions p
where (r.key in ('owner', 'member') and p.key in ('deadlines.read', 'deadlines.write'))
  or (r.key = 'owner' and p.key = 'deadlines.manage')
on conflict do nothing;
insert into better_supabase.permission_overrides (tenant_id, role_id, permission_id, granted)
select '00000000-0000-4000-8000-000000000001', r.id, p.id, false
from better_supabase.roles r, better_supabase.permissions p
where r.key = 'member' and p.key = 'deadlines.manage';

with rule_set as (
  insert into better_supabase.deadline_rule_sets (jurisdiction, kind) values ('pgtap-prune', 'notice') returning id
)
insert into better_supabase.deadline_rule_versions (rule_set_id, version, status, rules, groups, content_hash, effective_from, approved_at)
select id, 1, 'approved',
  '[{"key":"notice","group":"notice","deadline":{"n":30,"unit":"days","from":"start"},"citation":{"reference":"s"}}]',
  '[{"key":"notice","citation":{"reference":"s"}}]',
  'pgtap-prune', '2020-01-01', now()
from rule_set;

-- Acme member: deadlines.write, not deadlines.manage.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (better_supabase.compute_deadlines_many(
    '00000000-0000-4000-8000-000000000001',
    '[{"subjectType":"customer","subjectId":"00000000-0000-4000-8000-00000000a001","jurisdiction":"pgtap-prune","kind":"notice","facts":{"start":"2026-01-02"},"asOf":"2026-01-05"}]',
    true
  ) -> 0 ->> 'ok')::boolean,
  true,
  'a member who computes still prunes with compute_deadlines_many'
);
select is(
  better_supabase.prune_deadlines('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'pgtap-prune'),
  0,
  'and prunes the pending deadlines of other jurisdictions'
);
select throws_ok(
  $$select better_supabase.prune_deadlines('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', null, false)$$,
  '42501',
  'not allowed to delete settled deadlines',
  'but cannot delete every state without the prune key'
);

-- Acme owner: holds deadlines.manage.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.prune_deadlines('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', null, false),
  1,
  'deadlines.manage deletes every state'
);

reset role;
select is_empty(
  $$select id from better_supabase.deadlines where subject_type = 'customer' and subject_id = '00000000-0000-4000-8000-00000000a001'$$,
  'the subject has no deadlines left'
);

select * from finish();
rollback;
