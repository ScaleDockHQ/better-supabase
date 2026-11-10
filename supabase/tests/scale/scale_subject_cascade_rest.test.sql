-- Subject cascade deletes of approvals and relations (ADR 0610): deleting 1,000
-- subject rows reads the subject index of approval_requests and the tenant-led
-- source and target indexes of relations, and a same-id relation of another tenant
-- stays. Set bsb.scale_rows to resize the tables (default 60,000 products, 12,000
-- approval requests, 12,000 relations).
begin;
select plan(5);

select set_config('bsb.n', coalesce(nullif(current_setting('bsb.scale_rows', true), ''), '60000'), true);

insert into better_supabase.products (tenant_id, slug, title)
select '00000000-0000-4000-8000-000000000001', 'casc2-' || g, 'Casc2 ' || g
from generate_series(1, current_setting('bsb.n')::int) g;

create temp table pool as
select id, row_number() over (order by id) as n from better_supabase.products where title like 'Casc2 %';

insert into better_supabase.approval_requests (tenant_id, subject_type, subject_id, action, policy, step, status, payload)
select '00000000-0000-4000-8000-000000000001', 'product', p.id::text, 'publish', '{}'::jsonb, 0, 'approved', '{}'::jsonb
from pool p where p.n % 5 = 0;

insert into better_supabase.relations (tenant_id, kind, source_type, source_id, target_type, target_id)
select '00000000-0000-4000-8000-000000000001', 'related', 'product', a.id::text, 'product', b.id::text
from pool a join pool b on b.n = a.n + 1 where a.n % 5 = 0;

insert into better_supabase.relations (tenant_id, kind, source_type, source_id, target_type, target_id)
select '00000000-0000-4000-8000-000000000002', 'related', 'product', a.id::text, 'product', b.id::text
from pool a join pool b on b.n = a.n + 1 where a.n = 5;

analyze better_supabase.approval_requests;
analyze better_supabase.relations;
analyze better_supabase.products;

create temp table doomed as select id from pool where n % 5 = 0 order by n limit 1000;

select ok((select count(*) from better_supabase.approval_requests a join doomed d on a.subject_id = d.id::text) >= 1000, 'the doomed products have approval requests');

create temp table t0 as select clock_timestamp() as t;
delete from better_supabase.products where id in (select id from doomed);
select diag('SCALE_MS subject_cascade_rest_1000=' || round(extract(epoch from clock_timestamp() - (select t from t0)) * 1000));

select is(
  (select count(*) from better_supabase.approval_requests a join doomed d on a.subject_id = d.id::text where a.tenant_id = '00000000-0000-4000-8000-000000000001'),
  0::bigint, 'the cascade deleted their approval requests'
);
select is(
  (select count(*) from better_supabase.relations r join doomed d on r.source_id = d.id::text or r.target_id = d.id::text where r.tenant_id = '00000000-0000-4000-8000-000000000001'),
  0::bigint, 'the cascade deleted their relations'
);
select is(
  (select count(*) from better_supabase.relations where tenant_id = '00000000-0000-4000-8000-000000000002'),
  1::bigint, 'another tenant keeps its relation with the same subject id'
);

create temp table plan_json (p text);
do $$
declare v_plan jsonb; v_all text := '';
begin
  execute $q$explain (format json) delete from better_supabase.approval_requests r
    where r.subject_type = 'product' and r.subject_id = 'x'$q$ into v_plan;
  v_all := v_all || v_plan::text;
  execute $q$explain (format json) delete from better_supabase.relations x
    where ((x.source_type = 'product' and x.source_id = 'x') or (x.target_type = 'product' and x.target_id = 'x'))
      and x.tenant_id = '00000000-0000-4000-8000-000000000001'::uuid$q$ into v_plan;
  v_all := v_all || v_plan::text;
  insert into plan_json values (v_all);
end $$;
select ok((select p from plan_json) not like '%"Seq Scan"%', 'both cascade deletes read an index, not the whole table');

select * from finish();
rollback;

select pg_stat_statements_reset() is not null as reset \gset
