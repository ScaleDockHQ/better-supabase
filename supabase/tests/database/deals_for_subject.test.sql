-- list_deals_for_subject (ADR 0822): the deals that name a record as their
-- company or as one of their contacts, for one organization. It runs as the
-- caller, so a caller without read access sees none. Run with `supabase test db`.
begin;
select plan(4);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
create temporary table picked on commit drop as
select id, company_type, company_id::text as company_id
from better_supabase.deals
where company_id is not null and archived_at is null
order by created_at, id
limit 1;
grant select on picked to public;

select ok(
  (select jsonb_array_length(better_supabase.list_deals_for_subject(
    '00000000-0000-4000-8000-000000000001', p.company_type, p.company_id)) >= 1 from picked p),
  'the deals of a company include the one that names it'
);
select is(
  (select better_supabase.list_deals_for_subject(
    '00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-0000000000ff')),
  '[]'::jsonb,
  'an unrelated record has no deals'
);
select is(
  (select better_supabase.list_deals_for_subject(
    '00000000-0000-4000-8000-0000000000aa', p.company_type, p.company_id) from picked p),
  '[]'::jsonb,
  'another organization sees none of them'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e9","role":"authenticated"}', true);
set local role authenticated;
select is(
  (select better_supabase.list_deals_for_subject(
    '00000000-0000-4000-8000-000000000001', p.company_type, p.company_id) from picked p),
  '[]'::jsonb,
  'a caller who cannot read the deals gets none'
);

select * from finish();
rollback;
