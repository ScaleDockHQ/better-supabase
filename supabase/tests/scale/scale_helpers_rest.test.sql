-- Memo slots, thread reply rollups, the full messages index and the id tiebreaker on the
-- tenant and created_at indexes (ADR 0639). Set bsb.scale_rows to resize (default 20,000).
begin;
select plan(9);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '20000'), true);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

-- Memo keys: a key per statement or per user grew the session's settings without bound.
select better_supabase.memo_slot_set('scale.key.' || g, 'v' || g) from generate_series(1, 5000) g;
select count(*)::int as slots from pg_settings where name like 'better_supabase.memo.s%' \gset
select ok(:slots <= 256, 'five thousand memo keys occupy at most 256 settings');
select is(better_supabase.memo_slot_get('scale.never'), null, 'a key never stored reads as unset');
select better_supabase.memo_slot_set('scale.mine', 'kept');
select is(better_supabase.memo_slot_get('scale.mine'), 'kept', 'a stored key reads its value back');
select ok(
  (select count(*) from generate_series(1, 5000) g where better_supabase.memo_slot_get('scale.key.' || g) is not null and better_supabase.memo_slot_get('scale.key.' || g) <> 'v' || g) = 0,
  'a slot taken by another key answers unset, never another key''s value'
);

-- Reply rollups: one thread root takes n replies one at a time.
insert into better_supabase.conversations (id, tenant_id, kind, access, title)
values ('00000000-0000-4000-8000-0000000c0001', '00000000-0000-4000-8000-000000000001', 'channel', 'tenant', 'Scale thread');
insert into better_supabase.messages (id, tenant_id, conversation_id, author_id, body, sent_at)
values ('00000000-0000-4000-8000-0000000e0001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000c0001',
  '00000000-0000-4000-8000-0000000000a1', 'root', now() - interval '1 day');

-- A thread of n replies already stored (the rollup trigger is off while the rows go in, then
-- the root is counted once), then 200 replies sent one at a time on top of it.
set constraints all immediate;
alter table better_supabase.messages disable trigger bsb_messaging_message_written;
insert into better_supabase.messages (tenant_id, conversation_id, parent_id, thread_id, author_id, body, sent_at)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000c0001',
  '00000000-0000-4000-8000-0000000e0001', '00000000-0000-4000-8000-0000000e0001',
  ('00000000-0000-4000-8000-0000000000a' || (1 + g % 5))::uuid, 'reply ' || g, now() - interval '1 hour' + g * interval '1 millisecond'
from generate_series(1, current_setting('bsb.n')::int) g;
alter table better_supabase.messages enable trigger bsb_messaging_message_written;
update better_supabase.messages set reply_count = current_setting('bsb.n')::int,
  last_reply_at = (select max(sent_at) from better_supabase.messages where thread_id = '00000000-0000-4000-8000-0000000e0001'),
  reply_user_ids = array['00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-0000000000a3', '00000000-0000-4000-8000-0000000000a4']::uuid[]
where id = '00000000-0000-4000-8000-0000000e0001';
analyze better_supabase.messages;

create temp table t0 as select clock_timestamp() as t;
do $$
begin
  for i in 1..200 loop
    insert into better_supabase.messages (tenant_id, conversation_id, parent_id, thread_id, author_id, body, sent_at)
    values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000c0001',
      '00000000-0000-4000-8000-0000000e0001', '00000000-0000-4000-8000-0000000e0001', '00000000-0000-4000-8000-0000000000a1', 'one ' || i, now() + i * interval '1 second');
  end loop;
end
$$;
select diag('SCALE_MS thread_replies_single_200=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(
  (select reply_count from better_supabase.messages where id = '00000000-0000-4000-8000-0000000e0001'),
  current_setting('bsb.n')::int + 200,
  'the root counts every reply sent'
);
select is(
  (select last_reply_at from better_supabase.messages where id = '00000000-0000-4000-8000-0000000e0001'),
  (select max(sent_at) from better_supabase.messages where thread_id = '00000000-0000-4000-8000-0000000e0001'),
  'the root keeps the newest reply time'
);
select is(
  (select reply_user_ids from better_supabase.messages where id = '00000000-0000-4000-8000-0000000e0001'),
  array(
    select y.u from (
      select x.author_id as u, min(x.sent_at) as first from better_supabase.messages x
      where x.thread_id = '00000000-0000-4000-8000-0000000e0001' and x.sent_at is not null and x.archived_at is null and x.author_id is not null
      group by x.author_id
    ) y order by y.first limit 3
  ),
  'the first three repliers match a full recount'
);

-- The recount a reply paid before the rollup was incremental, on the same thread.
update t0 set t = clock_timestamp();
do $$
begin
  for i in 1..200 loop
    update better_supabase.messages r set
      reply_count = (select count(*) from better_supabase.messages x where x.thread_id = r.id and x.sent_at is not null and x.archived_at is null),
      last_reply_at = (select max(x.sent_at) from better_supabase.messages x where x.thread_id = r.id and x.archived_at is null),
      reply_user_ids = array(
        select y.u from (
          select x.author_id as u, min(x.sent_at) as first from better_supabase.messages x
          where x.thread_id = r.id and x.sent_at is not null and x.archived_at is null and x.author_id is not null
          group by x.author_id
        ) y order by y.first limit 3
      )
    where r.id = '00000000-0000-4000-8000-0000000e0001';
  end loop;
end
$$;
select diag('SCALE_MS thread_rollup_recount_200=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

-- The full index serves reads of a conversation's thread replies, which the partial one skips.
set local enable_seqscan = off;
create temp table plan (line text);
do $$
declare
  r text;
begin
  for r in execute 'explain select 1 from better_supabase.messages where conversation_id = ''00000000-0000-4000-8000-0000000c0001''' loop
    insert into plan values (r);
  end loop;
end
$$;
select ok(exists (select 1 from plan where line like '%messaging_messages_conversation_all_idx%'), 'a read by conversation_id alone uses the full index');

select is(
  (select count(*)::int from pg_indexes
   where schemaname = 'better_supabase' and indexdef ~ '\(tenant_id, created_at DESC, id DESC\)'
     and indexname in ('workflow_runs_tenant_idx', 'work_orders_tenant_idx', 'webhook_deliveries_tenant_created_idx', 'shipments_tenant_idx',
       'posts_tenant_idx', 'passes_tenant_idx', 'moderation_statements_tenant_idx', 'moderation_appeals_tenant_idx',
       'invoice_dunning_runs_tenant_idx', 'expense_reports_tenant_idx', 'commission_plans_tenant_idx', 'ai_moderation_events_tenant_idx',
       'ai_batches_tenant_idx', 'activities_tenant_created_idx', 'access_requests_tenant_idx')),
  15,
  'the tenant and created_at indexes end in the id'
);

select * from finish();
rollback;

select pg_stat_statements_reset() is not null as reset \gset
