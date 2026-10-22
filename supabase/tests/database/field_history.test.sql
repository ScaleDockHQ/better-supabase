-- Field history: the old and new values of a deal's and a company's watched
-- columns on update. Acme (…0001) has the owner …a1 and the member …a2;
-- Globex (…0002) has the owner …a3 (supabase/seed.sql).
begin;
select plan(13);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into ids values ('deal', gen_random_uuid()), ('company', gen_random_uuid());
insert into better_supabase.deals (id, tenant_id, number, identifier, name, amount, currency, expected_close_on) values
  ((select id from ids where name = 'deal'), '00000000-0000-4000-8000-000000000001', 9101, 'FH-1', 'History deal', 1000, 'EUR', '2026-02-01');
insert into better_supabase.companies (id, tenant_id, name, lifecycle) values
  ((select id from ids where name = 'company'), '00000000-0000-4000-8000-000000000001', 'History Co', 'lead');

select is(
  (select count(*)::integer from better_supabase.field_changes),
  0,
  'an insert keeps no history'
);

-- Acme owner edits the deal.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
update better_supabase.deals set amount = 1500 where id = (select id from ids where name = 'deal');
update better_supabase.deals set name = 'Renamed deal' where id = (select id from ids where name = 'deal');
update better_supabase.deals set amount = 1500 where id = (select id from ids where name = 'deal');
update better_supabase.deals set expected_close_on = '2026-03-01', owner_user_id = '00000000-0000-4000-8000-0000000000a2'
where id = (select id from ids where name = 'deal');
update better_supabase.companies set lifecycle = 'customer' where id = (select id from ids where name = 'company');

select is(
  (select count(*)::integer from better_supabase.field_changes where subject_type = 'deal'),
  3,
  'a watched column keeps a change; an unwatched or unchanged one keeps none'
);
select is(
  (select old_value from better_supabase.field_changes where field = 'amount'),
  '1000'::jsonb,
  'the change keeps the old value'
);
select is(
  (select changed_by from better_supabase.field_changes where field = 'amount'),
  '00000000-0000-4000-8000-0000000000a1'::uuid,
  'the change names who made it'
);
select is(
  (select new_value from better_supabase.field_changes where subject_type = 'company'),
  '"customer"'::jsonb,
  'a company''s lifecycle change is kept'
);

set local role authenticated;

select is(
  jsonb_array_length(api.field_history('deal', (select id from ids where name = 'deal')::text)),
  3,
  'the owner reads the deal''s history'
);
select is(
  api.field_history('deal', (select id from ids where name = 'deal')::text, 'amount') -> 0 ->> 'field',
  'amount',
  'the history filters by field'
);
select is(
  jsonb_array_length(api.field_history(
    'deal',
    (select id from ids where name = 'deal')::text,
    null,
    (api.field_history('deal', (select id from ids where name = 'deal')::text, null, null, 1) -> 0 ->> 'id')::bigint
  )),
  2,
  'before pages past the newest change'
);
select throws_ok(
  $$insert into better_supabase.field_changes (tenant_id, subject_type, subject_id, field) values ('00000000-0000-4000-8000-000000000001', 'deal', 'x', 'amount')$$,
  '42501',
  null,
  'members cannot write history'
);

-- Acme member reads it too.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.field_history('company', (select id from ids where name = 'company')::text)),
  1,
  'a member with history.read reads a company''s history'
);
select is(
  (select count(*)::integer from better_supabase.field_changes),
  4,
  'a member reads the history rows through row level security'
);

-- Globex owner sees none of it.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  api.field_history('deal', (select id from ids where name = 'deal')::text),
  '[]'::jsonb,
  'another organization reads none of the history'
);
select is(
  (select count(*)::integer from better_supabase.field_changes),
  0,
  'another organization selects none of the rows'
);

select * from finish();
rollback;
