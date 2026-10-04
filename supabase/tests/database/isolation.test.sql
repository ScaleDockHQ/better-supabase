-- Tenant isolation beyond the tables' own policies: realtime topics, every
-- tenant table read from another tenant, storage objects, the access token
-- hook and the kit functions' grants. A Globex member (tenant …0002) aims at
-- Acme (…0001), whose rows come from supabase/seed.sql.
begin;
select plan(22);

-- The insert broadcasts on the tenant's topic through the realtime-tables trigger.
insert into public.notifications (organization_id, user_id, title)
values ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'For the member');
insert into storage.objects (bucket_id, name)
values ('customer-logos', '00000000-0000-4000-8000-000000000001/00000000-0000-4000-8000-00000000a001/logo/1.webp');

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
set local realtime.topic = 'bs:t:public.notifications:00000000-0000-4000-8000-000000000001';

select is(
  (select count(*)::int from realtime.messages where topic = 'bs:t:public.notifications:00000000-0000-4000-8000-000000000001'),
  1,
  'a member receives their tenant''s topic'
);
select is(
  (select count(*)::int from storage.objects where bucket_id = 'customer-logos'),
  1,
  'a member sees their tenant''s logos'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('customer-logos', '00000000-0000-4000-8000-000000000001/00000000-0000-4000-8000-00000000a001/logo/2.png')$$,
  '42501', null, 'a logo outside the path template is rejected'
);

-- Globex member.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from realtime.messages where topic = 'bs:t:public.notifications:00000000-0000-4000-8000-000000000001'),
  0,
  'another tenant''s member does not receive the topic'
);

select is_empty(
  $$select id from public.organizations where id = '00000000-0000-4000-8000-000000000001'$$,
  'another tenant''s member cannot read the organization'
);
select is_empty(
  format('select 1 from public.%I where organization_id = %L', t, '00000000-0000-4000-8000-000000000001'),
  format('another tenant''s member cannot read public.%s', t)
)
from unnest(array['contacts', 'customers', 'locations', 'tags', 'customer_tags', 'notes', 'notifications']) as t;

select is_empty(
  $$select id from storage.objects where bucket_id = 'customer-logos'$$,
  'another tenant''s member cannot list the logos'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name)
    values ('customer-logos', '00000000-0000-4000-8000-000000000001/00000000-0000-4000-8000-00000000a001/logo/3.webp')$$,
  '42501', null, 'another tenant''s member cannot upload into the tenant''s folder'
);

-- The access token hook.
reset role;

select is(
  rbac.custom_access_token_hook(
    '{"user_id":"00000000-0000-4000-8000-0000000000a1","claims":{"sub":"00000000-0000-4000-8000-0000000000a1"}}'
  ) -> 'claims' ->> 'user_role',
  'admin',
  'the hook adds the user''s role'
);
select ok(
  not (rbac.custom_access_token_hook(
    '{"user_id":"00000000-0000-4000-8000-0000000000ff","claims":{"sub":"00000000-0000-4000-8000-0000000000ff"}}'
  ) -> 'claims' ? 'user_role'),
  'the hook adds no role for a user without one'
);

select ok(
  not has_function_privilege('authenticated', 'rbac.custom_access_token_hook(jsonb)', 'execute'),
  'authenticated cannot call the hook'
);

-- Kit function grants.
select ok(
  not has_function_privilege('authenticated', f, 'execute'),
  format('authenticated cannot call %s', f)
)
from unnest(array[
  'better_supabase.set_rate_limit(text, integer, interval, text)',
  'better_supabase.purge_rate_limits(integer)',
  'better_supabase.track_updated_at(regclass, text, boolean)'
]) as f;
select ok(
  has_function_privilege('anon', 'better_supabase.check_request()', 'execute'),
  'anon can run the pre-request hook'
);
select ok(
  not has_function_privilege('anon', 'public.search_notes(extensions.vector, integer)', 'execute'),
  'anon cannot search notes'
);

select * from finish();
rollback;
