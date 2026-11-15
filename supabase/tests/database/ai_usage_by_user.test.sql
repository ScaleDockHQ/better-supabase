-- Spend per user: ai_runs is readable by its owner only, so
-- ai_usage_by_user is the one read across an organization, for members that
-- hold ai_chat.manage. Acme (…0001) has the owner …a1 and the member …a2;
-- …a3 belongs to Globex only (supabase/seed.sql).
begin;
select plan(9);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'chat', (api.create_ai_chat(
  '00000000-0000-4000-8000-000000000001',
  '{"title":"Plans","visibility":"private"}'
) ->> 'id')::uuid;

reset role;
insert into better_supabase.ai_runs (chat_id, owner_id, model, status, usage, cost_micro_usd, started_at)
select (select id from ids where name = 'chat'), owner_id, 'openai/gpt-5', status, usage::jsonb, cost, started_at
from (values
  ('00000000-0000-4000-8000-0000000000a1'::uuid, 'completed', '{"inputTokens":100,"outputTokens":20,"cachedInputTokens":40}', 3000::bigint, now() - interval '1 day'),
  ('00000000-0000-4000-8000-0000000000a1'::uuid, 'failed', '{"inputTokens":"many"}', null::bigint, now() - interval '2 days'),
  ('00000000-0000-4000-8000-0000000000a2'::uuid, 'completed', '{"inputTokens":10,"outputTokens":5}', 500::bigint, now() - interval '10 days')
) as r (owner_id, status, usage, cost, started_at);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.ai_usage_by_user('00000000-0000-4000-8000-000000000001')),
  2,
  'a manager sees one row per user'
);

select is(
  api.ai_usage_by_user('00000000-0000-4000-8000-000000000001') -> 0 ->> 'user_id',
  '00000000-0000-4000-8000-0000000000a1',
  'the most expensive user comes first'
);

select is(
  (api.ai_usage_by_user('00000000-0000-4000-8000-000000000001') -> 0)
    - 'last_run_at' - 'user_id',
  '{"runs":2,"failed":1,"input_tokens":100,"output_tokens":20,"cached_input_tokens":40,"cost_micro_usd":3000}'::jsonb,
  'tokens and cost add up, and a usage key that is not a number counts as zero'
);

select is(
  jsonb_array_length(api.ai_usage_by_user(
    '00000000-0000-4000-8000-000000000001',
    now() - interval '5 days'
  )),
  1,
  'since leaves out older runs'
);

select is(
  jsonb_array_length(api.ai_usage_by_user(
    '00000000-0000-4000-8000-000000000001',
    null,
    now() - interval '5 days'
  )),
  1,
  'until leaves out newer runs'
);

select is(
  jsonb_array_length(api.ai_usage_by_user('00000000-0000-4000-8000-000000000001', null, null, 1)),
  1,
  'size caps the rows'
);

-- A member without ai_chat.manage.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.ai_usage_by_user('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'a member without ai_chat.manage may not read usage'
);

-- A member of another organization.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.ai_usage_by_user('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  null,
  'another organization may not read usage'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  jsonb_array_length(api.ai_usage_by_user('00000000-0000-4000-8000-000000000001')),
  2,
  'the service role reads any organization'
);

select * from finish();
rollback;
