-- list_invoices_for_subject (ADR 0822): the invoices that name a record as
-- their company or contact, newest first, for one organization. A caller
-- without invoices.read on the organization is refused, and another
-- organization's invoices never show. Run with `supabase test db`.
begin;
select plan(5);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
insert into better_supabase.invoices (tenant_id, title, currency, status, company_type, company_id, created_at)
values ('00000000-0000-4000-8000-000000000001', 'By company', 'EUR', 'draft', 'company', '00000000-0000-4000-8000-0000000000c1', now() - interval '1 hour');
insert into better_supabase.invoices (tenant_id, title, currency, status, contact_type, contact_id, created_at)
values ('00000000-0000-4000-8000-000000000001', 'By contact', 'EUR', 'draft', 'company', '00000000-0000-4000-8000-0000000000c1', now());

select is(
  (select jsonb_array_length(better_supabase.list_invoices_for_subject(
    '00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-0000000000c1'))),
  2,
  'both the company and the contact match name the record'
);
select is(
  (better_supabase.list_invoices_for_subject(
    '00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-0000000000c1', 1) -> 0 ->> 'title'),
  'By contact',
  'newest first, and the limit applies'
);
select is(
  better_supabase.list_invoices_for_subject(
    '00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-0000000000ff'),
  '[]'::jsonb,
  'an unrelated record has no invoices'
);
select is(
  better_supabase.list_invoices_for_subject(
    '00000000-0000-4000-8000-0000000000aa', 'company', '00000000-0000-4000-8000-0000000000c1'),
  '[]'::jsonb,
  'another organization sees none of them'
);

reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e9","role":"authenticated"}', true);
set local role authenticated;
select throws_ok(
  $$ select better_supabase.list_invoices_for_subject('00000000-0000-4000-8000-000000000001', 'company', 'x') $$,
  '42501',
  null,
  'a caller without invoices.read is refused'
);

select * from finish();
rollback;
