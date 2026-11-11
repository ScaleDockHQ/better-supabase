-- Batch reads on the scale fixture: assistant run steps, project versions, hiring
-- applications, templates and care plans. Each batch function answers what a
-- loop of the per-row function answers, in one call, and skips what the caller
-- cannot read. SCALE_MS lines print the loop and the batch side by side; a loop in
-- the database pays no network hop, so an app that loops over PostgREST pays the
-- loop time plus one round trip per row. bsb.batch (default 100) sizes the batch,
-- bsb.scale_rows (default 60,000) the rows around it.
begin;
select plan(10);

select set_config('bsb.batch', coalesce(nullif(current_setting('bsb.batch', true), ''), '100'), true);
select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

create temp table res (name text, ms numeric);
grant all on res to public;

-- Assistant runs: one chat of the caller with `batch` runs of 50 steps, and a
-- second chat nobody reads with the scale rows spread over 1,000 runs.
insert into better_supabase.ai_chats (id, tenant_id, owner_id, title) values
  ('00000000-0000-4000-8000-0000000fc001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'Mine'),
  ('00000000-0000-4000-8000-0000000fc002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'Theirs');
insert into better_supabase.ai_runs (id, chat_id, owner_id, engine)
select ('00000000-0000-4000-8000-000000d' || lpad(g::text, 5, '0'))::uuid,
  '00000000-0000-4000-8000-0000000fc001', '00000000-0000-4000-8000-0000000000a1', 'workflow'
from generate_series(1, current_setting('bsb.batch')::int) g;
insert into better_supabase.ai_runs (id, chat_id, owner_id, engine)
select ('00000000-0000-4000-8000-000000e' || lpad(g::text, 5, '0'))::uuid,
  '00000000-0000-4000-8000-0000000fc002', '00000000-0000-4000-8000-0000000000a2', 'workflow'
from generate_series(1, 1000) g;
insert into better_supabase.ai_run_steps (run_id, chat_id, owner_id, step_key, label)
select r.id, r.chat_id, r.owner_id, 'step-' || s, 'Step ' || s
from better_supabase.ai_runs r, generate_series(1, 50) s
where r.chat_id = '00000000-0000-4000-8000-0000000fc001';
insert into better_supabase.ai_run_steps (run_id, chat_id, owner_id, step_key, label)
select r.id, r.chat_id, r.owner_id, 'step-' || s, 'Step ' || s
from better_supabase.ai_runs r, generate_series(1, current_setting('bsb.n')::int / 1000) s
where r.chat_id = '00000000-0000-4000-8000-0000000fc002';

-- Versions: `batch` versions of one customer, and the scale rows over 500 other records.
insert into better_supabase.versions (tenant_id, subject_type, subject_id, number, content, content_hash)
select '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', g,
  jsonb_build_object('name', 'Road Runner ' || g, 'notes', repeat('x', 200)), 'h' || g
from generate_series(1, current_setting('bsb.batch')::int) g;
insert into better_supabase.versions (tenant_id, subject_type, subject_id, number, content, content_hash)
select '00000000-0000-4000-8000-000000000001', 'customer', 'noise-' || (g % 500), g / 500 + 1,
  jsonb_build_object('name', 'Noise ' || g), 'n' || g
from generate_series(1, current_setting('bsb.n')::int) g;

-- Hiring: 50 jobs of 20 applications, and the scale rows on one job of the other tenant.
insert into better_supabase.job_openings (id, tenant_id, title)
select ('00000000-0000-4000-8000-000000a' || lpad(g::text, 5, '0'))::uuid,
  '00000000-0000-4000-8000-000000000001', 'Job ' || g
from generate_series(1, 50) g;
insert into better_supabase.job_openings (id, tenant_id, title)
values ('00000000-0000-4000-8000-0000000a9999', '00000000-0000-4000-8000-000000000002', 'Elsewhere');
insert into better_supabase.applications (tenant_id, job_id, candidate_type, candidate_id)
select '00000000-0000-4000-8000-000000000001', j.id, 'person', 'candidate-' || j.id || '-' || a
from better_supabase.job_openings j, generate_series(1, 20) a
where j.tenant_id = '00000000-0000-4000-8000-000000000001';
insert into better_supabase.applications (tenant_id, job_id, candidate_type, candidate_id)
select '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000a9999', 'person', 'noise-' || g
from generate_series(1, current_setting('bsb.n')::int) g;

-- Templates: `batch` published templates of the tenant, and scale rows of another type.
insert into better_supabase.templates (id, tenant_id, key, type, name)
select ('00000000-0000-4000-8000-000000b' || lpad(g::text, 5, '0'))::uuid,
  '00000000-0000-4000-8000-000000000001', 'scale-' || g, 'customer', 'Template ' || g
from generate_series(1, current_setting('bsb.batch')::int) g;
insert into better_supabase.template_versions (template_id, version, body, hash, published_at)
select id, 1, jsonb_build_object('status', 'active', 'rows', repeat('y', 200)), 'hash-' || id, now()
from better_supabase.templates where key like 'scale-%';
insert into better_supabase.templates (id, tenant_id, key, type, name)
select ('00000000-0000-4000-8000-000000c' || lpad(g::text, 5, '0'))::uuid,
  '00000000-0000-4000-8000-000000000001', 'noise-' || g, 'noise', 'Noise ' || g
from generate_series(1, current_setting('bsb.n')::int / 10) g;
insert into better_supabase.template_versions (template_id, version, body, hash, published_at)
select id, 1, '{}'::jsonb, 'noise-' || id, now() from better_supabase.templates where key like 'noise-%';

-- Care plans: `batch` plans of one customer with a problem, goal and action each, and
-- scale plans of other clients.
insert into better_supabase.care_plans (id, tenant_id, subject_type, subject_id, title, version)
select ('00000000-0000-4000-8000-000000f' || lpad(g::text, 5, '0'))::uuid,
  '00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', 'Plan ' || g, g
from generate_series(1, current_setting('bsb.batch')::int) g;
insert into better_supabase.care_plan_problems (tenant_id, plan_id, title)
select tenant_id, id, 'Problem' from better_supabase.care_plans where subject_id = '00000000-0000-4000-8000-00000000a001';
insert into better_supabase.care_plan_goals (tenant_id, plan_id, problem_id, title)
select tenant_id, plan_id, id, 'Goal' from better_supabase.care_plan_problems;
insert into better_supabase.care_plan_actions (tenant_id, plan_id, goal_id, title)
select tenant_id, plan_id, id, 'Action' from better_supabase.care_plan_goals;
insert into better_supabase.care_plans (tenant_id, subject_type, subject_id, title, version)
select '00000000-0000-4000-8000-000000000001', 'customer', 'noise-' || g, 'Noise ' || g, 1
from generate_series(1, current_setting('bsb.n')::int / 20) g;

analyze better_supabase.ai_run_steps;
analyze better_supabase.versions;
analyze better_supabase.applications;
analyze better_supabase.template_versions;
analyze better_supabase.care_plans;

create temp table ids as
select 'runs' as kind, array_agg(id order by id) as ids from better_supabase.ai_runs where chat_id = '00000000-0000-4000-8000-0000000fc001'
union all select 'versions', array_agg(id order by number) from better_supabase.versions where subject_id = '00000000-0000-4000-8000-00000000a001'
union all select 'jobs', array_agg(id order by id) from better_supabase.job_openings where tenant_id = '00000000-0000-4000-8000-000000000001'
union all select 'templates', array_agg(id order by id) from better_supabase.templates where key like 'scale-%'
union all select 'plans', array_agg(id order by version) from better_supabase.care_plans where subject_id = '00000000-0000-4000-8000-00000000a001';
grant all on ids to public;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

-- Assistant run steps.
create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;
do $$
declare v_id uuid; v_count integer := 0;
begin
  for v_id in select unnest(ids) from ids where kind = 'runs' loop
    v_count := v_count + jsonb_array_length(better_supabase.list_ai_run_steps(v_id));
  end loop;
end
$$;
insert into res select 'run steps loop', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
update t0 set t = clock_timestamp();
select better_supabase.list_ai_run_steps_for((select ids from ids where kind = 'runs'), 50) as steps \gset
insert into res select 'run steps batch', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
select is(
  (select array_agg(s ->> 'id' order by ordinality)
   from jsonb_array_elements(:'steps'::jsonb) with ordinality t(s, ordinality)),
  (select array_agg(s ->> 'id' order by r.n, o)
   from (select u, n from (select unnest(ids) as u, generate_series(1, array_length(ids, 1)) as n from ids where kind = 'runs') x) r,
     lateral jsonb_array_elements(better_supabase.list_ai_run_steps(r.u)) with ordinality t(s, o)),
  'the batch returns the steps a loop returns'
);

-- Versions.
update t0 set t = clock_timestamp();
do $$
declare v_id uuid;
begin
  for v_id in select unnest(ids) from ids where kind = 'versions' loop
    perform better_supabase.get_version(v_id);
  end loop;
end
$$;
insert into res select 'versions loop', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
update t0 set t = clock_timestamp();
select better_supabase.get_versions((select ids from ids where kind = 'versions')) as versions \gset
insert into res select 'versions batch', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
select is(
  (select array_agg(v ->> 'id' order by ordinality) from jsonb_array_elements(:'versions'::jsonb) with ordinality t(v, ordinality)),
  (select array_agg(id::text order by o) from unnest((select ids from ids where kind = 'versions')) with ordinality t(id, o)),
  'the batch returns every version in the order requested'
);
select is(
  (:'versions'::jsonb -> 0 -> 'content' ->> 'name'), 'Road Runner 1', 'a version carries its content');

-- Hiring applications.
update t0 set t = clock_timestamp();
do $$
declare v_id uuid;
begin
  for v_id in select unnest(ids) from ids where kind = 'jobs' loop
    perform better_supabase.list_applications(v_id);
  end loop;
end
$$;
insert into res select 'applications loop', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
update t0 set t = clock_timestamp();
select better_supabase.list_applications_for_jobs((select ids from ids where kind = 'jobs')) as apps \gset
insert into res select 'applications batch', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
select is(
  (select array_agg(a ->> 'id' order by ordinality) from jsonb_array_elements(:'apps'::jsonb) with ordinality t(a, ordinality)),
  (select array_agg(a ->> 'id' order by r.o, ordinality)
   from (select u, o from unnest((select ids from ids where kind = 'jobs')) with ordinality t(u, o)) r,
     lateral jsonb_array_elements(better_supabase.list_applications(r.u)) with ordinality t(a, ordinality)),
  'the batch returns the applications of every job in job order'
);

-- Templates.
update t0 set t = clock_timestamp();
do $$
declare v_id uuid;
begin
  for v_id in select unnest(ids) from ids where kind = 'templates' loop
    perform better_supabase.template_get(v_id);
  end loop;
end
$$;
insert into res select 'templates loop', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
update t0 set t = clock_timestamp();
select better_supabase.templates_get_many((select ids from ids where kind = 'templates')) as templates \gset
insert into res select 'templates batch', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
select is(
  (select array_agg(t ->> 'id' order by ordinality) from jsonb_array_elements(:'templates'::jsonb) with ordinality x(t, ordinality)),
  (select array_agg(id::text order by o) from unnest((select ids from ids where kind = 'templates')) with ordinality t(id, o)),
  'the batch returns every template in the order requested'
);
select is(
  (:'templates'::jsonb -> 0 -> 'published' -> 'body' ->> 'status'), 'active', 'a template carries its published body');

-- Care plans.
update t0 set t = clock_timestamp();
do $$
declare v_id uuid;
begin
  for v_id in select unnest(ids) from ids where kind = 'plans' loop
    perform better_supabase.get_care_plan(v_id);
  end loop;
end
$$;
insert into res select 'care plans loop', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
update t0 set t = clock_timestamp();
select better_supabase.get_care_plans((select ids from ids where kind = 'plans')) as plans \gset
insert into res select 'care plans batch', extract(epoch from clock_timestamp() - (select t from t0)) * 1000;
select is(
  (select array_agg(p ->> 'id' order by ordinality) from jsonb_array_elements(:'plans'::jsonb) with ordinality t(p, ordinality)),
  (select array_agg(id::text order by o) from unnest((select ids from ids where kind = 'plans')) with ordinality t(id, o)),
  'the batch returns every plan in the order requested'
);
select is(jsonb_array_length(:'plans'::jsonb -> 0 -> 'problems'), 1, 'a plan carries its problems');

select diag('SCALE_MS ' || name || '=' || round(ms, 1)) from res order by name;

-- A member of the other tenant reads none of it, and an empty list reads nothing.
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}', true);

select is(
  better_supabase.list_ai_run_steps_for((select ids from ids where kind = 'runs'), 50)
    || better_supabase.get_versions((select ids from ids where kind = 'versions'))
    || better_supabase.list_applications_for_jobs((select ids from ids where kind = 'jobs'))
    || better_supabase.templates_get_many((select ids from ids where kind = 'templates'))
    || better_supabase.get_care_plans((select ids from ids where kind = 'plans')),
  '[]'::jsonb,
  'the other tenant reads nothing from any batch'
);
select is(better_supabase.get_versions('{}'::uuid[]), '[]'::jsonb, 'an empty list reads nothing');

select * from finish();
rollback;

select pg_stat_statements_reset() is not null as reset \gset
