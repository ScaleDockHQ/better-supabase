-- approval_eligible reads the caller's role approvals once per statement, and
-- keeps permissions, the request's decisions and the memberships live. Ann
-- (…a1) owns Acme (…0001) and Ben (…a2) is a member (supabase/seed.sql).
begin;
select plan(11);

set local track_functions = 'all';

insert into better_supabase.approval_requests (tenant_id, subject_type, subject_id, action, policy, requested_by)
select '00000000-0000-4000-8000-000000000001', 'memo_test', 's' || g, 'approve',
  case when g % 2 = 0
    then '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":false}'::jsonb
    else '{"steps":[{"approvers":{"role":"owner"},"required":1}],"selfApproval":false}'::jsonb end,
  '00000000-0000-4000-8000-0000000000a2'
from generate_series(1, 40) g;

insert into better_supabase.approval_requests (tenant_id, subject_type, subject_id, action, policy, requested_by)
values ('00000000-0000-4000-8000-000000000001', 'memo_test', 'ben', 'approve',
  '{"steps":[{"approvers":{"role":"member"},"required":1}],"selfApproval":false}'::jsonb,
  '00000000-0000-4000-8000-0000000000a1');

create temp table calls_before on commit drop as
  select funcname, calls from pg_stat_xact_user_functions where schemaname = 'better_supabase';

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);

select is(
  (select count(*) from better_supabase.approval_eligible_ids('00000000-0000-4000-8000-000000000001') x
    join better_supabase.approval_requests r on r.id = x where r.subject_type = 'memo_test'),
  40::bigint,
  'Ann may decide the 40 permission and role requests'
);

create temp table calls_after on commit drop as
  select funcname, calls from pg_stat_xact_user_functions where schemaname = 'better_supabase';

select is(
  (select coalesce(a.calls, 0) - coalesce(b.calls, 0) from calls_after a left join calls_before b using (funcname) where a.funcname = 'can'),
  1::bigint,
  'permissions stay live: one can() call for the tenant and permission pair, not one per request'
);

select is(
  (select coalesce(a.calls, 0) - coalesce(b.calls, 0) from calls_after a left join calls_before b using (funcname) where a.funcname = 'memo_set'),
  null::bigint,
  'the set form joins memberships and needs no per-request role lookup'
);

select is(
  (select coalesce(a.calls, 0) - coalesce(b.calls, 0) from calls_after a left join calls_before b using (funcname) where a.funcname = 'approval_eligible'),
  null::bigint,
  'approval_eligible_ids does not call approval_eligible per request'
);

do $$
declare
  v_id uuid := (select id from better_supabase.approval_requests where subject_type = 'memo_test' and subject_id = 's2');
  v_before boolean := better_supabase.approval_eligible(v_id);
begin
  insert into better_supabase.approval_decisions (request_id, tenant_id, step, approver, decision)
  values (v_id, '00000000-0000-4000-8000-000000000001', 0, '00000000-0000-4000-8000-0000000000a1', 'approved');
  perform set_config('test.decided', format('%s/%s', v_before, better_supabase.approval_eligible(v_id)), true);
end;
$$;

select is(
  current_setting('test.decided'),
  't/f',
  'a decision inserted in the same statement makes the request ineligible'
);

select is(
  better_supabase.approval_eligible((select id from better_supabase.approval_requests where subject_type = 'memo_test' and subject_id = 's2')),
  false,
  'a decision made earlier in the transaction makes the request ineligible'
);

do $$
declare
  v_id uuid := (select id from better_supabase.approval_requests where subject_type = 'memo_test' and subject_id = 's4');
  v_before boolean := better_supabase.approval_eligible(v_id);
begin
  delete from better_supabase.role_permissions rp
  using better_supabase.roles r, better_supabase.permissions p
  where rp.role_id = r.id and rp.permission_id = p.id and r.key = 'owner' and p.key = 'approvals.manage';
  perform set_config('test.unpermitted', format('%s/%s', v_before, better_supabase.approval_eligible(v_id)), true);
end;
$$;

select is(
  current_setting('test.unpermitted'),
  't/f',
  'a permission removed from the role in the same call makes the request ineligible'
);

do $$
declare
  v_id uuid := (select id from better_supabase.approval_requests where subject_type = 'memo_test' and subject_id = 's1');
  v_before boolean := better_supabase.approval_eligible(v_id);
begin
  update better_supabase.roles set key = 'owner_renamed' where key = 'owner';
  perform set_config('test.unassigned', format('%s/%s', v_before, better_supabase.approval_eligible(v_id)), true);
end;
$$;

select is(
  current_setting('test.unassigned'),
  't/f',
  'a role the policy names, renamed in the same call, no longer matches'
);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);

select is(
  better_supabase.approval_eligible((select id from better_supabase.approval_requests where subject_type = 'memo_test' and subject_id = 'ben')),
  true,
  'Ben may decide the request for members'
);

delete from public.memberships
where organization_id = '00000000-0000-4000-8000-000000000001' and user_id = '00000000-0000-4000-8000-0000000000a2';

select is(
  better_supabase.approval_eligible((select id from better_supabase.approval_requests where subject_type = 'memo_test' and subject_id = 'ben')),
  false,
  'a membership removed earlier in the transaction is respected in the next statement'
);

do $$
declare
  v_id uuid := (select id from better_supabase.approval_requests where subject_type = 'memo_test' and subject_id = 'ben');
  v_before boolean := better_supabase.approval_eligible(v_id);
begin
  insert into public.memberships (organization_id, user_id, role)
  values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', (select id from better_supabase.roles where key = 'member' limit 1));
  perform set_config('test.member_added', format('%s/%s', v_before, better_supabase.approval_eligible(v_id)), true);
end;
$$;

select is(
  current_setting('test.member_added'),
  'f/t',
  'a membership added in the same statement moves the memo generation'
);

select * from finish();
rollback;
