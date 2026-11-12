begin;
select plan(16);

delete from better_supabase.notification_recipients where user_id = '00000000-0000-4000-8000-0000000000a1';

update better_supabase.profiles set first_name = 'Zelda', last_name = 'Quarry'
where id = '00000000-0000-4000-8000-0000000000a2';

with e as (
  insert into better_supabase.notification_events (id, tenant_id, type, actor_id, subject_type, subject_id, subject_label, summary, created_at)
  values
    ('10000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000001', 'task.assigned', '00000000-0000-4000-8000-0000000000a2', 'task', 't1', 'beta', 'One', now() - interval '4 minutes'),
    ('10000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000001', 'approval.requested', null, 'approval', 'a1', 'Alpha', 'Two', now() - interval '3 minutes'),
    ('10000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000001', 'approval.requested', null, 'approval', 'a2', 'gamma', 'Three', now() - interval '2 minutes'),
    ('10000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000001', 'comment.added', null, 'task', 't2', 'delta', 'Four', now() - interval '1 minute')
  returning id, tenant_id, created_at
)
insert into better_supabase.notification_recipients (id, event_id, tenant_id, user_id, read_at, resolved_at, created_at)
select ('20000000-0000-4000-8000-00000000000' || right(id::text, 1))::uuid, id, tenant_id, '00000000-0000-4000-8000-0000000000a1',
  case right(id::text, 1) when '1' then created_at when '3' then created_at end,
  case right(id::text, 1) when '3' then created_at end,
  created_at
from e;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create function pg_temp.summaries(page jsonb) returns text language sql as
$$ select string_agg(x ->> 'summary', ',' order by o) from jsonb_array_elements(page -> 'items') with ordinality t(x, o) $$;

select is(pg_temp.summaries(better_supabase.notification_page()), 'Four,Three,Two,One', 'newest is the default order');
select is(pg_temp.summaries(better_supabase.notification_page(order_by => 'oldest')), 'One,Two,Three,Four', 'oldest pages from the first');
select is(pg_temp.summaries(better_supabase.notification_page(order_by => 'type')), 'Three,Two,Four,One', 'type sorts by type, then newest');
select is(pg_temp.summaries(better_supabase.notification_page(order_by => 'type_desc')), 'One,Four,Three,Two', 'type_desc reverses the type only');
select is(pg_temp.summaries(better_supabase.notification_page(order_by => 'subject')), 'Two,One,Four,Three', 'subject sorts by the lowercased label');
select is(pg_temp.summaries(better_supabase.notification_page(order_by => 'status')), 'Four,Two,One,Three', 'status sorts unread, read, then resolved');
select is(pg_temp.summaries(better_supabase.notification_page(order_by => 'status', max_items => 2, skip => 2)), 'One,Three', 'another order pages with skip');
select is(pg_temp.summaries(better_supabase.notification_page(exclude_types => array['approval.requested'])), 'Four,One', 'exclude_types leaves those types out');
select is(pg_temp.summaries(better_supabase.notification_page(subject_ids => array['t1', 'a2'])), 'Three,One', 'subject_ids keeps those subjects');
select is(
  pg_temp.summaries(better_supabase.notification_page(any_of => '[{"exclude_types": ["approval.requested"]}, {"resolved": true}]')),
  'Four,Three,One', 'any_of matches either group');
select is(pg_temp.summaries(better_supabase.notification_page(any_of => '[]')), null, 'an empty any_of matches nothing');
select is(pg_temp.summaries(better_supabase.notification_page(search => 'zelda quarry')), 'One', 'search matches the actor name');
select is((better_supabase.notification_page(max_items => 900) ->> 'limit')::int, 500, 'the page reports the limit it applied');
select throws_ok($$ select better_supabase.notification_page(order_by => 'sideways') $$, '22023', null, 'an unknown order is rejected');
select throws_ok($$ select better_supabase.notification_page(order_by => 'oldest', before => now()) $$, '22023', null, 'before pages only the newest order');
select throws_ok($$ select better_supabase.notification_page(any_of => '{"read": true}') $$, '22023', null, 'any_of is an array');

select * from finish();
rollback;
