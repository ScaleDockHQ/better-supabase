-- Today's open items of an organization with 5,000 open invoices over 50
-- parties (ADR 1214). The stored read takes the maintained table; a past or
-- future as_of replays invoices and ledger entries. Both answer the same
-- balances; the times go to SCALE_MS diag lines.
begin;
select plan(3);

insert into better_supabase.companies (tenant_id, name, lifecycle)
select '00000000-0000-4000-8000-000000000001', 'Scale open items ' || p, 'customer' from generate_series(1, 50) p;

insert into better_supabase.invoices (tenant_id, title, currency, status, number, identifier, total, issued_on, due_on, company_type, company_id)
select '00000000-0000-4000-8000-000000000001', 'Scale open item ' || g, 'EUR', 'issued', 900000 + g, 'SCALE-' || g, 1000 + g,
  current_date - (g % 120), current_date - (g % 120) + 30, 'company',
  (select id from better_supabase.companies where name = 'Scale open items ' || (1 + g % 50))
from generate_series(1, 5000) g;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

create temp table marks (name text, t timestamptz, n int, total numeric);
insert into marks values ('start', clock_timestamp(), null, null);
insert into marks select 'stored', clock_timestamp(), jsonb_array_length(r),
  (select sum((i ->> 'balance')::bigint) from jsonb_array_elements(r) i)
from (select better_supabase.open_items_for_party('00000000-0000-4000-8000-000000000001') r) x;
insert into marks values ('stored_done', clock_timestamp(), null, null);
insert into marks select 'fold', clock_timestamp(), jsonb_array_length(r),
  (select sum((i ->> 'balance')::bigint) from jsonb_array_elements(r) i where i ->> 'documentId' in (
    select id::text from better_supabase.invoices where title like 'Scale open item %'))
from (select better_supabase.open_items_for_party('00000000-0000-4000-8000-000000000001', null, current_date + 1) r) x;
insert into marks values ('fold_done', clock_timestamp(), null, null);
select set_config('bsb.party', (select id::text from better_supabase.companies where name = 'Scale open items 7'), true);
insert into marks select 'party_stored', clock_timestamp(), jsonb_array_length(
  better_supabase.open_items_for_party('00000000-0000-4000-8000-000000000001', current_setting('bsb.party'))), null;
insert into marks select 'party_fold', clock_timestamp(), jsonb_array_length(
  better_supabase.open_items_for_party('00000000-0000-4000-8000-000000000001', current_setting('bsb.party'), current_date + 1)), null;
insert into marks values ('party_done', clock_timestamp(), null, null);

select ok((select n from marks where name = 'stored') >= 5000, 'the stored read returns every open invoice');
select is(
  (select total from marks where name = 'fold'),
  (select sum(1000 + g)::numeric from generate_series(1, 5000) g),
  'the fold answers the same balances'
);
select is(better_supabase.open_items_drift('00000000-0000-4000-8000-000000000001'), '[]'::jsonb, 'and drift is empty');

select diag('SCALE_MS open_items_stored_5000=' || round(extract(epoch from
  (select t from marks where name = 'stored_done') - (select t from marks where name = 'start')) * 1000));
select diag('SCALE_MS open_items_fold_5000=' || round(extract(epoch from
  (select t from marks where name = 'fold_done') - (select t from marks where name = 'stored_done')) * 1000));
select diag('SCALE_MS open_items_party_stored_100=' || round(extract(epoch from
  (select t from marks where name = 'party_fold') - (select t from marks where name = 'party_stored')) * 1000, 1));
select diag('SCALE_MS open_items_party_fold_100=' || round(extract(epoch from
  (select t from marks where name = 'party_done') - (select t from marks where name = 'party_fold')) * 1000, 1));

select * from finish();
rollback;
