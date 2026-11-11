-- Historical quote import over a decided quote (ADR 0667). A first run imports
-- an accepted quote with one line. A second run with update "apply" and two
-- lines replaces the lines of the sent and decided quote, keeps its status, its
-- dates and its answer, and stores the given totals. Without "apply" the quote
-- is kept as imported. Run with `supabase test db`.
begin;
select plan(8);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create function pg_temp.start_run(source text) returns void language plpgsql as $$
begin
  perform set_config('better_supabase.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', source, '{}'::jsonb) ->> 'id'), true);
end;
$$;

select pg_temp.start_run('quotes-hist');
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);
select better_supabase.import_upsert_batch(current_setting('better_supabase.run')::uuid, 'quote',
  '[{"key":"q-9001","data":{"number":"Q-9001","status":"accepted","currency":"EUR","title":"Kitchen",
    "sentAt":"2026-01-05T10:00:00Z","decidedAt":"2026-01-08T10:00:00Z","decidedBy":"Customer","decisionNote":"Go ahead",
    "lines":[{"description":"Cabinets","quantity":1,"unitAmount":"10000","taxRateBps":2100}]}}]'::jsonb);
select better_supabase.finish_import_run(current_setting('better_supabase.run')::uuid);

select is(
  (select jsonb_build_array(status, decided_by, (select count(*)::int from better_supabase.quote_lines l where l.parent_id = q.id))
   from better_supabase.quotes q where q.identifier = 'Q-9001'),
  '["accepted", "Customer", 1]'::jsonb,
  'the first run imports the quote with its status, its answer and one line'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select pg_temp.start_run('quotes-hist');
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);

-- Without apply the imported quote is kept as it is, with a warning.
select is(
  (select better_supabase.import_upsert_batch(current_setting('better_supabase.run')::uuid, 'quote',
    '[{"key":"q-9001","data":{"number":"Q-9001","status":"accepted","currency":"EUR","title":"Kitchen v2",
      "lines":[{"description":"Cabinets","quantity":1,"unitAmount":"10000","taxRateBps":2100},{"description":"Fitting","quantity":1,"unitAmount":"5000","taxRateBps":2100}]}}]'::jsonb)
    -> 'warnings' -> 0 ->> 'code'),
  'IMPORT_DOCUMENT_CHANGED',
  'a changed source quote is kept as imported without apply'
);
select is(
  (select count(*)::int from better_supabase.quote_lines l join better_supabase.quotes q on q.id = l.parent_id where q.identifier = 'Q-9001'),
  1,
  'the lines are unchanged without apply'
);

select is(
  (select better_supabase.import_upsert_batch(current_setting('better_supabase.run')::uuid, 'quote',
  '[{"key":"q-9001","data":{"update":"apply","number":"Q-9001","status":"accepted","currency":"EUR","title":"Kitchen v2",
    "sentAt":"2026-01-05T10:00:00Z","decidedAt":"2026-01-08T10:00:00Z","decidedBy":"Customer","decisionNote":"Go ahead",
    "lines":[{"description":"Cabinets","quantity":1,"unitAmount":"10000","taxRateBps":2100},{"description":"Fitting","quantity":1,"unitAmount":"5000","taxRateBps":2100}],
    "taxLines":[{"taxRateBps":2100,"net":15000,"tax":3150}],
    "totals":{"subtotal":15000,"tax":3150,"total":18150}}}]'::jsonb) -> 'warnings'),
  null,
  'apply reports no warning when the stored tax and totals match the lines'
);
select better_supabase.finish_import_run(current_setting('better_supabase.run')::uuid);

select is(
  (select count(*)::int from better_supabase.quote_lines l join better_supabase.quotes q on q.id = l.parent_id where q.identifier = 'Q-9001'),
  2,
  'apply replaces the lines of a decided quote'
);
select is(
  (select jsonb_build_array(status, decided_by, decision_note, title) from better_supabase.quotes where identifier = 'Q-9001'),
  '["accepted", "Customer", "Go ahead", "Kitchen v2"]'::jsonb,
  'the quote keeps its status and its answer'
);
select is(
  (select jsonb_build_array(subtotal, tax_total, total) from better_supabase.quotes where identifier = 'Q-9001'),
  '[15000, 3150, 18150]'::jsonb,
  'the given totals are stored'
);
select is(
  (select jsonb_agg(jsonb_build_array(tax_rate_bps, net, tax)) from better_supabase.quote_tax_lines t join better_supabase.quotes q on q.id = t.parent_id where q.identifier = 'Q-9001'),
  '[[2100, 15000, 3150]]'::jsonb,
  'the given tax lines replace the computed ones'
);

select * from finish();
rollback;
