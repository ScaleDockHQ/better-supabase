-- ERP import acceptance 5: after numbered documents of two legal entities and
-- two periods are imported, new numbers continue above the imported ones per
-- series, period and legal entity. Run with `supabase test db`.
begin;
select plan(15);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, service_role;

select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp-numbers', '{}'::jsonb) ->> 'id'),
  true
);
insert into ids values ('a', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'NUM-A', 'Numbers A') ->> 'id')::uuid);
insert into ids values ('b', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'NUM-B', 'Numbers B') ->> 'id')::uuid);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

create temporary table scopes (name text primary key, scope text) on commit drop;
grant all on scopes to authenticated, service_role;
insert into scopes
select i.name, better_supabase.number_scope('00000000-0000-4000-8000-000000000001', i.id) from ids i;

select isnt(
  (select scope from scopes where name = 'a'), (select scope from scopes where name = 'b'),
  'the two legal entities keep separate number series'
);

select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);
select better_supabase.begin_import_session(current_setting('bsb.run')::uuid);

-- Imported numbers: cases (a year series) and inspections, two years, two entities.
create temporary table imported (entity text, entity_name text, period date, number text, n bigint) on commit drop;
grant all on imported to authenticated, service_role;
insert into imported
select v.entity, v.name, v.at::date, v.number,
  better_supabase.register_fixed_number('00000000-0000-4000-8000-000000000001', v.entity, v.number, v.at::timestamptz,
    (select scope from scopes where name = v.name))
from (values
  ('case', 'a', '2024-06-01', '2024-0007'),
  ('case', 'a', '2025-02-01', '2025-0003'),
  ('case', 'b', '2024-06-01', '2024-0012'),
  ('case', 'b', '2025-02-01', '2025-0009'),
  ('inspection', 'a', '2024-06-01', 'AUD-2024-005')
) v(entity, name, at, number);

select is(
  (select jsonb_agg(n order by entity, entity_name, period) from imported),
  '[7, 3, 12, 9, 5]'::jsonb,
  'every imported number registers the digits it holds'
);

-- Imported invoices of the two entities, each in its own administration.
select is(
  (select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice', jsonb_build_array(
    jsonb_build_object('key', 'a-40', 'scope', 'A', 'data', jsonb_build_object(
      'number', 'INV-0040', 'status', 'issued', 'issuedOn', '2025-03-01', 'dueOn', '2025-04-01', 'currency', 'EUR',
      'legalEntityId', (select id from ids where name = 'a'),
      'lines', jsonb_build_array(jsonb_build_object('description', 'A work', 'quantity', 1, 'unitAmount', 1000, 'taxRateBps', 0)))),
    jsonb_build_object('key', 'b-07', 'scope', 'B', 'data', jsonb_build_object(
      'number', 'INV-0007', 'status', 'issued', 'issuedOn', '2025-03-01', 'dueOn', '2025-04-01', 'currency', 'EUR',
      'legalEntityId', (select id from ids where name = 'b'),
      'lines', jsonb_build_array(jsonb_build_object('description', 'B work', 'quantity', 1, 'unitAmount', 1000, 'taxRateBps', 0)))))) ->> 'inserted'),
  '2',
  'one invoice per entity imports with the same series'
);

select set_config('better_supabase.import_run', '', true);

-- New numbers continue above the imported ones.
create temporary table nxt (name text primary key, n bigint) on commit drop;
grant all on nxt to authenticated, service_role;

insert into nxt
select v.label, better_supabase.next_number('00000000-0000-4000-8000-000000000001', v.entity, v.at::timestamptz,
  (select scope from scopes where name = v.name))
from (values
  ('case a 2024', 'case', 'a', '2024-12-01'),
  ('case a 2025', 'case', 'a', '2025-03-01'),
  ('case b 2024', 'case', 'b', '2024-12-01'),
  ('case b 2025', 'case', 'b', '2025-03-01'),
  ('case a 2026', 'case', 'a', '2026-01-10'),
  ('case b 2026', 'case', 'b', '2026-01-10'),
  ('inspection a 2024', 'inspection', 'a', '2024-12-01'),
  ('inspection a 2025', 'inspection', 'a', '2025-03-01'),
  ('inspection b 2024', 'inspection', 'b', '2024-12-01')
) v(label, entity, name, at);

select is((select n from nxt where name = 'case a 2024'), 8::bigint, 'entity A continues its 2024 case series above 7');
select is((select n from nxt where name = 'case a 2025'), 4::bigint, 'entity A continues its 2025 case series above 3');
select is((select n from nxt where name = 'case b 2024'), 13::bigint, 'entity B continues its 2024 case series above 12');
select is((select n from nxt where name = 'case b 2025'), 10::bigint, 'entity B continues its 2025 case series above 9');
select is((select n from nxt where name = 'case a 2026'), 1::bigint, 'a new period of entity A starts at 1');
select is((select n from nxt where name = 'case b 2026'), 1::bigint, 'a new period of entity B starts at 1');
select is((select n from nxt where name = 'inspection a 2024'), 6::bigint, 'the inspection series continues apart from the case series');
select is((select n from nxt where name = 'inspection a 2025'), 1::bigint, 'the inspection series of another period starts at 1');
select is((select n from nxt where name = 'inspection b 2024'), 1::bigint, 'the inspection series of the other entity starts at 1');

-- Invoices continue per legal entity above the imported ones.
create temporary table drafts (name text primary key, id uuid) on commit drop;
grant all on drafts to authenticated, service_role;
insert into drafts
select n, (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Next ' || n, 'currency', 'EUR', 'termsDays', 10),
  jsonb_build_array(jsonb_build_object('description', 'Service', 'quantity', 1, 'unitAmount', 1000))) ->> 'id')::uuid
from unnest(array['a', 'b']) n;
update better_supabase.invoices x set legal_entity_id = (select id from ids where name = d.name)
from drafts d where x.id = d.id;

select is(
  (select better_supabase.issue_invoice(id, '2025-06-01') ->> 'identifier' from drafts where name = 'a'),
  'INV-41',
  'entity A issues the next invoice above its imported INV-0040'
);
select is(
  (select better_supabase.issue_invoice(id, '2025-06-01') ->> 'identifier' from drafts where name = 'b'),
  'INV-8',
  'entity B issues the next invoice above its imported INV-0007'
);

-- A sync from the issued rows leaves the counters where they are.
select is(
  (select last_number from better_supabase.number_sequences
   where tenant_id = '00000000-0000-4000-8000-000000000001' and entity = 'case' and scope = (select scope from scopes where name = 'b') and period = '2025'),
  10::bigint,
  'the counter of entity B in 2025 holds the last number handed out'
);

select * from finish();
rollback;
