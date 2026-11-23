-- A status-filtered orders or invoices list read as an authenticated member
-- uses the tenant and status index under RLS (ADR 0460, ADR 1216). status is
-- text, and texteq is leakproof, so Postgres may use `status = ...` as an index
-- condition before the policies pass; an enum column couldn't (doctor BS642).
-- With sequential and bitmap scans off, the plan must be an index scan whose
-- condition names status. Run with `supabase test db`.
begin;
select plan(4);

create function pg_temp.plan_of(text) returns text language plpgsql as $$
declare result jsonb;
begin
  execute 'explain (format json) ' || $1 into result;
  return result::text;
end $$;

analyze better_supabase.orders;
analyze better_supabase.invoices;
set local enable_seqscan = off;
set local enable_bitmapscan = off;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select ok(
  pg_temp.plan_of($$select id from better_supabase.orders where tenant_id = '00000000-0000-4000-8000-000000000001' and status = 'confirmed' order by placed_at desc limit 50$$)
    ~ '"Index Name": "orders_status_idx"',
  'the orders list by status reads orders_status_idx as authenticated'
);

select ok(
  pg_temp.plan_of($$select id from better_supabase.orders where tenant_id = '00000000-0000-4000-8000-000000000001' and status = 'confirmed' order by placed_at desc limit 50$$)
    ~ '"Index Cond": "[^"]*status[^"]*"',
  'the orders status filter is an index condition under RLS'
);

select ok(
  pg_temp.plan_of($$select id from better_supabase.invoices where tenant_id = '00000000-0000-4000-8000-000000000001' and status = 'issued' order by due_on limit 50$$)
    ~ '"Index Name": "invoices_tenant_status_idx"',
  'the invoices list by status reads invoices_tenant_status_idx as authenticated'
);

select ok(
  pg_temp.plan_of($$select id from better_supabase.invoices where tenant_id = '00000000-0000-4000-8000-000000000001' and status = 'issued' order by due_on limit 50$$)
    ~ '"Index Cond": "[^"]*status[^"]*"',
  'the invoices status filter is an index condition under RLS'
);

select * from finish();
rollback;
