-- Deadlines follow the read access of their subject (config.subjects): a
-- member who holds deadlines.read but cannot read the customer sees none of
-- its deadlines and cannot compute or satisfy them. Acme (…0001) owns Road
-- Runner Inc (…a001); …00a1 owns Acme and …00a2 is a member (supabase/seed.sql).
begin;
select plan(10);

insert into better_supabase.permissions (key) values ('deadlines.read'), ('deadlines.write')
on conflict do nothing;
insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id from better_supabase.roles r, better_supabase.permissions p
where r.key in ('owner', 'member') and p.key in ('deadlines.read', 'deadlines.write')
on conflict do nothing;
insert into better_supabase.permission_overrides (organization_id, role_id, permission_id, granted)
select '00000000-0000-4000-8000-000000000001', r.id, p.id, false
from better_supabase.roles r, better_supabase.permissions p
where r.key = 'member' and p.key = 'customers.read';

with rule_set as (
  insert into better_supabase.deadline_rule_sets (jurisdiction, kind) values ('pgtap', 'notice') returning id
)
insert into better_supabase.deadline_rule_versions (rule_set_id, version, status, rules, groups, content_hash, effective_from, approved_at)
select id, 1, 'approved',
  '[{"key":"notice","group":"notice","deadline":{"n":30,"unit":"days","from":"start"},"citation":{"reference":"s"}}]',
  '[{"key":"notice","citation":{"reference":"s"}}]',
  'pgtap', '2020-01-01', now()
from rule_set;

select is(
  jsonb_array_length(better_supabase.compute_deadlines('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'pgtap', 'notice', '{"start":"2026-01-02"}', '2026-01-05')),
  1,
  'the service role computes a customer''s deadline'
);
select is(
  jsonb_array_length(better_supabase.compute_deadlines('00000000-0000-4000-8000-000000000001', 'job', 'j1', 'pgtap', 'notice', '{"start":"2026-01-02"}', '2026-01-05')),
  1,
  'and one of a type config.subjects does not list'
);

-- Acme owner: reads the customer.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select array_agg(subject_type) from better_supabase.deadlines),
  array['customer'],
  'the owner reads the customer''s deadline and none of an unlisted type'
);
select is(
  jsonb_array_length(better_supabase.list_deadlines('00000000-0000-4000-8000-000000000001')),
  1,
  'list_deadlines returns it'
);

-- Acme member: holds deadlines.read and deadlines.write, not customers.read.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  better_supabase.can('tenant', '00000000-0000-4000-8000-000000000001', 'deadlines.read')
    and not better_supabase.can('tenant', '00000000-0000-4000-8000-000000000001', 'customers.read'),
  'the member holds deadlines.read but not customers.read'
);
select is_empty(
  'select id from better_supabase.deadlines',
  'the member reads no deadline of a customer they cannot read'
);
select is(
  better_supabase.list_deadlines('00000000-0000-4000-8000-000000000001'),
  '[]'::jsonb,
  'list_deadlines returns none'
);
select throws_ok(
  $$select better_supabase.compute_deadlines('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'pgtap', 'notice', '{"start":"2026-01-03"}', '2026-01-05')$$,
  '42501',
  'not allowed to compute deadlines for this subject',
  'the member cannot compute them'
);
select throws_ok(
  $$select better_supabase.recompute_deadlines('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', '{"start":"2026-01-03"}')$$,
  '42501',
  'not allowed to compute deadlines for this subject',
  'or recompute them'
);

reset role;
create temp table customer_deadline as
select id from better_supabase.deadlines where subject_type = 'customer';
grant select on customer_deadline to authenticated;
set local role authenticated;

select throws_ok(
  $$select better_supabase.satisfy_deadline((select id from customer_deadline), 'served')$$,
  'P0002',
  'no such deadline',
  'and cannot satisfy them'
);

select * from finish();
rollback;
