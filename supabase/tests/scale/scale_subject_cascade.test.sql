-- Subject cascade deletes (ADR 0600): deleting 1,000 subject rows deletes their
-- attachments through the tenant-led index, and a same-id attachment of another
-- tenant stays. Set bsb.scale_rows to resize the table (default 60,000
-- products, 12,000 attachments).
begin;
select plan(4);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

insert into better_supabase.products (tenant_id, slug, title)
select '00000000-0000-4000-8000-000000000001', 'cascade-' || g, 'Cascade ' || g
from generate_series(1, current_setting('bsb.n')::int) g;

insert into better_supabase.attachments (tenant_id, bucket, subject_type, subject_id, name, mime_type, size, uploaded_by)
select '00000000-0000-4000-8000-000000000001', 'attachments', 'product', c.id::text, 'f' || row_number() over (), 'text/plain', 10,
  '00000000-0000-4000-8000-0000000000a1'
from (select id from better_supabase.products where title like 'Cascade %' limit current_setting('bsb.n')::int / 5) c;

-- The same subject id in another tenant keeps its attachment.
insert into better_supabase.attachments (tenant_id, bucket, subject_type, subject_id, name, mime_type, size, uploaded_by)
select '00000000-0000-4000-8000-000000000002', 'attachments', 'product', c.id::text, 'other', 'text/plain', 10,
  '00000000-0000-4000-8000-0000000000a1'
from (select id from better_supabase.products where title like 'Cascade %' order by id limit 1) c;
analyze better_supabase.attachments;
analyze better_supabase.products;

create temp table doomed as
select id from better_supabase.products where title like 'Cascade %' order by id limit 1000;

select ok(
  (select count(*) from better_supabase.attachments a join doomed d on a.subject_id = d.id::text and a.tenant_id = '00000000-0000-4000-8000-000000000001') > 0,
  'the doomed products have attachments'
);

create temp table t0 as select clock_timestamp() as t;
delete from better_supabase.products where id in (select id from doomed);
select diag('SCALE_MS subject_cascade_1000=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(
  (select count(*) from better_supabase.attachments a join doomed d on a.subject_id = d.id::text and a.tenant_id = '00000000-0000-4000-8000-000000000001'),
  0::bigint,
  'the cascade deleted their attachments'
);
select is(
  (select count(*) from better_supabase.attachments where name = 'other' and tenant_id = '00000000-0000-4000-8000-000000000002'
    and subject_id in (select id::text from doomed)),
  (select count(*) from better_supabase.attachments where name = 'other' and tenant_id = '00000000-0000-4000-8000-000000000002'),
  'another tenant keeps its attachments'
) ;

create temp table plan_json (p jsonb);
do $$
declare v_plan jsonb;
begin
  execute $q$explain (format json) delete from better_supabase.attachments x
    where x.subject_type = 'product' and x.subject_id = 'x' and x.tenant_id = '00000000-0000-4000-8000-000000000001'::uuid$q$ into v_plan;
  insert into plan_json values (v_plan);
end $$;
select ok((select p::text from plan_json) not like '%"Seq Scan"%', 'the cascade delete reads an index, not the whole table');

select * from finish();
rollback;

-- The statistics are not transactional; a doctor run after pgTAP would report this
-- fixture's temporary files (BS208).
select pg_stat_statements_reset() is not null as reset \gset
