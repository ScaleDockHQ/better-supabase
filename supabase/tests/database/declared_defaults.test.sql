-- Declared defaults: with no declared rows the seeding functions keep the
-- literal templates they had before declared_defaults existed; a declared row
-- replaces the template for that subject only. Acme (…0001) is in
-- supabase/seed.sql.
begin;
select plan(9);

set local role service_role;

select is(
  better_supabase.declared_defaults_of('pipeline_stage', 'work_item'),
  null::jsonb,
  'nothing declared: the lookup is null, not an empty list'
);

select is(
  better_supabase.declared_defaults_of('option_set_item', 'work_item.priority'),
  null::jsonb,
  'nothing declared for the option set either'
);

select better_supabase.default_pipeline('00000000-0000-4000-8000-000000000001', 'work_item', 'no-declaration');

select results_eq(
  $$select s.key, s.name, s.category, s.outcome, s.rank collate "default"
    from better_supabase.pipeline_stages s
    join better_supabase.pipelines p on p.id = s.pipeline_id
    where p.scope_id = 'no-declaration'
    order by s.rank collate "C"$$,
  $$values
    ('triage', 'Triage', 'triage', 'open', '7'),
    ('backlog', 'Backlog', 'backlog', 'open', 'E'),
    ('todo', 'Todo', 'unstarted', 'open', 'L'),
    ('in_progress', 'In progress', 'started', 'open', 'S'),
    ('in_review', 'In review', 'started', 'open', 'Z'),
    ('done', 'Done', 'completed', 'success', 'g'),
    ('canceled', 'Canceled', 'canceled', 'failure', 'n')$$,
  'no declaration: the default pipeline has the literal work_item stages and ranks'
);

select better_supabase.default_option_set('00000000-0000-4000-8000-000000000001', 'work_item', 'priority', 'no-declaration');

select ok(
  (select count(*) from better_supabase.option_set_items i
   join better_supabase.option_sets s on s.id = i.option_set_id
   where s.scope_id = 'no-declaration' and s.subject_type = 'work_item' and s.field = 'priority') > 0,
  'no declaration: the default option set has its literal items'
);

-- A declaration for one subject changes that subject and nothing else.
reset role;
insert into better_supabase.declared_defaults (kind, subject, key, position, value) values
  ('pipeline_stage', 'work_item', 'open', 0, '{"key":"open","name":"Open","category":"started"}'),
  ('pipeline_stage', 'work_item', 'shut', 1, '{"key":"shut","name":"Shut","category":"completed"}');
set local role service_role;

select is(
  jsonb_array_length(better_supabase.declared_defaults_of('pipeline_stage', 'work_item')),
  2,
  'declared rows come back as a list'
);

select better_supabase.default_pipeline('00000000-0000-4000-8000-000000000001', 'work_item', 'declared');

select results_eq(
  $$select s.key from better_supabase.pipeline_stages s
    join better_supabase.pipelines p on p.id = s.pipeline_id
    where p.scope_id = 'declared'
    order by s.rank collate "C"$$,
  $$values ('open'), ('shut')$$,
  'a declaration replaces the literal stages, in declared order'
);

select is(
  (select count(*)::int from better_supabase.pipeline_stages s
   join better_supabase.pipelines p on p.id = s.pipeline_id
   where p.scope_id = 'no-declaration'),
  7,
  'the pipeline seeded before the declaration is unchanged'
);

select is(
  better_supabase.declared_defaults_of('option_set_item', 'work_item.priority'),
  null::jsonb,
  'a pipeline declaration leaves the option set lookup null'
);

select is(
  better_supabase.declared_defaults_of('pipeline_stage', 'deal'),
  null::jsonb,
  'another subject stays null'
);

select * from finish();
rollback;
