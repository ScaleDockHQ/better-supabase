-- approval_eligible_ids_in answers several tenants, or all of them, in one call
-- and checks each permission once, for whoever the claims name at the time of
-- the call: users and claims that change in one transaction each get their own
-- answer, and nothing carries over to the next transaction. Ann (…a1)
-- owns Acme (…0001) and is a member of Globex (…0002), Ben (…a2) is a member of
-- Acme and Cara (…a3) owns Globex (supabase/seed.sql).
--
-- The reads run in a transaction without a transaction id, as PostgREST reads
-- do, so the fixture is committed first (without triggers) and removed at the
-- end. pgTAP's own bookkeeping writes, so the reads record their results in
-- settings and the assertions run in a later transaction.

begin;
set local session_replication_role = replica;
delete from better_supabase.approval_requests where subject_type = 'eligible_set';
insert into better_supabase.approval_requests (tenant_id, subject_type, subject_id, action, policy, requested_by)
select '00000000-0000-4000-8000-000000000001'::uuid, 'eligible_set', 'p' || g, 'approve',
  '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":false}'::jsonb, '00000000-0000-4000-8000-0000000000a3'::uuid
from generate_series(1, 6) g
union all
select '00000000-0000-4000-8000-000000000001', 'eligible_set', 'm' || g, 'approve',
  '{"steps":[{"approvers":{"role":"member"},"required":1}],"selfApproval":false}', '00000000-0000-4000-8000-0000000000a3'
from generate_series(1, 3) g
union all
select '00000000-0000-4000-8000-000000000002', 'eligible_set', 'g' || g, 'approve',
  '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":false}', '00000000-0000-4000-8000-0000000000a2'
from generate_series(1, 4) g
union all
select '00000000-0000-4000-8000-000000000002', 'eligible_set', 'u1', 'approve',
  '{"steps":[{"approvers":{"users":["00000000-0000-4000-8000-0000000000a1"]},"required":1}],"selfApproval":false}', '00000000-0000-4000-8000-0000000000a3'
union all
select '00000000-0000-4000-8000-000000000002', 'eligible_set', 'b1', 'approve',
  '{"steps":[{"approvers":{"users":["00000000-0000-4000-8000-0000000000a2"]},"required":1}],"selfApproval":false}', '00000000-0000-4000-8000-0000000000a3'
union all
select '00000000-0000-4000-8000-000000000001', 'eligible_set', 'own', 'approve',
  '{"steps":[{"approvers":{"permission":"approvals.manage"},"required":1}],"selfApproval":false}', '00000000-0000-4000-8000-0000000000a1';
commit;

-- One read-only transaction: Ann, Ann again, Ben, Ann again, Ann with a
-- narrower token, and Ann for Acme alone.
begin;
set local track_functions = 'all';
do $$
declare
  v_ann constant text := '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}';
  v_ben constant text := '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}';
  v_capped constant text := '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","bsb_permission_cap":["approvals.read"]}';
  v_calls bigint;
  v_result text;
  v_parity text;
  v_step integer := 0;
  v_steps text[] := array['ann', 'ann_again', 'ann_wrapper', 'ben', 'ben_outside', 'ann_back', 'ann_capped', 'ann_acme'];
  v_claims text[] := array[v_ann, v_ann, v_ann, v_ben, v_ben, v_ann, v_capped, v_ann];
  v_name text;
begin
  foreach v_name in array v_steps loop
    v_step := v_step + 1;
    perform set_config('request.jwt.claims', v_claims[v_step], true);
    v_calls := (select coalesce(sum(f.calls), 0) from pg_stat_xact_user_functions f where f.schemaname = 'better_supabase' and f.funcname = 'tenant_ids_with');
    v_result := case v_name
      when 'ann_wrapper' then (select string_agg(r.subject_id, ',' order by r.subject_id) from better_supabase.approval_eligible_ids() x join better_supabase.approval_requests r on r.id = x where r.subject_type = 'eligible_set')
      when 'ben_outside' then (select string_agg(r.subject_id, ',' order by r.subject_id) from better_supabase.approval_eligible_ids_in(outside => true) x join better_supabase.approval_requests r on r.id = x where r.subject_type = 'eligible_set')
      when 'ann_acme' then (select string_agg(r.subject_id, ',' order by r.subject_id) from better_supabase.approval_eligible_ids('00000000-0000-4000-8000-000000000001') x join better_supabase.approval_requests r on r.id = x where r.subject_type = 'eligible_set')
      else (select string_agg(r.subject_id, ',' order by r.subject_id) from better_supabase.approval_eligible_ids_in() x join better_supabase.approval_requests r on r.id = x where r.subject_type = 'eligible_set')
    end;
    v_calls := (select coalesce(sum(f.calls), 0) from pg_stat_xact_user_functions f where f.schemaname = 'better_supabase' and f.funcname = 'tenant_ids_with') - v_calls;
    v_parity := (select string_agg(r.subject_id, ',' order by r.subject_id) from better_supabase.approval_requests r
      where r.subject_type = 'eligible_set' and r.status = 'pending'
        and case v_name
          when 'ann_acme' then r.tenant_id = '00000000-0000-4000-8000-000000000001'
          when 'ann_wrapper' then true
          when 'ben_outside' then r.tenant_id not in (select better_supabase.member_organization_ids())
          else r.tenant_id in (select better_supabase.member_organization_ids())
        end
        and better_supabase.approval_eligible(r.id));
    perform set_config('test.set_' || v_name, coalesce(v_result, ''), false);
    perform set_config('test.parity_' || v_name, coalesce(v_parity, ''), false);
    perform set_config('test.calls_' || v_name, v_calls::text, false);
  end loop;
  perform set_config('test.set_no_xid', (pg_current_xact_id_if_assigned() is null)::text, false);
  perform set_config('request.jwt.claims', '', true);
end;
$$;
commit;

-- A new transaction starts without the memo: Ben first, then Ann computes again.
begin;
set local track_functions = 'all';
do $$
declare
  v_calls bigint;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  perform set_config('test.set_next_ben', coalesce((select string_agg(r.subject_id, ',' order by r.subject_id) from better_supabase.approval_eligible_ids_in() x join better_supabase.approval_requests r on r.id = x where r.subject_type = 'eligible_set'), ''), false);
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  v_calls := (select coalesce(sum(f.calls), 0) from pg_stat_xact_user_functions f where f.schemaname = 'better_supabase' and f.funcname = 'tenant_ids_with');
  perform set_config('test.set_next_ann', coalesce((select string_agg(r.subject_id, ',' order by r.subject_id) from better_supabase.approval_eligible_ids_in() x join better_supabase.approval_requests r on r.id = x where r.subject_type = 'eligible_set'), ''), false);
  perform set_config('test.calls_next_ann', ((select coalesce(sum(f.calls), 0) from pg_stat_xact_user_functions f where f.schemaname = 'better_supabase' and f.funcname = 'tenant_ids_with') - v_calls)::text, false);
  perform set_config('request.jwt.claims', '', true);
end;
$$;
commit;

begin;
select plan(21);

select is(current_setting('test.set_no_xid'), 'true', 'the reads ran without a transaction id');

select is(current_setting('test.set_ann'), 'p1,p2,p3,p4,p5,p6,u1', 'Ann decides the Acme permission requests and the Globex request that names her');
select is(current_setting('test.set_ann'), current_setting('test.parity_ann'), 'Ann''s set matches approval_eligible');
select is(current_setting('test.calls_ann'), '1', 'one tenant_ids_with call for the one permission, across both tenants');

select is(current_setting('test.set_ann_again'), current_setting('test.set_ann'), 'the same claims read the same set again');
select is(current_setting('test.calls_ann_again'), '1', 'a second read computes the set again; it keeps nothing between calls');
select is(current_setting('test.set_ann_wrapper'), current_setting('test.set_ann'), 'approval_eligible_ids() returns the same set');
select is(current_setting('test.calls_ann_wrapper'), '1', 'approval_eligible_ids() asks each permission once as well');

select is(current_setting('test.set_ben'), 'm1,m2,m3', 'Ben, in the same transaction, gets his own set');
select is(current_setting('test.set_ben'), current_setting('test.parity_ben'), 'Ben''s set matches approval_eligible');
select is(current_setting('test.calls_ben'), '1', 'Ben''s set checks the permission once for him');

select is(current_setting('test.set_ben_outside'), 'b1', 'outside => true answers the Globex request that names Ben, outside his tenants');
select is(current_setting('test.set_ben_outside'), current_setting('test.parity_ben_outside'), 'the outside set matches approval_eligible');

select is(current_setting('test.set_ann_back'), current_setting('test.set_ann'), 'Ann after Ben gets her own set back');

select is(current_setting('test.set_ann_capped'), 'u1', 'a token capped below approvals.manage keeps only the request that names Ann');
select is(current_setting('test.set_ann_capped'), current_setting('test.parity_ann_capped'), 'the capped set matches approval_eligible');

select is(current_setting('test.set_ann_acme'), 'p1,p2,p3,p4,p5,p6', 'approval_eligible_ids(tenant) keeps to the tenant');
select is(current_setting('test.set_ann_acme'), current_setting('test.parity_ann_acme'), 'the tenant set matches approval_eligible');

select is(current_setting('test.set_next_ben'), 'm1,m2,m3', 'a later transaction starts with Ben and reads none of Ann''s set');
select is(current_setting('test.calls_next_ann'), '1', 'a later transaction checks Ann''s permission once');

-- A decision written in the transaction counts at once.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
insert into better_supabase.approval_decisions (request_id, tenant_id, step, approver, decision)
select r.id, r.tenant_id, 0, '00000000-0000-4000-8000-0000000000a1', 'approved'
from better_supabase.approval_requests r where r.subject_type = 'eligible_set' and r.subject_id = 'p1';

select is(
  (select string_agg(r.subject_id, ',' order by r.subject_id) from better_supabase.approval_eligible_ids_in() x join better_supabase.approval_requests r on r.id = x where r.subject_type = 'eligible_set'),
  'p2,p3,p4,p5,p6,u1',
  'a decision written in the transaction leaves the request out'
);

select * from finish();
rollback;

begin;
set local session_replication_role = replica;
delete from better_supabase.approval_requests where subject_type = 'eligible_set';
commit;
