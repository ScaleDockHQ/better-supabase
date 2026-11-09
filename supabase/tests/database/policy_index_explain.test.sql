-- A policy filter on an indexed column uses that index, and (select auth.uid())
-- is an InitPlan (ADR 0460, BS385). Run with `supabase test db`.
begin;
select plan(3);

create table public.policy_index_probe (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null
);
create index policy_index_probe_owner_idx on public.policy_index_probe (owner_id);
alter table public.policy_index_probe enable row level security;
create policy policy_index_probe_owner on public.policy_index_probe
  for select to authenticated
  using (owner_id = (select auth.uid()));
grant select on public.policy_index_probe to authenticated;

insert into public.policy_index_probe (owner_id)
select '00000000-0000-4000-8000-0000000000a2'
from generate_series(1, 20);
insert into public.policy_index_probe (owner_id)
select '00000000-0000-4000-8000-0000000000a3'
from generate_series(1, 4000);
analyze public.policy_index_probe;

create function pg_temp.plan_of(query text) returns text
language plpgsql as $$
declare
  rec record;
  out text := '';
begin
  for rec in execute 'explain (format text) ' || query loop
    out := out || rec."QUERY PLAN" || E'\n';
  end loop;
  return out;
end;
$$;
grant execute on function pg_temp.plan_of(text) to authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}',
  true
);
set local role authenticated;

select matches(
  pg_temp.plan_of('select id from public.policy_index_probe'),
  'Index Scan|Bitmap Index Scan|Index Only Scan',
  'the policy column uses its index'
);
select matches(
  pg_temp.plan_of('select id from public.policy_index_probe'),
  'InitPlan',
  'auth.uid() runs once per statement'
);
select matches(
  pg_temp.plan_of('select id from public.policy_index_probe'),
  'policy_index_probe_owner_idx',
  'the plan names the policy column index'
);

select * from finish();
rollback;
