-- Subject read policies of deal contacts, subject knowledge and deadlines on the scale fixture (ADR 0644): 60,000 customers with 12,000 rows of each
-- family on them, read as a signed-in member. Each policy inlines the subject check; the
-- same count through the earlier form (can_subject or the plpgsql wrapper per row,
-- recreated inside the transaction) prints beside it. Set bsb.scale_rows to resize.
begin;
select plan(6);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

insert into better_supabase.permissions (key) values ('deals.read'), ('knowledge.read'), ('deadlines.read')
on conflict do nothing;
insert into better_supabase.role_permissions (role_id, permission_id)
select r.id, p.id from better_supabase.roles r, better_supabase.permissions p
where r.key in ('owner', 'member') and p.key in ('deals.read', 'knowledge.read', 'deadlines.read')
on conflict do nothing;

insert into public.customers (organization_id, name)
select '00000000-0000-4000-8000-000000000001', 'Remaining ' || g
from generate_series(1, current_setting('bsb.n')::int) g;

create temp table picked as
select id from public.customers where name like 'Remaining %' limit current_setting('bsb.n')::int / 5;

-- Deals: one deal holds a contact per picked customer.
insert into better_supabase.deals (id, tenant_id, number, identifier, name, currency, expected_close_on)
values ('00000000-0000-4000-8000-0000000d0001', '00000000-0000-4000-8000-000000000001', 9000001, 'D-9000001', 'Scale deal', 'EUR', current_date);
insert into better_supabase.deal_contacts (tenant_id, deal_id, contact_type, contact_id)
select '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000d0001', 'customer', id::text from picked;

-- Knowledge: one subject document per picked customer.
insert into better_supabase.knowledge_documents (tenant_id, scope, subject_type, subject_id, title, status)
select '00000000-0000-4000-8000-000000000001', 'subject', 'customer', id::text, 'Scale ' || id, 'ready' from picked;

-- Deadlines: one due deadline per picked customer.
with rule_set as (
  insert into better_supabase.deadline_rule_sets (jurisdiction, kind) values ('scale', 'notice') returning id
), version as (
  insert into better_supabase.deadline_rule_versions (rule_set_id, version, status, rules, groups, content_hash, effective_from, approved_at)
  select id, 1, 'approved', '[]', '[]', 'scale', '2020-01-01', now() from rule_set returning id
)
insert into better_supabase.deadlines (tenant_id, subject_type, subject_id, jurisdiction, kind, group_key, rule_version_id, result, due_on, citation)
select '00000000-0000-4000-8000-000000000001', 'customer', p.id::text, 'scale', 'notice', 'notice', v.id, 'due', current_date, '{}'
from picked p, version v;

analyze public.customers;
analyze better_supabase.deal_contacts;
analyze better_supabase.knowledge_documents;
analyze better_supabase.deadlines;

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;

create temp table t0 as select clock_timestamp() as t;
grant all on t0 to public;

select count(*)::bigint as contacts_inlined from better_supabase.deal_contacts where contact_type = 'customer' \gset
select diag('SCALE_MS deal_contacts_policy_inlined=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as knowledge_inlined from better_supabase.knowledge_documents where scope = 'subject' \gset
select diag('SCALE_MS knowledge_documents_policy_inlined=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as deadlines_inlined from better_supabase.deadlines where jurisdiction = 'scale' \gset
select diag('SCALE_MS deadlines_policy_inlined=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

reset role;

drop policy bsb_deal_contacts_read on better_supabase.deal_contacts;
create policy bsb_deal_contacts_read on better_supabase.deal_contacts for select to authenticated
  using (exists (select 1 from better_supabase.deals x where x.id = deal_id) and better_supabase.can_subject(contact_type, contact_id, 'read'));
drop policy bsb_knowledge_documents_read on better_supabase.knowledge_documents;
create policy bsb_knowledge_documents_read on better_supabase.knowledge_documents for select to authenticated
  using (tenant_id is null or case when scope = 'subject' then better_supabase.knowledge_subject_readable(subject_type, subject_id) else false end);
drop policy bsb_deadlines_read on better_supabase.deadlines;
create policy bsb_deadlines_read on better_supabase.deadlines for select to authenticated
  using (tenant_id in (select better_supabase.tenant_ids_with('deadlines.read')) and better_supabase.deadline_subject_readable(subject_type, subject_id, tenant_id));

set local role authenticated;

update t0 set t = clock_timestamp();
select count(*)::bigint as contacts_perrow from better_supabase.deal_contacts where contact_type = 'customer' \gset
select diag('SCALE_MS deal_contacts_policy_per_row=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as knowledge_perrow from better_supabase.knowledge_documents where scope = 'subject' \gset
select diag('SCALE_MS knowledge_documents_policy_per_row=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

update t0 set t = clock_timestamp();
select count(*)::bigint as deadlines_perrow from better_supabase.deadlines where jurisdiction = 'scale' \gset
select diag('SCALE_MS deadlines_policy_per_row=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(:contacts_inlined::bigint, (current_setting('bsb.n')::bigint / 5), 'the member reads every deal contact that is a customer they can read');
select is(:contacts_perrow::bigint, :contacts_inlined::bigint, 'the per-row policy sees the same deal contacts');
select is(:knowledge_inlined::bigint, (current_setting('bsb.n')::bigint / 5), 'the member reads every subject document on a customer they can read');
select is(:knowledge_perrow::bigint, :knowledge_inlined::bigint, 'the per-row policy sees the same documents');
select is(:deadlines_inlined::bigint, (current_setting('bsb.n')::bigint / 5), 'the member reads every deadline of a customer they can read');
select is(:deadlines_perrow::bigint, :deadlines_inlined::bigint, 'the per-row policy sees the same deadlines');

select * from finish();
rollback;

select pg_stat_statements_reset() is not null as reset \gset
