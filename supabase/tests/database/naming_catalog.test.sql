-- The naming convention of api/naming.json, read from the catalog (ADR 0247).
-- Each rule counts the objects that still use the old shape and may only go
-- down: lower the number in the same commit that renames objects. A rule with
-- no old objects left is exact.
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(9);

select extensions.is(
  (select count(*) from pg_catalog.pg_namespace where nspname = 'bsb'),
  0::bigint,
  'the bsb schema is gone: helpers live in better_supabase'
);

select extensions.cmp_ok(
  (select count(*) from pg_catalog.pg_policies where schemaname = 'better_supabase' and policyname !~ '^bsb_'),
  '<=', 0::bigint,
  'better_supabase policies are named bsb_*'
);

select extensions.cmp_ok(
  (select count(*) from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace s on s.oid = c.relnamespace
    where s.nspname = 'better_supabase' and not t.tgisinternal and t.tgname !~ '^bsb_'),
  '<=', 0::bigint,
  'better_supabase triggers are named bsb_*'
);

select extensions.cmp_ok(
  (select count(*) from pg_catalog.pg_constraint k
    join pg_catalog.pg_class c on c.oid = k.conrelid
    join pg_catalog.pg_namespace s on s.oid = c.relnamespace
    where s.nspname = 'better_supabase' and k.contype = 'c' and k.conname !~ '^bsb_'),
  '<=', 0::bigint,
  'better_supabase check constraints are named bsb_*'
);

select extensions.cmp_ok(
  (select count(*) from pg_catalog.pg_indexes where schemaname = 'better_supabase' and indexname !~ '(_idx|_key|_pkey|_excl)$'),
  '<=', 0::bigint,
  'index names end in _idx, _key, _pkey or _excl'
);

select extensions.cmp_ok(
  (select count(*) from information_schema.columns
    where table_schema = 'better_supabase' and data_type = 'timestamp with time zone' and column_name !~ '_at$'),
  '<=', 33::bigint,
  'timestamp columns end in _at'
);

select extensions.cmp_ok(
  (select count(*) from information_schema.columns
    where table_schema = 'better_supabase' and column_name = 'organization_id'),
  '<=', 63::bigint,
  'block tables name the tenant column tenant_id'
);

select extensions.cmp_ok(
  (select count(*) from information_schema.columns
    where table_schema = 'better_supabase' and (column_name ~ '_user_id$' or column_name = 'deleted_at')),
  '<=', 31::bigint,
  'user references are <role>_id and soft delete is archived_at'
);

select extensions.cmp_ok(
  (select count(*) from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace s on s.oid = p.pronamespace
    where s.nspname = 'public' and p.prosecdef),
  '<=', 3::bigint,
  'security definer functions stay out of public'
);

select * from extensions.finish();
rollback;
