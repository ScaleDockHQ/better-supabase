-- list_risks_for_subject (ADR 0822): the open risks that have a relation to a
-- record, for one organization. A caller without risks.read is refused and
-- another organization sees none. Run with `supabase test db`.
begin;
select plan(5);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
create temporary table ids (name text primary key, id uuid) on commit drop;
grant select on ids to public;
insert into ids values
  ('linked', (better_supabase.create_risk('00000000-0000-4000-8000-000000000001', '{"title":"Solvent spill","category":"environment"}') ->> 'id')::uuid),
  ('other', (better_supabase.create_risk('00000000-0000-4000-8000-000000000001', '{"title":"Fire","category":"safety"}') ->> 'id')::uuid);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
insert into better_supabase.relations (tenant_id, kind, source_type, source_id, target_type, target_id)
select '00000000-0000-4000-8000-000000000001', 'about', 'risk', id::text, 'project', 'p1' from ids where name = 'linked';

select is(
  (select jsonb_agg(x ->> 'title') from jsonb_array_elements(better_supabase.list_risks_for_subject(
    '00000000-0000-4000-8000-000000000001', 'project', 'p1')) x),
  '["Solvent spill"]'::jsonb,
  'the risk linked to the record shows, the unlinked one does not'
);
select is(
  better_supabase.list_risks_for_subject('00000000-0000-4000-8000-000000000001', 'project', 'p2'),
  '[]'::jsonb,
  'an unrelated record has no risks'
);
select is(
  better_supabase.list_risks_for_subject('00000000-0000-4000-8000-0000000000aa', 'project', 'p1'),
  '[]'::jsonb,
  'another organization sees none of them'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e9","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select better_supabase.list_risks_for_subject('00000000-0000-4000-8000-000000000001', 'project', 'p1') $$,
  '42501',
  null,
  'a caller without risks.read is refused'
);
select is((select count(*) from ids), 2::bigint, 'both risks were created');

select * from finish();
rollback;
