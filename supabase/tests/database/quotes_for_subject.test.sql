-- list_quotes_for_subject (ADR 0822): the quotes that name a record as their
-- company, newest first, for one organization. A caller without read access to
-- the organization is refused. Run with `supabase test db`.
begin;
select plan(4);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
insert into better_supabase.companies (id, tenant_id, name, lifecycle)
values ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-000000000001', 'Subject Co', 'lead');
insert into better_supabase.deals (tenant_id, number, identifier, name, amount, currency, expected_close_on, company_type, company_id)
values ('00000000-0000-4000-8000-000000000001', 9202, 'FS-2', 'Subject deal', 1000, 'EUR', current_date, 'company', '00000000-0000-4000-8000-0000000000c1');
create temporary table picked on commit drop as
select 'company'::text as type, '00000000-0000-4000-8000-0000000000c1'::text as id;
select better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Fit-out', 'currency', 'EUR', 'company', jsonb_build_object('type', 'company', 'id', '00000000-0000-4000-8000-0000000000c1')),
  null
);

select is(
  (select jsonb_array_length(better_supabase.list_quotes_for_subject(
    '00000000-0000-4000-8000-000000000001', (select type from picked), (select id from picked)))),
  1,
  'the quote shows for the company it names'
);
select is(
  better_supabase.list_quotes_for_subject(
    '00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-0000000000ff'),
  '[]'::jsonb,
  'an unrelated record has no quotes'
);
select is(
  better_supabase.list_quotes_for_subject(
    '00000000-0000-4000-8000-0000000000aa', (select type from picked), (select id from picked)),
  '[]'::jsonb,
  'another organization sees none of them'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e9","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select better_supabase.list_quotes_for_subject('00000000-0000-4000-8000-000000000001', 'company', 'x') $$,
  '42501',
  null,
  'a caller without read access is refused'
);

select * from finish();
rollback;
