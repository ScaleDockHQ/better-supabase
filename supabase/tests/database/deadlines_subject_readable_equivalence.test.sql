-- The set-based gate of the deadlines read policy (ADR 1232) shows the same
-- deadlines as the 55-branch CASE it replaced. The "oracle" below is the read
-- policy as generated before the change (frozen from pg_get_expr), on a copy of
-- the table. Both tables hold the same rows, one per registry type and tenant,
-- for ids that exist, ids that do not, and a subject of the other tenant, and
-- are read by four roles.
begin;
select plan(13);

insert into better_supabase.permissions (key) values ('deadlines.read') on conflict do nothing;
insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id from better_supabase.roles r, better_supabase.permissions p
where r.key in ('owner', 'member') and p.key = 'deadlines.read'
on conflict do nothing;

create schema oracle_t;
grant usage on schema oracle_t to authenticated;
create table oracle_t.deadlines (like better_supabase.deadlines including defaults);
alter table oracle_t.deadlines enable row level security;
grant select on oracle_t.deadlines to authenticated;
create policy oracle_read on oracle_t.deadlines for select to authenticated using (
((tenant_id IN ( SELECT better_supabase.tenant_ids_with('deadlines.read'::text) AS tenant_ids_with)) AND
CASE subject_type
    WHEN 'message'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.messages s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'conversation'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.conversations s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'channel'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.channels s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('messages.read'::text) AS tenant_ids_with)))
    WHEN 'company'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.companies s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'person'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.people s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contacts.read'::text) AS tenant_ids_with)))
    WHEN 'deal'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.deals s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('deals.read'::text) AS tenant_ids_with)))
    WHEN 'course'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.courses s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('courses.read'::text) AS tenant_ids_with)))
    WHEN 'post'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.posts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('posts.read'::text) AS tenant_ids_with)))
    WHEN 'activity'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.activities s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('activities.read'::text) AS tenant_ids_with)))
    WHEN 'quote'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.quotes s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('quotes.read'::text) AS tenant_ids_with)))
    WHEN 'work_item'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_items s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tasks.read'::text) AS tenant_ids_with)))
    WHEN 'employee'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.employees s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('employees.read'::text) AS tenant_ids_with)))
    WHEN 'ledger_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.ledger_accounts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('ledger.read'::text) AS tenant_ids_with)))
    WHEN 'invoice'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.invoices s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('invoices.read'::text) AS tenant_ids_with)))
    WHEN 'product'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.products s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'product_variant'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.product_variants s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('catalog.read'::text) AS tenant_ids_with)))
    WHEN 'rfq'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.rfqs s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('rfqs.read'::text) AS tenant_ids_with)))
    WHEN 'till'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tills s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tills.read'::text) AS tenant_ids_with)))
    WHEN 'order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.orders s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('orders.read'::text) AS tenant_ids_with)))
    WHEN 'calendar_event'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.calendar_events s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('calendar.read'::text) AS tenant_ids_with)))
    WHEN 'booking'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bookings s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('bookings.read'::text) AS tenant_ids_with)))
    WHEN 'asset'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.assets s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'asset_location'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.asset_locations s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('assets.read'::text) AS tenant_ids_with)))
    WHEN 'lease'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.leases s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('leases.read'::text) AS tenant_ids_with)))
    WHEN 'expense_report'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_reports s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'expense_line'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.expense_lines s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('expenses.read'::text) AS tenant_ids_with)))
    WHEN 'donation_fund'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.donation_funds s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('donations.read'::text) AS tenant_ids_with)))
    WHEN 'warranty_claim'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.warranty_claims s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('warranty.read'::text) AS tenant_ids_with)))
    WHEN 'work_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_orders s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dispatch.read'::text) AS tenant_ids_with)))
    WHEN 'shipment'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.shipments s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('shipments.read'::text) AS tenant_ids_with)))
    WHEN 'contract'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.contracts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('contracts.read'::text) AS tenant_ids_with)))
    WHEN 'control'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.controls s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'compliance_policy'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.compliance_policies s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('compliance.read'::text) AS tenant_ids_with)))
    WHEN 'qualification_type'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.qualification_types s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('qualifications.read'::text) AS tenant_ids_with)))
    WHEN 'risk'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.risks s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('risks.read'::text) AS tenant_ids_with)))
    WHEN 'case'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.cases s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('cases.read'::text) AS tenant_ids_with)))
    WHEN 'inspection'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspections s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_program'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_programs s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'inspection_finding'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.inspection_findings s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('inspections.read'::text) AS tenant_ids_with)))
    WHEN 'form'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.forms s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('forms.read'::text) AS tenant_ids_with)))
    WHEN 'meeting'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meetings s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'meeting_decision'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.meeting_decisions s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('meetings.read'::text) AS tenant_ids_with)))
    WHEN 'maintenance_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.maintenance_plans s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('maintenance.read'::text) AS tenant_ids_with)))
    WHEN 'dam_usage_right'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.dam_usage_rights s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('dam.read'::text) AS tenant_ids_with)))
    WHEN 'lims_sample'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.lims_samples s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('lims.read'::text) AS tenant_ids_with)))
    WHEN 'tax_code'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.tax_codes s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('tax.read'::text) AS tenant_ids_with)))
    WHEN 'production_order'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.production_orders s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'work_center'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.work_centers s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('manufacturing.read'::text) AS tenant_ids_with)))
    WHEN 'bank_account'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.bank_accounts s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('banking.read'::text) AS tenant_ids_with)))
    WHEN 'care_plan'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.care_plans s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('care_plans.read'::text) AS tenant_ids_with)))
    WHEN 'incident'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.incidents s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('incidents.read'::text) AS tenant_ids_with)))
    WHEN 'content_entry'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.content_entries s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('content.read'::text) AS tenant_ids_with)))
    WHEN 'document'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.documents s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('documents.read'::text) AS tenant_ids_with)))
    WHEN 'customer'::text THEN ((EXISTS ( SELECT 1
       FROM customers s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('customers.read'::text) AS tenant_ids_with)))
    WHEN 'drive_node'::text THEN (EXISTS ( SELECT 1
       FROM better_supabase.drive_nodes s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id) AND ((deadlines.tenant_id IN ( SELECT better_supabase.tenant_ids_with('drive.read'::text) AS tenant_ids_with)) AND COALESCE(better_supabase.drive_node_readable(s.id), false)))))
    WHEN 'organization'::text THEN (EXISTS ( SELECT 1
       FROM organizations s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.id = deadlines.tenant_id))))
    WHEN 'application'::text THEN ((EXISTS ( SELECT 1
       FROM better_supabase.applications s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.tenant_id = deadlines.tenant_id)))) AND (tenant_id IN ( SELECT better_supabase.tenant_ids_with('hiring.read'::text) AS tenant_ids_with)))
    WHEN 'change_request'::text THEN (EXISTS ( SELECT 1
       FROM change_requests s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id))))
    WHEN 'project'::text THEN (EXISTS ( SELECT 1
       FROM projects s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id))))
    WHEN 'task'::text THEN (EXISTS ( SELECT 1
       FROM tasks s
      WHERE ((s.id = (deadlines.subject_id)::uuid) AND (s.organization_id = deadlines.tenant_id))))
    ELSE better_supabase.deadline_subject_readable(subject_type, subject_id, tenant_id)
END)
);

insert into public.customers (id, organization_id, name)
values ('00000000-0000-4000-8000-00000000e002', '00000000-0000-4000-8000-000000000002', 'Globex customer');

create temp table probes (subject_type text, subject_id text, subject_tenant uuid);

do $$
declare
  r record;
  ids text[];
begin
  for r in
    select distinct m[1] as type, m[2] as tbl
    from regexp_matches(pg_get_expr((select polqual from pg_policy where polrelid = 'oracle_t.deadlines'::regclass), 'oracle_t.deadlines'::regclass),
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

with rule_set as (
  insert into better_supabase.deadline_rule_sets (jurisdiction, kind) values ('equiv', 'notice') returning id
), version as (
  insert into better_supabase.deadline_rule_versions (rule_set_id, version, status, rules, groups, content_hash, effective_from, approved_at)
  select id, 1, 'approved', '[]', '[]', 'equiv', '2020-01-01', now() from rule_set returning id
)
insert into better_supabase.deadlines (tenant_id, subject_type, subject_id, jurisdiction, kind, group_key, rule_version_id, result, due_on, citation)
select t.id, p.subject_type, p.subject_id, 'equiv', 'notice', gen_random_uuid()::text, v.id, 'due', current_date, '{}'
from probes p, version v
cross join (values ('00000000-0000-4000-8000-000000000001'::uuid), ('00000000-0000-4000-8000-000000000002'::uuid)) t(id);

insert into oracle_t.deadlines select * from better_supabase.deadlines;

select is(
  (select count(*)::int from (select distinct subject_type, tenant_id from oracle_t.deadlines) d),
  2 * (select count(distinct subject_type)::int from probes),
  'the fixture holds a deadline for every type and tenant');
select cmp_ok((select count(distinct subject_type)::int from oracle_t.deadlines), '>=', 50, 'the fixture covers the registry types');

select cmp_ok(
  (select max(array_length(regexp_split_to_array(qual, 'WHEN '), 1) - 1)::int from pg_policies
    where schemaname = 'better_supabase' and tablename = 'deadlines' and cmd = 'SELECT'),
  '<', 12,
  'the generated read and scope policies inline only the open types, not all 55'
);
select cmp_ok(
  (select max(length(qual))::int from pg_policies where schemaname = 'better_supabase' and tablename = 'deadlines'),
  '<', 12000,
  'the generated policies are under 12 KB (the CASE form was 17 KB)'
);

-- as user, role: compare

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select is(
  (select count(*)::int from (select id from oracle_t.deadlines except select id from better_supabase.deadlines) x), 0,
  'Acme admin loses no deadline the CASE form showed');
select is(
  (select count(*)::int from (select id from better_supabase.deadlines except select id from oracle_t.deadlines) x), 0,
  'Acme admin gains no deadline the CASE form hid');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select is(
  (select count(*)::int from (select id from oracle_t.deadlines except select id from better_supabase.deadlines) x), 0,
  'Acme member loses no deadline the CASE form showed');
select is(
  (select count(*)::int from (select id from better_supabase.deadlines except select id from oracle_t.deadlines) x), 0,
  'Acme member gains no deadline the CASE form hid');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}', true);
set local role authenticated;
select is(
  (select count(*)::int from (select id from oracle_t.deadlines except select id from better_supabase.deadlines) x), 0,
  'Globex owner loses no deadline the CASE form showed');
select is(
  (select count(*)::int from (select id from better_supabase.deadlines except select id from oracle_t.deadlines) x), 0,
  'Globex owner gains no deadline the CASE form hid');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b9","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select is(
  (select count(*)::int from (select id from oracle_t.deadlines except select id from better_supabase.deadlines) x), 0,
  'a user with no membership loses no deadline the CASE form showed');
select is(
  (select count(*)::int from (select id from better_supabase.deadlines except select id from oracle_t.deadlines) x), 0,
  'a user with no membership gains no deadline the CASE form hid');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select cmp_ok((select count(*)::int from better_supabase.deadlines), '>', 3, 'the admin comparison is not vacuous');

select * from finish();
rollback;
