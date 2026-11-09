-- Audit trigger modes on 3,000 inserts into one block table (ADR 0435): the
-- deferred row trigger, the statement trigger audit(statement => true) and no
-- audit at all. Timings print as SCALE_MS lines; nothing is asserted but that
-- each mode wrote the rows.
begin;
select plan(3);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

create temp table t0 (t timestamptz);
grant all on t0 to public;
set constraints all immediate;

insert into t0 values (clock_timestamp());
insert into better_supabase.work_items (tenant_id, number, identifier, title, state)
select '00000000-0000-4000-8000-000000000001', 200000 + g, 'AM-' || g, 'Row ' || g, 'completed' from generate_series(1, 3000) g;
select diag('SCALE_MS audit_row_trigger_3000=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));
select ok((select count(*) from better_supabase.work_items where identifier like 'AM-%') = 3000, 'the row trigger run wrote the rows');

reset role;
select better_supabase.audit('better_supabase.work_items', target_type => 'work_item', event_prefix => 'work_item', statement => true);
set local role service_role;
delete from t0;
insert into t0 values (clock_timestamp());
insert into better_supabase.work_items (tenant_id, number, identifier, title, state)
select '00000000-0000-4000-8000-000000000001', 300000 + g, 'AS-' || g, 'Row ' || g, 'completed' from generate_series(1, 3000) g;
select diag('SCALE_MS audit_statement_trigger_3000=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));
select ok((select count(*) from better_supabase.work_items where identifier like 'AS-%') = 3000, 'the statement trigger run wrote the rows');

reset role;
select better_supabase.unaudit('better_supabase.work_items');
set local role service_role;
delete from t0;
insert into t0 values (clock_timestamp());
insert into better_supabase.work_items (tenant_id, number, identifier, title, state)
select '00000000-0000-4000-8000-000000000001', 400000 + g, 'AN-' || g, 'Row ' || g, 'completed' from generate_series(1, 3000) g;
select diag('SCALE_MS audit_none_3000=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));
select ok((select count(*) from better_supabase.work_items where identifier like 'AN-%') = 3000, 'the unaudited run wrote the rows');

select * from finish();
rollback;
