-- list_invoices_for_subject (ADR 0822): the invoices that name a record as
-- their company or contact, newest first, for one organization. A caller
-- without invoices.read on the organization is refused, and another
-- organization's invoices never show. Run with `supabase test db`.
begin;
select plan(5);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
update better_supabase.invoices
set company_type = 'company', company_id = '00000000-0000-4000-8000-0000000000c1'
where identifier = 'INV-0001';
update better_supabase.invoices
set contact_type = 'company', contact_id = '00000000-0000-4000-8000-0000000000c1', created_at = created_at + interval '1 minute'
where identifier = 'INV-0002';

select is(
  (select jsonb_array_length(better_supabase.list_invoices_for_subject(
    '00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-0000000000c1'))),
  2,
  'both the company and the contact match name the record'
);
select is(
  (better_supabase.list_invoices_for_subject(
    '00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-0000000000c1', 1) -> 0 ->> 'identifier'),
  'INV-0002',
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
