-- Segments: a saved filter over companies, with materialized members and
-- enter and leave events. Acme (…0001) has the owner …a1 and the member …a2;
-- Globex (…0002) has the owner …a3 (supabase/seed.sql).
begin;
select plan(20);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into better_supabase.automation_fields (subject_type, field_id, label, type, path, column_type, nullable)
values ('company', 'lifecycle', 'Lifecycle', 'select', 'lifecycle', 'text', false),
  ('company', 'archivedAt', 'Archived', 'date', 'archived_at', 'timestamptz', true);

insert into better_supabase.companies (id, tenant_id, name, lifecycle, archived_at) values
  ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-000000000001', 'One', 'customer', null),
  ('00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-000000000001', 'Two', 'customer', null),
  ('00000000-0000-4000-8000-00000000f003', '00000000-0000-4000-8000-000000000001', 'Three', 'lead', null),
  ('00000000-0000-4000-8000-00000000f004', '00000000-0000-4000-8000-000000000001', 'Gone', 'customer', now()),
  ('00000000-0000-4000-8000-00000000f005', '00000000-0000-4000-8000-000000000002', 'Globex client', 'customer', null);

-- Acme member: reads segments, can't change them.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.save_segment('00000000-0000-4000-8000-000000000001', '{"subjectType":"company","name":"Customers",
    "conditions":{"id":"root","type":"group","combinator":"and","rules":[]}}')$$,
  '42501',
  null,
  'a member without segments.write cannot save a segment'
);

-- Acme owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'customers', (api.save_segment('00000000-0000-4000-8000-000000000001', '{"subjectType":"company","name":"Customers",
  "conditions":{"id":"root","type":"group","combinator":"and","rules":[
    {"id":"r1","type":"rule","path":["lifecycle"],"operator":"is","value":"customer"},
    {"id":"r2","type":"rule","path":["archivedAt"],"operator":"empty"}]}}') ->> 'id')::uuid;
insert into ids
select 'leads', (api.save_segment('00000000-0000-4000-8000-000000000001', '{"subjectType":"company","name":"Leads",
  "conditions":{"id":"root","type":"group","combinator":"and","rules":[
    {"id":"r1","type":"rule","path":["lifecycle"],"operator":"is","value":"lead"}]}}') ->> 'id')::uuid;

select is(
  api.segment_get((select id from ids where name = 'customers')) ->> 'memberCount',
  '0',
  'a new segment has no members until it is refreshed'
);
select ok(
  api.segment_get((select id from ids where name = 'customers')) -> 'refreshedAt' = 'null'::jsonb,
  'a new segment is due'
);
select throws_ok(
  $$select api.save_segment('00000000-0000-4000-8000-000000000001', '{"subjectType":"company","name":"Customers",
    "conditions":{"id":"root","type":"group","combinator":"and","rules":[]}}')$$,
  '23505',
  null,
  'two segments in one organization cannot share a name'
);
select throws_ok(
  $$select api.save_segment('00000000-0000-4000-8000-000000000001', '{"subjectType":"planet","name":"Planets",
    "conditions":{"id":"root","type":"group","combinator":"and","rules":[]}}')$$,
  '22023',
  null,
  'a subject type outside config.subjects is refused'
);
select throws_ok(
  $$select api.save_segment('00000000-0000-4000-8000-000000000001', '{"subjectType":"company","name":"Bad",
    "conditions":{"id":"root","type":"group","combinator":"and","rules":[
      {"id":"r1","type":"rule","path":["revenue"],"operator":"gt","value":1}]}}')$$,
  '22023',
  null,
  'a condition on a field the subject type does not have is refused'
);

select is(
  api.refresh_segment((select id from ids where name = 'customers')),
  '{"entered":2,"left":0,"memberCount":2}'::jsonb,
  'a refresh adds the matching unarchived companies of this organization only'
);
select is(
  jsonb_array_length(api.list_segment_members((select id from ids where name = 'customers'))),
  2,
  'the members list shows both companies'
);
select is(
  api.segments_of('company', '00000000-0000-4000-8000-00000000f001') -> 0 ->> 'name',
  'Customers',
  'segments_of names the segments a company is in'
);
select is(
  api.segments_of('company', '00000000-0000-4000-8000-00000000f003'),
  '[]'::jsonb,
  'a company that does not match is in no segment'
);

reset role;
update better_supabase.companies set lifecycle = 'lead'
where id = '00000000-0000-4000-8000-00000000f002';
set local role authenticated;

select is(
  api.refresh_segment((select id from ids where name = 'customers')),
  '{"entered":0,"left":1,"memberCount":1}'::jsonb,
  'a company that stops matching leaves the segment'
);

reset role;
select is(
  (select count(*)::int from better_supabase.outbox_events
   where type = 'segment.entered' and payload ->> 'segmentId' = (select id::text from ids where name = 'customers')),
  2,
  'every company that entered gets a segment.entered event'
);
select is(
  (select payload ->> 'subjectId' from better_supabase.outbox_events
   where type = 'segment.left' and payload ->> 'segmentId' = (select id::text from ids where name = 'customers')),
  '00000000-0000-4000-8000-00000000f002',
  'the company that left gets a segment.left event'
);
select is(
  (select count(*)::int from better_supabase.outbox_events where type in ('segment.created', 'segment.updated')),
  2,
  'saving a segment emits segment.created or segment.updated'
);

-- The member reads what the owner built.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.segments_list('00000000-0000-4000-8000-000000000001', 'company')),
  2,
  'a member lists the organization''s segments'
);
select throws_ok(
  $$select api.refresh_segment((select id from ids where name = 'customers'))$$,
  '42501',
  null,
  'a member without segments.write cannot refresh a segment'
);
select throws_ok(
  $$select better_supabase.evaluate_segment((select id from ids where name = 'customers'))$$,
  '42501',
  null,
  'evaluate_segment is internal'
);

-- Globex owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select api.list_segment_members((select id from ids where name = 'customers'))$$,
  'P0002',
  null,
  'another organization cannot read the members'
);

-- The refresh job.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  api.refresh_due_segments(10, '1 hour'),
  '{"segments":1,"entered":2,"left":0}'::jsonb,
  'the job refreshes the segment that was never refreshed'
);
select is(
  api.remove_segment((select id from ids where name = 'customers')),
  true,
  'the service role removes a segment'
);

select * from finish();
rollback;
