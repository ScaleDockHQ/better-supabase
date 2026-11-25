-- The set-based registry read gate (ADR 1232) shows the same funding awards as
-- the 55-branch CASE it replaced. The "oracle" below is the read policy as
-- generated before the change (frozen from pg_get_expr), on a copy of the
-- table. Both tables hold the same rows, one per registry type and tenant, for
-- ids that exist, ids that do not, and a subject of the other tenant, and are
-- read by four roles.
begin;
select plan(14);

create schema oracle_t;
grant usage on schema oracle_t to authenticated;
create table oracle_t.funding_awards (like better_supabase.funding_awards including defaults);
alter table oracle_t.funding_awards enable row level security;
grant select on oracle_t.funding_awards to authenticated;
create policy oracle_read on oracle_t.funding_awards for select to authenticated using (
((tenant_id IN ( SELECT better_supabase.tenant_ids_with('funding.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM customers s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id)))) AND ((tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)) OR better_supabase.is_subject_member('customer'::text, subject_id)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id) AND (((funding_awards.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)) OR better_supabase.is_subject_member('drive_node'::text, funding_awards.subject_id)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM organizations s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.id = funding_awards.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.tenant_id = funding_awards.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM change_requests s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM projects s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM tasks s
      WHERE ((s.id = (funding_awards.subject_id)::uuid) AND (s.organization_id = funding_awards.tenant_id))))
    ELSE COALESCE(better_supabase.can_subject(subject_type, subject_id, 'read'::text), false)
END));

insert into better_supabase.funding_products (id, tenant_id, code, title, unit, rate, currency)
values ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-000000000001', 'EQ-A', 'A', 'hour', 100, 'EUR'),
       ('00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-000000000002', 'EQ-B', 'B', 'hour', 100, 'EUR');

insert into public.customers (id, organization_id, name)
values ('00000000-0000-4000-8000-00000000e002', '00000000-0000-4000-8000-000000000002', 'Globex customer');

create temp table probes (subject_type text, subject_id text, subject_tenant uuid);

do $$
declare
  r record;
  tbl text;
  ids text[];
begin
  for r in
    select distinct m[1] as type, m[2] as tbl
    from regexp_matches(pg_get_expr((select polqual from pg_policy where polrelid = 'oracle_t.funding_awards'::regclass), 'oracle_t.funding_awards'::regclass),
      'WHEN ''(\w+)''::text THEN \(\(EXISTS \( SELECT 1\s+FROM (\S+) s', 'g') as m
  loop
    execute format('select coalesce(array_agg(id::text), ''{}'') from (select id from %s limit 2) q', r.tbl) into ids;
    insert into probes select r.type, unnest(ids), null;
    insert into probes values (r.type, gen_random_uuid()::text, null);
  end loop;
  insert into probes values
    ('customer', '00000000-0000-4000-8000-00000000a001', null),
    ('customer', '00000000-0000-4000-8000-00000000a002', null),
    ('customer', '00000000-0000-4000-8000-00000000e002', null),
    ('customer', gen_random_uuid()::text, null),
    ('unknown_type', gen_random_uuid()::text, null);
end $$;

insert into better_supabase.funding_awards (id, tenant_id, subject_type, subject_id, funder_id, product_id, units, period, starts_on)
select gen_random_uuid(), t.id, p.subject_type, p.subject_id, gen_random_uuid(),
       case when t.id = '00000000-0000-4000-8000-000000000001' then '00000000-0000-4000-8000-00000000f001'::uuid else '00000000-0000-4000-8000-00000000f002'::uuid end,
       1, 'month', current_date
from probes p
cross join (values ('00000000-0000-4000-8000-000000000001'::uuid), ('00000000-0000-4000-8000-000000000002'::uuid)) t(id);

insert into oracle_t.funding_awards select * from better_supabase.funding_awards;

select is(
  (select count(*)::int from (select distinct subject_type, tenant_id from oracle_t.funding_awards) d),
  2 * (select count(distinct subject_type)::int from probes),
  'the fixture holds an award for every type and tenant');
select cmp_ok((select count(distinct subject_type)::int from oracle_t.funding_awards), '>=', 50, 'the fixture covers the registry types');

select cmp_ok(
  (select max(array_length(regexp_split_to_array(qual, 'WHEN '), 1) - 1)::int from pg_policies
    where schemaname = 'better_supabase' and tablename = 'funding_awards' and cmd = 'SELECT'),
  '<', 12,
  'the generated read and scope policies inline only the open types, not all 55'
);
select cmp_ok(
  (select max(length(qual))::int from pg_policies where schemaname = 'better_supabase' and tablename = 'funding_awards'),
  '<', 12000,
  'the generated policies are under 12 KB (the CASE form was 16 KB)'
);
select ok(
  (select qual not like '%x.tenant_id = x.tenant_id%' and qual like '%x.tenant_id = funding_deliveries.tenant_id%'
     from pg_policies where schemaname = 'better_supabase' and tablename = 'funding_deliveries' and policyname = 'bsb_funding_deliveries_read'),
  'the deliveries read policy compares the award tenant with the delivery tenant'
);

-- as user, role: compare

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select is(
  (select count(*)::int from (select id from oracle_t.funding_awards except select id from better_supabase.funding_awards) x), 0,
  'Acme admin loses no award the CASE form showed');
select is(
  (select count(*)::int from (select id from better_supabase.funding_awards except select id from oracle_t.funding_awards) x), 0,
  'Acme admin gains no award the CASE form hid');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select is(
  (select count(*)::int from (select id from oracle_t.funding_awards except select id from better_supabase.funding_awards) x), 0,
  'Acme member loses no award the CASE form showed');
select is(
  (select count(*)::int from (select id from better_supabase.funding_awards except select id from oracle_t.funding_awards) x), 0,
  'Acme member gains no award the CASE form hid');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}', true);
set local role authenticated;
select is(
  (select count(*)::int from (select id from oracle_t.funding_awards except select id from better_supabase.funding_awards) x), 0,
  'Globex owner loses no award the CASE form showed');
select is(
  (select count(*)::int from (select id from better_supabase.funding_awards except select id from oracle_t.funding_awards) x), 0,
  'Globex owner gains no award the CASE form hid');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b9","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select is(
  (select count(*)::int from (select id from oracle_t.funding_awards except select id from better_supabase.funding_awards) x), 0,
  'a user with no membership loses no award the CASE form showed');
select is(
  (select count(*)::int from (select id from better_supabase.funding_awards except select id from oracle_t.funding_awards) x), 0,
  'a user with no membership gains no award the CASE form hid');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select cmp_ok((select count(*)::int from better_supabase.funding_awards), '>', 3, 'the admin comparison is not vacuous');

select * from finish();
rollback;
