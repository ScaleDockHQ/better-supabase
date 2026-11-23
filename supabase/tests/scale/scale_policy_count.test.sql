-- What a policy costs on a list read (ADR 1218): 1,000 rows of one tenant
-- read as a member, with the library's 9 policies of a tenant table (four
-- permissive, four restrictive tenant scopes, bsb_session_active), with 13
-- (four more of the shapes providers and apps add), with 8 (without
-- bsb_session_active) and with 8 where the select tenant scope also calls
-- session_active(), which is what folding the two policies would ship. The
-- read serializes the rows the way PostgREST does. Each read runs 50 times;
-- SCALE_MS prints the mean.
begin;
select plan(4);

create table public.bsb_policy_probe (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  created_by uuid,
  status text not null default 'open',
  title text not null,
  created_at timestamptz not null default now()
);
create index on public.bsb_policy_probe (tenant_id, created_at);
grant select, insert, update, delete on public.bsb_policy_probe to authenticated;
alter table public.bsb_policy_probe enable row level security;

insert into public.bsb_policy_probe (tenant_id, created_by, title, created_at)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1',
  'Probe ' || g, now() - (g || ' seconds')::interval
from generate_series(1, 1000) g;
insert into public.bsb_policy_probe (tenant_id, title)
select gen_random_uuid(), 'Other ' || g from generate_series(1, 9000) g;
analyze public.bsb_policy_probe;

create policy p_select on public.bsb_policy_probe for select to authenticated
  using (tenant_id in (select better_supabase.member_organization_ids()));
create policy p_insert on public.bsb_policy_probe for insert to authenticated
  with check (tenant_id in (select better_supabase.member_organization_ids()));
create policy p_update on public.bsb_policy_probe for update to authenticated
  using (tenant_id in (select better_supabase.member_organization_ids()));
create policy p_delete on public.bsb_policy_probe for delete to authenticated
  using (tenant_id in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on public.bsb_policy_probe as restrictive for select to authenticated
  using (tenant_id in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_insert on public.bsb_policy_probe as restrictive for insert to authenticated
  with check (tenant_id in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on public.bsb_policy_probe as restrictive for update to authenticated
  using (tenant_id in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on public.bsb_policy_probe as restrictive for delete to authenticated
  using (tenant_id in (select better_supabase.member_organization_ids()));
create policy bsb_session_active on public.bsb_policy_probe as restrictive for all to authenticated
  using ((select better_supabase.session_active()))
  with check ((select better_supabase.session_active()));

insert into auth.sessions (id, user_id, created_at, updated_at)
values ('00000000-0000-4000-8000-00000000c0de', '00000000-0000-4000-8000-0000000000a1', now(), now());

create temp table timings (label text, ms numeric);
grant all on timings to public;

create function pg_temp.read(label text) returns void language plpgsql as $$
declare
  t timestamptz;
  n bigint;
begin
  perform count(*) from public.bsb_policy_probe;
  t := clock_timestamp();
  for i in 1..50 loop
    select json_array_length(coalesce(json_agg(x), '[]')) into n from (
      select * from public.bsb_policy_probe
      where tenant_id = '00000000-0000-4000-8000-000000000001'
      order by created_at desc limit 1000
    ) x;
  end loop;
  if n <> 1000 then
    raise exception 'read % rows', n;
  end if;
  insert into timings values (label, round(extract(epoch from clock_timestamp() - t) * 1000 / 50, 2));
end $$;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","session_id":"00000000-0000-4000-8000-00000000c0de","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);

set local role authenticated;
select pg_temp.read('policies_9');
reset role;

create policy app_own on public.bsb_policy_probe for select to authenticated
  using (created_by = (select auth.uid()));
create policy app_visible on public.bsb_policy_probe for select to authenticated
  using (status <> 'deleted' and tenant_id in (select better_supabase.member_organization_ids()));
create policy provider_aal on public.bsb_policy_probe as restrictive for all to authenticated
  using (coalesce((select auth.jwt() ->> 'aal'), 'aal1') <> 'none');
create policy provider_user on public.bsb_policy_probe as restrictive for all to authenticated
  using ((select auth.uid()) is not null);

set local role authenticated;
select pg_temp.read('policies_13');
reset role;

drop policy app_own on public.bsb_policy_probe;
drop policy app_visible on public.bsb_policy_probe;
drop policy provider_aal on public.bsb_policy_probe;
drop policy provider_user on public.bsb_policy_probe;
drop policy bsb_session_active on public.bsb_policy_probe;

set local role authenticated;
select pg_temp.read('policies_8');
reset role;

alter policy bsb_tenant_scope_select on public.bsb_policy_probe
  using (tenant_id in (select better_supabase.member_organization_ids()) and (select better_supabase.session_active()));

set local role authenticated;
select pg_temp.read('policies_8_folded');
reset role;

select diag('SCALE_MS list_read_' || label || '=' || ms) from timings order by label;

select ok((select count(*) from timings) = 4, 'four policy sets were timed');
select ok((select ms from timings where label = 'policies_13') > 0, 'the 13-policy read was timed');
select ok((select ms from timings where label = 'policies_8') > 0, 'the 8-policy read was timed');
select ok((select ms from timings where label = 'policies_8_folded') > 0, 'the folded read was timed');

select * from finish();
rollback;
