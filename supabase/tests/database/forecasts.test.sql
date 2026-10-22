-- Forecasts: snapshots of the forecast call with the deals they counted, and
-- what moved between two of them. Acme (…0001) has the owner …a1 and the
-- member …a2; Globex (…0002) has the owner …a3 (supabase/seed.sql).
begin;
select plan(20);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into ids values
  ('pipeline', gen_random_uuid()),
  ('commit', gen_random_uuid()),
  ('best', gen_random_uuid()),
  ('later', gen_random_uuid()),
  ('won', gen_random_uuid()),
  ('usd', gen_random_uuid()),
  ('new', gen_random_uuid());
insert into better_supabase.pipelines (id, tenant_id, subject_type, key, name) values
  ((select id from ids where name = 'pipeline'), '00000000-0000-4000-8000-000000000001', 'deal', 'forecast-test', 'Forecast test');
insert into better_supabase.pipeline_stages (tenant_id, pipeline_id, key, name, category, outcome) values
  ('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'pipeline'), 'open', 'Open', 'open', 'open'),
  ('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'pipeline'), 'won', 'Won', 'won', 'success');

-- Closing a deal stamps closed_at with now(), so the period is around today.
create temporary table period on commit drop as
select current_date - 30 as since, current_date + 60 as until;
grant all on period to authenticated, anon, service_role;
insert into better_supabase.deals (id, tenant_id, number, identifier, name, amount, currency, pipeline_id, stage_id, outcome, forecast_category, expected_close_on, closed_at) values
  ((select id from ids where name = 'commit'), '00000000-0000-4000-8000-000000000001', 9001, 'FC-1', 'Commit deal', 1000, 'EUR', (select id from ids where name = 'pipeline'), null, 'open', 'commit', current_date + 10, null),
  ((select id from ids where name = 'best'), '00000000-0000-4000-8000-000000000001', 9002, 'FC-2', 'Best case deal', 500, 'EUR', (select id from ids where name = 'pipeline'), null, 'open', 'best_case', current_date + 20, null),
  ((select id from ids where name = 'later'), '00000000-0000-4000-8000-000000000001', 9003, 'FC-3', 'Later deal', 900, 'EUR', (select id from ids where name = 'pipeline'), null, 'open', 'pipeline', current_date + 200, null),
  ((select id from ids where name = 'won'), '00000000-0000-4000-8000-000000000001', 9004, 'FC-4', 'Won deal', 700, 'EUR', (select id from ids where name = 'pipeline'), (select id from better_supabase.pipeline_stages where key = 'won' and pipeline_id = (select id from ids where name = 'pipeline')), 'won', null, current_date, null),
  ((select id from ids where name = 'usd'), '00000000-0000-4000-8000-000000000001', 9005, 'FC-5', 'Dollar deal', 400, 'USD', (select id from ids where name = 'pipeline'), null, 'open', 'commit', current_date + 10, null);

-- Acme member: reads snapshots, can't take one.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.take_forecast_snapshot('00000000-0000-4000-8000-000000000001', null, current_date, current_date + 30, 'EUR')$$,
  '42501',
  null,
  'a member without forecasts.snapshot cannot take a snapshot'
);

-- Acme owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.take_forecast_snapshot('00000000-0000-4000-8000-000000000001', null, current_date + 1, current_date, 'EUR')$$,
  '22023',
  null,
  'a period that ends before it starts is refused'
);
select throws_ok(
  $$select api.take_forecast_snapshot('00000000-0000-4000-8000-000000000001', null, current_date, current_date + 30, 'euro')$$,
  '22023',
  null,
  'a currency that is not a three-letter code is refused'
);
select throws_ok(
  format($$select api.take_forecast_snapshot('00000000-0000-4000-8000-000000000001', %L, current_date, current_date + 30, 'EUR')$$, gen_random_uuid()),
  'P0002',
  null,
  'an unknown pipeline is refused'
);

insert into ids
select 'first', (api.take_forecast_snapshot('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'pipeline'), (select since from period), (select until from period), 'eur', 2000) ->> 'id')::uuid;

select is(
  (select deal_count from better_supabase.forecast_snapshots where id = (select id from ids where name = 'first')),
  3,
  'the snapshot counts the open deals closing in the period and the deals closed in it'
);
select is(
  (select totals ->> 'commit' from better_supabase.forecast_snapshots where id = (select id from ids where name = 'first')),
  '1000',
  'the snapshot keeps the commit total'
);
select is(
  (select totals ->> 'gap' from better_supabase.forecast_snapshots where id = (select id from ids where name = 'first')),
  '300',
  'the snapshot keeps the gap to the target'
);
select is(
  jsonb_array_length(api.forecast_snapshot((select id from ids where name = 'first')) -> 'deals'),
  3,
  'a snapshot reads with its deals'
);

-- The quarter moves on: the commit deal is won, the best case grows, a new deal opens.
reset role;
update better_supabase.deals set outcome = 'won' where id = (select id from ids where name = 'commit');
update better_supabase.deals set amount = 800 where id = (select id from ids where name = 'best');
insert into better_supabase.deals (id, tenant_id, number, identifier, name, amount, currency, pipeline_id, outcome, forecast_category, expected_close_on) values
  ((select id from ids where name = 'new'), '00000000-0000-4000-8000-000000000001', 9006, 'FC-6', 'New deal', 300, 'EUR', (select id from ids where name = 'pipeline'), 'open', 'pipeline', current_date + 30);
set local role authenticated;

insert into ids
select 'second', (api.take_forecast_snapshot('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'pipeline'), (select since from period), (select until from period), 'EUR', 2000) ->> 'id')::uuid;
insert into ids
select 'dollars', (api.take_forecast_snapshot('00000000-0000-4000-8000-000000000001', null, (select since from period), (select until from period), 'USD') ->> 'id')::uuid;

select is(
  jsonb_array_length(api.forecast_changes((select id from ids where name = 'first'), (select id from ids where name = 'second')) -> 'deals'),
  3,
  'the comparison lists only the deals that moved'
);
select is(
  (select item ->> 'change' from jsonb_array_elements(api.forecast_changes((select id from ids where name = 'first'), (select id from ids where name = 'second')) -> 'deals') item
   where item ->> 'dealId' = (select id from ids where name = 'commit')::text),
  'won',
  'a deal that closed won between the snapshots is won'
);
select is(
  (select item ->> 'change' from jsonb_array_elements(api.forecast_changes((select id from ids where name = 'first'), (select id from ids where name = 'second')) -> 'deals') item
   where item ->> 'dealId' = (select id from ids where name = 'new')::text),
  'added',
  'a deal only the later snapshot counted is added'
);
select is(
  (select item -> 'after' ->> 'amount' from jsonb_array_elements(api.forecast_changes((select id from ids where name = 'first'), (select id from ids where name = 'second')) -> 'deals') item
   where item ->> 'dealId' = (select id from ids where name = 'best')::text),
  '800',
  'a changed deal carries its new amount'
);
select is(
  (select item ->> 'change' from jsonb_array_elements(api.forecast_changes((select id from ids where name = 'second'), (select id from ids where name = 'first')) -> 'deals') item
   where item ->> 'dealId' = (select id from ids where name = 'new')::text),
  'removed',
  'compared the other way round, the new deal is removed'
);
select throws_ok(
  format($$select api.forecast_changes(%L, %L)$$, (select id from ids where name = 'first'), (select id from ids where name = 'dollars')),
  '22023',
  null,
  'snapshots in two currencies are not compared'
);
select is(
  jsonb_array_length(api.forecast_snapshots('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'pipeline'))),
  2,
  'the list filters by pipeline'
);

reset role;
select is(
  (select count(*)::integer from better_supabase.outbox_events where type = 'forecast.snapshotted'),
  3,
  'each snapshot records forecast.snapshotted'
);

-- Acme member reads what the owner took.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.forecast_snapshots('00000000-0000-4000-8000-000000000001')),
  3,
  'a member with forecasts.read lists the snapshots'
);
select is(
  (select count(*)::integer from better_supabase.forecast_snapshot_deals where snapshot_id = (select id from ids where name = 'second')),
  4,
  'a member reads snapshot deals through row level security'
);

-- Globex owner sees none of Acme's snapshots.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select throws_ok(
  format($$select api.forecast_snapshot(%L)$$, (select id from ids where name = 'first')),
  'P0002',
  null,
  'another organization''s snapshot is not found'
);
select is(
  api.forecast_snapshots('00000000-0000-4000-8000-000000000001'),
  '[]'::jsonb,
  'another organization lists none of its snapshots'
);

select * from finish();
rollback;
