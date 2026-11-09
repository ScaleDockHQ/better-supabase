-- The naming convention of api/naming.json, read from the catalog (ADR 0247,
-- ADR 0385). Every rule lists the objects that break it, so a failure names
-- them; the only exceptions are listed in the rule and say why. There are no
-- thresholds: a violating name fails the suite.
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(11);

select extensions.is(
  (select count(*) from pg_catalog.pg_namespace where nspname = 'bsb'),
  0::bigint,
  'the bsb schema is gone: helpers live in better_supabase'
);

select extensions.is(
  (select coalesce(string_agg(policyname || ' on ' || tablename, ', ' order by policyname), '')
    from pg_catalog.pg_policies where schemaname = 'better_supabase' and policyname !~ '^bsb_'),
  '',
  'better_supabase policies are named bsb_*'
);

select extensions.is(
  (select coalesce(string_agg(t.tgname || ' on ' || c.relname, ', ' order by t.tgname), '')
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace s on s.oid = c.relnamespace
    where s.nspname = 'better_supabase' and not t.tgisinternal and t.tgname !~ '^bsb_'),
  '',
  'better_supabase triggers are named bsb_*'
);

select extensions.is(
  (select coalesce(string_agg(k.conname || ' on ' || c.relname, ', ' order by k.conname), '')
    from pg_catalog.pg_constraint k
    join pg_catalog.pg_class c on c.oid = k.conrelid
    join pg_catalog.pg_namespace s on s.oid = c.relnamespace
    where s.nspname = 'better_supabase' and k.contype = 'c' and k.conname !~ '^bsb_'),
  '',
  'better_supabase check constraints are named bsb_*'
);

select extensions.is(
  (select coalesce(string_agg(indexname, ', ' order by indexname), '')
    from pg_catalog.pg_indexes
    where schemaname = 'better_supabase' and indexname !~ '(_idx|_key|_pkey|_excl)$'),
  '',
  'index names end in _idx, _key, _pkey or _excl'
);

select extensions.is(
  (select coalesce(string_agg(table_name || '.' || column_name, ', ' order by table_name, column_name), '')
    from information_schema.columns
    where table_schema = 'better_supabase' and data_type = 'timestamp with time zone'
      and column_name !~ '_at$'
      and column_name <> 'dtstart'),
  '',
  'timestamp columns end in _at (dtstart stays: RFC 5545 names it)'
);

select extensions.is(
  (select coalesce(string_agg(table_name, ', ' order by table_name), '')
    from information_schema.columns
    where table_schema = 'better_supabase' and column_name = 'organization_id'),
  '',
  'block tables name the tenant column tenant_id'
);

select extensions.is(
  (select coalesce(string_agg(table_name || '.' || column_name, ', ' order by table_name, column_name), '')
    from information_schema.columns
    where table_schema = 'better_supabase'
      and (column_name ~ '_user_id$' or column_name = 'deleted_at')
      and column_name <> 'scim_user_id'),
  '',
  'user references are <role>_id (scim_user_id references scim_users) and soft delete is archived_at'
);

select extensions.is(
  (select coalesce(string_agg(table_name || '.' || column_name, ', ' order by table_name, column_name), '')
    from information_schema.columns
    where table_schema = 'better_supabase' and column_name ~ '(^|_)(engagement)(_|$)'
      ),
  '',
  'columns do not use the engagement noun'
);

select extensions.is(
  (select coalesce(string_agg(table_name, ', ' order by table_name), '')
    from information_schema.tables
    where table_schema = 'better_supabase' and table_type = 'BASE TABLE'
      and table_name ~ '(^|_)(engagement|engagements)(_|$)'),
  '',
  'tables do not use the engagement noun'
);

select extensions.is(
  (select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
    from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace s on s.oid = p.pronamespace
    where s.nspname = 'public' and p.prosecdef
      and p.proname not in ('customers_owner_team_check', 'import_customer', 'import_customer_batch', 'import_customer_updated_at')),
  '',
  'security definer functions stay out of public (the four fixture app functions are listed)'
);

select * from extensions.finish();
rollback;
