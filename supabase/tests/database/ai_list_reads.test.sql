-- The list reads of prompts, ai-evals and ai-guardrails: one tenant's rows
-- only, in key order, in pages, and closed to every role but the service role.
-- Acme is …0001 and Globex …0002 (supabase/seed.sql).
begin;
select plan(14);

insert into better_supabase.prompt_versions (tenant_id, name, version, template) values
  ('00000000-0000-4000-8000-000000000001', 'alpha', 1, 'a1'),
  ('00000000-0000-4000-8000-000000000001', 'alpha', 2, 'a2'),
  ('00000000-0000-4000-8000-000000000001', 'beta', 1, 'b1'),
  ('00000000-0000-4000-8000-000000000001', 'gamma', 1, 'g1'),
  ('00000000-0000-4000-8000-000000000002', 'globex-only', 1, 'x'),
  (null, 'system-only', 1, 's');
insert into better_supabase.prompt_labels (tenant_id, name, label, version) values
  ('00000000-0000-4000-8000-000000000001', 'alpha', 'production', 2),
  ('00000000-0000-4000-8000-000000000001', 'alpha', 'staging', 1);

insert into better_supabase.eval_datasets (id, tenant_id, name) values
  ('00000000-0000-4000-8000-00000000e101', '00000000-0000-4000-8000-000000000001', 'acme-a'),
  ('00000000-0000-4000-8000-00000000e102', '00000000-0000-4000-8000-000000000001', 'acme-b'),
  ('00000000-0000-4000-8000-00000000e103', '00000000-0000-4000-8000-000000000002', 'globex-a');
insert into better_supabase.eval_items (dataset_id, input) values
  ('00000000-0000-4000-8000-00000000e101', '"q1"'),
  ('00000000-0000-4000-8000-00000000e101', '"q2"');

insert into better_supabase.guardrail_policies (tenant_id, agent, stage) values
  ('00000000-0000-4000-8000-000000000001', '*', 'input'),
  ('00000000-0000-4000-8000-000000000001', 'sales', 'input'),
  ('00000000-0000-4000-8000-000000000001', 'sales', 'output'),
  ('00000000-0000-4000-8000-000000000002', 'sales', 'input'),
  (null, '*', 'output');

set local role service_role;

select is(
  jsonb_array_length(better_supabase.list_prompts('00000000-0000-4000-8000-000000000001') -> 'items'),
  3,
  'prompts: lists the tenant names and no other tenant'
);

select is(
  (better_supabase.list_prompts('00000000-0000-4000-8000-000000000001') -> 'items' -> 0) - 'updated_at',
  '{"name":"alpha","tenant_id":"00000000-0000-4000-8000-000000000001","latest_version":2,"version_count":2,"labels":{"production":2,"staging":1}}'::jsonb,
  'prompts: reports the latest version, count and labels'
);

select is(
  better_supabase.list_prompts('00000000-0000-4000-8000-000000000001', null, 2),
  jsonb_build_object(
    'items', better_supabase.list_prompts('00000000-0000-4000-8000-000000000001', null, 2) -> 'items',
    'hasMore', true,
    'nextCursor', '["beta"]'::jsonb
  ),
  'prompts: a short page has a cursor'
);

select is(
  better_supabase.list_prompts('00000000-0000-4000-8000-000000000001', 'beta', 2),
  jsonb_build_object(
    'items', better_supabase.list_prompts('00000000-0000-4000-8000-000000000001', 'beta', 2) -> 'items',
    'hasMore', false,
    'nextCursor', null
  ),
  'prompts: the last page has no cursor'
);

select is(
  better_supabase.list_prompts(null) -> 'items' -> 0 ->> 'name',
  'system-only',
  'prompts: a null tenant lists the system prompts'
);

select is(
  jsonb_array_length(better_supabase.list_eval_datasets('00000000-0000-4000-8000-000000000001') -> 'items'),
  2,
  'datasets: lists the tenant datasets only'
);

select is(
  better_supabase.list_eval_datasets('00000000-0000-4000-8000-000000000001') -> 'items' -> 0 ->> 'item_count',
  '2',
  'datasets: counts the items'
);

select is(
  better_supabase.list_eval_datasets('00000000-0000-4000-8000-000000000001', 'acme-a') -> 'items' -> 0 ->> 'name',
  'acme-b',
  'datasets: after skips to the next name'
);

select is(
  jsonb_array_length(better_supabase.list_guardrail_policies('00000000-0000-4000-8000-000000000001') -> 'items'),
  3,
  'policies: lists the tenant policies only'
);

select is(
  better_supabase.list_guardrail_policies('00000000-0000-4000-8000-000000000001', null, null, null, 2) -> 'nextCursor',
  '["sales", "input"]'::jsonb,
  'policies: the cursor holds the agent and the stage'
);

select is(
  (select jsonb_agg(i ->> 'stage') from jsonb_array_elements(
    better_supabase.list_guardrail_policies('00000000-0000-4000-8000-000000000001', null, 'sales', 'input') -> 'items') i),
  '["output"]'::jsonb,
  'policies: after continues past the stage'
);

select is(
  jsonb_array_length(better_supabase.list_guardrail_policies('00000000-0000-4000-8000-000000000001', 'sales') -> 'items'),
  2,
  'policies: filters by agent'
);

reset role;
set local role authenticated;

select throws_ok(
  $$select better_supabase.list_prompts('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'a signed-in user cannot list prompts'
);

select throws_ok(
  $$select better_supabase.list_guardrail_policies('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'a signed-in user cannot list policies'
);

select * from finish();
rollback;
