-- The blocks' restrictive scope keeps each member inside their organization on
-- the app's own tables, even though the app's invoices policy is using (true).
-- The integration test seeds organizations A and B with one member each.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(13);

select extensions.policies_are('public', 'invoices', array['members read invoices', 'bsb_tenant_scope_select', 'bsb_tenant_scope_insert', 'bsb_tenant_scope_update', 'bsb_tenant_scope_delete'], 'public.invoices keeps the app''s policy, which covers the block''s read, next to the scope');
select extensions.ok((select permissive = 'RESTRICTIVE' from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'invoices' and policyname = 'bsb_tenant_scope_select'), 'the scope on public.invoices is restrictive');
select extensions.ok((select permissive = 'RESTRICTIVE' from pg_catalog.pg_policies where schemaname = 'public' and tablename = 'notes' and policyname = 'bsb_tenant_scope_select'), 'the scope on the enriched public.notes is restrictive');

select set_config('request.jwt.claims', json_build_object('sub', '1a000000-0000-4000-8000-00000000000a', 'role', 'authenticated')::text, true);
set local role authenticated;

select extensions.results_eq($$select number from public.invoices order by 1$$, $$values ('A-1')$$, 'a member of A reads only A''s invoices through the app''s using (true) policy');
select extensions.results_eq($$select name from public.contacts order by 1$$, $$values ('Ann')$$, 'a member of A reads only A''s contacts');
select extensions.is_empty($$select 1 from public.invoices where organization_id = '0b000000-0000-4000-8000-00000000000b'$$, 'a member of A reads no invoice of B, even by its organization');
select extensions.is_empty($$update public.contacts set name = 'taken' where organization_id = '0b000000-0000-4000-8000-00000000000b' returning id$$, 'a member of A updates no contact of B');
select extensions.throws_ok($$insert into public.contacts (organization_id, name) values ('0b000000-0000-4000-8000-00000000000b', 'Eve')$$, '42501', null, 'a member of A cannot insert a contact into B');
select extensions.throws_ok($$insert into public.notes (organization_id, body) values ('0b000000-0000-4000-8000-00000000000b', 'x')$$, '42501', null, 'a member of A cannot insert a note into B');
select extensions.lives_ok($$insert into public.notes (organization_id, body) values ('0a000000-0000-4000-8000-00000000000a', 'mine')$$, 'a member of A writes a note into A');
select extensions.is_empty($$select 1 from public.notes where organization_id is null$$, 'a member reads no note written before the blocks, which has no owner');

reset role;
select set_config('request.jwt.claims', json_build_object('sub', '1b000000-0000-4000-8000-00000000000b', 'role', 'authenticated')::text, true);
set local role authenticated;

select extensions.results_eq($$select number from public.invoices order by 1$$, $$values ('B-1')$$, 'a member of B reads only B''s invoices');
select extensions.is_empty($$select 1 from public.contacts where name = 'Ann'$$, 'a member of B reads no contact of A');

select * from extensions.finish();
rollback;
