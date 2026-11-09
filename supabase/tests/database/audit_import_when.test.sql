-- A row audit trigger carries a when clause, so an import run with
-- imports.audit 'summary' never starts audit_row_change for a row; outside a
-- session, and for a caller who only sets the flag, the row is audited.
begin;
select plan(5);

set local track_functions = 'all';
set constraints all immediate;

create temp table marks (name text, calls int);
grant all on marks to public;

create function pg_temp.audit_calls() returns int language sql as $$
  select coalesce(pg_stat_get_xact_function_calls('better_supabase.audit_row_change()'::regprocedure), 0)::int
$$;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  (select count(*)::int from pg_trigger t
    where t.tgrelid = 'better_supabase.work_items'::regclass and t.tgname = 'bsb_audit'
      and pg_get_triggerdef(t.oid) like '%import_audit%'),
  1,
  'the audit trigger has the import check in its when clause'
);

-- Outside a session the row is audited.
insert into marks values ('start', pg_temp.audit_calls());
insert into better_supabase.work_items (id, tenant_id, number, identifier, title, state)
values ('00000000-0000-4000-8000-00000000fa01', '00000000-0000-4000-8000-000000000001', 9951, 'IM-9951', 'Plain', 'completed');
insert into marks values ('plain', pg_temp.audit_calls());
select cmp_ok(
  (select calls from marks where name = 'plain') - (select calls from marks where name = 'start'),
  '>', 0,
  'outside an import a row calls audit_row_change'
);

-- A setting alone does not turn the check on without a session.
select set_config('better_supabase.import_audit', 'summary', true);
insert into better_supabase.work_items (id, tenant_id, number, identifier, title, state)
values ('00000000-0000-4000-8000-00000000fa02', '00000000-0000-4000-8000-000000000001', 9952, 'IM-9952', 'Flag only', 'completed');
insert into marks values ('flag', pg_temp.audit_calls());
select cmp_ok(
  (select calls from marks where name = 'flag') - (select calls from marks where name = 'plain'),
  '>', 0,
  'the audit flag without an import session still audits the row'
);

-- Inside a summary session no row starts the function.
select set_config('better_supabase.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'audit-when', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);
select better_supabase.begin_import_session(current_setting('better_supabase.run')::uuid);
select set_config('better_supabase.import_audit', 'summary', true);

insert into better_supabase.work_items (id, tenant_id, number, identifier, title, state)
select ('00000000-0000-4000-8000-00000000fb' || lpad(n::text, 2, '0'))::uuid, '00000000-0000-4000-8000-000000000001', 9960 + n, 'IM-' || (9960 + n), 'Batch ' || n, 'completed'
from generate_series(1, 20) n;
update better_supabase.work_items set title = title || ' x' where identifier like 'IM-996%';
insert into marks values ('summary', pg_temp.audit_calls());
select is(
  (select calls from marks where name = 'summary') - (select calls from marks where name = 'flag'),
  0,
  'a summary import starts audit_row_change for none of its 40 row changes'
);

-- In rows mode the rows are audited as before.
select set_config('better_supabase.import_audit', 'rows', true);
insert into better_supabase.work_items (id, tenant_id, number, identifier, title, state)
values ('00000000-0000-4000-8000-00000000fc01', '00000000-0000-4000-8000-000000000001', 9990, 'IM-9990', 'Rows mode', 'completed');
insert into marks values ('rows', pg_temp.audit_calls());
select cmp_ok(
  (select calls from marks where name = 'rows') - (select calls from marks where name = 'summary'),
  '>', 0,
  'rows mode audits each row'
);

select * from finish();
rollback;
