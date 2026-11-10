-- The hot reads of the examples on the scale fixture: the inbox page, the
-- notification counts, the task board, the customer list and the islands
-- bootstrap (ADR 0652). Each read prints SCALE_MS, and the EXPLAIN baselines in
-- the ADR come from the same data. Set bsb.scale_rows to resize (default 20,000).
begin;
select plan(14);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '20000'), true);

-- Triggers (the inbox broadcast, the audit trail) would make the seed the slow part.
set local session_replication_role = replica;

insert into better_supabase.inboxes (id, tenant_id, name)
values ('00000000-0000-4000-8000-0000000fb001', '00000000-0000-4000-8000-000000000001', 'Scale inbox');

insert into better_supabase.people (id, tenant_id, name, email, lifecycle)
select gen_random_uuid(), '00000000-0000-4000-8000-000000000001', 'Scale person ' || g,
  'scale' || g || '@example.test', 'customer'
from generate_series(1, 2000) g;

with c as (
  select gen_random_uuid() as id, g,
    (select array_agg(id order by id) from (select id from better_supabase.people where name like 'Scale person %' limit 2000) x) as p
  from generate_series(1, current_setting('bsb.n')::int) g
), core as (
  insert into better_supabase.conversations (id, tenant_id, kind, access, last_message_at)
  select id, '00000000-0000-4000-8000-000000000001', 'inbox', 'tenant', now() + interval '1 day' - (g || ' minutes')::interval from c
)
insert into better_supabase.inbox_conversations
  (id, tenant_id, inbox_id, contact_id, subject, status, assignee_id, last_message_at, last_message_preview)
select id, '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000fb001',
  p[1 + g % 2000], 'Scale subject ' || g, case when g % 10 = 0 then 'resolved' else 'open' end,
  case when g % 3 = 0 then '00000000-0000-4000-8000-0000000000a1'::uuid end,
  now() + interval '1 day' - (g || ' minutes')::interval, 'Preview ' || g
from c;

insert into better_supabase.conversation_members (conversation_id, tenant_id, user_id, last_read_at)
select id, tenant_id, '00000000-0000-4000-8000-0000000000a1', now() - interval '3 hours'
from better_supabase.inbox_conversations
where inbox_id = '00000000-0000-4000-8000-0000000fb001' and id::text < '8';

with e as (
  insert into better_supabase.notification_events (id, tenant_id, type, summary, created_at)
  select gen_random_uuid(), '00000000-0000-4000-8000-000000000001', 'scale.type_' || (g % 4),
    'Scale ' || g, now() - (g || ' minutes')::interval
  from generate_series(1, current_setting('bsb.n')::int) g
  returning id, tenant_id, created_at
)
insert into better_supabase.notification_recipients (event_id, tenant_id, user_id, read_at, created_at)
select id, tenant_id, '00000000-0000-4000-8000-0000000000a1',
  case when abs(hashtext(id::text)) % 10 = 0 then null else created_at end, created_at
from e;

insert into public.customers (organization_id, name, created_at)
select '00000000-0000-4000-8000-000000000001', 'Scale customer ' || g, now() - (g || ' seconds')::interval
from generate_series(1, current_setting('bsb.n')::int) g;

insert into public.tasks (organization_id, project_id, title, rank)
select '00000000-0000-4000-8000-000000000001', gen_random_uuid(), 'Scale task ' || g, lpad(g::text, 8, '0')
from generate_series(1, current_setting('bsb.n')::int) g;

set local session_replication_role = origin;
analyze better_supabase.inbox_conversations;
analyze better_supabase.conversation_members;
analyze better_supabase.notification_recipients;
analyze public.customers;
analyze public.tasks;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

-- The inbox page.
select better_supabase.list_inbox_conversations(
  '00000000-0000-4000-8000-000000000001', '{"limit":50}') as page \gset
select diag('SCALE_MS list_inbox_conversations=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select is(jsonb_array_length(:'page'::jsonb), 50, 'the inbox page has 50 conversations');
select is(
  (select jsonb_agg(x ->> 'subject' order by ord) from jsonb_array_elements(:'page'::jsonb) with ordinality as e(x, ord) where ord <= 3),
  '["Scale subject 1", "Scale subject 2", "Scale subject 3"]'::jsonb,
  'the page runs newest first');
select ok(
  (:'page'::jsonb -> 0 -> 'contact' ->> 'email') like 'scale%@example.test'
    and (:'page'::jsonb -> 0 -> 'inbox' ->> 'name') = 'Scale inbox'
    and (:'page'::jsonb -> 0) ? 'last_read_at' and (:'page'::jsonb -> 0) ? 'contact_read_at',
  'each conversation carries its contact, inbox and read times');
select is(
  (select count(*)::int from jsonb_array_elements(:'page'::jsonb) x where (x ->> 'unread')::boolean),
  (select count(*)::int from jsonb_array_elements(:'page'::jsonb) x
    where (x ->> 'last_read_at') is null or (x ->> 'last_message_at')::timestamptz > (x ->> 'last_read_at')::timestamptz),
  'unread follows the caller''s last read time');

update t0 set t = clock_timestamp();
select better_supabase.list_inbox_conversations(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('limit', 20, 'before', (:'page'::jsonb -> 49) - 'contact' - 'inbox'
    || jsonb_build_object('last_message_at', :'page'::jsonb -> 49 -> 'last_message_at'))) as next \gset
select diag('SCALE_MS list_inbox_conversations_next=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select is(:'next'::jsonb -> 0 ->> 'subject', 'Scale subject 56', 'the keyset page continues after the last item');

update t0 set t = clock_timestamp();
select better_supabase.list_inbox_conversations(
  '00000000-0000-4000-8000-000000000001', '{"search":"scale42@example","status":"all"}') as found \gset
select diag('SCALE_MS list_inbox_conversations_search=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select ok(jsonb_array_length(:'found'::jsonb) > 0, 'a search matches the contact email');

update t0 set t = clock_timestamp();
select better_supabase.inbox_counts('00000000-0000-4000-8000-000000000001') as counts \gset
select diag('SCALE_MS inbox_counts=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select ok((:'counts'::jsonb ->> 'open')::int > 0, 'the open count reads the tenant');

-- The notification badge.
update t0 set t = clock_timestamp();
select better_supabase.notification_counts() as ncounts \gset
select diag('SCALE_MS notification_counts=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select is((:'ncounts'::jsonb ->> 'unread')::int, 100, 'the unread badge stops at its cap');

-- The task board and the customer list.
update t0 set t = clock_timestamp();
select count(*)::int as n from (
  select id from public.tasks where organization_id = '00000000-0000-4000-8000-000000000001' order by rank limit 50) t \gset
select diag('SCALE_MS tasks_first_page=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select is(:n, 50, 'the task board reads a page in rank order');

update t0 set t = clock_timestamp();
select count(*)::int as n from (
  select id from public.customers
  where organization_id = '00000000-0000-4000-8000-000000000001' and archived_at is null
  order by created_at desc limit 50) c \gset
select diag('SCALE_MS customers_newest_page=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select is(:n, 50, 'the customer list reads the newest page');

update t0 set t = clock_timestamp();
select count(*)::int as n from (
  select id from public.customers
  where organization_id = '00000000-0000-4000-8000-000000000001' order by name limit 50) c \gset
select diag('SCALE_MS customers_by_name_page=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select is(:n, 50, 'the customer list reads a page in name order');

-- The islands bootstrap.
update t0 set t = clock_timestamp();
select public.island_counts('{"tenant":"00000000-0000-4000-8000-000000000001"}') as islands \gset
select diag('SCALE_MS island_counts=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000, 1));
select is((:'islands'::jsonb ->> 'customers')::int, least(current_setting('bsb.n')::int, 10000), 'the customer count stops at its cap');
select is((:'islands'::jsonb ->> 'tasks')::int, least(current_setting('bsb.n')::int, 10000), 'the task count stops at its cap');
select ok(
  (select bool_and(provolatile = 's') from pg_proc
   where oid in ('better_supabase.list_inbox_conversations(uuid, jsonb)'::regprocedure, 'better_supabase.inbox_counts(uuid)'::regprocedure,
     'better_supabase.notification_counts(uuid, text[], integer)'::regprocedure)),
  'the inbox and notification read functions are marked stable');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
