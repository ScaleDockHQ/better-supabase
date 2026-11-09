-- 9.7: a `param is null or col = any(param)` filter cannot use an index under a
-- generic plan. The branch form can. knowledge_search forces a custom plan,
-- and mark_notifications_read branches. list_notifications still filters types
-- with coalesce after the join, and subject_types with `is null or = any`.
-- That index access belongs to the large-tenant work, so this test does not
-- change list_notifications. Run with `supabase test db`.
begin;
select plan(5);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'better_supabase'
      and p.proname = 'knowledge_search'
      and 'plan_cache_mode=force_custom_plan' = any (p.proconfig)
  ),
  'knowledge_search forces a custom plan'
);

select ok(
  pg_get_functiondef('better_supabase.mark_notifications_read(uuid[], uuid)'::regprocedure)
    !~ 'is null or',
  'mark_notifications_read does not use param is null or col = any(param)'
);

select ok(
  pg_get_functiondef('better_supabase.list_notifications(uuid, text, text[], timestamptz, integer, uuid, text[], text, boolean, boolean, boolean)'::regprocedure)
    ~ 'any\(coalesce\(',
  'list_notifications types filter uses coalesce'
);

create table public.null_filter_probe (
  id uuid primary key default gen_random_uuid(),
  kind text not null
);
create index null_filter_probe_kind_idx on public.null_filter_probe (kind);
insert into public.null_filter_probe (kind)
select case when g < 30 then 'kept' else 'other' end
from generate_series(1, 4000) g;
analyze public.null_filter_probe;

prepare null_filter_or (text[]) as
  select id from public.null_filter_probe
  where ($1 is null or kind = any ($1));
prepare null_filter_branch (text[]) as
  select id from public.null_filter_probe
  where kind = any ($1);

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

set local plan_cache_mode = force_custom_plan;

select matches(
  pg_temp.plan_of('execute null_filter_branch(array[''kept''])'),
  'null_filter_probe_kind_idx',
  'the branch form uses the kind index'
);

set local plan_cache_mode = force_generic_plan;

select matches(
  pg_temp.plan_of('execute null_filter_or(array[''kept''])'),
  'Seq Scan',
  'param is null or col = any(param) does not use the kind index under a generic plan'
);

select * from finish();
rollback;
